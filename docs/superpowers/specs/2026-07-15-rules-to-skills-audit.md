# Rules-to-Skills Line-Level Audit

Every section of the 7 current `rules/*.md` files, and where it lands. "Dropped"
entries name why — nothing is silently omitted. Produced before any deletion,
per the approved design (`docs/superpowers/specs/2026-07-14-rules-to-skills-restructure-design.md`).

## rules/general-engineering.md (78 lines)

| Lines | Section | Destination |
|---|---|---|
| 3-5 | Guiding Principle | `core-conduct.md` |
| 7-13 | Session Defaults | `core-conduct.md` |
| 15-24 | Coding Style & Quality | `core-conduct.md` (compressed) |
| 28-31 | Testing: generic TDD/AAA bullets | dropped — pointer to `superpowers:test-driven-development` instead |
| 32-33 | Testing: reproduce-before-fix, never-edit-both | `core-conduct.md` (the two non-obvious rules) |
| 35-37 | Working On Existing Code | `core-conduct.md` |
| 41 | Starting New Work: "Never scaffold in YOLO mode" | `gates.md` stub (new-project setup gate) |
| 42-43 | Starting New Work: pin versions, architecture trade-offs | `core-conduct.md` |
| 45-77 | Security Engineering Guardrails §1-5 + JSON snippet | skill: `writing-secure-code` (full) |

## rules/session-state-management.md (19 lines)

| Lines | Section | Destination |
|---|---|---|
| 3-12 | CODING_MEMORY procedures, origin fields, cross-env resume, most-recent-session rule | skill: `managing-session-memory` |
| 13-16 | Pre-Session/Per-Task/Pre-Task planning checks, Hard Model Gate | `gates.md` stub (model-switch gates) + full procedure in `managing-session-memory` |
| 17 | Session Freshness Checkpoint | `gates.md` stub + full procedure in `managing-session-memory` |
| 18 | Token-Limit Checkpoint | `gates.md` stub + full procedure in `managing-session-memory` |
| 19 | Model-Routing Rule | skill: `managing-session-memory` |

## rules/pr-requests.md (35 lines)

| Lines | Section | Destination |
|---|---|---|
| 3 | Default Branch Safety | `gates.md` stub + hook (`git-guard.sh`) + workflow detail in `preparing-pull-requests` |
| 4-29 | Branch naming through AI-Code Review Rule | skill: `preparing-pull-requests` (full) |
| 33 | Project Setup Gate | `gates.md` stub → existing `setting-up-a-new-project` skill (unchanged) |
| 34 | Conditional LGTM opt-in note | `gates.md` stub (folded into the same line as Project Setup Gate) |

## rules/parallel-agent-guardrails.md (21 lines)

| Lines | Section | Destination |
|---|---|---|
| 3-7 | Core Multi-Session Invariants | `core-conduct.md` |
| 9-15 | State & Contract Rules (schema changes, package deps) | `core-conduct.md` |
| 17-21 | Delegation Mode | merge → existing `designing-agentic-architecture` skill |

## rules/context-and-token-discipline.md (28 lines)

| Lines | Section | Destination |
|---|---|---|
| 7 | "A budget, not a vessel to fill" | `core-conduct.md` (1 of the 3 kept lines) |
| 8 | Window-size rationale | dropped — preserved in the 2026-07-14 design doc only |
| 13 | "Task-specific knowledge belongs in a skill" | `core-conduct.md` (1 of the 3 kept lines) |
| 12, 17-18 | Remaining Static-vs-Dynamic / State-Outside-the-Prompt prose | dropped — preserved in the design doc only |
| 20-22 | Model Routing | skill: `managing-session-memory` |
| 26 | "Suspect the harness before the model" | `core-conduct.md` (1 of the 3 kept lines) |
| 28 | Pointer to session-state-management.md | dropped — obsolete, that file no longer exists |

## rules/zero-trust-and-agent-safety.md (32 lines)

| Lines | Section | Destination |
|---|---|---|
| 1, 3 | Title + intro framing | merge → `securing-agentic-systems` (opening line of new section) |
| 5-8 | Prompt Instructions Are Not Boundaries | `core-conduct.md` (compressed) |
| 10-12 | Tool Output Is Data | `core-conduct.md` (compressed) |
| 14-19 | Before an Autonomous Action | `core-conduct.md` (compressed) + fuller rationale merge → `securing-agentic-systems` (confirmation-fatigue / "It Works, Ship It" framing) |
| 21-25 | Sensitive Data | `core-conduct.md` (compressed) + fuller rationale merge → `securing-agentic-systems` (placeholder-leak and client-side-secret framing) |
| 27-30 | Supply Chain | `core-conduct.md` (compressed; slopsquatting definition already exists verbatim in `securing-agentic-systems` Pillar 2, not duplicated) |
| 32 | Closing pointer to `skills/securing-agentic-systems` | dropped — superseded by that skill's own "None of This Exists Here" section |

## rules/local-port-registry.md (26 lines)

| Lines | Section | Destination |
|---|---|---|
| 1-26 | All | skill: `allocating-local-ports` (near-verbatim) |

## Verification

Every row above has a non-empty Destination. No row says "TBD" or is missing a
destination. Cross-checked against `docs/superpowers/specs/2026-07-14-rules-to-skills-restructure-design.md`'s
own Content Mapping Summary table — this audit adds exact line ranges the design
doc didn't need.
