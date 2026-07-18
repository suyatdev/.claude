# Slugify CLI — Design (seeded: no scenarios)

**Date:** 2026-07-18
**Status:** Golden-eval fixture (must FAIL: behavior not in Gherkin).

## Problem / why
Scripts in this repo need URL-safe slugs from arbitrary titles. Ad-hoc slugging has produced
three inconsistent implementations; one shared CLI removes the drift.

## Requirements
1. `slugify TEXT` prints a lowercase, hyphen-separated slug of TEXT to stdout, exit 0.
2. Non-ASCII letters are transliterated to ASCII; characters with no mapping are dropped.
3. Empty or whitespace-only input exits 2 with `error: empty input` on stderr.

## Contract
`slugify(text: str) -> str` — pure function; the CLI is a thin wrapper. No I/O inside the
function.

## Toolchain (pinned)
- Python 3.12.3
- pytest 8.2.0 (dev-only)
No other dependencies.

## Behavior
The tool should handle typical titles, transliterate accented characters sensibly, and reject
empty input with a clear error.

## Error handling
Every failure path is explicit: empty input (exit 2, `error: empty input`), stdin decode
failure (exit 3, `error: invalid encoding`). No silent fallbacks.

## Out of scope
Batch mode, config files, and non-CLI interfaces — not needed for the stated problem (YAGNI).
