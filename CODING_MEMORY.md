# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See `managing-session-memory` for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- session_origin: desktop · session_started_at: 2026-07-22 (Opus 4.8) · last_active_branch: feature/pane-layout-v2
- **PR #25 OPEN — pane-layout-v2 is feature-complete and awaiting review/merge.**
  https://github.com/suyatdev/.claude/pull/25 (created 2026-07-22 @ ec03621). All 9 tasks done,
  probe P8 done, ADR 0008 written, implementation judge PASSED across two rounds (risk=low).
  **NEXT ACTION: nothing to build — merge via the GitHub UI, then backfill the verdict outcome.**
  **First post-merge follow-up: the cmux version gate** (pin 0.64.20, compare at layout time, warn
  loudly on mismatch) — closes the branch's main latent risk, since a cmux that changes pane-walk
  order lands the aux column wrong while all 170 tests still pass. Detail:
  `coding-memory/pr-tracking.md` §PR #25 and resume #9 below.
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
   alongside PR #23's verdict. 16 nulls remain, deliberately untouched: they're intermediate
   rounds on multi-round branches (statusline ×6, token-bar ×4, handoff ×2, pane-orch
   architecting ×2, plus verifying-subagent-commits @ 8701ca8 and compliance-judge @ cf4efc7
   early rounds) where the honest value is likely `rework`, not `clean` — needs a calibration
   policy decision (does a judge-driven fix wave after round N mean round N's outcome is
   `rework`?) before bulk-backfilling.

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
