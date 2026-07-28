# .Claude

```
  ┌─────────────────────────────────────────┐
  │                                         │
  │   > follow my rules                     │
  │                                         │
  │   Claude: Understood. Also, you have    │
  │   3 unsanitized prompts, a hardcoded    │
  │   secret, and forgot to branch first.   │
  │                                         │
  │   ████████████████████░░  92% pedantic  │
  └─────────────────────────────────────────┘
         the AI that reads the docs
              so you don't have to

                      YOU:  just write me a quick script, no tests needed
              ___
          ___|   |___
         |           |       CLAUDE.md detected
         |   ◉   ◉   |   ──────────────────────────────
         |     ▽     |   📋 loading 47 rules...
         |___________|   🔒 scanning for hardcoded secrets
        /             \  🌿 checking if you branched first
       /  ┌─────────┐  \ 🧪 requiring tests anyway
      /   │  rules  │   \
     /    └─────────┘    \  "quick script" submitted
    ────────────────────────  "quick script" returned
                              with architecture diagram
```

> My personal Claude Code configuration — rules, conventions, and memory — version-controlled so every machine starts smart.

---

## What's in here

| File / Folder | Purpose |
|---|---|
| `CLAUDE.md` | Root entry point. Imports all rule files. |
| `rules/` | Focused rule files loaded by Claude on every task. |
| `RTK.md` | RTK proxy config for token-optimized CLI output. |
| `settings.json` | Hooks, enabled plugins, and TUI preferences. |
| `statusline-command.sh` | Status line renderer — oh-my-zsh `robbyrussell` prompt plus model and token count. Tests: `statusline-command.test.sh`; falsification harness: `statusline-command.falsify.py`. |
| `CODING_MEMORY.md` | Running session memory — decisions, state, next steps. |
| `SETUP.md` | New machine checklist: plugins, RTK, verification steps. |

## Rules at a glance

- **`core-conduct.md`** — permanent invariants: session defaults, code style, zero-trust rules, parallel-agent safety, context discipline
- **`gates.md`** — judgment-based checkpoints (model-switch gates, default-branch safety, project setup) as short stubs pointing at the skill with the full procedure

## 🗺️ Roadmap

- [x] Terminal-pane orchestration for dispatching subagents (judges, plan implementers) into real headless sessions (#23–#27)
- [x] Two dev-time judges gating PRs: compliance (spec vs. rules) and observability (evaluation + observability rubrics) (#13, #16)
- [x] Local memory RAG index (`memsearch`) over session digests and docs (#14)
- [x] Status line with model and token-usage segments (#18, #20)
- [x] Documentation-enforcement backstop — hooks that block undocumented business-logic changes (#10)
- [x] Phase-frontmatter permission system: a feature file's `phase` survives a session clear and gates what work is allowed on restore
- [ ] Per-session pane-split policy with three-lane agent routing (#28, open)
- [ ] A `phase-guard.sh` hook to computationally enforce the phase-frontmatter gate (deliberately deferred — see ADR 0010)
- [ ] Reconcile the remaining files still describing the retired `coding-memory/branches/<branch>.md` workflow

## New machine?

See [SETUP.md](SETUP.md) for the full install checklist.
