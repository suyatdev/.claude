#!/usr/bin/env bash
# git-quiet-toggle.sh — UserPromptSubmit hook that flips git-guard's per-session "quiet" flag.
#
# Mark types the whole message `git-guard quiet` or `git-guard on`; this hook sees that message
# (Claude cannot type it for him, which is the point — D13), creates or removes
#   $HOME/.claude/hooks/state/git-guard-quiet/<session_id>
# then RE-CHECKS the flag and prints, on stdout (plain text, added to Claude's context), the state
# it actually measured. Any other message: no output, no file touched.
#
# Contract: docs/features/git-guard-quiet.md — D10-D17 and R14-R17. The decisions that shape this file:
#   D15/R16  only the WHOLE message, surrounding whitespace trimmed, case-sensitive, flips the flag —
#            a pasted document that contains the phrase must not.
#   R15      session_id must match ^[A-Za-z0-9-]{1,128}$ before it becomes a path component.
#   R17      never blocks Mark's message: every path exits 0; any error prints the FAILED line.
#   D17      state dir 0700, flag file 0600.
#
# "The prompt" is git-guard's -C prompt: prompt ON = it asks (quiet is off), prompt OFF = quiet is on.
# The FAILED line therefore names the state git-guard will see after the failure.
#
# Fires on EVERY prompt (including background-task notifications), so the common case is one
# interpreter start, a parse, and silence.

PROMPT_ON='ON'
FAILED_HEAD='git-guard quiet: FAILED to change state — the prompt is'

if ! command -v python3 >/dev/null 2>&1; then
  # Nothing can be parsed without python3, so no flag could have been changed: the prompt is ON.
  printf '%s %s. python3 was not found on PATH.\n' "$FAILED_HEAD" "$PROMPT_ON"
  exit 0
fi

read -r -d '' PY <<'PYEOF'
import json
import os
import re
import sys

QUIET_PHRASE = "git-guard quiet"
ON_PHRASE = "git-guard on"
SESSION_ID_RE = re.compile(r"[A-Za-z0-9-]{1,128}")  # fullmatch only: "$" would admit a trailing newline
STATE_DIR_PARTS = (".claude", "hooks", "state", "git-guard-quiet")
DIR_MODE = 0o700
FILE_MODE = 0o600
GROUP_OTHER_BITS = 0o077
MSG_QUIET_ON = (
    "git-guard quiet: ON for this session (read-only -C lookups, git add, and plain "
    'feature-branch commits and "push <remote> HEAD" pass without a prompt; '
    "everything else still asks)."
)
MSG_QUIET_OFF = "git-guard quiet: OFF for this session (the -C prompt is back)."
FAILED_HEAD = "git-guard quiet: FAILED to change state — the prompt is"


def emit(line):
    sys.stdout.buffer.write(line.encode("utf-8") + b"\n")
    sys.stdout.buffer.flush()


def fail(prompt_is_on, error):
    detail = " ".join(str(error).split())  # one line, whatever the exception carried
    emit("%s %s. %s" % (FAILED_HEAD, "ON" if prompt_is_on else "OFF", detail))


def read_payload():
    try:
        payload = json.loads(sys.stdin.buffer.read())
    except ValueError as exc:
        raise ValueError("could not parse the hook payload as JSON (%s)" % exc)
    if not isinstance(payload, dict):
        raise ValueError("the hook payload is not a JSON object")
    return payload


def ensure_state_dir(home):
    if not os.path.isdir(home):
        raise OSError("HOME is not a directory: %s" % home)
    path = home
    for part in STATE_DIR_PARTS:
        path = os.path.join(path, part)
        try:
            os.mkdir(path, DIR_MODE)
        except FileExistsError:
            if not os.path.isdir(path):
                raise
    # Tighten only: a directory this hook did not create keeps a mode it already narrowed.
    if os.stat(path).st_mode & GROUP_OTHER_BITS:
        os.chmod(path, DIR_MODE)
    return path


def create_flag(flag):
    fd = os.open(flag, os.O_WRONLY | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), FILE_MODE)
    try:
        if os.fstat(fd).st_mode & GROUP_OTHER_BITS:
            os.fchmod(fd, FILE_MODE)
    finally:
        os.close(fd)


def remove_flag(flag):
    try:
        os.unlink(flag)
    except FileNotFoundError:
        pass  # already off: not an error, and no directory is created for it


def main():
    try:
        payload = read_payload()
    except ValueError as exc:
        fail(True, exc)  # no session was identified, so no flag could have changed
        return

    prompt = payload.get("prompt")
    if not isinstance(prompt, str):
        return
    message = prompt.strip()
    if message not in (QUIET_PHRASE, ON_PHRASE):
        return
    want_quiet = message == QUIET_PHRASE

    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not SESSION_ID_RE.fullmatch(session_id):
        fail(True, "session_id is missing or not [A-Za-z0-9-]{1,128}; nothing was changed.")
        return
    home = os.environ.get("HOME")
    if not home or not os.path.isabs(home):
        fail(True, "HOME is not set to an absolute path; nothing was changed.")
        return

    flag = os.path.join(home, *STATE_DIR_PARTS, session_id)
    error = None
    try:
        if want_quiet:
            ensure_state_dir(home)
            create_flag(flag)
        else:
            remove_flag(flag)
    except OSError as exc:
        error = exc

    quiet_now = os.path.isfile(flag)  # the state git-guard will see, measured after the attempt
    if error is not None:
        fail(not quiet_now, "%s: %s" % (type(error).__name__, error))
    elif quiet_now != want_quiet:
        fail(not quiet_now, "the flag did not change as expected: %s" % flag)
    else:
        emit(MSG_QUIET_ON if quiet_now else MSG_QUIET_OFF)


try:
    main()
except Exception as exc:  # R17: a hook bug must never block the message
    fail(True, "unexpected %s: %s" % (type(exc).__name__, exc))
PYEOF

python3 -I -c "$PY" || printf '%s %s. The toggle script crashed.\n' "$FAILED_HEAD" "$PROMPT_ON"
exit 0
