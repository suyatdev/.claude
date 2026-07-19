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
| `statusline-command.sh` | Status line renderer — oh-my-zsh `robbyrussell` prompt plus model and token count. Tests: `statusline-command.test.sh`. |
| `CODING_MEMORY.md` | Running session memory — decisions, state, next steps. |
| `SETUP.md` | New machine checklist: plugins, RTK, verification steps. |

## Rules at a glance

- **`core-conduct.md`** — permanent invariants: session defaults, code style, zero-trust rules, parallel-agent safety, context discipline
- **`gates.md`** — judgment-based checkpoints (model-switch gates, default-branch safety, project setup) as short stubs pointing at the skill with the full procedure

## New machine?

See [SETUP.md](SETUP.md) for the full install checklist.
