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
# Kept as a module-level constant rather than inline so it can be driven from outside pytest when
# a figure has to be re-measured.
#
# Four defects of the throwaway planning probe are fixed here by construction, and each has a
# falsifier in the card's task 8 because "we fixed it" is not evidence that it stays fixed:
#   * the SVG predicate is a closed list of shape tags, so the <svg> root -- which paints nothing
#     and merely inherits `fill: rgb(0,0,0)` -- is never scored (criterion 8, case 10);
#   * box-shadow is split on top-level commas, so all colours in a multi-shadow list are read,
#     not just the first (criterion 9, case 11);
#   * parseColor reads Chrome's `color(srgb r g b / a)` serialisation of `color-mix()` instead of
#     returning alpha 0 and having the caller mistake it for "not painted" (criterion 6, case 9);
#   * effectiveBackground reports whether the chain it walked crossed a `background-image`, and it
#     checks EVERY node it crosses rather than only the ones contributing an opaque-enough layer
#     -- a gradient normally sits on a transparent background-color, so a detector that only
#     looked at pushed layers would report 0 on every page, forever, green (case 12).
NONTEXT_WALK_JS = r"""
(() => {
  // A closed list, not an illustrative one: the counts it feeds are asserted exactly, and a
  // trailing "..." would let two implementations produce two different totals and both call
  // themselves correct. A shape tag outside this list appearing on the page surfaces as an
  // unmapped (colour, kind) key rather than by this predicate silently widening.
  const SHAPE_TAGS = {circle:1, ellipse:1, line:1, path:1, polygon:1, polyline:1, rect:1};
  const SVG_NS = 'http://www.w3.org/2000/svg';

  let parseFailures = 0;
  const parseFailureSamples = [];

  function describe(el) {
    const parts = [];
    let node = el, depth = 0;
    while (node && node.nodeType === 1 && depth < 4) {
      let seg = node.localName;
      const cls = (node.getAttribute && node.getAttribute('class')) || '';
      if (cls) seg += '.' + cls.trim().split(/\s+/).slice(0, 2).join('.');
      parts.unshift(seg);
      node = node.parentElement;
      depth++;
    }
    return parts.join(' > ');
  }

  function noteParseFailure(str, el, where) {
    parseFailures++;
    if (parseFailureSamples.length < 10) {
      parseFailureSamples.push({value: String(str), property: where, path: describe(el)});
    }
  }

  // Returns {r,g,b,a} with channels in 0..255, or null when the string cannot be read.
  // null is never coerced to transparent: that coercion is the bug this whole card is about.
  function parseColor(str) {
    if (!str) return null;
    const s = String(str).trim();
    if (s === 'transparent') return {r:0, g:0, b:0, a:0};
    let m = s.match(/^rgba?\(([^)]*)\)$/);
    if (m) {
      // A percentage would parseFloat to its face value and be silently 255x wrong, so it is a
      // parse failure rather than a guess. Chrome does not emit one today.
      if (m[1].indexOf('%') !== -1) return null;
      const parts = m[1].split(/[,\/\s]+/).filter(t => t.length).map(parseFloat);
      if (parts.length < 3 || parts.slice(0, 3).some(isNaN)) return null;
      const a = parts.length > 3 ? parts[3] : 1;
      if (isNaN(a)) return null;
      return {r: parts[0], g: parts[1], b: parts[2], a: a};
    }
    // How Chrome serialises color-mix(in srgb, ...) -- the form the planning probe could not
    // read, which cost it 41 painted marks in dark with no warning.
    m = s.match(/^color\(srgb\s+([^)]*)\)$/);
    if (m) {
      if (m[1].indexOf('%') !== -1) return null;
      const parts = m[1].split(/[\/\s]+/).filter(t => t.length).map(parseFloat);
      if (parts.length < 3 || parts.slice(0, 3).some(isNaN)) return null;
      const a = parts.length > 3 ? parts[3] : 1;
      if (isNaN(a)) return null;
      return {r: parts[0]*255, g: parts[1]*255, b: parts[2]*255, a: a};
    }
    return null;
  }


  function compositeOver(fg, bg) {
    const a = fg.a;
    return {r: fg.r*a + bg.r*(1-a), g: fg.g*a + bg.g*(1-a), b: fg.b*a + bg.b*(1-a), a: 1};
  }

  const WHITE = {r:255, g:255, b:255, a:1};

  // The surface behind `el`: background-color layers accumulated up the ancestor chain, stopping
  // at the first opaque one. `crossedImage` is produced by this same walk on purpose -- a
  // separate walk could drift out of agreement with the one that actually decided the colour.
  function effectiveBackground(el) {
    const layers = [];
    let crossedImage = null;
    let node = el;
    while (node && node.nodeType === 1) {
      const cs = getComputedStyle(node);
      // Checked before the opacity test and on every node, including ones contributing no
      // layer: a gradient element carries `background-color: transparent`, so checking only
      // pushed layers is the detector that can never fire.
      if (crossedImage === null && cs.backgroundImage && cs.backgroundImage !== 'none') {
        crossedImage = {path: describe(node), image: cs.backgroundImage.slice(0, 120)};
      }
      const rgba = parseColor(cs.backgroundColor);
      if (rgba === null) {
        noteParseFailure(cs.backgroundColor, node, 'background-color');
      } else if (rgba.a > 0) {
        layers.push(rgba);
        if (rgba.a >= 0.999) break;
      }
      node = node.parentElement;
    }
    let result = layers.length ? layers[layers.length - 1] : WHITE;
    if (result.a < 0.999) result = compositeOver(result, WHITE);
    for (let i = layers.length - 2; i >= 0; i--) result = compositeOver(layers[i], result);
    return {color: result, crossedImage: crossedImage};
  }

  function relLuminance(c) {
    const chan = v => { v /= 255; return v <= 0.03928 ? v/12.92 : Math.pow((v+0.055)/1.055, 2.4); };
    return 0.2126*chan(c.r) + 0.7152*chan(c.g) + 0.0722*chan(c.b);
  }

  function contrastRatio(c1, c2) {
    const L1 = relLuminance(c1), L2 = relLuminance(c2);
    return (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05);
  }

  // Split a box-shadow list on top-level commas only -- the commas inside rgba(...) are not
  // separators. Reading only the first entry drops 13 of the 16 outset shadows in light.
  function splitShadows(value) {
    const out = [];
    let depth = 0, start = 0;
    for (let i = 0; i < value.length; i++) {
      const ch = value[i];
      if (ch === '(') depth++;
      else if (ch === ')') depth--;
      else if (ch === ',' && depth === 0) { out.push(value.slice(start, i)); start = i + 1; }
    }
    out.push(value.slice(start));
    return out.map(s => s.trim()).filter(s => s.length);
  }

  function shadowColour(entry) {
    const m = entry.match(/(rgba?\([^)]*\)|color\([^)]*\))/);
    return m ? m[1] : null;
  }

  const SIDES = ['top', 'right', 'bottom', 'left'];

  const marks = [];                     // {key, kind, ratio, path}
  const excludedBlurred = [];
  const gradientPainted = [];
  const overImage = [];

  function record(el, colourStr, kind, blurred) {
    // A fill painted on an element with `backdrop-filter` has no flat surface behind it -- what
    // is behind is blurred page content -- so there is nothing to score it against. The SAME
    // element's border is still scored: a border is measured against the surface OUTSIDE the
    // element, which the blur does not touch.
    if (blurred && kind === 'fill') {
      excludedBlurred.push({path: describe(el), kind: kind, color: String(colourStr),
                                   why: 'fill over a backdrop-filter: the backdrop is blurred ' +
                                        'page content, not a flat colour'});
      return;
    }
    const own = parseColor(colourStr);
    if (own === null) { noteParseFailure(colourStr, el, kind); return; }
    if (own.a <= 0) return;
    const outside = effectiveBackground(el.parentElement);
    if (outside.crossedImage) {
      overImage.push({path: describe(el), kind: kind, color: String(colourStr),
                      ancestor: outside.crossedImage.path, image: outside.crossedImage.image});
      return;
    }
    const painted = own.a >= 0.999 ? own : compositeOver(own, outside.color);
    marks.push({
      key: String(colourStr) + '|' + kind,
      color: String(colourStr),
      kind: kind,
      ratio: contrastRatio(painted, outside.color),
      path: describe(el)
    });
  }

  const all = document.querySelectorAll('body *');
  let elementsWithArea = 0;

  all.forEach(el => {
    const rect = el.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return;
    elementsWithArea++;
    const cs = getComputedStyle(el);
    const isSvg = el.namespaceURI === SVG_NS;
    const blurred = !!(cs.backdropFilter && cs.backdropFilter !== 'none');

    if (isSvg) {
      // Gated on a closed list of shape tags: svg, g, defs and title paint nothing, and `fill`
      // is an inherited property, so reading it off a container invents a mark.
      if (!SHAPE_TAGS[el.localName]) return;
      if (cs.fill && cs.fill !== 'none') record(el, cs.fill, 'svg-fill', blurred);
      if (cs.stroke && cs.stroke !== 'none' && parseFloat(cs.strokeWidth) > 0) {
        record(el, cs.stroke, 'svg-stroke', blurred);
      }
      return;
    }

    // A background-image is not a flat colour, so the element emits no fill mark at all; it is
    // tallied instead, and the tally is what fails when the set of them changes.
    if (cs.backgroundImage && cs.backgroundImage !== 'none') {
      gradientPainted.push({path: describe(el), image: cs.backgroundImage.slice(0, 120),
                            size: Math.round(rect.width) + 'x' + Math.round(rect.height)});
    } else {
      record(el, cs.backgroundColor, 'fill', blurred);
    }

    SIDES.forEach(side => {
      const cap = side[0].toUpperCase() + side.slice(1);
      const style = cs['border' + cap + 'Style'];
      if (!style || style === 'none' || style === 'hidden') return;
      if (parseFloat(cs['border' + cap + 'Width']) <= 0) return;
      record(el, cs['border' + cap + 'Color'], 'border-' + side, blurred);
    });

    if (cs.boxShadow && cs.boxShadow !== 'none') {
      splitShadows(cs.boxShadow).forEach(entry => {
        if (/\binset\b/.test(entry)) return;
        const colour = shadowColour(entry);
        if (colour === null) { noteParseFailure(entry, el, 'box-shadow'); return; }
        record(el, colour, 'shadow-outset', blurred);
      });
    }
  });

  const byKey = {}, byKind = {};
  marks.forEach(m => {
    byKind[m.kind] = (byKind[m.kind] || 0) + 1;
    const slot = byKey[m.key];
    if (!slot || m.ratio < slot.minRatio) {
      byKey[m.key] = {count: (slot ? slot.count : 0) + 1, minRatio: m.ratio,
                      worstKind: m.kind, worstPath: m.path};
    } else {
      slot.count++;
    }
  });
  Object.keys(byKey).forEach(k => {
    byKey[k].minRatio = Math.round(byKey[k].minRatio * 10000) / 10000;
  });

  return {
    dataTheme: document.body.getAttribute('data-theme'),
    elementsWithArea: elementsWithArea,
    scoredMarks: marks.length,
    byKey: byKey,
    byKind: byKind,
    dump: marks.map(m => m.key + ' @ ' + m.path + ' = ' +
                         (Math.round(m.ratio * 10000) / 10000)).sort(),
    parseFailures: parseFailures,
    parseFailureSamples: parseFailureSamples,
    excludedBlurredFills: excludedBlurred.length,
    excludedBlurredFillSamples: excludedBlurred.slice(0, 10),
    gradientPaintedElements: gradientPainted.length,
    gradientPaintedSamples: gradientPainted.slice(0, 10),
    marksOverBackgroundImage: overImage.length,
    marksOverBackgroundImageSamples: overImage.slice(0, 10)
  };
})()
"""

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


# --------------------------------------------------------------------- the allowlist
#
# Twenty-three entries: 6 PIN, 3 DEBT, 14 EXEMPT. Twenty-two are palette colour tokens; the
# twenty-third is --shadow-sm, a shadow token whose value carries one colour in dark and two in
# light. Classified by hand once, per §D2 -- a machine guessing which marks are load-bearing
# fails three quarters of the page (§Background 2), including hairlines designed to be barely
# visible.
#
# Every colour string below is what Chrome serialises the token to, read off the live page in
# each theme rather than converted from the declared hex by hand. A token's dark and light
# figures have no relationship to each other (the light palette is a hand-inverted ramp, not a
# re-tinted one -- §Background 3), which is why every field is per theme.
#
# `kinds` is omitted unless an entry needs it: an entry with no filter claims every kind its
# colours paint, and today exactly two entries need one.
#
# --hair-2 and --hair-3 are NOT here, and not because they are unused: each has a live call site
# behind an interaction gate (the command-copy chip and the drawer's left edge; the agent panel's
# top border), and §Scope/Out puts every interaction-gated region outside this card's population.

PIN, DEBT, EXEMPT = "pin", "debt", "exempt"

ALLOWLIST = [
    {
     "token": "--color-accent", "klass": PIN, "floor": None,
     "reason": None,
     "dark": {"colors": ["rgb(56, 196, 227)"],
               "kinds": None, "marks": 34, "min_ratio": None},
     "light": {"colors": ["rgb(0, 116, 146)"],
               "kinds": None, "marks": 34, "min_ratio": None},
    },
    {
     "token": "--color-accent-300", "klass": PIN, "floor": None,
     "reason": None,
     "dark": {"colors": ["rgb(130, 216, 240)"],
               "kinds": None, "marks": 2, "min_ratio": None},
     "light": {"colors": ["rgb(0, 109, 136)"],
               "kinds": None, "marks": 2, "min_ratio": None},
    },
    {
     "token": "--ok", "klass": PIN, "floor": None,
     "reason": None,
     "dark": {"colors": ["rgb(130, 223, 169)"],
               "kinds": None, "marks": 4, "min_ratio": None},
     "light": {"colors": ["rgb(18, 121, 74)"],
               "kinds": None, "marks": 4, "min_ratio": None},
    },
    {
     "token": "--warn", "klass": PIN, "floor": None,
     "reason": None,
     "dark": {"colors": ["rgb(216, 176, 108)"],
               "kinds": None, "marks": 7, "min_ratio": None},
     "light": {"colors": ["rgb(138, 97, 19)"],
               "kinds": None, "marks": 7, "min_ratio": None},
    },
    {
     "token": "--bad", "klass": PIN, "floor": None,
     "reason": None,
     "dark": {"colors": ["rgb(232, 150, 142)"],
               "kinds": None, "marks": 7, "min_ratio": None},
     "light": {"colors": ["rgb(176, 58, 48)"],
               "kinds": None, "marks": 7, "min_ratio": None},
    },
    {
     "token": "--info", "klass": PIN, "floor": None,
     "reason": None,
     "dark": {"colors": ["rgb(137, 180, 242)"],
               "kinds": None, "marks": 1, "min_ratio": None},
     "light": {"colors": ["rgb(40, 86, 159)"],
               "kinds": None, "marks": 1, "min_ratio": None},
    },
    {
     "token": "--color-accent-700", "klass": DEBT, "floor": None,
     "reason": "merge-wave badge border, 5 badges x 4 sides, plus 1 outset shadow; an inverted-ramp "
     "defect recorded rather than fixed (§D5). The minimum comes from the shadow, not a "
     "border.",
     "dark": {"colors": ["rgb(34, 122, 147)"],
               "kinds": None, "marks": 21, "min_ratio": None},
     "light": {"colors": ["rgb(164, 226, 243)"],
               "kinds": None, "marks": 21, "min_ratio": None},
    },
    {
     "token": "--color-neutral-700", "klass": DEBT, "floor": None,
     "reason": "graph node border, 7 nodes x 4 sides, plus 4 SVG fills and 3 SVG strokes; an "
     "inverted-ramp defect recorded rather than fixed (§D5). The minimum comes from an SVG "
     "stroke.",
     "dark": {"colors": ["rgb(89, 93, 108)"],
               "kinds": None, "marks": 35, "min_ratio": None},
     "light": {"colors": ["rgb(110, 114, 126)"],
               "kinds": None, "marks": 35, "min_ratio": None},
    },
    # CRITERION 13 -- the one live colour collision on this page. This token's dark value is
    # #3f424d, and --shadow-sm's dark value is the literal hex #3f424d too
    # (_ds/nocturne-*/styles.css:78). Both serialise to rgb(63, 66, 77). The `kinds` filter is
    # the whole separation: all 22 of this token's dark marks are fills, all 13 of the
    # shadow's are outset shadows, and the partition is exact with nothing left over.
    # No other collision is claimed. An earlier draft asserted one between --color-accent and
    # --color-accent-500 -- false: --color-accent-500 has zero var() consumers and paints
    # nothing, so it cannot be misattributed (§Background 7).
    {
     "token": "--color-neutral-800", "klass": DEBT, "floor": None,
     "reason": "unfilled phase dot, 22 fills and nothing else; an inverted-ramp defect recorded "
     "rather than fixed (§D5). This ratio is vs the surface: filled-vs-unfilled dot is "
     "4.85 dk / 4.30 lt and reads fine, so do not repaint a meter that is already legible.",
     "dark": {"colors": ["rgb(63, 66, 77)"],
               "kinds": ['fill'], "marks": 22, "min_ratio": None},
     "light": {"colors": ["rgb(227, 230, 239)"],
               "kinds": ['fill'], "marks": 22, "min_ratio": None},
    },
    {
     "token": "--hair", "klass": EXEMPT, "floor": None,
     "reason": "1px hairline on 4 sides. Pushed to 3:1 it would be a visible regression -- being "
     "nearly invisible is the job (§D4).",
     "dark": {"colors": ["rgba(255, 255, 255, 0.06)"],
               "kinds": None, "marks": 42, "min_ratio": None},
     "light": {"colors": ["rgba(15, 18, 35, 0.09)"],
               "kinds": None, "marks": 42, "min_ratio": None},
    },
    {
     "token": "--hover", "klass": EXEMPT, "floor": None,
     "reason": "static row separator: border-top at Treko.dc.html:97,156,205,237,257,292, repeated "
     "by sc-for. Painted at mount with no pointer on the page, despite the token's name "
     "(§D4).",
     "dark": {"colors": ["rgba(255, 255, 255, 0.05)"],
               "kinds": None, "marks": 30, "min_ratio": None},
     "light": {"colors": ["rgba(15, 18, 35, 0.05)"],
               "kinds": None, "marks": 30, "min_ratio": None},
    },
    {
     "token": "--hover-soft", "klass": EXEMPT, "floor": None,
     "reason": "the selected sidebar row's fill, computed at Treko.dc.html:687,694,711 and applied "
     "through :84. Painted at mount despite the token's name (§D4).",
     "dark": {"colors": ["rgba(255, 255, 255, 0.03)"],
               "kinds": None, "marks": 2, "min_ratio": None},
     "light": {"colors": ["rgba(15, 18, 35, 0.03)"],
               "kinds": None, "marks": 2, "min_ratio": None},
    },
    {
     "token": "--color-divider", "klass": EXEMPT, "floor": None,
     "reason": "1px divider on 4 sides, same species as --hair (§D4). Its dark value is a "
     "color-mix(), which composites perfectly well and is scored like any other token -- "
     "see §D7.",
     "dark": {"colors": ["color(srgb 0.913725 0.913725 0.929412 / 0.16)"],
               "kinds": None, "marks": 40, "min_ratio": None},
     "light": {"colors": ["rgba(15, 18, 35, 0.12)"],
               "kinds": None, "marks": 40, "min_ratio": None},
    },
    {
     "token": "--color-bg", "klass": EXEMPT, "floor": None,
     "reason": "the page ground. Surfaces are what other marks are measured against; scoring one "
     "against itself is not a meaningful question (§D4).",
     "dark": {"colors": ["rgb(22, 24, 38)"],
               "kinds": None, "marks": 18, "min_ratio": None},
     "light": {"colors": ["rgb(245, 246, 250)"],
               "kinds": None, "marks": 18, "min_ratio": None},
    },
    {
     "token": "--color-surface", "klass": EXEMPT, "floor": None,
     "reason": "the card ground -- a surface other marks are measured against (§D4).",
     "dark": {"colors": ["rgb(28, 30, 43)"],
               "kinds": None, "marks": 14, "min_ratio": None},
     "light": {"colors": ["rgb(255, 255, 255)"],
               "kinds": None, "marks": 14, "min_ratio": None},
    },
    {
     "token": "--rail", "klass": EXEMPT, "floor": None,
     "reason": "the sidebar ground -- a surface other marks are measured against (§D4).",
     "dark": {"colors": ["rgb(18, 19, 30)"],
               "kinds": None, "marks": 1, "min_ratio": None},
     "light": {"colors": ["rgb(236, 238, 245)"],
               "kinds": None, "marks": 1, "min_ratio": None},
    },
    {
     "token": "--color-neutral-900", "klass": EXEMPT, "floor": None,
     "reason": "the inset well ground behind the progress track -- a surface other marks are "
     "measured against (§D4).",
     "dark": {"colors": ["rgb(41, 43, 49)"],
               "kinds": None, "marks": 11, "min_ratio": None},
     "light": {"colors": ["rgb(240, 242, 248)"],
               "kinds": None, "marks": 11, "min_ratio": None},
    },
    {
     "token": "--ok-bg", "klass": EXEMPT, "floor": None,
     "reason": "ok badge fill. It sits directly behind badge text, and card A's criterion 5 already "
     "scores that text against this exact alpha-composited background -- move it toward "
     "--ok and that check goes red first (§D3).",
     "dark": {"colors": ["rgb(18, 53, 38)"],
               "kinds": None, "marks": 5, "min_ratio": None},
     "light": {"colors": ["rgb(219, 243, 230)"],
               "kinds": None, "marks": 5, "min_ratio": None},
    },
    {
     "token": "--warn-bg", "klass": EXEMPT, "floor": None,
     "reason": "warn badge fill; scored indirectly by card A's criterion 5 through the text on it "
     "(§D3).",
     "dark": {"colors": ["rgb(58, 45, 21)"],
               "kinds": None, "marks": 5, "min_ratio": None},
     "light": {"colors": ["rgb(250, 238, 210)"],
               "kinds": None, "marks": 5, "min_ratio": None},
    },
    {
     "token": "--bad-bg", "klass": EXEMPT, "floor": None,
     "reason": "bad badge fill; scored indirectly by card A's criterion 5 through the text on it "
     "(§D3).",
     "dark": {"colors": ["rgb(66, 32, 29)"],
               "kinds": None, "marks": 6, "min_ratio": None},
     "light": {"colors": ["rgb(251, 226, 223)"],
               "kinds": None, "marks": 6, "min_ratio": None},
    },
    {
     "token": "--info-bg", "klass": EXEMPT, "floor": None,
     "reason": "info badge fill; scored indirectly by card A's criterion 5 through the text on it "
     "(§D3).",
     "dark": {"colors": ["rgb(22, 41, 74)"],
               "kinds": None, "marks": 3, "min_ratio": None},
     "light": {"colors": ["rgb(223, 233, 251)"],
               "kinds": None, "marks": 3, "min_ratio": None},
    },
    {
     "token": "--color-accent-900", "klass": EXEMPT, "floor": None,
     "reason": "accent badge fill; scored indirectly by card A's criterion 5 through the text on it "
     "(§D3).",
     "dark": {"colors": ["rgb(16, 56, 69)"],
               "kinds": None, "marks": 11, "min_ratio": None},
     "light": {"colors": ["rgb(226, 246, 252)"],
               "kinds": None, "marks": 11, "min_ratio": None},
    },
    # CRITERION 13, the other half of the same collision: this token's dark value is the
    # literal hex #3f424d, identical to --color-neutral-800's, so both entries legitimately
    # claim rgb(63, 66, 77) and the `kinds` filter is what tells their marks apart.
    {
     "token": "--shadow-sm", "klass": EXEMPT, "floor": None,
     "reason": "card elevation hairline on 13 cards, same species as --hair (§D4). Not a colour "
     "token: its value is a shadow list, one colour in dark and two in light.",
     "dark": {"colors": ["rgb(63, 66, 77)"],
               "kinds": ['shadow-outset'], "marks": 13, "min_ratio": None},
     "light": {"colors": ["rgba(15, 18, 35, 0.06)", "rgba(15, 18, 35, 0.07)"],
               "kinds": ['shadow-outset'], "marks": 26, "min_ratio": None},
    },
]

_NO_ALLOWLIST = (
    "ALLOWLIST is still empty -- the 23 entries are task 5 (green half) of "
    "docs/features/treko-non-text-contrast.md §D2. This assertion is the red half."
)


def _matches(entry, theme, colour, kind):
    """Does `entry` claim the mark identified by this (colour, kind) key?

    Marks are keyed on the PAIR, never on colour alone. Dark `rgb(63, 66, 77)` is painted by
    `--color-neutral-800` as 22 fills and by `--shadow-sm` as 13 outset shadows (§Background 7),
    and keying on colour alone makes criterion 5 ("exactly one entry") and criterion 7 (per-entry
    counts) impossible to satisfy at once. An entry with no `kinds` filter claims every kind its
    colours paint; today exactly two entries need one.
    """
    side = entry[theme]
    if colour not in side["colors"]:
        return False
    return side["kinds"] is None or kind in side["kinds"]


def _entry_counts(theme, by_key):
    """`{token: marks measured}` for every allowlist entry, tokens with no marks included at 0."""
    counts = {entry["token"]: 0 for entry in ALLOWLIST}
    for key, slot in by_key.items():
        colour, kind = key.rsplit("|", 1)
        for entry in ALLOWLIST:
            if _matches(entry, theme, colour, kind):
                counts[entry["token"]] += slot["count"]
    return counts


def _entry_delta_table(theme, by_key):
    """`token | expected | measured | delta`, unchanged entries omitted.

    §D8 makes this part of the requirement rather than a nicety: `333 != 334` across 23 entries
    tells a reader nothing about which entry moved. Unlike the per-kind breakdown above, this one
    has a real expected column -- the allowlist is where it comes from.
    """
    measured = _entry_counts(theme, by_key)
    rows = []
    for entry in ALLOWLIST:
        want, got = entry[theme]["marks"], measured[entry["token"]]
        if want != got:
            rows.append("  %-22s expected %4d  measured %4d  delta %+d"
                        % (entry["token"], want, got, got - want))
    return "\n".join(rows) if rows else "  (every entry sits at its recorded count)"


# --------------------------------------------------------------------- criterion 5


def test_no_allowlist_key_is_claimed_by_two_entries():
    """Criterion 5, second half — asserted over the allowlist data alone, before any page loads.

    A green run means no two entries fight over the same mark. It does not mean the board is
    accessible.

    This is the machine-checkable form of "exactly one entry", and it deliberately fails at
    import time rather than at measurement time: a stale list is then caught even in a run where
    the page never rendered. Dark `rgb(63, 66, 77)` is claimed by both `--color-neutral-800`
    (`fill`) and `--shadow-sm` (`shadow-outset`); the `kinds` filter is what keeps that
    unambiguous, and this assertion is what proves the filter is doing its job.
    """
    assert ALLOWLIST, _NO_ALLOWLIST
    for theme in THEMES:
        claimed = {}
        for entry in ALLOWLIST:
            side = entry[theme]
            kinds = side["kinds"] if side["kinds"] is not None else ["<any kind>"]
            for colour in side["colors"]:
                for kind in kinds:
                    key = (colour, kind)
                    assert key not in claimed, (
                        "%s: (%s, %s) is claimed by both %s and %s. Two entries cannot own one "
                        "mark -- give one of them a `kinds` filter, or the marks are "
                        "unattributable by machine (§Background 7)."
                        % (theme, colour, kind, claimed.get(key), entry["token"]))
                    claimed[key] = entry["token"]


@pytest.mark.parametrize("theme", THEMES)
def test_every_scored_key_maps_to_exactly_one_entry(walk, theme):
    """Criterion 5, first half — coverage, both directions.

    A green run means every mark on the board is painted in a colour a human classified. It does
    not mean the board is accessible.

    This is what stops the list going stale as the page grows, and it is also the assertion that
    catches an edited token value: the edited token's declared colour string is new, so its key
    is unmapped and neither the PIN floor nor the DEBT ratio ever sees a ratio to compare. §D8's
    Coverage bullet is the normative statement of that rule and of the qualifying second half --
    an edit that ALSO updates its entry passes here by construction and is caught by the floor or
    the ratio instead.
    """
    assert ALLOWLIST, _NO_ALLOWLIST
    by_key = walk[theme]["byKey"]

    unmapped, multi = [], []
    for key, slot in sorted(by_key.items()):
        colour, kind = key.rsplit("|", 1)
        hits = [e["token"] for e in ALLOWLIST if _matches(e, theme, colour, kind)]
        if not hits:
            unmapped.append("  %-46s x%-4d %s" % (key, slot["count"], slot["worstPath"]))
        elif len(hits) > 1:
            multi.append("  %-46s claimed by %s" % (key, ", ".join(hits)))

    assert not unmapped, (
        "%s: %d (colour, kind) key(s) among the scored marks map to no allowlist entry. Either "
        "a token's value was edited without re-recording it in the card, or a new mark appeared "
        "in a colour nobody has classified:\n%s" % (theme, len(unmapped), "\n".join(unmapped)))
    assert not multi, (
        "%s: %d key(s) claimed by more than one entry:\n%s" % (theme, len(multi), "\n".join(multi)))

    starved = [e["token"] for e in ALLOWLIST
               if not any(_matches(e, theme, *k.rsplit("|", 1)) for k in by_key)]
    assert not starved, (
        "%s: %d allowlist entr%s matched zero marks: %s. A token that stopped painting is either "
        "a regression or a stale list, and both need a human -- passing on an empty set is the "
        "vacuous green this card exists to prevent (§D7 rule 3)."
        % (theme, len(starved), "y" if len(starved) == 1 else "ies", ", ".join(starved)))


# --------------------------------------------------------------------- criterion 7


@pytest.mark.parametrize("theme", THEMES)
def test_every_entry_sits_at_its_recorded_mark_count(walk, theme):
    """Criterion 7 — per-entry counts, exact.

    A green run means no mark moved between entries. It does not mean the board is accessible.

    The scored total alone cannot catch a misfiling: file all 35 of dark `rgb(63, 66, 77)` under
    one entry and the total stays 334 while two entries are wrong. That is not hypothetical --
    the round-1 revision of this card was exactly that bug, 13 shadows filed under
    `--color-neutral-800` by hex collision, with every total-based check green.
    """
    assert ALLOWLIST, _NO_ALLOWLIST
    measured = _entry_counts(theme, walk[theme]["byKey"])
    wrong = [e["token"] for e in ALLOWLIST if measured[e["token"]] != e[theme]["marks"]]
    assert not wrong, (
        "%s: %d allowlist entr%s not at %s recorded mark count:\n%s"
        % (theme, len(wrong), "y is" if len(wrong) == 1 else "ies are",
           "its" if len(wrong) == 1 else "their", _entry_delta_table(theme, walk[theme]["byKey"])))
