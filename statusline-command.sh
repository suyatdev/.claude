#!/bin/bash
# Approximates the oh-my-zsh "robbyrussell" prompt theme for the Claude Code statusline.
# No PS1 was found in the user's shell config, so this reconstructs the look using
# data Claude Code provides via stdin JSON.
#
# Target look: "➜  <user>@<host> <dir> git:(<branch>) ✗  │ <model> │ <bar> <used>
# │ Σ <cumulative>"
# Σ is cumulative input+output tokens for this session (cache traffic excluded
# -- see the call_tokens comment below for why).
# The ✗ dirty marker only appears when the working tree has uncommitted changes;
# clean repos show no marker, matching robbyrussell's ZSH_THEME_GIT_PROMPT_CLEAN.
# The trailing segments are secondary to the git prompt and sourced from the
# statusline JSON plus per-session state this script maintains under
# ~/.claude/statusline-state/ (see the "Claude-specific segments" section
# below for what each one means and why). Each segment -- and its separator
# -- is silently omitted when its field/state is absent (e.g. before the
# first API response of a session).
#
# No cost/spend segment by design: this account is on a subscription plan, not
# metered per-token billing, so any dollar figure here would be a locally
# computed estimate rather than a real charge. Displaying one would invite
# reading it as a bill. Token pressure is the thing worth watching, and that is
# what the bar and Σ show.

# Every value below originates outside this script, so each is stripped of C0
# control bytes and DEL before it reaches the terminal. Two distinct routes get
# closed here; the first alone is not enough:
#   1. printf '%b' would expand the literal seven-character text \x1b into a real
#      escape. Addressed by the $'...' colours plus printf '%s' below.
#   2. JSON can carry a *real* control byte directly, written as a unicode
#      escape. jq -r decodes that into an actual byte, which printf '%s' then
#      passes through untouched -- enough to set a blink attribute, rewrite the
#      terminal title with an OSC sequence, or split the status line with a
#      newline. Only stripping closes this second route.
# ${v//[[:cntrl:]]/} is pure bash (works on macOS's bash 3.2), so each strip is
# an inline expansion rather than another fork, in a script that re-renders on
# every status line update.

input=$(cat)
# Both candidate sources are external -- the JSON payload, and the name of
# whatever directory the shell happens to be in -- so each is stripped AT ITS
# SOURCE rather than once after the fallback. Ordering a strip around a fallback
# is what went wrong twice: put the strip first and the fallback reintroduces an
# unstripped value; put it last and a value that strips to empty falls through to
# a second, unstripped assignment. Stripping each source removes the trap
# entirely -- there is no later assignment that can reintroduce a raw value.
#
# $PWD cannot strip to empty: it is always absolute, so it always retains its
# slashes. That is what guarantees $cwd is non-empty below, which in turn keeps
# `git -C "$cwd"` from silently resolving to the process's own directory.
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
cwd="${cwd//[[:cntrl:]]/}"
[ -z "$cwd" ] && cwd="${PWD//[[:cntrl:]]/}"

# $'...' embeds real ESC bytes at assignment time, so the final render can use
# printf '%s' rather than '%b'. With '%b', printf expands backslash escapes
# anywhere in the string -- including inside *data* -- so a directory or model
# name containing a literal \x1b or \n would inject a live terminal escape or
# split the status line across two lines. Git forbids backslashes in ref names,
# but directory names have no such restriction.
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
BLUE=$'\033[0;34m'
RED=$'\033[0;31m'
WHITE=$'\033[0;37m'
DIM=$'\033[2m'
RESET=$'\033[0m'
ARROW=$'\xe2\x9e\x9c'
ORANGE=$'\033[38;5;208m'
YELLOW=$'\033[0;33m'
PURPLE=$'\033[38;5;141m'
SIGMA=$'\xce\xa3'
CLOCK_ICON=$'\xe2\x8f\xb1'
BAR_FILL=$'\xe2\x96\x88'
BAR_EMPTY=$'\xe2\x96\x91'

# --- Context-window progress bar ----------------------------------------
# The bar measures context against a fixed 100k reference, NOT the model's
# actual context window size. 100k is the point at which the session is worth
# clearing, so that -- not the model's headroom -- is the number that matters:
# a 1M-context model still gets unwieldy long before it is technically full.
# Scaling fill and colour to the same 100k reference is what keeps the two
# halves of the widget consistent; against the real window size a 143k session
# rendered as a nearly-empty bar coloured red, which read as a bug.
# Consequence: at >=100k the bar is full and red and stays there. That is
# deliberate -- past the clear threshold, how far past stops mattering, and the
# exact count is still shown numerically beside the bar.
BAR_WIDTH=10
BAR_REFERENCE_TOKENS=100000
THRESHOLD_TOKENS_YELLOW=50000
THRESHOLD_TOKENS_ORANGE=75000
THRESHOLD_TOKENS_RED=100000

# Formats a raw token count as "1234" (<1000) or "12.3k" (>=1000).
format_k() {
  awk -v n="$1" 'BEGIN { n += 0; if (n >= 1000) printf "%.1fk", n / 1000; else printf "%d", n }' 2>/dev/null
}

# Timestamp -> epoch seconds, or empty if it cannot be read.
# `resets_at` is documented as Unix epoch SECONDS (an integer), so the
# all-digits case below is the real one and is handled first, without
# shelling out to date at all. The ISO-8601 branch after it is defensive
# only: an earlier version of this script assumed ISO and silently rendered
# no countdown at all, because a failed parse is indistinguishable from an
# absent field at the call site. Accepting both shapes means a format change
# in either direction degrades to a working countdown rather than a missing
# one. BSD date (macOS) is tried before GNU date; fractional seconds and a
# trailing Z/offset are trimmed first, as BSD's -f matching is strict enough
# to reject the whole string over either.
to_epoch() {
  local raw="$1"
  case "$raw" in
    '') return 0 ;;
    *[!0-9]*) ;;
    *) printf '%s' "$raw"; return 0 ;;
  esac
  local ts="${raw%%.*}"
  ts="${ts%Z}"
  ts="${ts%%+*}"
  [ -z "$ts" ] && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%S' "$ts" '+%s' 2>/dev/null && return 0
  date -u -d "$ts" '+%s' 2>/dev/null
}

# Seconds -> compact "2d 4h" / "4h 12m" / "18m". Only the two largest units
# are shown; past the reset (or under a minute) this yields "0m", which the
# caller treats as "no useful countdown" rather than printing it.
format_duration() {
  awk -v s="$1" 'BEGIN {
    s = int(s); if (s < 0) s = 0
    d = int(s / 86400); s -= d * 86400
    h = int(s / 3600);  s -= h * 3600
    m = int(s / 60)
    if (d > 0)      printf "%dd %dh", d, h
    else if (h > 0) printf "%dh %dm", h, m
    else            printf "%dm", m
  }' 2>/dev/null
}

dir=$(basename "$cwd")
# whoami/hostname are far less exposed than the JSON -- reaching them means
# controlling the hostname or PATH, at which point the terminal is the least of
# it. Stripped anyway so the claim above holds for *every* value without a
# carve-out a future reader has to re-derive.
user=$(whoami)
user="${user//[[:cntrl:]]/}"
host=$(hostname -s)
host="${host//[[:cntrl:]]/}"

branch=""
dirty=""
# --no-optional-locks avoids contending with other concurrent git operations
# (e.g. parallel agents in worktrees).
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  # git rejects control characters in ref names, so this is belt-and-braces --
  # but it costs one inline expansion and removes the need to trust that.
  branch="${branch//[[:cntrl:]]/}"
  if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
    dirty=" ${RED}✗${RESET}"
  fi
fi

out="${GREEN}${ARROW}${RESET}  ${WHITE}${user}@${host}${RESET} ${CYAN}${dir}${RESET}"
if [ -n "$branch" ]; then
  out="${out} ${BLUE}git:(${RESET}${RED}${branch}${RESET}${BLUE})${RESET}${dirty}"
fi

# --- Claude-specific segments (secondary to the git prompt) -------------
# Model name, context-window progress bar, and session-cumulative tokens.
# Each segment is independently omitted when its JSON field is absent/null or
# its state can't be read, so a partial payload or a missing state file never
# breaks the line -- it just renders fewer segments.
model_name=$(echo "$input" | jq -r '.model.display_name // empty')
model_name="${model_name//[[:cntrl:]]/}"

tokens_used=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
tokens_used="${tokens_used//[[:cntrl:]]/}"

# --- Weekly rate-limit window --------------------------------------------
# Deliberately a PERCENTAGE, not a token count. Claude Code exposes weekly
# quota consumption as `used_percentage` only -- there is no field giving a
# token allowance or a remaining-token figure -- so a "tokens left" number
# could only be produced by inventing a denominator and would look
# authoritative while being made up. The percentage is the real measurement;
# it answers the same question ("how much of the week is left") honestly.
week_used_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_used_pct="${week_used_pct//[[:cntrl:]]/}"
week_resets_at=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
week_resets_at="${week_resets_at//[[:cntrl:]]/}"

session_id=$(echo "$input" | jq -r '.session_id // empty')
session_id="${session_id//[[:cntrl:]]/}"
# Restricted to a filesystem-safe charset before it ever touches a path --
# this value comes straight from the JSON payload, so an unsanitized
# session_id containing e.g. "../" could otherwise escape statusline-state/.
session_id_safe=$(printf '%s' "$session_id" | tr -cd 'A-Za-z0-9_-')

cu_input=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
cu_input="${cu_input//[[:cntrl:]]/}"
cu_output=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // empty')
cu_output="${cu_output//[[:cntrl:]]/}"
cu_cache_write=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // empty')
cu_cache_write="${cu_cache_write//[[:cntrl:]]/}"
cu_cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // empty')
cu_cache_read="${cu_cache_read//[[:cntrl:]]/}"

# --- Per-session running token total -------------------------------------
# Keyed by session_id so concurrent Claude Code sessions each keep their own
# counter (see the Parallel-Agent Invariants in CLAUDE.md -- multiple
# sessions can genuinely run at once from different worktrees). "New API
# call" is detected by diffing the four current_usage numbers against the
# last-seen set rather than prompt_id: a single prompt can trigger several
# internal API calls (tool-use loops), all sharing one prompt_id, and keying
# on that would silently drop every call but the last one from the total.
STATE_DIR="$HOME/.claude/statusline-state"
mkdir -p "$STATE_DIR" 2>/dev/null

# --- State file format ----------------------------------------------------
# Two lines: the usage signature, then the running total. Plain text rather
# than JSON specifically so it can be read with the `read` BUILTIN. The JSON
# form cost two jq forks (~8ms measured) on every render, and that is what made
# a prompt-safe lock unworkable below: a critical section long enough to fork
# jq cannot serialise several waiting renders inside any delay a prompt can
# absorb. Reading fork-free brings the whole locked section to roughly one mv.
#
# Anything not matching the shape written here is treated as absent rather than
# trusted, which also handles the one-time migration from the old .json file:
# its single line fails the signature charset test, so the counter restarts
# from the current call. Legacy session-*.json files are inert leftovers.
read_session_state() { # $1 state file -> sets $state_sig / $state_cum
  state_sig=""
  state_cum=0
  [ -f "$1" ] || return 0
  local f_sig="" f_cum=""
  # No `|| f_var=""` fallbacks: `read` returns non-zero at EOF on a final line
  # with no trailing newline even though it assigned the value, so treating that
  # status as failure would discard a total this script had written correctly.
  # Both values are charset-validated below, which is the real guard.
  { read -r f_sig; read -r f_cum; } <"$1" 2>/dev/null
  case "$f_sig" in ''|*[!0-9:]*) f_sig="" ;; esac
  case "$f_cum" in ''|*[!0-9]*) f_cum=0 ;; esac
  state_sig="$f_sig"
  state_cum="$f_cum"
}

# --- Serialising the read-modify-write ------------------------------------
# The total is read, incremented, and written back. Two renders that overlap
# both read the same starting value and the later write erases the earlier: a
# LOST UPDATE. The atomic mv below does not prevent this and never did -- that
# guards a torn READ, which is a different failure. Conflating the two is what
# left this open. Measured before fixing: 20 concurrent renders against a
# seeded 200 stored 1213, the seed plus exactly one writer.
#
# mkdir is the lock primitive. It is atomic on every POSIX filesystem and needs
# no flock, which macOS does not ship. The holder's PID is recorded inside so a
# lock orphaned by a killed render can be cleared instead of wedging the
# counter for the rest of the session.
#
# Failing to acquire is NOT an error. This is a cosmetic counter on a line that
# re-renders constantly, so no total is worth a stalled prompt. On timeout the
# update is skipped -- and skipping is usually deferral rather than loss: the
# signature is not stored either, so the next render sees the same unrecorded
# usage and tries again. It is only a real loss when usage moves on before any
# retry wins the lock, which needs sustained contention to happen at all.
# Sized against measurement, not arithmetic. Worst case is ATTEMPTS *
# (LOCK_SLEEP + one fork of /bin/sleep), and the FORK dominates: at ~9ms it
# makes each attempt cost ~19ms, so the interval is nearly irrelevant.
# Change ATTEMPTS, not LOCK_SLEEP.
#
# 20 gives a ~390ms ceiling, deliberately above the ~314ms measured for 20
# concurrent renders of one session to drain. A budget below the drain time does
# not degrade gracefully -- it structurally guarantees the last waiters give up.
# Tried and rejected: 10 attempts (~190ms) looked like the safer prompt-latency
# choice and made the concurrency test fail every run, at 387-495 of 510.
#
# The ceiling is only ever paid in full by a render that never acquires, and
# that render skips its update rather than blocking anything downstream. An
# uncontended render is ~65-78ms and takes the lock on the first attempt.
LOCK_ATTEMPTS=20
LOCK_SLEEP=0.01
LOCK_STALE_MINUTES=1

# Clears a lock whose owner is provably gone. Called ONCE before the spin, not
# per attempt: the age branch forks `find`, and doing that on every iteration
# stretched the give-up ceiling from ~200ms to a measured 455ms -- a stall a
# prompt cannot absorb, to re-answer a question whose answer cannot change
# while we hold still. A holder that dies mid-spin is simply cleared by the
# next render, which is soon and costs nothing.
# Breaking a stale lock must be ATOMIC with respect to whoever takes it next.
# `rm -rf "$lock"` is not, and that is a lost update in its own right: several
# renders can each judge the same lock stale, and a removal that lands after
# another render has legitimately acquired the lock deletes a LIVE lock. The
# mechanism built to prevent lost updates then causes them. Reproduced at 20
# concurrent renders against a planted stale lock.
#
# The lock is renamed away instead. rename() is atomic, so exactly one breaker
# wins and the losers get ENOENT and carry on. Crucially the winner only ever
# deletes the directory it captured, never the live path. It then confirms the
# capture is the lock it judged -- a fresh holder may have taken the lock
# between the judgement and the rename -- and puts it back on a mismatch rather
# than destroying a live lock.
#
# Residual window, deliberately accepted: if the restore fails because a newer
# lock already exists at the path, the captured directory is dropped. That
# needs two breakers and a new holder to interleave within two syscalls, and
# the cost is one wrong cosmetic total that self-heals next render. Closing it
# properly needs a compare-and-swap the filesystem does not offer.
# The verification must test WHATEVER JUSTIFIED THE BREAK, not merely something
# about the capture. An earlier version justified a break by AGE and then
# verified by PID: a lock released and re-taken in between passed the PID check
# and a live lock was deleted. `mv` preserves mtime, so the age of a captured
# directory is still the age that was judged -- which is what makes verifying on
# the capture sound for both modes.
break_lock_verified() { # $1 dir, $2 mode: "age" | "pid:<expected>"
  local lock="$1" mode="$2" grave="$1.dead.$$" captured="" verified=1
  mv "$lock" "$grave" 2>/dev/null || return 0
  case "$mode" in
    age)
      [ -n "$(find "$grave" -maxdepth 0 -mmin "+$LOCK_STALE_MINUTES" 2>/dev/null)" ] && verified=0
      ;;
    pid:*)
      [ -r "$grave/pid" ] && read -r captured <"$grave/pid" 2>/dev/null
      [ "$captured" = "${mode#pid:}" ] && verified=0
      ;;
  esac
  if [ "$verified" -eq 0 ]; then
    rm -rf "$grave" 2>/dev/null
    return 0
  fi
  # Not what we judged: a fresh holder took it in between. Put it back rather
  # than destroy a live lock.
  mv "$grave" "$lock" 2>/dev/null || rm -rf "$grave" 2>/dev/null
  return 0
}

acquire_break_lock() { # $1 breaker dir -> 0 acquired, 1 someone else is breaking
  mkdir "$1" 2>/dev/null || return 1
  printf '%s\n' "$$" >"$1/pid" 2>/dev/null
  return 0
}

# Releases only a lock this process still owns -- used for BOTH the state lock
# and the breaker lock. If ours was broken and re-taken while we held it,
# removing it would evict a live holder: the same eviction bug, at the other end
# of the lock's life. The breaker lock originally released unconditionally,
# which let two renders hold it at once and defeated the serialisation that is
# the entire point of it.
release_lock_if_owned() { # $1 lock dir
  local holder=""
  [ -r "$1/pid" ] && read -r holder <"$1/pid" 2>/dev/null
  [ "$holder" = "$$" ] && rm -rf "$1" 2>/dev/null
  return 0
}

# Clears a breaker lock orphaned by a killed render. There is no third lock to
# serialise this with, so the atomic capture IS the protection -- and it is
# verified by age, the same property that justified it.
break_aged_breaker() { # $1 breaker dir
  [ -d "$1" ] || return 0
  [ -n "$(find "$1" -maxdepth 0 -mmin "+$LOCK_STALE_MINUTES" 2>/dev/null)" ] || return 0
  break_lock_verified "$1" "age"
}

# Last-resort backstop for a lock whose PID looks alive but is not its owner:
# PIDs are reused after wraparound, and kill -0 cannot tell a reused PID from
# the original holder, so without this a stale lock would wedge that session's
# counter permanently and silently. Run only after the spin is exhausted, never
# per attempt -- it forks `find`, and the contended path is exactly where that
# cost is least affordable. The counter self-heals on the following render.
force_break_aged_lock() { # $1 lock dir
  local lock="$1" breaker="$1.break"
  # Clear a breaker orphaned by a killed render first -- while one stands, no
  # render can break anything, so this is what keeps a wedge recoverable.
  break_aged_breaker "$breaker"
  [ -d "$lock" ] || return 0
  acquire_break_lock "$breaker" || return 0
  # Judge age INSIDE the breaker lock, and break on that same property. The
  # first version judged age out here and then verified the capture by PID, so
  # a lock released and re-taken in between passed the check and a LIVE lock was
  # deleted. Age is the justification, so age is what must be re-checked.
  [ -n "$(find "$lock" -maxdepth 0 -mmin "+$LOCK_STALE_MINUTES" 2>/dev/null)" ] &&
    break_lock_verified "$lock" "age"
  release_lock_if_owned "$breaker"
  return 0
}

# Only ONE render may attempt a break, serialised by a second mkdir lock.
# Atomic renaming alone is not enough: twenty renders each judge the same lock
# stale, and each then acts on a judgement that is already out of date, so one
# captures a lock a different render legitimately acquired microseconds earlier.
# Measured with renaming but no serialisation: 4 runs in 10 still lost updates.
# Serialising removes the stampede entirely. The single breaker's own
# judge-then-rename window remains, and is what break_lock_verified's
# verification covers.
#
# A breaker lock orphaned by a killed render would disable breaking for that
# session; force_break_aged_lock clears it on age, off the contended path.
clear_stale_lock() { # $1 lock dir
  local lock="$1" holder="" breaker="$1.break"
  [ -d "$lock" ] || return 0
  acquire_break_lock "$breaker" || return 0
  # Re-read INSIDE the breaker lock: a judgement made before serialising is
  # exactly the out-of-date judgement this function exists to avoid acting on.
  #
  # No `|| holder=""` on failure: `read` returns non-zero at EOF on a file with
  # no trailing newline while still having assigned the value, so treating its
  # exit status as "nothing was read" discards a perfectly good PID. That is
  # exactly the bug this line replaces -- it made the whole PID check dead code
  # and sent every stale lock down the slow age path instead.
  [ -r "$lock/pid" ] && read -r holder <"$lock/pid" 2>/dev/null
  case "$holder" in
    ''|*[!0-9]*)
      # No usable PID: the holder either died between mkdir and the pid write,
      # or the file is corrupt. Neither can be tested with kill -0, so fall back
      # to age -- a lock older than a minute cannot belong to a live render,
      # which finishes in milliseconds. Deliberately NOT cleared when it is
      # merely young and pid-less: that is the normal, microseconds-long window
      # of a healthy holder, and breaking it would reintroduce the lost update.
      [ -n "$(find "$lock" -maxdepth 0 -mmin "+$LOCK_STALE_MINUTES" 2>/dev/null)" ] &&
        break_lock_verified "$lock" "age"
      ;;
    *)
      # kill -0 tests for existence only; it sends no signal. A PID that looks
      # alive is left alone here; force_break_aged_lock covers PID reuse after
      # the spin, where the extra fork is affordable.
      kill -0 "$holder" 2>/dev/null || break_lock_verified "$lock" "pid:$holder"
      ;;
  esac
  release_lock_if_owned "$breaker"
  return 0
}

acquire_state_lock() { # $1 lock dir -> 0 acquired, 1 gave up
  local lock="$1" attempt=0
  clear_stale_lock "$lock"
  while [ "$attempt" -lt "$LOCK_ATTEMPTS" ]; do
    # Trailing newline matters: it is what lets a reader's `read` succeed
    # rather than report EOF on the last line.
    if mkdir "$lock" 2>/dev/null; then
      printf '%s\n' "$$" >"$lock/pid" 2>/dev/null
      return 0
    fi
    attempt=$((attempt + 1))
    sleep "$LOCK_SLEEP" 2>/dev/null
  done
  # A lock this persistent may be held by a reused PID that kill -0 cannot
  # distinguish from its original owner. Break it on age here, off the
  # contended path, so the next render acquires normally.
  force_break_aged_lock "$lock"
  return 1
}

cum_tokens=0

if [ -n "$session_id_safe" ] && [ -d "$STATE_DIR" ]; then
  session_state_file="$STATE_DIR/session-${session_id_safe}.state"
  read_session_state "$session_state_file"
  prev_sig="$state_sig"
  cum_tokens="$state_cum"

  have_usage=false
  if [ -n "$cu_input" ] || [ -n "$cu_output" ] || [ -n "$cu_cache_write" ] || [ -n "$cu_cache_read" ]; then
    have_usage=true
  fi

  if [ "$have_usage" = "true" ]; then
    sig="${cu_input:-0}:${cu_output:-0}:${cu_cache_write:-0}:${cu_cache_read:-0}"
    if [ "$sig" != "$prev_sig" ]; then
      # Σ counts input + output ONLY. Cache reads/writes are deliberately
      # excluded: they dominate raw token flow by two orders of magnitude
      # (this account's own stats show ~2.7B cache-read against ~13M output
      # on a single model), so folding them in would swamp the figure and
      # stop it tracking actual conversation volume. Note this differs from
      # $sig above, which still fingerprints all four fields -- that is for
      # detecting a new API call, not for measuring one.
      #
      # Computed BEFORE the lock: it depends only on the payload, and every
      # instruction inside the critical section is one every other render is
      # waiting through.
      call_tokens=$(awk -v a="${cu_input:-0}" -v b="${cu_output:-0}" 'BEGIN { printf "%d", a + b }')
      case "$call_tokens" in ''|*[!0-9]*) call_tokens=0 ;; esac

      lock_dir="$STATE_DIR/.session-${session_id_safe}.lock"
      if acquire_state_lock "$lock_dir"; then
        # Re-read INSIDE the lock. Holding the lock while adding to a value
        # read outside it leaves the race exactly as it was -- the read and the
        # write have to be one indivisible step, and the earlier read was only
        # ever for display.
        read_session_state "$session_state_file"
        cum_tokens="$state_cum"
        # A concurrent render may have recorded this very call while we waited.
        if [ "$sig" != "$state_sig" ]; then
          cum_tokens=$((state_cum + call_tokens))
          # Atomic write: a reader must never see a half-written file. Writing
          # to a per-process temp name then `mv`-ing into place guarantees that
          # -- rename within a directory is a single filesystem operation,
          # never a partial one. This is separate from the lock above: the lock
          # is what makes the update not get lost, the rename is what makes it
          # not get read torn.
          session_tmp="$STATE_DIR/.session-${session_id_safe}.$$.tmp"
          if printf '%s\n%s\n' "$sig" "$cum_tokens" >"$session_tmp" 2>/dev/null; then
            mv -f "$session_tmp" "$session_state_file" 2>/dev/null
          else
            rm -f "$session_tmp" 2>/dev/null
          fi
        fi
        release_lock_if_owned "$lock_dir"
      fi
    fi
  fi
fi

extras=()

if [ -n "$model_name" ]; then
  extras+=("${ORANGE}${model_name}${RESET}")
fi

if [ -n "$tokens_used" ]; then
  # Colour tier and fill fraction share the same 100k reference (see the
  # bar constants above), so a full bar and a red bar mean the same thing.
  bar_tier=$(awk -v n="$tokens_used" -v y="$THRESHOLD_TOKENS_YELLOW" -v o="$THRESHOLD_TOKENS_ORANGE" -v r="$THRESHOLD_TOKENS_RED" \
    'BEGIN { n += 0; if (n < y) print "green"; else if (n < o) print "yellow"; else if (n < r) print "orange"; else print "red" }')
  case "$bar_tier" in
    green)  bar_color="$GREEN" ;;
    yellow) bar_color="$YELLOW" ;;
    orange) bar_color="$ORANGE" ;;
    *)      bar_color="$RED" ;;
  esac
  bar_filled=$(awk -v n="$tokens_used" -v d="$BAR_REFERENCE_TOKENS" -v w="$BAR_WIDTH" \
    'BEGIN { if (d <= 0) { print 0; exit } f = (n / d) * w; if (f < 0) f = 0; if (f > w) f = w; printf "%d", f + 0.5 }')
  # Guards the bash arithmetic just below: an unexpected (non-integer) awk
  # result must degrade to "no bar" rather than throw a syntax error that
  # would abort the script and blank the whole status line.
  case "$bar_filled" in ''|*[!0-9]*) bar_filled=0 ;; esac
  bar_empty=$((BAR_WIDTH - bar_filled))
  # Built with a loop, not `printf '%*s' | tr`: BSD tr (macOS) does not
  # reliably map a single-byte space onto a multi-byte UTF-8 replacement
  # character, so that trick would risk corrupting the bar glyphs here.
  bar=""
  i=0
  while [ $i -lt "$bar_filled" ]; do
    bar="${bar}${BAR_FILL}"
    i=$((i + 1))
  done
  i=0
  while [ $i -lt "$bar_empty" ]; do
    bar="${bar}${BAR_EMPTY}"
    i=$((i + 1))
  done
  tokens_fmt=$(format_k "$tokens_used")
  extras+=("${bar_color}${bar} ${tokens_fmt}${RESET}")
fi

if [ -n "$session_id_safe" ]; then
  cum_fmt=$(format_k "$cum_tokens")
  extras+=("${CYAN}${SIGMA} ${cum_fmt}${RESET}")
fi

# Weekly quota: "⏱ 63% used · resets 2d 4h". The countdown is appended only
# when resets_at parses to a future instant -- a missing, malformed, or
# already-elapsed timestamp degrades to the bare percentage rather than
# showing a stale or negative duration.
if [ -n "$week_used_pct" ]; then
  week_pct_fmt=$(awk -v p="$week_used_pct" 'BEGIN { printf "%d", p + 0.5 }' 2>/dev/null)
  case "$week_pct_fmt" in ''|*[!0-9]*) week_pct_fmt="" ;; esac
  if [ -n "$week_pct_fmt" ]; then
    week_text="${CLOCK_ICON} ${week_pct_fmt}% used"
    if [ -n "$week_resets_at" ]; then
      reset_epoch=$(to_epoch "$week_resets_at")
      case "$reset_epoch" in ''|*[!0-9]*) reset_epoch="" ;; esac
      if [ -n "$reset_epoch" ]; then
        now_epoch=$(date -u '+%s' 2>/dev/null)
        case "$now_epoch" in ''|*[!0-9]*) now_epoch="" ;; esac
        if [ -n "$now_epoch" ] && [ "$reset_epoch" -gt "$now_epoch" ]; then
          week_text="${week_text} · resets $(format_duration $((reset_epoch - now_epoch)))"
        fi
      fi
    fi
    extras+=("${PURPLE}${week_text}${RESET}")
  fi
fi

if [ ${#extras[@]} -gt 0 ]; then
  # Each extra already carries its own colour + reset (see above), so the
  # separator gets its own dim colour rather than wrapping the whole line --
  # nesting DIM outside a segment's own RESET would just get cancelled by
  # that inner RESET and stop applying to anything after the first segment.
  sep="${DIM} │ ${RESET}"
  joined="${extras[0]}"
  i=1
  while [ $i -lt ${#extras[@]} ]; do
    joined="${joined}${sep}${extras[$i]}"
    i=$((i + 1))
  done
  # Leading "│" matches the original divider between the git prompt and the
  # Claude segments (see the "Target look" comment at the top of the file).
  out="${out}  ${DIM}│ ${RESET}${joined}"
fi

printf '%s' "$out"
