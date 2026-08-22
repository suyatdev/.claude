"""Decide where the analysis store lives, and prove that place is usable.

`docs/features/treko-store-location.md` SS D1 and SS D2 are authoritative. This module owns
resolution and startup validation of the store *directory*; the filename stays a constant
owned elsewhere (`server.py`'s `build_config`, per D3) and adopting a legacy store is a
separate task (D4). `StartupAbort` lives here rather than in `server.py` so both modules can
import one definition instead of each keeping their own (D5).

**Canonicalization is not cosmetic.** `server.py`'s serving path containment-checks a
resolved request path against `resolved.parents`, which is always symlink-free. If the
configured directory were stored as given rather than canonicalized here, a directory reached
through a symlink (`/tmp` is `/private/tmp` on macOS) would never appear in that parents list
and every request would 403. Both sides of that comparison must be canonical, so this module
resolves once, at startup, and everything downstream trusts the result.
"""

import os
import sys
import tempfile
from pathlib import Path

import store  # sibling module; every caller already puts treko/ on sys.path before import

TREKO_STORE_DIR_ENV = "TREKO_STORE_DIR"
XDG_STATE_HOME_ENV = "XDG_STATE_HOME"

# The XDG fallback base, with `~` left in place -- expanduser() (below) is what turns it
# into the real home directory, the same way it handles an explicit `~`-prefixed value.
DEFAULT_STATE_HOME = "~/.local/state"
STORE_DIRNAME = "treko"

STORE_DIR_MODE = 0o700  # owner-only; see the module-level rationale in the design doc (D2)

# adopt_legacy_store's three outcomes (D4) -- the contract test_store_location.py pins.
OUTCOME_COPIED = "copied"
OUTCOME_ALREADY_PRESENT = "already_present"
OUTCOME_NO_LEGACY = "no_legacy"

MSG_COPIED = "copied %d runs from %s"
MSG_ALREADY_PRESENT = "store already present, legacy file ignored"
MSG_NO_LEGACY = "no legacy store to adopt"


class StartupAbort(Exception):
    """A misconfiguration that must surface before anything is served, never as a fallback."""


def read_store_dir(environ=None):
    """Resolve the configured store directory to a canonical absolute `Path`.

    Takes `environ` for the same reason `read_port` and `read_timeout` do (`server.py`) --
    so tests inject a mapping rather than mutating the process environment. `~` in the value
    is expanded via `expanduser()`; nothing else is. In particular, a literal `$VAR` inside
    the value is never expanded -- `expanduser()` only ever touches a leading `~`, and that is
    the whole of D1's expansion rule.
    """
    env = environ if environ is not None else os.environ
    raw = env.get(TREKO_STORE_DIR_ENV)
    if raw is None or raw == "":
        xdg_state_home = env.get(XDG_STATE_HOME_ENV)
        base = xdg_state_home if xdg_state_home else DEFAULT_STATE_HOME
        raw = str(Path(base) / STORE_DIRNAME)
    return Path(raw).expanduser().resolve()


def ensure_store_dir(path):
    """Make `path` usable as the store directory, or raise `StartupAbort` naming why.

    The four outcomes are D2's table, in order: create (parents included, `STORE_DIR_MODE`)
    when absent; leave alone when present, a directory, and writable; abort naming the path
    when present but not a directory; abort naming the path and the errno when creation fails
    or an existing directory is not writable. An existing directory's mode is never changed --
    silently tightening a directory the user already made is not this function's call.
    """
    path = Path(path)
    if path.exists():
        if not path.is_dir():
            raise StartupAbort("%s exists and is not a directory" % path)
        try:
            # A real write, not os.access(): access() only answers yes/no and can't
            # report why. This probe writes into the directory the same way
            # store.py's write_store does before its os.replace, so it fails exactly
            # when the real write would, with the errno that write would actually get.
            with tempfile.NamedTemporaryFile(dir=str(path)):
                pass
        except OSError as exc:
            raise StartupAbort(
                "%s is not writable (errno %d: %s)"
                % (path, exc.errno, exc.strerror))
        return path

    try:
        path.mkdir(mode=STORE_DIR_MODE, parents=True)
        # mkdir's mode argument is subject to the process umask, so it is not on its own a
        # guarantee of STORE_DIR_MODE; chmod it explicitly rather than trust the umask.
        os.chmod(str(path), STORE_DIR_MODE)
    except OSError as exc:
        raise StartupAbort(
            "cannot create %s (errno %d: %s)" % (path, exc.errno, exc.strerror))
    return path


def adopt_legacy_store(store_path, legacy_path):
    """Copy the legacy store into the configured location, exactly once.

    The guard is a conjunction, checked in this order so it stays obvious to a reader:
    copy only when `store_path` is absent *and* `legacy_path` exists. Either half failing
    is its own reported outcome, not a fallthrough -- a present `store_path` must never be
    overwritten (it may hold real data the legacy file does not), and an absent
    `legacy_path` is the ordinary case on every launch after the first, not an error.

    `Path.exists()` decides whether a legacy file is there, never `store.read_store` --
    that call returns a fresh empty envelope for a missing file instead of raising, so
    treating its result as "found" would report every ordinary launch as a successful
    adoption of nothing.

    Reads through `store.read_store` and writes through `store.write_store`, so the copy
    is validated (must parse as an envelope) and atomic (`write_store` places its temp
    file in `store_path`'s own directory, so `os.replace` stays on one filesystem -- see
    the atomicity note in the design doc; do not "optimise" this into a byte copy). A
    `StoreError` from the read becomes a `StartupAbort` naming the legacy file; since
    `write_store` is only reached after a successful read, `store_path` is never created
    on that path.
    """
    store_path = Path(store_path)
    legacy_path = Path(legacy_path)

    if store_path.exists():
        print(MSG_ALREADY_PRESENT, file=sys.stderr)
        return OUTCOME_ALREADY_PRESENT

    if not legacy_path.exists():
        print(MSG_NO_LEGACY, file=sys.stderr)
        return OUTCOME_NO_LEGACY

    try:
        data = store.read_store(legacy_path)
    except store.StoreError as exc:
        raise StartupAbort("%s is not a valid legacy store: %s" % (legacy_path, exc))

    store.write_store(store_path, data)
    print(MSG_COPIED % (len(data["runs"]), legacy_path), file=sys.stderr)
    return OUTCOME_COPIED
