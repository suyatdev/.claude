"""What a card is: one `docs/features/<name>.md`, parsed, read-only.

Moved out of `analyze.py` unchanged (docs/features/treko-ledger.spec.md, section 1.1, split 1).
`hooks/lib/feature_tasks.py` still owns what a checklist task is.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "hooks" / "lib"))

import feature_tasks  # noqa: E402  — the single checklist parser

SPEC_SUFFIX = ".spec.md"
FRONTMATTER_DELIM = "---"
# A YAML comment opens at whitespace-then-`#`, so a `#` inside a token stays in the
# value: this repo's closed cards write `branch: none  # merged via PR #39 (...)`,
# while a branch legitimately named `feat/issue#42` must survive whole. Quoted
# scalars are not modelled -- no card quotes a frontmatter value.
FRONTMATTER_COMMENT = re.compile(r"\s+#.*$")
NO_VALUE = "—"
DONE_MARKERS = "xX"
CHECKBOX_OPEN = "["
UNPARSEABLE_META = "?/?"

DEPENDS_HEADING_RE = re.compile(r"^\s*##\s+Depends on\s*$", re.IGNORECASE)
HEADING_RE = re.compile(r"^\s*#{1,6}\s+")
BULLET_RE = re.compile(r"^\s*[-*]\s+(.+?)\s*$")
LINK_RE = re.compile(r"^\[([^\]]+)\]\([^)]*\)$")


# ------------------------------------------------------------------------------- cards


def _card_paths(repo_root):
    features_dir = Path(repo_root) / "docs" / "features"
    if not features_dir.is_dir():
        return []
    return sorted(
        path for path in features_dir.glob("*.md") if not path.name.endswith(SPEC_SUFFIX)
    )


def _parse_frontmatter(text):
    """(fields, is_well_formed). Only the delimited head is read."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != FRONTMATTER_DELIM:
        return {}, False
    fields = {}
    for line in lines[1:]:
        if line.strip() == FRONTMATTER_DELIM:
            return fields, True
        key, sep, value = line.partition(":")
        if sep:
            fields[key.strip()] = FRONTMATTER_COMMENT.sub("", value).strip()
    return fields, False  # never closed


def _checklist(text, label):
    """([(ident, is_done, body)], total). Raises feature_tasks.ParseError, never guesses."""
    total = len(feature_tasks.task_ids(text, label))
    items = []
    for line in text.splitlines():
        match = feature_tasks.STRICT_RE.match(line)
        if match is None:
            continue
        body = match.group(1)
        # STRICT_RE anchors `- [c]`, so the first '[' is the checkbox.
        is_done = line[line.index(CHECKBOX_OPEN) + 1] in DONE_MARKERS
        items.append((feature_tasks.identity(body), is_done, body.strip()))
    return items, total


def _depends_on(text):
    """[(target, reason)] from an explicit `## Depends on` section. Prose is ignored."""
    declared = []
    inside = False
    for line in text.splitlines():
        if DEPENDS_HEADING_RE.match(line):
            inside = True
            continue
        if inside and HEADING_RE.match(line):
            break
        if not inside or feature_tasks.STRICT_RE.match(line):
            continue
        bullet = BULLET_RE.match(line)
        if not bullet:
            continue
        target, _, reason = bullet.group(1).partition(feature_tasks.EM_DASH)
        declared.append((_normalize_target(target), reason.strip()))
    return declared


def _normalize_target(raw):
    target = raw.strip().strip("`").strip()
    link = LINK_RE.match(target)
    if link:
        target = link.group(1).strip().strip("`")
    if target.endswith(SPEC_SUFFIX):
        target = target[: -len(SPEC_SUFFIX)]
    elif target.endswith(".md"):
        target = target[: -len(".md")]
    return target.strip().strip("/").split("/")[-1]


class Card:
    """One `docs/features/<name>.md`, parsed."""

    def __init__(self, path):
        self.path = path
        self.name = path.name[: -len(".md")]
        self.text = path.read_text()
        self.frontmatter, self.frontmatter_ok = _parse_frontmatter(self.text)
        self.phase = self.frontmatter.get("phase", "")
        self.model_tier = self.frontmatter.get("model_tier", "")
        declared = self.frontmatter.get("branch", "").strip()
        self.branch = "" if declared.lower() in ("", "none", NO_VALUE) else declared
        self.depends_on = _depends_on(self.text)
        self.parse_error = None
        try:
            self.items, self.total = _checklist(self.text, "%s.md" % self.name)
        except feature_tasks.ParseError as exc:
            self.items, self.total, self.parse_error = [], None, str(exc)
        self.done = sum(1 for _, is_done, _ in self.items if is_done)

    @property
    def meta(self):
        if self.parse_error:
            return UNPARSEABLE_META
        return "%d/%d" % (self.done, self.total)

    @property
    def is_complete(self):
        return self.total is not None and self.total > 0 and self.done == self.total
