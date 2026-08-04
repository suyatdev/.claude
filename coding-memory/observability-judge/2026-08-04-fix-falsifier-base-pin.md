# Observability verdict — `fix/falsifier-base-pin`

- **repo:** `.claude`
- **branch:** `fix/falsifier-base-pin` (slug `fix-falsifier-base-pin`)
- **head_sha:** `d0dac2ed0b1dc0e7b8e79f3139909fd64b68ba9f`
- **base:** `main` @ `e0d8546` (merge-base confirmed `e0d8546176bed556b776c25493ffb01ff2fc6789`)
- **stage:** implementation
- **ts:** 2026-08-04T21:17:15Z
- **risk:** low · **confidence:** high

---

## What was changed

`hooks/shell-segments-falsifier.sh` is a *side-by-side* test rig. It builds two copies of the hook
code that differ in exactly one file — the bit that reads a shell command and works out where one
command ends and the next begins — and runs the same seven command lines through the real
`git-guard.sh` against each copy, so you can see "old behaviour vs. new behaviour" in one table.

The "old" copy was being fetched from the branch `main`. But `main` is a moving target, and the whole
point of the branch that wrote this script was to land on `main`. Forty minutes after it was written,
the fix merged, `main` acquired the fix, and the rig started fetching the *new* code as its "old"
baseline — comparing the fix with itself. It printed four lines that looked exactly like the fix had
broken, and nothing anywhere in the output said "your baseline moved."

Two changes, one commit (`d0dac2e`, 2 files, +171/−5):

1. The default baseline is now the fixed commit `bc7da76` instead of the branch `main`, with the rule
   written into the source: a differential harness's baseline must be a fixed commit, never a branch.
2. Before any row runs, the script asks the baseline copy a direct question — "do you still have the
   bug?" — by feeding it `> out.txt git commit …` and checking whether any resulting segment starts
   with `git`. Pre-fix it doesn't (the redirect shoves the command out of first position); post-fix it
   does. If the baseline already has the fix, the script refuses in one plain sentence naming *itself*
   as the problem, instead of printing four rows that blame the implementation.

The Tier-1 guard code (`git-guard.sh`, `lib/shell_segments.py`) is **not touched**. This is an
evidence-harness fix only.

## Does it do what you wanted?

Yes, and I verified it rather than taking the report's word for it.

**Test suites — I ran all seven myself:** `shell_segments` 35, `git-guard` 77, `doc-guard` 16,
`phase-guard` 134, `judge-guard` 101, `classify-git-command` 78, `classify-pr-command` 51 =
**492 passed, 0 failed**. The claimed number is exact.

**All four scenarios reproduce as documented** (`$?` captured before anything else):

| scenario | base | my exit | my `FAIL` rows | output |
|---|---|---|---|---|
| A | default (`bc7da76`) | 0 | 0 | all seven rows as expected |
| B | `main` | 1 | **0** | names the baseline, says HARNESS not regression, gives the remedy |
| C | `0000000` | 1 | 0 | `fatal: invalid object name` + `falsifier: cannot read 0000000:…` |
| D | `bc7da76` | 0 | 0 | all seven rows as expected |

Scenario B against A/D is the falsification that matters: the self-check **fires** on a fixed base and
**stays silent** on a pre-fix one. It discriminates; it is not an always-on warning.

**The probe is sound — I checked it independently.** I extracted every version of
`shell_segments.py` that has ever existed (`ac5afa2`, `bc7da76`, `64ba2fa`, `28e2053`, `4ecd996`,
`e0d8546`, `d0dac2e`) and ran the probe against each:

| rev | probe verdict | correct? |
|---|---|---|
| `ac5afa2`, `bc7da76` | PRE-FIX | ✅ both predate `64ba2fa` |
| `64ba2fa` … `d0dac2e` | FIXED | ✅ all contain the fix |

Zero disagreement across the whole history. More importantly, I checked **why** the leading redirect
was chosen. Of the five shapes the harness tests, I measured which ones behave differently between the
pre-fix and post-fix lexers:

| shape | pre-fix yields a `git` segment? | post-fix? | discriminating? |
|---|---|---|---|
| **leading** `> out git commit` | **no** | **yes** | **✅ the only one** |
| mid `git >out commit` | yes | yes | ❌ |
| trailing `… 2>&1 \| tail` | yes | yes | ❌ |
| bare-digit `… 2 > out` | yes | yes | ❌ |
| proc-subst `> >(git …)` | yes | yes | ❌ |

The leading redirect is the *only* one of the five that flips `argv[0]`. Picking it was reasoning, not
luck — any of the other four would have produced a probe that always says FIXED and refuses every base.

**Fail-closed under abuse.** I built four broken baseline modules to attack the third `case` branch:
a syntax error, a `segments()` returning 3-tuples (whose unpack happens *outside* the `try`), a module
missing the symbol, and one that prints on import. All four land in the "cannot evaluate" branch and
refuse. None slips through as a false PRE-FIX.

**The pin is durable.** `bc7da76` is an ancestor of `main`, 7 commits back — a normal clone has it.
The stated "unreachable pin" risk is real only for `--depth 1` clones or rewritten history, and it
degrades to the named error, not a wrong answer. That is honest.

## What could go wrong / what I'm unsure about

**1. The same class is still live one file over, with a worse symptom.** `git-guard.replay.sh:13-15`
hardcodes `git show main:…` for *its* baseline and cannot be pointed elsewhere (only the candidate is
parameterisable). I ran it on this branch:

```
63 commands x 6 states = 378 pairs: 378 identical, 0 stricter, 0 relaxed (0 distinct commands)
```

That is a green, authoritative-looking result produced by comparing the fix against itself. The
falsifier's version of this bug screamed in red; replay's version smiles and says nothing — which is
the more dangerous half of the pair. There is a genuine defence: replay's question is "is this branch
ever weaker than *current* main", for which a moving base is correct by design. But the exact argument
used to justify part 2 of this fix — *"the pin alone cures the symptom and leaves the failure MODE
intact"* — applies word-for-word to replay, which has no guard against a degenerate baseline. The
class was named and then fixed in one instance. This repo's standing lesson is that patching one
instance of a class instead of enumerating it has bitten several rounds running. I looked repo-wide;
replay is the only other instance.

**2. Nothing runs the falsifier automatically.** No CI, no `Makefile`, no test runner, no hook
invokes it. Its green depends entirely on someone remembering. There is no `shell-segments-falsifier.test.sh`
either, so the new three-branch `case` has no committed coverage — and the note in the last ADR that
`shell_segments.py` having no suite is exactly what let the original defect survive applies here too.
Mitigating, and it is real: the self-check makes the pin *self-testing when run* — flip `BASE` back to
`main` and the script refuses loudly rather than lying. So the primary failure cannot silently return.

**3. The self-check licenses seven rows on one probed property.** A hypothetical base that fixed the
trailing-`2>&1` shape but not the leading one would be called PRE-FIX, and the `(a) false denial`
row would then print a `FAIL` that reads like a content regression — the original symptom, narrowed.
No such commit exists in this repo's history (the fix landed atomically at `64ba2fa`), and the outcome
is a loud failure rather than a silent pass, so this is a narrow residual, not a defect.

**4. Message asymmetry.** The three failure modes *are* distinguishable to a reader who did not write
them — different first lines and different vocabulary ("already contains the redirection fix" /
"cannot evaluate the baseline lexer" / "cannot read `<rev>:<path>`"). But only the "already fixed"
branch offers a remedy line; the other two say what is wrong without saying what to do. And the
"cannot evaluate" branch can dump a raw multi-line Python traceback with only its first line indented.
Cosmetic.

**5. Repeat finding, still open.** My verdict on `28e2053` flagged *"falsifier not linked from
hooks/README.md; orphan script like the existing replay harness"*. `hooks/README.md` still contains
zero mentions of it. The script that ADR 0015 designates as the load-bearing evidence for a Tier-1
guard is undiscoverable from the directory's own README.

**Calibration note on myself:** I passed `28e2053` at `risk=low confidence=high` and did not catch that
its baseline was a moving ref. That defect was found by post-merge human verification, not by me. I
have weighted this review accordingly and re-derived every claim by execution.

## What I'd double-check before merging

1. **Nothing, to block this merge.** The change is strictly an improvement to an evidence script; it
   cannot weaken any guard, and I re-ran everything.
2. **Queue `git-guard.replay.sh` as the immediate next item** — it needs a "base and candidate are
   identical, this proves nothing" guard, not a pin. It is currently emitting a false green.
3. Decide whether the falsifier now warrants a `.test.sh`, or at minimum a line in `hooks/README.md`
   telling a reader it exists, what its default base means, and that a red run may be the harness.
4. Consider a one-line amendment to ADR 0015 recording the pinned default, since that ADR is the
   document that sends readers to this script.

---

## Dimensions

| dimension | verdict | note |
|---|---|---|
| `intent` | **pass** | Both parts built exactly as decided; pin-only correctly rejected as leaving the failure mode intact. Scenarios A–D reproduce. |
| `execution` | **pass** | 492/492 verified by me across seven suites; four scenarios re-run; branch 3 independently proved reachable and fail-closed against four pathological modules. |
| `trajectory` | **pass** | The leading redirect is provably the only discriminating shape of the five — reasoning, not luck. Probe agrees with ground truth on all seven historical revisions. `$?` captured first, per the standing repo lesson. |
| `regression` | **pass** | Two files, one new doc; no guard logic touched; all suites green; replay output unchanged from its pre-branch behaviour. |
| `context_budget` | **pass** | No always-on surface touched — no `CLAUDE.md`, `rules/`, or skill growth. The 123-line feature file is on-demand; hook scripts never enter context. |
| `traceability` | **pass** | The *why* sits at the point of decision in the source, plus feature file, commit body, `session-state.md`, `CODING_MEMORY.md`, `pr-tracking.md`. Nit: `hooks/README.md` still never mentions the script. |
| `success_masking` | **concern** | Nothing runs the falsifier automatically and it has no suite, so its green depends on recall; and the identified class is still live in `git-guard.replay.sh`, where I measured a vacuous 378/378-identical green produced by comparing the fix with itself. |
| `intent_drift` | **pass** | Two files, both in scope. No dependencies, no drive-by edits, no unrelated renames. |
| `checkpoint` | **pass** | Single commit off `e0d8546`, clean working tree, `git revert d0dac2e` is a complete undo. |
| `audit_trail` | **pass** | Commit body reproduces the red output, both parts with rationale, the verification table, and the accepted limit. Fully attributable. |

## Concerns

- `git-guard.replay.sh` hardcodes `main:` as its baseline and now reports 378/378 identical — a vacuous green comparing the fix with itself; same class, worse (silent) symptom, not addressed here
- nothing runs the falsifier automatically (no CI, no runner, no `.test.sh`); its green depends on someone remembering, and the new three-branch `case` has no committed coverage
- the self-check licenses seven rows on one probed property; a partially-fixed base would be called PRE-FIX and emit a misleading `FAIL` (no such base exists in this history; fails loud, not silent)
- only the "already fixed" branch offers a remedy line; the "cannot evaluate" branch can dump an unindented multi-line traceback
- repeat finding from the `28e2053` verdict, still open: the falsifier is not linked from `hooks/README.md` despite ADR 0015 designating it the evidence for a Tier-1 guard
