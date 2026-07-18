import pytest

from memsearch import db as dbmod
from memsearch.config import load_config
from memsearch.search import format_results, search
from tests.conftest import DIM, make_chunk, vec
from tests.test_config import write_cfg


def make_cfg(tmp_path, **over):
    p = write_cfg(tmp_path, **{
        "embed_model": "test-embed", "embed_dim": DIM,
        "db_path": str(tmp_path / "memory-index" / "memory.db"), **over,
    })
    return load_config(p)


def seed(cfg):
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    rows = [
        # (path, chunk, vector) — vec axes are a fake semantic space
        ("/x/docs/decisions/0002-sqlite.md", make_chunk(
            content="We chose SQLite over Qdrant for zero idle RAM.",
            recall_type="decision", weight=1.5,
            file_path="/x/docs/decisions/0002-sqlite.md",
            session_date="2026-07-17"), vec(1.0, 0.0, 0.0)),
        ("/x/projects/p/s1.jsonl", make_chunk(
            content="[session s1] Bugs & Fixes\n- ERR_AUTH_401 fixed in auth.py",
            source_type="transcript_digest", recall_type="episodic", weight=1.0,
            file_path="/x/projects/p/s1.jsonl", session_id="s1",
            repo_id="myrepo", repo_name="myrepo",
            session_date="2026-06-01"), vec(0.0, 1.0, 0.0)),
        ("/x/myrepo/docs/arch.md", make_chunk(
            content="The scheduler uses a priority queue design.",
            source_type="repo_doc", recall_type="doc", weight=1.2,
            file_path="/x/myrepo/docs/arch.md", repo_id="myrepo",
            repo_name="myrepo", session_date="2026-05-01"),
         vec(0.0, 0.0, 1.0)),
    ]
    for path, chunk, v in rows:
        dbmod.replace_source(conn, path, "doc", "h" + path, [chunk], [v])
    conn.close()


def near(*axes):
    def embedder(texts):
        return [vec(*axes) for _ in texts]
    return embedder


def test_semantic_match_via_vector(tmp_path):
    cfg = make_cfg(tmp_path)
    seed(cfg)
    out = search(cfg, "database choice rationale", k=1,
                 embedder=near(0.9, 0.1, 0.0))
    assert out[0]["file_path"].endswith("0002-sqlite.md")


def test_exact_string_via_fts(tmp_path):
    cfg = make_cfg(tmp_path)
    seed(cfg)
    # embedder points AWAY from the right chunk; FTS must still surface it
    out = search(cfg, "ERR_AUTH_401", k=1, embedder=near(1.0, 0.0, 0.0))
    assert out[0]["file_path"].endswith("s1.jsonl")


def test_weight_boosts_curated_over_digest(tmp_path):
    cfg = make_cfg(tmp_path)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    same_vec = vec(1.0, 0.0, 0.0)
    dbmod.replace_source(conn, "/a", "doc", "ha", [make_chunk(
        content="chunking strategy decision", weight=1.5,
        file_path="/curated.md")], [same_vec])
    dbmod.replace_source(conn, "/b", "doc", "hb", [make_chunk(
        content="chunking strategy decision", source_type="transcript_digest",
        weight=1.0, file_path="/digest.jsonl")], [same_vec])
    conn.close()
    out = search(cfg, "chunking strategy", k=2, embedder=near(1.0, 0.0, 0.0))
    assert out[0]["file_path"] == "/curated.md"


def test_filters(tmp_path):
    cfg = make_cfg(tmp_path)
    seed(cfg)
    everything = near(0.5, 0.5, 0.5)
    by_repo = search(cfg, "anything", k=6, repo="myrepo", embedder=everything)
    assert all(r["repo_name"] == "myrepo" for r in by_repo)
    by_type = search(cfg, "anything", k=6, rtype="decision", embedder=everything)
    assert all(r["recall_type"] == "decision" for r in by_type)
    by_date = search(cfg, "anything", k=6, since="2026-07-01",
                     embedder=everything)
    assert all(r["session_date"] >= "2026-07-01" for r in by_date)


def test_provenance_always_present(tmp_path):
    cfg = make_cfg(tmp_path)
    seed(cfg)
    out = search(cfg, "anything at all", k=6, embedder=near(0.5, 0.5, 0.5))
    assert out, "expected results"
    for r in out:
        assert r["file_path"].startswith("/")
        assert r["score"] > 0
    text = format_results(out)
    for r in out:
        assert r["file_path"] in text
    assert "·" in text


def test_search_raises_on_model_mismatch(tmp_path):
    cfg = make_cfg(tmp_path)
    seed(cfg)
    # same db_path, different embed_model/dim — as if the config was swapped
    # to a new embed model without a `memsearch index --full` rebuild. The
    # stub embedder returns vectors sized to the *new* model's dim, exactly
    # like a real embed model swap would (the on-disk vec0 table stays at
    # the old dim), so an unguarded search() hits a raw sqlite3 dimension
    # mismatch rather than the friendly SystemExit under test.
    cfg2 = make_cfg(tmp_path, embed_model="other-model", embed_dim=8)
    mismatched_embedder = lambda texts: [[0.5] * cfg2.embed_dim for _ in texts]
    with pytest.raises(SystemExit, match="other-model"):
        search(cfg2, "anything", embedder=mismatched_embedder)


def test_latency_logged_and_fts_syntax_safe(tmp_path):
    cfg = make_cfg(tmp_path)
    seed(cfg)
    # queries full of FTS5 operators must not raise
    out = search(cfg, 'why "quotes" AND (parens) - dashes?', k=2,
                 embedder=near(0.5, 0.5, 0.5))
    assert isinstance(out, list)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    assert conn.execute("SELECT count(*) FROM query_log").fetchone()[0] >= 1
    conn.close()
