"""Red tests for `channel.bind_surface`, `channel.SurfaceUnavailable` and `channel.Reason`.

`docs/features/treko-degraded-no-cmux.md` §D1 is authoritative; the four reason tokens and the
exception's shape below are transcribed from that section's yaml block rather than read back out
of an implementation, because `treko/channel.py` does not exist yet — these tests define what
"done" means for task 3, not confirm it.

Covers checklist task 2: each of the four reason tokens is raised by driving the *real* failure
path, and the reason set is closed.

**The import is `channel`, not `treko.channel`.** `treko/` holds no `__init__.py`, so every
sibling test in this directory imports flat off the `sys.path` shim below (`import server`,
`from store_location import ...`). D6 makes `channel.py` a sibling of `server.py`, so `channel`
is the name it will answer to once task 3 lands, and this file needs no edit then.

**The whole module is red on import today, on purpose.** `channel.py` does not exist, so
collection fails with `ModuleNotFoundError: No module named 'channel'`. That is the correct red
state for a test-first step; task 3 creates the module and turns every test here green.

**Every failure is driven, never mocked.** `bind_surface` itself is called for real in each test;
what varies is `CMUX_BIN`, monkeypatched on the `channel` module (it is a module-level constant
read once at import, so setting the environment variable would do nothing). `probe_timeout` and
`probe_failed` point it at a two-line shell script synthesised in `tmp_path`; `cmux_unrunnable`
points it at a path that does not exist. An autouse fixture points it at that same nonexistent
path for *every* test, so no test in this file can reach a real `cmux` on the developer's machine
— including the `surface_unset` cases, which must fail before any subprocess is spawned at all.

**The human messages are asserted verbatim.** D1 pins them as "unchanged from today, verbatim —
it still goes to stderr", so today's `server.py:216-235` is the authority for the four strings
below rather than a thing they are merely compared against. D2 writes the exception with
`"server: %s\n" % exc`, so `str(exc)` carrying the message is part of the contract, not an
incidental of how `StartupAbort` was constructed.
"""

import enum
import errno
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import channel  # noqa: E402  (path shim above must run first)
import server  # noqa: E402
from channel import (  # noqa: E402
    Reason,
    SurfaceUnavailable,
    bind_surface,
)


# Transcribed from D1's yaml block: the closed set, in the order the design lists it.
REASON_TOKENS = ("surface_unset", "probe_timeout", "probe_failed", "cmux_unrunnable")

SURFACE_ENV = "CMUX_SURFACE_ID"  # D1; D6 moves the constant itself into `channel.py`
SURFACE = "11111111-2222-3333-4444-555555555555"

# Nothing is at this path, so `subprocess.run` raises OSError(ENOENT) rather than running
# anything. It is both the `cmux_unrunnable` driver and the default guard against a test in
# this file accidentally invoking the real `cmux`.
NONEXISTENT_CMUX = "/nonexistent/path/to/cmux-does-not-exist"


@pytest.fixture(autouse=True)
def never_the_real_cmux(monkeypatch):
    """No test here may spawn the developer's actual `cmux`.

    A `surface_unset` case that reached a subprocess would be an ordering bug in
    `bind_surface`; with this default it surfaces as the wrong reason token instead of as a
    real probe against a real terminal.
    """
    monkeypatch.setattr(channel, "CMUX_BIN", NONEXISTENT_CMUX)


@pytest.fixture
def fake_cmux(tmp_path, monkeypatch):
    """Install a shell script as `CMUX_BIN` and return the path `bind_surface` will run.

    The script ignores its arguments: `bind_surface` invokes it as
    `read-screen --surface <uuid>`, and a stock binary like `sleep` or `false` would either
    reject those arguments or exit for the wrong reason.
    """

    def _install(body):
        script = tmp_path / "fake-cmux"
        script.write_text("#!/bin/sh\n%s\n" % body)
        script.chmod(0o755)
        monkeypatch.setattr(channel, "CMUX_BIN", str(script))
        return str(script)

    return _install


# --------------------------------------------------------------------------
# The reason set is closed — a fifth member is a spec change, not a code change
# --------------------------------------------------------------------------


def test_the_reason_set_holds_exactly_the_four_tokens_the_design_names():
    assert len(Reason) == 4
    assert {member.value for member in Reason} == set(REASON_TOKENS)
    assert [member.name for member in Reason] == list(REASON_TOKENS)


def test_every_member_name_matches_its_own_value():
    """The token is the wire form; a member whose name and value diverge would make
    `Reason.probe_failed.value` and the string `"probe_failed"` two different facts."""
    for member in Reason:
        assert member.name == member.value


def test_success_is_not_a_reason():
    """D1: `CHANNEL_OK = "ok"` is deliberately *not* a `Reason` member, so that `len(Reason)`
    keeps describing how many ways `bind_surface` can fail."""
    assert "ok" not in {member.value for member in Reason}


def test_reason_is_a_plain_enum_and_not_a_str_mixin():
    """D1 mandates a plain `Enum` so that `.value` is *required* rather than coincidental.

    A `str`-mixin enum would make `"{}".format()` and f-strings render the bare token by
    accident — a correctness that depends on a declaration style nothing else asserts, and one
    that breaks silently the day the declaration changes. The formatting assertions below are
    the falsifier: they fail if the mixin is ever added back.
    """
    assert issubclass(Reason, enum.Enum)
    assert not issubclass(Reason, str)
    assert "{}".format(Reason.surface_unset) != "surface_unset"
    assert "%s" % Reason.surface_unset != "surface_unset"
    assert str(Reason.surface_unset) != "surface_unset"
    assert Reason.surface_unset.value == "surface_unset"


def test_surface_unavailable_is_a_startup_abort():
    """D1 subclasses rather than adds a flag, so every existing `except StartupAbort` in
    `main()` keeps catching this one untouched (criterion 9)."""
    assert issubclass(SurfaceUnavailable, server.StartupAbort)


# --------------------------------------------------------------------------
# surface_unset — CMUX_SURFACE_ID is unset or empty
# --------------------------------------------------------------------------

SURFACE_UNSET_MESSAGE = (
    "%s is unset or empty -- the server was detached or launched outside cmux, and "
    "a send with no target defaults to whatever surface it inherits" % SURFACE_ENV
)


@pytest.mark.parametrize(
    "environ",
    [
        pytest.param({}, id="absent"),
        pytest.param({SURFACE_ENV: ""}, id="empty"),
        pytest.param({SURFACE_ENV: "   "}, id="spaces"),
        pytest.param({SURFACE_ENV: "\t\n"}, id="whitespace"),
    ],
)
def test_an_absent_or_blank_surface_id_raises_surface_unset(environ):
    with pytest.raises(SurfaceUnavailable) as excinfo:
        bind_surface(environ=environ)

    assert excinfo.value.reason is Reason.surface_unset
    assert excinfo.value.reason.value == "surface_unset"


def test_surface_unset_carries_todays_human_message_unchanged():
    with pytest.raises(SurfaceUnavailable) as excinfo:
        bind_surface(environ={})

    assert excinfo.value.message == SURFACE_UNSET_MESSAGE
    assert str(excinfo.value) == SURFACE_UNSET_MESSAGE


# --------------------------------------------------------------------------
# probe_timeout — `cmux read-screen` outran the bound
# --------------------------------------------------------------------------

PROBE_TIMEOUT_SECS = 1  # short enough for a suite, whole so the message's `%ds` is unambiguous


def test_a_probe_that_outruns_the_timeout_raises_probe_timeout(fake_cmux):
    # `exec` so the shell *becomes* the sleep: `subprocess.run` kills its direct child on
    # timeout, and a plain `sleep 30` would leave the grandchild running for 30s.
    fake_cmux("exec sleep 30")

    with pytest.raises(SurfaceUnavailable) as excinfo:
        bind_surface(environ={SURFACE_ENV: SURFACE}, timeout=PROBE_TIMEOUT_SECS)

    assert excinfo.value.reason is Reason.probe_timeout
    assert excinfo.value.reason.value == "probe_timeout"


def test_probe_timeout_carries_todays_human_message_unchanged(fake_cmux):
    script = fake_cmux("exec sleep 30")
    expected = "`%s read-screen` exceeded %ds probing the surface" % (
        script,
        PROBE_TIMEOUT_SECS,
    )

    with pytest.raises(SurfaceUnavailable) as excinfo:
        bind_surface(environ={SURFACE_ENV: SURFACE}, timeout=PROBE_TIMEOUT_SECS)

    assert excinfo.value.message == expected
    assert str(excinfo.value) == expected


# --------------------------------------------------------------------------
# probe_failed — it ran, and said no: the target is not a terminal
# --------------------------------------------------------------------------

PROBE_EXIT_CODE = 3  # not 1, so the assertion cannot pass on a generic truthy failure


def test_a_probe_that_exits_non_zero_raises_probe_failed(fake_cmux):
    fake_cmux("exit %d" % PROBE_EXIT_CODE)

    with pytest.raises(SurfaceUnavailable) as excinfo:
        bind_surface(environ={SURFACE_ENV: SURFACE})

    assert excinfo.value.reason is Reason.probe_failed
    assert excinfo.value.reason.value == "probe_failed"


def test_probe_failed_carries_todays_human_message_unchanged(fake_cmux):
    script = fake_cmux("exit %d" % PROBE_EXIT_CODE)
    expected = (
        "`%s read-screen --surface %s` exited %d -- the control channel does not exist "
        "for this target (an agent-session surface is not a terminal)"
        % (script, SURFACE, PROBE_EXIT_CODE)
    )

    with pytest.raises(SurfaceUnavailable) as excinfo:
        bind_surface(environ={SURFACE_ENV: SURFACE})

    assert excinfo.value.message == expected
    assert str(excinfo.value) == expected


# --------------------------------------------------------------------------
# cmux_unrunnable — the binary could not be run at all
# --------------------------------------------------------------------------


def test_a_cmux_binary_that_does_not_exist_raises_cmux_unrunnable(monkeypatch):
    monkeypatch.setattr(channel, "CMUX_BIN", NONEXISTENT_CMUX)

    with pytest.raises(SurfaceUnavailable) as excinfo:
        bind_surface(environ={SURFACE_ENV: SURFACE})

    assert excinfo.value.reason is Reason.cmux_unrunnable
    assert excinfo.value.reason.value == "cmux_unrunnable"


def test_cmux_unrunnable_carries_todays_human_message_unchanged(monkeypatch):
    monkeypatch.setattr(channel, "CMUX_BIN", NONEXISTENT_CMUX)
    # `strerror` is the C library's text, not this repo's, so it is looked up rather
    # than transcribed.
    expected = "cannot run `%s`: %s" % (NONEXISTENT_CMUX, os.strerror(errno.ENOENT))

    with pytest.raises(SurfaceUnavailable) as excinfo:
        bind_surface(environ={SURFACE_ENV: SURFACE})

    assert excinfo.value.message == expected
    assert str(excinfo.value) == expected


# --------------------------------------------------------------------------
# Every token in the closed set was reached by a real call, not just declared
# --------------------------------------------------------------------------


def test_zz_the_four_drivers_above_cover_every_member_of_the_closed_set():
    """A guard against the set growing without a driver: if a fifth `Reason` is ever added,
    `len(Reason) == 4` above fails and this names what is missing — a test per token."""
    driven = {
        Reason.surface_unset,
        Reason.probe_timeout,
        Reason.probe_failed,
        Reason.cmux_unrunnable,
    }

    assert driven == set(Reason)
