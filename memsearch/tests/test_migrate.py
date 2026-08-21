"""Schema migration 0 -> 1: the stored chunks.weight column is dropped.

Version 0 databases are built here with the literal pre-0030 CREATE TABLE
rather than by importing an old build, so the fixture cannot drift into
agreeing with the code it grades."""
import sqlite3
from pathlib import Path

import pytest

from memsearch import db as dbmod
from memsearch.config import load_config
from memsearch.index import run_index
from memsearch.search import search
from tests.conftest import DIM, vec
from tests.test_config import write_cfg

V0_CHUNKS = (
    "CREATE TABLE chunks("
    "id INTEGER PRIMARY KEY,"
    "source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,"
    "content TEXT NOT NULL, repo_id TEXT NOT NULL, repo_name TEXT NOT NULL,"
    "source_type TEXT NOT NULL, recall_type TEXT NOT NULL,"
    "session_date TEXT NOT NULL, file_path TEXT NOT NULL,"
    "line_start INTEGER NOT NULL, line_end INTEGER NOT NULL,"
    "session_id TEXT, weight REAL NOT NULL, content_hash TEXT NOT NULL)")


def make_cfg(tmp_path, **over):
    """An empty corpus on purpose: run_index here exercises the migration, not
    the walk, so nothing must be reachable to index."""
    p = write_cfg(tmp_path, **{
        "embed_model": "test-embed", "embed_dim": DIM,
        "db_path": str(tmp_path / "mi" / "memory.db"),
        "transcripts_glob": str(tmp_path / "none" / "*.jsonl"),
        "curated_docs": [], "repo_roots": [], **over})
    return load_config(p)


def build_v0(cfg) -> None:
    """A database in the pre-0030 shape: user_version 0, weight column present,
    one curated_doc chunk with a STALE stored weight of 1.0."""
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    conn.execute("DROP TABLE chunks")
    conn.execute(V0_CHUNKS)
    conn.execute("PRAGMA user_version = 0")
    with conn:
        sid = conn.execute(
            "INSERT INTO sources(path, kind, content_hash, indexed_at) "
            "VALUES('/x/doc.md','doc','h','2026-08-20T00:00:00+00:00')").lastrowid
        conn.execute(
            "INSERT INTO chunks(source_id, content, repo_id, repo_name,"
            "source_type, recall_type, session_date, file_path, line_start,"
            "line_end, session_id, weight, content_hash) "
            "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (sid, "a stored decision", ".claude", ".claude", "curated_doc",
             "decision", "2026-08-20", "/x/doc.md", 1, 9, None, 1.0, "ch"))
    conn.close()


def columns(cfg) -> list[str]:
    conn = sqlite3.connect(cfg.db_path)
    cols = [r[1] for r in conn.execute("PRAGMA table_info(chunks)")]
    conn.close()
    return cols


def version(cfg) -> int:
    conn = sqlite3.connect(cfg.db_path)
    v = conn.execute("PRAGMA user_version").fetchone()[0]
    conn.close()
    return v


def test_fresh_database_is_created_at_the_current_version(tmp_path):
    cfg = make_cfg(tmp_path)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    conn.close()
    assert version(cfg) == dbmod.USER_VERSION
    assert "weight" not in columns(cfg)


def test_migrate_drops_the_column_and_keeps_the_rows(tmp_path):
    cfg = make_cfg(tmp_path)
    build_v0(cfg)
    result = dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                           progress=lambda _: None)
    assert result["from_version"] == 0 and result["to_version"] == dbmod.USER_VERSION
    assert version(cfg) == dbmod.USER_VERSION
    assert "weight" not in columns(cfg)
    conn = sqlite3.connect(cfg.db_path)
    assert conn.execute("SELECT content FROM chunks").fetchall() == \
        [("a stored decision",)]
    conn.close()


def test_migrate_takes_a_restorable_copy_first(tmp_path):
    cfg = make_cfg(tmp_path)
    build_v0(cfg)
    result = dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                           progress=lambda _: None)
    backup = Path(result["backup"])
    assert backup.exists()
    # restoring is a cp: the copy still has the old shape and the old rows
    conn = sqlite3.connect(backup)
    cols = [r[1] for r in conn.execute("PRAGMA table_info(chunks)")]
    rows = conn.execute("SELECT weight FROM chunks").fetchall()
    conn.close()
    assert "weight" in cols and rows == [(1.0,)]


def test_migrate_is_idempotent(tmp_path):
    cfg = make_cfg(tmp_path)
    build_v0(cfg)
    dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                  progress=lambda _: None)
    assert dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                         progress=lambda _: None) is None


def test_migrate_on_a_missing_database_is_a_no_op(tmp_path):
    cfg = make_cfg(tmp_path)
    assert dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                         progress=lambda _: None) is None


def test_a_failed_drop_leaves_the_database_untouched(tmp_path, monkeypatch):
    """Fail closed: version unchanged, column still there, and the message
    names the copy already taken (ADR 0030)."""
    cfg = make_cfg(tmp_path)
    build_v0(cfg)

    def boom(conn):
        raise sqlite3.OperationalError("database is locked")

    monkeypatch.setattr(dbmod, "_drop_weight_column", boom)
    with pytest.raises(SystemExit) as e:
        dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                      progress=lambda _: None)
    assert "database is locked" in str(e.value) and ".bak" in str(e.value)
    assert version(cfg) == 0
    assert "weight" in columns(cfg)


def test_an_earlier_migration_copy_is_removed(tmp_path):
    """The copy is deleted on the NEXT successful migration, not kept forever."""
    cfg = make_cfg(tmp_path)
    build_v0(cfg)
    stale = cfg.db_path.parent / (cfg.db_path.name + ".pre-v7.bak")
    stale.write_bytes(b"an older migration's copy")
    dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                  progress=lambda _: None)
    assert not stale.exists()


def test_index_migrates_but_query_refuses(tmp_path):
    """A read must never write schema: query names `memsearch index` as the fix
    and does not fall back to the stored column (ADR 0030)."""
    cfg = make_cfg(tmp_path)
    build_v0(cfg)
    with pytest.raises(SystemExit, match="memsearch index"):
        search(cfg, "a stored decision", k=1,
               embedder=lambda texts: [vec(1.0) for _ in texts])
    assert version(cfg) == 0            # the failed query migrated nothing

    report = run_index(cfg, embedder=lambda texts: [vec(1.0) for _ in texts],
                       digester=lambda extract: "## Summary\nx\n",
                       progress=lambda _: None)
    assert report["migration"]["to_version"] == dbmod.USER_VERSION
    assert version(cfg) == dbmod.USER_VERSION


def test_a_failure_after_the_drop_rolls_the_drop_back(tmp_path, monkeypatch):
    """The half-migrated state this migration must never produce: the column
    gone while user_version still reads 0. Python's sqlite3 opens a
    transaction implicitly only for DML, so the DDL and the version stamp are
    atomic only if migrate() begins one itself."""
    cfg = make_cfg(tmp_path)
    build_v0(cfg)
    real_drop = dbmod._drop_weight_column

    def drop_then_fail(conn):
        real_drop(conn)
        raise sqlite3.OperationalError("disk I/O error")

    monkeypatch.setattr(dbmod, "_drop_weight_column", drop_then_fail)
    with pytest.raises(SystemExit, match="disk I/O error"):
        dbmod.migrate(cfg.db_path, cfg.embed_model, cfg.embed_dim,
                      progress=lambda _: None)
    assert version(cfg) == 0
    assert "weight" in columns(cfg)
