"""Indexing pipeline: docs first (fast, immediately useful), then transcripts
newest-first. Hash-diff via the sources table makes every run incremental and
interrupt-safe: each source commits atomically in replace_source, so a killed
backfill resumes where it left off."""
from __future__ import annotations

import glob as globmod
import json
from functools import partial
from pathlib import Path

from memsearch import db as dbmod
from memsearch import digest as digestmod
from memsearch import ollama
from memsearch.chunk import chunk_digest, chunk_doc
from memsearch.config import Config, is_excluded
from memsearch.extract import extract_session

CLAUDE_REPO = (".claude", ".claude")  # curated docs belong to the config repo


def repo_for_cwd(cwd: str, cfg: Config) -> tuple[str, str]:
    if not cwd:
        return ("unknown", "unknown")
    best = None
    for r in cfg.repo_roots:
        root = str(r.root)
        if (cwd == root or cwd.startswith(root + "/")) and \
                (best is None or len(root) > len(str(best.root))):
            best = r
    if best:
        return (best.id, best.name)
    base = Path(cwd).name
    return (base.lower(), base)


def _iter_transcripts(cfg: Config) -> list[Path]:
    paths = [Path(p) for p in globmod.glob(cfg.transcripts_glob)]
    paths = [p for p in paths if not is_excluded(p, cfg)]
    return sorted(paths, key=lambda p: p.stat().st_mtime, reverse=True)


def _iter_docs(cfg: Config) -> list[tuple[Path, str, str, str]]:
    """Yields (path, repo_id, repo_name, source_type)."""
    out: list[tuple[Path, str, str, str]] = []
    for entry in cfg.curated_docs:
        files = [entry] if entry.is_file() else sorted(entry.rglob("*.md"))
        out.extend((f, *CLAUDE_REPO, "curated_doc")
                   for f in files if not is_excluded(f, cfg))
    for r in cfg.repo_roots:
        out.extend((f, r.id, r.name, "repo_doc")
                   for f in sorted(r.root.rglob("*.md"))
                   if not is_excluded(f, cfg))
    return out


def _write_status(cfg: Config, conn) -> None:
    s = dbmod.stats(conn)
    status = {
        "chunks": s["chunks"],
        "sources": s["sources"],
        "last_indexed": s["last_indexed"],
        "db_bytes": cfg.db_path.stat().st_size if cfg.db_path.exists() else 0,
        "embed_model": s["meta"].get("embed_model"),
        "embed_dim": int(s["meta"].get("embed_dim", 0)),
    }
    (cfg.db_path.parent / "status.json").write_text(json.dumps(status, indent=1))


def run_index(cfg: Config, full: bool = False, limit: int | None = None,
              embedder=None, digester=None, progress=print) -> dict:
    if full and cfg.db_path.exists():
        cfg.db_path.unlink()  # model/dim may have changed: rebuild from scratch
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    mismatch = dbmod.model_mismatch(conn, cfg.embed_model, cfg.embed_dim)
    if mismatch:
        raise SystemExit(f"memsearch: {mismatch}")
    embedder = embedder or partial(
        ollama.embed, model=cfg.embed_model, base_url=cfg.ollama_url)
    digester = digester or partial(digestmod.digest_session, cfg=cfg)
    report = {"processed": 0, "skipped": 0, "chunks_added": 0, "errors": []}

    for path, repo_id, repo_name, source_type in _iter_docs(cfg):
        _index_one(conn, cfg, report, path, progress, kind="doc",
                   make_chunks=lambda p=path, rid=repo_id, rname=repo_name,
                   st=source_type: chunk_doc(
                       p, p.read_text(errors="replace"), rid, rname, st,
                       float(cfg.weights[st]),
                       _mtime_date(p)),
                   embedder=embedder)

    transcripts = _iter_transcripts(cfg)
    if limit is not None:
        transcripts = transcripts[:limit]
    for path in transcripts:
        _index_one(conn, cfg, report, path, progress, kind="transcript",
                   make_chunks=partial(_transcript_chunks, path, cfg, digester),
                   embedder=embedder)

    _write_status(cfg, conn)
    conn.close()
    return report


def _mtime_date(path: Path) -> str:
    from datetime import datetime, timezone
    return datetime.fromtimestamp(
        path.stat().st_mtime, timezone.utc).strftime("%Y-%m-%d")


def _transcript_chunks(path: Path, cfg: Config, digester) -> list:
    extract = extract_session(path)
    if extract is None:
        return []
    repo_id, repo_name = repo_for_cwd(extract.cwd, cfg)
    digest_md = digester(extract)
    return chunk_digest(digest_md, extract, repo_id, repo_name,
                        float(cfg.weights["transcript_digest"]), str(path))


def _index_one(conn, cfg: Config, report: dict, path: Path, progress,
               kind: str, make_chunks, embedder) -> None:
    try:
        content_hash = dbmod.sha256_file(path)
        if dbmod.source_hash(conn, str(path)) == content_hash:
            report["skipped"] += 1
            return
        chunks = make_chunks()
        embeddings = embedder([c.content for c in chunks]) if chunks else []
        n = dbmod.replace_source(conn, str(path), kind, content_hash,
                                 chunks, embeddings)
        report["processed"] += 1
        report["chunks_added"] += n
        progress(f"indexed {path} ({n} chunks)")
    except Exception as e:  # record and continue — one bad source never
        report["errors"].append(f"{path}: {e}")  # kills a multi-hour backfill
        progress(f"ERROR {path}: {e}")
