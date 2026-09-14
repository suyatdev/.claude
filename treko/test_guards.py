"""Regression guards — card A (`docs/features/treko-theme-and-layout.md`) task 8, criteria
15, 16 and 17. §Risks "Hazard 1" is the failure mode criteria 15/16 exist to catch: adding a
`'settings'` id to `TRACKER_COMMAND_IDS` is "the obvious way to get a gear button into a row
that already renders buttons", and it would also break the node load because the fence would
then reach a DOM concern.

**Criterion 15 — `Treko.dc.html:325-418` at the base commit names the marker-INCLUSIVE
span, not the node loader's span.** Correction to an earlier draft of this docstring, which
claimed the card's 4851-byte figure "does not match" `test_ui_commands.py`'s own extraction
and was wrong to say so. Checked directly: `git show a5a66a7:treko/Treko.dc.html | grep -n
"node-loadable slice"` returns `325:...begins...` / `418:...ends...` — at the base commit,
lines 325 and 418 ARE the two fence marker comment lines. So the card's literal citation
`:325-418` names the span *from the first byte of the START marker line through the last
byte of the END marker line* — the two marker comments are IN the criterion's span, not
outside it. Line numbers are still the wrong *locator* on this branch (tasks 2-4 shifted the
fence to `:348-441`, checked with `grep -n` before writing this file) — this module still
locates the region by the literal fence comments — `// <<< tracker-command-handler:
node-loadable slice begins >>>` / `// <<< ... slice ends >>>` — never by line number. What
changed is which *span*, once located, the guard is required to compare.

**Three distinct spans were independently re-derived, byte-for-byte, against
`git show a5a66a7:treko/Treko.dc.html` and the current working tree; all three reproduce
identically at both points** — i.e. nothing inside any of them has drifted since the base
commit:

* **Marker-inclusive** — from the first byte of the START marker line through the last byte
  of the END marker line, including its trailing newline. This is what the criterion's
  `:325-418` names, and this guard's PRIMARY assertion (`extract_fence`, below):
  **4851 bytes**, sha256 `f0a37389f08f31dfdf18a0a1676657919a01272746d5ab28dbd65a53dae7c136`.
* **NODE_BRIDGE-style** — `html.slice(html.indexOf(START) + START.length, html.indexOf(END))`,
  a byte offset with no line awareness. This is the literal slice
  `test_ui_commands.py:68-87`'s `NODE_BRIDGE.loadHandler` writes to a temp `.js` and
  `require()`s — the span the running system actually depends on being loadable, not the span
  the criterion names. Kept here as a SECONDARY, explicitly-subsumed check
  (`extract_fence_node_bridge`, below): **4728 bytes**, sha256
  `1aa22b5f01d1d4a5e42d328496c08bc46fa260fe35c5b40cdb0a9d77cdb2139b`.
* **Line-based exclusive** — every full line strictly between the two marker lines, both
  marker lines dropped, rejoined with `\n`. Recorded here for completeness only, because an
  earlier draft of this file conflated it with the NODE_BRIDGE figure; it is one byte lower,
  because the `\n` immediately after the START marker line survives `NODE_BRIDGE`'s
  byte-offset slice but is stripped by a line-based cut: **4727 bytes**, sha256
  `5409d62e91d402fa2085d2974d9343067fd38b2c6248db8f1f90fdf80b222d08`. No test below asserts
  against this figure — it is not a span anything in this repo actually consumes; it exists
  in this docstring solely so the next reader does not re-derive it and wonder why it is one
  byte off from the other two.

**Why the guard's primary assertion is the inclusive span, not the node-bridge span.** The
inclusive span is strictly stronger: it also covers the two marker comments themselves, which
`NODE_BRIDGE.loadHandler` depends on to find the slice at all. A rename or reflow of a marker
comment breaks the node loader while — if the exclusive check locates the region the same way
NODE_BRIDGE does, by searching for the exact marker text — *also* breaking that check's own
detection, rather than leaving it silently agreeing. What was actually observed when this was
tried, and reported without adjusting it to fit the tidier "inclusive catches, exclusive
misses" story: see `test_criterion15_marker_text_mutation_is_reported_honestly`, below.

**What criterion 15's tests do NOT prove:** that the sliced region is *correct*, only that it
has not changed since the base commit. `test_ui_commands.py`'s own suite is what proves the
handler behaves correctly against every row of §Design 3's failure table.

**Criterion 16** is checked by extracting `TRACKER_COMMAND_IDS` as source text (no browser or
node needed) and confirming the two render sites (`cmdButtons`, `cmdCopies`) still `.map()`
over that same array — the same static-text approach `test_theme.py` already uses for
criterion 4's reachability check, chosen over headless Chrome per this task's own guidance to
prefer a text-based check when one suffices.

**Criterion 17** is a text-based scan (see `find_external_fetches` below) of
`Treko.dc.html`, `nocturne.css`, and every vendored `.css`, plus a source check of the CSP and
`STATIC_MANIFEST` in `server.py`. It does not launch a browser or fetch anything over the
network — it only inspects literal fetching-position targets in the source text.

**The match is case-insensitive on purpose.** HTML attribute names (`HREF=`, `SRC=`) and CSS
function/at-rule names (`URL(`, `@IMPORT`) are case-insensitive per spec, so a case-sensitive
pattern would silently miss a literal `<LINK HREF="https://...">` or `URL(https://...)`. An
independent 17-case probe against an earlier, case-sensitive version of this scan found
exactly this gap — `<LINK HREF=...>`, `<script SRC=...>`, CSS `URL(...)`, and `@IMPORT` all
went unflagged — and it is fixed with `re.IGNORECASE` on all three fetching-position regexes,
with those four cases now permanent falsifiers (below). The same probe confirmed
protocol-relative `//...` URLs, quote and whitespace variation inside `url()`, and the bare
`@import "...";` form (no `url()` wrapper) were already caught, and that `data:` URIs,
fragment `href`s, relative paths, and bare URLs mentioned only in comment prose were already
correctly left alone.

**A commented-out fetching construct still fires, deliberately, not by accident.**
`/* @import url(https://...); */` and `<!-- <script src="https://..."></script> -->` both
still count as hits. This is a supply-chain guard, not a renderer — a commented-out CDN
reference in a vendored file is worth a human's attention, and stripping comments before
scanning would create exactly the place to hide one that this check exists to close. This is
also the precise distinction that makes
`test_criterion17_inter_provenance_comment_is_not_a_false_positive` a meaningful test rather
than a tautology: `vendor/inter/inter.css:3` passes not because it is inside a comment, but
because it states the URL as bare prose with no `url()`/`src=`/`href=`/`@import` construct
around it — a fetching construct inside that same comment would still be flagged.

Every check below ships with an explicit falsifier: a mutation the check must catch, applied
to an in-memory copy of the real text and never written back to disk. See each test's
docstring and the parametrized "falsifiers_are_caught" tests for the case list.
"""

import re
import sys
from hashlib import sha256
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
TREKO_DIR = REPO_ROOT / "treko"
HTML_PATH = TREKO_DIR / "Treko.dc.html"
NOCTURNE_PATH = TREKO_DIR / "nocturne.css"
VENDOR_DIR = TREKO_DIR / "vendor"
INTER_CSS_PATH = VENDOR_DIR / "inter" / "inter.css"

BASE_COMMIT = "a5a66a75204f334fff09462e931981431b39081a"

sys.path.insert(0, str(TREKO_DIR))
import server  # noqa: E402  (path shim above must run first, same pattern as test_server.py)


# ===========================================================================================
# Criterion 15 — the node-loadable slice is byte-identical to its base-commit form
# ===========================================================================================

FENCE_START = b"// <<< tracker-command-handler: node-loadable slice begins >>>"
FENCE_END = b"// <<< tracker-command-handler: node-loadable slice ends >>>"

# PRIMARY: the marker-inclusive span the criterion's `:325-418` literally names (verified:
# at the base commit those ARE the two marker lines). See the module docstring for the full
# derivation and for the two other spans that were also re-derived and rejected as the
# primary assertion.
BASE_FENCE_BYTES = 4851
BASE_FENCE_SHA256 = "f0a37389f08f31dfdf18a0a1676657919a01272746d5ab28dbd65a53dae7c136"

# SECONDARY, explicitly subsumed: the span `test_ui_commands.py`'s NODE_BRIDGE.loadHandler
# actually require()s. Retained because it is the span the running system depends on being
# loadable -- not retained as an alternative primary assertion.
BASE_FENCE_NODE_BRIDGE_BYTES = 4728
BASE_FENCE_NODE_BRIDGE_SHA256 = "1aa22b5f01d1d4a5e42d328496c08bc46fa260fe35c5b40cdb0a9d77cdb2139b"


def _locate_markers(html_bytes):
    """Shared marker lookup for both extractors below. Raises AssertionError if the markers
    are missing, duplicated, or out of order -- the same failure NODE_BRIDGE.loadHandler
    raises for a malformed fence."""
    starts = html_bytes.count(FENCE_START)
    ends = html_bytes.count(FENCE_END)
    if starts != 1 or ends != 1:
        raise AssertionError(
            "expected exactly one marker pair, found %d start / %d end" % (starts, ends))
    start_index = html_bytes.index(FENCE_START)
    end_index = html_bytes.index(FENCE_END)
    if end_index < start_index:
        raise AssertionError("end marker precedes start marker")
    return start_index, end_index


def extract_fence(html_bytes):
    """PRIMARY. Slice out the marker-INCLUSIVE region the criterion's `Treko.dc.html:325-418`
    names: from the first byte of the START marker line through the last byte of the END
    marker line, including its trailing newline (dropped only if the file happens to end
    there, which it does not in practice).

    This is strictly stronger than `extract_fence_node_bridge` below: it also guards the two
    fence comments themselves, which the node loader depends on to find the slice at all.
    """
    start_index, end_index = _locate_markers(html_bytes)
    end_of_end_marker = end_index + len(FENCE_END)
    if html_bytes[end_of_end_marker:end_of_end_marker + 1] == b"\n":
        end_of_end_marker += 1
    return html_bytes[start_index:end_of_end_marker]


def extract_fence_node_bridge(html_bytes):
    """SECONDARY. Slice out the marker-EXCLUSIVE region, matching `test_ui_commands.py`'s
    NODE_BRIDGE `loadHandler` exactly: the bytes strictly *between* the two marker lines,
    excluding the marker comments themselves -- what is actually written to the temp `.js`
    and `require()`d. Kept as a documented secondary check, subsumed by `extract_fence`
    above, never as a substitute for it.
    """
    start_index, end_index = _locate_markers(html_bytes)
    return html_bytes[start_index + len(FENCE_START):end_index]


def _fence_measurements(html_bytes):
    region = extract_fence(html_bytes)
    return len(region), sha256(region).hexdigest()


def _fence_measurements_node_bridge(html_bytes):
    region = extract_fence_node_bridge(html_bytes)
    return len(region), sha256(region).hexdigest()


def test_criterion15_fence_region_byte_identical_to_base_commit():
    """Criterion 15, PRIMARY assertion. Proves the marker-inclusive node-loadable slice in
    the working tree is byte-identical to its form at the base commit, located by fence
    marker rather than by the card's `:325-418` (accurate only at the base commit; on this
    branch the markers are at `:348-441`, per `grep -n` on this file).

    Does NOT prove the slice is *correct* — see the module docstring.
    """
    current_bytes, current_digest = _fence_measurements(HTML_PATH.read_bytes())
    assert (current_bytes, current_digest) == (BASE_FENCE_BYTES, BASE_FENCE_SHA256), (
        "node-loadable fence (marker-inclusive) drifted from base commit %s: "
        "expected %d bytes / %s, got %d bytes / %s" % (
            BASE_COMMIT, BASE_FENCE_BYTES, BASE_FENCE_SHA256, current_bytes, current_digest))


def test_criterion15_node_bridge_span_also_matches_base_commit_secondary():
    """Criterion 15, SECONDARY assertion. The span NODE_BRIDGE.loadHandler actually
    `require()`s is also unchanged since the base commit. This does not widen what criterion
    15 covers beyond the primary (inclusive) test above -- it is retained because it is the
    span the running system depends on, and a future change could in principle touch it while
    leaving the inclusive digest agreeing only by accident of where the marker lines fall."""
    current_bytes, current_digest = _fence_measurements_node_bridge(HTML_PATH.read_bytes())
    assert (current_bytes, current_digest) == (
        BASE_FENCE_NODE_BRIDGE_BYTES, BASE_FENCE_NODE_BRIDGE_SHA256), (
        "node-loadable fence (NODE_BRIDGE span) drifted from base commit %s: "
        "expected %d bytes / %s, got %d bytes / %s" % (
            BASE_COMMIT, BASE_FENCE_NODE_BRIDGE_BYTES, BASE_FENCE_NODE_BRIDGE_SHA256,
            current_bytes, current_digest))


def _flip_one_byte_inside_fence(html_bytes):
    s = html_bytes.index(FENCE_START) + len(FENCE_START)
    e = html_bytes.index(FENCE_END)
    mid = s + (e - s) // 2
    flipped = html_bytes[mid] ^ 0x01
    return html_bytes[:mid] + bytes([flipped]) + html_bytes[mid + 1:]


def _add_line_inside_fence(html_bytes):
    s = html_bytes.index(FENCE_START) + len(FENCE_START)
    insertion = b"\n// regression-guard falsifier: an added line\n"
    return html_bytes[:s] + insertion + html_bytes[s:]


def _append_settings_id(html_bytes):
    original = b"var TRACKER_COMMAND_IDS=['clear','handoff','reanalyze'];"
    mutated = b"var TRACKER_COMMAND_IDS=['clear','handoff','reanalyze','settings'];"
    assert html_bytes.count(original) == 1, "fixture literal not found or not unique"
    return html_bytes.replace(original, mutated)


FENCE_FALSIFIERS = [
    (_flip_one_byte_inside_fence, "one-byte edit inside the fence"),
    (_add_line_inside_fence, "a line added inside the fence"),
    (_append_settings_id, "'settings' id appended to TRACKER_COMMAND_IDS (Hazard 1)"),
]


@pytest.mark.parametrize("mutate,label", FENCE_FALSIFIERS, ids=[l for _, l in FENCE_FALSIFIERS])
def test_criterion15_falsifiers_are_caught(mutate, label):
    """Every mutator above must actually change the bytes it claims to, and the PRIMARY
    (inclusive) fence check must then disagree with the recorded base-commit measurement. A
    falsifier that silently no-ops, or a check that still agrees after mutation, means the
    guard cannot fail."""
    base = HTML_PATH.read_bytes()
    mutated = mutate(base)
    assert mutated != base, "falsifier %r produced no change to the bytes" % (label,)
    mutated_measurements = _fence_measurements(mutated)
    assert mutated_measurements != (BASE_FENCE_BYTES, BASE_FENCE_SHA256), (
        "falsifier %r was NOT caught -- the fence check cannot fail" % (label,))


def _rename_marker_word(html_bytes):
    original_line = b"// <<< tracker-command-handler: node-loadable slice begins >>>"
    mutated_line = b"// <<< tracker-command-handler: node-loadable slice starts >>>"
    assert html_bytes.count(original_line) == 1, "fixture literal not found or not unique"
    return html_bytes.replace(original_line, mutated_line)


def test_criterion15_marker_text_mutation_is_reported_honestly():
    """Falsifier requested for criterion 15: mutate the START marker comment's own text
    ('begins' -> 'starts') and report what each extractor actually does with it, without
    assuming the tidy "inclusive catches it, exclusive silently misses it" story.

    Both `extract_fence` (primary/inclusive) and `extract_fence_node_bridge`
    (secondary/exclusive) locate the fence the same way NODE_BRIDGE.loadHandler itself does:
    by searching for the exact marker-line bytes. Renaming the marker word makes FENCE_START
    match zero times in the mutated text, so BOTH extractors raise the same "found 0 start
    markers" AssertionError -- neither produces a silently-agreeing digest. There is no case
    here where the exclusive check misses the mutation while the inclusive one catches it;
    a corrupted marker breaks detection for both equally, which is reported as observed
    rather than engineered into the anticipated asymmetric shape.
    """
    base = HTML_PATH.read_bytes()
    mutated = _rename_marker_word(base)
    assert mutated != base, "marker-word falsifier produced no change to the bytes"

    with pytest.raises(AssertionError, match="found 0 start"):
        extract_fence(mutated)
    with pytest.raises(AssertionError, match="found 0 start"):
        extract_fence_node_bridge(mutated)


# ===========================================================================================
# Criterion 16 — TRACKER_COMMAND_IDS is exactly ['clear','handoff','reanalyze'], and
# cmdButtons/cmdCopies still map over that same array
# ===========================================================================================

COMMAND_IDS_RE = re.compile(r"var TRACKER_COMMAND_IDS=\[(.*?)\];")
CMD_BUTTONS_RE = re.compile(r"cmdButtons:\(hasChannel&&view\.offersButton\)\?TRACKER_COMMAND_IDS\.map\(")
CMD_COPIES_RE = re.compile(r"cmdCopies:showCopies\?TRACKER_COMMAND_IDS\.map\(")

EXPECTED_COMMAND_IDS = ["clear", "handoff", "reanalyze"]


def extract_command_ids(text):
    """Pull the `TRACKER_COMMAND_IDS` array literal's string entries out of source text.

    Text-based on purpose: the array is a plain JS literal (`Treko.dc.html:356` on this
    branch), so no node/browser round-trip is needed to read it.
    """
    match = COMMAND_IDS_RE.search(text)
    if not match:
        raise AssertionError("TRACKER_COMMAND_IDS declaration not found")
    return re.findall(r"'([^']*)'", match.group(1))


def test_criterion16_command_ids_unchanged():
    """Criterion 16, first half. `TRACKER_COMMAND_IDS` is still exactly the three ids the card
    pins. Does not prove anything about what the ids render to on screen -- that is the
    second half, below."""
    ids = extract_command_ids(HTML_PATH.read_text())
    assert ids == EXPECTED_COMMAND_IDS, (
        "TRACKER_COMMAND_IDS is %r, expected %r" % (ids, EXPECTED_COMMAND_IDS))


def test_criterion16_cmdButtons_and_cmdCopies_map_the_same_three_ids():
    """Criterion 16, second half. `cmdButtons` and `cmdCopies` both still `.map()` directly
    over `TRACKER_COMMAND_IDS` (`Treko.dc.html:515` and `:519` on this branch) rather than a
    second, independently-maintained list -- so once the first half confirms the array's
    contents, both render sites are proven to render the same three rows they render today
    without needing a live DOM render to check it.

    Does NOT prove the rendered pixels are unchanged (no style/markup byte comparison here);
    only that the two render sites still draw from the one pinned array.
    """
    text = HTML_PATH.read_text()
    assert CMD_BUTTONS_RE.search(text), (
        "cmdButtons no longer maps TRACKER_COMMAND_IDS the same way -- source snippet: %r"
        % (text[text.find("cmdButtons:"):text.find("cmdButtons:") + 80],))
    assert CMD_COPIES_RE.search(text), (
        "cmdCopies no longer maps TRACKER_COMMAND_IDS the same way -- source snippet: %r"
        % (text[text.find("cmdCopies:"):text.find("cmdCopies:") + 80],))


def _append_fourth_id(text):
    original = "var TRACKER_COMMAND_IDS=['clear','handoff','reanalyze'];"
    mutated = "var TRACKER_COMMAND_IDS=['clear','handoff','reanalyze','settings'];"
    assert text.count(original) == 1, "fixture literal not found or not unique"
    return text.replace(original, mutated)


def _rename_an_id(text):
    original = "var TRACKER_COMMAND_IDS=['clear','handoff','reanalyze'];"
    mutated = "var TRACKER_COMMAND_IDS=['clear','handoffx','reanalyze'];"
    assert text.count(original) == 1, "fixture literal not found or not unique"
    return text.replace(original, mutated)


ID_FALSIFIERS = [
    (_append_fourth_id, "a fourth id appended"),
    (_rename_an_id, "an id renamed ('handoff' -> 'handoffx')"),
]


@pytest.mark.parametrize("mutate,label", ID_FALSIFIERS, ids=[l for _, l in ID_FALSIFIERS])
def test_criterion16_falsifiers_are_caught(mutate, label):
    text = HTML_PATH.read_text()
    mutated = mutate(text)
    assert mutated != text, "falsifier %r produced no change" % (label,)
    ids = extract_command_ids(mutated)
    assert ids != EXPECTED_COMMAND_IDS, (
        "falsifier %r was NOT caught -- got ids %r, the check cannot fail" % (label, ids))


# ===========================================================================================
# Criterion 17 — no CDN URL in a fetching position
# ===========================================================================================

EXTERNAL_SCHEME_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.\-]*://")
# IGNORECASE on all three: HTML attribute names (`HREF=`, `SRC=`) and CSS function/at-rule
# names (`URL(`, `@IMPORT`) are case-insensitive per spec, so a case-sensitive pattern here
# would silently miss a literal <LINK HREF="https://..."> or a CSS `URL(https://...)`.
URL_FN_RE = re.compile(r"url\(\s*(['\"]?)([^'\")]+)\1\s*\)", re.IGNORECASE)
HTML_ATTR_RE = re.compile(r"\b(?:src|href)\s*=\s*([\"'])([^\"']*)\1", re.IGNORECASE)
IMPORT_BARE_RE = re.compile(r"@import\s+([\"'])([^\"']+)\1\s*;", re.IGNORECASE)

FETCH_POSITION_REGEXES = (
    (URL_FN_RE, "url()"),
    (HTML_ATTR_RE, "src/href attribute"),
    (IMPORT_BARE_RE, "@import (bare string form)"),
)


def is_fetching_external(target):
    """True if `target` is a literal URL that would cause a live external network fetch.

    `data:` URIs are inline, not a fetch. `{{ ... }}` is a page template binding whose real
    value is not present in the source text -- treating it as external would be a guess, and
    a guessed verdict fails closed the same way a guessed schema field does (no such binding
    exists in Treko.dc.html today; the one templated `href` in the file, `{{ t.prHref }}`, is
    filtered out here rather than by exemption-listing that one string).
    """
    if not target:
        return False
    if "{{" in target:
        return False
    if target.startswith("data:"):
        return False
    if target.startswith("//"):
        return True  # protocol-relative -- still an external fetch
    return bool(EXTERNAL_SCHEME_RE.match(target))


def find_external_fetches(text):
    """Every literal fetching-position target in `text` with an external scheme.

    Covers CSS `url(...)` (which also matches `@import url(...)`), HTML `src=`/`href=`
    attributes, and the bare-string `@import "...";` form. Returns a list of (kind, target)
    pairs; an empty list means the text is clean.
    """
    hits = []
    for regex, kind in FETCH_POSITION_REGEXES:
        for match in regex.finditer(text):
            target = match.group(2)
            if is_fetching_external(target):
                hits.append((kind, target))
    return hits


def vendor_css_files():
    return sorted(VENDOR_DIR.rglob("*.css"))


def test_criterion17_no_external_fetch_in_treko_html():
    hits = find_external_fetches(HTML_PATH.read_text())
    assert hits == [], "external fetch targets found in Treko.dc.html: %r" % (hits,)


def test_criterion17_no_external_fetch_in_nocturne_css():
    hits = find_external_fetches(NOCTURNE_PATH.read_text())
    assert hits == [], "external fetch targets found in nocturne.css: %r" % (hits,)


def test_criterion17_no_external_fetch_in_vendored_css():
    files = vendor_css_files()
    assert files, "no vendored .css files found under treko/vendor/ -- check the glob"
    all_hits = []
    for path in files:
        for kind, target in find_external_fetches(path.read_text()):
            all_hits.append((str(path.relative_to(REPO_ROOT)), kind, target))
    assert all_hits == [], "external fetch targets found in vendored CSS: %r" % (all_hits,)


def test_criterion17_inter_provenance_comment_is_not_a_false_positive():
    """The comment at `vendor/inter/inter.css:3` names a Google Fonts URL as plain prose
    documenting where the vendored file was fetched from. It is a documented non-hit: this
    test proves the scan does not flag it, guarding against a naive regex (e.g. one that
    matches any 'https://...' substring regardless of position) that would."""
    inter_css = INTER_CSS_PATH.read_text()
    assert "fonts.googleapis.com" in inter_css, (
        "the provenance comment moved or was deleted from inter.css -- re-point this test")
    hits = find_external_fetches(inter_css)
    assert hits == [], (
        "the provenance comment (or something else) in inter.css false-positived: %r" % (hits,))


FETCH_FALSIFIERS = [
    (lambda t: t + "\n@import url(https://fonts.googleapis.com/css2?family=Inter);\n",
     "@import url(https://...) added"),
    (lambda t: t + '\n<img src="https://cdn.example/x.png">\n', 'img src="https://cdn.example/..." added'),
    (lambda t: t + "\n.x{background:url(https://cdn.example/bg.png)}\n",
     "CSS url(https://...) property added"),
    # Case-insensitivity regression guards. An independent probe found these four unflagged
    # against an earlier, case-sensitive version of URL_FN_RE/HTML_ATTR_RE/IMPORT_BARE_RE --
    # permanent cases so a future edit cannot silently reintroduce the gap (see the module
    # docstring, "The match is case-insensitive on purpose").
    (lambda t: t + '\n<LINK HREF="https://cdn.example/x.css">\n', '<LINK HREF="https://...">  (uppercase attribute name)'),
    (lambda t: t + '\n<script SRC="https://cdn.example/a.js"></script>\n',
     '<script SRC="https://...">  (uppercase attribute name)'),
    (lambda t: t + "\n.x{background:URL(https://cdn.example/bg.png)}\n",
     "CSS URL(https://...) property  (uppercase function name)"),
    (lambda t: t + "\n@IMPORT url(https://fonts.googleapis.com/css2);\n",
     "@IMPORT url(https://...);  (uppercase at-rule name)"),
]


@pytest.mark.parametrize("mutate,label", FETCH_FALSIFIERS, ids=[l for _, l in FETCH_FALSIFIERS])
def test_criterion17_falsifiers_are_caught(mutate, label):
    """Applied to an in-memory copy of the real nocturne.css text -- never written to disk."""
    clean = NOCTURNE_PATH.read_text()
    mutated = mutate(clean)
    hits = find_external_fetches(mutated)
    assert hits, "falsifier %r was NOT caught -- the check cannot fail" % (label,)


# --- CSP and STATIC_MANIFEST, both named explicitly by criterion 17 -----------------------

EXPECTED_MANIFEST_ROWS = 17


def _csp_has_self_default(csp_text):
    return csp_text.startswith("default-src 'self';")


def _manifest_row_count_matches(manifest, expected=EXPECTED_MANIFEST_ROWS):
    return len(manifest) == expected


def test_criterion17_csp_default_src_self():
    """Criterion 17. The CSP in server.py stays `default-src 'self'` -- checked against the
    live `server.CSP` constant, not a copied string, so a future edit to server.py is what
    this test reads."""
    assert _csp_has_self_default(server.CSP), (
        "server.CSP no longer starts with \"default-src 'self';\": %r" % (server.CSP,))


def test_criterion17_csp_falsifiers_are_caught():
    widened = "default-src *; " + server.CSP
    rewritten = server.CSP.replace("default-src 'self'", "default-src *", 1)
    assert not _csp_has_self_default(widened), "widened-CSP falsifier was not caught"
    assert not _csp_has_self_default(rewritten), "rewritten-CSP falsifier was not caught"


def test_criterion17_static_manifest_row_count():
    """Criterion 17. `STATIC_MANIFEST` keeps its recorded row count. Verified against the
    live `server.STATIC_MANIFEST` tuple, not against a copied number -- see the report for
    this value re-derived independently and compared to the card's recorded 17."""
    count = len(server.STATIC_MANIFEST)
    assert _manifest_row_count_matches(server.STATIC_MANIFEST), (
        "STATIC_MANIFEST has %d rows, expected %d" % (count, EXPECTED_MANIFEST_ROWS))


def test_criterion17_static_manifest_falsifiers_are_caught():
    with_extra_row = server.STATIC_MANIFEST + ("extra-file.js",)
    missing_a_row = server.STATIC_MANIFEST[:-1]
    assert not _manifest_row_count_matches(with_extra_row), "18-row falsifier was not caught"
    assert not _manifest_row_count_matches(missing_a_row), "16-row falsifier was not caught"
