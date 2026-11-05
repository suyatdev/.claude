#!/usr/bin/env python3
"""The cmux control channel: binding this session's surface, and why binding failed.

`docs/features/treko-degraded-no-cmux.md` §D1 is authoritative. `bind_surface` and the three
constants below moved here verbatim from `server.py` (§D6) so that the degraded-mode decision
has one home: a caller that must tell "no surface" apart from "the store is unreadable" reads
`SurfaceUnavailable.reason`, and the reason set is closed by design -- a fifth member is a spec
change, not a code change.

`CONFIRM_REFUSAL_REASONS`, `confirm_surface` and `send_keys` moved here verbatim from
`server.py` too (the send path), so the whole cmux channel lives in this one file.

`StartupAbort` is imported from `store_location`, the module that owns it (§D5), never from
`server.py`: `server.py` imports *this* module, so importing back would be a cycle.
"""

import enum
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from store_location import StartupAbort  # noqa: E402  (moved out per D5, both modules import it)

# The cmux probe and the send share one bound: 5s. An unbounded probe is a server that
# neither starts nor reports why (§Security); an unbounded send is a request that hangs.
CMUX_TIMEOUT_SECS = 5
CMUX_BIN = os.environ.get("CMUX_BIN", "cmux")
SURFACE_ENV = "CMUX_SURFACE_ID"


class Reason(enum.Enum):
    """The closed set of ways `bind_surface` can fail (§D1).

    A plain `Enum`, deliberately not a `str` mixin: `.value` is then *required* to reach the
    wire token, rather than an f-string happening to render it. A mixin would make every
    format string correct by accident and wrong the day the declaration changes.
    """

    surface_unset = "surface_unset"
    probe_timeout = "probe_timeout"
    probe_failed = "probe_failed"
    cmux_unrunnable = "cmux_unrunnable"


# Success is not a `Reason`, so that `len(Reason)` keeps describing how many ways the bind
# can fail rather than how many outcomes it has (§D1).
CHANNEL_OK = "ok"


class SurfaceUnavailable(StartupAbort):
    """No usable cmux surface, plus the machine-readable reason why.

    Subclasses rather than adds a flag: every existing `except StartupAbort` keeps catching
    this untouched, and a caller that cares about degraded mode narrows to this type.
    """

    def __init__(self, reason, message):
        super().__init__(message)  # Exception.__str__ returns args[0], so `str(exc) == message`
        self.reason = reason
        self.message = message


def bind_surface(environ=None, timeout=CMUX_TIMEOUT_SECS):
    """Capture the session's own surface UUID once, and prove it is a terminal.

    The UUID is inherited, never deduced. A send targeted at a *deduced* surface was
    delivered to a different live Claude session at exit 0 during task 1's spike
    (§"Injection route"); the fix is to delete the inference, not to check it harder.
    """
    env = environ if environ is not None else os.environ
    surface = (env.get(SURFACE_ENV) or "").strip()
    if not surface:
        raise SurfaceUnavailable(
            Reason.surface_unset,
            "%s is unset or empty -- the server was detached or launched outside cmux, and "
            "a send with no target defaults to whatever surface it inherits" % SURFACE_ENV)
    try:
        probe = subprocess.run(
            [CMUX_BIN, "read-screen", "--surface", surface],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise SurfaceUnavailable(
            Reason.probe_timeout,
            "`%s read-screen` exceeded %ds probing the surface" % (CMUX_BIN, timeout))
    except OSError as exc:
        raise SurfaceUnavailable(
            Reason.cmux_unrunnable, "cannot run `%s`: %s" % (CMUX_BIN, exc.strerror))
    if probe.returncode != 0:
        raise SurfaceUnavailable(
            Reason.probe_failed,
            "`%s read-screen --surface %s` exited %d -- the control channel does not exist "
            "for this target (an agent-session surface is not a terminal)"
            % (CMUX_BIN, surface, probe.returncode))
    return surface


# ----------------------------------------------------------------- send path


# The two unconfirmable states refuse identically on the wire -- 502 send_failed, nothing
# sent -- so the audit reason is the only place an operator can tell "cmux hung" from "cmux
# errored", and a stuck control channel needs a different response from a broken one. Keyed
# by state so task 9 can drive every value from the mapping rather than a hand-listed pair.
CONFIRM_REFUSAL_REASONS = {"unrunnable": "confirm_failed", "timeout": "confirm_timeout"}


def confirm_surface(surface, timeout=CMUX_TIMEOUT_SECS):
    """Re-resolve the bound UUID before any send.

    Returns 'present'|'absent'|'unrunnable'|'timeout'. "Could not confirm" is not
    "confirmed absent" and must never be read as "probably fine" -- the last two outcomes
    refuse, and they are the ones that are silent when wrong. They are separate states
    only so the audit stream keeps them apart; see CONFIRM_REFUSAL_REASONS.
    """
    try:
        tree = subprocess.run(
            [CMUX_BIN, "tree", "--id-format", "both"],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return "timeout"
    except OSError:
        return "unrunnable"
    if tree.returncode != 0:
        return "unrunnable"
    return "present" if surface in tree.stdout else "absent"


def send_keys(surface, payload, timeout=CMUX_TIMEOUT_SECS):
    """Invoke `cmux send`. Returns (ok, sent) where sent is 'yes' or 'unknown'.

    `unknown` is the honest answer whenever send was invoked and did not exit 0: a timeout
    kill may still have typed. A log that resolved this to "failed" would be a lie in the
    direction that loses the operator's trust.
    """
    try:
        result = subprocess.run(
            [CMUX_BIN, "send", "--surface", surface, "--", payload],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return False, "unknown"
    except OSError:
        return False, "unknown"
    if result.returncode != 0:
        sys.stderr.write("server: cmux send exited %d\n" % result.returncode)
        return False, "unknown"
    return True, "yes"
