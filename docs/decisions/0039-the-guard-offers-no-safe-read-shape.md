# 0039 — The secret-command guard offers no safe read shape, and gains the escape hatch it said it did not need

- **Status:** Accepted (2026-08-28).
- **Context:** `hooks/secret-command-guard.sh` (new) and
  `hooks/lib/classify-secret-command.py` (new), registered `PreToolUse`/`Bash` in
  `settings.json`; `hooks/scan-secrets.sh` registered `PreToolUse`/`Edit|Write|NotebookEdit`
  with `hooks/scan-secrets.test.sh` (new, 17 cases) written first; `rules/gates.md`.
  Full scope, the Known-gaps table and the verification record:
  `docs/features/secret-command-guard.md`. Fifth consumer of the shared shell-segment
  lexer established by **ADR 0013** and amended by **ADR 0015**; `segments()`'s contract is
  unchanged. Fail-open direction is the deliberate inverse of the fail-closed machinery in
  **ADR 0012**'s `judge-guard.sh`, for the reason given below.
- **Note:** ADR number **0039** was confirmed free at the moment of writing against **every
  local and remote ref** (34 scanned, a per-ref `git ls-tree` loop), not a local `ls` and not
  local `main`, which is a stale ancestor 161 commits behind `origin/main` in this worktree.
  The same loop finds `0038` on 8 refs, so it is not blind. `0028` remains an unused gap and
  is left alone rather than backfilled out of order.

## Context

On 2026-08-27 a single Claude session printed real secrets from `~/.terminal_aliases` into its
own transcript twice: once from a diagnostic script whose output carried a subprocess's full
inherited environment, once from `grep -n "export "` on the dotfile, which echoed complete
`export VAR="value"` lines. `rules/core-conduct.md` already forbade this. Prose did not stop it,
and a `PostToolUse` hook cannot retract output the model has already read — so the guard had to
sit at `PreToolUse`, judging command text before it runs.

v1 shipped with two decisions that this ADR reverses. Both were made in good faith, both were
falsified by measurement within a day, and the shape of the error is the point.

## Decision 1 — there is no permitted read shape

v1 blocked any command naming a secret-bearing path **unless** every mention sat inside a
`grep`/`egrep`/`fgrep` call carrying an `-o`-family flag. The reasoning: `-o` prints only the
substring the pattern matched, not the file's raw line, so a value cannot ride along.

The observability judge scored `success_masking = fail` and the reasoning is wrong in one step:
**the caller supplies the pattern.** Reproduced directly against the classifier:

```
$ grep -o 'export .*' <dotfile>
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMIK7MDENG"     ← classifier said ALLOW
```

That is the original incident, verbatim, through the one door the guard held open. A second
defect rode along: the flag test accepted **any** single-dash token containing an `o`, so
`grep -e -notes .env` satisfied it with no `-o` anywhere — `-notes` there is grep's *pattern*.

Twenty-three passing tests never noticed, because every one of them supplied a narrow pattern.
The suite asserted that the mechanism worked; it never asked whether the mechanism was the right
one. A test written from the same assumption as the code cannot falsify that assumption.

**Decided: remove the carve-out whole.** Every mention of a secret-bearing path blocks; no read
shape through Bash is permitted.

A bounded-pattern variant — allow `-o` only when the pattern contains no unbounded wildcard —
was considered and **rejected**. It narrows the hole rather than closing it (`grep -o
'[A-Za-z0-9/+=]\{20,\}'` still extracts the value), and it buys that partial result with a new
pattern mini-language to specify, implement and keep correct. The simpler rule is also the
stronger one, which is the rare case where KISS and security agree; where they had not, the
security answer would still have won here.

The cost is real and accepted: reading one variable out of a dotfile is now a `SECRET_EXEMPT`
command, not a clever `grep`. The Read tool is unaffected — this hook only sees `Bash`.

The deny message changed with the code, and this is not cosmetic. It previously advised "read
the specific value with a narrower tool (e.g. `grep -o` capturing only the value, never the
whole line)" — the guard was *prescribing the command that leaked*. A refusal that recommends a
workaround is only as safe as the workaround. It now names no read shape at all.

## Decision 2 — the escape hatch v1 argued against

v1 shipped no bypass variable, deliberately, on the reasoning that the hook "only fires on the
two narrow, already-incident shapes, not on ordinary work, so there is no legitimate case that
needs an escape hatch." That premise was measurable, was not measured, and is false. The dotenv
pattern `(^|/)\.env(\.[^/]*)?$` also blocked:

```
git add .env.example                       docker compose --env-file .env up
cat .env.template                          vim .env.sample
```

`.env.example` and its siblings are conventionally committed and never hold a real value.

**Decided, both parts:** exempt `.env.example` / `.env.template` / `.env.sample` from the dotenv
pattern, *and* add `SECRET_EXEMPT=<reason>` (non-empty, logged), matching `MERGE_EXEMPT`,
`TEST_EXEMPT`, `JUDGE_EXEMPT` and `WORKTREE_EXEMPT` elsewhere in this repo. The exemption is
checked before either block shape, so one flag clears both. It is read from a segment's leading
assignment through the shared lexer, so it composes with chaining the way the other guards do.

The general lesson, and the reason this is an ADR rather than a commit message: **"it will not
fire on ordinary work" is a measurement, not an argument.** Consistency with the family's
existing hatches would have produced the right answer without measuring anything.

## Decision 3 — this fails OPEN, and the inverse hook shipped the same day

`secret-command-guard.sh` allows on a missing `python3`, an unparseable payload, or any internal
classifier error. That is the opposite of `judge-guard.sh` (ADR 0012) and of `scan-secrets.sh`,
registered in the same commit.

The asymmetry is intentional and turns on blast radius. `secret-command-guard` sits on the `Bash`
matcher: a broken classifier failing closed would be a machine-wide ban on using the shell, in
every session, until someone noticed. `scan-secrets` guards a single write, where failing closed
costs one blocked edit. A guard's failure direction should follow what its failure costs, not a
house style.

The honest consequence, written here because the deny message must not imply otherwise: this is a
**momentum guardrail, not a security boundary.** The card's Known-gaps table records seven measured
`ALLOW` shapes — variable indirection (`F=~/.zshrc; cat "$F"`), a path built by expansion,
`export -p` / `declare -p` / `set` / `env -0` / `ps eww`, a secrets file not named `.env`
(`config/prod.env`), the compound-token boundary described below, and any read performed inside a
script file. That last one matters most: **leak #1's original form was a script, so the hook does
not block the shape of the first incident** — only its bare `env` / `os.environ` cousins. Widening
the environment-dump check was offered and declined (user, 2026-08-28): bare `set` is common enough
that blocking it was judged worse than the residual risk.

One boundary deserves naming in full, because this ADR's own wording above ("every mention blocks",
"no permitted read shape") is stronger than the mechanism. The patterns anchor at **both** ends —
`(^|/)` before the name, `$` after — so the operative rule is **"the path is a whole *trailing
component* of a lexed token"**. An interpreter or remote string is one token, so `bash -c "cat
~/.zshrc"` blocks, and it fails in both directions:

```
2  bash -c "cat ~/.zshrc"                              blocks
0  bash -c "cat ~/.zshrc | head -5"                    ALLOWS — token no longer ends at the name
0  ssh host "cat ~/.zshrc; true"                       ALLOWS — same
0  python3 -c "print(open('/Users/m/.zshrc').read())"  ALLOWS — same
0  cat foo.zshrc                                       ALLOWS — no `/` before the name
2  cat ./foo/.zshrc                                    blocks — a real component
```

The last two are why "suffix" is the wrong word and is not used here: an earlier revision of this
paragraph said suffix, which described a guard wider than the one that exists.

Found by the observability judge in round 2 and reproduced. It is **pre-existing** — the carve-out
removal neither caused nor widened it — and it is now pinned by `ALLOW` assertions beside the
others, so the strong wording and its boundary travel together.

Each gap is pinned by an `ALLOW` assertion in the suite. They are not endorsements — they make
widening the guard a deliberate edit to a named block, so the card's promises cannot drift away
from the code silently.

## Decision 4 — write the missing suite before arming the dormant hook

`rules/gates.md` listed `scan-secrets.sh` among four dormant hooks that "all exist and pass their
tests". A repo-wide search established it had **no test suite anywhere**; `git log --all` shows
`hooks/scan-secrets.test.sh` has exactly one commit, this branch's. The bullet was asserting a
green run that had never happened.

Arming an untested, fail-closed, repo-wide hook on the strength of that sentence was refused. The
17-case suite was written first, then the hook registered, then the bullet corrected. The feature
card had inherited the same false sentence and is corrected here too — a claim does not stop being
false because it is quoted somewhere new.

## Consequences

- Reading a secret-bearing file through `Bash` requires `SECRET_EXEMPT=<reason>`, logged. The Read
  tool is untouched.
- One flag defeats the guard. That is the accepted design, not an oversight: it raises the floor on
  accidents, which is the whole threat model.
- The suite is 48 assertions (34 pre-existing behaviours, 14 new), and went red-then-green in the
  amending session — 14 failures, then 0 — so the new assertions are known to discriminate.
- Two `rules/gates.md` bullets change: the dormant list drops to three scripts and retracts its
  "passes its tests" claim, and a new bullet describes this guard with its gaps stated.
