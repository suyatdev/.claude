#!/usr/bin/env python3
"""Put one git segment into one of five classes, for the `git-guard quiet` session toggle.

Card: docs/features/git-guard-quiet.md, "The lists" (D3-D5, D8). Imported by
classify-git-command.py, which emits the answer as `SEG_QUIET<tab><i><tab><class>` on any line
that already carries SCOPE_UNKNOWN. This file only names the class; whether a class is allowed to
pass without a prompt is decided elsewhere (git_guard_quiet.py), which also checks the branch.

    read    a command that cannot write: the named read list, with the argument rules below
    add     `git add`, any arguments -- it stages, it cannot move a branch
    commit  `git commit`, any arguments -- the quiet decision checks the folder and the branch
    push    `git push` in the ONE allowed shape (D8)
    other   everything else, including every subcommand not named here

`nongit` (a segment that is not a git command) is the CALLER's class: this function is only ever
handed a git subcommand, so it never returns it.

Every rule below errs toward `other`, because `other` is today's prompt: a wrong `other` costs one
prompt, a wrong `read` is a silent write. A subcommand is matched by its EXACT name, so an alias
(`git -C F st`) or a different case is never on a list.

Pure and total: no I/O, no environment, and `classify()` catches every exception itself and answers
`other` (the card's "Errors at this boundary").
"""

import re

__all__ = ["classify", "CLASSES", "READ", "ADD", "COMMIT", "PUSH", "OTHER"]

READ = "read"
ADD = "add"
COMMIT = "commit"
PUSH = "push"
OTHER = "other"
CLASSES = (READ, ADD, COMMIT, PUSH, OTHER)

# Subcommands that read and nothing else, provided no argument starts with OUTPUT_OPTION_PREFIX.
READ_SUBCOMMANDS = (
    "status", "log", "diff", "show", "cat-file", "rev-parse", "ls-files", "ls-tree",
    "show-ref", "merge-base", "describe", "blame", "shortlog", "for-each-ref",
)

# These commands can write a file to a path the caller names. A PREFIX test on purpose: round 5
# measured git rejecting abbreviations of the option, and a longer spelling that merely starts
# with it asks too, which costs a prompt, never a silent write.
OUTPUT_OPTION_PREFIX = "--output"

# `git hash-object -w` stores the object. `-w` is a short-only option, so it can hide in any
# single-dash bundle (`-wt blob`), which is why the test is on the bundle and not on the exact word.
HASH_OBJECT_WRITE_LETTER = "w"

BRANCH_SHOW_CURRENT = "--show-current"
BRANCH_LIST_OPTIONS = ("--list", "-l")

# D8: the one push shape. Options come first and only these; then exactly <remote> HEAD.
PUSH_OPTIONS = (
    "-u", "--set-upstream", "-q", "--quiet", "-v", "--verbose",
    "--force-with-lease",   # bare only: `--force-with-lease=x` is not in this tuple
)
PUSH_REF = "HEAD"
# fullmatch, never `^...$` with re.match: `$` also matches before a trailing newline.
# The first character may not be `-`: git reads `-o HEAD` as a push option and runs a bare push.
PUSH_REMOTE_PATTERN = re.compile(r"[A-Za-z0-9._][A-Za-z0-9._-]*")
PUSH_POSITIONAL_COUNT = 2


def _no_output_option(argv):
    return not any(arg.startswith(OUTPUT_OPTION_PREFIX) for arg in argv)


def _hash_object_is_read(argv):
    for arg in argv:
        is_single_dash = arg.startswith("-") and not arg.startswith("--")
        if is_single_dash and HASH_OBJECT_WRITE_LETTER in arg:
            return False
    return True


def _branch_is_read(argv):
    if argv == [BRANCH_SHOW_CURRENT]:
        return True
    if argv and argv[0] in BRANCH_LIST_OPTIONS:
        return not any(arg.startswith("-") for arg in argv[1:])
    return False


def _worktree_is_read(argv):
    return argv == ["list"]


def _push_is_allowed_shape(argv):
    index = 0
    while index < len(argv) and argv[index] in PUSH_OPTIONS:
        index += 1
    positionals = argv[index:]
    if len(positionals) != PUSH_POSITIONAL_COUNT:
        return False
    remote, ref = positionals
    return ref == PUSH_REF and PUSH_REMOTE_PATTERN.fullmatch(remote) is not None


def _classify(subcommand, argv):
    if not isinstance(subcommand, str):
        return OTHER
    if not isinstance(argv, (list, tuple)) or not all(isinstance(arg, str) for arg in argv):
        return OTHER
    argv = list(argv)

    if subcommand in READ_SUBCOMMANDS:
        return READ if _no_output_option(argv) else OTHER
    if subcommand == "hash-object":
        return READ if _hash_object_is_read(argv) else OTHER
    if subcommand == "branch":
        return READ if _branch_is_read(argv) else OTHER
    if subcommand == "worktree":
        return READ if _worktree_is_read(argv) else OTHER
    if subcommand == "add":
        return ADD
    if subcommand == "commit":
        return COMMIT
    if subcommand == "push":
        return PUSH if _push_is_allowed_shape(argv) else OTHER
    return OTHER


def classify(subcommand, argv):
    """The class of `git <subcommand> <argv...>`, where `argv` is what follows the subcommand.

    Never raises. Anything unexpected -- a non-string, a non-list, an internal error -- is `other`.
    """
    try:
        return _classify(subcommand, argv)
    except Exception:
        return OTHER
