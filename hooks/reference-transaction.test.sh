#!/usr/bin/env bash
# reference-transaction.test.sh — unit tests for hooks/reference-transaction (layer 2).
#
# Written BEFORE the hook exists (card task 6a, TDD). Every case below is expected
# to fail until the implementation lands; the suite's job today is to be red for
# the right reason — "hook not found", not "assertion never evaluated". The two
# controls that enforce that are HOOK_PRESENT (the hook is on disk and copied into
# the armed hooksPath) and LOG_LIVE (some invocation in this run has been observed
# to append an attribution line).
#
# Layer 2 is NOT a Claude Code hook. Git invokes it directly, once per ref
# transaction, with one argument (`prepared`|`committed`|`aborted`) and the
# transaction's lines on stdin as `<old-value> SP <new-value> SP <ref-name> LF`.
# That contract was measured live rather than taken from memory — probe dumps in
# a throwaway repo under $TMPDIR, git 2.50.1 (Apple Git-155), ref-format `files`:
#
#   ARGC=1  ARGV[0]=prepared
#   --- STDIN ---
#   0000000000000000000000000000000000000000 ref:refs/heads/other HEAD
#
# So the suite drives the hook two ways, and both are needed:
#
#   * END TO END, through a real git — a throwaway repo with core.hooksPath armed.
#     The pinned matrix (four `worktree add` forms, switch/checkout/--detach/sh -c/
#     env -C, the mkdir forgery) is about WHICH LOCK GIT ACTUALLY HOLDS, and only a
#     real git can establish that. Nothing in this file simulates it.
#   * DIRECTLY, `bash hooks/reference-transaction <stage> < lines` — for the stage
#     guard, the stdin shapes and the probe failures, which git will not produce on
#     demand.
#
# There is no `.sh` on the hook: git resolves hooks by exact filename. That also
# means it has no `X.sh`↔`X.test.sh` sibling, so hooks/lib/write-test-marker.py is
# deliberately NOT called at the tally below — it would report "no tracked subject"
# and write nothing. The pair rule cannot apply to a filename git owns.
#
# Run: bash hooks/reference-transaction.test.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/reference-transaction"

# Physical path, not the one mktemp hands back. On macOS `mktemp -d` returns the
# /var symlink form while `git rev-parse` resolves to /private/var — and this hook
# COMPARES two rev-parse answers for equality, so a fixture path built from the
# symlink form would make the scope test pass or fail for the wrong reason.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
GIT_REAL="$(command -v git)"

# The attribution log the hook appends its clause lines to. Same knob name as
# layer 1's (WORKTREE_GUARD_STATE_DIR) so one override moves both; task 6c
# measured that an inherited variable survives the git → hook hop, which is what
# makes this reachable at all from an end-to-end case.
STATE_DIR="$TMP/state"
LOG="$STATE_DIR/reference-transaction.log"
export WORKTREE_GUARD_STATE_DIR="$STATE_DIR"
mkdir -p "$STATE_DIR"

# The armed hooksPath: a directory holding a copy of the hook, pointed at by
# core.hooksPath in each fixture repo. A copy rather than a symlink so a case can
# swap in a stub without touching the tracked file.
HOOKS_DIR="$TMP/hooksdir"
mkdir -p "$HOOKS_DIR"
# An empty hooks directory, for the fixture housekeeping that must NOT be judged —
# resetting a tree the previous deny left dirty is not a case, and running it
# through the armed hook would let one case's cleanup decide the next case.
NOHOOKS="$TMP/nohooks"
mkdir -p "$NOHOOKS"

pass=0; fail=0; skip=0; n=0

ok()   { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf 'FAIL — %s\n' "$1"; fail=$((fail+1)); }
# A skip is counted, not merely printed. A case this suite cannot construct is a
# gap in coverage; leaving it out of the totals lets "0 failed" read as "every
# scenario is pinned", which is the one thing the summary line must not do.
skipped() { printf 'skip — %s\n' "$1"; skip=$((skip+1)); }

# ------------------------------------------------------------ the two controls ---

# Control 1. Without the hook on disk every end-to-end case runs an unarmed git,
# which allows everything — and "the worktree was created" then passes against no
# guard at all. This is the falsifier for the whole ALLOW group.
HOOK_PRESENT=0
if [ -f "$HOOK" ] && [ -r "$HOOK" ]; then
  cp "$HOOK" "$HOOKS_DIR/reference-transaction" && chmod +x "$HOOKS_DIR/reference-transaction" &&
    HOOK_PRESENT=1
fi

# Control 2. A negative log assertion is VACUOUS until something in this run has
# been seen to append a line: with no hook on disk, "nothing was appended" is true
# of every conceivable implementation. LOG_LIVE is set by the first case that
# observes a line, and assert_log_empty refuses to count until it is.
LOG_LIVE=0

# The cumulative attribution record. Per-case assertions reset $LOG, so GROUP Z
# reads this instead: it is the whole run's clause history, and it is what makes
# "both clauses fired separately" an assertion rather than a hope.
ATTR="$TMP/attribution.all"
: > "$ATTR"

log_reset() { rm -f "$LOG"; }

log_clauses() { # the decision+clause field of every line the last case produced
  [ -f "$LOG" ] || return 0
  cut -f2 "$LOG"
}

log_harvest() { # fold the last case's lines into the cumulative record
  if [ -f "$LOG" ] && [ -s "$LOG" ]; then
    cat "$LOG" >> "$ATTR"
    LOG_LIVE=1
  fi
}

log_lines() {
  [ -f "$LOG" ] || { printf '0'; return; }
  grep -c . "$LOG" || true
}

assert_log_has() { # $1 desc, $2 required clause (exact field value)
  if log_clauses | grep -qxF -- "$2"; then ok "$1"; else
    printf 'FAIL — %s\n  want clause: %s\n  log:\n%s\n' "$1" "$2" \
      "$(cat "$LOG" 2>/dev/null)"; fail=$((fail+1))
  fi
}

assert_log_lacks() { # $1 desc, $2 forbidden clause
  if [ "$LOG_LIVE" != 1 ]; then
    printf 'FAIL — %s (VACUOUS: no attribution line has been observed in this run)\n' "$1"
    fail=$((fail+1)); return
  fi
  if log_clauses | grep -qxF -- "$2"; then
    printf 'FAIL — %s (found forbidden clause: %s)\n%s\n' "$1" "$2" "$(cat "$LOG")"
    fail=$((fail+1))
  else ok "$1"; fi
}

assert_log_empty() { # $1 desc
  if [ "$LOG_LIVE" != 1 ]; then
    printf 'FAIL — %s (VACUOUS: no attribution line has been observed in this run)\n' "$1"
    fail=$((fail+1)); return
  fi
  local c; c="$(log_lines)"
  if [ "$c" = 0 ]; then ok "$1"; else
    printf 'FAIL — %s (want 0 attribution lines, got %s)\n%s\n' "$1" "$c" "$(cat "$LOG")"
    fail=$((fail+1))
  fi
}

# --------------------------------------------------------------- direct runner ---

# Invokes the hook the way git does: argv[1] is the stage, the transaction lines
# arrive on stdin. RUN_ENV and RUN_STAGE_ABSENT are per-case knobs the runner
# consumes and clears, so neither can leak into the next case.
RUN_ENV=()
RUN_STAGE_ABSENT=0
got=0; out=""; err=""
_run() { # $1 cwd, $2 stage, $3 stdin text
  n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
  if [ "$RUN_STAGE_ABSENT" = 1 ]; then
    ( cd "$1" && printf '%s' "$3" | env ${RUN_ENV[@]+"${RUN_ENV[@]}"} \
        bash "$HOOK" ) >"$out" 2>"$err"
  else
    ( cd "$1" && printf '%s' "$3" | env ${RUN_ENV[@]+"${RUN_ENV[@]}"} \
        bash "$HOOK" "$2" ) >"$out" 2>"$err"
  fi
  got=$?
  RUN_ENV=(); RUN_STAGE_ABSENT=0
}

# deny: a non-zero exit. Git turns that into rc=128 at `prepared` and ignores it
# everywhere else, so this suite asserts non-zero and not a specific code — the
# card fixes no exit-2 convention for layer 2 (boundary table preamble).
d_deny() { # $1 desc, $2 cwd, $3 stage, $4 stdin, [$5 required stderr substring]
  local desc="$1"
  log_reset; _run "$2" "$3" "$4"; log_harvest
  if [ "$got" -eq 0 ]; then
    printf 'FAIL — %s (want non-zero, got 0)\n  stderr: %s\n' "$desc" "$(cat "$err")"
    fail=$((fail+1)); return
  fi
  if [ $# -ge 5 ] && ! grep -qF -- "$5" "$err"; then
    printf 'FAIL — %s\n  want (substring): %s\n  stderr: %s\n' "$desc" "$5" "$(cat "$err")"
    fail=$((fail+1)); return
  fi
  ok "$desc"
}

d_allow() { # $1 desc, $2 cwd, $3 stage, $4 stdin — exit 0, and stdout/stderr silent
  local desc="$1"
  log_reset; _run "$2" "$3" "$4"; log_harvest
  if [ "$got" -ne 0 ]; then
    printf 'FAIL — %s (want exit 0, got %s)\n  stderr: %s\n' "$desc" "$got" "$(cat "$err")"
    fail=$((fail+1)); return
  fi
  if [ -s "$out" ]; then
    printf 'FAIL — %s (stdout not empty: %s)\n' "$desc" "$(cat "$out")"; fail=$((fail+1)); return
  fi
  if [ -s "$err" ]; then
    printf 'FAIL — %s (stderr not empty: %s)\n' "$desc" "$(cat "$err")"; fail=$((fail+1)); return
  fi
  ok "$desc"
}

assert_stderr_empty() { # $1 desc — the other half of boundary 35's silent deny
  if [ -s "$err" ]; then
    printf 'FAIL — %s (stderr not empty: %s)\n' "$1" "$(cat "$err")"; fail=$((fail+1))
  else ok "$1"; fi
}

# ------------------------------------------------------------ end-to-end runner ---

git_q() { "$GIT_REAL" -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }
# Housekeeping git: the same git with the hook deliberately disarmed.
git_bare_hooks() { git_q -c core.hooksPath="$NOHOOKS" "$@"; }

e_rc=0
e_run() { # $1 cwd, $2.. the command — runs under the ARMED hook
  n=$((n+1)); out="$TMP/out.$n"; err="$TMP/err.$n"
  local dir="$1"; shift
  log_reset
  ( cd "$dir" && "$@" ) >"$out" 2>"$err"
  e_rc=$?
  log_harvest
}

e_deny() { # $1 desc, $2 cwd, $3.. command — git must exit 128
  local desc="$1" dir="$2"; shift 2
  e_run "$dir" "$@"
  if [ "$e_rc" -eq 128 ]; then ok "$desc"; else
    printf 'FAIL — %s (want git rc=128, got %s)\n  stderr: %s\n' "$desc" "$e_rc" "$(cat "$err")"
    fail=$((fail+1))
  fi
}

e_allow() { # $1 desc, $2 cwd, $3.. command — git must exit 0
  local desc="$1" dir="$2"; shift 2
  e_run "$dir" "$@"
  if [ "$e_rc" -eq 0 ]; then ok "$desc"; else
    printf 'FAIL — %s (want git rc=0, got %s)\n  stderr: %s\n' "$desc" "$e_rc" "$(cat "$err")"
    fail=$((fail+1))
  fi
}

assert_head() { # $1 desc, $2 repo, $3 expected symbolic-ref
  local h; h="$(git_bare_hooks -C "$2" symbolic-ref HEAD 2>/dev/null)" || h='<detached>'
  if [ "$h" = "$3" ]; then ok "$1"; else
    printf 'FAIL — %s (want HEAD %s, got %s)\n' "$1" "$3" "$h"; fail=$((fail+1))
  fi
}

assert_worktree_listed() { # $1 desc, $2 repo, $3 path
  if git_bare_hooks -C "$2" worktree list 2>/dev/null | grep -qF -- "$3"; then ok "$1"; else
    printf 'FAIL — %s (not in git worktree list)\n%s\n' "$1" \
      "$(git_bare_hooks -C "$2" worktree list 2>&1)"; fail=$((fail+1))
  fi
}

assert_last_stderr_lacks() { # $1 desc, $2 forbidden substring
  if [ "$HOOK_PRESENT" != 1 ]; then
    printf 'FAIL — %s (VACUOUS: the hook is not on disk, so nothing wrote stderr)\n' "$1"
    fail=$((fail+1)); return
  fi
  if grep -qiF -- "$2" "$err"; then
    printf 'FAIL — %s (found forbidden substring: %s)\n  stderr: %s\n' "$1" "$2" "$(cat "$err")"
    fail=$((fail+1)); return
  fi
  ok "$1"
}

assert_last_stderr_has() { # $1 desc, $2 required substring
  if grep -qF -- "$2" "$err"; then ok "$1"; else
    printf 'FAIL — %s\n  want (substring): %s\n  stderr: %s\n' "$1" "$2" "$(cat "$err")"
    fail=$((fail+1))
  fi
}

# ------------------------------------------------------------------- fixtures ---

# The tree the deny cases leave behind is NOT clean: vetoing the HEAD write does
# not undo the checkout, and the destination branch's content stays staged (the
# card's blocking finding, measured). Every deny case therefore hands the fixture
# to the next one dirty, and the reset runs with hooks disarmed so one case's
# housekeeping can never be judged as the next case's subject.
reset_fixture() { # $1 repo
  git_bare_hooks -C "$1" reset --hard -q HEAD >/dev/null 2>&1
  git_bare_hooks -C "$1" clean -fdq >/dev/null 2>&1
}

mk_repo() { # $1 absolute path, $2.. extra branch names — a primary checkout, hook armed
  mkdir -p "$1"
  git_q -C "$1" init -q
  mkdir -p "$1/sub"
  printf 'v1\n' > "$1/f.txt"
  printf 's\n'  > "$1/sub/s.txt"
  git_q -C "$1" add . >/dev/null 2>&1
  git_q -C "$1" commit -q -m init
  git_q -C "$1" config core.hooksPath "$HOOKS_DIR"
  local b
  for b in "${@:2}"; do git_q -C "$1" branch "$b" >/dev/null 2>&1; done
}

# A `git` shim ahead of the real one on PATH, for the probe-failure cases the hook
# cannot be talked into any other way. Every knob is an environment variable so a
# case bends exactly one rev-parse and leaves the rest real — a stub that answered
# everything would let an implementation pass this suite without calling git.
mk_git_stub() {
  mkdir -p "$TMP/stub"
  cat > "$TMP/stub/git" <<STUB
#!/bin/sh
# knobs: STUB_FAIL_PROBE (rev-parse flag -> exit 128, no output)
#        STUB_EMPTY_PROBE (rev-parse flag -> exit 0, no output)
#        STUB_REF_FORMAT  (--show-ref-format -> print this, exit 0)
is_rp=0; probe=""
for a in "\$@"; do
  case "\$a" in
    rev-parse) is_rp=1 ;;
    --show-ref-format|--absolute-git-dir|--git-common-dir|--git-dir) probe="\$a" ;;
  esac
done
if [ "\$is_rp" = 1 ] && [ -n "\$probe" ]; then
  if [ "\$probe" = "--show-ref-format" ] && [ -n "\${STUB_REF_FORMAT:-}" ]; then
    printf '%s\n' "\$STUB_REF_FORMAT"; exit 0
  fi
  [ "\$probe" = "\${STUB_FAIL_PROBE:-}" ]  && exit 128
  [ "\$probe" = "\${STUB_EMPTY_PROBE:-}" ] && exit 0
fi
exec "$GIT_REAL" "\$@"
STUB
  chmod +x "$TMP/stub/git"
  printf '%s' "$TMP/stub:$PATH"
}

# The transaction lines the measured contract produces, spelled out once. HEAD_TX
# is a symref move (`git switch`), OID_TX an OID write (`git switch --detach`),
# BRANCH_TX an ordinary branch advance (`git commit`) — the one the hook must not
# gate at all.
ZERO='0000000000000000000000000000000000000000'
ONE='7bf398dfa9945d65d07bc885cf264efbbd9e112f'
HEAD_TX="$ZERO ref:refs/heads/other HEAD
"
OID_TX="$ZERO $ONE HEAD
"
BRANCH_TX="$ZERO $ONE refs/heads/other
"

# ================================================================= GROUP H ===
# The controls. Neither is a scenario; both decide whether the rest of the file
# is evidence. Run first so a red suite says WHY in its first two lines.

if [ "$HOOK_PRESENT" = 1 ]; then
  ok 'H1 the hook is on disk and copied into the armed hooksPath'
else
  bad "H1 the hook is on disk and copied into the armed hooksPath (missing: $HOOK)"
fi

PRIMARY="$TMP/repos/proj"
mk_repo "$PRIMARY" other d1 d2 d3 d4 d5 d6 d7 wtb1
LINKED="$TMP/repos/linked"
git_q -C "$PRIMARY" worktree add -q "$LINKED" -b linkbr >/dev/null 2>&1

# H2 — the log control. A HEAD transaction at `prepared` in the primary checkout
# with the lock held must append exactly one attribution line. Until this passes,
# every assert_log_empty/assert_log_lacks below reports itself vacuous rather than
# passing, and GROUP Z has nothing to count.
: > "$PRIMARY/.git/HEAD.lock"
log_reset
_run "$PRIMARY" prepared "$HEAD_TX"
if [ "$(log_lines)" = 1 ]; then
  LOG_LIVE=1; ok 'H2 the attribution log can be written in this run (control for every log case)'
else
  printf 'FAIL — H2 the attribution log can be written in this run (want 1 line, got %s)\n' \
    "$(log_lines)"; fail=$((fail+1))
fi
log_harvest
rm -f "$PRIMARY/.git/HEAD.lock"

# ================================================================= GROUP T ===
# Feature: the stage guard. Only `prepared` can veto — a non-zero exit at
# `aborted` or `committed` is IGNORED by git (rc=0, the ref moves anyway,
# measured), so a hook that judged at those stages would not block anything
# extra; it would print a refusal for a move that then succeeded, which is a
# message contradicting the tree. Boundary 35.
#
# Every case here holds the primary's HEAD.lock, so the lock clause WOULD fire if
# the stage guard let it. That is what makes T2/T3 falsifiable: an implementation
# that judges at every stage fails them, and passes if the fixture were clean.

: > "$PRIMARY/.git/HEAD.lock"

# T1 — the control for T2 and T3. Same lock, same transaction, `prepared`: deny.
d_deny 'T1 prepared + HEAD.lock held: denies (control for T2/T3)' \
  "$PRIMARY" prepared "$HEAD_TX"
assert_log_has 'T1 …attributed to the lock clause' 'DENY primary-HEAD-lock-held'

# T2/T3 — Scenario: The hook says nothing at the stages it cannot veto.
d_allow 'T2 committed + HEAD.lock held: exits 0, silent' "$PRIMARY" committed "$HEAD_TX"
assert_log_empty 'T2 …and appends nothing to the attribution log'
d_allow 'T3 aborted + HEAD.lock held: exits 0, silent'   "$PRIMARY" aborted   "$HEAD_TX"
assert_log_empty 'T3 …and appends nothing to the attribution log'

# T4/T5 — Boundary 35. An UNRECOGNISED stage is not `committed`: it may be one
# that can veto, so it takes the policy default and denies. With NO message —
# suppressing it keeps an ineffective refusal from being announced as an
# effective one.
d_deny 'T4 an unrecognised stage denies' "$PRIMARY" 'bogus' "$HEAD_TX"
assert_stderr_empty 'T4 …and says nothing on stderr'
RUN_STAGE_ABSENT=1
d_deny 'T5 an absent stage argument denies' "$PRIMARY" '' "$HEAD_TX"
assert_stderr_empty 'T5 …and says nothing on stderr'

rm -f "$PRIMARY/.git/HEAD.lock"

# ================================================================= GROUP X ===
# Feature: the transaction lines. Boundaries 32 and 37 — the ref name is the only
# field that decides whether the transaction touches HEAD, so an unparseable line
# is an undecidable transaction, and one bad line makes the WHOLE transaction
# unclassifiable rather than just that ref.
#
# The lock is held throughout, so a bail that reached the lock test would deny for
# the wrong reason. X5 and X8 are the discriminators: they must exit 0 AND log
# nothing, which no implementation that judged every ref can do.

: > "$PRIMARY/.git/HEAD.lock"

d_deny 'X1 a line of two fields denies'   "$PRIMARY" prepared "$ZERO $ONE
"
d_deny 'X2 a line of four fields denies'  "$PRIMARY" prepared "$ZERO $ONE refs/heads/x extra
"
d_deny 'X3 an empty line among lines denies' "$PRIMARY" prepared "$BRANCH_TX
"
d_deny 'X4 no lines at all denies (boundary 37)' "$PRIMARY" prepared ''

# X5 — Scenario: An ordinary commit is not gated. The transaction writes
# refs/heads/<b> and never HEAD, so the ref test bails before the lock test is
# reached. The lock IS held, so an implementation gating every ref write denies
# here — and committing in the primary checkout is not what this card stops.
d_allow 'X5 a non-HEAD ref alone is not gated' "$PRIMARY" prepared "$BRANCH_TX"
assert_log_empty 'X5 …and nothing is attributed, because no clause was reached'

# X6 — one HEAD line among several gates the whole transaction. `git rebase`
# writes HEAD, then refs/heads/<b>, then HEAD.
d_deny 'X6 a HEAD line among several gates the transaction' "$PRIMARY" prepared \
  "$BRANCH_TX$HEAD_TX"
assert_log_has 'X6 …attributed to the lock clause' 'DENY primary-HEAD-lock-held'

# X7 — a final line with no trailing LF is still a line. Dropping it would make
# the single-line HEAD transaction git actually sends invisible on any git that
# stops terminating the last line.
d_deny 'X7 a last line with no trailing newline is still read' "$PRIMARY" prepared \
  "$ZERO ref:refs/heads/other HEAD"

# X8 — the ref test is EQUALITY, not a prefix or a substring. `refs/heads/HEAD`
# and `HEADS` both contain HEAD and neither is it; matching loosely would gate
# ordinary branch work in every repo on the machine.
d_allow 'X8a a ref named refs/heads/HEAD is not HEAD' "$PRIMARY" prepared \
  "$ZERO $ONE refs/heads/HEAD
"
assert_log_empty 'X8a …and nothing is attributed'
d_allow 'X8b a ref named HEADS is not HEAD' "$PRIMARY" prepared \
  "$ZERO $ONE HEADS
"
assert_log_empty 'X8b …and nothing is attributed'

rm -f "$PRIMARY/.git/HEAD.lock"

# ================================================================= GROUP K ===
# Feature: the ref backend. Boundary 28 — under `reftable` there is no
# .git/HEAD.lock, so the deny clause can never fire and the lock rule allows
# EVERY HEAD write. That is a fail-open across an entire backend rather than a
# missed shape, so the hook refuses to arm on a backend it does not implement.

RT="$TMP/repos/reftable"
mkdir -p "$RT"
if git_q -C "$TMP" init -q --ref-format=reftable "$RT" >/dev/null 2>&1 && [ -d "$RT/.git" ]; then
  printf 'v1\n' > "$RT/f.txt"
  git_q -C "$RT" add . >/dev/null 2>&1
  git_q -C "$RT" commit -q -m init
  git_q -C "$RT" config core.hooksPath "$HOOKS_DIR"
  git_q -C "$RT" branch other >/dev/null 2>&1

  # K1 — the refusal itself, end to end through a real reftable repo.
  e_deny 'K1 reftable: git switch is refused rather than silently allowed' \
    "$RT" "$GIT_REAL" switch other
  assert_head 'K1 …and HEAD did not move' "$RT" 'refs/heads/main'
  assert_log_has 'K1 …attributed to the backend clause' 'DENY backend-not-files'
  # The message contract, boundary 28: it names what it read, says the guard does
  # not implement it, and does NOT claim the HEAD move was itself unsafe — the
  # user is being told the guard is blind here, not that they did something wrong.
  assert_last_stderr_has 'K1 …the message names the backend it read' 'reftable'
  assert_last_stderr_has 'K1 …the message says the guard does not implement it' \
    'does not implement'
  assert_last_stderr_lacks 'K1 …and does not call the HEAD move unsafe' 'unsafe'
else
  skipped 'K1 reftable: git switch is refused rather than silently allowed (no --ref-format support)'
  skipped 'K1 …and HEAD did not move'
  skipped 'K1 …attributed to the backend clause'
  skipped 'K1 …the message names the backend it read'
  skipped 'K1 …the message says the guard does not implement it'
  skipped 'K1 …and does not call the HEAD move unsafe'
fi

# K2 — the `files` control for K1, in the same run. Without it, "reftable denies"
# proves nothing: a hook that denied unconditionally would pass K1 too. The
# discriminator is the CLAUSE, not the verdict — both deny, for different reasons.
: > "$PRIMARY/.git/HEAD.lock"
d_deny 'K2 files control: the same shape denies for a DIFFERENT reason' \
  "$PRIMARY" prepared "$HEAD_TX"
assert_log_has  'K2 …attributed to the lock clause' 'DENY primary-HEAD-lock-held'
assert_log_lacks 'K2 …and not to the backend clause' 'DENY backend-not-files'

# K3/K4 — a git that cannot answer the backend question at all. Boundary 28's own
# ⬜: the version at which --show-ref-format appeared was never measured, and a git
# that rejects the option exits non-zero and lands here. Denying is what keeps
# "too old to ask" from meaning "allowed".
RUN_ENV=(PATH="$(mk_git_stub)" STUB_FAIL_PROBE=--show-ref-format)
d_deny 'K3 --show-ref-format exits non-zero: denies' "$PRIMARY" prepared "$HEAD_TX"
RUN_ENV=(PATH="$(mk_git_stub)" STUB_EMPTY_PROBE=--show-ref-format)
d_deny 'K4 --show-ref-format exits 0 but prints nothing: denies' "$PRIMARY" prepared "$HEAD_TX"

# K5 — a backend name the hook has never heard of. The rule is an allowlist of one
# (`files`), not a denylist of `reftable`: a third backend must land on the same
# refusal, and a hook written as "deny if reftable" would allow it.
RUN_ENV=(PATH="$(mk_git_stub)" STUB_REF_FORMAT=someday-format)
d_deny 'K5 an unknown backend name denies (allowlist, not a reftable denylist)' \
  "$PRIMARY" prepared "$HEAD_TX"
assert_log_has 'K5 …attributed to the backend clause' 'DENY backend-not-files'
rm -f "$PRIMARY/.git/HEAD.lock"

# K6 — the measured COST of boundary 28's fail-closed rule, pinned so it is not
# discovered by surprise at installation (task 6e). `git init` runs this hook for
# its own initial HEAD write, at `prepared`, in a state where every rev-parse
# reports "not a git repository" — measured live: GIT_DIR is SET to the .git
# being created and `git rev-parse --show-ref-format` exits 128 there. Boundary 28
# denies, so an armed hook makes `git init` fail with rc=128 and no HEAD file.
# This case asserts what was MEASURED, not what is wanted. If task 6e carves an
# exemption, this is the case that must change with it.
INITREPO="$TMP/repos/freshinit"
e_run "$TMP" "$GIT_REAL" -c user.email=t@t -c user.name=t -c init.defaultBranch=main \
  -c core.hooksPath="$HOOKS_DIR" init -q "$INITREPO"
if [ "$e_rc" -ne 0 ]; then
  ok 'K6 an armed hook refuses git init, because its own HEAD write cannot be evaluated'
else
  printf 'FAIL — K6 an armed hook refuses git init (want non-zero, got %s)\n  stderr: %s\n' \
    "$e_rc" "$(cat "$err")"; fail=$((fail+1))
fi
assert_log_has 'K6 …attributed to the backend clause, which is where an unreadable repo lands' \
  'DENY backend-not-files'

# ================================================================= GROUP C ===
# Feature: scope — the primary context only. THE SCOPE TEST NEEDS A CASE IN EACH
# DIRECTION, and the passing one alone is not enough (card task 6a).
#
# Written without `--path-format=absolute` the comparison is false EVERYWHERE:
# measured, git chdirs a hook to the repo toplevel, so the bare --git-common-dir
# answers `.git` while --absolute-git-dir answers /…/proj/.git — never equal, in
# the primary checkout or anywhere else. A suite asserting only "a linked worktree
# is not judged" therefore stays fully green against a guard that judges nothing
# at all. C1 is the direction that catches it.

# C1 — the EQUAL direction. This is the whole falsifier for the missing
# --path-format=absolute: with the bug, this case exits 0 on the scope bail.
: > "$PRIMARY/.git/HEAD.lock"
d_deny 'C1 primary checkout: the two paths are equal, so the context IS judged' \
  "$PRIMARY" prepared "$HEAD_TX"
assert_log_has   'C1 …and the lock clause decided it' 'DENY primary-HEAD-lock-held'
assert_log_lacks 'C1 …not the scope bail' 'ALLOW scope-not-primary'

# C2 — the same, invoked from a subdirectory. Measured: git chdirs the hook to the
# toplevel regardless, so this reaches the same verdict — asserted so a future git
# that stops doing that does not silently turn every subdirectory into a bail.
d_deny 'C2 …and still judged when the command was run from a subdirectory' \
  "$PRIMARY/sub" prepared "$HEAD_TX"
assert_log_has 'C2 …by the lock clause' 'DENY primary-HEAD-lock-held'
rm -f "$PRIMARY/.git/HEAD.lock"

# C3 — the UNEQUAL direction, end to end. A linked worktree's HEAD is its own;
# nobody else shares it. The hook is shared with every linked worktree
# ($GIT_COMMON_DIR/hooks, measured), so without the scope test it would judge them.
e_allow 'C3 linked worktree: git switch there is allowed' "$LINKED" "$GIT_REAL" switch other
assert_head 'C3 …and that worktree HEAD moved' "$LINKED" 'refs/heads/other'
assert_log_has 'C3 …attributed to the scope bail' 'ALLOW scope-not-primary'
assert_log_lacks 'C3 …not to the allow clause' 'ALLOW no-primary-HEAD-lock'
git_bare_hooks -C "$LINKED" switch -q linkbr >/dev/null 2>&1

# C4 — the discriminator between the scope bail and the lock test. The PRIMARY's
# HEAD.lock is held by hand while a linked worktree switches: an implementation
# that ran the lock test before the scope test denies here, and one that read the
# lock path off the wrong rev-parse denies here too. Only a correct order allows.
: > "$PRIMARY/.git/HEAD.lock"
e_allow 'C4 linked worktree is allowed even while the PRIMARY holds HEAD.lock' \
  "$LINKED" "$GIT_REAL" switch d1
assert_log_has   'C4 …attributed to the scope bail' 'ALLOW scope-not-primary'
assert_log_lacks 'C4 …and the lock clause never fired' 'DENY primary-HEAD-lock-held'
rm -f "$PRIMARY/.git/HEAD.lock"
git_bare_hooks -C "$LINKED" switch -q linkbr >/dev/null 2>&1

# C5/C6 — boundaries 29 and 30. Either path being unreadable leaves the hook
# unable to tell a shared HEAD from a linked worktree's own, and an empty
# --git-common-dir is additionally the BASE of the lock path: it would test
# /HEAD.lock, which never exists, so the deny clause would stop firing silently.
: > "$PRIMARY/.git/HEAD.lock"
RUN_ENV=(PATH="$(mk_git_stub)" STUB_FAIL_PROBE=--absolute-git-dir)
d_deny 'C5a --absolute-git-dir exits non-zero: denies' "$PRIMARY" prepared "$HEAD_TX"
RUN_ENV=(PATH="$(mk_git_stub)" STUB_EMPTY_PROBE=--absolute-git-dir)
d_deny 'C5b --absolute-git-dir exits 0 but prints nothing: denies' "$PRIMARY" prepared "$HEAD_TX"
RUN_ENV=(PATH="$(mk_git_stub)" STUB_FAIL_PROBE=--git-common-dir)
d_deny 'C6a --git-common-dir exits non-zero: denies' "$PRIMARY" prepared "$HEAD_TX"
RUN_ENV=(PATH="$(mk_git_stub)" STUB_EMPTY_PROBE=--git-common-dir)
d_deny 'C6b --git-common-dir exits 0 but prints nothing: denies' "$PRIMARY" prepared "$HEAD_TX"
rm -f "$PRIMARY/.git/HEAD.lock"

# C7 — boundary 33. GIT_COMMON_DIR must not be read from the environment. GIT_DIR
# was measured UNSET at the gated HEAD write, so its sibling cannot be relied on;
# the notation in the card's rule is a path expression, not an environment read.
# Setting it to a directory holding no HEAD.lock must not turn the deny into an
# allow — an implementation reading the variable allows here, because the decoy
# holds no lock.
#
# ONE assertion, not two, and the reason is measured rather than assumed. This
# case first carried a follow-up requiring the LOCK clause to be the one that
# fired, and that expectation was wrong: GIT_COMMON_DIR redirects git ITSELF, so
# under a decoy value every rev-parse in the repository fails —
#
#   $ GIT_COMMON_DIR=/tmp/c7/decoy git rev-parse --show-ref-format
#   fatal: not a git repository (or any of the parent directories): .git
#
# — and the hook denies at the backend clause before it ever reaches the lock. The
# clause is therefore not a property this case can pin. What boundary 33 actually
# requires IS pinned: the variable does not buy an allow. C5/C6 already cover an
# unusable rev-parse, and C1 already proves the lock path comes from rev-parse in
# the ordinary case.
mkdir -p "$TMP/decoy-common"
: > "$PRIMARY/.git/HEAD.lock"
RUN_ENV=(GIT_COMMON_DIR="$TMP/decoy-common")
d_deny 'C7 a GIT_COMMON_DIR pointing elsewhere does not buy an allow' \
  "$PRIMARY" prepared "$HEAD_TX"
rm -f "$PRIMARY/.git/HEAD.lock"

# ================================================================= GROUP R ===
# Feature: the lock rule itself, end to end through a real git. THE PINNED
# MATRIX. Every case here is a real command in a real repo, because the whole
# rule turns on WHICH LOCK GIT HOLDS — worktrees/<n>/HEAD.lock for `worktree add`,
# the primary's own HEAD.lock for `switch`/`checkout` — and nothing short of git
# establishes that.

# --- the allow clause: git worktree add, all four measured forms ---------------
#
# The falsifier for this group is the naive "deny HEAD symref moves in the primary
# checkout" rule, which blocked the plain and the -b form outright (rc=128, no
# worktree created) — the guard forbidding the one operation it exists to mandate.

W1="$TMP/wt/w1"; W2="$TMP/wt/w2"; W3="$TMP/wt/w3"; W4="$TMP/wt/w4"
e_allow 'R1 git worktree add <path> wtb1 is allowed' \
  "$PRIMARY" "$GIT_REAL" worktree add "$W1" wtb1
assert_log_has 'R1 …attributed to the allow clause' 'ALLOW no-primary-HEAD-lock'
assert_worktree_listed 'R1 …and the worktree was created' "$PRIMARY" "$W1"

e_allow 'R2 git worktree add <path> -b newbr is allowed' \
  "$PRIMARY" "$GIT_REAL" worktree add "$W2" -b newbr
assert_log_has 'R2 …attributed to the allow clause' 'ALLOW no-primary-HEAD-lock'
assert_worktree_listed 'R2 …and the worktree was created' "$PRIMARY" "$W2"

e_allow 'R3 git worktree add --detach <path> is allowed' \
  "$PRIMARY" "$GIT_REAL" worktree add --detach "$W3"
assert_log_has 'R3 …attributed to the allow clause' 'ALLOW no-primary-HEAD-lock'
assert_worktree_listed 'R3 …and the worktree was created' "$PRIMARY" "$W3"

e_allow 'R4 git worktree add --no-checkout <path> -b nc is allowed' \
  "$PRIMARY" "$GIT_REAL" worktree add --no-checkout "$W4" -b nc
assert_log_has 'R4 …attributed to the allow clause' 'ALLOW no-primary-HEAD-lock'
assert_worktree_listed 'R4 …and the worktree was created' "$PRIMARY" "$W4"

# R5 — Scenario: The primary's HEAD is not moved by git worktree add. This is the
# PREMISE the whole lock rule rests on, so it is asserted separately from the
# allow verdicts: an implementation could allow the four forms for the wrong
# reason and this still catches a git that starts moving the primary's HEAD.
assert_head 'R5 the primary HEAD still names main after four worktree adds' \
  "$PRIMARY" 'refs/heads/main'

# --- the deny clause ----------------------------------------------------------
#
# The last two are the exact shapes that defeated layer 1's text classifier and
# are the reason for the pivot: layer 2 sees the ref update, never the command
# line, so quoting and wrappers are not a category it has.

e_deny 'R6 git switch other is denied'    "$PRIMARY" "$GIT_REAL" switch d1
assert_head    'R6 …and HEAD did not move' "$PRIMARY" 'refs/heads/main'
assert_log_has 'R6 …attributed to the lock clause' 'DENY primary-HEAD-lock-held'
reset_fixture "$PRIMARY"

e_deny 'R7 git checkout other is denied'  "$PRIMARY" "$GIT_REAL" checkout d2
assert_head    'R7 …and HEAD did not move' "$PRIMARY" 'refs/heads/main'
assert_log_has 'R7 …attributed to the lock clause' 'DENY primary-HEAD-lock-held'
reset_fixture "$PRIMARY"

# R8 — an OID write to HEAD, not a symref. This is the discriminating case for the
# RULE'S WORDING: a rule phrased "deny HEAD -> ref:refs/heads/…" passes R6 and R7
# and is blind to this one. The rule keys on the LOCK, which is why it is not.
e_deny 'R8 git switch --detach HEAD is denied (an OID write, not a symref)' \
  "$PRIMARY" "$GIT_REAL" switch --detach HEAD
assert_head    'R8 …and HEAD is still a symref naming main' "$PRIMARY" 'refs/heads/main'
assert_log_has 'R8 …attributed to the lock clause' 'DENY primary-HEAD-lock-held'
reset_fixture "$PRIMARY"

e_deny "R9 sh -c 'git switch other' is denied" "$PRIMARY" sh -c "\"$GIT_REAL\" switch d3"
assert_head    'R9 …and HEAD did not move' "$PRIMARY" 'refs/heads/main'
assert_log_has 'R9 …attributed to the lock clause' 'DENY primary-HEAD-lock-held'
reset_fixture "$PRIMARY"

e_deny 'R10 env -C . git switch other is denied' \
  "$PRIMARY" env -C . "$GIT_REAL" switch d4
assert_head    'R10 …and HEAD did not move' "$PRIMARY" 'refs/heads/main'
assert_log_has 'R10 …attributed to the lock clause' 'DENY primary-HEAD-lock-held'
reset_fixture "$PRIMARY"

# R11 — the forgery. The SUPERSEDED discriminator ("allow a HEAD move only if the
# expected worktree name now exists under worktrees/") is satisfied by an empty
# hand-made directory, and the live ~/.claude/.git/worktrees already holds four
# qualifying names with no attacker action. This is the regression pin against
# that discriminator returning.
mkdir -p "$PRIMARY/.git/worktrees/fakeA"
e_deny 'R11 a hand-made .git/worktrees/<n> does not buy an allow' \
  "$PRIMARY" "$GIT_REAL" switch d5
assert_head    'R11 …and HEAD did not move' "$PRIMARY" 'refs/heads/main'
assert_log_has 'R11 …attributed to the lock clause' 'DENY primary-HEAD-lock-held'
rm -rf "$PRIMARY/.git/worktrees/fakeA"
reset_fixture "$PRIMARY"

# R12 — Scenario: An ordinary commit is not gated, end to end. X5 asserts the same
# rule against a hand-made transaction; this asserts it against the one git really
# sends. Both are kept: X5 can hold the lock and this one cannot.
e_allow 'R12 git commit --allow-empty is not gated' \
  "$PRIMARY" "$GIT_REAL" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x
assert_log_empty 'R12 …and nothing is attributed, because no clause was reached'

# ================================================================= GROUP M ===
# Feature: the refusal-remediation contract (card task 6d). A layer-2 veto stops
# the ref write and does NOT undo the checkout, so the destination branch's
# content is left STAGED in a tree that is still on the old branch. The message
# is the only thing between the user and a commit that mixes two branches.
#
# The card decided this contract on 2026-08-25 after the remedy it used to name
# was run: `git reset --hard HEAD` destroyed another session's staged
# `other-session-work.txt`. What ships is a STATE-DESCRIBING message — the branch
# HEAD is still on, the staged destination, any sequencer directory by name, and
# one exit this hook can actually offer.
#
# Three tests, per the card: (a) the post-refusal tree state, (b) the absence of
# any destructive command from the message, (c) the dirty pre-command tree.
#
# ⚠️ WHAT THIS GROUP CANNOT TEST, AND WHY IT IS A COUNTED SKIP RATHER THAN AN
# OMISSION. Task 6d's contract reads "rollback ONLY when layer 1 recorded a clean
# pre-command tree". Layer 1 records no such thing: `hooks/worktree-guard.sh`
# never runs `git status --porcelain` and writes no tree-state fact anywhere
# (grepped), and the design section states the cross-process handoff that would
# carry it is "declined for v1". So in v1 the precondition is never satisfied,
# the rollback exit is never offered, and the CLEAN case and the DIRTY case
# produce the SAME message. M9 records that as a counted skip; M10 pins the
# sameness, within the limit measured at M10 itself.

MREPO="$TMP/repos/remedy"
mkdir -p "$MREPO"
git_q -C "$MREPO" init -q
printf 'ON-MAIN\n'   > "$MREPO/marker.txt"
printf 'shared-v1\n' > "$MREPO/shared.txt"
git_q -C "$MREPO" add . >/dev/null 2>&1
git_q -C "$MREPO" commit -q -m init
git_q -C "$MREPO" switch -q -c feature
printf 'ON-FEATURE\n' > "$MREPO/marker.txt"
printf 'shared-v2\n'  > "$MREPO/shared.txt"
printf 'only\n'       > "$MREPO/featonly.txt"
git_q -C "$MREPO" add . >/dev/null 2>&1
git_q -C "$MREPO" commit -q -m feat
git_q -C "$MREPO" switch -q main
git_q -C "$MREPO" config core.hooksPath "$HOOKS_DIR"

# The message assertions read a SNAPSHOT rather than $err: several cases below
# run housekeeping git between the refusal and the assertions, and a helper that
# read "the last stderr" would silently start reading the housekeeping's.
m_snap() { cp "$err" "$1"; }

m_has() { # $1 snapshot, $2 desc, $3 required substring
  if grep -qF -- "$3" "$1"; then ok "$2"; else
    printf 'FAIL — %s\n  want (substring): %s\n  message:\n%s\n' "$2" "$3" "$(cat "$1")"
    fail=$((fail+1))
  fi
}

m_lacks() { # $1 snapshot, $2 desc, $3 forbidden substring (case-insensitive)
  if [ "$HOOK_PRESENT" != 1 ]; then
    printf 'FAIL — %s (VACUOUS: the hook is not on disk, so nothing wrote a message)\n' "$2"
    fail=$((fail+1)); return
  fi
  if grep -qiF -- "$3" "$1"; then
    printf 'FAIL — %s (found: %s)\n  message:\n%s\n' "$2" "$3" "$(cat "$1")"
    fail=$((fail+1))
  else ok "$2"; fi
}

assert_porcelain() { # $1 desc, $2 repo, $3 expected `git status --porcelain` text
  local got_p
  got_p="$(git_bare_hooks -C "$2" status --porcelain 2>&1)"
  if [ "$got_p" = "$3" ]; then ok "$1"; else
    printf 'FAIL — %s\n  want:\n%s\n  got:\n%s\n' "$1" "$3" "$got_p"; fail=$((fail+1))
  fi
}

# --- (a) the post-refusal tree state ------------------------------------------
#
# This is the one place where "the guard fired correctly" and "the repo is in a
# good state" come apart, and only a test keeps them from being conflated again.
# The expected values are MEASURED, not assumed — probed 2026-08-26 in a
# throwaway repo, git 2.50.1, ref-format `files`, an unconditional-deny hook
# armed: rc=128, HEAD refs/heads/main, and `git status --porcelain` answering
# exactly the three lines below. An implementation that "fixes" this case by
# asserting an empty status is asserting a rollback no measurement supports.

M_CLEAN_ERR="$TMP/m.err.clean"
e_deny 'M1 a refused switch: git exits 128' "$MREPO" "$GIT_REAL" switch feature
m_snap "$M_CLEAN_ERR"
assert_head    'M1a …and HEAD still names main' "$MREPO" 'refs/heads/main'
assert_log_has 'M1b …attributed to the lock clause' 'DENY primary-HEAD-lock-held'

M_STATUS='A  featonly.txt
M  marker.txt
M  shared.txt'
assert_porcelain 'M1c …and the destination content is STAGED, not rolled back' "$MREPO" "$M_STATUS"

if [ "$(cat "$MREPO/marker.txt" 2>/dev/null)" = 'ON-FEATURE' ]; then
  ok 'M1d …marker.txt holds the destination content'
else
  printf 'FAIL — M1d marker.txt holds the destination content (got %s)\n' \
    "$(cat "$MREPO/marker.txt" 2>/dev/null)"; fail=$((fail+1))
fi
if [ "$(cat "$MREPO/shared.txt" 2>/dev/null)" = 'shared-v2' ]; then
  ok 'M1e …shared.txt holds the destination content'
else
  printf 'FAIL — M1e shared.txt holds the destination content (got %s)\n' \
    "$(cat "$MREPO/shared.txt" 2>/dev/null)"; fail=$((fail+1))
fi
if [ -f "$MREPO/featonly.txt" ]; then ok 'M1f …featonly.txt is present'; else
  printf 'FAIL — M1f featonly.txt is present\n'; fail=$((fail+1)); fi

# --- the message describes that state -----------------------------------------
#
# Every element the card lists, asserted separately so a message that drops one
# fails on that one rather than on a whole-message comparison nobody can read.

m_has "$M_CLEAN_ERR" 'M2a the message names the branch HEAD is still on' 'refs/heads/main'
m_has "$M_CLEAN_ERR" 'M2b the message names the destination' 'refs/heads/feature'
m_has "$M_CLEAN_ERR" 'M2c the message says the content is staged' 'staged'
m_has "$M_CLEAN_ERR" 'M2d the message says HEAD did not move' 'HEAD did not move'
m_has "$M_CLEAN_ERR" 'M2e the message carries the layer-2 prefix' \
  'worktree-location-guard (layer 2):'

# --- (b) the message contains NO destructive command --------------------------
#
# Asserted on the ABSENCE, so a later revision cannot quietly reintroduce one.
# `git reset --hard HEAD` is first because it is the one that was actually run
# and actually destroyed another session's staged work; the rest are the same
# species. The bare words are here too: a message that calls this tree clean,
# unchanged or restored is making the same false promise without a command.

m_lacks "$M_CLEAN_ERR" 'M3a no `git reset`'            'git reset'
m_lacks "$M_CLEAN_ERR" 'M3b no `--hard`'               '--hard'
m_lacks "$M_CLEAN_ERR" 'M3c no `git checkout`'         'git checkout'
m_lacks "$M_CLEAN_ERR" 'M3d no `git restore`'          'git restore'
m_lacks "$M_CLEAN_ERR" 'M3e no `git clean`'            'git clean'
m_lacks "$M_CLEAN_ERR" 'M3f no `git stash`'            'git stash'
m_lacks "$M_CLEAN_ERR" 'M3g no `rm -rf`'               'rm -rf'
m_lacks "$M_CLEAN_ERR" 'M3h no `--force`'              '--force'
m_lacks "$M_CLEAN_ERR" "M3i the tree is never called clean" 'clean'
m_lacks "$M_CLEAN_ERR" "M3j …nor unchanged"                 'unchanged'
m_lacks "$M_CLEAN_ERR" "M3k …nor restored"                  'restored'

# --- exit A, the one this hook can offer --------------------------------------

m_has "$M_CLEAN_ERR" 'M4a the message offers WORKTREE_EXEMPT as the forward exit' \
  'WORKTREE_EXEMPT'
m_has "$M_CLEAN_ERR" 'M4b …and states the cost: this is the guard overridden' \
  'guard overridden'

# M5 — exit A is a real exit, not a sentence. A message naming an escape hatch
# the hook does not honour would be prescribing a command that fails, which is
# the same species of fault as prescribing one that destroys. Task 6c measured
# that an inherited environment variable survives the git → hook hop, which is
# what makes this reachable from a child of git at all.
reset_fixture "$MREPO"
e_allow 'M5 re-running under WORKTREE_EXEMPT completes the switch' \
  "$MREPO" env WORKTREE_EXEMPT=hotfix "$GIT_REAL" switch feature
assert_head    'M5a …and HEAD moved to the destination' "$MREPO" 'refs/heads/feature'
assert_log_has 'M5b …attributed to the bypass clause' 'ALLOW bypass-worktree-exempt'
git_bare_hooks -C "$MREPO" switch -q main >/dev/null 2>&1
reset_fixture "$MREPO"

# M6 — an EMPTY value is not a bypass. `WORKTREE_EXEMPT= git switch main` reaches
# the hook set-but-empty, and treating that as a reason would make an accidental
# assignment a silent machine-wide off switch. Same rule as layer 1's.
e_deny 'M6 an empty WORKTREE_EXEMPT is not a bypass' \
  "$MREPO" env WORKTREE_EXEMPT= "$GIT_REAL" switch feature
assert_head      'M6a …and HEAD did not move' "$MREPO" 'refs/heads/main'
assert_log_has   'M6b …attributed to the lock clause' 'DENY primary-HEAD-lock-held'
assert_log_lacks 'M6c …not to the bypass clause' 'ALLOW bypass-worktree-exempt'
reset_fixture "$MREPO"

# M7 — the sequencer directory is named. Measured 2026-08-26: a `git rebase`
# whose ref transaction is vetoed leaves `rebase-merge` under the common git dir,
# and it is already present at the FIRST transaction of the rebase. Its own
# `--abort` is the only thing that ends it, so a message describing the tree
# without naming it describes half the state.
e_deny 'M7 a refused rebase: git exits 128' "$MREPO" "$GIT_REAL" rebase feature
m_snap "$TMP/m.err.rebase"
m_has "$TMP/m.err.rebase" 'M7a …and the message names the sequencer directory' 'rebase-merge'
git_bare_hooks -C "$MREPO" rebase --abort >/dev/null 2>&1
reset_fixture "$MREPO"

# --- (c) the dirty pre-command tree -------------------------------------------
#
# The regression test for the exact failure that retired the old remedy: the
# observability judge ran `git reset --hard HEAD` on this state and destroyed a
# pre-existing staged `other-session-work.txt`. The file name is the incident's.
#
# What this case CAN pin: the refusal leaves that file alone, the message offers
# the forward exit, and it still names no destructive command. What it CANNOT
# pin is in M9/M10 below.

printf 'other-session\n' > "$MREPO/other-session-work.txt"
git_bare_hooks -C "$MREPO" add other-session-work.txt >/dev/null 2>&1

M_DIRTY_ERR="$TMP/m.err.dirty"
e_deny 'M8 a refused switch over a DIRTY tree: git exits 128' \
  "$MREPO" "$GIT_REAL" switch feature
m_snap "$M_DIRTY_ERR"
assert_head 'M8a …and HEAD still names main' "$MREPO" 'refs/heads/main'

if [ -f "$MREPO/other-session-work.txt" ]; then
  ok 'M8b …and the pre-existing staged file still EXISTS'
else
  printf 'FAIL — M8b the pre-existing staged file still EXISTS (it is gone)\n'
  fail=$((fail+1))
fi

# Existing is not enough: the old remedy would have left it deleted AND unstaged.
# Measured 2026-08-26 in a throwaway repo: the veto leaves it staged, alongside
# the destination's three entries.
M_DIRTY_STATUS='A  featonly.txt
M  marker.txt
A  other-session-work.txt
M  shared.txt'
assert_porcelain 'M8c …and it is still STAGED, beside the destination content' \
  "$MREPO" "$M_DIRTY_STATUS"

m_has   "$M_DIRTY_ERR" 'M8d the dirty-tree message offers the forward exit' 'WORKTREE_EXEMPT'
m_lacks "$M_DIRTY_ERR" 'M8e …and still names no `git reset`' 'git reset'
m_lacks "$M_DIRTY_ERR" 'M8f …and no `--hard`'                '--hard'
m_has   "$M_DIRTY_ERR" 'M8g …and says outright that it names no rollback command' \
  'NAMES NO COMMAND'

# M9 — THE SKIP, COUNTED. Task 6d's contract offers rollback "only when layer 1
# recorded a clean pre-command tree". No such record exists: layer 1 runs no
# pre-command `git status --porcelain` and writes no tree-state fact, and the
# design section declines the cross-process handoff that would carry one for v1.
# So the discriminating half of test (c) — a CLEAN pre-command tree in which the
# message offers something the dirty one does not — cannot be constructed. This
# is a gap in coverage, and it is counted as one rather than left out of the
# totals, where "0 failed" would read as "every scenario is pinned".
skipped 'M9 clean pre-command tree offers a rollback exit — NOT CONSTRUCTIBLE: layer 1 records no pre-command tree state and the handoff is declined for v1 (card, "Why exit B is conditional")'

# M10 — the pin on "layer 2 cannot see the prior tree". If that is true, the
# clean-tree refusal (M1) and the dirty-tree refusal (M8) must produce the SAME
# bytes, and this compares them.
#
# WHAT IT WAS MEASURED TO CATCH, AND WHAT IT WAS MEASURED TO MISS — stated
# because the first version of this comment claimed both and a mutation run
# disproved half of it. Probed 2026-08-26 against the finished hook:
#
#   ✅ A hook that GUESSES at the prior tree from inside the veto. Mutation:
#      print `git diff --cached --name-only` into the message. It differs
#      (`featonly.txt,marker.txt,shared.txt` vs the same plus
#      `other-session-work.txt`) and M10 fails — 138 passed, 1 failed.
#   ❌ A real layer-1 -> layer-2 HANDOFF. Mutation: read a `pre-tree` file from
#      the state dir and print it. M10 does NOT fail — 139 passed, 0 failed —
#      because this suite drives layer 2 only, so the file is absent in BOTH
#      cases and the messages stay identical. A handoff would have to be driven
#      end to end here to be caught, and nothing in this file does that.
#
#   (A third mutation, branching on whether `--cached` is merely NON-EMPTY, also
#   did not fail — correctly: it is non-empty in both cases, because git stages
#   the destination before the ref transaction. That is reason 2 in the card,
#   reproduced. The probe was wrong, not the assertion.)
#
# So M10 is a tripwire against the cheap wrong fix, not against the declined
# design. The declined design is covered by M9's skip and by nothing else.
if cmp -s "$M_CLEAN_ERR" "$M_DIRTY_ERR"; then
  ok 'M10 the refusal message is byte-identical over a clean and a dirty pre-command tree (layer 2 cannot see the prior tree, and does not pretend to)'
else
  printf 'FAIL — M10 the refusal message differs between a clean and a dirty pre-command tree\n%s\n' \
    "$(diff "$M_CLEAN_ERR" "$M_DIRTY_ERR" 2>&1)"; fail=$((fail+1))
fi

git_bare_hooks -C "$MREPO" reset -q HEAD -- other-session-work.txt >/dev/null 2>&1
rm -f "$MREPO/other-session-work.txt"
reset_fixture "$MREPO"

# ================================================================= GROUP Z ===
# Feature: attribution. "Its test suite must show BOTH CLAUSES FIRING SEPARATELY
# in an attribution log: a run where every case is denied proves nothing about the
# allow clause, and vice versa" (card task 6a).
#
# $ATTR is the whole run's clause history. These are not extra scenarios — they
# are the assertion that the groups above were decided by DIFFERENT rules rather
# than by one rule absorbing everything.

clause_count() { cut -f2 "$ATTR" 2>/dev/null | grep -cxF -- "$1" || true; }

z_at_least_one() { # $1 desc, $2 clause
  local c; c="$(clause_count "$2")"
  if [ "${c:-0}" -ge 1 ]; then
    printf 'ok   — %s (fired %s time(s))\n' "$1" "$c"; pass=$((pass+1))
  else
    printf 'FAIL — %s (fired 0 times across the whole run)\n  clauses seen:\n%s\n' "$1" \
      "$(cut -f2 "$ATTR" 2>/dev/null | sort | uniq -c)"; fail=$((fail+1))
  fi
}

z_at_least_one 'Z1 the ALLOW clause fired: ALLOW no-primary-HEAD-lock' \
  'ALLOW no-primary-HEAD-lock'
z_at_least_one 'Z2 the DENY clause fired:  DENY primary-HEAD-lock-held' \
  'DENY primary-HEAD-lock-held'
z_at_least_one 'Z3 the scope bail fired:   ALLOW scope-not-primary' \
  'ALLOW scope-not-primary'
z_at_least_one 'Z4 the backend refusal fired: DENY backend-not-files' \
  'DENY backend-not-files'
z_at_least_one 'Z5 the bypass clause fired: ALLOW bypass-worktree-exempt' \
  'ALLOW bypass-worktree-exempt'

# Z6 — the assertion the card actually asks for, stated as one verdict rather than
# left implicit in Z1–Z4. A suite in which every case denied would satisfy Z2 and
# Z4 and fail here; one in which every case allowed would satisfy Z1 and Z3 and
# fail here too.
Z_ALLOW="$(clause_count 'ALLOW no-primary-HEAD-lock')"
Z_DENY="$(clause_count 'DENY primary-HEAD-lock-held')"
if [ "${Z_ALLOW:-0}" -ge 1 ] && [ "${Z_DENY:-0}" -ge 1 ]; then
  printf 'ok   — Z6 both lock-rule clauses fired independently in this run (allow=%s deny=%s)\n' \
    "$Z_ALLOW" "$Z_DENY"; pass=$((pass+1))
else
  printf 'FAIL — Z6 both lock-rule clauses fired independently (allow=%s deny=%s)\n' \
    "${Z_ALLOW:-0}" "${Z_DENY:-0}"; fail=$((fail+1))
fi

printf '\n--- attribution log, whole run ---\n'
cut -f2 "$ATTR" 2>/dev/null | sort | uniq -c | sed 's/^/  /'

printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
