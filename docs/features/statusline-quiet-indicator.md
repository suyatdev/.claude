---
phase: planning
model_tier: high
branch: none
---

# Status line: git-guard quiet indicator

## Spec

The status line shows whether `git-guard quiet` (ADR 0051, `docs/features/git-guard-quiet.md`) is on
for the current session, so Mark can see at a glance whether `git -C` lookups will prompt.

- **Quiet:** amber (`YELLOW`) `git-guard: quiet`, when a quiet flag exists for this session.
- **Off:** dim `git-guard: on` otherwise. Both states are shown, so off is visibly off rather than
  indistinguishable from a missing segment (Mark's choice, 2026-10-29).
- **No session_id in the payload:** no segment.
- **Source of truth is git-guard's own test, mirrored exactly** (`hooks/git-guard.sh`, `quiet_allows`):
  `$HOME` non-empty, `session_id` fullmatches `[A-Za-z0-9-]{1,128}` on the RAW payload value, and
  `$HOME/.claude/hooks/state/git-guard-quiet/<session_id>` is a regular file. Any id git-guard would
  reject renders `on`, even when a flag for a near-miss of it exists.
- The segment reports the flag, not a per-command verdict: with quiet on, git-guard still asks for
  shapes outside the quiet allowlist. The label says `quiet`, never "no prompts".
- Width is declared with the text (16 / 13 cells), so packing never overflows `COLUMNS`.
- Inert until merged: the status line loads `statusline-command.sh` from the primary checkout.

```gherkin
Scenario: quiet flag set by the real toggle hook
  Given the toggle hook ran "git-guard quiet" for session "sess-q1"
  When the status line renders for session "sess-q1"
  Then it shows amber "git-guard: quiet"

Scenario: near-miss id with a flag on disk
  Given a flag file exists for "sess_q4" (underscore, which git-guard rejects)
  When the status line renders for session "sess_q4"
  Then it shows dim "git-guard: on"
```

Edge cases pinned in `statusline-command.test.sh`: flag removed by `git-guard on`, no session_id,
control byte or trailing newline inside a flagged id, path traversal, flag path is a directory,
129-character id, and a COLUMNS 20..90 overflow sweep.

## Tasks

- [ ] Task 1 — failing tests in `statusline-command.test.sh` (written and run red: 124/134, 10 new cases fail)
- [ ] Task 2 — segment in `statusline-command.sh`; full suite green
- [ ] Task 3 — observability judge, then PR

## Verification
