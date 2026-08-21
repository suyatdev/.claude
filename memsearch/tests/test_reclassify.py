"""index --reclassify: re-type stored rows from the real source enumeration."""
from pathlib import Path

import pytest

from memsearch import cli
from memsearch import db as dbmod
from memsearch import reclassify
from memsearch.config import load_config
from memsearch.index import run_index
from tests.conftest import DIM, vec
from tests.test_config import write_cfg


def stub_embedder(texts):
    return [[0.1] * DIM for _ in texts]


def corpus_cfg(tmp_path: Path):
    """Two curated docs, one of them under a judge directory. Indexed BEFORE
    the judge rule existed is simulated by re-typing the row back to
    curated_doc — the same state a pre-0030 index is in."""
    curated = tmp_path / "coding-memory"
    (curated / "compliance-judge").mkdir(parents=True)
    (curated / "compliance-judge" / "verdict.md").write_text(
        "# Verdict\n\nZero violations.\n")
    (curated / "decisions.md").write_text("# Decisions\n\nWe decided things.\n")
    p = write_cfg(tmp_path, **{
        "embed_model": "test-embed", "embed_dim": DIM,
        "db_path": str(tmp_path / "mi" / "memory.db"),
        "transcripts_glob": str(tmp_path / "none" / "*.jsonl"),
        "curated_docs": [str(curated)], "repo_roots": []})
    return load_config(p)


def seed_pre_0030(cfg):
    run_index(cfg, embedder=stub_embedder, digester=lambda e: "",
              progress=lambda _: None)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    with conn:
        conn.execute("UPDATE chunks SET source_type='curated_doc' "
                     "WHERE source_type='judge_doc'")
    conn.close()


def types(cfg) -> dict:
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    out = dict(conn.execute(
        "SELECT file_path, source_type FROM chunks GROUP BY file_path"))
    conn.close()
    return out


def test_retypes_only_the_disagreeing_files(tmp_path):
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    r = reclassify.run_reclassify(cfg, progress=lambda _: None)
    stored = types(cfg)
    verdict = next(p for p in stored if p.endswith("verdict.md"))
    plain = next(p for p in stored if p.endswith("decisions.md"))
    assert stored[verdict] == "judge_doc"
    assert stored[plain] == "curated_doc"
    assert r["transitions"] == {
        "curated_doc->judge_doc": {"files": 1, "chunks": r["retyped_chunks"]}}
    assert r["retyped_chunks"] >= 1


def test_reports_the_denominator_not_just_the_transition(tmp_path):
    """"N files re-typed" reads identically whether the pass walked the whole
    corpus or died a third of the way in (ADR 0030)."""
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    r = reclassify.run_reclassify(cfg, progress=lambda _: None)
    assert r["walked"] == 2
    assert r["retyped_files"] == 1
    assert r["unchanged"] == 1
    assert r["walked"] == r["unchanged"] + r["retyped_files"]
    assert r["verified"] is True


def test_second_pass_is_a_no_op(tmp_path):
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    reclassify.run_reclassify(cfg, progress=lambda _: None)
    r = reclassify.run_reclassify(cfg, progress=lambda _: None)
    assert r["retyped_files"] == 0 and r["transitions"] == {}
    assert r["walked"] == 2 and r["unchanged"] == 2


def test_a_computed_type_with_no_weight_aborts_before_any_write(tmp_path):
    """The second lock on the gap config-load validation cannot see."""
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    before = types(cfg)

    def walker(_cfg):
        return [(Path(p), ".claude", ".claude", "mystery_doc")
                for p in before]

    with pytest.raises(SystemExit, match="mystery_doc"):
        reclassify.run_reclassify(cfg, walker=walker, progress=lambda _: None)
    assert types(cfg) == before


def test_an_unreachable_walk_entry_is_skipped_and_the_walk_continues(tmp_path):
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    from memsearch.index import _iter_docs

    def walker(c):
        return [(tmp_path / "gone.md", ".claude", ".claude", "curated_doc"),
                *_iter_docs(c)]

    r = reclassify.run_reclassify(cfg, walker=walker, progress=lambda _: None)
    assert len(r["skipped"]) == 1 and "gone.md" in r["skipped"][0]
    assert r["walked"] == 2                     # the skip is not walked
    assert r["retyped_files"] == 1              # and the rest still ran


def test_a_vanished_source_is_counted_and_left_alone(tmp_path):
    """Not deleted: pruning is replace_source's job, and a pass named
    "reclassify" must not quietly become a destructive one (ADR 0030)."""
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    (Path(cfg.curated_docs[0]) / "decisions.md").unlink()
    r = reclassify.run_reclassify(cfg, progress=lambda _: None)
    assert r["vanished_sources"] == 1
    assert any(p.endswith("decisions.md") for p in types(cfg))


def test_a_mid_walk_failure_rolls_the_whole_pass_back(tmp_path, monkeypatch):
    """One transaction: a partially re-typed corpus would score some verdicts
    at the new weight and some at the old, and no measurement taken against it
    would mean anything (ADR 0030)."""
    cfg = corpus_cfg(tmp_path)
    seed_pre_0030(cfg)
    before = types(cfg)
    from memsearch.index import _iter_docs

    def walker(c):
        # both files disagree, so there are two updates to apply
        return [(p, r, n, "repo_doc") for p, r, n, _t in _iter_docs(c)]

    calls = []
    real = reclassify._update_one

    def flaky(conn, path, was, now):
        calls.append(path)
        if len(calls) == 2:
            raise RuntimeError("write failed mid-walk")
        return real(conn, path, was, now)

    monkeypatch.setattr(reclassify, "_update_one", flaky)
    with pytest.raises(RuntimeError, match="mid-walk"):
        reclassify.run_reclassify(cfg, walker=walker, progress=lambda _: None)
    assert types(cfg) == before


def test_cli_reclassify_reports_and_exits_zero(tmp_path, capsys):
    cfg_path = str(tmp_path / "config.json")
    cfg = corpus_cfg(tmp_path)          # writes tmp_path/config.json
    seed_pre_0030(cfg)
    rc = cli.main(["--config", cfg_path, "index", "--reclassify"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "curated_doc -> judge_doc: 1 files" in out
    assert "walked=2" in out and "unchanged=1" in out


def test_cli_reclassify_exits_non_zero_when_an_entry_is_skipped(tmp_path, monkeypatch):
    cfg_path = str(tmp_path / "config.json")
    cfg = corpus_cfg(tmp_path)          # writes tmp_path/config.json
    seed_pre_0030(cfg)
    real_iter_docs = reclassify._iter_docs

    def walker(c):
        return [(tmp_path / "gone.md", ".claude", ".claude", "curated_doc"),
                *real_iter_docs(c)]

    monkeypatch.setattr(reclassify, "_iter_docs", walker)
    rc = cli.main(["--config", cfg_path, "index", "--reclassify"])
    assert rc == 1


def test_cli_reclassify_and_full_are_mutually_exclusive(tmp_path):
    cfg = corpus_cfg(tmp_path)
    with pytest.raises(SystemExit) as e:
        cli.main(["--config", str(tmp_path / "config.json"), "index",
                  "--full", "--reclassify"])
    assert e.value.code == 2
