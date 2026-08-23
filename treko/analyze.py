#!/usr/bin/env python3
"""Derive one `run` object for the Treko UI from a repo, read-only.

Output conforms to the shipped Nocturne export's schema (`task-tracker v0.4.1`,
`version: 1`). The schema is not ours to change: a missing field is a `questions[]`
entry and a conversation, never an ad-hoc extension.

Two rules shape everything below.

CHECKLISTS HAVE EXACTLY ONE PARSER. `hooks/lib/feature_tasks.py` owns what a task is,
so `total` here is literally `len(feature_tasks.task_ids(...))` and a line only counts
when `feature_tasks.STRICT_RE` matches it. That module deliberately discards the
checkbox marker -- task identity survives ticking, which is the point of it -- so the
`done` half reads the marker off the same STRICT_RE-matched lines rather than
introducing a second notion of what a checklist item is.

DEPENDENCIES COME ONLY FROM `## Depends on`. Prose that says "must land after X" is
not a dependency; it is unreadable to a machine, and guessing produces a confident
wrong merge order, which is worse than an admitted gap. Everything undetectable
becomes a `questions[]` entry.

The analyzer never writes to the repo it analyzes -- including to fix drift it finds.
"""

import argparse
import json
import re
import subprocess
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
MINUS = "−"  # U+2212, as the shipped sample data uses
DONE_MARKERS = "xX"
CHECKBOX_OPEN = "["
UNPARSEABLE_META = "?/?"

# Card phase -> the UI's task phase pill and its sort index.
PHASE_MAP = {
    "planning": ("Spec", 0),
    "implementation": ("Implement", 1),
    "review": ("Review", 3),
}
SHIPPED_PHASE = ("Ship", 4)
# Every state here appears in the UI's STATE_RANK; anything else sorts as undefined.
STATE_DONE = "Done"
STATE_BLOCKED = "Blocked"
STATE_BY_PHASE = {
    "planning": "Not started",
    "implementation": "In progress",
    "review": "In review",
}

TASK_NAME_MAX_CHARS = 72
MAX_COMMITS_PER_TASK = 5
GRAPH_X0, GRAPH_DX = 8, 250
GRAPH_Y0, GRAPH_DY = 8, 88

DEPENDS_HEADING_RE = re.compile(r"^\s*##\s+Depends on\s*$", re.IGNORECASE)
HEADING_RE = re.compile(r"^\s*#{1,6}\s+")
BULLET_RE = re.compile(r"^\s*[-*]\s+(.+?)\s*$")
LINK_RE = re.compile(r"^\[([^\]]+)\]\([^)]*\)$")
SHORTSTAT_INSERT_RE = re.compile(r"(\d+) insertion")
SHORTSTAT_DELETE_RE = re.compile(r"(\d+) deletion")

RELATIVE_UNITS = {
    "second": "s", "seconds": "s", "minute": "m", "minutes": "m",
    "hour": "h", "hours": "h", "day": "d", "days": "d",
    "week": "w", "weeks": "w", "month": "mo", "months": "mo",
    "year": "y", "years": "y",
}


class GitError(RuntimeError):
    """A git command that was expected to succeed did not."""


# --------------------------------------------------------------------------------- git


def _git(root, *args, allow_failure=False):
    """Run a read-only git command in `root`. Never mutates."""
    result = subprocess.run(
        ["git", "-C", str(root), *args], capture_output=True, text=True,
    )
    if result.returncode != 0:
        if allow_failure:
            return ""
        raise GitError(
            "git %s failed in %s: %s" % (" ".join(args), root, result.stderr.strip())
        )
    return result.stdout


def _compress_relative(rel):
    """'2 hours ago' -> '2h'. git computes the interval, so no clock is read here."""
    parts = rel.split()
    if len(parts) >= 2 and parts[0].isdigit():
        unit = RELATIVE_UNITS.get(parts[1].rstrip(","))
        if unit:
            return parts[0] + unit
    return rel.strip() or NO_VALUE


def _home_collapse(path):
    home = str(Path.home())
    text = str(path)
    return "~" + text[len(home):] if text.startswith(home) else text


def _worktrees(root):
    """branch name -> checkout path, from `git worktree list --porcelain`."""
    found = {}
    path = None
    for line in _git(root, "worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree "):]
        elif line.startswith("branch ") and path:
            found[line[len("branch "):].replace("refs/heads/", "", 1)] = path
    return found


def _base_branch(root, requested=None):
    heads = set(_local_branches(root))
    for candidate in ([requested] if requested else []) + ["main", "master"]:
        if candidate in heads:
            return candidate
    return None


def _local_branches(root):
    out = _git(root, "for-each-ref", "--format=%(refname:short)", "refs/heads")
    return [line.strip() for line in out.splitlines() if line.strip()]


def _ahead_behind(root, base, branch):
    if base is None or branch == base:
        return 0, 0
    out = _git(
        root, "rev-list", "--left-right", "--count", "%s...%s" % (base, branch),
        allow_failure=True,
    ).split()
    if len(out) != 2:
        return 0, 0
    behind, ahead = int(out[0]), int(out[1])  # left = base-only, right = branch-only
    return ahead, behind


def _diffstat(root, base, branch):
    if base is None or branch == base:
        return ""
    out = _git(root, "diff", "--shortstat", "%s...%s" % (base, branch), allow_failure=True)
    inserted = SHORTSTAT_INSERT_RE.search(out)
    deleted = SHORTSTAT_DELETE_RE.search(out)
    if not inserted and not deleted:
        return ""
    return "+%s %s%s" % (
        inserted.group(1) if inserted else "0",
        MINUS,
        deleted.group(1) if deleted else "0",
    )


def _commits(root, base, branch):
    span = branch if base is None or branch == base else "%s..%s" % (base, branch)
    out = _git(
        root, "log", "-n", str(MAX_COMMITS_PER_TASK), "--format=%h\t%s", span,
        allow_failure=True,
    )
    commits = []
    for line in out.splitlines():
        sha, _, message = line.partition("\t")
        if sha:
            commits.append({"sha": sha, "msg": message})
    return commits


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


# --------------------------------------------------------------------------- questions


class Questions:
    """Ordered, sequentially-numbered, always unresolved. The analyzer never answers."""

    def __init__(self):
        self._pending = []

    def add(self, question, context):
        self._pending.append({"q": question, "ctx": context})

    def emit(self):
        return [
            {"id": "q%d" % index, "q": item["q"], "ctx": item["ctx"], "resolved": False}
            for index, item in enumerate(self._pending, 1)
        ]


# ------------------------------------------------------------------------------ waves


def _layer(names, edges):
    """(layers, cycle_members). Kahn's algorithm; leftovers are a cycle, not an order."""
    remaining = set(names)
    incoming = {name: set() for name in names}
    for dependency, dependent in edges:
        incoming[dependent].add(dependency)
    layers, placed = [], set()
    while remaining:
        ready = sorted(name for name in remaining if not incoming[name] - placed)
        if not ready:
            break
        layers.append(ready)
        placed.update(ready)
        remaining.difference_update(ready)
    return layers, sorted(remaining)


def _node_id(index):
    label, index = "", index + 1
    while index:
        index, remainder = divmod(index - 1, 26)
        label = chr(ord("A") + remainder) + label
    return label


# ----------------------------------------------------------------------------- assembly


def _task_name(body):
    text = " ".join(body.split())
    if len(text) <= TASK_NAME_MAX_CHARS:
        return text
    clipped = text[:TASK_NAME_MAX_CHARS].rsplit(" ", 1)[0]
    return (clipped or text[:TASK_NAME_MAX_CHARS]) + "…"


def _card_tone(card, is_blocked):
    if is_blocked:
        return "bad"
    if card.is_complete:
        return "ok"
    return {"planning": "neutral", "implementation": "accent", "review": "info"}.get(
        card.phase, "neutral"
    )


def _build_tasks(card, repo_name, branch_facts, is_blocked, links, blocked_note):
    facts = branch_facts.get(card.branch, {})
    tasks = []
    for _ident, is_done, body in card.items:
        if is_done:
            phase_label, phase_index = SHIPPED_PHASE
            state = STATE_DONE
        else:
            phase_label, phase_index = PHASE_MAP.get(card.phase, ("Spec", 0))
            state = STATE_BLOCKED if is_blocked else STATE_BY_PHASE.get(
                card.phase, "Not started"
            )
        text = " ".join(body.split())
        tasks.append(
            {
                "name": _task_name(body),
                "desc": text,
                "phase": phase_label,
                "pi": phase_index,
                "state": state,
                "repo": repo_name,
                "branch": card.branch or NO_VALUE,
                "pr": NO_VALUE,
                "prState": NO_VALUE,
                "prUrl": "",
                "d": {
                    "worktree": facts.get("wt", NO_VALUE),
                    "diff": facts.get("diff", ""),
                    "last": facts.get("last_ago", NO_VALUE),
                    "commits": facts.get("commits", []),
                    "links": links,
                    "checklist": [],  # our cards carry no sub-checklists
                    "notes": blocked_note if is_blocked and not is_done else "",
                },
            }
        )
    return tasks


def _branch_entries(root, repo_name, branch_facts):
    entries = []
    for branch in _local_branches(root):
        facts = branch_facts[branch]
        dirty_count = facts["dirty_count"]
        if dirty_count:
            note, tone = "%d uncommitted" % dirty_count, "bad"
        elif facts["behind"]:
            note, tone = "needs rebase", "warn"
        elif facts["ahead"]:
            note, tone = "ahead %d" % facts["ahead"], "accent"
        else:
            note, tone = "clean", "ok"
        entries.append(
            {
                "repo": repo_name,
                "branch": branch,
                "wt": facts["wt"],
                "ahead": facts["ahead"],
                "behind": facts["behind"],
                "dirty": bool(dirty_count),
                "note": note,
                "tone": tone,
                "last": facts["last"],
            }
        )
    return entries


def _collect_branch_facts(root, base, worktrees):
    facts = {}
    for branch in _local_branches(root):
        worktree = worktrees.get(branch)
        ahead, behind = _ahead_behind(root, base, branch)
        dirty_count = 0
        if worktree and Path(worktree).is_dir():
            status = _git(worktree, "status", "--porcelain", allow_failure=True)
            dirty_count = len([line for line in status.splitlines() if line.strip()])
        last = _compress_relative(
            _git(root, "log", "-1", "--format=%cr", branch, allow_failure=True).strip()
        )
        facts[branch] = {
            "wt": _home_collapse(worktree) if worktree else NO_VALUE,
            "ahead": ahead,
            "behind": behind,
            "dirty_count": dirty_count,
            "last": last,
            "last_ago": "%s ago" % last if last != NO_VALUE else NO_VALUE,
            "diff": _diffstat(root, base, branch),
            "commits": _commits(root, base, branch),
        }
    return facts


def _named_for(card_name, branches):
    """Branches whose leaf segment is the card's name -- 'feat/x' is named for card 'x'."""
    return sorted(b for b in branches if b.split("/")[-1] == card_name or b == card_name)


# ------------------------------------------------------------------------------- public


def analyze(repo_root, run_id=None, name=None, base_branch=None):
    """Return one schema-conforming `run` object for `repo_root`. Read-only."""
    root = Path(repo_root).resolve()
    if not root.is_dir():
        raise ValueError("not a directory: %s" % root)
    _git(root, "rev-parse", "--git-dir")  # raises GitError if this is not a repo

    repo_name = root.name
    questions = Questions()
    worktrees = _worktrees(root)
    base = _base_branch(root, base_branch)
    if base is None:
        questions.add(
            "Which branch is the merge base for %s?" % repo_name,
            "Neither `main` nor `master` exists, so ahead/behind counts are reported as "
            "0 rather than guessed against an arbitrary ref.",
        )
    branch_facts = _collect_branch_facts(root, base, worktrees)
    all_branches = set(branch_facts)

    cards = [Card(path) for path in _card_paths(root)]
    by_name = {card.name: card for card in cards}

    _ask_about_cards(questions, cards, all_branches)
    edges = _declared_edges(questions, cards, by_name)
    layers, cycle = _layer([c.name for c in cards], edges)
    if cycle:
        questions.add(
            "Which card in the dependency cycle %s merges first?" % ", ".join(cycle),
            "Their `## Depends on` sections form a cycle, so no merge order can be "
            "derived. They are grouped in a final wave marked undetermined.",
        )
    _ask_about_readiness(questions, layers, by_name, branch_facts, base)

    blocked = _blocked_cards(edges, by_name)
    features = _build_features(cards, repo_name, branch_facts, edges, blocked)
    waves = _build_waves(layers, cycle)
    constraints = _build_constraints(edges, by_name)
    graph = _build_graph(layers, cycle, by_name, blocked)

    return {
        "id": run_id or repo_name.lstrip(".") or "run",
        "name": name or repo_name,
        "dir": _home_collapse(root),
        # Left empty on purpose: store.py stamps this when the analyzer does not, and
        # it owns the document's clock. A relative string frozen in here would still
        # read "just now" a week later -- the stale survey this feature replaces.
        "analyzedAt": "",
        "features": features,
        "waves": waves,
        "constraints": constraints,
        "branches": _branch_entries(root, repo_name, branch_facts),
        "graph": graph,
        "kanban": _build_kanban(cards, repo_name, blocked),
        "questions": questions.emit(),
    }


def _ask_about_cards(questions, cards, all_branches):
    undeclared = 0
    for card in cards:
        if card.parse_error:
            questions.add(
                "What should `%s` show? Its checklist cannot be parsed." % card.name,
                "feature_tasks.py reports: %s. Counts are shown as %s rather than "
                "guessed." % (card.parse_error, UNPARSEABLE_META),
            )
        if not card.frontmatter_ok:
            questions.add(
                "Does `%s` have valid frontmatter?" % card.name,
                "No closing `---` delimiter was found, so phase and branch are unread.",
            )
        elif card.phase not in PHASE_MAP:
            questions.add(
                "What phase is `%s` in?" % card.name,
                "Frontmatter says phase: %r, which is not planning/implementation/review."
                % card.phase,
            )
        if not card.depends_on:
            undeclared += 1
        _ask_about_drift(questions, card, all_branches)
        _ask_about_spec_half(questions, card)
    if cards and undeclared:
        questions.add(
            "Are the merge-order dependencies between these cards actually declared?",
            "Dependencies are read only from an explicit `## Depends on` section; prose "
            "is never inferred from. %d of %d cards declare none, so their ordering is "
            "unverified rather than confirmed independent."
            % (undeclared, len(cards)),
        )


def _ask_about_drift(questions, card, all_branches):
    named = _named_for(card.name, all_branches)
    if not card.branch and named:
        questions.add(
            "Does `%s` own the branch %s, or should that branch go?"
            % (card.name, ", ".join(named)),
            "The card's frontmatter says branch: none, but %s exists and is named for "
            "it. Reported both ways rather than resolved in either direction -- the "
            "analyzer never edits a card."
            % (" and ".join(named)),
        )
    elif card.branch and card.branch not in all_branches:
        questions.add(
            "Where is `%s`'s branch %s?" % (card.name, card.branch),
            "The frontmatter names it but no such local branch exists.",
        )


def _ask_about_spec_half(questions, card):
    spec_path = card.path.parent / ("%s%s" % (card.name, SPEC_SUFFIX))
    if not spec_path.is_file():
        return
    code, message = feature_tasks.compare(card.text, spec_path.read_text(), card.name)
    if code:
        questions.add(
            "Which half of `%s` is right?" % card.name,
            message,
        )


def _ask_about_readiness(questions, layers, by_name, branch_facts, base):
    if not layers:
        return
    for name in layers[0]:
        card = by_name[name]
        if not card.branch:
            questions.add(
                "Is `%s` ready to start? It is ordered first but has no branch." % name,
                "Nothing depends on it, so it heads the order, but its frontmatter "
                "names no branch -- ordered first is not the same as ready to merge.",
            )
        elif branch_facts.get(card.branch, {}).get("behind"):
            questions.add(
                "Should `%s` rebase before it merges first?" % name,
                "It heads the order but its branch is %d behind %s."
                % (branch_facts[card.branch]["behind"], base),
            )


def _declared_edges(questions, cards, by_name):
    """[(dependency, dependent)] for declared targets that are real cards."""
    edges = []
    for card in cards:
        for target, reason in card.depends_on:
            if target == card.name:
                questions.add(
                    "Why does `%s` declare a dependency on itself?" % card.name,
                    "Self-references are ignored rather than ordered.",
                )
                continue
            if target not in by_name:
                questions.add(
                    "What is `%s`, which `%s` declares a dependency on?"
                    % (target, card.name),
                    "No card by that name exists under docs/features/, so no ordering "
                    "edge was created and no node was invented for it."
                    + (" Stated reason: %s" % reason if reason else ""),
                )
                continue
            edges.append((target, card.name))
    return edges


def _blocked_cards(edges, by_name):
    """A card is blocked when a card it declares a dependency on is not complete."""
    blocked = {}
    for dependency, dependent in edges:
        if not by_name[dependency].is_complete:
            blocked.setdefault(dependent, []).append(dependency)
    return blocked


def _build_features(cards, repo_name, branch_facts, edges, blocked):
    dependencies = {}
    dependents = {}
    for dependency, dependent in edges:
        dependencies.setdefault(dependent, []).append(dependency)
        dependents.setdefault(dependency, []).append(dependent)
    features = []
    for card in cards:
        links = [
            {"t": "after — %s" % target, "kind": "after"}
            for target in dependencies.get(card.name, [])
        ] + [
            {"t": "blocks — %s" % target, "kind": "blocks"}
            for target in dependents.get(card.name, [])
        ]
        blockers = blocked.get(card.name, [])
        note = (
            "Blocked by %s — declared in this card's ## Depends on." % ", ".join(blockers)
            if blockers else ""
        )
        features.append(
            {
                "name": card.name,
                "meta": card.meta,
                "tasks": _build_tasks(
                    card, repo_name, branch_facts, bool(blockers), links, note
                ),
            }
        )
    return features


def _build_waves(layers, cycle):
    waves = []
    for index, names in enumerate(layers, 1):
        note = (
            "no declared dependencies — ordering beyond ## Depends on is unverified"
            if index == 1
            else "after wave %d — declared via ## Depends on" % (index - 1)
        )
        waves.append(
            {
                "n": str(index),
                "note": note,
                "items": [{"t": name, "pr": "", "prState": ""} for name in names],
            }
        )
    if cycle:
        waves.append(
            {
                "n": str(len(layers) + 1),
                "note": "cycle — order undetermined, see questions",
                "items": [{"t": name, "pr": "", "prState": ""} for name in cycle],
            }
        )
    return waves


def _build_constraints(edges, by_name):
    constraints = []
    for index, (dependency, dependent) in enumerate(edges, 1):
        reason = ""
        for target, stated in by_name[dependent].depends_on:
            if target == dependency and stated:
                reason = stated
                break
        constraints.append(
            {
                "id": "C%d" % index,
                "title": "%s merges before %s" % (dependency, dependent),
                "pair": "%s → %s" % (dependency, dependent),
                "body": reason or (
                    "`%s` declares this dependency in its ## Depends on section without "
                    "a stated reason." % dependent
                ),
            }
        )
    return constraints


def _build_graph(layers, cycle, by_name, blocked):
    columns = list(layers) + ([cycle] if cycle else [])
    nodes, ids = [], {}
    counter = 0
    for column, names in enumerate(columns):
        for row, name in enumerate(names):
            card = by_name[name]
            ids[name] = _node_id(counter)
            counter += 1
            nodes.append(
                {
                    "id": ids[name],
                    "label": name,
                    "sub": "%s · %s" % (card.branch or "no branch", card.phase or "?"),
                    "tone": _card_tone(card, name in blocked),
                    "x": GRAPH_X0 + GRAPH_DX * column,
                    "y": GRAPH_Y0 + GRAPH_DY * row,
                }
            )
    edges = [
        [ids[dependency], ids[dependent]]
        for name in ids
        for dependency, dependent in _edges_of(by_name, name)
        if dependency in ids and dependent in ids
    ]
    seen, unique = set(), []
    for edge in edges:
        key = tuple(edge)
        if key not in seen:
            seen.add(key)
            unique.append(edge)
    return {"nodes": nodes, "edges": unique}


def _edges_of(by_name, name):
    return [(target, name) for target, _ in by_name[name].depends_on if target in by_name]


def _build_kanban(cards, repo_name, blocked):
    columns = [
        ("Up next", "accent", []),
        ("In progress", "info", []),
        ("Blocked", "bad", []),
        ("In review", "ok", []),
    ]
    buckets = {title: items for title, _, items in columns}
    for card in cards:
        item = {"t": card.name, "m": "%s · %s" % (repo_name, card.meta)}
        if card.name in blocked:
            buckets["Blocked"].append(item)
        elif card.phase == "review" or card.is_complete:
            buckets["In review"].append(item)
        elif card.phase == "implementation":
            buckets["In progress"].append(item)
        else:
            buckets["Up next"].append(item)
    return [
        {"title": title, "tone": tone, "items": items} for title, tone, items in columns
    ]


def main(argv=None):
    parser = argparse.ArgumentParser(description="Derive one Treko run object.")
    parser.add_argument("repo_root", nargs="?", default=".")
    parser.add_argument("--id", dest="run_id", default=None)
    parser.add_argument("--name", default=None)
    parser.add_argument("--base", dest="base_branch", default=None)
    parser.add_argument("--pretty", action="store_true")
    args = parser.parse_args(argv)
    try:
        run = analyze(args.repo_root, args.run_id, args.name, args.base_branch)
    except (GitError, ValueError) as exc:
        sys.stderr.write("analyze: %s\n" % exc)
        return 1
    json.dump(run, sys.stdout, indent=2 if args.pretty else None, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
