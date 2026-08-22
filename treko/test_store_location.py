"""Red tests for `store_location.read_store_dir` and `store_location.ensure_store_dir`.

`docs/features/treko-store-location.md` SS D1 and SS D2 are authoritative; the values below
are transcribed from the design table and the Scenarios block rather than read back out of
an implementation, because `treko/store_location.py` does not exist yet -- these tests define
what "done" means for tasks 2 and 3, not confirm it.

Covers acceptance criteria 1, 3, 10 and 11.

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

**What this file does not cover.** `adopt_legacy_store` (D4, task 5) and the `_serve_static`
branch plus the startup banner (D3, task 7) are separate dispatches with their own red steps.
Nor does it drive `read_store_dir()` called with no argument at all -- that path reads the
live process environment and cannot be asserted deterministically from a test process whose
own HOME and XDG_STATE_HOME are whatever the machine running the suite happens to have.
"""

import errno
import os
import stat
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from store_location import StartupAbort, ensure_store_dir, read_store_dir  # noqa: E402


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
