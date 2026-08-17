# shellcheck shell=bash
# guard_test_helpers.sh — assertion bodies shared by the hook-level *.test.sh
# suites (git-guard, doc-guard, merge-guard). Sourced, not executed: the
# sourcing script must already define $HOOK, payload(), and the global
# pass/fail counters before calling anything below.
#
# Why this file exists (docs/features/global-option-blindness.md, task 0a):
# every hook-level suite in this repo threw stdout away (git-guard's own
# `2>&1 1>/dev/null`, doc-guard's `>/dev/null 2>&1`), and doc-guard had no
# stderr assertion at all. The new SCOPE_UNKNOWN "ask" decision is delivered
# as JSON on stdout at exit 0 -- exactly the channel nothing here could see.

# Checks stderr only, discarding stdout. Moved here unchanged from
# git-guard.test.sh, where it was written after git-guard.sh already
# rendered the text it checks -- so each call site is only trustworthy once
# proven able to fail (see that suite's mutation-round history). The
# `1>/dev/null` is deliberate: it keeps stdout out of $got entirely rather
# than merging the two streams.
assert_stderr() { # $1 dir, $2 desc, $3 command string, $4 expected substring
  local dir="$1" desc="$2" cmd="$3" want="$4" got
  got="$(cd "$dir" && payload "$cmd" | bash "$HOOK" 2>&1 1>/dev/null)"
  case "$got" in
    *"$want"*) printf 'ok   — %s\n' "$desc"; pass=$((pass+1)) ;;
    *) printf 'FAIL — %s\n  want (substring): %s\n  got:\n%s\n' "$desc" "$want" "$got"; fail=$((fail+1)) ;;
  esac
}

# Checks stdout only, discarding stderr -- the counterpart no suite has had
# until now. Substring match, same as assert_stderr, so it works unchanged
# against the compact single-line JSON git-guard's ask path will emit.
assert_stdout() { # $1 dir, $2 desc, $3 command string, $4 expected substring
  local dir="$1" desc="$2" cmd="$3" want="$4" got
  got="$(cd "$dir" && payload "$cmd" | bash "$HOOK" 2>/dev/null)"
  case "$got" in
    *"$want"*) printf 'ok   — %s\n' "$desc"; pass=$((pass+1)) ;;
    *) printf 'FAIL — %s\n  want (substring): %s\n  got:\n%s\n' "$desc" "$want" "$got"; fail=$((fail+1)) ;;
  esac
}
