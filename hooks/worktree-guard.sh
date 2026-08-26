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

# --- messages ---------------------------------------------------------------------------
# Every message carries the `worktree-guard:` prefix. phase-guard.sh prefixes its own and
# both hooks are PreToolUse on the same matchers, so a bare refusal does not say which one
# fired (card, "Deny message contract").

MSG_NO_PYTHON='worktree-guard: blocked — no python3 or python on PATH, so this tool payload could not be read at all. The guard cannot permit a request it cannot identify.'
MSG_NO_PAYLOAD='worktree-guard: blocked — this tool payload could not be read as JSON. The guard cannot permit a request it cannot identify, and it will not record a decision under a session id it had to invent.'
MSG_NO_GIT='worktree-guard: blocked — no git on PATH, so the guard could not verify the checkout this request acts on.'
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

# --- refusal ------------------------------------------------------------------------------
# The single exit for every mode-subject deny. $REFUSE_MSG holds the full message; it is a
# variable rather than an argument so the multi-line messages below stay readable.
REFUSE_MSG=''
refuse() { # $1 arm, $2 repo-root, $3 path-or-command
  local decision=deny
  [ "$MODE" = log ] && decision=would-deny
  if append_log "$1" "$decision" "$2" "$3"; then
    [ "$MODE" = log ] && exit 0
    printf '%s\n' "$REFUSE_MSG" 1>&2
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
  printf '%s\n\n%s\n' "$REFUSE_MSG" "$MSG_NOT_RECORDED" 1>&2
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
if [ -z "${WORKTREE_GUARD_MODE+set}" ]; then
  MODE=log
else
  case "$WORKTREE_GUARD_MODE" in
    log|deny) MODE=$WORKTREE_GUARD_MODE ;;
    *) hard_deny "worktree-guard: blocked — WORKTREE_GUARD_MODE is set to '$WORKTREE_GUARD_MODE', which is neither 'log' nor 'deny'. A mistyped switch is a failed attempt to arm the guard, not permission to run unguarded; fix the value in settings.json (which this guard never blocks)." ;;
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

# git, and its version. Both run before any rev-parse, because a missing or too-old git makes
# every later probe fail in a way that is indistinguishable from "not a git repository" — and
# `git rev-parse --path-format=absolute` exits 128 for BOTH of those, so the support test
# cannot be an exit code (card, "Detection", task 2 re-probe).
require_git() {
  local git_version version major minor tail_version
  command -v git >/dev/null 2>&1 || { REFUSE_MSG="$MSG_NO_GIT"; refuse "$ARM" '' "$SUBJECT"; }
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

# ==========================================================================================
# Arms B2 and D — the Bash command line, layer 1
# ==========================================================================================

# Step 1: the command, and the facts it yields. An empty command is nothing to judge.
command_line=$operand
[ -n "$command_line" ] || exit 0

deny_lexer() { # $1 what could not be read, quoted back so the failure is diagnosable
  REFUSE_MSG="worktree-guard: command blocked — the command line could not be lexed, so what it runs is unknown.

  command: $command_line
  failed:  $1

Boundary 7: both Bash arms judge only what the lexer returns, so an unreadable command line
is an unknown one and cannot be allowed. Restore $LIB_DIR (it ships beside this hook).
settings.json is exempt from this guard, so the hook registration and its
WORKTREE_GUARD_MODE switch stay editable."
  refuse "$ARM" '' "$command_line"
}

facts=$(printf '%s' "$command_line" | "$py" "$CLASSIFIER" 2>/dev/null) ||
  deny_lexer "$CLASSIFIER exited non-zero"

# One fact per LINE, compared as a whole line. An unquoted `for f in $facts` splits on bash's
# default IFS, which includes the TAB every indexed fact carries — the defect git-guard.sh
# records at :80-86 and doc-guard.sh was ported off in task 5.
has_fact() { # $1 the exact fact
  local f
  while IFS= read -r f; do
    [ "$f" = "$1" ] && return 0
  done <<< "$facts"
  return 1
}

facts_named() { # $1 fact name — every indexed fact of that name, one per line
  local f
  while IFS= read -r f; do
    case "$f" in "$1$TAB"*) printf '%s\n' "$f" ;; esac
  done <<< "$facts"
}

fact_operand() { # $1 fact name, $2 segment index — that fact's operand, if it has one
  local name idx operand
  while IFS="$TAB" read -r name idx operand; do
    if [ "${idx:-}" = "$2" ]; then printf '%s' "$operand"; return 0; fi
  done <<< "$(facts_named "$1")"
  return 1
}

# Step 2: the fast path. Only the SEG_* facts belong to these arms — COMMIT*/PUSH*/
# SCOPE_UNKNOWN are git-guard's and doc-guard's, and a line carrying none of ours is a line
# neither arm has anything to say about. Checked before $HOME and before git, so an ordinary
# Bash call costs one python process and nothing else.
seg_count=0
while IFS= read -r f; do
  case "$f" in SEG_*) seg_count=$((seg_count+1)) ;; esac
done <<< "$facts"
[ "$seg_count" -gt 0 ] || exit 0

require_home
require_git

# Step 3: the bypass, read lazily. `WORKTREE_EXEMPT=<reason> git switch main` allows the
# command and records the reason (card, "Bypass"); it is read only when a refusal is actually
# due, so an allowed command never pays for a second lexer run and never logs a bypass it did
# not need. The reason comes off the command line as a leading env-assignment — the same
# route classify-pr-command.py reads MERGE_EXEMPT/JUDGE_EXEMPT by, and the only route that
# works, since a PreToolUse hook's own environment is the session's, not the command's. An
# inherited value is honoured as a fallback because the card states layer 1 reads it from its
# environment.
#
# LINE-SCOPED on purpose, unlike every SEG_* fact. The granting/denying rule exists because a
# flat fact cannot say which segment it came from, so one segment could excuse another; this
# is not that. The user typed it, it names the whole tool call, and a per-segment reading
# would leave `WORKTREE_EXEMPT=x cd /repo && git switch main` refused — plainly the shape they
# meant to exempt.
exempt_reason() {
  local reason
  reason=$(printf '%s' "$command_line" | "$py" -c '
import sys
sys.path.insert(0, sys.argv[1])
from shell_segments import segments
name = sys.argv[2]
for assigns, _argv in segments(sys.stdin.read()):
    if name in assigns:
        sys.stdout.write(assigns[name])
        break
' "$LIB_DIR" "$EXEMPT_VAR" 2>/dev/null) || deny_lexer "$LIB_DIR/shell_segments.py could not be read"
  [ -n "$reason" ] || reason=${WORKTREE_EXEMPT:-}
  printf '%s' "$reason"
}

# The single exit for every fact-derived refusal on these two arms: bypass first, then the
# ordinary mode-subject refusal. $REFUSE_MSG holds the message, as everywhere else.
refuse_command() { # $1 arm, $2 repo-root
  local reason
  reason=$(exempt_reason)
  if [ -n "$reason" ]; then
    # Boundary 10, rule 3. A bypass is an ALLOW, so a failed append must not turn it into a
    # refusal — the user reaching for the escape hatch is by construction already blocked on
    # something. The loss is silent in the log by design; this warning is its only trace.
    if append_log "$1" bypass "$2" "$command_line" "$reason"; then
      exit 0
    fi
    printf '%s\n' "$MSG_BYPASS_WARN" 1>&2
    exit 0
  fi
  refuse "$1" "$2" "$command_line"
}

# Step 4: the line-scoped refusals, before any segment is resolved.
#
# SEG_UNPARSED — segments() returned [] for a non-empty command. shell_segments.py calls that
# a deliberate fail-OPEN for its other callers; this guard is the last line of defence and
# overrides it, because an empty fact set reads as "no worktree add here" and an absent fact
# is not safety.
if has_fact SEG_UNPARSED; then
  REFUSE_MSG="worktree-guard: command blocked — this command line cannot be lexed at all, so the guard cannot tell what it runs.

  command: $command_line

The lexer returned no segments for a non-empty command (usually unbalanced quoting). An
empty answer is not an allow: it is indistinguishable from a command that runs nothing.
Rewrite the command so it lexes, or bypass a genuinely intended one with
$EXEMPT_VAR=<reason>. settings.json is exempt from this guard, so the hook registration
and its WORKTREE_GUARD_MODE switch stay editable."
  refuse_command "$ARM" ''
fi

# Step 5: the per-segment refusals that need no repository at all. Each names its own segment
# — an indexed fact is judged on its own and no fact can vouch for a segment it did not come
# from. Lowest index first, so the message names the first thing on the line that earned it.
# $4 and $5 default to the shared-precondition attribution, which is what a refusal raised
# before the segment's repository is known can honestly claim. Once an arm HAS resolved a
# repository it passes both, so the log line names the arm that judged and the root it
# judged against rather than a blank field.
deny_segment() { # $1 headline, $2 the body, $3 segment index, [$4 arm], [$5 repo-root]
  REFUSE_MSG="worktree-guard: command blocked — $1

  command: $command_line
  segment: segment $3

$2

Bypass a genuinely intended command with $EXEMPT_VAR=<reason>. settings.json is exempt from
this guard, so the hook registration and its WORKTREE_GUARD_MODE switch stay editable."
  refuse_command "${4:-$ARM}" "${5:-}"
}

sort_by_index() { sort -t"$TAB" -k2,2n; }

# Derivations 1, 2 and 3 — three facts, one shape and one loop. Each names a way a segment
# can address a different repository, or hide that it runs git at all, that no amount of
# resolving can reach, so all three refuse before any repository is resolved:
#
#   SEG_SCOPE_OPT (1)  a global option resolve_subcommand refused to walk past, other than
#                      -C. Read off that return VALUE, never a list of option names, so an
#                      option git adds tomorrow lands here and not in "allow". It cannot join
#                      the cd/-C resolution path because the fact carries the option's name
#                      and never its value — measured, `--git-dir=/x` and `--git-dir /x` emit
#                      byte-identical output.
#   SEG_ENV (2)        a GIT_ assignment. A prefix test over the namespace git owns, so a
#                      variable added upstream is covered the day it ships. Measured:
#                      `GIT_DIR=/x git commit -m y` is otherwise byte-identical to a local
#                      commit, so the redirect is invisible to any rule that skips assignments.
#   SEG_OPAQUE (3)     argv[0] is neither `git` nor `cd`, yet one of them runs in the segment
#                      — behind a wrapper, a shell keyword, or a quoted string. A command
#                      that merely MENTIONS git lands here too; that false denial is accepted
#                      and stated, and WORKTREE_EXEMPT clears it.
for fact in SEG_SCOPE_OPT SEG_ENV SEG_OPAQUE; do
  case "$fact" in
    SEG_SCOPE_OPT) headline='this segment carries a global git option the guard cannot see past.'
                   detail='option' ;;
    SEG_ENV)       headline='this segment sets a GIT_ variable, which can point git at another repository.'
                   detail='variable' ;;
    SEG_OPAQUE)    headline="the guard cannot hold this segment's command accountable for the git or cd it runs."
                   detail='token' ;;
  esac
  while IFS="$TAB" read -r name idx operand; do
    [ -n "${idx:-}" ] || continue
    deny_segment "$headline" "  $detail: $operand

This is a redirect the guard cannot follow: what it points at is not readable from the
command line, so which repository this segment acts on cannot be established. \`cd\` and
\`-C\` are the only two redirects resolved rather than refused." "$idx"
  done <<< "$(facts_named "$fact" | sort_by_index)"
done

# ------------------------------------------------------------------------------------------
# The shared resolution rule — ONE function, called by both arms below.
# ------------------------------------------------------------------------------------------
#
# Effective repo for segment `i` (card, "The shared resolution rule"). Start from the
# session's cwd. Apply every SEG_CD whose index is < i, in index order, each resolved
# relative to the result of the one before — a cd affects the segments after it, never
# itself. Then apply segment i's own SEG_GIT_C operand if it has one: `-C` wins over `cd`,
# because the shell has already chosen the directory by the time git applies `-C`. Resolve
# the result to an absolute real path, then take the repository that owns it.
#
# If any step carries the sentinel, or the final path does not resolve, DENY — naming both
# the operand and its segment index (boundary 12). An unresolvable working directory means
# the guard cannot tell which repository it is protecting.
#
# `cd` and `-C` are the only two redirects this rule resolves. Every other way a segment can
# address a different repository has already denied above, by derivations 1 through 3.
#
# THERE IS NO SECOND COPY OF THIS. Round 4's finding was Arm B2 and Arm D each deriving it
# separately with only one of them complete; the suite's GROUP S substitutes this function at
# run time and fails any arm that does not move with it.
EFF_DIR=''      # the effective working directory of the segment
EFF_ROOT=''     # the repository that owns it — EMPTY when there is none
EFF_PRIMARY=''  # 1 when that repository's shared primary checkout is the one being acted on
resolve_effective_repo() {
  # $1 the segment index. The signature is spelled on its own line, without the trailing
  # argument comment the rest of this file uses, because the suite's GROUP S substitutes this
  # function by matching that line exactly.
  local i=$1 name idx operand dir common git_dir diag rc
  # Derivation 4. segments() appends a fresh segment per control operator and throws the
  # operator away, so `)` and `}` are indistinguishable in its return value — yet bash
  # discards a cd at `)` and keeps it past `}`. An index-ordered rule therefore carries a
  # subshell's cd to segments bash would never have applied it to. This OVER-DENIES the
  # `( ... )` case, refusing a command that was in fact safe; that is the correct direction,
  # and it is stated rather than left to be rediscovered.
  if has_fact SEG_GROUPED; then
    REFUSE_MSG="worktree-guard: command blocked — this command line groups commands with ( ) or { } and changes directory inside the grouping.

  command: $command_line

Derivation 4: the lexer reports that a grouping operator and a \`cd\` are both present, but
not which one is which — bash discards a \`cd\` at \`)\` and keeps it past \`}\`, and those
two are indistinguishable in what the guard can read. So it cannot tell which segments the
\`cd\` applies to, and refuses rather than guessing. Run the command without the grouping,
or bypass it with $EXEMPT_VAR=<reason>. settings.json is exempt from this guard, so the hook
registration and its WORKTREE_GUARD_MODE switch stay editable."
    refuse_command "$ARM" ''
  fi

  dir=$CWD
  while IFS="$TAB" read -r name idx operand; do
    [ -n "${idx:-}" ] || continue
    [ "$idx" -lt "$i" ] || continue
    if [ "$operand" = "$SENTINEL" ]; then
      deny_segment \
        "an earlier segment changes directory somewhere the guard cannot resolve." \
        "That \`cd\` names a variable, a substitution, or nothing at all — a directory only
the running shell could name. Every segment after it therefore acts on a repository the
guard cannot identify, which is the one thing it may not allow. The operand is on the
command line above." \
        "$idx"
    fi
    dir=$(cd "$dir" 2>/dev/null && cd "$operand" 2>/dev/null && pwd -P) || dir=""
    if [ -z "$dir" ]; then
      deny_segment \
        "an earlier segment changes directory to somewhere that cannot be entered." \
        "  cd to:   $operand

The guard could not enter that directory, so it cannot tell which repository the segments
after it act on." \
        "$idx"
    fi
  done <<< "$(facts_named SEG_CD | sort_by_index)"

  # `-C` wins over `cd`: the shell has already chosen the directory by the time git applies
  # it. Bound to THIS segment only — a `-C` on an earlier segment never carries, which is the
  # round-4 advisory finding and the incident this feature exists to stop.
  operand=$(fact_operand SEG_GIT_C "$i") || operand=''
  if [ -n "$operand" ]; then
    if [ "$operand" = "$SENTINEL" ]; then
      deny_segment \
        "this segment carries a \`-C\` whose directory the guard cannot resolve." \
        "Either the operand is attached (\`-C=/x\`, whose value lives inside the token under
git's own short-option grammar) or the segment carries more than one \`-C\`, which compose in
git and would have to compose here too. Spell it as a single \`-C <dir>\`." \
        "$i"
    fi
    dir=$(cd "$dir" 2>/dev/null && cd "$operand" 2>/dev/null && pwd -P) || dir=""
    if [ -z "$dir" ]; then
      deny_segment \
        "this segment's \`-C\` names a directory that cannot be entered." \
        "  -C:      $operand

The guard could not enter that directory, so it cannot tell which repository this segment
acts on — and a \`git worktree add\` or a HEAD move whose repository is unknown is precisely
the case it exists to catch." \
        "$i"
    fi
  fi
  EFF_DIR=$dir
  EFF_ROOT=''
  EFF_PRIMARY=''

  # The repository that owns it. Branch on the DIAGNOSTIC TEXT and never on the exit code:
  # rev-parse exits 128 for "not a repo", for "bare repo" and for every validation failure
  # alike. The first two are none of the guard's business and leave EFF_ROOT empty; a third
  # diagnostic denies and quotes what it read, because an upstream rewording lands here.
  common=$(git -C "$EFF_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    diag=$(git -C "$EFF_DIR" rev-parse --path-format=absolute --git-common-dir 2>&1 >/dev/null)
    case "$diag" in
      *'not a git repository'*|*'must be run in a work tree'*) return 0 ;;
    esac
    REFUSE_MSG="worktree-guard: command blocked — git could not report the repository for a directory this command acts on, and said something the guard does not recognize.

  command:   $command_line
  segment:   segment $i
  directory: $EFF_DIR
  git said:  $diag

That is neither 'not a git repository' nor 'this operation must be run in a work tree',
both of which the guard allows, so it cannot tell whether this segment acts on a shared
primary checkout. Resolve what git is reporting. settings.json is exempt from this guard, so
the hook registration and its WORKTREE_GUARD_MODE switch stay editable."
    refuse_command "$ARM" ''
  fi
  if [ -z "$common" ]; then
    REFUSE_MSG="worktree-guard: command blocked — git rev-parse --path-format=absolute --git-common-dir succeeded but printed nothing, so the repository for this segment is unknown.

  command:   $command_line
  segment:   segment $i
  directory: $EFF_DIR

An empty answer is not an allow: the guard would compare against an empty root and read
every checkout as somebody else's. settings.json is exempt from this guard, so the hook
registration and its WORKTREE_GUARD_MODE switch stay editable."
    refuse_command "$ARM" ''
  fi

  # The REPOSITORY, not the checkout. `--show-toplevel` answers with the working tree the
  # command sits in, which for a linked worktree is the worktree itself — so a rule built on
  # it would call this repo's store ~/.worktrees/feat-x. The common dir is shared by every
  # checkout of one repository (measured: it is <repo>/.git from the primary checkout, from a
  # subdirectory of it, and from a linked worktree alike), so its parent is the repository.
  case "$common" in
    */.git) EFF_ROOT=${common%/.git} ;;
    # A repository whose git dir is not a `.git` beside the work tree — a bare one, or a
    # --separate-git-dir. There is no work tree to name, so the git dir IS the identity.
    *)      EFF_ROOT=$common ;;
  esac

  # Primary checkout, or linked worktree? --path-format=absolute is load-bearing and not
  # stylistic: the bare forms are `.git` and `../../.git` from a subdirectory of a PRIMARY
  # checkout, so they differ in FORM only and a naive compare reads "linked worktree".
  git_dir=$(git -C "$EFF_DIR" rev-parse --path-format=absolute --git-dir 2>/dev/null) || git_dir=""
  if [ -z "$git_dir" ]; then
    REFUSE_MSG="worktree-guard: command blocked — git rev-parse --path-format=absolute --git-dir gave no usable answer for a directory this command acts on.

  command:   $command_line
  segment:   segment $i
  directory: $EFF_DIR

The guard tells a shared primary checkout from a linked worktree by comparing --git-dir with
--git-common-dir. A missing answer makes the two differ, which reads as 'linked worktree' and
allows — so an unusable probe denies instead of guessing. settings.json is exempt from this
guard, so the hook registration and its WORKTREE_GUARD_MODE switch stay editable."
    refuse_command "$ARM" ''
  fi
  [ "$git_dir" = "$common" ] && EFF_PRIMARY=1
  return 0
}

# Step 6: the session's own working directory, which every resolution starts from. The
# payload names it; $PWD is the fallback, the same shape context-handoff-watch.sh:74-75 uses.
CWD=$payload_cwd
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD=$PWD
CWD=$(cd "$CWD" 2>/dev/null && pwd -P) || CWD=""
if [ -z "$CWD" ]; then
  REFUSE_MSG="worktree-guard: command blocked — this session's working directory could not be entered, so no segment of this command can be resolved to a repository.

  command: $command_line

Every effective-repo resolution starts from the session cwd; without it the guard cannot
tell which repository anything on this line acts on. settings.json is exempt from this
guard, so the hook registration and its WORKTREE_GUARD_MODE switch stay editable."
  refuse_command "$ARM" ''
fi

# Step 7: the judged segments, in index order across both arms. A line may carry a worktree
# add and a HEAD move at once, and the deny must name whichever came first.
while IFS="$TAB" read -r idx kind operand; do
  [ -n "${idx:-}" ] || continue
  resolve_effective_repo "$idx"

  if [ "$kind" = add ]; then
    # ---- Arm B2 — a hand-rolled `git worktree add` ---------------------------------------
    # An unresolvable operand or an unidentifiable repository denies: a worktree add whose
    # target the guard cannot identify is precisely the case it exists to catch (card, Arm B2
    # step 4). Contrast Arm D below, where "no repository here" is genuinely none of the
    # guard's business.
    if [ -z "$EFF_ROOT" ]; then
      deny_segment \
        "this segment adds a worktree from a directory that is not in any git repository." \
        "  directory: $EFF_DIR

The centralized store is ~/$STORE_REL/<repo-name>/, and with no repository there is no
<repo-name> — so the guard cannot say where this worktree should go, and cannot vouch for
where it is going. Run the add from inside the repository it belongs to." \
        "$idx" B2 ""
    fi
    case "$operand" in
      "$SENTINEL"|*'$'*|*'`'*)
        # Same test the classifier applies to a `cd` operand, for the same reason: a variable
        # or a substitution names a directory only the running shell could resolve.
        deny_segment \
          "the guard cannot tell where this \`git worktree add\` would put the worktree." \
          "  operand: $operand

The path operand is a variable, a substitution, or a token the option table cannot account
for, so it cannot be resolved to a real location and cannot be tested against the
centralized store. Spell the destination out." \
          "$idx" B2 "$EFF_ROOT" ;;
    esac
    physical_path "$EFF_DIR" "$operand" || \
      deny_segment \
        "no existing ancestor of this \`git worktree add\` destination could be entered." \
        "  operand: $operand

The destination is resolved to an absolute real path before it is judged — a relative
operand and a symlinked one both have to be — and no part of this one could be entered." \
        "$idx" B2 "$EFF_ROOT"
    add_path=$PP_PATH

    repo_name=$(basename "$EFF_ROOT")
    store="${HOME%/}/$STORE_REL/$repo_name"
    # Physical on both sides or the compare is meaningless: $add_path came back from `pwd -P`
    # and a store reached through a symlinked ~ would never match it. A store that does not
    # exist yet is the ordinary case for a repo's first worktree, and keeps its literal form.
    store_phys=$(cd "$store" 2>/dev/null && pwd -P) || store_phys=$store
    case "$add_path" in
      "$store_phys"/*) : ;;
      *)
        deny_segment \
          "this \`git worktree add\` would put a worktree outside the centralized store." \
          "  destination: $add_path
  repository:  $EFF_ROOT
  must be under: $store/

Worktrees for every repository on this machine live at ~/$STORE_REL/<repo-name>/<name>, so
that 'what am I working on' is a single ls and no checkout ever nests inside the repository
it is a checkout of. Create it there instead:
    git worktree add $store/<name> -b <branch>" \
          "$idx" B2 "$EFF_ROOT" ;;
    esac

    # Boundary 14 — the basename collision. Two repositories named `api` in different orgs
    # would share ~/.worktrees/api/, so each store carries a marker naming the repo root it
    # belongs to. An absent marker is the normal state of a store nobody has used yet; an
    # UNREADABLE one is an undetermined collision, and reading a failed read as "no marker
    # yet" is exactly how two repos come to share one directory silently.
    marker="$store/$MARKER_NAME"
    if [ -e "$marker" ]; then
      if IFS= read -r marker_root < "$marker" 2>/dev/null && [ -n "$marker_root" ]; then
        if [ "$marker_root" != "$EFF_ROOT" ]; then
          deny_segment \
            "the centralized store for this repository name already belongs to a different repository." \
            "  store:        $store/
  marked for:   $marker_root
  this repo is: $EFF_ROOT

Both repositories have the basename '$repo_name', so both would claim the same store and
their worktrees would be indistinguishable. Give one of them a store of its own, or move the
marker deliberately once you have checked what is already in there." \
            "$idx" B2 "$EFF_ROOT"
        fi
      else
        deny_segment \
          "the marker naming which repository this store belongs to could not be read." \
          "  marker: $marker

An unreadable marker is an UNDETERMINED collision, not an absent one. Treating a failed read
as 'no marker yet' is how two repositories come to share one store silently, which is the
exact outcome the marker exists to prevent. Fix its permissions or its contents." \
          "$idx" B2 "$EFF_ROOT"
      fi
    fi
  else
    # ---- Arm D — moving a primary checkout's HEAD, layer 1 --------------------------------
    # A linked worktree's HEAD is its own and nobody else shares it, so only the primary
    # checkout is refused. No repository at all is one of the four cases that are genuinely
    # none of the guard's business, so it allows — unlike Arm B2 above, which has a store to
    # place the worktree in either way.
    [ "$EFF_PRIMARY" = 1 ] || continue
    repo_name=$(basename "$EFF_ROOT")
    REFUSE_MSG="worktree-guard: command blocked — \`git $operand\` would move HEAD in the PRIMARY checkout of $repo_name.

  command:    $command_line
  segment:    segment $idx
  repo root:  $EFF_ROOT

Primary checkouts are shared. Parallel sessions in one checkout share its single HEAD: this
command swaps the files another session is editing out from under it, and nothing in the
tree records that it happened. This is the incident the guard exists for, not a hypothetical.

Move HEAD in a linked worktree instead:
  1. Start the session in one — EnterWorktree, --worktree, or an Agent with
     isolation: \"worktree\" — all of which land under ~/$STORE_REL/$repo_name/.
  2. Or create one by hand:
       git worktree add ~/$STORE_REL/$repo_name/<name> -b <branch>
  3. If this really has to happen in the shared checkout, re-run it as
       $EXEMPT_VAR=<reason> <command>
     which allows it and records the reason. settings.json is exempt from this guard, so
     this hook's own registration and its WORKTREE_GUARD_MODE switch always stay editable.

This arm reads commands run through the Bash tool. A human typing in their own terminal is
never intercepted by any PreToolUse hook."
    refuse_command D "$EFF_ROOT"
  fi
# The two arms' facts, re-keyed to <index><TAB><kind><TAB><operand> and merged into ONE
# index-ordered stream. Sorted across both, not concatenated: a line carrying an add and a
# HEAD move must be judged left to right, or the deny names whichever arm happened to be
# listed first rather than whichever the reader typed first.
done <<< "$(
  {
    facts_named SEG_WORKTREE_ADD |
      while IFS="$TAB" read -r name idx operand; do
        [ -n "${idx:-}" ] && printf '%s%s%s%s%s\n' "$idx" "$TAB" add "$TAB" "$operand"
      done
    facts_named SEG_BRANCH_MOVE |
      while IFS="$TAB" read -r name idx operand; do
        [ -n "${idx:-}" ] && printf '%s%s%s%s%s\n' "$idx" "$TAB" move "$TAB" "$operand"
      done
  } | sort -t"$TAB" -k1,1n
)"

# Nothing on this line earned a refusal.
exit 0
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

# Step A2: $HOME (boundary 13).
require_home

# Step A3: git, and its version.
require_git

# Step A4: the repository that owns the WRITE TARGET. A PreToolUse Write names a file that
# need not exist yet, so walk up to the deepest ancestor that does and resolve from there.
physical_path "$PWD" "$file_path" || :
fp_phys=$PP_ANCHOR
if [ -z "$fp_phys" ]; then
  REFUSE_MSG="worktree-guard: write blocked — no existing ancestor directory of the write target could be entered, so the repository that owns it is unknowable.

  write target: $file_path

Create the parent directory, or write from a session whose permissions can read it.
settings.json is exempt from this guard, so the hook registration and its
WORKTREE_GUARD_MODE switch stay editable."
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
settings.json is exempt from this guard, so the hook registration and its
WORKTREE_GUARD_MODE switch stay editable."
  refuse A '' "$file_path"
fi
if [ -z "$top" ]; then
  REFUSE_MSG="worktree-guard: write blocked — git rev-parse --show-toplevel succeeded but printed nothing, so the repository root for this write is unknown.

  write target: $file_path

An empty answer is not an allow: the guard would compare against an empty root and read
every path as outside the repository. settings.json is exempt from this guard, so the hook
registration and its WORKTREE_GUARD_MODE switch stay editable."
  refuse A '' "$file_path"
fi

# Step A5: a submodule. Its --git-dir and --git-common-dir are BOTH
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

# Step A6: the exemption list, stated in full (card :99). It is written out rather than
# incorporated by reference from phase-guard.sh:294-298, because the round-1 draft claimed
# to reuse that list "verbatim" while printing a shorter one — and under the shorter list a
# judge writing coding-memory/*/verdicts.jsonl from a primary checkout would be denied, so
# this feature's own gate would jam. Relativized against the repo root first.
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

# Step A7: primary checkout, or linked worktree?
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
