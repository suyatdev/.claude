#!/usr/bin/env python3
"""Compare two label sets produced by label-set.py / run-set.py.

Card: docs/features/pane-dispatch-test-suite-split.md, Decision 3 and its
"Task 8 resolution" gap.

WHY THIS EXISTS
---------------
SOURCE-SET (label-set.py) and RUN-SET (run-set.py) cannot always be compared
with plain set equality. One assertion in the real suite interpolates a
shell variable into its own label:

    ok "panes max=2 bounds real panes: 6 workers opened $pc_panes pane(s), \\
never more than 2"

SOURCE-SET necessarily contains the literal text `$pc_panes`; RUN-SET
contains the runtime-substituted value (`2`). Not a defect in either
extractor -- a real difference between "the label as written" and "the
label as printed" -- so the comparator must understand placeholders rather
than the caller excluding the label or editing the suite.

INTERFACE
---------
Diff mode (compares two label files, one per line, WITH duplicates allowed
in the input -- duplicates are collapsed to sets for the diff; use count
mode, below, to check for them):

    python3 -I label-diff.py --source-set FILE --run-set FILE
    python3 -I label-diff.py --before FILE --after FILE

`--before`/`--after` are exact synonyms for `--source-set`/`--run-set`,
provided because the card also needs a SOURCE-SET-vs-SOURCE-SET comparison
(before the split vs. after it) and that reads more naturally under those
names. It is the SAME code path: a before/after comparison needs no
placeholder handling only because neither side has had its `$name` text
substituted yet, so every label on both sides is literal and the
placeholder branch is simply never entered for it.

Count mode (independent of diff mode; see REQUIREMENT 4 below):

    python3 -I label-diff.py --count FILE --expect-count N

MATCHING ALGORITHM
-------------------
1. Both inputs are read as one label per line (see "boundary errors" below
   for what counts as invalid input) and reduced to sets for the diff.
2. Literal labels (no `$name` / `${name}` reference) are matched first, by
   plain set membership, against the full right-hand set. This happens
   before any placeholder logic runs, so a literal label is never subject
   to a wildcard's false-positive risk, and it "claims" its run label so
   step 3 cannot also match something else onto it.
3. Each remaining left-hand label that DOES contain a variable reference is
   converted into an anchored regex: every `$name`/`${name}` becomes a
   wildcard (see WILDCARD RULE), everything else is escaped literally, and
   the whole thing is anchored with `^...$` (`re.fullmatch`). It is matched
   only against right-hand labels not already claimed in step 2.
4. Exactly-one matching, both directions:
   - a source pattern matching zero remaining run labels -> unmatched source
   - a source pattern matching exactly one, AND that run label matched by no
     other source pattern -> a clean placeholder match
   - a source pattern matching more than one run label -> ambiguous (source)
   - a run label matched by more than one source pattern -> ambiguous (run),
     even if each pattern individually matched only that one label
   Ambiguity is reported, never silently resolved by picking a candidate.
   One-pass conservative resolution, not a general bipartite matcher: it
   never removes an ambiguous candidate to see if the rest resolves
   cleanly. Over-reporting ambiguity is the chosen failure mode.

WILDCARD RULE, AND WHY NOT `.*`
--------------------------------
Each variable reference becomes `\\S+?` -- one or more NON-WHITESPACE
characters, non-greedy. Two restrictions, both load-bearing:

  - "one-or-more", not "zero-or-more": a placeholder must stand for
    something. An empty substitution would leave the text identical
    anyway, so requiring >=1 character costs nothing real and refuses to
    treat "the value was silently dropped" as a match.

  - `\\S` (non-whitespace), not `.` (any character): this is what stops the
    wildcard swallowing unrelated trailing text. Take source label
    "result: $x" (placeholder at the end, nothing after it to anchor
    against). With `.*`/`.+`, `re.fullmatch` against run label "result: 2
    and something else entirely different" WOULD succeed -- `.*` happily
    consumes the rest of the line, degrading into "the prefix matches, so
    accept anything after it". `\\S+?` refuses that line outright, because
    it cannot cross the space before "and" -- verified below
    (falsification 5), not just asserted.

  - Non-greedy (`+?` not `+`) additionally makes the split correct when a
    placeholder is immediately followed by literal punctuation with no
    separating space (e.g. `$n items,`); it does not change the whitespace
    boundary above, which is enforced by the character class, not laziness.

KNOWN LIMITATION, STATED NOT HIDDEN: a substituted value that itself
contains whitespace will never match this wildcard, and reports as
unmatched rather than matched. Correct for THIS card -- the one real
placeholder substitutes a bare integer -- but a future multi-word
substitution would need a different rule; widening to `.` speculatively
would reopen the hole this rule exists to close, so it is left documented,
not fixed pre-emptively.

Also stated: this tool does not enforce that two occurrences of the SAME
`$name` in one label were substituted with the SAME text. No label in the
current corpus repeats a variable, so this is untested territory.

REQUIREMENT 4 -- count mode is separate and explicit
------------------------------------------------------
Set comparison is blind to a duplicate: 140 emissions of 139 distinct
labels passes every set check above, because "distinct" already dropped
the duplicate before comparison ever ran. `--count FILE --expect-count N`
checks the raw line count of one file (not deduplicated), independently of
diff mode, and is the only check in this tool that can catch that case.

BOUNDARY ERRORS
----------------
A missing file is a hard error (exit 2), never an empty label list. An
empty file (0 labels) is ALSO a hard error (exit 2), never treated as "the
empty set", because comparing two empty sets would report a clean match
for a comparison that never actually ran -- a receipt for a check that did
not happen. There is no silent-empty path anywhere in this tool.

EXIT CODES
-----------
0 = clean match / count matches exactly.
1 = mismatch, ambiguity, or count mismatch -- the comparison ran and found
    a real difference.
2 = usage or boundary error -- bad arguments, missing file, or empty input.
"""
import re
import sys

USAGE = (
    "usage:\n"
    "  label-diff.py --source-set FILE --run-set FILE\n"
    "  label-diff.py --before FILE --after FILE\n"
    "  label-diff.py --count FILE --expect-count N\n"
)

# A shell variable reference: `$name` or `${name}`. This is the minimum set
# the card requires; other `$`-shapes (positional params, `$(...)`) are
# intentionally left as literal text -- see the module docstring.
VAR_REF_RE = re.compile(r"\$(?:\{[A-Za-z_][A-Za-z0-9_]*\}|[A-Za-z_][A-Za-z0-9_]*)")

# One-or-more non-whitespace characters, non-greedy. See WILDCARD RULE above.
WILDCARD = r"\S+?"

FLAGS_WITH_VALUE = {
    "--source-set",
    "--run-set",
    "--before",
    "--after",
    "--count",
    "--expect-count",
}


def has_placeholder(label):
    return VAR_REF_RE.search(label) is not None


def label_pattern(label):
    """Anchored regex for a source label containing >=1 variable reference:
    each reference becomes WILDCARD, everything else is escaped literally."""
    pieces = []
    pos = 0
    for m in VAR_REF_RE.finditer(label):
        pieces.append(re.escape(label[pos:m.start()]))
        pieces.append(WILDCARD)
        pos = m.end()
    pieces.append(re.escape(label[pos:]))
    return re.compile("^" + "".join(pieces) + "$")


def load_labels(path, what):
    """Read one label per line. Returns None (after printing a message) on
    a missing file or an empty result -- never a silent empty list."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError as exc:
        print(f"label-diff.py: cannot read {what} file {path}: {exc}", file=sys.stderr)
        return None

    labels = [line.rstrip("\n") for line in lines]
    if not labels:
        print(
            f"label-diff.py: {what} file {path} contains no labels (0 lines) -- "
            "refusing to treat this as an empty set that trivially compares equal",
            file=sys.stderr,
        )
        return None
    return labels


def compare(source_labels, run_labels):
    """Compare a SOURCE-SET's distinct labels against a RUN-SET's (or a
    second SOURCE-SET's) distinct labels. Literal labels are resolved
    first; only the remainder is matched via placeholder wildcards against
    the remainder on the other side. Returns a dict describing every
    matched and unmatched/ambiguous label; never raises on a mismatch."""
    source_set = set(source_labels)
    run_set = set(run_labels)

    literal_source = {s for s in source_set if not has_placeholder(s)}
    placeholder_source = source_set - literal_source

    matched_literal = literal_source & run_set
    unmatched_literal_source = literal_source - run_set
    remaining_run = run_set - matched_literal

    candidates = {
        s: [r for r in remaining_run if label_pattern(s).fullmatch(r)]
        for s in placeholder_source
    }

    reverse = {}
    for s, rs in candidates.items():
        for r in rs:
            reverse.setdefault(r, []).append(s)

    matched_placeholder = {}
    ambiguous_source = {}
    ambiguous_run = {}
    unmatched_placeholder_source = []

    for s, rs in candidates.items():
        if not rs:
            unmatched_placeholder_source.append(s)
        elif len(rs) == 1:
            r = rs[0]
            if len(reverse[r]) > 1:
                ambiguous_run[r] = sorted(reverse[r])
            else:
                matched_placeholder[s] = r
        else:
            ambiguous_source[s] = sorted(rs)

    claimed_run = set(matched_placeholder.values())
    claimed_run |= {r for rs in ambiguous_source.values() for r in rs}
    claimed_run |= set(ambiguous_run.keys())
    unmatched_run = sorted(remaining_run - claimed_run)

    return {
        "matched_literal": sorted(matched_literal),
        "matched_placeholder": matched_placeholder,
        "unmatched_source": sorted(unmatched_literal_source) + sorted(unmatched_placeholder_source),
        "unmatched_run": unmatched_run,
        "ambiguous_source": ambiguous_source,
        "ambiguous_run": ambiguous_run,
    }


def report(result):
    """Print the full diagnostic and return True iff the comparison is
    clean. Never exits by itself."""
    clean = not (
        result["unmatched_source"]
        or result["unmatched_run"]
        or result["ambiguous_source"]
        or result["ambiguous_run"]
    )
    if clean:
        total = len(result["matched_literal"]) + len(result["matched_placeholder"])
        print(
            f"OK: {total} distinct labels matched "
            f"({len(result['matched_placeholder'])} via placeholder)."
        )
        return True

    if result["unmatched_source"]:
        print("IN SOURCE, NOT MATCHED IN RUN:", file=sys.stderr)
        for s in result["unmatched_source"]:
            print(f"  {s}", file=sys.stderr)
    if result["unmatched_run"]:
        print("IN RUN, NOT MATCHED BY ANY SOURCE LABEL:", file=sys.stderr)
        for r in result["unmatched_run"]:
            print(f"  {r}", file=sys.stderr)
    if result["ambiguous_source"]:
        print(
            "AMBIGUOUS: one source placeholder label matches more than one run label:",
            file=sys.stderr,
        )
        for s, rs in result["ambiguous_source"].items():
            print(f"  source: {s}", file=sys.stderr)
            for r in rs:
                print(f"    -> {r}", file=sys.stderr)
    if result["ambiguous_run"]:
        print(
            "AMBIGUOUS: one run label is matched by more than one source placeholder label:",
            file=sys.stderr,
        )
        for r, ss in result["ambiguous_run"].items():
            print(f"  run: {r}", file=sys.stderr)
            for s in ss:
                print(f"    <- {s}", file=sys.stderr)
    return False


def run_diff(source_path, run_path):
    source_labels = load_labels(source_path, "source-set")
    if source_labels is None:
        return 2
    run_labels = load_labels(run_path, "run-set")
    if run_labels is None:
        return 2

    result = compare(source_labels, run_labels)
    return 0 if report(result) else 1


def run_count_check(path, expect_str):
    try:
        expect = int(expect_str)
    except ValueError:
        print(
            f"label-diff.py: --expect-count value must be an integer, got {expect_str!r}",
            file=sys.stderr,
        )
        return 2

    labels = load_labels(path, "count")
    if labels is None:
        return 2

    actual = len(labels)
    if actual == expect:
        print(f"OK: {path} emits exactly {expect} labels.")
        return 0
    print(
        f"COUNT MISMATCH: {path} emits {actual} labels, expected {expect}.",
        file=sys.stderr,
    )
    return 1


def parse_args(argv):
    opts = {}
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in FLAGS_WITH_VALUE:
            if i + 1 >= len(argv):
                return None, f"{arg} requires a value"
            opts[arg] = argv[i + 1]
            i += 2
        else:
            return None, f"unrecognized argument: {arg}"
    return opts, None


def main(argv):
    opts, err = parse_args(argv)
    if err is not None:
        print(f"label-diff.py: {err}\n{USAGE}", file=sys.stderr, end="")
        return 2

    diff_left = {k: opts[k] for k in ("--source-set", "--before") if k in opts}
    diff_right = {k: opts[k] for k in ("--run-set", "--after") if k in opts}
    count_keys = {k: opts[k] for k in ("--count", "--expect-count") if k in opts}

    has_diff = bool(diff_left or diff_right)
    has_count = bool(count_keys)

    if has_diff and has_count:
        print(
            "label-diff.py: diff flags (--source-set/--run-set/--before/--after) and "
            "count flags (--count/--expect-count) are mutually exclusive -- run them "
            "as two separate invocations",
            file=sys.stderr,
        )
        return 2

    if has_count:
        if "--count" not in count_keys or "--expect-count" not in count_keys:
            print("label-diff.py: --count FILE and --expect-count N must both be given", file=sys.stderr)
            print(USAGE, file=sys.stderr, end="")
            return 2
        return run_count_check(count_keys["--count"], count_keys["--expect-count"])

    if has_diff:
        if len(diff_left) != 1 or len(diff_right) != 1:
            print(
                "label-diff.py: give exactly one left-hand flag "
                "(--source-set or --before) and exactly one right-hand flag "
                "(--run-set or --after)",
                file=sys.stderr,
            )
            return 2
        left_path = next(iter(diff_left.values()))
        right_path = next(iter(diff_right.values()))
        return run_diff(left_path, right_path)

    print(USAGE, file=sys.stderr, end="")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
