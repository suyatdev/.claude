"""Session digesting: the one LLM step in the pipeline. The digest is DATA
with provenance, never instructions — the system prompt forbids speculation
and the chunker attaches the source transcript path to every claim."""
from __future__ import annotations

from memsearch import ollama
from memsearch.config import Config
from memsearch.extract import SessionExtract

DIGEST_SYSTEM = (
    "You write terse, factual engineering session digests. State only what "
    "the transcript supports — no speculation, no invented details. If a "
    "section has nothing, write 'None.'")

_TEMPLATE = """Summarize this coding session transcript into a digest with \
exactly these markdown sections:

## Summary
2-4 sentences: what was worked on and the outcome.

## Decisions
Bullets: each decision made, and why. 'None.' if none.

## Bugs & Fixes
Bullets: each bug hit and how it was fixed. 'None.' if none.

## Files Touched
Bullets: key files or components changed. 'None.' if none.

Transcript:
---
{transcript}
---"""

_TRUNCATION_MARK = "\n\n[... transcript middle truncated for digest ...]\n\n"


def truncate_middle(text: str, cap: int) -> str:
    if len(text) <= cap:
        return text
    half = max(1, cap // 2)
    return text[:half] + _TRUNCATION_MARK + text[-half:]


def build_prompt(extract: SessionExtract, char_cap: int) -> str:
    return _TEMPLATE.format(transcript=truncate_middle(extract.text, char_cap))


def digest_session(extract: SessionExtract, cfg: Config,
                   chat=ollama.chat) -> str:
    return chat(build_prompt(extract, cfg.digest_input_char_cap),
                cfg.digest_model, cfg.ollama_url, system=DIGEST_SYSTEM)
