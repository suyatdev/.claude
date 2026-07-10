# .Claude

```
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
| `CODING_MEMORY.md` | Running session memory — decisions, state, next steps. |
| `SETUP.md` | New machine checklist: plugins, RTK, verification steps. |

## Rules at a glance

- **`general-engineering.md`** — coding standards, security guardrails (injection, XSS, secrets, SAST, prompt sanitization)
- **`session-state-management.md`** — model-switch checkpoints, brainstorm-before-branch workflow, token-limit pauses
- **`pr-requests.md`** — branch naming, PR descriptions, PR memory tracking, no-pull-first workflow
- **`parallel-agent-guardrails.md`** — multi-agent/worktree safety rules

## New machine?

See [SETUP.md](SETUP.md) for the full install checklist.
