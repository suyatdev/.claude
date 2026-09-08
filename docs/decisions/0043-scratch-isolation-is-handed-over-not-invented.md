# 0043 — Scratch isolation is handed over, not invented, in two layers that fail differently

- **Status:** Accepted (2026-09-05).
- **Context:** `panes/dispatch-pane-agent.sh` — `mkdir "$run_dir/work"` (`:403`), the preamble
  heredoc (`:429`-`:443`), written ahead of the caller's prompt bytes (`:445`), the new
  `WORK_STALE_MINUTES=1440` constant (`:39`), and the `cleanup_stale` prune loop gated on an
  `agent-exit` marker with `touch -r` mtime restoration (`:112`-`:120`). `panes/run-pane-agent.sh`
  — the hoisted `run_dir` derivation and `*/runs/*` shape guard (`:37`-`:39`) and the
  `mkdir -p` + `export TMPDIR` pair (`:47`-`:48`). Full design, the Gherkin scenarios, and the
  measurement record: `docs/features/pane-agent-scratch-isolation.md`.
- **Note:** ADR number **0043** was confirmed free against every `origin/*` ref (checked
  2026-09-07); not re-derived here.
- **Note on the line numbers:** every `:NNN` below was re-opened and confirmed at
  `81f58d5`. They are anchors, not identifiers — six of them went stale *inside this
  branch* when a five-line comment expansion in `cleanup_stale` pushed everything below
  line 104 down by four, and the implementation-stage observability judge caught it. If one
  does not resolve, the quoted token beside it is the real anchor: `git grep -n
  'mkdir "$run_dir/work"' panes/` relocates it in one command.

## Context

Two judges dispatched in parallel into separate panes against the same repository invented the
same scratch path under `/tmp`, and one overwrote the other's working copies, producing one
wrong measurement before it isolated itself and recovered on its own. The round's verdicts were
not left in doubt only because the finding was independently reproduced in the dispatching
session — the failure itself was silent, and a future one might not be caught the same way.
Nothing in the dispatch path told either agent where to put its own scratch:
`panes/dispatch-pane-agent.sh` already gives each dispatch a collision-proof run directory and
result file, but neither `agents/compliance-judge.md` nor `agents/observability-judge.md` names
a scratch path, so two agents handed near-identical prompts invented the same obvious one. Full
incident account: `docs/features/pane-agent-scratch-isolation.md`.

## Decision — two layers, split on which lane has the ingredients

| Layer | Lane it covers | Guarantee | Fails how |
|---|---|---|---|
| 1 — dispatcher hands over a private `work` dir | paned (judges; workers under `panes`) | by construction — a child of an already-unique run dir | fail-fast at dispatch; a failed `mkdir` dies before any pane opens |
| 2 — one sentence in `rules/core-conduct.md` | every lane, including in-process `Explore`/`Plan` and worker fan-out under `inline` | guidance only | silently, exactly as today |

The split lands there because the paned lane is the only one that already owns the two
ingredients a mechanical fix needs: a per-dispatch unique directory (`new_run_dir`, mode 700 via
the file's `umask 077`) and a file the dispatcher writes into before the agent ever sees it
(`$run_dir/prompt.md`). Layer 1 rides both — it `mkdir`s a `work` child of the run dir
(`panes/dispatch-pane-agent.sh:403`) and prepends a preamble naming that absolute path to the
prompt the agent receives (`:429`-`:443`, ahead of the caller's bytes at `:445`), then `panes/run-pane-agent.sh` re-derives the same
run dir from `dirname(prompt_file)` under a `*/runs/*` shape guard (`:37`-`:39`) and points
`TMPDIR` at the same `work` child (`:47`-`:48`) — one fact, not two independent derivations that
could disagree.

Nothing equivalent exists in-process. There is no run directory, no file the dispatcher writes
into ahead of the agent, and no dispatcher between the caller and the model at all —
`hooks/pane-dispatch-guard.sh` classifies `.tool_input.subagent_type` and returns an exit code;
it never touches the prompt. A mechanical guarantee needs something to attach to, and in-process
dispatch has nothing. Layer 2 is what is left: a sentence in `rules/core-conduct.md`'s
Parallel-Agent Invariants, reaching every lane the same way that section's existing rules do,
and failing the same way they do — silently, if a subagent's context composition omits it (the
card measured that `Explore` receives no `rules/core-conduct.md` at all; `general-purpose`, in
both its in-process and paned forms, does).

## Rejected — rewrite the in-process prompt via `updatedInput`

A `PreToolUse` hook *can* rewrite the tool call it gates — measured by string-searching the
installed CLI binary (`~/.local/share/claude/versions/2.1.260`), which carries
`` `updatedInput` - Modified tool input (PreToolUse only) `` and
`updatedInput is missing or empty, falling back to original tool input`. That would have let
`hooks/pane-dispatch-guard.sh` inject the same scratch-path preamble into an in-process `Task`
prompt the way layer 1 injects it into a paned one, closing the in-process gap layer 2 leaves
open.

Rejected anyway, on cost:

- `pane-dispatch-guard.sh` is today a pure exit-code gate (`exit 0` allow / `exit 2` deny).
  Emitting `updatedInput` means emitting JSON on stdout instead — a change to what the hook
  fundamentally is, not an addition to it.
- The guard allows through at **ten** distinct `exit 0` sites, counted in the file rather than
  estimated. Each would need the same injection or the rewrite's coverage is partial and
  silent — exactly the defect class this card exists to remove, one level up.
- The dispatching session would no longer be able to read back the prompt its own agent
  received, since the tool call it logged would no longer match what ran.

## The retention constant

`WORK_STALE_MINUTES=1440` (`panes/dispatch-pane-agent.sh:39`), matched with `find -mmin`, never
`find -mtime` — BSD `find` truncates `-mtime` to whole days, so `-mtime +1` means strictly more
than two days, not one. A `work` child is pruned only where its run directory already holds an
`agent-exit` marker (`:114`), so a failed or in-flight run keeps its scratch for
post-mortem rather than losing it on a blind clock. Because removing the child bumps the parent
run directory's own mtime, `cleanup_stale` restores it immediately with
`touch -r "${d}prompt.md" "$d"` (`:118`) — `prompt.md` is written once at dispatch and never
modified afterward, so it is a stable reference that needs no captured timestamp of its own.

The 1440-minute (24h) figure is load-bearing, not a round number picked for tidiness. On one
fixture set aged 23h/25h/36h/49h, two different spellings prune the identical set:

| Spelling | Prunes |
|---|---|
| `-mmin +2880` (48h) | 49h alone |
| `-mtime +1` (the truncation bug) | 49h alone |

A 48-hour window is therefore indistinguishable, on this fixture, from the exact defect
`-mmin` exists to avoid — a test built around 48h could not tell the fix apart from the bug it
is supposed to catch. `WORK_STALE_MINUTES=1440` (24h) is the value that discriminates: under it
the 25h child is pruned and the 23h child survives, which neither of the two rows above can
produce.

## Consequences

- Layer 1's guarantee is structural — two dispatches get two run directories, therefore two
  `work` directories — so it is testable as a property rather than as agent compliance. Layer 2
  is a prompt instruction and is not mechanically verifiable; `rules/core-conduct.md`'s own
  Zero-Trust section already says prompt instructions are guidance, not a guarantee.
- The in-process gap is a recorded residual, not a fixed one: `Explore`, `Plan`, and worker
  fan-out under an `inline` policy get no mechanical scratch path, and an agent that hardcodes a
  literal path (rather than honoring `TMPDIR`) defeats layer 1 too.
- Falsification of layer 1 (one mutation per new assertion) is tracked as its own checklist item
  on `docs/features/pane-agent-scratch-isolation.md` and is not asserted here as complete.
