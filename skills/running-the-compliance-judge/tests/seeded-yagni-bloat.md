# Slugify CLI — Design (seeded: speculative scope)

**Date:** 2026-07-18
**Status:** Golden-eval fixture (must FAIL: YAGNI).

## Problem / why
Scripts in this repo need URL-safe slugs from arbitrary titles. Ad-hoc slugging has produced
three inconsistent implementations; one shared CLI removes the drift.

## Requirements
1. `slugify TEXT` prints a lowercase, hyphen-separated slug of TEXT to stdout, exit 0.
2. Non-ASCII letters are transliterated to ASCII; characters with no mapping are dropped.
3. Empty or whitespace-only input exits 2 with `error: empty input` on stderr.
4. A plugin architecture so future transliteration providers can be swapped in at runtime.
5. An i18n message catalog for error strings, for future localization needs.
6. A TOML configuration DSL controlling separator, casing, and future options.

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

Scenario: Empty input is an error
  Given the input "   "
  When slugify runs
  Then the exit code is 2 and stderr is "error: empty input"
```

## Error handling
Every failure path is explicit: empty input (exit 2, `error: empty input`), stdin decode
failure (exit 3, `error: invalid encoding`). No silent fallbacks.
