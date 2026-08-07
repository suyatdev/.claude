# Observability judge — memsearch-freshness (architecting, loop 2 round 10)

- **ts (UTC):** 2026-08-07T18:46:53Z
- **repo:** `.claude` · **branch:** `main` · **head_sha:** `85baf2d6c5dc3c2ee913d8d4edac72802a1378ec`
- **stage:** `architecting` (advisory — does not gate a PR)
- **artifact:** `docs/features/memsearch-freshness.md`, 1,289 lines, blob
  `022528c29a2b7ac9bd542f0271272855ceb4275d` — **verified against the invocation's expected blob, exact match**
- **checkpoint:** clean tree, `phase: planning`, `branch: none`, spec committed @ `85baf2d`
- **test command:** none supplied and no implementation code exists. I ran what *is* runnable —
  the golden retrieval suite, the live nudge, and direct reads of every cited source line — and say
  plainly below what that licenses and what it does not.

> **Round 9's four accepted findings: two closed, one closed-with-residue, one open and sharper than
> stated.** Risk stays **medium** — same level, different content. The freshness half is now the
> strongest artifact in this loop and I found nothing wrong with its mechanism this round. Everything
> below is about the acceptance half.

## What was changed

Picture a smoke detector that stopped chirping. For 19 days it reported "all good" on a flat
battery, and nothing anywhere checked. This spec designs two things: a timer that re-tests the
detector every six hours, and — deliberately first — **a display that shows the detector's real
state** instead of a number it remembers from a fortnight ago.

That defect is still live, and I watched it happen in this very session. My own `SessionStart`
printed `memsearch: 7631 chunks of past-session memory indexed` — a confident number with **no age
attached**, from a `status.json` whose `last_indexed` is `2026-08-06T23:56:46Z`, nearly 19 hours
old, and which carries none of the three fields this spec adds:

```json
{"chunks": 7631, "sources": 911, "last_indexed": "2026-08-06T23:56:46+00:00", ...}
```

Round 10 made nine text edits. The three that matter most: **both stored "derived surface"
inventories were deleted** on user direction — every stored copy had gone stale, twice *inside the
anti-staleness section itself* — and replaced by the sweep **method** plus a new task **1b** that
regenerates the sweep at implementation time and records it in that task's commit message. A
9-hour-run self-contradiction (stale in one scenario, stuck in another) was resolved. The retrieval
bar's pass mark moved to the step that grades it.

## Does it do what you wanted?

Yes for the nine directed edits — I verified each rather than accepting the summary, and I checked
the deletions left no dangling pointers:

| Round-10 claim | How I checked | Result |
|---|---|---|
| Both inventories deleted cleanly | `grep -n "inventor\|17-entry\|seven-entry\|the table below"` | Only the **historical narrative** survives (`:147-148`, `:332-333`). **No dangling reference to either deleted table** ✅ |
| Baseline pin is real and reproducible | Ran `uv run pytest -m golden -q` at HEAD | **16 passed, 63 deselected in 2.84s** — the spec pins *16 passed, 63 deselected, 2.53s*. Counts identical ✅ |
| A green golden run is *not* evidence | Read `test_golden_queries.py:35-60` + counted `kind` | **11 `must` / 3 `stretch` / 2 `negative`** — stretch and negative call `warnings.warn` and pass unconditionally. The spec's caveat is exactly right ✅ |
| Entry 11 is the predicted casualty | Read `golden_queries.json` line 12 | `"what were we working on in mid july 2026"`, `kind: must`, `{rtype: episodic, since: 2026-07-01}`, expects `.jsonl` — **exact** ✅ |
| Golden line 4 is the R10.5 target, line 2 is not | Read lines 2-5 | `:4` = *"why is CODING_MEMORY.md excluded…"*; `:2` = the sqlite-over-qdrant query. **Both exact** ✅ |
| `pyproject.toml:23` deselects golden | Read `:20-26` | `addopts = "-m 'not golden'"` at line 23 ✅ |
| The 9h stale/stuck contradiction is gone | Read both scenarios | `:781-786` and `:859-866` **both now say stuck**; state 2 covers 6h ≤ 9h < 24h with `run_started > last_run` ✅ |
| The pass mark reached the grading surface | Read task 10(b) | `:1271` — *"R9 passes iff all five queries satisfy both clauses — four of five is a failure, and this step is where that verdict gets written down"* ✅ |
| Falsifier (j) added, 10c reads (a)–(j) | Read `:1065-1067`, `:1278-1279` | Both present; (j) covers *both* the warm-run substitution and the proceed-anyway case ✅ |
| No `memory.db`-sourced chunk counts remain | `grep` for chunk figures | None. Character counts only ✅ |
| Toolchain table is true | Hit it live | My first command died on **`command not found: timeout`** — the table's *"No `timeout` binary on PATH"* row, confirmed the hard way ✅ |
| State surfaces agree with the table | `grep` for every `state N` / `states N`, walked all 20 against the table | **No disagreement found.** Decay from 1/2 always lands in 3 or 5, never a gap; `states 2,3,6,7 → the log` is exactly four of eight ✅ |

**Round-9 findings, closed:** the free pre-R10 control is now captured *and I confirmed it still
reproduces*; the pass mark now lives where the grading happens; task 9's stop-and-ask has a
falsifier clause at last (open since round 7). **Deleting both inventories was the right call** —
it matches the standing rule *delete the duplicate, don't sync it*, and moving the output to a
commit message closes the staleness route structurally, because a commit message is immutable and
dated and cannot rot in place.

## What could go wrong / what I'm unsure about

**1. The anti-gaming rule has a reading under which it cannot fail — and the spec's own falsifier
contradicts it.** R9 (`:335`) requires *"at least one target in the bottom third and at least one in
the top third"* of **"the corpus size range"** — and the population that range is drawn from is
still never named (round-9 concern 6, unclosed). The Gherkin scenario is the surface that decides
how this reads in practice:

```gherkin
When their target feature files are ranked by chunk count
Then at least one target is in the bottom third of the range
```

Ranked *among themselves*, the smallest of five is **always** in the bottom third of their own
range and the largest **always** in the top third. Under that reading the guard is a tautology.
Concretely — targets of 80, 75, 70, 65, 40 chunks: range 40–80, bottom third ≤53.3 (40 qualifies),
top third ≥66.7 (three qualify). **Passes.** Yet falsifier (i) names that exact shape as a
falsification: *"four large targets plus one medium is a falsification"* (`:1064`). Two derived
surfaces of one rule now disagree about whether the same sample passes. This is the single most
consequential open item, because it is the guard protecting the branch's only measurement of R10.

**2. The per-feature counting unit reached three places; there are four.** Round 10 states the unit
in R9 (`:338`), falsifier (i) (`:1062`), task 8b (`:1226`) and task 10(b) (`:1272`) — but the
scenario at `:1018-1022` still says *"their target **feature files** are ranked by chunk count"*,
per-file language in the one surface closest to an executable check. R9 itself calls per-file *"a
different and weaker rule"*. The round-10 summary said "all three places that restate it"; the
sweep's job is to find the fourth.

**3. A two-item inventory survived the inventory purge, and it is already incomplete.** `:348` reads
*"This exact wording is the rule; task 8b and falsifier (i) restate it verbatim"* — a stored list of
derived surfaces, sitting in the section that just deleted its stored lists for rotting. It names
two; task 10(b) (`:1272`) restates the unit too, and the scenario restates the spread rule. Small,
but it is the same species, in the same section, one round later.

**4. Task 1b is the right instruction with no carrier and no mechanism.** Three separate points:

- *No commit to attach it to.* Task 1b is "first task after the gate, **before any code**" and it
  changes no files — it is a sweep. Its deliverable is *"record the output in that task's commit
  message"*, but a commit needs a change; an empty commit (`--allow-empty`) is never named. An
  implementer will fold it into task 2's commit, or skip recording it. **The deliverable has no
  defined carrier.**
- *Not mechanizable as written.* Compare R10.6, which hands the implementer a literal command
  (`grep -n CODING_MEMORY`, and I confirmed the 14-hit claim last round). The R3/R9 sweep is prose,
  and it explicitly demands finding things no grep can find — *"a state named in prose, without its
  number, is still a surface"*, *"an ordering claim is duplication"*. It rests on exactly the careful
  reading that under-counted in rounds 5, 6, 7, 8 and 9. Deleting a wrong map removes the false
  confidence; it does not make the territory easier to survey. **Finding 2 above is live evidence:
  the drift the sweep must catch is sitting in the document right now.**
- *The escalation leaves no artifact.* A contradiction raises `"GATE: Spec change needed"` — correct,
  and correctly reasoned (spec edits are out-of-phase during implementation). But that is a spoken
  announcement in a session; nothing persists it. And note the enforcement reality from
  `rules/gates.md`: the phase guard **exempts `docs/*`**, so nothing computational prevents the
  in-place spec edit the task forbids. Detect-and-escalate is a discipline here, not a control.

**5. R9 still has no control of its own, and still pre-commits to a causal reading.** Task 10(b)
`:1274` — *"A failure of either clause is a real result about R10's noise cost"* — while the five
queries are authored **after** task 7 lands (task 8 is explicitly ordered after it) and run **once**,
afterwards. This is much improved: 10(a) now has a genuine before/after that I verified reproduces,
and entry 11 is pre-registered as a predicted casualty with the correct reading written down in
advance, which is real protection against explaining a failure away. But the spec says the two
instruments *"are not the same instrument and neither substitutes for the other"* and then never says
how to read them jointly — so if golden holds at 16/16 except the predicted entry 11 and R9 still
fails, nothing tells the reader that attribution to the archive is now weakly supported at best.
Round 9's live probes found the dominant crowders were judge files at weight **1.5**, above the
archive's proposed 1.0.

**6. The spec's own thesis, one field over — and it rotted again inside the round.** The archive is
pinned at *300,160 characters / 3,484 lines*. Measured just now: **320,406 characters / 3,723
lines** — **+239 lines and +20,246 characters**, in a document whose round-10 edit deleted two chunk
counts on the grounds that stored numbers rot. Character counts read from disk rot too; only the
cause differs. Two of three copies (`:455`, `:1235`) carry no caveat. Consequently the stated
**1.62×** multiplier is now at least **1.73×** against the same denominator — understating the risk
it exists to size. *(I could not verify the 184,620-character denominator: the named vibe-scape file
is not at any path I searched, so I report only the numerator drift I actually measured.)*

**7. Carried, structural, unchanged — the honest limit of the whole design.** A run that walks
**zero files** completes cleanly, stamps `last_run` at now, leaves `chunks` at its prior non-zero
value, and renders as **state 8, fresh, indefinitely**. That is the *same species* as the founding
defect — the indexer ran "successfully" for 19 days while never walking `CODING_MEMORY.md`. It is
named, bounded, pointed at its fix, and out of scope by user decision. But it means the direct
answer to the question I was asked to weigh is: **this design cannot reproduce its own founding
failure in the general case.** It fixes that instance by config; nothing detects the class.
Alongside it: **silence still equals health** — absent `status.json`, `chunks == 0`, an unregistered
hook and a file unreadable mid-rebuild are all indistinguishable from a healthy quiet start, and the
data-flow diagram's own dotted edge says *"the staleness line **is** its monitor."* **The monitor has
no monitor.** Also carried: **no prune path** (re-excluding the archive leaves its chunks scored and
returned until a multi-hour `--full`); **`scheduled-index.log` is unbounded** and is the destination
of four of eight lines; **falsifier (c)** is still unobservable at task-10c time, now honestly
absorbed by 10c's *"not yet observable"* option rather than resolved.

## What I'd double-check before merging

All text edits, `phase: planning`, before a line of code exists. In order of value:

1. **Name the population the "range" is drawn from** (the ten feature files? the whole indexed
   corpus?) and fix the scenario at `:1018-1022` so it cannot be read self-referentially. As written,
   the guard admits a reading in which it cannot fail, and falsifier (i) already disagrees with it.
   *My pick: state it as the ten `docs/features/` targets, per-feature summed — that population
   genuinely bites and is computable at task-8 time.*
2. **Put the per-feature counting unit in the scenario too** — it is the fourth restating surface and
   the only one still in per-file language.
3. **Give task 1b a carrier**: say explicitly that it commits with `--allow-empty`, or that it rides
   on task 2's commit. Otherwise its output has nowhere to land.
4. **Delete or caveat the two uncaveated archive figures** (`:455`, `:1235`) — now stale by 239 lines
   — and either recompute or drop the `1.62×`.
5. **Soften `:1274` or connect the two instruments**: say that a red R9 alongside a clean 10(a) means
   attribution is unresolved, not that it is R10's noise cost.
6. **Drop the mini-inventory at `:348`**, or accept it will need the same sweep as everything else.

Not asked for, noted only: the sweep's output lands in a commit message — durable and dated, but
**not in the indexed corpus this feature exists to improve**, so the next reader cannot retrieve it
with `memsearch`.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | **pass** | All nine directed edits present and correctly executed; I verified each against the artifact rather than the summary, including that both table deletions left **no dangling references**. Nothing added beyond them. Scope still stops at parent item 5; reporting-before-scheduling ordering still argued, not assumed. |
| execution | **concern** | No code exists; scored on design-verifiability against the live tree. The freshness half is excellent and I re-verified it: 20 state surfaces all agree with the table, decay never gaps, every code citation re-checked is exact (`pyproject:23`, golden `:4` and `:12`, the 11/3/2 harness split), and the toolchain table proved true when `timeout` killed my first command. Held at concern for the acceptance half: task 1b has no carrier commit and no mechanism, the spread rule's population is undefined with a vacuous reading available, and the scenario retains the weaker per-file unit. |
| trajectory | **pass** | Round 10's reasoning is sound and root-directed. Deleting both inventories rather than syncing them a third time is correct and matches the standing *delete the duplicate, don't sync it* rule; routing the output to a commit message closes the staleness route structurally (immutable, dated, cannot rot in place). Pinning the pre-change baseline, moving the pass mark to the grading surface, deleting `memory.db`-derived counts and adding (j) each address the round-9 finding at its cause. The one trade I would have liked weighed aloud: removing the map without making the territory mechanically surveyable swaps a wrong-but-checkable artifact for an unchecked one — defensible, user-directed, and honestly the lesser evil, but it puts the full weight on task 1b. |
| regression | **pass** | Documentation-only; no mechanism, dependency or behaviour change. The implementation it designs remains enumerated with verified exactness, and I confirmed the two deletions orphaned nothing — the surviving references at `:147-148` and `:332-333` are deliberate history, not pointers. |
| context_budget | **pass** | Feature doc, not always-on content. The `SessionStart` nudge is one line in every state — observed live this session. 1,289 lines, **+19 despite deleting two tables**: the correction narrative keeps growing, ~15 blocks now, and R9 still spends ~34 lines on a deleted clause's obituary (round-8 concern 10, open, migration target ADR 0019 already named). A named cost at this scale, not a finding — but a document arguing against duplication that grows while deleting duplicates is worth watching. |
| traceability | **concern** | Improved: the sweep's *method* is now the deliverable, and its output goes somewhere immutable and dated. Held at concern for three residues — a two-item inventory survives at `:348` inside the section that purged inventories, and is already incomplete (task 10(b) restates the unit too); the sweep output lands in a commit message, outside the corpus this feature exists to make searchable; and the archive size figures have rotted again (3,484→**3,723** lines, 300,160→**320,406** chars, two of three copies uncaveated, `1.62×` now ≥**1.73×**). A map that misdescribes the territory is a traceability defect, even when the map is two lines long. |
| success_masking | **concern** | Genuinely strengthened this round and I verified the strengthening: the pre-R10 control is pinned **and reproduces exactly** (16 passed, 63 deselected), entry 11 is pre-registered as a predicted casualty so its failure cannot be re-narrated afterwards, and the spec states plainly that a green golden run is not evidence — which I confirmed at the source (**11 `must` can fail; 3 `stretch` + 2 `negative` warn and pass regardless**). Task 4's *"every test asserts the emitted line, not the parsed field"* remains the strongest control in the document. What holds it at concern: **(1)** the zero-walked-files run still renders state 8 fresh indefinitely — the founding defect's own species, disclosed and bounded, but it means nothing in this branch can reproduce the original failure; **(2)** silence still equals health and the nudge is the scheduler's only monitor, by the diagram's own admission; **(3)** `:1274` still pre-commits a clause failure to R10's noise cost with no control over R9's five queries and no rule for reading the two instruments jointly; **(4)** the spread rule admits a reading under which it cannot fail, contradicting falsifier (i). |
| intent_drift | **pass** | Only the nine directed edits and their forced consequences. No new dependencies, no drive-by edits, no scope growth; the deleted tables were removed on explicit user direction and I did not re-litigate them. Verified against the round-9 text, not the summary. |
| checkpoint | **concern** | Spec committed at `85baf2d`, clean tree, `phase: planning`, `branch: none` — correct, and the absent implementation branch is by design. Held for: **task 1b's deliverable has no carrier** (it changes no files; `--allow-empty` unstated), task 7 remains a deliberately coarse seven-part single commit — correctly justified, still the branch's riskiest change in one revert unit — and there is still **no prune path** for chunks already embedded. Credit sustained: R7 making `--uninstall` first-class is a real checkpoint control for an artifact living outside the repo where `git revert` cannot reach. |
| audit_trail | **pass** | Dated, attributed user decisions throughout; ADRs 0018 and 0019 both scheduled as tasks; every removal keeps its evidence and its date, including this round's account of why both inventories died. Task 1b's escalation phrase is verbatim and quotable. One honest gap, recorded under concerns rather than held against this dimension: the escalation produces an announcement, not an artifact. |

**risk: medium · confidence: high**

Confidence is high because every claim above rests on a measurement I took at HEAD: the blob hash
confirmed against the invocation's expected value; `pytest -m golden` executed; the golden harness
and query file read line by line and the `kind` split counted; `pyproject.toml`, `settings.json` and
the live `status.json` read; `wc -l -c` on the archive; an independent `grep` sweep of all 20 state
surfaces walked against the table by hand; both 9-hour scenarios read in place; and this session's
own `SessionStart` line observed reproducing the defect live.

Risk is **medium** and means "one more text pass, not a redesign" — the same level as round 9 but for
different reasons, since two of round 9's four findings are genuinely closed. The freshness half I
would ship as designed. The medium mark is for the acceptance half, and it now concentrates in one
place: **the guard protecting the branch's only measurement of R10 admits a reading under which it
cannot fail, and the document's remaining self-check is a hand sweep with no carrier, no mechanism,
and a live example of the drift it is supposed to catch sitting in the file right now.** For a
feature whose thesis is *"the observability is the feature,"* the instrument that grades it should
not be the least mechanized artifact in the document.

## Concerns

1. **The spread rule admits a reading under which it cannot fail** — "the corpus size range"
   population is still unnamed (round-9 concern 6, open); ranked among themselves, the min of five is
   always in the bottom third and the max always in the top third. Falsifier (i) explicitly falsifies
   the shape (80/75/70/65/40) that this reading passes — two surfaces of one rule, now disagreeing.
2. **The per-feature counting unit reached three surfaces of four** — the scenario at `:1018-1022`
   still says "target feature **files** … ranked by chunk count", the per-file language R9 calls "a
   different and weaker rule". Live drift, sitting in the file, of exactly the class task 1b must catch.
3. **Task 1b's deliverable has no carrier** — it changes no files, so "record the output in that
   task's commit message" has nothing to attach to; `--allow-empty` is never named.
4. **Task 1b's sweep is not mechanizable as written** — prose method, and it explicitly requires
   finding surfaces no grep can find ("a state named in prose"); it rests on the same careful reading
   that under-counted in rounds 5–9. Contrast R10.6, which hands over a literal `grep -n` command.
5. **The escalation leaves no artifact** — `"GATE: Spec change needed"` is a spoken announcement;
   nothing persists it, and the phase guard exempts `docs/*`, so the "no in-place spec edit" premise
   is discipline, not enforcement.
6. **A two-item inventory survived the inventory purge and is already incomplete** — `:348` names
   task 8b and falsifier (i) as the restating surfaces; task 10(b) `:1272` restates the unit too.
7. **R9 still has no control of its own and `:1274` still pre-commits attribution** to R10's noise
   cost; task 10(a)'s verified before/after is corpus-level only, and the spec declines to let either
   instrument inform the other's reading.
8. **The archive figures rotted again inside the round** — 3,484→**3,723** lines, 300,160→**320,406**
   characters (measured at HEAD); two of three copies uncaveated (`:455`, `:1235`); `1.62×` is now
   ≥**1.73×**, understating the risk it exists to size.
9. **A run that walks zero files still reads as state 8, fresh, indefinitely** — the founding
   defect's own species; bounded Non-goal, correctly pointed, still live. Nothing in this branch can
   reproduce the original failure in the general case.
10. **Silence still equals health** — absent `status.json`, `chunks == 0`, an unregistered hook and a
    file unreadable mid-rebuild are indistinguishable; the nudge is the scheduler's only monitor by
    the diagram's own admission, and has none of its own.
11. **No prune path** — re-excluding the archive after a failing R9 leaves its chunks scored and
    returned until a multi-hour `index --full`. Disclosed and accepted.
12. **`scheduled-index.log` is unbounded** and is the destination of four of the eight nudge lines;
    rotation needs task 9's size figure. Disclosed Non-goal.
13. **Falsifier (c) remains unobservable at task-10c time** — now honestly absorbed by 10c's "not yet
    observable" option rather than resolved; its "20 sessions after it lands" window has no scheduled
    re-read.
14. **R9 still devotes ~34 lines to a deleted clause's history**; the document grew +19 lines in a
    round that deleted two tables. Migration target (ADR 0019) already named.
