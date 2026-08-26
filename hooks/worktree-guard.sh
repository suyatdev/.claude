#!/usr/bin/env bash
#
# worktree-guard.sh — PreToolUse hook (matcher: Edit|Write|NotebookEdit|Bash).
#
# Layer 1 of the worktree location guard. Arm A refuses a write whose target sits in a
# repository's PRIMARY checkout: parallel sessions share that checkout and share its one
# HEAD, so a branch switch under another session's feet destroys work no test catches.
# Design, boundaries and scenarios: docs/features/worktree-location-guard.md.
#
# Exit 0 = allow. Exit 2 = deny, reason on stderr. Nothing is ever written to stdout, on
# any path: a PreToolUse hook's stdout is a protocol channel, not a place to talk.
#
# SCOPE TODAY — Arm A only. The Bash arms (B2, hand-rolled `git worktree add`; D, branch
# switching) are card tasks 5 and 6 and are NOT implemented here. A `Bash` payload is
# ALLOWED, silently, and the allow is explicit rather than incidental (see arm dispatch):
# an unimplemented arm must not masquerade as an evaluated one, and it must not deny
# either — half a guard that blocks the commands it cannot yet judge is worse than no arm.
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

# --- messages ---------------------------------------------------------------------------
# Every message carries the `worktree-guard:` prefix. phase-guard.sh prefixes its own and
# both hooks are PreToolUse on the same matchers, so a bare refusal does not say which one
# fired (card, "Deny message contract").

MSG_NO_PYTHON='worktree-guard: blocked — no python3 or python on PATH, so this tool payload could not be read at all. The guard cannot permit a request it cannot identify.'
MSG_NO_PAYLOAD='worktree-guard: blocked — this tool payload could not be read as JSON. The guard cannot permit a request it cannot identify, and it will not record a decision under a session id it had to invent.'
MSG_NO_GIT='worktree-guard: blocked — no git on PATH, so the guard could not verify the checkout this write lands in.'
MSG_LOG_WARN="worktree-guard: this refusal could not be appended to $LOG_FILE — the guard is in log mode, so the write was allowed and the evidence line is lost."
MSG_NOT_RECORDED="worktree-guard: additionally, this decision could not be recorded in $LOG_FILE."

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
append_log() { # $1 arm, $2 decision, $3 repo-root, $4 path-or-command
  local ts field line
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || return 1
  # 21.4% of real commands carry a newline and 0.0% carry a tab, so tabs separate and the
  # last field escapes LF as the two characters \n. A line-oriented log whose fields hold
  # raw newlines is not parseable.
  field=${4//"$LF"/\\n}
  line="$ts$TAB$SID$TAB$1$TAB$MODE$TAB$2$TAB$3$TAB$field"
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

# Emitted as `<session_id>\n<tool_name>\n<operand>\nEND`. The operand is last because it is
# the only field that can contain a newline; the END sentinel is what keeps a command whose
# last character IS a newline from being eaten by command substitution's trailing-newline
# strip. NotebookEdit carries notebook_path and no file_path, so reading file_path alone
# would fail open on every notebook write.
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
                 operand + "\nEND")
')
rc=$?
[ "$rc" -eq 0 ] || hard_deny "$MSG_NO_PAYLOAD"

parsed=${parsed%END}
SID=${parsed%%"$LF"*}
rest=${parsed#*"$LF"}
tool=${rest%%"$LF"*}
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

# --- step 3: arm dispatch ---------------------------------------------------------------
# Bash is matched and explicitly allowed rather than falling off the end of the file: Arms
# B2 and D are card tasks 5 and 6, and an arm that does not exist yet must be visible as a
# deliberate gap rather than as an omission a reader has to infer.
case "$tool" in
  Edit|Write|NotebookEdit) : ;;
  *) exit 0 ;;
esac

# ==========================================================================================
# Arm A — a write into a primary checkout
# ==========================================================================================

# Step A1: no path, nothing to judge (boundary 2). The session's cwd is NOT consulted as a
# fallback, and that omission is the point: the cwd is a primary checkout constantly while
# the write target is not, and phase-guard.sh's Step 4 comment records this exact bug class
# ("Resolved from the WRITE TARGET, never from the session's cwd").
[ -n "$operand" ] || exit 0
file_path=$operand

# Step A2: $HOME. ~/.worktrees is where the answer to "then where should I work?" lives, so
# without it the guard cannot state its own remedy or test a path against the store it
# protects (boundary 13). Held in a function because Arms B2 and D need the identical check
# and will call it from their own entry points.
require_home() {
  [ -n "${HOME:-}" ] && return 0
  REFUSE_MSG='worktree-guard: write blocked — $HOME is unset or empty.

The centralized worktree root is defined as ~/.worktrees, so with no $HOME there is no
path to test a checkout against and no location to name as the place to work instead.

Fix the environment this session was launched with. settings.json is exempt from this
guard, so the hook registration and its WORKTREE_GUARD_MODE switch stay editable.'
  refuse A '' "$file_path"
}
require_home

# Step A3: git, and its version. Both run before any rev-parse, because a missing or too-old
# git makes every later probe fail in a way that is indistinguishable from "not a git
# repository" — and `git rev-parse --path-format=absolute` exits 128 for BOTH of those, so
# the support test cannot be an exit code (card, "Detection", task 2 re-probe).
command -v git >/dev/null 2>&1 || { REFUSE_MSG="$MSG_NO_GIT"; refuse A '' "$file_path"; }

deny_version() { # $1 the raw --version output, quoted back so the failure is diagnosable
  REFUSE_MSG="worktree-guard: write blocked — git is older than $FLOOR, or its version could not be read.

The guard tells a primary checkout from a linked worktree with
\`git rev-parse --path-format=absolute\`, which requires git >= $FLOOR. Without it the
bare forms differ by shape alone in every subdirectory of every primary checkout, and the
guard would read them as linked worktrees and allow — silently off for most writes.

  git --version said: $1

Install git >= $FLOOR. settings.json is exempt from this guard, so the hook registration
and its WORKTREE_GUARD_MODE switch stay editable."
  refuse A '' "$file_path"
}

git_version=$(git --version 2>/dev/null) || deny_version '<git --version failed>'
version=${git_version#git version }
major=${version%%.*}
rest=${version#*.}
minor=${rest%%.*}
case "$major" in ''|*[!0-9]*) deny_version "$git_version" ;; esac
case "$minor" in ''|*[!0-9]*) deny_version "$git_version" ;; esac
if [ "$major" -lt "$FLOOR_MAJOR" ] ||
   { [ "$major" -eq "$FLOOR_MAJOR" ] && [ "$minor" -lt "$FLOOR_MINOR" ]; }; then
  deny_version "$git_version"
fi

# Step A4: the repository that owns the WRITE TARGET. A PreToolUse Write names a file that
# need not exist yet, so walk up to the deepest ancestor that does and resolve from there.
fp_dir=$file_path
while [ ! -d "$fp_dir" ] && [ "$fp_dir" != "/" ] && [ "$fp_dir" != "." ]; do
  fp_dir=$(dirname "$fp_dir")
done
# Physically: `git rev-parse --show-toplevel` always reports the physical path, while a
# payload can legitimately reach the same file through a symlinked ancestor (/tmp and /var
# are symlinks on macOS). Both sides of the prefix match below have to be physical or the
# write reads as outside the repo and the guard is off for that whole repo.
fp_phys=$(cd "$fp_dir" 2>/dev/null && pwd -P) || fp_phys=""
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
    case "$file_path" in
      "$fp_dir")   tail_part="" ;;
      "$fp_dir"/*) tail_part=${file_path#"$fp_dir"} ;;
      /*)          tail_part=$file_path ;;
      *)           tail_part=/$file_path ;;
    esac
    phys_path="${fp_phys%/}$tail_part"
    case "$phys_path" in
      "$top"/*) rel=${phys_path#"$top"/} ;;
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
