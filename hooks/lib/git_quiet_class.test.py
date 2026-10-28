#!/usr/bin/env python3
"""Unit tests for git_quiet_class.py and for the SEG_QUIET fact classify-git-command.py emits
from it. Run: python3 hooks/lib/git_quiet_class.test.py

Card: docs/features/git-guard-quiet.md, "The lists" and "Classifier -- one new fact (D18)".

Three things are pinned here, none of them in classify-git-command.test.py:

  * every row of the card's class table, with the edge cases each round measured
    (CASES, check_class_contract);
  * the emission: which lines get a SEG_QUIET fact, how many, and which class each segment
    gets (EMISSION_CASES, check_emission_shape);
  * R19 -- a missing, unimportable, raising or lying git_quiet_class.py must leave every other
    fact exactly as it was and make every segment `other` (check_r19).

Deliberately dependency-free (no pytest): adding a dependency is not a unilateral call, and
this has to run anywhere the hook runs.
"""

import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

MARKER_SELF = os.path.abspath(__file__)
# cwd=dirname(MARKER_SELF), never the inherited process cwd: this file may also be run as a nested
# subprocess from inside a throwaway repo, where the ambient cwd resolves to that fixture's toplevel.
MARKER_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=os.path.dirname(MARKER_SELF),
                             capture_output=True, text=True, check=True).stdout.strip()

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)

import git_quiet_class  # noqa: E402  (path must be set first)
from shell_segments import segments  # noqa: E402

classify_class = git_quiet_class.classify

_SPEC = importlib.util.spec_from_file_location(
    "classify_git_command", os.path.join(_HERE, "classify-git-command.py")
)
_MOD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MOD)
classify_line = _MOD.classify

QUIET_PREFIX = "SEG_QUIET\t"
VALID_CLASSES = ("read", "add", "commit", "push", "other")

READ_SUBCOMMANDS = (
    "status", "log", "diff", "show", "cat-file", "rev-parse", "ls-files", "ls-tree",
    "show-ref", "merge-base", "describe", "blame", "shortlog", "for-each-ref",
)

# (subcommand, argv after the subcommand, expected class, why)
CASES = []

for _name in READ_SUBCOMMANDS:
    CASES.append((_name, [], "read", "read list: " + _name))
    CASES.append((_name, ["--output=/tmp/x"], "other",
                  _name + " with --output= writes a file (round 5)"))
    CASES.append((_name, ["--output", "/tmp/x"], "other", _name + " with a separate --output"))

CASES += [
    # --- read: plain argument shapes
    ("status", ["--short"], "read", "an option is not an --output"),
    ("log", ["--oneline", "-n", "5", "main"], "read", "options and a ref"),
    ("diff", ["--stat", "a", "b", "--", "f"], "read", "pathspec after --"),
    ("cat-file", ["-t", "abc123"], "read", "Mark's second example"),
    ("show", ["HEAD:docs/x.md"], "read", "a rev:path"),
    ("diff", ["a", "--output=/tmp/x"], "other", "--output after a positional"),
    ("diff", ["--", "--output=/tmp/x"], "other", "--output after -- still refused: any argument"),
    ("log", ["--outputfoo"], "other", "the rule is a PREFIX test on --output"),
    ("log", ["--output"], "other", "bare --output"),
    ("for-each-ref", ["--format=%(refname)", "--output=x"], "other", "last argument"),

    # --- read: hash-object writes only with -w, alone or inside a single-dash bundle
    ("hash-object", ["f.md"], "read", "Mark's first example"),
    ("hash-object", [], "read", "no arguments, no -w"),
    ("hash-object", ["-t", "blob", "f"], "read", "-t takes a type, not -w"),
    ("hash-object", ["--stdin"], "read", "long option"),
    ("hash-object", ["--stdin-paths"], "read", "long option"),
    ("hash-object", ["--no-filters", "f"], "read", "long option"),
    ("hash-object", ["--path=w", "f"], "read", "a long option whose value holds a w is not a -w"),
    ("hash-object", ["-w", "f"], "other", "-w writes the object"),
    ("hash-object", ["-wt", "blob", "f"], "other", "-wt: a bundle containing w (round 5)"),
    ("hash-object", ["-tw", "blob", "f"], "other", "-tw: the w is not first"),
    ("hash-object", ["-t", "blob", "-w", "f"], "other", "-w after other options"),
    ("hash-object", ["f", "-w"], "other", "-w after the file"),

    # --- read: branch, only the two listing spellings
    ("branch", ["--show-current"], "read", "exactly the one argument"),
    ("branch", ["--show-current", "x"], "other", "--show-current with anything else"),
    ("branch", ["--list"], "read", "bare --list"),
    ("branch", ["-l"], "read", "bare -l"),
    ("branch", ["--list", "feat/*"], "read", "--list with a pattern word"),
    ("branch", ["-l", "main", "feat/x"], "read", "-l followed only by non-option words"),
    ("branch", ["--list", "--no-list", "-D", "main"], "other", "round 5: this DELETED main"),
    ("branch", ["-l", "-M", "main", "old"], "other", "round 7: -M renames over main"),
    ("branch", ["--list", "-a"], "other", "any dash word after --list asks"),
    ("branch", [], "other", "bare branch is not on the list"),
    ("branch", ["feat/new"], "other", "creates a branch"),
    ("branch", ["-D", "main"], "other", "deletes"),
    ("branch", ["-f", "feat/x", "HEAD"], "other", "branch -f moves a branch"),
    ("branch", ["-m", "a", "b"], "other", "renames"),
    ("branch", ["--show-current", "--list"], "other", "two arguments"),

    # --- read: worktree list with nothing after it
    ("worktree", ["list"], "read", "exactly worktree list"),
    ("worktree", ["list", "--porcelain"], "other", "anything after list asks"),
    ("worktree", ["list", "--porcelain", "x"], "other", "round 7"),
    ("worktree", ["add", "../x"], "other", "worktree add"),
    ("worktree", ["remove", "../x"], "other", "worktree remove"),
    ("worktree", [], "other", "bare worktree"),

    # --- add
    ("add", [], "add", "no arguments"),
    ("add", ["--", "f"], "add", "a path"),
    ("add", ["-A"], "add", "any arguments"),
    ("add", ["-f", "ignored.txt"], "add", "any arguments"),

    # --- commit
    ("commit", [], "commit", "no arguments"),
    ("commit", ["-m", "x", "--", "f"], "commit", "any arguments"),
    ("commit", ["--amend", "--no-edit"], "commit", "any arguments -- D5/D6/D7 do the checking"),

    # --- push: the D8 shape and the ways to miss it
    ("push", ["origin", "HEAD"], "push", "the shape"),
    ("push", ["-u", "origin", "HEAD"], "push", "-u"),
    ("push", ["--set-upstream", "origin", "HEAD"], "push", "--set-upstream"),
    ("push", ["-q", "origin", "HEAD"], "push", "-q"),
    ("push", ["--quiet", "origin", "HEAD"], "push", "--quiet"),
    ("push", ["-v", "origin", "HEAD"], "push", "-v"),
    ("push", ["--verbose", "origin", "HEAD"], "push", "--verbose"),
    ("push", ["--force-with-lease", "origin", "HEAD"], "push", "bare lease, no ="),
    ("push", ["-u", "--force-with-lease", "-q", "origin", "HEAD"], "push", "several allowed options"),
    ("push", ["up.stream_1-x", "HEAD"], "push", "every character the remote pattern admits"),
    ("push", [], "other", "bare push (round 5: matching/mirror config)"),
    ("push", ["origin"], "other", "a remote and no ref"),
    ("push", ["HEAD"], "other", "one positional is not remote + HEAD"),
    ("push", ["origin", "HEAD:main"], "other", "refspec to main"),
    ("push", ["origin", "HEAD:refs/heads/main"], "other", "refspec to main, full name"),
    ("push", ["origin", "feat/x"], "other", "a branch name"),
    ("push", ["origin", "main"], "other", "main by name"),
    ("push", ["origin", "+HEAD"], "other", "a forced refspec"),
    ("push", ["origin", "head"], "other", "HEAD is case-sensitive"),
    ("push", ["origin", "HEAD", "extra"], "other", "a third positional"),
    ("push", ["origin", "HEAD", "-u"], "other", "an option after the positionals is not the shape"),
    ("push", ["--force", "origin", "HEAD"], "other", "bare force"),
    ("push", ["-f", "origin", "HEAD"], "other", "short force"),
    ("push", ["-uf", "origin", "HEAD"], "other", "round 7: a bundle holding f"),
    ("push", ["--force-with-lease=x", "origin", "HEAD"], "other", "lease with ="),
    ("push", ["--force-with-lease=feat/x"], "other", "lease with =, no positionals"),
    ("push", ["--all"], "other", "--all"),
    ("push", ["--mirror"], "other", "--mirror"),
    ("push", ["--tags", "origin", "HEAD"], "other", "--tags"),
    ("push", ["--delete", "origin", "HEAD"], "other", "--delete"),
    ("push", ["--receive-pack=x", "origin", "HEAD"], "other", "--receive-pack"),
    ("push", ["--exec=x", "origin", "HEAD"], "other", "--exec"),
    ("push", ["--repo=x", "origin", "HEAD"], "other", "--repo"),
    ("push", ["--no-verify", "origin", "HEAD"], "other", "any other option"),
    ("push", ["or igin", "HEAD"], "other", "a space is not in the remote pattern"),
    ("push", ["git@github.com:o/r.git", "HEAD"], "other", "a URL remote: @ and : are not in the pattern"),
    ("push", ["", "HEAD"], "other", "an empty remote"),
    ("push", ["origin\n", "HEAD"], "other", "a trailing newline does not match the pattern"),
    # A would-be remote that starts with `-` is an option, not a remote: git parses `-o HEAD` as a push
    # option plus nothing, and runs a BARE push (which moved main under push.default=upstream).
    ("push", ["-f", "HEAD"], "other", "a remote spelled -f is an option, not the shape"),
    ("push", ["-o", "HEAD"], "other", "-o takes HEAD as its value; a bare push follows"),
    ("push", ["--push-option", "HEAD"], "other", "--push-option takes HEAD as its value"),
    ("push", ["-u", "-o", "HEAD"], "other", "an allowed option, then -o"),
    ("push", ["--all", "HEAD"], "other", "--all is not an allowed option"),
    ("push", ["--mirror", "HEAD"], "other", "--mirror is not an allowed option"),
    ("push", ["--delete", "HEAD"], "other", "--delete is not an allowed option"),
    ("push", [".x", "HEAD"], "push", "a remote may start with a dot"),
    ("push", ["_r", "HEAD"], "push", "a remote may start with an underscore"),

    # --- everything else, including aliases and case variants
    ("st", [], "other", "an alias is never on a list"),
    ("Status", [], "other", "subcommands match by exact name"),
    ("STATUS", [], "other", "subcommands match by exact name"),
    ("Commit", [], "other", "subcommands match by exact name"),
    ("status ", [], "other", "no trimming"),
    ("", [], "other", "empty subcommand"),
    ("merge", ["feat/x"], "other", "merge"),
    ("switch", ["main"], "other", "switch"),
    ("checkout", ["main"], "other", "checkout"),
    ("rebase", ["main"], "other", "rebase"),
    ("reset", ["--hard"], "other", "reset"),
    ("pull", [], "other", "pull"),
    ("fetch", [], "other", "fetch"),
    ("cherry-pick", ["abc"], "other", "cherry-pick"),
    ("revert", ["abc"], "other", "revert"),
    ("am", [], "other", "am"),
    ("update-ref", ["refs/heads/main", "abc"], "other", "update-ref"),
    ("symbolic-ref", ["HEAD"], "other", "symbolic-ref"),
    ("symbolic-ref", ["HEAD", "refs/heads/main"], "other", "symbolic-ref write"),
    ("config", ["core.hooksPath", "/dev/null"], "other", "config"),
    ("stash", [], "other", "stash"),
    ("stash", ["list"], "other", "stash list is not on the read list"),
    ("tag", ["-d", "x"], "other", "tag"),
    ("remote", ["-v"], "other", "remote is not on the read list"),
    ("rm", ["f"], "other", "rm"),
    ("clean", ["-fd"], "other", "clean"),
    ("restore", ["f"], "other", "restore"),
    ("gc", [], "other", "gc"),
    ("ls-remote", [], "other", "not on the read list"),
    ("grep", ["x"], "other", "not on the read list"),
    ("commit-tree", ["abc"], "other", "plumbing that writes"),
]

# Inputs the pure function must survive without raising, each answered `other`.
HOSTILE = [
    (None, []),
    ("status", None),
    (123, []),
    ("status", [None]),
    ("status", [1]),
    ("status", "abc"),                  # a bare string is not an argv, though iterable
    ("status", [["--short"]]),
    (["status"], []),
    (b"status", []),
    ("push", [None, "HEAD"]),
    ("hash-object", [None]),
    ("branch", [None]),
    ("branch", ["--list", None]),
    ("worktree", [None]),
    ("push", {"origin": "HEAD"}),
    ("status", object()),
]

# (command line, expected SEG_QUIET classes by segment index, or None when the line carries no
# SCOPE_UNKNOWN and so must carry no SEG_QUIET at all, why)
EMISSION_CASES = [
    # --- no SCOPE_UNKNOWN: no new fact
    ("git status", None, "no -C"),
    ("git commit -m x", None, "no -C"),
    ("cd /x && git log", None, "a cd is not a scope option"),
    ("git --no-pager log", None, "a bucket-1 option does not raise SCOPE_UNKNOWN"),
    ("", None, "empty"),
    ("env git -C F status", None, "env at argv[0]: SEG_OPAQUE, no git segment, no SCOPE_UNKNOWN"),
    ('git -C F "unclosed', None, "SEG_UNPARSED: no segments at all"),

    # --- the card's examples
    ("git -C F status", ["read"], "R2"),
    ("git -C F cat-file -t abc123", ["read"], "R2, Mark's second example"),
    ('W=~/wt; git -C "$W" status --short; git -C "$W" hash-object f.md; wc -l f.md',
     ["nongit", "read", "read", "nongit"], "R2, Mark's first example: assignment-only and wc are nongit"),
    ("git -C F add -- f && git -C F commit -m x -- f && git -C F push -u origin HEAD",
     ["add", "commit", "push"], "R3"),
    ("time git -C F commit -m x", ["commit"], "R4: a stripped wrapper is judged as its command"),
    ("rtk git -C F status", ["read"], "R4: rtk is stripped too"),

    # --- every segment gets a fact, in index order
    ("git -C F status && git -C F log", ["read", "read"], "two reads"),
    ("git -C F status\ngit -C F log", ["read", "read"], "a newline separates segments"),
    ("git -C F status; ./script.sh", ["read", "nongit"], "a script is nongit"),
    ("cd M && git -C . commit -m x", ["nongit", "commit"], "R10: cd is nongit"),
    ("git -C F switch main && git -C F commit -m x", ["other", "commit"], "R6"),
    ("echo hi && git -C /x commit -m x -- app.js", ["nongit", "commit"], "the -C is on segment 1"),
    ("GIT_DIR=M/.git git -C F status", ["read"], "SEG_ENV is the quiet decision's business, not the class"),
    ("env git status && git -C F status", ["nongit", "read"], "an opaque segment is nongit"),
    ('git -C F commit -m "a; b"', ["commit"], "a quoted ; is not a separator"),

    # --- spellings of git
    ("Git -C F log", ["read"], "argv[0] folds like every other git guard"),
    ("/usr/bin/git -C F log", ["read"], "path-qualified git"),

    # --- anything that stops the class function from being reached is `other`
    ("git -C F push", ["other"], "R8: bare push"),
    ("git -C F push origin HEAD:main", ["other"], "R7"),
    ("git -C F push -uf origin HEAD", ["other"], "R9"),
    ("git -C F push --force-with-lease=feat/x", ["other"], "R9"),
    ("git -C F -c core.hooksPath=/dev/null status", ["other"], "R12: -c after -C"),
    ("git -c core.hooksPath=/dev/null -C F status", ["other"], "R12: -c before -C"),
    ("git -C F status && git -c core.hooksPath=/dev/null status", ["read", "other"], "R12"),
    ("git -C F st", ["other"], "R12: an alias"),
    ("git -C F diff --output=/tmp/x", ["other"], "R12"),
    ("git -C F branch --list --no-list -D main", ["other"], "R22"),
    ("git -C F branch -l -M main old", ["other"], "R22"),
    ("git -C F hash-object -wt blob f", ["other"], "R22"),
    ("git -C F worktree list --porcelain x", ["other"], "R22"),
    ("git -C F worktree list", ["read"], "worktree list alone"),
    ("git -C", ["other"], "-C with no operand: no subcommand"),
    ("git -C F", ["other"], "no subcommand"),
    ("git -C F --git-dir x status", ["other"], "a second scope option"),
    ("git -C F -- status", ["other"], "-- is an unrecognised option here"),
    ("git -C /a -C /b status", ["read"], "two -C: the class is by subcommand; D6 asks on the fact"),
    ("git -C F --no-pager log", ["read"], "a bucket-1 option is walked past"),
    ("git -C=/x commit -m y", ["other"], "the attached -C= leaves -m in subcommand position"),
]


def quiet_classes(facts):
    """The SEG_QUIET classes in a fact list, ordered by segment index, with the indexes checked."""
    rows = [f.split("\t") for f in facts if f.startswith(QUIET_PREFIX)]
    indexes = [int(r[1]) for r in rows]
    if indexes != list(range(len(rows))):
        return ["INDEXES %r" % indexes]
    return [r[2] for r in rows]


def check_class_contract():
    problems = []
    for subcommand, argv, want, why in CASES:
        got = classify_class(subcommand, list(argv))
        if got != want:
            problems.append("CLASS {!r} {!r} ({}): want {!r}, got {!r}".format(
                subcommand, argv, why, want, got))
    for subcommand, argv in HOSTILE:
        try:
            got = classify_class(subcommand, argv)
        except BaseException as exc:  # the contract is "never raises"
            problems.append("HOSTILE {!r} {!r} RAISED {!r}".format(subcommand, argv, exc))
            continue
        if got != "other":
            problems.append("HOSTILE {!r} {!r}: want 'other', got {!r}".format(subcommand, argv, got))
    for subcommand, argv in (("status", ("--short",)), ("push", ("origin", "HEAD"))):
        got = classify_class(subcommand, argv)
        want = "read" if subcommand == "status" else "push"
        if got != want:
            problems.append("TUPLE argv {!r} {!r}: want {!r}, got {!r}".format(subcommand, argv, want, got))
    return len(CASES) + len(HOSTILE) + 2, problems


def check_class_function_is_pure():
    """The caller's argv list must come back untouched, and the answer must not depend on history."""
    problems = []
    argv = ["-u", "origin", "HEAD"]
    first = classify_class("push", argv)
    if argv != ["-u", "origin", "HEAD"]:
        problems.append("PURITY: classify() mutated its argv: %r" % argv)
    if classify_class("push", argv) != first:
        problems.append("PURITY: the same call answered differently twice")
    classify_class("commit", ["x"])
    if classify_class("push", ["-u", "origin", "HEAD"]) != first:
        problems.append("PURITY: an unrelated call changed a later answer")
    for subcommand, argv, _want, _why in CASES:
        if classify_class(subcommand, list(argv)) not in VALID_CLASSES:
            problems.append("DOMAIN: %r %r left the five-class domain" % (subcommand, argv))
    if tuple(git_quiet_class.CLASSES) != tuple(_MOD.QUIET_CLASSES):
        problems.append("DOMAIN: the module's CLASSES %r and the classifier's own QUIET_CLASSES %r "
                        "disagree" % (git_quiet_class.CLASSES, _MOD.QUIET_CLASSES))
    if tuple(git_quiet_class.CLASSES) != VALID_CLASSES:
        problems.append("DOMAIN: CLASSES is not the card's five classes: %r" % (git_quiet_class.CLASSES,))
    return 1, problems


def check_emission_shape():
    problems = []
    for cmd, want, why in EMISSION_CASES:
        facts = classify_line(cmd)
        got = quiet_classes(facts)
        if want is None:
            if got:
                problems.append("EMISSION {!r} ({}): want no SEG_QUIET, got {!r}".format(cmd, why, got))
            continue
        if got != want:
            problems.append("EMISSION {!r} ({}): want {!r}, got {!r}".format(cmd, why, want, got))
        if not any(f.startswith("SCOPE_UNKNOWN\t") for f in facts):
            problems.append("EMISSION {!r}: expected SCOPE_UNKNOWN on a line with SEG_QUIET".format(cmd))
        if len(got) != len(segments(cmd)):
            problems.append("EMISSION {!r}: {} SEG_QUIET for {} segments".format(
                cmd, len(got), len(segments(cmd))))
    return len(EMISSION_CASES), problems


def check_other_facts_unchanged_by_emission():
    """SEG_QUIET is purely additive: dropping it must give back exactly the pre-card fact set.

    Compared against the fact set computed with the quiet step stubbed out in-process, so the
    pre-card behaviour is derived from this very classifier rather than transcribed.
    """
    problems = []
    original = _MOD.quiet_facts
    try:
        for cmd, want, _why in EMISSION_CASES:
            with_quiet = classify_line(cmd)
            _MOD.quiet_facts = lambda segs: []
            without = classify_line(cmd)
            _MOD.quiet_facts = original
            stripped = [f for f in with_quiet if not f.startswith(QUIET_PREFIX)]
            if stripped != without:
                problems.append("ADDITIVE {!r}: facts changed beyond SEG_QUIET:\n    with-minus-quiet {!r}\n"
                                "    without          {!r}".format(cmd, stripped, without))
            if with_quiet != sorted(with_quiet):
                problems.append("SORTED {!r}: facts not sorted".format(cmd))
    finally:
        _MOD.quiet_facts = original
    return len(EMISSION_CASES), problems


# --- R19: the classifier with a broken git_quiet_class.py -----------------------------------------

R19_COMMANDS = [cmd for cmd, _want, _why in EMISSION_CASES] + [
    "git -C F status && git -C F commit -m x && git -C F push origin HEAD",
    "git -C F push && git commit -m y",
    "G=git; $G commit",
    "git push --force",
]

R19_VARIANTS = {
    "module absent": None,
    "import raises": "raise RuntimeError('boom at import')\n",
    "classify raises": "CLASSES = ('read','add','commit','push','other')\n"
                       "def classify(subcommand, argv):\n    raise RuntimeError('boom in classify')\n",
    "classify raises KeyError": "CLASSES = ('read','add','commit','push','other')\n"
                       "def classify(subcommand, argv):\n    return {}['missing']\n",
    "classify answers outside the domain": "CLASSES = ('read','add','commit','push','other')\n"
                       "def classify(subcommand, argv):\n    return 'allow'\n",
    "classify answers a non-string": "CLASSES = ('read','add','commit','push','other')\n"
                       "def classify(subcommand, argv):\n    return None\n",
    "syntax error": "def classify(:\n",
}


def _run_classifier(script, command):
    proc = subprocess.run([sys.executable, "-I", script], input=command, capture_output=True,
                          text=True, timeout=30)
    return proc.returncode, [l for l in proc.stdout.split("\n") if l], proc.stderr


def check_r19():
    problems = []
    scratch = tempfile.mkdtemp(prefix="git-quiet-r19-")
    try:
        for label, body in R19_VARIANTS.items():
            lib = os.path.join(scratch, label.replace(" ", "_"))
            os.makedirs(lib)
            for name in ("classify-git-command.py", "shell_segments.py"):
                shutil.copy(os.path.join(_HERE, name), os.path.join(lib, name))
            if body is not None:
                with open(os.path.join(lib, "git_quiet_class.py"), "w") as handle:
                    handle.write(body)
            script = os.path.join(lib, "classify-git-command.py")
            for cmd in R19_COMMANDS:
                want_facts = [f for f in classify_line(cmd) if not f.startswith(QUIET_PREFIX)]
                rc, out, err = _run_classifier(script, cmd)
                if rc != 0:
                    problems.append("R19 [{}] {!r}: exit {} (stderr {!r})".format(label, cmd, rc, err[:200]))
                    continue
                got_other = [f for f in out if not f.startswith(QUIET_PREFIX)]
                if got_other != want_facts:
                    problems.append("R19 [{}] {!r}: other facts changed:\n    want {!r}\n    got  {!r}".format(
                        label, cmd, want_facts, got_other))
                got_quiet = quiet_classes(out)
                carries = any(f.startswith("SCOPE_UNKNOWN\t") for f in want_facts)
                if not carries:
                    if got_quiet:
                        problems.append("R19 [{}] {!r}: SEG_QUIET on a line without SCOPE_UNKNOWN: {!r}".format(
                            label, cmd, got_quiet))
                    continue
                want_quiet = ["other"] * len(segments(cmd))
                if got_quiet != want_quiet:
                    problems.append("R19 [{}] {!r}: want every segment other {!r}, got {!r}".format(
                        label, cmd, want_quiet, got_quiet))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    return len(R19_VARIANTS) * len(R19_COMMANDS), problems


def check_r19_control():
    """The same harness against an INTACT copy must reproduce the real classes.

    Without this, check_r19 passes for the trivial reason that the copied classifier never ran
    the quiet step at all (a copy that cannot import shell_segments would emit nothing).
    """
    problems = []
    scratch = tempfile.mkdtemp(prefix="git-quiet-r19-ctl-")
    try:
        for name in ("classify-git-command.py", "shell_segments.py", "git_quiet_class.py"):
            shutil.copy(os.path.join(_HERE, name), os.path.join(scratch, name))
        script = os.path.join(scratch, "classify-git-command.py")
        rc, out, err = _run_classifier(script, "git -C F status && git -C F push")
        if rc != 0 or quiet_classes(out) != ["read", "other"]:
            problems.append("R19 CONTROL: intact copy gave rc={} classes={!r} stderr={!r}".format(
                rc, quiet_classes(out), err[:200]))
        rc, out, err = _run_classifier(script, "git -C F add -- f && git -C F commit -m x")
        if rc != 0 or quiet_classes(out) != ["add", "commit"]:
            problems.append("R19 CONTROL: intact copy gave rc={} classes={!r}".format(rc, quiet_classes(out)))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    return 2, problems


def main():
    passed = failed = 0
    for check in (check_class_contract, check_class_function_is_pure, check_emission_shape,
                  check_other_facts_unchanged_by_emission, check_r19_control, check_r19):
        try:
            items, problems = check()
        except Exception as exc:  # a crashing check is a red check, never a silent skip
            items, problems = 1, ["CRASH in {}: {!r}".format(check.__name__, exc)]
        failed += len(problems)
        passed += max(items - len(problems), 0)
        for problem in problems:
            print("FAIL -- " + problem)
    print("\ngit quiet class unit: {} passed, {} failed".format(passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    _rc = main()
    if _rc == 0:
        subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF],
                       cwd=MARKER_ROOT, check=True)
    sys.exit(_rc)
