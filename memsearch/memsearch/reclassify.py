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
                # One bad source never kills the run — `_index_one`'s
                # record-and-continue contract. Recorded, and the exit code
                # carries it out.
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
