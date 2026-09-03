---
phase: planning
model_tier: high
branch: none
---

# `secret-command-guard` matches secret file names case-sensitively

Queued 2026-09-01 out of the observability judge's round-2 read of
`docs/features/argv0-spelling-blindness.md` (branch `fix/argv0-spelling-blindness`, HEAD
`eb02618`). That card folded the **program** name so `Git commit` is caught like
`git commit`. The judge asked the obvious next question and measured it: nobody folded the
**file** name.

Gate: **not confirmed.** No branch, no code. This card is a placeholder holding a measured
finding so it is not lost — it has not been designed, and the tasks below are a sketch, not
a plan.

## Measured

Through `hooks/secret-command-guard.sh` with a real `PreToolUse` payload
(`hook_event_name`, `tool_name`, `tool_input.command`, `cwd`, `session_id`). **Nothing was
executed** — the guard decides from command text, which is the whole point; a planning judge
on the predecessor card ran an env-dump row through a real shell "to verify" it and leaked a
live API key.

| Command | rc | verdict |
|---|---|---|
| `cat .env` | 2 | blocked (control) |
| `cat .ENV` | 0 | **allowed** |
| `cat .Env` | 0 | **allowed** |
| `cat ~/.zshrc` | 2 | blocked (control) |
| `cat ~/.ZSHRC` | 0 | **allowed** |
| `cat credentials.json` | 2 | blocked (control) |
| `cat CREDENTIALS.json` | 0 | **allowed** |

Every lowercase control refuses, so the group is measured rather than blind.

Cause: `hooks/lib/classify-secret-command.py`, `DOTFILE_PATTERNS` (`:137`) compiled into
`DOTFILE_RE` (`:147`) — plain `re.compile` with no `re.IGNORECASE`, e.g.
`(r"(^|/)\.zshrc$", "~/.zshrc")`. On this machine's case-insensitive APFS, `cat ~/.ZSHRC`
opens the same file.

**Not a regression from `fix/argv0-spelling-blindness`.** That branch changes exactly two
lines in `classify-secret-command.py`, both on the `argv[0]` test (`797663e`). This is
pre-existing.

## Why it is not obviously a one-line fix

`re.IGNORECASE` is the tempting answer and needs thinking about first:

- **Blast radius.** `secret-command-guard.sh` sits on nearly every Bash call, and it
  **fails open** on a classifier error (`:146`) — the opposite direction from `git-guard.sh`.
  A false denial here is expensive; the existing `grep -o` carve-out was removed whole rather
  than narrowed (ADR 0039) precisely because this hook's precision matters.
- **False positives are real.** A path a user legitimately names in caps — a directory
  `ENV/`, a file `Credentials.json` in someone else's project — would start refusing.
- **The filesystem is the actual variable.** The gap exists because APFS is
  case-insensitive. On a case-sensitive volume `cat .ENV` reads a *different* file, and
  folding would invent a refusal. Whether to key the behavior on the filesystem, or fold
  unconditionally and accept the false positives, is a genuine design question.
- **The `Application Support` pattern is already unanchored** and so behaves differently
  from the other seven. Any change here must not silently widen it further.

## Sketch of the work — not a plan

- [ ] 1. Enumerate every pattern in `DOTFILE_PATTERNS` and state, per pattern, what folding
      it would newly block and what it would newly false-positive on. Derived by command,
      not from memory.
- [ ] 2. Decide the filesystem question above. This is a human call, not an implementer's.
- [ ] 3. Red tests first, with a lowercase control per group that genuinely refuses.
- [ ] 4. Whatever lands, add this shape to `secret-command-guard`'s Known-gaps table — it is
      not among the rows there today. (Do **not** copy a row count from `rules/gates.md`
      into that edit: the bullet there says "ten rows as of 2026-08-31" while a crude count
      of the card's own table lines returns a different number, and the card itself says to
      count from the artifact rather than trust the prose figure. Whoever does task 4 should
      count the rows in the card and, if the gates.md figure is wrong, fix it there too.)

## Out of scope

- The `argv[0]` program-name fold. Done: ADR 0041.
- `secret-command-guard.sh`'s fail-open on classifier error. Depended on, not changed.
- The other known gaps listed in `docs/features/secret-command-guard.md` (count them
  there; see task 4).
