"""ADR 0030's weight sweep, run as a script.

Deliberately NOT named test_*: pytest must never collect it. It hits a real
index and the live embedder, and it is a measurement, not an assertion.

    cd memsearch && uv run --project . python -m tests.sweep_judge_weight
    cd memsearch && uv run --project . python -m tests.sweep_judge_weight --config PATH

`--config` exists because the sweep must be able to run against a *copy* of the
index. The primary checkout runs older code that still SELECTs `chunks.weight`,
so migrating the live database would break the user's `memsearch query`, the
SessionStart hook and the launchd indexer until this branch merges; the copy is
migrated and reclassified instead, and the live file is never opened for write.

Per-target hit counts and top-hit identity are recorded for EVERY row, not a
pass/fail per row: the remedy section's own table carried a verdict-level
"anything regress?" column that would have printed "no" through a
PASS(4) -> PASS(3) erosion.

One deviation from ADR 0030 is recorded in `index_state`: its same-index-state
proof keys on a corpus fingerprint rather than on the file's mtime, because
mtime is moved by the sweep's own queries and so can never hold. R9's
acceptance bar and the three-clause adoption rule are untouched.
"""
from __future__ import annotations

import argparse
import dataclasses
import hashlib
from pathlib import Path

from memsearch import db as dbmod
from memsearch.config import load_config
from memsearch.search import search
from tests.test_measurement_queries import QUERIES, belongs

# Baseline first, then descending. Written out rather than computed by a 0.1
# step so no float accumulation can shift a row's label.
WEIGHTS = (1.5, 1.4, 1.3, 1.2, 1.1, 1.0)
BASELINE = WEIGHTS[0]


def index_state(cfg) -> dict:
    """The corpus fingerprint the sweep pins, plus the file facts that explain
    it. A scheduled launchd indexer writes the index, so "measured at one index
    state" has to be proved, not hoped (ADR 0030).

    ADR 0030 specified that proof as `chunk count + file mtime`, and that pair
    is UNSATISFIABLE by construction: `search()` ends with `log_query()`
    (`search.py:103` -> `db.py:271-273`), which INSERTs a latency row, so every
    query the sweep itself issues moves the file's mtime. Measured directly —
    one query, zero corpus change, `query_log` +1, mtime moved — so the clause
    fails on every possible run and reports nothing about the corpus.

    The discard therefore keys on `fingerprint`: a digest over every chunk's
    identity, source, type, location and content hash, plus every source row.
    That is strictly more sensitive to the hazard the clause exists to catch —
    an indexer adding, dropping, re-chunking or re-typing rows mid-sweep — and
    it is blind only to the sweep's own instrumentation. `mtime` and
    `query_log` are still recorded, so a moved mtime is explained by the query
    count rather than quietly dropped."""
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    n = conn.execute("SELECT count(*) FROM chunks").fetchone()[0]
    h = hashlib.sha256()
    for row in conn.execute(
            "SELECT id, source_id, source_type, recall_type, file_path, "
            "line_start, line_end, content_hash FROM chunks ORDER BY id"):
        h.update(repr(row).encode())
    for row in conn.execute(
            "SELECT id, path, kind, content_hash FROM sources ORDER BY id"):
        h.update(repr(row).encode())
    vecs = conn.execute("SELECT count(*) FROM chunk_vec").fetchone()[0]
    h.update(f"vec={vecs}".encode())
    queries = conn.execute("SELECT count(*) FROM query_log").fetchone()[0]
    conn.close()
    return {"chunks": n, "vectors": vecs, "fingerprint": h.hexdigest(),
            "mtime": cfg.db_path.stat().st_mtime, "query_log": queries}


def print_state(label: str, s: dict) -> None:
    print(f"index state {label}: chunks={s['chunks']} vectors={s['vectors']} "
          f"fingerprint={s['fingerprint']} mtime={s['mtime']} "
          f"query_log={s['query_log']}")


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


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--config", type=Path, default=None,
                    help="path to config.json (default: packaged)")
    args = ap.parse_args(argv)

    cfg = load_config(args.config)
    print(f"index: {cfg.db_path}")
    before = index_state(cfg)
    print_state("before", before)

    rows = {}
    for weight in WEIGHTS:
        rows[weight] = measure(cfg, weight)
        print_row(weight, rows[weight])

    after = index_state(cfg)
    print()
    print_state("after ", after)
    moved = [k for k in ("chunks", "vectors", "fingerprint")
             if before[k] != after[k]]
    print(f"    corpus identical: {not moved}"
          f"{'' if not moved else '  moved: ' + ', '.join(moved)}")
    print(f"    mtime moved: {before['mtime'] != after['mtime']}, accounted "
          f"for by query_log +{after['query_log'] - before['query_log']} "
          f"(this sweep issued {len(WEIGHTS) * len(QUERIES)} searches, each of "
          f"which INSERTs one latency row — see index_state)")
    if moved:
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
