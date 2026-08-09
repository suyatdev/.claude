# Observability verdict — `docs/r9-counterfactual-control` @ `52b09c3`

- **repo:** `memsearch-freshness` (worktree of `~/.claude`)
- **branch:** `docs/r9-counterfactual-control`
- **head_sha:** `52b09c39526cdb19a35049b59a89aef2a4595b6a`
- **base:** `origin/main` @ `64d8acb` (local `main` is stale at `8d79094`; the caller's base is the
  correct one, and the diff below is taken against it)
- **stage:** implementation
- **ts:** 2026-08-09T16:56:23Z
- **diff:** 2 files, +120 / −1 — `docs/features/memsearch-freshness.md`, `CODING_MEMORY.md`. No
  source, no tests, no config.
- **test command run by me:** `cd ~/.claude/memsearch && uv run pytest -q` → **74 passed, 23
  deselected in 0.34s**. Matches the caller's report exactly. It exercises nothing in this diff.

---

## What was changed

Somebody ran an experiment that had been promised-but-not-done, and wrote down what it showed.

The setup, in plain terms: there is a search index over this repo's notes. A five-question quiz
("R9") checks that searching for a topic actually surfaces that topic's own document. Three of the
five questions are failing. The obvious suspect was **this very document** — it had grown so large
that its own write-up about the quiz was crowding out the answers the quiz was looking for. A note
that eats its own homework.

The experiment is a **leave-one-out**: copy the index, delete one group of documents from the copy,
re-run the five questions, and see if any answer changes. The result:

- Remove this document → **nothing changes.** The prime suspect is innocent.
- Remove the session archive → **nothing changes.** The previous prime suspect is also innocent here.
- Remove the **judge verdicts** (files like this one) → **two answers change**, one for the better
  and one for the worse.

The named mechanism is a nice piece of evidence: on a question about the `git-guard-empty-index`
feature, three chunks of the *judge verdict about that fix* rank above the feature's own second
chunk. I verified the structural part myself — `memsearch/config.json` puts `~/.claude/coding-memory`
(where verdicts live) and `~/.claude/docs` (where feature specs live) in the same `curated_doc`
tier at weight **1.5**, and `coding-memory/observability-judge/2026-08-03-fix-git-guard-empty-index.md`
is **639 lines** against the 375 lines of the feature doc it grades. The review of the thing is
bigger than the thing, at the same weight. That crowding is real regardless of the experiment.

## Does it do what you wanted?

Yes, and the method is the best this document has shown across five rounds.

Three decisions carried real weight, and I could confirm the one that mattered most:

- **The index was pinned before measuring.** A snapshot was taken at 8960 chunks; I checked the live
  index just now and it reads **9016 chunks, `max(indexed_at) = 2026-08-09T16:55:31+00:00`**. It has
  moved twice since. Measuring against "current" would have explained a corpus the monitor never saw.
  That was not ceremony — it was the difference between an answer and an artefact.
- **The no-op guard was treated as non-optional.** If the rebuilt harness doesn't reproduce the real
  `search()` path-for-path, every column is void. It matched on all five queries.
- **Noise was measured, not assumed.** I confirmed `memsearch/memsearch/ollama.py`'s `embed()` passes
  only `{model, input}` to `/api/embed` — there is genuinely no seed, so non-determinism was a live
  hypothesis rather than a rhetorical one. Verdicts held identical across 8 re-embeddings, which
  kills the "it's just wobble" explanation without pretending the wobble isn't there.

The honesty markers are also present: the finding does **not** retract the earlier 10b attribution
(different index state, not reconstructed), it flags that dropping judges *regresses* another query,
and it records a method limitation the original derivation omitted.

## What could go wrong / what I'm unsure about

**1. "Sufficient to restore" is not the same as "the cause" — and the excerpt hides where a rival
explanation would live.** The depth-10 dump prints ranks 1, 2, 3, 5, 7, 8. Ranks **4, 6, 9 and 10 are
elided.** In a rank-based system a chunk at rank 8 only needs three slots freed to re-enter the top
six; if two of the unshown slots were archive chunks, removing the archive alone would move it to
rank 6 and still fail, while removing judges alone succeeds — and "judges are the driver" would be a
sufficiency result dressed as a uniqueness result. The temporal argument (the judge batch landed
2026-08-08T10:30, after 10b) does real work here and partly covers this, but the four missing rows
are the cheapest possible way to close it and they are the four that were dropped.

**2. The headline claims more than the body does.** The section heading, the commit subject, and the
`CODING_MEMORY.md` entry all say *the cause is the judge corpus*. The body is careful and
state-scoped; the summary sentences are not. This matters more here than usual, because
`CODING_MEMORY.md` is itself indexed at weight 1.5 and will be **retrieved standalone**, detached
from the hedging two paragraphs down. This document has already required three corrections for
exactly this species — a summary outrunning its table — and this is the fourth instance, even though
the underlying work is the soundest of the five rounds. In fairness: `minus judges` improves hit
counts on three of five targets (1→2, 1→3, 2→3), so "judges crowd broadly" is *better* supported
than a single flip suggests. The overreach is the definite article, not the direction.

**3. The FTS/BM25 dismissal is asserted, not measured.** Recording the caveat is a credit — the
derivation omitted it. But "it does not threaten these verdicts — the flips are driven by chunks that
survive in both variants" explains *survival*, not *rank invariance*, and RRF consumes ranks. Dropping
237 judge chunks raises the IDF of terms concentrated in them (`git-guard`, `empty index`), which
re-scores the keyword branch for the survivors. My read is that this pushes in the finding's favour —
rarer terms boost the target's own chunks — so the conclusion is probably safe. But "probably safe by
my reasoning" is what the doc currently has too, and this is a case where the check was affordable:
the snapshot already held the vectors, so deleting the judge rows and rebuilding only the FTS index
would have made the approximation exact with no re-embedding.

**4. The control is no longer reproducible, despite the claim that it is.** The doc says "Query
vectors are pinned to disk alongside the DB so the control is reproducible." I went looking. There is
**no snapshot DB and no pinned vector file anywhere findable** — `~/.claude/memory-index/` holds only
the live `memory.db`, and `/tmp`, `/var/folders` and the worktree turn up nothing. The recorded
sha256 is truncated to eight hex characters, which cannot identify a file that no longer exists. So
the table's numbers rest entirely on the author's report. Keeping the harness uncommitted was the
right call (phase-guard's denial still stands) and storing the derivation rather than a path is the
right pattern — but the *evidence* went with it, and the reproducibility claim outlived the artefact.

**5. An unmarked contradiction now sits inside one 2055-line document.** At `:1824` the earlier
section states, in the present tense: *"This file is load-bearing for one of the two queries that
currently pass."* The new section states: *"Removing this file changes **no verdict** on any of the
five queries."* Both are true of their own index state, and the new section carries a back-pointer at
`:1966` — but `:1824` carries no forward-pointer, so a linear reader meets the stale claim first with
nothing marking it as superseded. Two statements about the same file, opposite conclusions, no
signpost between them.

**6. This commit enlarges the corpus it is measuring.** The preceding section explicitly warns that
recording a result grows `## Verification`, the population under suspicion. This addition (+92 lines
to the feature doc, +31 to `CODING_MEMORY.md`, both at weight 1.5) does exactly that and does not
re-note it for itself. The next R9 reading will be taken against a corpus this change grew. It is
also worth saying plainly that the feature card is now **2055 lines** — long past the point where the
one-canonical-file discipline's optional `.spec.md` split becomes the sensible move, and the doc's
own control says shrinking it is not free.

**7. The green test is not evidence about this change.** `pytest -q` reports 74 passed because
`memsearch/pyproject.toml:26` (`addopts = "-m 'not golden and not measurement'"`) deselects the
measurement suite — the instrument this entire change is about, which stands at 3 of 5 failing. I
confirmed both. Carried, not introduced, but the green bar must not be read as endorsement here.

**Self-interest disclosure.** This change concludes that judge verdicts crowd out feature docs — a
finding against my own output's cost. I scored it on the evidence. Where I could check the mechanism
independently of the experiment (equal 1.5 weight in `config.json`; 639-line verdict vs 375-line
spec), the structural crowding claim **holds on its own**, and I am recording that rather than
leaning on the leave-one-out I cannot reproduce.

## What I'd double-check before merging

1. **Print ranks 4, 6, 9 and 10.** One line of output turns a sufficiency result into a uniqueness
   one, or exposes a joint-displacement story. Highest value per unit effort of anything here.
2. **Soften the definite article in the three summary surfaces** — heading, commit subject,
   `CODING_MEMORY.md`. "Judge-verdict crowding is the driver of this flip, at this index state" costs
   six words and closes a repeat failure mode. The `CODING_MEMORY.md` sentence is the urgent one; it
   gets retrieved without its context.
3. **Either re-state or drop "reproducible."** Record where the snapshot and vectors live and the
   full sha256, or change the sentence to say the artefacts were ephemeral and the numbers are a
   reported observation. As written it promises a check nobody can now run.
4. **Add a forward-pointer at `:1824`**, the same shape as the one at `:1966`. Contradiction between
   two live sentences in one document is the failure this repo's own memory calls "delete the
   duplicate, don't sync it."
5. **Optional, if the snapshot can be recreated:** rebuild the FTS index on a judges-removed copy and
   confirm the two flips survive an exact keyword branch. Turns caveat 3 from reasoning into a
   measurement.

None of 1–5 is a merge blocker for a documentation commit with no source changes and a clean revert
point. They are the difference between a record a future planning pass can act on and one it will
have to re-litigate.

---

## Dimension table

| dimension | verdict | why |
|---|---|---|
| `intent` | **pass** | The owed control was run and recorded; the change matches its decisions summary exactly, two files, no scope beyond it. |
| `execution` | **concern** | The supplied test command passes (74/23 — I ran it) but covers none of this change. The central numbers cannot be reproduced: the pinned snapshot and query vectors are not findable, the sha is truncated to 8 chars, the harness is (correctly) uncommitted. |
| `trajectory` | **pass** | Index pinned before measuring — and it mattered, live index has since moved 8960 → 9016. No-op guard treated as non-optional. Noise measured (`ollama.py` confirmed seedless), not assumed. Two variants added because the recorded three could not have covered the 08-08T10:30 batch. 10b explicitly not retracted. This is control-before-conclusion, not luck. |
| `regression` | **concern** | No code touched, nothing adjacent to break. But the commit grows the corpus under measurement (+92 / +31 lines at `curated_doc` 1.5) without re-noting the self-perturbation for itself, and the next monitor reading is against that changed corpus. |
| `context_budget` | **concern** | Feature card now 2055 lines, `CODING_MEMORY.md` 4637. Not always-on, but both are indexed at 1.5 and the card is a top-6 occupant on 4 of 5 R9 queries — it competes with the answers the instrument is looking for. The `.spec.md` split exists and has not been taken. |
| `success_masking` | **concern** | `pyproject.toml:26` deselects the `measurement` marker, so `pytest -q` reports 74 passed while the retrieval bar sits 3-of-5 red. Verified. Carried, not introduced — but the green bar is not evidence for this change. |
| `traceability` | **concern** | Body is well-hedged and state-scoped; heading, commit subject and the `CODING_MEMORY.md` entry say "the cause" without the qualifier, and the memory entry is the surface most likely to be retrieved detached. Plus the unmarked `:1824` contradiction and the expired "reproducible" claim. |
| `intent_drift` | **pass** | +120 / −1 across two files, both squarely the owed control and its memory entry. No drive-by edits, no source changes, no dependency movement, working tree clean. |
| `checkpoint` | **pass** | Single docs-only commit on a branch cut cleanly from `origin/main` @ `64d8acb`; `git revert 52b09c3` is a complete undo. No uncommitted or foreign files in the tree. |
| `audit_trail` | **pass** | Dated, attributed, owner named (deferred planning pass, ADR 0021), open item stated explicitly rather than assumed closed, and the warning that retuning moves the failure rather than removing it is recorded alongside the finding. |

## Concerns

1. Depth-10 excerpt elides ranks 4, 6, 9, 10 — "removing judges restores the PASS" is sufficiency, not uniqueness; a joint-displacement explanation would hide in exactly the dropped rows
2. Heading, commit subject and CODING_MEMORY entry say "the cause"/"the driver" without the state and query-scope qualifiers the body carries — fourth instance of a summary outrunning its table in this section
3. CODING_MEMORY.md entry is indexed at weight 1.5 and will be retrieved standalone, detached from the hedging
4. FTS/BM25 approximation dismissed by assertion ("chunks survive in both variants") — that argues survival, not rank invariance, and RRF consumes ranks; the check was affordable on the snapshot (rebuild FTS only, no re-embedding)
5. "Query vectors are pinned to disk so the control is reproducible" is not currently true — no snapshot DB or vector file findable in ~/.claude/memory-index, /tmp, /var/folders or the worktree; sha256 truncated to 8 hex chars
6. :1824 still asserts in the present tense that this file is load-bearing for one passing query; the new section says it flips nothing — no forward-pointer marks the earlier claim as state-scoped
7. This commit enlarges the corpus under measurement (+92 doc / +31 memory lines at curated_doc 1.5); self-perturbation acknowledged for the prior entry, not for this one
8. Feature card is 2055 lines and grows every round; the optional .spec.md split has not been taken, and the doc's own control says shrinking is not free
9. pyproject.toml:26 deselects the measurement marker, so pytest -q reports 74 passed over a 3-of-5 red retrieval bar
10. Frontmatter still records branch: feature/memsearch-freshness while HEAD is docs/r9-counterfactual-control — inherited, but a restore on this branch reads a card pointing elsewhere
11. Local main is stale at 8d79094; a judge or hook defaulting to `main` rather than `origin/main` would diff 34 files instead of 2
12. 10b's index state remains unreconstructed — correctly recorded as open, but "10b was right then, judges are the cause now" is the only available reading, not a demonstrated one
13. Single leave-one-out, one index state, N=5 queries — the finding is a strong lead for the planning pass, not a settled weighting conclusion
