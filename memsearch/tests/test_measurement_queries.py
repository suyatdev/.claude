"""R9's retrieval bar — five measurement queries scored at k=6 against the REAL
index.

This is a DISTINCT instrument from the golden suite, and neither substitutes for
the other: `-m golden` is the noise-regression net over the pre-existing 16;
this is the retrieval bar. `test_golden_queries.py:37-41` asserts only
`any(expect_path_contains in p for p in paths)` — presence somewhere in top-k,
with no top-hit check and no >=2 count — so both of R9's clauses are invisible
to it.

Two clauses per query, BOTH binding:
  1. >=2 hits belonging to the named feature
  2. the top hit belongs to that feature
R9 passes iff ALL FIVE queries satisfy BOTH clauses. Four of five is a failure.

There is no score clause. The retired `>=0.30` floor was unreachable by
construction — the scorer fuses two retrievers by RRF, each contributing at most
1/(RRF_K + 1), times the chunk weight, so the ceiling is ~0.049 — and a floor
redrawn after seeing where the scores landed cannot fail the only run that ever
grades it. Raw scores are still recorded as a baseline for future comparison:
run this module as a script for the full table.

Per-feature chunk counts are COMPUTED from the source files here, never read
from `memory.db` and never pinned in a file. A count pinned in a document rots —
that is the defect this whole feature exists to fix, and an earlier draft of the
spec committed it by ranking targets on figures the stale index had produced.
"""
from __future__ import annotations

import json
from collections import defaultdict
from functools import lru_cache
from pathlib import Path

import pytest

from memsearch.chunk import split_markdown
from memsearch.config import load_config
from memsearch.search import RRF_K, search

# tests/ -> memsearch/ -> repo root. Derived, so no absolute path is committed
# and a worktree checkout resolves to its own docs/.
FEATURES_DIR = Path(__file__).resolve().parents[2] / "docs" / "features"

QUERIES = json.loads(
    (Path(__file__).parent / "measurement_queries.json").read_text())
CFG = load_config()

pytestmark = pytest.mark.measurement

needs_index = pytest.mark.skipif(
    not CFG.db_path.exists(),
    reason="no index built — run memsearch index first")


def belongs(path: str, feature: str) -> bool:
    """R9 membership, mechanical: a hit belongs to feature F iff its source path
    is exactly docs/features/F.md or docs/features/F.spec.md. Nothing else
    counts — not an ADR that mentions F, not a transcript discussing it."""
    return any(path.endswith(f"docs/features/{feature}{ext}")
               for ext in (".md", ".spec.md"))


def feature_chunk_count(feature: str) -> int:
    """Summed over every file belonging to the feature. The counting unit is the
    feature, not the file (R9) — per-file is a different and weaker rule, since a
    feature read off its largest file alone can slip out of the bottom third
    while still reading as compliant."""
    return sum(len(split_markdown(p.read_text()))
               for ext in (".md", ".spec.md")
               for p in [FEATURES_DIR / f"{feature}{ext}"] if p.exists())


@lru_cache(maxsize=1)
def ranked_population() -> tuple[tuple[str, int], ...]:
    """Every feature under docs/features/, per-feature summed, ranked ascending.

    The population is the whole directory, NOT the five chosen: measured against
    the five, the span rule cannot fail — the smallest of any five sits in its
    own bottom third by construction, so every possible sample passes and the
    guard measures nothing (R9)."""
    per_feature: dict[str, int] = defaultdict(int)
    for p in sorted(FEATURES_DIR.glob("*.md")):
        name = p.name[:-8] if p.name.endswith(".spec.md") else p.name[:-3]
        per_feature[name] += len(split_markdown(p.read_text()))
    return tuple(sorted(per_feature.items(), key=lambda kv: kv[1]))


@lru_cache(maxsize=1)
def tertiles() -> tuple[frozenset[str], frozenset[str], tuple[tuple[str, int], ...]]:
    """Rank tertiles of that population: the lowest floor(N/3) entries and the
    highest floor(N/3), by RANK — not slices of the value span, under which one
    outsized feature stretches the span far enough that a mid-ranked target
    falls inside the "bottom third" (R9).

    Boundary ties: entries tied in chunk count across a tertile boundary all
    belong to that third. Decided before any count was computed, because a tie
    is indistinguishable by the metric, so ranking either side of it is
    arbitrary — and a tied entry has an identical count to a bona fide
    bottom-third entry, not merely a nearby one, so it opens no gaming room.
    """
    ranked = ranked_population()
    n = len(ranked)
    t = n // 3
    if t == 0:
        return frozenset(), frozenset(), ranked
    lo_cut, hi_cut = ranked[t - 1][1], ranked[n - t][1]
    bottom = frozenset(name for name, c in ranked if c <= lo_cut)
    top = frozenset(name for name, c in ranked if c >= hi_cut)
    return bottom, top, ranked


def band(feature: str) -> str:
    bottom, top, _ = tertiles()
    if feature in bottom:
        return "bottom"
    return "top" if feature in top else "middle"


def score_ceiling() -> float:
    """2 x 1/(RRF_K + 1) x max(weight) — the most the scorer can emit, so a
    reader compares a score against the range rather than against intuition."""
    return 2 * (1 / (RRF_K + 1)) * max(CFG.weights.values())


def run(entry: dict) -> list[dict]:
    return search(CFG, entry["query"], k=entry["k"])


def test_there_are_five_distinct_targets():
    assert len(QUERIES) == 5, f"R9 specifies five queries, got {len(QUERIES)}"
    targets = [e["target_feature"] for e in QUERIES]
    assert len(set(targets)) == 5, f"targets must be distinct, got {targets}"
    assert all(e["k"] == 6 for e in QUERIES), "R9 scores at k=6"


def test_targets_span_the_corpus_size_range():
    """R9's anti-gaming rule: a large target has many more chances to land two
    hits in a top-6 than a small one, so five fat targets would pass both
    clauses while measuring nothing."""
    bottom, top, ranked = tertiles()
    counts = dict(ranked)
    targets = {e["target_feature"] for e in QUERIES}

    missing = sorted(targets - counts.keys())
    assert not missing, f"target has no file under docs/features/: {missing}"

    sample = {f: counts[f] for f in sorted(targets, key=lambda f: counts[f])}
    assert targets & bottom, (
        f"no target in the bottom third {sorted(bottom)}; sample={sample}")
    assert targets & top, (
        f"no target in the top third {sorted(top)}; sample={sample}")


@needs_index
@pytest.mark.parametrize("entry", QUERIES,
                         ids=lambda e: e["target_feature"])
def test_measurement_query_meets_both_clauses(entry):
    feature = entry["target_feature"]
    paths = [r["file_path"] for r in run(entry)]
    hits = [p for p in paths if belongs(p, feature)]

    clause1 = len(hits) >= 2
    clause2 = bool(paths) and belongs(paths[0], feature)
    # Both clauses are evaluated before asserting, so a failure reports the
    # status of each rather than hiding the second behind the first.
    assert clause1 and clause2, (
        f"{feature} ({feature_chunk_count(feature)} chunks, "
        f"{band(feature)} third)\n"
        f"  clause 1, >=2 hits belonging:  {'PASS' if clause1 else 'FAIL'} "
        f"({len(hits)} of {len(paths)})\n"
        f"  clause 2, top hit belongs:     {'PASS' if clause2 else 'FAIL'} "
        f"(top={paths[0] if paths else None})\n"
        f"  top-{entry['k']}: {paths}")


def _report() -> None:
    """Task 8b's baseline record: every hit's score alongside whether it belongs
    to the named feature, with no pass/fail derived from the numbers.

    Scores print as `search()` returns them — that call rounds to 6 decimal
    places at search.py:80, so 6dp is the finest resolution available, not a
    rounding applied here."""
    ranked = ranked_population()
    print(f"score ceiling: 2 x 1/({RRF_K}+1) x max(weight)="
          f"{max(CFG.weights.values())} = {score_ceiling():.5f}\n")
    print("per-feature chunk counts, whole docs/features/ population, "
          "ranked ascending (computed from source):")
    n = len(ranked)
    t = n // 3
    for i, (name, c) in enumerate(ranked, 1):
        print(f"  {i:2d}. {c:4d}  {name:38s} {band(name)}"
              f"{'  <-- target' if any(e['target_feature'] == name for e in QUERIES) else ''}")
    print(f"  N={n}, floor(N/3)={t}\n")

    for entry in QUERIES:
        feature = entry["target_feature"]
        results = run(entry)
        paths = [r["file_path"] for r in results]
        hits = [p for p in paths if belongs(p, feature)]
        clause1, clause2 = len(hits) >= 2, bool(paths) and belongs(paths[0], feature)
        print(f"--- {feature}  ({feature_chunk_count(feature)} chunks, "
              f"{band(feature)} third)")
        print(f"    query: {entry['query']!r}")
        for rank, r in enumerate(results, 1):
            mark = "*" if belongs(r["file_path"], feature) else " "
            print(f"    {mark}{rank}. {r['score']:<10} {r['source_type']:16s} "
                  f"{r['file_path']}:{r['line_start']}-{r['line_end']}")
        print(f"    clause 1 (>=2 hits): {'PASS' if clause1 else 'FAIL'} "
              f"({len(hits)});  clause 2 (top belongs): "
              f"{'PASS' if clause2 else 'FAIL'}\n")


if __name__ == "__main__":
    _report()
