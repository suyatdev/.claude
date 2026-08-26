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
