#!/usr/bin/env bash
# dispatch-pane-agent.sh — entry point for pane orchestration.
#
#   dispatch <agent-type> --prompt-file <f> [--result-file <f>] [--cwd <dir>] [--role implementer|aux]
#   wait --result-file <f> [--timeout <secs>]
#   handoff [--cwd <dir>]
#   set-policy {inline | panes --max <N>}      (this session's pane-split policy)
#   count-workers                              (debug: live worker panes)
#
# Design: docs/superpowers/specs/2026-07-20-pane-orchestration-design.md.
# Degrades, never blocks: one adapter failure writes a per-session cooldown
# flag (keyed by $CLAUDE_CODE_SESSION_ID — the dispatcher is not a hook, so it
# has no stdin session_id; pane-dispatch-guard.sh checks both sources) and the
# guard then allows in-process dispatch for the rest of the session.
set -u
umask 077

PANES_DIR="${PANE_HOME:-$HOME/.claude/panes}"
STATE_DIR="${PANE_STATE_DIR:-$PANES_DIR/state}"
ADAPTERS_DIR="${PANE_ADAPTERS_DIR:-$PANES_DIR/adapters}"
DETECT="${PANE_TERMINAL_DETECT:-$PANES_DIR/terminal-detect.sh}"
REDIRECT_CONF="${PANE_REDIRECT_CONF:-$PANES_DIR/redirect-agents.conf}"
RUNS_DIR="$STATE_DIR/runs"
CMUX_BIN="/Applications/cmux.app/Contents/Resources/bin/cmux"
STALE_DAYS=7
DEFAULT_TIMEOUT=900
POLL_SECS=2
MAX_PANES=16                 # upper bound on 'panes max=N' (spec: bounded positive int)
# Digits capped at 2 (MAX_PANES is 16) to keep this reader and the guard's in
# lockstep: a hand-corrupted N past 2^64 ERRORS in the test builtin below but
# WRAPS into range in the guard's $((10#$n)), so an uncapped regex lets the two
# disagree about whether a policy exists. Behavior is otherwise unchanged —
# anything with 3+ digits already failed the 1..MAX_PANES range check.
POLICY_RE='^panes max=([0-9]{1,2})$'
CMUX_WAIT_SECS=15
AGENT_TYPE_RE='^[A-Za-z0-9_-]{1,64}$'
TIMEOUT_RE='^[0-9]+$'
# Consecutive open_tab failures that mean "this adapter cannot tab" rather than
# "that one pane is stale" (obs judge RUN 2). 3, not 2: the cost is asymmetric.
# Over-triggering silently discards the user's explicit `panes max=N` for the
# rest of the session; under-triggering leaks at most TAB_FAIL_LIMIT-1 surplus
# panes, which are visible and stop the moment the cooldown lands. 3 tolerates
# the benign multi-stale case (a couple of panes closed by hand, a cmux restart)
# while an adapter that genuinely cannot tab still trips it within three
# overflows.
TAB_FAIL_LIMIT=3

die() { printf 'dispatch-pane-agent: %s\n' "$1" >&2; exit "${2:-64}"; }

# Housekeeping decision (obs r2 residual 2): state older than STALE_DAYS is
# deleted on every invocation — nothing legitimate lives in state for a week.
cleanup_stale() {
  [ -d "$STATE_DIR" ] || return 0
  find "$RUNS_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$STALE_DAYS" -exec rm -rf {} + 2>/dev/null
  find "$STATE_DIR" -maxdepth 1 -type f -mtime +"$STALE_DAYS" -delete 2>/dev/null
  return 0
}

# Unique under concurrent dispatches (obs r2 residual 5): epoch-pid-random,
# and mkdir itself is the atomic uniqueness check — collision retries.
new_run_dir() {
  local i run_id
  for i in 1 2 3 4 5; do
    run_id="$(date +%s)-$$-$RANDOM"
    if mkdir "$RUNS_DIR/$run_id" 2>/dev/null; then printf '%s\n' "$RUNS_DIR/$run_id"; return 0; fi
    sleep 0."$i"
  done
  return 1
}

sanitize_title() { printf '%s' "$1" | tr -cd 'A-Za-z0-9 ._:-' | cut -c1-64; }

# read_policy <file> -> prints "inline" or "panes max=N" for a VALID line, else
# nothing (missing/corrupt/out-of-range => caller treats as "no policy"). Never
# errors: a malformed policy is a safe re-ask, not a failure (spec error table).
read_policy() {
  local f="$1" line n
  [ -f "$f" ] && [ -r "$f" ] || return 0
  line="$(head -n 1 "$f" 2>/dev/null)"
  if [ "$line" = "inline" ]; then printf 'inline\n'; return 0; fi
  if [[ "$line" =~ $POLICY_RE ]]; then
    n="${BASH_REMATCH[1]}"
    if [ "$n" -ge 1 ] && [ "$n" -le "$MAX_PANES" ] 2>/dev/null; then printf 'panes max=%s\n' "$n"; fi
  fi
  return 0
}

# is_judge <agent-type> -> 0 if listed in the always-paned judge conf.
# The `|| [ -n "$line" ]` keeps a final line with no trailing newline; the
# guard's in_conf carries the same guard, and the two parsers must agree or a
# judge is a judge to one of them and a gated worker to the other.
is_judge() {
  local want="$1" line
  [ -f "$REDIRECT_CONF" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"; line=$(printf '%s' "$line" | tr -d '[:space:]')
    [ -n "$line" ] && [ "$line" = "$want" ] && return 0
  done < "$REDIRECT_CONF"
  return 1
}

# live_worker_panes <session-key> -> one run-dir path per line (no trailing /).
# Live = a run dir tagged lane=worker for this session with no agent-exit marker
# yet. Three exclusions, all riding on plain file checks:
#   - lane=judge      — judges sit outside the policy and never consume a slot
#   - other sessions  — the per-session guarantee
#   - kind=tab        — an overflow run LIVES IN someone else's pane, so it is
#                       neither a pane for the max (spec: "max CONCURRENT worker
#                       panes") nor a legal overflow target (open_tab into a tab
#                       would nest a tab in a tab). A MISSING kind marker reads
#                       as pane, keeping pre-Task-7 run dirs valid.
# The count and the round-robin selection share this one predicate on purpose:
# if they could disagree about what a live worker pane is, a freed pane would
# stop being reclaimable or a tab could become an overflow target.
live_worker_panes() {
  local key="$1" d
  # An empty key would match every run dir whose session marker is missing or
  # empty — "no session" silently meaning "all sessions" — because the test
  # below compares marker CONTENT. Unreachable from the CLI (every caller
  # defaults to "nosession"), but this predicate is what both the count and the
  # overflow target choice ride on, so it fails closed here instead of trusting
  # its callers.
  [ -n "$key" ] || return 0
  [ -d "$RUNS_DIR" ] || return 0
  for d in "$RUNS_DIR"/*/; do
    [ -d "$d" ] || continue
    [ -f "${d}agent-exit" ] && continue
    [ "$(cat "${d}lane" 2>/dev/null)" = worker ] || continue
    [ "$(cat "${d}session" 2>/dev/null)" = "$key" ] || continue
    [ "$(cat "${d}kind" 2>/dev/null)" = tab ] && continue
    printf '%s\n' "${d%/}"
  done
}

# count_live_workers <session-key> -> integer (0 when RUNS_DIR is missing).
count_live_workers() {
  local key="$1" line n=0
  while IFS= read -r line; do n=$((n+1)); done < <(live_worker_panes "$key")
  printf '%s\n' "$n"
}

# select_worker_surface <session-key> -> one live worker pane's surface ref,
# round-robin. Non-zero if no live worker pane has a recorded surface; the
# caller then degrades that one spawn to in-process. The rotating index persists
# in state so successive overflows spread across the panes instead of piling
# every tab onto the first one.
select_worker_surface() {
  local key="$1" line ref i=0
  local rr="$STATE_DIR/pane-rr-$key"   # its own 'local': $key would not yet be in effect in the one above
  local refs=()
  while IFS= read -r line; do
    ref="$(cat "$line/surface" 2>/dev/null)"
    [ -n "$ref" ] && refs+=("$ref")
  done < <(live_worker_panes "$key")
  [ "${#refs[@]}" -gt 0 ] || return 1
  [ -f "$rr" ] && i="$(cat "$rr" 2>/dev/null)"
  [[ "$i" =~ ^[0-9]+$ ]] || i=0
  printf '%s\n' "$(( i + 1 ))" > "$rr" 2>/dev/null
  printf '%s\n' "${refs[$(( i % ${#refs[@]} ))]}"
}

# run_dir_for_surface <session-key> <surface-ref> -> the live worker-pane run dir
# holding that ref, or nothing. Rides the SAME live_worker_panes predicate as the
# count and the round-robin selection, deliberately: a ref select_worker_surface
# just handed out must resolve back to the very dir the next selection would
# re-pick, or retiring it would miss.
run_dir_for_surface() {
  local key="$1" want="$2" d
  [ -n "$want" ] || return 0
  while IFS= read -r d; do
    [ "$(cat "$d/surface" 2>/dev/null)" = "$want" ] || continue
    printf '%s\n' "$d"; return 0
  done < <(live_worker_panes "$key")
  return 0
}

# Default result location per spec: the session scratchpad's pane-results/.
# Derivable because the scratchpad path ends .../<session-id>/scratchpad and
# CLAUDE_CODE_SESSION_ID matches that segment (verified 2026-07-21).
scratchpad_dir() {
  local sid="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$sid" ] || return 0
  find "/private/tmp/claude-$(id -u)" -maxdepth 3 -type d -path "*/$sid/scratchpad" 2>/dev/null | head -n 1
}

# dead_mark <run_dir> — write the completion marker for a dispatch that never
# got a surface (I1). Without it the run dir sits there tagged lane=worker with
# no agent-exit and counts as a live worker for the rest of the session: a
# phantom that inflates the count into premature overflow and, having no surface
# of its own, is not even a selectable overflow target. Best-effort by design —
# the caller is already on its way to die.
dead_mark() {
  { [ -n "${1:-}" ] && [ -d "$1" ]; } || return 0
  printf 'DISPATCH-FAILED\n' > "$1/agent-exit" 2>/dev/null
  return 0
}

# Consecutive-open_tab-failure streak, per session. Kept in STATE_DIR so it
# expires with everything else via cleanup_stale, and read defensively: a
# hand-corrupted counter must not wedge the session either way.
bump_tab_failures() {   # <sid> -> prints the new streak
  local f n
  f="$STATE_DIR/tab-failed-$1"
  n="$(head -n 1 "$f" 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$((n + 1))
  printf '%s\n' "$n" > "$f" 2>/dev/null
  printf '%s\n' "$n"
}

# open_surface_or_cooldown <verb> <run_dir|""> <adapter args...> — prints
# TERMINAL/PANE_REF. One body for both verbs (open_pane <title> <launcher> and
# open_tab <target-surface> <title> <launcher>): the terminal check, the
# cooldown flag, the dead-mark, and the surface record must never drift apart
# between them.
open_surface_or_cooldown() {
  local verb="$1" run_dir="$2" term ref sid tgt streak
  shift 2
  tgt="${1:-}"                 # open_tab's target surface (the title for open_pane)
  term="$("$DETECT" 2>/dev/null)" || term=none
  if [ "$term" = "none" ] || [ ! -x "$ADAPTERS_DIR/$term.sh" ]; then
    dead_mark "$run_dir"
    die "no supported terminal ('$term') — dispatch in-process via the Agent tool instead" 3
  fi
  if ! ref="$("$ADAPTERS_DIR/$term.sh" "$verb" "$@")"; then
    sid="${CLAUDE_CODE_SESSION_ID:-nosession}"
    dead_mark "$run_dir"
    if [ "$verb" = open_tab ]; then
      # A failed open_tab is STALE LOCAL STATE, not a broken adapter: a worker
      # pane closed by hand, lost to a cmux restart, or holding an agent hung
      # past the wait timeout never gets its completion marker, so it stays
      # counted live AND keeps a surface ref that no longer resolves. Retire that
      # target so the next overflow picks a different pane, and degrade only THIS
      # spawn — exit 3, no cooldown, the same classification the no-target path
      # uses. Retiring is right even if the adapter really IS broken: a pane we
      # cannot tab into is not usable as a tab host either way, and the count then
      # drains one pane per failure until it falls under N, at which point the
      # next worker takes the open_pane path, fails, and writes the cooldown — so
      # the session still converges on the cooldown, just without one stale pane
      # poisoning a healthy session.
      #
      # That convergence argument holds only while open_pane ALSO fails. An
      # adapter that opens panes but cannot tab retires a healthy pane on every
      # overflow, the freed slot immediately opens a new one, and the real pane
      # count grows past max=N without bound (obs judge RUN 2). So the retirement
      # is bounded by a streak: at TAB_FAIL_LIMIT consecutive open_tab failures
      # the adapter — not the target — is what's broken, and this becomes an
      # ordinary adapter failure with the cooldown that implies.
      dead_mark "$(run_dir_for_surface "$sid" "$tgt")"
      streak="$(bump_tab_failures "$sid")"
      if [ "$streak" -lt "$TAB_FAIL_LIMIT" ]; then
        die "cannot tab into '$tgt' — stale or unusable target surface, now retired; dispatch this spawn in-process" 3
      fi
      : > "$STATE_DIR/adapter-failed-$sid"
      die "adapter '$term' failed $streak consecutive open_tab calls — treating it as tab-incapable; cooldown flag written, in-process dispatch is allowed for the rest of this session" 4
    fi
    : > "$STATE_DIR/adapter-failed-$sid"
    die "adapter '$term' $verb failed; cooldown flag written — in-process dispatch is allowed for the rest of this session" 4
  fi
  # A completed tab is the ONLY evidence this adapter can tab, so it alone clears
  # the streak. An open_pane success proves nothing about tab capability — and in
  # the growth loop above one succeeds between every pair of tab failures, so
  # clearing on it would make the limit unreachable.
  if [ "$verb" = open_tab ]; then
    rm -f "$STATE_DIR/tab-failed-${CLAUDE_CODE_SESSION_ID:-nosession}" 2>/dev/null
  fi
  [ -n "$run_dir" ] && printf '%s\n' "$ref" > "$run_dir/surface" 2>/dev/null
  printf 'TERMINAL: %s\nPANE_REF: %s\n' "$term" "$ref"
}

cmd="${1:-}"
[ $# -ge 1 ] && shift

case "$cmd" in
  dispatch)
    agent_type="${1:-}"
    # shellcheck disable=SC2015 # non-empty agent_type guarantees $1 exists, so shift never fails into die
    [ -n "$agent_type" ] && shift || die "usage: dispatch <agent-type> --prompt-file <f> [--result-file <f>] [--cwd <dir>] [--role implementer|aux]"
    prompt_file=""; result_file=""; run_cwd="$PWD"; role="aux"
    while [ $# -gt 0 ]; do
      case "$1" in
        --prompt-file) [ $# -ge 2 ] || die "--prompt-file needs a value"; prompt_file="$2"; shift 2 ;;
        --result-file) [ $# -ge 2 ] || die "--result-file needs a value"; result_file="$2"; shift 2 ;;
        --cwd)         [ $# -ge 2 ] || die "--cwd needs a value";         run_cwd="$2";     shift 2 ;;
        --role)        [ $# -ge 2 ] || die "--role needs a value";        role="$2";        shift 2 ;;
        *) die "unknown option: $1" ;;
      esac
    done
    [[ "$agent_type" =~ $AGENT_TYPE_RE ]] || die "agent-type must match [A-Za-z0-9_-]{1,64}"
    # Allowlist, fail fast: a garbage role is a caller bug and must die before
    # any adapter call (spec error table).
    case "$role" in implementer|aux) ;; *) die "--role must be implementer or aux (got: $role)" ;; esac
    { [ -f "$prompt_file" ] && [ -r "$prompt_file" ]; } || die "--prompt-file missing or unreadable: $prompt_file"
    [ -d "$run_cwd" ] || die "--cwd is not an existing directory: $run_cwd"
    run_cwd="$(cd "$run_cwd" && pwd)" || die "cannot resolve --cwd"

    # Canonicalize a user-supplied --result-file to an absolute path against the
    # caller's CWD, the same way --cwd is resolved above (obs final-review F4).
    # A relative path would otherwise resolve against three different CWDs in the
    # dispatcher, the runner, and wait. The default path (computed below) is
    # already absolute, so this only touches an explicit --result-file.
    if [ -n "$result_file" ]; then
      rf_parent="$(dirname "$result_file")"
      rf_abs_parent="$(cd "$rf_parent" 2>/dev/null && pwd)" || die "result-file directory does not exist: $rf_parent"
      result_file="$rf_abs_parent/$(basename "$result_file")"
    fi

    mkdir -p "$RUNS_DIR"
    cleanup_stale
    run_dir="$(new_run_dir)" || die "could not create a unique run dir under $RUNS_DIR"

    if [ -z "$result_file" ]; then
      scratch="$(scratchpad_dir)"
      if [ -n "$scratch" ] && [ -d "$scratch" ]; then
        mkdir -p "$scratch/pane-results"
        # Unique per dispatch (obs final-review F1): epoch-pid-random, the same
        # recipe new_run_dir uses — two same-type dispatches in one second must
        # not collide onto one file that both runners would mv over.
        result_file="$scratch/pane-results/$agent_type-$(date +%s)-$$-$RANDOM.md"
      else
        result_file="$run_dir/result.md"
      fi
    fi
    [ -e "$result_file" ] && die "refusing to reuse an existing result file: $result_file" 65
    [ -d "$(dirname "$result_file")" ] || die "result-file directory does not exist: $(dirname "$result_file")"

    cp "$prompt_file" "$run_dir/prompt.md" || die "cannot copy prompt into run dir"

    # The launcher is the injection boundary's controlled token: %q-quoted args,
    # mode 700, inside the 700 run dir (prompt lives there too). It keeps the
    # pane open after the agent exits by dropping into an interactive shell.
    launcher="$run_dir/launch.sh"
    {
      printf '#!/usr/bin/env bash\n'
      printf 'bash %q %q %q %q %q\n' "$PANES_DIR/run-pane-agent.sh" "$agent_type" "$run_dir/prompt.md" "$result_file" "$run_cwd"
      printf 'echo; echo "[pane kept open for inspection -- agent exit $?]"\n'
      printf 'exec /bin/zsh -i\n'
    } > "$launcher"
    chmod 700 "$launcher"

    key="${CLAUDE_CODE_SESSION_ID:-nosession}"
    if is_judge "$agent_type"; then lane=judge; else lane=worker; fi

    # Layout-v2: the adapter composes the managed title from this bare label plus
    # the role; the old "pane: " prefix would eat the managed grammar's budget.
    export PANE_AGENT_ROLE="$role"
    title="$(sanitize_title "$agent_type")"
    kind=pane; target=""; live="-"; n="-"     # "-" = not applicable to this lane/policy
    if [ "$lane" = worker ]; then
      policy="$(read_policy "$STATE_DIR/pane-policy-$key")"
      case "$policy" in
        panes\ max=*)
          n="${policy#panes max=}"
          live="$(count_live_workers "$key")"
          if [ "$live" -ge "$n" ]; then
            # At/over the worker max this spawn overflows into an existing live
            # worker pane as a tab — never inline, never blocking (spec). If no
            # live worker pane has a surface to tab into there is nothing to
            # overflow into, so degrade THIS spawn to in-process without a
            # cooldown (capacity, not an adapter failure); exit 3 = "run
            # in-process", same as no-terminal.
            target="$(select_worker_surface "$key")" \
              || die "worker max $n reached ($live live) and no live worker pane to tab into — dispatch this spawn in-process" 3
            kind=tab
          fi ;;
        *) : ;;   # inline/none reaching the dispatcher: single pane, no gating
      esac
    fi
    # Written after the gate above: count_live_workers must not count THIS
    # dispatch's own run dir as already-live (C1 off-by-one). select_worker_surface
    # runs above them for the same reason, and so that a no-target overflow dies
    # before it can leave a phantom lane=worker dir behind (I1).
    #
    # Order within the set matters: `kind` first, `lane` LAST. live_worker_panes
    # gates on lane=worker && session=key before it ever reads kind, and a
    # MISSING kind reads as "pane" by design — so writing lane first exposes a
    # window where a concurrent dispatch counts this tab as a pane. Writing lane
    # last makes it the single commit point for the whole marker set.
    printf '%s\n' "$kind" > "$run_dir/kind"
    printf '%s\n' "$key"  > "$run_dir/session"
    printf '%s\n' "$lane" > "$run_dir/lane"
    # The decisive computation, on one line. The markers above record WHAT was
    # chosen; only this records WHY — "counted 2 live, max is 2, so tabbed into
    # surface:X" is otherwise unrecoverable and has to be re-derived by hand at
    # exactly the moment routing surprised someone. stderr reaches the caller now;
    # the run-dir copy outlives the session (and this dispatch's own failure).
    route="lane=$lane live=$live max=$n kind=$kind target=${target:--}"
    printf 'ROUTE: %s\n' "$route" >&2
    printf '%s\n' "$route" > "$run_dir/route" 2>/dev/null
    if [ "$kind" = tab ]; then
      open_surface_or_cooldown open_tab "$run_dir" "$target" "$title" "$launcher"
    else
      open_surface_or_cooldown open_pane "$run_dir" "$title" "$launcher"
    fi
    printf 'RESULT_FILE: %s\n' "$result_file"
    ;;

  wait)
    result_file=""; timeout="$DEFAULT_TIMEOUT"
    while [ $# -gt 0 ]; do
      case "$1" in
        --result-file) [ $# -ge 2 ] || die "--result-file needs a value"; result_file="$2"; shift 2 ;;
        --timeout)     [ $# -ge 2 ] || die "--timeout needs a value";     timeout="$2";     shift 2 ;;
        *) die "unknown option: $1" ;;
      esac
    done
    [ -n "$result_file" ] || die "wait needs --result-file"
    [[ "$timeout" =~ $TIMEOUT_RE ]] || die "--timeout must be a whole number of seconds"
    deadline=$(( $(date +%s) + timeout ))
    while :; do
      if [ -f "$result_file" ]; then
        last="$(tail -n 1 "$result_file")"
        case "$last" in
          'PANE_RESULT: DONE')   cat "$result_file"; exit 0 ;;
          'PANE_RESULT: FAILED') cat "$result_file"; exit 1 ;;
        esac
      fi
      if [ "$(date +%s)" -ge "$deadline" ]; then
        printf 'dispatch-pane-agent: wait timed out after %ss (%s); the pane stays open for post-mortem\n' "$timeout" "$result_file" >&2
        exit 2
      fi
      # Latency nicety per spec: block on cmux wait-for (runner signals it)
      # instead of a fixed sleep; correctness still comes from the file check.
      if [ -n "${CMUX_PANEL_ID:-}" ] && [ -x "$CMUX_BIN" ]; then
        # If cmux wait-for fails fast, fall back to the fixed poll interval so
        # the loop cannot hot-spin (obs final-review F3); the file check below
        # stays authoritative either way.
        "$CMUX_BIN" wait-for "pane-$(basename "$result_file")" --timeout "$CMUX_WAIT_SECS" >/dev/null 2>&1 || sleep "$POLL_SECS"
      else
        sleep "$POLL_SECS"
      fi
    done
    ;;

  handoff)
    run_cwd="$PWD"
    while [ $# -gt 0 ]; do
      case "$1" in
        --cwd) [ $# -ge 2 ] || die "--cwd needs a value"; run_cwd="$2"; shift 2 ;;
        *) die "unknown option: $1" ;;
      esac
    done
    [ -d "$run_cwd" ] || die "--cwd is not an existing directory: $run_cwd"
    run_cwd="$(cd "$run_cwd" && pwd)" || die "cannot resolve --cwd"
    mkdir -p "$RUNS_DIR"
    cleanup_stale
    run_dir="$(new_run_dir)" || die "could not create a unique run dir under $RUNS_DIR"
    launcher="$run_dir/launch.sh"
    {
      printf '#!/usr/bin/env bash\n'
      printf 'bash %q %q\n' "$PANES_DIR/handoff-wrapper.sh" "$run_cwd"
      printf 'exec /bin/zsh -i\n'
    } > "$launcher"
    chmod 700 "$launcher"
    # The handoff pane is a side pane like any judge — it belongs in the aux
    # column, never the implementer quadrant.
    export PANE_AGENT_ROLE=aux
    open_surface_or_cooldown open_pane "" "$(sanitize_title "handoff: press Enter")" "$launcher"
    ;;

  set-policy)
    mode="${1:-}"
    # shellcheck disable=SC2015 # non-empty mode guarantees $1 exists, so shift never fails into die
    [ -n "$mode" ] && shift || die "usage: set-policy {inline|panes --max N}"
    max=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --max) [ $# -ge 2 ] || die "--max needs a value"; max="$2"; shift 2 ;;
        *) die "unknown option: $1" ;;
      esac
    done
    key="${CLAUDE_CODE_SESSION_ID:-nosession}"
    mkdir -p "$STATE_DIR"
    case "$mode" in
      inline) printf 'inline\n' > "$STATE_DIR/pane-policy-$key" || die "cannot write policy file" ;;
      panes)
        [[ "$max" =~ ^[0-9]+$ ]] || die "--max must be a whole number 1..$MAX_PANES"
        { [ "$max" -ge 1 ] && [ "$max" -le "$MAX_PANES" ]; } || die "--max out of range (1..$MAX_PANES)"
        # Canonicalize (e.g. "03" -> "3") so the file can never contain a
        # zero-padded value the guard's reader would fail to recognize.
        max=$((10#$max))
        printf 'panes max=%s\n' "$max" > "$STATE_DIR/pane-policy-$key" || die "cannot write policy file" ;;
      *) die "set-policy mode must be inline or panes" ;;
    esac
    printf 'POLICY: %s\n' "$(cat "$STATE_DIR/pane-policy-$key")"
    ;;

  count-workers) count_live_workers "${CLAUDE_CODE_SESSION_ID:-nosession}" ;;

  *)
    die "usage: dispatch-pane-agent.sh {dispatch|wait|handoff|set-policy|count-workers} ..." ;;
esac
