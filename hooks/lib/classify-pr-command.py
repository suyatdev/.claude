#!/usr/bin/env python3
"""Classify a raw Bash command string as "does this really run `gh pr create`?".

Used by hooks/judge-guard.sh. Reads the command line on stdin and writes two lines
to stdout: the kind ("PR" or "NO"), then the JUDGE_EXEMPT reason ("" when absent).

Extracted from an inline `python -c` string inside judge-guard.sh (ADR 0012). That
string was single-quoted in shell, so a lone apostrophe anywhere in it -- including
in a comment -- terminated the quote and broke the entire hook. It happened three
times, twice inside the very comment block warning against it, costing ~24 spurious
test failures each time; a warning comment was a disproven control. Living in its
own file removes the hazard by construction and makes the classifier importable, so
bypass shapes can be unit-tested directly instead of probed through the hook.

The segment lexer that does the real work now lives in shell_segments.py, shared with
classify-git-command.py. All of the lexing rationale -- and the shapes deliberately
left open -- is documented there.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from shell_segments import WRAPPERS, segments  # noqa: E402  (path must be set first)

__all__ = ["classify", "WRAPPERS"]


def classify(src):
    """Return (kind, exempt_reason) for a raw Bash command string.

    kind is "PR" when some shell segment really runs `gh pr create`, else "NO".
    exempt_reason is the JUDGE_EXEMPT value from the *matching* segment, mirroring bash,
    where such a prefix binds only to its own command.
    """
    for assigns, argv in segments(src):
        # `gh` must hold the command position, but `pr create` need not be tokens 1-2: global
        # flags are legal before the subcommand (`gh -R owner/repo pr create`). Requiring the two
        # words ADJACENT keeps the false-positive surface narrow -- quoted text is a single token,
        # so a commit message mentioning the phrase still cannot produce an adjacent bare pair.
        if not argv or argv[0] != "gh":
            continue
        for j in range(1, len(argv) - 1):
            if argv[j] == "pr" and argv[j + 1] == "create":
                # The exemption name is matched exactly, never by suffix: a suffix match would
                # hand every *_EXEMPT variable in the repo the power to wave a PR past the gate,
                # and MERGE_EXEMPT is a real one belonging to merge-guard.sh.
                return ("PR", assigns.get("JUDGE_EXEMPT", "").replace("\n", " "))
    return ("NO", "")


def main():
    kind, exempt = classify(sys.stdin.read())
    sys.stdout.write(kind + "\n" + exempt + "\n")


if __name__ == "__main__":
    main()
