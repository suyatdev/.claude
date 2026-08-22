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

import errno
import os
from pathlib import Path

TREKO_STORE_DIR_ENV = "TREKO_STORE_DIR"
XDG_STATE_HOME_ENV = "XDG_STATE_HOME"

# The XDG fallback base, with `~` left in place -- expanduser() (below) is what turns it
# into the real home directory, the same way it handles an explicit `~`-prefixed value.
DEFAULT_STATE_HOME = "~/.local/state"
STORE_DIRNAME = "treko"

STORE_DIR_MODE = 0o700  # owner-only; see the module-level rationale in the design doc (D2)


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
        if not os.access(str(path), os.W_OK):
            raise StartupAbort(
                "%s is not writable (errno %d: %s)"
                % (path, errno.EACCES, os.strerror(errno.EACCES)))
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
