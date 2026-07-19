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
4. `display_name` containing a literal `\x1b[5m` → renders as inert text.
5. Directory named `aa\nbb` (literal backslash-n) → stays on one line.

These five were the initial manual pass. They are now superseded by the committed
`statusline-command.test.sh` (15 assertions), which additionally covers the *real*-byte
encoding that cases 4-5 structurally cannot reach — see the harness section below.

The observability judge additionally ran the script against detached HEAD, a fresh repo with no
commits, and paths containing spaces: short-SHA fallback, `git:(main)`, and intact paths
respectively. It measured ~52ms per render with `git status --porcelain` staying fast even
against a large untracked tree (git collapses untracked directories).

## Escape-injection fix (found by the observability judge, over two rounds)

Terminal-escape injection through the status line, which arrives by **two independent routes**.
Round 1 closed only the first, and the log at that point wrongly called the issue resolved —
round 2 caught the overclaim.

**Route 1 — the script manufacturing escapes.** It originally ended in `printf "%b" "$out"`,
colours defined as ordinary strings containing `\033[...]`. `%b` expands backslash escapes across
the whole string, data included, so a field holding the literal seven-character text `\x1b`
became a real escape. Fixed by building colours and the `➜` glyph with `$'...'` ANSI-C quoting
(real ESC bytes embedded at assignment time) and rendering with `printf '%s'`.

**Route 2 — real control bytes passing straight through.** JSON can carry an actual control byte
via a unicode escape; `jq -r` decodes it to a real byte and `printf '%s'` forwards it untouched.
Route 1's fix does nothing about this. Demonstrated: a blink attribute, a newline splitting the
status line in two, and an OSC sequence rewriting the terminal title. Fixed by stripping C0
controls and DEL from every externally-sourced value with `${v//[[:cntrl:]]/}` — pure bash, so
it costs an inline expansion rather than a fork in a script that re-renders constantly.

Why round 1's tests could not have caught route 2: they used *literal-backslash* payloads, the
exact encoding that removing `%b` neutralises by construction. They passed and could never fail
for the real-byte case — the same trap as the round-1 schema fixtures, where the test contained
the assumption it existed to disprove. The suite now asserts against the script's own 8-escape
colour baseline, so any injected escape shows as a surplus, regardless of encoding.

Residual risk is low: the data comes from Claude Code, and git rejects control characters in ref
names (branch values are stripped anyway, so that doesn't need trusting). The realistic hostile
route is a directory name inside an untrusted repo. Worst case was a garbled bar or a hijacked
terminal title — no execution, no data loss.

Aside worth keeping: while writing this up, a literal ESC byte ended up embedded in the script's
own comment block, and the judge did the same in its verdict file. The failure mode is easy to
reproduce by accident, which is part of why stripping beats escaping here.

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

## Test harness — declined, then reinstated

The user initially declined a `statusline-command.test.sh`, reasoning that a status line is
presentation-only, fails visibly, and that the one unfalsifiable assumption (the
`context_window` schema) was now confirmed against the docs. Sound on the information then
available — but round 2 undercut it: an injected escape does **not** fail visibly (a stripped one
is invisible, a successful one reads as a rendering quirk), and the defect regressed *within the
session*, fixed by one route while still open by another. Put back to the user with that new
information; they opted to commit it.

`statusline-command.test.sh` — 15 assertions in the style of `hooks/memsearch-nudge.test.sh`,
split into a rendering group and a control-byte injection group.

**Validated by falsification, not just by passing.** A test that cannot fail proves nothing, so
it was run against all three states of the script:

| Script version | Result | Reads as |
|---|---|---|
| `f0902ed` (original, `printf %b`) | 8/15 | both injection routes open |
| `925c310` (round-1 fix only) | 9/15 | route 1 closed, route 2 still open |
| current | 15/15 | both closed |

That middle row is the important one — it is the state the round-1 tests declared clean, and
this suite fails it.

Two weaknesses the falsification run exposed in the tests themselves, both fixed: the
carriage-return case passed against unfixed scripts because the assertion counted ESC/NL/BEL but
not CR; and the git-segment case silently depended on the script living inside a repo, so it now
builds a throwaway repo with `mktemp -d` and asserts on a known branch name.

## Checkpoint

Two commits: `feat(statusline)` (script + `statusLine` wiring + docs, with the escape-injection
fix folded in — the defect never shipped, so it isn't preserved as its own commit) and
`chore(settings)` (model + theme preferences). Observability judge run at implementation stage
against the pre-split HEAD f0902ed: risk=low, confidence=medium, no dimension failed; its three
actionable findings (escape injection, false checkpoint claims, unverified schema) are all
resolved above. Re-run required before `gh pr create` — the split moved HEAD and judge-guard
enforces strict freshness.
