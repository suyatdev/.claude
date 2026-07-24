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
