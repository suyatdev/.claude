#!/usr/bin/env python3
"""Unit tests for classify-git-command.py. Run: python3 hooks/lib/classify-git-command.test.py

The hook-level suites (git-guard.test.sh, doc-guard.test.sh) drive the real code path and
prove the guards block what they should. This file pins the classifier's answers directly,
so a shape can be added and reasoned about without standing up a git repo -- the same
argument that produced classify-pr-command.test.py.

Deliberately dependency-free (no pytest): adding a dependency is not a unilateral call, and
this has to run anywhere the hook runs.
"""

import importlib.util
import os
import subprocess
import sys

MARKER_SELF = os.path.abspath(__file__)
# cwd=dirname(MARKER_SELF), never the inherited process cwd: this file is also run as a nested
# subprocess by judge-guard.test.sh from inside a throwaway repo, where the ambient cwd resolves
# to that fixture's toplevel, not this one's.
MARKER_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=os.path.dirname(MARKER_SELF),
                             capture_output=True, text=True, check=True).stdout.strip()

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "classify_git_command", os.path.join(_HERE, "classify-git-command.py")
)
_MOD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MOD)
classify = _MOD.classify

# (command, expected facts, why)
CASES = [
    # --- commit, plain ---
    ("git commit", ["COMMIT"], "bare"),
    ("git commit -m msg", ["COMMIT"], "with a message"),
    ("rtk git commit -m msg", ["COMMIT"], "the rtk hook rewrites git commands before we see them"),
    ("time rtk git commit", ["COMMIT"], "wrappers stack, so stripping loops"),
    ("GIT_AUTHOR_NAME=x git commit", ["COMMIT"], "env prefix does not hide the command"),

    # --- commit, chained. THE bug: every one of these used to yield nothing at all. ---
    ("git add -- x && git commit -m msg", ["COMMIT"], "&& -- the shape that let commits reach main"),
    ("git add -- x&&git commit -m msg", ["COMMIT"], "unspaced && needs punctuation_chars"),
    ("git add -- x ; git commit -m msg", ["COMMIT"], "; separator"),
    ("false || git commit -m msg", ["COMMIT"], "|| separator"),
    ("git add -- x\ngit commit -m msg", ["COMMIT"], "newline ends a command exactly as ; does"),
    ("git add -- x && \\\ngit commit", ["COMMIT"], "backslash-newline is a CONTINUATION"),
    ("( git commit )", ["COMMIT"], "subshell"),
    ("{ git commit; }", ["COMMIT"], "brace group -- { is not a shlex punctuation char by default"),

    # --- not a commit. False positives block real work, which for a momentum guardrail is
    # --- worse than a rare miss, so these are load-bearing.
    ('echo "remember to git commit"', [], "argument, not a command"),
    ('git log --grep "git commit"', [], "quoted text can never hold a command position"),
    ('git commit -m "see git push --force"', ["COMMIT"], "the message is one token; only the commit counts"),
    ("git committed", [], "not the commit subcommand"),
    ("mytool commit", [], "commit without git at the command position"),
    ("git", [], "bare git has no subcommand"),
    ("", [], "empty input"),
    ("   ", [], "whitespace only"),
    ("unbalanced ' quote git commit", [], "unparseable -> fail OPEN, by design"),

    # --- commit -a family: stages tracked edits at commit time, so the guard must diff HEAD ---
    ("git commit -am msg", ["COMMIT", "COMMIT_ALL"], "combined short form"),
    ("git commit -a -m msg", ["COMMIT", "COMMIT_ALL"], "separate short form"),
    ("git commit --all -m msg", ["COMMIT", "COMMIT_ALL"], "long form"),
    ("git fetch && git commit -am msg", ["COMMIT", "COMMIT_ALL"], "chained, still --all"),
    # Searching the whole string for `-a` made an unrelated segment change which files
    # doc-guard judged. The flag binds to its own command.
    ("git commit -m msg && ls -a", ["COMMIT"], "-a belongs to ls, not to the commit"),
    ("ls -a && git commit -m msg", ["COMMIT"], "same, ordered the other way"),

    # --- push ---
    ("git push", ["PUSH"], "plain"),
    ("git push --force", ["PUSH", "PUSH_FORCE"], "bare force"),
    ("git push -f", ["PUSH", "PUSH_FORCE"], "short bare force"),
    ("git push origin main -f", ["PUSH", "PUSH_FORCE"], "flag after positionals"),
    ("git fetch && git push --force", ["PUSH", "PUSH_FORCE"], "chained -- used to yield nothing"),
    ("git push --force-with-lease", ["PUSH", "PUSH_LEASE"], "leased, never bare"),
    ("git push --force-with-lease=main:abc123", ["PUSH", "PUSH_LEASE"], "leased with a ref"),
    ("git fetch && git push --force-with-lease", ["PUSH", "PUSH_LEASE"], "chained lease"),

    # Both of these were wrong before, in opposite directions, because the shell version
    # searched the entire command string for each flag independently.
    ("git push --force && echo --force-with-lease",
     ["PUSH", "PUSH_FORCE"], "a lease in ANOTHER segment must not excuse this bare force"),
    ("git push && echo --force", ["PUSH"], "a force flag in another segment is not this push's"),
    ("echo --force && git push", ["PUSH"], "same, ordered the other way"),
    ('git push -m "do not use --force"', ["PUSH"], "quoted text is one token"),
    ("git push --force --force-with-lease",
     ["PUSH", "PUSH_LEASE"], "same segment: the lease wins, matching the old precedence"),

    # --- several segments, several facts ---
    ("git commit -m msg && git push --force",
     ["COMMIT", "PUSH", "PUSH_FORCE"], "facts accumulate across segments"),

    # --- accepted-open shapes, pinned so closing one is a decision with a failing test ---
    ('eval "git commit"', [], "quoted eval argument cannot reach a command position"),
    ("env git commit", [], "wrapper list is a denylist; env is not in it"),
    ("timeout 30 git commit", [], "denylist gap"),
    ("G=git; $G commit", [], "variable indirection is invisible to lexing"),
    ("git commit -m '-a'", ["COMMIT", "COMMIT_ALL"],
     "option values are not tracked; reading a `-a` message as --all errs toward inspecting more"),

    # --- pathspec and --amend, needed because an EMPTY index at hook time cannot
    # --- say what a commit will contain. Paths ride as `COMMIT_PATH\t<path>` so a
    # --- path containing whitespace survives; a tab sorts before `S`, which is why
    # --- COMMIT_PATH entries land ahead of COMMIT_PATHSPEC.
    ("git commit -m msg -- docs/x.md",
     ["COMMIT", "COMMIT_PATH\tdocs/x.md", "COMMIT_PATHSPEC"],
     "after `--` every token is definitively a path"),
    ("git commit -- a.md src/b.sh",
     ["COMMIT", "COMMIT_PATH\ta.md", "COMMIT_PATH\tsrc/b.sh", "COMMIT_PATHSPEC"],
     "several paths after the separator"),
    ("git commit --amend --no-edit", ["COMMIT", "COMMIT_AMEND"],
     "--amend re-writes HEAD's tree, which the index does not show"),

    # Without `--`, telling a path from an option VALUE needs a table of which
    # flags take arguments. The table below covers git commit's documented ones;
    # anything left over is a suspected path and the hook's fail direction is block.
    ("git commit -m msg", ["COMMIT"],
     "-m consumes its value, so nothing here is a stray path"),
    ("git commit -m msg docs/x.md", ["COMMIT", "COMMIT_BARE_ARGS"],
     "a token surviving the flag table is a suspected pathspec with no separator"),
    ("git commit -am msg", ["COMMIT", "COMMIT_ALL"],
     "-am is -a plus -m, so it consumes the message that follows"),
    ("git commit --message=x", ["COMMIT"],
     "an inline long-option value consumes no following token"),
    ("git commit -a -m msg", ["COMMIT", "COMMIT_ALL"],
     "-a takes no value; -m does"),

    # --- what a SIBLING command stages is deliberately not modelled. `git add` was
    # --- once reported as ADD_PATH/ADD_ALL facts so the guard could add them to the
    # --- commit's file set; that enumeration was abandoned, because `git add` is one
    # --- of at least ten commands that fill the index (rm, mv, reset --soft,
    # --- checkout -- , restore --staged, apply --cached, stash pop --index,
    # --- cherry-pick -n, revert -n) and two review rounds each found the list short.
    # --- The guard now trusts only what the COMMIT ITSELF names. See ADR 0014.
    ("git add -- src/x.sh && git commit -m msg", ["COMMIT"],
     "the add is not modelled; the commit names no paths, which is what makes it block"),
    ("git add src/x.sh", [],
     "a `git add` on its own commits nothing, so there is nothing to report"),
    ("git add -A && git commit -m msg", ["COMMIT"],
     "-A stages everything -- still not the classifier's business"),
    ("git rm src/x.sh && git commit -m msg", ["COMMIT"],
     "one of the nine other staging commands; identical treatment, no entry needed"),
    ("git cherry-pick -n abc123 && git commit -m msg", ["COMMIT"],
     "and another -- not enumerating them is the point"),

    # --- options the hook cannot understand must fail closed, not sail through.
    # --- git accepts any unambiguous prefix of a long option, so an exact-match
    # --- test for `--amend` is not a test for amending.
    ("git commit --amen --no-edit", ["COMMIT", "COMMIT_BARE_ARGS"],
     "an abbreviation git honours but this table does not recognise"),
    ("git commit --pathspec-from-file=list", ["COMMIT", "COMMIT_BARE_ARGS"],
     "the paths live in a file the hook cannot read"),
    ("git commit --some-future-option", ["COMMIT", "COMMIT_BARE_ARGS"],
     "an unrecognised option could mean anything, including a wider file set"),

    # ...and the ordinary harmless ones must not start blocking real work.
    ("git commit --no-edit -m msg", ["COMMIT"], "known-harmless option"),
    ("git commit --no-verify -m msg", ["COMMIT"], "known-harmless option"),
    ("git commit -q --signoff -m msg", ["COMMIT"], "known-harmless short and long forms"),

    # --- the flags BEFORE a `--` decide whether the paths after it are the WHOLE
    # --- commit. `-i`/`--include` commits the index as well, so the pathspec is not
    # --- exclusive; `-o`/`--only` is not understood either. A `--` used to return
    # --- the paths immediately, skipping the flag table entirely, so this whole
    # --- family reported a clean pathspec and the guard trusted it.
    ("git commit -i -m msg -- docs/x.md", ["COMMIT", "COMMIT_BARE_ARGS"],
     "-i ALSO commits the index, so the paths after `--` are not the whole commit"),
    ("git commit --include -m msg -- docs/x.md", ["COMMIT", "COMMIT_BARE_ARGS"],
     "long form of the same"),
    ("git commit -o -m msg -- docs/x.md", ["COMMIT", "COMMIT_BARE_ARGS"],
     "-o/--only is unrecognised, and unrecognised means cannot tell"),
    ("git commit --only -m msg -- docs/x.md", ["COMMIT", "COMMIT_BARE_ARGS"],
     "long form of the same"),
    ("git commit -i -m msg docs/x.md", ["COMMIT", "COMMIT_BARE_ARGS"],
     "with no separator this blocked already -- by the stray-token rule, not by -i"),

    # --amend and -a ride ALONGSIDE a pathspec and commit more than it names, so
    # that segment does not describe itself and the path facts are WITHHELD --
    # they would otherwise read as the commit's whole file set. The widening
    # flag is still reported in its own right.
    ("git commit --amend -m msg -- docs/x.md",
     ["COMMIT", "COMMIT_AMEND"],
     "--amend re-writes HEAD's tree on top of whatever the pathspec names"),
    ("git commit -a -m msg -- docs/x.md",
     ["COMMIT", "COMMIT_ALL"],
     "-a widens to tracked worktree edits, so the named paths are not the whole commit"),

    # --- ONE LINE, SEVERAL COMMITS. Facts arrive as a flat set with no segment
    # --- identity, so a fact that GRANTS permission has to be true of the whole
    # --- line; a fact that DENIES may be true of any one segment. PUSH_FORCE
    # --- already follows this rule in the denying direction. COMMIT_PATHSPEC is
    # --- the only granting fact, and a second commit naming nothing used to hide
    # --- behind the first one's paths -- the union read as documentation while
    # --- the second commit really carried the source file the chain had staged.
    ("git commit -m a -- docs/a.md && git add -- src/b.sh && git commit -m b",
     ["COMMIT"],
     "the second commit names nothing, so no path fact describes this line"),
    ("git commit -m a && git commit -m b -- docs/a.md",
     ["COMMIT"],
     "order does not matter: one unscoped commit is enough"),
    ("git commit -m a -- docs/a.md ; git commit -m b",
     ["COMMIT"],
     "every separator the lexer knows, not just &&"),
    ("git commit -m a -- docs/a.md && git commit -a -m b",
     ["COMMIT", "COMMIT_ALL"],
     "a widened second commit is unscoped for the same reason a bare one is"),
    ("git commit -m a -- docs/a.md && git commit -m b -- docs/b.md",
     ["COMMIT", "COMMIT_PATH\tdocs/a.md", "COMMIT_PATH\tdocs/b.md", "COMMIT_PATHSPEC"],
     "every commit names its own paths, so their union IS the line's file set"),
]


def main():
    passed = failed = 0
    for cmd, want, why in CASES:
        got = classify(cmd)
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL — {!r} ({})\n       want {!r}, got {!r}".format(cmd, why, want, got))
    print("\ngit classifier unit: {} passed, {} failed".format(passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    _rc = main()
    if _rc == 0:
        subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF],
                       cwd=MARKER_ROOT, check=True)
    sys.exit(_rc)
