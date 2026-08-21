import json
from pathlib import Path

import pytest

from memsearch.config import Config, ConfigError, is_excluded, load_config

REAL_CONFIG = Path(__file__).resolve().parent.parent / "config.json"


def write_cfg(tmp_path: Path, **overrides) -> Path:
    base = json.loads(REAL_CONFIG.read_text())
    base.update(overrides)
    p = tmp_path / "config.json"
    p.write_text(json.dumps(base))
    return p


def test_loads_real_config():
    cfg = load_config(REAL_CONFIG)
    assert isinstance(cfg, Config)
    assert cfg.embed_dim == 1024
    assert cfg.db_path.is_absolute()
    assert all(p.is_absolute() for p in cfg.curated_docs)
    assert cfg.weights["curated_doc"] > cfg.weights["transcript_digest"]


def test_cloud_model_refused(tmp_path):
    p = write_cfg(tmp_path, digest_model="deepseek-v4-pro:cloud")
    with pytest.raises(ConfigError, match="cloud"):
        load_config(p)


def test_cloud_embed_model_refused(tmp_path):
    p = write_cfg(tmp_path, embed_model="some-embedder:cloud")
    with pytest.raises(ConfigError, match="cloud"):
        load_config(p)


def test_is_excluded():
    cfg = load_config(REAL_CONFIG)
    assert not is_excluded(Path("/x/repo/CODING_MEMORY.md"), cfg)
    assert is_excluded(Path("/x/projects/p/abc/subagents/agent-1.jsonl"), cfg)
    assert not is_excluded(Path("/x/coding-memory/decisions.md"), cfg)
    # vendored/venv docs (smoke backfill pulled ~50 junk chunks from these)
    assert is_excluded(
        Path("/x/Snatch-Bracket/backend/.venv/bin/activate"), cfg)
    assert is_excluded(
        Path("/x/Snatch-Bracket/backend/lib/site-packages/fastapi/LICENSE.md"),
        cfg)


def test_real_config_weights_cover_every_known_source_type():
    from memsearch.config import SOURCE_TYPES
    cfg = load_config(REAL_CONFIG)
    assert set(SOURCE_TYPES) <= set(cfg.weights)
    assert cfg.weights["judge_doc"] == 1.2


def test_weights_missing_a_known_source_type_is_refused(tmp_path):
    """A missing key must fail at load with a named message, not surface as a
    KeyError halfway through a query (ADR 0030)."""
    p = write_cfg(tmp_path, weights={
        "curated_doc": 1.5, "repo_doc": 1.2,
        "transcript_digest": 1.0, "archive_doc": 1.0})
    with pytest.raises(ConfigError, match="judge_doc"):
        load_config(p)


def test_non_numeric_weight_is_refused(tmp_path):
    p = write_cfg(tmp_path, weights={
        "curated_doc": "heavy", "repo_doc": 1.2, "judge_doc": 1.2,
        "transcript_digest": 1.0, "archive_doc": 1.0})
    with pytest.raises(ConfigError, match="curated_doc"):
        load_config(p)
