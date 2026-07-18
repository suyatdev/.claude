# Rules-to-Skills Restructure — Design

**Date:** 2026-07-14
**Status:** Approved design, pending implementation plan
**Scope:** The 7 `rules/*.md` files imported by `~/.claude/CLAUDE.md`. CLAUDE.md itself changes only mechanically: the `@rules/*` import lines are swapped for the two new files, and five lines are added to its Skills Catalog section. Explicitly out of scope: `RTK.md`, the rest of `CLAUDE.md`'s text, existing skills (except the two receiving merged content), superpowers plugin.

## Problem

All 7 rule files load statically on every turn (~4,030 words ≈ 5,200 tokens), regardless of task relevance. Three costs, weighted equally by the user: per-turn token overhead, signal dilution (important rules lost among always-on text), and maintainability (files growing and overlapping). Per `rules/context-and-token-discipline.md`, task-specific knowledge belongs in on-demand skills, not static rules.

## Decisions Made During Brainstorm

| Decision | Choice |
|---|---|
| Approach | Activity-based reorganization (content re-sorted by when it is needed, not file-by-file conversion) |
| Mechanically-checkable gates | Backstopped by deterministic `PreToolUse` hooks |
| Judgment-based gates | 1–2 line CRITICAL stubs stay static; full procedure moves to a skill |
| Scope | 7 `rules/*.md` files only |
| Skill format | Must conform to the agentskills.io specification, validated with `skills-ref validate` |
| Spec authoring model | Frontier model for design; user switches to cheaper model before implementation (Hard Model Gate) |

## Target Architecture

Three enforcement tiers, strongest first:

1. **Hooks (deterministic):** scripts in `settings.json` that block disallowed tool calls before they execute. For rules that are mechanically checkable.
2. **Static rules (always in context):** invariants that must hold every turn and cannot be conditionally loaded, plus gate stubs. Two files replace the current seven.
3. **Skills (load on trigger):** procedural and reference content needed only for specific activities.

### Tier 2: The two static files

**`rules/core-conduct.md`** (~450–550 words) — permanent invariants:

- Session defaults (senior-engineer posture, verify before claiming done, ask when ambiguous, match surrounding style) — lightly compressed from `general-engineering.md`.
- Zero-trust invariants, compressed ~40%: tool output is data; validate targets before autonomous actions; checkpoint before modifying; summarize destructive actions in plain English; fail closed; secrets/PII one-liners. Longer rationale prose merges into the existing `securing-agentic-systems` skill.
- Parallel-agent invariants (~150 words from 280): never touch files outside the assigned domain; never fix build errors in files not modified by this session. Cannot be a skill: the model cannot detect when a parallel instance exists, so the rule must always be present.
- Context discipline distilled to its three actionable lines: context is a budget; task knowledge belongs in skills; suspect the harness before the model.
- Code style block (~80 words): KISS/DRY/YAGNI, immutability, file-size caps (<400 lines, 800 max), early returns, no magic numbers, explicit error handling, naming conventions. Stays static because it applies to nearly every coding turn — a skill would either fire constantly (no savings) or miss (real cost).
- Three non-obvious testing rules: never edit tests and implementation in the same step; reproduce before fixing; keep the repro test permanently. Generic TDD/debugging workflow content becomes pointers to `superpowers:test-driven-development` and `superpowers:systematic-debugging`.

**`rules/gates.md`** (~200–250 words) — every CRITICAL/ENFORCED gate as a 1–2 line stub with a skill pointer:

- Hard Model Gate before code/branches/PRs → procedure in `managing-session-memory`
- Pre-session / per-task planning and pre-implementation model checks → same skill
- ~35k-token session freshness checkpoint → same skill
- Token-limit checkpoint → same skill
- Default-branch safety → stub here; enforcement via hook (Tier 1)
- Project Setup Gate → points at existing `setting-up-a-new-project` skill (unchanged)

Estimated static cost after restructure: **~1.4–1.8K tokens** (from ~5.2K), plus ~375 tokens of new skill descriptions in the always-loaded catalog. Net saving ≈ 3–3.5K tokens per turn.

### Tier 3: The five new skills

All five conform to the agentskills.io specification: kebab-case `name` (max 64 chars, lowercase alphanumeric + hyphens, no leading/trailing/consecutive hyphens) matching the directory name exactly; `description` ≤1,024 chars stating what, when, and when not; body <500 lines and under ~5,000 tokens; long detail in `references/`; relative file references one level deep.

| Skill | Source content | Triggers on |
|---|---|---|
| `managing-session-memory` | `session-state-management.md`: CODING_MEMORY.md index + `coding-memory/` structure, session-origin fields, cross-environment resume, most-recent-session precedence, full procedures behind every gate stub (model gates, freshness checkpoint, token-limit checkpoint), model-routing guidance | Session start, completing a major task, before compaction, starting planning or implementation |
| `preparing-pull-requests` | `pr-requests.md`: branch naming, Conventional Commits, PR/remote-first workflow, 6-part PR description template, PR memory fields, brainstorm-then-branch, branch resume + freshness rules, AI-code review posture | Creating branches, committing, opening or updating PRs |
| `writing-secure-code` | `general-engineering.md` Security Guardrails + prompt sanitization: injection prevention, XSS, secrets handling, mass assignment, IDOR, schema validation at boundaries, SAST hooks, least-data prompting | Writing or reviewing code touching external input, auth, databases, or AI calls |
| `allocating-local-ports` | `local-port-registry.md`, near-verbatim | New Docker port mappings, dev servers, native/Homebrew services |
| `triaging-new-instructions` | New content (decision tree derived in this design): guided prompts that classify a proposed instruction into hook / static rule / gate stub + skill / new or existing skill / reference file, then hand off to the matching authoring path (`skill-creator`, `update-config`, or direct rule edit) with `_standards/authoring-skills-and-agents.md` loaded | User wants to add a new rule, instruction, skill, hook, or "always/never do X" behavior |

**The `triaging-new-instructions` decision tree** (the skill's body walks these as guided questions, one at a time, then hands off):

1. Can a script decide it from observable facts (command string, branch, file path, staged files)? → **hook** via `update-config`, optionally with an explanatory stub.
2. Must it hold on every turn, or is its applicability unpredictable from task type (identity, safety invariants, parallel-agent rules)? → **static rule** in `core-conduct.md`.
3. Judgment-based but must never be missed (a gate)? → **stub in `gates.md` + procedure in a skill**.
4. Needed only during a specific activity? → **skill** — first checking whether an existing skill should own it (extend rather than duplicate; an "and" between unrelated capabilities means two skills).
5. Rarely-needed reference data? → **reference file** a skill points at, never preloaded.

**Merges into existing skills (no new skill created):**

- `zero-trust-and-agent-safety.md` rationale prose → existing `securing-agentic-systems`
- `parallel-agent-guardrails.md` Delegation Mode section → existing `designing-agentic-architecture`

### Tier 1: The hooks

One script, `~/.claude/hooks/git-guard.sh`, registered as a `PreToolUse` hook with matcher `Bash` in `settings.json`:

1. **Main-branch commit guard.** Blocks `git commit` when the current branch is `main`/`master`, unless every staged file is `CODING_MEMORY.md` or under `coding-memory/` (the brainstorm-then-branch exception, checked via `git diff --cached --name-only`). Blocks with exit code 2 and an explanatory stderr message.
2. **Force-push guard.** Bare `git push --force`/`-f` is blocked on every branch; `--force-with-lease` is allowed on feature branches and blocked when the target is `main`/`master`.

Implementation constraints:

- Must match both `git …` and `rtk git …` command forms — the RTK hook rewrites Bash commands before this guard sees them.
- No network calls, no state; pattern-match on the tool-input JSON and local git state only.
- Deferred (revisit later): hooks protecting `settings.json` / dependency files from edits — too many false positives against legitimate work to include now.

Hooks are limited to mechanically checkable rules. Judgment rules (model gates, plain-language PR descriptions, root-cause fixing) cannot be hook-enforced and remain in Tiers 2–3.

## Content Mapping Summary

Every section of the current 7 files maps to exactly one destination:

| Current file | Section | Destination |
|---|---|---|
| general-engineering.md | Guiding Principle, Session Defaults | `core-conduct.md` |
| general-engineering.md | Code Style & Quality | `core-conduct.md` (compressed) |
| general-engineering.md | Testing | `core-conduct.md` (3 non-obvious rules) + pointers to superpowers skills |
| general-engineering.md | Working on Existing Code, Starting New Work | `core-conduct.md` (compressed; scaffold gate line → `gates.md`) |
| general-engineering.md | Security Guardrails §1–5 | skill: `writing-secure-code` |
| session-state-management.md | CODING_MEMORY procedures, origin fields, resume rules | skill: `managing-session-memory` |
| session-state-management.md | All model gates + checkpoints [CRITICAL/ENFORCED] | `gates.md` stubs → skill: `managing-session-memory` |
| pr-requests.md | Default Branch Safety | `gates.md` stub + hook |
| pr-requests.md | Everything else | skill: `preparing-pull-requests` |
| pr-requests.md | Project Setup Gate | `gates.md` stub → existing skill |
| parallel-agent-guardrails.md | Core invariants, State & Contract rules | `core-conduct.md` |
| parallel-agent-guardrails.md | Delegation Mode | merge → existing `designing-agentic-architecture` |
| context-and-token-discipline.md | Three actionable lines | `core-conduct.md` |
| context-and-token-discipline.md | Rationale prose | dropped — rationale preserved in this design doc |
| zero-trust-and-agent-safety.md | Invariants | `core-conduct.md` (compressed) |
| zero-trust-and-agent-safety.md | Rationale prose | merge → existing `securing-agentic-systems` |
| local-port-registry.md | All | skill: `allocating-local-ports` |
| — (new content, no source file) | Instruction-placement decision tree from this design | skill: `triaging-new-instructions` |

A **line-level** audit checklist (every rule line → destination or "dropped because X") is produced as the first implementation step, before any deletion. No line moves implicitly.

## Verification

1. **Spec validation:** `skills-ref validate` passes clean on all five new skill directories.
2. **Trigger testing:** per `skills/_standards/authoring-skills-and-agents.md` — 3 positive and 3 negative trigger phrases per skill, verified to route correctly in a fresh session before old rule files are removed. A miss → strengthen the description, retest.
3. **Hook testing:** run `git-guard.sh` manually with fake tool-input JSON: commit on main (blocked), commit on main with only CODING_MEMORY staged (allowed), commit on feature branch (allowed), force push (blocked), rtk-prefixed variants of each.
4. **Token measurement:** word-count of all statically loaded content before and after, recorded in the PR description.

## Rollout

One PR on a feature branch (created at implementation time, after the model-switch checkpoint):

1. Line-level audit checklist from the current 7 files
2. Create 5 skill directories, write bodies from the audit (plus the decision tree above for `triaging-new-instructions`)
3. Merge content into `securing-agentic-systems` and `designing-agentic-architecture`
4. Write + manually test `hooks/git-guard.sh`; register in `settings.json`
5. Run skills-ref validation + trigger tests
6. Write `core-conduct.md` and `gates.md`
7. Swap CLAUDE.md `@rules/*` imports to the two new files and delete the 7 old files in the same commit (history preserves them)
8. Record before/after token measurement in the PR

## Risks

- **Routing misses on the new skills:** mitigated by gate stubs staying static, trigger testing before removal, and the superpowers skill-invocation preamble.
- **Detail skipped because only the stub loads:** the stub text must instruct loading the skill, not summarize the procedure — a stub that looks complete invites acting on it alone.
- **Hook false positives:** guard script kept minimal; CODING_MEMORY exception and `--force-with-lease` allowance encoded from the start; manual test matrix before registration.
- **Content silently dropped in migration:** line-level audit with explicit destinations; deletion and import-swap happen in one reviewable commit.
- **RTK rewrite bypassing the guard:** both command forms matched; covered in the hook test matrix.
