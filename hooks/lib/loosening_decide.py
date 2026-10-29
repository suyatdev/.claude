"""Judge ONE commit in ONE repository: skip, allow, ask, or refuse. Called by loosening_guard.py.

The order of the checks below is the contract, and the order is part of it (spec section 7; ADR 0053's
precedence note):
  1. no watched file in the commit            -> skip   (a commit this hook has no business with)
  2. origin/main unobtainable                 -> REFUSE (no baseline: checked BEFORE the merge question)
  3. a merge whose parent is already on main  -> allow  (ADR 0053; any non-zero exit falls through)
  4. nothing differs from origin/main         -> allow  (unchanged)
  5. a side cannot be read                    -> REFUSE (names which side)
  6. tightening, or a cosmetic edit           -> allow
  7. a record for this exact state            -> allow
  8. not attended                             -> REFUSE (exit 2, never an ask: under bypass an ask runs)
  9. attended                                 -> ask
"""
import os
import re
import stat

import loosening_extract as extract
import loosening_watch as watch
from loosening_states import Git, GitError, Snapshot
import secret_approval as sa

BASE_REF = "origin/main"
EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
HEX_SHA_RE = re.compile(r"^[0-9a-fA-F]{40,64}$")
MAX_REASON_LINES = 30
MAX_LINE_CHARS = 200
ATTENDED_MODE = "default"
SIDE_STAGED, SIDE_BASELINE = "staged", "baseline"


class Refusal(Exception):
    """Fail closed: the caller prints `message` on stderr and exits 2."""

    def __init__(self, message, cls):
        super().__init__(message)
        self.message, self.cls = message, cls


class Outcome:
    def __init__(self, decision, cls, reason="", keys=(), notes=()):
        self.decision, self.cls, self.reason = decision, cls, reason
        self.keys, self.notes = tuple(keys), tuple(notes)


class Context:
    """What the payload says about the session and the command."""

    def __init__(self, payload, command):
        self.command = command
        self.session = str(payload.get("session_id") or "")
        self.mode = payload.get("permission_mode")
        self.is_subagent = any(payload.get(k) for k in ("agent_id", "agent_type"))


# ---- git-side facts -----------------------------------------------------------------------------
def changed_names(git, mode, ref, pathspecs):
    base = ("diff", "--name-only", "--no-renames", "-z")
    if mode == "index":
        return git.paths(*base, "--cached", ref)
    if mode == "pathspec":
        return git.paths(*base, ref, "--", *pathspecs)
    return git.paths(*base, ref)


def merge_already_on_main(git):
    """ADR 0053: True only when MERGE_HEAD exists, is a plain object id, and is an ancestor of origin/main.

    Every other answer -- no merge, an unreadable file, a malformed id, exit 1, exit 128 -- is False,
    because the caller treats "False" as "judge this commit on its merits" (a prompt), never as "allow".
    """
    merge_head = os.path.join(git.text("rev-parse", "--absolute-git-dir"), "MERGE_HEAD")
    try:
        with open(merge_head) as fh:
            sha = fh.read().strip()
    except OSError:
        return False
    return bool(HEX_SHA_RE.match(sha)) and git.ok("merge-base", "--is-ancestor", sha, BASE_REF)


# ---- classification -----------------------------------------------------------------------------
def classify(changed, base, new):
    """-> (class, {path: Findings}, {path: mode note}). Raises Refusal when a side cannot be read."""
    results, mode_notes, bad = {}, {}, {SIDE_STAGED: [], SIDE_BASELINE: []}
    for path in changed:
        old_state, new_state = base.state(path), new.state(path)
        found = extract.Findings()
        results[path] = found
        if new_state is None:
            found.unknown.append("the file is deleted by this commit")
            continue
        if old_state is None:
            found.unknown.append("the file is new: origin/main has no copy to compare it with")
            continue
        if old_state[0] != new_state[0]:
            mode_notes[path] = "git mode %s -> %s" % (old_state[0], new_state[0])
        if old_state[1] == new_state[1]:
            continue
        profiles = {}
        for side, snap in ((SIDE_BASELINE, base), (SIDE_STAGED, new)):
            try:
                profiles[side] = extract.extract(path, snap.data(path))
            except extract.ParseError as exc:
                bad[side].append("%s: %s" % (path, exc))
        if len(profiles) == 2:
            results[path] = extract.compare(path, profiles[SIDE_BASELINE], profiles[SIDE_STAGED])
    named = [side for side in (SIDE_STAGED, SIDE_BASELINE) if bad[side]]
    if named:
        lines = ["loosening-guard: cannot extract the permission list, so the commit is refused rather than guessed at."]
        for side in named:
            where = "the commit's copy" if side == SIDE_STAGED else "the origin/main copy"
            lines.append("  %s side (%s): %s" % (side, where, "; ".join(bad[side])))
        raise Refusal("\n".join(lines), "parse")
    loosen = any(f.loosen for f in results.values())
    tighten = any(f.tighten for f in results.values())
    unknown = any(f.unknown for f in results.values())
    if unknown or (loosen and tighten):
        cls = "unclassified"
    elif loosen:
        cls = "loosening"
    elif mode_notes:
        cls = "unclassified"      # a mode change is never silent, but it does not claim a direction
    elif tighten:
        cls = "tightening"
    else:
        cls = "unchanged"
    return cls, results, mode_notes


def describe(results, mode_notes):
    lines = []
    for path in sorted(results):
        found = results[path]
        feeds = ", ".join(watch.WATCH[path])
        rows = []
        for bucket in (found.loosen, found.tighten):
            for name, what, sign, shown in bucket:
                rows.append("    %s %s   [%s: %s]" % (sign, shown, name, what))
        rows += ["    ? %s" % reason for reason in found.unknown]
        if path in mode_notes:
            rows.append("    ? %s" % mode_notes[path])
        if rows:
            lines.append("  %s (feeds %s)" % (path, feeds))
            lines += rows
    clipped = [ln[:MAX_LINE_CHARS] for ln in lines[:MAX_REASON_LINES]]
    if len(lines) > MAX_REASON_LINES:
        clipped.append("  ... and %d more line(s)" % (len(lines) - MAX_REASON_LINES))
    return clipped


def build_reason(cls, missing, results, mode_notes, command, notes):
    names = ", ".join(missing)
    if cls == "loosening":
        head = "[LOOSENING] %s: this commit widens what the guard permits. Confirm to commit." % names
    else:
        head = ("[UNCLASSIFIED] the change to %s could not be classified as a tightening or a "
                "loosening; it needs your decision." % names)
    tail = ["commit: %s" % command,
            "Approving records this exact state of the guard's files; it stays valid until they change again."]
    return "\n".join([head] + describe(results, mode_notes) + tail + list(notes))


# ---- the approval store and attendedness ----------------------------------------------------------
def approval_status(session, key):
    """'yes' | 'no' | 'unreadable'. An unreadable store is never read as an approval (spec section 7)."""
    if not os.path.isabs(sa.state_dir()):
        return "unreadable"
    try:
        return "yes" if stat.S_ISREG(os.stat(sa.approval_path(session, key)).st_mode) else "no"
    except FileNotFoundError:
        return "no"
    except OSError:
        return "unreadable"


def require_attended(ctx, missing):
    """ADR 0054 decision 2. permission_mode first, subagent markers second, independently."""
    mode_says_unattended = ctx.mode is not None and ctx.mode != ATTENDED_MODE
    if ctx.is_subagent or mode_says_unattended:
        raise Refusal(
            "loosening-guard: approval cannot be obtained unattended (permission_mode=%r, subagent=%s), so a "
            "commit that changes %s is refused. Run it yourself in an interactive session." %
            (ctx.mode, "yes" if ctx.is_subagent else "no", ", ".join(missing)), "unattended")
    if ctx.mode is None:
        raise Refusal(
            "loosening-guard: the payload carries no permission_mode, so whether a human can answer a prompt "
            "cannot be established; a commit that changes %s is refused rather than asked about." %
            ", ".join(missing), "no-mode")


# ---- the decision -------------------------------------------------------------------------------
def evaluate(ctx, directory, mode, pathspecs):
    git = Git(directory)
    if not git.ok("rev-parse", "--git-dir"):
        return Outcome("skip", "unrelated")          # not a repository: this commit cannot happen
    git = Git(git.text("rev-parse", "--show-toplevel"))
    root = git.cwd
    ref = "HEAD" if git.ok("rev-parse", "--verify", "-q", "HEAD^{commit}") else EMPTY_TREE
    touched = sorted(n for n in set(changed_names(git, mode, ref, pathspecs)) if n in watch.WATCH)
    if not touched:
        return Outcome("skip", "unrelated")
    if not git.ok("rev-parse", "--verify", "-q", BASE_REF + "^{commit}"):
        raise Refusal("loosening-guard: the baseline %s is unobtainable (no such ref here), so no comparison "
                      "can be made and a commit touching %s is refused." % (BASE_REF, ", ".join(touched)),
                      "no-baseline")
    if merge_already_on_main(git):
        return Outcome("allow", "merge-on-main")
    base = Snapshot(git, "base", root, BASE_REF)
    new = Snapshot(git, "index" if mode == "index" else "worktree", root)
    changed = [p for p in touched if base.state(p) != new.state(p)]
    if not changed:
        return Outcome("allow", "unchanged")
    cls, results, mode_notes = classify(changed, base, new)
    if cls in ("unchanged", "tightening"):
        return Outcome("allow", cls)
    guards = [g for g in watch.GUARDS if any(g in watch.WATCH[p] for p in changed)]
    keys, missing, notes = {}, [], []
    for guard in guards:
        files = {}
        for path in watch.files_of(guard):
            state = new.state(path)
            files[path] = None if state is None else (state[0], new.data(path))
        keys[guard] = sa.state_id(guard, files)
        status = approval_status(ctx.session, keys[guard])
        if status == "unreadable":
            notes.append("note: the approval store could not be read, so earlier approvals were not consulted.")
        if status != "yes":
            missing.append(guard)
    if not missing:
        return Outcome("allow", "approved")
    require_attended(ctx, missing)
    reason = build_reason(cls, missing, results, mode_notes, ctx.command, sorted(set(notes)))
    return Outcome("ask", cls, reason, [keys[g] for g in missing])
