"""Card D — a non-text contrast guard on a named token allowlist.

`docs/features/treko-non-text-contrast.md` governs: §D2 is the allowlist, §D7 is the normative
statement of what happens to a mark the check cannot composite, §D8 is what this module asserts.

**What a green run here means.** The 23 named tokens on the allowlist have not regressed: the
6 PIN tokens still clear 3.0:1, the 3 DEBT tokens still sit at exactly the ratios this card
recorded, and no mark on the board is painted in a colour a human has not classified. **It does
not mean the board is accessible.** A correct implementation of WCAG 1.4.11 fails 261 of 336
marks in dark today (§Background 2); this module deliberately does not implement it. Every test
docstring below repeats that, because a green tick is what a future reader will see first.

Card A's `test_theme.py::test_criterion5_light_mode_contrast_meets_wcag` is the neighbouring
check and scores a disjoint population: elements that paint **text** in their own `color`, in
**light** only. Nothing here overlaps it.

RED HALF (task 2). At this commit `NONTEXT_WALK_JS` is `None` — the walk itself is task 3. Every
test below fails on that guard, with no browser launched, and the assertions are what task 3 has
to satisfy. Do not weaken them to reach green.
"""

import json
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cdp_harness  # noqa: E402
import server_harness  # noqa: E402


# --------------------------------------------------------------------- recorded population
#
# Every figure here was measured on the fixed tree fixture in the pinned Chrome build and is
# asserted EXACTLY, never as a floor: `>= 200` against a real 334 stays green after 134 marks
# disappear (§D8). Task 3 re-establishes these numbers with this module's own walk, run twice
# and diffed, rather than inheriting them from the throwaway planning probe.

# The scored population — what the allowlist assertions run over (§Background 1a).
SCORED_MARKS = {"dark": 334, "light": 347}

# §D7's enumerated exclusions. None of these is an addend of SCORED_MARKS; each is asserted in
# its own unit, and each count going above OR below its recorded value IS the abort for its
# class — there is no separate earlier per-mark abort.
#
# §D7 as written said the header fill is excluded because its own colour is a `color-mix()`,
# which Chrome serialises as `color(srgb ...)` and which therefore matches no token's declared
# value by string. **Measured, that rule excludes 41 marks in dark, not 1**: `--color-divider`'s
# dark value is itself `color-mix(in srgb, #e9e9ed 16%, transparent)` (`treko/nocturne.css:17`)
# and §D2 scores its 40 marks as EXEMPT -- the card's own 334 total requires them scored. The
# narrower rule below reproduces every figure the card recorded, and is the physically honest
# one: behind a `backdrop-filter` is blurred page content, not a flat colour, so a fill painted
# there has nothing to be scored against. The same element's border IS scored, because a border
# is measured against the surface outside the element, which the blur does not touch -- and it
# has to be, since §D2 records `--hair` at 42 marks and excluding it would give 41.
EXCLUDED_BLURRED_FILLS = 1           # the sticky header's fill, Treko.dc.html:102
GRADIENT_PAINTED_ELEMENTS = 5        # progress-bar fill x1, section-header rule x4
MARKS_OVER_BACKGROUND_IMAGE = 0      # measured: nothing is scored against a guessed ground

THEMES = ("dark", "light")


# --------------------------------------------------------------------- the walk
#
# Task 3 lands this. Kept as a module-level constant rather than inline so the red half asserts
# against a named absence instead of a NameError.
NONTEXT_WALK_JS = None

_RED_REASON = (
    "NONTEXT_WALK_JS is still None -- the element walk is task 3 (green half) of "
    "docs/features/treko-non-text-contrast.md. This module's assertions are the red half and "
    "were written first, deliberately, so that the walk is measured against numbers it did not "
    "choose."
)


def _wait_for_mount(chrome, timeout=15):
    """Poll until DCLogic has rendered the real board rather than a placeholder.

    Same shape as `test_theme.py::_wait_for_mount` and for the same reason: both placeholders
    render a handful of elements and the mounted board renders hundreds, so a low floor tells
    them apart without hardcoding a selector into the framework's internals. Duplicated rather
    than imported -- one test module importing another couples their collection order.
    """
    deadline = time.time() + timeout
    count = 0
    while time.time() < deadline:
        count = chrome.evaluate("document.querySelectorAll('body *').length")
        if count > 50:
            return count
        time.sleep(0.1)
    raise AssertionError(
        "page never rendered past %d body descendants within %ds (stuck on loading/missing "
        "state?)" % (count, timeout))


def _apply_theme(chrome, url, theme):
    """Reach `theme` the way the app itself would: through `localStorage` and a reload.

    Never `setAttribute('data-theme', ...)` -- that tests the assertion instead of the code
    under it (criterion 1; card A's Proof C establishes the pattern). Dark is reached by
    *removing* the key rather than seeding it, which is the §Scenarios "check runs on the
    default theme" case: no stored value, and the page's own mount-time seed falls back to dark.
    """
    chrome.navigate(url)
    _wait_for_mount(chrome)
    if theme == "dark":
        chrome.evaluate("localStorage.removeItem('taskTracker.theme')")
        assert chrome.evaluate("localStorage.getItem('taskTracker.theme')") is None
    else:
        chrome.evaluate("localStorage.setItem('taskTracker.theme',%s)" % json.dumps(theme))
        assert chrome.evaluate("localStorage.getItem('taskTracker.theme')") == theme
    chrome.reload()
    _wait_for_mount(chrome)
    applied = chrome.evaluate("document.body.getAttribute('data-theme')")
    assert applied == theme, (
        "expected body[data-theme=%r] after %s taskTracker.theme and reloading -- got %r"
        % (theme, "clearing" if theme == "dark" else "seeding", applied))


@pytest.fixture(scope="module")
def walk(tmp_path_factory):
    """`{theme: <walk result>}` for both themes, from one server and one Chrome.

    Module-scoped on purpose: the walk is read by every test below and a Chrome launch per test
    would multiply the suite's slowest fixture by the number of assertions. It builds its own
    tree and server rather than using `conftest.py`'s function-scoped `srv`, because criterion
    10 forbids editing that conftest -- a module-scoped fixture cannot depend on a
    function-scoped one.
    """
    if NONTEXT_WALK_JS is None:
        return None
    root = tmp_path_factory.mktemp("nontext")
    tree = server_harness.build_tree(root)
    server = server_harness.launch(root, tree=tree)
    try:
        chrome = cdp_harness.Chrome(str(root / "chrome-profile"))
        try:
            url = "http://127.0.0.1:%d/" % server.port
            results = {}
            for theme in THEMES:
                _apply_theme(chrome, url, theme)
                results[theme] = chrome.evaluate(NONTEXT_WALK_JS)
            return results
        finally:
            chrome.close()
    finally:
        server.stop()


def _kind_breakdown(by_kind):
    """`kind  count`, for a total that moved.

    Deliberately NOT laid out as an expected/measured/delta table: there is no recorded
    per-kind expectation to compare against, and a column of zeroes in an `expected` heading
    reads as a measurement while being a placeholder. The per-ENTRY delta table §D8 requires
    arrives with the allowlist, which is what gives it a real expected column.
    """
    return "\n".join("  %-16s %4d" % (kind, by_kind[kind]) for kind in sorted(by_kind)) or "  (none)"


# --------------------------------------------------------------------- criterion 7


@pytest.mark.parametrize("theme", THEMES)
def test_scored_mark_count_is_exact(walk, theme):
    """Criterion 7 — the scored population is 334 dark / 347 light, asserted exactly.

    A green run means these counts have not moved. It does not mean the board is accessible.

    A total other than the recorded one cannot tell you WHICH criterion is unmet and must not be
    read as if it could: re-scoring the `<svg>` root alone (criterion 8) gives 335 / 348,
    scoring the excluded header mark alone (criterion 6) gives 335 / 348 too, and both together
    give 336 / 349. Read the excluded-mark count and the SVG predicate to tell them apart.
    """
    assert walk is not None, _RED_REASON
    assert walk[theme]["scoredMarks"] == SCORED_MARKS[theme], (
        "%s: scored %d non-text marks, recorded %d\n%s"
        % (theme, walk[theme]["scoredMarks"], SCORED_MARKS[theme],
           _kind_breakdown(walk[theme]["byKind"])))


# --------------------------------------------------------------------- criterion 6


@pytest.mark.parametrize("theme", THEMES)
def test_no_colour_parse_failures(walk, theme):
    """Criterion 6 / §D7 rule 1 — a colour string the parser cannot read fails the run.

    A green run means no mark was silently dropped. It does not mean the board is accessible.

    This is the card's own origin story: the planning probe copied `parseColor` from
    `test_theme.py`, could not read Chrome's `color(srgb r g b / a)` serialisation, returned
    alpha 0, and the caller read that as "not painted" -- silently dropping 41 painted marks in
    dark. A silent skip is indistinguishable from a passing check, so an unreadable colour is
    counted and fails here rather than being treated as transparent.
    """
    assert walk is not None, _RED_REASON
    failures = walk[theme]["parseFailures"]
    assert failures == 0, (
        "%s: %d colour string(s) the parser could not read. Every one of these was dropped from "
        "the population rather than scored, which is the exact failure this card exists to "
        "prevent:\n%s"
        % (theme, failures, json.dumps(walk[theme]["parseFailureSamples"], indent=2)))


@pytest.mark.parametrize("theme", THEMES)
def test_enumerated_exclusions_are_at_their_recorded_counts(walk, theme):
    """Criterion 6 / §D7 rule 2 — the three exclusion counts, each in its own unit.

    A green run means no unclassified mark was excluded. It does not mean the board is accessible.

    These counts ARE the abort for their classes, not a second competing behaviour: a mark that
    cannot be composited and is not on this card's enumerated list takes one of them off its
    recorded value, and the run fails naming the path and why. An exclusion list that can grow
    silently is the same failure as a silent skip, so movement in EITHER direction fails --
    falsifier case 7 shrinks the header count to 0 and case 8 grows it to 2.
    """
    assert walk is not None, _RED_REASON
    result = walk[theme]
    assert result["excludedBlurredFills"] == EXCLUDED_BLURRED_FILLS, (
        "%s: %d fill(s) excluded for sitting over a backdrop-filter, recorded %d. The one this "
        "card enumerated is the sticky header (Treko.dc.html:102); anything else here is a mark "
        "no human has classified:\n%s"
        % (theme, result["excludedBlurredFills"], EXCLUDED_BLURRED_FILLS,
           json.dumps(result["excludedBlurredFillSamples"], indent=2)))
    assert result["gradientPaintedElements"] == GRADIENT_PAINTED_ELEMENTS, (
        "%s: %d element(s) paint a background-image, recorded %d. The predicate is "
        "`background-image !== 'none'`, not `is a gradient`: a url() backdrop defeats "
        "compositing exactly as a gradient does:\n%s"
        % (theme, result["gradientPaintedElements"], GRADIENT_PAINTED_ELEMENTS,
           json.dumps(result["gradientPaintedSamples"], indent=2)))
    assert result["marksOverBackgroundImage"] == MARKS_OVER_BACKGROUND_IMAGE, (
        "%s: %d scored mark(s) sit over a background-image, recorded %d. Such a mark is scored "
        "against a ground that is not what is painted -- `effectiveBackground()` accumulates "
        "background-color only. This assertion is what converts that latent wrong answer into a "
        "loud failure:\n%s"
        % (theme, result["marksOverBackgroundImage"], MARKS_OVER_BACKGROUND_IMAGE,
           json.dumps(result["marksOverBackgroundImageSamples"], indent=2)))
