"""What the Ledger routes check and answer (docs/features/treko-ledger.spec.md sections 3.1 and 3.3 to 3.8; D46, D47).

Plain functions, no socket: `server.py` calls them and turns the result into a reply and an audit line. The token
check and the body reader are shared with `/command` (3.8). An accepted poll writes no audit line (section 3.6:
about 1,800 an hour would bury the state-changing ones); a refused one writes exactly one, with id=status.
"""

import hmac
import json
import os
import re
from pathlib import Path

import ledger_jobs
import store
from ledger_state import LedgerWriteError, enqueue, queue_label, run_rows

STORE_FILE = "tracker-data.js"  # where runs live; server.py's FIRST_RUN_OPTIONAL names the same file
TOKEN_HEADER = "X-Tracker-Token"
STORE_UNREADABLE = "store_unreadable"
LEDGER_MAX_BODY_BYTES = 4096  # a macOS path alone can be 1024 bytes and JSON quoting can double it (3.4 step 3)
MAX_DIRECTORY_BYTES, MAX_NAME_BYTES, MAX_RUN_BYTES = 1024, 255, 255
ITEM_PATTERN = re.compile(r"[0-9a-f]{16}")
# op -> (required keys, optional keys); a key set outside required..required+optional is refused, never ignored
OP_KEYS = {"analyze": ({"directory"}, {"repo", "branch", "worktree"}), "reanalyze": ({"run"}, set()),
           "remove": ({"item"}, set()), "retry": ({"item"}, set()), "delete": ({"run"}, set())}
# What the ops task 18 owns (and a reanalyze of a run with no recorded request, task 28's) answer until then: not in
# the spec, a closed-table code that cannot read as success (3.5 has no 501). It lives here, not as a literal in
# server.py, because test_server.py derives the board's reason set from `_fail(` literals in server.py and
# internal_error is not a board reason.
OP_STUB_REFUSAL = (500, "internal_error", "internal_error")
TEXT_FIELDS = ("directory", "repo", "branch", "worktree")  # a bad value is 422 invalid_input; the rest are 400
SCAN_REFUSALS_422 = ("no_repository", "no_matching_repository", "no_such_worktree", "nothing_matched")  # 3.5
SCAN_REFUSALS_500 = (ledger_jobs.SCAN_TIMEOUT, ledger_jobs.SCAN_FAILED)
INTERNAL_ERROR = (500, "internal_error", "internal_error")  # a closed registry: the server is stopping (D49)
LAUNCH_FAILED = (500, "launch_failed", "launch_failed")
LEDGER_WRITE_FAILED = (500, "ledger_write_failed", "ledger_write_failed")
ENQUEUE_REFUSAL_STATUS = 409  # already_queued and queue_full


def _home_collapse(path):
    """Spelled as `analyze._home_collapse` (D8). Not imported: the server runs `analyze.py` as a child, and
    importing it here would also run whatever that file holds at startup (test_server.py swaps in a hanging one)."""
    home, text = str(Path.home()), str(path)
    return "~" + text[len(home):] if text.startswith(home) else text


def check_status_request(headers, config):
    """None when the poll may be answered, else the audit reason of the first failing check.

    Order is Host, then Origin and Sec-Fetch-Site (each only when present), then the token; the caller
    answers the one collapsed 403 whatever the reason, so the reason never reaches the wire.
    """
    if headers.get("Host", "") != config["origin_host"]:
        return "host_mismatch"
    origin = headers.get("Origin")
    if origin is not None and origin != config["origin"]:
        return "origin_mismatch"
    fetch_site = headers.get("Sec-Fetch-Site")
    if fetch_site is not None and fetch_site != "same-origin":
        return "origin_mismatch"
    if not token_ok(headers.get(TOKEN_HEADER, ""), config["token"]):
        return "bad_token"
    return None


def token_ok(presented, expected):
    """The one token comparison (3.8). hmac.compare_digest raises TypeError on a str that is not ASCII (U10),
    and an unhandled error there drops the connection with no audit line, so refuse such a value first."""
    return presented.isascii() and hmac.compare_digest(presented, expected)


def read_json_body(headers, rfile, cap):
    """The parsed JSON, or the refusal `(status, error, reason)`; it checks no shape, each route keeps its own.

    Reads at most cap + 1 bytes: the cap is enforced on the read, not merely checked against a header the
    caller controls. A tuple is never valid JSON output, so the two returns cannot be confused.
    """
    malformed = (400, "malformed", "malformed")
    if headers.get("Transfer-Encoding"):
        return malformed
    declared = headers.get("Content-Length")
    if declared is None:
        return malformed
    try:
        length = int(declared)
    except ValueError:
        return malformed
    if length < 0:
        return malformed
    too_large = (413, "too_large", "too_large")
    if length > cap:
        return too_large
    raw = rfile.read(min(length, cap + 1))
    if len(raw) > cap:
        return too_large
    try:
        return json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError, RecursionError):  # RecursionError is a RuntimeError, not a ValueError (U10)
        return malformed


def _has_control(text):
    return any(ord(char) < 0x20 or ord(char) == 0x7F for char in text)


def _encodable(text):
    try:
        text.encode("utf-8")
    except UnicodeEncodeError:  # a lone surrogate, which a JSON \ud800 escape produces from plain ASCII (U7)
        return False
    return True


def _text_refusal(name, value):
    """The pure rules of 3.4's field table for one text field, or None. Counts UTF-8 bytes, so run after `_encodable`."""
    limit = MAX_DIRECTORY_BYTES if name in ("directory", "worktree") else MAX_NAME_BYTES
    if len(value.encode("utf-8")) > limit or _has_control(value) or (name == "repo" and "/" in value):
        return "invalid_input"
    if name == "directory" and not os.path.isabs(os.path.expanduser(value)):
        return "relative_path"
    return None


def _run_refusal(value, store_dir):
    """`run`'s shape rule (400), then its store lookup (404); `item` is shape-only here, task 17 owns no_such_item."""
    if not 1 <= len(value.encode("utf-8")) <= MAX_RUN_BYTES or _has_control(value):
        return (400, "malformed", "malformed")
    try:
        runs = store.read_store(Path(store_dir) / STORE_FILE)["runs"]
    except store.StoreError:
        return (500, STORE_UNREADABLE, STORE_UNREADABLE)
    if not any(run.get("id") == value for run in runs):
        return (404, "no_such_run", "no_such_run")
    return None


def _field_refusal(fields, store_dir):
    """Step 7, as `(status, error, reason)` or None. Every field passes the UTF-8 rule before any other rule."""
    for name, value in fields.items():
        if not _encodable(value):
            return (422, "invalid_input", "invalid_input") if name in TEXT_FIELDS else (400, "malformed", "malformed")
    for name in TEXT_FIELDS:
        code = _text_refusal(name, fields[name]) if name in fields else None
        if code:
            return (422, code, code)
    if "item" in fields and not ITEM_PATTERN.fullmatch(fields["item"]):
        return (400, "malformed", "malformed")
    if "directory" in fields:  # last of the text rules: it is the only one that touches the filesystem
        if not os.path.isdir(os.path.realpath(os.path.expanduser(fields["directory"]))):
            return (422, "no_such_directory", "no_such_directory")
    if "run" in fields:
        return _run_refusal(fields["run"], store_dir)
    return None


def check_ledger_post(headers, rfile, config):
    """3.4 steps 1 to 7: `(op, fields, None)` when the request may reach its op, else `(None, None, refusal)`.

    A refusal is `(status, error, reason, audit_id)`; the audit id is `-` until step 5 accepts the op, since an
    unknown op is client text and the audit line does not escape it (3.6).
    """
    def refused(status, error, reason, audit_id="-"):
        return None, None, (status, error, reason, audit_id)

    if reason := check_status_request(headers, config):
        return refused(403, "forbidden", reason)
    media_type = headers.get("Content-Type", "").split(";")[0].strip().lower()
    if media_type != "application/json":
        return refused(415, "unsupported_media_type", "unsupported_media_type")
    payload = read_json_body(headers, rfile, LEDGER_MAX_BODY_BYTES)
    if isinstance(payload, tuple):
        return refused(*payload)
    if not isinstance(payload, dict) or not isinstance(payload.get("op"), str):
        return refused(400, "malformed", "malformed")
    op = payload["op"]
    if op not in OP_KEYS:
        return refused(403, "forbidden", "unknown_op")
    required, optional = OP_KEYS[op]
    fields = {key: value for key, value in payload.items() if key != "op"}
    if not required <= set(fields) <= required | optional or not all(isinstance(v, str) for v in fields.values()):
        return refused(400, "malformed", "malformed", op)
    if code := _field_refusal(fields, config["store_dir"]):
        return refused(*code, op)
    if "directory" in fields:
        fields["directory"] = os.path.realpath(os.path.expanduser(fields["directory"]))  # the canonical directory
    return op, fields, None


def _queue_row(item, stage):
    request = item["request"]
    row = {"item": item["item"], "state": item["state"],
           "label": queue_label(request["directory"], request["repo"], request["branch"], request["worktree"]),
           "queuedAt": item["queuedAt"], "run": item["run"]}
    if item["state"] == "running" and stage is not None:
        row["stage"] = stage  # the runner's own record, so `total: None` while scanning stays present
    if item["state"] == "failed":
        row["error"] = item["error"]
    if item["state"] in ("failed", "interrupted"):
        row["detail"] = item["detail"]
    return row


def build_status(ledger, runner, store_dir):
    """Section 3.3's payload as a plain dict. The queue is returned even when the store cannot be read."""
    state = ledger.snapshot()
    stage = runner.progress()
    queue = [_queue_row(item, stage) for item in state["queue"]]
    try:
        runs = run_rows(store.read_store(Path(store_dir) / STORE_FILE)["runs"], state["hidden"])
        runs_error = None
    except store.StoreError:
        runs, runs_error = None, STORE_UNREADABLE
    return {"ok": True, "storeDir": _home_collapse(store_dir), "queue": queue, "runs": runs,
            "runsError": runs_error}


# ------------------------------------------------------------------------------ analyze and reanalyze (task 17)

def _scan_refusal(result):
    """The refusal `(status, error, reason)` for a finished scan, or None when it found work to queue."""
    error, _ = ledger_jobs._scan_error(result)
    if error is None:
        return None
    if error in SCAN_REFUSALS_422:
        return (422, error, error)
    if error in SCAN_REFUSALS_500:
        return (500, error, error)
    return (500, ledger_jobs.SCAN_FAILED, ledger_jobs.SCAN_FAILED)  # an outcome the spec does not name


def _submit(op, ledger, registry, scan_secs, request, program):
    """The scan, outside the ledger lock (5.6), then `enqueue`; the success body or a refusal tuple."""
    try:
        result = ledger_jobs.run_scan(registry, request, scan_secs, program=program)
    except ledger_jobs.RegistryClosed:
        return INTERNAL_ERROR
    except OSError:
        return LAUNCH_FAILED
    if refusal := _scan_refusal(result):
        return refusal
    try:
        item, started, code = enqueue(ledger, request)
    except LedgerWriteError:
        return LEDGER_WRITE_FAILED
    if code:
        return (ENQUEUE_REFUSAL_STATUS, code, code)
    return (200, {"ok": True, "op": op, "item": item, "started": started})


def accept_analysis(ledger, registry, scan_secs, request, *, program=None):
    """Spec 3.4 step 8 for `analyze`: `(200, body)` once the request is queued, else `(status, error, reason)`."""
    return _submit("analyze", ledger, registry, scan_secs, request, program)


def reanalyze_request(ledger, run):
    """The request recorded for `run` (5.1 `requests`), or None when there is none."""
    return ledger.snapshot()["requests"].get(run)


def _reanalyze(ledger, registry, scan_secs, run, program):
    request = reanalyze_request(ledger, run)
    if request is None:
        return OP_STUB_REFUSAL  # a run from before the Ledger is task 28's
    if not os.path.isdir(os.path.realpath(os.path.expanduser(request["directory"]))):
        return (422, "no_such_directory", "no_such_directory")  # the field rules run again (3.4), before the scan
    return _submit("reanalyze", ledger, registry, scan_secs, request, program)


def handle_op(op, fields, config):
    """What `server.py` answers for an accepted `/ledger` request: `(200, body)` or `(status, error, reason)`.

    The runner is woken once, after an item exists, and never after a refusal.
    """
    ledger, registry, scan_secs = config["ledger"], config["registry"], config["scan_secs"]
    program = config.get("scan_program")
    if op == "analyze":
        request = {name: fields.get(name, "") for name in TEXT_FIELDS}
        answer = accept_analysis(ledger, registry, scan_secs, request, program=program)
    elif op == "reanalyze":
        answer = _reanalyze(ledger, registry, scan_secs, fields["run"], program)
    else:
        return OP_STUB_REFUSAL  # remove, retry and delete: task 18
    if answer[0] == 200:
        config["runner"].wake()
    return answer
