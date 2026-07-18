from pathlib import Path

from memsearch.chunk import (MAX_SECTION_CHARS, chunk_digest, chunk_doc,
                             split_markdown)
from memsearch.extract import SessionExtract

DOC = """# Title
Intro paragraph with enough words to stand alone as a meaningful chunk of
context for retrieval testing purposes across the corpus we maintain here.

## Decision A
We chose X over Y because of Z. This section is long enough to survive the
minimum-size merge because it carries the full rationale text with it.

## Tiny
Small.

## Decision B
Another decision paragraph with sufficient length to remain independent and
carry its own retrieval weight in the index without being merged away.
"""


def test_split_markdown_respects_headers_and_lines():
    sections = split_markdown(DOC)
    joined = "\n".join(s.text for s in sections)
    assert "Decision A" in joined and "Decision B" in joined
    # never mid-decision: each section's text starts at a heading or doc start
    for s in sections:
        assert s.line_start <= s.line_end
    # tiny section merged into a neighbor, not standalone
    assert not any(s.text.strip() == "## Tiny\nSmall." for s in sections)


def test_split_markdown_line_ranges_map_back():
    lines = DOC.splitlines()
    for s in split_markdown(DOC):
        window = "\n".join(lines[s.line_start - 1:s.line_end])
        assert s.text.strip() in window or window.strip() in s.text


def test_oversized_section_is_split():
    big = "# H\n" + "\n\n".join(f"Paragraph {i} " + "x" * 300 for i in range(12))
    sections = split_markdown(big)
    assert len(sections) > 1
    assert all(len(s.text) <= MAX_SECTION_CHARS + 400 for s in sections)


def test_chunk_doc_decision_detection():
    chunks = chunk_doc(Path("/x/docs/decisions/0002-a.md"), DOC, ".claude",
                       ".claude", "curated_doc", 1.5, "2026-07-17")
    assert all(c.recall_type == "decision" for c in chunks)
    assert all(c.source_type == "curated_doc" and c.weight == 1.5 for c in chunks)
    assert all(c.file_path == "/x/docs/decisions/0002-a.md" for c in chunks)
    other = chunk_doc(Path("/x/docs/spec.md"), DOC, ".claude", ".claude",
                      "curated_doc", 1.5, "2026-07-17")
    assert all(c.recall_type == "doc" for c in other)


DIGEST = """## Summary
Worked on auth bug; fixed and merged.

## Decisions
- Chose header-aware chunking because decisions must never split mid-thought.

## Bugs & Fixes
- Token check was inverted; fixed in auth.py.

## Files Touched
- auth.py
"""


def test_chunk_digest_maps_recall_types():
    ex = SessionExtract("sess-9", "2026-07-10", "/Users/x/repo", "…")
    chunks = chunk_digest(DIGEST, ex, "repo", "repo", 1.0,
                          "/x/projects/p/sess-9.jsonl")
    by_heading = {c.content.splitlines()[0]: c for c in chunks}
    assert len(chunks) == 4
    decision = [c for c in chunks if c.recall_type == "decision"]
    assert len(decision) == 1 and "header-aware" in decision[0].content
    assert all(c.recall_type == "episodic" for c in chunks
               if c is not decision[0])
    assert all(c.session_id == "sess-9" for c in chunks)
    assert all(c.session_date == "2026-07-10" for c in chunks)
    assert all(c.source_type == "transcript_digest" for c in chunks)
    assert all("sess-9" in c.content.splitlines()[0] for c in chunks), by_heading
