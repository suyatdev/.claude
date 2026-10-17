#!/usr/bin/env python3
"""Unit tests for decide-commit-gate.py's part comparison. Run: python3 hooks/lib/decide-commit-gate.test.py
(add -v to also list the passing assertions).

Item C of docs/features/trim-safety-followups.md: a runner `X.test.sh` may source a folder of
parts `X.test.d/NN-*.sh`, and the receipt (hooks/state/test-markers/<subject>) now names those
parts. The decider must read them back -- classify a part as a member of its runner's pair
(row 2a), enumerate the parts a commit would ship by each of the three commit forms, and block
with MSG_STALE_PART when that set differs from the receipt's. One assertion per scenario in the
card's gherkin block, every row of both Scenario Outlines included.

Every case drives the real decider as a subprocess with a real PreToolUse payload and reads the
four-field TSV it prints -- that wire line is the whole contract with the bash hook, so asserting
on it is asserting on the contract, not on an internal function. Receipts are built by the real
writer (`write-test-marker.py`, run with the fixture repo as cwd), never hand-assembled, so a
writer and decider that disagree about the receipt's shape fail here instead of agreeing in
isolation. Throwaway git repos only: the writer is never pointed at the live checkout and nothing
is written into the live hooks/state/.

SCOPE OF THE RED STATE (task 6 of the card; tasks 7 and 8 turn it green):
  * Most assertions fail against today's decider because it does not know about parts yet.
  * Some scenarios describe behaviour the decider ALREADY has (a lone deletion is not gated, a
    receipt without a `parts` key stays valid for a runner with no parts, a non-part file falls
    through, PATHSPEC allows a deleted part). They pass today on purpose: they are regression
    guards that stop task 7 from over-reaching, not evidence that the feature exists.
  * The hook-level assertion (`check_hook_prints_stale_part`) runs the REAL
    hooks/test-marker-guard.sh. It stays RED after task 7 -- the decider will then emit
    MSG_STALE_PART, which the hook does not yet recognise -- and goes green only in task 8. Red
    after task 7 is the expected state, not a failure to chase.

Deliberately dependency-free (no pytest): adding a dependency is not a unilateral call, and this
has to run anywhere the hook runs.
"""

import contextlib
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import traceback

MARKER_SELF = os.path.abspath(__file__)
_HERE = os.path.dirname(MARKER_SELF)
# cwd=dirname(MARKER_SELF), never the inherited process cwd -- the same reason the sibling suites
# resolve the root this way.
MARKER_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=_HERE,
                             capture_output=True, text=True, check=True).stdout.strip()

_DECIDER = os.path.join(_HERE, "decide-commit-gate.py")
_WRITER = os.path.join(_HERE, "write-test-marker.py")
_HOOK = os.path.join(_HERE, "..", "test-marker-guard.sh")

# A fake $HOME alone does NOT sever git's global config; only these do. Set process-wide so the
# decider, the writer and the bash hook (all subprocesses of this one) inherit them.
os.environ["GIT_CONFIG_GLOBAL"] = "/dev/null"
os.environ["GIT_CONFIG_SYSTEM"] = "/dev/null"

# The fixture. Nested on purpose: the receipt's paths and the store key both carry a directory.
SUBJECT = "tools/R.sh"
RUNNER = "tools/R.test.sh"
FOLDER = "tools/R.test.d"
PART_A = FOLDER + "/10-a.sh"
PART_B = FOLDER + "/20-b.sh"
PART_C = FOLDER + "/30-c.sh"
HELPER = FOLDER + "/helper.sh"
PAIR = SUBJECT + "|" + RUNNER

STALE_PART = "MSG_STALE_PART"
BAD_MARKER = "MSG_BAD_MARKER"

# One commit command per form (classify-commit-command.py reads these as PLAIN / ALL / PATHSPEC).
PLAIN, ALL, PATHSPEC = "PLAIN", "ALL", "PATHSPEC"
FORMS = (PLAIN, ALL, PATHSPEC)

VALID_BLOB = "a" * 40


def _commit_command(form, paths=()):
    if form == PLAIN:
        return "git commit -m x"
    if form == ALL:
        return "git commit -a -m x"
    return "git commit -m x -- " + " ".join(paths)


# --- fixture plumbing --------------------------------------------------------------------------

def _git(root, *args):
    out = subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True,
                         check=True)
    return out.stdout.strip()


def _write(root, rel, content):
    full = os.path.join(root, rel)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as handle:
        handle.write(content)


@contextlib.contextmanager
def _repo(files):
    """A throwaway repo with `files` {relpath: content} committed as the baseline (HEAD)."""
    root = os.path.realpath(tempfile.mkdtemp(prefix="decider-test-"))
    try:
        subprocess.run(["git", "init", "-q", root], check=True)
        for key, value in (("user.email", "t@example.com"), ("user.name", "t")):
            _git(root, "config", key, value)
        for rel, content in files.items():
            _write(root, rel, content)
        _git(root, "add", "--", ".")
        _git(root, "commit", "-q", "-m", "baseline")
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def _parts_files(extra=None):
    files = {
        SUBJECT: "subject v1\n",
        RUNNER: "runner v1\n",
        PART_A: "part a v1\n",
        PART_B: "part b v1\n",
    }
    files.update(extra or {})
    return files


def _write_receipt(root, test_rel=RUNNER):
    """Run the REAL writer the way a suite's call site does: absolute path, repo root as cwd."""
    proc = subprocess.run([sys.executable, "-I", _WRITER, os.path.join(root, test_rel)],
                          cwd=root, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError("writer failed rc={}: {}".format(proc.returncode, proc.stderr.strip()))


def _receipt_path(root, subject_rel=SUBJECT):
    key = subject_rel.replace("%", "%25").replace("/", "%2F")
    return os.path.join(root, "hooks", "state", "test-markers", key)


def _read_receipt(root, subject_rel=SUBJECT):
    with open(_receipt_path(root, subject_rel)) as handle:
        return json.load(handle)


def _put_receipt(root, doc, subject_rel=SUBJECT):
    with open(_receipt_path(root, subject_rel), "w") as handle:
        json.dump(doc, handle, indent=2, sort_keys=True)
        handle.write("\n")


def _decide(root, command):
    """(outcome, door, detail, pair) from the decider's TSV, or ("ERROR", rc, stderr, stdout)."""
    payload = {"cwd": root, "tool_name": "Bash", "tool_input": {"command": command},
               "hook_event_name": "PreToolUse"}
    proc = subprocess.run([sys.executable, "-I", _DECIDER], input=json.dumps(payload),
                          capture_output=True, text=True)
    line = proc.stdout.rstrip("\n")
    fields = line.split("\t")
    if proc.returncode != 0 or len(fields) != 4:
        return ("ERROR", str(proc.returncode), proc.stderr.strip()[-200:], line)
    return tuple(fields)


def _show(decision):
    outcome, door, detail, pair = decision
    if outcome == "ALLOW":
        return outcome
    if outcome == "ERROR":
        return "ERROR rc={} stderr={!r} stdout={!r}".format(door, detail, pair)
    return "{} {} detail={} pair={}".format(outcome, door, detail, pair)


def _expect(record, name, decision, outcome, door="-", detail="-", pair="-"):
    want = (outcome, door, detail, pair)
    record(decision == want, name, "want {}, got {}".format(_show(want), _show(decision)))


def _allow(record, name, decision):
    _expect(record, name, decision, "ALLOW")


def _stale_part(record, name, decision, detail):
    _expect(record, name, decision, "BLOCK", STALE_PART, detail, PAIR)


# --- harness controls --------------------------------------------------------------------------
# These pass on today's decider and exist to prove the harness can SEE both verdicts: if the
# fixtures were broken, every red below would be indistinguishable from a decider that lacks the
# feature. A control that cannot fail measures nothing, so each is the opposite of the other.

def check_harness_controls(record):
    with _repo(_parts_files()) as root:
        _write_receipt(root)
        receipt = _read_receipt(root)
        names = [part["path"] for part in receipt.get("parts", [])]
        record(names == [PART_A, PART_B], "control: the real writer's receipt names both parts",
               "want parts [{}, {}], got {}".format(PART_A, PART_B, names))
        _write(root, SUBJECT, "subject v2\n")
        _git(root, "add", "--", SUBJECT)
        _stale = _decide(root, _commit_command(PLAIN))
        _expect(record, "control: a subject edited after the receipt is MSG_STALE_SUBJECT",
                _stale, "BLOCK", "MSG_STALE_SUBJECT", "-", PAIR)
        _write_receipt(root)
        _allow(record, "control: the same edit with a fresh receipt is ALLOW",
               _decide(root, _commit_command(PLAIN)))


# --- scenarios ---------------------------------------------------------------------------------

def _edit_part_b(root, form):
    _write(root, PART_B, "part b v2\n")
    if form == PLAIN:
        _git(root, "add", "--", PART_B)


def check_changed_part_blocks(record):
    """Scenario: a changed part with a stale receipt is blocked -- once per commit form."""
    for form in FORMS:
        with _repo(_parts_files()) as root:
            _write_receipt(root)
            _edit_part_b(root, form)
            decision = _decide(root, _commit_command(form, [PART_B]))
            _stale_part(record, "changed part, {}: BLOCK MSG_STALE_PART naming 20-b.sh".format(form),
                        decision, PART_B)


def check_rerun_clears(record):
    """Scenario: re-running the suite after the edit clears it. Asserts the block FIRST, so the
    ALLOW afterwards cannot be the vacuous one today's decider gives (it never looked at parts)."""
    with _repo(_parts_files()) as root:
        _write_receipt(root)
        _edit_part_b(root, PLAIN)
        before = _decide(root, _commit_command(PLAIN))
        _write_receipt(root)
        after = _decide(root, _commit_command(PLAIN))
        ok = before == ("BLOCK", STALE_PART, PART_B, PAIR) and after == ("ALLOW", "-", "-", "-")
        record(ok, "re-running the suite clears a stale part: BLOCK then ALLOW",
               "want BLOCK MSG_STALE_PART then ALLOW, got {} then {}".format(_show(before),
                                                                             _show(after)))


def check_new_part_blocks(record):
    """Scenario: a new part the receipt has never seen is blocked."""
    with _repo(_parts_files()) as root:
        _write_receipt(root)
        _write(root, PART_C, "part c v1\n")
        _git(root, "add", "--", PART_C)
        _stale_part(record, "new part: BLOCK MSG_STALE_PART naming 30-c.sh",
                    _decide(root, _commit_command(PLAIN)), PART_C)


def _deleted_part_state(root):
    """R.sh edited and receipted with BOTH parts, then 20-b.sh removed and R.sh staged."""
    _write(root, SUBJECT, "subject v2\n")
    _write_receipt(root)
    _git(root, "rm", "-q", "--", PART_B)
    _git(root, "add", "--", SUBJECT)


def check_deleted_part_outline(record):
    """Scenario Outline: a deleted part is caught only where the form can see it."""
    cases = [
        (PLAIN, "BLOCK", STALE_PART, PART_B, PAIR),
        (ALL, "BLOCK", STALE_PART, PART_B, PAIR),
        # Deliberate, not a bug: PATHSPEC reads a pair member outside its path set from <base>,
        # where the part is still alive and matches the receipt. Do not "fix" this row.
        (PATHSPEC, "ALLOW", "-", "-", "-"),
    ]
    for form, outcome, door, detail, pair in cases:
        with _repo(_parts_files()) as root:
            _deleted_part_state(root)
            decision = _decide(root, _commit_command(form, [SUBJECT, PART_B]))
            _expect(record, "deleted part, {}: {}".format(form, outcome + (" " + door if door != "-" else "")),
                    decision, outcome, door, detail, pair)


def check_lone_deletion_not_gated(record):
    """Scenario: a lone part deletion is NOT gated -- no path in the set forms a pair."""
    with _repo(_parts_files()) as root:
        _write_receipt(root)
        _git(root, "rm", "-q", "--", PART_B)
        _allow(record, "lone part deletion: ALLOW (no pair forms)",
               _decide(root, _commit_command(PLAIN)))


def check_pre_card_receipt_with_parts(record):
    """Scenario: a pre-card receipt (no `parts` key) for a runner that HAS parts is stale."""
    with _repo(_parts_files()) as root:
        _write(root, SUBJECT, "subject v2\n")
        _write_receipt(root)
        receipt = _read_receipt(root)
        receipt.pop("parts", None)
        _put_receipt(root, receipt)
        _git(root, "add", "--", SUBJECT)
        _stale_part(record, "pre-card receipt, runner has parts: BLOCK MSG_STALE_PART naming 10-a.sh",
                    _decide(root, _commit_command(PLAIN)), PART_A)


def check_pre_card_receipt_without_parts(record):
    """Scenario: a pre-card receipt for a runner with NO .test.d folder stays valid."""
    files = {SUBJECT: "subject v1\n", RUNNER: "runner v1\n"}
    with _repo(files) as root:
        _write(root, SUBJECT, "subject v2\n")
        _write_receipt(root)
        receipt = _read_receipt(root)
        receipt.pop("parts", None)
        _put_receipt(root, receipt)
        _git(root, "add", "--", SUBJECT)
        _allow(record, "pre-card receipt, runner has no parts: ALLOW",
               _decide(root, _commit_command(PLAIN)))


def check_non_part_file_not_gated(record):
    """Scenario: a non-part file inside the folder (no NN- prefix) is not gated."""
    with _repo(_parts_files({HELPER: "helper v1\n"})) as root:
        _write_receipt(root)
        _write(root, HELPER, "helper v2\n")
        _git(root, "add", "--", HELPER)
        _allow(record, "helper.sh edited alone: ALLOW (falls through the rows below 2a)",
               _decide(root, _commit_command(PLAIN)))
    # The same file beside a receipted subject edit: were the glob too wide, helper.sh would be
    # counted as a part the receipt never named and this would block.
    with _repo(_parts_files({HELPER: "helper v1\n"})) as root:
        _write(root, SUBJECT, "subject v2\n")
        _write_receipt(root)
        _write(root, HELPER, "helper v2\n")
        _git(root, "add", "--", SUBJECT, HELPER)
        _allow(record, "helper.sh edited beside a receipted R.sh: ALLOW (not counted as a part)",
               _decide(root, _commit_command(PLAIN)))


def check_pair_formed_from_part_alone(record):
    """Scenario: only 20-b.sh is staged -- the pair forms and its receipt is read. With no
    receipt at all the proof is MSG_NO_MARKER carrying the pair, which nothing but a formed pair
    can produce."""
    with _repo(_parts_files()) as root:
        _write(root, PART_B, "part b v2\n")
        _git(root, "add", "--", PART_B)
        decision = _decide(root, _commit_command(PLAIN))
        _expect(record, "part staged alone, no receipt: BLOCK MSG_NO_MARKER for the pair",
                decision, "BLOCK", "MSG_NO_MARKER", "bash " + RUNNER, PAIR)


def check_part_of_orphan_runner_not_gated(record):
    """Row 2a joins the pair set 'exactly as its runner would': a runner whose subject is not
    tracked forms no pair, so its parts form none either."""
    files = {RUNNER: "runner v1\n", PART_A: "part a v1\n"}
    with _repo(files) as root:
        _write(root, PART_A, "part a v2\n")
        _git(root, "add", "--", PART_A)
        _allow(record, "part of a runner with no tracked subject: ALLOW (step 2 applies unchanged)",
               _decide(root, _commit_command(PLAIN)))


def check_python_runner_has_no_parts(record):
    """Scenario: a .test.py runner never has parts -- a hand-made X.test.d/ is ignored."""
    files = {"tools/X.py": "x v1\n", "tools/X.test.py": "x test v1\n",
             "tools/X.test.d/10-a.sh": "hand made v1\n"}
    with _repo(files) as root:
        _write(root, "tools/X.py", "x v2\n")
        _write_receipt(root, "tools/X.test.py")
        record("parts" not in _read_receipt(root, "tools/X.py"),
               "python runner: the writer wrote no parts key",
               "want no `parts` key for a .test.py runner")
        _write(root, "tools/X.test.d/10-a.sh", "hand made v2\n")
        _git(root, "add", "--", "tools/X.py", "tools/X.test.d/10-a.sh")
        _allow(record, "python runner with a hand-made .test.d/: ALLOW (folder ignored)",
               _decide(root, _commit_command(PLAIN)))


def _malformed_shapes(good_parts):
    first = good_parts[0]
    return [
        ("a string instead of a list", "10-a.sh"),
        ("a list holding a string", [PART_A]),
        ("an entry with no blob", [{"path": PART_A}]),
        ("an entry whose blob is not 40 or 64 hex characters",
         [{"path": PART_A, "blob": "a" * 41}] + good_parts[1:]),
        ("an entry whose path is outside <stem>.test.d/",
         good_parts + [{"path": "tools/Other.test.d/10-a.sh", "blob": VALID_BLOB}]),
        ("an entry whose path is inside the folder but not NN-*.sh",
         good_parts + [{"path": HELPER, "blob": VALID_BLOB}]),
        ("two entries with the same path", good_parts + [copy.deepcopy(first)]),
    ]


def check_malformed_parts_outline(record):
    """Scenario Outline: a malformed parts key is a bad receipt, not a stale one. The subject is
    edited and receipted so that, were `parts` tolerated and ignored, the result would be a plain
    ALLOW -- BAD_MARKER can therefore only come from the shape check."""
    with _repo(_parts_files()) as root:
        _write(root, SUBJECT, "subject v2\n")
        _write_receipt(root)
        base_receipt = _read_receipt(root)
    good_parts = base_receipt["parts"]
    for shape_name, bad in _malformed_shapes(good_parts):
        with _repo(_parts_files()) as root:
            _write(root, SUBJECT, "subject v2\n")
            _write_receipt(root)
            receipt = _read_receipt(root)
            receipt["parts"] = bad
            _put_receipt(root, receipt)
            _git(root, "add", "--", SUBJECT)
            _expect(record, "malformed parts ({}): BLOCK MSG_BAD_MARKER".format(shape_name),
                    _decide(root, _commit_command(PLAIN)), "BLOCK", BAD_MARKER, "-", PAIR)


# --- the hook, end to end ----------------------------------------------------------------------

def check_hook_prints_stale_part(record):
    """The REAL hooks/test-marker-guard.sh on a stale part: exit 2 with MSG_STALE_PART on stderr.

    EXPECTED RED until task 8. It also stays red after task 7: by then the decider emits
    MSG_STALE_PART, but the hook's door table does not know the constant and answers with its
    "door this version of the gate does not recognise" fallback (MSG_CLASSIFIER_BAD_OUTPUT)
    instead. That is the hook's half of the feature not existing yet -- not a broken test.
    """
    with _repo(_parts_files()) as root:
        # the hook is inert in a repo without the writer (its opt-in signal), so give it one
        os.makedirs(os.path.join(root, "hooks", "lib"), exist_ok=True)
        shutil.copy(_WRITER, os.path.join(root, "hooks", "lib", "write-test-marker.py"))
        _write_receipt(root)
        _edit_part_b(root, PLAIN)
        payload = {"cwd": root, "tool_name": "Bash", "hook_event_name": "PreToolUse",
                   "tool_input": {"command": _commit_command(PLAIN)}}
        proc = subprocess.run(["bash", _HOOK], input=json.dumps(payload), capture_output=True,
                              text=True)
        ok = proc.returncode == 2 and STALE_PART in proc.stderr and PAIR in proc.stderr
        record(ok, "hook: a stale part prints MSG_STALE_PART and exits 2 (green only in task 8)",
               "want rc 2 and stderr naming {} and {}, got rc {} stderr {!r}".format(
                   STALE_PART, PAIR, proc.returncode, proc.stderr.strip()))


CHECKS = [
    check_harness_controls,
    check_changed_part_blocks,
    check_rerun_clears,
    check_new_part_blocks,
    check_deleted_part_outline,
    check_lone_deletion_not_gated,
    check_pre_card_receipt_with_parts,
    check_pre_card_receipt_without_parts,
    check_non_part_file_not_gated,
    check_pair_formed_from_part_alone,
    check_part_of_orphan_runner_not_gated,
    check_python_runner_has_no_parts,
    check_malformed_parts_outline,
    check_hook_prints_stale_part,
]


def main():
    verbose = "-v" in sys.argv[1:]
    results = []

    def record(ok, name, detail):
        results.append((ok, name, detail))

    for check in CHECKS:
        try:
            check(record)
        except Exception:
            # a fixture that cannot build measures nothing -- surface it as its own failure
            record(False, "{} CRASHED (harness, not decider)".format(check.__name__),
                   traceback.format_exc().strip().splitlines()[-1])

    passed = sum(1 for ok, _, _ in results if ok)
    for ok, name, detail in results:
        if not ok:
            print("FAIL — {}\n       {}".format(name, detail))
        elif verbose:
            print("ok   — {}".format(name))
    failed = len(results) - passed
    print("\ndecider unit: {} passed, {} failed".format(passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    _rc = main()
    if _rc == 0:
        # Mirrors hooks/phase-guard.test.sh: the receipt is written only by a suite that passed,
        # by the real writer, with the live checkout as cwd.
        subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF],
                       cwd=MARKER_ROOT, check=True)
    sys.exit(_rc)
