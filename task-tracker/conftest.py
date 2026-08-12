"""Fixtures shared by test_server.py and test_server_lifetime.py.

They live here rather than in either file because pytest only auto-discovers fixtures
from a conftest, and both files need the same launcher. The machinery itself is in
`server_harness.py`; this module is only the pytest wiring.

`test_analyze.py` and `test_store.py` use none of these — a conftest offers fixtures, it
does not impose them.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import server_harness as harness  # noqa: E402


@pytest.fixture
def tree(tmp_path):
    """A private copy of `task-tracker/`; the real tree is never touched."""
    return harness.build_tree(tmp_path)


@pytest.fixture
def srv(tmp_path, tree):
    """A running server on the happy path: the surface binds and `cmux tree` resolves."""
    server_proc = harness.launch(tmp_path, tree=tree)
    yield server_proc
    server_proc.stop()


@pytest.fixture
def launcher(tmp_path):
    """Launch servers with per-test overrides; every one is stopped at teardown."""
    started = []

    def _launch(**kwargs):
        srv = harness.launch(tmp_path, **kwargs)
        started.append(srv)
        return srv

    yield _launch
    for srv in started:
        srv.stop()
