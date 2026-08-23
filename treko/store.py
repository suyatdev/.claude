"""Persist Treko analysis runs to the UI's data file.

The browser UI loads `tracker-data.js` with a plain `<script src>` tag, so the
store is a JS assignment (`window.TRACKER_DATA = {...};`) rather than JSON.
The envelope — version, tool, generatedAt, repoUrls, runs — matches the
`task-tracker v0.4.1` schema export; this module never redesigns it.

Two invariants carry the acceptance criteria:

  * **Upsert by run id.** Re-analysing replaces the run holding that id and
    leaves every other run untouched. Switching between analyses and
    re-analysing one are the same operation on different keys, so there is one
    code path, not two.
  * **Atomic write.** Content goes to a temp file in the same directory and is
    moved into place with `os.replace`. A half-written `tracker-data.js` is a
    JS syntax error, which blanks the whole UI instead of degrading it, so the
    target file is only ever swapped for a complete one.
"""

import copy
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = 1
TOOL = "task-tracker v0.4.1"

ASSIGNMENT = "window.TRACKER_DATA"
JS_PREFIX = ASSIGNMENT + " = "
JS_SUFFIX = ";\n"

TEMP_PREFIX = ".tracker-data-"
TEMP_SUFFIX = ".js.tmp"

# Readable by whatever serves the UI; only used when creating a new store, as
# an existing file's mode is carried across the replace.
DEFAULT_FILE_MODE = 0o644

TIMESTAMP_FORMAT = "%Y-%m-%dT%H:%M:%SZ"


class StoreError(Exception):
    """The store on disk is unreadable or is not a tracker-data.js envelope."""


def _utc_now_iso():
    return datetime.now(timezone.utc).strftime(TIMESTAMP_FORMAT)


def _validate_run(run):
    """Runs arrive from the analyzer, a system boundary — check before writing."""
    if not isinstance(run, dict):
        raise ValueError(f"run must be a dict, got {type(run).__name__}")
    run_id = run.get("id")
    if not isinstance(run_id, str) or not run_id.strip():
        raise ValueError("run['id'] must be a non-empty string")


def new_store(repo_urls=None, generated_at=None):
    """An empty envelope, with keys in the order the schema export uses."""
    return {
        "version": SCHEMA_VERSION,
        "tool": TOOL,
        "generatedAt": generated_at or _utc_now_iso(),
        "repoUrls": dict(repo_urls or {}),
        "runs": [],
    }


def dumps(data):
    """Render the envelope as the JS assignment the UI loads.

    `ensure_ascii` is not cosmetic: it escapes U+2028/U+2029, which are legal
    inside a JSON string but were illegal raw in a JS string literal before
    ES2019 — the one place JSON is not a subset of JS.
    """
    body = json.dumps(data, indent=2, ensure_ascii=True)
    return JS_PREFIX + body + JS_SUFFIX


def loads(text):
    """Parse a tracker-data.js back into the envelope dict."""
    body = text.strip()
    if not body.startswith(ASSIGNMENT):
        raise StoreError(f"not a tracker-data.js envelope: missing {ASSIGNMENT}")

    body = body[len(ASSIGNMENT) :].lstrip()
    if not body.startswith("="):
        raise StoreError(f"not a tracker-data.js envelope: {ASSIGNMENT} is not assigned")
    body = body[1:].strip()

    if body.endswith(";"):
        body = body[:-1].strip()

    try:
        data = json.loads(body)
    except ValueError as exc:
        raise StoreError(f"tracker-data.js is not parseable: {exc}") from exc

    if not isinstance(data, dict) or not isinstance(data.get("runs"), list):
        raise StoreError("tracker-data.js does not hold a runs[] envelope")
    return data


def read_store(path):
    """Load the store, or a fresh empty envelope when the file does not exist."""
    path = Path(path)
    if not path.exists():
        return new_store()
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise StoreError(f"cannot read {path}: {exc}") from exc
    return loads(text)


def get_run(data, run_id):
    """Select one run — this is what the UI's run switcher does. Read-only."""
    for run in data.get("runs", []):
        if run.get("id") == run_id:
            return run
    return None


def upsert_run(data, run):
    """Return a new envelope with `run` replacing the run of the same id.

    Position is preserved on replace so the UI's run list does not reshuffle
    under the user when they re-analyse.
    """
    _validate_run(run)
    runs = list(data.get("runs", []))
    incoming = copy.deepcopy(run)

    for index, existing in enumerate(runs):
        if existing.get("id") == incoming["id"]:
            runs[index] = incoming
            return {**data, "runs": runs}

    runs.append(incoming)
    return {**data, "runs": runs}


def _target_mode(path):
    try:
        return os.stat(path).st_mode & 0o777
    except FileNotFoundError:
        return DEFAULT_FILE_MODE


def _unlink_quietly(path):
    try:
        os.unlink(path)
    except OSError:
        pass


def write_store(path, data):
    """Write the envelope atomically: temp file alongside, then `os.replace`.

    The temp file must share a directory with the target, or the rename crosses
    a filesystem boundary and stops being atomic.
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    text = dumps(data)
    mode = _target_mode(path)

    fd, temp_path = tempfile.mkstemp(
        dir=str(path.parent), prefix=TEMP_PREFIX, suffix=TEMP_SUFFIX
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_path, mode)
        os.replace(temp_path, path)
    except BaseException:
        # Includes KeyboardInterrupt/SystemExit: never strand a .js.tmp beside
        # the store. A SIGKILL can still leave one, but never a partial target.
        _unlink_quietly(temp_path)
        raise


def emit_run(path, run, repo_urls=None, generated_at=None, now=None):
    """Upsert one run into the store at `path` and write it out atomically.

    `analyzedAt` is the analyzer's to set; it is only stamped here when the
    caller left it off. Returns the envelope that was written.
    """
    _validate_run(run)
    path = Path(path)

    data = read_store(path)

    incoming = dict(run)
    if not incoming.get("analyzedAt"):
        incoming["analyzedAt"] = now or _utc_now_iso()

    data = upsert_run(data, incoming)

    if repo_urls:
        data = {**data, "repoUrls": {**data.get("repoUrls", {}), **repo_urls}}

    data = {**data, "generatedAt": generated_at or _utc_now_iso()}

    write_store(path, data)
    return data
