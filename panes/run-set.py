#!/usr/bin/env python3
"""Extract assertion labels from the captured RUNTIME stdout of a pane-dispatch
test suite (the RUN-SET half of Decision 3's "nothing was lost" check --
docs/features/pane-dispatch-test-suite-split.md).

Where label-set.py proves a label was never deleted from the *source*, this
proves a label actually *ran*: it reads stdout already emitted by the two
helpers in dispatch-pane-agent.test.sh --

    ok()   { printf 'ok   - %s\\n' "$1"; pass=$((pass+1)); }
    bad()  { printf 'FAIL - %s%s\\n' "$1" "${2:+ ($2)}"; fail=$((fail+1)); }

(the real separator both print is an EM DASH, U+2014, not a hyphen -- shown
as "-" above only because this docstring is plain ASCII) -- and prints one
label per line, stripping the leading prefix. A `FAIL <em dash> <label>` line
still counts as the assertion having RUN (it ran and failed, which is a
different fact from "was deleted"); counting only `ok` lines would make a
genuinely failing assertion look indistinguishable from one that was lost.

Usage:
    python3 -I run-set.py [FILE ...]

With no arguments, reads captured stdout from stdin. With one or more file
arguments, reads and concatenates those files instead. (Both are supported
because the two real call sites differ: the cross-check in the card pipes a
freshly captured run's stdout in; a saved capture on disk is more convenient
to pass by path when re-diagnosing a mismatch after the fact.)

STRIPPING RULE
--------------
`ok` lines: strip the fixed prefix `ok   - ` (three spaces, per the literal
format string) and nothing else. `ok()` NEVER appends anything past `$1`, so
the rest of the line *is* the label verbatim -- including a label that itself
ends in a literal parenthetical. 21 real labels in the current suite end in
`)` this way, e.g. `"tab-failure streak 3 -> exit 4 (adapter cannot tab)"`;
none of that text is ever touched.

`FAIL` lines: strip the fixed prefix `FAIL - ` (one space either side of the
em dash), then remove a trailing detail parenthetical IF ONE IS PRESENT.
`bad()` appends `${2:+ ($2)}` -- a literal space, `(`, the second argument,
`)` -- only when a second argument was actually passed; with no second
argument the line is exactly the label, same as `ok`.

The stripped-off span is found by scanning from the END of the line for a
balanced parenthesized group, matching `)` and `(` by depth rather than a
non-nesting regex, because at least one real `bad()` call's OWN detail
argument contains a nested parenthetical:

    bad "no-target overflow adds no phantom" "got $n want 1 (the surfaceless fixture only)"

which prints as
    FAIL - no-target overflow adds no phantom (got $n want 1 (the surfaceless fixture only))

A regex requiring no inner parens (` \\([^()]*\\)$`) cannot match that whole
outer group; the depth-counting scan can, because it tracks nesting rather
than assuming there is none.

WHAT THIS RULE CANNOT HANDLE
-----------------------------
It is structurally impossible to tell, from the printed line alone, "a label
that legitimately ends in a real `)` with no `bad()` detail" apart from "a
label plus an appended detail" -- both look like `text (more text)`. This
tool resolves the ambiguity by always treating a trailing balanced
parenthetical on a FAIL line as an appended detail, which is correct for
every `bad()` call in the current suite (checked by hand: every `bad "..."`
call in dispatch-pane-agent.test.sh whose *first argument* ends in `)` also
passes a second argument, so the trailing group in its printed output is
always the appended detail, never the tail of a bare label -- see the card's
falsification section). If a future single-argument `bad()` call is added
whose label itself ends in a real parenthetical, this rule will mis-strip it;
that is a known limitation, not a silent one.
"""
import sys

OK_PREFIX = "ok   — "
FAIL_PREFIX = "FAIL — "


def strip_trailing_paren_detail(text):
    """If `text` ends with a balanced `(...)` group preceded by a space,
    return the text with that group (and the separating space) removed.
    Otherwise return `text` unchanged. Depth-counts parens from the end so a
    detail argument that itself contains `(...)` is still matched as one
    outer group."""
    if not text.endswith(")"):
        return text

    depth = 0
    i = len(text) - 1
    while i >= 0:
        if text[i] == ")":
            depth += 1
        elif text[i] == "(":
            depth -= 1
            if depth == 0:
                break
        i -= 1

    found_matching_open = i >= 0 and depth == 0
    preceded_by_space = found_matching_open and i > 0 and text[i - 1] == " "
    if preceded_by_space:
        return text[: i - 1]
    return text


def extract_labels(lines):
    labels = []
    for line in lines:
        line = line.rstrip("\n")
        if line.startswith(OK_PREFIX):
            labels.append(line[len(OK_PREFIX):])
        elif line.startswith(FAIL_PREFIX):
            body = line[len(FAIL_PREFIX):]
            labels.append(strip_trailing_paren_detail(body))
    return labels


def main(argv):
    if argv:
        lines = []
        for path in argv:
            try:
                with open(path, "r", encoding="utf-8") as fh:
                    lines.extend(fh.readlines())
            except OSError as exc:
                print(f"run-set.py: cannot read {path}: {exc}", file=sys.stderr)
                return 1
    else:
        lines = sys.stdin.readlines()

    for label in extract_labels(lines):
        print(label)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
