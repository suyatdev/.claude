"""Index health: counts, staleness, model/dim consistency, and the ADR-0002
revisit triggers (chunks > 500k or p95 > 500 ms -> reconsider Qdrant)."""
from __future__ import annotations

import json

from memsearch import db as dbmod
from memsearch.config import Config

REVISIT_CHUNKS = 500_000
REVISIT_P95_MS = 500.0


def _run_recency(cfg: Config) -> str:
    """Run recency lives in status.json, not the DB — `last_indexed` answers a
    different question (how current the *content* is) and a run that finds
    nothing new never advances it. Unknown is reported as unknown."""
    try:
        st = json.loads((cfg.db_path.parent / "status.json").read_text())
        last_run = st["last_run"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError):
        return "last run: unknown"
    errors = st.get("last_run_errors")
    tally = f"{errors} errors" if isinstance(errors, int) else "errors unknown"
    return f"last run: {last_run} ({tally})"


def status_report(cfg: Config) -> str:
    if not cfg.db_path.exists():
        return "no index yet — run `memsearch index` to build it"
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    s = dbmod.stats(conn)
    p95 = dbmod.p95_latency(conn)
    mismatch = dbmod.model_mismatch(conn, cfg.embed_model, cfg.embed_dim)
    conn.close()

    lines = [
        f"chunks: {s['chunks']}",
        "by source_type: " + ", ".join(
            f"{k}: {v}" for k, v in sorted(s["by_source_type"].items())),
        "by repo: " + ", ".join(
            f"{k}: {v}" for k, v in sorted(s["by_repo"].items())),
        f"sources: {s['sources']}  content indexed through: "
        f"{s['last_indexed']}  {_run_recency(cfg)}",
        f"db size: {cfg.db_path.stat().st_size / 1_048_576:.1f} MB",
        f"embed model: {s['meta'].get('embed_model')} "
        f"({s['meta'].get('embed_dim')}-dim)",
        f"p95 query latency: {p95:.0f} ms" if p95 is not None
        else "p95 query latency: n/a (no queries logged)",
    ]
    if mismatch:
        lines.append(f"MISMATCH: {mismatch}")
    if s["chunks"] > REVISIT_CHUNKS or (p95 or 0) > REVISIT_P95_MS:
        lines.append(
            "REVISIT: store revisit trigger hit — reconsider Qdrant "
            "(see docs/decisions/0002-sqlite-over-qdrant.md)")
    return "\n".join(lines)
