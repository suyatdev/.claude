#!/usr/bin/env bash
# terminal-detect.test.sh — run: bash panes/terminal-detect.test.sh
set -u
DETECT="$(cd "$(dirname "$0")" && pwd)/terminal-detect.sh"
pass=0; fail=0
run_case() { # $1 desc, $2 want, then env pairs as VAR=VAL...
  local desc="$1" want="$2"; shift 2
  local got
  got=$(env -i HOME="$HOME" PATH="$PATH" "$@" bash "$DETECT")
  if [ "$got" = "$want" ]; then printf 'ok   — %s -> %s\n' "$desc" "$got"; pass=$((pass+1))
  else printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1)); fi
}
run_case "cmux env"                 cmux     CMUX_PANEL_ID=abc
run_case "tmux env"                 tmux     TMUX=/tmp/sock,1,0
run_case "iTerm2"                   iterm    TERM_PROGRAM=iTerm.app
run_case "Terminal.app"             terminal TERM_PROGRAM=Apple_Terminal
run_case "nothing set"              none
run_case "unknown TERM_PROGRAM"     none     TERM_PROGRAM=ghostty
run_case "cmux beats tmux"          cmux     CMUX_PANEL_ID=abc TMUX=/tmp/sock,1,0
run_case "cmux beats TERM_PROGRAM"  cmux     CMUX_PANEL_ID=abc TERM_PROGRAM=ghostty
run_case "tmux beats TERM_PROGRAM"  tmux     TMUX=/tmp/sock,1,0 TERM_PROGRAM=iTerm.app
printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
