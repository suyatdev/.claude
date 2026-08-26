# shellcheck shell=bash
# worktree_guard_bash_arms.sh — Arms B2 and D of worktree-guard.sh (layer 1).
#
# Sourced, not executed: the sourcing hook must already have parsed the payload and run
# every shared precondition, so that $ARM, $SUBJECT, $operand, $py, $CLASSIFIER, $LIB_DIR,
# $SENTINEL, $STORE_REL, $MARKER_NAME, $EXEMPT_VAR, $MODE, $SID, $TAB, $LF, $payload_cwd
# and the shared functions append_log(), refuse(), physical_path() are all in place.
# worktree-guard.sh sources this file at its Bash dispatch point and nowhere else.
#
# It is a file of its own because task 6 grew worktree-guard.sh past the 800-line cap in
# rules/core-conduct.md, and because Arm A shares nothing with these two arms but those
# preconditions. Splitting it does not weaken the one-rule contract below: the suite's
# GROUP S substitutes resolve_effective_repo() in THIS file and still requires both arms
# to move, and its premise check counts the definition across both files so that a second
# copy re-appearing in either one fails.
#
# Every path through this file exits the hook. It never returns to its caller.

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
