import json
from pathlib import Path

from memsearch import db as dbmod
from memsearch.config import load_config
from memsearch.index import repo_for_cwd, run_index
from tests.conftest import DIM
from tests.test_config import write_cfg
from tests.test_extract import BASE, jl

CANNED_DIGEST = """## Summary
Fixed the login bug.

## Decisions
- Chose header-aware chunking for the fix notes.

## Bugs & Fixes
- Inverted token check fixed.

## Files Touched
- auth.py
"""


def stub_embedder(texts):
    return [[0.1] * DIM for _ in texts]


def stub_digester(extract):
    return CANNED_DIGEST


def setup_corpus(tmp_path: Path) -> Path:
    """A miniature ~/.claude layout: 2 transcripts (one older), 1 curated doc,
    1 repo doc, plus excluded files that must never be indexed."""
    proj = tmp_path / "projects" / "-x-repo"
    proj.mkdir(parents=True)
    old = proj / "old-session.jsonl"
    old.write_text(jl(type="user", message={"role": "user", "content": "old work"},
                      **BASE) + "\n" +
                   jl(type="assistant", message={"role": "assistant", "content": [
                       {"type": "text", "text": "did old work"}]}, **BASE) + "\n")
    new = proj / "new-session.jsonl"
    new.write_text(jl(type="user", message={"role": "user", "content": "new work"},
                      **BASE) + "\n" +
                   jl(type="assistant", message={"role": "assistant", "content": [
                       {"type": "text", "text": "did new work"}]}, **BASE) + "\n")
    import os
    os.utime(old, (1_000_000_000, 1_000_000_000))  # much older mtime
    sub = proj / "new-session" / "subagents"
    sub.mkdir(parents=True)
    (sub / "agent-1.jsonl").write_text(jl(
        type="user", message={"role": "user", "content": "subagent noise"},
        **BASE) + "\n")
    curated = tmp_path / "coding-memory"
    curated.mkdir()
    (curated / "decisions.md").write_text("# Decisions\n\nWe decided things.\n")
    (curated / "CODING_MEMORY.md").write_text("# Ephemeral\n\nNever index.\n")
    repo = tmp_path / "myrepo"
    (repo / "docs").mkdir(parents=True)
    (repo / "docs" / "arch.md").write_text("# Arch\n\nRepo doc content.\n")
    return tmp_path


def make_cfg(tmp_path):
    corpus = setup_corpus(tmp_path)
    p = write_cfg(tmp_path, **{
        "embed_model": "test-embed", "embed_dim": DIM,
        "db_path": str(corpus / "memory-index" / "memory.db"),
        "transcripts_glob": str(corpus / "projects" / "*" / "*.jsonl"),
        "curated_docs": [str(corpus / "coding-memory")],
        "repo_roots": [{"id": "myrepo", "name": "myrepo",
                        "root": str(corpus / "myrepo")}],
    })
    return load_config(p)


def test_full_run_indexes_all_sources_newest_first(tmp_path):
    cfg = make_cfg(tmp_path)
    order = []
    report = run_index(cfg, embedder=stub_embedder, digester=stub_digester,
                       progress=order.append)
    assert report["errors"] == []
    assert report["processed"] == 4  # 2 docs + 2 transcripts
    t_lines = [ln for ln in order if "session.jsonl" in ln]
    assert "new-session" in t_lines[0] and "old-session" in t_lines[1]
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    s = dbmod.stats(conn)
    assert s["by_source_type"]["transcript_digest"] == 8  # 2 sessions x 4 H2
    assert s["by_source_type"]["curated_doc"] >= 1
    assert s["by_source_type"]["repo_doc"] >= 1
    all_paths = [r[0] for r in conn.execute("SELECT file_path FROM chunks")]
    assert not any("CODING_MEMORY" in p or "subagents" in p for p in all_paths)
    status = json.loads((cfg.db_path.parent / "status.json").read_text())
    assert status["chunks"] == s["chunks"]
    assert status["embed_model"] == "test-embed"


def test_second_run_is_idempotent(tmp_path):
    cfg = make_cfg(tmp_path)
    run_index(cfg, embedder=stub_embedder, digester=stub_digester,
              progress=lambda _: None)
    report2 = run_index(cfg, embedder=stub_embedder, digester=stub_digester,
                        progress=lambda _: None)
    assert report2["processed"] == 0
    assert report2["skipped"] == 4


def test_changed_file_reindexes_only_itself(tmp_path):
    cfg = make_cfg(tmp_path)
    run_index(cfg, embedder=stub_embedder, digester=stub_digester,
              progress=lambda _: None)
    doc = Path(cfg.curated_docs[0]) / "decisions.md"
    doc.write_text("# Decisions\n\nWe decided MORE things.\n")
    report = run_index(cfg, embedder=stub_embedder, digester=stub_digester,
                       progress=lambda _: None)
    assert report["processed"] == 1


def test_limit_caps_transcripts(tmp_path):
    cfg = make_cfg(tmp_path)
    report = run_index(cfg, limit=1, embedder=stub_embedder,
                       digester=stub_digester, progress=lambda _: None)
    # 2 docs + 1 transcript (the newest)
    assert report["processed"] == 3


def test_digest_error_is_recorded_not_fatal(tmp_path):
    cfg = make_cfg(tmp_path)

    def bad_digester(extract):
        raise RuntimeError("model down")

    report = run_index(cfg, embedder=stub_embedder, digester=bad_digester,
                       progress=lambda _: None)
    assert report["processed"] == 2  # the two docs still landed
    assert len(report["errors"]) == 2


def test_repo_for_cwd(tmp_path):
    cfg = make_cfg(tmp_path)
    root = str(cfg.repo_roots[0].root)
    assert repo_for_cwd(root + "/src", cfg) == ("myrepo", "myrepo")
    assert repo_for_cwd("/somewhere/OtherRepo", cfg) == ("otherrepo", "OtherRepo")
    assert repo_for_cwd("", cfg) == ("unknown", "unknown")
