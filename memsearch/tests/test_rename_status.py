from memsearch import db as dbmod
from memsearch.config import load_config
from memsearch.rename import rename_repo
from memsearch.status import status_report
from tests.conftest import DIM, make_chunk, vec
from tests.test_config import write_cfg


def make_cfg(tmp_path, **over):
    p = write_cfg(tmp_path, **{
        "embed_model": "test-embed", "embed_dim": DIM,
        "db_path": str(tmp_path / "mi" / "memory.db"), **over})
    return load_config(p)


def seed(cfg, repo="Snatch-Bracket"):
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    dbmod.replace_source(
        conn, f"/x/{repo}/docs/a.md", "doc", "hash-a",
        [make_chunk(repo_id="snatch-bracket", repo_name=repo,
                    file_path=f"/x/{repo}/docs/a.md")], [vec(1.0)])
    conn.close()


def test_rename_rewrites_metadata_only(tmp_path):
    cfg = make_cfg(tmp_path)
    seed(cfg)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    vec_before = conn.execute(
        "SELECT embedding FROM chunk_vec").fetchone()[0]
    conn.close()

    report = rename_repo(cfg, "Snatch-Bracket", "CourtFlow")
    assert report["chunks_renamed"] == 1

    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    row = conn.execute(
        "SELECT repo_id, repo_name, file_path, content_hash FROM chunks"
    ).fetchone()
    assert row[0] == "snatch-bracket"          # stable id untouched
    assert row[1] == "CourtFlow"
    assert "/CourtFlow/" in row[2] and "Snatch-Bracket" not in row[2]
    assert conn.execute("SELECT path FROM sources").fetchone()[0] == \
        "/x/CourtFlow/docs/a.md"
    assert conn.execute("SELECT content_hash FROM sources").fetchone()[0] == \
        "hash-a"                               # zero re-embed: hash stable
    vec_after = conn.execute("SELECT embedding FROM chunk_vec").fetchone()[0]
    assert vec_after == vec_before             # zero re-embed: vector identical
    conn.close()


def test_rename_escapes_like_wildcards(tmp_path):
    # "my_repo" contains a SQL LIKE wildcard ('_' = any single char). An
    # unescaped LIKE '%/my_repo/%' would also match a decoy path where that
    # position holds a different literal character (e.g. "/myXrepo/") —
    # REPLACE() itself is literal so no corruption occurs, but the row
    # still gets touched by the UPDATE and inflates the returned counts.
    cfg = make_cfg(tmp_path)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    dbmod.replace_source(
        conn, "/x/my_repo/docs/a.md", "doc", "hash-a",
        [make_chunk(repo_id="my-repo", repo_name="my_repo",
                    file_path="/x/my_repo/docs/a.md")], [vec(1.0)])
    dbmod.replace_source(
        conn, "/x/myXrepo/docs/b.md", "doc", "hash-b",
        [make_chunk(repo_id="myxrepo", repo_name="myXrepo",
                    file_path="/x/myXrepo/docs/b.md")], [vec(2.0)])
    conn.close()

    report = rename_repo(cfg, "my_repo", "new_repo")
    assert report["chunks_renamed"] == 1
    assert report["paths_rewritten"] == 1          # decoy not counted
    assert report["sources_rewritten"] == 1         # decoy not counted

    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    decoy_path = conn.execute(
        "SELECT file_path FROM chunks WHERE repo_name='myXrepo'").fetchone()[0]
    assert decoy_path == "/x/myXrepo/docs/b.md"      # decoy untouched
    decoy_source = conn.execute(
        "SELECT path FROM sources WHERE path LIKE '%b.md'").fetchone()[0]
    assert decoy_source == "/x/myXrepo/docs/b.md"
    conn.close()


def test_status_report_contents(tmp_path):
    cfg = make_cfg(tmp_path)
    seed(cfg)
    out = status_report(cfg)
    assert "chunks: 1" in out
    assert "curated_doc: 1" in out
    assert "test-embed" in out and str(DIM) in out
    assert "REVISIT" not in out


def test_status_flags_model_mismatch(tmp_path):
    cfg = make_cfg(tmp_path)
    seed(cfg)
    cfg2 = make_cfg(tmp_path, embed_model="other-model", embed_dim=8)
    out = status_report(cfg2)
    assert "MISMATCH" in out


def test_status_flags_p95_revisit_trigger(tmp_path):
    cfg = make_cfg(tmp_path)
    seed(cfg)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    for _ in range(20):
        dbmod.log_query(conn, 900.0)
    conn.close()
    out = status_report(cfg)
    assert "REVISIT" in out and "Qdrant" in out


def test_status_without_db(tmp_path):
    cfg = make_cfg(tmp_path)
    out = status_report(cfg)
    assert "no index" in out.lower()
