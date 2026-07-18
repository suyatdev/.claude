"""Hybrid retrieval: exact brute-force cosine KNN (sqlite-vec) fused with
BM25 keyword rank (FTS5) via Reciprocal Rank Fusion, then multiplied by
source weight (curated > repo doc > digest). Filters are applied after
fusion over a wide candidate pool (CANDIDATES per branch), which is exact
enough at this corpus size and keeps the SQL trivial."""
from __future__ import annotations

import re
import time
from functools import partial

import sqlite_vec

from memsearch import db as dbmod
from memsearch import ollama
from memsearch.config import Config

CANDIDATES = 200
RRF_K = 60
_TOKEN = re.compile(r"[A-Za-z0-9_./-]+")

_CHUNK_COLS = ("content", "repo_id", "repo_name", "source_type", "recall_type",
               "session_date", "file_path", "line_start", "line_end",
               "session_id", "weight")


def _fts_query(query: str) -> str:
    tokens = _TOKEN.findall(query)
    return " OR ".join(f'"{t}"' for t in tokens)


def search(cfg: Config, query: str, k: int = 6, repo: str | None = None,
           rtype: str | None = None, since: str | None = None,
           embedder=None) -> list[dict]:
    embedder = embedder or partial(
        ollama.embed, model=cfg.embed_model, base_url=cfg.ollama_url)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    t0 = time.perf_counter()

    qvec = embedder([query])[0]
    # LIMIT is inlined (module constant, not user input): some sqlite-vec
    # 0.1.x builds reject a bound parameter as the vec0 KNN limit.
    vec_ids = [r[0] for r in conn.execute(
        f"SELECT rowid FROM chunk_vec WHERE embedding MATCH ? "
        f"ORDER BY distance LIMIT {CANDIDATES}",
        (sqlite_vec.serialize_float32(qvec),)).fetchall()]

    fts = _fts_query(query)
    fts_ids: list[int] = []
    if fts:
        try:
            fts_ids = [r[0] for r in conn.execute(
                f"SELECT rowid FROM chunk_fts WHERE chunk_fts MATCH ? "
                f"ORDER BY rank LIMIT {CANDIDATES}", (fts,)).fetchall()]
        except Exception:  # malformed FTS syntax -> keyword branch contributes 0
            fts_ids = []

    rrf: dict[int, float] = {}
    for ids in (vec_ids, fts_ids):
        for rank, cid in enumerate(ids):
            rrf[cid] = rrf.get(cid, 0.0) + 1.0 / (RRF_K + rank + 1)

    results = []
    cols = ", ".join(_CHUNK_COLS)
    for cid, base_score in rrf.items():
        row = conn.execute(
            f"SELECT {cols} FROM chunks WHERE id=?", (cid,)).fetchone()
        if row is None:
            continue
        r = dict(zip(_CHUNK_COLS, row))
        if repo and repo not in (r["repo_id"], r["repo_name"]):
            continue
        if rtype and r["recall_type"] != rtype:
            continue
        if since and r["session_date"] < since:
            continue
        r["score"] = round(base_score * r.pop("weight"), 6)
        results.append(r)
    results.sort(key=lambda r: -r["score"])

    dbmod.log_query(conn, (time.perf_counter() - t0) * 1000)
    conn.close()
    return results[:k]


def format_results(results: list[dict]) -> str:
    if not results:
        return "no results"
    blocks = []
    for r in results:
        lines = f"{r['file_path']}:{r['line_start']}-{r['line_end']}"
        prov = (f"{r['repo_name']} · {r['source_type']} · {r['recall_type']} · "
                f"{r['session_date']} · {lines} · score={r['score']}")
        blocks.append(f"--- {prov}\n{r['content']}")
    return "\n\n".join(blocks)
