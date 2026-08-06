#!/usr/bin/env python3
"""Compare the task identities of a feature file's two halves.

Used by hooks/feature-sync-guard.sh. Decision 6 of docs/features/memory-system-split.md
splits a feature file into `<name>.md` (frontmatter + checklist) and `<name>.spec.md`
(the long prose half), and defines sync as: THE TASK LISTS MUST MATCH. Ticking a box
and appending a completion note are explicitly free, so identity has to be a key that
survives both.

TASK IDENTITY, per the contract: the checklist item's leading text up to the first
em dash or newline, normalized on whitespace and case. `- [x] 3 — Rewrite the skill`
and `- [ ] 3   —   rewrite the skill, done in abc1234` are the SAME task. That is what
makes ticking and note-appending free without a second rule to exempt them: everything
those edits touch lives after the em dash, outside the identity.

Consequence worth stating rather than discovering: re-wording a task AFTER the em dash
is invisible to this guard. Only the leading key is compared. The contract calls that
out as intended -- the guard exists to catch a task appearing in one half and not the
other, not to diff prose.

WHAT COUNTS AS MALFORMED is deliberately narrow, because a false parse error blocks a
real commit. A line is a checkbox CANDIDATE only when its bracket holds zero or one
character (`- []`, `- [y]`, `-[ ]`). A markdown link bullet -- `- [ADR 0015](docs/...)`
-- holds many, so ordinary prose in the spec half can never be read as a broken
checkbox. Pinned from both sides in the sibling test.

Exit codes (the caller maps these to allow/block):
    0  the two halves list the same tasks
    3  they diverge -- the differing identities are named on stdout
    4  a half could not be parsed -- the offending line is named on stdout
"""

import re
import sys

# Strict: dash, ONE space, a bracket holding exactly a space/x/X, then content.
STRICT_RE = re.compile(r"^\s*-\s\[[ xX]\]\s+(.+)$")
# Candidate: something trying to be a checkbox. The {0,1} width is what keeps a
# markdown link bullet out of this set -- see the module docstring.
CANDIDATE_RE = re.compile(r"^\s*-\s*\[[^\]]{0,1}\]")

EM_DASH = "—"

__all__ = ["ParseError", "task_ids", "compare"]


class ParseError(Exception):
    """A half exists but cannot be read as a task list."""


def identity(body):
    """Normalize a checklist item's text to its comparison key."""
    head = body.split(EM_DASH, 1)[0]
    return " ".join(head.split()).lower()


def task_ids(text, label):
    """Ordered task identities in `text`. Raises ParseError, never guesses.

    A duplicate identity is a parse error, not a silently-deduplicated set: an
    identity that is not unique cannot key the comparison, and collapsing it would
    let an 11-vs-12-task divergence pass as an equal set -- a fail-OPEN on exactly
    the thing this guard exists to catch.
    """
    ids = []
    seen = set()
    for lineno, line in enumerate(text.splitlines(), 1):
        match = STRICT_RE.match(line)
        if match is None:
            if CANDIDATE_RE.match(line):
                raise ParseError(
                    "%s:%d: malformed checklist item: %s" % (label, lineno, line.strip())
                )
            continue
        ident = identity(match.group(1))
        if not ident:
            raise ParseError(
                "%s:%d: task has no identifying text before the em dash: %s"
                % (label, lineno, line.strip())
            )
        if ident in seen:
            raise ParseError(
                "%s:%d: duplicate task identity %r -- identities must be unique to "
                "compare the halves" % (label, lineno, ident)
            )
        seen.add(ident)
        ids.append(ident)
    return ids


def compare(checklist_text, spec_text, name):
    """(exit_code, message) for one feature's two halves."""
    checklist_label = "%s.md" % name
    spec_label = "%s.spec.md" % name
    try:
        in_checklist = task_ids(checklist_text, checklist_label)
        in_spec = task_ids(spec_text, spec_label)
    except ParseError as exc:
        return 4, str(exc)

    only_spec = [t for t in in_spec if t not in set(in_checklist)]
    only_checklist = [t for t in in_checklist if t not in set(in_spec)]
    if not only_spec and not only_checklist:
        return 0, ""

    lines = ["%s and %s list different tasks:" % (checklist_label, spec_label)]
    if only_spec:
        lines.append(
            "  in %s but missing from %s: %s"
            % (spec_label, checklist_label, ", ".join(only_spec))
        )
    if only_checklist:
        lines.append(
            "  in %s but missing from %s: %s"
            % (checklist_label, spec_label, ", ".join(only_checklist))
        )
    return 3, "\n".join(lines)


def main():
    if len(sys.argv) != 4:
        sys.stderr.write("usage: feature_tasks.py <checklist> <spec> <name>\n")
        return 2
    try:
        with open(sys.argv[1], "r") as fh:
            checklist_text = fh.read()
        with open(sys.argv[2], "r") as fh:
            spec_text = fh.read()
    except (IOError, OSError, UnicodeDecodeError) as exc:
        sys.stdout.write("cannot read a half of %s: %s\n" % (sys.argv[3], exc))
        return 4
    code, message = compare(checklist_text, spec_text, sys.argv[3])
    if message:
        sys.stdout.write(message + "\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
