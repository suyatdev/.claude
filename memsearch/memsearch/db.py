"""SQLite storage: chunks + sqlite-vec vectors (cosine) + FTS5 mirror + source
hashes. Only db.py and search.py know SQLite exists — the spec's swap-store
isolation boundary. All writes for one source happen in one transaction so an
interrupted backfill resumes cleanly by hash-diff."""
from __future__ import annotations

import hashlib
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import sqlite_vec

SCHEMA_VERSION = "1"
SOURCE_TYPES = ("transcript_digest", "curated_doc", "repo_doc")
RECALL_TYPES = ("decision", "episodic", "doc")
LATENCY_WINDOW = 100  # p95 computed over the most recent N queries


@dataclass(frozen=True)
class Chunk:
    content: str
    repo_id: str
    repo_name: str
    source_type: str
    recall_type: str
    session_date: str
    file_path: str
    line_start: int
    line_end: int
    session_id: str | None
    weight: float


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def connect(db_path: Path, embed_model: str, embed_dim: int) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    conn.execute("PRAGMA foreign_keys=ON")
    _init_schema(conn, embed_model, embed_dim)
    return conn


def _init_schema(conn: sqlite3.Connection, embed_model: str, embed_dim: int) -> None:
    with conn:
        conn.execute("CREATE TABLE IF NOT EXISTS meta("
                     "key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        conn.execute(
            "CREATE TABLE IF NOT EXISTS sources("
            "id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, kind TEXT NOT NULL,"
            "content_hash TEXT NOT NULL, indexed_at TEXT NOT NULL)")
        conn.execute(
            "CREATE TABLE IF NOT EXISTS chunks("
            "id INTEGER PRIMARY KEY,"
            "source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,"
            "content TEXT NOT NULL, repo_id TEXT NOT NULL, repo_name TEXT NOT NULL,"
            "source_type TEXT NOT NULL, recall_type TEXT NOT NULL,"
            "session_date TEXT NOT NULL, file_path TEXT NOT NULL,"
            "line_start INTEGER NOT NULL, line_end INTEGER NOT NULL,"
            "session_id TEXT, weight REAL NOT NULL, content_hash TEXT NOT NULL)")
        conn.execute(
            f"CREATE VIRTUAL TABLE IF NOT EXISTS chunk_vec USING vec0("
            f"embedding float[{int(embed_dim)}] distance_metric=cosine)")
        conn.execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS chunk_fts USING fts5("
            "content, content='chunks', content_rowid='id')")
        conn.execute("CREATE TABLE IF NOT EXISTS query_log("
                     "ts TEXT NOT NULL, ms REAL NOT NULL)")
        conn.execute("INSERT OR IGNORE INTO meta VALUES('schema_version', ?)",
                     (SCHEMA_VERSION,))
        conn.execute("INSERT OR IGNORE INTO meta VALUES('embed_model', ?)",
                     (embed_model,))
        conn.execute("INSERT OR IGNORE INTO meta VALUES('embed_dim', ?)",
                     (str(embed_dim),))


def model_mismatch(conn: sqlite3.Connection, embed_model: str,
                   embed_dim: int) -> str | None:
    meta = dict(conn.execute("SELECT key, value FROM meta").fetchall())
    stored = (meta.get("embed_model"), meta.get("embed_dim"))
    if stored == (embed_model, str(embed_dim)):
        return None
    return (f"DB was built with {stored[0]}/{stored[1]}-dim but config says "
            f"{embed_model}/{embed_dim}-dim — run `memsearch index --full` to rebuild")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def replace_source(conn: sqlite3.Connection, path: str, kind: str,
                   content_hash: str, chunks: list[Chunk],
                   embeddings: list[list[float]]) -> int:
    if len(chunks) != len(embeddings):
        raise ValueError(f"{len(chunks)} chunks but {len(embeddings)} embeddings")
    with conn:
        row = conn.execute("SELECT id FROM sources WHERE path=?", (path,)).fetchone()
        if row:
            sid = row[0]
            for (cid, content) in conn.execute(
                    "SELECT id, content FROM chunks WHERE source_id=?", (sid,)):
                conn.execute("DELETE FROM chunk_vec WHERE rowid=?", (cid,))
                conn.execute("INSERT INTO chunk_fts(chunk_fts, rowid, content) "
                             "VALUES('delete', ?, ?)", (cid, content))
            conn.execute("DELETE FROM chunks WHERE source_id=?", (sid,))
            conn.execute("UPDATE sources SET content_hash=?, indexed_at=?, kind=? "
                         "WHERE id=?", (content_hash, _now(), kind, sid))
        else:
            sid = conn.execute(
                "INSERT INTO sources(path, kind, content_hash, indexed_at) "
                "VALUES(?,?,?,?)", (path, kind, content_hash, _now())).lastrowid
        for chunk, emb in zip(chunks, embeddings):
            cid = conn.execute(
                "INSERT INTO chunks(source_id, content, repo_id, repo_name,"
                "source_type, recall_type, session_date, file_path, line_start,"
                "line_end, session_id, weight, content_hash) "
                "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (sid, chunk.content, chunk.repo_id, chunk.repo_name,
                 chunk.source_type, chunk.recall_type, chunk.session_date,
                 chunk.file_path, chunk.line_start, chunk.line_end,
                 chunk.session_id, chunk.weight,
                 sha256_text(chunk.content))).lastrowid
            conn.execute("INSERT INTO chunk_vec(rowid, embedding) VALUES(?,?)",
                         (cid, sqlite_vec.serialize_float32(emb)))
            conn.execute("INSERT INTO chunk_fts(rowid, content) VALUES(?,?)",
                         (cid, chunk.content))
    return len(chunks)


def source_hash(conn: sqlite3.Connection, path: str) -> str | None:
    row = conn.execute("SELECT content_hash FROM sources WHERE path=?",
                       (path,)).fetchone()
    return row[0] if row else None


def stats(conn: sqlite3.Connection) -> dict:
    by_type = dict(conn.execute(
        "SELECT source_type, count(*) FROM chunks GROUP BY source_type"))
    by_repo = dict(conn.execute(
        "SELECT repo_name, count(*) FROM chunks GROUP BY repo_name"))
    last = conn.execute("SELECT max(indexed_at) FROM sources").fetchone()[0]
    return {
        "chunks": conn.execute("SELECT count(*) FROM chunks").fetchone()[0],
        "sources": conn.execute("SELECT count(*) FROM sources").fetchone()[0],
        "by_source_type": by_type,
        "by_repo": by_repo,
        "last_indexed": last,
        "meta": dict(conn.execute("SELECT key, value FROM meta").fetchall()),
    }


def log_query(conn: sqlite3.Connection, ms: float) -> None:
    with conn:
        conn.execute("INSERT INTO query_log VALUES(?,?)", (_now(), ms))


def p95_latency(conn: sqlite3.Connection) -> float | None:
    rows = [r[0] for r in conn.execute(
        "SELECT ms FROM (SELECT ts, ms FROM query_log ORDER BY ts DESC LIMIT ?) "
        "ORDER BY ms", (LATENCY_WINDOW,)).fetchall()]
    if not rows:
        return None
    return rows[int(0.95 * (len(rows) - 1))]
