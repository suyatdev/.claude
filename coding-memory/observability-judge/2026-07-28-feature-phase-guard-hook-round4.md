# Observability verdict — phase-guard-hook, RUN 4 (adversarial)

- **repo:** phase-guard-hook (worktree of `~/.claude`)
- **branch:** `feature/phase-guard-hook`
- **head_sha:** `97b0bc0e3b6205dce47fbad217cf6dd48ddc63b3`
- **stage:** implementation (gates the PR)
- **ts:** 2026-07-28T20:02:23Z
- **risk:** high · **confidence:** high

> **Lead with the failures.** Two dimensions are `fail`: `success_masking` and `traceability`.
> A **fourth instance** of the guard-goes-silent class exists at this HEAD and is reproducible
> in one command. The spec asserts a guarantee that is provably false.

---

## What was changed

Imagine a night watchman whose one job is to shout "STOP" when someone tries to build before the
plans are approved. Three previous inspections all found the same kind of flaw: situations where
the watchman quietly says nothing at all — and a silent watchman looks *exactly* like a watchman
who is doing his job and finding nothing wrong.

This round's change fixes the third of those. Previously the watchman only looked at approval
cards that were ordinary pieces of paper; anything odd — a card that was really a shortcut pointing
at a missing file, or a folder pretending to be a card — got swept off the desk before he could
even count it. Now he counts **anything on the desk**, in whatever shape, and only ignores an
empty desk. Four new tests were added covering exactly those odd shapes, the spec was corrected in
three places, and a noisy error message from the card-reader tool was muted.

That fix is real and it works. I verified it.

## Does it do what you wanted?

Partly, and the gap is the point of this round.

**What genuinely landed:** the tests are real (I ran them: 100 passed, 0 failed), `shellcheck` is
clean, the previously-broken cases now behave correctly, and the commits are honest — tests were
committed *before* the fix, so the fix had to earn its green.

**What did not:** I was asked to hunt for a fourth instance of the "goes silent" class, assuming
it exists. **It exists.** The watchman now counts anything on the desk — but he can still be
stopped from ever *seeing the desk*, and when that happens he says nothing.

Concretely: if the `docs/features/` folder itself has its permissions changed so the process
cannot look inside it, every approval card in it vanishes from the guard's view at once. The tally
that is supposed to shout "I couldn't read something!" counts zero files, so it has nothing to
shout about. Verified by toggling one permission bit, with everything else identical:

| `docs/features/` mode | real committed `phase: planning` card present | result |
|---|---|---|
| `755` (normal) | yes | **exit 2**, full deny message |
| `444` (read kept, search dropped) | yes — glob still yields `real-feature.md` | **exit 0, stderr EMPTY** |
| `755` (restored) | yes | **exit 2**, full deny message |
| `000` | yes | **exit 0, stderr EMPTY** |
| `755` (restored) | yes | **exit 2**, full deny message |

The `444` row is the sharpest: the shell's glob still produces the real card's filename from the
directory listing, so the entry is *known to exist* — and it is still dropped before `nfiles` can
count it, because both `[ -e ]` and `[ -L ]` need search permission on the parent. This is the
identical shape as RUN 3: **the hole moved one step earlier again**, from "which entries are
counted" to "whether the directory can be enumerated at all". The unexamined assumption is now
"an unexpanded glob means the directory is empty" — an unreadable directory satisfies it too.

I guarded against the fixture error you disclosed: my throwaway repos all have a real initial
commit, and every probe is bracketed by a control that denies correctly.

**And the fixture class is not complete.** The suite chmods a *card* to `000` (A2.21). It never
chmods the *container* of that card. That is the obvious missing member — the same permission
mechanic, one directory up.

**Second silent-off route, upstream of the loop (step 5).** You asked me to probe steps 1–6. If the
payload's path uses a symlinked form of the repo path while `git rev-parse --show-toplevel` returns
the physical path, step 5 classifies a logically-inside path as outside and exits 0 silently — the
guard is off for that entire repo, permanently, no warning. Verified: same repo, same planning card,
real path → exit 2; symlink path → exit 0 silent. The test harness *works around* this
(`TMP="$(cd "$(mktemp -d)" && pwd -P)"`, with a comment saying otherwise "every guarded case would
fail open and pass for the wrong reason") rather than the hook handling it or the spec listing it.
By the design's own taxonomy this is squarely "opted in and could not evaluate" — step 3 already
passed — so it belongs in the audible category, not the silent one.

**The spec is wrong again, on the same rule, for the third consecutive round.** Step 7 now states:
"Every glob entry that **exists in any form** is counted … only a glob that matched nothing is
passed over." The `444` row above falsifies that sentence directly. Scenario A2 example 2 —
"*any* `docs/features/*.md` entry cannot be read → warns once per session" — is falsified by the
same fixture. These are normative statements, not prose. Someone writing tests from this spec would
write a passing test for a behaviour the hook does not have.

## What could go wrong / what I'm unsure about

- **A dead guard is indistinguishable from a working one.** That is the whole premise of the two
  audible exits, and it still holds in at least two reachable states. Realistic triggers for the
  permission case: a restore from tar/rsync that drops directory `+x`, a bad `chmod -R`, a
  bind-mount or network share with a uid mismatch, another user's checkout. For the symlink case:
  a repo under a symlinked `~/Code`, an external volume, or `/tmp`.
- **Honest calibration on likelihood.** A chmod'd `docs/features/` is *less* likely than RUN 3's
  moved-symlink-target. I am not inflating it. But it is *worse* when it happens — RUN 3's bug
  dropped one card; this drops every card at once, so the whole gate goes dark while the repo still
  looks perfectly opted-in. And by the design's own severity logic, the no-interpreter exit it
  already builds for is arguably rarer than a permission problem.
- **The pattern is the finding, more than any one instance.** Four adversarial passes, four
  instances, same class, each time one step earlier in the pipeline. Each fix was locally correct
  and each was described as a class fix; the code comment and spec both claim class-level coverage
  ("EXISTS IN ANY FORM is the test") that the next probe falsifies. That is instance-patching
  wearing a class fix's clothes — exactly what this round was asked to test for.
- **Green tests are actively reassuring here.** 100/0 with a brand-new fixture group explicitly
  named "unreadable entries" reads as coverage of unreadable inputs. It is not.
- **`2>/dev/null` on awk — I probed it and it is defensible.** Every stderr case I could construct
  (unopenable entry, awk syntax error, awk missing entirely) also yields empty stdout, so the
  `nfiles > nparsed` tally still fires. One residual nit: with awk missing, the true cause is now
  fully invisible and the user gets the misleading "could not be read as a feature card" message.
  Diagnosability nit, not a silent-allow.
- **Steps 8–9: no additional silent-allow route found.** I probed the byte-accounting in
  `BATCH_AWK`, request/response ordering, colons in paths, branch-claim collection, detached HEAD,
  and `pipefail`. One conditional portability issue: `length($0)` counts **bytes** on this machine's
  awk (BWK 20200816, verified — em-dash returns 5) but returns **characters** under `gawk` in a
  UTF-8 locale, and the hook pins no locale while `cat-file` sizes are bytes. I tried and **failed**
  to construct a false supersession under simulated drift across seven inflation offsets — the
  observed direction is fail-*closed* (over-deny), not silent. Reporting it as a low-severity
  portability note, explicitly **not** as the fourth instance.
- **Odd filenames: fail-closed, no silent route.** Spaces, glob metacharacters, and newlines in card
  names all still deny correctly. A file literally named `*.md` makes the deny message list a
  sibling card twice (unquoted `$planning_files` re-globbing in step 8) — cosmetic, fail-closed.
- **Out-of-contract but silent:** a card in a subdirectory (`docs/features/sub/a.md`) or a dotfile
  card is invisible to the guard and never counted. Both are outside the flat one-card contract, so
  I am not scoring them, but they are the same silence.
- **Cost:** ~0.5s per single write at 200 cards (one awk process per card, on a hook that fires on
  every Edit/Write). Fine at this repo's current 1 card; no perf test pins it.
- **Carried, unchanged, still true:** never run live; branch-granularity hole; rollback path 3
  withdrawn; parallel-worktree collision still an open user-owned decision. At `risk=high` I do not
  think leaving the parallel-worktree collision undecided is defensible *silently* — it needs to be
  an explicit, named acceptance in the PR description, not a paragraph inside a 1,463-line spec.

## What I'd double-check before merging

1. **Decide whether the class is closed or the approach changes.** The narrow patch is cheap — test
   readability/searchability of `docs/features/` at step 3 and route the failure to the existing
   `noparse` warning instead of exiting silently. But that is a fifth instance patch. The structural
   alternative is to make "the guard could not evaluate this repo" the *default* outcome of every
   unproven path from step 3 onward, so silence has to be positively earned rather than fallen into.
2. **Fix the two false normative statements** in the spec (step 7's "only a glob that matched
   nothing is passed over"; A2 example 2's "any entry that cannot be read"). Third strike on the
   same rule — I would not accept another round of "corrected in place" without a test that pins
   the sentence.
3. **Add the missing fixture-class member**: `chmod 000` and `chmod 444` on `docs/features/` itself,
   red before any fix.
4. **Decide the step-5 symlink question explicitly** — normalize both sides, or enumerate the
   silent-off route in the spec as accepted. Right now it is neither; it is worked around in the
   test harness only.
5. **Run it live at least once** before merge (RUN 3 finding 4, still open). Every result including
   mine is from throwaway fixtures.
6. **Surface the parallel-worktree collision in the PR description**, as already agreed.
7. Housekeeping: rounds 1–3 verdicts now exist twice under two naming schemes (committed
   `2026-07-25-worktree-*`, untracked `2026-07-28-feature-*`). Pick one canonical set.

---

## Dimensions

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | concern | The remediation matched its brief, but code comment and spec both claim a **class** fix ("EXISTS IN ANY FORM is the test") that a one-command probe falsifies. An instance fix presented as a class fix. |
| `execution` | concern | I ran it: 100 passed / 0 failed, `shellcheck -x` clean, fixed cases genuinely fixed. But a demonstrated silent fail-open survives at this HEAD. |
| `trajectory` | concern | Reasoning quality is high — reproduce-first, tests before fix, mutation-checked, rationale inline. But the search remains instance-driven: four rounds, four holes, each one step earlier in the same pipeline. |
| `regression` | pass | No adjacent breakage. A2.17 / A1.7 / B2 still green, deny path intact, 100/100. Cost acceptable at realistic card counts. |
| `context_budget` | pass | One line added to `rules/gates.md` (always-on). The 1,463-line spec is on-demand under `docs/`. |
| `traceability` | **fail** | Two normative spec statements are provably false (step 7's glob rule; A2 example 2), falsified by a single fixture — the **third consecutive round** the same rule has been documented wrongly, in the very sentence written this round to fix the previous wrongness. |
| `success_masking` | **fail** | 100 green tests including a new group explicitly named for "unreadable entries" read as coverage of unreadable inputs; the unreadable *container* — the obvious missing member of that exact class — silences the entire guard and no test would notice. |
| `intent_drift` | pass | Four tight, on-topic commits. No scope creep, no drive-by edits, no new dependencies. |
| `checkpoint` | pass | Clean granular revert points; tests committed before the fix (`2f1e2ec` → `8967723`), preserving the unbiased baseline. |
| `audit_trail` | pass | ADR 0011, memory entries, commit messages that explain *why*. Minor: duplicate verdict files under two naming schemes muddy the judge trail. |

## Concerns

- Fourth instance of the silent-guard class at HEAD: an unreadable/unsearchable `docs/features/` (modes `000`, `444`, `111`) silences the guard entirely with a real `phase: planning` card present — verified by permission-bit toggle with passing controls either side.
- Second silent-off route at step 5: a symlinked repo path form makes the guard exit 0 silently for the whole repo; worked around in the test harness rather than handled or specified.
- Spec asserts a false guarantee for the third consecutive round on the same rule (step 7 glob rule; scenario A2 example 2).
- New "unreadable entries" fixture class is incomplete — chmods the card, never the containing directory.
- Green 100/0 suite is actively reassuring about the exact property that still fails.
- `length($0)` is byte- vs character-dependent across awk implementations and the hook pins no locale; failure direction observed as fail-closed, not reproduced as a silent allow.
- Hook has still never been run live (carried from RUN 3, unchanged).
- Parallel-worktree collision remains an open user-owned decision, undesirable to leave implicit at risk=high.
