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
# The tracked mode file (card task 6e, piece 4). Layer 2 reads its arming switch
# from a file BESIDE ITSELF rather than from the environment: task 6c closed the
# `git` -> hook hop, but whether a settings.json `env:` entry reaches the Bash
# tool process at all is task 8's still-open question, and a layer that armed in
# `deny` on day one while layer 1 was still in `log` would enforce a machine-wide
# refusal nobody switched on. Its presence in the repo is asserted as its own
# control below; its VALUE is set per case, because the shipped value is `log`
# and almost every case in this file is about a refusal.
MODE_SRC="$HERE/reference-transaction.mode"

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
# What every case actually runs, direct cases included. It is the INSTALLED COPY,
# not the tracked file, because the mode file layer 2 reads sits beside the hook
# — so a direct case that invoked $HOOK would read the repo's own tracked `log`
# and turn every deny in this suite into an allow. Driving the copy is also the
# more faithful shape: it is the file `install-layer2.sh` places and git runs.
HOOK_RUN="$HOOKS_DIR/reference-transaction"
MODE_FILE="$HOOKS_DIR/reference-transaction.mode"

# The per-case arming switch. `--absent` removes the file entirely, which is a
# case of its own (boundary 9's analogue: a mode that cannot be read is not a
# licence to run unguarded). Anything else is written verbatim, so a case can
# hand the hook a value it must reject.
set_mode() { # $1 = log | deny | <literal> | --absent
  if [ "$1" = --absent ]; then rm -f "$MODE_FILE"; else printf '%s\n' "$1" > "$MODE_FILE"; fi
}
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
  cp "$HOOK" "$HOOK_RUN" && chmod +x "$HOOK_RUN" && HOOK_PRESENT=1
fi
# Every case from here to GROUP W runs ARMED — `deny` — because that is the mode
# whose verdicts this suite is about. GROUP W sets it per case and puts it back.
set_mode deny

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

# Field 5, not field 2. Task 6e piece 3 gave layer 2 the same leading field list
# layer 1's log uses — <iso8601> <session_id> <arm> <mode> — so a reader holding
# both files reads them the same way. The session_id field is EMPTY and stays
# empty: it arrives on a PreToolUse payload and layer 2, a child of `git`, has no
# payload at all. GROUP F asserts the whole shape.
CLAUSE_FIELD=5
log_clauses() { # the decision+clause field of every line the last case produced
  [ -f "$LOG" ] || return 0
  cut -f"$CLAUSE_FIELD" "$LOG"
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
        bash "$HOOK_RUN" ) >"$out" 2>"$err"
  else
    ( cd "$1" && printf '%s' "$3" | env ${RUN_ENV[@]+"${RUN_ENV[@]}"} \
        bash "$HOOK_RUN" "$2" ) >"$out" 2>"$err"
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

# H1b — the TRACKED mode file is a shipped artefact, not a test fixture. The whole
# point of piece 4 is that layer 2's switch lives in the repo where a diff shows
# it; a suite that only ever wrote its own copy would stay green against a hook
# nobody could arm. Its VALUE is asserted here too: the ship state is `log`
# (card, "Arming — log-only, then deny"), and a repo that shipped `deny` would
# arm a machine-wide refusal on the first install.
if [ -f "$MODE_SRC" ] && [ -r "$MODE_SRC" ]; then
  ok 'H1b the tracked mode file exists beside the hook'
  if [ "$(grep -v '^[[:space:]]*#' "$MODE_SRC" | grep -v '^[[:space:]]*$' | head -1 |
          tr -d '[:space:]')" = log ]; then
    ok 'H1b …and ships in log mode, not deny'
  else
    printf 'FAIL — H1b the tracked mode file ships in log mode (read: %s)\n' \
      "$(cat "$MODE_SRC")"; fail=$((fail+1))
  fi
else
  bad "H1b the tracked mode file exists beside the hook (missing: $MODE_SRC)"
  bad 'H1b …and ships in log mode, not deny'
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

# K6 lives in GROUP N now. Boundary 28's fail-closed rule used to make `git init`
# itself exit 128 with no HEAD written; task 6e's fifth piece carved that one
# shape out, and the case that pins it belongs with the narrowness cases that
# keep the carve-out from swallowing boundary 28 whole.

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

# ================================================================= GROUP N ===
# Feature: `git init`'s own initial HEAD write (card task 6e, piece 5 — a user
# decision of 2026-08-26, reversing what task 6a had pinned as a measured cost).
#
# WHAT WAS MEASURED, and why boundary 28 caught this at all. `git init` runs this
# hook for the HEAD it is about to create, at `prepared`, with GIT_DIR SET to the
# .git it is building and every `rev-parse` there answering
#   fatal: not a git repository: '<that .git>'
# — because the repository is not one yet: the very ref this transaction writes is
# what will make it one. Boundary 28 reads an unanswerable backend probe as "deny",
# so an armed hook made `git init` exit 128 with .git/ created and no HEAD file.
#
# THE DISCRIMINATOR, and why each of its three parts is there. Measured in a
# throwaway repo on git 2.50.1 (Apple Git-155):
#
#   * GIT_DIR is set — it is UNSET at every real primary HEAD move measured
#     (`git switch`, `git checkout`, `--detach`), so this alone excludes them all;
#   * <GIT_DIR>/HEAD does not exist — the repository has no HEAD yet, which is
#     precisely why git cannot open it;
#   * <GIT_DIR>/HEAD.lock does exist — git is mid-transaction on HEAD in THIS
#     directory, holding its lock. Without this part the exemption also fires for
#     GIT_DIR naming any empty directory, which is not a repository being created.
#
# WHAT THE EXEMPTION CANNOT REACH, measured rather than argued: git never invokes
# this hook at all when it cannot open the repository it was pointed at. Four
# shapes were run under an armed hook — GIT_DIR at an empty directory, GIT_DIR at
# a missing path, GIT_COMMON_DIR at an empty directory, and a checkout whose HEAD
# had been deleted — and every one exited 128 with NO hook invocation and the
# primary's HEAD unmoved. So "the repository cannot be opened" is a state only
# `git init` reaches a hook in. N6-N9 pin the edges anyway.

INITREPO="$TMP/repos/freshinit"
e_run "$TMP" "$GIT_REAL" -c user.email=t@t -c user.name=t -c init.defaultBranch=main \
  -c core.hooksPath="$HOOKS_DIR" init -q "$INITREPO"
if [ "$e_rc" -eq 0 ]; then
  ok 'N1 git init succeeds under an armed hook (was K6: "denies, as measured")'
else
  printf 'FAIL — N1 git init succeeds under an armed hook (want 0, got %s)\n  stderr: %s\n' \
    "$e_rc" "$(cat "$err")"; fail=$((fail+1))
fi

# N2 — the half that makes N1 mean something. `git init` exiting 0 is not the
# claim; the claim is that the ref it exists to write was written. The old
# breakage left .git/ on disk and no HEAD in it, so a case asserting only the exit
# code would have passed against a git that created a directory and nothing else.
if [ -f "$INITREPO/.git/HEAD" ]; then
  ok "N2 …and the HEAD file it exists to write is there: $(cat "$INITREPO/.git/HEAD")"
else
  printf 'FAIL — N2 the HEAD file was written by git init (absent: %s)\n  .git holds: %s\n' \
    "$INITREPO/.git/HEAD" "$(ls -A "$INITREPO/.git" 2>&1 | tr '\n' ' ')"; fail=$((fail+1))
fi

assert_log_has  'N3 …attributed to the git-init clause' 'ALLOW git-init-own-repository'
assert_log_lacks 'N4 …and NOT to the backend clause, which is where it used to land' \
  'DENY backend-not-files'

# N5 — `git init --bare` takes the same path (GIT_DIR set, HEAD absent, HEAD.lock
# held) and is a different command. Measured, not assumed: a discriminator written
# against the worktree shape alone would leave every bare init broken.
BAREREPO="$TMP/repos/freshbare.git"
e_run "$TMP" "$GIT_REAL" -c user.email=t@t -c user.name=t -c init.defaultBranch=main \
  -c core.hooksPath="$HOOKS_DIR" init -q --bare "$BAREREPO"
if [ "$e_rc" -eq 0 ] && [ -f "$BAREREPO/HEAD" ]; then
  ok 'N5 git init --bare succeeds too, and writes its HEAD'
else
  printf 'FAIL — N5 git init --bare (rc=%s, HEAD present=%s)\n  stderr: %s\n' "$e_rc" \
    "$( [ -f "$BAREREPO/HEAD" ] && echo yes || echo no )" "$(cat "$err")"; fail=$((fail+1))
fi

# ---- N6..N9: boundary 28 must still hold everywhere else -------------------
# THE FALSIFIER FOR THE WHOLE CARVE-OUT. An exemption written as "an unreadable
# backend allows" would pass N1-N5 and fail every case below; so would one written
# as "GIT_DIR being set allows". Each case bends exactly one of the three parts.

# N6 — GIT_DIR set, HEAD absent, but NO HEAD.lock: an empty directory is not a
# repository being created, and nothing is mid-transaction in it.
NOLOCK="$TMP/nolock"
mkdir -p "$NOLOCK"
RUN_ENV=(GIT_DIR="$NOLOCK")
d_deny 'N6 GIT_DIR at a directory with no HEAD and no HEAD.lock still denies' \
  "$PRIMARY" prepared "$HEAD_TX"
assert_log_lacks 'N6 …and the git-init clause did not fire' 'ALLOW git-init-own-repository'

# N7 — GIT_DIR set at a REAL, openable repository whose HEAD is present and whose
# lock is held. This is the shape the guard exists for, reached with GIT_DIR set:
# it must still be the lock clause that decides it.
: > "$PRIMARY/.git/HEAD.lock"
RUN_ENV=(GIT_DIR="$PRIMARY/.git")
d_deny 'N7 GIT_DIR at a real repo with HEAD present still denies' \
  "$PRIMARY" prepared "$HEAD_TX"
assert_log_has 'N7 …by the lock clause, not the exemption' 'DENY primary-HEAD-lock-held'
rm -f "$PRIMARY/.git/HEAD.lock"

# N8 — GIT_DIR UNSET and a probe that cannot answer: boundary 28's original rule,
# unchanged. This is the re-verification task 6e asks for in as many words — "a
# real primary-checkout HEAD move that merely fails a probe for an unrelated
# reason must still deny".
RUN_ENV=(PATH="$(mk_git_stub)" STUB_FAIL_PROBE=--show-ref-format)
d_deny 'N8 an unreadable backend with GIT_DIR unset still denies (boundary 28 intact)' \
  "$PRIMARY" prepared "$HEAD_TX"
assert_log_has 'N8 …still attributed to the backend clause' 'DENY backend-not-files'

# N9 — THE RESIDUAL, PINNED AS MEASURED RATHER THAN AS WANTED. All three parts can
# be assembled by hand: a directory holding a HEAD.lock, no HEAD, named by GIT_DIR.
# The hook allows it. Two facts bound what that costs, and neither is an argument
# that it is tidy: git was measured never to invoke a hook in that state (see the
# group preamble), and a write under a GIT_DIR git cannot open is confined to that
# directory — it cannot reach the shared primary checkout this guard is about.
# Asserted so the edge is on the record and a later revision cannot move it in
# silence.
FORGED="$TMP/forged"
mkdir -p "$FORGED"
: > "$FORGED/HEAD.lock"
RUN_ENV=(GIT_DIR="$FORGED")
d_allow 'N9 a hand-built <lock, no HEAD, unopenable> directory IS exempted (measured, not wanted)' \
  "$PRIMARY" prepared "$HEAD_TX"
assert_log_has 'N9 …attributed to the git-init clause' 'ALLOW git-init-own-repository'
rm -f "$FORGED/HEAD.lock"

# N11 — the falsifier for the HEAD-IS-ABSENT condition, which N6..N9 do not reach.
# A directory holding BOTH a HEAD and a HEAD.lock, that git still cannot open (no
# objects/, no refs/): every other condition of the exemption is satisfied and
# this one is not. Measured by mutation 2026-08-26 — with the HEAD-absent test
# deleted the hook exits 0 here and the suite is otherwise unchanged at 178/0/1,
# so without this case that condition is a line no test pins.
HASHEAD="$TMP/hashead"
mkdir -p "$HASHEAD"
printf 'ref: refs/heads/main\n' > "$HASHEAD/HEAD"
: > "$HASHEAD/HEAD.lock"
RUN_ENV=(GIT_DIR="$HASHEAD")
d_deny 'N11 GIT_DIR at an unopenable directory that HAS a HEAD still denies' \
  "$PRIMARY" prepared "$HEAD_TX"
assert_log_lacks 'N11 …and the git-init clause did not fire' 'ALLOW git-init-own-repository'
rm -f "$HASHEAD/HEAD.lock"

# ---- N10: a SECOND breakage of the same family, newly measured -------------
# 🚩 NOT COVERED BY TASK 6e's DECISION, WHICH NAMES `git init` AND NOTHING ELSE.
# Measured 2026-08-26 while verifying the exemption: `git clone` is refused by an
# armed layer 2 as well, and harder than `git init` was — git removes the clone
# directory on failure, so the command leaves nothing behind at all.
#
# It is a DIFFERENT mechanism and the exemption above does not touch it. A clone's
# final HEAD write happens in the freshly-created clone, which is its own primary
# checkout: GIT_DIR is set, the repository IS openable, `--show-ref-format` answers
# `files`, --absolute-git-dir equals the common dir, and the clone holds its own
# HEAD.lock. So the ordinary lock rule fires and the clause is
# `primary-HEAD-lock-held` — not `backend-not-files`, and not anything a
# "repository does not exist yet" test can see.
#
# Pinned here as WHAT WAS MEASURED, exactly as task 6a pinned K6 before the user
# ruled on it. Whether to carve a second exemption is the same kind of decision and
# has not been made.
CLONESRC="$TMP/repos/proj"
CLONEDST="$TMP/repos/cloned"
e_run "$TMP" "$GIT_REAL" -c user.email=t@t -c user.name=t \
  -c core.hooksPath="$HOOKS_DIR" clone -q "$CLONESRC" "$CLONEDST"
if [ "$e_rc" -ne 0 ]; then
  ok "N10 an armed hook refuses git clone too (measured cost, undecided — rc=$e_rc)"
else
  printf 'FAIL — N10 git clone was expected to be refused as measured (got rc=0)\n'
  fail=$((fail+1))
fi
assert_log_has 'N10 …by the LOCK clause, so no git-init test could ever see it' \
  'DENY primary-HEAD-lock-held'
if [ ! -e "$CLONEDST" ]; then
  ok 'N10 …and git removed the clone directory, so the command leaves nothing behind'
else
  printf 'FAIL — N10 the clone directory was expected to be removed (still there: %s)\n' \
    "$CLONEDST"; fail=$((fail+1))
fi
reset_fixture "$PRIMARY"

# ---- N12: a THIRD breakage of the same family, newly measured --------------
# 🚩 ALSO NOT COVERED BY TASK 6e's DECISION, and a different mechanism again.
# Measured 2026-08-26: `git init --ref-format=reftable` is refused by an armed
# hook, so creating a reftable repository is impossible while layer 2 is armed.
#
# The exemption cannot reach it, and the reason is a fact about git rather than a
# gap in the rule. Dumped from inside the hook at `prepared`, both inits side by
# side on git 2.50.1:
#
#   files init:     HEAD absent, HEAD.lock PRESENT,
#                   listing [HEAD.lock config description hooks info refs]
#   reftable init:  HEAD PRESENT, HEAD.lock absent,
#                   listing [HEAD config description hooks info refs reftable],
#                   and the lock it holds is reftable/tables.list.lock
#
# So "the repository has no HEAD yet" — the condition that makes the files case
# recognisable at all — is simply FALSE for a reftable init: git writes HEAD
# eagerly and locks the reftable stack instead. Covering it would mean teaching a
# guard that refuses to implement reftable (boundary 28) about a reftable lock
# file, which is a design change and not a fix, and it is not a decision this task
# was given. Pinned as WHAT WAS MEASURED, like N10.
if [ -d "$RT/.git" ]; then
  e_run "$TMP" "$GIT_REAL" -c user.email=t@t -c user.name=t -c init.defaultBranch=main \
    -c core.hooksPath="$HOOKS_DIR" init -q --ref-format=reftable "$TMP/repos/freshrt"
  if [ "$e_rc" -ne 0 ]; then
    ok "N12 an armed hook refuses git init --ref-format=reftable too (measured, undecided — rc=$e_rc)"
  else
    printf 'FAIL — N12 reftable init was expected to be refused as measured (got rc=0)\n'
    fail=$((fail+1))
  fi
  assert_log_has 'N12 …by the backend clause, because its HEAD already exists at prepared' \
    'DENY backend-not-files'
else
  skipped 'N12 an armed hook refuses git init --ref-format=reftable too (no --ref-format support)'
  skipped 'N12 …by the backend clause, because its HEAD already exists at prepared'
fi

# ================================================================= GROUP W ===
# Feature: the arming switch (card task 6e, piece 4). Layer 2 reads `log`/`deny`
# from a TRACKED file beside itself and from nowhere else.
#
# WHY NOT THE ENVIRONMENT, stated so the absence is not read as an oversight.
# Task 6c measured that an inherited variable survives the `git` -> hook hop, so
# the second half of the path works. The FIRST half — whether a settings.json
# `env:` entry reaches the Bash tool process at all — is task 8 and is unmeasured
# today. A layer 2 whose switch depended on it would arm in `deny` on day one, in
# every repository on the machine, while layer 1 was still in `log`. Nothing in
# this file claims the end-to-end mode switch works; it claims only what the file
# does.

set_mode deny
: > "$PRIMARY/.git/HEAD.lock"

# W1 — the control. Without it "log mode allows" proves nothing: a hook that
# allowed unconditionally would pass W2.
d_deny 'W1 deny mode: the lock clause refuses (control for W2)' "$PRIMARY" prepared "$HEAD_TX"
assert_log_has 'W1 …recorded as DENY' 'DENY primary-HEAD-lock-held'

# W2 — the same shape in `log` mode. Allowed, silent, and recorded — the decision
# token changes and the clause does not, so one grep over the log answers "what
# would this have refused" without a second vocabulary to learn.
set_mode log
d_allow 'W2 log mode: the same shape is allowed, and silently' "$PRIMARY" prepared "$HEAD_TX"
assert_log_has  'W2 …recorded as WOULD-DENY, same clause' 'WOULD-DENY primary-HEAD-lock-held'
assert_log_lacks 'W2 …and not as DENY' 'DENY primary-HEAD-lock-held'

# W3 — log mode covers the PRECONDITION refusals too, not just the verdict. An
# unreadable backend that still exited 128 in `log` mode would be a guard that
# blocks while claiming to be observing.
set_mode log
RUN_ENV=(PATH="$(mk_git_stub)" STUB_REF_FORMAT=someday-format)
d_allow 'W3 log mode: even the backend refusal is downgraded' "$PRIMARY" prepared "$HEAD_TX"
assert_log_has 'W3 …recorded as WOULD-DENY backend-not-files' 'WOULD-DENY backend-not-files'

# W4 — the mode file is MISSING. Fails closed, and this is a judgement worth
# stating: layer 1 treats an absent WORKTREE_GUARD_MODE as `log`, because absence
# there is the documented ship state. Absence HERE is different — the file is
# tracked and is placed beside the hook by install-layer2.sh, so its absence means
# a broken install, not a chosen mode. Defaulting to `log` would leave a hook that
# is armed, silent and enforcing nothing, which is the one failure this card
# refuses by name. No log line: the `mode` field would have to hold the value the
# hook just failed to read.
set_mode --absent
d_deny 'W4 a missing mode file denies rather than defaulting to log' \
  "$PRIMARY" prepared "$HEAD_TX" 'reference-transaction.mode'
assert_log_empty 'W4 …and writes no log line, because the mode field has no value'

# W5 — a mode file holding something that is neither `log` nor `deny`. Same
# argument as layer 1's boundary 9: a mistyped switch is a failed attempt to arm
# the guard, not permission to run unguarded. The value is quoted back.
set_mode 'DENY'
d_deny 'W5 an unrecognised mode value denies, and the message quotes it' \
  "$PRIMARY" prepared "$HEAD_TX" 'DENY'
assert_log_empty 'W5 …and writes no log line either'

# W6 — the file format. It is tracked and meant to be read by a human before it is
# flipped, so it carries comments; blank lines and `#` lines are skipped and the
# first real line decides. Surrounding whitespace is trimmed, because an editor
# that leaves a trailing space must not arm a machine-wide refusal by accident.
printf '# the layer 2 arming switch\n\n   deny   \n' > "$MODE_FILE"
d_deny 'W6 comments, blank lines and surrounding whitespace are tolerated' \
  "$PRIMARY" prepared "$HEAD_TX"
assert_log_has 'W6 …and the value read was deny' 'DENY primary-HEAD-lock-held'

# W7 — a `#`-only file names no mode at all. It is not `log`.
printf '# nothing here\n' > "$MODE_FILE"
d_deny 'W7 a file with no value line denies' "$PRIMARY" prepared "$HEAD_TX" \
  'reference-transaction.mode'
assert_log_empty 'W7 …and writes no log line'

rm -f "$PRIMARY/.git/HEAD.lock"

# W8 — the exemption does not depend on the mode, in either direction. `git init`
# is allowed in `deny` mode because it is not a shape this guard judges — not
# because the guard happens to be observing.
set_mode deny
INITREPO2="$TMP/repos/freshinit2"
e_run "$TMP" "$GIT_REAL" -c user.email=t@t -c user.name=t -c init.defaultBranch=main \
  -c core.hooksPath="$HOOKS_DIR" init -q "$INITREPO2"
if [ "$e_rc" -eq 0 ] && [ -f "$INITREPO2/.git/HEAD" ]; then
  ok 'W8 git init is allowed in DENY mode — the exemption is not a mode effect'
else
  printf 'FAIL — W8 git init in deny mode (rc=%s, HEAD present=%s)\n  stderr: %s\n' "$e_rc" \
    "$( [ -f "$INITREPO2/.git/HEAD" ] && echo yes || echo no )" "$(cat "$err")"; fail=$((fail+1))
fi

# ================================================================= GROUP F ===
# Feature: the log line's format (card task 6e, piece 3). Round 8's observability
# judge found layer 2 with no `<arm>` value and no way to tell its lines from
# layer 1's — which makes "did layer 1 miss this?" unanswerable, the exact
# question the two-layer design exists to let you ask.
#
#   <iso8601> <session_id> <arm> <mode> <DECISION clause> <detail>
#
# session_id is EMPTY and stays empty. It arrives on a PreToolUse payload; layer 2
# is a child of `git` and has no payload at all. Synthesising one would be a field
# the payload cannot source — the failure this card refuses by name. The cost is
# real and bounded: a layer-2 line answers "was this shape missed by layer 1" and
# not "which session typed it".

set_mode deny
: > "$PRIMARY/.git/HEAD.lock"
log_reset
_run "$PRIMARY" prepared "$HEAD_TX"
log_harvest
F_LINE="$(head -1 "$LOG" 2>/dev/null)"

f_field() { printf '%s' "$F_LINE" | cut -f"$1"; }

if [ "$(printf '%s' "$F_LINE" | awk -F'\t' '{print NF}')" = 6 ]; then
  ok 'F1 the line carries exactly six tab-separated fields'
else
  printf 'FAIL — F1 six tab-separated fields (got %s)\n  line: %s\n' \
    "$(printf '%s' "$F_LINE" | awk -F'\t' '{print NF}')" "$F_LINE"; fail=$((fail+1))
fi

# The `-n "$F_LINE"` half is not belt and braces: without it this case is VACUOUS
# against any hook that logs nothing at all — an absent line has an empty field 2
# too, and the two-stub falsification caught exactly that.
if [ -n "$F_LINE" ] && [ -z "$(f_field 2)" ]; then
  ok 'F2 the session_id field is EMPTY, not synthesised'
else
  printf 'FAIL — F2 the session_id field must be empty (got [%s])\n  line: %s\n' \
    "$(f_field 2)" "$F_LINE"; fail=$((fail+1))
fi

# F3 — the arm value. Asserted for EQUALITY and against layer 1's two values by
# name: `A` and `B2D` are what worktree-guard.sh writes, and a layer 2 that reused
# either would make the two logs unsplittable at exactly the field meant to split
# them.
F_ARM="$(f_field 3)"
if [ -n "$F_ARM" ] && [ "$F_ARM" != A ] && [ "$F_ARM" != B2D ]; then
  ok "F3 the arm field holds a value of layer 2's own: [$F_ARM]"
else
  printf "FAIL — F3 the arm field must be non-empty and neither A nor B2D (got [%s])\n" "$F_ARM"
  fail=$((fail+1))
fi

if [ "$(f_field 4)" = deny ]; then
  ok 'F4 the mode field holds the mode this run was armed in'
else
  printf 'FAIL — F4 the mode field (want deny, got [%s])\n  line: %s\n' \
    "$(f_field 4)" "$F_LINE"; fail=$((fail+1))
fi

set_mode log
log_reset
_run "$PRIMARY" prepared "$HEAD_TX"
log_harvest
if [ "$(head -1 "$LOG" 2>/dev/null | cut -f4)" = log ]; then
  ok 'F5 …and follows the mode when it changes'
else
  printf 'FAIL — F5 the mode field follows the mode (want log, got [%s])\n' \
    "$(head -1 "$LOG" 2>/dev/null | cut -f4)"; fail=$((fail+1))
fi

set_mode deny
rm -f "$PRIMARY/.git/HEAD.lock"

# ================================================================= GROUP Z ===
# Feature: attribution. "Its test suite must show BOTH CLAUSES FIRING SEPARATELY
# in an attribution log: a run where every case is denied proves nothing about the
# allow clause, and vice versa" (card task 6a).
#
# $ATTR is the whole run's clause history. These are not extra scenarios — they
# are the assertion that the groups above were decided by DIFFERENT rules rather
# than by one rule absorbing everything.

clause_count() { cut -f"$CLAUSE_FIELD" "$ATTR" 2>/dev/null | grep -cxF -- "$1" || true; }

z_at_least_one() { # $1 desc, $2 clause
  local c; c="$(clause_count "$2")"
  if [ "${c:-0}" -ge 1 ]; then
    printf 'ok   — %s (fired %s time(s))\n' "$1" "$c"; pass=$((pass+1))
  else
    printf 'FAIL — %s (fired 0 times across the whole run)\n  clauses seen:\n%s\n' "$1" \
      "$(cut -f"$CLAUSE_FIELD" "$ATTR" 2>/dev/null | sort | uniq -c)"; fail=$((fail+1))
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
z_at_least_one 'Z7 the git-init exemption fired: ALLOW git-init-own-repository' \
  'ALLOW git-init-own-repository'
z_at_least_one 'Z8 log mode fired at least once: WOULD-DENY primary-HEAD-lock-held' \
  'WOULD-DENY primary-HEAD-lock-held'

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
cut -f"$CLAUSE_FIELD" "$ATTR" 2>/dev/null | sort | uniq -c | sed 's/^/  /'

printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
