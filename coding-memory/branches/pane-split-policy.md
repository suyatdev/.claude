# Branch: feat/pane-split-policy

Session pane-split policy. At the first pane-eligible dispatch the model asks once:
`inline` (all in-process this session) or `panes max=N` (N concurrent worker panes;
spawns beyond N open as **tabs inside existing panes**, round-robin — never inline/blocked).
Three-lane governance model: read-only `Explore`/`Plan` always in-process; the two judges
always paned, *outside* the policy; only the worker fan-out is policy-governed.

- Spec: `docs/superpowers/specs/2026-07-22-pane-split-policy-design.md` (locked, blob `cdc777a`)
- Plan: `docs/superpowers/plans/2026-07-23-pane-split-policy.md` (8 TDD tasks)
- Gates answered (do not re-ask this branch's execution): Opus 4.8 (1M) implementation,
  subagent-driven execution (pane-routed implementers, inherit `opus[1m]` from settings.json).

## Task 1 — cmux tab probe (2026-07-23, live on real cmux, operator-run) — PASS

**`new-surface --pane <pane-ref>` IS the `open_tab` primitive: an in-pane tab, not a new
window or workspace.** So the spec's core mechanism ("spawns beyond N open as tabs inside
existing panes") is achievable with cmux as-is.

- Probe: `panes/cmux-tab-probe.sh` (re-runnable; run it after any cmux upgrade before trusting
  `cmux.sh open_tab`).
- Fixture: `panes/adapters/fixtures/tab-live.json` (scratch-workspace tree; titles `Terminal`
  + `tab-probe-scratch` only — no real paths/titles).
- cmux at probe time: `0.64.20 (100) [14e3400b9]` (matches the version pinned in the sibling
  orchestration / layout-v2 specs). Bin: `/Applications/cmux.app/Contents/Resources/bin/cmux`.

### The exact primitive Task 5 must use
- **Create the tab:** `cmux --json new-surface --pane <pane-ref> --workspace <ws-ref>`
  → returns JSON `{"pane_ref":"pane:N","surface_ref":"surface:M","type":"terminal",
  "window_ref":"window:N","workspace_ref":"workspace:N"}`. Extract `.surface_ref` for the new tab.
- **Launch the agent in the tab:** `cmux send --workspace <ws-ref> --surface <new-surface-ref> -- "<launcher>\n"`
  — confirmed live (Q3 below). Same send-to-surface path layout-v2's reuse (P4) already proved.

### Evidence (two live runs)
- Run 1 tree AFTER new-surface: `pane:31 / surface:64` (base) + `pane:31 / surface:65` (new) —
  both share `pane:31`, `window:1`, `workspace:9`.
- Run 2 (captured as the fixture): `pane:36 / surface:77` + `pane:36 / surface:78` — same,
  both in `pane:36`.
- Visual confirmation (run 2 VISUAL CHECK, operator-reported):
  - **Q1:** exactly ONE new workspace appeared (`tab-probe-scratch`).
  - **Q2:** pane `pane:36` shows TWO tabs.
  - **Q3:** `TAB_SEND_OK` printed inside the new tab.

### GOTCHA for re-runners (cost the first run a misread)
The probe creates a scratch workspace in T1 and cmux may not auto-focus it, so the new tab
appears "in a new workspace" from the operator's seat. That workspace IS `tab-probe-scratch`
— NOT evidence that `new-surface` spawns a workspace per tab. Switch into `tab-probe-scratch`
and count tabs in the pane (Q2). The VISUAL CHECK block in the probe was added after run 1
misread exactly this way.

### Feeds Task 4/5 — surface→pane resolution (decide in `validate_open_tab_args`)
`new-surface --pane` needs a **pane-ref**, but the overflow round-robin (`pane-rr-<key>`, Task 7)
selects a target *worker*, which the dispatcher tracks by its **surface** (`CMUX_SURFACE_ID`).
So `open_tab` must resolve the target's surface-ref → its `pane_ref` (the `norm` selector
already yields `pane_ref` per surface) before calling `new-surface --pane <pane_ref>` — unless
Task 4 chooses to accept a pane-ref directly. Either way the adapter call ends in
`new-surface --pane <pane_ref>`, and the caller-supplied ref stays under the frozen
no-interpolation + allowlist boundary the spec inherits from the orchestration spec.

## Task 2 — policy state file (`set-policy` writer + `read_policy` reader) — DONE 2026-07-23

Commit `8fb4534` (pane-dispatched implementer on Opus; commit-verified in-checkout: HEAD, parent
`1f70f58`, branch `feat/pane-split-policy`, only `dispatch-pane-agent.sh` +41 / `.test.sh` +14, a
`Doc-Exempt` trailer). Tests 44/44 (5 new `set-policy` assertions + 39 pre-existing), `shellcheck -x`
clean, TDD RED 42/2 → GREEN 44/0.

What landed in `panes/dispatch-pane-agent.sh`:
- `MAX_PANES=16` + `POLICY_RE='^panes max=([0-9]+)$'` (after `POLL_SECS`).
- `read_policy <file>` (after `sanitize_title`): prints `inline` or `panes max=N` for a VALID line,
  else nothing; fail-open (every branch → `return 0`), N range-gated 1..16 at read time. Defined but
  intentionally UNCALLED — consumed by the guard (Task 3) and dispatcher (Tasks 6/7).
- `set-policy` case arm: `set-policy inline` / `set-policy panes --max N` → writes
  `state/pane-policy-<key>` (key `${CLAUDE_CODE_SESSION_ID:-nosession}`); exit 0 on success, 64 on
  bad/out-of-range/non-numeric N. Bounded N validated at write time too (dual validation, both sites).

Reviewer (pane, Opus): **Spec ✅ / Approved / 0 Critical-Important**, every binding constraint traced
with file:line. Disclosed deviation (split the `set-policy` `mode` one-liner + `# shellcheck
disable=SC2015` at :236) byte-matches the `dispatch` arm's existing suppression at :100 — controller
confirmed, shellcheck clean, behavior-preserving, repo precedent.

Minors deferred to final review: `read_policy:62` `2>/dev/null` guards only the 2nd range test
(negligible — writer can't emit a >int64 value; group both under one redirect if touched); usage
fallthrough string `:111` still `{dispatch|wait|handoff}`, omits `set-policy` (stale help, unscoped).
**CARRY-FORWARD → Task 3** (when it wires `read_policy` into the guard): tighten the three `set-policy`
reject assertions (`test:135-140` only check `$?==64`, which `die` returns for ANY failure — they
don't pin the out-of-range/non-numeric path); add real branch coverage for `read_policy` (5 branches,
currently no asserter). Both plan-scoped to Task 3.

## Task 3 — guard three-lane routing + policy read (2026-07-23)

**DONE + committed `6bead2d7`** (parent `6fb9b20`), subagent-driven: pane Opus implementer +
pane task-reviewer, both cmux `surface:83`. Commit **verified in-checkout** (toplevel
`/Users/marksuyat/.claude`, branch `feat/pane-split-policy`, exactly the 4 domain files:
`hooks/pane-dispatch-guard.sh`, `hooks/pane-dispatch-guard.test.sh`, `panes/inprocess-agents.conf`,
`panes/redirect-agents.conf`; 140+/39-). Guard test **23/0 independently re-run by controller**;
`shellcheck -x` clean on both shell files; `dispatch-pane-agent.test.sh` still 44/0 (redirect-conf
header rewrite didn't disturb Task 2). Routing body + `in_conf` + both confs verbatim-faithful to the
plan; the `^panes max=([1-9]|1[0-6])$` bound verified across 1/9/16→redirect, 0/17/99→ask.
Implementer deviations (all sound): preserved an existing SC2016 rationale comment the plan dropped;
rewrote the old "missing conf → allow" test into two "missing conf + inline → exit 0" cases (the
three-lane design makes a missing conf mean "unlisted for that lane", not global allow); added an
out-of-range `max=99 → ask` case.

**Reviewer verdict: CHANGES-REQUESTED** (narrow — architecture stands, T4 unblocked). Every finding
reproduced end-to-end. Controller independently traced both Importants — mechanisms confirmed real,
accepted (not performative). **These must land before the branch PR (several tasks away); recorded
here rather than fixed this session to stay under the ~100k ceiling.**

- **FAIL-OPEN missing-conf question → RULED ACCEPTABLE (not a violation).** Exit-2-"ask" never
  blocks/waits: pane sessions bail at the `CLAUDE_PANE_AGENT` recursion guard before any conf is read;
  no-terminal exits 0 at the floor before confs matter; "ask" is the spec's already-blessed
  unconfigured state, one `set-policy` from resolved. The Global Constraint wording "missing conf →
  allow" describes the OLD two-outcome guard; re-read as "missing conf → unlisted for THAT lane".
  → **Task 8 ADR must state this refinement; Important-3 (below) fixes the now-false guard header.**

- **Important-1 — zero-padded N ask-loop (writer/reader asymmetry).** `guard:91` regex rejects padded
  ints but `set-policy` (`dispatch-pane-agent.sh:250-251`, `^panes max=([0-9]+)$` + range) accepts
  them. Repro: `set-policy panes --max 03` → exit 0, prints `POLICY: panes max=03`; guard then reads
  `panes max=03` → **ASK forever**, no error naming the cause. Same for `--max 08`. **Fix:** normalize
  N to canonical base-10 at write time in `set-policy` (`max=$((10#$max))` after validation) AND make
  the guard parse `^panes max=([0-9]+)$` + `10#`-based range 1..16 (matches `read_policy`), removing
  the divergent magic regex (also fixes Minor-6). Touches both files (Task 2 + Task 3) — justified
  cross-file fix.
- **Important-2 — stale `nosession` overrides a MALFORMED primary policy → allow.** `guard:85-92` loop
  only `break`s on a *valid* line, so a garbage file at the real key falls through to `nosession`.
  Repro: primary key=`garbage`, `pane-policy-nosession`=`inline` → **exit 0 in-process allow**,
  contradicting "malformed → re-ask". Also leaks another session's policy (state persists 7 days).
  **Fix:** break on the first *existing* policy file regardless of validity (malformed → policy empty
  → ask); consult `nosession` only when `env_sid` is empty (the condition that creates that file).
- **Important-3 — guard header comment (`:5-10`) now states the opposite of the code** ("redirect-
  listed types", "missing conf → allow … today's behavior", "ALL four spec conditions"). Rewrite to
  three-lane reality.
- **Minor-4** vacuous test `test:82` (passes whether or not `in_conf` missing-branch is correct — with
  `inline`, `Explore` exits 0 via lane 1 OR lane 3) → set `panes max=2` so a correct guard must exit 2.
- **Minor-5** two mutants survive 23/0: widening bound to `1[0-9]` (accepts 17-19) and dropping
  `nosession` from the policy loop → add `max=17` boundary test + an `env_sid`/`nosession` precedence
  case (the session-key triple, a Global Constraint, is currently untested — suite `unset`s
  `CLAUDE_CODE_SESSION_ID` throughout).
- **Minor-6** magic `16` in the regex vs. named `MAX_PANES=16` in the dispatcher — folded into
  Important-1's fix.
- **Minor-7** unvalidated session key interpolated into a path (`guard:87`, pre-existing at `:61`) — a
  `../` key escapes `STATE_DIR`; bounded (both key sources Claude-Code-supplied, content never echoed),
  NOT a regression. Optional `^[A-Za-z0-9._-]{1,64}$` shared key-check at both loops for consistency
  with the spec's frozen injection boundary — **deferred (touches pre-existing code, keep fix scoped)**.
- **Nit-8** last conf line dropped if trailing newline missing (`guard:23`, no `|| [ -n "$line" ]`) —
  latent, both confs currently end `\n`; pre-existing pattern the plan told the implementer to keep.
- **Nit-9** two redirect messages duplicate 3 byte-identical `printf` lines (`:72-77`,`:99-103`) →
  a shared `redirect_steps()`; key order differs cooldown (`sid,env_sid,nosession`) vs policy
  (`env_sid,sid,nosession`) with no comment (env-first is *correct* for policy — `set-policy` keys by
  `env_sid` — but the reasoning is invisible).
- **Security boundary CLEAN:** no `eval`/unquoted expansion; hostile policy content reaches only
  `[ "$line" = inline ]` and `grep` via *stdin* (no pattern/option injection). shellcheck clean.

**NEXT-SESSION Task 3a (do FIRST, before T4):** fix Important-1/2/3 + cheap Minors-4/5 via a pane
implementer under TDD (reproduce each Important as a RED test first). Then T4 (adapter `open_tab` +
`validate_open_tab_args`) — independent, dispatchable in parallel with 3a if budget allows. Minor-7 +
Nits-8/9 optional, carry to final review. Reviewer result file:
`<scratchpad>/pane-results/general-purpose-1784836895-68040-24084.md`.

## Task 3a — resolve the T3 CHANGES-REQUESTED (2026-07-23) — DONE, reviewer APPROVED

**Commit `c74e285`** (parent `3d3e089`), subagent-driven: pane Opus implementer + pane reviewer, both
cmux `surface:83`. **Verified in-checkout by controller** (toplevel `/Users/marksuyat/.claude`, branch
`feat/pane-split-policy`, exactly the 4 domain files — `hooks/pane-dispatch-guard.sh` +
`.test.sh`, `panes/dispatch-pane-agent.sh` + `.test.sh`; 146+/17-; NO `coding-memory/compliance-judge/`
files). Controller independently re-ran: guard **28/0**, dispatcher **51/0**, `shellcheck -x` clean.
`Doc-Exempt` trailer on the code commit (this doc checkpoint is separate). Not pushed by the implementer;
controller checkpoints + pushes.

What landed (all seven review items resolved, each confirmed by the reviewer *running* it):
- **Important-1** (padded-N asymmetry): `set-policy` normalizes N to base-10 (`max=$((10#$max))`,
  `dispatch-pane-agent.sh:254`, after regex+range gate) so files never hold a padded value; guard reader
  unified to `^panes max=([0-9]+)$` + `10#`-based range 1..16 via named `MAX_PANES` (`guard:24-25,111-114`),
  matching `read_policy`. Legacy padded files (`panes max=03`) now ACCEPTED by the guard. Magic `16`-in-regex
  gone (Minor-6 folded in).
- **Important-2** (nosession leak on malformed primary): guard Lane-3 loop breaks on the first *existing*
  policy file regardless of validity (malformed → empty policy → ask); `nosession` appended to the key list
  only when `env_sid` empty (matches `set-policy`'s key `${CLAUDE_CODE_SESSION_ID:-nosession}`). Repro
  (garbage primary + `inline` nosession) now exits 2 (ask), was exit 0 (allow) on the parent.
- **Important-3**: guard header (`:5-16`) rewritten to three-lane reality; comment-only.
- **Minors-4/5 + T2 carry-forward A/B**: de-vacuumed the `in_conf` miss test (`panes max=2` → must exit 2);
  added `max=17→ask` boundary + env_sid/nosession precedence + nosession-fallback tests (kills the two
  surviving mutants); tightened the 3 `set-policy` reject asserts to grep the specific cause; added direct
  5-branch `read_policy` coverage. TDD: new Important repros are RED against parent `3d3e089` (guard 26/2,
  dispatcher 49/2), green at HEAD.

**Reviewer VERDICT: APPROVED.** Reviewer result file:
`<scratchpad>/pane-results/general-purpose-1784838763-48447-16048.md`.

**TWO NEW Minor findings from the 3a review → CARRY TO FINAL REVIEW (fold into the Minor-7 pass):**
- **NEW-A (guard 64-bit wrap):** `guard:113` — a hand-corrupted `panes max=<2^64+3>` wraps to 3 in bash
  arithmetic → guard accepts (redirect) while `read_policy` (test-builtin) rejects → the two disagree once
  Tasks 6/7 wire `read_policy` into the dispatcher. Unreachable via `set-policy` (dies on huge N). Fix: cap
  digits in `POLICY_RE` to `([0-9]{1,2})` on BOTH readers.
- **NEW-B (newly-introduced by `c74e285` — PRIORITIZE):** the rewritten Important-2 key loop is now
  `for key in $keys` (`guard:104`), an UNQUOTED expansion that word-splits + glob-expands session ids; the
  pre-fix loop quoted each key. Reproduced: `session_id="*"` + a `pane-policy-sidfile` in CWD → guard reads
  the wrong file (toward "allow"). Nil real threat (session ids are harness UUIDs) but it's a real new
  unquoted expansion. Fix: build the key list with `set --` (or quote), folded into Minor-7's shared
  `^[A-Za-z0-9._-]{1,64}$` key validation at both loop sites.

**NEXT: Task 4** (adapter `open_tab` verb + `validate_open_tab_args`, surface-ref allowlist
`[A-Za-z0-9:%_.-]`≤64, for tmux/iterm/terminal) — independent of 3a, dispatchable now. Then T5 (cmux
`open_tab`, probe-verified `new-surface --pane`) which T4 gates, T6, T7, T8. Final-review pass before the
branch PR must clear Minor-7 + NEW-A + NEW-B + Nits-8/9; run both full pane suites green + implementation
observability judge before `gh pr create`.

## Task 4 — adapter `open_tab` verb + `validate_open_tab_args` (2026-07-23) — DONE, reviewer APPROVED

**Commit `86d796b`** (parent `57b3eb0`), subagent-driven: pane `general-purpose` implementer + pane
reviewer, both cmux `surface:83`. **Verified in-checkout by controller** (toplevel
`/Users/marksuyat/.claude`, branch `feat/pane-split-policy`, exactly the 5 domain files —
`panes/adapters/{common,tmux,iterm,terminal}.sh` + `panes/adapters.test.sh`; +114/−32; NO `coding-memory/`
files). Controller independently re-ran: adapters suite **36/0**, `shellcheck -x` clean on all four shell
files. `Doc-Exempt` trailer on the code commit (this doc checkpoint is separate). Not pushed by the
implementer; controller checkpoints + pushes.

What landed:
- **`validate_open_tab_args <ref> <title> <launcher>`** in `common.sh` — surface-ref pinned to the anchored
  allowlist `^[A-Za-z0-9:%_.-]{1,64}$` (covers `surface:42`, `%3`, UUID, `window-123`), then delegates
  title/launcher to `validate_open_pane_args`. Reject → stderr reason + `return 1` (adapters exit 65).
- **`open_tab` verb** across all three adapters (each single-verb guard → `case`): tmux = `new-window`,
  iTerm = `create tab`, Terminal.app shares its existing new-tab path (already tab-per-agent). Contract
  65/1/64 exit codes preserved; each prints the new surface ref on success. `open_pane` behaviorally
  untouched (reviewer confirmed byte-identical stdout/stderr/exit vs parent).
- **Tests** (`adapters.test.sh`, +24): `tab_case` helper + open_tab loop over tmux/iterm/terminal —
  dryrun-ok, bad-ref→65, bad-title→65, unknown-verb→64 (12 new cases). TDD RED-first: 9 fails at exit 64
  (adapters only knew `open_pane`) before impl → 36/0 after.

**Security note (reviewer):** in THIS commit the ref is NEVER interpolated into a tmux command line or
osascript heredoc — the allowlist is defense-in-depth for the Task 7 dispatcher, so zero current injection
surface. Reviewer adversarially probed space/`;`/quotes/backtick/`$(id)`/`$HOME`/backslash/newlines/
overlength — all rejected 65 on all three adapters; the 4 documented ref shapes pass.

**Reviewer VERDICT: APPROVED** (no Critical/Important). Result file:
`<scratchpad>/pane-results/general-purpose-1784856585-34789-7236.md`.

**Findings → CARRY TO FINAL REVIEW:**
- **T4-Minor (test tightening):** `adapters.test.sh:55` — open_tab dryrun-ok cases only grep the launcher
  path, not the adapter-specific command; a revert of tmux `open_tab` to `split-window` would still pass
  (the `open_pane` block DOES pin these at `:48-51`). Fix: add `tab_case` asserts for `new-window` (tmux) +
  `create tab` (iterm). The plan's own snippet had the same gap → carry-forward, not a deviation.
- **T4-Nit:** `adapters.test.sh:58-61` unknown-verb check is inline vs. the sibling helper pattern — fold
  into a `want=64` path in `tab_case`. `terminal.sh:16-18` validation moved into the case arm (vs the
  plan's trailing line) — conscious deviation, functionally identical, no action.

**NEXT: Task 5** (cmux adapter `open_tab`, probe-verified `new-surface --pane` — see §Task 1 "exact
primitive"). T4 gated T5; now unblocked. Then T6, T7, T8. Final-review pass before the branch PR must clear
Minor-7 + NEW-A + NEW-B + Nits-8/9 + T4-Minor/Nit; run both full pane suites + adapters suite green +
implementation observability judge before `gh pr create`.

## Task 5 — cmux adapter `open_tab` verb (2026-07-23) — DONE, reviewer APPROVED

**Commit `a443b82`** (parent `3f7b575` — the prompt's expected parent `86d796b` was stale by one docs
checkpoint; chain `a443b82 → 3f7b575 → 86d796b`, no anomaly). Subagent-driven: pane `general-purpose`
implementer + pane reviewer, both cmux `surface:83`. **Verified in-checkout by controller** (toplevel
`/Users/marksuyat/.claude`, branch `feat/pane-split-policy`, exactly 2 domain files —
`panes/adapters/cmux.sh` +38/−4, `panes/adapters.test.sh` +33/−2; NO `coding-memory/` files; vibe-scape's
3 uncommitted compliance-judge files untouched). Controller independently re-ran: adapters suite **43/0**,
`shellcheck -x panes/adapters/cmux.sh` clean. `Doc-Exempt` trailer on the code commit. Not pushed by the
implementer; controller checkpoints + pushes.

What landed in `panes/adapters/cmux.sh`:
- Single-verb guard (`[ "$1" = open_pane ] || …`) → a `case` (`:27-33`): `open_pane` binds `$2/$3`,
  `open_tab` binds `ref_in/$3-title/$4-launcher` + `validate_open_tab_args … || exit 65`, `*` → usage/64.
  Validation stays at the TOP (before any cmux call) so the injection boundary holds.
- **`cmux_open_tab <surface-ref> <title>`** (defined `:263`, after `split_capture`): dryrun → prints the
  `new-surface`/`send` intent, returns 0. Live → `fetch_tree` → `layout_normalize_tree` (TSV
  `pane_ref\tref\ttitle`) → awk `$2==ref{print $1}` resolves the surface's **pane_ref** →
  `split_capture new-surface --pane <pane_ref>` (appends `WS_ARGS`) → `finish_surface` sends launcher +
  prints new ref. Every failure (no tree / surface-not-in-tree / new-surface fail) → `return 1` so the
  dispatcher degrades. Dispatched by `if [ "$verb" = open_tab ]; then cmux_open_tab …; exit $?; fi` (`:277`).
- One-line fix: open_pane dryrun block gated `[ "$verb" = open_pane ] && [ "$PANE_DRYRUN" = 1 ]` (`:220`) so
  an open_tab dryrun isn't swallowed by the open_pane preview.

**Implementer deviations from the plan's sketch (reality won, both sound):** (1) the plan called
`cmux_open_tab` directly from the top-of-file `case` — where the function + `fetch_tree`/`split_capture`
aren't defined yet → would die "command not found"; split into validation-at-top / execution-dispatched-
after-`split_capture`. (2) Dropped the in-function `launcher_q` recompute: binding `launcher` at the case
arm lets the pre-existing top-level `launcher_q="$(printf %q …)"` (`:120`) quote the tab's launcher — verified
equivalent by trace. Confirmed (not deviated): `layout_normalize_tree` exists under that name
(cmux-layout.sh:36), `stamp_title`'s `[ -n "$TREE_RAW" ] || return 0` short-circuit exists (`:174`, so the
tab title is best-effort — cosmetic, the send already landed), `validate_open_tab_args` reused from common.sh.

**Reviewer VERDICT: APPROVED** (no Critical/Important) — probed live, not just read: 10 metachar/space/quote/
`;`/`$()`/backtick/newline injection attempts → **zero** reached a cmux command line (ref only hits awk `-v`
+ `printf %s`; `--pane` is tree-derived); 64-char ref accepts, 65 rejects; **7** degrade paths all rc 1;
`open_pane` **byte-identical** stdout/stderr/rc vs `a443b82~1`. Result file:
`<scratchpad>/pane-results/general-purpose-1784859305-76407-30719.md`.

**Findings → CARRY TO FINAL REVIEW:**
- **T5-Minor (test tightening):** `adapters.test.sh` live fake's `*"new-surface"*` arm doesn't pin `--pane`,
  so the resolution's **output column** is unverified — mutating `cmux.sh:271` `print $1`→`print $2` (passes
  the surface ref, not pane ref, to `--pane`) leaves the suite GREEN (only the wrong-column class escapes;
  removing resolution entirely IS caught). Fix: match `*"new-surface --pane pane:36"*` + add else-arm
  `*"new-surface"*) exit 1`. NB the T4-Minor (dryrun not pinning the command) **was fixed** here —
  `adapters.test.sh:63` pins `new-surface` and fails on revert.
- **T5-Nit:** `check_cmux_version` (`cmux.sh:336`) is unreachable from the `open_tab` dispatch (exits at
  `:279` first) — version-mismatch warning/receipt never fires on tab dispatch. Mitigated: overflow tabs only
  occur after ≥1 same-session `open_pane`, which does warn. (Re-probe cmux after any upgrade regardless.)
- **T5-Nit:** open_pane-only top-level derivations (`role` `:97`, `run_id` `:106`) run on the open_tab path
  though unused there; a nonconforming run-id would emit a misleading "surface unmanaged" stderr line.
  Cosmetic; real dispatcher run-ids conform.

**NEXT: Task 6** (dispatcher lane/session/surface markers + `count_live_workers` on REAL run-dir fixtures +
judge bypass; interim `count >= N` → in-process exit 3, replaced by `open_tab` overflow in Task 7). Then T7,
T8. Final-review pass before the branch PR must clear Minor-7 + NEW-A + NEW-B + Nits-8/9 + T4-Minor/Nit +
**T5-Minor + T5-Nits**; run both full pane suites + adapters suite green + implementation observability judge
before `gh pr create`.

## Task 6 — dispatcher lane/session markers + live-worker count + judge bypass (2026-07-23) — DONE, reviewer CHANGES-REQUESTED (→ Task 6a)

**Commit `e6ef22c`** (parent `6cb8687`), subagent-driven: pane `general-purpose` implementer + pane reviewer,
both cmux `surface:83`. **Verified in-checkout by controller** (toplevel `/Users/marksuyat/.claude`, branch
`feat/pane-split-policy`, exactly 2 domain files — `dispatch-pane-agent.sh` +55/−2, `.test.sh` +42; NO
`coding-memory/` files; vibe-scape's 4 uncommitted compliance-judge files untouched). Controller independently
re-ran: dispatcher suite **58/0**, `shellcheck -x` clean on both files. `Doc-Exempt` trailer on the code commit.

What landed in `panes/dispatch-pane-agent.sh`:
- `REDIRECT_CONF="${PANE_REDIRECT_CONF:-$PANES_DIR/redirect-agents.conf}"` (after `DETECT=`).
- `is_judge <type>` — 0 if the type is listed in the judge conf (comment/whitespace stripped).
- `count_live_workers <key>` — counts `runs/*/` dirs with `lane=worker` + `session=key` + no `agent-exit`;
  missing `RUNS_DIR` → `0`. Judge/other-session/exited excluded by two file checks (the least-proven piece).
- `open_pane_or_cooldown` gains an optional 3rd arg (run dir) → writes `<dir>/surface` after `open_pane` OK.
- `dispatch)` arm: tag `lane`+`session`; worker under `panes max=N` → gate on `count_live_workers` (`>=N` →
  `die … 3` interim in-process, NO cooldown; comment marks it "replaced by open_tab in Task 7"). Judge → always
  `open_pane`, never counted/gated.
- `count-workers` debug subcommand.
TDD RED confirmed by BOTH implementer and reviewer against parent `6cb8687`: baseline 51/0 → 53/5 with the 5
load-bearing new cases failing pre-impl.

**Reviewer VERDICT: CHANGES-REQUESTED** — verified by running (RED baseline 53/5, 6/7 mutants killed, parsers
compared over a hostile conf, live repros). Result file:
`<scratchpad>/pane-results/general-purpose-1784862912-50292-28807.md`.

- **C1 (CRITICAL) — dispatch counts ITSELF → off-by-one, `max=1` never opens a worker pane.** Markers
  (`sh:196-197`) are written BEFORE the gate (`:203-217`), so `count_live_workers` always includes the run
  being dispatched. Live repro (empty runs dir): `set-policy panes --max 1` → first worker dispatch →
  `worker max 1 reached (1 live)` exit 3, with ZERO other workers. Capacity is N−1 (`max=3`→2 panes; `max=1`→0
  ever). Violates the task contract ("count < N → open_pane") and BREAKS Task 7 (overflow must `open_tab` into a
  live worker pane that can't exist at `max=1`). Plan Step 4 had the same ordering — plan bug faithfully
  implemented. **Shipped green only because the suite has NO "worker under max opens a pane" positive case.**
  **Fix (reviewer verified in scratch, suite stays 58/0): move the two marker-write lines to just before the
  `open_pane_or_cooldown` call (after the gate) + add the missing positive test (`max=2`, 1 live fixture,
  dispatch → rc 0).**
- **I1 (IMPORTANT) — phantom live workers (implementer-flagged, CONFIRMED).** Three die-after-marker paths
  leave a `lane=worker` dir with no `agent-exit`, counted live until 7-day cleanup: over-max exit 3, no-terminal
  exit 3, adapter-fail exit 4. Traced: at `max=1` a gated dispatch bumped count 1→2; after the real worker
  exited it stayed 2 → next dispatch gated again → permanent pane-path starvation. **The C1 reorder kills the
  dominant (gated exit-3) source for free** (dispatch dies before tagging). Residual two are bounded (no-terminal
  rarely reaches the dispatcher — guard fails open first; adapter-fail writes the cooldown flag so the phantom is
  never consulted again; per-session keying blocks cross-session pollution) → **acceptable carry-forward, but
  PIN to Task 7's contract: dead-mark the run dir (`agent-exit`) on failure paths OR count only dirs with a
  `surface` marker** (Task 7's round-robin reads live workers' surfaces; a phantom has none). Nuance: a
  `fail_early` runner death also leaves no `agent-exit` by design (pane preserved) — counting that one is
  defensible (the pane genuinely holds a slot).
- **M1 (Minor) — weak test: `is_judge` comment-stripping unasserted.** Removing `line="${line%%#*}"` survives
  58/0 (fixture conf has no comments; real conf is 7/9 comment lines). Fix in 6a: add a commented + a
  whitespace-padded entry to the fixture conf.
- **M2 (Minor) — conf-path split-brain under `PANE_HOME`.** Dispatcher default honors `PANE_HOME`
  (`$PANES_DIR/redirect-agents.conf`); the guard hardcodes `$HOME/.claude/panes/redirect-agents.conf`. With
  `PANE_HOME` set but no `PANE_REDIRECT_CONF`, the two read different files (guard says judge, dispatcher says
  worker). Low likelihood (tests + hook set `PANE_REDIRECT_CONF`). **Carry-forward:** align the guard's default
  or document the constraint.
- **Nits:** both parsers drop a final line with no trailing newline (they AGREE — no split-brain; real conf ends
  `\n`); `count-workers`/`set-policy` absent from the usage string (pre-existing drift); `count_live_workers ""`
  would match empty-session dirs (unreachable via CLI). All carry-forward.
- **Security boundary CLEAN** — Task 6 did NOT widen exposure. Session key hits only marker-file *content* +
  quoted string tests; count glob `"$RUNS_DIR"/*/` never interpolates the key; `pane-policy-$key` is the
  pre-existing bounded read (Minor-7). `agent_type` regex-validated before `is_judge`/title.

**NEXT: Task 6a** (do FIRST, before T7) — under TDD, reproduce C1 as a RED positive test (worker under `max`
must open a pane; currently gated) then fix by reordering the two marker writes to after the gate; add the M1
fixture lines. Pin I1's residual dead-marking to Task 7's contract. Then T7, T8. Implementer result file:
`<scratchpad>/pane-results/general-purpose-1784862477-35934-9310.md`. Final-review carry-forward now also
includes **M2 + the three Task 6 Nits**.

## Task 6a — fix C1 off-by-one (marker writes after the gate) + M1 (2026-07-24) — DONE, reviewer APPROVED

**Commit `8ef4868`** (parent `d76ca82`), subagent-driven: pane `general-purpose` implementer + pane reviewer,
both cmux `surface:83`, `--role implementer`. **Verified in-checkout by controller** (toplevel
`/Users/marksuyat/.claude`, branch `feat/pane-split-policy`; `git show --stat HEAD` = EXACTLY 2 domain files —
`dispatch-pane-agent.sh` +6/−2, `.test.sh` +27/−1; NO `coding-memory/` files). Controller independently re-ran:
suite **61/0**, `shellcheck -x` clean on both, and read the .sh diff to confirm the relocation is real.
`Doc-Exempt` trailer on the code commit. **Index note:** the other-session `coding-memory/compliance-judge/*`
files were **STAGED** (not just modified) this session — implementer used a pathspec commit
(`git commit panes/… panes/…`), never `-a`/`add -A`, so they stayed staged and untouched.

The fix (C1, the reviewer's Task 6 CRITICAL):
- Moved ONLY the two marker-WRITE lines (`printf '%s\n' "$lane" > "$run_dir/lane"` and `… > "$run_dir/session"`)
  from before the worker gate to just before `open_pane_or_cooldown`, after the whole `if [ "$lane" = worker ]`
  block. `key="${…:-nosession}"` and the `is_judge` lane assignment stayed before the gate (the gate reads the
  `$key`/`$lane` VARIABLES, not the files). Added C1/I1 rationale comments at both the gate `die` and the new
  write point.
- **Result:** `count_live_workers "$key"` (called in the gate) no longer sees THIS dispatch's own run dir →
  capacity is N (not N−1). Boundary the bug was really about — `panes max=1`, 0 live — now opens exactly one
  pane and `count-workers` reports 1 afterward (reviewer-reproduced).
- **I1 dominant source killed for free:** a gated worker now `die … 3`s BEFORE any marker is written, so it
  leaves no `lane=worker` run dir behind (reviewer reproduced: gated run dir at `max=1` holds only
  `launch.sh` + `prompt.md`). Residual phantom paths (adapter-fail exit 4, no-terminal exit 3 that reach the
  dispatcher — rare, guard fails open first) still write markers before an open failure → carry to Task 7's
  dead-marking / count-only-dirs-with-`surface` contract, as before.

M1 (weak-test fix): strengthened the judge-conf fixture (`$PANE_REDIRECT_CONF`) with a comment-only line, an
INLINE comment on `compliance-judge`, and whitespace-padding on `observability-judge`, plus a new assertion that
`observability-judge` is still recognized as a judge. Both `is_judge` strips are now asserted — controller AND
reviewer independently verified the mutations bite: delete `${line%%#*}` → RED (57/4), delete
`tr -d '[:space:]'` → RED (55/6).

New positive test — "worker under max opens a pane" (`UMAX_SID`, 1 live-worker fixture, `panes max=2`, dispatch
→ rc 0). RED against parent confirmed by BOTH implementer and reviewer: reverting only the .sh to `d76ca82`
(keeping HEAD's test) fails with `rc=3: worker max 2 reached (2 live)` (60/1). The test genuinely discriminates
C1 — the missing positive case that let C1 ship green in Task 6.

**Reviewer VERDICT: APPROVED** — six required checks + three adversarial angles all RUN in an isolated detached
worktree (`/tmp/pane-review-*`, removed; live index untouched). No Criticals/Importants. Confirmed statically +
dynamically that nothing between the old and new marker location reads the marker *files* (only
`count_live_workers` does, during the gate). Result file:
`<scratchpad>/pane-results/general-purpose-1784904471-48929-5562.md`.
- **T6a-Minor (carry-forward, non-blocking):** the new positive test asserts only `rc -eq 0`, not that the fake
  adapter was invoked / a `surface` marker was written. Reviewer: no real gap today (control flow has no clean
  exit-0 that skips `open_pane_or_cooldown`'s adapter success), but a future refactor could open one. Fold into
  final review — add `grep -q '^PANE_REF:' <<<"$out"` or a `surface`-file check to match the happy-path test's
  rigor.

**NEXT: Task 7** (overflow → `open_tab` round-robin, `pane-rr-<key>`). The C1 fix is a hard prerequisite: Task 7
overflows a worker into a LIVE worker pane's tab, which at `max=1` could not exist under the N−1 bug. Pin I1's
residual: dead-mark run dirs on failure OR count only dirs with a `surface` marker (Task 7 reads live workers'
surfaces for round-robin; a phantom has none). Then Task 8 (skill + gate-stub correction + ADR 0009 + Mermaid).
Final-review carry-forward now: Minor-7 + NEW-A + NEW-B + Nits-8/9 + T4-Minor(fixed)/Nit + T5-Minor/Nits + M2
(PANE_HOME conf split-brain) + the three Task 6 Nits + **T6a-Minor**.

---

## Task 7 — worker overflow to `open_tab` (round-robin) (2026-07-24) — DONE, reviewer APPROVED

**Commit `7cb43b0`** (parent `4356802`), subagent-driven: pane `general-purpose` implementer, cmux
`surface:83`, `--role implementer`. **Verified in-checkout by controller** (`git rev-parse --show-toplevel`
= `/Users/marksuyat/.claude`, branch `feat/pane-split-policy`, `git worktree list` = single checkout;
`git show --stat HEAD` = EXACTLY 2 domain files — `dispatch-pane-agent.sh` +89/−22, `.test.sh` +132/−2; NO
`coding-memory/` files, the four other-session compliance-store files still staged and untouched via a
pathspec commit). `Doc-Exempt` trailer present. Controller independently re-ran ALL SEVEN suites —
guard 28/0, **dispatcher 82/0**, adapters 43/0, cmux-layout 34/0, cmux-exec 81/0, run-pane 10/0,
detect 9/0 (287 total) — plus `shellcheck -x` clean on both files, and read the full `.sh` diff.

### The plan was wrong against the LOCKED spec — two corrections the controller added to the brief

Plan Task 7 (lines 942–1075) leaves the `lane`/`session` marker writes unconditional, so an overflow
dispatch would be tagged `lane=worker` exactly like a pane dispatch. Both corrections were briefed
BEFORE dispatch, TDD'd, and mutation-checked independently.

- **A — a tab-run is not a pane.** Spec §3 caps "max CONCURRENT worker **panes**" and overflows into
  "an existing live worker **pane**". Counting tab-runs breaks the Gherkin *"A freed worker pane is
  reclaimed rather than tabbed"* (2 panes + 2 tabs = `live 4 >= 3`, so a freed pane is never reclaimed
  — the implementer reproduced this literally as `worker max 3 reached (4 live)`), and selecting one
  would hand `open_tab` a tab's ref → a tab nested in a tab. Fix: a `kind` marker (`pane`|`tab`), a
  **MISSING `kind` reads as `pane`** (keeps pre-T7 run dirs + all Task 6 fixtures valid).
- **B — the I1 residual pinned by Task 6a.** A dispatch that never gets a surface used to sit there
  `lane=worker` with no `agent-exit` → counted live all session; phantoms inflate the count into
  premature overflow and, having no `surface`, are not even selectable targets → the overflow dies
  exit 3, i.e. in-process, which the spec forbids. Fix: `dead_mark` (writes `agent-exit`
  `DISPATCH-FAILED`) on the no-terminal and adapter-failure paths. Chosen over "count only dirs with a
  `surface`", which races an in-flight dispatch between its marker write and its surface write and
  would let a concurrent dispatch exceed N.

### Implementer's deviations from the plan's literal snippets (all controller-reviewed in the diff)

1. **One shared predicate, not two.** `live_worker_panes <key>` prints one live worker-*pane* dir per
   line; `count_live_workers` and `select_worker_surface` are both built on it. The two must never
   disagree about what a live worker pane is — that disagreement IS correction A's bug class. One
   mutant (delete the `kind=tab` line) kills 4 assertions across both functions.
2. **No separate `open_tab_or_cooldown`.** Unified `open_surface_or_cooldown <verb> <run_dir|""> <args…>`
   (3 call sites incl. `handoff` with an empty run dir); the plan would have duplicated the terminal
   check + cooldown + dead-mark for the second verb, and the dead-mark is exactly what must not drift.
3. **Target resolved BEFORE the marker writes**, so a no-target overflow dies having written no markers
   at all — that phantom path is gone by construction, not by dead-marking. Task 6a's C1 ordering
   (markers strictly after the worker gate) is intact; only a third write (`kind`) joined the two.
4. `select_worker_surface` splits its `local` (`rr` needs its own — SC2318: `$key` is not yet in effect
   within the same `local`). `count_live_workers` inherits the `[ -d "$RUNS_DIR" ]` early return from
   `live_worker_panes` (re-verified: missing RUNS_DIR still prints `0`, rc 0).
5. Test fixture helper `mk_run_ref` uses `mktemp -d`, NOT a counter: several call sites capture the dir
   with `$(...)`, and a subshell's counter increment is lost to the parent, so fixtures silently reused
   one dir and produced a **false RED** (`3 live` not `4`). **Latent hazard: the pre-existing `mk_run`
   has the same bug**, harmless today only because every current call site is a plain redirect.

### Evidence

Baseline `4356802`: 61/0. Tests-first, implementation untouched → **67 passed, 15 failed**. After
implementation → **82/0**. Mutants: revert only the `.sh` → 67/15 (restore → 82/0); delete the
`kind=tab` exclusion → 78/4 (incl. `a freed worker pane is reclaimed (tab-target=surface:FT1)` — it
tabbed INTO a tab); delete both `dead_mark` calls → 79/3. A and B each fail independently.

### Carry-forwards raised by the implementer (fold into final review)

- `dispatch-pane-agent.sh` is now **387 lines** — under the 400 soft limit with no headroom. Task 8 is
  docs-only so nothing else lands here this branch; the next dispatcher change should split the
  run-dir/marker helpers out.
- `dispatch-pane-agent.test.sh` is **424 lines** (>400 soft, well under the 800 hard cap).
- `mk_run`'s `$RANDOM`/subshell collision hazard (item 5) — latent, no current call site trips it.
- The rr index advances even when the subsequent `open_tab` fails, so a failed overflow skips a pane in
  the rotation. Cosmetic (round-robin is spec assumption 3, a fairness heuristic with least-loaded as
  the named fallback), and after an `open_tab` failure the cooldown means no further overflow this session.
- `live_worker_panes` iterates glob order (run-dir name = `epoch-pid-random`), so round-robin runs over
  an arbitrary-but-stable order, not dispatch order. Spec-conformant; noted because a reviewer may
  expect oldest-first.
- **Unbounded tabs:** tab-runs are excluded from the count, so nothing caps how many tabs pile up.
  Believed spec-intended (N caps panes; "does not block/wait") — flagged to the reviewer to judge.

### Reviewer VERDICT: APPROVED (pane `general-purpose`, cmux `surface:83`, detached worktree `/tmp/pane-review-t7`, removed)

Zero Criticals, zero Importants. All six required checks RUN, all eight adversarial angles RUN and
reported. Independently reproduced: 287/0 across seven suites (twice, pristine tree), `shellcheck -x`
v0.11.0 clean, RED at `4356802` = 67/15 with `worker max 3 reached (4 live)`, both correction-mutants
kill (78/4 and 79/3), C1 non-regression proved end-to-end from an empty state dir (`max=1`/0-live →
exactly one `open_pane`, `post-count: 1`, `kind marker: pane`). It added a THIRD mutant the brief did
not ask for — hoist the marker writes above the gate → 77/5 — proving the target-resolution-before-
markers **ordering** is load-bearing, not incidental. Result file:
`<scratchpad>/pane-results/general-purpose-1784923348-87600-1119.md`.

Angles it closed for good (no follow-up needed): **bash 3.2.57 is the only bash on PATH**, so
`#!/usr/bin/env bash` really is 3.2 in production — the empty-array-under-`set -u` trap is REAL there
(`"${refs[@]}"` does throw), but this code only ever uses `${#refs[@]}` and reaches the indexed
expansion after the `-gt 0` guard; empty-`refs` exercised directly → `rc=1`, no error. **Injection
boundary holds under active attack:** eight hostile `surface` marker payloads (`; touch`, `$(…)`,
backticks, `--new-flag`, `../../../etc/passwd`, quote-splitting, 76-char overflow) fed through the
REAL cmux adapter — all eight rejected by `validate_open_tab_args`' allowlist → exit 65 → dispatcher
exit 4 + cooldown + dead_mark, no artifact created. A multi-line `surface` file cannot inject extra
argv (command substitution keeps it one argument, which then fails the allowlist). The dispatcher does
not pre-validate `target` — it relies wholly on the adapter, consistent with the existing design and
failing closed. **`handoff`** with an empty run_dir: correct 3 args, no `surface`, no `lane`,
`count-workers` = 0; `dead_mark ""` / no-arg / `/nonexistent` all rc 0, create nothing. **Missing
RUNS_DIR** → `stdout=[0] rc=0`.

**MINOR 1 — the one thing needing a human decision. Concurrent fan-out can still degrade an overflow
to in-process, which spec §3 forbids.** `dispatch-pane-agent.sh:271-272` vs `:284-289`: a dispatch's
`surface` marker is written only AFTER the adapter call returns, but its `lane`/`session` markers are
written BEFORE it. So for the whole duration of a real `open_pane` (a live cmux call — seconds) that
run is COUNTED as a live worker pane but is NOT selectable as an overflow target. A second dispatch
arriving in that window sees `live >= n`, finds no selectable surface, and takes the exit-3 in-process
path — violating spec line 63-64 ("does not overflow to inline") and the line-217 Gherkin ("nothing
runs in-process" for a 5-worker fan-out at max=3). Parallel fan-out is explicitly the governed lane
(spec line 47), so this IS the intended workload. Proved with a 2-second `open_pane` adapter at max=1:
`B: rc=3 | worker max 1 reached (1 live) and no live worker pane to tab into` while `A: rc=0`.
Graded Minor because it is **not a regression** (at `4356802` that same B also exited 3 — the whole
over-max path was interim in-process), it degrades safely, and spec "Error handling" (line 175-181)
blesses in-process degrade on every path. **There is no clean fix:** the ref does not exist until the
adapter returns, so the alternatives are blocking (spec-forbidden) or inventing a ref. Inherent to the
spec's own design → document as an accepted trade-off in `skills/dispatching-pane-agents` (T8), or
raise a spec amendment with the user. Do NOT code around it.

**MINOR 2 — free one-line hardening.** `:282-284` writes markers `lane` → `session` → `kind`, and the
predicate gates on `lane==worker && session==key` before checking `kind`. Between the `session` and
`kind` writes a `kind=tab` dispatch is visible to a concurrent counter as a PANE (missing `kind` reads
as `pane` BY DESIGN). Materialized: `after lane only → count=0` (safe) · `after lane+session → count=1`
(a TAB counted as a PANE) · `after all three → count=0`. Writing `kind` FIRST and `lane` LAST closes it
and makes `lane` the single atomic commit point for the whole marker set. Microseconds, dwarfed by
Minor 1, no downside → fold into T8.

**NIT 1** the rr index advances even when `open_tab` fails (confirmed 1→2→3 across three failed
overflows) and is written before the open succeeds — bounded to skipping one pane, and nearly
unreachable because the FIRST `open_tab` failure writes the session cooldown. Within spec line 194-195's
sanctioned tolerance. **NIT 2** glob order over `epoch-pid-random` = by PID then random within one epoch
second; spec-conformant (the essential property — spreading overflows across distinct panes — holds for
any stable order). **NIT 3** (report prose only, not the code): the plan's single-`local` form does not
merely trip shellcheck — `local key="$1" rr="…$key"` resolves `$key` to the OUTER scope and ERRORS under
`set -u` when no outer `key` exists; it would have produced the right filename only because the dispatch
arm happens to have a global `key` of the same value. The code comment at `:123` is accurate.

**Reviewer's carry-forward to FINAL review:** (1) Minor 1 — decide: document as accepted trade-off vs
spec amendment. (2) Minor 2 reorder. (3) `mk_run`'s latent `$RANDOM`-in-subshell hazard — fix before
anyone adds a capturing call site; it already produced one false RED. (4) No tab-run cap exists anywhere
BY DESIGN — if "too many tabs" ever surfaces, the lever is spec §4's least-loaded fallback (line 194-195),
not a cap.
