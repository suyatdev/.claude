"""Systematic digest-accuracy audit (observability-judge flag b): a scripted,
seeded, repeatable check — not a vibe spot-check. Each sampled digest is
verified against its re-extracted source transcript by the local digest
model; results are persisted under coding-memory/memsearch-evals/."""
from __future__ import annotations

import random
from datetime import date
from pathlib import Path

from memsearch import db as dbmod
from memsearch import ollama
from memsearch.config import Config
from memsearch.digest import truncate_middle
from memsearch.extract import extract_session

VERIFY_SYSTEM = (
    "You verify a session digest against its source transcript. Reply with "
    "exactly 'SUPPORTED' if every digest claim is supported by the "
    "transcript; otherwise reply 'UNSUPPORTED: <each unsupported claim>'.")

_VERIFY_TEMPLATE = """Digest for session {sid}:
---
{digest}
---

Source transcript (extracted):
---
{transcript}
---"""

DEFAULT_REPORT_DIR = Path.home() / ".claude" / "coding-memory" / "memsearch-evals"


def audit_digests(cfg: Config, sample: int = 12, seed: int = 17,
                  chat=ollama.chat, report_dir: Path | None = None) -> dict:
    conn = dbmod.connect(cfg.db_path, cfg.embed_model, cfg.embed_dim)
    sessions = conn.execute(
        "SELECT session_id, file_path, group_concat(content, char(10)) "
        "FROM chunks WHERE source_type='transcript_digest' "
        "GROUP BY session_id, file_path ORDER BY session_id").fetchall()
    conn.close()
    rng = random.Random(seed)
    picked = (sessions if len(sessions) <= sample
              else rng.sample(sessions, sample))
    picked = sorted(picked, key=lambda r: r[0])

    unsupported: list[str] = []
    rows: list[str] = []
    for sid, path, digest_text in picked:
        extract = extract_session(Path(path))
        transcript = extract.text if extract else "(transcript unreadable)"
        verdict = chat(
            _VERIFY_TEMPLATE.format(
                sid=sid, digest=digest_text,
                transcript=truncate_middle(transcript,
                                           cfg.digest_input_char_cap)),
            cfg.digest_model, cfg.ollama_url, system=VERIFY_SYSTEM)
        ok = verdict.strip().upper().startswith("SUPPORTED")
        if not ok:
            unsupported.append(sid)
        rows.append(f"## {sid}\n- source: `{path}`\n- verdict: {verdict}\n")

    report_dir = report_dir or DEFAULT_REPORT_DIR
    report_dir.mkdir(parents=True, exist_ok=True)
    report_path = report_dir / f"digest-audit-{date.today().isoformat()}.md"
    report_path.write_text(
        f"# Digest accuracy audit — {date.today().isoformat()}\n\n"
        f"- model: {cfg.digest_model}\n- sampled: {len(picked)} "
        f"(seed={seed})\n- unsupported: {len(unsupported)}\n\n"
        + "\n".join(rows))
    return {"sampled": len(picked), "supported": len(picked) - len(unsupported),
            "unsupported": unsupported, "report_path": report_path}
