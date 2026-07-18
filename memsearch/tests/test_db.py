import sqlite_vec

from memsearch import db as dbmod
from tests.conftest import DIM, make_chunk, vec


def test_connect_creates_schema_and_meta(conn):
    tables = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type IN ('table','virtual table') "
        "OR type='table'").fetchall()}
    assert {"meta", "sources", "chunks", "query_log"} <= tables
    meta = dict(conn.execute("SELECT key, value FROM meta").fetchall())
    assert meta["embed_model"] == "test-embed"
    assert meta["embed_dim"] == str(DIM)
    assert dbmod.model_mismatch(conn, "test-embed", DIM) is None


def test_model_mismatch_detected(conn):
    msg = dbmod.model_mismatch(conn, "qwen3-embedding:0.6b", 1024)
    assert msg is not None and "test-embed" in msg


def test_replace_source_inserts_chunk_vec_fts(conn):
    n = dbmod.replace_source(
        conn, "/x/doc.md", "doc", "hash1", [make_chunk()], [vec(1.0)])
    assert n == 1
    assert conn.execute("SELECT count(*) FROM chunks").fetchone()[0] == 1
    assert conn.execute("SELECT count(*) FROM chunk_vec").fetchone()[0] == 1
    hits = conn.execute(
        "SELECT rowid FROM chunk_fts WHERE chunk_fts MATCH 'Qdrant'").fetchall()
    assert len(hits) == 1
    assert dbmod.source_hash(conn, "/x/doc.md") == "hash1"


def test_replace_source_is_idempotent_replace_not_append(conn):
    dbmod.replace_source(conn, "/x/doc.md", "doc", "h1", [make_chunk()], [vec(1.0)])
    dbmod.replace_source(
        conn, "/x/doc.md", "doc", "h2",
        [make_chunk(content="Updated decision text about Qdrant.")], [vec(0.5)])
    assert conn.execute("SELECT count(*) FROM chunks").fetchone()[0] == 1
    assert conn.execute("SELECT count(*) FROM chunk_vec").fetchone()[0] == 1
    rows = conn.execute(
        "SELECT rowid FROM chunk_fts WHERE chunk_fts MATCH 'Updated'").fetchall()
    assert len(rows) == 1
    assert dbmod.source_hash(conn, "/x/doc.md") == "h2"


def test_vector_knn_returns_nearest(conn):
    dbmod.replace_source(conn, "/a.md", "doc", "ha",
                         [make_chunk(file_path="/a.md")], [vec(1.0, 0.0)])
    dbmod.replace_source(conn, "/b.md", "doc", "hb",
                         [make_chunk(file_path="/b.md")], [vec(0.0, 1.0)])
    q = sqlite_vec.serialize_float32(vec(0.9, 0.1))
    rows = conn.execute(
        "SELECT rowid FROM chunk_vec WHERE embedding MATCH ? "
        "ORDER BY distance LIMIT 1", (q,)).fetchall()
    path = conn.execute("SELECT file_path FROM chunks WHERE id=?",
                        (rows[0][0],)).fetchone()[0]
    assert path == "/a.md"


def test_hashes_and_stats_and_latency(conn, tmp_path):
    f = tmp_path / "f.txt"
    f.write_text("abc")
    assert dbmod.sha256_file(f) == dbmod.sha256_text("abc")
    dbmod.replace_source(conn, "/x.md", "doc", "h", [make_chunk()], [vec(1.0)])
    s = dbmod.stats(conn)
    assert s["chunks"] == 1 and s["sources"] == 1
    assert s["by_source_type"]["curated_doc"] == 1
    dbmod.log_query(conn, 12.5)
    assert dbmod.p95_latency(conn) == 12.5
