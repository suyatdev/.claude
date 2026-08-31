---
phase: implementation
model_tier: high
branch: fix/shell-lexer-comment-blindness
---

# An unquoted `#` truncates the shared lexer, blinding every Tier-1 command guard

Queued 2026-08-30 at the user's request, out of task 13 on
`docs/features/output-secret-redaction.md`. Discovered while fixing the SECRET_EXEMPT
approval id; **not introduced by that work, and deliberately not fixed there** — the
defect is in `hooks/lib/shell_segments.py`, which four guards share, so it is its own
change with its own tests.

Gate: **confirmed 2026-08-31.** Branch `fix/shell-lexer-comment-blindness`, based on
`origin/main` @ `e9a4118` (the merge of PR #89).

## Why this matters

Every Tier-1 command guard in this repo asks the same question — "does some segment of
this command really run `git commit` / `git push --force` / `gh pr create` / `gh pr
merge`, or name a secret-bearing file?" — and they all ask it of
`shell_segments.segments()`. That function lexes with `shlex(posix=True)`, whose
default `commenters` is `#`.

**`shlex` treats an unquoted `#` as starting a comment anywhere in a word. Bash does
not — bash starts a comment only where `#` begins a word.** So a command whose first
word merely *ends* in `#` is silently cut in half: the shell runs both halves, and
every guard sees only the harmless first one.

Prefixing any blocked command with `echo hi#; ` defeats it.

## Measured, not inferred

**Re-measured 2026-08-31** (task 1 and task 2) against
`fix/shell-lexer-comment-blindness` @ `e9a4118` — `origin/main` after PR #89 merged —
with the probe scripts named in Verification. The inherited 2026-08-30 figures against
`feat/output-secret-redaction` @ `3b7f44c` reproduced exactly; every row below is the
new run, not the old one. **Every case is paired with a plain control that the classifier does
detect and a quoted-`#` control that behaves like the plain form** — without those, a
`NO` verdict cannot be told apart from a blind probe. (Two earlier probe revisions
*were* blind: one passed the command in `argv` to a classifier that reads `stdin`, the
other tested `gh pr merge` against a classifier whose default pair is `("pr",
"create")`. Both returned a plausible, wrong `NO` for every row including the control.
That is why the control column exists.)

### The lexer

| Input | `_lex()` output |
|---|---|
| `cat ~/.zshrc` | `['cat', '~/.zshrc']` |
| `echo hi#; cat ~/.zshrc` | `['echo', 'hi']` |
| `echo 'hi#'; cat ~/.zshrc` (quoted control) | `['echo', 'hi#', ';', 'cat', '~/.zshrc']` |

### The shells really do run the discarded half

`bash -c "echo FIRST#; echo SECOND_RAN"` → `FIRST#\nSECOND_RAN\n`, exit 0.
`zsh -c` — identical. Control: `echo FIRST # ; echo SECOND_RAN` → `FIRST\n` only,
confirming a *word-initial* `#` is a genuine comment in both shells and that the probe
can distinguish the two cases.

### Every classifier (task 1)

| Guard | Classifier | Plain (control) | Quoted-`#` (control) | `echo hi#; ` prefixed | Negative control |
|---|---|---|---|---|---|
| secret-command-guard | `classify-secret-command.py` | exit 2 **blocked** | exit 2 **blocked** | exit 0 🔴 **allowed** | exit 0 allowed |
| judge-guard | `classify-pr-command.py` `("pr","create")` | `PR` | `PR` | `NO` 🔴 | `NO` |
| merge-guard | `classify-pr-command.py` `("pr","merge")` | `PR` | `PR` | `NO` 🔴 | `NO` |
| git-guard (force push) | `classify-git-command.py` | `["PUSH","PUSH_FORCE"]` | same | `[]` 🔴 | `[]` |
| git-guard / doc-guard / test-marker-guard (commit) | `classify-git-command.py` | `["COMMIT"]` | same | `[]` 🔴 | `[]` |

The negative-control column is new. Without it a `NO` from the exploit row is
indistinguishable from a probe that detects nothing at all.

### Every guard, end to end (task 2)

The rows above exercise the shared classifiers. These run the **hook scripts
themselves**, with a real payload on stdin and a scratch repo staged to trip each
guard's own precondition. Same four columns.

| Hook | Plain (control) | Quoted-`#` (control) | `echo hi#; ` prefixed | Negative control |
|---|---|---|---|---|
| `secret-command-guard.sh` | exit 2 **blocked** | exit 2 **blocked** | exit 0 🔴 **allowed** | exit 0 allowed |
| `git-guard.sh` (force push) | exit 2 **blocked** | exit 2 **blocked** | exit 0 🔴 | exit 0 |
| `merge-guard.sh` | exit 2 **blocked** | exit 2 **blocked** | exit 0 🔴 | exit 0 |
| `judge-guard.sh` | exit 2 **blocked** | exit 2 **blocked** | exit 0 🔴 | exit 0 |
| `doc-guard.sh` | exit 2 **blocked** | exit 2 **blocked** | exit 0 🔴 | exit 0 |
| `feature-sync-guard.sh` | exit 2 **blocked** | exit 2 **blocked** | exit 0 🔴 | exit 0 |
| `worktree-guard.sh` (`WORKTREE_GUARD_MODE=deny`) | exit 2 **blocked** | exit 2 **blocked** | exit 0 🔴 | exit 0 |
| `decide-commit-gate.py` (test-marker-guard's entry) | `BLOCK` | `BLOCK` | `ALLOW` 🔴 | `ALLOW` |

**Eight for eight.** Every guard that reads command text is bypassed by the same nine
characters, and the earlier inference for `doc-guard` and `test-marker-guard` was
correct — now measured rather than assumed.

Two rows read *clean* on the first run of this probe and were **wrong**, in the
probe rather than the guard; the self-check caught both because the plain control
matched the negative control:

- `worktree-guard.sh` was fed `git commit`, which it does not guard. It keys on
  `SEG_BRANCH_MOVE` / `SEG_WORKTREE_ADD` (`git switch` and friends), never on commit.
- `decide-commit-gate.py` was run in a repo with no subject/test sibling pair, so
  `_form_pairs()` found nothing and it allowed for a reason unrelated to the lexer.

That is what the control columns are for, and it is the second time on this card that
a probe returned a plausible, wrong verdict.

### `phase-guard.sh` is not affected — measured, not assumed

`phase-guard.sh` is registered on `Edit|Write|NotebookEdit` only, so it never receives
command text and the `#` shape cannot reach it. Fed a `Bash` payload directly it exits
`0` for both the plain and the prefixed form — it is declining to handle the event, not
failing to see the exploit. It is the one guard in the repo that this defect cannot
touch.

## Scope of the claim

This is a **momentum-guardrail failure, not a security-boundary breach.** The house
rules already class these hooks as guardrails against accidents, and every one of them
already carries a documented one-flag bypass. This card does not claim otherwise, and
no text written for it may. What it does change is the *effort* required: the existing
bypasses are named, logged and deliberate, while this one is nine invisible characters
that leave no trace anywhere.

It is also, unlike the other known gaps, **universal** — one input shape defeats all
four guards at once, rather than one guard having one blind spot.

## The design question — do NOT assume the one-line fix

The obvious repair is `lex.commenters = ""` in `_lex()`. Probed, and it is **not
correct as-is**:

| Input | current | `commenters=""` | bash's actual reading |
|---|---|---|---|
| `echo hi#; cat ~/.zshrc` | `['echo','hi']` | `['echo','hi#',';','cat','~/.zshrc']` | ✅ matches candidate |
| `git commit -m fix#123` | `['git','commit','-m','fix']` | `['git','commit','-m','fix#123']` | ✅ matches candidate |
| `echo a # a real comment` | `['echo','a']` | `['echo','a','#','a','real','comment']` | ❌ **both wrong** — bash stops at `#` |
| `# leading comment only` | `[]` | `['#','leading','comment','only']` | ❌ candidate wrong |

So `commenters=""` swaps one infidelity for another. The new one fails **closed**
(more tokens ⇒ more matches ⇒ more refusals), which is the safer direction, but it is
still wrong and it will produce false positives: a trailing comment mentioning a
guarded word — `cat notes.txt  # remember to check .env` — would begin to block
ordinary work. On a guard that sits on every Bash call, a false positive is expensive;
that is the whole reason `SECRET_EXEMPT` had to be added to
`secret-command-guard.sh` after v1 shipped without a hatch.

**The rule to implement is bash's own: `#` begins a comment only when it begins a
word** (start of input, or preceded by unquoted whitespace or a control operator).
Neither `shlex` setting expresses that, so this needs a deliberate approach — a
pre-pass over the raw text, a `commenters=""` lex plus a token-level re-scan, or a
narrow custom reader. Choosing between them is planning work, not a foregone
conclusion, and the choice must be justified in an ADR because four guards depend on
the outcome.

## Blast radius — why this is not a one-line drive-by

**Corrected 2026-08-31 — the original list was short by two.** Enumerated with
`grep -l` over `hooks/` rather than from memory:

`shell_segments.py` is imported by `classify-git-command.py`,
`classify-pr-command.py`, `classify-secret-command.py`, `classify-commit-command.py`
and `secret_approval.py`, and is therefore load-bearing for `git-guard.sh`,
`doc-guard.sh`, `merge-guard.sh`, `judge-guard.sh`, `test-marker-guard.sh`,
`secret-command-guard.sh`, `worktree-guard.sh` and **`feature-sync-guard.sh`**.

Two corrections to the original text:

- **`feature-sync-guard.sh` was missing entirely.** It is a Tier-1 blocking hook that
  reads `classify-git-command`, and it is bypassed like the rest (measured above).
- **`test-marker-guard.sh` does not read `classify-git-command`.** It reaches the lexer
  through `lib/decide-commit-gate.py` → `lib/classify-commit-command.py` →
  `shell_segments`, a chain the card did not name. `classify-commit-command.py` is
  therefore a fifth importer that has to be re-run in task 6. Any change to
the token stream can move a verdict in either direction for all of them. Every one of
those suites must be run, and the fix's own tests must include the false-positive
cases above, not only the exploit shapes.

## Tasks (none may start before `gate confirmed`)

- [x] 1. Re-measure the table above on the then-current HEAD; a card's inherited
      numbers are not evidence. Keep the control columns. — done 2026-08-31 against
      `e9a4118`; inherited figures reproduced exactly, negative-control column added.
- [x] 2. Extend the measurement to the two guards this card did not test —
      `worktree-guard.sh` and `phase-guard.sh` — and to `doc-guard.sh` /
      `test-marker-guard.sh` end-to-end rather than via their shared classifier.
      — done 2026-08-31. Eight hooks run end-to-end, all eight bypassed except
      `phase-guard.sh`, which has no command surface. Turned up two consumers the
      Blast-radius section had wrong; see above.
- [ ] 3. Write the failing tests first, in `hooks/lib/shell_segments.test.py`:
      the exploit shapes, the word-initial-comment cases that must still be
      stripped, and the false-positive cases that must NOT begin blocking.
- [ ] 4. Decide the approach and write the ADR before implementing. Re-fetch
      `origin` and re-check the next free ADR number against the deciding ref,
      not stale local `main`.
- [ ] 5. Implement the word-initial rule in `_lex()`.
- [ ] 6. Run all six dependent guard suites and record before/after counts for
      each. A changed count is a finding to explain, not automatically a
      regression.
- [ ] 7. Remove the corresponding Known-gaps row from
      `docs/features/secret-command-guard.md` and correct every count of that
      table — individually, never by blanket regex, so historical caveats keep
      their original scope.
- [ ] 8. Re-run the `secret_approval` end-to-end approval test: the approval id
      hashes raw text and so is independent of this change, but "independent" is
      a claim, and it should be measured rather than assumed.

## Not verified

- ~~`worktree-guard.sh` and `phase-guard.sh` were not probed at all.~~ **Closed by
  task 2** — both measured; `worktree-guard.sh` is bypassed, `phase-guard.sh` cannot be
  reached by this shape.
- ~~`doc-guard.sh` and `test-marker-guard.sh` were inferred from the shared classifier.~~
  **Closed by task 2** — both run end-to-end, both bypassed.
- The end-to-end rows were produced against **scratch repositories** built to trip each
  guard's precondition, not against this repo's real state. That is what makes the plain
  control block at all; it also means the rows measure the guards' *decisions*, not how
  often those preconditions arise in real traffic.
- `worktree-guard.sh` was measured with `WORKTREE_GUARD_MODE=deny` forced on. It ships in
  `log` mode, where it blocks nothing and the bypass is moot.
- Only `echo hi#; ` was probed as the hiding prefix. Whether other word-final `#`
  shapes behave identically is expected but unmeasured.
- No measurement of how often a legitimate trailing `#` comment appears in this
  repo's real command traffic, so the false-positive cost of `commenters=""` is
  argued, not quantified.
- The candidate-fix table compares two `shlex` configurations against a *stated*
  reading of bash's rule. Only the two `echo FIRST#` / `echo FIRST # ` cases were
  executed against real `bash` and `zsh`; the other rows' "bash's actual reading"
  column is reasoning, not execution.

## Verification

Probe scripts, 2026-08-30, against `3b7f44c`:

- `/tmp/scg_probe_hash.py` — lexer view and `classify-secret-command.py` verdicts.
- `/tmp/scg_probe_controls.py` — `classify-pr-command.py` for both subcommand
  pairs, via direct import, with plain and quoted-`#` controls. **Its first two
  revisions were blind and are the reason the control columns are mandatory.**
- `/tmp/scg_probe_git.py` — `classify-git-command.py`, same control structure.
- `/tmp/scg_probe_fix.py` — the `commenters=""` candidate against ten inputs.

These live in `/tmp` and did not survive into this branch. Task 1 re-measured
rather than citing them.

Probe scripts, 2026-08-31, against `e9a4118`:

- `/tmp/task1_probe.py` — task 1. Lexer view, all five classifiers, plain +
  quoted-`#` + exploit + negative controls, and the `bash`/`zsh` execution check.
  Prints a self-check line that names any row whose controls misbehaved.
- `/tmp/task2_probe.py` — task 2. The eight hook scripts end-to-end over three
  scratch repositories (`/tmp/task2_repo_doc`, `_sync`, `_marker`), plus the
  `phase-guard.sh` no-command-surface check. Same self-check; it is what caught the
  two blind rows described above.

These also live in `/tmp`. Task 6 re-runs the real suites, which do persist.
