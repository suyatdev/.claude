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
| `settings.json` | Hooks, enabled plugins, and TUI preferences. Tracked on purpose — it is the only thing that registers the scripts in `hooks/`, so an untracked copy leaves a clone with the guards installed and switched off. Carries `model`/`effortLevel` too, which churn after a deliberate `/model`. |
| `statusline-command.sh` | Status line renderer — oh-my-zsh `robbyrussell` prompt plus model and token count. Tests: `statusline-command.test.sh`; falsification harness: `statusline-command.falsify.py`. |
| `docs/features/`, `docs/decisions/` | Active session memory: feature cards (phase frontmatter, spec, checklist) and ADRs. |
| `CODING_MEMORY.md`, `coding-memory/` | Retired and frozen — local-only history, still greppable on disk and in git history, no longer tracked or pushed. The two judge verdict ledgers under `coding-memory/` are the exception and stay tracked. |
| `SETUP.md` | New machine checklist: plugins, verification steps. |

## Rules at a glance

- **`core-conduct.md`** — permanent invariants: session defaults, code style, zero-trust rules, parallel-agent safety, context discipline
- **`gates.md`** — judgment-based checkpoints (model-switch gates, default-branch safety, project setup) as short stubs pointing at the skill with the full procedure

## 🗺️ Roadmap

- [x] Terminal-pane orchestration for dispatching subagents (judges, plan implementers) into real headless sessions (#23–#27)
- [x] Two dev-time judges gating PRs: compliance (spec vs. rules) and observability (evaluation + observability rubrics) (#13, #16)
- [x] Local memory RAG index (`memsearch`) over session digests and docs (#14)
- [x] Scheduled index refreshes with honest staleness reporting — a launchd agent plus an eight-state session line that separates "a run happened" from "the content is current" (#42, #45)
- [x] Status line with model and token-usage segments (#18, #20)
- [x] Documentation-enforcement backstop — hooks that block undocumented business-logic changes (#10)
- [x] Phase-frontmatter permission system: a feature file's `phase` survives a session clear and gates what work is allowed on restore
- [x] Treko (formerly the feature-state tracker): surveys which cards, branches, and PRs are in flight and proposes a merge order, backed by a versioned state store and a localhost control server; the skill now launches the server and opens the browser itself instead of printing instructions (#51)
- [x] Per-session pane-split policy with three-lane agent routing (#28)
- [x] `phase-guard.sh` hook computationally enforcing the phase-frontmatter gate (ADR 0010's deferral overridden by ADR 0011 at the user's gate; #30)
- [x] Fixed a blind spot where a global option ahead of the subcommand (`git -C .`, `gh -R o/r pr merge`) hid the command entirely from `git-guard`/`doc-guard`/`merge-guard`; now it either passes through, asks for confirmation, or is refused with an honest reason, never silently allowed (ADR 0029; #54)
- [x] Verification-marker gate: blocks a `git commit` on a file whose paired test has never actually passed against that exact version, using a hash receipt each test suite leaves behind when it goes green — a computational form of "reproduce before fixing, verify before claiming" (ADR 0027)
- [x] Reconcile the remaining files still describing the retired `coding-memory/branches/<branch>.md` workflow (ADR 0031; #59) — the surface was enumerated rather than patched instance-by-instance, and this line is now the only live mention left
- [x] Judge verdicts ranked as their own retrieval tier, and `memsearch` chunk weights resolved from config at query time instead of frozen into each row — retuning a weight is a config edit plus an `index --reclassify` pass, not a full re-embed (ADR 0030; #60)
- [x] Treko's analysis store moved out of every repository into `$XDG_STATE_HOME/treko` — surveying a repo no longer dirties one (a single `reanalyze` used to leave a 6,170-line diff on a tracked file); `TREKO_STORE_DIR` overrides the location, and the existing snapshots are copied across once (ADR 0034; #68)
- [x] `--model` passthrough for pane dispatch: a single worker can run on a model other than the
      session default without giving up the pane for a separate visible session; omitting the flag
      is unchanged (#71)
- [x] Model-aware session-context thresholds: the checkpoint nudge and the status-line bar scale to the running model (100k Sonnet, 130k Opus/Fable, 75k otherwise) instead of a fixed 75k. The anchors are context-rot budgets, not window fractions — they deliberately do not grow with a 1M window — and are still capped by the model's real context window so the warning can never sit past the wall (ADR 0035; #67)
- [x] Hook-wiring health check: a session-start guard that says so when a registered guard cannot actually run, or when the live `settings.json` has drifted from the reviewed one — measured, a missing hook script fails silently and open, so silence had been indistinguishable from approval (#66)
- [x] Treko's board is themeable: 27 hardcoded colours became 8 named tokens, which is what makes the rest possible — a light theme, a Configuration drawer behind the gear (Appearance and Layout), and a sidebar you can drag from 190 to 440px and that remembers where you left it. The tokenize pass ships as a provable no-op in its own commit and the repaint in a second, so the colour change has a rollback point; before this branch nothing tested the page's appearance at all (ADR 0036; #79)

## New machine?

See [SETUP.md](SETUP.md) for the full install checklist.
