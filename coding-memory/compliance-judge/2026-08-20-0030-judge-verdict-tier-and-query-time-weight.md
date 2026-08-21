# Compliance judge — ADR 0030 (judge-verdict tier and query-time weight)

- **Spec:** `docs/decisions/0030-judge-verdict-tier-and-query-time-weight.md`
- **Repo/worktree:** `fix+memsearch-r9-retrieval-quality` (branch `worktree-fix+memsearch-r9-retrieval-quality`)
- **Head:** `3c27ccf56d56c615d39a61e3cc9aef01acaebe89` · **Spec blob:** `b35def039eaa9cde62cb7996ededa2f75344fbdf`

## Round 1 — 2026-08-20T17:55:31Z — **FAIL** (4 violations)

### In plain language

The decision itself is sound and unusually well-argued: it names one thing to change, says why the
cheaper alternatives were rejected, and — to its credit — refuses to redraw the R9 bar to match a
result. Four things stop it short of compliant.

The big one is a self-inflicted citation break. The ADR carries a boxed promise near the top saying
every `memsearch-freshness.md` line number "was re-derived, not copied" and is valid as of today.
It isn't. The *same commit* that added the ADR (`3c27ccf`) also inserted 11 lines into
`memsearch-freshness.md` at line 1531, which pushed every anchor below that point down by exactly
11. Six citations in the ADR now land on the wrong paragraph — `:2350-2358` (offered as the source
of the 3-of-5 sweep) points at prose *above* the sweep table, which really lives at `:2361-2369`;
`:2387-2391` (offered as the "a verdict-level summary hid a regression" warning) points at the
2866/2405/461 scope paragraph instead. The numbers were right when they were written and wrong by
the time the commit closed — the exact failure mode the box was written to prevent, one commit later.

Second, the ADR says the final weight is whatever "today's corpus supports" but never writes down
the rule for picking it. The decided rule (strict improvement, no per-target regression) exists in
the brainstorm and not in the artifact, so an implementer has no checkable acceptance criterion.

Third, two Consequences paragraphs quietly treat 1.2 as settled after the body says it isn't — and
one of them ("the perturbation is smaller") is only true if the adopted value is below 1.5, which
the same document elsewhere leaves open.

Fourth, dropping the `weight` column is a schema migration against a live, hours-to-rebuild
database, and the ADR says nothing about who runs the `ALTER TABLE ... DROP COLUMN`, what an old
database looks like to new code, or what `--reclassify` does when a walk hits an unreadable file or
an unknown source type.

### What checked out

Verified clean, so a later round need not re-do it: `index.py:169`, `index.py:46-58`, `db.py:75`,
`db.py:134`, `search.py:80`, `search.py:24`, `0020:105-110`,
`test_measurement_queries.py:16-20`, `test_measurement_queries.py:120-123`,
`memsearch-freshness.md:327-343` and `:1731-1757` (both above the shift point). SQLite **3.53.3**
confirmed in-environment (`uv run python -c "import sqlite3; print(sqlite3.sqlite_version)"`), so
`DROP COLUMN` really is available. The **163 / 22 = 185** judge-file count reproduced exactly.
The 2866 / 2405 / 461 figures are correctly flagged as quoted rather than re-measured.

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `core-conduct/verification-before-write-down` | `rules/core-conduct.md` | Verification precedes both the claim and the write-down | "On the line numbers below" note; Context; body citations | The boxed claim that every `memsearch-freshness.md` citation was re-derived and is current is false at HEAD — commit `3c27ccf` inserted 11 lines at `:1531` of that file in the same commit, so `:2339-2412`, `:2350-2358`, `:2382-2385`, `:2387-2391`, `:2393-2395`, `:2400-2407` and `:2409-2412` all land 11 lines above their referents. |
| `writing-specs/acceptance-criteria` | `skills/writing-specs/SKILL.md` | Requirements, not one-liners; state what correct looks like | "The tier is keyed on the judge directories"; "The measurement instrument reads a moving target" | "adopts whatever today's corpus supports" is not checkable, and the decided acceptance rule — strict improvement in R9 pass count with no per-target regression — is never stated, so an implementer cannot tell which sweep row to adopt or when to stop. |
| `writing-specs/unambiguous-requirements` | `skills/writing-specs/SKILL.md` | No requirement readable two ways | "Consequences" — "This tunes a proxy…" and "This branch's own verdicts land in the new tier" | The body states the number is explicitly *not* decided, yet these paragraphs assert "1.2 is fitted to this document class" and "those files become `judge_doc` at 1.2", the latter's conclusion holding only for adopted values below 1.5 — a bound the ceiling paragraph leaves open. |
| `core-conduct/explicit-error-handling` | `rules/core-conduct.md` | Handle errors explicitly at every boundary; validate input at system boundaries | "Weight was a stored copy of a config value"; "The reclassify pass is driven from source" | Only the config-load missing-key path is specified: the `ALTER TABLE ... DROP COLUMN` migration of an existing `memory.db` has no stated trigger, ordering, or old-database/new-code behaviour, and `--reclassify` has no stated behaviour for an unreadable file, a vanished source, an unknown source type, or a failed write mid-walk. |

### Notes (non-blocking)

- Judged as an ADR against the repo's `docs/decisions/` house form (following `0020`), not against
  `docs/superpowers/specs/` or a Gherkin layout — the missing scenario blocks are not cited.
- The 163 / 22 counts were reproduced against `~/.claude/coding-memory/`; this worktree carries its
  own `coding-memory/observability-judge` and `.../compliance-judge` copies, so the ADR would read
  more precisely if it named which checkout it counted.
- The remedy-section citation style would survive future edits better as quoted section headings
  with no line numbers at all — the ADR already tells the reader to prefer the headings.

### Waivers

None. No violation ids were waived for this round.

---

## Round 2 — 2026-08-20T18:07:50Z — **PASS**

- **Spec:** `docs/decisions/0030-judge-verdict-tier-and-query-time-weight.md`
- **Repo / branch:** `fix+memsearch-r9-retrieval-quality` (worktree) / `worktree-fix+memsearch-r9-retrieval-quality`
- **HEAD:** `052dd5da2b0bd94fcb271d232a8e659786f7f220` · **spec blob:** `57c261e752642931eefab7e4f5b343784571c8c3`
- **Confidence:** high

### In plain language

All four things flagged last round are genuinely fixed, and the revision did not smuggle in a new
unchecked claim. The line-number citations into the 2,423-line feature file are gone entirely —
replaced by quoted phrases that I found verbatim in that document, so a reader can still locate every
one of them with a search. The "what number do we ship" hole is closed by a rule that can actually
fail: sweep six weights, measure the 1.5 baseline in the same run, and only adopt a row that beats it
on pass count *and* loses no target's hits *and* loses no target's top hit — otherwise ship 1.5 and
change nothing. I looked for a loophole in that rule and did not find one: every term is measurable,
the tie-break is deterministic, and the "adopt nothing" branch is written as a legitimate outcome
rather than an excuse to relax the test. The migration and the reclassify pass now say what they do
when things go wrong, including the uncomfortable part — that dropping the column is one-way and the
only way back is a multi-hour rebuild.

I re-ran every citation rather than trusting the summary. The nine code references all land on the
right lines; the SQLite claim is true of the environment that actually runs this code (the project
virtualenv reports 3.53.3, and `DROP COLUMN` has existed since 3.35, which the ADR names correctly);
`0020:105-110` really does say both things attributed to it; and the "163 and 22 files, 185 together"
count reproduces exactly against the tree as it stood at the commit — the observability verdict that
would have made it 164 was written 27 seconds *after* the commit. Nothing left to block on.

### Round-1 violations — status

| id | status | evidence |
|---|---|---|
| `core-conduct/verification-before-write-down` | **fixed** | `grep -n "memsearch-freshness.md:"` on the ADR returns nothing; all eight replacement phrase-quotes located in the target file (`:2350`, `:1742`, `:2407`, `:2398`, `:2404`, `:2411`, `:2289`, `:2389`). Boxed note's "2400+ lines" checks out at 2,423. |
| `writing-specs/acceptance-criteria` | **fixed** | "The adoption rule, stated so it can fail" — six-row sweep, in-run baseline at 1.5, three-clause eligibility, deterministic tie-break, explicit no-adopt branch. |
| `writing-specs/unambiguous-requirements` | **fixed** | Consequences now read "whatever value the sweep adopts"; the perturbation paragraph names its range and states the 1.5-or-above case explicitly. |
| `core-conduct/explicit-error-handling` | **fixed** | Migration: trigger on the DB-open path (`db.connect` → `_init_schema`, `db.py:48/55`), `PRAGMA table_info` idempotence, one-way with named rollback cost, fail-closed `ALTER TABLE`. Reclassify: four named failure modes with exit-code behaviour. |

### Violations

None.

### Verification log (round 2)

- `index.py:169` (`float(cfg.weights[st])`), `index.py:217-219` (record-and-continue `except`),
  `index.py:46-58` (`ARCHIVE_FILENAME` / `_doc_source_type`), `db.py:75` (`weight REAL NOT NULL`),
  `db.py:134` (INSERT column list), `search.py:24` (`_CHUNK_COLS` ends in `"weight"`),
  `search.py:80` (`base_score * r.pop("weight")`), `0020:105-110` (no prune path outside
  `replace_source`; `index --full` is a multi-hour rebuild), `test_measurement_queries.py:120-123`
  (`max(CFG.weights.values())`) — all nine land on their referents.
- `test_measurement_queries.py:16-20` — the withdrawn `>=0.30` floor is explained there, but the
  quoted sentence finishes on line 21; the range is one line short of its own quote.
- SQLite: `memsearch/.venv/bin/python` reports `3.53.3`; system `python3` reports `3.51.0`. The ADR's
  "project environment" reading is the correct one, and the stated 3.35 threshold for `DROP COLUMN`
  is right. No index or trigger references `weight`, so the drop has nothing blocking it.
- Judge-directory counts at `052dd5d`: 163 tracked observability files, 21 tracked compliance files
  plus the round-1 verdict written at 13:58:19 (commit at 14:07:19) = 22. 185 total, exactly as
  written. The observability verdict (14:07:46) post-dates the commit and correctly does not count.
- `config.json` weights: `curated_doc` 1.5 — the ADR's baseline premise holds.
- `search(cfg: Config, ...)` already takes config, so query-time weight resolution needs no signature
  change; the ADR's design is implementable as written.

### Notes (non-blocking)

- **Latent boundary the config check does not cover.** The ADR says config-load validation stops a
  missing weight "surfacing as a `KeyError` mid-query". That covers config-known types, not a stored
  row carrying a `source_type` that config no longer names — and the ADR's own citation of
  `0020:105-110` establishes that orphan rows outlive their sources. Today's index is clean (only
  `curated_doc`, `repo_doc`, `transcript_digest`, `archive_doc`, all configured), so this is latent,
  not present-day. Worth one sentence at implementation time.
- Round 1's note stands: the ADR still does not name *which* checkout it counted 163/22 in. Both
  `~/.claude/coding-memory/` and this worktree reproduce it, so nothing is wrong — only underspecified.
- The `Chunk` dataclass field (`db.py:33`) and the `weight` parameters in `chunk.py:110/128` are
  covered only by the general "the write path stops emitting it"; naming them would remove a small
  guess.
- Still judged as an ADR against the repo's `docs/decisions/` house form, as in round 1 — not against
  `docs/superpowers/specs/` or a Gherkin layout. Missing scenario blocks are not cited.
- The sweep deliberately never tests above 1.5, so the rule can only adopt at-or-below baseline. That
  is consistent with the score-ceiling consequence and is stated, not hidden.

### Waivers

None. No violation ids were waived for this round.

---

## Round 3 — 2026-08-20T18:14:07Z — **FAIL** (1 violation)

- **Spec:** `docs/decisions/0030-judge-verdict-tier-and-query-time-weight.md`
- **Repo / branch:** `fix+memsearch-r9-retrieval-quality` (worktree) / `worktree-fix+memsearch-r9-retrieval-quality`
- **HEAD:** `8c136121dfb8989617a53e3b94f477f298e2b82f` · **spec blob:** `708d84376b74d3ed6a2a4d97077210d8e86fa73c`
- **Confidence:** high

### In plain language

Three of the four edits are good and I could not break them. The migration change is the strongest
one: making only `index` migrate, failing a `query` closed with a named fix, versioning with
`PRAGMA user_version` instead of sniffing for a column, and taking a pre-drop copy of the database
are all correct, and the copy really is cheap — `memory.db` is 75 MB, so restoring it is seconds
against the multi-hour rebuild the old text named. The reclassify denominator and the
self-re-check are genuine falsifiability improvements. The sweep's new "prove the index did not
move" clause is right, and its premise checks out: `local.memsearch-index.plist` is installed, so
the corpus really can shift under a running sweep. The adoption rule is untouched by this edit and
still fails the way it did at round 2.

The one thing that has to go back is the paragraph that replaced the bad count. The *number* is
fine — 162 and 23 reproduces exactly against the primary checkout. What is wrong is the story told
about why the number moved, and this is the third time in this repo that a correct measurement has
been shipped attached to an invented explanation. The ADR says the jump from 21 to 23 compliance
files is "this decision's own compliance verdicts landing in the directory being counted." It is
not. This decision's compliance verdict is the file you are reading, and it lives in the worktree,
not in `~/.claude/coding-memory/`. The two files that actually arrived in the primary directory are
`2026-08-20-06-deck-import-export.md` (18:11:59Z) and `2026-08-20-07-badging.md` (18:12:42Z) —
two entirely unrelated features being judged in parallel. The ADR attributes to itself a movement
caused by somebody else's work, which is exactly the "absence from the frame is not absence of
effect" error this repo has already recorded twice.

Two smaller defects sit in the same three sentences. The timestamp `14:10Z` is local Eastern time
wearing a `Z`: the two files that make the count 23 were written at 18:11Z and 18:12Z, so at true
14:10Z the directories held 162 and 21, not 162 and 23. And the post-mortem on the old figure —
"163 and 22 … included `verdicts.jsonl`, which is not walked" — only explains the 22. The 163 was
never a `verdicts.jsonl` artifact: this worktree genuinely holds 163 observability `*.md` files and
the primary holds 162, and the extra one is this branch's own observability verdict. The difference
is *which checkout was counted*, not which files were globbed. So the sentence that exists to leave
the old error visible states the wrong cause for half of it.

That matters more than usual because of the framing around it. "Left visible rather than quietly
corrected" is the right instinct, but it only pays off if the visible version is right. As written,
a reader who trusts the paragraph learns two false facts (this branch grew its own count; the old
error was a glob bug) from a passage whose stated purpose is honesty about counting.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `core-conduct/verification-before-write-down` | `rules/core-conduct.md` | Session Defaults — never record a claim in a durable artifact until it has been run and the output re-read; an explicit gap is cheap, a false certainty is not | "The tier is keyed on the judge directories…" → **"The size of the affected population is a derivation, not a constant."** (ADR lines 135–143) | The paragraph's three causal claims are unverified and two are demonstrably false — the 21→23 movement is two unrelated features' verdicts, not this decision's; the `14:10Z` label is local EDT, at which true UTC instant the count was 162 and 21; and the "163" in the retracted figure came from counting the worktree, not from including `verdicts.jsonl`. |

*Reused from round 1 per the persistence-detection rule: same rule, reintroduced by this edit in new
territory. It was confirmed fixed at round 2 in its original territory (the line-citation block),
which remains fixed.*

### Verification log (round 3)

- `index.py:65` — `sorted(entry.rglob("*.md"))` inside `_iter_docs`'s `curated_docs` loop. The
  citation and the "only `*.md` counts" claim are both exact.
- Counts, all taken at 18:14Z: primary `~/.claude/coding-memory/` = **162** observability `.md`,
  **23** compliance `.md` (matches the ADR). Worktree = **163** and **21**.
- Set diff, worktree vs primary: worktree's extra observability file is
  `2026-08-20-worktree-fix+memsearch-r9-retrieval-quality.md` (this branch's own verdict); worktree's
  extra compliance file is `2026-08-20-0030-…md` (this decision's verdict). Primary's extra
  compliance files are `2026-08-17-assistant-jwt-forwarding-design.md`,
  `2026-08-20-06-deck-import-export.md`, `2026-08-20-07-badging.md`. The two 2026-08-20 ones carry
  mtimes 18:11:59Z and 18:12:42Z — they are the entire 21→23 delta, and neither is this decision's.
- Clock: `date -u` = 18:14:07Z, `date` = 14:14 EDT. UTC−4. `14:10Z` therefore predates both new files.
- `launchd`: `~/Library/LaunchAgents/local.memsearch-index.plist` exists and invokes
  `memsearch/bin/memsearch` — "this feature installed that scheduler" holds, so the sweep's
  index-state guard has a real threat behind it.
- `PRAGMA user_version`: currently **unused** anywhere in `memsearch/` — correctly read as proposed
  design, not an assertion about today's code.
- `db.connect` → `_init_schema` (`db.py:47-55`) — confirms the read path *already* opens a write
  transaction (`CREATE TABLE IF NOT EXISTS`), which does not falsify the ADR's argument about not
  adding a *migration* there, but see notes.
- Rollback feasibility: `~/.claude/memory-index/memory.db` is **75 MB** — a `cp` is seconds, as claimed.
- `ALTER TABLE … DROP COLUMN` / SQLite 3.53.3 in `memsearch/.venv`, threshold 3.35: re-confirmed
  from round 2, unchanged by this edit.
- Adoption rule: byte-identical across `052dd5d..8c13612` — round 2's falsifiability finding stands.

### Notes (non-blocking)

- The fix is small: state the derivation and the number, timestamp it in real UTC, and either drop
  the causal sentence entirely or say "two unrelated features' verdicts arrived mid-judgement" —
  which makes the *live and rising* point better than the false version did, because it shows the
  count moving for reasons this branch does not control.
- `db.connect` already runs `CREATE TABLE IF NOT EXISTS` on every open, so "would make a plain read a
  schema writer" is, strictly, already true today. The ADR's conclusion is still right (a no-op DDL
  is not a multi-hour backfill), but one clause acknowledging the existing behaviour would stop a
  reader finding the contradiction themselves.
- Pre-drop copy: `memory.db-wal` / `-shm` are not named. A `cp` of the main file alone after an
  unclean shutdown is not a complete snapshot; one sentence at implementation time closes it.
- Round 2's latent-boundary note (a stored `source_type` config no longer names) is untouched by this
  edit and still worth a sentence.
- Still judged as an ADR against the repo's `docs/decisions/` house form — not against
  `docs/superpowers/specs/` or a Gherkin layout. Missing scenario blocks are not cited.

### Waivers

None. No violation ids were waived for this round.

---

## Round 4 — 2026-08-20T18:44:33Z — **PASS**

- **Spec:** `docs/decisions/0030-judge-verdict-tier-and-query-time-weight.md`
- **Spec blob:** `9b161f7311d2630965d39e683c5a771721f990bf` (file at commit `06a9b8c`)
- **HEAD:** `f9217e13f46217ec5a6231d19e4c79695c6ae84b` on `worktree-fix+memsearch-r9-retrieval-quality`
- **Waived:** none

### In plain language

The one violation carried out of round 3 is closed. Round 3 said the ADR measured a number
correctly and then made up the story of why the number had moved. That story is now measured, and
I re-measured every piece of it myself rather than taking the ADR's word: the counts, the two files
that caused the movement, where this branch's own verdicts actually land, and the all-entries-vs-
markdown split that produced the retracted "163". All four hold. I also re-checked every quotation
the ADR takes from other documents and every `file:line` citation it makes into code — twenty-odd
of them — and found no fabrication. The document is verbose about its own drafting history, and one
paragraph of it argues with a previous judge rather than informing an implementer; that is worth
trimming, but it is a style note, not a rule breach.

**I also withdraw round 3's third sub-claim.** I re-ran the check and the ADR's rejection of it is
correct — see below.

### Verification performed this round

| Claim in the ADR | Command | Result |
|---|---|---|
| `162` and `23` md files, primary checkout | `ls ~/.claude/coding-memory/{observability,compliance}-judge/*.md \| wc -l` | 162, 23 ✅ |
| `all=163` / `md=162` in the primary observability dir | `ls` vs `ls *.md` | 163 vs 162; the extra entry is `verdicts.jsonl` ✅ |
| the compliance delta's two new files are `…-06-deck-import-export.md` and `…-07-badging.md` | `ls -t ~/.claude/coding-memory/compliance-judge/` | both present, both unrelated features ✅ |
| this branch's verdicts land in the worktree, not the primary checkout | listed both stores | `2026-08-20-0030-…md` exists only in the worktree ✅ |
| the retracted `163` was **not** a worktree count | see "round-3 sub-claim 3" below | ADR is right, my predecessor was wrong ✅ |
| "the project environment runs SQLite **3.53.3**" | `memsearch/.venv/bin/python -c 'import sqlite3;print(sqlite3.sqlite_version)'` | `3.53.3` ✅ (system `sqlite3` is 3.51.0 — the ADR's scoping to *the project environment* is precisely right, and both are ≥3.35) |
| `index.py:65` walks `*.md` | `sed -n 65p` | `sorted(entry.rglob("*.md"))` ✅ |
| `index.py:169`, `index.py:217-219` | `sed` | weight read from config at index time; one-bad-source-continues `except` ✅ |
| `db.py:75`, `db.py:134` | `sed` | `weight REAL NOT NULL` in DDL; `weight` in the INSERT column list ✅ |
| `search.py:24`, `search.py:80` | `sed` | `"weight"` in `_CHUNK_COLS`; `base_score * r.pop("weight")` ✅ |
| `test_measurement_queries.py:120-123` | `sed` | `score_ceiling()` … `max(CFG.weights.values())` ✅ |
| `0020:105-110` | `sed` | the `replace_source`-only prune text ✅ |
| ADR 0020 quote "distinct key so R9 can tune it alone" | normalized substring search | present in 0020 ✅ |
| 6 quotations attributed to `memsearch-freshness.md` | normalized substring search | all present (`:173`, `:1229`, `:2289`, `:2404`, `:2411`, `"anything regress?"`) ✅ |
| `2866` / `2405` / `461`, `639` / `375`, the 1.2 → 3-of-5 sweep row | `grep` in the feature file | all present at `:2388-2389`, `:2283-2284`, `:2366`, `:2369` — and the ADR explicitly labels them quoted-not-remeasured ✅ |

### Round-3 sub-claim 3 — I withdraw it

Round 3 proposed the retracted "163" came from counting the worktree. The ADR rejects that with
evidence. **The rejection is correct and I confirm it:**

```
ls ~/.claude/coding-memory/observability-judge/     | wc -l  → 163   (all entries)
ls ~/.claude/coding-memory/observability-judge/*.md | wc -l  → 162   (markdown only)
ls <worktree>/coding-memory/observability-judge/*.md | wc -l → 163   (markdown only)
```

The primary checkout's `all=163 / md=162` reproduces the retracted pair exactly, including the
companion `22` (compliance `all` when `md` was 21). The worktree's 163 is a numerical coincidence,
as the ADR states. No violation on this point.

### Round-2 regression check — clean

- **Adoption rule still falsifiable** (§"The adoption rule, stated so it can fail", lines 97–126):
  baseline row, strict-greater pass count, per-target no-loss and top-hit-retention clauses, an
  explicit adopt-nothing branch, and the chunk-count/mtime invalidation guard. Intact.
- **No line-number citations into `memsearch-freshness.md`:** `grep` for `freshness.md:[0-9]` returns
  nothing; every reference is by section heading. Intact.
- **Migration and reclassify error handling:** fail-closed unmigrated `query`, `user_version`
  gating, pre-drop file copy, abort-on-`ALTER`-failure; single-transaction reclassify, unreadable
  source recorded + non-zero exit, vanished source left untouched, unconfigured weight aborts before
  any write. Intact.

### Violations

_None._

### Waiver record

No violations were waived at any round of this spec. Round 3's single violation was closed by
revision `06a9b8c`, not by waiver.

### Notes (non-blocking — not rule violations, do not gate)

1. **The judge-rebuttal parenthetical (lines 152–155) is the one passage I would cut.** It records a
   correction a reviewer proposed and why it was not adopted. Recording *rejected* alternatives is
   normal and good in an ADR — the mindmap does it four times — but this one rejects a *review
   comment about the document's own arithmetic*, not a design option. Its useful content (the count
   was taken against `~/.claude`) is already stated one sentence earlier at line 138. An implementer
   gains nothing; the next reviewer would. Consider moving it to this verdict file, where it now is.
2. **The retraction apparatus is at the edge of its budget, not over it.** Roughly 30 of 315 lines
   (~10%) narrate the ADR's own drafting errors: the line-number blockquote (18–26), "corrected three
   times" (128), the two count retractions (140–158), the rollback-draft note (209–211). Each of the
   others is anchored to a lesson an implementer needs (don't cite line numbers into a live file;
   don't pin a count; don't offer the expensive rollback as the only one), so they earn their space.
   The pattern has **not** become cover — but it is one more addition away from it, and
   `writing-specs` is explicit that padding degrades reasoning quality independent of context size.
   If a round 5 ever happens, the right move is to trim, not to add another note.
3. **"Do not pin this number" then pinning it** (lines 135–158) is deliberate and self-labelled, and
   the derivation command is given alongside, so a reader can always re-derive. I re-derived it and
   it is currently correct. Acceptable as written; the numbers will rot, as the ADR says.
4. **`test_measurement_queries.py:16-20` is off by one at the tail.** The quoted sentence ends
   "…that ever grades it" on line 21. Cosmetic.
5. **`"what the planning pass inherits"`** (line 283) elides `(ADR 0021)` from the source phrase at
   `memsearch-freshness.md:2404` without an ellipsis. It reads as a paragraph label rather than a
   verbatim quote, so this is cosmetic too.
6. **Artifact class.** This is an ADR under `docs/decisions/`, not a spec under
   `docs/superpowers/specs/`, and it carries no Gherkin. As at rounds 2 and 3, I do not cite the
   canonical-path or BDD rules: the decision-record genre is the correct home for this content, the
   Gherkin-bearing artifact is `docs/features/memsearch-freshness.md`, and the adoption rule supplies
   the falsifiable acceptance criteria those rules exist to guarantee.
7. **`writing-secure-code` was read**, because the design touches a database. Nothing in it applies:
   memsearch is a local single-user SQLite store with no external input, no auth surface, and no
   user-constructed SQL (`db.py:132-136` uses `?` placeholders). The ADR contains no secrets, and its
   only paths are tilde-relative (`~/.claude`), not absolute.

## Round 5 — 2026-08-20T19:29:03Z — PASS

**Spec:** `docs/decisions/0030-judge-verdict-tier-and-query-time-weight.md`
**Blob:** `2eae08813c76423edf99450302bafdd1b6d74e99` (working tree, one uncommitted edit on `f9217e13f46217ec5a6231d19e4c79695c6ae84b`)
**Branch:** `worktree-fix+memsearch-r9-retrieval-quality`
**Waived:** none

### In plain language

Nothing is wrong with this document. The only change since round 4 was deleting four lines — a
parenthetical in which the ADR argued back at an earlier judge about where a retracted count came
from. That argument belonged in the verdict file, not in the decision record, and removing it did not
break the sentence around it: the surviving bullet ("an earlier draft wrote 163 and 22 — both were
counts of *all* directory entries, including `verdicts.jsonl`, which `_iter_docs` does not walk")
still explains the retracted number completely on its own, without needing the rebuttal. Nothing else
in the file referred to the deleted text, so there is no dangling pointer. Everything the round-4 pass
rested on was re-derived against the current bytes rather than copied forward, and it all still holds.

### Violations

None.

| id | rule | where | why |
|----|------|-------|-----|
| — | — | — | — |

### Checks performed this round

- **Deletion is exactly what was described.** `git diff` on the spec shows a single hunk: four lines
  removed at the second bullet of the count paragraph, nothing else added or moved.
- **The surviving bullet stands alone.** Read fresh, the whole "size of the affected population"
  passage is complete: the derivation (`ls .../*.md | wc -l`, `*.md` only because that is what
  `_iter_docs` walks), the measured 162/23 against the primary checkout at a UTC stamp, the two
  documented movements with their causes, and the "do not pin this number" close. No sentence depends
  on the removed parenthetical.
- **No orphaned references.** `grep` for `163` / `coincidence` / `worktree` returns only the surviving
  bullet and the independent line-145 worktree sentence.
- **Line-number drift re-derived, not reused.** File is now 312 lines (was 316). All citations
  re-opened at the current bytes: `index.py:65` (`rglob("*.md")`), `index.py:169`
  (`cfg.weights[st]`), `index.py:217-219` (the record-and-continue error contract), `db.py:75` and
  `db.py:134` (the `weight` column, write path), `search.py:24` (`_CHUNK_COLS` includes `"weight"`),
  `search.py:80` (`base_score * r.pop("weight")`), `test_measurement_queries.py:120-123`
  (`score_ceiling()` over `max(CFG.weights.values())`). All land on their referents.
- **Population counts re-measured now:** `~/.claude/coding-memory/observability-judge/*.md` = 162,
  `compliance-judge/*.md` = 23 — matching the ADR's recorded figures, which it correctly frames as a
  derivation rather than a constant.
- **No line citations into the live `memsearch-freshness.md`** — grep for `memsearch-freshness…:N`
  is clean; the section-heading discipline the ADR sets for itself is still kept.
- **Adoption rule still falsifiable:** six-row sweep 1.0–1.5, baseline at 1.5 measured in the same
  run, three-clause eligibility (strictly greater pass count AND no per-target hit loss AND no
  top-hit loss), deterministic tie resolution, explicit adopt-nothing branch named a legitimate
  outcome, plus the same-index-state proof (chunk count + db mtime before and after, discard if moved).
- **Error handling intact at every boundary the design introduces:** migration fail-closed on
  `ALTER TABLE` failure with `user_version` unchanged and the pre-drop copy reported; `query` against
  an unmigrated database fails closed rather than falling back to stored weights; config load
  validates every source type has a weight; reclassify is one transaction, continues past unreadable
  sources but exits non-zero, leaves vanished-source rows untouched, and aborts on an unweighted type.

### Answer to the round-4 note #2 question (is the retraction apparatus now balanced?)

Yes — the balance is right, and nothing more should go. The count passage now costs 21 lines to carry
three things that each earn their place: the derivation (so the number can be re-taken instead of
trusted), one worked example of the population moving for reasons this branch does not control (which
is the live-corpus argument the whole ADR rests on), and two one-line retraction records. The
mis-attribution warning at lines 147–150 is the only remaining piece a trimmer might target, and it
should stay: it names a failure mode — measuring a number and inventing its explanation — that this
repo has hit repeatedly, and it is three lines. Removing more would start deleting the evidence
rather than the commentary.

### Notes (non-blocking)

1. `test_measurement_queries.py:16-20` is still one line short of its own quote — the sentence
   finishes on line 21. Cosmetic, carried from round 2; not a rule violation.
2. Judged as an ADR against this repo's `docs/decisions/` house form, not against
   `docs/superpowers/specs/` or a Gherkin layout. The `writing-specs` canonical-path and
   scenario-block rules are not cited, consistent with rounds 1–4.
3. The pre-drop rollback copy still names only `memory.db`, not `memory.db-wal` / `-shm`. Carried
   from round 3 as a note; the migration runs from `index`, which owns the connection, so it does not
   rise to a stated-error-handling gap.
