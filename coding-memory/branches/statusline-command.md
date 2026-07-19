# Branch: feature/statusline-command

Started 2026-07-19. No brainstorm doc — the user had already written the config and asked for
it to be documented and pushed, so this branch reconciles existing working-tree state rather
than designing something new.

## What this branch delivers

A Claude Code status line that reproduces the oh-my-zsh `robbyrussell` prompt the user is used
to seeing in their terminal, extended with two Claude-specific segments.

- `statusline-command.sh` — reads the status line JSON on stdin and prints
  `➜  <user>@<host> <dir> git:(<branch>) ✗  │ <model> │ <used> tokens`.
  - The `✗` dirty marker only renders when the working tree has uncommitted changes, matching
    robbyrussell's `ZSH_THEME_GIT_PROMPT_CLEAN` behaviour.
  - Git calls use `--no-optional-locks` so the status line can't contend with concurrent git
    operations (parallel agents in worktrees).
  - The model and token segments — and their `│` separators — are omitted individually when
    their JSON field is absent or null, which is the normal state before a session's first API
    response.
  - Token count is formatted by `awk`, not bash arithmetic, so a non-integer
    `total_input_tokens` can't crash the script.
- `settings.json` — registers the script via a `statusLine` command entry. Two unrelated
  preference changes made in the same sitting (default model `claude-fable-5[1m]` → `opus[1m]`,
  and `"theme": "dark"`) were split into their own `chore(settings):` commit at the user's
  direction, matching the existing precedent of keeping preference churn separate from feature
  work. User confirmed `opus[1m]` is the intended committed default.
- `README.md` — new row in the "What's in here" table. The README has no Roadmap section, so
  there was nothing to update there.

## Why the script rather than a PS1 port

The user has no `PS1` in their shell config — the robbyrussell look comes from the oh-my-zsh
theme itself, so there was no prompt string to translate. The script reconstructs the theme's
output from the fields Claude Code supplies on stdin.

## Test evidence

Manually exercised against five stdin shapes, all exit 0:

1. Full payload (git repo + model + tokens) → full line, `113.3k tokens`, `✗` present because
   the tree was dirty.
2. Payload with no `model` / `context_window` (start of session) → git prompt only, no trailing
   `│` separators left dangling.
3. Non-git dir (`/tmp`) with a low token count → no `git:(...)` segment, tokens rendered raw
   (`42 tokens`) rather than in `k` form.
4. `display_name` containing a literal `\x1b[5m` → renders as inert text (regression test for
   the escape-injection fix below).
5. Directory named `aa\nbb` → stays on one line.

The observability judge additionally ran the script against detached HEAD, a fresh repo with no
commits, and paths containing spaces: short-SHA fallback, `git:(main)`, and intact paths
respectively. It measured ~52ms per render with `git status --porcelain` staying fast even
against a large untracked tree (git collapses untracked directories).

## Escape-injection fix (found by the observability judge)

The script originally ended in `printf "%b" "$out"`, with colours defined as ordinary strings
containing `\033[...]`. `%b` expands backslash escapes across the *whole* string, data included —
so a directory or model name holding a literal `\x1b` or `\n` injected a live terminal escape or
split the status line in two. Reproduced independently before fixing: `Opus\x1b[5m4.8` rendered
with a real ESC byte (blink attribute).

Fix: colours and the `➜` glyph are now built with `$'...'` ANSI-C quoting, which embeds real ESC
bytes at assignment time, so the render is `printf '%s'` and no expansion touches data. Git
forbids backslashes in ref names, so branch names were never the exposure — directory names were.

## Schema verification

`.context_window.total_input_tokens` was an unverified guess when the script was written — if the
key were wrong the segment would have silently never rendered, and hand-written test fixtures
could not have caught it (they contain the same guess). Checked against the official
[status line docs](https://code.claude.com/docs/en/statusline): the path is correct, and
`total_input_tokens` is current context occupancy from the latest API response, not a cumulative
total. Also available if wanted later: `context_window.used_percentage` / `remaining_percentage`,
`cost.total_cost_usd`, `session_id`, `workspace.git_worktree`, `rate_limits.*.used_percentage`.

## Not done deliberately

- **No ADR.** A status line is presentation-only — it isn't a structural/architectural
  decision, doesn't touch business logic, and doesn't pivot a feature's direction, so it
  misses all three ADR triggers in `managing-session-memory`.
- **No hook, no skill.** Nothing here is a rule or a recurring procedure.
- **`chrome/` left untracked.** Claude Code's auto-generated Chrome native-messaging wrapper —
  machine-local tooling, not repo work. Worth noting that it keeps the tree permanently dirty,
  so the new `✗` marker will always show in this repo until it's either committed or
  gitignored. Flagged to the user; not decided here.

## Follow-up not done here

No `statusline-command.test.sh`, unlike `hooks/git-guard.sh` and `hooks/judge-guard.sh` which
each ship a harness. User's call, on the reasoning that a status line is presentation-only and
fails visibly, and that the one assumption a hand-written fixture could not have falsified (the
`context_window` schema) is now confirmed against the official docs. Worth revisiting if the
script grows conditional logic.

## Checkpoint

Two commits: `feat(statusline)` (script + `statusLine` wiring + docs, with the escape-injection
fix folded in — the defect never shipped, so it isn't preserved as its own commit) and
`chore(settings)` (model + theme preferences). Observability judge run at implementation stage
against the pre-split HEAD f0902ed: risk=low, confidence=medium, no dimension failed; its three
actionable findings (escape injection, false checkpoint claims, unverified schema) are all
resolved above. Re-run required before `gh pr create` — the split moved HEAD and judge-guard
enforces strict freshness.
