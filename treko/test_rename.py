"""Tests for the Treko rename — acceptance criteria 5, 11 and 17.

`docs/features/treko-rename.md` §Acceptance criteria is authoritative; the values below
are transcribed from it rather than read back out of `server.py`, because a table derived
from the implementation asserts only that the implementation equals itself.

These are deliberately **unit** tests over `read_port`, `read_timeout` and the two
manifest constants, not process launches. Criterion 5's second half — that the retired
`TASK_TRACKER_PORT` is no longer honoured — cannot be proven by launching: a server that
ignores the override binds `DEFAULT_PORT` instead, and asserting on 8422 in a test would
collide with any real Treko already holding it on the developer's machine. `read_port`
takes an `environ` mapping, so the same claim is provable in microseconds with no port
at all.

**One test here is green before the change and is pinned, not driven** — see
`test_page_contains_no_nested_row_identifiers`. Task 1 of the card names it explicitly so
that a reader does not mistake a passing test for a test that was never red on purpose.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import channel  # noqa: E402  (D6 moved part of server.py here; the source guard below reads both)
import server  # noqa: E402  (path shim above must run first)
import server_harness as harness  # noqa: E402


# --------------------------------------------------------------------------
# criterion 5 — the four environment variables are renamed, and the old names
# are dead rather than silently honoured
# --------------------------------------------------------------------------

# Transcribed from §Scope: the rename map. `read_timeout` takes the spec tuple, so the
# name under test is the tuple's third element in each case.
TIMEOUT_SPEC_NAMES = {
    "IDLE_SECS": "TREKO_IDLE_SECS",
    "POLL_SECS": "TREKO_POLL_SECS",
    "ANALYZE_SECS": "TREKO_ANALYZE_SECS",
}

RETIRED_NAMES = (
    "TASK_TRACKER_PORT",
    "TASK_TRACKER_IDLE_SECS",
    "TASK_TRACKER_POLL_SECS",
    "TASK_TRACKER_ANALYZE_SECS",
)


def test_read_port_honours_treko_port():
    assert server.read_port({"TREKO_PORT": "9001"}) == 9001


def test_read_port_ignores_the_retired_port_name():
    """The old name is dead, not aliased.

    A fallback that still reads `TASK_TRACKER_PORT` is the invisible half-rename: every
    other test passes, and the stale name survives in the one layer nobody re-reads.
    """
    assert server.read_port({"TASK_TRACKER_PORT": "9001"}) == server.DEFAULT_PORT


@pytest.mark.parametrize("spec_name,env_name", sorted(TIMEOUT_SPEC_NAMES.items()))
def test_timeout_specs_name_treko_variables(spec_name, env_name):
    spec = getattr(server, spec_name)
    assert spec[2] == env_name


@pytest.mark.parametrize("spec_name,env_name", sorted(TIMEOUT_SPEC_NAMES.items()))
def test_timeout_specs_read_the_treko_variable(spec_name, env_name):
    spec = getattr(server, spec_name)
    floor = spec[1]
    assert server.read_timeout(spec, {env_name: str(floor)}) == floor


@pytest.mark.parametrize("retired", RETIRED_NAMES)
def test_no_retired_variable_name_survives_in_server_source(retired):
    """Asserted over the source, because a name can linger in a docstring or a comment.

    What this cannot see: a name assembled at runtime from fragments. Nothing in
    `server.py` does that today, and criterion 1's repo-wide grep is the backstop.
    """
    source = (Path(server.__file__)).read_text()
    assert retired not in source
    # D6 moved constants and `bind_surface` out of server.py; without this the guard would
    # stop seeing the code it moved.
    assert retired not in (Path(channel.__file__)).read_text()


# --------------------------------------------------------------------------
# criterion 11 — the Treko icon is servable, which needs a manifest row AND a
# content type, or the server refuses to start
# --------------------------------------------------------------------------

ICON = "treko-icon.png"


def test_icon_is_on_the_static_manifest():
    assert ICON in server.STATIC_MANIFEST


def test_png_has_a_content_type():
    assert server.EXTENSION_TYPES.get(".png") == "image/png"


def test_manifest_types_check_passes_with_the_icon_on_the_manifest():
    """`check_manifest_types` is the startup abort that couples the two above.

    Green today and pinned: it passes now because the manifest has no `.png` row at all.
    It exists to fail the moment a manifest row is added without its content type, which
    is the ordering mistake task 6 could actually make.
    """
    server.check_manifest_types()


def test_icon_file_exists_beside_the_page():
    assert (harness.REAL_TREE / ICON).is_file()


def test_get_icon_serves_image_png(srv):
    response = srv.get("/" + ICON)
    assert response.status == 200
    assert response.header("Content-Type") == "image/png"


# --------------------------------------------------------------------------
# criterion 17 — the ported page carries no markup its data cannot fill
# --------------------------------------------------------------------------

# The five bindings the prototype's nested feature -> story -> task rows read. Measured
# in the prototype 2026-08-21: f.rally x5, f.rallyId x1, f.rallyUrl x1, f.stories x4,
# st.tasks x2. Every one of them is absent from the producer side.
NESTED_ROW_IDENTIFIERS = ("f.rally", "f.rallyId", "f.rallyUrl", "f.stories", "st.tasks")


def test_page_contains_no_nested_row_identifiers():
    """Green before the change. A regression guard, not a driver.

    Verified 2026-08-21: all five are already absent from the served page. This exists to
    fail the moment task 6 ports more of the prototype's page than its branding.

    **What a pass here proves, and what it does not.** It catches the realistic failure —
    the rows copied across verbatim — and nothing else. It is a string match against five
    names the prototype uses today, so it cannot see the same feature re-implemented under
    different bindings, nor a hardcoded placeholder that reads no data at all. Do not cite
    a pass here as evidence of the broader claim.
    """
    page = (harness.REAL_TREE / server.INDEX_FILE).read_text()
    found = [name for name in NESTED_ROW_IDENTIFIERS if name in page]
    assert found == []


def test_producer_side_still_has_no_rally_or_story_fields():
    """The premise criterion 17 rests on, asserted rather than remembered.

    If the analyzer ever grows these fields, the nested rows stop being unportable and
    this guard should be revisited rather than silently kept.

    Beware when re-deriving by hand: a case-insensitive grep for `rally` over
    `analyze.py` returns one hit, and it is the word "lite**rally**".
    """
    analyzer = (harness.REAL_TREE / "analyze.py").read_text()
    for field in ('"rally"', '"rallyId"', '"rallyUrl"', '"stories"', '"story"'):
        assert field not in analyzer
