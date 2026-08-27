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

SEGMENT-INDEXED FACTS (worktree-location-guard). `<i>` is the zero-based position of
the segment in the list segments() returns.

    SEG_CD<tab><i><tab><operand>
                segment `i` is a `cd`. <operand> is its literal operand, or the
                sentinel UNRESOLVABLE when it is a variable, a substitution, or absent.
    SEG_GIT_C<tab><i><tab><operand>
                segment `i`'s git command carries `-C <operand>`. Emitted IN ADDITION
                to SCOPE_UNKNOWN<tab>-C, never in place of it: `git -C <other-repo>`
                appears hundreds of times in this repo's own scripts, so `-C` is
                resolved rather than refused.
    SEG_WORKTREE_ADD<tab><i><tab><path>
                segment `i` runs `git worktree add`, with option values skipped.
    SEG_BRANCH_MOVE<tab><i><tab><subcommand>
                segment `i` runs a git form that moves a checkout's HEAD or overwrites
                its working tree.
    SEG_SCOPE_OPT<tab><i><tab><option>
                segment `i` carries a global option resolve_subcommand refused to walk
                past, OTHER than -C. Emitted from that return VALUE, never from a list
                of option names, so an option git adds tomorrow lands here rather than
                in "allow".
    SEG_ENV<tab><i><tab><name>
                one per assignment on segment `i` whose name begins GIT_. A PREFIX
                test over the namespace git owns, so a variable added upstream is
                covered the day it ships.
    SEG_OPAQUE<tab><i><tab><token>
                segment `i` runs git or cd somewhere argv[0] cannot be held
                accountable for. Two clauses, one fact -- see opaque_token().
    SEG_UNPARSED
                LINE-scoped: segments() returned [] for a non-empty command string.
    SEG_GROUPED
                LINE-scoped: the line holds a grouping operator AND some SEG_CD.

THE GRANTING/DENYING DISTINCTION DOES NOT APPLY TO THE INDEXED FACTS. That rule exists
BECAUSE a flat fact cannot say which segment it came from, so a permission granted by
one segment could excuse another. An indexed fact names its own segment, so each is
judged on its own and no fact can vouch for a segment it did not come from. This is
also why the indexed facts are collected BEFORE the SCOPE_UNKNOWN `continue`, which
suppresses only the unindexed COMMIT*/PUSH* facts.

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

from shell_segments import has_grouping, segments  # noqa: E402  (path must be set first)

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


# The sentinel every indexed fact carries when its operand cannot be read off the
# command line. The guard denies on it: an unresolvable working directory means it
# cannot tell which repository it is protecting.
UNRESOLVABLE = "UNRESOLVABLE"

# The two commands whose presence at argv[0] makes a segment accountable. Everything
# else running one of them is opaque -- see opaque_token().
OPAQUE_TARGETS = ("git", "cd")

# How deep clause 3b re-lexes a collapsed token before it stops. Three levels of
# evidence is evidence, not blindness (user decision, 2026-08-25): past this bound
# the segment is ALLOWED, while a token no level could lex at all still denies.
RELEX_DEPTH_BOUND = 3

# The namespace git owns. A PREFIX, never an enumeration: GIT_DIR, GIT_WORK_TREE,
# GIT_COMMON_DIR, GIT_INDEX_FILE, GIT_CEILING_DIRECTORIES and GIT_NAMESPACE were each
# confirmed to arrive in the assignments dict with their values -- named as evidence
# the dict works, not as the set being matched.
GIT_ENV_PREFIX = "GIT_"

# `git worktree add` options that consume the NEXT token, so their value is never
# mistaken for the path operand. Same shape, and same fail direction, as
# COMMIT_VALUE_FLAGS above.
WORKTREE_ADD_VALUE_FLAGS = ("-b", "-B", "--reason")

# ...and the ones that take no value. Anything on neither list is UNRECOGNISED, which
# makes the path operand unidentifiable rather than harmless: an option this file does
# not name might or might not consume the token after it, so which token is the path
# genuinely cannot be told. Fails to UNRESOLVABLE, which denies.
WORKTREE_ADD_SAFE_FLAGS = (
    "-f", "--force", "--detach", "--checkout", "--no-checkout", "--lock",
    "--track", "--no-track", "--guess-remote", "--no-guess-remote",
    "--relative-paths", "--no-relative-paths", "--orphan", "-q", "--quiet",
)

# Arm D's in-scope list: forms that move a checkout's HEAD or overwrite its working
# tree wholesale. The list is a known UNDER-block and that direction is deliberate --
# an unrecognised git subcommand is allowed, because the alternative is denying every
# subcommand nobody has taught this file yet.
BRANCH_MOVE_ALWAYS = ("switch", "merge", "pull", "rebase", "cherry-pick", "revert")
# ...and the two that move HEAD only when they are NOT naming paths. `git checkout --
# <path>` and `git reset -- <path>` touch named files, so they stay out of scope.
BRANCH_MOVE_UNLESS_PATHSPEC = ("checkout", "reset")
# `git stash` itself saves; only these two write the working tree back.
STASH_MOVE_SUBCOMMANDS = ("pop", "apply")


def _seg(name, index, operand):
    """One indexed fact. The tab keeps an operand containing spaces in one piece,
    exactly as COMMIT_PATH already does."""
    return "%s\t%d\t%s" % (name, index, operand)


def _walk_globals(argv):
    """The single global-option walk, returning (subcommand, rest, blocking, index).

    `index` is where the blocking option sits in argv, which is the only way to reach
    its OPERAND -- resolve_subcommand() reports the option's name and nothing else.
    Split out for the same reason shell_segments._lex was: one walker, two views. A
    second option walker would be free to disagree with this one about where the
    global-option prefix ends, and the disagreement would land in a guard.
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
            return None, [], name, i   # bucket 2: known to redirect the repo
        return None, [], name, i       # bucket 3: unrecognised -- cannot tell, so cannot allow
    if i >= len(argv):
        return None, [], None, None
    return argv[i], argv[i + 1:], None, None


def resolve_subcommand(argv):
    """argv[0] == "git". Walk past bucket-1 global options and return the real
    subcommand.

    Returns (subcommand, rest, None) once a genuine subcommand is found,
    (None, [], None) if the line runs out of tokens first, or
    (None, [], <option>) the moment a bucket-2 or bucket-3 option is seen --
    once that happens nothing past it is inspected, because git-guard cannot
    tell which repository or branch the rest of the segment targets.

    THE THREE-TUPLE IS A PUBLIC CONTRACT, not an implementation detail: git-guard.sh
    (its inline python), classify-commit-command.py and decide-commit-gate.py all
    unpack exactly three. Callers needing the blocking option's POSITION use
    _walk_globals directly rather than widening this.
    """
    subcommand, rest, blocking, _at = _walk_globals(argv)
    return subcommand, rest, blocking


def resolve_git_segment(argv):
    """Everything classify() needs about one `git ...` segment, from one walk.

    Returns (subcommand, rest, blocking, residual, c_operands):

      blocking     the FIRST option resolve_subcommand refused to walk past. This is
                   what SCOPE_UNKNOWN has always named, and it is unchanged.
      residual     the first such option that is NOT `-C`, i.e. the one that denies.
      c_operands   every `-C` operand this segment carries, in order.
      subcommand   resolved PAST the `-C` pairs, so a `git -C /other worktree add /bad`
      rest         still yields its indexed facts. Stopping at the `-C` would leave that
                   line carrying nothing any arm denies on, which is a silent fail-open.

    `-C` is the single GLOBAL_REDIRECT member this design resolves rather than refuses,
    so it is the single one worth walking past. The walk is _walk_globals called again
    on the remainder -- there is no second option walker to disagree with it.
    """
    c_operands = []
    cur = argv
    while True:
        subcommand, rest, blocking, at = _walk_globals(cur)
        if blocking != "-C":
            first = "-C" if c_operands else blocking
            return subcommand, rest, first, blocking, c_operands
        # Only the exact spelling `-C` carries its operand in the NEXT token. An
        # attached form (`-C=/x`) puts the value inside the token under git's own
        # short-option grammar, and modelling that grammar is the trap this file
        # exists to avoid -- so it is unresolvable rather than guessed at.
        if cur[at] == "-C" and at + 1 < len(cur):
            c_operands.append(cur[at + 1])
        else:
            c_operands.append(UNRESOLVABLE)
        cur = ["git"] + cur[at + 2:]


def cd_operand(argv):
    """argv[0] == "cd". Its literal operand, or the sentinel when it cannot be one.

    A leading `-` covers `cd -` ($OLDPWD) and `cd -P /tmp` with one rule instead of a
    list of cd's own options; `$` and a backtick cover a variable, a `$(...)` (which
    the lexer splits at the paren, leaving a bare `$` behind) and a backticked
    substitution. Each is a directory only the running shell could name.
    """
    if len(argv) < 2:
        return UNRESOLVABLE
    operand = argv[1]
    if not operand or operand.startswith("-"):
        return UNRESOLVABLE
    if "$" in operand or "`" in operand:
        return UNRESOLVABLE
    return operand


def worktree_add_path(tokens):
    """The path operand of `git worktree add`, given the tokens after `add`.

    The first token the option table cannot account for ends the walk, because an
    unrecognised option may or may not consume the token behind it.
    """
    skip = False
    for tok in tokens:
        if skip:
            skip = False
            continue
        if not tok.startswith("-"):
            return tok
        name = tok.split("=", 1)[0]
        if name in WORKTREE_ADD_VALUE_FLAGS:
            skip = "=" not in tok          # `--opt=value` carries its value inline
            continue
        if name in WORKTREE_ADD_SAFE_FLAGS:
            continue
        return UNRESOLVABLE
    return UNRESOLVABLE


def is_branch_move(subcommand, rest):
    """Whether this git form moves HEAD or overwrites the working tree wholesale."""
    if subcommand in BRANCH_MOVE_ALWAYS:
        return True
    if subcommand in BRANCH_MOVE_UNLESS_PATHSPEC:
        return "--" not in rest
    if subcommand == "stash":
        return bool(rest) and rest[0] in STASH_MOVE_SUBCOMMANDS
    return False


def relex_hit(argv, depth):
    """Clause 3b: the whitespace-bearing token of `argv` that hides a git or cd, or None.

    Re-lexes every collapsed token through the SAME lexer and tests COMMAND POSITION --
    an inner segment's argv[0] -- not presence. The difference is load-bearing and was
    measured: the wider "git anywhere in the re-lexed tokens" form falsely denied
    `gh pr create --title "fix git guard"` and 3 other real shapes out of 19.

    Clause 3c splits the two unresolvable cases, which are not equivalent. A token no
    level could lex at all means the guard has seen NOTHING, so it denies like
    SEG_UNPARSED; a token still collapsed at RELEX_DEPTH_BOUND means it has seen three
    levels and found no command position, which is evidence.
    """
    for tok in argv:
        if not any(ch.isspace() for ch in tok):
            continue
        if depth >= RELEX_DEPTH_BOUND:
            return None
        inner = segments(tok)
        if not inner:
            return tok
        for _assigns, iargv in inner:
            if iargv and iargv[0] in OPAQUE_TARGETS:
                return tok
            if relex_hit(iargv, depth + 1) is not None:
                return tok
    return None


def opaque_token(argv):
    """The token making this segment unaccountable, or None. Caller guarantees argv is
    non-empty and argv[0] is neither git nor cd.

    Two clauses, one fact, each derived from one half of the WRAPPERS comment in
    shell_segments.py -- both halves, because a derivation is only as sound as the whole
    of the premise it cites:

      3a  `:62-63`, the denylist half. argv[0] is unaccounted for, yet git or cd appears
          later in argv. One rule about argv[0] covers env, timeout, if, for/do and
          anything else in that family, instead of a sixth hand-maintained list.
      3b  `:60-62`, the quoted-token half, which says such a token "can never reach a
          command position". So the rule re-lexes until it can, then applies the
          ordinary command-position test. No shell name, no `-c` and no wrapper word
          appears here, which is what keeps it a derivation: `zsh -c '...'` is covered
          without `zsh` being written down anywhere.
    """
    if any(tok in OPAQUE_TARGETS for tok in argv[1:]):
        return argv[0]
    return relex_hit(argv, 0)


def segment_facts(index, assigns, argv):
    """The indexed facts readable from one segment without resolving a git subcommand."""
    facts = [_seg("SEG_ENV", index, name)
             for name in assigns if name.startswith(GIT_ENV_PREFIX)]
    if not argv:
        return facts
    if argv[0] == "cd":
        facts.append(_seg("SEG_CD", index, cd_operand(argv)))
        return facts
    if argv[0] == "git":
        return facts
    token = opaque_token(argv)
    if token is not None:
        facts.append(_seg("SEG_OPAQUE", index, token))
    return facts


def git_subcommand_facts(index, subcommand, rest):
    """The indexed facts that need the resolved git subcommand."""
    if subcommand == "worktree" and rest and rest[0] == "add":
        return [_seg("SEG_WORKTREE_ADD", index, worktree_add_path(rest[1:]))]
    if is_branch_move(subcommand, rest):
        return [_seg("SEG_BRANCH_MOVE", index, subcommand)]
    return []


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
    # SEG_GROUPED is a CONJUNCTION -- grouping AND a cd. With no cd there is nothing
    # for a grouping operator to carry to the wrong segment, so nothing to refuse.
    saw_cd = False

    segs = segments(src)
    # segments() returns [] both for a genuinely empty command and for one shlex cannot
    # parse, and its docstring calls the latter a deliberate fail-OPEN. This is the one
    # caller that overrides that policy: an empty fact set reads as "nothing here", and
    # this guard is the last line of defence, which the module's rationale is not
    # written for. Measured: `git worktree add "unclosed` produced no output and exit 0,
    # so a caller checking only the exit code never learns anything happened.
    if not segs and src.strip():
        facts.add("SEG_UNPARSED")

    for index, (assigns, argv) in enumerate(segs):
        # Collected for EVERY segment, git or not: a `cd` was never seen here before,
        # so `cd /tmp/other && git worktree add /tmp/x` emitted nothing at all.
        indexed = segment_facts(index, assigns, argv)
        facts.update(indexed)
        saw_cd = saw_cd or any(f.startswith("SEG_CD\t") for f in indexed)

        if len(argv) < 2 or argv[0] != "git":
            continue
        subcommand, rest, blocking_option, residual_option, c_operands = \
            resolve_git_segment(argv)

        if c_operands:
            # The shared resolution rule applies ONE `-C` per segment. Two of them
            # compose in git and would have to compose here too, so more than one is
            # unresolvable rather than quietly resolved to the wrong directory.
            facts.add(_seg("SEG_GIT_C", index,
                           c_operands[0] if len(c_operands) == 1 else UNRESOLVABLE))
        if residual_option is not None:
            facts.add(_seg("SEG_SCOPE_OPT", index, residual_option))
        elif subcommand is not None:
            facts.update(git_subcommand_facts(index, subcommand, rest))

        if blocking_option is not None:
            if scope_unknown is None:
                scope_unknown = blocking_option
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

    # segments() appends a fresh segment per control operator and throws the operator
    # away, so `)` and `}` are indistinguishable in its return value -- yet bash
    # discards a cd at `)` and keeps it past `}`. Measured, `( cd /tmp/other && git log
    # ) && git switch main` lexes to indices 0..4, so an index-ordered rule carries the
    # subshell's cd to index 4 where bash would not. This OVER-DENIES the `( ... )`
    # case, refusing a command that was in fact safe; that is the correct direction.
    if saw_cd and has_grouping(src):
        facts.add("SEG_GROUPED")

    return sorted(facts)


def main():
    facts = classify(sys.stdin.read())
    sys.stdout.write("".join(f + "\n" for f in facts))


if __name__ == "__main__":
    main()
