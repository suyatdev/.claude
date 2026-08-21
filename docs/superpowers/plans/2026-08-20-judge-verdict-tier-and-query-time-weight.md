# Judge Verdict Tier and Query-Time Weight — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give judge verdicts their own `judge_doc` weight tier, move weight resolution from index
time to query time so a config edit can move a ranking, and run ADR 0030's adoption rule to pick (or
decline to pick) the tier's number.

**Architecture:** Four separable code changes plus one measurement. (1) `_doc_source_type` gains a
parent-directory rule beside the existing filename carve-out, and config load refuses a weights map
that does not cover every known source type. (2) `search.py` stops reading the stored `weight` column
and resolves `cfg.weights[source_type]` after fusion instead. (3) The now-derived column is dropped
under a `PRAGMA user_version` migration that runs only from `index`, takes a file copy first, and
fails closed. (4) `index --reclassify` re-types stored rows by walking the real source enumeration,
in one transaction, and proves convergence with a second pass. Then the weight sweep runs R9's five
queries at each candidate weight against one proved-static index state and applies the ADR's
three-clause eligibility rule.

**Tech Stack:** Python 3.12.13 (`.python-version` pins `3.12`), pytest 8.3.4, sqlite-vec 0.1.9,
SQLite 3.53.3 (verified: `.venv/bin/python -c "import sqlite3;print(sqlite3.sqlite_version)"`),
`uv` for environment resolution. No new dependencies — the whole change is stdlib plus what is
already pinned in `memsearch/pyproject.toml`.

**Spec:** `docs/decisions/0030-judge-verdict-tier-and-query-time-weight.md` (status: accepted).
Read it in full before Task 1. Where this plan and the ADR disagree, the ADR wins and the plan is
the bug.

---

## Verified baseline

Everything below was run in this worktree at HEAD `1a35a98`, from
`<worktree>/memsearch`, before any task was written.

| Fact | Command | Result |
|---|---|---|
| Test command | `cd memsearch && uv run pytest -q` | `74 passed, 23 deselected in 0.55s` |
| Single test | `cd memsearch && uv run pytest tests/test_config.py::test_loads_real_config -v` | the invocation form every step below uses |
| Deselection | `pyproject.toml` `addopts = "-m 'not golden and not measurement'"` | the 23 deselected are the `golden` + `measurement` suites; both need a built index |
| SQLite | `.venv/bin/python -c "import sqlite3;print(sqlite3.sqlite_version)"` | `3.53.3` — above the 3.35 floor `ALTER TABLE … DROP COLUMN` needs |
| Live index | `ls -la ~/.claude/memory-index/` | `memory.db`, 78,282,752 bytes, mtime 2026-08-20 10:04 |

**The baseline is green. Any task that ends with fewer than 74 passing unit tests, or with a
failure, is not done.**

Two environment facts that will bite an executor who does not know them:

- `memsearch/bin/memsearch` execs `uv run --project "$HOME/.claude/memsearch"` — the **primary
  checkout**, not this worktree. Never use `bin/memsearch` to exercise this branch's code. Use
  `cd <worktree>/memsearch && uv run --project . memsearch …`.
- `memsearch/config.json` points `db_path` at `~/.claude/memory-index/memory.db` — the **live**
  index, shared with the scheduled `launchd` indexer. Every unit test overrides `db_path` into
  `tmp_path` (see `tests/test_config.py:11-16` `write_cfg`, `tests/test_search.py:10-15`
  `make_cfg`). Task 5 is the only task that touches the live database, and it takes a backup first.

## Global Constraints

- Python `>=3.12`; pytest pinned at `8.3.4`; sqlite-vec pinned at `0.1.9`; hatchling `1.27.0`.
  **Do not add, remove, or upgrade a dependency.** The whole change is stdlib.
- `JUDGE_DIRS` is exactly `{"observability-judge", "compliance-judge"}` — not `coding-memory/`, not
  a configurable pattern list. ADR 0030 rejects both alternatives by name.
- `_iter_docs` walks `*.md` only (`memsearch/memsearch/index.py:65,70`). Any count derived for this
  change counts `*.md`, never all directory entries — `verdicts.jsonl` is not walked.
- The weight sweep runs `1.0`–`1.5` inclusive, in steps of `0.1`, baseline (`1.5`) first.
- `config.json` seeds `judge_doc` at `1.2`. That is a starting point, not the decision; Task 5's
  measurement selects the shipped value, and **"no row was eligible, ship 1.5" is a valid result.**
- The migration runs from `index` only. `query` never writes schema.
- No new markdown document may be created for this work beyond this plan. Results are recorded in
  `docs/features/memsearch-freshness.md` (which already owns R9's results) — one canonical file.
- Never edit a test and the implementation it grades in the same step. Task 3 contains one
  *mechanical* test adaptation (a constructor loses a field) that is called out explicitly and is
  its own step.

## Known gaps carried in from ADR 0030's judge rounds

**Gap 1 — a stored `source_type` that config no longer names.** ADR 0030's config-load validation
covers *config-known* types: it asserts every name in the source-type vocabulary has a weight. It
does not cover the reverse — a row already in the index whose `source_type` is absent from
`weights`. Latent today (the index holds only the four configured types), but two paths meet it and
both must handle it. **This plan puts it in two places:** the query path fails closed with a named
error (Task 2, Step 1) rather than defaulting to a silent weight, and the reclassify pass aborts
before any write on a computed type with no configured weight (Task 4, per the ADR). It is
deliberately not "solved" by a default multiplier — a silent default is this feature's original
failure mode (a stale value reporting success) one field over.

**Gap 2 — the population figures were counted against the primary checkout.** The ADR's 162
observability / 23 compliance `.md` files, and its 2866 / 2405 / 461 chunk counts, were measured
against `~/.claude`, not this worktree, and the ADR says explicitly that the implementation
re-derives them rather than trusting them. **Task 5, Steps 1–2 are that re-derivation**, with the
commands and the as-of stamp.

## File Structure

| File | Change | Responsibility after the change |
|---|---|---|
| `memsearch/memsearch/config.py` | modify (`:24-36`, `:50-72`) | owns the source-type vocabulary (`SOURCE_TYPES`) and refuses a weights map that does not cover it |
| `memsearch/memsearch/index.py` | modify (`:46-58`, `:164-171`, `:193-200`, `run_index` head) | classification (`_doc_source_type`) and enumeration (`_iter_docs`) only; no longer looks weights up |
| `memsearch/memsearch/db.py` | modify (`:15-16`, `:21-33`, `:59-89`, `:109-145`) | schema, `PRAGMA user_version`, the migration, the backup copy. `Chunk` no longer carries `weight` |
| `memsearch/memsearch/chunk.py` | modify (`:109-125`, `:127-154`) | chunkers stop taking a `weight` parameter |
| `memsearch/memsearch/search.py` | modify (`:22-24`, `:32-40`, `:66-82`) | resolves weight from config at query time; refuses an unmigrated database |
| `memsearch/memsearch/reclassify.py` | **create** | `run_reclassify` — source-driven re-typing, one transaction, self-verifying |
| `memsearch/memsearch/cli.py` | modify (`:29-33`, `:59-66`, `:67-75`) | `index --reclassify` wiring and its report |
| `memsearch/config.json` | modify | `weights` gains `judge_doc` |
| `memsearch/README.md` | modify (Invariants) | records the new tier beside the `archive_doc` line |
| `memsearch/tests/test_index.py` | modify | classification tests |
| `memsearch/tests/test_config.py` | modify | weights-coverage tests |
| `memsearch/tests/test_search.py` | modify | query-time weight tests |
| `memsearch/tests/test_migrate.py` | **create** | version, drop, backup, idempotence, fail-closed |
| `memsearch/tests/test_reclassify.py` | **create** | transitions, denominator, transaction, skips, vanished sources |
| `memsearch/tests/conftest.py` | modify (`:13-28`) | `make_chunk` loses its `weight` kwarg |
| `memsearch/tests/sweep_judge_weight.py` | **create** | the sweep, as a script — deliberately not named `test_*` so pytest never collects it |
| `docs/features/memsearch-freshness.md` | modify (R9 results) | records the sweep table and the adopted value |

`reclassify.py` is a new module rather than more of `index.py` because `index.py` is already 219
lines and the pass shares nothing with the indexing pipeline but `_iter_docs`.

---

### Task 1: The `judge_doc` source type

Classify judge verdicts into their own tier, seed its weight, and make a weights map that does not
cover the vocabulary a load-time error instead of a mid-query `KeyError`.

**Files:**
- Modify: `memsearch/memsearch/index.py:46-58` (`ARCHIVE_FILENAME`, `_doc_source_type`)
- Modify: `memsearch/memsearch/config.py:50-72` (`load_config`), plus a new `SOURCE_TYPES`
- Modify: `memsearch/memsearch/db.py:15-16` (`SOURCE_TYPES` moves to `config.py`, re-exported)
- Modify: `memsearch/config.json` (`weights`)
- Modify: `memsearch/README.md` (Invariants section)
- Test: `memsearch/tests/test_index.py`, `memsearch/tests/test_config.py`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `memsearch.index.JUDGE_DIRS: frozenset[str]` — `{"observability-judge", "compliance-judge"}`
  - `memsearch.index._doc_source_type(path: Path, default: str) -> str` — unchanged signature
  - `memsearch.config.SOURCE_TYPES: tuple[str, ...]` — includes `"judge_doc"`; re-exported as
    `memsearch.db.SOURCE_TYPES` so existing importers keep working
  - `memsearch.config.ConfigError` raised by `load_config` when a known source type has no weight
    or a weight is not a number
  - `config.json` key `weights["judge_doc"] = 1.2`

- [ ] **Step 1: Write the failing classification tests**

Append to `memsearch/tests/test_index.py`:

```python
def test_judge_directory_files_get_their_own_source_type():
    """Keyed on the PARENT DIRECTORY name, not a full-path substring: a verdict
    tiers identically no matter which config bucket enumerated it (ADR 0030)."""
    from memsearch.index import _doc_source_type
    obs = Path("/x/coding-memory/observability-judge/2026-08-20-verdict.md")
    comp = Path("/x/coding-memory/compliance-judge/2026-08-20-verdict.md")
    assert _doc_source_type(obs, "curated_doc") == "judge_doc"
    assert _doc_source_type(comp, "curated_doc") == "judge_doc"
    # the accepted exposure, pinned so a later change has to argue with it:
    # any repo-root directory of that name tiers the same way.
    assert _doc_source_type(
        Path("/x/myrepo/observability-judge/note.md"), "repo_doc") == "judge_doc"


def test_non_judge_curated_docs_are_unchanged():
    from memsearch.index import _doc_source_type
    assert _doc_source_type(
        Path("/x/coding-memory/pr-tracking.md"), "curated_doc") == "curated_doc"
    assert _doc_source_type(
        Path("/x/coding-memory/judge-notes/x.md"), "curated_doc") == "curated_doc"
    assert _doc_source_type(
        Path("/x/docs/decisions/0030-x.md"), "curated_doc") == "curated_doc"


def test_archive_filename_wins_over_the_judge_directory():
    """Precedence is stated, not incidental: the archive carve-out is checked
    first, so a CODING_MEMORY.md parked in a judge directory stays archive_doc
    (1.0) rather than being promoted into the verdict tier."""
    from memsearch.index import _doc_source_type
    assert _doc_source_type(
        Path("/x/coding-memory/compliance-judge/CODING_MEMORY.md"),
        "curated_doc") == "archive_doc"


def judge_corpus_cfg(tmp_path: Path):
    """A corpus of its own — deliberately NOT setup_corpus(), whose file count
    is asserted verbatim by test_full_run_indexes_all_sources_newest_first
    (`processed == 5`) and test_second_run_is_idempotent (`skipped == 5`)."""
    curated = tmp_path / "coding-memory"
    (curated / "observability-judge").mkdir(parents=True)
    (curated / "observability-judge" / "2026-08-20-verdict.md").write_text(
        "# Verdict\n\nScored the change against the rubrics.\n")
    (curated / "decisions.md").write_text("# Decisions\n\nWe decided things.\n")
    p = write_cfg(tmp_path, **{
        "embed_model": "test-embed", "embed_dim": DIM,
        "db_path": str(tmp_path / "memory-index" / "memory.db"),
        "transcripts_glob": str(tmp_path / "no-transcripts" / "*.jsonl"),
        "curated_docs": [str(curated)],
        "repo_roots": [],
    })
    return load_config(p)


def test_indexing_stores_judge_doc_for_verdict_files(tmp_path):
    cfg = judge_corpus_cfg(tmp_path)
    run_index(cfg, embedder=stub_embedder, digester=stub_digester,
              progress=lambda _: None)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    types = dict(conn.execute(
        "SELECT file_path, source_type FROM chunks GROUP BY file_path"))
    conn.close()
    verdict = next(p for p in types if p.endswith("2026-08-20-verdict.md"))
    plain = next(p for p in types if p.endswith("decisions.md"))
    assert types[verdict] == "judge_doc"
    assert types[plain] == "curated_doc"
```

- [ ] **Step 2: Write the failing config-validation tests**

Append to `memsearch/tests/test_config.py`:

```python
def test_real_config_weights_cover_every_known_source_type():
    from memsearch.config import SOURCE_TYPES
    cfg = load_config(REAL_CONFIG)
    assert set(SOURCE_TYPES) <= set(cfg.weights)
    assert cfg.weights["judge_doc"] == 1.2


def test_weights_missing_a_known_source_type_is_refused(tmp_path):
    """A missing key must fail at load with a named message, not surface as a
    KeyError halfway through a query (ADR 0030)."""
    p = write_cfg(tmp_path, weights={
        "curated_doc": 1.5, "repo_doc": 1.2,
        "transcript_digest": 1.0, "archive_doc": 1.0})
    with pytest.raises(ConfigError, match="judge_doc"):
        load_config(p)


def test_non_numeric_weight_is_refused(tmp_path):
    p = write_cfg(tmp_path, weights={
        "curated_doc": "heavy", "repo_doc": 1.2, "judge_doc": 1.2,
        "transcript_digest": 1.0, "archive_doc": 1.0})
    with pytest.raises(ConfigError, match="curated_doc"):
        load_config(p)
```

- [ ] **Step 3: Run both test files to verify they fail**

Run: `cd memsearch && uv run pytest tests/test_index.py tests/test_config.py -q`
Expected: FAIL — the classification tests fail on `_doc_source_type` returning `"curated_doc"`,
`test_real_config_weights_cover_every_known_source_type` fails on `KeyError: 'judge_doc'`, and the
two refusal tests fail with `Failed: DID NOT RAISE`.

- [ ] **Step 4: Move the source-type vocabulary into `config.py` and validate weights**

In `memsearch/memsearch/config.py`, add below `_MODEL_KEYS` (`config.py:10`):

```python
SOURCE_TYPES = ("transcript_digest", "curated_doc", "repo_doc", "archive_doc",
                "judge_doc")
```

Add above `load_config`:

```python
def _validate_weights(raw: dict) -> dict:
    """Every known source type needs a weight, checked once at load. Weight is
    resolved per result at query time (ADR 0030), so a missing key would
    otherwise surface as a KeyError mid-query — after the search has run."""
    missing = [t for t in SOURCE_TYPES if t not in raw]
    if missing:
        raise ConfigError(
            "weights is missing an entry for known source type(s): "
            f"{', '.join(missing)} — add them to config.json's `weights` map")
    out = {}
    for name, value in raw.items():
        try:
            out[name] = float(value)
        except (TypeError, ValueError):
            raise ConfigError(
                f"weight for {name!r} is not a number: {value!r}") from None
    return out
```

Change `config.py:71` from `weights=dict(raw["weights"]),` to:

```python
        weights=_validate_weights(raw["weights"]),
```

In `memsearch/memsearch/db.py`, replace line 16 with a re-export so existing importers keep working
and the vocabulary has one home:

```python
from memsearch.config import SOURCE_TYPES  # noqa: F401  (re-exported: the
# vocabulary lives with the validation that checks it; db.py stays its
# historical import site)
```

Place that import with the other imports at the top of `db.py`, not at line 16. There is no cycle:
`config.py` imports nothing from the package.

- [ ] **Step 5: Add the judge-directory rule to `_doc_source_type`**

Replace `memsearch/memsearch/index.py:46-58` with:

```python
ARCHIVE_FILENAME = "CODING_MEMORY.md"
JUDGE_DIRS = frozenset({"observability-judge", "compliance-judge"})


def _doc_source_type(path: Path, default: str) -> str:
    """Classify by path, not by which bucket found it.

    The archive has three copies — the ~/.claude one reached via curated_docs
    and one inside each repo_root — and bucket-based typing would tier them
    differently (1.5 vs 1.2), ranking session narrative at or above the
    decision records it narrates. archive_doc (1.0) keeps all three
    retrievable without ever outranking a real decision record.

    Judge verdicts get the same treatment one level up, keyed on the parent
    directory name (ADR 0030): they are the one document class R9's sweep
    measured, and coding-memory/ as a whole is 461 chunks wider than that
    measurement. The archive check runs first, so the two rules cannot
    disagree about a CODING_MEMORY.md sitting under a judge directory.
    """
    if path.name == ARCHIVE_FILENAME:
        return "archive_doc"
    if path.parent.name in JUDGE_DIRS:
        return "judge_doc"
    return default
```

- [ ] **Step 6: Seed the weight in `config.json`**

In `memsearch/config.json`, replace the `weights` line with:

```json
  "weights": {"curated_doc": 1.5, "repo_doc": 1.2, "judge_doc": 1.2, "transcript_digest": 1.0, "archive_doc": 1.0}
```

**1.2 is a seed, not a decision.** Task 5 re-runs the sweep and may replace it with any value in
1.0–1.5, including 1.5.

- [ ] **Step 7: Run the two test files to verify they pass**

Run: `cd memsearch && uv run pytest tests/test_index.py tests/test_config.py -q`
Expected: PASS.

- [ ] **Step 8: Run the whole suite**

Run: `cd memsearch && uv run pytest -q`
Expected: PASS, and the count is now above the 74-test baseline by the number of tests added. No
test may have been deleted to get here.

- [ ] **Step 9: Record the tier in the README**

In `memsearch/README.md`, in the **Invariants** list, immediately after the `CODING_MEMORY.md`
bullet, add:

```markdown
- Judge verdicts under `coding-memory/observability-judge/` and `coding-memory/compliance-judge/`
  are typed `judge_doc` and carry their own weight, keyed on the parent directory so every copy
  tiers alike. Design: `../docs/decisions/0030-judge-verdict-tier-and-query-time-weight.md`.
```

- [ ] **Step 10: Commit**

```bash
cd memsearch && uv run pytest -q          # green before the commit, not after
cd .. && git commit -F - -- memsearch/memsearch/index.py memsearch/memsearch/config.py \
  memsearch/memsearch/db.py memsearch/config.json memsearch/README.md \
  memsearch/tests/test_index.py memsearch/tests/test_config.py <<'MSG'
feat(memsearch): classify judge verdicts as their own source type

Keyed on the parent directory name beside the existing archive filename
carve-out, per ADR 0030. Config load now refuses a weights map that does
not cover every known source type, so a missing key fails at load instead
of as a KeyError mid-query. judge_doc is seeded at 1.2 — a starting point;
the sweep selects the shipped value.
MSG
```

Use a scoped pathspec (never `git add -A`): other sessions may have staged work in this repo.

---

### Task 2: Weight resolved at query time

Stop reading the stored `weight` column when scoring. The column still exists after this task — its
removal is Task 3 — so this task's deliverable is exactly "ranking now follows config, and a stale
stored value has no effect", which is independently testable and independently rejectable.

**Files:**
- Modify: `memsearch/memsearch/search.py:1-5` (docstring), `:22-24` (`_CHUNK_COLS`), `:66-82`
- Test: `memsearch/tests/test_search.py`

**Interfaces:**
- Consumes: `memsearch.config.Config.weights` (validated at load, Task 1);
  `config.json` key `judge_doc` (Task 1).
- Produces:
  - `memsearch.search._weight_for(cfg: Config, source_type: str) -> float` — raises `SystemExit`
    with a message containing `--reclassify` when the type has no configured weight
  - `_CHUNK_COLS` no longer contains `"weight"`; `search()` result dicts no longer contain a
    `weight` key (they never did — it was popped at `search.py:80`)

- [ ] **Step 1: Write the failing tests**

Append to `memsearch/tests/test_search.py`:

```python
def test_score_uses_config_weight_not_the_stored_column(tmp_path):
    """The regression this task exists to prevent: two chunks whose STORED
    weights are the inverse of config's. Under index-time weight the digest
    wins; under query-time weight the curated doc does (ADR 0030)."""
    cfg = make_cfg(tmp_path)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    same_vec = vec(1.0, 0.0, 0.0)
    dbmod.replace_source(conn, "/a", "doc", "ha", [make_chunk(
        content="chunking strategy decision", source_type="curated_doc",
        weight=1.0, file_path="/curated.md")], [same_vec])
    dbmod.replace_source(conn, "/b", "doc", "hb", [make_chunk(
        content="chunking strategy decision", source_type="transcript_digest",
        weight=1.5, file_path="/digest.jsonl")], [same_vec])
    conn.close()
    out = search(cfg, "chunking strategy", k=2, embedder=near(1.0, 0.0, 0.0))
    assert out[0]["file_path"] == "/curated.md"


def test_judge_doc_scores_at_its_configured_weight(tmp_path):
    cfg = make_cfg(tmp_path, weights={
        "curated_doc": 1.5, "repo_doc": 1.2, "judge_doc": 0.5,
        "transcript_digest": 1.0, "archive_doc": 1.0})
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    same_vec = vec(1.0, 0.0, 0.0)
    dbmod.replace_source(conn, "/v", "doc", "hv", [make_chunk(
        content="verdict on the change", source_type="judge_doc",
        weight=1.5, file_path="/observability-judge/v.md")], [same_vec])
    dbmod.replace_source(conn, "/s", "doc", "hs", [make_chunk(
        content="verdict on the change", source_type="curated_doc",
        weight=1.5, file_path="/spec.md")], [same_vec])
    conn.close()
    out = search(cfg, "verdict on the change", k=2, embedder=near(1.0, 0.0, 0.0))
    assert [r["file_path"] for r in out] == ["/spec.md", "/observability-judge/v.md"]


def test_stored_source_type_with_no_configured_weight_fails_closed(tmp_path):
    """Gap 1 in the plan: config validation covers config-known types, not a
    stored row config no longer names. A silent default would reintroduce this
    feature's own failure mode — a wrong value reporting success."""
    cfg = make_cfg(tmp_path)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    dbmod.replace_source(conn, "/m", "doc", "hm", [make_chunk(
        content="an orphaned tier", source_type="mystery_doc",
        file_path="/mystery.md")], [vec(1.0, 0.0, 0.0)])
    conn.close()
    with pytest.raises(SystemExit, match="reclassify"):
        search(cfg, "an orphaned tier", k=1, embedder=near(1.0, 0.0, 0.0))
```

`make_cfg` in that file already forwards `**over` into `write_cfg`
(`tests/test_search.py:10-15`), so the `weights=` override needs no new helper.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd memsearch && uv run pytest tests/test_search.py -q`
Expected: FAIL —
`test_score_uses_config_weight_not_the_stored_column` fails with
`assert '/digest.jsonl' == '/curated.md'`,
`test_judge_doc_scores_at_its_configured_weight` fails on the returned order,
`test_stored_source_type_with_no_configured_weight_fails_closed` fails with
`DID NOT RAISE <class 'SystemExit'>`.

- [ ] **Step 3: Resolve the weight from config**

In `memsearch/memsearch/search.py`, replace `_CHUNK_COLS` (`:22-24`) with:

```python
_CHUNK_COLS = ("content", "repo_id", "repo_name", "source_type", "recall_type",
               "session_date", "file_path", "line_start", "line_end",
               "session_id")
```

Add below `_fts_query`:

```python
def _weight_for(cfg: Config, source_type: str) -> float:
    """Weight is config, not storage (ADR 0030). An indexed type config does
    not name fails closed: a default multiplier would score the row with a
    number nobody chose and report success."""
    try:
        return cfg.weights[source_type]
    except KeyError:
        raise SystemExit(
            f"memsearch: indexed chunks carry source_type {source_type!r}, "
            "which has no weight in config.json — add the key, or re-type the "
            "rows with `memsearch index --reclassify`") from None
```

Replace `search.py:80`:

```python
        r["score"] = round(base_score * _weight_for(cfg, r["source_type"]), 6)
```

Update the module docstring's second sentence (`search.py:2-3`) from
`then multiplied by source weight (curated > repo doc > digest)` to:

```python
"""Hybrid retrieval: exact brute-force cosine KNN (sqlite-vec) fused with
BM25 keyword rank (FTS5) via Reciprocal Rank Fusion, then multiplied by the
source weight config assigns that source type — resolved per result at query
time, never read from the row, so a config edit moves a ranking without a
re-index (ADR 0030). Filters are applied after fusion over a wide candidate
pool (CANDIDATES per branch), which is exact enough at this corpus size and
keeps the SQL trivial."""
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd memsearch && uv run pytest tests/test_search.py -q`
Expected: PASS, including the pre-existing `test_weight_boosts_curated_over_digest`
(`tests/test_search.py:67-79`) — its stored weights agree with config, so it is unaffected.

- [ ] **Step 5: Run the whole suite**

Run: `cd memsearch && uv run pytest -q`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd .. && git commit -F - -- memsearch/memsearch/search.py memsearch/tests/test_search.py <<'MSG'
feat(memsearch): resolve chunk weight from config at query time

search() looks up cfg.weights[source_type] after fusion instead of reading
the value frozen into the row at index time, so a weight change is a config
edit rather than a re-index (ADR 0030). A stored source_type with no
configured weight fails closed naming `index --reclassify`; the stored
column itself is dropped in the next commit.
MSG
```

---

### Task 3: Drop the stored column, under a versioned migration

The `weight` column is now dead. Removing it is a one-way schema change, so it ships with a
`PRAGMA user_version` migration that runs only from `index`, takes a rollback copy first, and fails
closed. Storage and migration are one task because neither half is shippable alone: dropping the
column without the migration breaks every existing database, and migrating without dropping it
migrates nothing.

**Files:**
- Modify: `memsearch/memsearch/db.py:15` (versions), `:21-33` (`Chunk`), `:59-89` (`_init_schema`),
  `:109-145` (`replace_source`)
- Modify: `memsearch/memsearch/chunk.py:109-125`, `:127-154` (chunker signatures)
- Modify: `memsearch/memsearch/index.py:146-162` (`run_index` head), `:164-171`, `:193-200`
- Modify: `memsearch/memsearch/search.py:37-40` (migration guard)
- Modify: `memsearch/memsearch/cli.py:59-66` (report the backup)
- Modify: `memsearch/tests/conftest.py:13-28`, `memsearch/tests/test_search.py`,
  `memsearch/tests/test_chunk.py:69`, `memsearch/tests/test_index.py:191-199`
- Test: `memsearch/tests/test_migrate.py` (create)

**Interfaces:**
- Consumes: `search._weight_for` (Task 2) — nothing in `search()` reads the column any more.
- Produces:
  - `db.USER_VERSION: int` = `1` (0 = the pre-0030 schema carrying `chunks.weight`)
  - `db.schema_version(conn) -> int`
  - `db.migration_required(conn) -> str | None` — a ready-to-print message naming `memsearch index`
  - `db.migrate(db_path: Path, embed_model: str, embed_dim: int, progress=print) -> dict | None` —
    returns `{"from_version": int, "to_version": int, "backup": str}` or `None` if nothing to do
  - `db._drop_weight_column(conn) -> None` — the DDL, factored out so a test can make it fail
  - `db.Chunk` no longer has a `weight` field
  - `chunk.chunk_doc(path, text, repo_id, repo_name, source_type, session_date) -> list[Chunk]`
  - `chunk.chunk_digest(digest_md, extract, repo_id, repo_name, transcript_path) -> list[Chunk]`
  - `run_index(...)` report gains key `"migration"`, valued as `migrate()`'s return

- [ ] **Step 1: Write the failing migration tests**

Create `memsearch/tests/test_migrate.py`:

```python
"""Schema migration 0 -> 1: the stored chunks.weight column is dropped.

Version 0 databases are built here with the literal pre-0030 CREATE TABLE
rather than by importing an old build, so the fixture cannot drift into
agreeing with the code it grades."""
import sqlite3
from pathlib import Path

import pytest

from memsearch import db as dbmod
from memsearch.config import load_config
from memsearch.index import run_index
from memsearch.search import search
from tests.conftest import DIM, vec
from tests.test_config import write_cfg

V0_CHUNKS = (
    "CREATE TABLE chunks("
    "id INTEGER PRIMARY KEY,"
    "source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,"
    "content TEXT NOT NULL, repo_id TEXT NOT NULL, repo_name TEXT NOT NULL,"
    "source_type TEXT NOT NULL, recall_type TEXT NOT NULL,"
    "session_date TEXT NOT NULL, file_path TEXT NOT NULL,"
    "line_start INTEGER NOT NULL, line_end INTEGER NOT NULL,"
    "session_id TEXT, weight REAL NOT NULL, content_hash TEXT NOT NULL)")


def make_cfg(tmp_path, **over):
    """An empty corpus on purpose: run_index here exercises the migration, not
    the walk, so nothing must be reachable to index."""
    p = write_cfg(tmp_path, **{
        "embed_model": "test-embed", "embed_dim": DIM,
        "db_path": str(tmp_path / "mi" / "memory.db"),
        "transcripts_glob": str(tmp_path / "none" / "*.jsonl"),
        "curated_docs": [], "repo_roots": [], **over})
    return load_config(p)


def build_v0(cfg) -> None:
    """A database in the pre-0030 shape: user_version 0, weight column present,
    one curated_doc chunk with a STALE stored weight of 1.0."""
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    conn.execute("DROP TABLE chunks")
    conn.execute(V0_CHUNKS)
    conn.execute("PRAGMA user_version = 0")
    with conn:
        sid = conn.execute(
            "INSERT INTO sources(path, kind, content_hash, indexed_at) "
            "VALUES('/x/doc.md','doc','h','2026-08-20T00:00:00+00:00')").lastrowid
        conn.execute(
            "INSERT INTO chunks(source_id, content, repo_id, repo_name,"
            "source_type, recall_type, session_date, file_path, line_start,"
            "line_end, session_id, weight, content_hash) "
            "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (sid, "a stored decision", ".claude", ".claude", "curated_doc",
             "decision", "2026-08-20", "/x/doc.md", 1, 9, None, 1.0, "ch"))
    conn.close()


def columns(cfg) -> list[str]:
    conn = sqlite3.connect(cfg.db_path)
    cols = [r[1] for r in conn.execute("PRAGMA table_info(chunks)")]
    conn.close()
    return cols


def version(cfg) -> int:
    conn = sqlite3.connect(cfg.db_path)
    v = conn.execute("PRAGMA user_version").fetchone()[0]
    conn.close()
    return v


def test_fresh_database_is_created_at_the_current_version(tmp_path):
    cfg = make_cfg(tmp_path)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    conn.close()
    assert version(cfg) == dbmod.USER_VERSION
    assert "weight" not in columns(cfg)


def test_migrate_drops_the_column_and_keeps_the_rows(tmp_path):
    cfg = make_cfg(tmp_path)
    build_v0(cfg)
    result = dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                           progress=lambda _: None)
    assert result["from_version"] == 0 and result["to_version"] == dbmod.USER_VERSION
    assert version(cfg) == dbmod.USER_VERSION
    assert "weight" not in columns(cfg)
    conn = sqlite3.connect(cfg.db_path)
    assert conn.execute("SELECT content FROM chunks").fetchall() == \
        [("a stored decision",)]
    conn.close()


def test_migrate_takes_a_restorable_copy_first(tmp_path):
    cfg = make_cfg(tmp_path)
    build_v0(cfg)
    result = dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                           progress=lambda _: None)
    backup = Path(result["backup"])
    assert backup.exists()
    # restoring is a cp: the copy still has the old shape and the old rows
    conn = sqlite3.connect(backup)
    cols = [r[1] for r in conn.execute("PRAGMA table_info(chunks)")]
    rows = conn.execute("SELECT weight FROM chunks").fetchall()
    conn.close()
    assert "weight" in cols and rows == [(1.0,)]


def test_migrate_is_idempotent(tmp_path):
    cfg = make_cfg(tmp_path)
    build_v0(cfg)
    dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                  progress=lambda _: None)
    assert dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                         progress=lambda _: None) is None


def test_migrate_on_a_missing_database_is_a_no_op(tmp_path):
    cfg = make_cfg(tmp_path)
    assert dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                         progress=lambda _: None) is None


def test_a_failed_drop_leaves_the_database_untouched(tmp_path, monkeypatch):
    """Fail closed: version unchanged, column still there, and the message
    names the copy already taken (ADR 0030)."""
    cfg = make_cfg(tmp_path)
    build_v0(cfg)

    def boom(conn):
        raise sqlite3.OperationalError("database is locked")

    monkeypatch.setattr(dbmod, "_drop_weight_column", boom)
    with pytest.raises(SystemExit) as e:
        dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                      progress=lambda _: None)
    assert "database is locked" in str(e.value) and ".bak" in str(e.value)
    assert version(cfg) == 0
    assert "weight" in columns(cfg)


def test_an_earlier_migration_copy_is_removed(tmp_path):
    """The copy is deleted on the NEXT successful migration, not kept forever."""
    cfg = make_cfg(tmp_path)
    build_v0(cfg)
    stale = cfg.db_path.parent / (cfg.db_path.name + ".pre-v7.bak")
    stale.write_bytes(b"an older migration's copy")
    dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                  progress=lambda _: None)
    assert not stale.exists()


def test_index_migrates_but_query_refuses(tmp_path):
    """A read must never write schema: query names `memsearch index` as the fix
    and does not fall back to the stored column (ADR 0030)."""
    cfg = make_cfg(tmp_path)
    build_v0(cfg)
    with pytest.raises(SystemExit, match="memsearch index"):
        search(cfg, "a stored decision", k=1,
               embedder=lambda texts: [vec(1.0) for _ in texts])
    assert version(cfg) == 0            # the failed query migrated nothing

    report = run_index(cfg, embedder=lambda texts: [vec(1.0) for _ in texts],
                       digester=lambda extract: "## Summary\nx\n",
                       progress=lambda _: None)
    assert report["migration"]["to_version"] == dbmod.USER_VERSION
    assert version(cfg) == dbmod.USER_VERSION
```

`make_cfg` here points `transcripts_glob` and `curated_docs` at the real config's values, which is
wrong for `run_index` — override them in `make_cfg` above by adding
`"transcripts_glob": str(tmp_path / "none" / "*.jsonl"), "curated_docs": [], "repo_roots": []` to
the `write_cfg` defaults, so `run_index` walks an empty corpus and exercises only the migration.

- [ ] **Step 2: Run the migration tests to verify they fail**

Run: `cd memsearch && uv run pytest tests/test_migrate.py -q`
Expected: FAIL — `AttributeError: module 'memsearch.db' has no attribute 'USER_VERSION'` on most,
and `test_fresh_database_is_created_at_the_current_version` failing on `"weight" in columns`.

- [ ] **Step 3: Add the version, the migration and the backup to `db.py`**

In `memsearch/memsearch/db.py`, beside `SCHEMA_VERSION` (`:15`):

```python
SCHEMA_VERSION = "1"
USER_VERSION = 1      # PRAGMA user_version. 0 = pre-ADR-0030: chunks.weight
BACKUP_SUFFIX = ".bak"
```

Add `import shutil`-free copy support via the stdlib sqlite3 backup API — no new import beyond
`sqlite3`, already imported at `db.py:8`.

Replace the `chunks` CREATE (`db.py:67-75`) with the same statement minus `weight REAL NOT NULL,`:

```python
        conn.execute(
            "CREATE TABLE IF NOT EXISTS chunks("
            "id INTEGER PRIMARY KEY,"
            "source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,"
            "content TEXT NOT NULL, repo_id TEXT NOT NULL, repo_name TEXT NOT NULL,"
            "source_type TEXT NOT NULL, recall_type TEXT NOT NULL,"
            "session_date TEXT NOT NULL, file_path TEXT NOT NULL,"
            "line_start INTEGER NOT NULL, line_end INTEGER NOT NULL,"
            "session_id TEXT, content_hash TEXT NOT NULL)")
```

Make `_init_schema` stamp a fresh database at the current version — it must decide *before* the
`CREATE TABLE IF NOT EXISTS` runs, so amend its head (`db.py:59-60`):

```python
def _init_schema(conn: sqlite3.Connection, embed_model: str, embed_dim: int) -> None:
    # Decided before the CREATE below: a database that already has chunks is
    # pre-existing, and only migrate() may move its version.
    is_fresh = conn.execute(
        "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='chunks'"
    ).fetchone()[0] == 0
    with conn:
```

and, at the end of that `with conn:` block after the three `INSERT OR IGNORE` statements:

```python
        if is_fresh:
            # PRAGMA takes no bound parameter; USER_VERSION is a module
            # constant, never user input — the same reasoning as the inlined
            # KNN LIMIT at search.py:44-45.
            conn.execute(f"PRAGMA user_version = {USER_VERSION}")
```

Add, below `model_mismatch` (`db.py:100`):

```python
def schema_version(conn: sqlite3.Connection) -> int:
    return conn.execute("PRAGMA user_version").fetchone()[0]


def migration_required(conn: sqlite3.Connection) -> str | None:
    """A ready-to-print message, or None. Read paths call this and refuse;
    they never migrate — a plain query must not become a schema writer, and
    must not queue behind a multi-hour backfill (ADR 0030)."""
    found = schema_version(conn)
    if found >= USER_VERSION:
        return None
    return (f"index database is at schema version {found}, this build needs "
            f"{USER_VERSION} — run `memsearch index` to migrate it")


def _backup_path(db_path: Path, from_version: int) -> Path:
    return db_path.parent / f"{db_path.name}.pre-v{from_version}{BACKUP_SUFFIX}"


def _take_backup(conn: sqlite3.Connection, db_path: Path,
                 from_version: int) -> Path:
    """Rollback is a file copy, taken before the drop: the database is one
    file, so restoring it is a cp — seconds, against the multi-hour
    `index --full` (ADR 0030). Copies from earlier migrations are removed
    here, so one stale copy never outlives the schema it belonged to."""
    target = _backup_path(db_path, from_version)
    for old in db_path.parent.glob(f"{db_path.name}.pre-v*{BACKUP_SUFFIX}"):
        if old != target:
            old.unlink()
    target.unlink(missing_ok=True)
    dest = sqlite3.connect(target)
    try:
        with dest:
            conn.backup(dest)      # page-level copy: consistent under a hot DB
    finally:
        dest.close()
    return target


def _drop_weight_column(conn: sqlite3.Connection) -> None:
    """Factored out so a test can make it fail. Guarded because a database may
    reach version 0 without the column (a fresh DB from a build between the
    column's removal and the version stamp)."""
    cols = [r[1] for r in conn.execute("PRAGMA table_info(chunks)")]
    if "weight" in cols:
        conn.execute("ALTER TABLE chunks DROP COLUMN weight")


def migrate(db_path: Path, embed_model: str, embed_dim: int,
            progress=print) -> dict | None:
    """One-way, versioned, and run only from a write command. Returns None when
    there is nothing to do — a missing database, or one already current."""
    if not db_path.exists():
        return None
    conn = connect(db_path, embed_model, embed_dim)
    try:
        found = schema_version(conn)
        if found >= USER_VERSION:
            return None
        backup = _take_backup(conn, db_path, found)
        try:
            with conn:
                _drop_weight_column(conn)
                conn.execute(f"PRAGMA user_version = {USER_VERSION}")
        except Exception as e:
            # Fail closed: the transaction rolled back, so user_version and the
            # column are both as they were. Name the copy already on disk.
            raise SystemExit(
                f"memsearch: schema migration {found} -> {USER_VERSION} failed "
                f"({e}) — the database is unchanged; a pre-migration copy is at "
                f"{backup}") from None
        progress(f"migrated schema {found} -> {USER_VERSION}; "
                 f"pre-migration copy at {backup}")
        return {"from_version": found, "to_version": USER_VERSION,
                "backup": str(backup)}
    finally:
        conn.close()
```

- [ ] **Step 4: Stop writing the column**

In `memsearch/memsearch/db.py`, delete `weight: float` from `Chunk` (`db.py:33`), and in
`replace_source` (`db.py:130-140`) drop it from both the column list and the values tuple:

```python
        for chunk, emb in zip(chunks, embeddings):
            cid = conn.execute(
                "INSERT INTO chunks(source_id, content, repo_id, repo_name,"
                "source_type, recall_type, session_date, file_path, line_start,"
                "line_end, session_id, content_hash) "
                "VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                (sid, chunk.content, chunk.repo_id, chunk.repo_name,
                 chunk.source_type, chunk.recall_type, chunk.session_date,
                 chunk.file_path, chunk.line_start, chunk.line_end,
                 chunk.session_id,
                 sha256_text(chunk.content))).lastrowid
```

In `memsearch/memsearch/chunk.py`, drop the `weight` parameter and field from both chunkers:

```python
def chunk_doc(path: Path, text: str, repo_id: str, repo_name: str,
              source_type: str, session_date: str) -> list[Chunk]:
```
with `weight=weight` removed from the `Chunk(...)` construction at `chunk.py:122`, and

```python
def chunk_digest(digest_md: str, extract: SessionExtract, repo_id: str,
                 repo_name: str, transcript_path: str) -> list[Chunk]:
```
with `weight=weight` removed at `chunk.py:153`.

In `memsearch/memsearch/index.py`, drop the two lookups. The doc loop (`index.py:164-171`) becomes:

```python
    for path, repo_id, repo_name, source_type in _iter_docs(cfg):
        _index_one(conn, cfg, report, path, progress, kind="doc",
                   make_chunks=lambda p=path, rid=repo_id, rname=repo_name,
                   st=source_type: chunk_doc(
                       p, p.read_text(errors="replace"), rid, rname, st,
                       _mtime_date(p)),
                   embedder=embedder)
```

and `_transcript_chunks` (`index.py:199-200`):

```python
    return chunk_digest(digest_md, extract, repo_id, repo_name, str(path))
```

- [ ] **Step 5: Migrate from `index`, refuse from `query`**

In `memsearch/memsearch/index.py`, inside `run_index` between the `--full` unlink and the `connect`
(`index.py:148-150`):

```python
    if full and cfg.db_path.exists():
        cfg.db_path.unlink()  # model/dim may have changed: rebuild from scratch
    # Before connect(): the only command that may write schema is this one.
    # After the unlink, so --full never migrates a database it just deleted.
    migration = dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                              progress)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
```

and add it to the report (`index.py:157`):

```python
    report = {"processed": 0, "skipped": 0, "chunks_added": 0, "errors": [],
              "migration": migration}
```

In `memsearch/memsearch/search.py`, insert the guard directly after the existing model-mismatch
block (`search.py:38-40`), so a read refuses an unmigrated database before it embeds anything:

```python
    mismatch = dbmod.model_mismatch(conn, cfg.embed_model, cfg.embed_dim)
    if mismatch:
        raise SystemExit(f"memsearch: {mismatch}")
    stale = dbmod.migration_required(conn)
    if stale:
        conn.close()
        raise SystemExit(f"memsearch: {stale}")
```

In `memsearch/memsearch/cli.py`, in the `index` branch (`cli.py:59-66`), print the backup so the
rollback route is named in the output the operator actually reads:

```python
        if args.cmd == "index":
            report = indexmod.run_index(cfg, full=args.full, limit=args.limit)
            if report["migration"]:
                m = report["migration"]
                print(f"schema {m['from_version']} -> {m['to_version']}; "
                      f"rollback copy: {m['backup']}")
            print(f"processed={report['processed']} skipped={report['skipped']} "
                  f"chunks_added={report['chunks_added']} "
                  f"errors={len(report['errors'])}")
```

- [ ] **Step 6: Run the migration tests to verify they pass**

Run: `cd memsearch && uv run pytest tests/test_migrate.py -q`
Expected: PASS (9 tests).

- [ ] **Step 7: Run the whole suite and read the failures**

Run: `cd memsearch && uv run pytest -q`
Expected: FAIL — `TypeError: Chunk.__init__() got an unexpected keyword argument 'weight'` from
`tests/conftest.py:25`, and `tests/test_chunk.py:69` / `tests/test_index.py:198` asserting on a
value that no longer exists. **These are the mechanical consequences of a deliberate signature
change, not evidence the behaviour is wrong.** Fix them in the next step, on their own, and change
no assertion's *meaning*.

- [ ] **Step 8: Adapt the tests the signature change broke**

`memsearch/tests/conftest.py:13-28` — delete the `weight=1.5,` line from `make_chunk`'s `base` dict.

`memsearch/tests/test_search.py` — delete every `weight=` kwarg passed to `make_chunk` (in `seed`
at `:24,29,35`, in `test_weight_boosts_curated_over_digest` at `:72,76`, and in the three tests
added in Task 2). `test_score_uses_config_weight_not_the_stored_column` loses its premise — there is
no stored column to contradict — so **replace it** with:

```python
def test_score_uses_config_weight(tmp_path):
    """Post-migration form of the query-time-weight test: there is no stored
    weight left to contradict, so the guarantee is now structural — ordering
    follows cfg.weights and nothing else."""
    cfg = make_cfg(tmp_path, weights={
        "curated_doc": 1.0, "repo_doc": 1.2, "judge_doc": 1.2,
        "transcript_digest": 1.5, "archive_doc": 1.0})
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    same_vec = vec(1.0, 0.0, 0.0)
    dbmod.replace_source(conn, "/a", "doc", "ha", [make_chunk(
        content="chunking strategy decision", source_type="curated_doc",
        file_path="/curated.md")], [same_vec])
    dbmod.replace_source(conn, "/b", "doc", "hb", [make_chunk(
        content="chunking strategy decision", source_type="transcript_digest",
        file_path="/digest.jsonl")], [same_vec])
    conn.close()
    out = search(cfg, "chunking strategy", k=2, embedder=near(1.0, 0.0, 0.0))
    # config inverts the usual order, and the ranking follows config.
    assert out[0]["file_path"] == "/digest.jsonl"
```

`memsearch/tests/test_chunk.py:69` — drop the weight clause:

```python
    assert all(c.source_type == "curated_doc" for c in chunks)
```
and remove the `weight` argument from that test's `chunk_doc(...)` call.

`memsearch/tests/test_index.py:191-199` — the archive tier test loses its stored-weight assertion
and keeps the tier assertion:

```python
def test_archive_doc_gets_its_own_weight_tier(tmp_path):
    """1.0, not curated_doc's 1.5: session narrative must stay retrievable
    without ever outranking the decision records it narrates. Weight is no
    longer stored (ADR 0030), so the tier is asserted where it now lives —
    the source_type on the row, and the number in config."""
    cfg = make_cfg(tmp_path)
    run_index(cfg, embedder=stub_embedder, digester=stub_digester,
              progress=lambda _: None)
    assert archive_rows(cfg, "source_type") == ["archive_doc"]
    assert cfg.weights["archive_doc"] < cfg.weights["curated_doc"]
```

Search for any remaining reference before moving on:

Run: `cd memsearch && grep -rn "weight" tests/ memsearch/`
Expected: hits only in `config.py` (`weights`), `search.py` (`_weight_for`, docstring),
`config.json`, the tests that assert on `cfg.weights`, and `test_migrate.py`'s v0 fixture. **No hit
may construct a `Chunk` with a weight or select the column outside `test_migrate.py`.**

- [ ] **Step 9: Run the whole suite to verify it passes**

Run: `cd memsearch && uv run pytest -q`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
cd .. && git commit -F - -- memsearch/memsearch/db.py memsearch/memsearch/chunk.py \
  memsearch/memsearch/index.py memsearch/memsearch/search.py memsearch/memsearch/cli.py \
  memsearch/tests/test_migrate.py memsearch/tests/conftest.py memsearch/tests/test_search.py \
  memsearch/tests/test_chunk.py memsearch/tests/test_index.py <<'MSG'
feat(memsearch)!: drop the stored chunks.weight column under a versioned migration

Weight is resolved from config at query time, so the stored copy is a second
authority for a derived value. It is removed under PRAGMA user_version 0 -> 1,
which runs only from `index`, takes a page-level copy of the database first,
and fails closed leaving user_version untouched. `query` against an
unmigrated database refuses and names `memsearch index`; it never falls back
to the stored column. One-way: old code cannot read a migrated database.
Rollback is a cp of the .pre-v0.bak copy (ADR 0030).
MSG
```

---

### Task 4: `index --reclassify`

Existing rows carry the source type they were given at index time, and the indexer skips any file
whose content has not moved (`index.py:207-209`) — so without this pass, no verdict already in the
corpus ever becomes a `judge_doc`.

**Files:**
- Create: `memsearch/memsearch/reclassify.py`
- Modify: `memsearch/memsearch/cli.py:29-33` (parser), `:59-66` (dispatch)
- Test: `memsearch/tests/test_reclassify.py` (create)

**Interfaces:**
- Consumes: `index._iter_docs(cfg) -> list[tuple[Path, str, str, str]]`;
  `db.migration_required` (Task 3); `config.Config.weights` (Task 1).
- Produces:
  - `reclassify.run_reclassify(cfg: Config, walker=None, progress=print) -> dict` with keys
    `walked`, `unchanged`, `retyped_files`, `retyped_chunks`, `transitions`
    (`{"curated_doc->judge_doc": {"files": int, "chunks": int}}`), `vanished_sources`,
    `skipped` (`list[str]`), `verified` (`bool`)
  - `reclassify._update_one(conn, path: str, was: str, now: str) -> int` — one file's UPDATE,
    factored out so a test can make the second call fail
  - CLI: `memsearch index --reclassify`, mutually exclusive with `--full`, exit 1 if anything was
    skipped

- [ ] **Step 1: Write the failing tests**

Create `memsearch/tests/test_reclassify.py`:

```python
"""index --reclassify: re-type stored rows from the real source enumeration."""
from pathlib import Path

import pytest

from memsearch import cli
from memsearch import db as dbmod
from memsearch import reclassify
from memsearch.config import load_config
from memsearch.index import run_index
from tests.conftest import DIM, vec
from tests.test_config import write_cfg


def stub_embedder(texts):
    return [[0.1] * DIM for _ in texts]


def corpus_cfg(tmp_path: Path):
    """Two curated docs, one of them under a judge directory. Indexed BEFORE
    the judge rule existed is simulated by re-typing the row back to
    curated_doc — the same state a pre-0030 index is in."""
    curated = tmp_path / "coding-memory"
    (curated / "compliance-judge").mkdir(parents=True)
    (curated / "compliance-judge" / "verdict.md").write_text(
        "# Verdict\n\nZero violations.\n")
    (curated / "decisions.md").write_text("# Decisions\n\nWe decided things.\n")
    p = write_cfg(tmp_path, **{
        "embed_model": "test-embed", "embed_dim": DIM,
        "db_path": str(tmp_path / "mi" / "memory.db"),
        "transcripts_glob": str(tmp_path / "none" / "*.jsonl"),
        "curated_docs": [str(curated)], "repo_roots": []})
    return load_config(p)


def seed_pre_0030(cfg):
    run_index(cfg, embedder=stub_embedder, digester=lambda e: "",
              progress=lambda _: None)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    with conn:
        conn.execute("UPDATE chunks SET source_type='curated_doc' "
                     "WHERE source_type='judge_doc'")
    conn.close()


def types(cfg) -> dict:
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    out = dict(conn.execute(
        "SELECT file_path, source_type FROM chunks GROUP BY file_path"))
    conn.close()
    return out


def test_retypes_only_the_disagreeing_files(tmp_path):
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    r = reclassify.run_reclassify(cfg, progress=lambda _: None)
    stored = types(cfg)
    verdict = next(p for p in stored if p.endswith("verdict.md"))
    plain = next(p for p in stored if p.endswith("decisions.md"))
    assert stored[verdict] == "judge_doc"
    assert stored[plain] == "curated_doc"
    assert r["transitions"] == {
        "curated_doc->judge_doc": {"files": 1, "chunks": r["retyped_chunks"]}}
    assert r["retyped_chunks"] >= 1


def test_reports_the_denominator_not_just_the_transition(tmp_path):
    """"N files re-typed" reads identically whether the pass walked the whole
    corpus or died a third of the way in (ADR 0030)."""
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    r = reclassify.run_reclassify(cfg, progress=lambda _: None)
    assert r["walked"] == 2
    assert r["retyped_files"] == 1
    assert r["unchanged"] == 1
    assert r["walked"] == r["unchanged"] + r["retyped_files"]
    assert r["verified"] is True


def test_second_pass_is_a_no_op(tmp_path):
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    reclassify.run_reclassify(cfg, progress=lambda _: None)
    r = reclassify.run_reclassify(cfg, progress=lambda _: None)
    assert r["retyped_files"] == 0 and r["transitions"] == {}
    assert r["walked"] == 2 and r["unchanged"] == 2


def test_a_computed_type_with_no_weight_aborts_before_any_write(tmp_path):
    """The second lock on the gap config-load validation cannot see."""
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    before = types(cfg)

    def walker(_cfg):
        return [(Path(p), ".claude", ".claude", "mystery_doc")
                for p in before]

    with pytest.raises(SystemExit, match="mystery_doc"):
        reclassify.run_reclassify(cfg, walker=walker, progress=lambda _: None)
    assert types(cfg) == before


def test_an_unreachable_walk_entry_is_skipped_and_the_walk_continues(tmp_path):
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    from memsearch.index import _iter_docs

    def walker(c):
        return [(tmp_path / "gone.md", ".claude", ".claude", "curated_doc"),
                *_iter_docs(c)]

    r = reclassify.run_reclassify(cfg, walker=walker, progress=lambda _: None)
    assert len(r["skipped"]) == 1 and "gone.md" in r["skipped"][0]
    assert r["walked"] == 2                     # the skip is not walked
    assert r["retyped_files"] == 1              # and the rest still ran


def test_a_vanished_source_is_counted_and_left_alone(tmp_path):
    """Not deleted: pruning is replace_source's job, and a pass named
    "reclassify" must not quietly become a destructive one (ADR 0030)."""
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    (Path(cfg.curated_docs[0]) / "decisions.md").unlink()
    r = reclassify.run_reclassify(cfg, progress=lambda _: None)
    assert r["vanished_sources"] == 1
    assert any(p.endswith("decisions.md") for p in types(cfg))


def test_a_mid_walk_failure_rolls_the_whole_pass_back(tmp_path, monkeypatch):
    """One transaction: a partially re-typed corpus would score some verdicts
    at the new weight and some at the old, and no measurement taken against it
    would mean anything (ADR 0030)."""
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    before = types(cfg)
    from memsearch.index import _iter_docs

    def walker(c):
        # both files disagree, so there are two updates to apply
        return [(p, r, n, "repo_doc") for p, r, n, _t in _iter_docs(c)]

    calls = []
    real = reclassify._update_one

    def flaky(conn, path, was, now):
        calls.append(path)
        if len(calls) == 2:
            raise RuntimeError("write failed mid-walk")
        return real(conn, path, was, now)

    monkeypatch.setattr(reclassify, "_update_one", flaky)
    with pytest.raises(RuntimeError, match="mid-walk"):
        reclassify.run_reclassify(cfg, walker=walker, progress=lambda _: None)
    assert types(cfg) == before


def test_cli_reclassify_reports_and_exits_zero(tmp_path, capsys):
    cfg_path = str(tmp_path / "config.json")
    cfg = corpus_cfg(tmp_path)          # writes tmp_path/config.json
    seed_pre_0030(cfg)
    rc = cli.main(["--config", cfg_path, "index", "--reclassify"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "curated_doc -> judge_doc: 1 files" in out
    assert "walked=2" in out and "unchanged=1" in out


def test_cli_reclassify_and_full_are_mutually_exclusive(tmp_path):
    cfg = corpus_cfg(tmp_path)
    with pytest.raises(SystemExit) as e:
        cli.main(["--config", str(tmp_path / "config.json"), "index",
                  "--full", "--reclassify"])
    assert e.value.code == 2
```

`corpus_cfg` writes its config to `tmp_path / "config.json"` (that is what `write_cfg` does —
`tests/test_config.py:11-16`), so the two CLI tests can name that path directly.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd memsearch && uv run pytest tests/test_reclassify.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'memsearch.reclassify'`.

- [ ] **Step 3: Write the reclassify pass**

Create `memsearch/memsearch/reclassify.py`:

```python
"""index --reclassify: re-type stored chunks from the real source enumeration.

Driven from _iter_docs, not from the index: a pass driven from stored rows
would re-type a file that stopped being walked, and ADR 0020 records that
nothing removes such a source's chunks. Chunk text is never touched, so
nothing is re-embedded — a re-type is metadata, and the embedding is keyed on
content (ADR 0030)."""
from __future__ import annotations

from memsearch import db as dbmod
from memsearch.config import Config
from memsearch.index import _iter_docs


def _stored_doc_types(conn) -> dict[str, str]:
    """file_path -> stored source_type, for doc sources only.

    Restricted to kind='doc' because transcripts are typed by their own path
    and are not part of this walk; without the join, every transcript would be
    reported as a vanished source."""
    out: dict[str, str] = {}
    for path, stype in conn.execute(
            "SELECT DISTINCT c.file_path, c.source_type FROM chunks c "
            "JOIN sources s ON s.id = c.source_id WHERE s.kind = 'doc'"):
        if path in out and out[path] != stype:
            raise SystemExit(
                f"memsearch: {path} holds chunks of two source types "
                f"({out[path]!r} and {stype!r}) — reclassify aborted before "
                "any write; rebuild that source with `memsearch index --full`")
        out[path] = stype
    return out


def _update_one(conn, path: str, was: str, now: str) -> int:
    return conn.execute(
        "UPDATE chunks SET source_type=? WHERE file_path=? AND source_type=?",
        (now, path, was)).rowcount


def run_reclassify(cfg: Config, walker=None, progress=print) -> dict:
    walker = walker or _iter_docs
    if not cfg.db_path.exists():
        raise SystemExit("memsearch: no index found — run: memsearch index")
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    stale = dbmod.migration_required(conn)
    if stale:
        conn.close()
        raise SystemExit(f"memsearch: {stale}")
    try:
        stored = _stored_doc_types(conn)
        walked = 0
        seen: set[str] = set()
        skipped: list[str] = []
        updates: list[tuple[str, str, str]] = []

        for path, _repo_id, _repo_name, computed in walker(cfg):
            key = str(path)
            try:
                path.stat()   # the entry may have gone since enumeration
            except OSError as e:
                # One bad source never kills the run — index.py:217-219's
                # contract. Recorded, and the exit code carries it out.
                skipped.append(f"{key}: {e}")
                progress(f"SKIPPED {key}: {e}")
                continue
            if computed not in cfg.weights:
                raise SystemExit(
                    f"memsearch: {key} classifies as {computed!r}, which has "
                    "no weight in config.json — reclassify aborted before any "
                    "write")
            walked += 1
            seen.add(key)
            was = stored.get(key)
            if was is not None and was != computed:
                updates.append((key, was, computed))

        vanished = sorted(set(stored) - seen - {s.split(":")[0] for s in skipped})

        transitions: dict[str, dict[str, int]] = {}
        retyped_chunks = 0
        with conn:                      # the whole pass is one transaction
            for key, was, computed in updates:
                n = _update_one(conn, key, was, computed)
                t = transitions.setdefault(f"{was}->{computed}",
                                           {"files": 0, "chunks": 0})
                t["files"] += 1
                t["chunks"] += n
                retyped_chunks += n

        # Prove the walk converged rather than asserting it: re-read the stored
        # types and re-run the same comparison over the same walk.
        after = _stored_doc_types(conn)
        remaining = [str(p) for p, _i, _n, c in walker(cfg)
                     if str(p) in seen and after.get(str(p)) not in (None, c)]
        if remaining:
            raise SystemExit(
                f"memsearch: reclassify did not converge — {len(remaining)} "
                f"file(s) still disagree after the update, first: "
                f"{remaining[0]}")

        return {"walked": walked, "unchanged": walked - len(updates),
                "retyped_files": len(updates),
                "retyped_chunks": retyped_chunks, "transitions": transitions,
                "vanished_sources": len(vanished), "skipped": skipped,
                "verified": True}
    finally:
        conn.close()
```

- [ ] **Step 4: Wire the flag into the CLI**

In `memsearch/memsearch/cli.py`, import the module beside the others (`cli.py:10-14`):

```python
from memsearch import reclassify as reclassifymod
```

Replace the `index` subparser block (`cli.py:29-33`):

```python
    pi = sub.add_parser("index", help="incremental index (hash-diff)")
    mode = pi.add_mutually_exclusive_group()
    mode.add_argument("--full", action="store_true",
                      help="rebuild from scratch (required after model change)")
    mode.add_argument("--reclassify", action="store_true",
                      help="re-type stored chunks from the source enumeration "
                           "(no chunking, no embedding)")
    pi.add_argument("--limit", type=int, default=None,
                    help="cap transcripts processed this run")
```

At the head of the `index` branch (`cli.py:59`), before the `run_index` call:

```python
        if args.cmd == "index" and args.reclassify:
            r = reclassifymod.run_reclassify(cfg)
            for name, t in sorted(r["transitions"].items()):
                was, now = name.split("->")
                print(f"{was} -> {now}: {t['files']} files, "
                      f"{t['chunks']} chunks")
            print(f"walked={r['walked']} unchanged={r['unchanged']} "
                  f"retyped={r['retyped_files']} "
                  f"vanished_sources={r['vanished_sources']} "
                  f"skipped={len(r['skipped'])}")
            for s in r["skipped"]:
                print(f"  skipped: {s}", file=sys.stderr)
            # A partial walk must not read as a clean one.
            return 1 if r["skipped"] else 0
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd memsearch && uv run pytest tests/test_reclassify.py -q`
Expected: PASS (9 tests).

- [ ] **Step 6: Run the whole suite**

Run: `cd memsearch && uv run pytest -q`
Expected: PASS.

- [ ] **Step 7: Document the flag in the README**

In `memsearch/README.md`, in the usage block that lists the commands, add a line beside `index`:

```markdown
    memsearch index --reclassify      # re-type stored chunks from the source
                                      # enumeration (no re-embed); exits 1 if
                                      # any source was skipped
```

- [ ] **Step 8: Commit**

```bash
cd .. && git commit -F - -- memsearch/memsearch/reclassify.py memsearch/memsearch/cli.py \
  memsearch/tests/test_reclassify.py memsearch/README.md <<'MSG'
feat(memsearch): add index --reclassify

Walks the real source enumeration, compares each file's computed source type
against what is stored, and updates only where they disagree — in one
transaction, with no chunking and no embedding. Reports per-transition counts
plus the walked/unchanged/re-typed denominator, then re-runs its own
comparison and asserts zero remaining disagreements before reporting success.
Unreadable entries are skipped and carried out in the exit code; a source
whose file has vanished is counted and left alone (ADR 0030).
MSG
```

---

### Task 5: The weight sweep, and the value it selects

A measurement, not a code change. It runs ADR 0030's *"The adoption rule, stated so it can fail"* in
full: baseline first, the three-clause eligibility test, adopt-closest-to-1.5, and the explicit
adopt-nothing branch. **"No row was eligible, ship 1.5" is a first-class result** — the
classification, query-time weight and reclassify pass all still land, and R9's number is recorded
unchanged.

This is also the only task that touches the live index at `~/.claude/memory-index/memory.db`.

**Files:**
- Create: `memsearch/tests/sweep_judge_weight.py`
- Modify: `memsearch/config.json` (only if a row is adopted)
- Modify: `docs/features/memsearch-freshness.md` (R9 results — the sweep table and the decision)

**Interfaces:**
- Consumes: `search.search` with query-time weights (Task 2); `tests.test_measurement_queries.QUERIES`
  and `belongs` (unchanged); `db.migrate` and `reclassify.run_reclassify` (Tasks 3–4).
- Produces: the adopted `judge_doc` weight in `config.json`, and the recorded table.

⚠️ **Phase note for the executor.** Recording measured results in
`docs/features/memsearch-freshness.md` is a results record in the file that already owns R9's
results (`### Task 8b — R9 baseline, measured pre-R10`), not a spec edit. If the session judges it
out of phase, **escalate — do not invent a second document to hold the table.**

- [ ] **Step 1: Re-derive the population count**

The ADR's 162 / 23 were counted against the primary checkout at 2026-08-20 18:17Z and it says
plainly not to trust them. Count again, and only `*.md`, because that is what `_iter_docs` walks
(`index.py:65`):

```bash
date -u +%Y-%m-%dT%H:%MZ
ls ~/.claude/coding-memory/observability-judge/*.md | wc -l
ls ~/.claude/coding-memory/compliance-judge/*.md | wc -l
```

Write both numbers down with that stamp. They will not match the ADR's; that is the point.

- [ ] **Step 2: Confirm the environment before touching the live index**

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:11434/api/tags   # expect 200
ls -la ~/.claude/memory-index/memory.db
launchctl list | grep -i memsearch || echo "no scheduled indexer loaded"
```

If Ollama is not answering, stop — the sweep cannot embed the five queries and every row would be
identical garbage. If the scheduled indexer is loaded, note it: it can write to the same file
mid-sweep, which is exactly what Step 6's same-state proof exists to catch.

- [ ] **Step 3: Migrate and reclassify the live index**

`bin/memsearch` points at the primary checkout — use the worktree project explicitly:

```bash
cd <worktree>/memsearch
uv run --project . memsearch index            # migrates 0 -> 1, prints the rollback copy
uv run --project . memsearch index --reclassify
```

Record the printed rollback copy path, the per-transition counts, and the
walked/unchanged/re-typed denominator. `index` walks every source to hash-diff, so it takes minutes
even with nothing to re-embed; `--reclassify` is fast because it embeds nothing.

**If `index` reports a failed migration, stop.** It fails closed: the database is unchanged and the
copy it names is the rollback.

- [ ] **Step 4: Re-derive the chunk counts the ADR quotes**

The ADR quotes 2866 / 2405 / 461 from the remedy section and says the implementation re-derives
them. Now that the index is reclassified, they are three queries:

```bash
uv run --project . python - <<'PY'
import sqlite3
from memsearch.config import load_config
cfg = load_config()
conn = sqlite3.connect(cfg.db_path)
q = conn.execute
whole = q("SELECT count(*) FROM chunks WHERE file_path LIKE '%/coding-memory/%'").fetchone()[0]
judge = q("SELECT count(*) FROM chunks WHERE source_type='judge_doc'").fetchone()[0]
print(f"coding-memory/ total: {whole}")
print(f"judge_doc:            {judge}")
print(f"the remainder:        {whole - judge}")
conn.close()
PY
```

Record all three against the ADR's 2866 / 2405 / 461. A gap is information, not a failure — the
corpus has moved since those were taken.

- [ ] **Step 5: Write the sweep script**

Create `memsearch/tests/sweep_judge_weight.py`:

```python
"""ADR 0030's weight sweep, run as a script.

Deliberately NOT named test_*: pytest must never collect it. It hits the live
index and the live embedder, and it is a measurement, not an assertion.

    cd memsearch && uv run --project . python -m tests.sweep_judge_weight

Per-target hit counts and top-hit identity are recorded for EVERY row, not a
pass/fail per row: the remedy section's own table carried a verdict-level
"anything regress?" column that would have printed "no" through a
PASS(4) -> PASS(3) erosion.
"""
from __future__ import annotations

import dataclasses

from memsearch import db as dbmod
from memsearch.config import load_config
from memsearch.search import search
from tests.test_measurement_queries import QUERIES, belongs

# Baseline first, then descending. Written out rather than computed by a 0.1
# step so no float accumulation can shift a row's label.
WEIGHTS = (1.5, 1.4, 1.3, 1.2, 1.1, 1.0)
BASELINE = WEIGHTS[0]


def index_state(cfg) -> tuple[int, float]:
    """Chunk count and database mtime — the pair the sweep pins. A scheduled
    launchd indexer writes this same file, so "measured at one index state"
    has to be proved, not hoped (ADR 0030)."""
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    n = conn.execute("SELECT count(*) FROM chunks").fetchone()[0]
    conn.close()
    return n, cfg.db_path.stat().st_mtime


def measure(cfg, weight: float) -> dict:
    cfg = dataclasses.replace(cfg, weights={**cfg.weights,
                                            "judge_doc": weight})
    row = {}
    for entry in QUERIES:
        feature = entry["target_feature"]
        paths = [r["file_path"] for r in search(cfg, entry["query"],
                                                k=entry["k"])]
        hits = [p for p in paths if belongs(p, feature)]
        top = paths[0] if paths else None
        top_belongs = bool(paths) and belongs(top, feature)
        row[feature] = {"hits": len(hits), "top": top,
                        "top_belongs": top_belongs,
                        "passes": len(hits) >= 2 and top_belongs}
    return row


def passes(row: dict) -> int:
    return sum(1 for t in row.values() if t["passes"])


def is_eligible(base: dict, row: dict) -> tuple[bool, str]:
    """ADR 0030's three clauses, each reported by name so a rejection says
    which one bit."""
    if passes(row) <= passes(base):
        return False, f"pass count {passes(row)} not > baseline {passes(base)}"
    lost = [f for f in base if row[f]["hits"] < base[f]["hits"]]
    if lost:
        return False, f"targets lost hits: {', '.join(sorted(lost))}"
    dethroned = [f for f in base
                 if base[f]["top_belongs"] and not row[f]["top_belongs"]]
    if dethroned:
        return False, f"targets lost their top hit: {', '.join(sorted(dethroned))}"
    return True, "eligible"


def print_row(weight: float, row: dict) -> None:
    tag = " (baseline)" if weight == BASELINE else ""
    print(f"\n=== judge_doc = {weight}{tag}   R9: {passes(row)} of 5")
    for feature, t in row.items():
        print(f"    {'PASS' if t['passes'] else 'FAIL'}  {feature:34s} "
              f"hits={t['hits']}  top_belongs={t['top_belongs']}  "
              f"top={t['top']}")


def main() -> int:
    cfg = load_config()
    before = index_state(cfg)
    print(f"index state before: chunks={before[0]} mtime={before[1]}")

    rows = {}
    for weight in WEIGHTS:
        rows[weight] = measure(cfg, weight)
        print_row(weight, rows[weight])

    after = index_state(cfg)
    print(f"\nindex state after:  chunks={after[0]} mtime={after[1]}")
    if after != before:
        print("\nSWEEP DISCARDED — the index moved mid-sweep, so every "
              "comparison above is between two different corpora. "
              "Re-run it (ADR 0030).")
        return 1

    base = rows[BASELINE]
    verdict = {w: is_eligible(base, rows[w]) for w in WEIGHTS if w != BASELINE}
    print("\n--- eligibility, ADR 0030's three clauses")
    for weight, (ok, why) in verdict.items():
        print(f"    {weight}: {'ELIGIBLE' if ok else 'no'} — {why}")

    # Adopt the eligible row closest to 1.5: the smallest departure from
    # current behaviour that buys the improvement. WEIGHTS is descending, so
    # the first eligible row IS the closest. No tie is possible.
    adopted = next((w for w in WEIGHTS if w != BASELINE and verdict[w][0]),
                   None)
    if adopted is None:
        print("\nADOPT NOTHING — no row was eligible. judge_doc ships at "
              f"{BASELINE}, behaviourally identical to today. This is a "
              "legitimate result, not a reason to relax clause 2.")
    else:
        print(f"\nADOPT judge_doc = {adopted}  "
              f"(R9 {passes(base)} of 5 -> {passes(rows[adopted])} of 5)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 6: Run the sweep**

```bash
cd <worktree>/memsearch && uv run --project . python -m tests.sweep_judge_weight
```

Expected: six `=== judge_doc = …` blocks, each with five per-target lines carrying `hits`,
`top_belongs` and the top hit's path; then the eligibility lines; then either an `ADOPT` or the
`ADOPT NOTHING` line.

**If it prints `SWEEP DISCARDED`, the whole run is void.** Do not read the table, do not adopt a
value from it. Re-run it — and if the scheduled indexer is what moved the file, run the sweep in a
window where it is not due, or unload it for the duration and reload it after.

Copy the full output somewhere you can read it while writing Step 8 — the terminal is the record
until then; do not create a scratch file for it.

- [ ] **Step 7: Apply the rule**

If the sweep adopted a value, set it in `memsearch/config.json`:

```json
  "weights": {"curated_doc": 1.5, "repo_doc": 1.2, "judge_doc": <ADOPTED>, "transcript_digest": 1.0, "archive_doc": 1.0}
```

If it adopted nothing, set `judge_doc` to `1.5` — equal to `curated_doc`, behaviourally identical to
today — and change `tests/test_config.py::test_real_config_weights_cover_every_known_source_type`'s
`assert cfg.weights["judge_doc"] == 1.2` to the shipped value in the same edit. Either way, the seed
from Task 1 is now a measured decision.

Then record R9's post-change number:

```bash
cd <worktree>/memsearch
uv run --project . pytest -m measurement -q          # expect FAILures: R9 is a red requirement
uv run --project . python -m tests.test_measurement_queries   # the full per-hit table
uv run pytest -q                                     # the unit suite stays green
```

R9 stays 5-of-5-or-fail and stays failing — its text is untouched, and a pass count redrawn after
seeing the pass count is the move this feature already retired once
(`tests/test_measurement_queries.py:16-20`). Record the number; do not adjust the bar.

- [ ] **Step 8: Record the results**

In `docs/features/memsearch-freshness.md`, in the R9 results area (beside
`### Task 8b — R9 baseline, measured pre-R10 (2026-08-07)`), add one section containing:

- the re-derived population counts from Step 1, with their as-of stamp, against the ADR's 162 / 23;
- the re-derived 2866 / 2405 / 461 equivalents from Step 4;
- the migration and reclassify output from Step 3 (transitions plus the denominator);
- the sweep's chunk-count and mtime pair, before and after, and the statement that they matched —
  the same-index-state proof, quoted, not summarized;
- the full per-row table: every weight, every target's hit count, and every top-hit identity;
- the eligibility line for each row, naming the clause that rejected it;
- the adopted value or the explicit adopt-nothing;
- R9's post-change result from Step 7, with the note that it remains a failing requirement.

- [ ] **Step 9: Commit**

```bash
cd .. && git commit -F - -- memsearch/tests/sweep_judge_weight.py memsearch/config.json \
  memsearch/tests/test_config.py docs/features/memsearch-freshness.md <<'MSG'
feat(memsearch): run ADR 0030's weight sweep and adopt its result

Sweeps judge_doc across 1.0-1.5 against one index state — chunk count and
database mtime recorded before the first row and after the last, whole sweep
discarded if either moved — and records per-target hit counts and top-hit
identity for every row, not a verdict per row. The three-clause eligibility
rule and the adopt-closest-to-1.5 tie-break are applied as ADR 0030 states
them, including the adopt-nothing branch. R9's bar is untouched and still
failing; its number is recorded with the reason.
MSG
```

- [ ] **Step 10: Run the observability judge before opening a PR**

The repo's judge gate (`hooks/judge-guard.sh`) blocks `gh pr create` until a fresh
implementation-stage verdict matches HEAD. Follow `running-the-observability-judge`, and note that
committing a verdict invalidates it by `head_sha` — open the PR while the verdict is uncommitted,
then push it onto the PR.

---

## Self-review

Run against ADR 0030 with fresh eyes after the plan was complete.

**Spec coverage.** Every stated behaviour maps to a task:

| ADR requirement | Where |
|---|---|
| `judge_doc` keyed on parent directory, two names only | Task 1, Steps 1, 5 |
| `config.json` seeded at 1.2 | Task 1, Step 6 |
| Config load checks every known type has a weight | Task 1, Steps 2, 4 |
| Weight resolved at query time from `cfg.weights` | Task 2, Step 3 |
| `weight` leaves `_CHUNK_COLS`; write path stops emitting it | Task 2 Step 3; Task 3 Step 4 |
| The column is dropped | Task 3, Step 3 |
| Versioned via `PRAGMA user_version`, idempotent, fresh DB at current version | Task 3, Steps 3, 1 (`test_fresh_database_is_created_at_the_current_version`, `test_migrate_is_idempotent`) |
| Migration runs from `index`, never `query` | Task 3, Step 5; tested by `test_index_migrates_but_query_refuses` |
| Named error naming `memsearch index` on an unmigrated read | Task 3, Step 3 (`migration_required`) |
| No fallback to the stored column | Task 3, Step 5 — `search` raises before scoring |
| Pre-drop file copy as rollback, named in output, older copies deleted | Task 3, Step 3 (`_take_backup`), tests 3 and 7 |
| Fail closed on migration error, `user_version` unchanged | Task 3, Step 1 test 6, Step 3 |
| `--reclassify` walks the real source enumeration | Task 4, Step 3 |
| Re-types only where stored and computed disagree | Task 4, `test_retypes_only_the_disagreeing_files` |
| One transaction; mid-walk failure rolls back entirely | Task 4, `test_a_mid_walk_failure_rolls_the_whole_pass_back` |
| Unreadable source recorded, walk continues, exit non-zero | Task 4, `test_an_unreachable_walk_entry_…` + CLI `return 1 if r["skipped"]` |
| Vanished source untouched, own count, not pruned | Task 4, `test_a_vanished_source_is_counted_and_left_alone` |
| Computed type with no weight aborts before any write | Task 4, `test_a_computed_type_with_no_weight_aborts_before_any_write` |
| Per-transition counts plus the denominator | Task 4, `test_reports_the_denominator_not_just_the_transition` |
| Self-verifying second pass, zero remaining disagreements | Task 4, Step 3 (`remaining`), asserted via `verified` |
| Explicit flag, not automatic | Task 4, Step 4 — a flag, and no call from the scheduled path |
| Sweep 1.0–1.5 in 0.1 steps, baseline first | Task 5, `WEIGHTS` |
| Per-target hits and top-hit identity for **every** row | Task 5, `measure`/`print_row` |
| Three-clause eligibility, adopt closest to 1.5 | Task 5, `is_eligible`, `adopted` |
| Adopt-nothing branch, ships 1.5 | Task 5, `main`, Step 7 |
| Same-index-state proof: chunk count + mtime, discard if moved | Task 5, `index_state`, Step 6 |
| R9's text untouched, number recorded | Task 5, Steps 7–8 |
| 162 / 23 and 2866 / 2405 / 461 re-derived | Task 5, Steps 1 and 4 |
| Score ceiling unmoved for any adopted value ≤ 1.5 | No task — see below |

**One requirement with no task, deliberately.** The ADR's closing consequence about
`score_ceiling()` (`test_measurement_queries.py:120-123`) is an observation about what *will not*
change, not a behaviour to build: any adopted value ≤ 1.5 leaves `max(CFG.weights.values())` at 1.5.
Adding an assertion for it would test arithmetic. It is carried as a note here so a future change
that sets `judge_doc` above 1.5 knows the printed ceiling moves with it.

**Placeholder scan.** No "TBD", no "add appropriate error handling", no "similar to Task N", no
"write tests for the above". Every code step carries the code. One deliberate blank exists — the
adopted weight in Task 5, Step 7's JSON, written `<ADOPTED>` — because a plan that pre-fills it
would be pre-deciding the measurement the task exists to run, which is the failure ADR 0030's
adoption rule is written to prevent.

**Type consistency.** `_doc_source_type(path, default) -> str` keeps its signature across Tasks 1
and 4. `run_reclassify`'s report keys are identical in the module (Task 4, Step 3), the CLI printer
(Step 4) and every test (Step 1). `migrate()` returns the same three keys in `db.py`, in
`run_index`'s report, in `cli.py`'s printer and in `test_migrate.py`. `_weight_for` (Task 2) is the
only weight lookup left after Task 3 removes the two in `index.py`. `Chunk` loses `weight` in one
place (Task 3, Step 4) and every constructor of it is listed in Step 8.

**One fix applied during this pass.** Task 3's Step 5 first showed a mangled two-expression edit of
the `model_mismatch` line; it is replaced with the plain insertion after the existing block. Task 4's
`vanished` computation was widened to exclude skipped paths, so a file that could not be stat'd is
counted once, as a skip, and not a second time as a vanished source.
