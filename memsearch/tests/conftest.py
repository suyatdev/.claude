import pytest

from memsearch import db as dbmod

DIM = 4  # tiny test dimension; production dim comes from config


def vec(*vals: float) -> list[float]:
    v = list(vals) + [0.0] * (DIM - len(vals))
    return v[:DIM]


def make_chunk(**overrides) -> dbmod.Chunk:
    base = dict(
        content="We chose SQLite over Qdrant for zero idle RAM.",
        repo_id=".claude",
        repo_name=".claude",
        source_type="curated_doc",
        recall_type="decision",
        session_date="2026-07-17",
        file_path="/x/docs/decisions/0002-sqlite-over-qdrant.md",
        line_start=1,
        line_end=10,
        session_id=None,
        weight=1.5,
    )
    base.update(overrides)
    return dbmod.Chunk(**base)


@pytest.fixture
def conn(tmp_path):
    c = dbmod.connect(tmp_path / "m.db", "test-embed", DIM)
    yield c
    c.close()
