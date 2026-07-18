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


def test_coding_memory_exclusion_is_mandatory(tmp_path):
    p = write_cfg(tmp_path, exclude_paths=["/subagents/"])
    with pytest.raises(ConfigError, match="CODING_MEMORY"):
        load_config(p)


def test_is_excluded():
    cfg = load_config(REAL_CONFIG)
    assert is_excluded(Path("/x/repo/CODING_MEMORY.md"), cfg)
    assert is_excluded(Path("/x/projects/p/abc/subagents/agent-1.jsonl"), cfg)
    assert not is_excluded(Path("/x/coding-memory/decisions.md"), cfg)
