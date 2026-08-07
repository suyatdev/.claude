"""Indexing pipeline: docs first (fast, immediately useful), then transcripts
newest-first. Hash-diff via the sources table makes every run incremental and
interrupt-safe: each source commits atomically in replace_source, so a killed
backfill resumes where it left off."""
from __future__ import annotations

import glob as globmod
import json
import os
import sys
import tempfile
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


ARCHIVE_FILENAME = "CODING_MEMORY.md"


def _doc_source_type(path: Path, default: str) -> str:
    """Classify the session archive by filename, not by which bucket found it.

    The archive has three copies — the ~/.claude one reached via curated_docs
    and one inside each repo_root — and bucket-based typing would tier them
    differently (1.5 vs 1.2), ranking session narrative at or above the
    decision records it narrates. archive_doc (1.0) keeps all three
    retrievable without ever outranking a real decision record.
    """
    return "archive_doc" if path.name == ARCHIVE_FILENAME else default


def _iter_docs(cfg: Config) -> list[tuple[Path, str, str, str]]:
    """Yields (path, repo_id, repo_name, source_type)."""
    out: list[tuple[Path, str, str, str]] = []
    for entry in cfg.curated_docs:
        files = [entry] if entry.is_file() else sorted(entry.rglob("*.md"))
        out.extend((f, *CLAUDE_REPO, _doc_source_type(f, "curated_doc"))
                   for f in files if not is_excluded(f, cfg))
    for r in cfg.repo_roots:
        out.extend((f, r.id, r.name, _doc_source_type(f, "repo_doc"))
                   for f in sorted(r.root.rglob("*.md"))
                   if not is_excluded(f, cfg))
    return out


CARRIED_KEYS = ("chunks", "sources", "last_indexed", "db_bytes",
                "embed_model", "embed_dim")


def _status_path(cfg: Config) -> Path:
    return cfg.db_path.parent / "status.json"


def _read_prior_status(cfg: Config) -> dict:
    """Fallible by design, and never fatal: a missing, empty, truncated or
    unparseable status file must not abort a scheduled run. The alternative is
    this feature's own failure mode one field over — an unreadable status file
    killing every run while the nudge, silent on malformed input by contract,
    reports nothing at all. Reported on stderr so it lands in the run log."""
    try:
        prior = json.loads(_status_path(cfg).read_text())
    except (OSError, json.JSONDecodeError) as e:
        print(f"memsearch: no usable prior status.json ({e}) — "
              "stamping run_started alone", file=sys.stderr)
        return {}
    return prior if isinstance(prior, dict) else {}


def _write_status_file(cfg: Config, status: dict) -> None:
    """Atomic: render to a temp file alongside the target, then rename onto it.
    This spec twice expects the writing process to be hard-killed, and a kill
    mid-write is what produces the truncated file _read_prior_status absorbs."""
    path = _status_path(cfg)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".status-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(json.dumps(status, indent=1))
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def _write_status(cfg: Config, conn, *, phase: str, run_started: str,
                  errors: int = 0) -> None:
    """Written twice per run.

    `phase="start"` stamps run_started and carries the prior file's keys over
    verbatim. It must not recompute: --full unlinks the DB before connecting,
    so a recompute would stamp `chunks: 0`, and the nudge exits silently on an
    absent-or-zero chunk count — deleting the session line for the whole
    multi-hour rebuild, which is exactly the window the in-progress line covers.

    `phase="end"` recomputes all six from the DB, precisely as before."""
    if phase == "start":
        prior = _read_prior_status(cfg)
        status = {k: prior[k]
                  for k in (*CARRIED_KEYS, "last_run", "last_run_errors")
                  if k in prior}
        status["run_started"] = run_started
    else:
        s = dbmod.stats(conn)
        status = {
            "chunks": s["chunks"],
            "sources": s["sources"],
            "last_indexed": s["last_indexed"],
            "db_bytes": cfg.db_path.stat().st_size if cfg.db_path.exists() else 0,
            "embed_model": s["meta"].get("embed_model"),
            "embed_dim": int(s["meta"].get("embed_dim", 0)),
            "run_started": run_started,
            "last_run": dbmod.now_iso(),
            "last_run_errors": errors,
        }
    _write_status_file(cfg, status)


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
    # After the mismatch check on purpose: a config error that indexes nothing
    # must not leave a phantom in-progress marker for the nudge to decay into a
    # stuck run. A genuinely killed run does leave run_started > last_run.
    run_started = dbmod.now_iso()
    _write_status(cfg, conn, phase="start", run_started=run_started)

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

    _write_status(cfg, conn, phase="end", run_started=run_started,
                  errors=len(report["errors"]))
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
