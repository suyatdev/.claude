"""RED tests for card A task 6 — D5/D6/D7 "the drawer shell", criteria 12 and 14.

`docs/features/treko-theme-and-layout.md` §D5 (the drawer), §D6 (Esc goes first) and §D7 (the
gear grafts beside `cmdButtons`, never into it) govern, together with §Acceptance criteria 12
and 14. Written against the page as it stood at the commit this file was written against, where the drawer does not exist
at all: `settingsOpen`, `openSettings` and `closeSettings` each have **0 occurrences** in
`Treko.dc.html`, there is no gear button, and the `Escape` handler has exactly **three** arms
(`:477-481`). Every runtime test below was expected to fail, at the commit this file was
written against, until task 6 landed the gear, the scrim, the panel and the prepended Esc arm.

**What each test binds to, and why.**

*The drawer's identity is its rendered geometry, not a selector.* §D5 forbids a DOM `id`
anywhere in the drawer (criterion 14), and the page exposes no component handle to
`Runtime.evaluate` (established in `test_sidebar.py`'s docstring). So the scrim is located by
the one property §D5 gives it that nothing else on this page has: `position:fixed` covering the
whole viewport. `_probe_drawer` **counts** the matches and refuses to proceed unless the count
is exactly the expected one — the lesson `test_sidebar.py`'s "main column" bug taught, where a
first-match selector matched 13 elements, took the wrong one, and read as a different bug.
Every test asserts `count == 0` *before* opening, which is the probe's own control: it proves
the selector is not already matching some pre-existing element and quietly passing.

*Closing is proven by a bounded observation window with its own falsifier.*
`test_criterion12_panel_click_does_not_close_it` has to prove a negative — that a click inside
the panel changes nothing. A negative cannot be proven by polling until something happens, so
it watches for `NEGATIVE_WATCH_SECS` and asserts the drawer stayed open throughout. That alone
would pass against a page where *no* click ever closes the drawer, so the same test then clicks
the scrim and requires the close to be observed inside a window of the same length. The
falsifier is in the test, not in a comment.

**Amended at task 6's green half.** `test_esc_arm_parser_is_falsifiable` originally built its
mutations by editing the live page text. That worked only while the page had three Escape arms;
the moment task 6 prepended a fourth, duplicating the drawer arm produced five arms with
`settingsOpen` legitimately first, and the mutation stopped constructing the case it was written
to detect. It now builds every case from `BASE_ESC_ARMS` through `_chain_from_arms`, so it tests
the parser rather than drifting with the page under test — and it gained a satisfiability case,
because a check proven able to fail is not thereby proven able to pass.

*The Esc arms are compared as parsed (condition, body) pairs, not as raw text.* Criterion 12
says the three existing arms "keep their bodies and their relative order" while the new arm is
prepended. Prepending necessarily rewrites the second arm's leading keyword from `if` to
`else if` — that is chain glue, not a change to the arm. Comparing raw text would fail on that
rewrite and would therefore be testing the wrong thing; `_esc_arms` parses the chain and
compares what the criterion actually names.

**Not proven here, and owed elsewhere:**

- **Criterion 13** (the Layout readout is the live `S.sideW`) and **criterion 11's Reset
  clause** both need the drawer's Layout *section*, which is task 7, not task 6. They are
  recorded as owed in `test_sidebar.py`'s docstring and in the card; nothing here covers them.
- **Criterion 7's "Dark card selected" clause** needs the Appearance section — also task 7.
- That the drawer *looks* right in either theme. Task 9 eyeballs it and records it as
  eyeballed, never as measured.

Do not add implementation code here. Do not touch `Treko.dc.html`.
"""

import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cdp_harness  # noqa: E402
from test_theme import _wait_for_mount  # noqa: E402 -- reuse, not duplicate (rules/core-conduct.md DRY)

REPO_ROOT = Path(__file__).resolve().parent.parent
PAGE_PATH = REPO_ROOT / "treko" / "Treko.dc.html"
PAGE = PAGE_PATH.read_text()

# §D5: the gear's `title` is the drawer's only stable handle, since criterion 14 forbids an id.
GEAR_TITLE = "Settings"

# How long a test watches for a state change that must NOT happen. Paired in the same test with
# a change that MUST happen inside a window of this same length -- see the module docstring.
NEGATIVE_WATCH_SECS = 1.0
STATE_POLL_SECS = 0.05
STATE_SETTLE_TIMEOUT_SECS = 5

# The three Escape arms as they stand at the base commit `a5a66a75` -- read from
# `git show a5a66a75204f334fff09462e931981431b39081a:treko/Treko.dc.html`, not retyped from
# the card, and confirmed byte-identical at this HEAD. Criterion 12 requires these three to
# survive task 6 with their bodies and relative order intact, below a prepended fourth.
BASE_ESC_ARMS = [
    ("tag==='INPUT'&&document.activeElement===this._search",
     "this.setState({q:''});document.activeElement.blur();"),
    ("tag==='INPUT'",
     "document.activeElement.blur();"),
    ("this.state.agentOpen",
     "this.setState({agentOpen:false});"),
]


# ===========================================================================================
# JS probes. Each one COUNTS its matches before acting -- a first-match selector fails open.
# ===========================================================================================

# §D5's scrim is `position:fixed;inset:0`, so it is the only element on this page that is
# fixed AND covers the full viewport: the agent panel is `left:{{mainML}};right:0;bottom:0`
# (never full width) and the sidebar handle is `top:0;bottom:0;width:7px` (never full width).
# Verified by every test's own `count == 0` precondition before the drawer is opened.
_PROBE_DRAWER_JS = """
(() => {
  const vw = window.innerWidth, vh = window.innerHeight;
  const hits = [];
  document.querySelectorAll('body *').forEach(el => {
    if (getComputedStyle(el).position !== 'fixed') return;
    const r = el.getBoundingClientRect();
    if (Math.round(r.width) === vw && Math.round(r.height) === vh
        && Math.round(r.top) === 0 && Math.round(r.left) === 0) hits.push(el);
  });
  const out = {count: hits.length, viewportW: vw, viewportH: vh};
  if (hits.length !== 1) return out;
  const scrim = hits[0];
  const panel = scrim.firstElementChild;
  out.scrimZ = getComputedStyle(scrim).zIndex;
  out.panelCount = scrim.children.length;
  if (panel) {
    const p = panel.getBoundingClientRect();
    out.panel = {left: p.left, right: p.right, top: p.top, width: p.width, height: p.height};
    out.panelOverflowY = getComputedStyle(panel).overflowY;
  } else {
    out.panel = null;
  }
  return out;
})()
"""

_CLICK_GEAR_JS = """
(() => {
  const hits = document.querySelectorAll('[title=%s]');
  if (hits.length !== 1) return {count: hits.length};
  hits[0].dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));
  return {count: 1};
})()
""" % json.dumps(GEAR_TITLE)

# Dispatched with `bubbles: true` deliberately: a click inside the panel that does NOT bubble
# would pass criterion 12's "does not close" clause for the wrong reason. The event must reach
# the scrim's own listener and be stopped there by `stopEvt`, which is what §D5 specifies.
_CLICK_IN_DRAWER_JS = """
(() => {
  const vw = window.innerWidth, vh = window.innerHeight;
  const hits = [];
  document.querySelectorAll('body *').forEach(el => {
    if (getComputedStyle(el).position !== 'fixed') return;
    const r = el.getBoundingClientRect();
    if (Math.round(r.width) === vw && Math.round(r.height) === vh
        && Math.round(r.top) === 0 && Math.round(r.left) === 0) hits.push(el);
  });
  if (hits.length !== 1) return {count: hits.length};
  const scrim = hits[0];
  const target = %s ? scrim.firstElementChild : scrim;
  if (!target) return {count: 1, target: null};
  target.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));
  return {count: 1, target: 'ok'};
})()
"""

_ESCAPE_JS = (
    "window.dispatchEvent(new KeyboardEvent('keydown', "
    "{key: 'Escape', bubbles: true, cancelable: true})); true"
)

# React owns the input's value, so assigning `el.value` directly is swallowed by React's
# change tracker on the next render. The native setter + an `input` event is the sanctioned
# route: it is what a real keystroke produces, and it drives `onChange="{{ setQ }}"`.
_TYPE_IN_SEARCH_JS = """
(() => {
  const hits = document.querySelectorAll('input[placeholder^="Search tasks"]');
  if (hits.length !== 1) return {count: hits.length};
  const el = hits[0];
  const set = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
  set.call(el, %s);
  el.dispatchEvent(new Event('input', {bubbles: true}));
  el.focus();
  return {count: 1, value: el.value, focused: document.activeElement === el,
          tag: (document.activeElement || {}).tagName};
})()
"""

_READ_SEARCH_JS = """
(() => {
  const hits = document.querySelectorAll('input[placeholder^="Search tasks"]');
  if (hits.length !== 1) return {count: hits.length};
  return {count: 1, value: hits[0].value};
})()
"""


# ===========================================================================================
# Python helpers
# ===========================================================================================

def _probe(chrome):
    return chrome.evaluate(_PROBE_DRAWER_JS)


def _click_gear(chrome):
    return chrome.evaluate(_CLICK_GEAR_JS)


def _click_in_drawer(chrome, inside_panel):
    return chrome.evaluate(_CLICK_IN_DRAWER_JS % ("true" if inside_panel else "false"))


def _press_escape(chrome):
    chrome.evaluate(_ESCAPE_JS)


def _wait_for_drawer(chrome, want_open, timeout=STATE_SETTLE_TIMEOUT_SECS):
    """Poll until the drawer reaches `want_open`, then return the final probe.

    React batches `setState`, so the DOM read immediately after a dispatched click can still
    show the previous frame. This only waits -- it never loosens the assertion that follows.
    On timeout it raises with the last reading, so a drawer that opened to the wrong geometry
    still fails on geometry rather than being silently tolerated here.
    """
    deadline = time.time() + timeout
    probe = _probe(chrome)
    while time.time() < deadline:
        if (probe["count"] == 1) == want_open:
            return probe
        time.sleep(STATE_POLL_SECS)
        probe = _probe(chrome)
    raise AssertionError(
        "drawer never reached open=%r within %ss -- last probe was %r"
        % (want_open, timeout, probe))


def _watch_stays_open(chrome, seconds=NEGATIVE_WATCH_SECS):
    """Read the probe repeatedly for `seconds` and return the number of readings that showed
    the drawer open, alongside the total. Proving a negative needs a window, not a poll."""
    deadline = time.time() + seconds
    readings = 0
    open_readings = 0
    while time.time() < deadline:
        readings += 1
        if _probe(chrome)["count"] == 1:
            open_readings += 1
        time.sleep(STATE_POLL_SECS)
    return open_readings, readings


def _open_drawer(chrome):
    """Assert the closed precondition (the probe's own control), click the gear, wait."""
    before = _probe(chrome)
    assert before["count"] == 0, (
        "the full-viewport fixed-position probe matched %d element(s) BEFORE the drawer was "
        "opened -- the selector is matching something else and would pass for the wrong "
        "reason: %r" % (before["count"], before))
    clicked = _click_gear(chrome)
    assert clicked["count"] == 1, (
        "expected exactly one element with title=%r (the gear, §D7), found %d"
        % (GEAR_TITLE, clicked["count"]))
    return _wait_for_drawer(chrome, want_open=True)


# ===========================================================================================
# Criterion 12 — runtime behaviour
# ===========================================================================================

def test_criterion12_the_gear_opens_the_drawer(srv, tmp_path):
    """Criterion 12, clause 1: "the drawer opens on the gear". §D5's geometry is asserted
    with it, because "a full-viewport fixed element appeared" on its own would also be true
    of a scrim with no panel in it."""
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        chrome.navigate("http://127.0.0.1:%d/" % srv.port)
        _wait_for_mount(chrome)
        probe = _open_drawer(chrome)

        assert probe["panel"] is not None, "the scrim rendered with no panel inside it: %r" % probe
        panel = probe["panel"]
        # §D5: `justify-content:flex-end` -- the panel sits AT the right edge, not centred.
        assert round(panel["right"]) == probe["viewportW"], (
            "panel is not flush with the right edge: right=%r viewportW=%r"
            % (panel["right"], probe["viewportW"]))
        # §D5: `width:min(400px,92vw)`.
        expected_w = min(400, 0.92 * probe["viewportW"])
        assert abs(panel["width"] - expected_w) < 1.0, (
            "panel width %r does not match min(400px, 92vw) = %r"
            % (panel["width"], expected_w))
        # §D5: `height:100%`.
        assert round(panel["height"]) == probe["viewportH"], (
            "panel height %r is not the full viewport height %r"
            % (panel["height"], probe["viewportH"]))
        assert probe["panelOverflowY"] in ("auto", "scroll"), (
            "§D5 requires the panel to scroll its own overflow; overflow-y is %r"
            % probe["panelOverflowY"])
    finally:
        chrome.close()


def test_criterion12_the_scrim_closes_it(srv, tmp_path):
    """Criterion 12, clause 2: "closes on the scrim"."""
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        chrome.navigate("http://127.0.0.1:%d/" % srv.port)
        _wait_for_mount(chrome)
        _open_drawer(chrome)

        clicked = _click_in_drawer(chrome, inside_panel=False)
        assert clicked["count"] == 1, "lost the scrim between opening and clicking: %r" % clicked
        _wait_for_drawer(chrome, want_open=False)
    finally:
        chrome.close()


def test_criterion12_panel_click_does_not_close_it(srv, tmp_path):
    """Criterion 12, clause 3: "does not close on a click inside the panel" -- §D5's
    `onClick="{{ stopEvt }}"` on the panel.

    A negative, so it is watched for a window rather than polled for. The falsifier is the
    second half of this same test: after the watch, a scrim click must be observed to close
    the drawer within a window of the same length. If it were not, the watch above would be
    passing merely because nothing in this page ever closes the drawer.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        chrome.navigate("http://127.0.0.1:%d/" % srv.port)
        _wait_for_mount(chrome)
        _open_drawer(chrome)

        clicked = _click_in_drawer(chrome, inside_panel=True)
        assert clicked["count"] == 1, "lost the scrim before clicking the panel: %r" % clicked
        assert clicked.get("target") == "ok", "the scrim had no panel child to click: %r" % clicked

        open_readings, readings = _watch_stays_open(chrome)
        assert readings > 1, "the watch window took only %d reading(s)" % readings
        assert open_readings == readings, (
            "a click inside the panel closed the drawer: it was open in %d of %d readings "
            "across %.1fs" % (open_readings, readings, NEGATIVE_WATCH_SECS))

        # The falsifier: the same-length window MUST be enough to observe a real close.
        assert _click_in_drawer(chrome, inside_panel=False)["count"] == 1
        closed_open_readings, closed_readings = _watch_stays_open(chrome)
        assert closed_open_readings < closed_readings, (
            "a scrim click did not close the drawer within the same %.1fs window, so the "
            "watch above proves nothing: open in %d of %d readings"
            % (NEGATIVE_WATCH_SECS, closed_open_readings, closed_readings))
    finally:
        chrome.close()


def test_criterion12_escape_closes_it_and_leaves_the_search_text(srv, tmp_path):
    """Criterion 12, clause 4 + §D6's edge case: with the drawer open and the search box
    holding text and focus, Esc closes the drawer and the search text survives. That is only
    true if the new arm is FIRST -- with it appended, the `tag==='INPUT'` arm would win and
    clear the query instead."""
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        chrome.navigate("http://127.0.0.1:%d/" % srv.port)
        _wait_for_mount(chrome)
        _open_drawer(chrome)

        typed = chrome.evaluate(_TYPE_IN_SEARCH_JS % json.dumps("ordering"))
        assert typed["count"] == 1, (
            "expected exactly one search input, found %d" % typed["count"])
        assert typed["focused"] is True, "the search input did not take focus: %r" % typed
        assert typed["tag"] == "INPUT", (
            "document.activeElement is %r, so the handler's own `tag` guard would not see an "
            "INPUT and this test would not exercise §D6's edge case" % typed["tag"])

        _press_escape(chrome)
        _wait_for_drawer(chrome, want_open=False)

        after = chrome.evaluate(_READ_SEARCH_JS)
        assert after["count"] == 1, "lost the search input: %r" % after
        assert after["value"] == "ordering", (
            "Esc closed the drawer but also cleared the search box (value=%r) -- the new arm "
            "is not first in the chain" % after["value"])
    finally:
        chrome.close()


# ===========================================================================================
# Criterion 12 — the three existing Esc arms are undisturbed (a source assertion)
# ===========================================================================================

def _balanced(text, start, opener, closer):
    """Return the index just past the `closer` that balances the `opener` at `start`."""
    assert text[start] == opener, "expected %r at %d, found %r" % (opener, start, text[start])
    depth = 0
    i = start
    while i < len(text):
        if text[i] == opener:
            depth += 1
        elif text[i] == closer:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise AssertionError("unbalanced %r opened at %d" % (opener, start))


def _esc_arms(html_text):
    """Parse the `Escape` branch of `this._key` into an ordered list of (condition, body).

    Deliberately a parser, not a regex over the whole chain: criterion 12 is a claim about
    the arms' conditions, bodies and order, and prepending an arm necessarily rewrites the
    old first arm's leading keyword from `if` to `else if`. A raw-text comparison would fail
    on that keyword and would be testing the chain's punctuation instead of its arms.
    """
    marker = "else if(e.key==='Escape'){"
    occurrences = html_text.count(marker)
    assert occurrences == 1, (
        "expected exactly one `%s`, found %d" % (marker, occurrences))
    brace_at = html_text.index(marker) + len(marker) - 1
    block = html_text[brace_at + 1:_balanced(html_text, brace_at, "{", "}") - 1]

    arms = []
    i = 0
    while True:
        while i < len(block) and block[i] in " \t\r\n":
            i += 1
        if i >= len(block):
            break
        if block.startswith("else ", i):
            i += len("else ")
            while i < len(block) and block[i] in " \t\r\n":
                i += 1
        assert block.startswith("if(", i), (
            "unparsed text in the Escape chain at offset %d: %r" % (i, block[i:i + 60]))
        cond_start = i + len("if")
        cond_end = _balanced(block, cond_start, "(", ")")
        body_start = cond_end
        while body_start < len(block) and block[body_start] in " \t\r\n":
            body_start += 1
        body_end = _balanced(block, body_start, "{", "}")
        arms.append((block[cond_start + 1:cond_end - 1].strip(),
                     block[body_start + 1:body_end - 1].strip()))
        i = body_end
    return arms


def test_criterion12_the_esc_arm_is_prepended_and_the_others_are_undisturbed():
    """Criterion 12's second half, and §D6: exactly four arms, the drawer's is first, and the
    three that existed at the base commit follow in their original order with their original
    bodies."""
    arms = _esc_arms(PAGE)
    assert len(arms) == 4, (
        "expected 4 Escape arms after task 6 (the prepended drawer arm plus the 3 that "
        "already existed); found %d: %r" % (len(arms), [c for c, _ in arms]))

    first_cond, first_body = arms[0]
    assert "settingsOpen" in first_cond, (
        "the FIRST Escape arm does not test `settingsOpen` -- §D6 requires the drawer arm to "
        "be prepended, not appended. First arm condition: %r" % first_cond)
    assert "settingsOpen" in first_body, (
        "the first arm tests `settingsOpen` but does not close the drawer: %r" % first_body)

    assert arms[1:] == BASE_ESC_ARMS, (
        "the three pre-existing Escape arms changed. Expected (base commit a5a66a75):\n%s\n"
        "Found:\n%s" % (json.dumps(BASE_ESC_ARMS, indent=2), json.dumps(arms[1:], indent=2)))


def _chain_from_arms(arms):
    """Build an `Escape` chain from (condition, body) pairs -- the inverse of `_esc_arms`.

    The falsifier below needs a three-arm page to mutate, and this page no longer is one. It
    could hardcode the base commit's chain as a string, but a retyped copy is a second source
    of truth that drifts silently; building it from `BASE_ESC_ARMS` keeps exactly one. The
    round-trip assertion in `test_esc_arm_parser_is_falsifiable` is what ties the builder and
    the parser together, so a bug in either is reported rather than cancelling out.
    """
    lines = ["      else if(e.key==='Escape'){"]
    for index, (condition, body) in enumerate(arms):
        lines.append("        %s(%s){%s}"
                     % ("if" if index == 0 else "else if", condition, body))
    lines.append("      }")
    return "\n".join(lines) + "\n"


# The arm task 6 prepends, as `_esc_arms` reads it off the real page.
DRAWER_ESC_ARM = ("this.state.settingsOpen", "this.setState({settingsOpen:false});")


def test_esc_arm_parser_is_falsifiable():
    """The parser is the oracle for the test above, so it must be shown able to fail -- and,
    separately, able to pass. Both halves matter: a red suite proven able to fail is not
    proven able to pass.

    Every case is built from `BASE_ESC_ARMS` via `_chain_from_arms` rather than by mutating
    the live page. The first version of this test did mutate the live page, and it broke the
    moment task 6 landed: duplicating the drawer arm onto a page that already had one yielded
    five arms with `settingsOpen` legitimately first, so the mutation stopped constructing the
    case it was written to detect. A falsifier that drifts with the page under test is not a
    falsifier.
    """
    # Round trip first: if the builder and the parser disagree, nothing below means anything.
    assert _esc_arms(_chain_from_arms(BASE_ESC_ARMS)) == BASE_ESC_ARMS, (
        "builder/parser round trip failed on the three base arms")

    # SATISFIABLE: the shape criterion 12 asks for must actually pass the checks.
    good = _esc_arms(_chain_from_arms([DRAWER_ESC_ARM] + BASE_ESC_ARMS))
    assert len(good) == 4, "a correctly prepended chain parsed to %d arms, not 4" % len(good)
    assert "settingsOpen" in good[0][0], (
        "a correctly prepended chain did not read as prepended: first arm is %r" % good[0][0])
    assert good[1:] == BASE_ESC_ARMS, (
        "a correctly prepended chain was rejected -- the check is unsatisfiable, which would "
        "make the test above pass for no reason a correct page could satisfy")

    # FALSIFIABLE 1: appended, not prepended.
    appended = _esc_arms(_chain_from_arms(BASE_ESC_ARMS + [DRAWER_ESC_ARM]))
    assert len(appended) == 4, "the appended chain should still have four arms"
    assert "settingsOpen" not in appended[0][0], (
        "an APPENDED drawer arm was read as prepended -- the parser cannot tell them apart")
    assert appended[1:] != BASE_ESC_ARMS, (
        "an appended arm left the trailing three looking like the untouched base arms")

    # FALSIFIABLE 2: the first two existing arms swapped, below a correct prepend.
    swapped_order = [DRAWER_ESC_ARM, BASE_ESC_ARMS[1], BASE_ESC_ARMS[0], BASE_ESC_ARMS[2]]
    swapped = _esc_arms(_chain_from_arms(swapped_order))
    assert "settingsOpen" in swapped[0][0], "the prepend itself should still be intact here"
    assert swapped[1:] != BASE_ESC_ARMS, "swapping the first two existing arms was not detected"

    # FALSIFIABLE 3: an existing arm's body changed, order untouched.
    rebodied_arms = list(BASE_ESC_ARMS)
    rebodied_arms[-1] = (rebodied_arms[-1][0], "this.setState({agentOpen:true});")
    rebodied = _esc_arms(_chain_from_arms([DRAWER_ESC_ARM] + rebodied_arms))
    assert [c for c, _ in rebodied[1:]] == [c for c, _ in BASE_ESC_ARMS], (
        "this case is meant to change only a body, but a condition changed too")
    assert rebodied[1:] != BASE_ESC_ARMS, "changing an arm's body was not detected"

    # FALSIFIABLE 4: the drawer arm present but closing nothing.
    inert = _esc_arms(_chain_from_arms(
        [("this.state.settingsOpen", "this.setState({agentOpen:false});")] + BASE_ESC_ARMS))
    assert "settingsOpen" not in inert[0][1], (
        "an arm that tests settingsOpen but does not close the drawer was not detected")

# ===========================================================================================
# §D7 — the gear is a static button, never a `cmdButtons` row
# ===========================================================================================

_SC_FOR_RE = re.compile(r"<sc-for\b[^>]*>(.*?)</sc-for>", re.S)


def test_d7_the_gear_is_static_and_not_inside_any_sc_for():
    """§D7: adding a `'settings'` id to reach the command-button row would edit the fenced
    slice (criterion 15) and put a DOM concern inside it. The gear must be a static
    `<button>`, exactly like the Agent button that precedes it.

    Criterion 16 already guards `TRACKER_COMMAND_IDS` itself; this asserts the other half --
    that the gear's markup did not land inside a `<sc-for>` body.
    """
    gear_marker = 'onClick="{{ openSettings }}"'
    assert PAGE.count(gear_marker) == 1, (
        "expected exactly one gear button carrying %s, found %d"
        % (gear_marker, PAGE.count(gear_marker)))
    gear_at = PAGE.index(gear_marker)
    for match in _SC_FOR_RE.finditer(PAGE):
        assert not (match.start() <= gear_at < match.end()), (
            "the gear button is inside a <sc-for> body at offset %d -- §D7 requires it to be "
            "static, beside `cmdButtons` and never in it" % match.start())


# ===========================================================================================
# Criterion 14 — the drawer adds no DOM id
#
# This one PASSES by design: it is a regression guard, not a red test. At the commit this
# was written, the drawer did not exist yet, so the count was already 7. It was written then,
# with task 6's other tests, because the moment it could fail was the moment task 6's markup
# landed.
# ===========================================================================================

_ID_ATTR_RE = re.compile(r'\bid="([^"]*)"')


def test_criterion14_the_page_has_exactly_seven_ids_all_sec_anchors():
    """Criterion 14: "The drawer carries no `id` attribute. The page's `id="…"` count stays
    at 7, all `sec-*`." The seven are the scroll anchors `goTo` and the scroll spy read via
    `getElementById`; an eighth id for a drawer control would put a second, unrelated
    convention into that lookup (§D5)."""
    ids = _ID_ATTR_RE.findall(PAGE)
    assert len(ids) == 7, (
        "expected exactly 7 `id=\"…\"` attributes in Treko.dc.html, found %d: %r"
        % (len(ids), ids))
    assert sorted(ids) == sorted(set(ids)), "duplicate id attributes: %r" % ids
    non_sec = [i for i in ids if not i.startswith("sec-")]
    assert non_sec == [], (
        "criterion 14 requires every id to be a `sec-*` scroll anchor; found %r" % non_sec)


def test_criterion14_id_check_is_falsifiable():
    """The guard above passes at this commit whether or not it works, so show it can fail."""
    with_drawer_id = PAGE.replace(
        '<sc-if value="{{ agentOpen }}"',
        '<div id="settings-panel"></div><sc-if value="{{ agentOpen }}"', 1)
    assert with_drawer_id != PAGE, "the mutation matched nothing -- the fixture is stale"
    ids = _ID_ATTR_RE.findall(with_drawer_id)
    assert len(ids) == 8, "an added id was not counted: %r" % ids
    assert [i for i in ids if not i.startswith("sec-")] == ["settings-panel"], (
        "a non-`sec-` id was not reported: %r" % ids)
