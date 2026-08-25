"""RED tests for card A task 3, first half — criteria 4, 5, 6 and 7.

`docs/features/treko-theme-and-layout.md` §Acceptance criteria and §Verification ("Criterion 4 —
the light block's coverage", "Proof C — contrast, via headless Chrome computed style") govern.
Written against the page as it stood at the commit this file was written against — tokenized (task 2 landed: `--rail`,
`--hair*`, `--hover*`, the eight status tokens, all present via `var()`), but still **dark-only**:
`data-theme` has 0 occurrences in `Treko.dc.html` and there is no `body[data-theme="light"]`
block. All three tests below were expected to fail, for the reasons documented on each one, at the
commit this file was written against, until task 3's second half added the light block,
`THEME_DEFAULT`, the validated seed, and `applyTheme`/`setTheme`.

Criterion 7 (reload persistence, unavailable `localStorage`, corrupt stored theme) was added to
this file on 2026-08-24. The original task-3 dispatch brief said "criteria 4, 5 and 6", copied
from this task's pre-revision text; round 3 had already moved criterion 7 here.

**One clause of criterion 7 is deliberately NOT tested here.** The criterion requires a corrupt
stored value to leave the drawer's Appearance section showing the Dark card *selected* rather
than neither card. The drawer does not exist until task 7, and its markup is not pinned by the
spec, so any selector written now would be a guess — and a guessed selector fails closed, which
is indistinguishable from the check being switched off. What IS tested here is the state that
clause depends on: `S.theme` validating to exactly `'dark'`, observable as `data-theme="dark"`.
Per §D5 the six selection values are ternaries on `S.theme`, so once that holds the Dark card
follows. The DOM half belongs with task 7 and must be written there.

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

REPO_ROOT = Path(__file__).resolve().parent.parent
PAGE_PATH = REPO_ROOT / "treko" / "Treko.dc.html"
NOCTURNE_PATH = REPO_ROOT / "treko" / "nocturne.css"
PAGE = PAGE_PATH.read_text()
NOCTURNE = NOCTURNE_PATH.read_text()

# Criterion 4's exception list, verbatim (docs/features/treko-theme-and-layout.md:700-702):
# "--font-*, --space-*, --radius-* and --mono. --color-section* may join the list only with the
# measured '0 readers' evidence attached." No --color-section* token appears in the reachable set
# computed below (matching §D3's own claim of 0 readers), so it is not added here — adding it
# without a token that actually needs it would be an unverified exception, not evidence.
#
# --mono joined that list on 2026-08-24 (commit 28933a1), resolving the gate task 3 raised: it is
# var()-reachable (33 uses) but is a monospace font stack with no light or dark form, and §D3's
# 51-property light block never declared it, so criterion 4 could not have passed against a
# correct implementation. It is exempt BY EXACT NAME, never as a "--mono-" prefix — the spec is
# explicit that a pattern would pre-approve tokens nobody has weighed.
EXEMPT_PREFIXES = ("--font-", "--space-", "--radius-")
EXEMPT_NAMES = ("--mono",)

LIGHT_BLOCK_RE = re.compile(r'body\[data-theme=(["\'])light\1\]\s*\{([^}]*)\}', re.DOTALL)
VAR_CALL_RE = re.compile(r'var\((--[A-Za-z0-9_-]+)\)')
CSS_RULE_RE = re.compile(r'([^{}]+)\{([^{}]*)\}')
CSS_CLASS_TOKEN_RE = re.compile(r'\.([A-Za-z_-][A-Za-z0-9_-]*)')
CSS_COMMENT_RE = re.compile(r'/\*.*?\*/', re.DOTALL)


# --------------------------------------------------------------------- criterion 4 helpers


def _direct_var_tokens(text):
    return set(VAR_CALL_RE.findall(text))


def _literal_classes(html):
    """Class names the page actually applies — skips template-only bindings like
    `class="{{ c.icon }}"` entirely (a naive per-token filter would let `c.icon` itself through,
    since neither `{` nor `}` survives on that one split token)."""
    classes = set()
    for match in re.finditer(r'class="([^"]*)"', html):
        value = match.group(1)
        if "{{" in value:
            continue
        classes.update(value.split())
    return classes


def _nocturne_rules():
    """[(selector, declarations), ...] — flat top-level rules only. Verified: `nocturne.css` has
    no `@media`/`@supports`/`@keyframes` and no nested rule, so a non-nested `{...}` split is
    exact, not an approximation."""
    text = CSS_COMMENT_RE.sub('', NOCTURNE)
    text = re.sub(r'@import[^;]*;', '', text)
    return CSS_RULE_RE.findall(text)


def _reachable_tokens():
    """Criterion 4's own definition: every `--name` inside a `var(--name)` in `Treko.dc.html`,
    plus every `--name` read by a `nocturne.css` rule whose selector matches a class the page
    uses."""
    reachable = _direct_var_tokens(PAGE)
    classes_used = _literal_classes(PAGE)
    for selector, declarations in _nocturne_rules():
        selector_classes = set(CSS_CLASS_TOKEN_RE.findall(selector))
        if selector_classes & classes_used:
            reachable |= _direct_var_tokens(declarations)
    return reachable


def _is_exempt(token):
    return token in EXEMPT_NAMES or any(token.startswith(prefix) for prefix in EXEMPT_PREFIXES)


def _declared_props(block_text):
    """`{name: value}` for every `--name: value;` pair in a CSS block's inner text."""
    props = {}
    for part in block_text.split(';'):
        part = part.strip()
        if not part or ':' not in part:
            continue
        name, _, value = part.partition(':')
        name = name.strip()
        if name.startswith('--'):
            props[name] = value.strip()
    return props


def _light_block():
    """The `body[data-theme="light"]` block's inner text, or None if it doesn't exist yet."""
    match = LIGHT_BLOCK_RE.search(PAGE)
    return match.group(2) if match else None


# --------------------------------------------------------------------- criterion 4


def test_criterion4_light_block_covers_every_reachable_custom_property():
    """docs/features/treko-theme-and-layout.md criterion 4 + §Verification "Criterion 4 — the
    light block's coverage".

    Was RED when written. At that commit: `body[data-theme="light"]` does not exist in `Treko.dc.html` at all,
    so every non-exempt reachable token is "missing" — this fails because the light block is
    absent, not because the reachable-token computation itself is broken (see the sanity assert
    below, which pins that the computation finds a plausible, non-trivial set today).
    """
    reachable = _reachable_tokens()
    non_exempt = {token for token in reachable if not _is_exempt(token)}

    # Sanity floor: confirms this scan is actually finding the page's real custom properties
    # (measured today: 40) rather than silently matching nothing and vacuously passing once a
    # light block exists.
    assert len(non_exempt) >= 20, (
        "only found %d non-exempt var()-reachable custom properties (%r) -- expected at least "
        "20 on this page; the scan itself looks broken, not the light block"
        % (len(non_exempt), sorted(non_exempt))
    )

    block_text = _light_block()
    assert block_text is not None, (
        "no body[data-theme=\"light\"] block exists in Treko.dc.html yet -- criterion 4 needs "
        "%d reachable custom properties declared there (task 3, second half): %s"
        % (len(non_exempt), ", ".join(sorted(non_exempt)))
    )

    declared = set(_declared_props(block_text))
    missing = sorted(non_exempt - declared)
    assert not missing, (
        "%d custom propert%s reachable via var() are not declared under "
        "body[data-theme=\"light\"]: %s"
        % (len(missing), "y is" if len(missing) == 1 else "ies are", ", ".join(missing))
    )


# --------------------------------------------------------------------- criterion 6


def test_criterion6_shadow_sm_and_shadow_lg_overridden_but_not_shadow_md():
    """docs/features/treko-theme-and-layout.md criterion 6.

    `--shadow-sm` and `--shadow-lg` must be overridden in light mode and must not contain the
    dark-mode ring hexes (#3f424d, #9397ab); `--shadow-md` must NOT be overridden (zero readers
    in this page — §D3, same reasoning that excluded `--panel`).

    Was RED when written. At that commit: no light block exists, so neither shadow token is overridden yet.
    """
    root_rule = next((decl for sel, decl in _nocturne_rules() if sel.strip() == ":root"), None)
    assert root_rule is not None, "nocturne.css has no :root rule to read dark shadow values from"
    dark = _declared_props(root_rule)
    assert "--shadow-sm" in dark and "--shadow-md" in dark and "--shadow-lg" in dark, (
        "nocturne.css :root is missing one of --shadow-sm/--shadow-md/--shadow-lg: %r" % dark
    )

    block_text = _light_block()
    assert block_text is not None, (
        "no body[data-theme=\"light\"] block exists in Treko.dc.html yet -- --shadow-sm "
        "(dark: %r) and --shadow-lg (dark: %r) must be overridden there (task 3, second half)"
        % (dark["--shadow-sm"], dark["--shadow-lg"])
    )
    light = _declared_props(block_text)

    for forbidden_hex in ("#3f424d", "#9397ab"):
        assert "--shadow-sm" in light, "--shadow-sm is not overridden under body[data-theme=light]"
        assert forbidden_hex not in light["--shadow-sm"].lower(), (
            "--shadow-sm's light value still contains the dark ring hex %s: %r"
            % (forbidden_hex, light["--shadow-sm"])
        )
        assert "--shadow-lg" in light, "--shadow-lg is not overridden under body[data-theme=light]"
        assert forbidden_hex not in light["--shadow-lg"].lower(), (
            "--shadow-lg's light value still contains the dark ring hex %s: %r"
            % (forbidden_hex, light["--shadow-lg"])
        )

    assert "--shadow-md" not in light, (
        "--shadow-md is overridden under body[data-theme=light] but has zero readers in this "
        "page (§D3) -- it should stay dark-hardcoded, like --panel"
    )


# --------------------------------------------------------------------- criterion 5 / Proof C


CONTRAST_CHECK_JS = """
(() => {
  function parseColor(str) {
    if (!str) return {r:0,g:0,b:0,a:0};
    const m = str.match(/rgba?\\(([^)]+)\\)/);
    if (!m) return {r:0,g:0,b:0,a:0};
    const parts = m[1].split(',').map(s => parseFloat(s.trim()));
    const a = parts.length > 3 ? parts[3] : 1;
    return {r: parts[0], g: parts[1], b: parts[2], a: a};
  }
  function compositeOver(fg, bg) {
    const a = fg.a;
    return { r: fg.r*a + bg.r*(1-a), g: fg.g*a + bg.g*(1-a), b: fg.b*a + bg.b*(1-a), a: 1 };
  }
  function effectiveBackground(el) {
    // Walk from el itself up through its ancestors; stop at the first fully opaque layer,
    // alpha-compositing every translucent layer crossed on the way (criterion 5's own words).
    const layers = [];
    let node = el;
    while (node && node.nodeType === 1) {
      const rgba = parseColor(getComputedStyle(node).backgroundColor);
      if (rgba.a > 0) {
        layers.push(rgba);
        if (rgba.a >= 0.999) break;
      }
      node = node.parentElement;
    }
    if (layers.length === 0) return {r:255,g:255,b:255,a:1};
    let result = layers[layers.length - 1];
    if (result.a < 0.999) result = compositeOver(result, {r:255,g:255,b:255,a:1});
    for (let i = layers.length - 2; i >= 0; i--) result = compositeOver(layers[i], result);
    return result;
  }
  function effectiveColor(el, bg) {
    const c = parseColor(getComputedStyle(el).color);
    if (c.a >= 0.999) return c;
    return compositeOver(c, bg);
  }
  function relLuminance(c) {
    const chan = v => { v /= 255; return v <= 0.03928 ? v/12.92 : Math.pow((v+0.055)/1.055, 2.4); };
    return 0.2126*chan(c.r) + 0.7152*chan(c.g) + 0.0722*chan(c.b);
  }
  function contrastRatio(c1, c2) {
    const L1 = relLuminance(c1), L2 = relLuminance(c2);
    const lighter = Math.max(L1, L2), darker = Math.min(L1, L2);
    return (lighter + 0.05) / (darker + 0.05);
  }
  function paintsText(el) {
    // Criterion 5's population: elements that paint a mark in their OWN color. `color` inherits,
    // so "has rendered area" is not the same thing -- a 7x7px decorative dot (Treko.dc.html:251)
    // reports an inherited foreground it never renders, and scoring it made the criterion
    // unsatisfiable by any palette. A direct, non-whitespace text node of its own...
    for (let i = 0; i < el.childNodes.length; i++) {
      const n = el.childNodes[i];
      if (n.nodeType === 3 && n.nodeValue && n.nodeValue.trim() !== '') return true;
    }
    // ...or a generated glyph: a Phosphor <i> has no text node but an icon font paints its
    // content in the element's color, so dropping these would under-measure, not over-narrow.
    const pseudos = ['::before', '::after'];
    for (let i = 0; i < pseudos.length; i++) {
      const content = getComputedStyle(el, pseudos[i]).content;
      if (content && content !== 'none' && content !== 'normal' && content !== '\\"\\"') return true;
    }
    return false;
  }
  const dataTheme = document.body.getAttribute('data-theme');
  const all = document.querySelectorAll('body *');
  let checked = 0, totalViolations = 0;
  const violations = [];
  all.forEach(el => {
    const rect = el.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return;
    if (!paintsText(el)) return;
    checked++;
    const bg = effectiveBackground(el);
    const fg = effectiveColor(el, bg);
    const ratio = contrastRatio(fg, bg);
    const fontSize = parseFloat(getComputedStyle(el).fontSize);
    const floor = isNaN(fontSize) ? 4.5 : (fontSize >= 18 ? 3.0 : 4.5);
    if (ratio < floor) {
      totalViolations++;
      if (violations.length < 25) {
        violations.push({
          tag: el.tagName,
          cls: (el.className && el.className.toString) ? el.className.toString().slice(0, 60) : '',
          id: el.id || '',
          color: 'rgba(' + fg.r + ',' + fg.g + ',' + fg.b + ',' + fg.a + ')',
          bg: 'rgba(' + bg.r + ',' + bg.g + ',' + bg.b + ',' + bg.a + ')',
          ratio: Math.round(ratio * 100) / 100,
          floor: floor,
          fontSize: fontSize
        });
      }
    }
  });
  return { dataTheme: dataTheme, elementCount: checked, violationCount: totalViolations,
           violations: violations };
})()
"""


def _wait_for_mount(chrome, timeout=15):
    """Poll until DCLogic has rendered the real board, not the loading/missing placeholder.
    Both placeholders render a handful of elements; the mounted board renders hundreds (measured
    on this exact page: 848 visible elements) -- a low, generous floor tells 'not mounted yet'
    from 'mounted' apart without hardcoding a selector into React's internals."""
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


def test_criterion5_light_mode_contrast_meets_wcag(srv, tmp_path):
    """docs/features/treko-theme-and-layout.md criterion 5, via §Verification "Proof C".

    Renders the real page in headless Chrome (pinned build: cdp_harness.PINNED_VERSION), applies
    the light theme exactly the way the app would -- `taskTracker.theme` seeded into
    `localStorage` *before* a reload, never `data-theme` set directly -- then reads resolved
    `getComputedStyle()` for every element with non-zero rendered area and asserts WCAG contrast
    >= 4.5:1 (>= 3:1 at/above an 18px resolved font-size) against the effective, alpha-composited
    background.

    Only elements that paint a mark in their own `color` are scored -- see `paintsText` in
    CONTRAST_CHECK_JS for why, and criterion 5 for the rule it implements.

    Was still RED after `af5321a`, at the time this docstring was written -- for a different
    reason than before, and deliberately so. The precondition held: the light block, the
    validated seed and `applyTheme` all existed, so `data-theme` did become "light". What failed
    was the contrast assertion itself -- 127 violations across four light-palette text tokens,
    worst 1.64:1. Those were real defects and **task 4 owned them**, not task 3: criterion 5 is a
    card-level criterion and the fix is a palette redesign rather than wiring (§Verification,
    "Task 3 second half"). Do not chase this green by editing the assertion, the floors, or
    paintsText.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        chrome.navigate(url)
        _wait_for_mount(chrome)

        # Proof C step 3: set localStorage, THEN reload -- never set the attribute directly.
        # This is what makes the check exercise the app's own seed/mount logic instead of
        # simulating its result.
        chrome.evaluate("localStorage.setItem('taskTracker.theme','light')")
        assert chrome.evaluate("localStorage.getItem('taskTracker.theme')") == "light"
        chrome.reload()
        mount_count = _wait_for_mount(chrome)

        result = chrome.evaluate(CONTRAST_CHECK_JS)

        # Sanity floor first, regardless of theme state: a check that silently found nothing
        # would vacuously pass. Of the 848 elements with rendered area on this exact page, 367
        # paint a mark in their own color and are therefore scored (criterion 5's population);
        # 200 is a wide margin under that and a tight one over "the walk found basically
        # nothing." It also guards the narrowing itself: a paintsText() that wrongly returned
        # false everywhere would collapse this count rather than vacuously pass.
        assert result["elementCount"] >= 200, (
            "contrast check only found %d elements with non-zero rendered area (mount poll saw "
            "%d body descendants) -- too few to be the real board; the element walk itself is "
            "broken, not the theme" % (result["elementCount"], mount_count)
        )

        assert result["dataTheme"] == "light", (
            "expected body[data-theme=\"light\"] after seeding localStorage."
            "taskTracker.theme='light' and reloading -- got %r. The light theme does not exist "
            "yet (task 3, second half): nothing reads taskTracker.theme or calls "
            "setAttribute('data-theme', ...), so the attribute is never set."
            % result["dataTheme"]
        )

        assert result["violationCount"] == 0, (
            "%d element(s) fail WCAG contrast under data-theme=light:\n%s"
            % (result["violationCount"], json.dumps(result["violations"], indent=2))
        )
    finally:
        chrome.close()


# --------------------------------------------------------------------- criterion 7


# Values a user, a browser extension, or an older build could leave in `taskTracker.theme`.
# Every one of them is outside the closed set {'dark','light'} and must therefore yield dark.
# 'Dark' and 'LIGHT' are here on purpose: the spec's seed compares with `===` against the exact
# lowercase literal, so a case variant is corrupt input, not a near-miss to be helpfully coerced.
CORRUPT_STORED_THEMES = ["banana", "Dark", "LIGHT", "true", "", "null", "{}", "0", "light "]


def _seed_theme_and_reload(chrome, url, value):
    """Put `value` in `taskTracker.theme` the way a real user's browser would, then reload so the
    page's own mount-time seed reads it. Never sets `data-theme` directly -- that would test the
    assertion instead of the code under it."""
    chrome.navigate(url)
    _wait_for_mount(chrome)
    chrome.evaluate("localStorage.setItem('taskTracker.theme', %s)" % json.dumps(value))
    assert chrome.evaluate("localStorage.getItem('taskTracker.theme')") == value
    chrome.reload()
    return _wait_for_mount(chrome)


@pytest.mark.parametrize("stored", CORRUPT_STORED_THEMES)
def test_criterion7_corrupt_stored_theme_yields_dark(srv, tmp_path, stored):
    """docs/features/treko-theme-and-layout.md criterion 7, the corrupt-stored-theme clause, and
    §D3 "The seed, validated at mount".

    §D3's seed is `(t => t === 'light' ? 'light' : THEME_DEFAULT)(ls('taskTracker.theme'))`, so
    anything that is not the exact string 'light' must fall to 'dark'. This is the boundary
    validation `rules/core-conduct.md` requires: `localStorage` is user-editable input crossing a
    system boundary, and the prototype's `||` seed only substitutes for null/'' -- every other
    string passes straight through into `setAttribute('data-theme', ...)`.

    Was RED when written. At that commit: nothing reads `taskTracker.theme` and nothing calls
    `setAttribute('data-theme', ...)` -- `data-theme` has 0 occurrences in `Treko.dc.html`. So
    `data-theme` is absent (None), not 'dark'. It fails on the missing seed, not on a wrong
    validation result. The mount assertion below runs first and passes against the untouched dark
    page, proving the harness reached a real board rather than a blank document.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        mount_count = _seed_theme_and_reload(chrome, url, stored)

        assert mount_count > 50, (
            "board never mounted with taskTracker.theme=%r (%d body descendants) -- a corrupt "
            "stored value must not be able to stop the page rendering" % (stored, mount_count)
        )

        applied = chrome.evaluate("document.body.getAttribute('data-theme')")
        assert applied == "dark", (
            "taskTracker.theme=%r is outside the closed set {'dark','light'} and must yield "
            "data-theme=\"dark\" -- got %r instead: the validated seed did not fall back to "
            "THEME_DEFAULT for an invalid stored value." % (stored, applied)
        )
    finally:
        chrome.close()


def test_criterion7_theme_survives_a_reload(srv, tmp_path):
    """docs/features/treko-theme-and-layout.md criterion 7, the persistence clause.

    A legitimately stored 'light' must still be light after a reload -- the paired positive case
    that stops the corrupt-value tests above from passing vacuously. A seed hardwired to 'dark'
    would satisfy every parametrised case in this file and fail only here.

    Was RED when written. At that commit: no light block and no seed, so `data-theme` is absent.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        url = "http://127.0.0.1:%d/" % srv.port
        _seed_theme_and_reload(chrome, url, "light")

        applied = chrome.evaluate("document.body.getAttribute('data-theme')")
        assert applied == "light", (
            "a stored taskTracker.theme='light' must survive a reload as data-theme=\"light\" -- "
            "got %r. Without this case the corrupt-value tests would all pass against a seed "
            "hardwired to 'dark'." % applied
        )

        # Reload once more: persistence must be a property of the stored value, not of the
        # single transition that wrote it.
        chrome.reload()
        _wait_for_mount(chrome)
        again = chrome.evaluate("document.body.getAttribute('data-theme')")
        assert again == "light", (
            "data-theme was %r after a second reload -- the theme is not persisting, it is "
            "surviving exactly one round trip" % again
        )
    finally:
        chrome.close()


# Poisons `localStorage` before any page script runs: every access throws, which is what a
# browser does with storage disabled or a cross-origin/private-mode restriction in force.
# `configurable: true` keeps the override itself from being the thing that breaks teardown.
POISON_LOCALSTORAGE_JS = """
Object.defineProperty(window, 'localStorage', {
  configurable: true,
  get() { throw new DOMException('localStorage is unavailable', 'SecurityError'); }
});
"""


def test_criterion7_unavailable_localstorage_yields_dark_without_throwing(srv, tmp_path):
    """docs/features/treko-theme-and-layout.md criterion 7: "an unavailable `localStorage` yields
    dark mode without throwing", and §D3's "The `try/catch` is kept".

    Installed via `Page.addScriptToEvaluateOnNewDocument` so the poison is in place *before* the
    page's seed runs -- setting it after load would be too late to test a mount-time read.

    Was RED when written. At that commit: `data-theme` is never set at all, so the attribute is absent rather
    than 'dark'. The board-still-mounts assertion runs first and is expected to PASS even today,
    which is the point of ordering it first: it separates "the page survived" from "the page
    chose dark", and only the second half is waiting on task 3's implementation.
    """
    chrome = cdp_harness.Chrome(str(tmp_path / "chrome-profile"))
    try:
        chrome.add_startup_script(POISON_LOCALSTORAGE_JS)
        chrome.navigate("http://127.0.0.1:%d/" % srv.port)
        mount_count = _wait_for_mount(chrome)

        # Confirm the poison is actually armed -- a check that silently failed to install would
        # make this whole test a second copy of the plain-mount case.
        threw = chrome.evaluate(
            "(() => { try { window.localStorage; return false; } catch (e) { return true; } })()"
        )
        assert threw is True, (
            "localStorage did not throw on access -- the startup poison never installed, so "
            "this test is not exercising the unavailable-storage path at all"
        )

        assert mount_count > 50, (
            "board rendered only %d body descendants with localStorage throwing -- the seed's "
            "try/catch is missing and the unavailable-storage case takes the page down"
            % mount_count
        )

        applied = chrome.evaluate("document.body.getAttribute('data-theme')")
        assert applied == "dark", (
            "with localStorage unavailable the page must still apply data-theme=\"dark\" -- got "
            "%r. Nothing calls setAttribute('data-theme', ...) yet (task 3, second half)."
            % applied
        )
    finally:
        chrome.close()
