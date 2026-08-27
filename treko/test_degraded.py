"""Red tests for `channel.bind_surface`, `channel.SurfaceUnavailable` and `channel.Reason`.

`docs/features/treko-degraded-no-cmux.md` §D1 is authoritative; the four reason tokens and the
exception's shape below are transcribed from that section's yaml block rather than read back out
of an implementation, because `treko/channel.py` does not exist yet — these tests define what
"done" means for task 3, not confirm it.

Covers checklist task 2: each of the four reason tokens is raised by driving the *real* failure
path, and the reason set is closed.

Task 4 (§D2) adds the other half, below the second banner: each of those four conditions now
*serves* instead of aborting, the served page's `tracker-channel` meta carries that condition's
own token, `config["surface"] is None`, and -- the anti-regression half -- criterion 9's fatal
conditions still exit 2 and still refuse a connection. Those tests are red until task 5 wires
`main()`'s `except SurfaceUnavailable`, `build_config`'s seventh parameter and the banner
variant; the criterion-9 five are the exception and pass today, because they lock behaviour
this card must *not* change.

**The import is `channel`, not `treko.channel`.** `treko/` holds no `__init__.py`, so every
sibling test in this directory imports flat off the `sys.path` shim below (`import server`,
`from store_location import ...`). D6 makes `channel.py` a sibling of `server.py`, so `channel`
is the name it will answer to once task 3 lands, and this file needs no edit then.

**Task 2's tests were red on import until task 3 landed `channel.py`**, which was the correct
red state for a test-first step. They are green now; task 4's are the ones red today.

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
import re
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
# Reuse, not duplicate (rules/core-conduct.md DRY): criterion 9 says `assert_aborted` is
# unchanged and still used for all of them, which a second copy here would stop being true.
from test_server_lifetime import assert_aborted  # noqa: E402


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


# ==========================================================================
# Task 4 / §D2 — the four conditions serve, and the served bytes say which one
# ==========================================================================

# One row per D2 condition: the `launcher(**kwargs)` that drives it, and the token that
# condition alone must produce. Parametrised rather than written out four times because the
# shape is identical and only the driver differs -- and because a shared body is what makes a
# *swapped* mapping fail: each row asserts its own token, never "one of the five legal ones".
DEGRADED_LAUNCHES = (
    pytest.param({"surface": ""}, "surface_unset", id="surface_unset"),
    pytest.param({"overrides": {"FAKE_READ_SCREEN": "hang"}}, "probe_timeout",
                 id="probe_timeout"),
    pytest.param({"overrides": {"FAKE_READ_SCREEN": "fail"}}, "probe_failed",
                 id="probe_failed"),
    pytest.param({"overrides": {"CMUX_BIN": NONEXISTENT_CMUX}}, "cmux_unrunnable",
                 id="cmux_unrunnable"),
)

# Mirrors `server_harness.py:165`'s token regex; D4 specifies the second meta in the same
# `<head>` replacement and the same `%s` idiom, so the pattern is the same shape.
CHANNEL_META_RE = re.compile(r'<meta name="tracker-channel" content="([^"]+)">')

# D2's worked example, in the order it pins: `surface=none` then `reason=<token>`. The
# trailing space is load-bearing -- without it `reason=probe_failed` would also match a
# hypothetical longer token sharing that prefix.
DEGRADED_BANNER = "surface=none reason=%s "


@pytest.mark.parametrize("launch_kwargs,token", DEGRADED_LAUNCHES)
def test_a_degraded_launch_serves_and_names_its_own_reason(launcher, launch_kwargs, token):
    """Criterion 1, both halves, against one launch per condition.

    The meta and the banner are asserted together rather than in two tests because each
    condition costs a real server start -- `probe_timeout` alone burns the full 5s
    `CMUX_TIMEOUT_SECS` -- and the two claims are about the same launch. Splitting them
    doubles the wall clock to assert nothing extra.

    `wait=True` (the default) is itself the "serves instead of aborting" assertion:
    `await_ready` raises naming the server's own stderr if the process exits first.
    """
    srv = launcher(**launch_kwargs)

    body = srv.get("/").body.decode()
    match = CHANNEL_META_RE.search(body)
    assert match, "GET / served no tracker-channel meta tag:\n%s" % body[:2000]
    assert match.group(1) == token

    assert DEGRADED_BANNER % token in srv.stderr, \
        "the banner did not carry D2's `surface=none reason=%s`:\n%s" % (token, srv.stderr)


# ==========================================================================
# Task 4 / §D2 — `config["surface"] is None`, proved against `build_config`
# ==========================================================================

# Not observable over HTTP: `config` never leaves the server process, and the meta above
# carries the *channel*, not the surface. So criterion 2 is proved where the value is
# assigned, the same way the rest of this module proves internal behaviour -- by calling the
# real function. D2 appends `channel` after `store_dir`; the call below is red with a
# `TypeError` until task 5 widens the signature, which is the correct state for a red step.
BUILD_CONFIG_TOKEN = "not-the-real-token"
BUILD_CONFIG_PORT = 8422
BUILD_CONFIG_ANALYZE_SECS = 60


@pytest.mark.parametrize("token", REASON_TOKENS)
def test_a_degraded_config_holds_no_surface_and_its_own_channel_token(token, tmp_path):
    """Criterion 2: `is None`, never `""`.

    An empty string is what an *unset* environment variable looks like after `.strip()`
    (`channel.py:71`), so a falsy check would pass on the one value D2 rules out.
    """
    config = server.build_config(
        None, BUILD_CONFIG_TOKEN, tmp_path, BUILD_CONFIG_PORT,
        BUILD_CONFIG_ANALYZE_SECS, tmp_path, token)

    assert config["surface"] is None
    assert config["channel"] == token


# ==========================================================================
# Task 4 / criterion 9 — the fatal conditions still exit 2 and serve nothing
# ==========================================================================

# Four of criterion 9's nine already have a full-launch test in `test_server_lifetime.py`
# (busy port, unmapped manifest extension, `<head>`-less index, disabled timeout) and are not
# repeated here. The five below had no full-launch coverage at all -- only unit-level cover of
# the functions they call, in `test_store_location.py` -- so a regression that made any of
# them serve would have gone unnoticed by the very criterion this card leans on.


def test_an_out_of_range_port_aborts_before_serving(launcher):
    """The port is passed as `launch(port=...)`, not through `overrides=`.

    `server_harness.launch` writes `env["TREKO_PORT"] = str(port)` *after* applying
    `overrides`, so a `TREKO_PORT` override is silently replaced by a free port and the
    server starts normally -- the abort would never be driven.
    """
    srv = launcher(port=99999999, wait=False)
    assert_aborted(srv, expect="is not a valid port")


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignores the permission bits this drives")
def test_an_unreadable_index_aborts_before_serving(launcher, tree):
    """`check_index_injectable` reads the index at startup; unreadable is not `<head>`-less,
    and the two abort on different branches (`server.py:207-211`)."""
    index = tree / server.INDEX_FILE
    index.chmod(0o000)
    try:
        srv = launcher(tree=tree, wait=False)
        assert_aborted(srv, expect="cannot read %s" % server.INDEX_FILE)
    finally:
        index.chmod(0o644)


def test_a_store_directory_that_is_a_file_aborts_before_serving(launcher, tmp_path):
    occupied = tmp_path / "store-dir-is-a-file"
    occupied.write_text("not a directory\n")

    srv = launcher(overrides={"TREKO_STORE_DIR": str(occupied)}, wait=False)
    assert_aborted(srv, expect="exists and is not a directory")


@pytest.mark.skipif(os.geteuid() == 0, reason="root ignores the permission bits this drives")
def test_an_unwritable_store_directory_aborts_before_serving(launcher, tmp_path):
    """`ensure_store_dir` probes with a real write rather than `os.access`, so the abort
    carries the errno the store's own write would have got."""
    unwritable = tmp_path / "unwritable-store"
    unwritable.mkdir()
    unwritable.chmod(0o500)  # r-x: listable, not writable
    try:
        srv = launcher(overrides={"TREKO_STORE_DIR": str(unwritable)}, wait=False)
        assert_aborted(srv, expect="is not writable")
    finally:
        unwritable.chmod(0o700)


def test_a_corrupt_legacy_store_aborts_before_serving(launcher, tree, tmp_path):
    """Reaching this abort takes both halves of `adopt_legacy_store`'s guard.

    It checks the *legacy* path first and the configured one second, so the harness's
    default -- `TREKO_STORE_DIR` pointing at the tree itself, where `store_path` and
    `legacy_path` are the same existing file -- short-circuits to "already present" and
    never reads the legacy bytes. So: corrupt the legacy file the server actually names
    (`SERVE_ROOT / FIRST_RUN_OPTIONAL`, i.e. the tree's own copy -- `server.py:709-710`),
    and point the store at a directory where `store_path` does not exist yet.
    """
    (tree / server.FIRST_RUN_OPTIONAL).write_text("window.NOT_TRACKER_DATA = 1;\n")
    fresh_store = tmp_path / "fresh-store"  # absent, so `store_path` inside it is absent too

    srv = launcher(tree=tree, overrides={"TREKO_STORE_DIR": str(fresh_store)}, wait=False)
    assert_aborted(srv, expect="is not a valid legacy store")
