"""The `Ledger` object (docs/features/treko-ledger.spec.md, sections 5.1 and 5.6 "One lock"), in
`ledger_state.py`. Nothing outside holds a reference to its state: `snapshot`, the value `update`
returns and the constructor's input are copies, and `update` gives its change a private copy and
stores a copy of what it returns. Edits reach nested lists and dicts, so a shallow copy fails.

Run:  see section 15 of the spec (the pinned `uv run ... pytest` command).
"""

import sys
import threading
import time
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from ledger_state import Ledger  # noqa: E402  — path shim above must run first

EMPTY = {"version": 1, "queue": [], "hidden": [], "requests": {}}
THREADS, INCREMENTS = 8, 200
WAIT = 5  # seconds a helper thread may take before a test calls it stuck


def populated():
    request = {"directory": "/Users/x/dev", "repo": "memsearch"}
    return {"version": 1, "queue": [{"item": "a", "state": "waiting", "request": request}],
            "hidden": ["r1"], "requests": {"r1": dict(request)}}


def scribble(state):
    """Edit every level of a state in place, as a holder of a live reference would."""
    state["version"] = 99
    state["queue"][0]["request"]["repo"] = "scribbled"
    state["queue"].append({"item": "late"})
    state["requests"]["r1"]["repo"] = "scribbled"
    return state


def test_a_new_ledger_snapshot_is_exactly_the_empty_state():
    assert Ledger().snapshot() == EMPTY


def test_the_constructor_keeps_no_reference_to_the_dict_it_was_given():
    given = populated()
    ledger = Ledger(given)
    assert ledger.snapshot() == populated()
    scribble(given)
    assert ledger.snapshot() == populated()


def test_mutating_a_snapshot_does_not_change_the_ledger():
    ledger = Ledger(populated())
    first, second = ledger.snapshot(), ledger.snapshot()
    scribble(first)
    assert ledger.snapshot() == populated() == second


def test_a_change_that_mutates_its_argument_and_raises_leaves_the_ledger_unchanged():
    ledger = Ledger(populated())

    def change(state):
        scribble(state)
        raise RuntimeError("the change failed half way")

    with pytest.raises(RuntimeError):
        ledger.update(change)
    seen = []  # read on a thread, so a lock the change leaked fails the test instead of hanging it
    probe = threading.Thread(target=lambda: seen.append(ledger.snapshot()), daemon=True)
    probe.start()
    probe.join(WAIT)
    assert not probe.is_alive(), "the lock is still held after the change raised"
    assert seen == [populated()]


def test_a_change_that_returns_a_state_replaces_the_state():
    ledger = Ledger(populated())
    replacement = {"version": 1, "queue": [], "hidden": ["r2"], "requests": {}}
    assert ledger.update(lambda state: replacement) == replacement
    assert ledger.snapshot() == replacement


def test_the_value_update_returns_is_a_copy():
    ledger = Ledger(populated())
    returned = ledger.update(lambda state: state)
    assert returned == populated()
    scribble(returned)
    assert ledger.snapshot() == populated()


def test_a_change_that_keeps_what_it_touched_cannot_edit_the_ledger_later():
    for returns_its_argument in (True, False):
        ledger, kept = Ledger(populated()), []

        def change(state):
            kept.extend([state, state if returns_its_argument else populated()])
            return kept[-1]

        ledger.update(change)
        for held in kept:
            scribble(held)
        assert ledger.snapshot() == populated(), returns_its_argument


def test_the_lock_serialises_updates():
    ledger = Ledger(dict(EMPTY, counter=0))
    start = threading.Barrier(THREADS)

    def bump(state):
        seen = state["counter"]
        time.sleep(0.0001)  # holds the read-modify-write open until another thread cuts in
        state["counter"] = seen + 1
        return state

    def work():
        start.wait()
        for _ in range(INCREMENTS):
            ledger.update(bump)

    threads = [threading.Thread(target=work, daemon=True) for _ in range(THREADS)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(WAIT * 6)
    assert ledger.snapshot()["counter"] == THREADS * INCREMENTS


def test_a_snapshot_waits_for_an_update_in_progress():
    ledger = Ledger()
    inside, release, seen = threading.Event(), threading.Event(), []

    def slow(state):
        inside.set()
        release.wait(WAIT)
        state["hidden"].append("r1")
        return state

    updater = threading.Thread(target=ledger.update, args=(slow,), daemon=True)
    updater.start()
    assert inside.wait(WAIT)
    reader = threading.Thread(target=lambda: seen.append(ledger.snapshot()), daemon=True)
    reader.start()
    reader.join(0.2)
    still_waiting = reader.is_alive()
    release.set()
    updater.join(WAIT)
    reader.join(WAIT)
    assert still_waiting, "snapshot returned while an update held the lock"
    assert seen == [dict(EMPTY, hidden=["r1"])]
