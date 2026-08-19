# 0029 — Global options sort into three buckets, and "cannot tell" asks rather than allows or denies

- **Status:** Accepted
- **Date:** 2026-08-18
- **Context:** `hooks/lib/classify-git-command.py`, `hooks/git-guard.sh`, `hooks/doc-guard.sh`,
  `hooks/merge-guard.sh`, `hooks/lib/classify-pr-command.py`. Joins the guard-hook lineage of ADRs
  0012 (shared `gh` reader), 0013 (shared shell-segment lexer), 0014 (empty index means ask the
  *command*, a different mechanism — see Context below), 0015 (redirections are part of a command)
  and 0026 (`symbolic-ref` names the branch). Full derivation, the measured git 2.50.1 grammar, the
  bucket-assignment table, and the full Gherkin scenario set: `docs/features/global-option-blindness.md`.

## Context

`classify-git-command.py` read a git command's subcommand as `argv[1]`, unconditionally. Any global
option ahead of it — `git --no-pager commit`, `git -C /other/repo commit`, an abbreviation like
`--work-tre`, anything git itself accepts before the subcommand — pushed the real subcommand out of
that position. The classifier saw an unrecognised token, resolved no subcommand, and reported no
facts at all. `git-guard.sh`, `doc-guard.sh`, and `merge-guard.sh` all read this classifier's output
to decide whether to intervene; all three were blind to exactly the same class of command, silently.

Fixing this required answering a harder question than "parse past the global options": **which
global options are safe to skip, and what happens to the ones that aren't?** Git accepts dozens of
global options, several take a value, one (`--attr-source`) consumes the next token in a way that
can swallow the subcommand itself if misclassified, and the language keeps growing — `git --help`'s
own synopsis is not even the complete list (`--attr-source` and `--list-cmds` are documented only in
`man git`, found by diffing the manual page against the synopsis, not by reading either alone).

## The three-bucket rule

Every global option a segment carries ahead of its subcommand sorts into exactly one bucket,
decided by what the option can do to the *target* of the command — not by how it looks:

1. **Skip it.** The option cannot change which repository is inspected or widen what a pathspec
   covers. Read the subcommand normally once it's skipped. Membership is a fixed, exhaustively
   enumerated table (`GLOBAL_SKIP_NO_VALUE`, `GLOBAL_SKIP_CONSUMING`) — every member has a test,
   because bucket 1 is the only bucket whose mistakes are silent. Two sub-shapes: options that
   consume no following token (`--no-pager`, `--version`, …) and the one that does
   (`--attr-source`, measured to swallow the next token including a literal `commit`).
2. **Refuse and ask — known to redirect.** `-C`, `--git-dir`, `--work-tree`, `--namespace`,
   `--bare`, `-c`, `--config-env`, and the four pathspec-modifying options. These can point git at
   a different repository, or change what a pathspec *means* — which is the string `git-guard`'s
   documentation-only exemption is decided from. Enumerated explicitly, even though bucket 2 and
   bucket 3 produce the identical fact and decision (see Consequences) — the enumeration documents
   *why* each one is dangerous, which the catch-all alone cannot say.
3. **Refuse and ask — unrecognised.** Anything else starting with `-` before the subcommand,
   including an abbreviation nobody enumerated (git honours unambiguous prefixes, so a list of
   exact spellings can never be complete). "Cannot tell" must not mean "allow" — the same reasoning
   `COMMIT_SAFE_FLAGS` already used for unrecognised `commit` flags, extended to the global-option
   position.

## Why "cannot tell" asks, not allows or denies

| Option | Verdict | Why |
|---|---|---|
| **Allow on cannot-tell** (silent, today's bug) | Rejected | This is the defect the feature exists to fix. A guard that reports confidently on the wrong repository or the wrong branch is worse than today's visible hole — it looks like protection while providing none. |
| **Hard deny on cannot-tell** | Rejected | Bucket 2 deliberately includes options that are *usually* harmless — `git -c user.name=x commit` is plainly benign, and `-c` is there only because it *can* set `core.worktree` and thereby redirect the target. A hard, silent-only block on every bucket-2/3 option would make ordinary config overrides and any future git option permanently unusable from a session, for a guard that is a momentum guardrail, not a security boundary. |
| **Ask (chosen)** | **Accepted** | Refusing outright and refusing-by-asking cost differently. Over-refusing an `ask` costs one keystroke; under-refusing an `allow` is a silent hole. That asymmetry is what makes bucket 2's conservatism (including options that are usually fine) affordable — **and it only holds while the refusal is an `ask`.** If this mechanism is ever weakened to a hard `deny`, bucket 2's membership needs to be revisited with a narrower, stricter list; the two decisions are coupled. |

This is the first hook in this repo to use `permissionDecision:"ask"` (confirmed against the
installed binary, not the docs site, which omits it — the validation error `Valid types are: allow,
deny, ask, defer` is the authoritative source). `ask` is a different mechanism from ADR 0014's
"an empty index means ask the *command*" — that ADR asks the command line a question by reading its
own pathspec; this one asks the *human*, via an interactive permission prompt. The two should not be
conflated even though both use the word "ask".

## Consequences

- **Bucket 1 carries the exhaustiveness burden, and it is paid, not deferred.** Every skip-list
  member has its own test case (`classify-git-command.test.py`, task 1) — **17** members across the
  harmless (8) and print-and-exit (9) tables, which occupy **18** Examples rows because
  `--list-cmds` is exercised in both its bare and `=<group>` spellings, plus `--attr-source`'s two
  standalone scenarios. 17 + `--attr-source` is the whole of bucket 1: `len(GLOBAL_SKIP_NO_VALUE)`
  + `len(GLOBAL_SKIP_CONSUMING)` = 18, the number to re-derive rather than copy. An option
  named in the bucket-1 prose with no scenario behind it is treated as a defect, not a shorthand —
  this caught real drift three times during the feature's own revisions (the pathspec options and
  `--list-cmds` each briefly fell out of every Examples table while still being claimed in prose).
- **A future git version is safe by construction, not by maintenance.** Bucket 3's catch-all means
  a new global option this list has never seen lands in `ask`, never in `allow`. The list will go
  stale; the failure mode of staleness is an occasional extra prompt, not a silent gap. The
  compliance judge confirmed this framing during the feature's own review.
- **Bucket 2 and bucket 3 are decision-equivalent today, but that equivalence is not structurally
  enforced.** Both return the identical `SCOPE_UNKNOWN<tab><option>` fact and the identical `ask`
  decision; `GLOBAL_REDIRECT`'s explicit table exists for documentation and traceability, not
  because the code branches on it. A future change that wants bucket 2 and bucket 3 to diverge
  (e.g. a different message, or only one of them prompting) will need to add that branch, not
  assume it already exists.
- **Bucket 1's own false-denial edge case is accepted, not solved.** Several no-value options print
  and exit rather than reaching the subcommand at all (`git --version commit -m x` commits nothing,
  in reality) — after skipping the option the classifier still reports a `COMMIT` fact and
  `git-guard` still refuses, on a command that would never have run. Accepted: the fail direction is
  toward blocking, and modelling "which options suppress the subcommand" would be a fourth list that
  rots the same way the others would. What *is* fixed is the lie: `PRINTS_AND_EXITS` is a
  message-only set, proven decision-independent by a hand-run mutation round (emptying it reproduced
  the pre-fix red baseline number-for-number; restoring it cleanly `diff`'d against the pre-mutation
  copy) — the refusal still fires, but it now says the command carries an option that prints and
  exits, not that it targeted `main`.
- **The `ask` mechanism itself was unverified until a human confirmed it.** No automated test can
  raise a real interactive prompt or observe a human declining one. Verified by hand, once, against
  the actual launch mode this repo's sessions use (`--allow-dangerously-skip-permissions`) — full
  transcript in the feature file's own Verification section — because asserting it passed would have
  been exactly the false certainty `core-conduct.md`'s verification rule exists to prevent.
