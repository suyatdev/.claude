"""Tests for store.py — atomic emit of tracker-data.js and run upsert by id.

Covers acceptance criteria 3, 4 and 5, in §Acceptance criteria of
docs/features/tracking-feature-state.spec.md (the spec half):

  3. Two analyses of different directories both persist in runs[]; switching
     between them changes no data on disk.
  4. Re-analysis of an existing run id advances that run's analyzedAt and
     leaves every other run byte-identical.
  5. An interrupted write leaves the previous tracker-data.js valid JS.

Every test works on a tmp_path copy; the real task-tracker/tracker-data.js is
never touched.
"""

import json
import os
import shutil
import stat
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import store  # noqa: E402  (path shim above must run first)


NODE = shutil.which("node")

# The window the atomic write is meant to survive: the child has finished
# writing the temp file and is about to os.replace when it is SIGKILLed.
KILL_MARKER = "TMP_WRITTEN"


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------


def make_run(run_id, name=None, analyzed_at="2026-08-09T00:00:00Z", features=None):
    """A schema-shaped run object. Mirrors the envelope in tracker-data.json."""
    return {
        "id": run_id,
        "name": name or f"run {run_id}",
        "dir": f"~/dev/{run_id}",
        "analyzedAt": analyzed_at,
        "features": features if features is not None else [],
        "waves": [],
        "constraints": [],
        "branches": [],
        "graph": {"nodes": [], "edges": []},
        "kanban": [],
        "questions": [],
    }


def canonical(obj):
    """Order-insensitive byte image of one run, for byte-identity assertions."""
    return json.dumps(obj, sort_keys=True, ensure_ascii=True).encode("utf-8")


def load_via_node(path):
    """Execute the emitted file in a real JS engine and hand back the object.

    This is the honest reading of "still valid JS": the UI loads the file with
    <script src>, so the only proof that matters is that a JS engine accepts it
    and window.TRACKER_DATA comes out populated.
    """
    harness = textwrap.dedent(
        """
        const fs = require('fs');
        const vm = require('vm');
        const src = fs.readFileSync(process.argv[1], 'utf8');
        const sandbox = { window: {} };
        vm.createContext(sandbox);
        vm.runInContext(src, sandbox, { filename: 'tracker-data.js' });
        process.stdout.write(JSON.stringify(sandbox.window.TRACKER_DATA));
        """
    )
    proc = subprocess.run(
        [NODE, "-e", harness, "--", str(path)],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise AssertionError(f"node rejected {path}:\n{proc.stderr}")
    return json.loads(proc.stdout)


def run_child(script, tmp_path, wait_for=None):
    """Run a child python that dies mid-write. Returns the finished Popen."""
    script_path = tmp_path / "child.py"
    script_path.write_text(script)
    proc = subprocess.Popen(
        [sys.executable, str(script_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if wait_for is not None:
        for line in proc.stdout:
            if wait_for in line:
                break
        else:  # pragma: no cover - child died before reaching the marker
            proc.wait(timeout=10)
            raise AssertionError(
                f"child never reached {wait_for!r}; stderr:\n{proc.stderr.read()}"
            )
    proc.kill()
    proc.wait(timeout=10)
    return proc


@pytest.fixture
def store_path(tmp_path):
    return tmp_path / "tracker-data.js"


# --------------------------------------------------------------------------
# envelope / round-trip
# --------------------------------------------------------------------------


def test_emits_the_js_assignment_not_bare_json(store_path):
    store.emit_run(store_path, make_run("a"))
    text = store_path.read_text()

    assert text.startswith("window.TRACKER_DATA = ")
    assert text.endswith(";\n")


def test_preserves_the_top_level_envelope(store_path):
    store.emit_run(
        store_path,
        make_run("a"),
        repo_urls={".claude": "https://github.com/suyatdev/.claude"},
    )
    data = store.read_store(store_path)

    assert data["version"] == 1
    assert data["tool"] == "task-tracker v0.4.1"
    assert data["repoUrls"] == {".claude": "https://github.com/suyatdev/.claude"}
    assert "generatedAt" in data
    assert isinstance(data["runs"], list)


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_emitted_file_executes_in_a_real_js_engine(store_path):
    store.emit_run(store_path, make_run("a", name="first"))

    data = load_via_node(store_path)

    assert data["runs"][0]["name"] == "first"


def test_round_trips_through_the_js_envelope(store_path):
    original = make_run("a", features=[{"name": "card", "meta": "2/5", "tasks": []}])
    store.emit_run(store_path, original)

    reloaded = store.get_run(store.read_store(store_path), "a")

    assert reloaded == original


def test_rejects_a_run_without_a_usable_id(store_path):
    with pytest.raises(ValueError):
        store.emit_run(store_path, {"name": "no id"})


def test_rejects_a_corrupt_store_rather_than_silently_blanking_it(store_path):
    store_path.write_text("window.TRACKER_DATA = {truncated")

    with pytest.raises(store.StoreError):
        store.read_store(store_path)


# --------------------------------------------------------------------------
# criterion 3 — two runs persist; reading/switching mutates nothing
# --------------------------------------------------------------------------


def test_two_analyses_of_different_dirs_both_persist(store_path):
    store.emit_run(store_path, make_run("guard-memsearch"))
    store.emit_run(store_path, make_run("pane-orchestration-v2"))

    data = store.read_store(store_path)

    assert [r["id"] for r in data["runs"]] == [
        "guard-memsearch",
        "pane-orchestration-v2",
    ]


def test_adding_a_second_run_leaves_the_first_byte_identical(store_path):
    store.emit_run(store_path, make_run("first"))
    before = canonical(store.get_run(store.read_store(store_path), "first"))

    store.emit_run(store_path, make_run("second"))
    after = canonical(store.get_run(store.read_store(store_path), "first"))

    assert after == before


def test_switching_between_runs_writes_nothing_to_disk(store_path):
    store.emit_run(store_path, make_run("first"))
    store.emit_run(store_path, make_run("second"))
    before_bytes = store_path.read_bytes()
    before_mtime = store_path.stat().st_mtime_ns

    # "Switching" is a read plus a selection — the store must stay untouched.
    data = store.read_store(store_path)
    for _ in range(3):
        assert store.get_run(data, "first")["id"] == "first"
        assert store.get_run(data, "second")["id"] == "second"
        store.read_store(store_path)

    assert store_path.read_bytes() == before_bytes
    assert store_path.stat().st_mtime_ns == before_mtime


def test_get_run_returns_none_for_an_unknown_id(store_path):
    store.emit_run(store_path, make_run("first"))

    assert store.get_run(store.read_store(store_path), "nope") is None


def test_upsert_run_does_not_mutate_the_store_it_was_given(store_path):
    original = store.new_store()
    before = canonical(original)

    store.upsert_run(original, make_run("a"))

    assert canonical(original) == before


# --------------------------------------------------------------------------
# criterion 4 — re-analysis advances analyzedAt, others byte-identical
# --------------------------------------------------------------------------


def test_reanalysis_replaces_the_run_instead_of_appending_a_duplicate(store_path):
    store.emit_run(store_path, make_run("a", name="old name"))
    store.emit_run(store_path, make_run("a", name="new name"))

    runs = store.read_store(store_path)["runs"]

    assert [r["id"] for r in runs] == ["a"]
    assert runs[0]["name"] == "new name"


def test_reanalysis_keeps_the_run_in_its_original_position(store_path):
    for run_id in ("a", "b", "c"):
        store.emit_run(store_path, make_run(run_id))

    store.emit_run(store_path, make_run("b", name="reanalysed"))

    assert [r["id"] for r in store.read_store(store_path)["runs"]] == ["a", "b", "c"]


def test_reanalysis_advances_analyzed_at_for_that_run(store_path):
    store.emit_run(store_path, make_run("a", analyzed_at="2026-08-09T00:00:00Z"))
    store.emit_run(store_path, make_run("a", analyzed_at="2026-08-09T06:30:00Z"))

    assert store.get_run(store.read_store(store_path), "a")["analyzedAt"] == (
        "2026-08-09T06:30:00Z"
    )


def test_store_stamps_analyzed_at_when_the_caller_omits_it(store_path):
    run = make_run("a")
    del run["analyzedAt"]

    store.emit_run(store_path, run, now="2026-08-09T07:00:00Z")

    assert store.get_run(store.read_store(store_path), "a")["analyzedAt"] == (
        "2026-08-09T07:00:00Z"
    )


def test_reanalysis_leaves_every_other_run_byte_identical(store_path):
    for run_id in ("a", "b", "c"):
        store.emit_run(store_path, make_run(run_id, features=[{"name": run_id}]))
    before = {r["id"]: canonical(r) for r in store.read_store(store_path)["runs"]}

    store.emit_run(
        store_path, make_run("b", name="reanalysed", analyzed_at="2026-08-09T09:00:00Z")
    )
    runs = store.read_store(store_path)["runs"]
    after = {r["id"]: canonical(r) for r in runs}

    assert len(after) == len(runs), "re-analysis must not duplicate a run id"
    assert after["a"] == before["a"]
    assert after["c"] == before["c"]
    assert after["b"] != before["b"]


def test_rewriting_identical_input_reproduces_the_file_byte_for_byte(store_path):
    """The emitter must be deterministic, or 'byte-identical' cannot be checked."""
    run_a = make_run("a")
    run_b = make_run("b")
    store.emit_run(store_path, run_a, generated_at="2026-08-09T00:00:00Z")
    store.emit_run(store_path, run_b, generated_at="2026-08-09T00:00:00Z")
    first = store_path.read_bytes()

    store_path.unlink()
    store.emit_run(store_path, run_a, generated_at="2026-08-09T00:00:00Z")
    store.emit_run(store_path, run_b, generated_at="2026-08-09T00:00:00Z")

    assert store_path.read_bytes() == first


def test_envelope_generated_at_advances_on_write(store_path):
    store.emit_run(store_path, make_run("a"), generated_at="2026-08-09T00:00:00Z")
    store.emit_run(store_path, make_run("b"), generated_at="2026-08-09T05:00:00Z")

    assert store.read_store(store_path)["generatedAt"] == "2026-08-09T05:00:00Z"


def test_repo_urls_persist_when_a_later_write_omits_them(store_path):
    store.emit_run(store_path, make_run("a"), repo_urls={"x": "https://example/x"})

    store.emit_run(store_path, make_run("b"))

    assert store.read_store(store_path)["repoUrls"] == {"x": "https://example/x"}


# --------------------------------------------------------------------------
# criterion 5 — interrupted write leaves the previous file valid
# --------------------------------------------------------------------------


def test_replace_failure_leaves_the_previous_file_intact(store_path, monkeypatch):
    store.emit_run(store_path, make_run("a", name="survivor"))
    before = store_path.read_bytes()

    def boom(src, dst):
        raise OSError("simulated crash after the temp file was written")

    monkeypatch.setattr(store.os, "replace", boom)
    with pytest.raises(OSError):
        store.emit_run(store_path, make_run("b", name="never lands"))

    assert store_path.read_bytes() == before


def test_replace_failure_leaves_a_parseable_store(store_path, monkeypatch):
    store.emit_run(store_path, make_run("a", name="survivor"))

    monkeypatch.setattr(store.os, "replace", lambda src, dst: 1 / 0)
    with pytest.raises(ZeroDivisionError):
        store.emit_run(store_path, make_run("b"))

    survivor = store.read_store(store_path)
    assert store.get_run(survivor, "a")["name"] == "survivor"
    assert store.get_run(survivor, "b") is None, "the failed write must not land"


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_replace_failure_leaves_a_file_a_js_engine_still_accepts(
    store_path, monkeypatch
):
    store.emit_run(store_path, make_run("a", name="survivor"))

    monkeypatch.setattr(store.os, "replace", lambda src, dst: 1 / 0)
    with pytest.raises(ZeroDivisionError):
        store.emit_run(store_path, make_run("b"))

    assert load_via_node(store_path)["runs"][0]["name"] == "survivor"


def test_failed_write_does_not_leave_a_temp_file_behind(store_path, monkeypatch):
    store.emit_run(store_path, make_run("a"))

    monkeypatch.setattr(store.os, "replace", lambda src, dst: 1 / 0)
    with pytest.raises(ZeroDivisionError):
        store.emit_run(store_path, make_run("b"))

    assert list(store_path.parent.iterdir()) == [store_path]


def test_sigkill_between_temp_write_and_replace_leaves_the_store_intact(
    store_path, tmp_path
):
    """The real crash window: temp file complete, process dies before rename."""
    store.emit_run(store_path, make_run("a", name="survivor"))
    before = store_path.read_bytes()

    script = textwrap.dedent(
        f"""
        import os, sys, time
        sys.path.insert(0, {str(Path(store.__file__).parent)!r})
        import store

        def blocking_replace(src, dst):
            print({KILL_MARKER!r}, flush=True)
            time.sleep(300)          # SIGKILLed here, before the rename lands

        os.replace = blocking_replace
        store.emit_run({str(store_path)!r}, {make_run("b", name="never lands")!r})
        """
    )
    proc = run_child(script, tmp_path, wait_for=KILL_MARKER)

    assert proc.returncode == -9, "child should have been SIGKILLed"
    assert store_path.read_bytes() == before
    assert store.get_run(store.read_store(store_path), "a")["name"] == "survivor"


@pytest.mark.skipif(NODE is None, reason="node not installed")
def test_store_survives_sigkill_as_loadable_js(store_path, tmp_path):
    store.emit_run(store_path, make_run("a", name="survivor"))

    script = textwrap.dedent(
        f"""
        import os, sys, time
        sys.path.insert(0, {str(Path(store.__file__).parent)!r})
        import store

        def blocking_replace(src, dst):
            print({KILL_MARKER!r}, flush=True)
            time.sleep(300)

        os.replace = blocking_replace
        store.emit_run({str(store_path)!r}, {make_run("b")!r})
        """
    )
    run_child(script, tmp_path, wait_for=KILL_MARKER)

    data = load_via_node(store_path)
    assert [r["id"] for r in data["runs"]] == ["a"]


def test_sigkill_mid_stream_never_truncates_the_target(store_path, tmp_path):
    """A death *during* the content write can only damage the temp file.

    The child's write handle is wrapped so it commits half the bytes and then
    blocks forever, so the kill deterministically lands mid-stream. Sizing a
    payload to lose a race does not work — a 64MB write finishes in ~8ms.
    Both `open` and `os.fdopen` are wrapped, so a store that wrote straight to
    the target would be caught here rather than quietly skipping the wrapper.
    """
    store.emit_run(store_path, make_run("a", name="survivor"))
    before = store_path.read_bytes()

    script = textwrap.dedent(
        f"""
        import builtins, os, sys, time
        sys.path.insert(0, {str(Path(store.__file__).parent)!r})
        import store

        class HalfWrite:
            def __init__(self, inner):
                self._inner = inner

            def write(self, text):
                self._inner.write(text[: len(text) // 2])
                self._inner.flush()
                print({KILL_MARKER!r}, flush=True)
                time.sleep(300)      # SIGKILLed here, content half committed

            def __getattr__(self, name):
                return getattr(self._inner, name)

            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return self._inner.__exit__(*exc)

        def wrap(opener):
            def wrapped(*args, **kwargs):
                mode = kwargs.get("mode")
                if mode is None:
                    mode = args[1] if len(args) > 1 else "r"
                handle = opener(*args, **kwargs)
                return HalfWrite(handle) if "w" in str(mode) else handle
            return wrapped

        builtins.open = wrap(builtins.open)
        os.fdopen = wrap(os.fdopen)

        store.emit_run({str(store_path)!r}, {make_run("b")!r})
        """
    )
    proc = run_child(script, tmp_path, wait_for=KILL_MARKER)

    assert proc.returncode == -9, "child finished before it could be killed"
    assert store_path.read_bytes() == before
    assert store.get_run(store.read_store(store_path), "a")["name"] == "survivor"


def test_write_is_atomic_via_replace_in_the_same_directory(store_path, monkeypatch):
    """A cross-filesystem temp dir would make the rename non-atomic."""
    seen = {}

    real_replace = store.os.replace

    def spy(src, dst):
        seen["src"] = Path(src)
        seen["dst"] = Path(dst)
        return real_replace(src, dst)

    monkeypatch.setattr(store.os, "replace", spy)
    store.emit_run(store_path, make_run("a"))

    assert seen["src"].parent == store_path.parent
    assert seen["dst"] == store_path


def test_atomic_write_preserves_the_existing_file_mode(store_path):
    store.emit_run(store_path, make_run("a"))
    os.chmod(store_path, 0o644)

    store.emit_run(store_path, make_run("b"))

    assert stat.S_IMODE(store_path.stat().st_mode) == 0o644


def test_creates_the_store_when_none_exists(store_path):
    assert not store_path.exists()

    store.emit_run(store_path, make_run("a"))

    assert store.get_run(store.read_store(store_path), "a") is not None


def test_read_store_of_a_missing_file_returns_an_empty_envelope(store_path):
    data = store.read_store(store_path)

    assert data["runs"] == []
    assert data["version"] == 1
    assert not store_path.exists(), "reading must not create the file"
