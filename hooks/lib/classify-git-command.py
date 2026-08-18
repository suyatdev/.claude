#!/usr/bin/env python3
"""Report which git operations a raw Bash command string really runs.

Used by hooks/git-guard.sh and hooks/doc-guard.sh. Reads the command line on stdin and
writes zero or more fact tokens to stdout, one per line, sorted. Always exits 0 -- an
unrecognised command simply yields no facts.

    COMMIT      some segment runs `git commit`
    COMMIT_ALL  ...and that same segment carries -a / --all / -am, which stages tracked
                edits at commit time, so the change to inspect is HEAD's diff, not the index
    COMMIT_AMEND      ...and that segment carries --amend, which re-writes HEAD's tree
    COMMIT_PATHSPEC   EVERY `git commit` on the line names paths after a `--` separator and
                carries nothing besides that could commit more -- so the COMMIT_PATH facts
                below are the whole file set of the whole line
    COMMIT_PATH<tab><path>
                one per path after `--`, across every commit on the line, and only
                alongside COMMIT_PATHSPEC. A path rides in the fact stream rather than being
                re-lexed by the caller, so there is no second parser to disagree with this
                one; the tab keeps a path containing spaces in one piece.
    COMMIT_BARE_ARGS  ...and that segment has a token the flag table cannot account for,
                i.e. a suspected pathspec with no `--` to confirm it
    PUSH        some segment runs `git push`
    PUSH_FORCE  some segment runs `git push` with a bare --force / -f AND NO
                --force-with-lease of its own
    PUSH_LEASE  some segment runs `git push` with --force-with-lease
    SCOPE_UNKNOWN<tab><option>
                a global option ahead of the subcommand that this file cannot
                account for -- it may redirect which repository is inspected, or
                change what a pathspec means, or simply be unrecognised. Denying:
                suppresses every COMMIT*/PUSH* fact for THAT segment, emitted at
                most once per LINE, naming the first triggering option.

Both guards previously matched a regex anchored to the start of the command string, so
`git add -- x && git commit -m y` -- the shape this repo uses constantly -- never matched
and the guard body never ran. See shell_segments.py for the lexer and its accepted limits.

GRANTING vs DENYING facts. The caller gets a flat SET with no segment identity, so a fact
that GRANTS permission must be true of the whole LINE, while a fact that DENIES may be true
of any one segment. COMMIT_PATHSPEC is the only granting fact and used to be emitted from a
single segment: in `git commit -m a -- docs/a.md && git add -- src/b.sh && git commit -m b`
the first commit's paths answered for a line whose second commit really carries src/b.sh.
PUSH_FORCE already followed the rule in the denying direction -- a lease in a different
segment must not excuse a bare force in this one.

Why the flags are judged PER SEGMENT rather than by searching the whole string, which is
what the shell versions did:

  * `git push --force && echo --force-with-lease` used to read as a leased push and go
    unblocked, because the lease check was a plain substring search over everything.
  * `git push && echo --force` used to be blocked, because the force check was too.
  * doc-guard read `-a` from ANY segment, so `git commit -m msg && ls -a` made it judge
    every dirty tracked file instead of the (empty) index.

Deliberately NOT reported: what a SIBLING command stages. `git add` briefly had ADD_PATH /
ADD_ALL facts so git-guard could add them to a commit's file set, and that was wrong in kind
rather than in detail -- at least ten commands fill the index (add, rm, mv, reset --soft,
checkout -- , restore --staged, apply --cached, stash pop --index, cherry-pick -n, revert -n),
two review rounds each measured the list short, and a list that is short in the ALLOW direction
is a fail-open. The guard now trusts only what the `commit` itself names. See ADR 0014.

Deliberately NOT parsed: git accepts any unambiguous prefix of a long option (`--amen` ==
`--amend`), so enumerating the grammar cannot be completed. Only fully-spelled forms are
recognised. A consequence worth stating: a commit whose message is literally `-a`
(`git commit -m "-a"`) is read as --all, because option values are not tracked. That
direction is safe -- it makes doc-guard inspect more, never less -- and closing it would
mean modelling git's option grammar, which is the trap this file exists to avoid.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from shell_segments import segments  # noqa: E402  (path must be set first)

__all__ = ["classify"]

ALL_FLAGS = ("-a", "--all", "-am")
FORCE_FLAGS = ("--force", "-f")
LEASE_FLAG = "--force-with-lease"

# `git commit` options that consume the NEXT token. This exists only to tell a
# pathspec from an option value when there is no `--` separator; -a detection
# still ignores option values entirely (see the `git commit -m '-a'` case in the
# unit suite, which must keep reporting COMMIT_ALL). A long option spelled
# `--opt=value` carries its value inline and needs no entry. An unknown flag is
# assumed to take no value, so its value looks like a stray path -- which errs
# toward blocking, the fail direction git-guard.sh states for itself.
COMMIT_VALUE_FLAGS = (
    "-m", "-am", "-F", "-c", "-C", "-t",
    "--message", "--file", "--reedit-message", "--reuse-message",
    "--author", "--date", "--fixup", "--squash", "--cleanup",
    "--template",
)

# Options that take no value AND cannot widen what gets committed. Anything not
# on this list or the value list above is UNRECOGNISED, and unrecognised means
# block: git honours any unambiguous abbreviation of a long option, so testing
# for the exact spelling `--amend` is not a test for amending -- `--amen` does
# the same thing and would otherwise pass unexamined. `--pathspec-from-file` is
# deliberately absent from both lists for the same reason: its paths live in a
# file this hook cannot read, so it must fail closed rather than look harmless.
COMMIT_SAFE_FLAGS = (
    "-a", "--all", "--amend",
    "-e", "--edit", "--no-edit", "-n", "--no-verify", "--verify",
    "-q", "--quiet", "-v", "--verbose", "-s", "--signoff", "--no-signoff",
    "--allow-empty", "--allow-empty-message", "--reset-author",
    "--short", "--branch", "--porcelain", "--long", "-z", "--null",
    "--dry-run", "--status", "--no-status", "--no-post-rewrite",
    "-S", "--gpg-sign", "--no-gpg-sign",
)

# Global options resolve_subcommand() walks past before reading the real
# subcommand (docs/features/global-option-blindness.md, "The rule -- three
# buckets"). Every member is enumerated here, never inferred -- the same
# reasoning as COMMIT_SAFE_FLAGS below: an option this file does not name is
# unrecognised, and unrecognised must not mean "skip".

# Bucket 1a -- takes no value, or an attached `=value` that is never a
# SEPARATE token, and never redirects the repo or changes what a pathspec
# means. Recognised by the name before any "=". The spec's two Examples
# tables (harmless-skip and print-and-exit) name exactly these; the tables
# differ only in git-guard.sh's refusal MESSAGE for a print-and-exit option
# (task 3b), never in this classifier's fact.
GLOBAL_SKIP_NO_VALUE = (
    "--no-pager", "-p", "--paginate", "-P",
    "--no-optional-locks", "--no-advice", "--no-replace-objects", "--no-lazy-fetch",
    "--exec-path", "--version", "-v", "--help", "-h",
    "--html-path", "--man-path", "--info-path", "--list-cmds",
)

# Bucket 1b -- also skipped, but CONSUMES the next token as its value.
# --attr-source is the only member; it cannot share the table above, or the
# subcommand itself gets swallowed as the option's value (measured against
# git 2.50.1: `git --attr-source commit -m x -a` errors `unknown option: -m`
# and commits nothing -- "commit" was consumed as attr-source's value).
GLOBAL_SKIP_CONSUMING = ("--attr-source",)

# Bucket 2 -- refuse and ask: can redirect which repository is inspected, or
# changes what a pathspec MEANS, which git-guard's documentation-only
# exemption is decided from. Checked explicitly, the same shape as
# COMMIT_SAFE_FLAGS below: anything not in bucket 1 or named here is bucket
# 3, unrecognised, and gets the identical SCOPE_UNKNOWN treatment -- the
# asymmetry that lets a future git option land in "ask", never in "allow".
GLOBAL_REDIRECT = (
    "-C", "--git-dir", "--work-tree", "--namespace", "--bare",
    "-c", "--config-env",
    "--literal-pathspecs", "--glob-pathspecs", "--noglob-pathspecs", "--icase-pathspecs",
)


def resolve_subcommand(argv):
    """argv[0] == "git". Walk past bucket-1 global options and return the real
    subcommand.

    Returns (subcommand, rest) once a genuine subcommand is found, (None, [])
    if the line runs out of tokens first, or ("SCOPE_UNKNOWN", <option>) the
    moment a bucket-2 or bucket-3 option is seen -- once that happens nothing
    past it is inspected, because git-guard cannot tell which repository or
    branch the rest of the segment targets.
    """
    i = 1
    while i < len(argv) and argv[i].startswith("-"):
        name = argv[i].split("=", 1)[0]
        if name in GLOBAL_SKIP_NO_VALUE:
            i += 1
            continue
        if name in GLOBAL_SKIP_CONSUMING:
            i += 2
            continue
        if name in GLOBAL_REDIRECT:
            return "SCOPE_UNKNOWN", name      # bucket 2: known to redirect the repo
        return "SCOPE_UNKNOWN", name          # bucket 3: unrecognised -- cannot tell, so cannot allow
    if i >= len(argv):
        return None, []
    return argv[i], argv[i + 1:]


def commit_scan(rest):
    """(paths named after `--`, whether the file set is UNKNOWABLE).

    The flags BEFORE a `--` are scanned even though the paths after it are
    unambiguous, because some of them mean the paths are not the whole commit:
    `-i`/`--include` commits the index AS WELL. Returning the paths as soon as a
    `--` was seen -- the obvious reading, and what this did first -- handed the
    caller a pathspec that looked exhaustive and was not.
    """
    if "--" in rest:
        cut = rest.index("--")
        flags, paths = rest[:cut], rest[cut + 1:]
    else:
        flags, paths = rest, []
    skip = False
    for tok in flags:
        if skip:
            skip = False
            continue
        if not tok.startswith("-"):
            return [], True                   # a stray token: suspected pathspec
        name = tok.split("=", 1)[0]
        if name in COMMIT_VALUE_FLAGS:
            skip = "=" not in tok             # `--opt=value` carries its value inline
            continue
        if name in COMMIT_SAFE_FLAGS:
            continue
        return [], True                       # unrecognised option: cannot tell
    return paths, False


def classify(src):
    """Return the sorted list of fact tokens for a raw Bash command string."""
    facts = set()
    # One entry per `git commit` segment: the paths that commit names for itself,
    # or None when it names none this file can vouch for. The path facts are
    # emitted only if NO entry is None -- see "granting vs denying" in the module
    # docstring. Collected first and emitted after the loop because a segment
    # cannot know whether a LATER one will name nothing.
    commit_scopes = []
    # The option that first triggered SCOPE_UNKNOWN, across the whole line --
    # "at most once per line, from the first triggering option" (contract).
    # segments() and resolve_subcommand() both scan left to right, so the
    # first one found in iteration order IS the first one on the line.
    scope_unknown = None
    for _assigns, argv in segments(src):
        if len(argv) < 2 or argv[0] != "git":
            continue
        subcommand, rest = resolve_subcommand(argv)

        if subcommand == "SCOPE_UNKNOWN":
            if scope_unknown is None:
                scope_unknown = rest
            continue  # denying: no COMMIT*/PUSH* fact for THIS segment
        if subcommand is None:
            continue  # ran out of tokens before a subcommand appeared

        if subcommand == "commit":
            facts.add("COMMIT")
            widened = False
            if any(tok in ALL_FLAGS for tok in rest):
                facts.add("COMMIT_ALL")
                widened = True
            if "--amend" in rest:
                facts.add("COMMIT_AMEND")
                widened = True
            paths, bare = commit_scan(rest)
            if bare:
                facts.add("COMMIT_BARE_ARGS")
            # -a and --amend commit more than the pathspec names, so this segment
            # does not describe itself even though it does name paths.
            scoped = bool(paths) and not bare and not widened
            commit_scopes.append(paths if scoped else None)

        elif subcommand == "push":
            facts.add("PUSH")
            # `--force-with-lease` and `--force-with-lease=<ref>` both count as leased.
            leased = any(
                tok == LEASE_FLAG or tok.startswith(LEASE_FLAG + "=") for tok in rest
            )
            if leased:
                facts.add("PUSH_LEASE")
            # PUSH_FORCE is self-contained: it means "this segment force-pushes WITHOUT a
            # lease". Emitting bare-force and leased as independent facts would let a lease
            # in a different segment excuse a bare force in this one.
            if not leased and any(tok in FORCE_FLAGS for tok in rest):
                facts.add("PUSH_FORCE")

    if commit_scopes and all(scope is not None for scope in commit_scopes):
        facts.add("COMMIT_PATHSPEC")
        for scope in commit_scopes:
            for path in scope:
                facts.add("COMMIT_PATH\t" + path)

    if scope_unknown is not None:
        facts.add("SCOPE_UNKNOWN\t" + scope_unknown)

    return sorted(facts)


def main():
    facts = classify(sys.stdin.read())
    sys.stdout.write("".join(f + "\n" for f in facts))


if __name__ == "__main__":
    main()
