"""One run from several repositories' runs (docs/features/treko-ledger.spec.md section 7; decision D42).

`merge(request, parts, scan_questions)` is a pure function: it reads its arguments, copies whatever it
reuses, and returns a new run with exactly the key set of an analyzer run (ADR 0023 says the schema is not
ours to change). It reads no file, runs no process and consults no clock; `analyzedAt` stays empty for the
store to stamp.

A part is one family, in the order the caller gives, and is one of
    {"root", "label", "questions", "run"}                                       the analyzer finished
    {"root", "label", "questions", "failure": {"exit", "timedOut", "stderr"}}   it did not
`request` is {"directory", "repo", "branch", "worktree"}; `scan_questions` and each part's `questions` are
lists of {"q", "ctx"}, already worded by the scan.

With one family and no narrowing the result is that family's run with only `id`, `name` and `dir`
replaced (section 7.3), so nothing here may reorder, renumber or regroup a single family.
"""

import copy
from collections import Counter

import analyze
import ledger_state

# The note the analyzer gives the wave it puts last for a dependency cycle (`analyze._build_waves`).
# A test pins it to the analyzer's real output, so it cannot drift silently.
CYCLE_NOTE = "cycle — order undetermined, see questions"
# How the analyzer joins a repo label and a card's meta in a kanban item's `m`.
KANBAN_META_JOIN = " · "
# A family's first row sits one empty row below the previous family's last row (D42 item 2).
GRAPH_FAMILY_GAP = 2 * analyze.GRAPH_DY
QUESTION_PREFIX = "q"
CONSTRAINT_PREFIX = "C"


# ---------------------------------------------------------------------------------- labels

def _repo_labels(parts):
    """Each part's repo label: its folder name, or its home-collapsed root when another part shares it."""
    folder_counts = Counter(part["label"] for part in parts)
    return [
        ledger_state.run_dir(part["root"]) if folder_counts[part["label"]] > 1 else part["label"]
        for part in parts
    ]


def _relabel(run, old, new):
    """Change the repo label in the three places section 7.1 names; card names and question text stay."""
    for feature in run["features"]:
        for task in feature["tasks"]:
            task["repo"] = new
    for branch in run["branches"]:
        branch["repo"] = new
    prefix = old + KANBAN_META_JOIN
    for column in run["kanban"]:
        for item in column["items"]:
            if not item["m"].startswith(prefix):
                raise ValueError("kanban item %r does not start with its repository's label %r" % (item["m"], old))
            item["m"] = new + item["m"][len(old):]


def _own_runs(parts, labels):
    """A private copy of each finished family's run, relabelled where names collide; failed ones have none."""
    runs = []
    for part, label in zip(parts, labels):
        if "run" not in part:
            continue
        run = copy.deepcopy(part["run"])
        if label != part["label"]:
            _relabel(run, part["label"], label)
        runs.append(run)
    return runs


# --------------------------------------------------------------------------------- sections

def _concat(runs, section):
    return [row for run in runs for row in run[section]]


def _numbered(prefix, rows):
    """The rows with ids `<prefix>1…<prefix>N`; each analyzer restarts its own numbering."""
    return [
        dict([("id", "%s%d" % (prefix, number))] + [(key, value) for key, value in row.items() if key != "id"])
        for number, row in enumerate(rows, 1)
    ]


def _plain_question(question):
    return {"q": question["q"], "ctx": question["ctx"], "resolved": False}


def _failure_context(failure):
    if failure["timedOut"]:
        how = "The analyzer timed out before it finished."
    elif failure["exit"] is None:
        how = "The analyzer stopped without an exit status."
    else:
        how = "The analyzer exited with status %s." % failure["exit"]
    said = "Its last line on stderr was: %s" % failure["stderr"] if failure["stderr"] else "It wrote nothing to stderr."
    return "%s %s Its cards, branches and graph are missing from this run." % (how, said)


def _failure_question(label, failure):
    return _plain_question({"q": "Why could `%s` not be analyzed?" % label, "ctx": _failure_context(failure)})


def _questions(parts, labels, scan_questions):
    """Scan-level first, then the failed families', then each family's own just before its analyzer's."""
    asked = [_plain_question(question) for question in scan_questions]
    asked += [
        _failure_question(label, part["failure"])
        for part, label in zip(parts, labels) if "run" not in part
    ]
    for part in parts:
        asked += [_plain_question(question) for question in part["questions"]]
        if "run" in part:
            asked += part["run"]["questions"]
    return _numbered(QUESTION_PREFIX, asked)


def _split_cycle_wave(waves):
    """(layered waves, the cycle wave or None): the analyzer always puts a cycle wave last."""
    if waves and waves[-1]["note"] == CYCLE_NOTE:
        return waves[:-1], waves[-1]
    return waves, None


def _waves(runs):
    """Layered waves merge by index; every family's cycle wave becomes one wave after the longest run."""
    split = [_split_cycle_wave(run["waves"]) for run in runs]
    layered = [waves for waves, _ in split]
    cycles = [wave for _, wave in split if wave]
    depth = max((len(waves) for waves in layered), default=0)
    merged = []
    for index in range(depth):
        owners = [waves[index] for waves in layered if len(waves) > index]
        merged.append({
            "n": str(index + 1),
            "note": owners[0]["note"],
            "items": [item for wave in owners for item in wave["items"]],
        })
    if cycles:
        items = [item for wave in cycles for item in wave["items"]]
        merged.append({"n": str(depth + 1), "note": CYCLE_NOTE, "items": items})
    return merged


def _graph(runs):
    nodes, edges = [], []
    previous_bottom = None
    for run in runs:
        own = run["graph"]["nodes"]
        if not own:
            continue  # a family with no nodes takes no space
        shift = 0 if previous_bottom is None else previous_bottom + GRAPH_FAMILY_GAP - min(n["y"] for n in own)
        new_ids = {}
        for node in own:
            new_ids[node["id"]] = analyze._node_id(len(nodes))
            nodes.append(dict(node, id=new_ids[node["id"]], y=node["y"] + shift))
        edges += [[new_ids[source], new_ids[target]] for source, target in run["graph"]["edges"]]
        previous_bottom = max(node["y"] for node in nodes[-len(own):])
    return {"nodes": nodes, "edges": edges}


def _kanban(runs):
    # The four columns come from the analyzer itself, built with no cards, so they cannot drift from it.
    columns = analyze._build_kanban([], "", {})
    by_title = {column["title"]: column for column in columns}
    for run in runs:
        for column in run["kanban"]:
            by_title[column["title"]]["items"].extend(column["items"])
    return columns


# ------------------------------------------------------------------------------------ merge

def merge(request, parts, scan_questions):
    fields = [request.get(key, "") for key in ("directory", "repo", "branch", "worktree")]
    labels = _repo_labels(parts)
    runs = _own_runs(parts, labels)
    return {
        "id": ledger_state.run_id(*fields),
        "name": ledger_state.run_name(*fields),
        "dir": ledger_state.run_dir(fields[0]),
        "analyzedAt": "",
        "features": _concat(runs, "features"),
        "waves": _waves(runs),
        "constraints": _numbered(CONSTRAINT_PREFIX, _concat(runs, "constraints")),
        "branches": _concat(runs, "branches"),
        "graph": _graph(runs),
        "kanban": _kanban(runs),
        "questions": _questions(parts, labels, scan_questions),
    }
