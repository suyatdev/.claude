# shellcheck shell=bash
# 20-reference-double.sh — sourced by ../loosening-guard.test.sh — not runnable on its own.
# The reference double and its LG_DEGRADE controls: writes $MODELPY (consulted only by the --matrix / --impl runs).
# ---------------------------------------------------------------------------------------------
# The reference double: the contract above as a decision table, with the CLASSIFICATION supplied by
# the harness (LG_ORACLE_CLASS) because the extractors are task 5's work. LG_DEGRADE removes one
# capability at a time -- each degradation is a plausible way a real implementation goes wrong.
# ---------------------------------------------------------------------------------------------
cat > "$MODELPY" <<'PYEOF'
import hashlib, json, re, subprocess, sys
from os import environ as ENV
import os
DEG = ENV.get("LG_DEGRADE", "")
SEC, GIT, WT = "secret-command-guard", "git-guard", "worktree-guard"
WATCH = {
 "hooks/lib/classify-secret-command.py": (SEC,), "hooks/secret-command-guard.sh": (SEC,),
 "hooks/lib/secret_approval.py": (SEC,), "hooks/git-guard.sh": (GIT,),
 "hooks/lib/git_quiet_class.py": (GIT,), "hooks/lib/git_guard_quiet.py": (GIT,),
 "hooks/lib/classify-git-command.py": (GIT, WT), "hooks/worktree-guard.sh": (WT,),
 "hooks/lib/worktree_guard_bash_arms.sh": (WT,), "hooks/lib/worktree_guard_liveness.sh": (WT,),
 "hooks/reference-transaction": (WT,), "hooks/reference-transaction.mode": (WT,),
 "hooks/lib/shell_segments.py": (SEC, GIT, WT), "settings.json": (SEC, GIT, WT)}
GUARD_FILES = {"hooks/secret-command-guard.sh", "hooks/git-guard.sh", "hooks/worktree-guard.sh"}

def run(*a):
    return subprocess.run(list(a), stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
def git(*a): return run("git", *a)
def log(decision, cls):
    path = ENV.get("LOOSENING_GUARD_LOG")
    if path:
        with open(path, "a") as fh: fh.write("decision=%s class=%s\n" % (decision, cls))
def done(decision, cls):
    log(decision, cls)
    if DEG == "chatty" and decision == "skip": sys.stderr.write("loosening-guard: nothing to check\n")
    sys.exit(0)
def refuse(msg): sys.stderr.write("loosening-guard: %s\n" % msg); sys.exit(2)

try:
    p = json.loads(sys.stdin.read()); assert isinstance(p, dict)
except Exception:
    if DEG == "json-open": sys.exit(0)
    refuse("payload is not valid JSON, so the command cannot be inspected")
ev, cmd = p.get("hook_event_name"), (p.get("tool_input") or {}).get("command") or ""
sid = re.sub(r"[^A-Za-z0-9_-]", "_", str(p.get("session_id") or "nosession"))[:128]
state = ENV["SECRET_GUARD_STATE_DIR"]
cid = hashlib.sha256(cmd.encode()).hexdigest()[:16]
rec = lambda k: os.path.join(state, "secret-approval-%s-%s" % ("any" if DEG == "sess-blind" else sid, k))

if ev == "PostToolUse":
    pend = os.path.join(state, "lg-pending-%s-%s" % (sid, cid))
    try:
        if os.path.exists(pend) and DEG != "no-record":
            for k in open(pend).read().split():
                open(rec(k), "w").write("1")
            os.remove(pend)
    except OSError:
        pass
    done("skip", "post")
if ev != "PreToolUse": done("skip", "unrelated")

flat = re.sub(r'"[^"]*"|\'[^\']*\'', '""', cmd)
m = re.search(r'(^|[;&|]\s*)git\s+commit\b([^;&|]*)', flat)
if not m and DEG != "loose-detect": done("skip", "unrelated")
# Spec 7: a note left by an earlier DECLINED ask for this exact command is dropped before judging; when it
# cannot be dropped, the allow path would let PostToolUse turn it into an approval nobody gave, so REFUSE.
stale = os.path.join(state, "lg-pending-%s-%s" % (sid, cid))
if os.path.exists(stale):
    try: os.remove(stale)
    except OSError as exc:
        if DEG != "stale-open": refuse("an earlier approval note for this command could not be cleared (%s)" % exc)
use_wt = bool(re.search(r"\s-[A-Za-z]*a[A-Za-z]*\b|\s--all\b", m.group(2))) if m else False
pm, agent = p.get("permission_mode"), bool(p.get("agent_id"))
mode_says = pm is not None and pm != "default"
unattended = mode_says if DEG == "agent-blind" else (agent or mode_says)
if DEG == "unattended-blanket" and p.get("permission_mode") != "default": refuse("unattended: refusing every commit")
if DEG == "absent-blanket" and pm is None: refuse("permission_mode is absent from the payload: refusing every commit")
has_base = git("rev-parse", "--verify", "-q", "origin/main^{commit}").returncode == 0
if DEG == "base-first" and not has_base: refuse("baseline origin/main is unobtainable")
if DEG == "dirty-tree": open(".lg-dirt", "w").write("x")
names = (git("diff", "HEAD", "--name-only", "--no-renames") if use_wt
         else git("diff", "--cached", "--name-only", "--no-renames")).stdout.split("\n")
view = GUARD_FILES if DEG == "guard-filename-only" else set(WATCH)
touched = [n for n in names if n in view]
if not touched: done("skip", "unrelated")
if DEG == "store-first" and not os.access(state, os.R_OK): refuse("approval store unreadable")

if not has_base:
    if DEG == "base-open": done("allow", "unchanged")
    refuse("baseline origin/main is unobtainable, so no comparison can be made")
gd = git("rev-parse", "--git-dir").stdout.strip()
if os.path.exists(os.path.join(gd, "MERGE_HEAD")):
    if DEG == "merge-skip-all": done("allow", "merge-on-main")
    sha = open(os.path.join(gd, "MERGE_HEAD")).read().strip()
    rc = git("merge-base", "--is-ancestor", sha, "origin/main").returncode
    if (rc == 0 and DEG != "merge-never-skip") or (DEG == "merge-exit1-only" and rc != 1): done("allow", "merge-on-main")
elif DEG == "squash-skip" and os.path.exists(os.path.join(gd, "SQUASH_MSG")): done("allow", "merge-on-main")

ref = "HEAD" if DEG == "head-baseline" else "origin/main"
def new_state(f):
    if use_wt:
        if not os.path.exists(f): return None
        return ("100755" if os.access(f, os.X_OK) else "100644", git("hash-object", f).stdout.strip())
    o = git("ls-files", "-s", "--", f).stdout.split()
    return (o[0], o[1]) if o else None
def base_state(f):
    o = git("ls-tree", ref, "--", f).stdout.split()
    return (o[0], o[2]) if o else None
norm = lambda s: s if (s is None or DEG != "content-only") else s[1]
changed = [f for f in touched if norm(new_state(f)) != norm(base_state(f))]

oracle = ENV.get("LG_ORACLE_CLASS") or "unclassified"
if DEG == "head-baseline" and ENV.get("LG_ORACLE_CLASS_HEAD"): oracle = ENV["LG_ORACLE_CLASS_HEAD"]
if oracle == "parse-error" and changed:
    if DEG == "parse-open": done("allow", "tightening")
    side = ENV.get("LG_ORACLE_BAD_SIDE", "staged")
    refuse({"staged": "cannot extract the permission list from the staged side",
            "baseline": "cannot extract the permission list from the baseline side",
            "both": "cannot extract the permission list from either the staged or the baseline side"}[side])
if not changed: cls = "unchanged"
elif any(new_state(f) is None for f in changed): cls = "unclassified"
elif any(base_state(f) is None for f in changed): cls = "loosening"
else: cls = oracle
if cls == "unchanged" and changed and DEG == "whole-file": cls = "unclassified"
if cls == "unchanged" or (cls == "tightening" and DEG != "ask-tighten"): done("allow", cls)
if cls == "unclassified" and DEG == "two-outcome": done("allow", "tightening")

guards = sorted({g for f in changed for g in WATCH[f]})
if DEG == "first-guard-only": guards = guards[:1]
def key(g):
    if DEG == "name-only": return hashlib.sha256(g.encode()).hexdigest()[:24]
    h = hashlib.sha256(g.encode())
    for f in sorted(f for f, gs in WATCH.items() if g in gs):
        s = new_state(f); h.update(repr((f, norm(s))).encode())
    return h.hexdigest()[:24]
try:
    missing = [g for g in guards if not os.path.exists(rec(key(g)))]
except OSError:
    missing = guards
if DEG == "store-open" and not os.access(state, os.R_OK): missing = []
if not missing:
    # ADR 0054 decision 1: the record is scoped to the permission-list state and is NOT spent by a
    # commit. consume-on-use is the rejected design (secret_approval.py single-use consume).
    if DEG == "consume-on-use":
        for g in guards:
            try: os.remove(rec(key(g)))
            except OSError: pass
    done("allow", "approved")

# ADR 0054 decision 2: a subagent payload (agent_id) is the MEASURED unattended signal; permission_mode
# is an ADDITIONAL signal when present. When it is absent AND no subagent keys identify the session, the
# FALLBACK also refuses (2026-10-29 decision, after the field was measured present): an ask under a bypass
# session is silently allowed, so asking on a refuse path is a fail-open. agent-blind ignores the measured
# signal; ask-fallback is the rejected design (asks on the fallback); absent-blanket refuses even when no
# prompt is needed; fallback-claims-unattended makes the fallback message assert something it cannot know.
if unattended and DEG != "ask-not-deny":
    refuse("approval cannot be obtained unattended (permission mode %r, subagent %s): refusing" % (pm, agent))
if pm is None and DEG != "ask-fallback":
    refuse("permission_mode is absent from the payload, so whether a human can answer a prompt cannot be established: refusing%s"
           % (" (unattended)" if DEG == "fallback-claims-unattended" else ""))
diff = git(*(["diff", ref, "--"] if use_wt else ["diff", "--cached", ref, "--"]), *changed).stdout.split("\n")
lines = [l[:160] for l in diff if l[:1] in "+-" and l[:3] not in ("+++", "---")][:20]
if DEG == "terse-reason": lines = []
tag = "[UNCLASSIFIED]" if (cls == "unclassified" and DEG != "single-message") else "[LOOSENING]"
body = ("%s change to %s could not be classified; it needs your decision." % (tag, ", ".join(missing))
        if tag == "[UNCLASSIFIED]" else "%s %s: entries changed below. Confirm to commit." % (tag, ", ".join(missing)))
reason = "%s\ncommit: %s\n%s" % (body, cmd, "\n".join(lines))
try:
    with open(os.path.join(state, "lg-pending-%s-%s" % (sid, cid)), "w") as fh:
        fh.write(" ".join(key(g) for g in missing))
except OSError:
    pass
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask",
                                          "permissionDecisionReason": reason}}))
log("ask", cls); sys.exit(0)
PYEOF
