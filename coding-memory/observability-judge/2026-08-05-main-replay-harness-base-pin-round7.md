# Observability judge — `replay-harness-base-pin` (architecting, round 7)

- **ts:** 2026-08-05T13:25:58Z
- **repo:** `.claude` · **branch:** `main` · **head_sha:** `8634fba446edbcb5d853df392488569134f59d5e`
- **spec:** `docs/features/replay-harness-base-pin.md` (revision 9, blob `ea2b820c`, 626 lines)
- **stage:** architecting (advisory — does not block)
- **risk: medium · confidence: high**

## What was changed

There is a tool in this repo whose only job is to compare two versions of a safety check and shout
if the new one lets something through that the old one blocked. The problem: the tool never says
*which* old version it compared against, and it can be silently comparing a program to **itself** —
which is like proofreading a document by holding it up against a photocopy of itself and announcing
"no differences found."

I ran the tool twice today to see this for myself:

| what I ran | what it printed | exit |
|---|---|---|
| `git-guard.replay.sh "$PWD"` (the normal way) | `378 identical, 0 stricter, 0 relaxed` | 0 |
| `git-guard.replay.sh .` (one character different) | `378 identical, 0 stricter, 0 relaxed` | 0 |

Run 1 compared main against main — the photocopy. Run 2 never executed the new version at all
(the path broke, every run crashed with exit 127, and the tool counted every crash as "agreement").
**Identical output. Both meaningless. Neither distinguishable from a real, clean pass.** The header
prints the literal word `main` no matter what, and the summary line names no baseline at all.

The design fixes this in six parts: let the caller name a baseline, check that every file actually
loaded, refuse to run when the two sides are the same program, resolve the folder path properly,
print the real 40-character commit id in every run, and write the rule down permanently in an ADR.

## Does it do what you wanted?

Yes. All four items from round 6 were taken, and I checked each one rather than taking the summary's
word for it:

1. **Task 7 now says A-L.** Verified — the checklist step that actually runs the scenarios no longer
   omits the falsifier the whole revision exists to add.
2. **The false safety claim is narrowed.** The `cmp` bullet no longer claims part 2 proved every file
   loaded; it now claims only what it can prove and names the residual out loud.
3. **The disk-reading rule is stated once**, and the membership paragraph's pointer ("stated once in
   its own bullet below") resolves — the target bullet opens with the same phrase, so it is findable.
4. **The history counts are pinned to a SHA.** I re-measured at `5bc39b9` in both directions and got
   **632 commits, 66 / 66, zero mixed-shape commits** — the spec's numbers reproduce exactly.

Also re-verified independently: `cmp -s` on two absent paths exits **2** (the mechanism behind
Scenario K); `e3b09ba`'s guard has **0** occurrences of `lib/`; `f5c5689`'s three blobs are still
byte-identical to HEAD's, so Scenario B's premise holds; all three code pointers (`git-guard.sh:44`,
`:53-57`, `:74-77`) are correct; all five citation sites resolve to the text the table claims; and
`CODING_MEMORY.md` no longer advertises the cancelled round-7 pass — it now says "do not cite a
passing verdict for this spec."

**On your headline question — did revision 9 repeat revision 8's mistake?** Mostly no. It touched
five sites and I could not find a *contradiction* among them. But it left one twin standing and one
known-stale line inside the block it edited. Details below.

## Dimensions

| dimension | verdict | why |
|---|---|---|
| intent | pass | Fixes exactly the defect described; all four round-6 items taken and independently verified. |
| execution | concern | Scenario set is genuinely discriminating (A–L + H), and every measured row I could re-run reproduced. But the on-disk-is-truth rule now has two consumers and still no scenario, and default-`worktree`-mode behaviour is described rather than specified. |
| trajectory | pass | Seven reads, each finding acted on, evidence-led; the spec previously retracted its own founding premise when measurement disproved it. |
| regression | pass | No code touched. Harness, `git-guard.sh` and ADR 0015 all explicitly out of scope; citations annotated, not retracted. |
| context_budget | pass | 626 lines under `docs/features/`, loaded on demand, not always-on. The nine-deep revision log is ~26% of the file — a maintenance surface, not a context cost. |
| traceability | concern | Numbers now carry provenance. But "disk" carries two opposite senses four bullets apart, revision 3's superseded bullet lacks the inline marker revisions 7 and 8 both carry, and revisions 2/4/5 are absent from the log with no note. |
| success_masking | concern | The subject matter itself. One un-narrowed over-claim survives; the default-mode silent pass is recorded but open; an empty on-disk candidate guard is unchecked (loud direction). |
| intent_drift | pass | Exemplary scope discipline: five recommendations deferred *with* written rationale, `git-guard.sh` untouched, ADR 0015 untouched by the repo's amend-by-new-ADR convention. |
| checkpoint | concern | Spec is committed and the phase gate holds (`planning`, `branch: none`, no code). But the verdict trail is uncommitted again — round-6 markdown untracked, both judges' JSONL modified in the working tree. Third round flagged. |
| audit_trail | pass | ADR 0016 is specified *with* the limits it does not close, so it cannot over-claim once permanent. `CODING_MEMORY.md` is accurate this round. |

## Concerns

1. **The twin over-claim, ten lines below the one you fixed.** The narrowed `cmp` bullet (`:156-162`)
   now correctly says part 2 does not cover the default `worktree` candidate. The *next* bullet
   (`:172-173`) still says: *"Part 2 has separately rejected the case where an absence is a broken
   extraction … so by the time part 3 runs, a set difference is signal."* Part 2 does not run against
   the default candidate, so a set difference originating on that side is **not** guaranteed to be
   signal — a truncated on-disk guard loses its `lib/` references, produces the set `{guard}`, differs
   from the base's set, and sails into the matrix labelled "signal". Same family, unmarked. Severity
   is limited because that failure is *loud* (an empty candidate allows everything, so every base
   block becomes a reported relaxation), but the spec's own standard is that a false safety claim is
   worse than the gap it hides.
2. **"Disk" now means two opposite things four bullets apart.** `:168` forbids *"reading membership
   off the disk"* (meaning: by file presence). `:177-178` mandates reading the candidate *"from disk,
   not `git show HEAD:`"* (meaning: which bytes are authoritative). Both are correct on their own axis
   and they do not contradict — but an implementer who conflates them has nothing in A–L that catches
   the mistake, because the axis they would get wrong is the deferral-1 one.
3. **Scenario D's stale comment survived the edit to Scenario D.** `:347` still reads *"Identical to
   Scenario A's counts"* — but A now refuses and prints **no** counts. Flagged in rounds 5 and 6 and
   carried again; revision 9 added the new header assertion on the line directly above it and left it.
   That is, in miniature, the exact drift pattern the revision exists to stop.
4. **Scenario D alone never demands a SHA.** Its header assertion *does* falsify a summary-only
   implementation (header `main` ≠ summary's resolved base → fails). But its summary clause says
   *"naming bc7da76 as the base"* — the rev string — and the header clause is comparative. So an
   implementation printing `base=bc7da76` in *both* places passes D outright. The 40-character-SHA
   requirement for a **successful** run rests entirely on Scenario I; the header-carries-a-SHA
   property is only derived transitively (D says header = summary, I says summary is a SHA) and holds
   only for a uniform implementation.
5. **`cmp` exit 2 on a present-but-absent member is described, not specified.** The residual note says
   *"`cmp` then reports 'not identical', the run is correctly judged non-vacuous."* Task 4 says only
   "compare sets first, then bytes, and never `cmp` a non-member." An implementer could just as
   reasonably raise a named error on exit 2 — arguably better — and nothing in the spec or scenarios
   chooses.
6. **Part 4 checks existence, not emptiness.** It fails if the worktree does not *contain*
   `hooks/git-guard.sh`; part 2's non-empty rule covers only the base and a rev candidate. A 0-byte
   on-disk candidate therefore passes. Loud direction, so low severity — worth one clause.
7. **Revision 3's superseded bullet has no inline marker.** `:601-603` still asserts *"Extraction
   validation covers all six `git show` calls"* — the rule revision 6 rejected. Revision 6 carries a
   forward reference ("Supersedes … below (revision 3)"), so a newest-first reader is safe, but
   revisions 7 and 8 both mark their superseded text *in place* (`⚠️ Refined by revision 8 above`,
   `(Superseded by revision 9 …)`). This is the one bullet that breaks the document's own convention,
   and it is the one a `grep` for "all six" lands on.
8. **Revision numbering has holes.** Headers exist for 9, 8, 7, 6, 3 and "revision 1". Revisions 2, 4
   and 5 appear nowhere, with no line saying whether they existed. The header says "what changed is
   recorded at the end, newest first" — a reader cannot tell if something is missing.
9. **The most-argued claim is still the least-tested.** On-disk-is-truth now has two dependents and
   zero scenarios. Deferral 1 remains correctly ranked first; it has got heavier again, which the
   spec says but the deferral ordering does not yet reflect in priority language.
10. **Verdict trail uncommitted, third round running.** `coding-memory/observability-judge/…round6.md`
    is untracked and both judges' JSONL files are modified in the working tree. The record of these
    seven reads currently exists only on this disk.

## Method note

My first history probe returned `0 of 632` and looked like a clean disproof of the spec's `66/66`.
It was wrong: zsh applied the `:h` history modifier inside `"$c:hooks/git-guard.sh"` even in double
quotes, so every lookup silently missed. `${c}:hooks/…` fixed it and the spec's figures reproduced
exactly. Separately, the `rtk` proxy on `git cat-file -e` does not preserve the exit code — it
reported a present blob as absent. Two silent-false-measurement traps in one session, in a review of
a document about silent false measurements.
