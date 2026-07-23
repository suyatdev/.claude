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
