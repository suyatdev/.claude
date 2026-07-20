# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See `managing-session-memory` for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- session_origin: desktop (VSCode) · session_started_at: 2026-07-19 (post-/clear continuation)
- last_active_branch: main (both PRs merged; branch `docs/diagramming-pointers` not yet deleted)
- **AUTHORSHIP RESOLVED (was: "uncommitted parallel work, do not commit blind").** The modified
  `statusline-command.sh` + `.gitignore` are **this session's work**, not a parallel agent's —
  a statusline follow-on to PR #18 (orange model name, 100k-referenced context bar, cumulative
  input+output counter, purple weekly-quota segment; cost display built then deliberately removed).
  The earlier "verify authorship before committing or discarding" warning was written by a
  *concurrent* session that saw the file change mid-session and correctly refused to guess.
  Safe to commit. Detail: `coding-memory/branches/statusline-token-bar.md`.
- **A concurrent session was active on 2026-07-19.** It merged PR #19, advanced `main` to f574213,
  and wrote the memory entry above — all while this session was editing `statusline-command.sh`.
  Evidence: this session opened on branch `docs/diagramming-pointers` @ ff9d215 and later found
  itself on `main` @ f574213 with no local checkout. Not a problem in itself, but the parallel-agent
  invariant applied in both directions and neither session could see the other's intent.
- current work: **diagramming reachability — PR #19 MERGED** 2026-07-20 (merge commit a735fb4,
  3 commits). The
  `diagramming-technical-docs` standard was reachable only from the ADR bullet in
  `managing-session-memory` and the `CLAUDE.md:21` catalog line, so it never self-triggered
  while writing `coding-memory/`
  branch logs, specs, or agent-architecture designs. Added one conditional pointer to each
  of those three authoring paths. Triaged as category 4 (extend an existing skill) —
  explicitly **not** a hook (a script can detect whether a mermaid block exists, not whether
  one is warranted) and **not** a gate (a missing diagram is recoverable later, so it fails
  the never-miss bar the other nine gates share). Judge R1 84a60bf low/high, no blocking
  findings, **outcome backfilled `clean`**. ADR
  `docs/decisions/0004-diagramming-reachability-not-enforcement.md` (carries a
  mindmap of the rejected tiers; escalation path if it underperforms is a gate stub, never the
  hook — the hook's rejection is structural, not evidentiary).
  Detail: `coding-memory/branches/diagramming-pointers.md`, `coding-memory/pr-tracking.md`.
- **status line config — PR #18 MERGED** (2026-07-19, merge commit b6362ff).
  Detail: `coding-memory/branches/statusline-command.md`, `coding-memory/pr-tracking.md`.
- **Orca hooks in `settings.json` deliberately uncommitted** (~112 lines, written by an external
  process mid-session; third-party, machine-local, absolute paths). Left dirty at the user's
  direction, so the working tree stays permanently modified. Worth knowing: `claude-hook.sh`
  sources `$ORCA_AGENT_HOOK_ENDPOINT` *before* its token check, and that file's stdout becomes
  hook stdout — a channel into the agent control plane. Not resolved; user's call pending.
- untracked `chrome/`, `telemetry/`, `stats-cache.json`: machine-local Claude Code artifacts, not
  repo work — leave untracked. They keep the tree permanently dirty, so the status line's `✗`
  always shows here; gitignoring them is still an open question for the user.
- Model gate: session started on **Sonnet 5**, user switched to **Opus 4.8** before any commit.
  (An earlier entry misattributed PR #17's "Fable 5" here; each is right for its own session.)
- `settings.json` model/theme preference changes follow the `chore(settings):` precedent —
  superseding the earlier "not mine to commit" note. Distinct from the Orca hooks below.

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
  injection via four distinct paths (`printf %b` expansion, real control bytes through jq, the unstripped
  `$PWD` fallback, then a **second** unstripped fallback introduced by the fix for the third), false
  "pushed" claims, and an unverified `context_window` schema — all fixed, schema confirmed against the
  official docs. `statusline-command.test.sh`: 20 assertions, validated by falsification against all 5
  historical versions (9/20, 10/20, 15/20, 20/20, 19/20) rather than by passing alone;
  `statusline-command.falsify.py` makes that reproducible, with each expected count derived from what the
  version does rather than fitted to its output. Recurring lesson: **the write-up ran ahead of the code in
  every round**, including a "Cosmetic, no leak" claim about a path that did leak. Scope overran badly —
  5 of 6 commits are judge-driven; taken to the user rather than resolved unilaterally. No ADR
  (presentation-only — misses all three ADR triggers).
  Detail: `coding-memory/branches/statusline-command.md`.
- feature/statusline-token-bar (2026-07-19, **pushed, judge findings fixed, not yet PR'd**) —
  follow-on to
  PR #18: model name orange, context bar scaled to a fixed 100k "time to clear" reference (not the
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

## Pointers
- PR tracking (all repos, all branches): `coding-memory/pr-tracking.md`
- Session log (chronological summaries): `coding-memory/session-log.md`
- Decisions & conventions: `coding-memory/decisions.md`
- Branch implementation logs: `coding-memory/branches/`
- Brainstorm write-ups: `coding-memory/brainstorms/`

## Exact Next Steps
0. **Statusline token bar — all three judge findings FIXED 2026-07-19 (suite 17/20 → 44/44).**
   Next action: **fresh implementation-stage judge verdict** @ cc0a853, then PR (judge-guard
   blocks `gh pr create` without one). Two findings were wider than the verdict scoped them.
   Detail: `coding-memory/branches/statusline-token-bar.md`, ADR 0005.
   **Still open, user's call:** the judge's "also worth doing" — split "field absent" from "field
   present but unparseable", logging the latter to `$STATE_DIR/debug.log` behind `STATUSLINE_DEBUG`,
   never stdout. Would have caught the epoch bug on render one. Deliberately not absorbed: this
   branch overran scope once already and that was escalated rather than resolved unilaterally.
   Cosmetics still left: duration floors, bar rounds full at 95k, no MB rollover.
1. **compliance-judge (post-merge reconcile DONE 2026-07-18):** remaining loose end only —
   the store is global but writeup filenames carry no repo component (final-review
   recommendation); revisit if cross-repo spec slugs ever collide. Also: backfill the
   compliance-judge verdicts' own `outcome` fields once those specs implement (calibration
   ledger, see running-the-compliance-judge SKILL.md).
2. **memsearch debt (recorded, not blocking; ledger `.superpowers/sdd/progress.md` has detail):**
   `index` exits 0 even when errors>0 (fix before wiring automation to exit codes); validate
   `ollama_url` is loopback; busy_timeout PRAGMA; fail-fast on Ollama-down backfill; `--since`
   format validation; README sentence that digest-chunk line numbers are digest-relative.
   Memsearch-nudge SessionStart line: **VERIFIED live 2026-07-18** (fired post-/clear, 2332 chunks).
3. **Live-verify** doc-guard's PreCompact injection against a real `/compact` — still pending.
   SessionStart injection **VERIFIED live 2026-07-18**: post-/clear it surfaced the uncommitted
   verdict-store + settings.json changes exactly as designed (15-case harness had covered logic only).
4. (Optional) Retire `coding-memory/decisions.md` in favour of `docs/decisions/`, which is already
   live and now holds ADRs 0001-**0004** — the "adopt" framing was stale, the directory was never
   the blocker. Diagramming-pointers half **DONE 2026-07-19** (PR #19), and wider than this item
   scoped it: `managing-session-memory` was the actual gap, not just the two skills named here.
4a. **Watch the next 2-3 `coding-memory/` branch logs** (ADR-0004 revisit trigger). If one lands with
   real structure and no diagram, the `managing-session-memory:18` pointer is in the wrong place —
   move it from the index-description bullet into the save-time procedure section. Escalation if that
   also fails is a **gate stub, never the hook**: the hook's rejection is structural (a script cannot
   judge warrant), the gate's is cost/benefit and could be legitimately overturned. Evidence so far:
   1 of 3 (`coding-memory/branches/diagramming-pointers.md` carries a flowchart).
5. (Optional) Backfill `outcome` for the remaining `null` judge verdicts now that results are known:
   `feature/observability-judge` @ fdbd7b9 and @ 381bd79 (PR #13 merged clean), and the memsearch
   *architecting*-stage verdict @ c2b23fe (superseded by the implementation-stage verdict, also
   clean). See `coding-memory/observability-judge/verdicts.jsonl`.

**Merged 2026-07-16 → 07-18** (full detail: `coding-memory/pr-tracking.md`): `.claude` PRs #10–#16 —
documentation-enforcement, PORTS.md reconcile, diagramming skill, observability judge (+ judge-guard
hook, now live and global), memsearch RAG index, verifying-subagent-commits, compliance judge;
plus vibe-scape (Tayvyx-Lab/VibeSpace) PRs #6–#7. All branches deleted. No orphans outstanding.

**Merged 2026-07-19:** PR #17 (writing-project-readmes + wiring, d242e69) + PR #18 (statusline,
4 rounds of escape-injection hardening, b6362ff). **Merged 2026-07-20:** PR #19 (diagramming
reachability — 3 conditional pointers + ADR 0004, a735fb4; judge R1 low/high, outcome clean).

**Orphans outstanding:** branches `feature/statusline-command` and `docs/diagramming-pointers` are
merged but not deleted (local + remote). `feature/statusline-token-bar` @ d302479 has all judge
findings fixed and the suite green at 44/44; it needs a **fresh implementation-stage judge verdict**
before `gh pr create` will pass judge-guard. See Next Step 0.
