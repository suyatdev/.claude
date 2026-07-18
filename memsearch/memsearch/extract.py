"""Deterministic transcript extraction: session JSONL -> clean user/assistant
text. Drops tool payloads, system-reminders, thinking, sidechains, meta lines;
keeps tool NAMES as light signal. This is the 251 MB -> ~20 MB step — no LLM."""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

_STRIP_BLOCKS = re.compile(
    r"<system-reminder>.*?</system-reminder>"
    r"|<local-command-caveat>.*?</local-command-caveat>",
    re.DOTALL)
_FALLBACK_DATE = "1970-01-01"


@dataclass(frozen=True)
class SessionExtract:
    session_id: str
    session_date: str  # YYYY-MM-DD from the first turn's timestamp
    cwd: str
    text: str


def _user_text(content) -> str:
    if isinstance(content, str):
        return _STRIP_BLOCKS.sub("", content).strip()
    if isinstance(content, list):
        # Real user lines can carry list content mixing genuine text blocks
        # with tool_result payloads — keep the text, drop the payload noise.
        parts = [
            item["text"] for item in content
            if isinstance(item, dict) and item.get("type") == "text" and item.get("text")
        ]
        return _STRIP_BLOCKS.sub("", "\n".join(parts)).strip()
    return ""


def _assistant_text(content) -> str:
    if not isinstance(content, list):
        return ""
    parts = []
    for item in content:
        if not isinstance(item, dict):
            continue
        kind = item.get("type")
        if kind == "text" and item.get("text"):
            parts.append(item["text"])
        elif kind == "tool_use":
            parts.append(f"[tool: {item.get('name', '?')}]")
    return "\n".join(parts).strip()


def extract_session(path: Path) -> SessionExtract | None:
    cwd, first_ts = "", ""
    turns: list[str] = []
    with path.open() as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(d, dict):
                continue
            kind = d.get("type")
            if kind not in ("user", "assistant"):
                continue
            if d.get("isSidechain") or d.get("isMeta"):
                continue
            cwd = cwd or d.get("cwd", "")
            first_ts = first_ts or d.get("timestamp", "")
            content = (d.get("message") or {}).get("content")
            text = _user_text(content) if kind == "user" else _assistant_text(content)
            if text:
                turns.append(("User: " if kind == "user" else "Assistant: ") + text)
    if not turns:
        return None
    return SessionExtract(
        session_id=path.stem,
        session_date=first_ts[:10] or _FALLBACK_DATE,
        cwd=cwd,
        text="\n\n".join(turns),
    )
