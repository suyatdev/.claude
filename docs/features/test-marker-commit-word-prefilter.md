---
phase: planning
model_tier: high
branch: none
---

# test-marker-guard refuses a read-only `git -C` command whose request mentions "commit"

> **Status: problem recorded, planning not started (2026-10-28).** Filed from the live verification
> of `docs/features/git-guard-quiet.md` (§ Verification, § Known gaps). No design has been chosen;
> the entering-planning model checkpoint is still to be asked.

## Problem

From a session in a repo that has opted in to test-marker-guard (any `~/.claude` checkout), a
read-only `git -C <dir> log --oneline` was refused:

```
test-marker-guard: MSG_UNSUPPORTED_FORM (FOREIGN_REPO) -- this commit's contents cannot be verified before it runs.
```

The same command, re-run with a Bash `description` that did not contain the word "commit", ran.
Two steps combine to cause it (both read on `origin/main` at `5fba281`):

1. **Pre-filter on the raw payload** — `hooks/test-marker-guard.sh:43-46`:
   ```bash
   case "$payload" in
     *commit*) ;;
     *) exit 0 ;;
   esac
   ```
   The payload is the whole `PreToolUse` JSON, so the tool call's `description` field (and any
   other text in it) can arm the guard, not just the command.
2. **Any global option ahead of the subcommand is treated as an unseeable commit** —
   `hooks/lib/classify-commit-command.py:218` (`if blocking_option is not None:` → `COMMIT`,
   `UNSUPPORTED`), deliberately fail-closed because `git -C X <alias>` could be a commit.

So whether a read-only `-C` command runs depends on the wording of text that is not the command.

## Why it matters

- It refuses commands that cannot commit, so it costs work for no protection.
- It shadows `git-guard quiet`'s `read` allow in opted-in repos, intermittently.
- The refusal message says "this commit's contents", which misleads when nothing commits.

## Open questions (for planning — none decided)

- Should the pre-filter read the command only (`tool_input.command`) rather than the raw payload?
- Should step 2 stay fail-closed for every global option, given that is its stated design?
- What do the existing `classify-commit-command.test.py` and `test-marker-guard.test.sh` cases
  pin about the pre-filter, so a change is measured rather than assumed?

## Tasks

- [ ] Task 1 — planning: brainstorm, then spec (none written yet)

## Verification

<Appended during review: pass/fail per area and open issues only.>
