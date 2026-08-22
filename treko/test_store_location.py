"""Red tests for `store_location.read_store_dir`, `store_location.ensure_store_dir` and
`store_location.adopt_legacy_store`.

`docs/features/treko-store-location.md` SS D1, SS D2 and SS D4 are authoritative; the values
below are transcribed from the design table and the Scenarios block rather than read back out
of an implementation, because `treko/store_location.py` does not have these functions yet --
these tests define what "done" means for tasks 2, 3 and 5, not confirm it.

Covers acceptance criteria 1, 3, 4, 10, 11 and 12.

**D4's two contract points are pinned here, not just described.** The design says
`adopt_legacy_store` "announces which of its three outcomes happened" and returns something "a
caller can act on... without parsing English", but does not spell out the return value's exact
form -- so this file pins it: three plain strings, `"copied"`, `"already_present"` and
`"no_legacy"`, one per outcome in the same order as D4's three stderr lines. Task 6's
implementer is being given this same wording as the contract to build against.

**`environ` carries only what the design says the process actually reads.** `TREKO_STORE_DIR`
and `XDG_STATE_HOME` are read from the injected mapping, mirroring how `read_port` and
`read_timeout` are tested in `test_rename.py`. `HOME` is not: D1 pins the canonicalization
step as `Path(value).expanduser().resolve()`, and stdlib `expanduser()` takes no environ
argument -- it always reads the real process's home directory. So the "XDG_STATE_HOME unset"
test below asserts against the real `$HOME/.local/state/treko`, computed the same way the
implementation must compute it, rather than against an injected fake HOME that `expanduser()`
could never see.

**`StartupAbort` is imported from `store_location`, not `server`.** D5 moves it there so both
modules can import it; today it still lives in `server.py`, so this import is itself part of
the red state on purpose -- it fails alongside the rest of the module until task 4 lands, and
needs no edit here once it does.

**What this file does not cover.** The `_serve_static` branch plus the startup banner (D3,
task 7) is a separate dispatch with its own red steps. Nor does it drive `read_store_dir()`
called with no argument at all -- that path reads the live process environment and cannot be
asserted deterministically from a test process whose own HOME and XDG_STATE_HOME are whatever
the machine running the suite happens to have.

**Every D4 fixture is synthesised inside `tmp_path`.** The real `treko/tracker-data.js` holds
four snapshots dated 2026-08-20T03:07:28Z that cannot be regenerated (the card's Risks
section) -- no test here reads, writes, or depends on it. Legacy envelopes are built through
`store.new_store` / `store.upsert_run` / `store.write_store` so the fixtures stay valid if the
envelope shape changes, except for the corrupt-file case, which is deliberately hand-written
garbage.
"""

import errno
import os
import re
import stat
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import store  # noqa: E402
from store_location import (  # noqa: E402
    StartupAbort,
    adopt_legacy_store,
    ensure_store_dir,
    read_store_dir,
)


# --------------------------------------------------------------------------
# D1 -- resolution: one directory, one constant filename (criteria 1, 10)
# --------------------------------------------------------------------------


def test_default_uses_xdg_state_home_when_set_in_the_injected_mapping():
    resolved = read_store_dir({"XDG_STATE_HOME": "/custom/xdg-state"})

    assert resolved == Path("/custom/xdg-state/treko").resolve()


def test_default_falls_back_to_home_local_state_when_xdg_state_home_is_unset():
    """No TREKO_STORE_DIR, no XDG_STATE_HOME -- the real $HOME/.local/state/treko.

    Built the same way the implementation must build it (`~/.local/state/treko`, then
    `expanduser()`), not from an injected HOME -- see the module docstring.
    """
    resolved = read_store_dir({})

    expected = Path("~/.local/state/treko").expanduser().resolve()
    assert resolved == expected


def test_treko_store_dir_wins_over_the_default(tmp_path):
    explicit = tmp_path / "explicit-store"

    resolved = read_store_dir(
        {
            "TREKO_STORE_DIR": str(explicit),
            "XDG_STATE_HOME": str(tmp_path / "xdg-should-be-ignored"),
        }
    )

    assert resolved == explicit.resolve()


def test_a_tilde_prefixed_value_is_expanded_via_expanduser():
    resolved = read_store_dir({"TREKO_STORE_DIR": "~/treko-store-location-test"})

    assert resolved == Path("~/treko-store-location-test").expanduser().resolve()


def test_a_relative_value_is_resolved_against_the_process_cwd(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)

    resolved = read_store_dir({"TREKO_STORE_DIR": "relative-store"})

    assert resolved == (tmp_path / "relative-store").resolve()


def test_dollar_variables_inside_the_value_are_not_expanded(tmp_path, monkeypatch):
    """D1's `no_expansion` row: only `~` is special; nothing else in the string is."""
    monkeypatch.chdir(tmp_path)

    resolved = read_store_dir(
        {
            "TREKO_STORE_DIR": "$HOME/treko",
            "HOME": str(tmp_path / "real-home"),
        }
    )

    assert resolved == (tmp_path / "$HOME" / "treko").resolve()
    assert "real-home" not in str(resolved)


def test_returns_the_canonical_form_of_a_symlinked_store_dir(tmp_path):
    """Criterion 10, and the property D3's containment check depends on entirely.

    Built from our own symlink under `tmp_path` rather than `/tmp` itself, so the test does
    not depend on `/tmp` -> `/private/tmp` existing on this particular machine -- but it
    asserts exactly the property that macOS case is an instance of: the returned path must be
    symlink-free, or a directory reached through a symlink 403s every request (D1, D3).
    """
    real_dir = tmp_path / "real-store"
    real_dir.mkdir()
    link = tmp_path / "link-to-store"
    link.symlink_to(real_dir)

    resolved = read_store_dir({"TREKO_STORE_DIR": str(link)})

    assert resolved == real_dir.resolve()
    assert resolved != link


# --------------------------------------------------------------------------
# D2 -- startup validation, on the existing abort path (criteria 3, 11)
# --------------------------------------------------------------------------


def test_creates_a_missing_directory_including_parents(tmp_path):
    target = tmp_path / "nested" / "store"

    result = ensure_store_dir(target)

    assert result == target
    assert target.is_dir()


def test_leaves_an_existing_writable_directory_alone(tmp_path):
    target = tmp_path / "existing-store"
    target.mkdir()

    result = ensure_store_dir(target)

    assert result == target
    assert target.is_dir()


def test_rejects_a_path_that_is_a_regular_file(tmp_path):
    target = tmp_path / "not-a-directory"
    target.write_text("i am a file, not a directory")

    with pytest.raises(StartupAbort) as excinfo:
        ensure_store_dir(target)

    assert str(target) in str(excinfo.value)


@pytest.mark.skipif(
    hasattr(os, "geteuid") and os.geteuid() == 0,
    reason="root ignores directory write permissions, so the parent is never actually locked",
)
def test_reports_the_path_and_errno_when_the_directory_cannot_be_created(tmp_path):
    parent = tmp_path / "locked-parent"
    parent.mkdir()
    target = parent / "store"
    os.chmod(parent, 0o500)
    try:
        with pytest.raises(StartupAbort) as excinfo:
            ensure_store_dir(target)
        message = str(excinfo.value)
        assert str(target) in message
        assert str(errno.EACCES) in message
    finally:
        os.chmod(parent, 0o700)  # restore before tmp_path's own cleanup runs


@pytest.mark.skipif(
    hasattr(os, "geteuid") and os.geteuid() == 0,
    reason="root ignores directory write permissions, so an existing directory is never actually locked",
)
def test_reports_the_path_and_an_errno_when_an_existing_directory_is_not_writable(tmp_path):
    """D2 row 4's other half: not "cannot create" but "exists and is not writable".

    Green today and pinned: it passes now because the current check is `os.access`, which
    answers yes/no and never reports why -- the errno in the message is `errno.EACCES`
    chosen by the code, not one a syscall returned. It exists to keep passing once that
    source changes to a real `OSError.errno` from an actual write attempt: this test asserts
    only the row's shape (an abort naming the path and *an* errno), never which errno, so it
    needs no edit when the number's source does.
    """
    target = tmp_path / "readonly-store"
    target.mkdir()
    os.chmod(target, 0o500)
    try:
        with pytest.raises(StartupAbort) as excinfo:
            ensure_store_dir(target)
        message = str(excinfo.value)
        assert str(target) in message
        assert re.search(r"errno \d+", message)
    finally:
        os.chmod(target, 0o700)  # restore before tmp_path's own cleanup runs


def test_a_newly_created_directory_is_mode_0o700(tmp_path):
    target = tmp_path / "fresh-store"

    ensure_store_dir(target)

    assert stat.S_IMODE(target.stat().st_mode) == 0o700


def test_an_existing_directorys_mode_is_left_alone(tmp_path):
    target = tmp_path / "already-there"
    target.mkdir(mode=0o755)
    os.chmod(target, 0o755)  # mkdir's mode argument is subject to umask; set it explicitly

    ensure_store_dir(target)

    assert stat.S_IMODE(target.stat().st_mode) == 0o755


# --------------------------------------------------------------------------
# D4 -- the one-time legacy-store copy (criteria 4, 12)
# --------------------------------------------------------------------------


def _write_legacy_envelope(path, run_ids):
    """Build a real envelope through store.py, not hand-written JS text (see module docstring)."""
    data = store.new_store()
    for run_id in run_ids:
        data = store.upsert_run(data, {"id": run_id})
    store.write_store(path, data)
    return data


def test_adopts_a_legacy_store_once_comparing_by_run_id(tmp_path, capsys):
    legacy_path = tmp_path / "legacy" / "tracker-data.js"
    store_path = tmp_path / "configured" / "tracker-data.js"
    run_ids = ["run-a", "run-b", "run-c", "run-d"]
    _write_legacy_envelope(legacy_path, run_ids)

    outcome = adopt_legacy_store(store_path, legacy_path)

    assert outcome == "copied"
    adopted_ids = {run["id"] for run in store.read_store(store_path)["runs"]}
    assert adopted_ids == set(run_ids)  # a count would pass even for four empty runs

    captured = capsys.readouterr()
    assert captured.err.splitlines() == [
        "copied %d runs from %s" % (len(run_ids), legacy_path)
    ]


def test_a_second_launch_does_not_rewrite_the_already_adopted_store(tmp_path, capsys):
    legacy_path = tmp_path / "legacy" / "tracker-data.js"
    store_path = tmp_path / "configured" / "tracker-data.js"
    _write_legacy_envelope(legacy_path, ["run-a", "run-b", "run-c", "run-d"])

    adopt_legacy_store(store_path, legacy_path)
    capsys.readouterr()  # discard the first launch's stderr line
    before_bytes = store_path.read_bytes()
    before_mtime_ns = store_path.stat().st_mtime_ns

    outcome = adopt_legacy_store(store_path, legacy_path)

    assert outcome == "already_present"
    assert store_path.read_bytes() == before_bytes
    assert store_path.stat().st_mtime_ns == before_mtime_ns  # untouched, not merely unchanged

    captured = capsys.readouterr()
    assert captured.err.splitlines() == ["store already present, legacy file ignored"]


def test_an_existing_real_store_is_never_overwritten_by_the_legacy_file(tmp_path):
    legacy_path = tmp_path / "legacy" / "tracker-data.js"
    store_path = tmp_path / "configured" / "tracker-data.js"
    _write_legacy_envelope(legacy_path, ["legacy-1", "legacy-2", "legacy-3", "legacy-4"])
    _write_legacy_envelope(store_path, ["real-run"])

    outcome = adopt_legacy_store(store_path, legacy_path)

    assert outcome == "already_present"
    remaining_ids = {run["id"] for run in store.read_store(store_path)["runs"]}
    assert remaining_ids == {"real-run"}  # the guard against destroying unregenerable snapshots


def test_a_corrupt_legacy_file_aborts_and_never_creates_the_configured_store(tmp_path):
    legacy_path = tmp_path / "legacy" / "tracker-data.js"
    store_path = tmp_path / "configured" / "tracker-data.js"
    legacy_path.parent.mkdir(parents=True)
    legacy_path.write_text("this is not a tracker-data.js envelope at all")

    with pytest.raises(StartupAbort) as excinfo:
        adopt_legacy_store(store_path, legacy_path)

    assert str(legacy_path) in str(excinfo.value)
    assert not store_path.exists()  # silently starting empty is how snapshots disappear


def test_no_legacy_store_to_adopt_when_neither_file_exists(tmp_path, capsys):
    legacy_path = tmp_path / "legacy" / "tracker-data.js"
    store_path = tmp_path / "configured" / "tracker-data.js"

    outcome = adopt_legacy_store(store_path, legacy_path)

    assert outcome == "no_legacy"
    assert not store_path.exists()

    captured = capsys.readouterr()
    assert captured.err.splitlines() == ["no legacy store to adopt"]


def test_the_copied_message_names_the_real_run_count_not_a_fixed_number(tmp_path, capsys):
    """A different N than the other tests' 4, so a hardcoded "copied 4 runs" cannot pass."""
    legacy_path = tmp_path / "legacy" / "tracker-data.js"
    store_path = tmp_path / "configured" / "tracker-data.js"
    run_ids = ["only-run-1", "only-run-2"]
    _write_legacy_envelope(legacy_path, run_ids)

    adopt_legacy_store(store_path, legacy_path)

    captured = capsys.readouterr()
    assert captured.err.splitlines() == [
        "copied %d runs from %s" % (len(run_ids), legacy_path)
    ]
