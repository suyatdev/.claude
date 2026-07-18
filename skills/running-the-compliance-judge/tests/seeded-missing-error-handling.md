# Slugify CLI — Design (seeded: no error handling)

**Date:** 2026-07-18
**Status:** Golden-eval fixture (must FAIL: error handling unstated).

## Problem / why
Scripts in this repo need URL-safe slugs from arbitrary titles. Ad-hoc slugging has produced
three inconsistent implementations; one shared CLI removes the drift.

## Requirements
1. `slugify TEXT` prints a lowercase, hyphen-separated slug of TEXT to stdout, exit 0.
2. Non-ASCII letters are transliterated to ASCII; characters with no mapping are dropped.
3. Bad input is handled appropriately.

## Contract
`slugify(text: str) -> str` — pure function; the CLI is a thin wrapper. No I/O inside the
function.

## Toolchain (pinned)
- Python 3.12.3
- pytest 8.2.0 (dev-only)
No other dependencies.

## Scenarios
```gherkin
Scenario: Basic title
  Given the input "Hello, World!"
  When slugify runs
  Then stdout is "hello-world" and the exit code is 0

Scenario: Transliteration
  Given the input "Crème Brûlée"
  When slugify runs
  Then stdout is "creme-brulee"
```

## Out of scope
Batch mode, config files, and non-CLI interfaces — not needed for the stated problem (YAGNI).
