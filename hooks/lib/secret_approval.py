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
whole purpose is to be a place to stop and ask.

Do not call that file an audit trail. It is EMPTY, named only by a truncated
hash and the session, and deleted on first use, so after a bypass has been used
there is nothing left on disk at all. The durable record of a bypass is the
stderr line the wrapper logs into the transcript, not this file.

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
  * The lexer's own blind spots are inherited whole: two commands that segments()
    parses identically share an id. It is the same lexer the block decision
    already rests on, but do NOT conclude from that -- as an earlier revision of
    this docstring did -- that it "adds no new blindness". A blind spot means
    something different for an identity decision than for a block decision: for a
    block it merely fails to catch a shape, while for an identity it silently
    WIDENS what a human's consent covers. The redirection case below is exactly
    that, and it is why is_approvable() refuses rather than trusting the parse.

REDIRECTIONS ARE NOT APPROVABLE
-------------------------------
segments() reads a redirection as part of its command rather than as a separator
and drops it from argv, so the id cannot see one -- measured 2026-08-30:

    id("cat .env")           = 088ade89056f9f6a
    id("cat .env > /tmp/x")  = 088ade89056f9f6a      <- the SAME id

For a BLOCK decision that blindness is harmless. For an IDENTITY decision it is
not: a user who inspected `cat .env` and typed `secret-gate override` would have
unknowingly approved writing that file's contents to disk. The docstring of the
first cut said the inherited blindness "adds no new blindness", which was wrong
in exactly this way -- found by the observability judge, and the reason
is_approvable() exists.

A SECOND SHAPE, same species, found in review round 2: segments() strips a
leading wrapper word (`rtk`, `time`, `eval`, `command`, `builtin`, `exec`,
`nohup`) BEFORE it reads assignments, so a leading `SECRET_EXEMPT=` stops the
stripping and moves the id -- `nohup cat .env` hashes to 088ade89056f9f6a but
`SECRET_EXEMPT=r nohup cat .env` to ee2802fc504a950a (measured). The id printed
in a deny message could therefore never be spent by the re-run. That failed
SAFE, but printing unusable instructions is its own defect.

Closed by REFUSING, not by parsing: any raw command text containing `<` or `>`,
and any command whose id moves when the flag is added, gets no id and is never
exempted. Over-refusing is the safe direction here -- it
costs an out-of-band ask, never a leak -- and it avoids inventing the redirection
mini-language ADR 0039 warned against when it rejected a bounded `grep -o`. A
The cost is that a quoted `>` inside an unrelated argument also makes a command
unapprovable; that only ever fires on a command already being blocked.

An earlier revision of this docstring said "a PIPE needs no special case: it
produces a second segment, so the id already distinguishes it." **That was false,
untested, and is why the separator case below went unwritten for two review
rounds.** A pipe is distinguished from the UNPIPED command, never from `;` or
`&&` -- see the next section. Do not restate it.

A THIRD SHAPE: THE SEPARATOR IS INVISIBLE TOO
---------------------------------------------
segments() returns the segments and drops what joined them, so every separator
hashes alike -- measured 2026-08-30:

    id("cat .env ; true") == id("cat .env | true") == 9c3686e29bdc3ec0

`;` hands the second command nothing; `|` hands it the file. A human who
inspected the `;` form and approved it would have approved the pipe form too --
an exfiltration path THROUGH a human approval, found by the observability judge
in round 3 and reproduced against the live hook. So a command with more than one
segment is not approvable either. Carrying separators into the fingerprint would
mean changing shell_segments.py, which three other guards depend on; refusing
costs `cd /x && cat .env`, which the user can approve as a plain read instead.

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
                                                  # exit 3 = not approvable
  secret_approval.py fingerprint <command-text>   # the raw hash, checks skipped
  secret_approval.py grant <id> [--session <sid>] # record an approval
Exit 0 on success, 2 on a malformed argument or an unwritable store.
"""
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# _lex is shell_segments' own token-producing head, imported rather than
# reimplemented: a second lexer would be free to disagree with the one the block
# decision uses, and the disagreement would land inside a guard. It is private by
# name, and this is a deliberate in-repo coupling -- see accounts_for_every_token.
from shell_segments import segments, _lex, WRAPPERS  # noqa: E402

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


def accounts_for_every_token(command):
    """True when the fingerprint's inputs account for every lexed token.

    THE RULE THAT REPLACED THREE SPECIAL CASES. Three review rounds each found a
    different thing the id could not see -- a redirection, a wrapper word, a
    separator -- and each was patched individually. They were one defect: the
    fingerprint is built from segments(), which was designed for a BLOCK
    decision and keeps only (assignments, argv) per segment, discarding
    everything else. Enumerating what it discards cannot terminate, because the
    list is "whatever the next reviewer notices".

    So this inverts the default. Rather than name the discards, compare the raw
    token list against the tokens the fingerprint actually consumed. If anything
    was dropped -- a `>`, a `;`, a `nohup`, a subshell paren, or something nobody
    has thought of yet -- the id does not identify the command a human saw, and
    it is refused. Closed by default, and it cannot go stale as the lexer grows.

    Costs an approval for `cd /x && cat .env` and `nohup cat .env`. The user can
    approve the plain read instead. That is the right side to err on: an id that
    covers more than the user inspected is how consent gets widened silently,
    which is exactly what round 1 and round 3 each measured.
    """
    toks = _lex(command)
    if toks is None:          # unparseable: segments() fails OPEN for a block
        return False          # decision, the wrong direction for an identity one
    accounted = []
    for assigns, argv in segments(command):
        accounted += ["%s=%s" % kv for kv in (assigns or {}).items()]
        accounted += list(argv or [])
    return sorted(toks) == sorted(accounted)


def unapprovable_reason(command):
    """Why this command cannot be approved, or None if it can.

    Every answer here is a REFUSAL rather than a repair: printing an id that
    cannot work, or one that covers more than the user saw, is worse than
    printing none. The specific cases below run first only so the message can say
    something useful; accounts_for_every_token is the rule that actually holds.
    """
    if "<" in command or ">" in command:
        return ("a redirection is invisible to the approval id, so approving this "
                "command would also approve writing the file's contents elsewhere")

    # The whole flow rests on one property: the id computed from the BLOCKED
    # command must equal the id computed from the same command carrying the flag.
    # segments() strips a leading wrapper word (rtk/time/eval/command/builtin/
    # exec/nohup) BEFORE it reads assignments, so a leading SECRET_EXEMPT= stops
    # the stripping and moves the id -- `nohup cat .env` and
    # `SECRET_EXEMPT=r nohup cat .env` do not match (measured).
    #
    # Tested as the property itself rather than by re-listing WRAPPERS here: a
    # copy of that list would drift from the lexer's, and this form also catches
    # any future quirk with the same shape. It costs one extra hash of a short
    # string, on a path that only runs when a command is already blocked.
    if fingerprint(command) != fingerprint("%s=x %s" % (EXEMPT_VAR, command)):
        return ("a wrapper word makes the approval id unstable -- the id shown here "
                "is not the one the re-run would compute, so the grant could never "
                "be spent")

    # The check above catches a wrapper only on the UNFLAGGED command: once a
    # leading assignment is present the wrapper is no longer stripped, so both
    # sides agree and the flagged form slipped through with a grantable id. Same
    # answer either way -- refuse -- so test argv[0] directly as well, against the
    # lexer's OWN list rather than a copy of it, which would drift.
    parsed = segments(command)

    # The instability check above sees a wrapper only on the UNFLAGGED command:
    # once a leading assignment is present the wrapper is no longer stripped, so
    # both probes agree AND the token accounting balances -- the backstop below
    # cannot catch it either (measured). Without this, refusing `nohup cat .env`
    # would be a detour rather than a refusal: adding the flag and retrying would
    # yield a grantable id. Tested against the lexer's OWN list, never a copy.
    for _assigns, argv in parsed:
        if argv and argv[0] in WRAPPERS:
            return ("a wrapper word (%s) sits in the command position, so the id "
                    "depends on where the shell prefix falls and would not reliably "
                    "identify the command that was inspected" % argv[0])

    # Every separator hashes alike: `;` gives the next command nothing while `|`
    # gives it the file, and the id cannot tell them apart, so approving the
    # harmless-looking form would approve the exfiltrating one. Also refuses the
    # unparseable case (segments() returns [] and fails open for BLOCK decisions,
    # which is the wrong direction for an IDENTITY decision).
    if len(parsed) != 1:
        return ("the approval id cannot see which separator joins the commands -- "
                "`;`, `|`, `&&` and `&` all produce the same id, so approving this "
                "would also approve piping the file into the next command")

    # The backstop, and the only one of these that is not an enumeration. Runs
    # last because the messages above are more specific, but it is what makes the
    # set closed rather than a list of the blindnesses found so far.
    if not accounts_for_every_token(command):
        return ("the approval id does not account for every part of this command "
                "(a wrapper word, grouping, or something else the lexer drops), so "
                "it would not identify the exact command that was inspected")
    return None


def is_approvable(command):
    return unapprovable_reason(command) is None


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

    if mode == "fingerprint":
        # Deliberately skips the approvability checks: this is how the suite pins
        # that `;` and `|` still collide, i.e. that the refusal is still needed.
        print(fingerprint(arg))
        return 0

    if mode == "id":
        why = unapprovable_reason(arg)
        if why:
            print(why, file=sys.stderr)
            return 3
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

    print("unknown mode %r (expected 'id', 'fingerprint' or 'grant')" % mode,
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
