"""The parts-folder convention, defined once: what counts as "the suite" besides the runner itself.

A bash runner `<stem>.test.sh` may source a folder `<stem>.test.d/` of parts. Both
hooks/lib/write-test-marker.py (the receipt) and hooks/lib/decide-commit-gate.py (the gate that
reads it) need the same answer, so the convention lives here and both import it -- they cannot
drift on what counts as a part.

It is its own module, and imports almost nothing, because the gate loads it on EVERY commit:
importing it out of the writer instead dragged in `tempfile`, `datetime` and `glob` for two short
string functions (measured ~18 ms inside the decision call; docs/features/trim-safety-followups.md
task 14). `fnmatch` stays: measured ~0.5 ms (import 0.36 + first match 0.11) and `re`, which it
sits on, is already loaded by the gate.

No sibling `parts_convention.test.py` on purpose: a `X.py`/`X.test.py` pair is a new pair the
commit gate would demand a receipt for. The convention is covered by write-test-marker.test.py's
parts assertions (including PARTS_GLOB == the bash loop's glob) and by its live-checkout
cross-check.
"""

import fnmatch
import os

__all__ = ["PARTS_GLOB", "PARTS_DIR_SUFFIX", "parts_folder_for", "is_part"]

# The `.test.sh` suffix is the only runner form that has parts (nothing sources parts for a
# `.test.py` runner). Mirrors PAIR_SUFFIXES[0][0] in write-test-marker.py.
RUNNER_SUFFIX = ".test.sh"

# A bash runner `<stem>.test.sh` may source a folder `<stem>.test.d/` of parts. PARTS_GLOB is the
# glob in the `for part in` loop of hooks/handoff/lib/test-parts.sh -- bash cannot share a
# constant, so write-test-marker.test.py asserts the two strings are equal.
PARTS_GLOB = "[0-9][0-9]-*.sh"
PARTS_DIR_SUFFIX = ".test.d"


def parts_folder_for(test_rel):
    """The parts folder (repo-relative, no trailing slash) of a runner, or None.

    Only a `.test.sh` runner has one: nothing sources parts for a `.test.py` runner, so the
    writer does not even look.
    """
    if not test_rel.endswith(RUNNER_SUFFIX):
        return None
    return test_rel[: -len(RUNNER_SUFFIX)] + PARTS_DIR_SUFFIX


def is_part(path):
    """True when `path` is `<something>.test.d/<name matching PARTS_GLOB>` (last two components)."""
    folder, name = os.path.split(path)
    return os.path.basename(folder).endswith(PARTS_DIR_SUFFIX) and fnmatch.fnmatchcase(
        name, PARTS_GLOB
    )
