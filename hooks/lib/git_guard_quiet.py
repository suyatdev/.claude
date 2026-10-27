#!/usr/bin/env python3
"""The `git-guard quiet` decision: may this `git -C` line pass without a prompt?

Card: docs/features/git-guard-quiet.md -- Decisions D3-D9, "The lists", the Line rule, and
"git-guard -- the quiet decision". Run by hooks/git-guard.sh as a CHILD PROCESS (`python3 -I
<this file>`), never sourced, and only when a quiet flag exists for the session.

Input: ONE JSON object on stdin,
    {"command": <raw command>, "cwd": <payload cwd>, "session_id": <id>, "facts": [<fact>, ...]}
where each fact is one line of classify-git-command.py's output. Output: exactly `allow` or
`ask`, no newline, exit 0. `allow` is printed only AFTER its log line has been appended (D16); a
child killed in between leaves a log line for a prompt that was in fact shown, an accepted
over-count. Any error, any unparseable input and any doubt answers `ask`: this file can only
turn today's prompt into a pass, never into a deny, and a fault here can only keep the prompt.

The class of each segment (read / add / commit / push / other / nongit) comes from the
classifier's SEG_QUIET facts. What this file adds is everything the classifier cannot see:
the raw-text checks (D9), the checkable folder (D6) and the branch of that folder (D7).
"""

import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import unicodedata
from collections import namedtuple

# Every git call below is bounded: a stalled disk must end in a prompt, not in a hook the
# platform kills (which, by this repo's notes, lets the command run).
QUIET_GIT_CALL_TIMEOUT_SECONDS = 3

SESSION_ID_PATTERN = re.compile(r"[A-Za-z0-9-]{1,128}")
INDEX_PATTERN = re.compile(r"[0-9]+")

CLASS_READ, CLASS_ADD, CLASS_COMMIT, CLASS_PUSH = "read", "add", "commit", "push"
CLASS_OTHER, CLASS_NONGIT = "other", "nongit"
ALL_CLASSES = (CLASS_READ, CLASS_ADD, CLASS_COMMIT, CLASS_PUSH, CLASS_OTHER, CLASS_NONGIT)
LANDING_CLASSES = (CLASS_COMMIT, CLASS_PUSH)
# On a line that commits or pushes, nothing else may appear (D5(a)).
LANDING_LINE_CLASSES = (CLASS_READ, CLASS_ADD, CLASS_COMMIT, CLASS_PUSH)

FACT_QUIET = "SEG_QUIET"
FACT_GIT_C = "SEG_GIT_C"
# D9: a fact with any of these names means a line the allowlist was never built for.
BLOCKING_FACTS = ("SEG_SCOPE_OPT", "SEG_ENV", "SEG_OPAQUE", "SEG_GROUPED", "SEG_UNPARSED")
UNRESOLVABLE = "UNRESOLVABLE"

# D9, on the RAW text -- the lexer's parse is blind to what these run: a substitution, a process
# substitution, or `eval` (which re-reads its arguments as new shell code).
HIDDEN_COMMAND_PATTERN = re.compile(r"\$\(|`|<\(|>\(|\beval\b")
REDIRECT_CHARACTERS = ("<", ">")

# D6: characters that make a -C operand mean more than its spelling.
FOLDER_FORBIDDEN_CHARACTERS = ("$", "`", "*", "?", "[")

# D7.
HEADS_PREFIX = "refs/heads/"
PROTECTED_BRANCHES = ("main", "master")
IN_PROGRESS_MARKERS = ("rebase-merge", "rebase-apply", "MERGE_HEAD",
                       "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG")

KIND_READ, KIND_LANDS = "read", "lands"
LOG_RELATIVE_PATH = (".claude", "hooks", "state", "git-guard-quiet.log")
LOG_FILE_MODE = 0o600

ANSWER_ALLOW, ANSWER_ASK = "allow", "ask"

Request = namedtuple("Request", "command cwd session_id facts")
Verdict = namedtuple("Verdict", "allow kind reason")
Facts = namedtuple("Facts", "classes git_c blocking")


class Ask(Exception):
    """A rule decided this line must keep today's prompt. The text names the rule (for tests)."""


def parse_request(text):
    """The JSON object on stdin as a Request. Raises Ask on anything but the four right keys."""
    try:
        data = json.loads(text)
    except ValueError as exc:
        raise Ask("input is not JSON: {}".format(exc))
    if not isinstance(data, dict):
        raise Ask("input is not an object")
    for key in ("command", "cwd", "session_id", "facts"):
        if key not in data:
            raise Ask("input lacks " + key)
    command, cwd, session_id, facts = (data[k] for k in ("command", "cwd", "session_id", "facts"))
    if not (isinstance(command, str) and command and isinstance(cwd, str)):
        raise Ask("command or cwd is not a string")
    if not (isinstance(session_id, str) and SESSION_ID_PATTERN.fullmatch(session_id)):
        raise Ask("session_id is not a valid id")
    if not (isinstance(facts, list) and all(isinstance(f, str) for f in facts)):
        raise Ask("facts is not a list of strings")
    return Request(command, cwd, session_id, facts)


def parse_facts(facts):
    """Split fact lines into segment classes, -C operands and the D9 blocking names.

    A repeated SEG_QUIET or SEG_GIT_C index, a gap in the indices, or a class outside the six
    asks: the two are produced once per segment, so anything else is not the classifier's output.
    """
    classes, git_c, blocking = {}, {}, set()
    for fact in facts:
        if "\n" in fact:
            raise Ask("a fact spans lines")
        name = fact.split("\t", 1)[0]
        if name in BLOCKING_FACTS:
            blocking.add(name)
        elif name in (FACT_QUIET, FACT_GIT_C):
            parts = fact.split("\t", 2)
            if len(parts) != 3 or not INDEX_PATTERN.fullmatch(parts[1]):
                raise Ask("malformed " + name)
            index, table = int(parts[1]), (classes if name == FACT_QUIET else git_c)
            if index in table:
                raise Ask("repeated {} for segment {}".format(name, index))
            table[index] = parts[2]
    if sorted(classes) != list(range(len(classes))):
        raise Ask("SEG_QUIET indices are not 0..n-1")
    if any(c not in ALL_CLASSES for c in classes.values()):
        raise Ask("SEG_QUIET names an unknown class")
    return Facts([classes[i] for i in range(len(classes))], git_c, blocking)


def checkable_folder(operand):
    """D6: the absolute folder a -C operand names, or Ask.

    A RELATIVE operand is not checkable: Task 0 measured the payload's cwd lagging the directory
    a command really starts in, so it cannot be resolved here.
    """
    if operand is None:
        raise Ask("segment has no -C folder")
    if operand == UNRESOLVABLE or not operand:
        raise Ask("-C folder is unresolvable (two -C, or a variable)")
    if any(ch in operand for ch in FOLDER_FORBIDDEN_CHARACTERS):
        raise Ask("-C folder carries a variable, substitution or glob")
    if operand.startswith("~"):
        if operand != "~" and not operand.startswith("~/"):
            raise Ask("-C folder uses a ~ form other than ~ and ~/")
        operand = os.path.expanduser(operand)
    if not operand.startswith("/"):
        raise Ask("-C folder is relative or did not expand to an absolute path")
    return operand


def run_git(folder, *args):
    """stdout of `git -C <folder> <args>`; Ask on a non-zero exit, a timeout or a missing git."""
    try:
        result = subprocess.run(
            ["git", "-C", folder] + list(args), stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            timeout=QUIET_GIT_CALL_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        raise Ask("git {} timed out".format(args[0]))
    except OSError as exc:
        raise Ask("git could not run: {}".format(exc))
    if result.returncode != 0:
        raise Ask("git {} exited {}".format(args[0], result.returncode))
    # Decoded as UTF-8 on purpose, never by locale: a branch name like `maſter` must read the same
    # under any LANG. Bytes that are not UTF-8 raise, and a raise is an ask.
    return result.stdout.decode("utf-8")


def fold_branch_name(name):
    """D7: case- and look-alike-insensitive form. `Main`, `MASTER` and `maſter` (U+017F) are the
    same file as `main`/`master` on a case-insensitive filesystem."""
    return unicodedata.normalize("NFKC", name).casefold()


def check_folder_is_quiet_safe(folder):
    """D7: HEAD is a branch other than main/master and nothing is in progress, or Ask."""
    head = run_git(folder, "symbolic-ref", "HEAD").rstrip("\n")
    # Full name, NOT `--short`: a tag named `main` makes --short print `heads/main`.
    if not head.startswith(HEADS_PREFIX) or "\n" in head:
        raise Ask("HEAD is detached or not a plain branch")
    name = head[len(HEADS_PREFIX):]
    if not name or fold_branch_name(name) in PROTECTED_BRANCHES:
        raise Ask("HEAD is main/master (or spells it differently)")
    args = ["rev-parse"]
    for marker in IN_PROGRESS_MARKERS:
        args += ["--git-path", marker]
    paths = run_git(folder, *args).split("\n")
    if paths and paths[-1] == "":
        paths.pop()
    if len(paths) != len(IN_PROGRESS_MARKERS):
        raise Ask("git answered the wrong number of marker paths")
    for path in paths:
        if os.path.lexists(os.path.join(folder, path)):
            raise Ask("an operation is in progress in the folder")


def evaluate(request):
    """The Line rule. Returns a Verdict; Ask and any other error become an `ask` Verdict."""
    try:
        return _evaluate(request)
    except Ask as exc:
        return Verdict(False, "", str(exc))
    except Exception as exc:  # fail closed: a bug here is a prompt, never a pass
        return Verdict(False, "", "error: {!r}".format(exc))


def _evaluate(request):
    facts = parse_facts(request.facts)
    if facts.blocking:
        raise Ask("blocking facts: " + ",".join(sorted(facts.blocking)))
    if HIDDEN_COMMAND_PATTERN.search(request.command):
        raise Ask("raw text holds a substitution or eval")
    classes = facts.classes
    if all(c == CLASS_NONGIT for c in classes):
        raise Ask("no git segment to judge")
    if CLASS_OTHER in classes:
        raise Ask("a segment is not on any list")
    if not any(c in LANDING_CLASSES for c in classes):
        return Verdict(True, KIND_READ, "read/add line")
    if any(c not in LANDING_LINE_CLASSES for c in classes):
        raise Ask("a commit/push line holds a non-git segment")
    if any(ch in request.command for ch in REDIRECT_CHARACTERS):
        raise Ask("a commit/push line holds < or >")
    for index, segment_class in enumerate(classes):
        if segment_class in LANDING_CLASSES:
            check_folder_is_quiet_safe(checkable_folder(facts.git_c.get(index)))
    return Verdict(True, KIND_LANDS, "feature-branch commit/push")


def append_log(request, kind):
    """D16: one tab-separated line -- UTC time, session, read|lands, SHA-256 of the command."""
    home = os.environ.get("HOME", "")
    if not home.startswith("/"):
        raise OSError("HOME is not an absolute path")
    stamp = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    digest = hashlib.sha256(request.command.encode("utf-8")).hexdigest()
    line = "\t".join((stamp, request.session_id, kind, digest)) + "\n"
    data = line.encode("ascii")
    fd = os.open(os.path.join(home, *LOG_RELATIVE_PATH),
                 os.O_WRONLY | os.O_APPEND | os.O_CREAT, LOG_FILE_MODE)
    try:
        if os.write(fd, data) != len(data):
            raise OSError("short write to the quiet log")
    finally:
        os.close(fd)


def answer_for(text):
    """ANSWER_ALLOW only for a verdict whose log line was written; ANSWER_ASK otherwise."""
    try:
        request = parse_request(text)
        verdict = evaluate(request)
        if not verdict.allow:
            return ANSWER_ASK
        append_log(request, verdict.kind)
        return ANSWER_ALLOW
    except Exception:
        return ANSWER_ASK


def main():
    try:
        text = sys.stdin.buffer.read().decode("utf-8")
    except Exception:
        text = ""
    sys.stdout.write(answer_for(text))
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
