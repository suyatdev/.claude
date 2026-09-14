#!/usr/bin/env python3
"""Extract assertion labels from the SOURCE text of a pane-dispatch test suite.

Card: docs/features/pane-dispatch-test-suite-split.md, Decision 3.

This is the SOURCE-SET half of the "nothing was lost" check: it parses the
string literal passed to every `ok "<label>"` call out of the raw shell
source (never executes it), so a set diff of the labels before/after a file
split proves no assertion was deleted -- see run-set.py for the RUN-SET half,
which proves an assertion actually executed.

Usage:
    python3 -I label-set.py FILE [FILE ...]

Prints one label per line to stdout, in source order, WITH duplicates (a
duplicate is itself a finding -- see the card's blind-spot table -- so this
tool must not silently dedupe it away; do `sort -u` downstream if a set is
wanted).

MATCH RULE
----------
Only `ok` used as a *command word* counts -- `ok` at the start of a line, or
preceded by whitespace, `&&`, `||`, `;`, or `*)` (a case-statement arm) --
never as a substring of a longer identifier (e.g. a hypothetical `mock`, or
the literal function name `ok()` in a definition or comment). This is
implemented as a negative lookbehind for a word character (`[A-Za-z0-9_]`):
anything that is NOT a letter/digit/underscore immediately before `ok`
already covers "start of line" (nothing to match => lookbehind trivially
succeeds), plain whitespace, and every listed punctuation, without having to
enumerate each shell operator by name.

The command word must then be followed by whitespace and an opening `"` --
this is what excludes the `ok()` definition line, the `printf 'ok   - ...'`
format string inside ok()/bad(), and prose mentions like "`ok`." in a
comment, none of which have `ok` immediately followed by `\s+"`.

STRING RULE -- escape-aware, on purpose
----------------------------------------
The quoted-string body uses `(?:[^"\\]|\\.)*`, not a naive `[^"]*`. Two real
labels in dispatch-pane-agent.test.sh contain an escaped quote:

    ok "--model \"a b\" (shape-invalid) -> non-zero exit"
    ok "--model \"a b\" -> no pane opened"

A naive `ok "[^"]*"` rule stops at the first `\"`, truncates both labels to
`--model \`, and reports 138 distinct labels with one duplicate -- a false
finding (measured 2026-09-07, reproduced by this script's own falsification
test; see the card). `(?:[^"\\]|\\.)*` consumes an escaped character (any
`\` followed by one more character) as a single unit, so the string body
runs all the way to the real closing quote.

EMITTED VALUE -- unescaped, deliberately
-----------------------------------------
Each label is emitted UNESCAPED (`\"` -> `"`, and generally `\X` -> `X` for
any escaped character), not as the raw source bytes. This is required for
SOURCE-SET to be directly diffable against RUN-SET: when bash actually
executes `ok "--model \"a b\" ..."`, the shell itself performs this exact
unescaping before `$1` ever reaches `ok()`, so runtime stdout carries the
unescaped text. Emitting raw source text here would make the two sets
permanently non-comparable for any label that contains an escape. Verified
by running the real suite and diffing this tool's output against run-set.py's
output over its captured stdout (see the card, Decision 3 cross-check).

WHAT THIS CANNOT SEE
---------------------
This only reads `ok` calls. It says nothing about whether the file was ever
invoked by a runner (that is what RUN-SET is for), and nothing about whether
a test body still exercises what its label claims (Decision 3's blind-spot
table; not this tool's job).
"""
import re
import sys

# `ok` as a command word: not glued to a preceding identifier character.
# Whitespace, start-of-line, `&&`, `||`, `;`, and `*)` are all covered
# because none of their last characters is a letter/digit/underscore.
_NOT_WORD_BEFORE = r"(?<![A-Za-z0-9_])"
_DQ_STRING_BODY = r'(?:[^"\\]|\\.)*'
OK_CALL_RE = re.compile(_NOT_WORD_BEFORE + r'ok\s+"(' + _DQ_STRING_BODY + r')"')

_ESCAPE_RE = re.compile(r"\\(.)")


def unescape(raw_label):
    """Undo backslash-escaping the way bash does inside a double-quoted
    string: `\\X` -> `X` for any character X. Only `\"` is attested in the
    current suite; this is written generally because that is what bash
    itself does, not because other escapes are expected."""
    return _ESCAPE_RE.sub(r"\1", raw_label)


def extract_labels(source_text):
    return [unescape(m.group(1)) for m in OK_CALL_RE.finditer(source_text)]


def main(argv):
    if not argv:
        print("usage: label-set.py FILE [FILE ...]", file=sys.stderr)
        return 2

    for path in argv:
        try:
            with open(path, "r", encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            print(f"label-set.py: cannot read {path}: {exc}", file=sys.stderr)
            return 1

        for label in extract_labels(text):
            print(label)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
