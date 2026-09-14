"""RED tests for card A task 5 — D4 "Sidebar drag-resize", criteria 9, 10 and 11.

`docs/features/treko-theme-and-layout.md` §D4 and §Acceptance criteria (9, 10, 11) govern.
Written against the page as it stood at the commit this file was written against: the sidebar's expanded width is a
hardcoded inline-style literal (`Treko.dc.html:76`, `width:236px`), `mainML` is
`S.collapsed?'56px':'236px'` (`:650`, two fixed strings, never a stored or dragged number),
and there is no drag handle at all — `col-resize` has 0 occurrences in `Treko.dc.html`. None
of `sideHandleDown`, `SIDE_W_MIN`, `SIDE_W_MAX`, `SIDE_W_DEFAULT` or `resetSideW` exist yet.
Every test below was expected to fail, at the commit this file was written against, until
task 5 landed the handle, the validated seed and the three (four, with `resetSideW`) computed
substitutions §D4 specifies.

**One item criterion 11 asks for is deliberately NOT tested here — an owed item, not a
silently dropped one:**

`resetSideW` ships in task 5, per §D4's own text, as one of the computed substitutions
(`() => { lsSet('taskTracker.sideW', String(SIDE_W_DEFAULT)); this.setState({sideW:SIDE_W_DEFAULT}) }`).
But its only caller — the drawer's Layout section `btn-ghost` Reset button — is §D5, and the
drawer does not exist in `Treko.dc.html` at this commit (no `settingsOpen`, no gear button, no
drawer markup at all). Clicking a button that is not there would mean guessing a selector,
which `test_theme.py`'s module docstring already establishes as "indistinguishable from the
check being switched off." Nothing in this repo exposes the mounted component instance to
`Runtime.evaluate` either (checked: no `window.__DC*` handle, no React devtools hook usage in
`support.js`), so `resetSideW` cannot be invoked without a DOM element wired to it.
**Criterion 11's "Reset returns `SIDE_W_DEFAULT` (236), in both the DOM and
`taskTracker.sideW`" is therefore NOT proven by this file.** Whoever lands the drawer's Reset
button — task 7, per §D5 — owes that test there, the same way task 3 deferred the drawer's
"Dark card selected" check to task 7.

**The pre-data scenario ("mainML stays '0px' regardless of taskTracker.sideW") IS tested
below, but as a source-text assertion, not a runtime one — see
`test_criterion11_pre_data_return_still_yields_mainml_0px` for why: `mainML` is consumed only
by `Treko.dc.html:100` and `:301`, both inside `<sc-if value="{{ ready }}">`, and `ready` is
`false` whenever `!data` (`renderVals()`'s early return), so no DOM node ever carries the
value in this state — criterion 11's own final clause ("`Treko.dc.html:514`'s `mainML:'0px'`
is unchanged") is itself a claim about the source, not the render, which is exactly why a
source check is the faithful test here rather than a fallback.**

Do not add implementation code here. Do not touch `Treko.dc.html`.
"""

import json
import re
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cdp_harness  # noqa: E402
from test_theme import _wait_for_mount  # noqa: E402 -- reuse, not duplicate (rules/core-conduct.md DRY)

REPO_ROOT = Path(__file__).resolve().parent.parent
PAGE_PATH = REPO_ROOT / "treko" / "Treko.dc.html"
PAGE = PAGE_PATH.read_text()

# docs/features/treko-theme-and-layout.md §D4's three named module constants. Hardcoded here
# as the spec's own values, not read from Treko.dc.html -- these tests assert on rendered
# pixels and localStorage, never on the page's source text.
SIDE_W_MIN = 190
SIDE_W_MAX = 440
SIDE_W_DEFAULT = 236

SIDEW_KEY = "taskTracker.sideW"


# --------------------------------------------------------------------- page-side JS helpers


# No other element in this page sets `cursor:col-resize` (grepped: 0 occurrences before this
# task). Counting rather than boolean-testing lets "no handle while collapsed" and "exactly
# one handle while expanded" share the same probe.
_COUNT_HANDLES_JS = """
(() => {
  let count = 0;
  document.querySelectorAll('body *').forEach(el => {
    if (getComputedStyle(el).cursor === 'col-resize') count++;
  });
  return count;
})()
"""

# Finds the handle and dispatches a real `mousedown` on it -- the event §D4's `sideHandleDown`
# is wired to (`onMouseDown="{{ sideHandleDown }}"`). Returns false, never throws, when no
# handle exists, so the caller gets a clean diagnostic instead of a dispatchEvent-on-null crash.
_MOUSEDOWN_ON_HANDLE_JS = """
(() => {
  let handle = null;
  document.querySelectorAll('body *').forEach(el => {
    if (!handle && getComputedStyle(el).cursor === 'col-resize') handle = el;
  });
  if (!handle) return false;
  handle.dispatchEvent(new MouseEvent('mousedown', {clientX: %d, bubbles: true, cancelable: true}));
  return true;
})()
"""

# §D4: "addEventListener('mousemove',move); addEventListener('mouseup',up)" -- both on the
# global, never on the handle element, so these dispatch on `window`.
_MOUSEMOVE_JS = (
    "window.dispatchEvent(new MouseEvent('mousemove', "
    "{clientX: %d, bubbles: true, cancelable: true})); true"
)
_MOUSEUP_JS = (
    "window.dispatchEvent(new MouseEvent('mouseup', {bubbles: true, cancelable: true})); true"
)

# The sidebar/rail: `position:fixed;left:0;top:0;bottom:0` (Treko.dc.html:59 collapsed,
# :76 expanded -- only one renders at a time, sc-if on `expandedBar`).
#
# The main column: originally matched on "the one element whose live style attribute starts
# with margin-left:" -- but the sidebar's own collapse-toggle button
# (Treko.dc.html:80, `style="margin-left:auto;width:26px;..."`) ALSO starts with that exact
# substring and sits earlier in document order while the sidebar is expanded, so that probe
# silently matched the button instead and read its flex-auto margin (a real, but irrelevant,
# number that happens to shift when the sidebar's width changes the row's available space --
# this is what produced the impossible-looking readings during investigation: a value with no
# CSS transition at all that still moved between drags, and one that never moved at all
# post-mount because collapsing removes the button from the DOM entirely, leaving the real
# main column as the only remaining match). Fixed by requiring the second, distinguishing
# fact from the same anchor: only Treko.dc.html:100's div also declares
# `transition:margin-left .18s ease` -- the toggle button has no transition at all. Both
# checks read the live DOM (`getComputedStyle`, the live `style` attribute), never the file's
# source text.
_MEASURE_LAYOUT_JS = """
(() => {
  let sidebar = null, mainCol = null;
  document.querySelectorAll('body *').forEach(el => {
    const cs = getComputedStyle(el);
    if (!sidebar && cs.position === 'fixed' && parseFloat(cs.left) === 0
        && parseFloat(cs.top) === 0 && parseFloat(cs.bottom) === 0) sidebar = el;
    if (!mainCol) {
      const raw = el.getAttribute('style') || '';
      if (raw.indexOf('margin-left:') === 0 && cs.transitionProperty.indexOf('margin-left') !== -1) {
        mainCol = el;
      }
    }
  });
  return {
    sidebarWidth: sidebar ? Math.round(sidebar.getBoundingClientRect().width) : null,
    mainMarginLeft: mainCol ? getComputedStyle(mainCol).marginLeft : null,
  };
})()
"""

_CLICK_COLLAPSE_TOGGLE_JS = """
(() => {
  const btn = document.querySelector('[title="Collapse sidebar"]');
  if (!btn) return false;
  btn.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));
  return true;
})()
"""

# Wraps localStorage.setItem so the test can count writes to exactly one key -- other page
# behaviour (collapsing the rail writes 'taskTracker.sidebar', picking a run writes
# 'taskTracker.run', etc.) must not be miscounted as a sideW write.
_INSTRUMENT_SIDEW_WRITES_JS = """
(() => {
  window.__sideWWriteCount = 0;
  const original = localStorage.setItem.bind(localStorage);
  localStorage.setItem = function(key, value) {
    if (key === '%s') window.__sideWWriteCount++;
    return original(key, value);
  };
  return true;
})()
""" % SIDEW_KEY


def _handle_count(chrome):
    return chrome.evaluate(_COUNT_HANDLES_JS)


def _mousedown_on_handle(chrome, client_x):
    return chrome.evaluate(_MOUSEDOWN_ON_HANDLE_JS % client_x)


def _mousemove(chrome, client_x):
    chrome.evaluate(_MOUSEMOVE_JS % client_x)


def _mouseup(chrome):
    chrome.evaluate(_MOUSEUP_JS)


def _measure(chrome):
    return chrome.evaluate(_MEASURE_LAYOUT_JS)


# `Treko.dc.html:101`'s main column carries `transition:margin-left .18s ease`. A single
# post-action read of `mainMarginLeft` can land mid-animation: measured in a real build,
# clicking collapse produced '236px' at t=0ms (the pre-click value, read before the browser's
# next paint), '150.886px' at t=60ms, '76.863px' at t=120ms, and the settled '56px' from
# t=200ms onward; the same lag applies to the 0->236px transition on mount. The sidebar's own
# width has no transition and is unaffected -- only mainMarginLeft needs this wait.
MARGIN_SETTLE_TIMEOUT_SECS = 5
MARGIN_SETTLE_POLL_SECS = 0.05


def _measure_settled(chrome, timeout=MARGIN_SETTLE_TIMEOUT_SECS):
    """`_measure`, but polled until `mainMarginLeft` stops changing between two consecutive
    reads, so the caller asserts against the transition's settled target rather than a
    mid-animation sample.

    This only waits -- it does not loosen what gets asserted afterwards. The returned reading
    is whatever `mainMarginLeft` settles to; if the implementation drove that value to a wrong
    target, the settled reading is that wrong value, and a caller's exact-equality assertion
    against it still fails. This is a timing fix for a CSS transition (measured settle time
    ~200ms against the real page), never a tolerance on the expected number.
    """
    previous = None
    current = _measure(chrome)
    deadline = time.time() + timeout
    while time.time() < deadline:
        if current["mainMarginLeft"] == previous:
            return current
        previous = current["mainMarginLeft"]
        time.sleep(MARGIN_SETTLE_POLL_SECS)
        current = _measure(chrome)
    raise AssertionError(
        "mainMarginLeft never settled within %ss -- last two reads were %r then %r"
        % (timeout, previous, current["mainMarginLeft"])
    )


def _assert_handle_found(found, where):
    assert found, (
        "no element with cursor:col-resize exists in the DOM (%s) -- expected the drag "
        "handle (docs/features/treko-theme-and-layout.md §D4, 'Handle markup'): "
        "sideHandleDown, the handle's 7px position:fixed strip, and its onMouseDown wiring" % where
    )


def _seed_sidew_and_reload(chrome, url, value):
    """Mirrors test_theme._seed_theme_and_reload for the sidebar's own storage key: seed
    localStorage the way a real user's browser would, then reload so the page's own
    mount-time seed (§D4 'Seed, validated at mount') reads it. Never touches the DOM
    directly -- that would test the assertion instead of the code under it."""
    chrome.navigate(url)
    _wait_for_mount(chrome)
    chrome.evaluate("localStorage.setItem(%s, %s)" % (json.dumps(SIDEW_KEY), json.dumps(value)))
    assert chrome.evaluate("localStorage.getItem(%s)" % json.dumps(SIDEW_KEY)) == value
    chrome.reload()
    return _wait_for_mount(chrome)


# --------------------------------------------------------------------- scenario 1 + criterion 9


def test_dragging_resizes_sidebar_and_main_column(srv, tmp_path):
    """Gherkin "dragging resizes the sidebar" + criterion 9 (sidebar and mainML update
    together).

    Was RED when written. At that commit: no cursor:col-resize handle exists anywhere in the DOM (0
    occurrences of 'col-resize' in Treko.dc.html), so the drag can never start. Fails on the
    handle-found precondition, not on a wrong width.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        chrome.navigate(url)
        mount_count = _wait_for_mount(chrome)
        assert mount_count > 50, "board never mounted (%d body descendants)" % mount_count

        found = _mousedown_on_handle(chrome, SIDE_W_DEFAULT)
        _assert_handle_found(found, "before dragging to clientX 300")

        _mousemove(chrome, 300)
        layout = _measure_settled(chrome)
        _mouseup(chrome)

        assert layout["sidebarWidth"] == 300, (
            "after dragging to clientX 300, the sidebar's rendered width is %r, expected "
            "300px" % layout["sidebarWidth"]
        )
        assert layout["mainMarginLeft"] == "300px", (
            "after dragging to clientX 300, the main column's margin-left is %r, expected "
            "'300px' -- mainML must track the same drag in the same frame (criterion 9)"
            % layout["mainMarginLeft"]
        )
    finally:
        chrome.close()


# --------------------------------------------------------------------- scenario 2 + criterion 9


def test_drag_clamps_at_both_ends(srv, tmp_path):
    """Gherkin "the drag clamps at both ends" + criterion 9 ("clamps at 190 and 440").

    §D4's move handler: `Math.max(SIDE_W_MIN, Math.min(SIDE_W_MAX, ev.clientX))`. Dragging past
    either bound must clamp, not pass the raw clientX through.

    Was RED when written. At that commit: same reason as the plain-drag test -- no col-resize handle
    exists, so the drag never starts.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        chrome.navigate(url)
        _wait_for_mount(chrome)

        found = _mousedown_on_handle(chrome, SIDE_W_DEFAULT)
        _assert_handle_found(found, "before dragging to clientX 40")

        _mousemove(chrome, 40)
        low = _measure(chrome)
        assert low["sidebarWidth"] == SIDE_W_MIN, (
            "dragging to clientX 40 produced sidebar width %r, expected the clamped floor "
            "%dpx (SIDE_W_MIN)" % (low["sidebarWidth"], SIDE_W_MIN)
        )

        _mousemove(chrome, 900)
        high = _measure(chrome)
        _mouseup(chrome)
        assert high["sidebarWidth"] == SIDE_W_MAX, (
            "dragging on to clientX 900 produced sidebar width %r, expected the clamped "
            "ceiling %dpx (SIDE_W_MAX)" % (high["sidebarWidth"], SIDE_W_MAX)
        )
    finally:
        chrome.close()


# --------------------------------------------------------------------- scenario 3 + criterion 10


def test_width_persisted_once_on_mouseup_not_per_mousemove(srv, tmp_path):
    """Gherkin "the width is written once, not per frame" + criterion 10.

    §D4: "Persist on mouseup, never per frame. A drag fires mousemove at frame rate; a
    lsSet per frame is a synchronous localStorage write per frame." This counts writes to
    exactly `taskTracker.sideW` (not the sidebar-collapse or other keys the page also writes)
    across 60 simulated mousemove events, asserting zero until mouseup and exactly one after.

    Was RED when written. At that commit: no col-resize handle exists, so the drag never starts and the
    write-count precondition never gets exercised.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        chrome.navigate(url)
        _wait_for_mount(chrome)
        chrome.evaluate(_INSTRUMENT_SIDEW_WRITES_JS)

        found = _mousedown_on_handle(chrome, SIDE_W_DEFAULT)
        _assert_handle_found(found, "before a 60-mousemove drag")

        for i in range(60):
            _mousemove(chrome, 236 + i)

        mid_count = chrome.evaluate("window.__sideWWriteCount")
        assert mid_count == 0, (
            "%d write(s) to localStorage['%s'] happened during 60 mousemove events, before "
            "mouseup -- the width must be persisted only once, on release" % (mid_count, SIDEW_KEY)
        )

        _mouseup(chrome)
        final_count = chrome.evaluate("window.__sideWWriteCount")
        assert final_count == 1, (
            "%d write(s) to localStorage['%s'] happened after mouseup, expected exactly 1"
            % (final_count, SIDEW_KEY)
        )
    finally:
        chrome.close()


# --------------------------------------------------------------------- scenario 4 + criterion 9


def test_width_survives_a_reload(srv, tmp_path):
    """Gherkin "the width survives a reload" + criterion 9 ("survives a reload").

    Was RED when written. At that commit: mainML is `S.collapsed?'56px':'236px'` (Treko.dc.html:650), two
    fixed literals -- nothing reads or writes `taskTracker.sideW`, so a drag to 300px cannot
    outlive the drag itself even if it could happen. Fails after the reload, not before: the
    drag+release sequence itself is the same missing-handle failure the other tests hit, so
    this test seeds localStorage directly (the same technique test_theme.py uses for theme
    persistence) to isolate the reload half specifically.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        _seed_sidew_and_reload(chrome, url, "300")

        layout = _measure(chrome)
        assert layout["sidebarWidth"] == 300, (
            "with taskTracker.sideW='300' stored before a reload, the sidebar renders at "
            "%r, expected 300px -- the mount-time seed did not read taskTracker.sideW"
            % layout["sidebarWidth"]
        )
    finally:
        chrome.close()


# --------------------------------------------------------------------- scenario 6 + criterion 11


def test_corrupt_stored_width_yields_default_not_a_hardcoded_coincidence(srv, tmp_path):
    """Gherkin "a corrupt stored width" + criterion 11 ("a non-numeric stored value also
    yields SIDE_W_DEFAULT").

    SIDE_W_DEFAULT (236) is, by §D4's own design, the same number already hardcoded as the
    sidebar's literal width (Treko.dc.html:76). So `taskTracker.sideW='banana'` rendering at
    236px today is **not evidence the seed exists** -- the literal renders 236px regardless
    of what is in storage, corrupt or not. Asserting only that would pass vacuously both
    before and after this task lands, which docs/features/treko-theme-and-layout.md's own
    reasoning for --mono (criterion 4) and this task's brief both warn against.

    This test therefore also seeds a *valid, distinguishable* value ('300') in the same run:
    a hardcoded-236 implementation passes the corrupt case but fails this second half, which
    was the part actually expected RED when this was written (same reason as
    test_width_survives_a_reload).
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        corrupt_mount = _seed_sidew_and_reload(chrome, url, "banana")
        assert corrupt_mount > 50, (
            "board never mounted with taskTracker.sideW='banana' (%d body descendants) -- a "
            "corrupt stored value must not be able to stop the page rendering" % corrupt_mount
        )
        corrupt_layout = _measure(chrome)
        assert corrupt_layout["sidebarWidth"] == SIDE_W_DEFAULT, (
            "taskTracker.sideW='banana' rendered sidebar width %r, expected the default %dpx"
            % (corrupt_layout["sidebarWidth"], SIDE_W_DEFAULT)
        )

        # The proof this isn't the hardcoded-236 literal in disguise: a valid, non-default
        # stored value must be honoured. Was RED here when written.
        _seed_sidew_and_reload(chrome, url, "300")
        valid_layout = _measure(chrome)
        assert valid_layout["sidebarWidth"] == 300, (
            "taskTracker.sideW='300' rendered sidebar width %r, expected 300px -- if this "
            "assertion is the one that failed, the 236px result above was the page's "
            "existing hardcoded literal (Treko.dc.html:76), not a validated seed; the "
            "mount-time seed did not read taskTracker.sideW" % valid_layout["sidebarWidth"]
        )
    finally:
        chrome.close()


# --------------------------------------------------------------- scenario 7 + criterion 11


@pytest.mark.parametrize("stored,expected", [("0", SIDE_W_MIN), ("99999", SIDE_W_MAX)])
def test_out_of_range_stored_width_clamped_at_mount(srv, tmp_path, stored, expected):
    """Gherkin "a stored width outside the clamp range is corrected at mount" + criterion 11
    ("a numeric stored value outside SIDE_W_MIN-SIDE_W_MAX is clamped to the nearer bound at
    mount, not only during a drag").

    Was RED when written. At that commit: the sidebar's width is the hardcoded literal 236px regardless of
    localStorage, so a stored '0' or '99999' renders 236px, not the clamped bound (190 or
    440) -- both parametrised cases differ from today's rendered value, so unlike the
    corrupt-value scenario above this needs no extra proof against a hardcoded coincidence.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        mount_count = _seed_sidew_and_reload(chrome, url, stored)
        assert mount_count > 50, (
            "board never mounted with taskTracker.sideW=%r (%d body descendants)"
            % (stored, mount_count)
        )
        layout = _measure(chrome)
        assert layout["sidebarWidth"] == expected, (
            "taskTracker.sideW=%r rendered sidebar width %r, expected the mount-time clamp "
            "to %dpx -- the seed was not clamped to that range"
            % (stored, layout["sidebarWidth"], expected)
        )
    finally:
        chrome.close()


# --------------------------------------------------------------------- scenario 8


def test_no_handle_while_collapsed(srv, tmp_path):
    """Gherkin "no handle while collapsed".

    §D4: the handle "lives inside <sc-if value='{{ expandedBar }}'>, so it does not exist
    while the sidebar is collapsed." Proving that requires first proving a handle exists
    while *expanded* -- otherwise "no handle while collapsed" is true today for the wrong
    reason (no handle exists in either state). That first assertion is this test's real RED
    trigger; the collapsed-state checks after it are expected to already hold (the collapsed
    rail is unconditionally 56px, Treko.dc.html:59, and toggleSidebar already works) and are
    included as the regression guard the scenario also asks for.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        chrome.navigate(url)
        _wait_for_mount(chrome)

        expanded_layout = _measure(chrome)
        assert expanded_layout["sidebarWidth"] and expanded_layout["sidebarWidth"] > 100, (
            "sidebar is not expanded by default (width %r) -- precondition for this test "
            "failed before it could check the handle" % expanded_layout["sidebarWidth"]
        )

        expanded_handles = _handle_count(chrome)
        assert expanded_handles == 1, (
            "expected exactly 1 cursor:col-resize element while the sidebar is expanded, "
            "found %d -- the drag handle (§D4 'Handle markup') does not match that count"
            % expanded_handles
        )

        toggled = chrome.evaluate(_CLICK_COLLAPSE_TOGGLE_JS)
        assert toggled, "could not find [title=\"Collapse sidebar\"] to click"

        deadline = time.time() + 5
        collapsed_layout = _measure(chrome)
        while collapsed_layout["sidebarWidth"] != 56 and time.time() < deadline:
            time.sleep(0.05)
            collapsed_layout = _measure(chrome)

        # sidebarWidth has no CSS transition and is already settled above; mainMarginLeft
        # does (Treko.dc.html:101, transition:margin-left .18s ease) and needs its own wait.
        collapsed_layout = _measure_settled(chrome)

        assert collapsed_layout["sidebarWidth"] == 56, (
            "after collapsing, the rail's width is %r, expected 56px"
            % collapsed_layout["sidebarWidth"]
        )
        assert collapsed_layout["mainMarginLeft"] == "56px", (
            "after collapsing, the main column's margin-left is %r, expected '56px'"
            % collapsed_layout["mainMarginLeft"]
        )
        assert _handle_count(chrome) == 0, (
            "a cursor:col-resize element exists while the sidebar is collapsed -- the handle "
            "must live only inside <sc-if value='{{ expandedBar }}'>"
        )
    finally:
        chrome.close()


# --------------------------------------------------------------- criterion 11, pre-data clause


# Anchored on the `if(!data)return {ready:false,` text, not a line number: the base commit has
# this at :514, this branch has it at :543 today, and it will move again once tasks 6-7 land
# and add more markup above it. `[^}]*` is safe only because this object literal is flat (no
# nested `{...}`) -- true of the real file today, checked by eye above.
PRE_DATA_RETURN_RE = re.compile(r"if\(!data\)return\s*\{ready:false,([^}]*)\}")


def _pre_data_return_block(html_text):
    """The pre-data early return's object-literal body (everything between `ready:false,` and
    the closing `}`), or None if the anchor text isn't found at all."""
    match = PRE_DATA_RETURN_RE.search(html_text)
    return match.group(1) if match else None


def _pre_data_mainml_is_0px(html_text):
    """True iff `renderVals()`'s pre-data early return still yields `mainML:'0px'`.

    A source-text check, not a runtime one -- see
    test_criterion11_pre_data_return_still_yields_mainml_0px's docstring for why the value has
    no independent DOM signal to read instead.
    """
    block = _pre_data_return_block(html_text)
    if block is None:
        return False
    return re.search(r"mainML\s*:\s*'0px'", block) is not None


def test_pre_data_mainml_check_is_falsifiable():
    """Confirms `_pre_data_mainml_is_0px` can actually fail before trusting the real check
    below (`rules/core-conduct.md` "Confirm the check can fail" -- a checker that returns True
    regardless of input would make that test meaningless, since it is expected to PASS today).

    Feeds the extractor synthetic text -- never the real `Treko.dc.html` -- covering the three
    ways a future edit could break this invariant: a wrong hardcoded literal, a version that
    reads `sideW` before data has loaded, and the clause deleted outright. All three, plus a
    positive control on the untouched real text, are run here and reported, not predicted.
    """
    real = "if(!data)return {ready:false,loading:!S.missing,missing:S.missing,mainML:'0px'};"
    assert _pre_data_mainml_is_0px(real) is True, (
        "control failed: the checker rejected the real, unmodified early-return text"
    )

    wrong_literal = real.replace("mainML:'0px'", "mainML:'236px'")
    assert _pre_data_mainml_is_0px(wrong_literal) is False, (
        "checker did not reject mainML:'236px' -- it cannot detect a wrong hardcoded literal"
    )

    reactive = real.replace("mainML:'0px'", "mainML:S.sideW+'px'")
    assert _pre_data_mainml_is_0px(reactive) is False, (
        "checker did not reject mainML:S.sideW+'px' -- it cannot detect the clause reading "
        "sideW before data has loaded"
    )

    deleted = real.replace(",mainML:'0px'", "")
    assert _pre_data_mainml_is_0px(deleted) is False, (
        "checker did not reject a return object with the mainML clause deleted entirely"
    )


def test_criterion11_pre_data_return_still_yields_mainml_0px():
    """docs/features/treko-theme-and-layout.md criterion 11's final clause: "and
    `Treko.dc.html:514`'s `mainML:'0px'` is unchanged" -- itself a claim about the source, not
    the render: §D4 says "there is no sidebar to be flush against before the data arrives."

    This is a SOURCE-TEXT check, not a runtime one, and deliberately so. Tracing the markup:
    `mainML` is consumed only at `Treko.dc.html:100` and `:301`, and both live inside
    `<sc-if value="{{ ready }}">` (`:56`); `renderVals()` returns `ready:false` whenever
    `!data`. So in exactly the state this clause describes ("tracker-data has not loaded"),
    the only elements that would ever render `mainML` do not render at all -- there is no DOM
    node in that state for a CDP-driven test to read the value from. That is not a reason to
    skip the check; it is why the criterion itself is phrased as a source claim.

    What this test does NOT prove: that the pre-data branch *renders* correctly (the loading
    or missing placeholder actually appearing, with no crash) -- no test in this file drives a
    genuine data-never-arrives page through headless Chrome to confirm that. It proves only
    that the early return's source still assigns the literal `'0px'`.

    Expected to PASS today -- this is a regression guard for something task 5 must not touch,
    not new behaviour task 5 introduces. `test_pre_data_mainml_check_is_falsifiable` (above)
    is what proves this isn't vacuous: the same extractor rejects three plausible ways this
    clause could be broken.
    """
    block = _pre_data_return_block(PAGE)
    assert block is not None, (
        "the 'if(!data)return {ready:false,...}' early return is no longer present in "
        "Treko.dc.html in the expected shape -- criterion 1's regression-guard anchor text "
        "itself has changed, not just mainML within it"
    )
    assert _pre_data_mainml_is_0px(PAGE), (
        "renderVals()'s pre-data early return no longer yields mainML:'0px' -- got %r. "
        "criterion 11 requires this literal to survive task 5 unchanged, since there is no "
        "sidebar to be flush against before data arrives (§D4)" % block
    )
