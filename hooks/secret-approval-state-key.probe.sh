#!/usr/bin/env bash
# secret-approval-state-key.probe.sh — does an approval keyed to a guard's
# permission-list STATE discriminate? Task 3 on docs/features/guard-loosening-approval.md,
# the blocking precondition in spec §8 ("prove the key shape before building on it").
#
# WHAT IT MEASURES. hooks/lib/secret_approval.py today fingerprints shell command
# TEXT. This probe keys it to a guard's permission-list state instead — the state
# being the real bytes + git file mode of the guard's watch-set files (ADR 0052,
# Decision 1, the fourteen-file table), read with `git show` / `git ls-tree` from
# HEAD, never a string the probe made up. It then asks the §8 question through the
# real store (grant -> consume): approved at S1, tested at S1 must match; tested at
# a different S2 must NOT.
#
# THE FALSIFIERS (spec §8, and §10's "passes shared by both stubs discriminate
# nothing"). Every assertion runs unchanged against SEVEN implementations:
#   real          the actual secret_approval fingerprint/grant/consume
#   always-match  check() returns True            (stub)
#   never-match   check() returns False           (stub)
#   ctl:*         four DEGRADED real keys — same store, a worse serializer — the
#                 shapes a silently non-discriminating key would take. They exist
#                 to prove the assertions can SEE a permissive failure, not just
#                 the two cartoon stubs.
# An assertion that BOTH stubs pass discriminates nothing and is counted.
#
# S2 is a realistic loosening, taken from ADR 0052 Decision 2's own list, applied
# to real file bytes: whole-entry add, whole-entry remove, `$` anchor dropped,
# re.IGNORECASE -> 0, sys.exit(1) -> sys.exit(0), plus a file-mode flip that leaves
# content byte-identical. Every mutation asserts its target occurs exactly once; a
# mutation that finds nothing (or twice) is reported MISS and INVALIDATES the probe
# — a falsifier that mutates nothing passes everything.
#
# It is a PROBE, not a test: it measures and prints, and always exits 0 unless the
# fixture cannot be built. The serializer (state -> key text) is PROBE-LOCAL: no
# such function exists in the repo yet. See the report's "what was not measured".
#
# Run: bash hooks/secret-approval-state-key.probe.sh        (from a worktree root)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MODULE="$HERE/lib/secret_approval.py"
[ -r "$MODULE" ] || { printf 'probe: %s is not readable\n' "$MODULE" >&2; exit 1; }
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { printf 'probe: %s is not a git checkout\n' "$ROOT" >&2; exit 1; }

TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export SECRET_GUARD_STATE_DIR="$TMP/state"
mkdir -p "$SECRET_GUARD_STATE_DIR"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

printf 'secret-approval-state-key.probe.sh\n'
printf 'repo   : %s\n' "$ROOT"
printf 'HEAD   : %s\n' "$(git -C "$ROOT" rev-parse HEAD)"
printf 'python : %s\n\n' "$(python3 --version 2>&1)"

python3 - "$ROOT" "$MODULE" <<'PYEOF'
import hashlib, importlib.util, os, subprocess, sys, traceback

ROOT, MODULE = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("secret_approval", MODULE)
sa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sa)

# ---- the watch set: ADR 0052 Decision 1, one row per file, guards it feeds ------
SEC, GIT, WT = "secret", "git", "worktree"
WATCH = {
    "hooks/lib/classify-secret-command.py": (SEC,),
    "hooks/secret-command-guard.sh":        (SEC,),
    "hooks/lib/secret_approval.py":         (SEC,),
    "hooks/git-guard.sh":                   (GIT,),
    "hooks/lib/git_quiet_class.py":         (GIT,),
    "hooks/lib/git_guard_quiet.py":         (GIT,),
    "hooks/lib/classify-git-command.py":    (GIT, WT),
    "hooks/worktree-guard.sh":              (WT,),
    "hooks/lib/worktree_guard_bash_arms.sh": (WT,),
    "hooks/lib/worktree_guard_liveness.sh": (WT,),
    "hooks/reference-transaction":          (WT,),
    "hooks/reference-transaction.mode":     (WT,),
    "hooks/lib/shell_segments.py":          (SEC, GIT, WT),
    "settings.json":                        (SEC, GIT, WT),
}
GUARD_FILE = {SEC: "hooks/secret-command-guard.sh", GIT: "hooks/git-guard.sh",
              WT: "hooks/worktree-guard.sh"}
GUARDS = (SEC, GIT, WT)


def files_of(guard):
    return sorted(p for p, gs in WATCH.items() if guard in gs)


def git(*args):
    return subprocess.run(["git", "-C", ROOT] + list(args), check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout


def read_state_from_head():
    """{path: (mode, bytes)} — real blob bytes and real git mode, from HEAD."""
    st = {}
    for path in WATCH:
        mode = git("ls-tree", "HEAD", "--", path).split()[0].decode()
        st[path] = (mode, git("show", "HEAD:" + path))
    return st


def read_state_from_worktree():
    """Independent second read path (working tree bytes) for the determinism row."""
    st = {}
    for path in WATCH:
        mode = git("ls-tree", "HEAD", "--", path).split()[0].decode()
        with open(os.path.join(ROOT, path), "rb") as fh:
            st[path] = (mode, fh.read())
    return st


class StateUnreadable(Exception):
    pass


# ---- serializers: state -> the text handed to fingerprint() --------------------
def _digest(b):
    return hashlib.sha256(b).hexdigest()


def ser_full(guard, st):
    lines = ["guard:" + guard]
    for p in files_of(guard):
        if p not in st:
            raise StateUnreadable(p)
        mode, data = st[p]
        lines.append("%s\t%s\t%s" % (p, mode, _digest(data)))
    return "\n".join(lines)


def ser_no_mode(guard, st):     # control: content only, git file mode ignored
    lines = ["guard:" + guard]
    for p in files_of(guard):
        if p not in st:
            raise StateUnreadable(p)
        lines.append("%s\t%s" % (p, _digest(st[p][1])))
    return "\n".join(lines)


def ser_no_guard(guard, st):    # control: guard label dropped from the key
    return "\n".join(ser_full(guard, st).split("\n")[1:])


def ser_guard_file_only(guard, st):   # control: spec §5.1 as first worded — the guard's own .sh
    p = GUARD_FILE[guard]
    if p not in st:
        raise StateUnreadable(p)
    return "guard:%s\n%s\t%s\t%s" % (guard, p, st[p][0], _digest(st[p][1]))


def ser_name_only(guard, st):   # control: degenerate key — the guard name, no state at all
    return "guard:" + guard


# ---- implementations: same assertions, swapped key ----------------------------
class StoreKey:
    """The real secret_approval store (grant -> consume), keyed by serializer(state)."""
    def __init__(self, name, serializer):
        self.name, self.ser = name, serializer

    def grant(self, session, guard, st):
        sa.grant(session, sa.fingerprint(self.ser(guard, st)))

    def check(self, session, guard, st):
        try:
            key = sa.fingerprint(self.ser(guard, st))
        except StateUnreadable:
            return False          # cannot name the state -> refuse (fail closed)
        return sa.consume(session, key)


class Const:
    def __init__(self, name, value):
        self.name, self.value = name, value

    def grant(self, session, guard, st):
        pass

    def check(self, session, guard, st):
        return self.value


IMPLS = [
    StoreKey("real", ser_full),
    Const("always", True),
    Const("never", False),
    StoreKey("ctl:no-mode", ser_no_mode),
    StoreKey("ctl:no-guard", ser_no_guard),
    StoreKey("ctl:guard-file-only", ser_guard_file_only),
    StoreKey("ctl:name-only", ser_name_only),
]
STUBS = ("always", "never")
CONTROLS = [i.name for i in IMPLS if i.name.startswith("ctl:")]

# ---- mutations on REAL bytes ---------------------------------------------------
class Miss(Exception):
    pass


def mutate(st, path, old, new, count=1):
    mode, data = st[path]
    text = data.decode("utf-8")
    n = text.count(old)
    if n != count:
        raise Miss("%s: needle occurs %d times, expected %d: %r" % (path, n, count, old[:70]))
    out = dict(st)
    out[path] = (mode, text.replace(old, new).encode("utf-8"))
    return out


def set_mode(st, path, mode):
    cur, data = st[path]
    if cur == mode:
        raise Miss("%s: mode already %s" % (path, mode))
    out = dict(st)
    out[path] = (mode, data)
    return out


S1 = read_state_from_head()

# (id, guard, kind, description, builder(S1) -> S2)
MUTS = [
    ("M1", SEC, "whole-entry remove", "DOTFILE_PATTERNS: drop the .zprofile entry",
     lambda s: mutate(s, "hooks/lib/classify-secret-command.py",
                      '    (r"(^|/)\\.zprofile$", "~/.zprofile"),\n', "")),
    ("M2", SEC, "whole-entry add", "DOTFILE_PATTERNS: add a .npmrc entry",
     lambda s: mutate(s, "hooks/lib/classify-secret-command.py",
                      '    (r"(^|/)\\.zshenv$", "~/.zshenv"),\n',
                      '    (r"(^|/)\\.zshenv$", "~/.zshenv"),\n    (r"(^|/)\\.npmrc$", "~/.npmrc"),\n')),
    ("M3", SEC, "in-place", "regex: drop the $ anchor on credentials.json",
     lambda s: mutate(s, "hooks/lib/classify-secret-command.py",
                      '(r"(^|/)credentials\\.json$"', '(r"(^|/)credentials\\.json"')),
    ("M4", SEC, "in-place", "FOLD_FLAGS = re.IGNORECASE -> 0",
     lambda s: mutate(s, "hooks/lib/classify-secret-command.py",
                      "FOLD_FLAGS = re.IGNORECASE ", "FOLD_FLAGS = 0 ")),
    ("M5", SEC, "in-place", "classifier internal-error exit: sys.exit(1) -> sys.exit(0)",
     lambda s: mutate(s, "hooks/lib/classify-secret-command.py",
                      "fails OPEN on any exit other than 0/2/3.\n        sys.exit(1)",
                      "fails OPEN on any exit other than 0/2/3.\n        sys.exit(0)")),
    ("M6", SEC, "in-place", "secret-command-guard.sh: final block `exit 2` -> `exit 0`",
     lambda s: mutate(s, "hooks/secret-command-guard.sh", "\nexit 2\n", "\nexit 0\n")),
    ("M7", SEC, "in-place", "secret_approval.py: hatch value allowlist -> ^.+$",
     lambda s: mutate(s, "hooks/lib/secret_approval.py",
                      'r"^[A-Za-z0-9._,:/-]+$"', 'r"^.+$"')),
    ("M8", GIT, "whole-entry add", "READ_SUBCOMMANDS (quiet read-only list): add \"stash\"",
     lambda s: mutate(s, "hooks/lib/git_quiet_class.py",
                      '"for-each-ref",\n)', '"for-each-ref", "stash",\n)')),
    ("M9", GIT, "whole-entry remove", "READ_SUBCOMMANDS: remove \"shortlog\"",
     lambda s: mutate(s, "hooks/lib/git_quiet_class.py", '"shortlog", ', "")),
    ("M10", GIT, "whole-entry add", "git-guard.sh main allowlist: add a third judge ledger",
     lambda s: mutate(s, "hooks/git-guard.sh",
                      "      coding-memory/compliance-judge/verdicts.jsonl) ;;\n",
                      "      coding-memory/compliance-judge/verdicts.jsonl) ;;\n"
                      "      coding-memory/third-judge/verdicts.jsonl) ;;\n")),
    ("M11", GIT, "whole-entry remove", "git-guard.sh main allowlist: drop a judge ledger",
     lambda s: mutate(s, "hooks/git-guard.sh",
                      "      coding-memory/observability-judge/verdicts.jsonl) ;;\n", "")),
    ("M12", GIT, "in-place", "git-guard.sh prints-and-exits branch: `exit 2` -> `exit 0`",
     lambda s: mutate(s, "hooks/git-guard.sh", '"$prints_and_exits" >&2\n    exit 2',
                      '"$prints_and_exits" >&2\n    exit 0')),
    ("M13", WT, "whole-entry add", "worktree-guard.sh Arm A exemption list: add hooks/*",
     lambda s: mutate(s, "hooks/worktree-guard.sh",
                      "  rules/*|skills/*) exit 0 ;;\n",
                      "  rules/*|skills/*) exit 0 ;;\n  hooks/*) exit 0 ;;\n")),
    ("M14", WT, "whole-entry remove", "worktree-guard.sh Arm A exemption list: drop rules/*|skills/*",
     lambda s: mutate(s, "hooks/worktree-guard.sh", "  rules/*|skills/*) exit 0 ;;\n", "")),
    ("M15", WT, "in-place", "settings.json env.WORKTREE_GUARD_MODE \"log\" -> \"deny\"",
     lambda s: mutate(s, "settings.json", '"WORKTREE_GUARD_MODE": "log"',
                      '"WORKTREE_GUARD_MODE": "deny"')),
    ("M16", WT, "in-place", "reference-transaction.mode switch: log -> deny",
     lambda s: mutate(s, "hooks/reference-transaction.mode", "\n\nlog\n", "\n\ndeny\n")),
    ("M17", WT, "mode-only", "hooks/worktree-guard.sh 100755 -> 100644, content identical",
     lambda s: set_mode(s, "hooks/worktree-guard.sh", "100644")),
    ("M18", SEC, "shared-file", "shell_segments.py WRAPPERS: drop \"nohup\" (read by 8 guards)",
     lambda s: mutate(s, "hooks/lib/shell_segments.py", ', "nohup")', ")")),
]
MUT = {m[0]: m for m in MUTS}

built = {}
miss = []
for mid, guard, kind, desc, fn in MUTS:
    try:
        built[mid] = fn(S1)
    except Miss as exc:
        miss.append((mid, str(exc)))

# ---- assertions ---------------------------------------------------------------
# Each returns (observed_steps, expected_steps) for an impl and a fresh session id.
ASSERTIONS = []


def assertion(aid, desc, fn):
    ASSERTIONS.append((aid, desc, fn))


def approve_then_test(guard, s_approved, s_tested, expect):
    def run(impl, sess):
        impl.grant(sess, guard, s_approved)
        return [impl.check(sess, guard, s_tested)], [expect]
    return run


for g in GUARDS:
    assertion("A-same-" + g, "approved at S1, tested at S1 (%s) -> MATCH" % g,
              approve_then_test(g, S1, S1, True))

assertion("A-reread", "S1 re-read from the working tree (independent read path) -> MATCH",
          approve_then_test(SEC, S1, read_state_from_worktree(), True))

for mid, guard, kind, desc, _fn in MUTS:
    if mid not in built:
        continue
    # M18 feeds every guard; the rest feed the one guard named.
    changed = [pth for pth in WATCH if built[mid][pth] != S1[pth]]
    # a guard is tested only if the mutation touched a file ITS key covers
    gs = [g for g in GUARDS if any(g in WATCH[pth] for pth in changed)]
    for g in gs:
        assertion("%s/%s" % (mid, g[:3]),
                  "[%s] %s -> NO MATCH (%s)" % (kind, desc, g),
                  approve_then_test(g, S1, built[mid], False))

# precision rows: a change in a file the guard does NOT read must leave its approval valid
assertion("P1", "git-only file changed (M8) -> secret approval still MATCHES",
          approve_then_test(SEC, S1, built["M8"], True) if "M8" in built else None)
assertion("P2", "secret-only file changed (M1) -> worktree approval still MATCHES",
          approve_then_test(WT, S1, built["M1"], True) if "M1" in built else None)

def _c1(impl, sess):
    impl.grant(sess, SEC, S1)
    return [impl.check(sess, GIT, S1)], [False]


assertion("C1", "approved as secret, tested as git (S1) -> NO MATCH", _c1)


def _missing(impl, sess):
    impl.grant(sess, SEC, S1)
    gone = dict(S1)
    del gone["hooks/lib/classify-secret-command.py"]
    return [impl.check(sess, SEC, gone)], [False]


assertion("E1", "a watched file is unreadable -> NO MATCH (fail closed, no key built)", _missing)


def _session(impl, sess):
    impl.grant(sess + "-A", SEC, S1)
    return [impl.check(sess + "-B", SEC, S1)], [False]


assertion("E2", "approved in session A, tested in session B (S1) -> NO MATCH", _session)


def _single_use(impl, sess):
    impl.grant(sess, SEC, S1)
    return [impl.check(sess, SEC, S1), impl.check(sess, SEC, S1)], [True, False]


assertion("E3", "match once, then again -> MATCH then NO MATCH (single use)", _single_use)


def _survives(impl, sess):
    impl.grant(sess, SEC, S1)
    first = impl.check(sess, SEC, built["M1"])    # a mismatch must not burn the grant
    second = impl.check(sess, SEC, S1)
    return [first, second], [False, True]


assertion("E4", "mismatch at S2 first, then S1 -> NO MATCH then MATCH (a miss keeps the grant)",
          _survives)

ASSERTIONS = [a for a in ASSERTIONS if a[2] is not None]

# ---- run ------------------------------------------------------------------------
results = {}      # aid -> {impl: (passed, observed, expected)}
for aid, desc, fn in ASSERTIONS:
    results[aid] = {}
    for n, impl in enumerate(IMPLS):
        sess = "probe-%s-%s-%d" % (aid.replace("/", "_"), impl.name.replace(":", "_"), n)
        try:
            obs, exp = fn(impl, sess)
            results[aid][impl.name] = (obs == exp, obs, exp)
        except Exception:
            results[aid][impl.name] = (False, "ERROR", traceback.format_exc(limit=1))

# ---- report ---------------------------------------------------------------------
names = [i.name for i in IMPLS]
print("S1 = HEAD blobs + git modes of the 14 watched files (ADR 0052 Decision 1).")
print("Per-guard key covers: secret=%d files, git=%d files, worktree=%d files."
      % tuple(len(files_of(g)) for g in GUARDS))
print("Cell: P = the implementation satisfied the assertion, F = it did not.\n")

if miss:
    print("!! MUTATION MISS — the probe is INVALID for these (target not found exactly once):")
    for mid, why in miss:
        print("   %s: %s" % (mid, why))
    print()

hdr = "%-9s %-4s " % ("id", "") + " ".join("%-6s" % n.replace("ctl:", "c:")[:6] for n in names)
print(hdr)
print("-" * len(hdr))
nondisc, stub_pass_always_only, stub_pass_never_only = [], 0, 0
real_fail = []
for aid, desc, _fn in ASSERTIONS:
    r = results[aid]
    cells = " ".join("%-6s" % ("P" if r[n][0] else "F") for n in names)
    both = r["always"][0] and r["never"][0]
    flag = "  <-- BOTH STUBS PASS" if both else ""
    if both:
        nondisc.append(aid)
    if not r["real"][0]:
        real_fail.append(aid)
    print("%-9s      %s%s" % (aid, cells, flag))
print()
for aid, desc, _fn in ASSERTIONS:
    print("  %-8s %s" % (aid, desc))

n_assert = len(ASSERTIONS)
real_pass = sum(1 for a in results if results[a]["real"][0])
alw_pass = sum(1 for a in results if results[a]["always"][0])
nev_pass = sum(1 for a in results if results[a]["never"][0])
print("\n== summary ==")
print("assertions run                     : %d" % n_assert)
print("real passes                        : %d / %d" % (real_pass, n_assert))
print("always-match stub passes           : %d / %d   (expect: only the NO-MATCH rows fail it)" % (alw_pass, n_assert))
print("never-match stub passes            : %d / %d   (expect: only the MATCH rows fail it)" % (nev_pass, n_assert))
print("passed by BOTH stubs (discriminate nothing): %d  %s" % (len(nondisc), nondisc))
print("real FAILS                         : %d  %s" % (len(real_fail), real_fail))
for c in CONTROLS:
    fails = [a for a in results if not results[a][c][0]]
    print("%-20s fails %2d: %s" % (c, len(fails), fails))
print("\nper-assertion observed/expected for any real failure:")
for a in real_fail:
    print("  %s real observed=%r expected=%r" % (a, results[a]["real"][1], results[a]["real"][2]))
if not real_fail:
    print("  (none)")

# invalidity gates: a probe whose own preconditions failed must not read as a pass
inval = []
if miss:
    inval.append("%d mutation(s) missed their target" % len(miss))
if nondisc:
    inval.append("%d assertion(s) are passed by both stubs" % len(nondisc))
if alw_pass == n_assert:
    inval.append("the always-match stub passes every assertion")
if nev_pass == n_assert:
    inval.append("the never-match stub passes every assertion")
print("\nPROBE VALIDITY: %s" % ("INVALID — " + "; ".join(inval) if inval else "ok (both stubs fail at least one assertion and no assertion is shared)"))

# A probe that declares itself INVALID, or that saw a real failure, must not exit 0:
# a caller checking only the status would otherwise read "INVALID" as a pass.
PROBE_RC = 1 if (inval or real_fail) else 0

# ---- properties of the EXISTING module, measured as-is -------------------------
print("\n== secret_approval.py, existing entry points, handed real permission-list text ==")
secret_text = ser_full(SEC, S1)
real_block = [l for l in S1["hooks/lib/classify-secret-command.py"][1].decode().split("\n")
              if l.lstrip().startswith('(r"')]   # the real DOTFILE_PATTERNS lines
real_block = "\n".join(real_block)
print("real DOTFILE_PATTERNS text: %d lines, handed to `secret_approval.py id`" % real_block.count("\n"))
p = subprocess.run([sys.executable, MODULE, "id", real_block], stdout=subprocess.PIPE,
                   stderr=subprocess.PIPE, universal_newlines=True)
print("  id mode      rc=%d   stderr: %s" % (p.returncode, p.stderr.strip()[:110]))
p = subprocess.run([sys.executable, MODULE, "fingerprint", real_block], stdout=subprocess.PIPE,
                   stderr=subprocess.PIPE, universal_newlines=True)
print("  fingerprint  rc=%d   stdout: %s" % (p.returncode, p.stdout.strip()))
print("  -> `id` mode (the approvable-check path) REFUSES real list text; only the raw fingerprint() is usable.")

raw_all = b"".join(S1[p][1] for p in files_of(SEC)).decode("utf-8", "replace")
p = subprocess.run([sys.executable, MODULE, "fingerprint", raw_all], stdout=subprocess.PIPE,
                   stderr=subprocess.PIPE, universal_newlines=True)
print("raw bytes of the secret key's %d files (%d bytes) as one argv: rc=%d" %
      (len(files_of(SEC)), len(raw_all.encode()), p.returncode))

fp = sa.fingerprint
print("\ncanonical_text() collisions on the real serialization (secret S1):")
print("  fp(T) == fp(T + trailing whitespace)         : %s" % (fp(secret_text) == fp(secret_text + "\n  \n")))
print("  fp(T) == fp('SECRET_EXEMPT=x ' + T)          : %s" % (fp(secret_text) == fp("SECRET_EXEMPT=x " + secret_text)))
print("  fp(T) == fp(leading whitespace + T)          : %s" % (fp(secret_text) == fp("  \n" + secret_text)))
print("  id length (hex) / space                      : %d / 2^%d" % (sa.ID_LEN, sa.ID_LEN * 4))

print("\n== informational: a cosmetic edit (comment text only, no behaviour change) ==")
try:
    cos = mutate(S1, "hooks/lib/classify-secret-command.py",
                 "# (regex, human label). Anchored on the basename",
                 "# (regex, human label). Anchored on the basename [reworded]")
    r = StoreKey("real", ser_full)
    r.grant("probe-cosmetic", SEC, S1)
    print("  real key, secret guard, comment-only edit -> %s"
          % ("MATCH" if r.check("probe-cosmetic", SEC, cos) else "NO MATCH (a whole-file digest key over-prompts on cosmetic edits)"))
except Miss as exc:
    print("  MISS: %s" % exc)

print("\nsizes of the real states, bytes of watched content per guard:")
for g in GUARDS:
    print("  %-9s %6d bytes over %d files" % (g, sum(len(S1[p][1]) for p in files_of(g)), len(files_of(g))))

sys.exit(PROBE_RC)
PYEOF
rc=$?
printf '\npython rc=%s\n' "$rc"
printf 'unconsumed approval records in the throwaway state dir (grants no check spent; removed on exit): %s\n' "$(find "$SECRET_GUARD_STATE_DIR" -type f | wc -l | tr -d ' ')"
exit "$rc"
