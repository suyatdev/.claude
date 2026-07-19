# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See `managing-session-memory` for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- session_origin: desktop (VSCode)
- session_started_at: 2026-07-19 (post-/clear continuation)
- last_active_branch: feature/statusline-command
- current work: **status line config — PR #18 OPEN** (7 commits, pushed
  2026-07-19). User had already written `statusline-command.sh` and wired it into
  `settings.json`; this session documented, hardened and shipped it.
  Detail: `coding-memory/branches/statusline-command.md`, `coding-memory/pr-tracking.md`.
- **Orca hooks in `settings.json` deliberately uncommitted** (~112 lines, written by an external
  process mid-session; third-party, machine-local, absolute paths). Left dirty at the user's
  direction, so the working tree stays permanently modified. Worth knowing: `claude-hook.sh`
  sources `$ORCA_AGENT_HOOK_ENDPOINT` *before* its token check, and that file's stdout becomes
  hook stdout — a channel into the agent control plane. Not resolved; user's call pending.
- untracked `chrome/chrome-native-host` in working tree: Claude Code auto-generated Chrome
  native-messaging wrapper (machine-local tooling) — not repo work, leave untracked. Note it
  keeps the tree permanently dirty, so the new status line's `✗` marker always shows in this
  repo; gitignoring it is an open question flagged to the user, not yet decided.
- Model gate: this session started on **Sonnet 5** and the user switched to **Opus 4.8** via
  /model before any commit. (Correction: the previous entry here read "session was on Fable 5" —
  that described PR #17's session, not this one. Both are accurate for their own session; the
  earlier wording was overwritten rather than superseded, noted here per the same convention as
  commit 69cc063.)
- `settings.json` model/theme preference changes are now committed on this branch, following
  the existing `chore(settings):` precedent — superseding the earlier "not mine to commit" note.

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
  `agents/observability-judge.md` (subagent scoring 10 dims → JSONL+markdown verdict + junior-dev
  layman summary), `hooks/judge-guard.sh` (+17-case test + settings.json) blocking `gh pr create`
  without a fresh strict-freshness verdict, `skills/running-the-observability-judge/`, `rules/gates.md`
  stub + `CLAUDE.md` catalog, ADR `docs/decisions/0001-observability-judge.md`, spec
  `docs/superpowers/specs/2026-07-16-observability-judge-design.md`, verdict store. Command detection
  took 2 review-driven security fixes (substring→anchored→python shlex, closing a quoted-env-prefix
  bypass); Opus whole-branch review fixed the verdict-filename-on-slashed-branches bug + a stale
  `hooks/README.md` "only git-guard installed" claim. **PR #13 MERGED 2026-07-17 (bootstrap self-gate → JUDGE_EXEMPT).**
  Detail: `coding-memory/branches/observability-judge.md`; PR status: `coding-memory/pr-tracking.md`.
- feature/memory-rag-index (2026-07-17→18) — `memsearch`: local SQLite (sqlite-vec + FTS5) RAG over
  session transcripts + curated docs, Qwen3-Embedding-0.6B embeddings, qwen3.6:35b-mlx digests,
  hybrid retrieval, silent SessionStart nudge. 15-task plan, subagent-driven (Sonnet 5 implementers/
  reviewers), 60-test suite green, full backfill 228 sources / 2332 chunks / 0 errors / p95 149ms,
  golden bar 16/16, digest audit 11/12 supported. **PR #14 MERGED 2026-07-18** (merge commit
  7015369); branch deleted. Judge (impl): risk=low conf=high, outcome=clean.
  Detail: `coding-memory/branches/memory-rag-index.md`.
- feature/compliance-judge (2026-07-18) — the compliance judge: `agents/compliance-judge.md`
  (subagent judging ONE finished spec against live rules — writing-specs + core-conduct/security —
  blocking pass/fail verdict, per-rule citations, JSONL + markdown store), `skills/running-the-
  compliance-judge/` (parallel dispatch with observability judge, capped auto-revise loop,
  escalation on persistent ids, explicit-only waivers), gates stub + catalog line, ADR 0003,
  golden eval 12/12 + loop dry-run (convergence + escalation). **PR #16 MERGED 2026-07-18**
  (merge commit 4c2abec); branch deleted. Judge (impl, head 85d8982): risk=low conf=high,
  outcome=clean. Post-merge live-verify of real dispatch → real store: confirmed.
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
4. (Optional) Have the `.claude` repo itself adopt `docs/decisions/` (it now has ADRs 0001-0002 but
   `coding-memory/decisions.md` still serves as the older equivalent); add diagramming pointers to
   `designing-agentic-architecture` / `writing-specs`.
5. (Optional) Backfill `outcome` for the remaining `null` judge verdicts now that results are known:
   `feature/observability-judge` @ fdbd7b9 and @ 381bd79 (PR #13 merged clean), and the memsearch
   *architecting*-stage verdict @ c2b23fe (superseded by the implementation-stage verdict, also
   clean). See `coding-memory/observability-judge/verdicts.jsonl`.

**Merged 2026-07-16:** `.claude` PR #10 (documentation-enforcement) + PR #11 (PORTS.md reconcile) +
PR #12 (diagramming-technical-docs skill); vibe-scape (Tayvyx-Lab/VibeSpace) PR #6 (ADR backfill
0001-0003 + template) + PR #7 (Plan 4a-1 + memory reconcile). No orphans outstanding.

**Merged 2026-07-17:** `.claude` PR #13 (observability judge — agent + judge-guard hook + skill +
gate/catalog + verdict store; merge commit 82d7b9b). Judge + gate now live and global.

**Merged 2026-07-18:** `.claude` PR #14 (memsearch — local RAG index; merge commit 7015369) + PR #15
(verifying-subagent-commits skill — controller-side subagent-checkout verification gate; merge
commit 417e8e7) + PR #16 (compliance judge — agent + skill + gate stub + catalog + store + ADR 0003;
merge commit 4c2abec). All three feature branches deleted, local + remote. No orphans outstanding.

**Merged 2026-07-19:** `.claude` PR #17 (writing-project-readmes skill + trigger wiring; merge
commit d242e69). Branch deleted local + remote; judge verdicts backfilled outcome=clean.
No orphans outstanding.
