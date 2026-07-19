#!/bin/bash
# Approximates the oh-my-zsh "robbyrussell" prompt theme for the Claude Code statusline.
# No PS1 was found in the user's shell config, so this reconstructs the look using
# data Claude Code provides via stdin JSON.
#
# Target look: "➜  <user>@<host> <dir> git:(<branch>) ✗  │ <model> │ <used> tokens"
# The ✗ dirty marker only appears when the working tree has uncommitted changes;
# clean repos show no marker, matching robbyrussell's ZSH_THEME_GIT_PROMPT_CLEAN.
# The "│ <model> │ <used> tokens" tail is dimmed/secondary and sourced from the
# statusline JSON (.model.display_name, .context_window.total_input_tokens --
# the tokens currently occupying the context window); each segment -- and its
# separator -- is silently omitted when its field is absent or null (e.g.
# before the first API response of a session).

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
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
# The $PWD fallback must be applied BEFORE the strip, not after. $PWD is just as
# external as the JSON -- it is the name of whatever directory the shell is in --
# and stdin without a usable cwd is routine, not exotic: {}, malformed JSON,
# {"cwd":null} and {"workspace":{}} all land here.
[ -z "$cwd" ] && cwd="$PWD"
cwd="${cwd//[[:cntrl:]]/}"

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

dir=$(basename "$cwd")
user=$(whoami)
host=$(hostname -s)

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

# --- Claude-specific segments (dim/grey, secondary to the git prompt) ---
model_name=$(echo "$input" | jq -r '.model.display_name // empty')
model_name="${model_name//[[:cntrl:]]/}"
tokens_used=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
tokens_used="${tokens_used//[[:cntrl:]]/}"

extras=()
[ -n "$model_name" ] && extras+=("$model_name")
if [ -n "$tokens_used" ]; then
  # Render as "113.3k tokens" above 1000, otherwise the raw count. awk (not
  # bash arithmetic) does both the comparison and the formatting so this
  # can't choke if total_input_tokens ever arrives as a non-integer number.
  tokens_fmt=$(awk -v n="$tokens_used" 'BEGIN { if (n >= 1000) printf "%.1fk", n / 1000; else printf "%d", n }' 2>/dev/null)
  [ -n "$tokens_fmt" ] && extras+=("${tokens_fmt} tokens")
fi

if [ ${#extras[@]} -gt 0 ]; then
  joined="${extras[0]}"
  i=1
  while [ $i -lt ${#extras[@]} ]; do
    joined="${joined} │ ${extras[$i]}"
    i=$((i + 1))
  done
  out="${out}  ${DIM}│ ${joined}${RESET}"
fi

printf '%s' "$out"
