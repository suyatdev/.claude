"""What GET /ledger/status checks and answers (docs/features/treko-ledger.spec.md sections 3.1 and 3.3; D46).

Plain functions, no socket: `server.py` calls them and turns the result into a reply and an audit line. The
checks mirror `_handle_command`'s, and task 16 will fold the token half of both into one shared function (3.8).
An accepted poll writes no audit line (section 3.6: about 1,800 an hour would bury the state-changing ones); a
refused one writes exactly one, with id=status.
"""

import hmac
from pathlib import Path

import store
from ledger_state import queue_label, run_rows

STORE_FILE = "tracker-data.js"  # where runs live; server.py's FIRST_RUN_OPTIONAL names the same file
TOKEN_HEADER = "X-Tracker-Token"
STORE_UNREADABLE = "store_unreadable"


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
    presented = headers.get(TOKEN_HEADER, "")
    # hmac.compare_digest raises TypeError on a str that is not ASCII (U10), so refuse it before comparing.
    if not presented.isascii() or not hmac.compare_digest(presented, config["token"]):
        return "bad_token"
    return None


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
