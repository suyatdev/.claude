# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See `managing-session-memory` for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- session_origin: desktop · session_started_at: 2026-07-23 (Opus 4.8) · last_active_branch:
  **`feat/pane-split-policy`** — **RESUME after clear. Restored clean: HEAD `6888e16` in sync w/ origin;
  spec blob VERIFIED still `cdc777a` (lock intact, compliance verdicts valid).** doc-guard's two flagged
  files (`verdicts.jsonl` +3 vibe-scape lines, `css-visual-pass.md`) confirmed the vibe-scape session's —
  NOT mine, left as-is. **HARD MODEL GATE ANSWERED THIS SESSION: Opus 4.8 for `superpowers:writing-plans`;
  IMPLEMENTATION tier still deferred — re-ask before any coding.** **writing-plans IN PROGRESS:** read the
  spec + all target infra (`hooks/pane-dispatch-guard.sh`, `panes/dispatch-pane-agent.sh`,
  `panes/redirect-agents.conf`, adapters). **PLAN WRITTEN + self-reviewed →
  `docs/superpowers/plans/2026-07-23-pane-split-policy.md` (committed).** 8 TDD tasks: T1 live cmux
  tab-primitive probe (HARD GATE, operator-run on real cmux — gates T5); T2 `pane-policy-<key>` state +
  `set-policy` subcommand + `read_policy` (bounded N 1..16); T3 guard 3-lane routing + new
  `inprocess-agents.conf` (Explore/Plan) + narrowed `redirect-agents.conf` (judges); T4 `open_tab`
  adapter verb + `validate_open_tab_args` (surface-ref allowlist `[A-Za-z0-9:%_.-]`≤64) for
  tmux/iterm/terminal; T5 cmux `open_tab` (probe-verified `new-surface --pane`); T6 dispatcher
  lane/session/surface markers + `count_live_workers` (proven on REAL run-dir fixtures) + judge bypass;
  T7 overflow → `open_tab` round-robin (`pane-rr-<key>`); T8 skill + gate-stub correction + ADR 0009 +
  Mermaid. Config decision RESOLVED (two flat include-lists). All 7 Gherkin scenarios + 4 flagged
  assumptions mapped to tasks. **HARD MODEL GATE ANSWERED 2026-07-23 (impl tier): Opus 4.8 (1M) for the
  whole 8-task implementation; execution = SUBAGENT-DRIVEN (pane-routed implementers). `settings.json` is
  `opus[1m]` so pane implementers inherit Opus — no Fable 5 surprise. Do NOT re-ask either gate for this
  branch's execution.** **T1 DONE + pushed (`fe7f30a`) 2026-07-23 — live cmux 0.64.20 probe PASS:
  `new-surface --pane <pane-ref>` IS the open_tab primitive (in-pane tab; confirmed structurally in the
  tree AND visually Q1 one-workspace/Q2 two-tabs/Q3 TAB_SEND_OK; agent launches via
  `send --surface <new-ref>`). So "spawns beyond N open as tabs inside existing panes" is achievable.
  Findings + exact verb/flags + the surface→pane resolution note that feeds T4/T5 in
  `coding-memory/branches/pane-split-policy.md`; probe `panes/cmux-tab-probe.sh`, fixture
  `panes/adapters/fixtures/tab-live.json`.** **T2 DONE 2026-07-23 (subagent-driven: pane Opus implementer + pane task-reviewer):** commit
  `8fb4534`, commit-verified in-checkout; policy state file — `set-policy` writer + `read_policy`
  reader (bounded N 1..16, dual-validated at write+read, fail-open), `read_policy` defined-but-uncalled
  (consumed by T3/6/7). 44/44 tests, shellcheck -x clean, review Spec ✅/Approved/0 Crit-Imp. Detail +
  T3 carry-forwards: `coding-memory/branches/pane-split-policy.md` §Task 2. **T3 DONE 2026-07-23
  (subagent-driven: pane Opus implementer + pane reviewer, both cmux surface:83):** commit `6bead2d7`,
  **verified in-checkout** (4 domain files only), guard test **23/0 re-run by controller**, shellcheck
  clean, Task 2 suite still 44/0. Guard now three-lane (read-only `inprocess-agents.conf` → judges
  `redirect-agents.conf` → per-session policy). **Reviewer = CHANGES-REQUESTED (narrow; arch stands,
  T4 unblocked).** Fail-open missing-conf ruled ACCEPTABLE. **2 Important defects reproduced end-to-end
  (must fix before branch PR): (1) zero-padded N ask-loop — `set-policy --max 03` writes `panes max=03`
  but guard regex rejects it → ASK forever; (2) stale `pane-policy-nosession` overrides a MALFORMED
  primary policy → wrongly allows.** + Important-3 stale guard header + Minors 4-7 + Nits. Full repro +
  fixes: `coding-memory/branches/pane-split-policy.md` §Task 3. **T3a DONE + reviewer APPROVED 2026-07-23
  (subagent-driven: pane Opus implementer + pane reviewer, both cmux surface:83):** commit `c74e285`,
  **verified in-checkout** (4 domain files only, 146+/17-, no store files), controller re-ran guard **28/0**
  + dispatcher **51/0**, shellcheck clean. Fixed Important-1 (base-10 normalize N + unified guard regex),
  Important-2 (break on first existing policy, nosession only when env_sid empty), Important-3 (three-lane
  header), Minors-4/5 + T2 carry-forward A/B; TDD Important repros RED against parent (26/2, 49/2). **TWO NEW
  Minors from the 3a review → final-review carry-forward (fold into Minor-7): NEW-A guard 64-bit `10#` wrap
  vs read_policy (cap POLICY_RE digits `{1,2}`); NEW-B — PRIORITIZE — `c74e285` introduced an UNQUOTED
  `for key in $keys` at guard:104 (quote via `set --`).** Detail: branch log §Task 3a. **T4 DONE + reviewer APPROVED 2026-07-23
  (subagent-driven: pane `general-purpose` implementer + pane reviewer, both cmux `surface:83`):** commit
  `86d796b` (parent `57b3eb0`), **verified in-checkout** (5 adapter files only, +114/−32, `Doc-Exempt`),
  controller re-ran adapters suite **36/0** + shellcheck clean. `open_tab` verb on tmux(`new-window`)/
  iterm(`create tab`)/terminal(shared path) + `validate_open_tab_args` (anchored allowlist
  `^[A-Za-z0-9:%_.-]{1,64}$`); ref not yet interpolated anywhere (defense-in-depth for T7); reviewer
  adversarially probed the boundary, all rejected 65; open_pane byte-identical vs parent. **T4
  carry-forward → final review:** T4-Minor `adapters.test.sh:55` (open_tab dryrun cases don't pin
  `new-window`/`create tab` — a revert would pass; **FIXED in T5's cmux case**) + T4-Nit (inline unknown-verb
  test). Detail: branch log §Task 4. **T5 DONE + reviewer APPROVED 2026-07-23 (subagent-driven: pane
  `general-purpose` implementer + pane reviewer, both cmux `surface:83`):** commit `a443b82` (parent
  `3f7b575`), **verified in-checkout** (2 domain files only — `cmux.sh` +38/−4, `adapters.test.sh` +33/−2;
  vibe-scape's 3 uncommitted compliance-judge files untouched), controller re-ran adapters **43/0** +
  shellcheck clean. cmux verb guard → `case`; new `cmux_open_tab` resolves surface-ref → its `pane_ref` via
  `fetch_tree`+`layout_normalize_tree`+awk, then `new-surface --pane <pane_ref>` (Task 1 primitive) + send;
  every failure → return 1 (degrade). Implementer caught + fixed the plan's call-before-define (split
  validation-at-top / execution-after-`split_capture`). Reviewer probed live: 10 injection attempts → zero
  reached a cmux line, 7 degrade paths all rc 1, open_pane byte-identical vs `a443b82~1`. **T5 carry-forwards
  → final review:** T5-Minor (live fake's `new-surface` arm doesn't pin `--pane` → wrong-column mutation
  `print $1`→`print $2` stays green; fix: match `--pane pane:36` + else-arm `exit 1`) + T5-Nit
  (`check_cmux_version` unreachable on open_tab path) + T5-Nit (open_pane-only role/run_id derivations run
  harmlessly on tab path). Detail: branch log §Task 5. **T6 DONE + reviewer CHANGES-REQUESTED → Task 6a
  2026-07-23 (subagent-driven: pane `general-purpose` implementer + pane reviewer, both cmux `surface:83`):**
  commit `e6ef22c` (parent `6cb8687`), **verified in-checkout** (2 domain files only — `dispatch-pane-agent.sh`
  +55/−2, `.test.sh` +42; no store files), controller re-ran dispatcher **58/0** + shellcheck clean, `Doc-Exempt`.
  Landed: `is_judge`, `count_live_workers` (runs/* with `lane=worker`+`session=key`+no `agent-exit`), lane/session/
  surface markers, `count-workers` subcommand, worker gate (`count>=N`→interim exit 3 no-cooldown). **Reviewer
  verified by running (RED baseline 53/5, 6/7 mutants killed, parsers compared, live repros). VERDICT:
  CHANGES-REQUESTED — C1 CRITICAL: dispatch counts ITSELF (markers written BEFORE the gate) → off-by-one,
  `max=1` never opens a worker pane, capacity is N−1, BREAKS Task 7.** Plan Step 4 had the ordering bug; shipped
  green only because there's NO "worker under max opens a pane" positive test. **Task 6a fix (reviewer-verified in
  scratch): move the 2 marker-writes to after the gate + add that positive test; also M1 (add commented/padded
  fixture-conf lines so `is_judge` comment-strip is asserted).** I1 (phantom workers) CONFIRMED — C1 reorder kills
  the dominant gated-exit-3 source; residual (no-terminal exit 3, adapter-fail exit 4) bounded, carry to Task 7 as
  a dead-marking requirement. Security boundary CLEAN. Detail + full findings: branch log §Task 6.
  **T6a DONE + reviewer APPROVED 2026-07-24 (subagent-driven: pane Opus implementer + pane reviewer, both cmux
  `surface:83`):** commit `8ef4868` (parent `d76ca82`), **verified in-checkout** (2 domain files only —
  `dispatch-pane-agent.sh` +6/−2, `.test.sh` +27/−1; NO store files; the STAGED other-session compliance-judge
  files left untouched via pathspec commit). Controller re-ran suite **61/0** + shellcheck clean + read the diff.
  Fixed C1: moved the 2 marker WRITES to after the worker gate (kept `key=`/`lane=` before it) → capacity N not
  N−1; `max=1`/0-live now opens exactly one pane (reviewer-reproduced). I1 dominant source killed for free
  (gated `die 3` before tagging → no phantom). M1: judge-conf fixture now asserts both `is_judge` strips
  (mutations RED 57/4 + 55/6). New positive test "worker under max opens a pane" RED-against-parent confirmed by
  both agents. Reviewer ran all checks in an isolated worktree; APPROVED, 0 Crit/Imp. **NEW T6a-Minor** (new
  test asserts only `rc 0`, not adapter-invoked — non-blocking, fold into final review). Detail: branch log
  §Task 6a. **NEXT: Task 7** (overflow → `open_tab` round-robin `pane-rr-<key>`; C1 fix is its hard prereq),
  then Task 8 (skill + gate-stub correction + ADR 0009 + Mermaid). Per-task loop: pane implementer → verify
  commit in-checkout (`verifying-subagent-commits`) → pane reviewer → checkpoint. Final-review carry-forward:
  Minor-7 + NEW-A + NEW-B + Nits-8/9 + T4-Minor(fixed)/Nit + T5-Minor/Nits + M2 (PANE_HOME conf split-brain) +
  T6 Nits + **T6a-Minor**; run full pane suites + implementation obs judge before `gh pr create`.
  **Freshness: 2026-07-24 resume paid the branch's recurring restore tax (~75k) before output; user chose
  proceed. T6a impl+review done in panes (light on controller ctx), saved+pushed at this checkpoint; clear
  offered before Task 7.**
  **T7 DONE + reviewer APPROVED 2026-07-24 (subagent-driven: pane implementer + pane reviewer, both cmux
  `surface:83`):** commit `7cb43b0` — worker overflow to `open_tab` with round-robin pane selection
  (`state/pane-rr-<key>`), replacing T6's interim exit-3. Controller-verified in-checkout (exactly 2 `panes/`
  files, `Doc-Exempt` trailer, single worktree, other-session compliance files still staged/untouched) and
  independently re-ran all 7 suites (**287/0**, dispatcher 82/0 from 61/0) + `shellcheck -x` clean + read the
  full `.sh` diff. **The controller caught, BEFORE dispatch, that the plan's Task 7 contradicts the LOCKED
  spec** and briefed two corrections, each TDD'd and independently mutation-killed: **(A) a tab-run is not a
  pane** — the plan leaves the `lane`/`session` writes unconditional, so an overflow would count toward N
  (spec caps worker *panes*) and become a round-robin target (spec selects a *pane*), breaking the
  "freed pane is reclaimed" Gherkin (reproduced literally as `worker max 3 reached (4 live)`) and nesting a
  tab in a tab; fixed with a `kind` marker (missing = `pane`) behind ONE shared predicate `live_worker_panes`
  so the count and the selection can never disagree. **(B) the I1 residual pinned by T6a** — `dead_mark`
  writes `agent-exit` on the no-terminal + adapter-fail paths, and resolving the round-robin target BEFORE
  the marker writes kills the third phantom path by construction. Reviewer: 0 Crit/0 Imp, all 6 checks + 8
  adversarial angles RUN; **bash 3.2.57 is the only bash on PATH** (the empty-array-under-`set -u` trap is
  real but unreachable here) and the Task-4 injection boundary held against 8 hostile `surface` payloads
  through the REAL cmux adapter. **NEW Minor 1 = an OPEN USER DECISION** (spec-level, no clean fix): during a
  real `open_pane` a run is counted live but not yet selectable, so a concurrent fan-out worker can still
  degrade to in-process, which spec line 63-64 + the line-217 Gherkin forbid — not a regression, but decide
  document-as-trade-off (T8) vs spec amendment. Plus Minor 2 (write `kind` first / `lane` last — free
  atomicity, fold into T8) and 3 Nits. Detail: branch log §Task 7. **NEXT: Task 8** (skill + gate-stub
  correction + ADR 0009 + Mermaid), then final branch review + obs judge + PR. Carry-forward now also
  includes **T7: `dispatch-pane-agent.sh` at 387 lines (400 soft limit, no headroom), `.test.sh` at 424, and
  `mk_run`'s latent `$RANDOM`-in-subshell fixture-collision hazard (already produced one false RED).**
  **MINOR 1 RESOLVED by the user 2026-07-24 → document as an accepted trade-off** (spec stays locked, no
  compliance re-run, no code change; rejected a transient N+1 pane and a spec amendment). **T8 DONE
  2026-07-24 (pane implementer; review folded into the FINAL branch review — 134 lines of docs, all read
  by the controller):** commit `d801573`, verified in-checkout (exactly 3 doc files, sanity suites still
  28/0 + 82/0). `rules/gates.md:21` corrected IN PLACE — the controller caught pre-dispatch that the
  PLAN's own replacement prose silently drops "fails open, with a per-session cooldown after an adapter
  failure", still true and load-bearing, so the brief required keeping it. `SKILL.md` gained the
  three-lane policy section + the accepted trade-off in reader's terms, and the implementer correctly
  also fixed that file's own stale "plan implementers are your judgment call" bullet rather than ship a
  self-contradictory file. **ADR 0009** records the include→exclude reshaping, the two user review-gate
  choices that decided three lanes (`inline` must not silence the judges; judge panes uncounted), and the
  `open_tab` allowlist as THE security boundary for the overflow path. Mermaid verified with the repo's
  `validate-diagrams.sh` (PASS); the implementer **refused to claim a browser render** it could not do
  (no `mmdc`; rendering meant an unpinned dep add) and its hand-audit caught a real defect the linter
  passes — labels containing `--` are ambiguous with edge syntax unless quoted. **ALL 8 TASKS DONE.
  NEXT: pre-PR cleanup pass** (NEW-B unquoted `for key in $keys` at guard:104 first — a real
  word-splitting bug; then NEW-A, Minor 2's marker reorder, `mk_run`, the skill-description call, and the
  remaining T3–T6a minors/nits) → full pane suites → implementation obs judge → PR.
  **CLEANUP PASS DONE 2026-07-24 (pane implementer; all 16 carry-forwards cleared):** commits `4d9e713`
  (fix — guard key handling + marker ordering), `f6d83ac` (test — the four escaping-mutant gaps),
  `3c2ad2c` (docs — the three judgment calls). Controller-verified in-checkout + independently re-ran all
  seven suites: **302 passed, 0 failed** (287 baseline), shellcheck clean on six shell files, guard diff
  read in full. NEW-B reproduced literally (a `"*"` session id + a decoy file made the guard exit 0 off a
  FOREIGN policy file) and fixed with `set --`. **Minor-7's anchors were stale — the brief said verify,
  not trust, and that caught it**; its RED (`d/../../outside-policy` resolving above `STATE_DIR`) has NO
  glob char, proving the key-validation and the quoting fixes are independent. **M2 came back WIDER than
  filed and correctly so:** the guard also read `STATE_DIR` from a hardcoded `$HOME`, so under `PANE_HOME`
  it would never see the policy `set-policy` had just written — an unbreakable ask loop, worse than the
  conf split; all four defaults now match the dispatcher. Nit-9's refactor was proven safe by
  byte-comparing both stderr messages against the pre-change guard. Group 3's tightening is the sharpest
  evidence in the branch: the three adapter mutants ALL escaped the old suite (43/0) and are caught by the
  new one (42/3). **Two things deliberately NOT fixed:** `CLAUDE.md`'s skills-catalog line still says
  "(judge, plan implementer)" (pre-three-lane, the other trigger surface — user's global file, out of
  scope), and **`panes/dispatch-pane-agent.sh` is now 410 lines, over the 400 soft limit** — split the
  run-dir/marker helpers out as the FIRST move of the next dispatcher change, not at the tail of this
  branch. **NEXT: implementation obs judge (must match final HEAD), then PR `--draft` → `gh pr ready`.**
  **OBS JUDGE RUN 2026-07-24 → `risk=medium confidence=high`** (verdict
  `coding-memory/observability-judge/2026-07-24-feat-pane-split-policy.md`, `head_sha b38aa24`; judge
  took its OWN pane `surface:107` while workers sat on `surface:83` — the judge lane bypassing the
  policy, observed working). **It found what eight task-reviewers missed:** a worker run is marked
  finished only on NORMAL completion (no exit trap; `wait` skips the marker on timeout), so a
  hand-closed pane stays "live" WITH its surface ref → the next overflow tabs into a dead surface →
  `open_tab` fails → the dispatcher called it an ADAPTER failure → session cooldown → everything
  in-process for the rest of the session, blaming cmux. It also rejected the controller's framing of the
  observability question: exit 3 covering three causes is NOT the problem (nothing branches on `$?`); the
  real gap was that the decisive computation ("counted 3 live, max 3, tabbed into surface:X") was
  recorded NOWHERE. **User chose fix-now → commit `8c2b07f`** (suites **308/0**, +6; controller-verified):
  `open_tab` failure reclassified to exit 3 + no cooldown + dead-mark the stale target so the next
  selection picks a different pane (`open_pane` failure keeps cooldown/exit 4, now explicitly asserted);
  a one-line `ROUTE: lane=… live=… max=… kind=… target=…` decision record to BOTH stderr and
  `<run-dir>/route`, written before the adapter call so it survives a failed open; `CLAUDE.md`'s catalog
  line corrected to the three lanes. Two Task-7 tests REPLACED not repaired — they pinned T7's stated
  intent, and that intent is what the judge found wrong. **Still open (next branch):** the ROOT CAUSE —
  nothing writes `agent-exit` when a pane dies abnormally (needs an exit trap in `run-pane-agent.sh` or a
  liveness probe); T7's NIT 1 lost its mitigation (the rr index still advances on a failed `open_tab`,
  previously "unreachable" only because the first failure ended overflow for the session); **`doc-guard.sh:149`
  classifies `CLAUDE.md` as SOURCE not documentation** — decide whether it belongs in the hook's doc set;
  dispatcher now **450 lines**.
  **OBS JUDGE RUN 2 2026-07-24 → `risk=medium confidence=high`** (verdict appended to
  `coding-memory/observability-judge/2026-07-24-feat-pane-split-policy.md`, `head_sha 2418e5b`;
  commit `2bd2935`). **It falsified RUN 1's own fix:** the new comment's convergence argument holds
  only if `open_pane` ALSO fails. Against an adapter that can pane but cannot tab — exactly the case
  the spec names — every overflow retires a HEALTHY pane, the live count drops back under N, and the
  next worker opens a NEW pane: **+1 real pane per two overflowing dispatches, unbounded and silent,
  cooldown never written, `max=N` quietly exceeded.** It also caught that the reclassification was
  disclosed as task-level when it is spec-level (SKILL.md lines 55-58 still described the old
  cooldown-only degrade path, ADR 0009 unamended, `<run-dir>/route` documented nowhere).
  **User chose fix-now → commit `9073b2b`** (suites **316/0**, +8; `shellcheck -x` clean;
  controller-verified in-checkout): a **consecutive**-`open_tab`-failure streak with
  `TAB_FAIL_LIMIT=3` — a single stale target still self-heals (exit 3, no cooldown), but at the
  limit the ADAPTER, not the target, is judged tab-incapable and it becomes a full adapter failure
  (cooldown + exit 4), which bounds the growth loop. **Only a SUCCESSFUL `open_tab` resets the
  streak** — an `open_pane` success is not evidence of tab capability, and one lands between every
  pair of failures in the growth loop, so counting it would make the bound unreachable. Judge items
  2-4 (SKILL.md degrade paths, ADR 0009 consequence, `<run-dir>/route`) shipped in the same commit.
  **No spec amendment needed — the streak restores the spec's cooldown outcome for a genuinely
  tab-incapable adapter, so the spec stays LOCKED at blob `cdc777a`** (compliance verdicts stay
  valid, no compliance re-run).
  **ORDERING CONSTRAINT (learned here, applies to every future PR):** `judge-guard.sh` requires
  strict `head_sha` EQUALITY with current HEAD, so the verdict commit CANNOT precede the PR —
  sequence is checkpoint-commit → judge at that HEAD → `gh pr create --draft` with the verdict still
  uncommitted in the working tree → THEN commit + push the verdict onto the open PR (pushing after
  creation adds to the PR, so nothing strands).
  **OBS JUDGE RUN 3 DONE 2026-07-24 @ `2454d1d` → `risk=medium confidence=high`** (verdict
  `coding-memory/observability-judge/2026-07-24-feat-pane-split-policy-round3.md`, commit `6c717d0`;
  judge pane `surface:109`, `ROUTE: lane=judge` — the judge lane bypassing the policy, observed
  working a third time). Controller independently confirmed **316/0** and `shellcheck -x` clean at
  that HEAD before dispatching. **RUN 3 broke TWO CLAIMS THIS BRANCH HAD WRITTEN INTO ITS OWN
  DURABLE RECORD** (ADR 0009 + branch log), each with a ~10-line repro:
  **(F1) the pane-growth bound belongs to the GUARD, not the streak** — `dispatch-pane-agent.sh`
  never reads its own cooldown flag, only `pane-dispatch-guard.sh` does; at `max=2`, 10 DIRECT
  dispatches opened **6 real panes, two of them after the cooldown was written**. Normal operation is
  bounded because the guard is the gatekeeper; a direct dispatch is not.
  **(F2) "3 tolerates a cmux restart" is FALSE at N≥3** — a restart leaves exactly N ghosts, so with
  N≥3 the limit trips and a HEALTHY adapter is declared tab-incapable, silently discarding
  `panes max=N` for the session with a message blaming cmux (RUN 1's finding, back in bounded form).
  **(F3, the sharpest) RUN 2's "cosmetic" rr-index nit is the CAUSE of F2** — advancing the index on a
  failed tab marches the selector through every ghost in turn, skipping exactly the healthy panes
  whose success would reset the streak. Judge pinned the index as a counterfactual: **the scenario
  then self-heals completely, zero cooldowns.** The nit was graded cosmetic BEFORE the streak existed
  and was never re-graded after the change that altered its consequence — **the reusable lesson: a
  nit's grade expires when the code around it changes.**
  Also: the 8 new assertions test the MECHANISM (streak fires at 3), never the PROPERTY RUN 2 raised
  (pane count stays under `max`) — **nothing anywhere counts panes against `max`**, which is why F1
  sailed through 316 green tests. All three share the one deferred root cause (no EXIT trap → no
  `agent-exit` on abnormal pane death), and RUN 2 priced that deferral too cheaply: "self-healing" is
  false at N≥3. Judge credited the mutation discipline (RED 101/2 with only the discriminating
  assertions failing; 3 mutants each killing two assertions).
  **PR #28 OPENED as a DRAFT 2026-07-25 — https://github.com/suyatdev/.claude/pull/28** (base `main`,
  40 commits). Sequence used, and the reason for it: the fresh RUN 3 verdict matched HEAD exactly, so
  `gh pr create` ran FIRST while it was valid, and the verdict was committed onto the already-open PR
  afterwards (`6c717d0`) — the PR #26 anti-stranding flow. F1+F2+F3 are declared in the PR
  description as KNOWN-NOT-FIXED, which was the judge's explicit ship condition.
  **OWED BEFORE `gh pr ready` (user chose "draft PR now, then fix on it", 2026-07-25):** (1) correct
  the two overstated sentences in ADR 0009 + the branch log — a decision record asserting a safety
  guarantee that does not exist is the worst of the three findings; (2) the ONE-LINE rr-index fix
  (do not advance on a failed `open_tab`) which dissolves F2/F3 per the judge's own counterfactual;
  (3) a PROPERTY test that counts panes against `max`; (4) **obs judge RUN 4** at the new HEAD
  (judge-guard does not gate `gh pr ready`, but the user's chosen sequence does); then `gh pr ready`.
  Root cause (EXIT trap in `run-pane-agent.sh`) stays deferred to the follow-up branch.
  **Two corrections to this file's own state, found 2026-07-25:** **PR #27 is MERGED** (2026-07-22
  23:39Z, `0a1f80e`), not open as recorded — reachability re-verified, **no 4th stranding**, but its
  remote branch still exists so the prune and the verdict backfill are still owed. And the
  `preparing-pull-requests` rule "feature PRs update the README Roadmap" **could not be satisfied:
  README.md still has no Roadmap section at all** (the known open item 0c(d)) — flagged, not silently
  skipped; standardizing it remains its own task.
  **Process slip worth keeping: a bare `git commit -m` swept the 4 OTHER-SESSION compliance-judge
  files that sit permanently STAGED in this shared checkout into a checkpoint commit.** Caught
  immediately, undone with `reset --soft` (which restores the index exactly) + a pathspec commit +
  `push --force-with-lease`. **The durable gotcha "commit by pathspec ONLY" means the pathspec must
  be on `git commit` itself — `git add <file>` does not protect you, because `commit` without a
  pathspec commits the WHOLE index.**
  **RUN 3 REMEDIATION 2026-07-27 (Opus 5 1M; pane implementer `surface:53`, policy `panes max=2`):
  commits `cbc3c4e` (test) + `5cee1e8` (docs). Controller-verified in-checkout, pathspec-scoped
  (2 files each), the 6 other-session compliance-judge files byte-identical to session start;
  suites independently re-run **326/0** (from 316), `shellcheck -x` rc=0, and the dispatcher diff
  proven **comments-only** (no behavior change).
  **THE IMPLEMENTER REFUSED DELIVERABLE 1 (the rr-index fix) ON EVIDENCE, AND IS RIGHT — RUN 3's
  F2/F3 ARE BACKWARDS.** `new_run_dir` names every run `<epoch>-<pid>-<random>` and
  `live_worker_panes` walks `$RUNS_DIR/*/` in glob order, so glob order IS creation order and a
  stale pane **always sorts BEFORE** every pane opened after it. RUN 3's fixtures sorted the ghosts
  LAST, which production cannot produce. Controller confirmed both premises independently (empirical
  glob-order check + analytic derivation) BEFORE reading the implementer's table, same result.
  Mechanism: retiring a ghost drops the live count under `max`, so the next dispatch opens a REAL
  pane that sorts last; an ADVANCING cursor marches into it and its successful tab resets the streak,
  while a PINNED cursor sits on the oldest ghost and trips the limit. Evidence table (restart 5 min
  ago, 3 ghosts, healthy adapter, `max=3`): ghosts-last → HEAD cools down @ d5 (RUN 3's trace), fix
  does not; ghosts-**first** (the only ordering production makes) → **HEAD self-heals, no cooldown in
  12; the proposed fix cools down @ d5.** The fix MOVES F2 into the real ordering rather than removing
  it. **The rr advance is load-bearing, not cosmetic** — and was one "cosmetic cleanup" away from
  removal. Now pinned by test with a PAST-epoch fixture, because the naming is the precondition.
  **F1 is REAL and fully corrected** (reproduced byte-for-byte: 6 panes at `max=2`, 2 after the
  cooldown). ADR 0009 now says plainly that the streak does NOT restore `max=N`, that the bound is
  the GUARD's and therefore **emergent, not mechanical**, that a direct `dispatch` is unbounded, and
  adds the judge's asked-for sentence that the late cooldown is a **declared timing deviation**, not
  compliance. Spec untouched, still blob `cdc777a`. **+10 assertions, all mutation-verified**: overflow
  gate `-ge`→`-gt` → 96/17; "dispatcher honors its own cooldown" → 108/5; the brief's Deliverable 1 →
  111/2 killing exactly the two restart assertions. Guard suite already covered "flag → allow
  in-process", so only the uncovered dispatcher half was pinned.
  **REUSABLE LESSON: a judge finding can be an artifact of its own fixtures.** RUN 3 was right about
  F1 and wrong about F2/F3 for the same reason this branch keeps getting burned — a fixture that
  cannot occur in production. Verify a judge's repro against the real naming/ordering before acting.
  **Process slip (2nd occurrence, new variant): `git commit --amend --no-edit` to add a trailer has
  NO pathspec and swallowed two other-session staged files.** Implementer caught it on `--stat`,
  `reset --soft` + re-amended with a pathspec; staged state verifiably restored (controller
  re-confirmed). **The rule must read: the pathspec goes on `git commit` AND on `git commit --amend`.**
  **OPEN DECISION for the user:** F2/F3 are answered by EVIDENCE, not a code change, so obs judge
  RUN 4 must adjudicate the rebuttal (evidence table is in the branch log). The order-dependence is
  real but emergent from a naming convention two functions away; the robust fix — retry the next
  candidate WITHIN one dispatch, or probe the newest pane while the streak is warm — removes it
  entirely but is a design change, deliberately not taken unilaterally. Root cause (no EXIT trap →
  no `agent-exit` on abnormal pane death) still dissolves the whole class and stays deferred.
  **`dispatch-pane-agent.sh` is now 517 lines** (+25, all comment) against a 400 soft limit — the
  split is owed as the FIRST move of the next dispatcher change.
  **OBS JUDGE RUN 4 IS IN — DONE, verdict committed `2078408`.** It adjudicated its own RUN 3
  findings and **WITHDREW F2/F3 itself**: its RUN 3 fixtures were letter-named and sorted after real
  panes, an inversion production naming cannot produce. It then swept 81 configurations per variant
  (`max=3`/`max=4` × every starting rr index): **HEAD 2 spurious cooldowns, RUN 3's own proposed fix
  8** — the index advance is load-bearing, confirmed. F1 confirmed fixed. risk=medium, confidence=high.
  **F4 NEW + ACCEPTED:** the tolerance claim held only at `max=3`; at **N≥4 a healthy cmux restart
  can still trip the streak** (1/4 starting indices at max=4, 2/5 at max=5, 4/6 at max=6) — user's
  `panes max=N` silently discarded, exit 4 blaming a blameless adapter. Hand-traced independently
  before accepting (overflow only fires while live ≥ max, so each failed tab retires a ghost and the
  next dispatch opens a real pane — that alternation saves max=3 and is one beat too slow at max=4).
  **User decision 2026-07-27: qualify the record, no behavior change** → `6d781c9` (comment-only,
  113/0, shellcheck clean) + branch-log RUN 4 section, which also corrected a second overclaim
  ("ghosts sorting last cannot happen in production" is false — close the two newest panes by hand).
  **>>> RESUME HERE (session cleared 2026-07-27 at the 76k handoff, all judge work banked) <<<**
  **NEXT, IN ORDER:** (1) **resolve PR #28's conflict** — `mergeable: CONFLICTING`, but it is ONLY
  `CODING_MEMORY.md` + `coding-memory/observability-judge/verdicts.jsonl` (verified by
  `git merge-tree` against a freshly fetched `origin/main`); both are append-heavy files that other
  sessions landed on main, NOT a code conflict — take both sides, do not drop other sessions' rows;
  (2) `gh pr ready` on PR #28 — `judge-guard.sh` gates `gh pr create` only, NOT `gh pr ready`, so no
  head_sha equality dance is needed, and RUN 4's verdict is banked at `e6e2e3e` regardless of the two
  later docs commits. **Do NOT re-run the judge for the comment-only commits.**
  **KNOWN OPEN, none blocking the PR, all waiting on the same root cause:** the N≥4 restart
  false-positive (F4); exit 4's misleading blame (only wrong when F4 fires); the **525-line**
  dispatcher vs a 400 soft limit — the split is owed as the FIRST move of the next dispatcher change.
  **Still deferred by decision, do not start unilaterally:** the robust ordering fix (retry the next
  candidate within one dispatch) and the root cause (EXIT trap in `run-pane-agent.sh` → `agent-exit`
  on abnormal pane death), which dissolves the whole class. Session pane policy `panes max=2` is
  per-session state — a fresh session will be ASKED again at its first worker dispatch.
  **Working-tree caution (still true):** the uncommitted `coding-memory/compliance-judge/` files are
  OTHER concurrent sessions' verdicts (repos `phase-guard-hook`, `mtg-wizard`, `vibe-scape`,
  `Snatch-Bracket`), two already `git add`ed by them. Leave them; pathspec-scope every commit.
- session_origin: desktop · session_started_at: 2026-07-22 (Opus 4.8) · last_active_branch:
  **`feat/pane-split-policy`** — **NEW FEATURE SPEC'D + committed, then session cleared.**
  Session pane-split policy: at the first pane-eligible dispatch the model asks once —
  `inline` (all in-process this session) or `panes max=N` (N concurrent panes; spawns beyond N open
  as **tabs inside existing panes**, round-robin, never inline/blocked). Read-only `Explore`/`Plan`
  never governed (exclude-list, flipping today's `redirect-agents.conf` include-list). cmux primary
  (user's terminal); others degrade. Spec:
  `docs/superpowers/specs/2026-07-22-pane-split-policy-design.md`; provenance + Q&A + gate answers:
  `coding-memory/brainstorms/2026-07-22-pane-split-policy.md`. Prior-session Snatch-Bracket verdicts
  committed to main (`7854ae3`) before branching. **GATES ANSWERED (do not re-ask this design):
  Hard Model Gate = Opus 4.8 for the spec, implementation tier deferred; freshness = write-then-clear.**
  **NEXT (fresh session, IN ORDER): (1) compliance judge on the spec — BLOCKING, deliberately deferred
  to preserve checkpoint budget, run via `running-the-compliance-judge` alongside the obs architecting
  read; (2) user review gate on the spec; (3) re-ask model gate before implementation;
  (4) `superpowers:writing-plans`. cmux tab primitive must be live-probed FIRST in the plan.**
  **JUDGES RAN TWICE (2026-07-22, Opus 4.8, all pane-dispatched to cmux).** Round A: obs low/high;
  compliance R1 FAIL (arrow-prose scenarios) → Gherkin reformat `9bd9966` → compliance R2 PASS.
  **User review gate → 2 design decisions:** (1) `inline` must NOT silence the two judges; (2) `max=N`
  caps the worker fan-out only, judge panes uncounted. → Spec reshaped into a **THREE-lane model**
  (read-only in-process / judges always-paned OUTSIDE policy / worker fan-out policy-governed),
  commit `2815bba` (blob `cdc777a`). Round B (re-entry on the revised spec): **compliance PASS, high
  conf; obs low/high — obs judged the revision MORE correct** (inline would have "cut power to the
  judges' PR-gate enforcement"). Verdicts in `coding-memory/{compliance,observability}-judge/`.
  **USER REVIEW GATE CLEARED 2026-07-22 — spec APPROVED as-is, LOCKED at blob `cdc777a`
  (commit `2815bba`); do NOT re-edit or the verdicts invalidate.** NEXT (fresh session): re-ask the
  Hard Model Gate, then `superpowers:writing-plans` (probe the cmux tab primitive FIRST). User
  declined the optional three-lane diagram for now (would re-run the loop). Plan-time carry-forward
  (do NOT lose, all non-spec): **ADR for the three-lane governance model** (ADR 0007 precedent);
  CORRECT (not append) the stale `rules/gates.md` "plan implementers are skill-routed" line (the
  "judges are hook-enforced" line stays true); `open_tab` verb inherits the orchestration spec's
  no-interpolation + title-allowlist boundary; validate `N` as a bounded positive int; **prove the
  worker-pane count AND the worker/judge lane-tag early on REAL run-dir fixtures** (the "judge not
  counted" test rides on both); live cmux tab probe as a hard gate. Optional: a small three-lane
  decision diagram would aid review (costs a re-judge if added now).**
- **PR #29 MERGED 2026-07-25** (`122b8a5`); branch pruned local+remote; ancestor-check verified.
  Phase-frontmatter permission system (ADR `docs/decisions/0010-phase-frontmatter-as-permission-source.md`)
  now on `main` — every feature-scale change gets a `docs/features/<name>.md` with `phase` in
  frontmatter, checked on restore. **Mechanism is still undogfooded** — no such file exists yet
  anywhere; the next feature-scale branch should be its first real user. Detail:
  `.claude/session-state.md`.
- session_origin: desktop · session_started_at: 2026-07-22 (Sonnet 5) · last_active_branch: main —
  **Q&A only, no code/architecture changes.** Answered how to manually smoke-test the pane
  dispatcher: single `pane-echo` dispatch, and a 5-pane test (4 `--role implementer` filling the
  quadrant + 1 default `aux`) was being scoped when the 75k handoff fired. **Pre-existing
  uncommitted `coding-memory/compliance-judge/verdicts.jsonl` (2-line diff) + new
  `2026-07-22-0007-tea-room.md` predate this session and are unrelated to it — committed to main
  as `7854ae3` by the later Opus 4.8 session above.**
- session_origin: desktop · session_started_at: 2026-07-22 (Opus 4.8) · last_active_branch: feature/cmux-version-gate
- **PR #25 MERGED 2026-07-22 (`3491464`); branch pruned local + remote; verdict outcomes
  backfilled.** pane-layout-v2 shipped: 9 tasks, probe P8, ADR 0008, implementation judge PASSED
  over two rounds. Detail: `coding-memory/pr-tracking.md` §PR #25, resume #9 below.
- **CURRENT: `feature/cmux-version-gate`** — PR #25's agreed first post-merge follow-up, and the
  round-2 judge's top item. `check_cmux_version` in the adapter pins the verified cmux release and
  warns + leaves a durable receipt when the live binary differs, because the aux-column anchor is
  a heuristic that no test can catch drifting (every adapter test drives a FAKE binary).
  **Its own round-1 judge found a real bug by probing nine version strings: a
  `[0-9.]`-only filter silently swallowed `0.65.0-rc1`/`0.64.20-beta`** — the pre-release builds
  most likely to have moved behaviour — so the parser now tests version-SHAPED, not version-CLEAN.
  **PR #26 OPEN** (https://github.com/suyatdev/.claude/pull/26) — 3 judge rounds, all risk=low,
  none blocking; it found two real defects (the pre-release deafness above, and a `2>/dev/null`
  that does not suppress a failing *redirection* — a trap `run-pane-agent.sh:81` already
  documented). Suite 170 → 197. Log: `coding-memory/branches/cmux-version-gate.md`,
  `coding-memory/pr-tracking.md` §PR #26.
- current work: **pane-orchestration FULLY CLOSED OUT — PR #23 MERGED (8f40e05) and docs-only
  PR #24 MERGED 2026-07-21 13:05Z (23dd2e3); both branches pruned local+remote.** PR #24
  merged WITHOUT the late-pushed brainstorm checkpoint 9e16d7f (PR #21 stranding failure
  mode, 2nd occurrence) — recovered by cherry-pick onto `main` as 2d8a416 (memory-only →
  git-guard brainstorm exception; user-approved), parity verified, then pruned. Detail:
  `coding-memory/pr-tracking.md` §PR #24. Obs judge (impl @ 5c846b2) outcome=clean.
  **Remaining: post-merge watch items in Next Steps 0c.** Per-task history:
  `.superpowers/sdd/progress.md` (RUN section), `coding-memory/branches/pane-orchestration.md`.
- **CURRENT: pane-layout-v2 — USER REVIEW GATE CLEARED 2026-07-21 (resume #4, Fable 5).**
  Spec: `docs/superpowers/specs/2026-07-21-pane-layout-v2-design.md` @ blob aeb0074
  (commit bb4050b on `feature/pane-layout-v2`, pushed, no PR). Round-1 judges clean,
  pane-dispatched: compliance **pass**/high 0 violations; obs advisory **low**/high, 1
  concern = success_masking ("run folder missing = finished" infers success from absence —
  out-of-band `panes/state/runs/` cleanup could recycle a busy pane). Judge notes for
  implementation: pin `respawn-pane --command` quoting during the live probe before REUSE
  is coded; log live probes first thing; fallback tests assert the exact legacy command
  sequence. **User sign-off EXPLICIT on (a) the aux-reuse extension and (b) all 4 flagged
  assumptions — ZERO spec edits, so both verdicts remain fresh.** Spec status line
  intentionally left saying "pending" (editing the file would invalidate the blob-sha-keyed
  verdicts); the authoritative approval record is
  `coding-memory/brainstorms/2026-07-21-pane-layout-v2.md` §"User review gate". **PLAN
  WRITTEN same session (user said "continue for now" on Fable 5 = per-task planning gate
  answer; Hard Model Gate untouched):
  `docs/superpowers/plans/2026-07-21-pane-layout-v2.md` — 8 tasks, TDD, live probe FIRST
  (P1–P7 resolve the 4 assumptions + respawn quoting), unverified tree schema quarantined
  in `layout_normalize_tree` validated against a live-captured fixture; self-review caught
  and fixed a T4/T5 fixture state collision. GATES ANSWERED (do not re-ask): Opus 4.8
  in a FRESH session; subagent-driven execution, pane-routed implementers.** Full design
  history: the brainstorm file; earlier session blocks: git history of this file
  (98faa38, c252135).
- **Resume #9 (2026-07-22, Opus 4.8): probe P8 + implementation judge PASSED. PR is the only
  step left.** HEAD `e12dc06`. **P8 finally supplied the live coverage Tasks 8/9 could not**
  (`coding-memory/branches/pane-layout-v2.md` §P8, script `<scratchpad>/live-quadrant-probe.sh`):
  four sequential `--role implementer` dispatches, each plan *predicted* from the live tree
  before firing, all four matching exactly — **impl slots 3–4 are no longer fake-verified**,
  because the agents were still booting so no `agent-exit` existed and reuse could not preempt
  growth. Two corrections: **27** — `index` is traversal order over a FLAT panes array, NOT
  left-to-right (Task 8's experiment only made horizontal splits; with a real quadrant impl.2
  in the left column sorts *after* impl.3 in the right one), so `layout_rightmost_surface` is
  a heuristic and its comment now says so — logic unchanged, nothing better is exposed; **28** —
  `new-pane` *does* follow `focus-pane`, so it is anchorable after all, but that neither beats
  `new-split --surface` nor fixes height. **Aux height is ordering-dependent and accepted as a
  limitation → ADR 0008**: full-height when the column predates the quadrant (the common path —
  handoff + judges open first), half-height bottom-right when created after, unfixable because
  the tree is flat, both split verbs are pane-relative, and `--placement dock` is disabled.
  Implementation judge **PASS, risk=low confidence=high**, no dimension failed, concerns
  `success_masking` + `audit_trail`; it independently re-ran three recorded falsifications and
  re-checked the unfixability argument. **Its sharpest catch, now the branch's main latent risk:
  a future cmux changing pane-walk order lands the aux column wrong while all 170 tests still
  pass** — every test drives a fake binary, so mitigation is procedural (re-run
  `panes/cmux-layout-probe.sh` after any cmux upgrade). Live workspace restored and **diffed**
  against its captured baseline. Judge follow-up not blocking: widen the one-line stderr notice
  when the layout path degrades to legacy.
- **Resume #8 (2026-07-21, Opus 4.8): Tasks 7–9 DONE + pushed (45fee28, 1d1e3c7, 17a0f44).**
  Plan execution + verify-after-rename; Task 8's first-ever real-binary smoke check, which
  **falsified spec assumption 4** (aux landed 2nd from left — `new-pane` splits off the current
  pane); Task 9 added mid-flight to anchor aux on the rightmost pane. Also proved live: the P4
  send-not-respawn reuse deviation (same surface re-used), `--workspace` scoping, title
  stamping, the T3 handoff-wrapper rename. `--role` documented in the skill.
- **Resume #7 (2026-07-21, Opus 4.8): Task 6 DONE + pushed (aa2cc42).** Pane-dispatched
  implementer (`--role implementer`, surface:78); commit verified in-checkout, all five
  suites independently re-run, one falsification independently re-run by me. Corrections
  10–15 — detail in Next Steps 0-ACTIVE and `coding-memory/branches/pane-layout-v2.md`.
  Session note: ~82k of this session's budget went to context RESTORE before any output,
  which is the recurring cost of task-by-task execution on this branch.
- **Resume #6 (2026-07-21): Task 1 live probe EXECUTED on Opus 4.8 (ffe22d2).** Probe is
  re-runnable: `panes/cmux-layout-probe.sh`; fixture `panes/adapters/fixtures/tree-live.json`.
  Three plan corrections + one user-approved spec deviation — see Next Steps 0-ACTIVE and
  `coding-memory/branches/pane-layout-v2.md`.
- **Resume #5 (2026-07-21, Fable 5): NO execution — stopped at the model gate.** Session
  ran Fable 5 vs the answered Opus 4.8; discovered pane implementers would ALSO run
  Fable 5 (settings.json `"model": "claude-fable-5[1m]"`, dispatcher passes no model
  flag). User chose stop + relaunch on Opus 4.8. **Next session MUST be started with
  `claude --model claude-opus-4-8` (or `/model` immediately) — the handoff pane and a
  plain `claude` both inherit the Fable 5 default (handoff-wrapper.sh execs claude with
  no --model). Open: whether to pin pane implementers to Opus too (settings/dispatcher
  change, user's call) or accept Fable 5 implementers.** Then execute the plan from
  Task 1 (live probe); implementation-stage obs judge before PR.
- prior session (2026-07-20): claude-code-handoff cherry-pick SHIPPED — PRs #21+#22 MERGED;
  audit-trail recovery + 8-branch orphan sweep. Detail: ADR 0006,
  `coding-memory/branches/add-claude-code-handoff.md`, Next Steps 0.
  settings.json dual-version staging policy unchanged (Orca hooks + fable-model line stay uncommitted).
- **SUPERSEDED (was parked): judge terminal-enforcement.** Branch
  `feature/judge-terminal-enforcement` retired, NOT deleted (~3,400 lines unmerged judged
  spec work; deletion = explicit user cleanup). Reference text for any future `spec-guard`
  resurrection. ADR 0007;
  `coding-memory/brainstorms/2026-07-20-judge-terminal-enforcement.md`.
- **Session-budget preference (2026-07-20): keep each session below ~100k tokens; checkpoint memory
  after each task so the user can /clear before the next design task.**
- **CORRECTED 2026-07-21 (was stale): the Orca hooks and the fable-model line are now IN
  committed `settings.json`** (HEAD == live, last touched by a3aedc8 "Add merge guard") —
  the old "stay uncommitted / dual-version staging" policy no longer reflects reality.
  Whether committing them was intended is the user's call (flagged 2026-07-21). The Orca
  channel caveat still stands: `claude-hook.sh` sources `$ORCA_AGENT_HOOK_ENDPOINT` before
  its token check and that stdout becomes hook stdout. Untracked `chrome/`, `telemetry/`,
  `stats-cache.json` stay untracked (machine-local; gitignore an open question).
- 2026-07-19 session notes — statusline-edit authorship resolved as that session's own work,
  concurrent-session evidence, model-gate history (Sonnet 5 → Opus 4.8), `chore(settings):`
  precedent for model/theme changes: `coding-memory/branches/statusline-token-bar.md` and
  `coding-memory/session-log.md`.

## Repositories

### suyatdev/.claude
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR #4 (feature/vibe-coding-standards-integration) — MERGED 2026-07-12.
- PR #3 (feature/standards-extractor-agent) — MERGED.
- PR #5 (feature/modular-coding-memory) — MERGED 2026-07-14. `main` fast-forwarded to include it.
- PR #6, #7, #8 (feature/new-project-memory-scaffold) — all MERGED. Branch deleted 2026-07-15
  (fully superseded — see `coding-memory/branches/new-project-memory-scaffold.md`).
- PR #9 (feature/rules-to-skills-restructure) — MERGED 2026-07-15 (fast-forward, user's choice to
  merge locally rather than wait for GitHub review). Branch deleted. The rules-to-skills
  restructure: 7 always-loaded rule files → core-conduct.md + gates.md + 5 new skills + git-guard
  hook. Always-on content: 4,030 → 1,151 words (~71% cut).
- feature/documentation-enforcement (2026-07-16) — documentation-enforcement backstop:
  `hooks/doc-guard.sh` (block substantial undocumented source commits + surface uncommitted
  work before compaction / at next session start), broadened `managing-session-memory` criteria
  (business-logic + direction-pivoting changes → mandatory + ADR), ADR standard/template in
  `setting-up-a-new-project`, gates stub. Verified (15-case harness). **PR #10 MERGED (2026-07-16).**
  Detail: `coding-memory/branches/documentation-enforcement.md`.
- PR #11 (chore/ports-registry-snatch-8001) — MERGED 2026-07-16. Reconciled the orphaned PORTS.md
  edit (snatch-bracket backend on port 8001) as its own commit, per user's commit-only-my-work call.
- PR #12 (feature/diagramming-skill) — MERGED 2026-07-16. New `diagramming-technical-docs` skill
  (Mermaid docs standard: SKILL.md + references/assets/scripts validator; Mermaid-not-PlantUML).
  Detail: `coding-memory/branches/diagramming-skill.md`.
- feature/observability-judge (2026-07-16) — the observability judge (16 commits, 17/17 tests):
  scoring subagent (10 dims → JSONL+markdown verdict + layman summary), `hooks/judge-guard.sh`
  blocking `gh pr create` without a fresh strict-freshness verdict, skill + gate stub + catalog,
  ADR 0001, spec, verdict store. Command detection took 2 review-driven security fixes
  (substring→anchored→python shlex, closing a quoted-env-prefix bypass). **PR #13 MERGED
  2026-07-17** (bootstrap self-gate → JUDGE_EXEMPT).
  Detail: `coding-memory/branches/observability-judge.md`; PR status: `coding-memory/pr-tracking.md`.
- feature/memory-rag-index (2026-07-17→18) — `memsearch`: local SQLite (sqlite-vec + FTS5) RAG over
  transcripts + curated docs, Qwen3 embeddings, hybrid retrieval, silent SessionStart nudge.
  60-test suite green, backfill 228 sources / 2332 chunks / 0 errors / p95 149ms, golden 16/16.
  **PR #14 MERGED 2026-07-18** (7015369). Judge (impl): risk=low conf=high, outcome=clean.
  Detail: `coding-memory/branches/memory-rag-index.md`.
- feature/compliance-judge (2026-07-18) — subagent judging ONE finished spec against live rules
  (writing-specs + core-conduct/security): blocking pass/fail, per-rule citations, JSONL+markdown
  store; skill with parallel dispatch alongside the observability judge, capped auto-revise loop,
  escalation, explicit-only waivers; gates stub + catalog, ADR 0003, golden eval 12/12.
  **PR #16 MERGED 2026-07-18** (4c2abec). Judge (impl @ 85d8982): risk=low conf=high, clean.
  Detail: `coding-memory/branches/compliance-judge.md`.
- feature/writing-project-readmes-skill (2026-07-19) — `writing-project-readmes` skill: house
  README standard from the user-supplied template (check-then-create, real facts only, `[TODO:]`
  greppable placeholders) + Roadmap upkeep as features land + trigger wiring (setting-up-a-new-
  project step 5, preparing-pull-requests bullet, CLAUDE.md catalog). TDD RED/GREEN + 8/8 routing.
  **PR #17 MERGED 2026-07-19** (merge commit d242e69); branch deleted. Judge rounds 1-2
  (3c5a826 low/medium → grep hole fixed → 0d23feb low/high), outcome=clean (backfilled).
  Detail: `coding-memory/branches/writing-project-readmes-skill.md`.
- feature/statusline-command (2026-07-19) — Claude Code status line reproducing the oh-my-zsh
  `robbyrussell` prompt (`➜ user@host dir git:(branch) ✗`) plus dimmed model + token-count
  segments: new `statusline-command.sh`, `statusLine` entry in `settings.json`, README table
  row; model → opus[1m] and theme → dark split into their own `chore(settings)` commit.
  Observability judge ran **5 rounds**, each finding something real in the round before: terminal-escape
  injection via four distinct paths (incl. a **second** unstripped fallback introduced by the fix for the
  third), false "pushed" claims, and an unverified `context_window` schema — all fixed. Test suite
  validated by falsification against all 5 historical versions rather than by passing alone
  (`statusline-command.falsify.py` makes that reproducible). Recurring lesson: **the write-up ran ahead
  of the code in every round**, including a "Cosmetic, no leak" claim about a path that did leak. Scope
  overran badly — 5 of 6 commits judge-driven; taken to the user rather than resolved unilaterally.
  No ADR (presentation-only — misses all three ADR triggers).
  Detail: `coding-memory/branches/statusline-command.md`.
- feature/statusline-token-bar (2026-07-19) — **PR #20 MERGED 2026-07-20 04:01Z.** Follow-on
  to PR #18: model name orange, context bar scaled to a fixed 100k "time to clear" reference (not the
  model's window — against 1M a 143k session rendered nearly-empty-but-red), cumulative Σ counting
  input+output only (cache traffic swamped it ~16x), purple weekly-quota segment. A cost-estimate
  feature was requested, built, then **removed entirely**: subscription plan, `costUSD: 0`, no cost
  field in the payload — any dollar figure would have been invented. Weekly quota is a percentage
  for the same reason: docs confirm `rate_limits` exposes `used_percentage` + `resets_at` only, so
  "tokens left" is uncomputable. Schema check caught a silent bug: `resets_at` is epoch seconds, not
  ISO — the countdown would have never rendered and looked merely absent.
  Judge R1 (b24d422) risk=**high**; all three findings fixed across 4 commits (fc67ab1 tests,
  888449e race repro RED, d7a2861 lock GREEN + ADR 0005, d302479 lock-recovery tests).
  Recurring lesson, now three-for-three on this branch: **writing the check is not the same as the
  check working.** The first lock regression test planted its PID file with a trailing newline —
  a condition the buggy writer cannot produce — so re-introducing the bug passed 44/44. Only the
  mutation revealed it. Every claim on this branch is now falsification-backed.
  Detail: `coding-memory/branches/statusline-token-bar.md`, ADR 0005.
- feature/verifying-subagent-commits (2026-07-18) — new skill: after a dispatched implementer/fix
  subagent reports DONE with a commit SHA, the controller independently confirms via `git log -1`
  in the target checkout that it actually landed there, before trusting the report. Harvested from
  a real trace (a subagent committed to the wrong checkout 3x in one session, despite an explicit
  dispatch-prompt self-check instruction). Not hook-enforced by design. **PR #15 MERGED
  2026-07-18** (merge commit 417e8e7); branch deleted. Judge (impl, head 367da77): risk=low
  conf=high, outcome=clean.
- feature/add-claude-code-handoff (2026-07-20) — vendored Sonovore/claude-code-handoff @
  c6cb717, then cherry-picked per the user's 15-row picks (ADR 0006): handoff SessionStart
  loader + doc-guard PreCompact removed, tracker bug patched locally (verified live),
  `/handoff` = checkpoint UX, committed memory stays authoritative. Judge R1 medium→fixed,
  R2 **low/high** @ e56c2f2. **PR #21 MERGED 2026-07-20 22:02Z (3c58363).** Judge audit trail
  committed to the branch post-merge (77b59ad) and stranded off `main`; recovered via docs-only
  **PR #22 MERGED (284478a)** — cherry-pick 7337186.
  Detail: `coding-memory/branches/add-claude-code-handoff.md`, `coding-memory/pr-tracking.md`.

## Pointers
- PR tracking (all repos, all branches): `coding-memory/pr-tracking.md`
- Session log (chronological summaries): `coding-memory/session-log.md`
- Decisions & conventions: `coding-memory/decisions.md`
- Branch implementation logs: `coding-memory/branches/`
- Brainstorm write-ups: `coding-memory/brainstorms/`

## Exact Next Steps
0-ACTIVE. **pane-layout-v2 — EXECUTING. Task 1 (live probe) DONE + pushed (ffe22d2)
   2026-07-21. Gates answered, do not re-ask: model = Opus 4.8 (user ran `/model`
   this session — satisfied); execution = SUBAGENT-DRIVEN, implementers PANE-routed.
   **Tasks 2 (ba9a91b) + 3 (0711017) DONE + pushed** — both pane-routed, commit-verified
   and independently re-run (Task 3: dispatch 39/0, siblings 24/0 10/0 9/0, shellcheck
   clean, `--role` guard falsified 37/2 → restored 39/0).
   **Task 4 (`cmux-layout.sh`) DONE + pushed (5da1cad)** — layout 12/0, siblings
   39/24/10/9 all 0 failed, `shellcheck -x` clean; all 4 falsifications RED and reverted
   (I independently re-ran the two jq ones: 7/5 and 11/1, restored byte-identical 12/0).
   **Task 5 (decide + title composition) DONE + pushed (8ad7d7a)** — layout 26/0, siblings
   39/24/10/9 all 0 failed, `shellcheck -x` clean; 3 falsifications RED and reverted (I
   re-ran the tab tie-break one myself: 25/1 → restored byte-identical 26/0).
   **Correction 8:** every Task 5 test fixture called `tree "$(pane …)"`, skipping Task 4's
   new `workspace` level — and would have PASSED anyway, because normalize uses recursive
   descent. Silent builder drift, the exact hazard Task 4 existed to kill. All 8 fixtures
   now wrap through `workspace workspace:1`. **Correction 9:** the plan's reuse
   falsification couldn't discriminate with only one finished surface; needs two.
   **Task 6 (cmux.sh v2 frame — tiered degradation, legacy floor, dryrun) DONE (aa2cc42)**
   — new `cmux-exec.test.sh` 24/0, siblings 26/39/10/9 + adapters 24/0 (file untouched),
   `shellcheck -x` clean. 5 falsifications RED and reverted; **I independently re-ran the
   workspace-scoping one** (anchor asserted to match exactly once, non-empty diff, 23/1 RED
   on that exact case, restored byte-identical by sha256 → 24/0). RED run was 5/18 with
   **all five passes vacuous** — enumerated in the branch log.
   **Corrections 10–15** (10: `T_EMPTY` in the imagined shape normalizes to 0 bytes yet
   passes every plan assertion — 3rd builder-drift occurrence, so a `T_SLOT1` fixture whose
   plan is reachable only if the tree really parsed was added; 11: tree fetch must carry
   `--workspace`, bare is window-scoped; 12: `send`/`rename-tab` carry it too, `new-split`
   deliberately does not; 13: dryrun comment contradicted its own load-bearing guard;
   **14: the plan's Step 2 RED run is UNSAFE here** — v1 hardcodes the real cmux path and
   ignores `PANE_CMUX_BIN`, so a literal RED run inside a live cmux workspace fires ~10 real
   `new-split down` calls at the user's window; run RED against a `cp -R` copy in `$TMP`
   instead — **Task 7 needs the same precaution**; 15: the plan's `legacy_open` falsification
   could not discriminate — `|| true` left the suite green because the ref-shape guard exits
   on its own).
   NEXT: **Task 7** (plan execution + verify-after-rename) → Task 8 →
   implementation-stage obs judge (OWED — not yet run; judge-guard blocks PR) → PR.
   **Still gotchas for Task 7:** `grep -c .` on empty input prints 0 but EXITS 1 —
   `layout_decide`'s tab-count loop is safe only because these files are `set -u` and NOT
   `set -e`; introducing `set -e` breaks it. **Nothing in Task 6 touched the real cmux
   binary** — every execution assertion runs against the fake, so the `--workspace`
   placement on `send`/`rename-tab` rests on `--help` + probe P5, **not** a live mutating
   call. That live confirmation is owed at Task 8 alongside Task 3's handoff-wrapper rename.
   **Task 4 = plan corrections 5–7, all verified against the live fixture before dispatch:**
   (a) the normalize selector returns EMPTY (real shape keys each level's own ref as `ref`;
   surfaces carry `pane_ref`+`title`); (b) **the workspace filter was a SILENT TOTAL
   FAILURE** — workspace objects carry `ref` and their `workspace_ref` is `null`, so
   `select(.workspace_ref? == $ws)` matched only the root `active`/`caller` objects and
   returned NOTHING whenever `CMUX_WORKSPACE_ID` was set (the normal case), degrading the
   whole feature to legacy; repaired to filter on the workspace's own `.ref`, kept as
   defence-in-depth with primary scoping SERVER-side via `tree --workspace` (P1);
   (c) the canned `pane()`/`tree()` builders were in the imagined shape and would have kept
   (a)+(b) green while live degraded — now mirror `fixtures/tree-live.json`.
   Implementer also fixed a real footgun: `layout_managed` dropped its last line when stdin
   lacked a trailing newline (Task 5 will feed it via `$(...)`, which strips it).
   Note for later tasks: the plan's `> file 2>/dev/null` idiom does NOT suppress a
   redirect failure (left-to-right); put the stderr redirect FIRST.
   **Task 3 = the plan's 4th correction:** its handoff `rename-tab --surface
   "$CMUX_SURFACE_ID"` (a UUID, and no `--workspace`) would have silently renamed the
   user's FOCUSED tab (P5+P6+P7 combined) — shipped instead with
   `--workspace "$CMUX_WORKSPACE_ID"` and NO `--surface`, resolving via the pane's own env.
   **Unverified live — confirm at Task 8.** The plan's predicted RED set was also wrong
   (the `--role` allowlist case passes vacuously pre-implementation) — exactly the failure
   the mandatory falsification rule exists to catch.
   **The probe changed the plan in three places — full verbatim findings in
   `coding-memory/branches/pane-layout-v2.md` §Live probe; read it before Tasks 4/6/7:**
   (a) the real tree JSON shape differs from the plan's assumption at EVERY level (each
   level keys its own ref as `ref`; surfaces carry `pane_ref`+`title`) — the plan's jq
   matches nothing, so Task 4 must rewrite both the jq AND the canned test builders, or
   unit tests stay green while live silently degrades to legacy; (b) `rename-tab` does
   NOT error on an unresolvable `--surface` — it silently renames the FOCUSED tab, so
   Task 7 needs verify-after-rename, not retry-once; (c) `respawn-pane` destroys the
   surface when its command exits → reuse uses `cmux send` instead (**user-approved
   deviation; spec left unedited — flag it to the implementation-stage judge**).
   Spec assumption 1 (bare tree workspace-scoped) is FALSE but the gate did not trip
   (`tree --workspace` accepts `$CMUX_WORKSPACE_ID`); assumption 4 confirmed visually.
   Also: every mutating cmux call needs an explicit `--workspace` (refs resolve relative
   to it; UUIDs work for `--workspace` but not `--pane`).
   **settings.json's `model` field tracks the ACTIVE session model — it is not a stable
   committed preference. Now `opus[1m]` (user's /model), uncommitted. Re-`grep` fresh
   rather than trusting any earlier diff.**
0. **claude-code-handoff cherry-pick (2026-07-20) — DONE. PR #21 + PR #22 both MERGED.** Picks
   applied per ADR 0006; judge R1 medium→R2 low/high; PR #21 merged 22:02Z. The audit trail
   stranded off `main` (committed post-merge as 77b59ad) was recovered via docs-only PR #22.
   **Branch cleanup DONE:** all 8 merged orphans pruned local + remote (see Orphans below).
   Ongoing duty (unchanged): add handoff state-file gitignore entries per project repo on
   first work there (recorded in `managing-session-memory`).
0b. **Judge terminal-enforcement — SUPERSEDED by pane orchestration (ADR 0007, 2026-07-21).**
   Branch retired, not deleted (user cleanup decision pending). Platform research absorbed
   into the pane-orchestration spec. Resurrect its §3 only if a skipped compliance judge is
   ever observed (spec-guard remedy).
0c. **Pane orchestration — PR #23 MERGED 2026-07-21 (8f40e05); branch pruned.** Verdict
   outcome backfilled `clean`. Open post-merge items, none blocking: (a) judge suggested a
   short ADR for the bypassPermissions rider (79495c5, user-requested, commit-message-only
   rationale) — user's call; (b) live-verify a second adapter (tmux or iTerm) — only cmux is
   live-proven, a real iTerm failure fails open + cools down silently; (c) watch for
   `adapter-failed-nosession` (shared cooldown can mute pane redirect for all env-less
   sessions up to 7 days) and the first concurrent two-implementer pane dispatch; (d) README
   has no Roadmap section (non-template, 55 lines) — standardizing via
   `writing-project-readmes` is its own task if wanted. Only chrome/chrome-native-host stays
   uncommitted (machine-local).
1. **Statusline token bar — DONE (PR #20 merged 2026-07-20 04:01Z).** Still open, deliberately
   unabsorbed: R1's `STATUSLINE_DEBUG` logging splitting "field absent" from "field present but
   unparseable" (would have caught the epoch-seconds bug on render one); cosmetics (duration floors,
   bar full at 95k, no MB rollover). Detail + lessons: `coding-memory/branches/statusline-token-bar.md`, ADR 0005.
2. **compliance-judge (post-merge reconcile DONE 2026-07-18):** remaining loose end only —
   the store is global but writeup filenames carry no repo component (final-review
   recommendation); revisit if cross-repo spec slugs ever collide. Also: backfill the
   compliance-judge verdicts' own `outcome` fields once those specs implement (calibration
   ledger, see running-the-compliance-judge SKILL.md).
3. **memsearch debt (recorded, not blocking; ledger `.superpowers/sdd/progress.md` has detail):**
   `index` exits 0 even when errors>0 (fix before wiring automation to exit codes); validate
   `ollama_url` is loopback; busy_timeout PRAGMA; fail-fast on Ollama-down backfill; `--since`
   format validation; README sentence that digest-chunk line numbers are digest-relative.
   Memsearch-nudge SessionStart line: **VERIFIED live 2026-07-18** (fired post-/clear, 2332 chunks).
4. **Live-verify** doc-guard's PreCompact injection against a real `/compact` — still pending.
   SessionStart injection **VERIFIED live 2026-07-18**: post-/clear it surfaced the uncommitted
   verdict-store + settings.json changes exactly as designed (15-case harness had covered logic only).
5. (Optional) Retire `coding-memory/decisions.md` in favour of `docs/decisions/` (now ADRs
   0001-**0005**) — the "adopt" framing was stale, the directory was never the blocker.
   Diagramming-pointers half **DONE 2026-07-19** (PR #19), wider than this item scoped it.
5a. **Watch the next 2-3 `coding-memory/` branch logs** (ADR-0004 revisit trigger). If one lands with
   real structure and no diagram, move the `managing-session-memory:18` pointer from the
   index-description bullet into the save-time procedure section. Escalation if that also fails is a
   **gate stub, never the hook** (the hook's rejection is structural; the gate's is cost/benefit).
   Evidence: **2 of 3** — `diagramming-pointers.md` has a flowchart; `statusline-token-bar.md` now
   describes a lock protocol with real structure and carries **none** (its diagram went to ADR 0005).
   The 07-20 brainstorm write-up carries its flowchart inline (counts toward the healthy side).
6. **DONE 2026-07-21** — backfilled `outcome: clean` for the three known-clean nulls
   (`feature/observability-judge` @ fdbd7b9 + @ 381bd79, memsearch architecting @ c2b23fe)
   alongside PR #23's verdict. **CALIBRATION POLICY DECIDED 2026-07-22 (user):** on a branch with
   multiple judge rounds, the **final** round that shipped is `clean` and **earlier** rounds whose
   findings changed the code or docs before merge are `rework`. Chosen over "every round on a
   merged PR is clean" precisely because that would make the calibration history show the judge
   never prompting rework, which is false and useless for tuning it. Applied to pane-layout-v2:
   e12dc06 → `rework`, ec03621 → `clean`.
   **17 nulls remain**, now resolvable under that policy but NOT bulk-applied — each needs its
   per-branch history read to identify which round was final: statusline ×6, token-bar ×4,
   handoff ×2, pane-orch architecting ×2, verifying-subagent-commits @ 8701ca8,
   compliance-judge @ cf4efc7, and pane-layout-v2 architecting @ bb4050b. **Architecting-stage
   entries are the genuinely unclear case** — there is no merge event for a design, so "did it
   ship clean" has no direct meaning; decide that sub-policy before touching them.

**Merged** (full detail: `coding-memory/pr-tracking.md`): `.claude` PRs #10–#16 (07-16→18) —
documentation-enforcement, PORTS.md reconcile, diagramming skill, observability judge (+ judge-guard
hook, live and global), memsearch RAG index, verifying-subagent-commits, compliance judge; plus
vibe-scape (Tayvyx-Lab/VibeSpace) PRs #6–#7. **07-19:** #17 (writing-project-readmes, d242e69),
#18 (statusline, b6362ff). **07-20:** #19 (diagramming reachability + ADR 0004, a735fb4),
**#20 (statusline token bar, merged 04:01Z)**, **#21 (claude-code-handoff cherry-pick, 3c58363,
22:02Z)**, **#22 (docs-only follow-up landing PR #21's stranded judge audit trail, 284478a)**.
**07-21:** **#23 (pane orchestration, 8f40e05, 12:35Z)**, **#24 (docs-only PR #23 close-out +
outcome backfills, 23dd2e3, 13:05Z; late brainstorm-checkpoint commit stranded → cherry-picked
to main as 2d8a416)**.

**Orphans: ALL PRUNED 2026-07-20.** The 8 merged orphans (`feature/statusline-command`,
`docs/diagramming-pointers`, `feature/statusline-token-bar`, `feature/add-claude-code-handoff`,
`feature/documentation-enforcement`, `feature/modular-coding-memory`,
`feature/vibe-coding-standards-integration`, `update/update-default-model`, plus local-only
`chore/ports-registry-snatch-8001` and `feature/diagramming-skill`) were deleted local + remote
after verifying each tip is reachable from `main`. Repo now holds only `main` and the active
`feature/judge-terminal-enforcement`.
