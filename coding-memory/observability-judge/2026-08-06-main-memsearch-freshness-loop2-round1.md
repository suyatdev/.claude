# Observability judge — `memsearch-freshness` R10 (architecting, advisory)

- **repo:** `.claude`
- **branch:** `main` (`branch_slug`: `main`)
- **head_sha:** `3b793fa0df4e2d4d1f0ecb598edf6bc86cc6c567`
- **stage:** `architecting` (advisory — does not gate a PR)
- **spec:** `docs/features/memsearch-freshness.md` (659 lines, `phase: planning`, `branch: none`)
- **round:** fresh loop, round 1 (prior loop passed at its round 4; user reversed a decision, spec materially revised)
- **test command:** none supplied. No code exists yet (`phase: planning`), so nothing was run. Not a fabricated pass — there is nothing to run.
- **judged:** 2026-08-06T23:44:03Z

**Filename note.** The plain `2026-08-06-main.md` slot is already occupied by the `memory-system-split`
verdict written at 05:15 today. This directory's existing convention for repeat reads on `main` is
`<date>-main-<feature>-round<N>.md` (see the `replay-harness-base-pin` and `memsearch-freshness`
round2–4 files). Overwriting another feature's verdict to satisfy a filename rule would destroy the
audit trail this file exists to create, so the disambiguating suffix is used.

---

## ⚠️ Leading with the failure

**`intent`, `execution`, and `success_masking` are `fail`.** R10 — the requirement this round exists
to judge — does not deliver its stated goal, and every acceptance signal the spec defines would go
green anyway.

**R10 as specified will not index `~/.claude/CODING_MEMORY.md`.** The six-part change lifts the
exclusion, but nothing in the indexer ever *reaches* that file. Removing an entry from `exclude_paths`
only matters for files the enumerator already walks.

Verified from source and from the live index, not inferred:

| Check | Result |
|---|---|
| `_iter_docs` (`memsearch/memsearch/index.py:43-53`) enumerates exactly two things | `cfg.curated_docs` (each entry: the file itself, or `rglob("*.md")` if a dir) and `cfg.repo_roots` (`rglob("*.md")`) |
| `curated_docs` in `memsearch/config.json` | `["~/.claude/coding-memory", "~/.claude/docs", "~/.claude/PORTS.md"]` |
| `repo_roots` | `vibe-scape`, `Snatch-Bracket` — **`~/.claude` is not a repo root** |
| Where the target file lives | `~/.claude/CODING_MEMORY.md` — top level of `~/.claude`; not under `coding-memory/`, not under `docs/`, not `PORTS.md`, not in a repo root |
| **Control:** `~/.claude/CLAUDE.md` (same directory level, 3,242 bytes, exists) | `SELECT count(*) … path='…/.claude/CLAUDE.md'` → **0 rows.** The `~/.claude` root is not walked. |
| **Control:** `~/.claude/PORTS.md` | 1 row — and only because it is an *explicit single-file entry* in `curated_docs` |
| Sources grouped by root | transcripts 419 · vibe-scape 152 · Snatch-Bracket 145 · `.claude/coding-memory` 133 · `.claude/docs` 47 · `.claude/PORTS.md` 1. Nothing else from `~/.claude`. |

So what R10 actually lands is `vibe-scape/CODING_MEMORY.md` (159 lines / 10,852 chars) and
`Snatch-Bracket/CODING_MEMORY.md` (119 lines / 6,980 chars) — verified by `wc`, matching the spec's
own line counts exactly. What it does **not** land is `~/.claude/CODING_MEMORY.md`
(3,232 lines / 285,187 chars) — the file whose three-week retrieval hole is the entire stated
justification for the requirement.

The spec has the emphasis exactly inverted. It writes: *"vibe-scape (159 lines) and Snatch-Bracket
(119 lines) join `~/.claude`'s 3,232. Their combined 278 lines are negligible against the corpus."*
Those 278 negligible lines are the **whole** delivery; the 3,232 are the part that does not arrive.

### Why this is `success_masking` and not just a bug

Five independent green signals are all satisfiable with the goal unmet. This is the concerning part —
the design's own safety net certifies the non-delivery.

1. **The flipped test's fixture pre-creates the reachability production lacks.**
   `test_index.py:58` writes the fixture file as `(curated / "CODING_MEMORY.md")` — i.e. *inside* a
   curated-docs root. R10.3 flips `test_index.py:93` from asserting exclusion to asserting inclusion.
   It will pass, because the fixture puts the file somewhere the enumerator reaches. Production does
   not. (This is the recorded lesson *a fixture must not pre-create the state under test*, recurring.)
2. **`test_config.py:48`** is a pure `is_excluded()` unit check on a synthetic path — it never touches
   enumeration. Flips green.
3. **`test_config.py:42`** removal is trivially green.
4. **The acceptance scenario is worded so it cannot fail.** *"Then a sources row exists for
   `CODING_MEMORY.md` in every repo root."* `~/.claude` is **not** a repo root, so the two small files
   satisfy the scenario in full.
5. **Task 9 repeats the same wording** — *"`CODING_MEMORY.md` now has a `sources` row in each repo
   root."* Same blind spot, same pass.

And the compounding one: **R9 is named as the instrument that measures R10's noise risk.** The spec
says *"if narrative chunks crowd feature files out of the top hits, R9 fails and says so… a failure
is a real result, not a reason to quietly re-exclude."* But the corpus would grow by 17,832
characters, not 285,187. R9 returns a clean pass, and the reader concludes the noise risk was
measured and cleared — when the change that carried the risk never landed. A green measurement of an
absent change is worse than no measurement.

The cheapest known fix shape is a one-line addition of `~/.claude/CODING_MEMORY.md` to `curated_docs`
(exactly how `PORTS.md` is reached today). **Diagnosing is my job; deciding and implementing is not** —
`curated_doc` carries weight `1.5` vs `repo_doc`'s `1.2`, so which enumerator the file joins changes
its retrieval weighting, and that is a design call for the author.

## The verified-true part

I was asked to check R10's central factual claim rather than accept it. **It holds, precisely.**

- `coding-memory/session-log.md` — last dated entry **2026-07-16** (file mtime Jul 18). ✅
- `coding-memory/decisions.md` — last dated entry **2026-07-19** (mtime Jul 20). ✅
- `CODING_MEMORY.md` — carries sessions **17 through 30**, so 24–30 as claimed, all dated 2026-08-06. ✅
- `CODING_MEMORY.md` — **285,187 chars / 3,232 lines**, exact. ✅
- The `ConfigError` guard is real and enforced at `config.py:56-59`; `README.md:22` and the three
  pinning tests are all where R10 says they are. ✅

The promotion pipeline **has** stopped, and the exclusion's original rationale **is** falsified. The
reversal is correctly motivated. One caveat on the framing: the hole is narrower than "three weeks of
decisions and history exist *only* in that file" — `docs/decisions/` ADRs are current (0017 dated
Aug 6), and `coding-memory/pr-tracking.md` (61 KB, Aug 6), `compliance-judge/` and
`observability-judge/` are all live and indexed. What is genuinely lost is the *narrative session
log*, not the decision record. Worth correcting in the ADR so it does not overstate its own case.

One citation slip: `golden_queries.json:2` is the sqlite-over-qdrant query; the CODING_MEMORY query is
on line 4 (array index 2). The spec quotes the query text verbatim, so intent is unambiguous —
cosmetic only.

## Do the three prior open items change weight under R10?

- **(1) `last_run_errors` has no unusable-value rule** — *unchanged, still open.* The contract table
  defines "usable" for the two timestamps only ("*for both fields*"); a malformed or missing
  `last_run_errors` still falls to a natural `0` default and prints the reassuring line. R10 adds
  sources, so it marginally widens the window in which a real error count exists to be misread, but
  the defect is orthogonal.
- **(2) A permanently-failing source pins the count at 1 forever** — *weight barely changes, because
  R10 barely changes the corpus.* Two small, well-formed markdown files are a low-probability
  permanent-failure surface. **This inverts if R10 is fixed**: a 285,187-char file becomes a
  meaningfully larger and more failure-prone single source, and a persistent failure on it would fire
  the degraded warning every session with no way to clear it — decision 1's own alert-fatigue failure
  mode, arriving through a different door. Worth resolving *before* the reach is corrected, not after.
- **(3) The error line points at re-running the indexer, not `scheduled-index.log`** — *unchanged.*
  R6 creates the evidence file; no line ever names it. Still the weakest reporting edge.

## Run duration / `RUN_MAX_HOURS`

- **As written, no interaction.** +17,832 chars against a 683-source run is noise. The spec's own
  stated worry (*"roughly 2.5× the largest doc currently indexed"*) is a worry about something that
  will not happen. Confirmed: the largest indexed doc today is 130 chunks
  (`coding-memory/compliance-judge/2026-07-26-03b-deploy-design.md`).
- **If R10 is fixed, still modest.** One 285 KB doc goes through `chunk_doc` (correctly excluded from
  the `digest_input_char_cap` path — the spec's note there is accurate) and adds a few hundred
  embed calls to a run already spanning hundreds of sources. Additive, not transformative.
- **The real duration risk is pre-existing and correctly handled.** The true full-run wall clock is
  unmeasured — the spec says so plainly, names its own earlier 1h26m figure as a stopwatch glance
  misrecorded as a finish time, and routes the decision to task 9 with an explicit stop-and-ask if it
  exceeds 6h. That is exemplary and I have no criticism of it.
- **Minor, low confidence:** `RunAtLoad: true` plus an idempotent re-run of `install-schedule`
  (bootout → bootstrap) starts an index immediately, which could stack on a manual run. `launchd`
  keeps one instance per label, so `StartInterval` firing during a long run should not itself spawn a
  second indexer — I did not verify that empirically and am not asserting it as fact.

## Dimensions

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | **fail** | R10's six parts do not index the file R10 exists to index; ~278 of 3,510 target lines land |
| `execution` | **fail** | Every defined test, scenario and task-9 check passes with the goal unmet; `test_index.py:58`'s fixture supplies reachability production lacks. No code to run at this stage |
| `trajectory` | concern | Reasoning is unusually rigorous and self-critical — it caught this exact error class for parent item 2 ("no-op — nothing to add") and recorded three measurement traps — but did not apply its own method to R10's reach claim |
| `regression` | pass | `subagents/` assertions explicitly preserved; existing `status.json` keys, `last_indexed`, and the CLI exit contract explicitly unchanged; guard deletion scoped and justified |
| `context_budget` | pass | Nudge stays at one line, exit 0 on all paths, no second interpreter start, no always-on rule growth |
| `traceability` | pass | ADRs 0018 and 0019 assigned; decisions enumerated with rationale; falsifier written before code; the premise refresh and the weakened blindness guarantee both recorded rather than smoothed over |
| `success_masking` | **fail** | Five green signals compatible with non-delivery, plus R9 — the designated instrument for the noise risk — returning a false all-clear on a change that never landed |
| `intent_drift` | pass | User-directed reversal, bounded to one commit, cross-repo reach named deliberately, non-goals enumerated (no re-scoping, no promotion revival, no lock) |
| `checkpoint` | concern | R7's `--uninstall` is a genuinely strong revert path for the out-of-repo plist. But `git revert` of the config restores the exclusion without removing the chunks already embedded into `memory.db`; no DB cleanup is stated |
| `audit_trail` | pass | Evidence measured and dated; ADR-worthy decisions identified and assigned; attribution clear |

**risk: high · confidence: high**

Risk is high not because the design is careless — it is one of the more rigorous specs in this repo —
but because the specific failure mode is *"green tests, silent non-delivery"*, which is the exact
defect class this entire feature exists to eliminate. Confidence is high: verified from the
enumerator source, the live `sources` table, the test fixture, and a same-directory control
(`CLAUDE.md`, 0 rows).

This read is **advisory** and blocks nothing.

## Concerns

1. R10 does not index `~/.claude/CODING_MEMORY.md`: `_iter_docs` walks only `curated_docs` and `repo_roots`, and the `~/.claude` root is neither
2. `~/.claude/CLAUDE.md` is unindexed at the same directory level — control proving the root is not walked
3. R10 delivers 278 lines (vibe-scape + Snatch-Bracket); the 3,232-line file motivating it stays out
4. The spec's scope note inverts the emphasis — the "negligible" 278 lines are the entire delivery
5. `test_index.py:58`'s fixture writes the file under `curated`, so the flipped inclusion assertion passes regardless
6. The acceptance scenario says "in every repo root"; `~/.claude` is not one, so it cannot fail
7. Task 9's confirmation repeats the same "each repo root" wording and inherits the same blind spot
8. R9, named as the instrument measuring R10's noise risk, would pass on a corpus that never grew
9. Which enumerator the file joins changes its weight (`curated_doc` 1.5 vs `repo_doc` 1.2) — an unmade design call
10. "Three weeks of decisions and history exist only in that file" overstates it: ADRs and pr-tracking are current and indexed; the narrative session log is what is lost
11. `last_run_errors` still has no unusable-value rule; the natural `0` default prints the reassuring line
12. A permanently-failing source still pins the degraded warning on forever — risk grows once R10's reach is fixed
13. The degraded line still points at re-running the indexer, never at `scheduled-index.log`, the evidence R6 creates
14. No stated cleanup for chunks R10 adds to `memory.db`; reverting the config does not un-embed them
15. `golden_queries.json:2` cites the wrong line (the query is on line 4) — cosmetic
