#!/usr/bin/env python3
"""Session- and command-scoped approval records for the SECRET_EXEMPT hatch.

WHAT THIS IS NOT
----------------
This is a SPEED BUMP, not a security boundary, and no caller may describe it as
one. The record is written from inside the session by the same agent the gate
constrains, so it is forgeable: `secret_approval.py grant <id>` is an ordinary
command an agent can issue on its own authority. The record states that an
approval was claimed; it does not prove one was given. The load-bearing control
remains the literal phrase `secret-gate override`, typed by a human, described
in rules/gates.md and skills/securing-agentic-systems/SKILL.md.

What it buys, and the only thing it buys: `SECRET_EXEMPT=<reason> <cmd>` used to
clear a block on its own, so the flag was one keystroke away at the exact moment
an agent was already frustrated by a refusal. Now the flag alone does nothing.
Getting past the guard takes a second, separate, differently-shaped step whose
whole purpose is to be a place to stop and ask -- and which leaves a file on
disk naming the command it covers.

THE FLOW
--------
1. secret-command-guard.sh blocks a command and prints an approval id -- the
   first 16 hex of a SHA-256 over the command's LEXED form.
2. The agent shows the user the command, and waits for `secret-gate override`.
3. `secret_approval.py grant <id>` writes $STATE_DIR/secret-approval-<sid>-<id>.
4. The command is re-run with SECRET_EXEMPT=<reason>. The classifier recomputes
   the same id, finds the record, DELETES it, and allows the command once.

The delete in step 4 is what makes an approval single-use, which is what
rules/gates.md promises ("re-run once, covering that one command only -- not the
file, not the session"). os.remove is the consume: it succeeds for exactly one
caller, so a concurrent second attempt loses rather than sharing the grant.

FINGERPRINT SCOPE -- what changes the id and what does not
----------------------------------------------------------
The id is computed over segments()' parse, not the raw text, so incidental
whitespace and assignment ORDER do not change it. Deliberately:

  * SECRET_EXEMPT's own value is EXCLUDED. The user approves a command, not a
    wording; re-typing the reason differently must not silently waste a grant.
  * Every OTHER assignment is INCLUDED. `FOO=1 cat x` and `cat x` are different
    commands -- an assignment can change what the command reads (`HOME=/x cat
    $HOME/.zshrc`) -- and including them keeps the id in a deny message tied to
    the exact command that produced it.
  * The lexer's own blind spots are inherited whole. Two commands that segments()
    parses identically share an id. That is the same lexer the block decision
    already rests on, so it adds no new blindness.

FAIL DIRECTION -- opposite to the rest of the hook, on purpose
--------------------------------------------------------------
secret-command-guard.sh fails OPEN on a broken classifier: it sits on every Bash
call in every session, and a de facto ban on using the shell is worse than the
leak it prevents. This module fails the other way -- a missing, unreadable or
corrupt store means the bypass is REFUSED and the command is judged on its own
merits (user decision, 2026-08-30). The asymmetry is safe because refusing a
bypass can only ever block a command that was ALREADY a blockable shape; it
never touches ordinary work. The alternative -- honouring an unverifiable
permission slip -- would mean `rm -rf` on one state directory silently restores
the old unchecked flag, with nothing running to report that it had.

Usage:
  secret_approval.py id <command-text>            # print the approval id
  secret_approval.py grant <id> [--session <sid>] # record an approval
Exit 0 on success, 2 on a malformed argument or an unwritable store.
"""
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_segments import segments  # noqa: E402

EXEMPT_VAR = "SECRET_EXEMPT"
ID_LEN = 16
ID_RE = re.compile(r"^[0-9a-f]{%d}$" % ID_LEN)
NO_SESSION = "nosession"

# Both halves of the filename are attacker-adjacent -- the id comes from a
# command line and the session id from a JSON payload -- and both are pasted
# into a path. Validate the id by shape and scrub the session, so neither can
# walk out of the state directory.
_SESSION_UNSAFE_RE = re.compile(r"[^A-Za-z0-9._-]")


def state_dir():
    override = os.environ.get("SECRET_GUARD_STATE_DIR")
    if override:
        return override
    return os.path.join(os.environ.get("HOME", ""), ".claude", "hooks", "state")


def safe_session(session):
    session = (session or "").strip() or NO_SESSION
    return _SESSION_UNSAFE_RE.sub("_", session)[:128]


def fingerprint(command):
    """A stable id for the command, ignoring only SECRET_EXEMPT's value."""
    shape = []
    for assigns, argv in segments(command):
        kept = {k: v for k, v in (assigns or {}).items() if k != EXEMPT_VAR}
        shape.append([sorted(kept.items()), list(argv or [])])
    blob = json.dumps(shape, separators=(",", ":"), sort_keys=True)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:ID_LEN]


def approval_path(session, approval_id):
    return os.path.join(
        state_dir(), "secret-approval-%s-%s" % (safe_session(session), approval_id)
    )


def consume(session, approval_id):
    """True if an approval existed and was spent. Any store problem -> False."""
    if not ID_RE.match(approval_id or ""):
        return False
    try:
        os.remove(approval_path(session, approval_id))
        return True
    except OSError:
        return False


def grant(session, approval_id):
    if not ID_RE.match(approval_id or ""):
        raise ValueError("approval id must be %d lowercase hex chars" % ID_LEN)
    path = approval_path(session, approval_id)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write("")
    return path


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip().rsplit("Usage:", 1)[-1], file=sys.stderr)
        return 2

    mode, arg = argv[1], argv[2]
    session = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if "--session" in argv:
        i = argv.index("--session")
        if i + 1 >= len(argv):
            print("--session needs a value", file=sys.stderr)
            return 2
        session = argv[i + 1]

    if mode == "id":
        print(fingerprint(arg))
        return 0

    if mode == "grant":
        try:
            path = grant(session, arg)
        except (ValueError, OSError) as exc:
            print("secret_approval: cannot record approval: %s" % exc, file=sys.stderr)
            return 2
        print(
            "recorded an approval for id %s in session %s.\n"
            "It clears ONE run of ONE command and is deleted on first use.\n"
            "It records that an approval was claimed -- it does not prove one was given."
            % (arg, safe_session(session)),
            file=sys.stderr,
        )
        print(path)
        return 0

    print("unknown mode %r (expected 'id' or 'grant')" % mode, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
