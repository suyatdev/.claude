"""RED tests for card A task 7 — §D5's two drawer sections, criteria 7, 11, 13 and 2.

`docs/features/treko-theme-and-layout.md` §D5 ("Appearance" `:428-444`, "Layout" `:448-452`),
§D2 (the preview cards keep their literals) and §D9 (there is no Artifacts section) govern,
together with acceptance criteria 7, 11, 13 and 2. Task 6 landed the drawer *shell* — gear,
scrim, panel, header — and nothing inside it. Every runtime test here is expected to fail
until task 7 lands the two sections.

**A separate file from `test_drawer.py`, deliberately.** `test_drawer.py` is 594 lines at this
commit; task 7's tests are ~350 more, which would put it past `rules/core-conduct.md`'s 800-line
ceiling. The shell and its sections are also separable subjects: nothing here reads task 6's
probes except `_open_drawer`, which is imported rather than copied.

**What each test binds to, and why.**

*The preview cards are located by their glyphs, then by computed border, never by a selector.*
Criterion 14 forbids an `id` anywhere in the drawer, and §D5 gives the two cards no class of
their own. The two Phosphor glyphs `ph-moon` and `ph-sun` are unique on this page (measured:
0 occurrences before task 7), so each is a one-of-a-kind anchor; the card itself is then the
nearest ancestor that actually paints a border, which is a rendered fact rather than a guess
about markup depth. Every probe **counts** its matches and refuses to proceed unless the count
is exactly one — `test_sidebar.py`'s "main column" bug is what that rule is for.

*Selection is asserted against the page's own resolved tokens, not against hardcoded rgb.*
§D5's six ternaries name `var(--color-accent)`, `var(--color-accent-900)`,
`var(--color-accent-300)`, `var(--color-neutral-700)` and `transparent`. The probe resolves
each of those five through a throwaway element in the live document and compares the cards'
computed values against the results, so a palette re-tint (task 4 already did one) cannot turn
these tests red for a reason that has nothing to do with selection.

*"The Dark card is selected, not neither" needs a control that selection can move.* A test
that only ever checks the corrupt-input case would pass against an implementation that hardwires
the Dark card as selected forever. The parametrization therefore includes a stored `'light'`,
which must select the *other* card; both cases share one assertion helper, so neither can be
weakened without the other noticing.

*The Layout readout is proven live by changing the state while the drawer stays open.* Reading
"317px" after seeding 317 shows the readout is not a hardcoded 236 — it does not show the
readout is not a copy taken when the drawer opened. Pressing Reset with the drawer still open
and requiring the readout to follow is what separates those two, and it is criterion 13's whole
claim ("not a second stored copy").

**Not proven here, and owed elsewhere:**

- That the sections *look* right in either theme, and that the drawer's own contents pass
  criterion 5's contrast check when it is open — criterion 5 measures the page at mount, where
  the drawer is closed. Task 9 eyeballs the drawer and records it as eyeballed, never measured.
- §D9's "no Artifacts section" is asserted here only as the absence of the prototype's
  `saveArtPath` / `artifactsPath` names. It cannot prove nobody adds an unrelated third section.

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
from test_theme import _wait_for_mount, _seed_theme_and_reload  # noqa: E402 -- reuse, not duplicate
from test_sidebar import (  # noqa: E402 -- reuse, not duplicate (rules/core-conduct.md DRY)
    SIDE_W_DEFAULT,
    SIDEW_KEY,
    _measure_settled,
    _seed_sidew_and_reload,
)
from test_drawer import _open_drawer, _probe  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
PAGE_PATH = REPO_ROOT / "treko" / "Treko.dc.html"
PAGE = PAGE_PATH.read_text()

THEME_KEY = "taskTracker.theme"

# Two widths that are both inside §D4's 190-440 clamp and neither of which is SIDE_W_DEFAULT.
# A readout hardcoded to "236px" -- the failure criterion 13 exists to catch -- fails both.
LIVE_WIDTHS = ["317", "205"]


# ===========================================================================================
# JS probes. Each one COUNTS its matches before reading -- a first-match selector fails open.
# ===========================================================================================

# Resolves the five values §D5's ternaries name, through a real element in the live document,
# so the comparison is against whatever the current palette makes them rather than against a
# colour typed into this file. `transparent` is included because §D5's unselected `*Bg` is
# literally that, and it computes to `rgba(0, 0, 0, 0)` rather than to the keyword.
#
# The cards: `ph-moon` and `ph-sun` are each unique on this page, and the card is the nearest
# ancestor of the glyph that paints a border -- §D5 gives the card `border:1px solid {{ *Edge }}`
# and gives no border to the label div between them. The panel's own `border-left` is not a
# match: `borderTopWidth` is 0 on a left-only border.
_APPEARANCE_PROBE_JS = """
(() => {
  const resolve = value => {
    const probe = document.createElement('span');
    probe.style.display = 'none';
    probe.style.color = value;
    document.body.appendChild(probe);
    const out = getComputedStyle(probe).color;
    probe.remove();
    return out;
  };
  const tokens = {
    accent: resolve('var(--color-accent)'),
    accent900: resolve('var(--color-accent-900)'),
    accent300: resolve('var(--color-accent-300)'),
    neutral700: resolve('var(--color-neutral-700)'),
    neutral400: resolve('var(--color-neutral-400)'),
    transparent: resolve('transparent'),
  };
  const read = glyph => {
    const hits = document.querySelectorAll('i.' + glyph);
    if (hits.length !== 1) return {count: hits.length};
    const icon = hits[0];
    const label = icon.parentElement;
    let card = label;
    while (card && parseFloat(getComputedStyle(card).borderTopWidth) === 0) card = card.parentElement;
    if (!card) return {count: 1, card: null};
    const cs = getComputedStyle(card);
    return {
      count: 1,
      border: cs.borderTopColor,
      background: cs.backgroundColor,
      labelColor: label ? getComputedStyle(label).color : null,
      text: (label ? label.textContent : '').trim(),
      cursor: cs.cursor,
    };
  };
  return {
    tokens: tokens,
    dark: read('ph-moon'),
    light: read('ph-sun'),
    dataTheme: document.body.getAttribute('data-theme'),
  };
})()
"""

# Clicks a preview card by its glyph. Bubbling is on purpose: the click must reach the panel's
# `stopEvt` and be stopped there, exactly as a real user's click would be -- a non-bubbling
# dispatch would leave the drawer's close-on-scrim path untested in the same motion.
_CLICK_CARD_JS = """
(() => {
  const hits = document.querySelectorAll('i.__GLYPH__');
  if (hits.length !== 1) return {count: hits.length};
  let card = hits[0].parentElement;
  while (card && parseFloat(getComputedStyle(card).borderTopWidth) === 0) card = card.parentElement;
  if (!card) return {count: 1, card: null};
  card.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));
  return {count: 1, card: 'ok'};
})()
"""

# The Layout readout, §D5: "a read-only `{{ sideW }}` readout". `sideW` renders as `<n>px`, so
# the readout is the one element inside the drawer panel whose OWN text (not a descendant's)
# begins with a pixel count. Scoped to the panel so the sidebar's own inline width -- which is
# the same number, from the same state -- cannot be picked up instead and pass vacuously.
_LAYOUT_PROBE_JS = """
(() => {
  const vw = window.innerWidth, vh = window.innerHeight;
  const scrims = [];
  document.querySelectorAll('body *').forEach(el => {
    if (getComputedStyle(el).position !== 'fixed') return;
    const r = el.getBoundingClientRect();
    if (Math.round(r.width) === vw && Math.round(r.height) === vh
        && Math.round(r.top) === 0 && Math.round(r.left) === 0) scrims.push(el);
  });
  if (scrims.length !== 1) return {scrimCount: scrims.length};
  const panel = scrims[0].firstElementChild;
  if (!panel) return {scrimCount: 1, panel: null};
  const ownText = el => Array.from(el.childNodes)
    .filter(n => n.nodeType === 3).map(n => n.textContent).join('');
  const readouts = [];
  panel.querySelectorAll('*').forEach(el => {
    const m = ownText(el).trim().match(/^(\\d+)px\\b/);
    if (m) readouts.push({value: m[1], text: ownText(el).trim()});
  });
  const buttons = [];
  panel.querySelectorAll('button').forEach(el => {
    if (el.textContent.trim().toLowerCase() === 'reset') {
      buttons.push({classes: el.className, text: el.textContent.trim()});
    }
  });
  return {scrimCount: 1, readoutCount: readouts.length, readouts: readouts,
          resetCount: buttons.length, resets: buttons};
})()
"""

_CLICK_RESET_JS = """
(() => {
  const vw = window.innerWidth, vh = window.innerHeight;
  const scrims = [];
  document.querySelectorAll('body *').forEach(el => {
    if (getComputedStyle(el).position !== 'fixed') return;
    const r = el.getBoundingClientRect();
    if (Math.round(r.width) === vw && Math.round(r.height) === vh
        && Math.round(r.top) === 0 && Math.round(r.left) === 0) scrims.push(el);
  });
  if (scrims.length !== 1) return {count: -1};
  const panel = scrims[0].firstElementChild;
  if (!panel) return {count: -1};
  const hits = [];
  panel.querySelectorAll('button').forEach(el => {
    if (el.textContent.trim().toLowerCase() === 'reset') hits.push(el);
  });
  if (hits.length !== 1) return {count: hits.length};
  hits[0].dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));
  return {count: 1};
})()
"""


# ===========================================================================================
# Python helpers
# ===========================================================================================

def _appearance(chrome):
    return chrome.evaluate(_APPEARANCE_PROBE_JS)


def _click_card(chrome, glyph):
    return chrome.evaluate(_CLICK_CARD_JS.replace("__GLYPH__", glyph))


def _layout(chrome):
    return chrome.evaluate(_LAYOUT_PROBE_JS)


def _click_reset(chrome):
    return chrome.evaluate(_CLICK_RESET_JS)


def _assert_cards_found(probe):
    """Both glyph anchors resolved to exactly one card each -- the precondition every
    appearance assertion depends on, reported as a missing section rather than as a colour
    mismatch when task 7 has not landed."""
    for name, glyph in (("dark", "ph-moon"), ("light", "ph-sun")):
        card = probe[name]
        assert card["count"] == 1, (
            "expected exactly one `i.%s` glyph in the open drawer (§D5's %s preview card), "
            "found %d -- the Appearance section does not exist yet (task 7): %r"
            % (glyph, name, card["count"], probe))
        assert card.get("card") is not None, (
            "the %s glyph has no bordered ancestor, so §D5's `border:1px solid {{ %sEdge }}` "
            "card is not there: %r" % (name, name, probe))


def _assert_selection(probe, expected):
    """Assert exactly the six values §D5's ternaries produce for `S.theme == expected`.

    Written as one helper used by every case so the corrupt-input case and the control case
    cannot drift apart: an implementation that hardwires Dark as selected fails the `'light'`
    case here, on the same three assertions that pass for the `'dark'` case.
    """
    tokens = probe["tokens"]
    other = "light" if expected == "dark" else "dark"
    chosen, unchosen = probe[expected], probe[other]

    assert chosen["border"] == tokens["accent"], (
        "the %s card is not marked selected: its border is %r, §D5 requires "
        "var(--color-accent) = %r" % (expected, chosen["border"], tokens["accent"]))
    assert chosen["background"] == tokens["accent900"], (
        "the %s card's background is %r, §D5 requires var(--color-accent-900) = %r"
        % (expected, chosen["background"], tokens["accent900"]))
    assert chosen["labelColor"] == tokens["accent300"], (
        "the %s card's label colour is %r, §D5 requires var(--color-accent-300) = %r"
        % (expected, chosen["labelColor"], tokens["accent300"]))

    assert unchosen["border"] == tokens["neutral700"], (
        "the %s card is ALSO marked selected (border %r) -- exactly one card is selected at a "
        "time; §D5 requires the unselected card's border to be var(--color-neutral-700) = %r"
        % (other, unchosen["border"], tokens["neutral700"]))
    assert unchosen["background"] == tokens["transparent"], (
        "the %s card's background is %r, §D5 requires `transparent` = %r"
        % (other, unchosen["background"], tokens["transparent"]))
    assert unchosen["labelColor"] == tokens["neutral400"], (
        "the %s card's label colour is %r, §D5 requires var(--color-neutral-400) = %r"
        % (other, unchosen["labelColor"], tokens["neutral400"]))


def _readout_value(probe, where):
    assert probe.get("scrimCount") == 1, (
        "the drawer was not open when the Layout section was read (%s): %r" % (where, probe))
    assert probe.get("readoutCount") == 1, (
        "expected exactly one `<n>px` readout inside the drawer panel (§D5's Layout section, "
        "%s), found %r -- the Layout section does not exist yet (task 7): %r"
        % (where, probe.get("readoutCount"), probe))
    return probe["readouts"][0]["value"]


# ===========================================================================================
# Criterion 7 — the Appearance section's selection state
# ===========================================================================================

# `'banana'`, `'Dark'` and `'light '` are the same corrupt-input shapes `test_theme.py` already
# pins for the `data-theme` half of criterion 7 (a case variant and a trailing space are corrupt
# input, not near-misses to coerce). `'light'` is the control that proves selection can move at
# all; `'dark'` is the ordinary case. Every corrupt value must select DARK, never neither.
@pytest.mark.parametrize("stored,expected", [
    ("light", "light"),
    ("dark", "dark"),
    ("banana", "dark"),
    ("Dark", "dark"),
    ("light ", "dark"),
    ("", "dark"),
])
def test_criterion7_appearance_selection_follows_the_validated_theme(srv, tmp_path, stored, expected):
    """Criterion 7's third clause: a stored value outside `{'dark','light'}` yields dark mode
    "in the applied `data-theme` attribute **and in the drawer's Appearance selection state,
    where it leaves the Dark card selected rather than neither card**".

    §D5 explains why that holds by construction once the section exists: §D3 validates the seed
    against the closed set, so `S.theme` is always exactly one of two strings and exactly one
    ternary arm can fire. This test is what makes that an asserted fact rather than a claim.

    Expected RED right now: the Appearance section does not exist, so neither glyph is found.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        _seed_theme_and_reload(chrome, url, stored)
        _open_drawer(chrome)

        probe = _appearance(chrome)
        # A precondition, not the subject: test_theme.py owns the `data-theme` half. If this
        # fails, the seed regressed and the selection assertions below would be meaningless.
        assert probe["dataTheme"] == expected, (
            "precondition failed -- with taskTracker.theme=%r the page applied data-theme=%r, "
            "expected %r (test_theme.py owns this half of criterion 7)"
            % (stored, probe["dataTheme"], expected))

        _assert_cards_found(probe)
        _assert_selection(probe, expected)
    finally:
        chrome.close()


def test_appearance_cards_switch_the_theme_both_ways(srv, tmp_path):
    """§D5: "two clickable preview cards side by side, `setDark` / `setLight`". Both
    directions are exercised in one test on purpose -- a one-way test passes against a page
    where the Light card is wired and the Dark card is inert.

    `setTheme` (`Treko.dc.html:517`) writes `taskTracker.theme`, applies the attribute and
    sets state, so all three are asserted: a card that only re-tinted the DOM would leave a
    reload back on the old theme.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        chrome.navigate("http://127.0.0.1:%d/" % srv.port)
        _wait_for_mount(chrome)
        _open_drawer(chrome)

        before = _appearance(chrome)
        _assert_cards_found(before)
        assert before["dataTheme"] == "dark", (
            "precondition failed -- an unseeded page must mount dark (§D3), got %r"
            % before["dataTheme"])

        clicked = _click_card(chrome, "ph-sun")
        assert clicked["count"] == 1, "could not click the Light preview card: %r" % clicked
        after_light = _appearance(chrome)
        assert after_light["dataTheme"] == "light", (
            "clicking the Light card did not apply data-theme=\"light\": %r" % after_light)
        assert chrome.evaluate("localStorage.getItem(%s)" % json.dumps(THEME_KEY)) == "light", (
            "clicking the Light card did not persist taskTracker.theme -- `setLight` is not "
            "wired to setTheme (§D5), so the choice would not survive a reload")
        _assert_selection(after_light, "light")

        clicked = _click_card(chrome, "ph-moon")
        assert clicked["count"] == 1, "could not click the Dark preview card: %r" % clicked
        after_dark = _appearance(chrome)
        assert after_dark["dataTheme"] == "dark", (
            "clicking the Dark card did not apply data-theme=\"dark\": %r" % after_dark)
        assert chrome.evaluate("localStorage.getItem(%s)" % json.dumps(THEME_KEY)) == "dark", (
            "clicking the Dark card did not persist taskTracker.theme")
        _assert_selection(after_dark, "dark")

        # §D5: the panel carries `stopEvt`, so clicking a card must not close the drawer.
        assert _probe(chrome)["count"] == 1, (
            "picking a theme closed the drawer -- the card's click reached the scrim's "
            "close handler instead of being stopped by the panel's `stopEvt` (§D5)")
    finally:
        chrome.close()


# ===========================================================================================
# Criterion 13 — the Layout readout is the live S.sideW
# ===========================================================================================

@pytest.mark.parametrize("stored", LIVE_WIDTHS)
def test_criterion13_layout_readout_reads_the_stored_width(srv, tmp_path, stored):
    """Criterion 13 + the Gherkin "the Layout readout is the real width". Two distinguishable
    widths, neither of them 236: a readout hardcoded to the default fails both, which is the
    failure this criterion names ("not a second stored copy").

    Expected RED right now: the Layout section does not exist, so no `<n>px` readout is
    inside the panel at all.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        _seed_sidew_and_reload(chrome, url, stored)
        _open_drawer(chrome)

        value = _readout_value(_layout(chrome), "after seeding %r" % stored)
        assert value == stored, (
            "the Layout readout shows %rpx with taskTracker.sideW=%r -- criterion 13 requires "
            "it to be the live S.sideW" % (value, stored))
    finally:
        chrome.close()


def test_criterion13_readout_follows_state_without_reopening(srv, tmp_path):
    """Criterion 13's real claim: "there is exactly one source for the number on screen".

    Seeding a width and reading it back cannot tell a live binding from a copy taken when the
    drawer opened -- both show 317. Changing `S.sideW` while the drawer stays open can: a copy
    keeps showing the old number. Reset is the only in-drawer control that moves the width, so
    it is what drives the change here; criterion 11's own assertions live in the next test.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        _seed_sidew_and_reload(chrome, url, "317")
        _open_drawer(chrome)

        assert _readout_value(_layout(chrome), "before Reset") == "317", (
            "precondition failed -- the readout did not start at the seeded 317px")

        clicked = _click_reset(chrome)
        assert clicked["count"] == 1, (
            "expected exactly one Reset button inside the drawer panel (§D5's Layout section), "
            "found %d -- the Layout section does not exist yet (task 7)" % clicked["count"])

        deadline = time.time() + 5
        value = _readout_value(_layout(chrome), "after Reset")
        while value != str(SIDE_W_DEFAULT) and time.time() < deadline:
            time.sleep(0.05)
            value = _readout_value(_layout(chrome), "after Reset")
        assert value == str(SIDE_W_DEFAULT), (
            "the readout still shows %rpx after Reset set S.sideW to %d -- it is a copy taken "
            "when the drawer opened, not the live state criterion 13 requires"
            % (value, SIDE_W_DEFAULT))

        assert _probe(chrome)["count"] == 1, (
            "pressing Reset closed the drawer -- the button's click was not stopped by the "
            "panel's `stopEvt` (§D5)")
    finally:
        chrome.close()


# ===========================================================================================
# Criterion 11 — the Reset clause, owed since task 5
# ===========================================================================================

def test_criterion11_reset_returns_the_default_in_the_dom_and_in_storage(srv, tmp_path):
    """Criterion 11, clause 1 + the Gherkin "Reset returns 236". `resetSideW` shipped in task 5
    per §D4 and had **no caller** until this section existed; `test_sidebar.py` records the
    clause as owed by name. This is its first and only caller.

    Both halves are asserted because `resetSideW` does two things (§D4): `lsSet` and
    `setState`. An implementation that only re-rendered would pass a DOM-only check and lose
    the reset on the next reload.

    The 300px precondition is the falsifier: without it, a page whose sidebar never left 236
    would pass every assertion below.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        _seed_sidew_and_reload(chrome, url, "300")

        before = _measure_settled(chrome)
        assert before["sidebarWidth"] == 300, (
            "precondition failed -- the seeded 300px did not reach the sidebar (%r), so a "
            "later reading of 236px would not prove Reset did anything" % before)

        _open_drawer(chrome)
        clicked = _click_reset(chrome)
        assert clicked["count"] == 1, (
            "expected exactly one Reset button inside the drawer panel (§D5's Layout section), "
            "found %d -- the Layout section does not exist yet (task 7)" % clicked["count"])

        after = _measure_settled(chrome)
        assert after["sidebarWidth"] == SIDE_W_DEFAULT, (
            "Reset left the sidebar at %rpx, criterion 11 requires SIDE_W_DEFAULT (%d)"
            % (after["sidebarWidth"], SIDE_W_DEFAULT))
        assert after["mainMarginLeft"] == "%dpx" % SIDE_W_DEFAULT, (
            "Reset moved the sidebar but not the main column (margin-left %r) -- criterion 9's "
            "same-frame pairing must survive Reset too" % after["mainMarginLeft"])

        stored = chrome.evaluate("localStorage.getItem(%s)" % json.dumps(SIDEW_KEY))
        assert stored == str(SIDE_W_DEFAULT), (
            "Reset left localStorage[%r] = %r, criterion 11 requires %r -- the width would "
            "come back at 300px on the next reload"
            % (SIDEW_KEY, stored, str(SIDE_W_DEFAULT)))
    finally:
        chrome.close()


# ===========================================================================================
# Criterion 2 — the preview cards are the ONLY exempt literals
#
# Task 7 is the commit that can make criterion 2 false: until now every occurrence of the two
# dark literals is on the `:root` line (measured at this commit: 8 occurrences, all on one
# line). §D2 requires the two preview cards to keep theirs -- "each card is a miniature of the
# OTHER theme, so it must not follow the active one" -- and to "say so in a comment". This is
# a source check, so it names the marker the implementation must carry.
# ===========================================================================================

DARK_LITERALS = ("#12131e", "rgba(255,255,255,")
EXEMPT_OPEN = "criterion-2-exempt:start"
EXEMPT_CLOSE = "criterion-2-exempt:end"
_ROOT_DECL_RE = re.compile(r"^\s*:root\{", re.M)
_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)


def _criterion2_violations(html_text):
    """Return a list of human-readable reasons `html_text` fails criterion 2, empty if it passes.

    A pure function over text so the falsifier below can feed it built fixtures rather than
    mutating the live page -- the drift that broke task 6's first falsifier (`50e9a32`).
    """
    problems = []

    # Criterion 2 exempts "the eight `:root` declarations". This page carries TWO `:root{`
    # rules -- `Treko.dc.html:21` (the eight status hues plus `--mono`) and `:27` (§D2's eight
    # tokens) -- so the allowed span is every `:root` rule line, not one of them. Measured at
    # this commit: all 8 literal occurrences are on `:27`, and `:21` has none.
    roots = list(_ROOT_DECL_RE.finditer(html_text))
    if not roots:
        return ["no `:root{` declaration found"]
    root_spans = []
    for match in roots:
        end = html_text.find("\n", match.start())
        root_spans.append((match.start(), len(html_text) if end == -1 else end))

    comments = [m for m in _COMMENT_RE.finditer(html_text)]
    opens = [m for m in comments if EXEMPT_OPEN in m.group(0)]
    closes = [m for m in comments if EXEMPT_CLOSE in m.group(0)]
    if len(opens) != 1 or len(closes) != 1:
        problems.append(
            "expected exactly one `%s` and one `%s` HTML comment marking §D2's preview-card "
            "exemption, found %d and %d" % (EXEMPT_OPEN, EXEMPT_CLOSE, len(opens), len(closes)))
        exempt = None
    elif opens[0].end() >= closes[0].start():
        problems.append("the `%s` marker does not precede `%s`" % (EXEMPT_OPEN, EXEMPT_CLOSE))
        exempt = None
    else:
        exempt = (opens[0].end(), closes[0].start())
        region = html_text[exempt[0]:exempt[1]]
        # The region must be the preview cards and nothing wider: both glyphs §D5 names are
        # inside it, and the drawer's own panel/scrim markup is not.
        for glyph in ("ph-moon", "ph-sun"):
            if glyph not in region:
                problems.append(
                    "the exempt region does not contain `%s`, so it is not §D2's two preview "
                    "cards" % glyph)
        if "position:fixed;inset:0" in region:
            problems.append(
                "the exempt region has been widened to cover the drawer's scrim; §D2 exempts "
                "the two preview cards only")

    for literal in DARK_LITERALS:
        start = 0
        while True:
            at = html_text.find(literal, start)
            if at == -1:
                break
            start = at + 1
            if any(lo <= at < hi for lo, hi in root_spans):
                continue
            if exempt and exempt[0] <= at < exempt[1]:
                continue
            line = html_text.count("\n", 0, at) + 1
            problems.append(
                "`%s` at line %d is neither in the `:root` declaration nor inside the marked "
                "preview-card exemption" % (literal, line))
    return problems


def test_criterion2_dark_literals_live_only_in_root_and_the_preview_cards():
    """Criterion 2: the two dark literals "appear only in the eight `:root` declarations and in
    the drawer's two preview cards, which are exempt **by explicit name and comment**".

    Expected RED right now: the preview cards and their marker comments do not exist yet, so
    the exemption markers are missing. It goes green when task 7 lands the cards *with* the
    comment §D2 requires -- and it stays red if a later change tokenizes the cards away or
    scatters a literal somewhere new.
    """
    problems = _criterion2_violations(PAGE)
    assert problems == [], "criterion 2 violations in Treko.dc.html:\n  - " + "\n  - ".join(problems)


# The fixtures below are BUILT, never derived from PAGE: a mutation cut from the live page
# stops constructing its case the moment the implementation changes shape, which is exactly
# how task 6's first falsifier went blind (`50e9a32`, and gotcha 15 in the handoff).
_FIXTURE_ROOT = ":root{--rail:#12131e;--hair:rgba(255,255,255,.06)}"
_FIXTURE_CARDS = (
    '        <!-- %s §D2: each card is a miniature of the OTHER theme, so these literals\n'
    '             must not be tokenized -- doing so would make both previews identical. -->\n'
    '        <div style="background:#161826;border:1px solid rgba(255,255,255,.1)">\n'
    '          <i class="ph ph-moon"></i>Dark\n'
    '          <i class="ph ph-sun"></i>Light\n'
    '        </div>\n'
    '        <!-- %s -->\n' % (EXEMPT_OPEN, EXEMPT_CLOSE)
)


def _build_page(root=_FIXTURE_ROOT, cards=_FIXTURE_CARDS, stray=""):
    return "<html>\n<style>\n%s\n</style>\n<body>\n%s%s</body>\n</html>\n" % (
        root, cards, stray)


def test_criterion2_checker_is_falsifiable_and_satisfiable():
    """A checker proven able to fail is not thereby proven able to pass, and vice versa. Both
    halves are shown here, and each broken case reports WHICH problem the checker raised --
    a count of "all caught" hides a guard that catches everything for one shared reason.
    """
    # Satisfiability: the well-formed shape passes. Without this, every case below could be
    # "caught" by a checker that rejects all input.
    assert _criterion2_violations(_build_page()) == [], (
        "the checker rejects a correctly-shaped page, so its failures below mean nothing")

    stray_literal = '  <div style="background:rgba(255,255,255,.06)">elsewhere</div>\n'
    no_markers = _FIXTURE_CARDS.replace("<!-- %s " % EXEMPT_OPEN, "<!-- ").replace(
        "<!-- %s -->" % EXEMPT_CLOSE, "<!-- -->")
    widened = _FIXTURE_CARDS.replace(
        '<div style="background:#161826',
        '<div style="position:fixed;inset:0"></div><div style="background:#161826')
    no_glyphs = _FIXTURE_CARDS.replace("ph-moon", "ph-note").replace("ph-sun", "ph-star")

    cases = {
        "a literal outside both regions":
            (_build_page(stray=stray_literal), "neither in the `:root` declaration"),
        "the exemption comment is missing":
            (_build_page(cards=no_markers), "expected exactly one `%s`" % EXEMPT_OPEN),
        "the exempt region swallows the scrim":
            (_build_page(cards=widened), "widened to cover the drawer's scrim"),
        "the exempt region is not the preview cards":
            (_build_page(cards=no_glyphs), "does not contain `ph-moon`"),
    }
    for name, (fixture, expected_fragment) in cases.items():
        problems = _criterion2_violations(fixture)
        assert problems, "the checker missed: %s" % name
        assert any(expected_fragment in p for p in problems), (
            "%s was caught, but by the wrong assertion -- expected a problem mentioning %r, "
            "got %r" % (name, expected_fragment, problems))


# ===========================================================================================
# §D9 — there is no Artifacts section
# ===========================================================================================

def test_d9_no_artifacts_section_was_ported():
    """§D9: the prototype's third section is "dropped, not deferred". `saveArtPath` writes
    `taskTracker.artifactsPath` and nothing reads it back; since PR #68 our store directory is
    resolved once at startup by `treko/store_location.py`, so a path typed into the drawer
    would change a browser key while the server kept writing where it always did.

    This asserts the absence of the prototype's own names, which is what a copy-paste port
    would bring with it. It cannot prove nobody adds an unrelated third section (recorded in
    the module docstring as not proven).
    """
    for name in ("artifactsPath", "saveArtPath", "artPathDraft", "artSaved", "setArtPath"):
        assert name not in PAGE, (
            "`%s` is in Treko.dc.html -- §D9 drops the Artifacts section outright, because "
            "nothing reads the key back and the store directory is resolved at startup" % name)
