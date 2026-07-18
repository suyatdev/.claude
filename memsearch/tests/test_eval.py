from memsearch import db as dbmod
from memsearch.config import load_config
from memsearch.eval import audit_digests
from tests.conftest import DIM, make_chunk, vec
from tests.test_config import write_cfg
from tests.test_extract import BASE, jl


def make_cfg_with_digests(tmp_path, n=5):
    proj = tmp_path / "projects" / "-x-repo"
    proj.mkdir(parents=True)
    cfg = load_config(write_cfg(tmp_path, **{
        "embed_model": "test-embed", "embed_dim": DIM,
        "db_path": str(tmp_path / "mi" / "memory.db"),
        "transcripts_glob": str(proj) + "/*.jsonl"}))
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    for i in range(n):
        p = proj / f"sess-{i}.jsonl"
        p.write_text(jl(type="user",
                        message={"role": "user", "content": f"work {i}"},
                        **BASE) + "\n" +
                     jl(type="assistant", message={"role": "assistant",
                        "content": [{"type": "text", "text": f"done {i}"}]},
                        **BASE) + "\n")
        dbmod.replace_source(conn, str(p), "transcript", f"h{i}", [make_chunk(
            content=f"[session sess-{i}] Summary\nDid work {i}.",
            source_type="transcript_digest", recall_type="episodic",
            session_id=f"sess-{i}", file_path=str(p))], [vec(1.0)])
    conn.close()
    return cfg


def test_sampling_is_deterministic(tmp_path):
    cfg = make_cfg_with_digests(tmp_path)
    seen = []

    def fake_chat(prompt, model, base_url, system=None, **kw):
        seen.append(prompt)
        return "SUPPORTED"

    r1 = audit_digests(cfg, sample=3, seed=42, chat=fake_chat,
                       report_dir=tmp_path / "evals")
    seen2 = []

    def fake_chat2(prompt, model, base_url, system=None, **kw):
        seen2.append(prompt)
        return "SUPPORTED"

    r2 = audit_digests(cfg, sample=3, seed=42, chat=fake_chat2,
                       report_dir=tmp_path / "evals")
    assert r1["sampled"] == r2["sampled"] == 3
    assert seen == seen2  # same seed -> same sessions in same order


def test_unsupported_claims_flagged_and_report_written(tmp_path):
    cfg = make_cfg_with_digests(tmp_path, n=2)

    def fake_chat(prompt, model, base_url, system=None, **kw):
        if "sess-0" in prompt:
            return "UNSUPPORTED: claims a refactor the transcript never shows"
        return "SUPPORTED"

    r = audit_digests(cfg, sample=2, seed=1, chat=fake_chat,
                      report_dir=tmp_path / "evals")
    assert r["sampled"] == 2
    assert r["unsupported"] == ["sess-0"]
    assert r["supported"] == 1
    report = r["report_path"].read_text()
    assert "sess-0" in report and "UNSUPPORTED" in report


def test_sample_larger_than_population(tmp_path):
    cfg = make_cfg_with_digests(tmp_path, n=2)
    r = audit_digests(cfg, sample=10, seed=1,
                      chat=lambda *a, **k: "SUPPORTED",
                      report_dir=tmp_path / "evals")
    assert r["sampled"] == 2
