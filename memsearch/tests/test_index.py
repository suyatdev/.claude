import json
import os
import re
from pathlib import Path

import pytest

from memsearch import db as dbmod
from memsearch.config import load_config
from memsearch.index import repo_for_cwd, run_index
from tests.conftest import DIM
from tests.test_config import write_cfg
from tests.test_extract import BASE, jl

# ISO-8601 UTC at second precision — the shape `last_indexed` already promises.
# A bare isoformat() emits microseconds and would break that promise.
STAMP = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+00:00$")

STATUS_KEYS = {"chunks", "sources", "last_indexed", "db_bytes", "embed_model",
               "embed_dim", "run_started", "last_run", "last_run_errors"}

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
    1 archive doc, 1 repo doc, plus excluded files that must never be
    indexed."""
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
    # Deliberately *inside* the curated directory, a path the walker already
    # visits. The ~/.claude-root position — where the real archive lives, and
    # which no bucket reaches — is covered by its own cfg variant in
    # test_root_position_archive_is_reached_only_via_curated_docs.
    (curated / "CODING_MEMORY.md").write_text(
        "# Coding Memory\n\n## 2026-08-07 — session 40\n\nWhat happened.\n")
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
    assert report["processed"] == 5  # 3 docs + 2 transcripts
    t_lines = [ln for ln in order if "session.jsonl" in ln]
    assert "new-session" in t_lines[0] and "old-session" in t_lines[1]
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    s = dbmod.stats(conn)
    assert s["by_source_type"]["transcript_digest"] == 8  # 2 sessions x 4 H2
    assert s["by_source_type"]["curated_doc"] >= 1
    assert s["by_source_type"]["repo_doc"] >= 1
    all_paths = [r[0] for r in conn.execute("SELECT file_path FROM chunks")]
    assert not any("subagents" in p for p in all_paths)
    assert any("CODING_MEMORY" in p for p in all_paths)
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
    assert report2["skipped"] == 5


def test_changed_file_reindexes_only_itself(tmp_path):
    cfg = make_cfg(tmp_path)
    run_index(cfg, embedder=stub_embedder, digester=stub_digester,
              progress=lambda _: None)
    doc = Path(cfg.curated_docs[0]) / "decisions.md"
    doc.write_text("# Decisions\n\nWe decided MORE things.\n")
    report = run_index(cfg, embedder=stub_embedder, digester=stub_digester,
                       progress=lambda _: None)
    assert report["processed"] == 1


def test_full_rebuild_reprocesses_and_dedupes(tmp_path):
    """--full is the prescribed remedy for a model_mismatch: it unlinks the DB
    and reindexes from scratch. Assert every source is re-processed (not
    skipped by hash-diff, since the DB — and therefore its `sources` hash
    cache — no longer exists) and the resulting chunk count matches a fresh
    single run exactly, i.e. nothing got duplicated."""
    cfg = make_cfg(tmp_path)
    run_index(cfg, embedder=stub_embedder, digester=stub_digester,
              progress=lambda _: None)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    chunks_before = dbmod.stats(conn)["chunks"]
    conn.close()

    report = run_index(cfg, full=True, embedder=stub_embedder,
                       digester=stub_digester, progress=lambda _: None)
    assert report["processed"] == 5  # 3 docs + 2 transcripts, all reprocessed
    assert report["skipped"] == 0

    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    chunks_after = dbmod.stats(conn)["chunks"]
    conn.close()
    assert chunks_after == chunks_before  # rebuilt exactly once, not duplicated


def test_limit_caps_transcripts(tmp_path):
    cfg = make_cfg(tmp_path)
    report = run_index(cfg, limit=1, embedder=stub_embedder,
                       digester=stub_digester, progress=lambda _: None)
    # 3 docs + 1 transcript (the newest)
    assert report["processed"] == 4


def test_digest_error_is_recorded_not_fatal(tmp_path):
    cfg = make_cfg(tmp_path)

    def bad_digester(extract):
        raise RuntimeError("model down")

    report = run_index(cfg, embedder=stub_embedder, digester=bad_digester,
                       progress=lambda _: None)
    assert report["processed"] == 3  # the three docs still landed
    assert len(report["errors"]) == 2


def archive_rows(cfg, column: str) -> list:
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    rows = [r[0] for r in conn.execute(
        f"SELECT DISTINCT {column} FROM chunks "
        "WHERE file_path LIKE '%CODING_MEMORY.md'")]
    conn.close()
    return rows


def test_archive_doc_gets_its_own_weight_tier(tmp_path):
    """1.0, not curated_doc's 1.5: session narrative must stay retrievable
    without ever outranking the decision records it narrates."""
    cfg = make_cfg(tmp_path)
    run_index(cfg, embedder=stub_embedder, digester=stub_digester,
              progress=lambda _: None)
    assert archive_rows(cfg, "source_type") == ["archive_doc"]
    assert archive_rows(cfg, "weight") == [1.0]
    assert cfg.weights["archive_doc"] < cfg.weights["curated_doc"]


def test_archive_chunks_answer_the_episodic_filter(tmp_path):
    """`--type episodic` is what a reader asking "what happened in session 27"
    reaches for. chunk_doc derives recall_type from a path substring, which
    would bucket the archive as generic `doc` — indexed but silently
    unreachable by the obvious filter."""
    cfg = make_cfg(tmp_path)
    run_index(cfg, embedder=stub_embedder, digester=stub_digester,
              progress=lambda _: None)
    assert archive_rows(cfg, "recall_type") == ["episodic"]


def test_root_position_archive_is_reached_only_via_curated_docs(tmp_path):
    """The archive's zero rows had TWO sufficient causes, not one: the
    exclusion, and ~/.claude/CODING_MEMORY.md sitting off every walked path
    (curated_docs names ~/.claude/coding-memory, ~/.claude/docs and
    ~/.claude/PORTS.md — never the ~/.claude root). Both halves are asserted,
    because lifting the exclusion alone changes nothing for the file it
    targets, and a suite that checks only the first half rubber-stamps it."""
    corpus = setup_corpus(tmp_path)
    archive = corpus / "CODING_MEMORY.md"
    archive.write_text(
        "# Coding Memory\n\n## 2026-08-07 — session 40\n\nRoot position.\n")

    def sources_for(curated_docs, db_name):
        p = write_cfg(tmp_path, **{
            "embed_model": "test-embed", "embed_dim": DIM,
            "db_path": str(corpus / db_name / "memory.db"),
            "transcripts_glob": str(corpus / "projects" / "*" / "*.jsonl"),
            "curated_docs": curated_docs,
            "repo_roots": [],
        })
        cfg = load_config(p)
        run_index(cfg, embedder=stub_embedder, digester=stub_digester,
                  progress=lambda _: None)
        conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
        rows = [r[0] for r in conn.execute("SELECT path FROM sources")]
        conn.close()
        return rows

    curated = str(corpus / "coding-memory")
    assert str(archive) in sources_for([curated, str(archive)], "db-named")
    # Exclusion lifted, but curated_docs omits it: still unreachable.
    assert str(archive) not in sources_for([curated], "db-omitted")


def read_status(cfg) -> dict:
    return json.loads((cfg.db_path.parent / "status.json").read_text())


def status_dir_temp_files(cfg) -> list[str]:
    d = cfg.db_path.parent
    return [p.name for p in d.iterdir()
            if p.name != "status.json" and (
                p.name.endswith(".tmp") or p.name.startswith(".status"))]


def run(cfg, **kw):
    kw.setdefault("progress", lambda _: None)
    return run_index(cfg, embedder=stub_embedder, digester=stub_digester, **kw)


def test_completed_run_stamps_run_timestamps_and_error_count(tmp_path):
    cfg = make_cfg(tmp_path)
    run(cfg)
    st = read_status(cfg)
    assert set(st) == STATUS_KEYS  # six existing keys keep their names
    assert STAMP.match(st["run_started"]), st["run_started"]
    assert STAMP.match(st["last_run"]), st["last_run"]
    assert st["last_run"] >= st["run_started"]
    assert st["last_run_errors"] == 0


def test_last_run_errors_counts_the_runs_errors(tmp_path):
    """A run with the embedding backend down completes, exits 0, and looks
    identical to a clean one — the count is the only thing that distinguishes
    them, so it is what the nudge reads."""
    cfg = make_cfg(tmp_path)

    def bad_digester(extract):
        raise RuntimeError("model down")

    report = run_index(cfg, embedder=stub_embedder, digester=bad_digester,
                       progress=lambda _: None)
    assert len(report["errors"]) == 2
    assert read_status(cfg)["last_run_errors"] == 2


def test_run_started_is_written_before_the_run_finishes(tmp_path):
    cfg = make_cfg(tmp_path)
    seen: list[dict] = []
    run(cfg, progress=lambda _: seen.append(read_status(cfg)))
    assert STAMP.match(seen[0]["run_started"])
    assert "last_run" not in seen[0]  # first ever run: nothing has finished


def test_full_rebuild_keeps_the_prior_chunk_count_visible_mid_run(tmp_path):
    """--full unlinks the DB before connecting, so an entry write that
    recomputed from it would stamp chunks: 0 — and the nudge exits silently on
    an absent-or-zero chunk count, deleting the session line for the whole
    multi-hour rebuild. The entry write must carry the prior file over."""
    cfg = make_cfg(tmp_path)
    run(cfg)
    before = read_status(cfg)
    assert before["chunks"] > 0

    seen: list[dict] = []
    run(cfg, full=True, progress=lambda _: seen.append(read_status(cfg)))
    assert seen[0]["chunks"] == before["chunks"]
    assert seen[0]["last_run"] == before["last_run"]
    assert seen[0]["last_run_errors"] == before["last_run_errors"]
    assert seen[0]["run_started"] >= before["last_run"]


def test_unreadable_prior_status_never_aborts_the_run(tmp_path, capsys):
    """The alternative is this feature's own failure mode one field over: an
    unreadable status file aborting every scheduled run while the nudge, silent
    on malformed input by contract, reports nothing at all."""
    cfg = make_cfg(tmp_path)
    run(cfg)
    (cfg.db_path.parent / "status.json").write_text('{"chunks": 12')  # truncated

    seen: list[dict] = []
    report = run(cfg, full=True, progress=lambda _: seen.append(read_status(cfg)))

    assert report["errors"] == []
    assert "status.json" in capsys.readouterr().err
    assert set(seen[0]) == {"run_started"}  # stamped alone, nothing carried
    assert read_status(cfg)["chunks"] > 0  # completion write repairs the file


def test_status_write_leaves_no_temp_file_behind(tmp_path):
    cfg = make_cfg(tmp_path)
    run(cfg)
    assert status_dir_temp_files(cfg) == []


def test_failed_status_write_leaves_the_previous_file_intact(tmp_path,
                                                             monkeypatch):
    """This spec twice expects the writing process to be hard-killed, so the
    write renders to a temp file and renames onto status.json — a half-written
    file is exactly what the unreadable-prior rule above has to absorb."""
    cfg = make_cfg(tmp_path)
    run(cfg)
    before = (cfg.db_path.parent / "status.json").read_text()

    def boom(src, dst):
        raise OSError("no space left on device")

    monkeypatch.setattr(os, "replace", boom)
    with pytest.raises(OSError):
        run(cfg)

    assert (cfg.db_path.parent / "status.json").read_text() == before
    assert status_dir_temp_files(cfg) == []


def test_repo_for_cwd(tmp_path):
    cfg = make_cfg(tmp_path)
    root = str(cfg.repo_roots[0].root)
    assert repo_for_cwd(root + "/src", cfg) == ("myrepo", "myrepo")
    assert repo_for_cwd("/somewhere/OtherRepo", cfg) == ("otherrepo", "OtherRepo")
    assert repo_for_cwd("", cfg) == ("unknown", "unknown")


def test_glob_reachable_subagents_transcript_is_excluded(tmp_path):
    """Two layers protect the "never index subagents" invariant, and this
    test exercises only the second one. Layer 1 (structural, untested here):
    setup_corpus's subagent fixture lives 4 path segments below `projects/`
    (.../new-session/subagents/agent-1.jsonl), while `transcripts_glob`
    (`projects/*/*.jsonl`) is non-recursive and only ever matches 2 segments
    — so that fixture path is unreachable by the glob regardless of
    `is_excluded`, which is why the path assertion in
    test_full_run_indexes_all_sources_newest_first stays green even if
    `is_excluded` were deleted from `_iter_transcripts`. Layer 2 (logical,
    exercised here): a subagents-pattern transcript placed where the glob
    DOES reach it (`projects/subagents/agent-1.jsonl`, 2 segments) is kept
    out only by `is_excluded` — a real exercise of the backstop, so this
    invariant stays covered even if a future recursive glob makes the deep
    layout reachable too."""
    cfg = make_cfg(tmp_path)
    sub_dir = tmp_path / "projects" / "subagents"
    sub_dir.mkdir(parents=True)
    sub_path = sub_dir / "agent-1.jsonl"
    sub_path.write_text(jl(
        type="user", message={"role": "user", "content": "subagent noise"},
        **BASE) + "\n")

    seen_session_ids = []

    def spy_digester(extract):
        seen_session_ids.append(extract.session_id)
        return CANNED_DIGEST

    run_index(cfg, embedder=stub_embedder, digester=spy_digester,
              progress=lambda _: None)

    # extractor/digester were never invoked for the excluded transcript
    assert "agent-1" not in seen_session_ids
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    sources = [r[0] for r in conn.execute("SELECT path FROM sources")]
    conn.close()
    # Exact-path check, not a bare "subagents" substring check: pytest's own
    # tmp_path embeds this test's function name, which itself contains the
    # word "subagents" — a naive substring assertion would false-positive on
    # every source path regardless of whether the excluded file leaked in.
    assert str(sub_path) not in sources


def test_judge_directory_files_get_their_own_source_type():
    """Keyed on the PARENT DIRECTORY name, not a full-path substring: a verdict
    tiers identically no matter which config bucket enumerated it (ADR 0030)."""
    from memsearch.index import _doc_source_type
    obs = Path("/x/coding-memory/observability-judge/2026-08-20-verdict.md")
    comp = Path("/x/coding-memory/compliance-judge/2026-08-20-verdict.md")
    assert _doc_source_type(obs, "curated_doc") == "judge_doc"
    assert _doc_source_type(comp, "curated_doc") == "judge_doc"
    # the accepted exposure, pinned so a later change has to argue with it:
    # any repo-root directory of that name tiers the same way.
    assert _doc_source_type(
        Path("/x/myrepo/observability-judge/note.md"), "repo_doc") == "judge_doc"


def test_non_judge_curated_docs_are_unchanged():
    from memsearch.index import _doc_source_type
    assert _doc_source_type(
        Path("/x/coding-memory/pr-tracking.md"), "curated_doc") == "curated_doc"
    assert _doc_source_type(
        Path("/x/coding-memory/judge-notes/x.md"), "curated_doc") == "curated_doc"
    assert _doc_source_type(
        Path("/x/docs/decisions/0030-x.md"), "curated_doc") == "curated_doc"


def test_archive_filename_wins_over_the_judge_directory():
    """Precedence is stated, not incidental: the archive carve-out is checked
    first, so a CODING_MEMORY.md parked in a judge directory stays archive_doc
    (1.0) rather than being promoted into the verdict tier."""
    from memsearch.index import _doc_source_type
    assert _doc_source_type(
        Path("/x/coding-memory/compliance-judge/CODING_MEMORY.md"),
        "curated_doc") == "archive_doc"


def judge_corpus_cfg(tmp_path: Path):
    """A corpus of its own — deliberately NOT setup_corpus(), whose file count
    is asserted verbatim by test_full_run_indexes_all_sources_newest_first
    (`processed == 5`) and test_second_run_is_idempotent (`skipped == 5`)."""
    curated = tmp_path / "coding-memory"
    (curated / "observability-judge").mkdir(parents=True)
    (curated / "observability-judge" / "2026-08-20-verdict.md").write_text(
        "# Verdict\n\nScored the change against the rubrics.\n")
    (curated / "decisions.md").write_text("# Decisions\n\nWe decided things.\n")
    p = write_cfg(tmp_path, **{
        "embed_model": "test-embed", "embed_dim": DIM,
        "db_path": str(tmp_path / "memory-index" / "memory.db"),
        "transcripts_glob": str(tmp_path / "no-transcripts" / "*.jsonl"),
        "curated_docs": [str(curated)],
        "repo_roots": [],
    })
    return load_config(p)


def test_indexing_stores_judge_doc_for_verdict_files(tmp_path):
    cfg = judge_corpus_cfg(tmp_path)
    run_index(cfg, embedder=stub_embedder, digester=stub_digester,
              progress=lambda _: None)
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    types = dict(conn.execute(
        "SELECT file_path, source_type FROM chunks GROUP BY file_path"))
    conn.close()
    verdict = next(p for p in types if p.endswith("2026-08-20-verdict.md"))
    plain = next(p for p in types if p.endswith("decisions.md"))
    assert types[verdict] == "judge_doc"
    assert types[plain] == "curated_doc"
