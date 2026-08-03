# ADR 0013 — One shared shell-segment lexer for all command-inspecting guards

**Status:** Accepted (2026-08-03)

Amends ADR 0012, which remains Accepted. Every decision recorded there still holds; only
the *location* of the lexer it describes has changed, and this record exists so a reader
following ADR 0012's file references does not land on the wrong file.

## Context

`git-guard.sh` and `doc-guard.sh` each decided whether a Bash command ran `git commit`
(and, in git-guard, `git push`) with a regex anchored to the **start** of the command
string. Anything chained — `git add -- x && git commit -m y`, the shape this repo uses
constantly — never matched, so the guard body never executed and the hook exited 0 without
having evaluated anything. Commit `6046565` reached `main` past an allowlist that forbids
it; the guard had fail-opened rather than permitted it.

ADR 0012 had already solved this class for `judge-guard.sh` by lexing the command into
shell segments with `shlex`, and recorded the shapes deliberately left open (`eval "…"`,
`env`/`timeout` wrappers, backticks, heredocs, variable indirection). That work lived
inside `hooks/lib/classify-pr-command.py`, coupled to the single question "does this run
`gh pr create`?".

So the same class of bug was solved in one guard and live in two others, with the remedy
sitting a directory away.

## Options weighed

1. **Fix the two regexes in place** — smallest diff. Rejected: it re-derives, in shell,
   the quoting and operator handling `shlex` already does correctly, and produces a third
   and fourth independent answer to "what commands does this line run". The four would
   drift, and only one of them would have tests.
2. **Extract the generic half into a shared module (chosen)** — `hooks/lib/shell_segments.py`
   provides `segments(src)`; `classify-pr-command.py` and the new
   `classify-git-command.py` both consume it.
3. **One classifier answering every guard's question** — a single script returning facts
   for `gh`, `git`, and future callers. Rejected as premature: it couples unrelated guards'
   release cycles, and the shared surface that actually repeats is the *lexing*, not the
   matching.

## Decision

The lexer moves to `hooks/lib/shell_segments.py`. `classify-pr-command.py` keeps its public
`classify()` and re-exports `WRAPPERS`; a new `classify-git-command.py` reports which git
operations a command really runs. All lexing rationale and accepted limits move with the
code and are now documented in `shell_segments.py`.

Flags are judged **within the segment that owns them**, which the previous whole-string
substring searches did not do. That closed two further defects nobody had reported:
`git push --force && echo --force-with-lease` was *allowed* (a lease anywhere excused a
bare force anywhere), and `git push && echo --force` was *blocked*.

`classify-pr-command.test.py` was not edited and stayed 51/51 green throughout, serving as
the regression baseline that the extraction preserved behaviour. A later independent check
fuzzed 24,016 command strings through the old and new implementations with zero
divergences.

## Consequences

- **ADR 0012's file references are stale.** Its decisions stand unchanged; where it says the
  lexer lives in `classify-pr-command.py`, read `shell_segments.py`. `rules/gates.md` points
  at both records.
- **One shared file is now a dependency of three live Tier 1 hooks.** `git-guard.sh` fails
  **closed** if it cannot run the classifier, and it runs on every Bash call — so an
  unreadable `shell_segments.py` blocks every Bash command until it is restored. This is the
  correct direction for a guard against destructive action, and the error names the file, but
  it is a real cliff. `doc-guard.sh` fails **open** on the identical condition, because a
  missing note is not worth blocking work over. Both directions are now pinned by tests
  (`git-guard.test.sh`, `doc-guard.test.sh`); before this change they existed only in comments.
- **Accepted limits are inherited, not re-litigated.** Option *values* are not tracked, so a
  commit whose message is literally `-a` is read as `--all`. git accepts any unambiguous
  prefix of a long option (`--amen` == `--amend`), so modelling that grammar is unbounded.
  The error direction is safe — doc-guard inspects more, never less.
- **`merge-guard.sh` still does not lex**, and remains the one guard where a chained
  `foo && gh pr merge` is not caught. Routing it through this module is open work, not a
  decision taken here.
- Neither hook had any test suite before this change; both now do.
