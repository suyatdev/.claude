"""Retrieval-quality acceptance bar (observability-judge flag a). Runs against
the REAL index — excluded from the default unit run via the golden marker.
must: expected source in top-K — this is the bar. negative + stretch: reported
as warnings, never fail the bar. Negatives can't be hard asserts: RRF scores
are rank-based with no absolute confidence floor, and brute-force KNN always
returns nearest neighbors even for off-topic queries — a warned negative is
calibration data (a future cosine-distance floor is the recorded fix if
negatives misbehave in practice)."""
import json
import warnings
from pathlib import Path

import pytest

from memsearch.config import load_config
from memsearch.search import search

GOLDEN = json.loads(
    (Path(__file__).parent / "golden_queries.json").read_text())
CFG = load_config()

pytestmark = [
    pytest.mark.golden,
    pytest.mark.skipif(not CFG.db_path.exists(),
                       reason="no index built — run memsearch index first"),
]


def run(entry):
    f = entry.get("filters", {})
    return search(CFG, entry["query"], k=entry["k"], repo=f.get("repo"),
                  rtype=f.get("rtype"), since=f.get("since"))


@pytest.mark.parametrize("entry", [e for e in GOLDEN if e["kind"] == "must"],
                         ids=lambda e: e["query"][:40])
def test_must_queries_hit_expected_source(entry):
    paths = [r["file_path"] for r in run(entry)]
    assert any(entry["expect_path_contains"] in p for p in paths), (
        f"expected a path containing {entry['expect_path_contains']!r} "
        f"in top-{entry['k']}, got: {paths}")


@pytest.mark.parametrize("entry",
                         [e for e in GOLDEN if e["kind"] == "negative"],
                         ids=lambda e: e["query"][:40])
def test_negative_queries_reported_not_enforced(entry):
    paths = [r["file_path"] for r in run(entry)][:3]
    if any(entry["expect_path_contains"] in p for p in paths):
        warnings.warn(
            f"negative miss: off-topic {entry['query']!r} surfaced "
            f"{entry['expect_path_contains']!r} in top-3: {paths}")


@pytest.mark.parametrize("entry", [e for e in GOLDEN if e["kind"] == "stretch"],
                         ids=lambda e: e["query"][:40])
def test_stretch_queries_reported_not_enforced(entry):
    paths = [r["file_path"] for r in run(entry)]
    if not any(entry["expect_path_contains"] in p for p in paths):
        warnings.warn(f"stretch miss: {entry['query']!r} -> {paths}")
