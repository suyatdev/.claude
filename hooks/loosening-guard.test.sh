#!/usr/bin/env bash
# loosening-guard.test.sh -- the failing suite for hooks/loosening-guard.sh (task 4 on
# docs/features/guard-loosening-approval.md). The hook DOES NOT EXIST YET: this suite is red until
# task 5 writes it, and it is red for ONE reason -- rc=127, the hook file is missing -- which the
# harness checks below prove is not a broken harness.
#
# Run:   bash hooks/loosening-guard.test.sh               real hook only (fast)
#        bash hooks/loosening-guard.test.sh --matrix      real + 2 stubs + 1 no-op + 1 reference
#                                                         double + 34 degraded controls, in parallel
#        bash hooks/loosening-guard.test.sh --impl NAME   one implementation, full detail
#
# THE CONTRACT THIS SUITE PINS. The spec fixes behaviour, not the wire format; where it was silent
# the choice below is MINE and task 5 may change it in ONE place (run_hook / ex_* / approve_flow).
#   A1 input   PreToolUse JSON on stdin: hook_event_name, tool_name, tool_input.command, session_id,
#              cwd, and -- when present -- permission_mode and, for a subagent, agent_id + agent_type
#              (the measured keys). Process cwd = the repo being committed in.
#   A2 outcome silent allow = rc 0 + EMPTY stdout (never a `permissionDecision: allow`, which would
#              skip Claude's own permission check); ask = rc 0 + hookSpecificOutput.permissionDecision
#              "ask" + a reason; refuse = rc 2 + stderr. Fail-closed is rc 2, NEVER ask: under a
#              bypass session an ask is silently allowed and the command runs (card, task 0).
#   A3 unattended (ADR 0054 decision 2) = a subagent payload (agent_id present: the MEASURED signal)
#              OR permission_mode present and other than "default". A needed prompt in an unattended
#              case becomes a refuse (rc 2) naming "unattended"; no ask is ever emitted there.
#              permission_mode ABSENT with no subagent keys is the FALLBACK path and it REFUSES too
#              (rc 2, stderr names permission_mode and does NOT claim "unattended" -- the hook cannot
#              know that): an ask under a bypass session was measured to be silently allowed with the
#              command running, so an ask on a path that is meant to refuse is a fail-open. Only a
#              NEEDED prompt refuses: absent mode + an unrelated or tightening commit stays silent.
#              PROVENANCE (measured live in this repo, 2026-10-29, key-only probe on PreToolUse/Bash,
#              since removed): the main-session payload keys are cwd, effort, hook_event_name,
#              permission_mode, prompt_id, scratchpad_dir, session_id, tool_input, tool_name,
#              tool_use_id, transcript_path; a subagent adds agent_id and agent_type
#              ('general-purpose'). permission_mode was 'bypassPermissions' in both (in-process
#              subagents inherit the parent mode). The field IS present, so the fallback is a
#              defensive branch kept strict -- do not re-hedge it back to an ask.
#   A4 liveness  every invocation appends `decision=<skip|allow|ask|refuse> class=<c>` to the file
#              named by $LOOSENING_GUARD_LOG. ONLY skip/allow lines are asserted: "allowed" is
#              otherwise indistinguishable from "never inspected". class for the pinned allows:
#              unrelated (decision=skip), unchanged, tightening. Other classes are not pinned.
#   A5 messages  an ask on a confirmed loosening carries the literal marker [LOOSENING]; an ask on
#              CHANGED-DIRECTION-UNKNOWN carries [UNCLASSIFIED] and must NOT carry [LOOSENING]
#              (ADR 0052 decision 2a: it may not claim a loosening it has not established).
#   A6 parse     a parse refusal names the failing side as `staged` and/or `baseline`, and a
#              one-sided failure must not mention the other label.
#   A7 approval  the human approves in the Claude Code UI, which the hook cannot see; the record is
#              written by a PostToolUse invocation of the SAME script for the command that ran.
#              approve_flow() is the only place that encodes this. Lifetime (ADR 0054 decision 1): the
#              record is scoped to the permission-list STATE and lives until that state changes -- it
#              is NOT spent by a commit, so any number of commits of the same state stay silent.
#   A8 store     $SECRET_GUARD_STATE_DIR, session_id-scoped, as hooks/lib/secret_approval.py.
#   A9 baseline  the literal ref origin/main (not HEAD, not merge-base).
#   A10 libs     the hook finds its libraries relative to its own path (so a lone copy refuses).
# Directions asserted (loosening / tightening) are MY reading of ADR 0052's tag tables, which
# decision 4 says no human has reviewed: entry ADDED to an allow list or REMOVED from a block list =
# loosening; the reverse = tightening.
#
# TEST DOUBLES. The stubs and degraded controls below are consulted ONLY by this suite; they are
# never installed. The reference double is fed the *classification* by the harness (the extractors
# are task 5's job), so it proves the assertions are mutually consistent -- NOT that a real hook
# can satisfy them.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)" || exit 3
MARKER_SELF="$HERE/$(basename "$0")"
REAL_HOOK="$HERE/loosening-guard.sh"
RUNMODE="${1:-run}"
JQ=/usr/bin/jq
[ -x "$JQ" ] || { echo "harness: $JQ not found" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "harness: python3 not found" >&2; exit 3; }

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
TPL="$TMP/tpl"; IMPL="$TMP/impl"; RES="$TMP/res"; NOPY="$TMP/nopy"
mkdir -p "$TMP/home" "$IMPL" "$RES" "$NOPY"
MUTPY="$TMP/muts.py"; MODELPY="$TMP/model.py"; REPORTPY="$TMP/report.py"
US=$'\037'
SC=hooks/lib/classify-secret-command.py

# ADR 0052 decision 1: the fourteen-file watch set.
WATCH='hooks/lib/classify-secret-command.py
hooks/secret-command-guard.sh
hooks/lib/secret_approval.py
hooks/git-guard.sh
hooks/lib/git_quiet_class.py
hooks/lib/git_guard_quiet.py
hooks/lib/classify-git-command.py
hooks/worktree-guard.sh
hooks/lib/worktree_guard_bash_arms.sh
hooks/lib/worktree_guard_liveness.sh
hooks/reference-transaction
hooks/reference-transaction.mode
hooks/lib/shell_segments.py
settings.json'

# The mutation table (writes $MUTPY) and the reference double with its degraded controls (writes
# $MODELPY) live in loosening-guard.test.d/ so this runner stays under the 800-line maximum
# (rules/core-conduct.md). Parts are sourced through the repo's shared loader, which fails loudly --
# FAIL line, exit 2 -- on a missing, unreadable or syntax-broken part or a count mismatch.
source "$HERE/handoff/lib/test-parts.sh" || exit 2
command -v source_test_parts >/dev/null 2>&1 || {
  printf 'FAIL — source_test_parts not defined after sourcing handoff/lib/test-parts.sh\n'
  exit 2
}
source_test_parts "$HERE/loosening-guard.test.d" 2


# ---------------------------------------------------------------------------------------------
# Implementations the same assertions run against.
# ---------------------------------------------------------------------------------------------
mk_impl() { # $1 name, $2 kind (model|allow|deny|nop), $3 degrade
  local d="$IMPL/$1"; mkdir -p "$d/lib"; : > "$d/lib/MARK"
  case "$2" in
    model)
      { echo '#!/usr/bin/env bash'
        [ "$3" = orphan-open ] || echo '[ -e "$(dirname "$0")/lib/MARK" ] || { echo "loosening-guard (double): lib/ not found beside the hook" >&2; exit 2; }'
        if [ "$3" = python-open ]; then echo 'command -v python3 >/dev/null 2>&1 || exit 0'
        else echo 'command -v python3 >/dev/null 2>&1 || { echo "loosening-guard (double): python3 is not on PATH" >&2; exit 2; }'; fi
        echo "LG_DEGRADE='$3' exec python3 -I \"$MODELPY\""; } > "$d/loosening-guard.sh" ;;
    allow) cat > "$d/loosening-guard.sh" <<'EOF'
#!/usr/bin/env bash
c="${LG_ORACLE_CLASS:-unrelated}"; d=allow; [ "$c" = unrelated ] && d=skip
[ -z "${LOOSENING_GUARD_LOG:-}" ] || printf 'decision=%s class=%s\n' "$d" "$c" >> "$LOOSENING_GUARD_LOG"
exit 0
EOF
    ;;
    deny) printf '#!/usr/bin/env bash\necho "always-deny stub" >&2\nexit 2\n' > "$d/loosening-guard.sh" ;;
    nop)  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/loosening-guard.sh" ;;
  esac
}
# name:kind:degrade   -- order is the matrix column order
IMPLS='real
stub-allow:allow:
stub-deny:deny:
nop:nop:
ref:model:
gfile:model:guard-filename-only
nomode:model:content-only
two-outcome:model:two-outcome
wholefile:model:whole-file
onemsg:model:single-message
headbase:model:head-baseline
askdeny:model:ask-not-deny
parseopen:model:parse-open
mexit1:model:merge-exit1-only
namekey:model:name-only
pyopen:model:python-open
orphanopen:model:orphan-open
norecord:model:no-record
sessblind:model:sess-blind
storeopen:model:store-open
mergeskip:model:merge-skip-all
basefirst:model:base-first
baseopen:model:base-open
loosedetect:model:loose-detect
asktight:model:ask-tighten
terse:model:terse-reason
unattblanket:model:unattended-blanket
storefirst:model:store-first
firstguard:model:first-guard-only
dirty:model:dirty-tree
jsonopen:model:json-open
mergeask:model:merge-never-skip
chatty:model:chatty
squashskip:model:squash-skip
consumeuse:model:consume-on-use
askfallback:model:ask-fallback
absentblanket:model:absent-blanket
fallbackclaims:model:fallback-claims-unattended
agentblind:model:agent-blind'
CONTROLS="gfile nomode two-outcome wholefile onemsg headbase askdeny parseopen mexit1 namekey pyopen orphanopen norecord sessblind storeopen mergeskip basefirst baseopen loosedetect asktight terse unattblanket storefirst firstguard dirty jsonopen mergeask chatty squashskip consumeuse askfallback absentblanket fallbackclaims agentblind"
impl_path() { if [ "$1" = real ]; then printf '%s' "$REAL_HOOK"; else printf '%s' "$IMPL/$1/loosening-guard.sh"; fi; }
make_impls() {
  local n k d
  while IFS=: read -r n k d; do
    [ "$n" = real ] && continue
    mk_impl "$n" "$k" "$d"
  done <<EOF
$IMPLS
EOF
}

# PATH with every tool except python (E7): linked from the system dirs, python* skipped.
make_nopy() {
  local dir f gitdir; gitdir="$(dirname "$(command -v git)")"
  for dir in /usr/bin /bin /usr/sbin /sbin "$gitdir"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*; do
      case "${f##*/}" in python*|pip*|pydoc*|idle*) continue ;; esac
      [ -x "$f" ] && [ -f "$f" ] && [ ! -e "$NOPY/${f##*/}" ] && ln -s "$f" "$NOPY/${f##*/}"
    done
  done
}

# ---------------------------------------------------------------------------------------------
# Fixture. S1 = the HEAD blobs AND git modes of the fourteen watched files, read with `git show` /
# `git ls-tree` from this checkout -- never a string this suite made up. origin/main exists.
# ---------------------------------------------------------------------------------------------
build_template() {
  local w="$TPL/work" p mode
  mkdir -p "$w" "$TPL/origin.git"
  git -C "$w" init -q -b main || return 1
  git -C "$w" config user.email t@example.com; git -C "$w" config user.name test
  git -C "$w" config core.fileMode true; git -C "$w" config commit.gpgsign false
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    mkdir -p "$w/$(dirname "$p")"
    git -C "$ROOT" show "HEAD:$p" > "$w/$p" || { echo "harness: $p is not in HEAD" >&2; return 1; }
    mode="$(git -C "$ROOT" ls-tree HEAD -- "$p" | awk '{print $1}')"
    [ "$mode" = 100755 ] && chmod +x "$w/$p"
  done <<EOF
$WATCH
EOF
  mkdir -p "$w/docs"; printf 'seed\n' > "$w/docs/note.md"
  git -C "$w" add -A && git -C "$w" commit -q -m seed || return 1
  git init -q --bare "$TPL/origin.git" && git -C "$w" remote add origin "$TPL/origin.git" || return 1
  git -C "$w" push -q origin main 2>/dev/null || return 1
  git -C "$w" checkout -q -b feat
}

CASE=""; REPO=""; CUR_ID=x; RC=0; OUT=""; ERR=""; LOGTXT=""; REASON=""
ORACLE=unrelated; ORACLE_HEAD=""; BAD_SIDE=""; PERM=default; EVENT=PreToolUse
SID=s; HOOK_OVERRIDE=""; HOOK_PATH=""; RAW_PAYLOAD=""; CMD=""; HOOK=""; AGENT_ID=""; AGENT_TYPE=""
T_OK=1; T_WHY=""; T_MISSING=0; T_HARNESS=0
g() { git -C "$REPO" "$@"; }
new_case() {
  CASE="$(mktemp -d "$TMP/case.XXXXXX")" || { echo "harness: mktemp failed" >&2; exit 3; }
  cp -Rp "$TPL/work" "$CASE/repo"; REPO="$CASE/repo"
  mkdir -p "$CASE/state"; : > "$CASE/log"
  ORACLE=unrelated; ORACLE_HEAD=""; BAD_SIDE=""; PERM=default; EVENT=PreToolUse
  SID="sess-$$-$RANDOM"; HOOK_OVERRIDE=""; HOOK_PATH=""; RAW_PAYLOAD=""; AGENT_ID=""; AGENT_TYPE=""
  CMD="git commit -m lg-$CUR_ID"; RC=0; OUT=""; ERR=""; LOGTXT=""
}
fail_t() { T_OK=0; T_WHY="$T_WHY [$*]"; }
harness_fail() { T_OK=0; T_HARNESS=1; T_WHY="$T_WHY [HARNESS: $*]"; }
sm() { local p; p="$(python3 -I "$MUTPY" apply "$1" "$REPO")" || { harness_fail "mutation $1 missed its target"; return 1; }; g add -- "$p"; }
wm() { python3 -I "$MUTPY" apply "$1" "$REPO" >/dev/null || harness_fail "mutation $1 missed its target"; }
restore_real() { git -C "$ROOT" show "HEAD:$1" > "$REPO/$1"; }
rebaseline() { # mutations (or rm:<path>) go onto main; origin/main moves there; feat is re-cut from it
  local a; g checkout -q main || { harness_fail "checkout main"; return 1; }
  for a in "$@"; do case "$a" in rm:*) g rm -q -- "${a#rm:}" ;; *) wm "$a" ;; esac; done
  g add -A; g commit -q -m "baseline moves"; g update-ref refs/remotes/origin/main main; g checkout -q -B feat
}
build_merge() { # $1 ancestor | side | bogus | squash | nomain  -- leaves a merge in progress (squash: none)
  case "$1" in
    ancestor)
      sm git_add_ledger; g commit -q -m "branch: loosening"
      g checkout -q main; wm git_exit; g add -A; g commit -q -m "main moved"
      g update-ref refs/remotes/origin/main main; g checkout -q feat
      g merge --no-ff --no-commit -q origin/main >/dev/null 2>&1 ;;
    *)
      g checkout -q -b side; sm wt_add_exempt; g commit -q -m "side: loosening"; g checkout -q feat
      printf 'x\n' >> "$REPO/docs/note.md"; g add -- docs/note.md; g commit -q -m "feat: docs"
      if [ "$1" = squash ]; then g merge --squash -q side >/dev/null 2>&1
      else g merge --no-ff --no-commit -q side >/dev/null 2>&1; fi
      [ "$1" = bogus ] && printf '%s\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa > "$REPO/.git/MERGE_HEAD" ;;
  esac
  if [ -n "$(g diff --name-only --diff-filter=U)" ]; then harness_fail "merge fixture conflicted"; fi
  if [ "$1" = squash ]; then [ ! -e "$REPO/.git/MERGE_HEAD" ] || harness_fail "squash left a MERGE_HEAD"
  else [ -e "$REPO/.git/MERGE_HEAD" ] || harness_fail "merge left no MERGE_HEAD"; fi
}

run_hook() { # $1 command; sets RC OUT ERR LOGTXT. rc is captured on the very next line.
  local cmd="$1" payload hook="${HOOK_OVERRIDE:-$HOOK}"
  : > "$CASE/log"
  if [ -n "$RAW_PAYLOAD" ]; then payload="$RAW_PAYLOAD"; else
    payload="$("$JQ" -nc --arg c "$cmd" --arg s "$SID" --arg pm "$PERM" --arg cwd "$REPO" --arg ev "$EVENT" \
      --arg aid "$AGENT_ID" --arg aty "$AGENT_TYPE" \
      '{hook_event_name:$ev,tool_name:"Bash",tool_input:{command:$c},session_id:$s,cwd:$cwd}
       | if $pm == "" then . else . + {permission_mode:$pm} end
       | if $aid == "" then . else . + {agent_id:$aid} end
       | if $aty == "" then . else . + {agent_type:$aty} end
       | if $ev == "PostToolUse" then . + {tool_response:{interrupted:false}} else . end')"
  fi
  ( cd "$REPO" && printf '%s' "$payload" | env SECRET_GUARD_STATE_DIR="$CASE/state" \
      LOOSENING_GUARD_LOG="$CASE/log" LG_ORACLE_CLASS="$ORACLE" LG_ORACLE_CLASS_HEAD="$ORACLE_HEAD" \
      LG_ORACLE_BAD_SIDE="$BAD_SIDE" HOME="$TMP/home" PATH="${HOOK_PATH:-$PATH}" \
      /bin/bash "$hook" >"$CASE/out" 2>"$CASE/err" )
  RC=$?
  OUT="$(cat "$CASE/out")"; ERR="$(cat "$CASE/err")"; LOGTXT="$(cat "$CASE/log")"
  if [ "$RC" -eq 127 ] && [ ! -e "$hook" ]; then T_MISSING=1; fi
}
approve_flow() { # S staged -> hook asks -> the "user" approves -> commit runs -> PostToolUse -> S staged again
  run_hook "$CMD"; ex_ask any
  g commit -q -m "lg approved" || harness_fail "fixture commit failed"
  EVENT=PostToolUse; run_hook "$CMD"; EVENT=PreToolUse
  [ "$RC" -eq 0 ] || fail_t "PostToolUse rc=$RC want 0"
  g reset -q --soft HEAD~1
}

# ---- expectations ---------------------------------------------------------------------------
has() { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
decision() { printf '%s' "$OUT" | "$JQ" -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }
ex_ask() { # $1 any | loosening | unclassified
  local d r; d="$(decision)"; r="$(printf '%s' "$OUT" | "$JQ" -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"; REASON="$r"
  [ "$RC" -eq 0 ] || fail_t "rc=$RC want 0 for an ask"
  [ "$d" = ask ] || fail_t "permissionDecision='$d' want ask"
  [ -n "$r" ] || fail_t "empty reason"
  case "$1" in
    loosening) has "$r" '[LOOSENING]' || fail_t "reason lacks [LOOSENING]" ;;
    unclassified) has "$r" '[UNCLASSIFIED]' || fail_t "reason lacks [UNCLASSIFIED]"
                  has "$r" '[LOOSENING]' && fail_t "unclassified reason carries [LOOSENING]" ;;
  esac
}
ex_reason_has() { has "$REASON" "$1" || fail_t "reason lacks '$1'"; }
ex_refuse() { # words stderr must carry
  local w; [ "$RC" -eq 2 ] || fail_t "rc=$RC want 2"
  [ -n "$ERR" ] || fail_t "no reason on stderr"
  has "$OUT" permissionDecision && fail_t "refusal also printed a permissionDecision"
  for w in "$@"; do has "$ERR" "$w" || fail_t "stderr lacks '$w'"; done
}
ex_err_lacks() { has "$ERR" "$1" && fail_t "stderr must not mention '$1'"; return 0; }
ex_silent() { # $1 class $2 decision -- nothing printed AND a positive signal that the hook ran
  [ "$RC" -eq 0 ] || fail_t "rc=$RC want 0"
  [ -z "$OUT" ] || fail_t "stdout not empty"
  [ -z "$ERR" ] || fail_t "stderr not empty"
  has "$LOGTXT" "decision=$2 class=$1" || fail_t "no liveness signal 'decision=$2 class=$1' (log: '$LOGTXT')"
}
ex_allow() { # rc 0, nothing on stdout, a logged allow
  [ "$RC" -eq 0 ] || fail_t "rc=$RC want 0"
  [ -z "$OUT" ] || fail_t "stdout not empty"
  has "$LOGTXT" "decision=allow" || fail_t "no liveness signal 'decision=allow' (log: '$LOGTXT')"
}
ex_not_silent() {
  if [ "$RC" -eq 2 ]; then return 0; fi
  if [ "$RC" -eq 0 ] && [ "$(decision)" = ask ]; then return 0; fi
  fail_t "neither refused (rc 2) nor asked: rc=$RC out='${OUT:0:60}'"
}

# ---- test bodies ----------------------------------------------------------------------------
t_loosen() { local mid gname tok; IFS=, read -r mid gname tok <<EOF
$1
EOF
  new_case; ORACLE=loosening; sm "$mid"; run_hook "$CMD"
  ex_ask loosening; ex_reason_has "$gname"; ex_reason_has "$tok"; ex_reason_has "lg-$CUR_ID"; }
t_tighten() { new_case; ORACLE=tightening; sm "$1"; run_hook "$CMD"; ex_silent tightening allow; }
t_unrelated() { new_case; printf 'x\n' >> "$REPO/docs/note.md"; g add -- docs/note.md; run_hook "$CMD"; ex_silent unrelated skip; }
t_notcommit() { new_case; sm sec_rm_zprofile; run_hook "$1"; ex_silent unrelated skip; }
t_chained() { new_case; ORACLE=loosening; sm sec_rm_zprofile
  run_hook "git add -- $SC && git commit -m lg-$CUR_ID"; ex_ask loosening; }
t_commit_a() { new_case; ORACLE=loosening; wm sec_rm_zprofile; run_hook "git commit -am lg-$CUR_ID"; ex_ask loosening; }
t_recommit() { # ADR 0054 decision 1: three more commits of the approved state stay silent AND the record survives
  local before after lost n cmd
  new_case; ORACLE=loosening; sm wt_add_exempt; approve_flow
  before="$(ls -1 "$CASE/state" | /usr/bin/grep '^secret-approval-' | sort)"
  [ -n "$before" ] || fail_t "approve_flow left no approval record in the store, so survival cannot be checked"
  for n in 1 2 3; do
    cmd="git commit -m lg-$CUR_ID-again-$n"
    run_hook "$cmd"; ex_allow
    g commit -q -m "lg recommit $n" || harness_fail "fixture commit $n failed"
    EVENT=PostToolUse; run_hook "$cmd"; EVENT=PreToolUse
    [ "$RC" -eq 0 ] || fail_t "PostToolUse rc=$RC want 0 after silent commit $n"
    g reset -q --soft HEAD~1 || harness_fail "fixture reset $n failed"
  done
  after="$(ls -1 "$CASE/state" | /usr/bin/grep '^secret-approval-' | sort)"
  lost="$(comm -23 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
  [ -z "$lost" ] || fail_t "approval record spent by use (gone after 3 commits): $lost"
  [ -n "$after" ] || fail_t "no approval record left in the store after 3 commits"; }
t_session() { new_case; ORACLE=loosening; sm wt_add_exempt; SID=sess-A; approve_flow; SID=sess-B
  run_hook "$CMD"; ex_ask loosening; }
t_unclass() { new_case; ORACLE=unclassified; sm "$1"; run_hook "$CMD"; ex_ask unclassified; }
t_cosmetic() { new_case; ORACLE=unchanged; sm "$1"; run_hook "$CMD"; ex_silent unchanged allow; }
t_modeonly() { new_case; ORACLE=unclassified; chmod -x "$REPO/hooks/worktree-guard.sh"; g add -- hooks/worktree-guard.sh
  has "$(g diff --cached --summary)" "mode change 100755 => 100644" || harness_fail "fixture is not a mode-only change"
  run_hook "$CMD"; ex_ask any; }
t_unattended() { new_case; PERM=bypassPermissions; ORACLE=loosening; sm "$1"; run_hook "$CMD"; ex_refuse unattended; }
t_unatt_tight() { new_case; PERM=bypassPermissions; ORACLE=tightening; sm git_rm_ledger; run_hook "$CMD"; ex_silent tightening allow; }
t_unatt_unrel() { new_case; PERM=bypassPermissions; printf 'x\n' >> "$REPO/docs/note.md"; g add -- docs/note.md
  run_hook "$CMD"; ex_silent unrelated skip; }
t_unatt_unk() { new_case; PERM=bypassPermissions; ORACLE=unclassified; sm sec_fold; run_hook "$CMD"; ex_refuse unattended; }
t_nomode() { # ADR 0054 decision 2, FALLBACK path: permission_mode absent AND no subagent keys -> a needed prompt REFUSES (rc 2)
  local oracle mid; IFS=, read -r oracle mid <<EOF
$1
EOF
  new_case; PERM=""; ORACLE="$oracle"; sm "$mid"; run_hook "$CMD"; ex_refuse permission_mode; ex_err_lacks unattended; }
t_nomode_silent() { # absent mode but NO prompt needed: the fallback refuses only a needed prompt, never every commit
  new_case; PERM=""
  if [ "$1" = unrelated ]; then printf 'x\n' >> "$REPO/docs/note.md"; g add -- docs/note.md; run_hook "$CMD"; ex_silent unrelated skip
  else ORACLE=tightening; sm git_rm_ledger; run_hook "$CMD"; ex_silent tightening allow; fi; }
t_subagent() { # $1 permission_mode ("" = absent); a subagent payload carries agent_id + agent_type (measured keys)
  new_case; PERM="$1"; AGENT_ID=agent-1; AGENT_TYPE=general-purpose; ORACLE=loosening; sm sec_rm_zprofile
  run_hook "$CMD"; ex_refuse unattended; }
t_bypass_only() { new_case; PERM=bypassPermissions; ORACLE=loosening; sm sec_rm_zshenv; run_hook "$CMD"; ex_refuse unattended; }
t_parse() { new_case; ORACLE=parse-error
  case "$1" in
    staged-py) BAD_SIDE=staged; sm brk_py ;;
    staged-sh) BAD_SIDE=staged; sm brk_sh ;;
    staged-json) BAD_SIDE=staged; sm brk_json ;;
    base) BAD_SIDE=baseline; rebaseline brk_py; restore_real $SC; g add -- $SC ;;
    both) BAD_SIDE=both; rebaseline brk_py; sm brk_py2 ;;
  esac
  run_hook "$CMD"
  case "$BAD_SIDE" in
    staged) ex_refuse staged; ex_err_lacks baseline ;;
    baseline) ex_refuse baseline; ex_err_lacks staged ;;
    both) ex_refuse staged baseline ;;
  esac; }
t_decline() { new_case; ORACLE=loosening; sm sec_rm_zprofile
  local before after; before="$(g rev-parse HEAD)|$(g write-tree)|$(g status --porcelain)"
  run_hook "$CMD"; ex_ask loosening
  after="$(g rev-parse HEAD)|$(g write-tree)|$(g status --porcelain)"
  [ "$before" = "$after" ] || fail_t "the hook changed HEAD, the index or the tree"
  run_hook "$CMD"; ex_ask loosening; }
t_transfer() { new_case; ORACLE=loosening; sm sec_rm_zprofile; approve_flow; sm sec_rm_zshenv
  run_hook "$CMD"; ex_ask loosening; }
t_modekey() { new_case; ORACLE=loosening; sm sec_rm_zprofile; approve_flow
  chmod -x "$REPO/$SC"; g add -- $SC; run_hook "$CMD"; ex_ask loosening; }
t_newfile() { new_case; rebaseline rm:hooks/lib/git_guard_quiet.py; restore_real hooks/lib/git_guard_quiet.py
  g add -- hooks/lib/git_guard_quiet.py; ORACLE=loosening; run_hook "$CMD"; ex_ask any; }
t_deleted() { new_case; ORACLE=unclassified; g rm -q -- hooks/git-guard.sh; run_hook "$CMD"; ex_ask any; }
t_renamed() { new_case; ORACLE=unclassified; g mv hooks/git-guard.sh hooks/git-guard-renamed.sh; run_hook "$CMD"; ex_ask any; }
t_two_ask() { new_case; ORACLE=loosening; sm sec_rm_zprofile; sm wt_add_exempt; run_hook "$CMD"
  ex_ask loosening; ex_reason_has secret-command-guard; ex_reason_has worktree-guard; }
t_two_approved() { new_case; ORACLE=loosening; sm sec_rm_zprofile; sm wt_add_exempt; approve_flow; run_hook "$CMD"; ex_allow; }
t_two_partial() { new_case; ORACLE=loosening; sm sec_rm_zprofile; approve_flow; sm wt_add_exempt
  run_hook "$CMD"; ex_ask loosening; ex_reason_has worktree-guard; }
t_identical() { new_case; ORACLE=unchanged; ORACLE_HEAD=tightening; sm sec_rm_zprofile; g commit -q -m "branch loosening"
  g checkout -q origin/main -- $SC; run_hook "$CMD"; ex_silent unchanged allow; }
t_not_head() { new_case; ORACLE=loosening; ORACLE_HEAD=unchanged; sm sec_rm_zprofile; g commit -q -m "branch loosening"
  sm cosmetic; run_hook "$CMD"; ex_ask loosening; }
t_nobaseline() { new_case
  case "$1" in
    loosen) ORACLE=loosening; sm sec_rm_zprofile ;;
    tighten) ORACLE=tightening; sm sec_add_npmrc ;;
    unrelated) printf 'x\n' >> "$REPO/docs/note.md"; g add -- docs/note.md ;;
  esac
  g update-ref -d refs/remotes/origin/main; run_hook "$CMD"
  if [ "$1" = unrelated ]; then ex_silent unrelated skip; else ex_refuse origin/main; fi; }
t_nopython() { new_case; ORACLE=loosening; HOOK_PATH="$NOPY"; sm sec_rm_zprofile; run_hook "$CMD"; ex_refuse python3; }
t_merge() { new_case; ORACLE=loosening; build_merge "$1"
  case "$1" in
    ancestor) run_hook "$CMD"; ex_allow ;;
    side|squash) run_hook "$CMD"; ex_ask loosening ;;
    bogus) run_hook "$CMD"; ex_ask any ;;
    nomain) g update-ref -d refs/remotes/origin/main; run_hook "$CMD"; ex_not_silent ;;
  esac; }
t_store() { new_case
  if [ "$1" = loosen ]; then ORACLE=loosening; sm wt_add_exempt; approve_flow; else ORACLE=tightening; sm git_rm_ledger; fi
  chmod 000 "$CASE/state"; run_hook "$CMD"; chmod 755 "$CASE/state"
  if [ "$1" = loosen ]; then ex_not_silent; else ex_silent tightening allow; fi; }
t_orphan() { new_case; ORACLE=loosening; sm sec_rm_zprofile; mkdir -p "$CASE/orphan"; cp "$HOOK" "$CASE/orphan/loosening-guard.sh" 2>/dev/null
  HOOK_OVERRIDE="$CASE/orphan/loosening-guard.sh"; run_hook "$CMD"; ex_refuse; }
t_badjson() { new_case; RAW_PAYLOAD='this is not json'; run_hook "$CMD"; ex_refuse; }
t_watch() { new_case; ORACLE=unclassified; sm "$1"; run_hook "$CMD"; ex_not_silent; }

# ---- registry -------------------------------------------------------------------------------
TESTS=""
reg() { TESTS="${TESTS}$1${US}$2${US}$3${US}${4:-}
"; }
reg G1s "6.1 loosening, interactive: asks, names guard + removed entry + commit (secret)" t_loosen "sec_rm_zprofile,secret-command-guard,zprofile"
reg G1g "6.1 loosening, interactive: asks, names guard + added entry + commit (git)" t_loosen "git_add_ledger,git-guard,third-judge"
reg G1w "6.1 loosening, interactive: asks, names guard + added entry + commit (worktree)" t_loosen "wt_add_exempt,worktree-guard,hooks/*"
reg G2s "6.1 tightening is silent (secret: block entry added)" t_tighten sec_add_npmrc
reg G2g "6.1 tightening is silent (git: allow entry removed)" t_tighten git_rm_ledger
reg G2w "6.1 tightening is silent (worktree: exemption removed)" t_tighten wt_rm_exempt
reg G3 "6.1 unrelated commit: no action, no output, liveness logged" t_unrelated
reg G3b "6.1 not a commit (git status) with a loosening staged: skipped" t_notcommit "git status --short"
reg G3c "6.1 'git commit' only inside a quoted string, loosening staged: skipped" t_notcommit 'echo "then git commit it"'
reg G3d "chained 'git add && git commit' is judged (ask)" t_chained
reg G3e "git commit -am with the loosening UNSTAGED is judged (ask) [beyond spec]" t_commit_a
reg G4 "6.1 + ADR0054-1 three more commits of the approved state: all silent, approval record still on disk" t_recommit
reg G5 "approval from session A does not satisfy session B" t_session
reg U1 "2: regex anchor dropped in place -> ask [UNCLASSIFIED]" t_unclass sec_anchor
reg U2 "2: re.IGNORECASE -> 0 -> ask [UNCLASSIFIED]" t_unclass sec_fold
reg U3 "2: sys.exit(1) -> sys.exit(0) -> ask [UNCLASSIFIED]" t_unclass sec_exit
reg U4 "2: deleted precondition call (require_home) -> ask [UNCLASSIFIED]" t_unclass wt_no_home
reg U5 "2: final 'exit 2' -> 'exit 0' in the .sh -> ask [UNCLASSIFIED]" t_unclass secsh_exit
reg C1 "5.2: comment-only edit is silent (unchanged)" t_cosmetic cosmetic
reg C2 "5.2: reordering two list entries is silent (unchanged)" t_cosmetic reorder
reg MF1 "5: 100755 -> 100644, content identical: not silent (ask)" t_modeonly
reg R1w "6.2 unattended + loosening (worktree): refuse rc 2 'unattended'" t_unattended wt_add_exempt
reg R1s "6.2 unattended + loosening (secret): refuse rc 2 'unattended'" t_unattended sec_rm_zprofile
reg R1g "6.2 unattended + loosening (git): refuse rc 2 'unattended'" t_unattended git_add_ledger
reg R1b "unattended + tightening: still silent" t_unatt_tight
reg R1c "unattended + unrelated commit: still silent" t_unatt_unrel
reg R1d "unattended + direction-unknown: refuse rc 2 'unattended'" t_unatt_unk
reg R1e "ADR0054-2 permission_mode ABSENT, no subagent keys, loosening: FALLBACK path -> refuse rc 2 naming permission_mode, not 'unattended' (an ask under bypass is silently allowed = fail-open)" t_nomode "loosening,sec_rm_zprofile"
reg R1f "ADR0054-2 subagent (agent_id) with permission_mode=default, loosening: unattended, refuse rc 2 not ask" t_subagent default
reg R1h "ADR0054-2 permission_mode=bypassPermissions, no subagent keys, loosening: unattended, refuse rc 2 not ask" t_bypass_only
reg R1i "ADR0054-2 subagent AND permission_mode=bypassPermissions, loosening: refuse rc 2" t_subagent bypassPermissions
reg R1j "ADR0054-2 permission_mode ABSENT + subagent (agent_id), loosening: the fallback leg fires, refuse rc 2" t_subagent ""
reg R1k "ADR0054-2 permission_mode ABSENT, no subagent keys, direction-unknown: FALLBACK path -> refuse rc 2 naming permission_mode, not 'unattended' (an ask under bypass is silently allowed = fail-open)" t_nomode "unclassified,sec_fold"
reg R1l "ADR0054-2 permission_mode ABSENT, no subagent keys, unrelated commit: no prompt needed, silent skip (the fallback refuses a needed prompt only)" t_nomode_silent unrelated
reg R1m "ADR0054-2 permission_mode ABSENT, no subagent keys, tightening: no prompt needed, silent allow" t_nomode_silent tightening
reg R2a "6.2 staged .py unparseable: refuse rc 2 naming 'staged' only" t_parse staged-py
reg R2b "6.2 staged .sh unparseable: refuse rc 2 naming 'staged' only" t_parse staged-sh
reg R2c "6.2 staged settings.json unparseable: refuse rc 2 naming 'staged' only" t_parse staged-json
reg R2d "6.2 origin/main copy unparseable: refuse rc 2 naming 'baseline' only" t_parse base
reg R2e "6.2 both sides unparseable: refuse rc 2 naming both" t_parse both
reg R3 "6.2 decline: re-run asks again, HEAD/index/tree untouched" t_decline
reg R4 "6.2 approval at S1 does not satisfy S2 of the same guard" t_transfer
reg R4b "approval is keyed to the git MODE too (mode flip re-prompts)" t_modekey
reg E1 "6.3 origin/main has no copy of the file: ask" t_newfile
reg E2 "6.3 guard file deleted by the commit: ask" t_deleted
reg E3 "6.3 guard file renamed: ask" t_renamed
reg E4a "6.3 two guards staged: one ask naming both" t_two_ask
reg E4b "6.3 two guards staged, both approved: silent" t_two_approved
reg E4c "6.3 two guards staged, only one approved: still asks for the other" t_two_partial
reg E5 "6.3 staged blob byte-identical to origin/main (HEAD differs): silent unchanged" t_identical
reg E5b "baseline is origin/main, NOT HEAD (HEAD carries the loosening)" t_not_head
reg E6a "6.3 origin/main unobtainable + loosening: refuse naming origin/main" t_nobaseline loosen
reg E6b "6.3 origin/main unobtainable + tightening: refuse naming origin/main" t_nobaseline tighten
reg E6c "origin/main unobtainable + unrelated commit: silent (offline stays usable)" t_nobaseline unrelated
reg E7 "6.3 python3 missing + loosening: refuse naming python3" t_nopython
reg E8a "ADR0053 merge of content already on origin/main: silent allow" t_merge ancestor
reg E8b "ADR0053 merge of a side branch not on main: ask" t_merge side
reg E8c "ADR0053 is-ancestor exits 128 (bad MERGE_HEAD), main present: ask, not allow" t_merge bogus
reg E8d "ADR0053 merge with origin/main missing: not silent" t_merge nomain
reg E8e "ADR0053 squash merge has no MERGE_HEAD: ordinary path, ask" t_merge squash
reg E9a "7 approval store unreadable + prior approval: bypass refused, not silent" t_store loosen
reg E9b "7 approval store unreadable + tightening: judged on its merits, silent" t_store tighten
reg E10 "7 hook copied alone (libs missing): refuse rc 2, never fail open" t_orphan
reg X1 "7 payload is not JSON: refuse rc 2 [extrapolated from 'any internal error']" t_badjson
reg W01 "1 watch set: classify-secret-command.py changed -> not silent" t_watch sec_exit
reg W02 "1 watch set: secret-command-guard.sh changed -> not silent" t_watch secsh_exit
reg W03 "1 watch set: secret_approval.py changed -> not silent" t_watch sec_hatch
reg W04 "1 watch set: git-guard.sh changed -> not silent" t_watch git_exit
reg W05 "1 watch set: git_quiet_class.py changed -> not silent" t_watch gq_add_stash
reg W06 "1 watch set: git_guard_quiet.py changed -> not silent" t_watch gq_protected
reg W07 "1 watch set: classify-git-command.py changed -> not silent" t_watch cgc_force
reg W08 "1 watch set: worktree-guard.sh changed -> not silent" t_watch wt_add_exempt
reg W09 "1 watch set: worktree_guard_bash_arms.sh changed -> not silent" t_watch wta_refuse
reg W10 "1 watch set: worktree_guard_liveness.sh changed -> not silent" t_watch wtl_liveness
reg W11 "1 watch set: reference-transaction changed -> not silent" t_watch rt_exit
reg W12 "1 watch set: reference-transaction.mode changed -> not silent" t_watch rtm_off
reg W13 "1 watch set: shell_segments.py changed -> not silent" t_watch seg_paren
reg W14 "1 watch set: settings.json changed (registration retargeted) -> not silent" t_watch set_retarget

run_suite() { # $1 label, $2 hook path, $3 verbose
  local label="$1" id desc fn arg pass=0 fail=0 miss=0 harn=0 v c
  HOOK="$2"; : > "$RES/$label.tsv"
  while IFS="$US" read -r id desc fn arg <&3; do
    [ -n "$id" ] || continue
    CUR_ID="$id"; T_OK=1; T_WHY=""; T_MISSING=0; T_HARNESS=0
    "$fn" "$arg"
    if [ "$T_OK" -eq 1 ]; then v=P; c=ok; pass=$((pass+1))
    else v=F; fail=$((fail+1))
      if [ "$T_HARNESS" -eq 1 ]; then c=harness; harn=$((harn+1))
      elif [ "$T_MISSING" -eq 1 ]; then c=hook-missing; miss=$((miss+1)); else c=contract; fi
    fi
    printf '%s\t%s\t%s\n' "$id" "$v" "$c" >> "$RES/$label.tsv"
    [ "$label" = real ] && printf '%s\t%s\n' "$id" "$desc" >> "$RES/desc.tsv"
    if [ "$3" = 1 ]; then
      if [ "$v" = P ]; then printf 'ok   — %-4s %s\n' "$id" "$desc"
      else printf 'FAIL — %-4s %s  <%s>%s\n' "$id" "$desc" "$c" "$( [ "$c" = hook-missing ] || printf '%s' "$T_WHY")"; fi
    fi
  done 3<<EOF
$TESTS
EOF
  printf '%s\t%s\t%s\t%s\t%s\n' "$pass" "$fail" "$miss" "$harn" "$((pass+fail))" > "$RES/$label.sum"
}

# ---- harness checks: facts about the FIXTURE, independent of any hook -----------------------
H_FAILS=0
hres() { if [ "$2" -eq 0 ]; then printf 'ok   — [harness] %s\n' "$1"; else printf 'FAIL — [harness] %s\n' "$1"; H_FAILS=$((H_FAILS+1)); fi; }
run_harness_checks() {
  local paths want got n rc id bad
  paths="$(printf '%s' "$WATCH" | tr '\n' ' ')"
  want="$(git -C "$ROOT" ls-tree HEAD -- $paths)"; got="$(git -C "$TPL/work" ls-tree HEAD -- $paths)"
  n="$(printf '%s\n' "$got" | wc -l | tr -d ' ')"
  [ "$want" = "$got" ] && [ "$n" -eq 14 ]; hres "S1 = this checkout's HEAD blobs AND modes for all 14 watched files ($n rows, ls-tree identical)" $?
  CUR_ID=H; T_WHY=""; T_HARNESS=0; new_case
  bad=""; for id in $(python3 -I "$MUTPY" list); do
    python3 -I "$MUTPY" apply "$id" "$REPO" >/dev/null 2>"$CASE/err" || bad="$bad $id"
    [ "$(g status --porcelain | wc -l | tr -d ' ')" -eq 1 ] || bad="$bad $id(!=1 path)"
    g checkout -q -- .
  done
  [ -z "$bad" ]; hres "every mutation hits its target exactly once on real bytes${bad:+ -- MISSED:$bad}" $?
  g rev-parse --verify -q origin/main >/dev/null && [ "$(g rev-parse origin/main)" = "$(g rev-parse HEAD)" ] && [ -z "$(g diff --cached --name-only)" ]
  hres "fixture: origin/main resolves, feat starts at it, nothing staged" $?
  T_HARNESS=0; T_WHY=""; new_case; build_merge ancestor
  g merge-base --is-ancestor "$(cat "$REPO/.git/MERGE_HEAD")" origin/main; rc=$?
  [ "$rc" -eq 0 ] && [ "$T_HARNESS" -eq 0 ]; hres "merge fixture 'ancestor': is-ancestor exits 0 (ADR 0053 case A) [rc=$rc $T_WHY]" $?
  T_HARNESS=0; T_WHY=""; new_case; build_merge side
  g merge-base --is-ancestor "$(cat "$REPO/.git/MERGE_HEAD")" origin/main; rc=$?
  [ "$rc" -eq 1 ] && [ "$T_HARNESS" -eq 0 ]; hres "merge fixture 'side': is-ancestor exits 1 (ADR 0053 case B) [rc=$rc $T_WHY]" $?
  T_HARNESS=0; T_WHY=""; new_case; build_merge bogus
  g merge-base --is-ancestor "$(cat "$REPO/.git/MERGE_HEAD")" origin/main >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 128 ] && [ "$T_HARNESS" -eq 0 ]; hres "merge fixture 'bogus': is-ancestor exits 128 with origin/main present [rc=$rc $T_WHY]" $?
  T_HARNESS=0; T_WHY=""; new_case; build_merge squash
  [ "$T_HARNESS" -eq 0 ] && ! g diff --cached --quiet; hres "merge fixture 'squash': no MERGE_HEAD, changes staged [$T_WHY]" $?
  ( PATH="$NOPY"; hash -r; ! command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1 && command -v bash >/dev/null 2>&1 )
  hres "no-python PATH hides python3 but keeps git and bash" $?
  "$JQ" -nc --arg ev PreToolUse '{hook_event_name:$ev}' | "$JQ" -e '.hook_event_name == "PreToolUse"' >/dev/null
  hres "synthetic payloads carry hook_event_name (a payload without it is 'never inspected')" $?
  # The R1e/R1f/R1h/R1i/R1j/R1k/R1l/R1m cells are only distinct if the payloads really differ: dump what run_hook sends.
  T_HARNESS=0; T_WHY=""; new_case; printf '#!/usr/bin/env bash\ncat > "$SECRET_GUARD_STATE_DIR/payload.json"\n' > "$CASE/dump.sh"; HOOK_OVERRIDE="$CASE/dump.sh"
  PERM=""; run_hook "$CMD"
  "$JQ" -e 'has("permission_mode") == false and has("agent_id") == false and has("agent_type") == false' "$CASE/state/payload.json" >/dev/null
  hres "payload with PERM='' and no agent carries NEITHER permission_mode NOR agent_id/agent_type" $?
  PERM=default; AGENT_ID=agent-1; AGENT_TYPE=general-purpose; run_hook "$CMD"
  "$JQ" -e '.permission_mode == "default" and .agent_id == "agent-1" and .agent_type == "general-purpose"' "$CASE/state/payload.json" >/dev/null
  hres "subagent payload carries permission_mode=default, agent_id and agent_type" $?
  PERM=bypassPermissions; AGENT_ID=""; AGENT_TYPE=""; run_hook "$CMD"
  "$JQ" -e '.permission_mode == "bypassPermissions" and has("agent_id") == false' "$CASE/state/payload.json" >/dev/null
  hres "bypass payload carries permission_mode=bypassPermissions and NO agent_id" $?
}

if [ "$RUNMODE" = "--impl" ]; then
  build_template || exit 3; make_impls; make_nopy
  run_suite "$2" "$(impl_path "$2")" 1
  awk -F'\t' '{printf "\n%s passed, %s failed (hook-missing %s, harness %s) of %s\n",$1,$2,$3,$4,$5}' "$RES/$2.sum"
  exit 0
fi

build_template || { echo "harness: fixture could not be built" >&2; exit 3; }
make_impls; make_nopy
run_harness_checks
if [ "$H_FAILS" -ne 0 ]; then printf '\nHARNESS BROKEN (%s checks failed): the results below, if any, mean nothing.\n' "$H_FAILS"; exit 3; fi
printf '\n'

if [ "$RUNMODE" = "--matrix" ]; then
  names=""
  while IFS=: read -r n k d; do
    names="$names $n"
    ( run_suite "$n" "$(impl_path "$n")" 0 ) </dev/null &
  done <<EOF
$IMPLS
EOF
  wait
  cat > "$REPORTPY" <<'PYEOF'
import sys, os
from collections import Counter
res, names, controls = sys.argv[1], sys.argv[2].split(), sys.argv[3].split()
order, data, cls = [], {}, {}
for n in names:
    for line in open(os.path.join(res, n + ".tsv")):
        i, v, c = line.rstrip("\n").split("\t")
        if n == names[0]: order.append(i)
        data.setdefault(i, {})[n] = v
        if n == "real": cls[i] = c
desc = dict(l.rstrip("\n").split("\t", 1) for l in open(os.path.join(res, "desc.tsv")))
print("columns: " + "  ".join("%d=%s" % (k, n) for k, n in enumerate(names)))
print("%-5s " % "id" + " ".join("%-3s" % str(k) for k in range(len(names))) + "  real-failure-class")
for i in order:
    print("%-5s " % i + " ".join("%-3s" % data[i][n] for n in names) + "  " + (cls[i] if data[i]["real"] == "F" else ""))
fails = lambda n: [i for i in order if data[i][n] == "F"]
passes = lambda n: [i for i in order if data[i][n] == "P"]
print("\n== per-implementation totals (passed / %d) ==" % len(order))
for n in names: print("  %-12s %3d" % (n, len(passes(n))))
a, d = set(passes("stub-allow")), set(passes("stub-deny"))
print("\npassed by BOTH stubs (discriminate nothing): %d %s" % (len(a & d), sorted(a & d)))
print("failed by the always-allow stub: %d    failed by the always-deny stub: %d" % (len(order) - len(a), len(order) - len(d)))
print("failed by the no-op (never-inspects) hook: %d of %d" % (len(fails("nop")), len(order)))
ref_f = fails("ref")
print("\nREFERENCE DOUBLE fails: %d %s" % (len(ref_f), ref_f))
print("  -> %s" % ("assertions are mutually consistent against a contract-obedient implementation (NOT proof a real hook can pass)"
                   if not ref_f else "INCONSISTENT: an assertion or the double is wrong; the controls below mean nothing"))
print("\n== which assertions each degraded control fails ==")
for n in controls:
    f = fails(n); print("  %-12s fails %2d: %s" % (n, len(f), " ".join(f) if f else "(NONE -- this control is invisible to the suite)"))
weak = [i for i in order if all(data[i][n] == "P" for n in controls)]
print("\nassertions NO degraded control fails: %d %s" % (len(weak), weak))
print("  (the stubs/no-op still kill these; but no near-miss implementation does -- the weak ones)")
print("\nreal hook: %d passed, %d failed -- failure classes %s" % (len(passes("real")), len(fails("real")),
      dict(Counter(cls[i] for i in order if data[i]["real"] == "F"))))
print("\n== legend ==")
for i in order: print("  %-5s %s" % (i, desc[i]))
PYEOF
  python3 -I "$REPORTPY" "$RES" "$names" "$CONTROLS"
  exit 0
fi

run_suite real "$REAL_HOOK" 1
IFS=$'\t' read -r pass fail miss harn total < "$RES/real.sum"
printf '\nloosening-guard: %s passed, %s failed of %s\n' "$pass" "$fail" "$total"
if [ "$fail" -gt 0 ]; then
  if [ "$miss" -eq "$fail" ]; then printf 'RED, for the expected reason: %s does not exist (all %s failures are rc=127). Harness checks above passed.\n' "$REAL_HOOK" "$fail"
  else printf 'failure classes: hook-missing=%s harness=%s contract=%s\n' "$miss" "$harn" "$((fail-miss-harn))"; fi
  exit 1
fi
( cd "$ROOT" && python3 -I hooks/lib/write-test-marker.py "$MARKER_SELF" ) || { printf 'marker write FAILED\n' >&2; exit 1; }
exit 0
