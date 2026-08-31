#!/usr/bin/env bash
#
# worktree-guard.sh — PreToolUse hook (matcher: Edit|Write|NotebookEdit|Bash).
#
# Layer 1 of the worktree location guard. Three arms, all resting on one idea: parallel
# sessions share a repository's PRIMARY checkout and share its single HEAD, so work done
# there lands under another session's feet and nothing in the tree records that it happened.
#
#   Arm A   Edit/Write/NotebookEdit — refuses a write whose TARGET sits in a primary checkout.
#   Arm B2  Bash — refuses a hand-rolled `git worktree add` that lands anywhere but
#           ~/.worktrees/<repo-name>/ for the repository the command really acts on.
#   Arm D   Bash — refuses a command that moves a primary checkout's HEAD, or overwrites its
#           working tree wholesale. LAYER 1 ONLY: layer 2 (hooks/reference-transaction, card
#           task 6a) is a separate git-side hook and is NOT part of this file.
#
# Layer 1 also CHECKS layer 2, in check_liveness() below: every refusal it prints carries a
# report when the effective repo's core.hooksPath holds no armed `reference-transaction`.
# All three of layer 2's absence modes were measured to fail open silently, so layer 2
# cannot report any of them and only this file can.
#
# Design, boundaries and scenarios: docs/features/worktree-location-guard.md.
#
# Exit 0 = allow. Exit 2 = deny, reason on stderr. Nothing is ever written to stdout, on
# any path: a PreToolUse hook's stdout is a protocol channel, not a place to talk.
#
# The two Bash arms judge SEGMENTS, never the line. `git -C /other log && git switch main`
# must bind segment 0's redirect to segment 0 alone — reading it as a property of the line
# lets an earlier segment's permission excuse a later segment's HEAD move, which is the
# incident this whole feature exists to stop. The segment-indexed facts come from
# lib/classify-git-command.py, and the ONE rule turning a segment index into "which
# repository is this?" lives in resolve_effective_repo(). There is deliberately no second
# copy of that rule: round 4 found both arms deriving it separately with only one of them
# complete, and hooks/worktree-guard.test.sh GROUP S substitutes the function at run time
# and requires both arms to move.
#
# Both Bash arms — and that shared rule with them — live in lib/worktree_guard_bash_arms.sh,
# sourced at the dispatch point below. What stays HERE is Arm A and the preconditions every
# arm rests on: the payload, the mode, $HOME, git and its version, physical_path(),
# append_log() and refuse(). The split is by line count (rules/core-conduct.md caps a file at
# 800) and not by contract; nothing about the one-rule guarantee above changes with it.
#
# Fails CLOSED, unlike phase-guard.sh. That sibling fires in every repo on this machine and
# a false block there costs a session in a repo that never opted in, so it allows whenever
# it cannot finish. This guard has no opt-in signal by explicit design decision (card,
# "The accepted blast radius"), and a guard that switches itself off exactly when it cannot
# verify its own precondition is indistinguishable from the feature being absent. So every
# "I could not evaluate this" below denies, and the ship state is `log` mode, which
# downgrades every deny to a logged `would-deny`.

set -u

LF='
'
# Spelled as a literal tab. Bash 3.2 is the floor here and $'\t' is not available in every
# position this value is used in; the test suite pins the separator the same way.
TAB='	'

# git rev-parse --path-format=absolute is the whole detection mechanism (card, "Detection")
# and it landed in git 2.31. Below the floor the guard denies rather than guessing.
FLOOR_MAJOR=2
FLOOR_MINOR=31
FLOOR='2.31'

# Same override precedent as phase-guard.sh's PHASE_GUARD_STATE_DIR, and the same default
# shape: the card fixes the log at `hooks/state/worktree-guard.log`, which is that path
# inside the ~/.claude repo. `${HOME:-}` and not `$HOME` — under `set -u` an unset HOME is
# an unbound variable, and exiting 1 on every write is the one outcome the contract has no
# room for. An unusable path fails at the append instead, which boundary 10 already covers.
STATE_DIR="${WORKTREE_GUARD_STATE_DIR:-${HOME:-}/.claude/hooks/state}"
LOG_FILE="$STATE_DIR/worktree-guard.log"

# The lexer and classifier the Bash arms read the command through. Overridable on the same
# precedent as STATE_DIR above, and for the same reason: boundary 7 has to be testable
# against a deliberately broken lexer without breaking the one every other hook uses.
LIB_DIR="${WORKTREE_GUARD_LIB:-$(cd "$(dirname "$0")" && pwd)/lib}"
CLASSIFIER="$LIB_DIR/classify-git-command.py"
# Arms B2 and D themselves, sourced at the dispatch point below. Resolved through LIB_DIR
# like the classifier, so a suite substituting one substitutes the other from the same knob
# — which is how GROUP S drives a mutated copy of the shared resolution rule.
BASH_ARMS="$LIB_DIR/worktree_guard_bash_arms.sh"
# The shared "is layer 2 armed?" judgement, sourced HERE rather than at a dispatch point:
# check_liveness() runs from refuse(), which every arm reaches. Task 6e's installer sources
# the same file and reports through the same verdict, so the two cannot drift apart — the
# argument round 4 made about resolve_effective_repo(), applied to a check whose whole job is
# to be right about something nobody looks at twice.
LIVENESS_LIB="$LIB_DIR/worktree_guard_liveness.sh"
LIVENESS_LIB_OK=0
if [ -r "$LIVENESS_LIB" ]; then
  # shellcheck source=lib/worktree_guard_liveness.sh
  . "$LIVENESS_LIB" && LIVENESS_LIB_OK=1
fi

# The sentinel classify-git-command.py puts in an indexed fact whose operand it could not
# read off the command line (its own UNRESOLVABLE). Spelled out rather than imported: the
# fact stream is the interface between the two files, and this is a token in it.
SENTINEL='UNRESOLVABLE'

# The centralized worktree store, relative to $HOME. Rule 2 of the card's Problem section.
STORE_REL='.worktrees'

# The marker create-worktree.sh writes into each store directory, naming the repo root that
# store belongs to. Its whole job is to make a <repo-name> basename collision a deny rather
# than two repos silently sharing one directory (card, boundary 14).
MARKER_NAME='.repo-root'

# The bypass, same shape as MERGE_EXEMPT / TEST_EXEMPT / JUDGE_EXEMPT. Read as a leading
# env-assignment on the command line, exactly as classify-pr-command.py reads its own.
EXEMPT_VAR='WORKTREE_EXEMPT'

# Layer 2's hook NAME and the git-path used to resolve its directory both live in
# $LIVENESS_LIB now ($WG_LAYER2_HOOK, $WG_HOOKS_GIT_PATH), because the installer needs the
# same two values and a second spelling of either is a second thing to keep in step.

# --- messages ---------------------------------------------------------------------------
# Every message carries the `worktree-guard:` prefix. phase-guard.sh prefixes its own and
# both hooks are PreToolUse on the same matchers, so a bare refusal does not say which one
# fired (card, "Deny message contract").

# task 17, Group C: each of these three fires before a repository is knowable — the payload
# cannot be read, or there is no git to ask — so, like Group B above, none of them can honour
# the exemption list; the trailing clause says so rather than staying silent about it.
MSG_NO_PYTHON='worktree-guard: blocked — no python3 or python on PATH, so this tool payload could not be read at all. The guard cannot permit a request it cannot identify. This fires before the exemption list is reached — settings.json is not exempt here; an edit through the Bash tool is the route to it in this state.'
MSG_NO_PAYLOAD='worktree-guard: blocked — this tool payload could not be read as JSON. The guard cannot permit a request it cannot identify, and it will not record a decision under a session id it had to invent. This fires before the exemption list is reached — settings.json is not exempt here; an edit through the Bash tool is the route to it in this state.'
MSG_NO_GIT='worktree-guard: blocked — no git on PATH, so the guard could not verify the checkout this request acts on. This fires before the exemption list is reached — settings.json is not exempt here; an edit through the Bash tool is the route to it in this state.'
MSG_LOG_WARN="worktree-guard: this refusal could not be appended to $LOG_FILE — the guard is in log mode, so the request was allowed and the evidence line is lost."
MSG_NOT_RECORDED="worktree-guard: additionally, this decision could not be recorded in $LOG_FILE."
# Boundary 10, rule 3 — the design's ONE deliberate fail-open on an enforcement path. It
# needs its own wording: MSG_LOG_WARN above says "the guard is in log mode", which is false
# here. A bypass is an allow, and switching the escape hatch off because the disk filled up
# is the worst moment to switch it off; the loss is silent in the log by design, so this
# warning is its only trace.
MSG_BYPASS_WARN="worktree-guard: this bypass could not be appended to $LOG_FILE — the command was allowed under $EXEMPT_VAR and no record of it survives."

# --- the exits that carry no log line -----------------------------------------------------
# Boundary 1 outranks the mode: the line format requires a session_id an unreadable payload
# cannot supply, and no line is ever written with a fabricated or empty one. The same holds
# one step further out for an unreadable mode (boundary 9) — the `mode` field would have to
# hold the very value the guard just rejected. Both refuse in log mode too.
hard_deny() { # $1 message
  printf '%s\n' "$1" 1>&2
  exit 2
}

# --- the log ------------------------------------------------------------------------------
# Refusals and bypasses only, never allows: one line per evaluation was measured at 10–20 MB
# per three days, at which size "review the log before flipping" is not a real instruction.
# Callers must not probe the log when no line is due (boundary 10's fourth, unnumbered rule:
# a guard that stats the log on every evaluation warns on writes it was never going to record).
append_log() { # $1 arm, $2 decision, $3 repo-root, $4 path-or-command, [$5 exempt-reason]
  local ts field line
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || return 1
  # 21.4% of real commands carry a newline and 0.0% carry a tab, so tabs separate and the
  # last field escapes LF as the two characters \n. A line-oriented log whose fields hold
  # raw newlines is not parseable.
  field=${4//"$LF"/\\n}
  line="$ts$TAB$SID$TAB$1$TAB$MODE$TAB$2$TAB$3$TAB$field"
  # The eighth field exists only on a bypass. A refusal carrying an empty exempt-reason slot
  # would be a field the card's format does not specify, and no substring assertion can see
  # a trailing empty field.
  [ $# -ge 5 ] && line="$line$TAB${5//"$LF"/\\n}"
  mkdir -p "$STATE_DIR" 2>/dev/null
  # The append runs in a subshell so that bash's own "cannot create" diagnostic for a failed
  # redirection lands on the subshell's stderr and not on the session's. A trailing
  # `2>/dev/null` would not do it: redirections are applied left to right, so the failure is
  # reported before the suppression is in place.
  ( printf '%s\n' "$line" >>"$LOG_FILE" ) 2>/dev/null
}

# --- the liveness check: layer 1 checks layer 2 --------------------------------------------
# Layer 2 (hooks/reference-transaction) is what refuses a HEAD move in a shared primary
# checkout however the move is started — including from a terminal no PreToolUse hook ever
# sees. All three ways it can be absent were measured to fail open SILENTLY (rc=0, HEAD
# moved), so no layer-2 code runs and nothing on that side can report them; a guard whose
# absence is indistinguishable from its success is the failure this card has already
# recorded once (card, "The liveness check").
#
# CHANNEL — a judgement the card deliberately left open (":2490, this scenario asserts a
# REPORT, not a verdict"). Settled here as: a paragraph APPENDED to a refusal this guard was
# already printing, and nothing else. It does not deny on its own — a missing hook file in
# one repo is not a reason to block every git command in every repo — and it does not warn
# on an allow, which would put a paragraph on stderr for every Bash tool call and teach
# sessions to skip the stream the real refusals arrive on. The cost is stated rather than
# hidden: while this guard is quiet, and in `log` mode where it prints nothing at all,
# layer 2's absence goes unreported.
#
# The repository is NOT re-derived here. It arrives as refuse()'s own repo-root argument,
# which each arm filled in from the resolution it had already done — Arm A's $top, Arms B2
# and D's $EFF_ROOT. An empty one means no repository was ever established (every
# precondition refusal, including the ones require_git_present/require_git_version raise),
# and there is no hooks path to resolve without one. That is also why the
# --path-format=absolute below is safe: every caller that passes a non-empty root has
# already been through require_git_version's floor.
LIVENESS_NOTE=''
check_liveness() { # $1 the repository this refusal was judged against, '' when there is none
  local rc
  LIVENESS_NOTE=''
  [ -n "$1" ] || return 0
  # A missing lib is a new way for this check to be absent, and the ONE thing it may not do
  # then is nothing: silence is exactly what an armed layer 2 looks like, so an unrunnable
  # check reports that it could not run. The refusal above is unaffected either way.
  if [ "$LIVENESS_LIB_OK" != 1 ]; then
    LIVENESS_NOTE="${LF}${LF}worktree-guard: layer 2 could not be checked — $LIVENESS_LIB is missing or could not be sourced, so whether the \`reference-transaction\` hook is armed for this repository is unknown."
    return 0
  fi
  wg_liveness "$1"
  rc=$?
  [ "$rc" -eq 0 ] && return 0
  if [ "$rc" -eq 2 ]; then
    # Unanswerable, not unarmed. Still not silent, for the reason above.
    LIVENESS_NOTE="${LF}${LF}worktree-guard: layer 2 could not be checked — $WG_LIVENESS_STATE ($1), so whether the \`$WG_LAYER2_HOOK\` hook is armed for this repository is unknown."
    return 0
  fi
  LIVENESS_NOTE="${LF}${LF}worktree-guard: separately — LAYER 2 IS NOT ARMED for this repository: $WG_LIVENESS_STATE.

  hooks path: $WG_LIVENESS_PATH
  expected:   $WG_LIVENESS_PATH/$WG_LAYER2_HOOK, executable

Layer 2 is the git-side \`$WG_LAYER2_HOOK\` hook. It is what refuses a HEAD move in
a shared primary checkout however the move is started, including from a terminal no
PreToolUse hook ever sees, and every way it can be absent was measured to exit 0 and move
HEAD without a word — so this paragraph is the only signal that it is off. The refusal
above came from layer 1 and stands on its own; it is unaffected by layer 2's state.

This check is not self-hosting: if this hook is itself unregistered, nothing checks either
layer. That regress terminates at settings.json, which is tracked and reviewable."
  return 0
}

# --- refusal ------------------------------------------------------------------------------
# The single exit for every mode-subject deny. $REFUSE_MSG holds the full message; it is a
# variable rather than an argument so the multi-line messages below stay readable.
REFUSE_MSG=''
refuse() { # $1 arm, $2 repo-root, $3 path-or-command
  local decision=deny
  [ "$MODE" = log ] && decision=would-deny
  # Only a refusal that will actually be PRINTED carries the report, so log mode pays for no
  # extra git process and says nothing it was not already going to say. The log line is left
  # alone for the same reason: the card fixes its field list, and a liveness field would be
  # one the format does not specify.
  if [ "$decision" = deny ]; then check_liveness "$2"; fi
  if append_log "$1" "$decision" "$2" "$3"; then
    [ "$MODE" = log ] && exit 0
    printf '%s\n' "$REFUSE_MSG$LIVENESS_NOTE$BAD_MODE_NOTE" 1>&2
    exit 2
  fi
  # Boundary 10, rules 1 and 2. Rule 1: log mode enforces nothing, and a guard that is not
  # blocking must not start blocking because a disk filled up — the cost is a gap in the
  # evidence window, and the warning is what keeps that gap from being silent. Rule 2: in
  # deny mode the command was already being refused, so the failed append changes only what
  # the message has to say. (Rule 3, a failed append while recording a BYPASS, belongs to
  # Arm D and arrives with it — there is no bypass path in this file yet.)
  if [ "$MODE" = log ]; then
    printf '%s\n' "$MSG_LOG_WARN" 1>&2
    exit 0
  fi
  # $BAD_MODE_NOTE rides both refusal exits, not just the one above. This arm is where the
  # log is unwritable, so the note is the ONLY surviving record of which value was mistyped —
  # dropping it here loses the fix instruction at the exact moment nothing else is keeping it.
  # It sits inside the first argument so "could not be recorded" stays its own trailing
  # paragraph; the grouping matches :239 deliberately.
  printf '%s\n\n%s\n' "$REFUSE_MSG$LIVENESS_NOTE$BAD_MODE_NOTE" "$MSG_NOT_RECORDED" 1>&2
  exit 2
}

# --- step 1: the payload -------------------------------------------------------------------
payload=""
if [ ! -t 0 ]; then
  payload=$(cat)
fi
[ -n "$payload" ] || hard_deny "$MSG_NO_PAYLOAD"

py=$(command -v python3 || command -v python) || py=""
[ -n "$py" ] || hard_deny "$MSG_NO_PYTHON"

# Emitted as `<session_id>\n<tool_name>\n<cwd>\n<operand>\nEND`. The operand is last because
# it is the only field that can contain a newline; the END sentinel is what keeps a command
# whose last character IS a newline from being eaten by command substitution's
# trailing-newline strip. NotebookEdit carries notebook_path and no file_path, so reading
# file_path alone would fail open on every notebook write.
#
# `cwd` is the session's working directory and is the starting point of the shared resolution
# rule. Only the Bash arms read it — Arm A resolves from the write TARGET and must not fall
# back to it (phase-guard.sh:191-197 records that as its one bug class).
parsed=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.loads(sys.stdin.read())
except Exception:
    sys.exit(1)
if not isinstance(p, dict):
    sys.exit(1)
ti = p.get("tool_input")
if not isinstance(ti, dict):
    ti = {}
operand = ti.get("file_path") or ti.get("notebook_path") or ti.get("command") or ""
if not isinstance(operand, str):
    operand = ""
def s(v):
    return v if isinstance(v, str) else ""
sys.stdout.write(s(p.get("session_id")) + "\n" + s(p.get("tool_name")) + "\n" +
                 s(p.get("cwd")).replace("\n", " ") + "\n" + operand + "\nEND")
')
rc=$?
[ "$rc" -eq 0 ] || hard_deny "$MSG_NO_PAYLOAD"

parsed=${parsed%END}
SID=${parsed%%"$LF"*}
rest=${parsed#*"$LF"}
tool=${rest%%"$LF"*}
rest=${rest#*"$LF"}
payload_cwd=${rest%%"$LF"*}
rest=${rest#*"$LF"}
operand=${rest%"$LF"}

# --- step 2: the mode ------------------------------------------------------------------
# Absence and a typo are deliberately different cases. Absent is the documented ship state
# and means `log`; a present-but-wrong value means someone tried to arm the guard and
# mistyped, and reading a failed configuration attempt as "off" is the silent disarm the
# version floor argues against.
#
# A bad value selects `deny` MODE and records why; it does NOT refuse here. That
# distinction is the whole of boundary 9 ("**deny**, and the message names the bad
# value") and of the card at :1481, and refusing here instead was a third, stricter
# reading no line of the card asks for. Measured 2026-08-27: refusing here blocked a
# Write to settings.json — the file whose exemption exists so "the hook registration
# and its WORKTREE_GUARD_MODE switch stay editable" — while the refusal's own text
# claimed this guard never blocks it. That is the footgun phase-guard.sh:280-283 names,
# recreated in the one state where you most need the switch. An exempt path, and a write
# already inside a worktree, are never guarded, so refusing them protects nothing and
# only removes the way out. Everything the guard WOULD have judged is still refused,
# under the strictest real mode, with the bad value named — see BAD_MODE_NOTE in refuse().
BAD_MODE_NOTE=''
if [ -z "${WORKTREE_GUARD_MODE+set}" ]; then
  MODE=log
else
  case "$WORKTREE_GUARD_MODE" in
    log|deny) MODE=$WORKTREE_GUARD_MODE ;;
    *) MODE=deny
       BAD_MODE_NOTE="

worktree-guard: also — WORKTREE_GUARD_MODE is set to '$WORKTREE_GUARD_MODE', which is
neither 'log' nor 'deny', so the guard is running in 'deny'. A mistyped switch is a failed
attempt to arm the guard, not permission to run unguarded; absence and a typo are
deliberately not the same case. Fix the value in settings.json, which is exempt from this
guard and therefore still editable — as is any path already inside a worktree." ;;
  esac
fi

# --- step 3: the checks every arm shares ---------------------------------------------------
# $ARM is the arm a refusal and its log line are attributed to, $SUBJECT the thing being
# judged — a write target under Arm A, a command line under Arms B2 and D. Both are set at
# dispatch so the shared checks below can refuse without knowing which arm called them; task
# 4 left the Bash-payload `arm` field open for exactly this reason.
#
# `B2D` is the value for a refusal that is the shared PRECONDITION of both Bash arms — an
# unlexable command line, an unaccountable argv[0], a repo-redirecting global option. Naming
# either arm alone would claim a judgement the guard never reached; the derivations behind
# those refusals are written for both (card, "Everything else that can redirect a segment").
ARM=''
SUBJECT=''

# $HOME. ~/.worktrees is where the answer to "then where should I work?" lives, so without it
# the guard cannot state its own remedy or test a path against the store it protects
# (boundary 13). One function, called from each arm's own entry point.
require_home() {
  [ -n "${HOME:-}" ] && return 0
  REFUSE_MSG='worktree-guard: blocked — $HOME is unset or empty.

The centralized worktree root is defined as ~/.worktrees, so with no $HOME there is no
path to test a checkout against and no location to name as the place to work instead.

Fix the environment this session was launched with. settings.json is exempt from this
guard, so the hook registration and its WORKTREE_GUARD_MODE switch stay editable.'
  refuse "$ARM" '' "$SUBJECT"
}

deny_version() { # $1 the raw --version output, quoted back so the failure is diagnosable
  REFUSE_MSG="worktree-guard: blocked — git is older than $FLOOR, or its version could not be read.

The guard tells a primary checkout from a linked worktree with
\`git rev-parse --path-format=absolute\`, which requires git >= $FLOOR. Without it the
bare forms differ by shape alone in every subdirectory of every primary checkout, and the
guard would read them as linked worktrees and allow — silently off for most writes.

  git --version said: $1

Install git >= $FLOOR. settings.json is exempt from this guard, so the hook registration
and its WORKTREE_GUARD_MODE switch stay editable."
  refuse "$ARM" '' "$SUBJECT"
}

# git, and its version. Split in two (task 17) so Arm A can run the presence check
# early — every rev-parse needs SOME git — while deferring the VERSION FLOOR until
# just before Step A8 below, which is the only probe that needs it
# (--path-format=absolute, landed in 2.31; --show-toplevel long predates it). That
# split is what lets the exemption check move ahead of the floor without ever
# asking a too-old git to answer a question it cannot.
require_git_present() {
  command -v git >/dev/null 2>&1 || { REFUSE_MSG="$MSG_NO_GIT"; refuse "$ARM" '' "$SUBJECT"; }
}

require_git_version() {
  local git_version version major minor tail_version
  git_version=$(git --version 2>/dev/null) || deny_version '<git --version failed>'
  version=${git_version#git version }
  major=${version%%.*}
  tail_version=${version#*.}
  minor=${tail_version%%.*}
  case "$major" in ''|*[!0-9]*) deny_version "$git_version" ;; esac
  case "$minor" in ''|*[!0-9]*) deny_version "$git_version" ;; esac
  if [ "$major" -lt "$FLOOR_MAJOR" ] ||
     { [ "$major" -eq "$FLOOR_MAJOR" ] && [ "$minor" -lt "$FLOOR_MINOR" ]; }; then
    deny_version "$git_version"
  fi
}

# Arms B2/D (lib/worktree_guard_bash_arms.sh) have no exemption check to defer the floor
# past — a Bash command is judged as a whole, not against a write target — so they keep
# needing presence and the floor together, in one call, unchanged by task 17.
require_git() {
  require_git_present
  require_git_version
}

# lib/worktree_guard_bash_arms.sh, unreadable or unparseable. Its own refusal rather than a
# fallthrough: the arms are sourced, and a `source` that fails returns non-zero without
# stopping the script, so the only alternative is a Bash call that no arm judged — the exact
# silent disarm the file header argues against. Mode-subject like every other precondition
# refusal, so `log` mode still only logs it.
deny_arms() { # $1 what happened to the file
  REFUSE_MSG="worktree-guard: command blocked — the file holding this guard's two Bash arms $1.

  expected at: $BASH_ARMS

Arms B2 and D live beside the classifier and ship with this hook. Without them a Bash
command would be evaluated by nothing at all, which is indistinguishable from the guard
being switched off, so it refuses instead. Restore $LIB_DIR. settings.json is exempt from
this guard, so the hook registration and its WORKTREE_GUARD_MODE switch stay editable."
  refuse "$ARM" '' "$SUBJECT"
}

# The absolute PHYSICAL form of a path that need not exist yet. Arm A's write target and Arm
# B2's `git worktree add` operand are the same problem: walk up to the deepest ancestor that
# does exist, resolve THAT physically, and re-append the tail.
#
# `pwd -P` is what makes it physical, and that is load-bearing on both arms. `git rev-parse`
# always reports physical paths while a payload can legitimately reach the same file through
# a symlinked ancestor (/tmp and /var are symlinks on macOS), so a logical path reads as
# outside the repo and the guard is off for that whole repo; and on Arm B2,
# ~/.worktrees/<n>/feat-link/feat-y sits under the centralized root as written and outside it
# once the symlink is followed.
#
# Reports through globals rather than stdout because both callers need the ancestor as well
# as the whole path, and because a `$( )` here would run in a subshell — where an `exit 2`
# raised by a caller's deny would not exit the hook at all (hooks/README.md records that
# exact trap).
PP_ANCHOR=''  # deepest ancestor that exists, resolved physically; empty if unenterable
PP_PATH=''    # the whole path, physical
physical_path() { # $1 base directory a relative path is read against, $2 the path
  local p dir tail_part
  case "$2" in
    /*) p=$2 ;;
    *)  p="${1%/}/$2" ;;
  esac
  dir=$p
  while [ ! -d "$dir" ] && [ "$dir" != "/" ]; do
    dir=$(dirname "$dir")
  done
  PP_ANCHOR=$(cd "$dir" 2>/dev/null && pwd -P) || PP_ANCHOR=""
  PP_PATH=""
  [ -n "$PP_ANCHOR" ] || return 1
  case "$p" in
    "$dir")   tail_part="" ;;
    "$dir"/*) tail_part=${p#"$dir"} ;;
    # Unreachable: the walk above only ever shortens $p, so $dir is always a prefix of it.
    *)        tail_part="" ;;
  esac
  PP_PATH="${PP_ANCHOR%/}$tail_part"
}

# --- step 4: arm dispatch ---------------------------------------------------------------
case "$tool" in
  Edit|Write|NotebookEdit) ARM=A ;;
  Bash)                    ARM=B2D ;;
  *) exit 0 ;;
esac
SUBJECT=$operand

if [ "$ARM" = B2D ]; then
  # Arms B2 and D live in a file of their own beside the classifier they read the command
  # through (lib/worktree_guard_bash_arms.sh). Sourced rather than run, because every arm
  # reports through the globals above and exits through the same refuse().
  #
  # Both failures below are checked explicitly. `source` of an absent or unparseable file
  # returns non-zero WITHOUT stopping the script, so an unchecked source falls through to
  # "no arm ran" — and an arm that silently did not run is indistinguishable from a command
  # with nothing to judge, which is the fail-open this whole file is written against. The
  # readability test comes first so the ordinary missing-file case refuses with a message of
  # its own rather than through bash's redirection diagnostic on the session's stderr.
  [ -r "$BASH_ARMS" ] || deny_arms 'is missing or could not be read'
  # shellcheck source=lib/worktree_guard_bash_arms.sh
  . "$BASH_ARMS" || deny_arms 'could not be sourced'
fi

# ==========================================================================================
# Arm A — a write into a primary checkout
# ==========================================================================================

# Step A1: no path, nothing to judge (boundary 2). The session's cwd is NOT consulted as a
# fallback, and that omission is the point: the cwd is a primary checkout constantly while
# the write target is not, and phase-guard.sh's Step 4 comment records this exact bug class
# ("Resolved from the WRITE TARGET, never from the session's cwd").
[ -n "$operand" ] || exit 0
file_path=$operand

# Step A2: git, presence only (boundary 3). Every later probe in this arm needs SOME git;
# the version floor is deferred to Step A6, after the exemption check, because only Step A8's
# --path-format=absolute needs it (task 17 — this ordering is what lets an exempt write
# survive an old-but-present git).
require_git_present

# Step A3: the repository that owns the WRITE TARGET. A PreToolUse Write names a file that
# need not exist yet, so walk up to the deepest ancestor that does and resolve from there.
#
# Every refusal in this step fires before the repository is known, so none of them can
# honour the exemption list (Step A4 below) — there is no repo root yet to relativize a path
# against, and matching `settings.json` by name alone would exempt every repository's copy,
# including ones this guard should be watching (task 17, Group B — "do not honour the
# exemption by filename here").
physical_path "$PWD" "$file_path" || :
fp_phys=$PP_ANCHOR
if [ -z "$fp_phys" ]; then
  REFUSE_MSG="worktree-guard: write blocked — no existing ancestor directory of the write target could be entered, so the repository that owns it is unknowable.

  write target: $file_path

Create the parent directory, or write from a session whose permissions can read it.
This refusal fires before the exemption list is reached, because the repository that owns
this path could not be identified — settings.json is not exempt here. This guard reads only
Edit, Write and NotebookEdit payloads; an edit made through the Bash tool is outside its
surface, and is the route to settings.json in this state."
  refuse A '' "$file_path"
fi

# Branch on the DIAGNOSTIC TEXT, never on the exit code: `--show-toplevel` exits 128 for
# "not a repo", for "bare repo", and for every validation failure alike. The second call
# runs only on the failure path, so the common case still costs one process.
top=$(git -C "$fp_phys" rev-parse --show-toplevel 2>/dev/null)
top_rc=$?
if [ "$top_rc" -ne 0 ]; then
  diag=$(git -C "$fp_phys" rev-parse --show-toplevel 2>&1 >/dev/null)
  case "$diag" in
    # Not a git repository at all — none of the guard's business.
    *'not a git repository'*) exit 0 ;;
    # A bare repository: no working tree exists to write into, so neither rule can be
    # violated. The signal is this diagnostic and not `--is-bare-repository`, which exits
    # 128 on a non-repo too and so cannot tell the two apart without the same text match.
    *'must be run in a work tree'*) exit 0 ;;
  esac
  # A third diagnostic. This branch denies every write in the repo, so it names what it
  # read — a deny that does not is indistinguishable from a deny for any other reason, and
  # an upstream rewording of either sentence above lands exactly here.
  REFUSE_MSG="worktree-guard: write blocked — git could not report the working tree for this path, and said something the guard does not recognize.

  write target: $file_path
  git said:     $diag

That is neither 'not a git repository' (which the guard allows) nor 'this operation must be
run in a work tree' (a bare repo, which it also allows), so the guard cannot tell whether
this write lands in a shared primary checkout. Resolve what git is reporting.
This refusal fires before the exemption list is reached, because the repository that owns
this path could not be identified — settings.json is not exempt here. This guard reads only
Edit, Write and NotebookEdit payloads; an edit made through the Bash tool is outside its
surface, and is the route to settings.json in this state."
  refuse A '' "$file_path"
fi
if [ -z "$top" ]; then
  REFUSE_MSG="worktree-guard: write blocked — git rev-parse --show-toplevel succeeded but printed nothing, so the repository root for this write is unknown.

  write target: $file_path

An empty answer is not an allow: the guard would compare against an empty root and read
every path as outside the repository. This refusal fires before the exemption list is
reached, because the repository that owns this path could not be identified —
settings.json is not exempt here. This guard reads only Edit, Write and NotebookEdit
payloads; an edit made through the Bash tool is outside its surface, and is the route to
settings.json in this state."
  refuse A '' "$file_path"
fi

# Step A4: the exemption list, stated in full (card :99). It is written out rather than
# incorporated by reference from phase-guard.sh:294-298, because the round-1 draft claimed
# to reuse that list "verbatim" while printing a shorter one — and under the shorter list a
# judge writing coding-memory/*/verdicts.jsonl from a primary checkout would be denied, so
# this feature's own gate would jam. Relativized against the repo root first.
#
# Runs here — as soon as the repo root is known, ahead of $HOME, the version floor and the
# submodule probe — so that an exempt write survives every precondition failure a later step
# could raise (task 17, Group A: this is what makes require_home()'s, deny_version()'s and
# the submodule-probe refusal's own "settings.json is exempt" sentence true).
case "$file_path" in
  "$top"/*) rel=${file_path#"$top"/} ;;
  *)
    # The target as written does not sit under the repo root, so try its physical form —
    # the payload may have reached the same file through a symlinked ancestor.
    case "$PP_PATH" in
      "$top"/*) rel=${PP_PATH#"$top"/} ;;
      # Reachable only when the target IS the repo root directory, which no Write means.
      # Retained as the floor: a path that does not relativize into this repo is not this
      # repo's write to judge.
      *) exit 0 ;;
    esac
    ;;
esac
case "$rel" in
  CODING_MEMORY.md|coding-memory/*|docs/*|.claude/*|settings.json) exit 0 ;;
  projects/*/memory/*) exit 0 ;;
  rules/*|skills/*) exit 0 ;;
esac

# Step A5: $HOME (boundary 13). Deferred behind the exemption check above (task 17); an
# exempt write no longer depends on $HOME being usable at all.
require_home

# Step A6: the git version floor. Deferred behind the exemption check above (task 17) —
# Step A3's --show-toplevel long predates 2.31, so resolving the root ahead of the floor is
# sound, and only Step A8's --path-format=absolute actually needs it.
require_git_version

# Step A7: a submodule. Its --git-dir and --git-common-dir are BOTH
# <super>/.git/modules/<name>, i.e. equal, so it reads as a primary checkout and omitting
# this step denies every submodule wholesale. Deliberate under-block (card, "Repo shapes
# that are out of scope"). Runs BEFORE the primary-vs-linked compare, so a swallowed failure
# here would land on the linked-worktree allow rather than on any error path — hence the
# explicit deny on a non-zero exit (boundary 6). Empty output is the NORMAL answer here and
# is the one probe whose emptiness is not a failure.
super=$(git -C "$fp_phys" rev-parse --show-superproject-working-tree 2>/dev/null)
super_rc=$?
if [ "$super_rc" -ne 0 ]; then
  REFUSE_MSG="worktree-guard: write blocked — the submodule probe (git rev-parse --show-superproject-working-tree) failed for this path.

  write target: $file_path
  repo root:    $top

Submodules are exempt from this guard, and the guard cannot tell whether this is one.
Allowing on a failed probe would make every submodule test indistinguishable from a
successful one. settings.json is exempt from this guard, so the hook registration and its
WORKTREE_GUARD_MODE switch stay editable."
  refuse A "$top" "$file_path"
fi
[ -z "$super" ] || exit 0

# Step A8: primary checkout, or linked worktree?
#
# --path-format=absolute is load-bearing, not stylistic. The bare forms are `.git` and
# `../../.git` from a subdirectory of a PRIMARY checkout — they differ in FORM only, so a
# naive compare reads "linked worktree" and allows, and the guard is silently off in every
# subdirectory of every primary checkout, which is most writes.
deny_probe() { # $1 the probe that failed, $2 why
  REFUSE_MSG="worktree-guard: write blocked — git rev-parse --path-format=absolute $1 $2.

  write target: $file_path
  repo root:    $top

The guard tells a shared primary checkout from a linked worktree by comparing --git-dir
with --git-common-dir. A missing answer makes the two differ, which reads as 'linked
worktree' and allows — so an unusable probe denies instead of guessing. settings.json is
exempt from this guard, so the hook registration and its WORKTREE_GUARD_MODE switch stay
editable."
  refuse A "$top" "$file_path"
}

git_dir=$(git -C "$fp_phys" rev-parse --path-format=absolute --git-dir 2>/dev/null) ||
  deny_probe '--git-dir' 'exited non-zero'
[ -n "$git_dir" ] || deny_probe '--git-dir' 'exited 0 but printed nothing'
common_dir=$(git -C "$fp_phys" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
  deny_probe '--git-common-dir' 'exited non-zero'
[ -n "$common_dir" ] || deny_probe '--git-common-dir' 'exited 0 but printed nothing'

[ "$git_dir" = "$common_dir" ] || exit 0

# --- the deny -----------------------------------------------------------------------------
# All five elements the card's Deny message contract names (:1438): what was blocked, why,
# the state that caused it, the legitimate fixes, and a NARROW closing claim. The shape comes
# from phase-guard.sh:537-561, whose comment counts FOUR without listing them; which element
# the card's fifth corresponds to is not determinable from that file, so no mapping is claimed
# here. Follow the card's list, which is the one written out. Element 4
# names the real escape hatches — settings.json is exempt so the registration stays
# editable, and WORKTREE_EXEMPT belongs to Arm D, not to this refusal. Element 5 does not
# claim the Bash write surface is covered, because it is not: a message that overclaims
# teaches sessions to distrust its true parts too.
repo_name=$(basename "$top")
REFUSE_MSG="worktree-guard: write blocked — $rel

This is the PRIMARY checkout of $repo_name, and primary checkouts are shared. Parallel
sessions in one checkout share its single HEAD: a branch switch under another session's
feet swaps the files it is editing, and nothing in the tree records that it happened.

  repo root:    $top
  write target: $file_path

Work from a linked worktree instead:
  1. Start the session in one — EnterWorktree, --worktree, or an Agent with
     isolation: \"worktree\" — all of which land under ~/.worktrees/$repo_name/.
  2. Or create one by hand:
       git worktree add ~/.worktrees/$repo_name/<name> -b <branch>
  3. settings.json is exempt from this guard, so this hook's own registration and its
     WORKTREE_GUARD_MODE switch always stay editable. WORKTREE_EXEMPT=<reason> bypasses
     Arm D's branch-switch refusals; it does not apply to this one.

This guard reads Edit, Write and NotebookEdit payloads. Writes made through the Bash tool
are not covered by it."
refuse A "$top" "$file_path"
