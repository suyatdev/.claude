"""The writer half of SS Design D3 — which file `reanalyze` actually rewrites.

Split from `test_server.py` for two reasons. Size: that file is at this repo's 800-line
ceiling and the D3 section in it is already 116 lines. And the seam is real — every test
in that section is a `GET`, proving the *reader* serves the configured store. This is the
only place in the suite that watches the store being **written**.

**Why this needed writing at all.** `server_harness.server_env` points `TREKO_STORE_DIR`
at the per-test tree, so for almost every test here the store directory and the serving
root are the same directory and the distinction is invisible; the six tests that do
override it are all read-path. A writer still resolving `SERVE_ROOT / "tracker-data.js"`
would therefore leave the whole suite green while re-dirtying the repo this card exists to
stop dirtying. Only a launch whose store is a *different* directory, followed by something
that writes, can tell the two apart.

**The analyzer is stubbed.** What is under test is which path `run_reanalyze` hands to
`store.emit_run`, not what the analyzer finds. A stub makes the run id a sentinel, so the
assertion is "this exact run landed in this exact file" rather than the much weaker "the
bytes changed", and it keeps the test under a second instead of the ~100s the real
analyzer costs against this repo.

**What this file does not cover.** The other caller of `run_reanalyze` — `main()`'s
first-run analyze, which fires only under `--open` against an empty store — is not driven
here, because a `--open` launch opens a real browser. It is not a second place the path
could be wrong: it passes the same `config["store_path"]`, and `build_config` is the only
construction of it (D3). The test below covers that construction; what stays uncovered is
that call site's own arguments.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import store  # noqa: E402  (path shim above must run first)

# Emitted by the stub analyzer and asserted by id, so "the store was rewritten" is a claim
# about *this* run arriving rather than about a timestamp moving.
SENTINEL_RUN_ID = "SENTINEL-WRITER-RUN"

STUB_ANALYZER = '''#!/usr/bin/env python3
import json, sys
print(json.dumps({"id": "%s", "repo": sys.argv[1]}))
''' % SENTINEL_RUN_ID


def test_reanalyze_writes_the_configured_store_and_never_the_tree(launcher, tree, tmp_path):
    """Criterion 2's automatable half: surveying a repo must not touch the served tree.

    Both halves are asserted because either alone passes while the feature is broken. A
    writer pointed at the tree leaves the configured store without the sentinel run *and*
    changes the tree's bytes; a test asserting only the first would also fail for a
    reanalyze that failed outright, and one asserting only the second would pass for a
    server that wrote nowhere at all.
    """
    store_dir = tmp_path / "writer-store"
    store_dir.mkdir()
    store_path = store_dir / "tracker-data.js"
    # A store that already exists is what stops D4 adopting the tree's file into it — this
    # test is about the writer, not the one-time copy, and an empty envelope is a real one.
    store.write_store(store_path, store.new_store())
    (tree / "analyze.py").write_text(STUB_ANALYZER)
    tree_store = tree / "tracker-data.js"
    tree_before = tree_store.read_bytes()

    srv = launcher(tree=tree, overrides={"TREKO_STORE_DIR": str(store_dir)})
    response = srv.command("reanalyze", timeout=60)

    assert response.status == 200, \
        "reanalyze precondition failed: %s\n%s" % (response.body, srv.stderr)

    written = store.read_store(store_path)
    assert store.get_run(written, SENTINEL_RUN_ID) is not None, \
        "the configured store holds %r; the analyzer emitted %r" % (
            [run.get("id") for run in written["runs"]], SENTINEL_RUN_ID)

    assert tree_store.read_bytes() == tree_before, \
        "reanalyze rewrote %s — the store is configured at %s" % (tree_store, store_dir)
