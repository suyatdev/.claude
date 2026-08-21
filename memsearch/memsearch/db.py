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

from memsearch.config import SOURCE_TYPES  # noqa: F401  (re-exported: the
# vocabulary lives with the validation that checks it; db.py stays its
# historical import site)

SCHEMA_VERSION = "1"
USER_VERSION = 1      # PRAGMA user_version. 0 = pre-ADR-0030: chunks.weight
BACKUP_SUFFIX = ".bak"
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
    # Decided before the CREATE below: a database that already has chunks is
    # pre-existing, and only migrate() may move its version.
    is_fresh = conn.execute(
        "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='chunks'"
    ).fetchone()[0] == 0
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
            "session_id TEXT, content_hash TEXT NOT NULL)")
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
        if is_fresh:
            # PRAGMA takes no bound parameter; USER_VERSION is a module
            # constant, never user input — the same reasoning as the inlined
            # KNN LIMIT at search.py:44-45.
            conn.execute(f"PRAGMA user_version = {USER_VERSION}")


def model_mismatch(conn: sqlite3.Connection, embed_model: str,
                   embed_dim: int) -> str | None:
    meta = dict(conn.execute("SELECT key, value FROM meta").fetchall())
    stored = (meta.get("embed_model"), meta.get("embed_dim"))
    if stored == (embed_model, str(embed_dim)):
        return None
    return (f"DB was built with {stored[0]}/{stored[1]}-dim but config says "
            f"{embed_model}/{embed_dim}-dim — run `memsearch index --full` to rebuild")


def schema_version(conn: sqlite3.Connection) -> int:
    return conn.execute("PRAGMA user_version").fetchone()[0]


def migration_required(conn: sqlite3.Connection) -> str | None:
    """A ready-to-print message, or None. Read paths call this and refuse;
    they never migrate — a plain query must not become a schema writer, and
    must not queue behind a multi-hour backfill (ADR 0030)."""
    found = schema_version(conn)
    if found >= USER_VERSION:
        return None
    return (f"index database is at schema version {found}, this build needs "
            f"{USER_VERSION} — run `memsearch index` to migrate it")


def _backup_path(db_path: Path, from_version: int) -> Path:
    return db_path.parent / f"{db_path.name}.pre-v{from_version}{BACKUP_SUFFIX}"


def _take_backup(conn: sqlite3.Connection, db_path: Path,
                 from_version: int) -> Path:
    """Rollback is a file copy, taken before the drop: the database is one
    file, so restoring it is a cp — seconds, against the multi-hour
    `index --full` (ADR 0030). Copies from earlier migrations are removed
    here, so one stale copy never outlives the schema it belonged to."""
    target = _backup_path(db_path, from_version)
    for old in db_path.parent.glob(f"{db_path.name}.pre-v*{BACKUP_SUFFIX}"):
        if old != target:
            old.unlink()
    target.unlink(missing_ok=True)
    dest = sqlite3.connect(target)
    try:
        with dest:
            conn.backup(dest)      # page-level copy: consistent under a hot DB
    finally:
        dest.close()
    return target


def _drop_weight_column(conn: sqlite3.Connection) -> None:
    """Factored out so a test can make it fail. Guarded because a database may
    reach version 0 without the column (a fresh DB from a build between the
    column's removal and the version stamp)."""
    cols = [r[1] for r in conn.execute("PRAGMA table_info(chunks)")]
    if "weight" in cols:
        conn.execute("ALTER TABLE chunks DROP COLUMN weight")


def migrate(db_path: Path, embed_model: str, embed_dim: int,
            progress=print) -> dict | None:
    """One-way, versioned, and run only from a write command. Returns None when
    there is nothing to do — a missing database, or one already current."""
    if not db_path.exists():
        return None
    conn = connect(db_path, embed_model, embed_dim)
    try:
        found = schema_version(conn)
        if found >= USER_VERSION:
            return None
        backup = _take_backup(conn, db_path, found)
        try:
            # An explicit BEGIN, not `with conn:`: sqlite3 opens a transaction
            # implicitly only for DML, so under the connection's default
            # transaction control the DDL and the version stamp would each
            # autocommit and a failure between them would leave the column
            # dropped at version 0 — the half-migrated state this must never
            # produce.
            conn.execute("BEGIN IMMEDIATE")
            _drop_weight_column(conn)
            conn.execute(f"PRAGMA user_version = {USER_VERSION}")
            conn.commit()
        except Exception as e:
            # Fail closed: the transaction rolled back, so user_version and the
            # column are both as they were. Name the copy already on disk.
            conn.rollback()
            raise SystemExit(
                f"memsearch: schema migration {found} -> {USER_VERSION} failed "
                f"({e}) — the database is unchanged; a pre-migration copy is at "
                f"{backup}") from None
        progress(f"migrated schema {found} -> {USER_VERSION}; "
                 f"pre-migration copy at {backup}")
        return {"from_version": found, "to_version": USER_VERSION,
                "backup": str(backup)}
    finally:
        conn.close()


def now_iso() -> str:
    """The one timestamp format the index publishes. `timespec="seconds"` is
    required, not cosmetic: a bare isoformat() emits microseconds, and
    status.json's run stamps must match `last_indexed`'s shape exactly."""
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
                         "WHERE id=?", (content_hash, now_iso(), kind, sid))
        else:
            sid = conn.execute(
                "INSERT INTO sources(path, kind, content_hash, indexed_at) "
                "VALUES(?,?,?,?)", (path, kind, content_hash, now_iso())).lastrowid
        for chunk, emb in zip(chunks, embeddings):
            cid = conn.execute(
                "INSERT INTO chunks(source_id, content, repo_id, repo_name,"
                "source_type, recall_type, session_date, file_path, line_start,"
                "line_end, session_id, content_hash) "
                "VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                (sid, chunk.content, chunk.repo_id, chunk.repo_name,
                 chunk.source_type, chunk.recall_type, chunk.session_date,
                 chunk.file_path, chunk.line_start, chunk.line_end,
                 chunk.session_id,
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
        conn.execute("INSERT INTO query_log VALUES(?,?)", (now_iso(), ms))


def p95_latency(conn: sqlite3.Connection) -> float | None:
    rows = [r[0] for r in conn.execute(
        "SELECT ms FROM (SELECT ts, ms FROM query_log ORDER BY ts DESC LIMIT ?) "
        "ORDER BY ms", (LATENCY_WINDOW,)).fetchall()]
    if not rows:
        return None
    return rows[int(0.95 * (len(rows) - 1))]
