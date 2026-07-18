"""Repo rename: rewrite display metadata in place. Content hashes, repo_id,
and vectors are keyed on content, not path — a rename re-embeds nothing."""
from __future__ import annotations

from memsearch import db as dbmod
from memsearch.config import Config

LIKE_ESCAPE_CHAR = "\\"


def _like_escape(segment: str) -> str:
    """Escape SQL LIKE wildcards (%, _) and the escape char itself, so a
    literal path segment like '/my_repo/' can't accidentally wildcard-match
    an unrelated path (e.g. '/myXrepo/', since '_' means "any one char")."""
    return (segment
            .replace(LIKE_ESCAPE_CHAR, LIKE_ESCAPE_CHAR * 2)
            .replace("%", LIKE_ESCAPE_CHAR + "%")
            .replace("_", LIKE_ESCAPE_CHAR + "_"))


def rename_repo(cfg: Config, old: str, new: str) -> dict:
    if not cfg.db_path.exists():
        raise SystemExit("memsearch: no index found — run: memsearch index")
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    old_seg, new_seg = f"/{old}/", f"/{new}/"
    like_pattern = f"%{_like_escape(old_seg)}%"
    with conn:
        chunks_renamed = conn.execute(
            "UPDATE chunks SET repo_name=? WHERE repo_name=?",
            (new, old)).rowcount
        paths = conn.execute(
            "UPDATE chunks SET file_path=REPLACE(file_path, ?, ?) "
            "WHERE file_path LIKE ? ESCAPE '\\'",
            (old_seg, new_seg, like_pattern)).rowcount
        sources = conn.execute(
            "UPDATE sources SET path=REPLACE(path, ?, ?) "
            "WHERE path LIKE ? ESCAPE '\\'",
            (old_seg, new_seg, like_pattern)).rowcount
    conn.close()
    return {"chunks_renamed": chunks_renamed, "paths_rewritten": paths,
            "sources_rewritten": sources}
