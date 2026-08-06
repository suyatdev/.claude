---
phase: implementation
model_tier: high
branch: fix/shell-segments-redirects
---

# `shell_segments.py` misreads redirections as command separators

Queue item 1. Branched from `main` @ `bc7da76`. User confirmed the gate 2026-08-04 (session 9) and
chose the **root-cause** scope over patching the one symptom that bites.

## Spec

### Root cause

`OPS` (`hooks/lib/shell_segments.py:25`) contains `<` and `>`, and the split loop at :78-82 starts a
new segment for any token made entirely of `OPS` characters. That treats a redirection operator as a
**control** operator — as if `>` ended one command and began another. It does not: a redirection is
part of the command it attaches to, and may appear anywhere in it, including before the command name.

One misclassification, three observable failures. All three are reproduced, not inferred:

| # | Shape | Current `segments()` output | Effect |
|---|---|---|---|
| a | `git commit -m msg -- FILE 2>&1` | `[…,'--','FILE','2']` + `['1']` | **fail-CLOSED.** The stray fd digit `2` becomes a pathspec; `2` is not documentation, so `doc-guard` denies a legitimate commit. The symptom the user hits. |
| b | `git commit -m x -- foo.sh > out.txt` | `[…,'foo.sh']` + `['out.txt']` | Redirect **target** lands in command position as its own segment. Noise; harmless only because no guard matches `out.txt` / `/dev/null` / `1` / `log`. |
| c | `> out.txt git commit -m x -- foo.sh` | `[]` + `['out.txt','git','commit',…]` | 🔴 **fail-OPEN.** `argv[0]` is never `git`, so **no guard sees a commit at all**. `git >out.txt commit …` likewise yields a bare `['git']`. A real bypass of a Tier-1 guard. |

Mode (c) is a **momentum guardrail failure, not a security-boundary breach** — the house rules class
these hooks as guardrails, and this document does not claim otherwise.

### The rule

Partition punctuation tokens instead of lumping them:

- A token made entirely of `OPS` chars **that contains `<` or `>`** is a **redirection operator**.
  It does not split. It is dropped along with the single token that follows it (its target).
- Any other all-`OPS` token is a **control operator** and splits, exactly as today.

This classifies correctly across the set: `>` `>>` `<` `<<` `<<<` `<>` `>|` `>&` `<&` `&>` `&>>` are
redirections (all contain `<` or `>`); `|` `||` `&&` `;` `;;` `&` `(` `)` `{` `}` `|&` remain control
operators. Note `|&` — bash's pipe-with-stderr — contains neither `<` nor `>` and so stays a splitter,
which is correct.

**Leading fd digit.** `2>&1` lexes as `2`, `>&`, `1`; shlex discards spacing, so `cmd 2>x` and
`cmd 2 >x` are indistinguishable at the token level. On encountering a redirection operator, a
trailing bare-digit token already appended to the current segment is dropped.

> **Accepted limit, stated not discovered — and it is wider than "a file named `2`".** *Any* trailing
> bare digit before a redirection is lost: `git log -n 5 > out` loses the `5` (an option value, no
> guard impact found), and `git commit -m x -- docs/foo.md 2 > out` loses the pathspec and goes
> **block → allow** on `main`. The pathspec case is the one guard-visible flip, because git-guard's
> docs-only exemption is decided from the pathspec; doc-guard reads the staged index and matches
> `Doc-Exempt:` against the raw string, neither of which a lost token can reach.
>
> Accepted because the alternative reinstates a *false denial* on the routine `2>&1` idiom — the
> symptom that started this — and because a bare digit can never be `argv[0]`, so the command itself
> is still always recognised. It is a **fail-open on a Tier-1 guard** and is recorded as one:
> **ADR 0015**. Pinned from both sides in `shell_segments.test.py` (the digit *is* dropped, at the
> pathspec *and* at an option value; an ordinary filename is *not*), so it cannot widen silently.

**Heredocs stay out of scope and stay working.** shlex cannot see heredoc bodies — a documented limit
(ADR 0012). The existing `\n` → `;` translation (:71) already isolates each body line into its own
segment, so consuming `<<` plus its delimiter leaves the real command's argv intact. Scenario H below
pins this, because the naive reading — that body words would be appended to the command — was the one
plausible regression in this change.

### Scenarios

```gherkin
Scenario A: fd-duplicating redirect no longer invents a pathspec
  When segments("git commit -m msg -- FILE 2>&1 | tail -3")
  Then one segment has argv ["git","commit","-m","msg","--","FILE"]
   And no segment has argv ["1"]

Scenario B: a redirect target never reaches command position
  When segments("git commit -m x -- foo.sh > out.txt")
  Then the only non-empty segment is ["git","commit","-m","x","--","foo.sh"]

Scenario C: a leading redirect does not hide the command
  When segments("> out.txt git commit -m x -- foo.sh")
  Then some segment has argv[0] == "git"

Scenario D: a mid-command redirect does not truncate the command
  When segments("git >out.txt commit -m x -- foo.sh")
  Then some segment has argv ["git","commit","-m","x","--","foo.sh"]

Scenario E: control operators still split
  When segments("git add -- a.sh && git commit -m x -- a.sh")
  Then there are two segments with argv[0] == "git"

Scenario F: pipe-with-stderr still splits
  When segments("git log |& tail")
  Then some segment has argv[0] == "tail"

Scenario G: wrapper stripping still composes with redirects
  When segments("rtk git commit -m x -- a.sh 2>/dev/null")
  Then some segment has argv ["git","commit","-m","x","--","a.sh"]

Scenario H: a heredoc body does not leak into the command's argv
  When segments("git commit -q -F - -- CODING_MEMORY.md <<'MSG'\ndocs: subject\nMSG\n")
  Then some segment has argv ["git","commit","-q","-F","-","--","CODING_MEMORY.md"]

Scenario I: quoted redirect characters are untouched
  When segments("git commit -m 'a > b' -- a.sh")
  Then some segment has argv ["git","commit","-m","a > b","--","a.sh"]
```

## Corrections found by measuring (the spec above was written before these)

1. **Mode (a) bites `git-guard`, not `doc-guard`** — the queue note said doc-guard. Measured:
   `doc-guard.sh:154-157` inspects the **staged index** (or `git diff HEAD` under `-a`) and never
   consults the pathspec, so a phantom `COMMIT_PATH` cannot reach it. The real site is
   `git-guard.sh:155-157`: guard 1 uses `commit_pathspec_files()` **only when nothing is staged**.
   So mode (a) fires exactly on the empty-index path — the same path
   `docs/features/git-guard-empty-index.md` covers.
2. **The replay harness is blind to this defect class.** `git-guard.replay.sh` reports
   378/378 identical, 0 relaxed — but its 63-command matrix contains **zero** redirect shapes, so
   that result is evidence of *no regression* and is **not** evidence the fix works. Recorded because
   the standing note ("has missed a shape in three consecutive rounds") applies here too.
   *Provenance ([ADR 0016](../decisions/0016-differential-harness-must-prove-difference.md)): base
   `main` @ `bc7da76`, ~68 minutes before this branch's own merge.*
3. **Heredocs put `git commit` at a command position — on both lexers, identically.** A probe script
   whose heredoc body contained `git commit …` was blocked by the live doc-guard. Verified this is the
   pre-existing ADR 0012 shlex limit, unchanged by this fix, by running both lexers over the same
   string. Not a regression; noted so the next person does not re-diagnose it.

## Checklist

- [x] 1. Red: `hooks/lib/shell_segments.test.py` — the suite this module has never had. Scenarios A-I
      plus the existing behaviour it must not break (chaining, newline/continuation, braces, quoting,
      `WRAPPERS`, `VAR=` assignments, unparseable input → `[]`). **31 checks.**
- [x] 2. Confirmed red for the stated reason: **14 failed, 17 passed** on the unfixed module. The 17
      were the regression block, and the heredoc check was among them — current behaviour there was
      already correct, which is what the fix had to preserve.
- [x] 3. Green: `_is_redirect()` + redirect-aware split loop in `shell_segments.py`; trailing
      bare-digit dropped; accepted limit documented in the source and pinned by
      `check_accepted_limit()`. **31/31.**
- [x] 4. Dependent suites all green: `git-guard` **77/0**, `doc-guard` **16/0**, `phase-guard`
      **134/0**, `judge-guard` **101/0**, `classify-git-command` **78/0**, `classify-pr-command`
      **51/0**. With the new 31, **488 checks passing**.
- [x] 5. Replay: 63 × 6 = 378 pairs, 378 identical, 0 stricter, 0 relaxed. **See correction 2 — this
      does not demonstrate the fix.** *Provenance: same measurement as correction 2, base `main` @
      `bc7da76`.*
- [x] 6. End-to-end falsifier, old lexer vs new, driving the real `git-guard.sh`:
      | case | old | new |
      |---|---|---|
      | docs commit, no redirect (baseline) | 0 allow | 0 allow |
      | mode (a) `… -- docs/foo.md 2>&1 \| tail -3` | **2 BLOCK** | **0 allow** |
      | mode (c) `> out.txt git commit -m x -- src/app.js` on `main` | **0 allow** | **2 BLOCK** |
      | control: plain source commit to `main` | 2 block | 2 block |
      The baseline row is load-bearing: the same commit without the redirect is allowed by both, so
      the redirect alone caused the denial. Classifier level: old emits a phantom `COMMIT_PATH -> 2`,
      new does not.
- [x] 7a. Observability judge, round 1 on `64ba2fa` — **`risk=medium confidence=high`**, and it found
      a **regression the fix itself introduced**. Verdict:
      `coding-memory/observability-judge/2026-08-04-fix-shell-segments-redirects.md`.
- [x] 7b. Judge round 2 on `28e2053` — **`risk=low confidence=high`**, 9/10 pass. PR **#38** opened at
      that commit. See "Judge round 2" below.

## Judge round 1 — what it caught, and the fix

**🔴 Process substitution.** `<(cmd)` and `>(cmd)` contain `<`/`>` but **open a command context**, so
`_is_redirect` classified them as redirections and ate the substituted command's name. Verified at
three levels: `cat <(gh pr create)` → `['cat','pr','create']`; the PR classifier flipped `PR` → `NO`;
and `echo hi > >(git commit -m x -- src/app.js)` on `main` went **block → allow**. Both shapes are
valid executable bash. **Same fail-open class as mode (c) — reintroduced by the fix for mode (c).**

The naive repair (exclude parens from `_is_redirect`) is **not sufficient**: in `> >(cmd)` the
redirection's *target* is itself a substitution, so blindly consuming the next token still buried the
command in `echo`'s argv. Full rule now: a redirection contains `<`/`>` and **no paren**, *and* its
target must be a **word** — a punctuation token is never consumed as a target.

**🔴 The accepted limit was undersold.** The original note said a dropped bare digit leaves "command
recognition unaffected". True of `argv[0]`, and beside the point: git-guard's docs-only exemption is
decided from the **pathspec**, so losing a path flips deny → allow. Concrete:
`git commit -m x -- docs/foo.md 2 > out` on `main` — old **blocks**, new **allows**. Still accepted
(it beats a false denial on the routine `2>&1` idiom) but now recorded as a **fail-open on a Tier-1
guard** and pinned at guard level, not merely described.

**Also actioned:** the falsifier is now `hooks/shell-segments-falsifier.sh` — a real script with
expected values per row that **fails** on regression, replacing a markdown table nobody could re-run.
It carries the baseline and control rows, and the process-substitution and fail-open rows above.

**Judge findings NOT actioned at the time, deliberately:** amending ADR 0013 for the changed lexer
semantics. Left for the user to direct — it does not affect behaviour and would have moved HEAD again
before the re-judge. **Now closed** — see round 2 below.

**Note for the re-judge:** the suite that was added to prevent this defect class had no `<(`/`>(`
case, so it could not see the defect the change introduced. Four cases now cover it (35 checks).

**Not in scope, deliberately:** the `^git`-anchored lexer in `checkpoint-before-modify.sh:97` (dormant,
unregistered — fixes nothing observable today); unifying the four `git commit` lexers; `env`/`timeout`
wrapper shapes, which remain the accepted-open denylist from ADR 0012.

## Judge round 2 — clean, and the two docs items it left

Round 2 on `28e2053`: **`risk=low confidence=high`**, 9/10 dimensions pass, one `audit_trail`
concern. Round 1's findings verified closed at all three levels (lexer, classifier, real
`git-guard.sh` exit code); 9 process-substitution shapes ground-truthed by execution — round 1 blind
to all 9, round 2 blind to none. A 44-shape end-to-end sweep found **zero unaccounted fail-opens**,
and **five bypasses beyond the three stated modes** close versus `main`, including
`> out git push --force` — a force-push hole, not only a commit hole. Both verdicts live in
`coding-memory/observability-judge/2026-08-04-fix-shell-segments-redirects.md`.

PR **#38** was opened at `28e2053` — the judged tree — on the user's decision, and the two
documentation items below landed on the branch afterwards. Both are prose plus one test assertion; no
implementation logic changed.

- [x] 8. **ADR 0015** — `docs/decisions/0015-redirections-are-part-of-a-command.md`, amending 0013.
      Records the changed operator semantics, the options weighed, and the new accepted fail-open.
      `rules/gates.md:14` repointed at the chain.
- [x] 9. **The accepted limit was written too narrowly a third time.** It is *any* trailing bare
      digit, not "a file named `2`" — `git log -n 5 > out` loses the `5`. Corrected in
      `shell_segments.py`, `shell_segments.test.py` and the spec above, and now **pinned**:
      `check_accepted_limit()` carries a second assertion at an option value, so the width itself is
      falsifiable rather than merely described. Both assertions confirmed able to fail by mutating
      `argvs` — a check that cannot fail is not evidence.
