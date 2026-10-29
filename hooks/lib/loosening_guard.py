"""loosening-guard: a PreToolUse(Bash) / PostToolUse(Bash) hook that stops a `git commit` which widens a
security guard's permission list and asks a human first. Entry point; the judgement is loosening_decide.py.

Wire format (the suite, hooks/loosening-guard.test.sh, is the specification; its header is authoritative):
  silent allow  exit 0, EMPTY stdout and stderr -- never a `permissionDecision: allow`, which would skip
                Claude's own permission check
  ask           exit 0, hookSpecificOutput.permissionDecision "ask" + a reason
  refuse        exit 2, reason on stderr. Fail-closed is exit 2 and NEVER an ask: under a bypass session an
                ask is silently allowed and the command runs (card, task 0)
  liveness      every run appends `decision=<skip|allow|ask|refuse> class=<c>` to $LOOSENING_GUARD_LOG

HOW AN APPROVAL IS RECORDED. The human answers the ask in the Claude Code UI, which no hook can see. So:
the PreToolUse ask leaves a note (lg-pending-<session>-<command hash>) naming the state keys it asked
about, and a PostToolUse for the SAME command turns that note into approval records. That inference holds
because PostToolUse fires only when the tool ran, and this hook asks only in an attended session; a decline
yields no PostToolUse and so no record. It is a momentum guardrail, not a security boundary: the record is
written from inside the session and is forgeable by the agent the gate constrains.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
LIB = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, LIB)

import loosening_decide as decide  # noqa: E402
from loosening_decide import Outcome, Refusal  # noqa: E402
from loosening_states import GitError  # noqa: E402
import secret_approval as sa  # noqa: E402
from shell_segments import segments  # noqa: E402

CLASSIFIER = os.path.join(LIB, "classify-git-command.py")
CLASSIFIER_TIMEOUT_SECONDS = 20
REDIRECTING_ENV = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR")
REDIRECTING_OPTIONS = ("--git-dir", "--work-tree")
UNRESOLVABLE = "UNRESOLVABLE"
# The classifier hands a quoted `-C "$dir"` over as the literal text $dir, not as UNRESOLVABLE; these
# characters mean the operand is something the shell will rewrite (same set as git_guard_quiet.py's D6).
UNRESOLVED_CHARACTERS = ("$", "`", "*", "?", "[")
COMMIT_WORD_RE = re.compile(r"\bcommit\b")
COMMAND_ID_LEN = 16
PENDING_PREFIX = "lg-pending-"
DECISION_RANK = {"refuse": 3, "ask": 2, "allow": 1, "skip": 0}


def log_raw(line):
    path = os.environ.get("LOOSENING_GUARD_LOG")
    if not path:
        return
    try:
        with open(path, "a") as fh:
            fh.write(line + "\n")
    except OSError as exc:
        print("loosening-guard: warning: cannot write the liveness log: %s" % exc, file=sys.stderr)


def log(decision, cls):
    log_raw("decision=%s class=%s" % (decision, cls))


def finish_refuse(message, cls):
    log("refuse", cls)
    print(message if message.startswith("loosening-guard") else "loosening-guard: " + message, file=sys.stderr)
    return 2


def command_id(command):
    return hashlib.sha256(command.encode("utf-8")).hexdigest()[:COMMAND_ID_LEN]


def pending_path(session, command):
    """Where the PreToolUse ask leaves its note, or None when the approval store has no usable location."""
    state = sa.state_dir()
    if not os.path.isabs(state):
        return None
    return os.path.join(state, "%s%s-%s" % (PENDING_PREFIX, sa.safe_session(session), command_id(command)))


# ---- which repositories, and which view of them, does this command commit? ---------------------------
def classifier_facts(command):
    try:
        done = subprocess.run([sys.executable, "-I", CLASSIFIER], input=command.encode("utf-8"),
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=CLASSIFIER_TIMEOUT_SECONDS)
    except (OSError, subprocess.SubprocessError) as exc:
        raise Refusal("cannot read the command: the git-command classifier did not run (%s)" % exc, "classifier")
    if done.returncode != 0:
        raise Refusal("cannot read the command: the git-command classifier exited %d" % done.returncode, "classifier")
    return [ln for ln in done.stdout.decode("utf-8", "replace").split("\n") if ln]


def resolve_operand(operand, what):
    if operand in (UNRESOLVABLE, "-") or any(c in operand for c in UNRESOLVED_CHARACTERS):
        raise Refusal("%s names a directory the hook cannot resolve (%r), so which repository this commit "
                      "targets is unknown; write the path out" % (what, operand), "redirected")
    return os.path.expanduser(operand)


def commit_targets(command, cwd):
    """-> ([(directory, mode)], pathspecs). Empty when the command commits nothing.

    mode: 'index' (a plain commit), 'worktree' (-a, or a suspected bare pathspec), 'pathspec'. A chained line
    is ALSO judged against the work tree, because a sibling `git add` has not run yet when this hook fires
    and the index it will fill cannot be known (ADR 0014's lesson; a superset is the safe direction).
    """
    if not COMMIT_WORD_RE.search(command):
        return [], []
    facts = classifier_facts(command)
    if "SEG_UNPARSED" in facts:
        raise Refusal("this command mentions a commit but cannot be parsed, so what it commits cannot be inspected",
                      "unparsed")
    parts = [f.split("\t") for f in facts]
    is_commit = "COMMIT" in facts
    unknown_options = [p[1] for p in parts if p[0] == "SCOPE_UNKNOWN" and len(p) > 1]
    git_c = [p[2] for p in parts if p[0] == "SEG_GIT_C" and len(p) > 2]
    if not (is_commit or unknown_options or git_c):
        return [], []
    for name in (p[2] for p in parts if p[0] == "SEG_ENV" and len(p) > 2):
        if name in REDIRECTING_ENV:
            raise Refusal("this commit sets %s, which can point git at another repository, so what it commits "
                          "cannot be inspected" % name, "redirected")
    for opt in unknown_options:
        if opt.startswith(REDIRECTING_OPTIONS):
            raise Refusal("this commit passes %s, which points git at another repository, so what it commits "
                          "cannot be inspected" % opt, "redirected")
    directories = [cwd] if (is_commit or unknown_options) else []
    # `cd <dir> && git commit`: the hook's own cwd is the SESSION's, not the commit's, so every directory
    # the line walks into is judged as well (a superset; it prompts only if that repo has a watched change).
    here = cwd
    for _index, operand in sorted((int(p[1]), p[2]) for p in parts if p[0] == "SEG_CD" and len(p) > 2):
        here = os.path.normpath(os.path.join(here, resolve_operand(operand, "cd")))
        directories.append(here)
    for operand in git_c:
        directories.append(os.path.normpath(os.path.join(here, resolve_operand(operand, "git -C"))))
    pathspecs = [p[1] for p in parts if p[0] == "COMMIT_PATH" and len(p) > 1]
    if "COMMIT_ALL" in facts or "COMMIT_BARE_ARGS" in facts:
        modes = {"worktree"}
    elif "COMMIT_PATHSPEC" in facts and pathspecs:
        modes = {"pathspec"}
    else:
        modes = {"index"}
    if len(segments(command)) != 1:
        modes |= {"worktree", "index"}
    seen, targets = set(), []
    for directory in directories:
        real = os.path.realpath(directory)
        if real in seen or not os.path.isdir(real):
            continue
        seen.add(real)
        targets += [(real, mode) for mode in sorted(modes)]
    return targets, pathspecs


# ---- merging the outcomes of several (directory, mode) judgements ------------------------------------
def merge(outcomes):
    if not outcomes:
        return Outcome("skip", "unrelated")
    top = max(DECISION_RANK[o.decision] for o in outcomes)
    chosen = [o for o in outcomes if DECISION_RANK[o.decision] == top]
    if chosen[0].decision != "ask":
        return chosen[0]
    reasons = []
    for o in chosen:
        if o.reason not in reasons:
            reasons.append(o.reason)
    keys = sorted({k for o in chosen for k in o.keys})
    return Outcome("ask", chosen[0].cls, "\n\n".join(reasons), keys, [n for o in chosen for n in o.notes])


def write_pending(session, command, keys):
    """-> a note for the reason when the approval cannot be remembered, else ''."""
    path = pending_path(session, command)
    if path is None:
        return "\nnote: approving this will not be remembered (the approval store has no absolute path; is HOME set?)."
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            fh.write(" ".join(keys))
    except OSError as exc:
        return "\nnote: approving this will not be remembered (the approval store is not writable: %s)." % exc
    return ""


def clear_pending(session, command):
    """Drop a note left by an earlier ask for this exact command. -> a warning when that could not be done.

    A stale note is the one way PostToolUse could record an approval nobody gave (an ask that was declined,
    then the same command text run again on a state that needs no ask). An unwritable store is spec
    section 7's "bypass refused, commit judged on its merits", so a failure here does not refuse the
    commit; it is reported where the human can see it (the ask) or in the log (a silent outcome).
    """
    path = pending_path(session, command)
    if path is None:
        return ""
    try:
        os.remove(path)
    except FileNotFoundError:
        return ""
    except OSError as exc:
        return "an earlier approval note for this command could not be cleared (%s)" % exc
    return ""


# ---- the two events ----------------------------------------------------------------------------------
def pre_tool_use(payload, command):
    ctx = decide.Context(payload, command)
    targets, pathspecs = commit_targets(command, os.getcwd())
    if not targets:
        log("skip", "unrelated")
        return 0
    stale = clear_pending(ctx.session, command)
    outcome = merge([decide.evaluate(ctx, d, m, pathspecs) for d, m in targets])
    if outcome.decision == "ask":
        reason = outcome.reason + write_pending(ctx.session, command, outcome.keys)
        if stale:
            reason += "\nnote: " + stale + "."
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask",
                                                 "permissionDecisionReason": reason}}))
    elif stale:
        log_raw("warning=stale-approval-note-uncleared")
    log(outcome.decision, outcome.cls)
    return 0


def post_tool_use(payload, command):
    """Turn the note a PreToolUse ask left into approval records: the command ran, so a human said yes."""
    session = str(payload.get("session_id") or "")
    log("skip", "post")
    if not isinstance(command, str) or not command:
        return 0
    path = pending_path(session, command)
    if path is None:
        return 0
    try:
        with open(path) as fh:
            keys = fh.read().split()
    except FileNotFoundError:
        return 0
    except OSError as exc:
        return finish_refuse("cannot read the approval note, so no approval was recorded (%s); you will be asked "
                             "again" % exc, "store")
    response = payload.get("tool_response")
    interrupted = isinstance(response, dict) and response.get("interrupted") is True
    try:
        os.remove(path)
        if not interrupted:
            for key in keys:
                sa.grant(session, key)
    except (OSError, ValueError) as exc:
        return finish_refuse("cannot record the approval (%s); you will be asked again" % exc, "store")
    return 0


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
    except ValueError:
        return finish_refuse("the payload is not valid JSON, so the command cannot be inspected", "payload")
    if not isinstance(payload, dict):
        return finish_refuse("the payload is not a JSON object, so the command cannot be inspected", "payload")
    tool_input = payload.get("tool_input")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if payload.get("hook_event_name") == "PostToolUse":
        return post_tool_use(payload, command)
    if payload.get("tool_name") not in (None, "Bash") or command is None:
        log("skip", "unrelated")
        return 0
    if not isinstance(command, str):
        return finish_refuse("tool_input.command is not a string, so the command cannot be inspected", "payload")
    return pre_tool_use(payload, command)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Refusal as refusal:
        sys.exit(finish_refuse(refusal.message, refusal.cls))
    except (GitError, sa.StateUnreadable) as exc:
        sys.exit(finish_refuse("cannot establish what this commit changes: %s" % exc, "git"))
    except Exception as exc:  # noqa: BLE001 -- the fail-closed contract: any internal error refuses (spec section 7)
        sys.exit(finish_refuse("internal error (%s: %s); refusing rather than guessing" % (type(exc).__name__, exc),
                               "internal"))
