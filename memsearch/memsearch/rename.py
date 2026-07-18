"""Repo rename: rewrite display metadata in place. Content hashes, repo_id,
and vectors are keyed on content, not path — a rename re-embeds nothing."""
from __future__ import annotations

from memsearch import db as dbmod
from memsearch.config import Config


def rename_repo(cfg: Config, old: str, new: str) -> dict:
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    old_seg, new_seg = f"/{old}/", f"/{new}/"
    with conn:
        chunks_renamed = conn.execute(
            "UPDATE chunks SET repo_name=? WHERE repo_name=?",
            (new, old)).rowcount
        paths = conn.execute(
            "UPDATE chunks SET file_path=REPLACE(file_path, ?, ?) "
            "WHERE file_path LIKE ?",
            (old_seg, new_seg, f"%{old_seg}%")).rowcount
        sources = conn.execute(
            "UPDATE sources SET path=REPLACE(path, ?, ?) WHERE path LIKE ?",
            (old_seg, new_seg, f"%{old_seg}%")).rowcount
    conn.close()
    return {"chunks_renamed": chunks_renamed, "paths_rewritten": paths,
            "sources_rewritten": sources}
