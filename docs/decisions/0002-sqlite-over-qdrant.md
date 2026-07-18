# ADR 0002 — SQLite (sqlite-vec + FTS5) over Qdrant for the memory RAG index

**Status:** Accepted (2026-07-17)

## Context
memsearch needs a local vector + keyword store for ~30–50k chunks (session
digests + durable docs) on a 64 GB Mac Studio whose idle headroom is a hard
requirement. Candidates: sqlite-vec + FTS5 in one file, or a Qdrant
container. Full analysis: spec
`docs/superpowers/specs/2026-07-17-memory-rag-index-design.md`.

## Decision
One SQLite file (`~/.claude/memory-index/memory.db`, gitignored, regenerable)
using sqlite-vec for exact brute-force cosine KNN and FTS5 for BM25, fused
with RRF. No service, no port, no daemon.

## Options weighed
- **sqlite-vec + FTS5 (chosen):** exact search = 100% recall at this size;
  tens of ms on M4 Max; zero idle RAM; zero ops surface.
- **Qdrant:** HNSW ~98–99% recall (worse accuracy here), always-resident
  graph + container + port — a standing RAM/ops tax for a latency win that is
  imperceptible at a handful of queries per session.

## Consequences
- Retrieval accuracy is bounded by embeddings + chunking, not the store.
- Storage sits behind `db.py`/`search.py`; swapping stores later is contained
  (export chunks, re-load vectors — no re-embedding).
- **Revisit triggers (checked by `memsearch status`):** index > 500,000
  chunks, or p95 query latency > 500 ms. Either flips a REVISIT flag naming
  this ADR.
