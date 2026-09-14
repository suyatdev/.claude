# 0040 — The shared lexer applies bash's own word-initial comment rule, in a quote-aware pre-pass

- **Status:** Accepted (2026-08-31).
- **Context:** `hooks/lib/shell_segments.py` (`_lex()` only; `segments()`'s and
  `has_grouping()`'s contracts are unchanged) with `hooks/lib/shell_segments.test.py`
  written first. Amends **ADR 0013** (which established the shared lexer) and **ADR 0015**
  (which amended it for redirections); does not touch either's decisions. Five importers —
  `classify-git-command.py`, `classify-pr-command.py`, `classify-secret-command.py`,
  `classify-commit-command.py`, `secret_approval.py` — and through them eight Tier-1 hooks.
  Full measurement record: `docs/features/shell-lexer-comment-blindness.md`.
- **Note:** ADR number **0040** was confirmed free across **all 46 refs in this clone**
  (`git log --all --diff-filter=A -- docs/decisions/`, which walks every ref `git rev-parse
  --all` lists — 46, matching `git for-each-ref`). The same command lists `0036`–`0039`, so
  it is not blind. `0028` remains an unused gap and is left alone rather than backfilled.

## Context

`_lex()` lexes with `shlex(posix=True)`, whose default `commenters` is `#`. **`shlex` opens a
comment at an unquoted `#` anywhere in a word; bash opens one only where `#` begins a word.**
And because `_lex()` translates newline → `;` *before* lexing, by the time shlex applies its
comment rule there is no newline left for the comment to end at, so it discards to end of
**input** rather than end of line.

Two independent infidelities, both fail-**open**. Prefixing any blocked command with
`echo hi#; ` hides it from every guard that reads command text — measured end to end against
eight hooks, eight bypassed, in the feature card. It is the first known gap in this repo that
is *universal*: one input shape defeats every command guard at once, rather than one guard
having one blind spot.

This is a **momentum-guardrail failure, not a security-boundary breach** — every one of these
hooks already ships a documented one-flag bypass, and this ADR does not claim otherwise. What
changes is the effort: the sanctioned bypasses are named and logged, this one is nine
characters that leave no trace.

## Decision — implement bash's rule, rather than pick a `shlex` setting

The obvious repair, `lex.commenters = ""`, was probed and rejected. It does fix the exploit, but
it also stops stripping *genuine* comments, so `cat notes.txt  # remember to check .env` starts
producing `.env` as a token and `secret-command-guard.sh` blocks ordinary work. On a hook that
sits on **every** Bash call a false denial is expensive — it is precisely why `SECRET_EXEMPT`
had to be retrofitted to that guard after v1 shipped without a hatch (ADR 0039).

The alternative of "lex with `commenters=\"\"`, then re-scan the tokens" was rejected for a
harder reason: **shlex strips quotes**, so after lexing, `echo '#x'` and `echo #x` are the same
token list. The information the rule needs is destroyed before the re-scan can read it. A
derived parse cannot recover what its own producer discarded.

So: a **quote-aware pre-pass over the raw text**, then `commenters = ""`.

1. Join backslash-newline continuations (already done, and it must stay first).
2. Walk the raw string tracking single quotes, double quotes and backslash escapes. At an
   unquoted, unescaped `#` that **begins a word**, delete through the end of that **line** —
   not the end of input.
3. Lex the result with `commenters = ""`, everything else unchanged.

Ordering matters and is load-bearing: the pre-pass runs *before* the newline → `;`
translation, which is what restores end-of-line scoping for free.

### What "begins a word" means, measured rather than read

A `#` begins a word at start of input, after unquoted whitespace, or after one of `;` `&` `|`
`(`. Every row below is an execution in **both** `bash` and `zsh`, which agreed on all 15:

| after | comment? | | after | comment? |
|---|---|---|---|---|
| start of input | yes | | `$( … )`'s `)` | **no** |
| space / tab / newline | yes | | `${ … }`'s `}` | **no** |
| `;` `&&` `\|\|` `\|` `&` | yes | | a closing backtick | **no** |
| a subshell's `)` | yes | | `=` in an assignment | no |
| a subshell's `(` | yes | | a redirect target | no |

A backslash-escaped `#` is text (`echo \#notcomment` prints `#notcomment`), and a
backslash-escaped space does **not** end the word, so the `#` in `echo a\ # b` is text too.
Both measured; neither is obvious.

### The accepted deviation: closing `)` and `}` are not word breaks

The table above contains a genuine ambiguity. A `)` that closes a **subshell** ends the word,
so bash comments after it — but a `)` that closes **`$( )`** does not. Same character, opposite
answers, and the same split holds for `}` versus `${ }`. Separating them requires tracking
expansion nesting inside the pre-pass.

**Decision: exclude the closers from the word-break set and do not track expansions.** The
expansion forms are then read correctly, and the subshell form is read *wrongly in the
fail-closed direction* — the lexer reports a command bash would not have run, which produces a
possible false denial, never a hidden command. Measured:

```
(echo hi)# git commit -m x -- foo.sh
  today     [['echo','hi']]                                  # commit hidden — fail-OPEN
  candidate [['echo','hi'], ['#','git','commit',…]]           # commit seen  — fail-CLOSED
```

Expansion tracking was rejected on KISS grounds: it is meaningful machinery to buy fidelity on
a shape (`)` glued directly to `#`) that does not appear in real command traffic, and it would
have to get `$( )` nesting, `${ }` and backticks all right to be worth having. The deviation is
pinned from **both** sides in the suite — as an expected token list, and as an expected
*disagreement* with the shell in `check_bash_fidelity()` — so it cannot widen, or silently
reverse, without a test failing.

### Direction of every change — measured, and the first version of this claim was too strong

An earlier revision of this ADR said "on every input measured the new lexer emits the same
tokens or **more** — never fewer". That is a universal, and it is **false**. A differential
fuzz over **5,216 inputs** (`/tmp/judge_differential_fuzz.py`, built from guard-relevant
fragments) compares the set of segment `argv[0]`s — what a guard actually keys on — under both
lexers:

| | count |
|---|---|
| new lexer sees strictly more commands | 1,537 |
| identical | 3,149 |
| new lexer loses a head the old one saw | 530 |
| **of those, a head any guard keys on** | **0** |

All 530 are **one shape**, and the loss is always the same harmless token:

```
echo $'a\'#b'; git commit -m x -- foo.sh
   old  argv[0]s: ['echo']      new: []        lost: ['echo']
```

`$'…'` is bash's ANSI-C quoting, where a backslash escapes a quote **without** closing the
string. Neither shlex nor this pre-pass models that form, so the quote reads as closing one
character early, the command becomes unparseable, and `segments()` returns `[]` — the
pre-existing fail-open its own docstring documents. **The guarded `git commit` after the `;` is
invisible to both lexers**, so no protection changes hands; what is lost is a benign `echo`
head. Found by the observability judge in round 1 by direct attack, then reproduced and scoped
here.

The claim that survives measurement is therefore the narrower one: **in that population, no
guarded command that the old lexer surfaced is lost, and 1,537 inputs surface one the old lexer
hid.** It is scoped to the population — the first fuzz run, whose case list had no `$'…'`
prefix, reported 0 losses and was wrong in exactly the way a clean number is most convincing.
The shape is pinned as a case in the suite and disclosed as a Known-gaps row in
`docs/features/secret-command-guard.md`.

A third run (5,984 cases, seeded with `$(( ))`, `<( )` and hex/octal `$'…'` forms at the
judge's suggestion) raises the raw loss count to 582 and leaves the guarded-head count at
**0**. It also shows the raw count is the wrong metric: 188 of those "losses" are the bare
`1` from `$((1#2))`, bash's arithmetic *base* notation, which the old lexer produced only by
commenting mid-token — and in all 188 the new lexer additionally surfaces guarded commands the
old one hid. Per-run figures and the partition: `docs/features/shell-lexer-comment-blindness.md`.

## Consequences

- Eight Tier-1 hooks stop being bypassable by `echo hi#; `. That is the point of the change.
- Five importers see a token stream that can now be longer for inputs containing `#`. Every one
  of their suites is re-run with before/after counts recorded (task 6 of the card). **A changed
  count is a finding to explain, not automatically a regression.**
- The Known-gaps row for this shape leaves `docs/features/secret-command-guard.md`, and that
  table's counts are corrected individually — never by blanket regex, so historical caveats
  keep their original scope.
- **Heredoc bodies are still not understood.** shlex cannot see a heredoc at all (a pre-existing
  limit recorded in ADR 0012), so a `#` in a body line is stripped as if it were a comment.
  Today's lexer strips more — it eats the rest of the input including the terminator — so this
  is strictly an improvement, not a new limit, but it is not fidelity and is recorded as such.
- The suite gains an oracle anchored **outside** this repo: `check_bash_fidelity()` executes
  every shape in real `bash` and real `zsh` and holds the lexer to what the shell did. A missing
  shell is reported as a failure rather than skipped, and the harness asserts its own table
  discriminates in both directions — a check that quietly declines to run is indistinguishable
  from one that passes.

## What this ADR does not claim

- Not a security fix. See the guardrail paragraph above.
- The eight-hook bypass was measured against **scratch repositories** built to trip each guard's
  precondition, so the rows measure the guards' decisions, not how often those preconditions
  arise in real traffic.
- No measurement exists of how often a legitimate trailing `#` comment appears in this repo's
  real command traffic, so the false-positive cost avoided by rejecting bare `commenters=""` is
  argued from the shape of the rule, not quantified.
