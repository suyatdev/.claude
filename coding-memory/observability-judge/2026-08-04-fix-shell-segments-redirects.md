# Observability verdict — `fix/shell-segments-redirects` (implementation)

- **repo:** `.claude`
- **branch:** `fix/shell-segments-redirects`
- **head_sha:** `64ba2fa8eb43314ab6b8d7cb5028d41b3d7bb637` (single commit off `main` @ `bc7da76`)
- **stage:** implementation
- **judged:** 2026-08-04T19:48:54Z
- **risk:** medium — **confidence:** high

---

## What was changed

The hooks that stop bad `git` commands read your command string and chop it into "separate
commands" before deciding anything. It was chopping in the wrong places. It treated `>` and `<`
— the symbols that send output to a file — as if they *ended one command and started another*.
They don't; they're part of the command they're attached to.

Analogy: it read `mail this letter > to the outbox` as two instructions ("mail this letter", then
"to the outbox"), instead of one instruction with a delivery address stapled to it.

That single mistake caused three separate problems, and this change fixes the reading rule: a
punctuation symbol containing `<` or `>` is an address, not a full stop — swallow it with the
thing it points at, and don't split there. It also adds a 31-check test file for this lexer, which
had **no tests at all** despite every guard depending on it.

## Does it do what you wanted?

**Yes for the three problems it targeted — I verified them myself, from scratch.**

I rebuilt the end-to-end test independently (copied the hooks to a temp dir, put the *old* lexer
in one copy, drove the real `git-guard.sh` with real hook JSON) and got the author's exact four
rows. Nothing was fabricated:

| case | old | new |
|---|---|---|
| docs commit, no redirect (baseline) | 0 allow | 0 allow |
| `… -- docs/foo.md 2>&1 \| tail -3` | **2 BLOCK** | **0 allow** ✅ fixed |
| `> out.txt git commit -m x -- src/app.js` on `main` | **0 allow** | **2 BLOCK** ✅ fixed |
| plain source commit to `main` (control) | 2 block | 2 block |

All 8 test suites reproduce their claimed counts exactly: 31 / 78 / 51 / 77 / 16 / 134 / 101 =
488 checks, 0 failures, and replay 378/378 identical, 0 relaxed.

## What could go wrong / what I'm unsure about

**The main finding: the new rule is not total, and it opens a new hole of exactly the kind it
was written to close.** The change asks "does this symbol contain `<` or `>`?" — but bash has two
symbols that contain `>`/`<` and are **not** addresses: `<(` and `>(` (process substitution).
Those *open a command*, just like `(` does. The new rule reads them as an address and eats the
command name that follows.

Both the source docstring and the spec claim the partition is exact and list the operator set —
that list omits `<(` and `>(`. Verified at three levels, old lexer vs new:

- lexer: `cat <(gh pr create)` → old `[['cat'], ['gh','pr','create']]`, new `[['cat','pr','create']]`
- PR classifier: same command → old emits `PR`, new emits `NO`
- real `git-guard.sh` on `main`: `echo hi > >(git commit -m x -- src/app.js)` → **old exit 2
  BLOCK, new exit 0 ALLOW**

Both shapes are valid, executable bash (`bash -n` accepts them). So a commit of `src/app.js` to
`main` now walks past a Tier-1 guard that previously caught it. Narrow and nobody types it by
accident — but it is a genuine regression in the same failure class as mode (c).

**Second, answering the bare-digit question directly: yes, it can make a guard weaker.** The docs
justify the dropped digit as "command recognition is unaffected" — true for `argv[0]`, but
`git-guard`'s docs-only exemption is decided from the **pathspec**, not from `argv[0]`. Dropping a
path can flip deny into allow: `git commit -m x -- docs/foo.md 2 > out` on `main` is **old exit 2
BLOCK, new exit 0 ALLOW**. It needs a file literally named with a bare digit as the last pathspec
before a redirect, so it is rare — but it is a fail-*open*, not merely "a lost operand", and the
spec's framing understates the direction.

**Third: is the falsifier falsifiable?** Yes, genuinely. It moves in both directions (2→0 and
0→2), the control row stays put, and the baseline row is load-bearing exactly as claimed — I
reproduced it independently. It is not a check that cannot fail; it is only *incomplete*. (By
contrast, my own first probe through `judge-guard` blocked all three inputs regardless of content,
because the temp repo had no verdict — a check that could not fail. I discarded it and used the
classifier instead.)

**Fourth, bootstrap risks not stated in the summary:** hooks load from the working tree, so (a)
the new fail-open is armed on this machine as of the commit, before any review; (b) checking out
`main` mid-session silently re-arms the *old* mode-(c) bypass; (c) there is no staging gap where a
regression could surface before it is live.

**Where the green tests masked this:** the new 31-check suite — added specifically to prevent this
defect class — contains no `<(` or `>(` case, so the one suite that could have caught the change's
own regression cannot see it. This is the house pattern from memory: *confirm the check can fail.*

Minor, not exploitable: a malformed redirect swallows the following control operator
(`git commit -m x > && git push --force` merges into one segment), but `bash -n` rejects both such
shapes, so they never execute.

## What I'd double-check before merging

1. **Exclude `(` and `)` from the redirect test** so `<(` / `>(` split as command contexts again —
   and add both to the test suite. This is the one change I would not merge without.
2. **Re-state the accepted limit honestly** as a fail-open on the pathspec-exemption path, not just
   a lost operand — and pin it with a `git-guard`-level test, not only a lexer-level one.
3. **Commit the end-to-end falsifier** as a script. It is the strongest positive evidence in the
   change and today it exists only in a markdown table nobody can re-run.
4. **Amend ADR 0013** — it documents this shared lexer's accepted limits; this change alters the
   operator semantics and adds a new limit, with no ADR update (0013-amending-0012 is the precedent).
5. Confirm nothing in the queue depends on `<(…)` shapes reaching a guard.

---

## Dimensions

| dimension | verdict | note |
|---|---|---|
| intent | pass | Root-cause scope the user chose; 3 files, 1 commit; modes (a) and (c) verified fixed end-to-end. |
| execution | concern | 488 checks reproduce exactly, but a new fail-open on `<(`/`>(` is live and verified at guard level. |
| trajectory | pass | Reasoning, not luck: RED confirmed 14/17 for a stated reason, corrections-by-measurement retracts two wrong fixtures and a wrong attribution. Gap: totality claimed from an enumerated list, never tested against the real token set. |
| regression | concern | Adjacent breakage confirmed: two valid-bash shapes newly slip past Tier-1 guards (old 2 → new 0). |
| context_budget | pass | No always-on context added; hooks/lib code plus one feature doc. |
| traceability | pass | Docstring, spec with 9 scenarios, commit body with measured numbers; every claim I checked held. |
| success_masking | concern | 488 green + 378/378 replay coexist with a live regression; the new suite has no process-substitution case. Replay correctly self-labelled as non-evidence. |
| intent_drift | pass | No drive-by edits, no dependencies added (test kept dependency-free deliberately), out-of-scope items listed and untouched. |
| checkpoint | pass | Clean single-commit revert point off `bc7da76`, clean tree; note reverting re-arms the mode-(c) bypass. |
| audit_trail | concern | Excellent attribution (author, Co-Authored-By, session URL); but the falsifier is uncommitted and ADR 0013 is not amended for a change to its own documented lexer. |

## Concerns

1. `_is_redirect` is not total: `<(` and `>(` are all-OPS tokens containing `<`/`>` but open a
   command context — the docstring's "partitions the operator set exactly" and the spec's operator
   list both omit them.
2. New fail-open, verified end-to-end: `echo hi > >(git commit -m x -- src/app.js)` on `main` —
   old `git-guard` exit 2 BLOCK, new exit 0 ALLOW; valid bash per `bash -n`.
3. New guard blind spot on the PR path: `cat <(gh pr create)` classifies `PR` under the old lexer
   and `NO` under the new one.
4. The bare-digit drop is a fail-open on the pathspec-exemption path, not just a lost operand:
   `git commit -m x -- docs/foo.md 2 > out` on `main` goes old 2 BLOCK → new 0 ALLOW; the spec
   argues "command recognition unaffected", which is true of `argv[0]` but not of the exemption.
5. The new 31-check suite has no `<(`/`>(` case, so the suite added to prevent this defect class
   cannot detect the regression this change introduced.
6. The checklist item 6 end-to-end falsifier is not committed as a script — I had to rebuild it to
   verify it (it reproduced exactly, so the claim is honest, but it is not reproducible from the repo).
7. ADR 0013 documents this shared lexer and its accepted limits; the operator semantics changed and
   a new accepted limit was added with no ADR amendment.
8. Bootstrap, unstated: the regression is armed on this machine as of the commit; checking out
   `main` mid-session silently re-arms the old mode-(c) bypass; no staging gap exists.
9. Cosmetic, non-exploitable: a malformed redirect swallows the next control operator
   (`git commit -m x > && git push --force` merges into one segment); `bash -n` rejects the shape.

---
---

# Observability verdict — ROUND 2 (implementation)

- **repo:** `.claude`
- **branch:** `fix/shell-segments-redirects`
- **head_sha:** `28e2053a1b73d3bfe6868477d37ce30b3549b134` (two commits off `main` @ `bc7da76`)
- **stage:** implementation
- **judged:** 2026-08-04T20:12:45Z
- **risk:** low — **confidence:** high
- **supersedes:** the round-1 verdict above, which pins `64ba2fa` and is now stale.
  Round 1 is retained deliberately — the feature doc's checklist item 7a cites this path.

---

## What was changed

Round 1 found that the redirect fix had, while closing one hole, opened a new one of exactly
the same kind. Commit `28e2053` is the response.

The lexer chops a command line into separate commands so the guards can inspect each one. The
original bug: it treated `>` (send output to a file) as if it *ended* one command and started
another. Analogy: reading `mail this letter > to the outbox` as two instructions instead of one
instruction with a delivery address stapled on.

Commit 1 fixed that but over-applied it. Bash has two symbols — `<(` and `>(` — that *contain*
`>` but are not addresses at all; they open a **real command**. Commit 1 read those as addresses
and swallowed the command hiding inside them. Commit 2 adds the missing half of the rule: an
address contains `<`/`>` **and no bracket**, and the thing it points at must be a plain word —
never another piece of punctuation. It also stops describing an accepted weakness as harmless,
and turns the evidence from a table into a script that actually fails when the fix breaks.

## Does it do what you wanted?

**Yes — and this time I confirmed it by running the shapes, not by reading the claims.**

Round 1's findings are genuinely closed, at every level they were found:

| level | round-1 result (`64ba2fa`) | now (`28e2053`) |
|---|---|---|
| lexer `cat <(gh pr create)` | `['cat','pr','create']` ❌ | `['cat'], ['gh','pr','create']` ✅ |
| real `git-guard.sh`, `echo hi > >(git commit … src/app.js)` on `main` | exit 0 ALLOW ❌ | exit 2 BLOCK ✅ |
| 9 process-substitution shapes, execution-ground-truthed | blind to all 9 ❌ | sees all 9, matching `main` ✅ |

I ran all seven suites myself: 35 + 78 + 51 + 77 + 16 + 134 + 101 = **492 checks, 0 failed** —
exactly as claimed. Replay **378/378 identical, 0 relaxed**. The committed falsifier runs, carries
per-row expectations, and exits non-zero on regression.

I then swept **44 shapes** end-to-end through the real `git-guard.sh`, `main`'s lexer vs this one,
looking for any block→allow. **Zero unaccounted fail-opens.** The only two block→allow rows are the
bug being fixed (the routine `2>&1` false denial) and the accepted limit that is pinned by a test.

The branch also closes **five more Tier-1 bypasses** than were claimed — including
`> out git push --force`, which `main` **allows** today. That is a force-push guard hole, not just
a commit guard hole.

I checked the specific question round 1 could not answer: **is the rule now total?** I fuzzed every
punctuation token bash accepts, using real execution as ground truth ("does bash actually run the
next command?") against the lexer ("does it see it?"). Every token that really runs a command is
seen. The remaining mismatches are all in the over-strict, safe direction.

Two of my own probes were dead and I threw them away rather than report them: the first fuzz used
`timeout`, which macOS does not have, so every row silently read "no"; and one end-to-end row used
`jq -R`, which splits multi-line input, inventing a heredoc bypass that does not exist. Re-tested
correctly, the heredoc blocks on both lexers. Both are retracted, not reported.

## What could go wrong / what I'm unsure about

**Nothing here blocks the merge.** The honest remainders:

1. **The accepted fail-open is real, and it is on a Tier-1 guard.**
   `git commit -m x -- docs/foo.md 2 > out` on `main` — old **blocks**, new **allows**. It needs a
   file literally named with a bare digit as the last thing before a redirect. It is now described
   honestly (round 1's "command recognition unaffected" was wrong) and pinned from *both* sides: one
   test asserts the digit **is** dropped, another asserts a normal filename is **not**. So it cannot
   widen silently. I think it is the right trade — the alternative reinstates a false denial on the
   everyday `2>&1` idiom.

2. **That limit is still described slightly narrower than it is.** The docs say "a file literally
   named `2`". It is actually *any* trailing bare-digit token before a redirect — `git log -n 5 > out`
   loses the `5` too. Same class, same direction, no guard impact I could find. But this is the third
   time this particular limit has been written down narrower than it behaves, which is worth naming.

3. **ADR 0013 is still not amended** — deliberately deferred. Weaker than round 1 implied: 0013
   explicitly delegates accepted limits to the source file, and the limit *is* in the source, the
   spec, a test docstring and a falsifier row. But a new accepted fail-open on a Tier-1 guard is
   ADR-worthy under the house rules. Practical trap: amending it moves HEAD, which makes this verdict
   stale and re-blocks `gh pr create` under `judge-guard`. Decide before the PR, not after.

4. **Minor:** the falsifier is not linked from `hooks/README.md`, so it is discoverable only from the
   commit message and feature doc — though the pre-existing replay harness has the same status, so
   this matches the repo's convention rather than breaking it.

5. **Bootstrap, unchanged from round 1:** hooks run from the working tree, so this fix is live on this
   machine now, and checking out `main` mid-session silently re-arms all the bypasses it closes.

## What I'd double-check before merging

1. **Decide the ADR question now, not after** — either amend 0013 and accept a round-3 re-judge, or
   consciously waive it. Leaving it until after the PR is the one path that creates rework.
2. **Correct the one-line description of the digit limit** to "any trailing bare digit", so the
   written record finally matches the behaviour.
3. Nothing else. I could not find a shape that defeats the rule, and I tried specifically to.

---

## Dimensions

| dimension | verdict | note |
|---|---|---|
| intent | pass | Responds to each round-1 finding at the level it was found; deferral stated openly, not hidden. |
| execution | pass | 492 checks reproduced by me, 0 failed; falsifier runnable and failing-capable; 44-shape e2e sweep clean. Was `concern` in round 1. |
| trajectory | pass | The insight that excluding parens alone is insufficient — because in `> >(cmd)` the target is itself a substitution — is reasoning, not luck; the nested case confirms it. Honest retraction of the undersold limit. |
| regression | pass | Round-1 breakage closed and verified independently; commit 2 moves strictly in the more-segments (fail-closed) direction; 5 extra bypasses closed vs `main`. Was `concern`. |
| context_budget | pass | No always-on context; no `rules/`, `skills/`, `CLAUDE.md` or `settings.json` touched. Files 150/201/76 lines. |
| traceability | pass | Source docstrings, spec with measured corrections, commit bodies with real numbers, runnable evidence. Falsifier not linked from `hooks/README.md` (matches existing convention). |
| success_masking | pass | The gap that caused round 1 is closed: 4 process-substitution cases added, and the accepted limit is pinned from both directions so it cannot widen silently. Replay still correctly self-labelled as non-evidence. Was `concern`. |
| intent_drift | pass | No drive-by edits, no dependencies added, out-of-scope items listed and untouched. |
| checkpoint | pass | Two clean commits, clean tree; each commit is a revert point. Note a full revert re-arms the mode-(c) and force-push bypasses. |
| audit_trail | concern | Falsifier now committed (round-1 item closed). ADR 0013 still unamended for changed lexer semantics plus a new accepted Tier-1 fail-open; digit limit still stated narrower than it behaves. |

## Concerns

1. ADR 0013 not amended for the changed operator partition and the new accepted fail-open on a
   Tier-1 guard; deferred deliberately, but it is the last open item and amending it later moves
   HEAD and invalidates this verdict for `judge-guard`.
2. The bare-digit limit is documented as "a file named `2`" but drops any trailing bare-digit token
   before a redirect (`git log -n 5 > out` loses the `5`) — third narrower-than-reality framing of
   this same limit.
3. Accepted fail-open remains live: `git commit -m x -- docs/foo.md 2 > out` goes block → allow.
   Correctly pinned from both sides, so it cannot widen silently.
4. Falsifier not discoverable from `hooks/README.md`; consistent with the replay harness, but both
   are effectively orphan scripts.
5. Bootstrap, unchanged: the fix is live from the working tree before review, and checking out
   `main` mid-session re-arms every bypass it closes.
