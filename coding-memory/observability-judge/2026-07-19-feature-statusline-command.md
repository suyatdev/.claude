# Observability Judge — feature/statusline-command

- **repo:** .claude
- **branch:** feature/statusline-command
- **head_sha:** f0902ed82880e9e793b40a4576c5cd1d7bd3055e
- **base:** main (merge-base 54b9b265f91c7b259e29f8193c9c589005e3eec5)
- **stage:** implementation
- **ts:** 2026-07-19T18:30:42Z
- **risk:** low — **confidence:** medium

## What was changed

The status bar at the bottom of Claude Code now looks like the user's normal terminal prompt
(`➜ user@host dir git:(branch) ✗`), with the current model and token count tacked on the end in
grey. One new shell script does the drawing, one line in `settings.json` switches it on, and the
change is written up in the README, the running memory file, and a new branch log.

Two extra settings hitched a ride in the same commit: the default model flipped to `opus[1m]`
and a `"theme": "dark"` entry appeared.

## Does it do what was asked

Yes. The user had already written the script by hand and asked for it to be documented and
shipped; the agent correctly treated this as a reconcile-and-ship job and did not redesign
someone else's script. I ran the script myself against nine input shapes and it behaved
correctly in every one, including the three the author was unsure about.

## What could go wrong

The script is built to stay quiet when data is missing — if a field it wants isn't there, that
part of the line just doesn't appear. That is good for a status bar and bad for testing: the
token counter reads `.context_window.total_input_tokens`, and I could find no independent
confirmation that Claude Code actually sends that field. If the name is wrong, the token segment
silently never shows and nothing ever errors. The three manual tests were hand-written payloads
that assumed the same field name, so they could not have caught it. Think of it as testing a
mail slot by posting letters through it yourself — it proves the slot works, not that the
postman uses it.

The script prints with `printf "%b"`, which expands backslash escapes. That is intentional for
the colour codes, but it also expands escapes sitting in *data*. I demonstrated this: a value
containing `\x1b[5m` gets rendered as a live terminal escape, and a directory named `aa\nbb`
splits the status line across two lines. Branch names are safe (git forbids backslashes in ref
names), but directory names are not. Low likelihood, real mechanism.

Two sibling scripts in this repo (`judge-guard.sh`, `memsearch-nudge.sh`) ship with `.test.sh`
harnesses. This one does not, and the author flagged that gap honestly.

## What I'd double-check before merging

1. Open any session and look at the status bar. If the token count renders, the schema guess was
   right. That is a five-second check that closes the biggest unknown.
2. Confirm the user actually wants `"model": "opus[1m]"` committed as the durable repo default.
   The author describes it as leftover churn from running `/model` mid-session; committing churn
   as config changes every future session's starting model.
3. The branch log states "Committed and pushed; PR opened. Nothing pending." None of that is
   true at HEAD — `git ls-remote` shows no remote branch and `gh pr list` returns empty. Fix the
   line before it becomes the permanent record.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Documented and committed the user's existing script without redesigning it. Push/PR still outstanding, which is correct gate ordering. |
| execution | concern | Works across all 9 scenarios I ran; but no automated test despite repo precedent, unverified token-field schema, and a demonstrated escape-expansion path. |
| trajectory | concern | Genuinely evidence-driven: checked `git-guard.sh` policy before the main commit (I verified it does permit coding-memory-only commits), checked history for settings precedent, asked the user about the split, declined the `chrome/` drive-by. Did not ask about the settings churn despite asking about everything else. |
| regression | concern | `settings.json` is valid JSON and hooks are untouched; but the committed model default now changes every future session, and `✗` is permanently lit in this repo because `chrome/` is untracked. |
| context_budget | pass | No always-on rule or prompt growth. +1 README row, ~17 net lines of memory, a status line costs zero context. |
| traceability | concern | Branch log explains the *why* well (no PS1 to port, `--no-optional-locks` for parallel agents, awk over bash arithmetic). Undercut by a false completion claim and a silent rewrite of a prior session's model record (Fable 5 → Sonnet 5) with no correction note. |
| success_masking | concern | Silent-omission design plus self-authored payloads means the tests cannot falsify the core schema assumption. jq parse errors on bad stdin go to stderr while exit stays 0. |
| intent_drift | concern | Model + theme preference changes bundled into a `feat(statusline)` commit, reversing this repo's own recorded "not mine to commit" note. Repo precedent for tracking settings exists but uses separate `chore(settings):` commits. |
| checkpoint | pass | Single commit, clean feature branch off clean main, nothing pushed, no PR. Trivially revertible — though a revert also takes the model/theme change with it. |
| audit_trail | pass | Attributable single commit with branch log and memory entry. Agree with the no-ADR call: presentation-only, misses all three triggers. |

## Verification I ran myself

Independently exercised `statusline-command.sh` (bash 3.2.57, jq 1.x) — I did not take the
reported evidence on faith:

- Full payload → correct line, `113.3k tokens`, `✗` present, exit 0.
- **Fresh repo, no commits (unborn branch)** → renders `git:(main)` correctly, exit 0. Handled.
- **Detached HEAD** → falls back to short SHA `git:(f9dfd30)`, exit 0. Handled.
- **Path with spaces** → renders `has space dir` intact, exit 0. Handled.
- Directory name containing `\n` → **status line breaks across two lines**.
- `display_name` containing `\x1b[5m` → **live ANSI escape injected into terminal output**.
- Non-JSON stdin → 3 jq parse errors to stderr, still exits 0 with a `$PWD` fallback line.
- Empty stdin → same fail-soft behaviour, exit 0.
- Timing: ~52 ms/render (≈8 subprocesses, incl. 3 separate `jq` calls on the same input).
  20k-untracked-file repo stayed fast — git collapses untracked directories, so the feared
  `git status --porcelain` blowup does not materialise.

Also verified: `settings.json` parses; `statusLine` entry well-formed; script committed mode
100755; commit `54b9b26` on main staged only `coding-memory/*`, which `hooks/git-guard.sh`
lines 88-110 explicitly permit. Could not locate the Claude Code CLI bundle to confirm the
statusline JSON schema — that remains the load-bearing unknown behind my medium confidence.

## Concerns

- Token-count field `.context_window.total_input_tokens` is an unverified schema assumption; silent-omission design means a wrong field name never surfaces an error
- Manual tests used self-authored payloads that bake in the same schema assumption, so they cannot falsify it
- `printf "%b"` expands backslash escapes present in data — directory names can inject ANSI escapes or line breaks (demonstrated)
- No automated test harness despite `judge-guard.test.sh` / `memsearch-nudge.test.sh` precedent in this repo
- `model: opus[1m]` and `theme: dark` bundled into a `feat(statusline)` commit, reversing a recorded "not mine to commit" decision without asking
- Committing transient `/model` churn as the durable repo default changes every future session
- Branch log asserts "Committed and pushed; PR opened" — nothing is pushed and no PR exists
- CODING_MEMORY silently rewrites a prior session record (Fable 5 → Sonnet 5) with no correction note
- `✗` dirty marker is permanently lit in this repo because `chrome/` stays untracked, degrading the signal to noise
