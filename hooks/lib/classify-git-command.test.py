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
import shlex
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
    ("GIT_AUTHOR_NAME=x git commit", ["COMMIT", "SEG_ENV\t0\tGIT_AUTHOR_NAME"],
     "env prefix does not hide the command -- and now names itself, because the fact's "
     "test is the GIT_ PREFIX, not a list of variables"),

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
    ("unbalanced ' quote git commit", ["SEG_UNPARSED"],
     "segments() still returns [] -- its documented fail-OPEN -- but an ABSENT fact reads "
     "as 'nothing here', so this classifier says so out loud and its callers fail closed"),

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
    ('eval "git commit"', ["SEG_OPAQUE\t0\tgit commit"],
     "WRAPPERS strips eval, leaving the whole command as argv[0]; clause 3b re-lexes it "
     "like any other collapsed token, so no special case for eval is needed"),
    ("env git commit", ["SEG_OPAQUE\t0\tenv"],
     "the WRAPPERS denylist gap, closed by a rule about argv[0] rather than a sixth list"),
    ("timeout 30 git commit", ["SEG_OPAQUE\t0\ttimeout"], "the same denylist gap"),
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
    ("git cherry-pick -n abc123 && git commit -m msg",
     ["COMMIT", "SEG_BRANCH_MOVE\t0\tcherry-pick"],
     "and another -- not enumerating them is the point. The cherry-pick is ALSO a HEAD "
     "move, which is a different question from what it stages"),

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

    # =========================================================================
    # global-option-blindness (docs/features/global-option-blindness.md, task 1,
    # RED). Today argv[1] is read as the subcommand unconditionally, so a leading
    # global option makes the whole segment yield NO facts at all -- the bug this
    # feature exists to fix. Fact output only, per this file's own docstring:
    # the SAME options also get hook-level exit-code/ask-decision cases in
    # git-guard.test.sh (task 3) and doc-guard.test.sh (task 4) -- not here.
    # =========================================================================

    # --- bucket 1, table 1: harmless, no value, command still seen ---
    ("git --no-pager commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 harmless-skip"),
    ("git -p commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 harmless-skip"),
    ("git --paginate commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 harmless-skip"),
    ("git --no-optional-locks commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 harmless-skip"),
    ("git --no-advice commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 harmless-skip"),
    ("git --no-replace-objects commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 harmless-skip"),
    ("git --no-lazy-fetch commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 harmless-skip"),
    ("git -P commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 harmless-skip"),

    # --- bucket 1, table 2: the print-and-exit set. Same fact-level outcome as
    # --- table 1 -- classify() does not model "prints and exits"; only
    # --- git-guard.sh's MESSAGE differs for these (task 3b), never the fact.
    ("git --exec-path commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"],
     "bucket 1, attach-only: must not swallow the subcommand as its value"),
    ("git --version commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 print-and-exit"),
    ("git -v commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 print-and-exit"),
    ("git --help commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 print-and-exit"),
    ("git -h commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 print-and-exit"),
    ("git --html-path commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 print-and-exit"),
    ("git --man-path commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 print-and-exit"),
    ("git --info-path commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1 print-and-exit"),
    ("git --list-cmds commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"], "bucket 1, attached value form"),
    ("git --list-cmds=main commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"],
     "attached spelling with a value must not eat the subcommand either"),

    # --attr-source is bucket 1 but CONSUMES a value, so it needs its own two
    # scenarios rather than the shared table template (neither table can host
    # it). Measured against git 2.50.1 -- see the spec's own measurement.
    ("git --attr-source .gitattributes commit -m x -- app.js",
     ["COMMIT", "COMMIT_PATH\tapp.js", "COMMIT_PATHSPEC"],
     "the value is consumed; the subcommand still resolves to commit"),
    ("git --attr-source commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t-m", "SEG_SCOPE_OPT\t0\t-m"],
     "commit is consumed as attr-source's VALUE, so git itself commits nothing; "
     "-m is left in subcommand position, unrecognised -> bucket 3"),

    # --- bucket 2: repo-redirecting, refused and asked. Fact level: exactly one
    # --- SCOPE_UNKNOWN fact naming the option, and no COMMIT fact for the segment.
    ("git -C commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t-C", "SEG_GIT_C\t0\tcommit", "SEG_SCOPE_OPT\t0\t-m"],
     "`commit` really is -C's operand here, so git would chdir into a directory of that "
     "name; walking past the pair leaves -m in subcommand position, which is bucket 3"),
    ("git --git-dir commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t--git-dir", "SEG_SCOPE_OPT\t0\t--git-dir"], "bucket 2 redirecting"),
    ("git --work-tree commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t--work-tree", "SEG_SCOPE_OPT\t0\t--work-tree"], "bucket 2 redirecting"),
    ("git --namespace commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t--namespace", "SEG_SCOPE_OPT\t0\t--namespace"], "bucket 2 redirecting"),
    ("git --bare commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t--bare", "SEG_SCOPE_OPT\t0\t--bare"],
     "takes no value but still redirects the repo -- bucket 2, not bucket 1"),
    ("git -c commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t-c", "SEG_SCOPE_OPT\t0\t-c"], "bucket 2 redirecting"),
    ("git --config-env commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t--config-env", "SEG_SCOPE_OPT\t0\t--config-env"], "bucket 2 redirecting"),
    ("git --literal-pathspecs commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t--literal-pathspecs", "SEG_SCOPE_OPT\t0\t--literal-pathspecs"],
     "changes what a pathspec MEANS, which doc-guard's exemption is decided from"),
    ("git --glob-pathspecs commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t--glob-pathspecs", "SEG_SCOPE_OPT\t0\t--glob-pathspecs"],
     "bucket 2, pathspec-modifying"),
    ("git --noglob-pathspecs commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t--noglob-pathspecs", "SEG_SCOPE_OPT\t0\t--noglob-pathspecs"],
     "bucket 2, pathspec-modifying"),
    ("git --icase-pathspecs commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t--icase-pathspecs", "SEG_SCOPE_OPT\t0\t--icase-pathspecs"],
     "bucket 2, pathspec-modifying"),

    # --- bucket 3: unrecognised, including an abbreviation nobody enumerated --
    # --- git honours unambiguous abbreviations, so a list of exact spellings
    # --- can never be complete.
    ("git --work-tre=/tmp commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t--work-tre", "SEG_SCOPE_OPT\t0\t--work-tre"],
     "an abbreviated option nobody enumerated is still refused, named without its value"),

    # A value-consuming bucket-2 option's value is never mistaken for the
    # subcommand or a pathspec -- the fact set has nothing but the one denial.
    ("git --git-dir /tmp/x commit -m y -- app.js",
     ["SCOPE_UNKNOWN\t--git-dir", "SEG_SCOPE_OPT\t0\t--git-dir"],
     "/tmp/x is the option's value, never a subcommand or a pathspec"),

    # SCOPE_UNKNOWN is a DENYING fact: it suppresses PUSH*/PUSH_FORCE for its own
    # segment too, not just COMMIT*. No scenario elsewhere used push, so nothing
    # could fail if an implementer wired the suppression to commit only.
    ("git -C . push --force", ["SCOPE_UNKNOWN\t-C", "SEG_GIT_C\t0\t."],
     "force-push protection survives a global option -- no PUSH or PUSH_FORCE fact. The "
     "INDEXED fact still lands: it carries its own scope and needs no suppression"),

    # At most once per line, from the FIRST triggering option.
    ("git -c a=b -C /x commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t-c", "SEG_SCOPE_OPT\t0\t-c"],
     "two triggering options in one segment -- exactly one fact, naming the first"),

    # SCOPE_UNKNOWN denies the whole LINE even from a non-first segment, because
    # it is a denying fact under the module's existing granting/denying rule.
    ("echo hi && git -C /x commit -m x -- app.js",
     ["SCOPE_UNKNOWN\t-C", "SEG_GIT_C\t1\t/x"],
     "a redirecting option in a later segment still denies the whole line -- and the "
     "indexed fact names segment 1, so nothing can apply this -C to segment 0"),

    # =========================================================================
    # worktree-location-guard, task 5: the nine SEG_* facts.
    #
    # Every fact above is a flat SET member with no segment identity, which is
    # what forced the granting/denying rule at the top of the module. These nine
    # carry the index segments() already produces, so each is judged on its own
    # and no fact can vouch for a segment it did not come from. The seven indexed
    # facts are `SEG_X<tab><i><tab><operand>`; SEG_UNPARSED and SEG_GROUPED are
    # line-scoped and carry no index.
    #
    # A tab sorts before every letter, so the facts for one name group together
    # and segment 0 sorts ahead of segment 1.
    # =========================================================================

    # --- SEG_CD. The classifier used to skip every non-git segment outright, so
    # --- none of these emitted anything at all -- measured before the change.
    ("cd /tmp/other && git worktree add /tmp/x",
     ["SEG_CD\t0\t/tmp/other", "SEG_WORKTREE_ADD\t1\t/tmp/x"],
     "the card's measured example: this emitted NOTHING before, in either fact"),
    ("cd /repos/other && git worktree add ~/.worktrees/.claude/x",
     ["SEG_CD\t0\t/repos/other", "SEG_WORKTREE_ADD\t1\t~/.worktrees/.claude/x"],
     "THE MATCHING cd CASE -- Arm B2 judged this against the session repo and allowed it. "
     "The tilde is never expanded by the lexer, so the operand rides as typed"),
    ("cd /a && cd b && git switch main",
     ["SEG_BRANCH_MOVE\t2\tswitch", "SEG_CD\t0\t/a", "SEG_CD\t1\tb"],
     "shared-rule row: each cd resolved relative to the one before, so /a then /a/b. The "
     "classifier reports them in index order; composing them is the guard's job, not this file's"),
    ('cd "$d" && git switch main',
     ["SEG_BRANCH_MOVE\t1\tswitch", "SEG_CD\t0\tUNRESOLVABLE"],
     "shared-rule row: a variable operand. The guard denies naming $d and segment 0, which it "
     "reads off the raw command line -- the SENTINEL is what the fact stream carries"),
    ("cd $(pwd) && git switch main",
     ["SEG_BRANCH_MOVE\t3\tswitch", "SEG_CD\t0\tUNRESOLVABLE", "SEG_GROUPED"],
     "a subshell operand: shlex splits at the paren, so cd's operand is the bare `$` -- "
     "unresolvable, and the parens make the line grouped as well"),
    ("cd", ["SEG_CD\t0\tUNRESOLVABLE"], "no operand at all"),
    ("cd -", ["SEG_CD\t0\tUNRESOLVABLE"],
     "`cd -` is $OLDPWD, which no amount of lexing can resolve. Any operand starting with `-` "
     "is unresolvable, which covers `cd -P /tmp` by the same rule rather than a fourth list"),
    ("cd /tmp", ["SEG_CD\t0\t/tmp"], "the plain form"),
    ("cd /x", ["SEG_CD\t0\t/x"], "a cd with no git anywhere on the line still reports itself"),

    # --- SEG_GIT_C. Collected BEFORE the SCOPE_UNKNOWN continue, which used to
    # --- abandon a -C segment before it could emit anything.
    ("git -C /repos/other log && git switch main",
     ["SCOPE_UNKNOWN\t-C", "SEG_BRANCH_MOVE\t1\tswitch", "SEG_GIT_C\t0\t/repos/other"],
     "THE -C-DOES-NOT-CARRY-FORWARD CASE. The -C is bound to segment 0 and the switch to "
     "segment 1, so nothing can apply one to the other -- the exact incident this feature exists "
     "to stop, which the old unindexed GIT_DIR_OPT fact would have allowed"),
    ("git -C /repos/other switch main",
     ["SCOPE_UNKNOWN\t-C", "SEG_BRANCH_MOVE\t0\tswitch", "SEG_GIT_C\t0\t/repos/other"],
     "THE DISCRIMINATING -C CASE: same index on both facts, so this switch IS judged against "
     "/repos/other. Compare the row above -- identical fact NAMES, opposite meaning"),
    ("git -C /repos/other worktree add /tmp/x",
     ["SCOPE_UNKNOWN\t-C", "SEG_GIT_C\t0\t/repos/other", "SEG_WORKTREE_ADD\t0\t/tmp/x"],
     "the indexed facts survive the -C bail. Stopping at it would leave Arm B2 with nothing "
     "but SCOPE_UNKNOWN, which no arm denies on -- a silent fail-open"),
    ("git -C", ["SCOPE_UNKNOWN\t-C", "SEG_GIT_C\t0\tUNRESOLVABLE"], "-C with no operand"),
    ("git -C=/x commit -m y",
     ["SCOPE_UNKNOWN\t-C", "SEG_GIT_C\t0\tUNRESOLVABLE", "SEG_SCOPE_OPT\t0\t-m"],
     "an ATTACHED spelling. git's own short-option grammar puts the value at `=/x`, and "
     "modelling that grammar is the trap this file exists to avoid -- so it is unresolvable"),
    ("git -C /a -C /b switch main",
     ["SCOPE_UNKNOWN\t-C", "SEG_BRANCH_MOVE\t0\tswitch", "SEG_GIT_C\t0\tUNRESOLVABLE"],
     "git composes repeated -C; the shared rule resolves ONE operand per segment, so two is "
     "unresolvable rather than quietly resolved to the wrong one"),

    # --- SEG_WORKTREE_ADD ---
    ("git worktree add ../a && git worktree add ../b",
     ["SEG_WORKTREE_ADD\t0\t../a", "SEG_WORKTREE_ADD\t1\t../b"],
     "THE TWO-ADDS-ON-ONE-LINE CASE. A flat set would collapse these into one unlocatable "
     "fact; indexed, each add is judged against its own segment's effective repo"),
    ("git worktree add ../a", ["SEG_WORKTREE_ADD\t0\t../a"], "the plain form"),
    ("git worktree add -b feat/x ../a", ["SEG_WORKTREE_ADD\t0\t../a"],
     "-b consumes its value, so the branch name is not mistaken for the path"),
    ('git worktree add --reason "parked for review" ../a', ["SEG_WORKTREE_ADD\t0\t../a"],
     "--reason consumes its value too, and the value holds spaces"),
    ("git worktree add --detach ../a", ["SEG_WORKTREE_ADD\t0\t../a"],
     "a no-value option is walked past"),
    ("git worktree add ../a origin/main", ["SEG_WORKTREE_ADD\t0\t../a"],
     "the commit-ish after the path is not a second path operand"),
    ("git worktree add", ["SEG_WORKTREE_ADD\t0\tUNRESOLVABLE"], "no path operand"),
    ("git worktree add --some-future-option ../a", ["SEG_WORKTREE_ADD\t0\tUNRESOLVABLE"],
     "an unrecognised option might or might not consume ../a, so which token is the path "
     "cannot be told -- the same fail-closed asymmetry as COMMIT_SAFE_FLAGS"),
    ("git worktree list", [], "not an add"),
    ("git worktree remove ../a", [], "not an add; removing one is not misplacing one"),

    # --- SEG_BRANCH_MOVE. In scope: HEAD moves and wholesale working-tree
    # --- overwrites. The list is a known under-block and that direction is
    # --- deliberate -- an unrecognised subcommand is allowed.
    ("git switch main", ["SEG_BRANCH_MOVE\t0\tswitch"], "in scope: switch in every form"),
    ("git switch -c feat/x", ["SEG_BRANCH_MOVE\t0\tswitch"], "in scope: -c"),
    ("git switch --detach", ["SEG_BRANCH_MOVE\t0\tswitch"], "in scope: --detach"),
    ("git switch -", ["SEG_BRANCH_MOVE\t0\tswitch"], "in scope: previous branch"),
    ("git checkout main", ["SEG_BRANCH_MOVE\t0\tcheckout"], "in scope: checkout a branch"),
    ("git checkout -b feat/x", ["SEG_BRANCH_MOVE\t0\tcheckout"], "in scope: -b"),
    ("git checkout --detach", ["SEG_BRANCH_MOVE\t0\tcheckout"], "in scope: --detach"),
    ("git merge --ff-only main", ["SEG_BRANCH_MOVE\t0\tmerge"],
     "the session-state.md:85 incident -- a stray `git merge --ff-only`, which the round-1 "
     "design and the first version of Arm D both missed"),
    ("git pull", ["SEG_BRANCH_MOVE\t0\tpull"], "in scope"),
    ("git rebase main", ["SEG_BRANCH_MOVE\t0\trebase"], "in scope"),
    ("git reset --hard HEAD~1", ["SEG_BRANCH_MOVE\t0\treset"], "in scope: reset without a pathspec"),
    ("git reset", ["SEG_BRANCH_MOVE\t0\treset"], "in scope: every form except a `--` pathspec"),
    ("git cherry-pick abc123", ["SEG_BRANCH_MOVE\t0\tcherry-pick"], "in scope"),
    ("git revert abc123", ["SEG_BRANCH_MOVE\t0\trevert"], "in scope"),
    ("git stash pop", ["SEG_BRANCH_MOVE\t0\tstash"], "in scope: stash pop overwrites the tree"),
    ("git stash apply", ["SEG_BRANCH_MOVE\t0\tstash"], "in scope: stash apply"),
    # Out of scope: these touch NAMED PATHS, not HEAD. A false denial here blocks
    # ordinary work, which for a momentum guardrail is the more expensive error.
    ("git checkout -- docs/a.md", [], "out: a pathspec checkout touches named paths, not HEAD"),
    ("git checkout main -- docs/a.md", [], "out: same, with a ref in front of the separator"),
    ("git restore docs/a.md", [], "out: restore in any form"),
    ("git restore --staged --worktree docs/a.md", [], "out: restore in any form"),
    ("git reset -- docs/a.md", [], "out: reset carrying a `--` pathspec"),
    ("git stash", [], "out: bare stash. The card's in-scope list names pop and apply only, and "
                     "the under-block direction is the one it chose deliberately"),
    ("git stash list", [], "out: read-only"),
    ("git status", [], "out: read-only"),
    ("git log --oneline", [], "out: read-only"),
    ("git fetch", [], "out: fetch moves no local HEAD"),

    # --- SEG_SCOPE_OPT. Emitted from blocking_option's RETURN VALUE by a
    # --- two-clause test, never from a list of option names, so an option git
    # --- adds tomorrow lands in "cannot tell" rather than in "allow".
    ("git --git-dir /tmp/o/.git switch main",
     ["SCOPE_UNKNOWN\t--git-dir", "SEG_SCOPE_OPT\t0\t--git-dir"],
     "the redirect denies rather than joining the cd/-C resolution path, because the fact "
     "stream carries the option NAME and never its value"),
    ("git --git-dir=/tmp/o/.git switch main",
     ["SCOPE_UNKNOWN\t--git-dir", "SEG_SCOPE_OPT\t0\t--git-dir"],
     "measured: byte-identical output to the separate-token form above. The value survives "
     "only in argv, which is precisely why this class cannot be resolved"),
    ("git --future-option switch main",
     ["SCOPE_UNKNOWN\t--future-option", "SEG_SCOPE_OPT\t0\t--future-option"],
     "bucket 3. Nothing in this file names --future-option, and it still denies"),

    # --- SEG_ENV. A PREFIX test over the namespace git owns, so a variable added
    # --- upstream is covered the day it ships.
    ("GIT_DIR=/tmp/o/.git git commit -m x", ["COMMIT", "SEG_ENV\t0\tGIT_DIR"],
     "measured: this used to emit exactly COMMIT -- byte-identical to a purely local commit, "
     "with the redirect nowhere in the output"),
    ("GIT_WORK_TREE=/tmp/o git switch main",
     ["SEG_BRANCH_MOVE\t0\tswitch", "SEG_ENV\t0\tGIT_WORK_TREE"], "another confirmed member"),
    ("GIT_INDEX_FILE=/tmp/i git commit", ["COMMIT", "SEG_ENV\t0\tGIT_INDEX_FILE"], "another"),
    ("GIT_NO_SUCH_VARIABLE_YET=x git commit",
     ["COMMIT", "SEG_ENV\t0\tGIT_NO_SUCH_VARIABLE_YET"],
     "THE POINT OF THE PREFIX TEST: git has never shipped this name, and it is covered anyway"),
    ("GIT_DIR=/a GIT_WORK_TREE=/b git commit",
     ["COMMIT", "SEG_ENV\t0\tGIT_DIR", "SEG_ENV\t0\tGIT_WORK_TREE"],
     "one fact per entry in the segment's assignments dict"),
    ("FOO=bar git commit", ["COMMIT"], "a non-GIT_ assignment is not this rule's business"),
    ("GITFOO=x git commit", ["COMMIT"],
     "GIT without the underscore is outside the namespace git owns -- the test is on `GIT_`"),
    ("echo hi && GIT_DIR=/a git commit", ["COMMIT", "SEG_ENV\t1\tGIT_DIR"],
     "the assignment binds to its own segment, which is what segments() already guaranteed"),

    # --- SEG_OPAQUE clause 3a: a bare token. argv[0] is neither git nor cd, yet
    # --- one of them appears later in argv, so nothing holds argv[0] accountable.
    ("env -C /tmp/other git switch main", ["SEG_OPAQUE\t0\tenv"],
     "`env -C` works on this host (measured: /usr/bin/env -C /tmp pwd prints /tmp) -- a live "
     "HEAD move against another repo that was wholly invisible before"),
    ("timeout 5 git commit -m x", ["SEG_OPAQUE\t0\ttimeout"],
     "named in the WRAPPERS comment as knowingly open"),
    ("env GIT_DIR=/tmp/o/.git git commit -m x", ["SEG_OPAQUE\t0\tenv"],
     "defeats derivation 2 as well: behind env the assignment is an ordinary argv token, so "
     "no SEG_ENV fact is possible and 3a is the only thing that sees it"),
    ("if cd /tmp/other; then git commit -m x; fi",
     ["SEG_OPAQUE\t0\tif", "SEG_OPAQUE\t1\tthen"],
     "if/then hold the command position. Covered by one rule about argv[0], not by adding "
     "`if` and `then` to a sixth list of wrapper words"),
    ("./myscript.sh", [],
     "NON-GOAL, pinned as a MEASURED ALLOW: the guard cannot read a script file. Widening to "
     "catch this means reading arbitrary files, which is not lexing"),

    # --- SEG_OPAQUE clause 3b: a collapsed token. Re-lex every whitespace-bearing
    # --- token; fire if any inner segment holds git or cd at argv[0]. COMMAND
    # --- POSITION, not presence -- the wider form was measured and rejected.
    ("sh -c 'git switch main'", ["SEG_OPAQUE\t0\tgit switch main"],
     "the quoted-command half of the WRAPPERS comment, which said such a token `can never "
     "reach a command position` -- so the rule re-lexes until it can"),
    ('bash -c "git switch main"', ["SEG_OPAQUE\t0\tgit switch main"], "same shape"),
    ("zsh -c 'git switch main'", ["SEG_OPAQUE\t0\tgit switch main"],
     "no shell name and no -c appears anywhere in the rule, which is what keeps it a derivation"),
    ("sh -c 'cd /tmp/other && git switch main'",
     ["SEG_OPAQUE\t0\tcd /tmp/other && git switch main"],
     "the inner line is re-lexed whole, so either command position is enough"),
    ('sh -c "sh -c \'git switch main\'"', ["SEG_OPAQUE\t0\tsh -c \'git switch main\'"],
     "two levels deep. The token NAMED is the outer one, because that is the thing the reader "
     "can actually see on their command line"),
    ("""sh -c 'echo "unclosed'""", ['SEG_OPAQUE\t0\techo "unclosed'],
     "clause 3c, the case that KEEPS denying: segments() returns [] for the inner token, so "
     "the guard has seen nothing at any depth -- the same direction as SEG_UNPARSED"),
    ('gh pr create --title "fix git guard" --body "closes the hole"', [],
     "THE ACCEPTED COST, in the other direction: the wider `git anywhere in the re-lexed "
     "tokens` form denied this real shape, which is why command position was chosen"),
    ('gh issue comment 12 --body "the git switch case is covered"', [],
     "the second shape the wider form broke"),
    ("rg 'git switch' hooks/", ["SEG_OPAQUE\t0\tgit switch"],
     "STILL DENIED, and accepted -- via 3b, not 3a: the quoting keeps `git switch` as ONE "
     "token, so it is never at argv[1] to be a bare token, and the re-lex then finds git in "
     "command position. A command that merely MENTIONS git. WORKTREE_EXEMPT clears it"),
    ('ssh host "git pull"', ["SEG_OPAQUE\t0\tgit pull"],
     "also denied, and arguably correct: it does run git, just elsewhere"),
    ("""python3 -c 'import subprocess; subprocess.run(["git","log"])'""", [],
     "NON-GOAL, pinned as a MEASURED ALLOW: a git call built inside an interpreter string. "
     "Catching it means parsing arbitrary languages"),

    # --- SEG_UNPARSED. Line-scoped. The one place this design overrides a called
    # --- module's stated policy, because that policy is written for callers that
    # --- are not the last line of defence.
    ('git worktree add "unclosed', ["SEG_UNPARSED"],
     "measured: this produced NO output and exit 0, so boundary 7's non-zero-exit rule never "
     "sees it either -- an absent fact reads as `no worktree add here`"),
    ("", [], "empty input is not unparseable -- segments() returns one empty segment"),
    ("   ", [], "whitespace only, likewise"),

    # --- SEG_GROUPED. Line-scoped, and a CONJUNCTION: grouping AND a cd.
    # --- segments() throws the operator away, so `)` and `}` are
    # --- indistinguishable in its return value -- and bash discards a cd at `)`
    # --- while keeping it past `}`.
    ("( cd /tmp/other && git log ) && git switch main",
     ["SEG_BRANCH_MOVE\t4\tswitch", "SEG_CD\t1\t/tmp/other", "SEG_GROUPED"],
     "the card's measured example: this lexes to indices 0..4, so an index-ordered rule would "
     "carry the subshell's cd forward to index 4, where bash would not"),
    ("{ cd /x; git log; }", ["SEG_CD\t1\t/x", "SEG_GROUPED"],
     "a brace group, where bash DOES keep the cd. Same fact, because the return value cannot "
     "tell the two apart -- the over-deny on the `( ... )` case is the correct direction"),
    ("( git log ) && git switch main", ["SEG_BRANCH_MOVE\t3\tswitch"],
     "grouping with NO cd is not SEG_GROUPED: with nothing to carry, nothing can be miscarried"),
    ("cd /x && git switch main", ["SEG_BRANCH_MOVE\t1\tswitch", "SEG_CD\t0\t/x"],
     "and a cd with no grouping is not SEG_GROUPED either"),
    ('echo "(a)" && cd /x && git switch main',
     ["SEG_BRANCH_MOVE\t2\tswitch", "SEG_CD\t1\t/x"],
     "ONE LEXER, TWO VIEWS: a paren inside quotes is an ordinary token, so has_grouping sees "
     "exactly what segments() sees. A second parser is what would disagree here"),
]

# The measured populations from the card's derivation-3 section. Pinned as data
# rather than paraphrased, and asserted on the SEG_OPAQUE fact SPECIFICALLY --
# `git switch main` is a population-3 member that this classifier emits
# SEG_BRANCH_MOVE for, and reading its presence in P3 as "Arm D allows git
# switch" is the misreading the card calls out by name.
POP2_MUST_DENY = [
    "sh -c 'git switch main'",
    'bash -c "git switch main"',
    "zsh -c 'git switch main'",
    'eval "git switch main"',
    "sh -c 'cd /tmp/other && git switch main'",
    'sh -c "sh -c \'git switch main\'"',
    "env -C /tmp/other git switch main",
    "timeout 5 git commit -m x",
    "if cd /tmp/other; then git commit -m x; fi",
]

# Population 1 rows 5-19: the shapes the WIDER form allowed. Built as a named
# list so population 3 below can be assembled from it the way the card words it,
# rather than transcribed -- the transcription is what drifted to 21.
P1_ROWS_5_TO_19 = [
    "git commit -m 'fix: git switch is now denied'",
    'echo "Co-Authored-By: Claude"',
    "python3 -c 'print(1)'",
    """python3 -c 'import subprocess; subprocess.run(["git","log"])'""",
    'jq -r ".git"',
    'sed -i "" "s/git/hg/" f.txt',
    'find . -name "*.py"',
    'curl -s "https://github.com/o/r.git"',
    'echo "see docs/features/worktree-location-guard.md"',
    'test -d "$HOME/.claude"',
    'make test ARGS="-v"',
    'docker run -e MSG="hello" img',
    'ssh host "uptime"',
    "gh pr create --body-file /tmp/body.md",
    "npm run build -- --watch",
]
POP3_MUST_ALLOW = P1_ROWS_5_TO_19 + [
    "git switch main", "echo hello", "ls -la /tmp", "npm test", "cat README.md",
] + [
    'gh pr create --title "fix git guard" --body "closes the hole"',
    'gh issue comment 12 --body "the git switch case is covered"',
]

# The two Non-goals residuals, asserting an allow deliberately. The second is
# also population 1 row 8, which is the OVERLAP that made the population-3 count
# read 21 instead of 22 -- 24 rows over 23 distinct shapes.
RESIDUALS_MUST_ALLOW = ["./myscript.sh", P1_ROWS_5_TO_19[3]]


def opaque(cmd):
    return [f for f in classify(cmd) if f.startswith("SEG_OPAQUE\t")]


def check_populations():
    """Pin the card's three measured populations, and their arithmetic."""
    problems = []
    if len(POP2_MUST_DENY) != 9:
        problems.append("POPULATION 2 IS NOT 9 SHAPES — got {}".format(len(POP2_MUST_DENY)))
    if len(POP3_MUST_ALLOW) != 22:
        problems.append(
            "POPULATION 3 IS NOT 22 SHAPES — got {}. The card's own arithmetic is 15 + 5 + 2; "
            "it read 21 until 2026-08-25 and 21 was wrong.".format(len(POP3_MUST_ALLOW)))
    overlap = set(POP3_MUST_ALLOW) & set(RESIDUALS_MUST_ALLOW)
    if len(overlap) != 1:
        problems.append(
            "POPULATION 3 / RESIDUALS OVERLAP IS NOT 1 — got {}. The overlap is the reason 24 "
            "rows run over 23 distinct shapes; if it moves, the count reconciles wrongly "
            "again.".format(sorted(overlap)))

    for shape in POP2_MUST_DENY:
        if not opaque(shape):
            problems.append("POPULATION 2 — {!r} must emit SEG_OPAQUE and emitted none".format(shape))
    for shape in POP3_MUST_ALLOW:
        got = opaque(shape)
        if got:
            problems.append("POPULATION 3 — {!r} must emit NO SEG_OPAQUE, got {!r}".format(shape, got))
    for shape in RESIDUALS_MUST_ALLOW:
        got = opaque(shape)
        if got:
            problems.append("RESIDUAL — {!r} is a measured ALLOW, got {!r}".format(shape, got))
    return problems


def check_global_redirect_members():
    """Every GLOBAL_REDIRECT member except -C must deny, iterating the tuple AT RUNTIME.

    WHAT THIS DOES NOT CATCH, stated because the obvious reading is wrong: adding a
    member to GLOBAL_REDIRECT cannot redden this, and that is the design working rather
    than the test failing. SEG_SCOPE_OPT is emitted from blocking_option's RETURN VALUE,
    so an option nobody has enumerated is already bucket 3 and already denies. Measured
    against that mutant: GREEN, correctly.

    WHAT IT DOES CATCH -- each mutant measured RED:
      * a redirecting option escaping into GLOBAL_SKIP_NO_VALUE (walked past, so
        `git --bare switch main` reports only the branch move and no denial);
      * one escaping into GLOBAL_SKIP_CONSUMING (which also swallows the subcommand,
        leaving NO facts at all);
      * -C dropped from GLOBAL_REDIRECT, which silently ends the resolve-rather-than-
        refuse treatment the whole SEG_GIT_C / SEG_SCOPE_OPT split is defined against.

    So the property is "a member of this tuple is reachable ONLY through the blocking
    path", not "the tuple is complete". A list of option names written into this test
    would be the sixth hand-maintained list wearing different clothes; iterating the
    live tuple is what keeps it honest.
    """
    problems = []
    members = _MOD.GLOBAL_REDIRECT
    if "-C" not in members:
        problems.append(
            "-C IS NO LONGER IN GLOBAL_REDIRECT — the whole SEG_GIT_C / SEG_SCOPE_OPT split "
            "is defined against that membership; got {!r}".format(members))
    for option in members:
        got = classify("git {} switch main".format(option))
        want = ("SEG_GIT_C\t0\tswitch" if option == "-C"
                else "SEG_SCOPE_OPT\t0\t{}".format(option))
        if want not in got:
            problems.append(
                "GLOBAL_REDIRECT MEMBER {!r} — want {!r} among the facts, got {!r}. A new "
                "member must be classified deliberately, not left to fall through.".format(
                    option, want, got))
    return problems


def _nest(payload, levels):
    """shlex.quote, never hand-escaping -- the card's own harness builds it this way."""
    for _ in range(levels):
        payload = "sh -c " + shlex.quote(payload)
    return payload


def check_depth_bound():
    """Clause 3c's discriminating PAIR: same payload, one level apart, opposite verdicts.

    Both carry `git switch main`, a payload clause 3b denies at every shallower
    depth, so an allow at 4 levels can ONLY have come from the bound branch --
    nothing else in the rule could have let it through. A control whose payload
    held no git would have allowed for the trivial reason and proved nothing.
    """
    problems = []
    for levels in (1, 2, 3):
        shape = _nest("git switch main", levels)
        if not opaque(shape):
            problems.append(
                "DEPTH BOUND — {} level(s) must still deny and emitted no SEG_OPAQUE".format(levels))
    for levels in (4, 5):
        shape = _nest("git switch main", levels)
        got = opaque(shape)
        if got:
            problems.append(
                "DEPTH BOUND — {} level(s) is past BOUND=3 and must allow, got {!r}. Three levels "
                "of evidence is evidence, not blindness (user decision, 2026-08-25).".format(
                    levels, got))
    return problems


def main():
    passed = failed = 0
    for cmd, want, why in CASES:
        got = classify(cmd)
        if got == want:
            passed += 1
        else:
            failed += 1
            print("FAIL — {!r} ({})\n       want {!r}, got {!r}".format(cmd, why, want, got))

    for extra in (check_populations, check_depth_bound, check_global_redirect_members):
        msgs = extra()
        if msgs:
            failed += len(msgs)
            for m in msgs:
                print("FAIL — " + m)
        else:
            passed += 1

    print("\ngit classifier unit: {} passed, {} failed".format(passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    _rc = main()
    if _rc == 0:
        subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF],
                       cwd=MARKER_ROOT, check=True)
    sys.exit(_rc)
