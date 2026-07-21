#!/usr/bin/env bash
# terminal-detect.sh — print exactly one of: cmux | tmux | iterm | terminal | none.
#
# Priority order is load-bearing: cmux embeds Ghostty and sets
# TERM_PROGRAM=ghostty, so CMUX_PANEL_ID must win over TERM_PROGRAM; tmux can
# run inside anything, so $TMUX beats TERM_PROGRAM too. `none` covers SSH,
# headless, and unknown terminals — callers then keep today's in-process path.
set -u
if [ -n "${CMUX_PANEL_ID:-}" ]; then echo cmux; exit 0; fi
if [ -n "${TMUX:-}" ]; then echo tmux; exit 0; fi
case "${TERM_PROGRAM:-}" in
  iTerm.app)      echo iterm ;;
  Apple_Terminal) echo terminal ;;
  *)              echo none ;;
esac
