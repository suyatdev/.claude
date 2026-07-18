import pytest

from memsearch import cli
from memsearch.config import load_config
from tests.conftest import DIM
from tests.test_config import write_cfg


@pytest.fixture
def cfg_path(tmp_path):
    return str(write_cfg(tmp_path, **{
        "embed_model": "test-embed", "embed_dim": DIM,
        "db_path": str(tmp_path / "mi" / "memory.db")}))


def test_no_args_shows_usage_exit_2(capsys):
    with pytest.raises(SystemExit) as e:
        cli.main([])
    assert e.value.code == 2


def test_bad_type_choice_exit_2(cfg_path):
    with pytest.raises(SystemExit) as e:
        cli.main(["--config", cfg_path, "query", "x", "--type", "bogus"])
    assert e.value.code == 2


def test_query_without_index_exits_1(cfg_path, capsys):
    rc = cli.main(["--config", cfg_path, "query", "anything"])
    assert rc == 1
    assert "no index" in capsys.readouterr().err.lower()


def test_status_without_index(cfg_path, capsys):
    rc = cli.main(["--config", cfg_path, "status"])
    assert rc == 0
    assert "no index" in capsys.readouterr().out.lower()


def test_query_formats_results(cfg_path, monkeypatch, capsys):
    from memsearch import db as dbmod
    from tests.conftest import make_chunk, vec
    cfg = load_config(__import__("pathlib").Path(cfg_path))
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    dbmod.replace_source(conn, "/x/doc.md", "doc", "h",
                         [make_chunk()], [vec(1.0)])
    conn.close()
    monkeypatch.setattr(cli, "_default_embedder",
                        lambda cfg: (lambda texts: [vec(1.0)] * len(texts)))
    rc = cli.main(["--config", cfg_path, "query", "sqlite decision", "-k", "1"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "0002-sqlite-over-qdrant.md" in out and "score=" in out


def test_rename_command(cfg_path, capsys):
    from memsearch import db as dbmod
    from tests.conftest import make_chunk, vec
    cfg = load_config(__import__("pathlib").Path(cfg_path))
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    dbmod.replace_source(conn, "/x/Old/doc.md", "doc", "h",
                         [make_chunk(repo_name="Old",
                                     file_path="/x/Old/doc.md")], [vec(1.0)])
    conn.close()
    rc = cli.main(["--config", cfg_path, "rename", "Old", "New"])
    assert rc == 0
    assert "1" in capsys.readouterr().out
