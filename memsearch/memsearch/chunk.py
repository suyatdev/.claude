"""Chunkers. Markdown is split at H1-H3 boundaries — never mid-section, so a
decision's rationale always travels with its heading. Digests split per H2
section, each mapped to a recall_type. Every chunk carries provenance."""
from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from memsearch.db import Chunk
from memsearch.extract import SessionExtract

MAX_SECTION_CHARS = 2000
MIN_SECTION_CHARS = 200
_HEADING = re.compile(r"^#{1,3}\s")


@dataclass(frozen=True)
class Section:
    heading: str
    text: str
    line_start: int  # 1-based inclusive
    line_end: int


def split_markdown(text: str) -> list[Section]:
    lines = text.splitlines()
    starts = [i for i, ln in enumerate(lines) if _HEADING.match(ln)]
    if not starts or starts[0] != 0:
        starts = [0] + starts
    starts.append(len(lines))
    raw: list[Section] = []
    for a, b in zip(starts, starts[1:]):
        body = "\n".join(lines[a:b]).strip()
        if not body:
            continue
        heading = lines[a].lstrip("#").strip() if _HEADING.match(lines[a]) else ""
        raw.append(Section(heading, body, a + 1, b))
    return _split_oversized(_merge_tiny(raw))


def _merge_tiny(sections: list[Section]) -> list[Section]:
    merged: list[Section] = []
    for s in sections:
        prev = merged[-1] if merged else None
        if (prev and len(s.text) < MIN_SECTION_CHARS
                and len(prev.text) + len(s.text) <= MAX_SECTION_CHARS):
            merged[-1] = Section(prev.heading, prev.text + "\n\n" + s.text,
                                 prev.line_start, s.line_end)
        else:
            merged.append(s)
    return merged


def _hard_split(text: str, max_chars: int) -> list[str]:
    """Force-split text into pieces of at most max_chars each: prefer the
    last newline before the cap, fall back to an exact-length cut when the
    text has no newline to break on (e.g. one dense, unbroken paragraph).
    Pieces concatenate back into `text` with no separator — no data lost."""
    pieces: list[str] = []
    while len(text) > max_chars:
        cut = text.rfind("\n", 0, max_chars)
        cut = cut + 1 if cut > 0 else max_chars
        pieces.append(text[:cut])
        text = text[cut:]
    pieces.append(text)
    return pieces


def _split_oversized(sections: list[Section]) -> list[Section]:
    out: list[Section] = []
    for s in sections:
        if len(s.text) <= MAX_SECTION_CHARS:
            out.append(s)
            continue
        paras = s.text.split("\n\n")
        buf: list[str] = []
        line_cursor = s.line_start

        def emit(piece: str, cursor: int) -> int:
            n_lines = piece.count("\n") + 2  # + blank separator line
            end = min(cursor + n_lines - 1, s.line_end)
            if len(piece) <= MAX_SECTION_CHARS:
                out.append(Section(s.heading, piece, cursor, end))
                return min(cursor + n_lines, s.line_end)
            # Paragraph splitting alone wasn't enough — e.g. a dense ledger
            # with no blank lines collapses to one giant "paragraph". Hard
            # split it so every emitted chunk stays under the embed API's
            # size limit; line numbers are recomputed exactly per part
            # rather than by the heuristic above, since we now hold the
            # real substrings.
            for part in _hard_split(piece, MAX_SECTION_CHARS):
                part_lines = part.count("\n") + 1
                part_end = min(cursor + part_lines - 1, s.line_end)
                out.append(Section(s.heading, part, cursor, part_end))
                cursor = min(cursor + part_lines, s.line_end)
            return cursor

        for para in paras:
            if buf and len("\n\n".join(buf)) + len(para) > MAX_SECTION_CHARS:
                line_cursor = emit("\n\n".join(buf), line_cursor)
                buf = []
            buf.append(para)
        if buf:
            line_cursor = emit("\n\n".join(buf), line_cursor)
    return out


def chunk_doc(path: Path, text: str, repo_id: str, repo_name: str,
              source_type: str, weight: float, session_date: str) -> list[Chunk]:
    recall = "decision" if "decisions" in str(path) else "doc"
    return [
        Chunk(content=s.text, repo_id=repo_id, repo_name=repo_name,
              source_type=source_type, recall_type=recall,
              session_date=session_date, file_path=str(path),
              line_start=s.line_start, line_end=s.line_end,
              session_id=None, weight=weight)
        for s in split_markdown(text)
    ]


def chunk_digest(digest_md: str, extract: SessionExtract, repo_id: str,
                 repo_name: str, weight: float,
                 transcript_path: str) -> list[Chunk]:
    # One chunk per H2 section, split directly — digest sections are small by
    # design, so split_markdown's tiny-section merge would wrongly collapse them.
    context = (f"[session {extract.session_id} · {extract.session_date} · "
               f"repo {repo_name}]")
    lines = digest_md.splitlines()
    starts = [i for i, ln in enumerate(lines) if ln.startswith("## ")]
    if not starts or starts[0] != 0:
        starts = [0] + starts
    starts.append(len(lines))
    chunks: list[Chunk] = []
    for a, b in zip(starts, starts[1:]):
        body = "\n".join(lines[a:b]).strip()
        if not body:
            continue
        heading = lines[a][3:].strip() if lines[a].startswith("## ") else "Summary"
        recall = ("decision" if heading.lower().startswith("decision")
                  else "episodic")
        chunks.append(Chunk(
            content=f"{context} {heading}\n{body}",
            repo_id=repo_id, repo_name=repo_name,
            source_type="transcript_digest", recall_type=recall,
            session_date=extract.session_date, file_path=transcript_path,
            line_start=a + 1, line_end=b,
            session_id=extract.session_id, weight=weight))
    return chunks
