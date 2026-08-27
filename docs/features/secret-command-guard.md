---
phase: planning
model_tier: high
branch: feat/secret-command-guard
---

# Secret command guard — block Bash commands that surface credential material

## Why

This session leaked real secrets from `~/.terminal_aliases` into a conversation
transcript twice in one session (2026-08-27): once via a diagnostic script whose
output included a subprocess's full inherited environment, once via
`grep -n "export "` on a dotfile that printed full `export VAR="value"` lines. The
user asked for hard enforcement, not a stronger prose rule — `rules/core-conduct.md`
already says "nothing sensitive lives client-side" and it did not prevent either
leak. Routed through `triaging-new-instructions`: mechanically decidable from the
command text, so hook-tier, not a rule-tier fix.

A `PostToolUse` hook cannot retroactively redact output already returned to the
model (confirmed in-session against this repo's existing `PostToolUse` hooks, which
only ever *add* context, never replace a prior tool result) — so prevention has to
happen at `PreToolUse`, on the command text, before it runs.

## Scope

1. New hook `hooks/secret-command-guard.sh` (Tier 1, PreToolUse, matcher `Bash`),
   registered in `settings.json` alongside git-guard/doc-guard/etc. Blocks (exit 2):
   - a command naming a known secret-bearing dotfile/path (`~/.terminal_aliases`,
     `~/.bash_profile`, `~/.zshrc`, `~/.zprofile`, `~/.zshenv`, `.env`/`.env.*`,
     `credentials.json`, `*/Application Support/*/credentials*`) unless every
     mention sits inside a `grep`/`egrep`/`fgrep` call carrying an `-o` family flag;
   - a full-environment dump: `os.environ`/`process.env` anywhere in the raw command
     text, or a bare `env`/`printenv` with no argument as a segment's own command.
   - Fails OPEN on missing python3/unparseable payload/internal error — explicit
     judgment call, opposite of `scan-secrets.sh`'s fail-closed, because this hook's
     blast radius (nearly every Bash call, every session) is much larger than a
     single write.
2. Register the existing dormant `hooks/scan-secrets.sh` under
   `PreToolUse`/`Edit|Write|NotebookEdit` in `settings.json` — it already has a
   passing test suite and blocks writes that introduce credential material; it was
   simply never wired in. Pure wiring change, no script edits.
3. Update `rules/gates.md`: remove `scan-secrets.sh` from the "Dormant hooks" bullet
   (now three scripts, not four) and add one new gate bullet for
   `secret-command-guard.sh`.

## Non-goals

- No output-scanning/redaction of Bash results (rejected: a pipe wrapper risks
  swallowing exit codes, a known failure mode already in this session's memory).
- No attempt to catch every possible env-leak shape (e.g. a test harness's own
  invocation log nesting an inherited environment under an arbitrary name) — v1
  covers the two shapes that actually fired.

## Verification plan

- New `hooks/secret-command-guard.test.sh` matching this repo's existing
  `run_case`/`run_case_msg` hook-test convention (see `feature-sync-guard.test.sh`),
  including a registration self-test with a mutation control.
- Confirm `scan-secrets.sh`'s existing test suite still passes before registering it.
