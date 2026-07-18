"""Config loading + validation. All model choice is gated here: cloud-backed
Ollama models are refused because the corpus is private conversation history."""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

DEFAULT_CONFIG_PATH = Path(__file__).resolve().parent.parent / "config.json"
_MODEL_KEYS = ("embed_model", "digest_model", "embed_fallback_model")


class ConfigError(ValueError):
    """Invalid or unsafe memsearch configuration."""


@dataclass(frozen=True)
class RepoRoot:
    id: str
    name: str
    root: Path


@dataclass(frozen=True)
class Config:
    ollama_url: str
    embed_model: str
    embed_dim: int
    digest_model: str
    digest_input_char_cap: int
    db_path: Path
    transcripts_glob: str
    curated_docs: tuple[Path, ...]
    repo_roots: tuple[RepoRoot, ...]
    exclude_paths: tuple[str, ...]
    weights: dict


def _expand(p: str) -> Path:
    return Path(p).expanduser()


def _refuse_cloud(model: str) -> None:
    if "cloud" in model.lower():
        raise ConfigError(
            f"cloud-backed model refused: {model!r} — memsearch is local-only"
        )


def load_config(path: Path | None = None) -> Config:
    path = path or DEFAULT_CONFIG_PATH
    raw = json.loads(path.read_text())
    for key in _MODEL_KEYS:
        if raw.get(key):
            _refuse_cloud(raw[key])
    excludes = tuple(raw.get("exclude_paths", ()))
    if not any("CODING_MEMORY.md" in e for e in excludes):
        raise ConfigError(
            "exclude_paths must contain CODING_MEMORY.md (ephemeral working index)"
        )
    return Config(
        ollama_url=raw["ollama_url"],
        embed_model=raw["embed_model"],
        embed_dim=int(raw["embed_dim"]),
        digest_model=raw["digest_model"],
        digest_input_char_cap=int(raw.get("digest_input_char_cap", 80_000)),
        db_path=_expand(raw["db_path"]),
        transcripts_glob=str(_expand(raw["transcripts_glob"])),
        curated_docs=tuple(_expand(p) for p in raw["curated_docs"]),
        repo_roots=tuple(
            RepoRoot(r["id"], r["name"], _expand(r["root"]))
            for r in raw.get("repo_roots", ())
        ),
        exclude_paths=excludes,
        weights=dict(raw["weights"]),
    )


def is_excluded(path: Path, cfg: Config) -> bool:
    s = str(path)
    return any(pat in s for pat in cfg.exclude_paths)
