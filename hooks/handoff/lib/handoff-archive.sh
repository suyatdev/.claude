#!/usr/bin/env bash
# handoff-archive.sh — shared library for the SessionStart/handoff hooks under
# hooks/handoff/. Pure definitions: sourcing this file runs nothing, prints nothing,
# and exits nothing, and it is safe to source more than once. It does not `set -u` or
# `set -e` on the caller's behalf — the sourcing hook owns its own strict-mode choices.
#
# Sourced today by slim-session-start.sh only. Per docs/features/handoff-trim-safety.md,
# three more consumers are planned: the Stop-hook keep-guard, for gen_tag/sanitize_line;
# and live-handoff.sh plus pre-compact-handoff.sh, for the snapshot and archive functions
# that land here later — hence "hooks" (plural) above. Tasks are named by what they do and
# never by number: that card renumbered once already and states the rule outright, and
# stale number references are a recorded, repeated failure in this repo.
#
# MARKER_PATTERN, TAG_BYTES, URANDOM_SRC, sanitize_line() and gen_tag() below were
# moved verbatim out of slim-session-start.sh by that card's extraction step, so every
# consumer shares one definition of the tamper-evident envelope tag and the marker
# sanitizer, rather than drifting copies.

TAG_BYTES=4
URANDOM_SRC="${SLIM_HANDOFF_URANDOM:-/dev/urandom}"

# Regexes live in variables, never inline in `[[ ]]` — a bare `(` or `;` in an inline
# regex kills bash's parser and a dead script exits non-zero (confirmed by running one).
#
# written lowercase-canonical; nocasematch (not bracket classes) is what makes this
# case-insensitive — see docs/features/memory-system-split.md on why the bracket-class
# fix shipped twice and still missed "=== END HANDOFF ===".
MARKER_PATTERN='^[[:space:]]*===[[:space:]]*(end[[:space:]]+)?handoff'

# Sanitizes one body line: prefixes it with "| " if it could be mistaken for an
# envelope marker, case-insensitively. Never drops a line — a false positive costs
# two characters, not a lost line. Brackets nocasematch tightly around the match and
# restores whatever the caller had set, since it is shell-global state.
sanitize_line() {
  local line="$1" was_on=0
  case "$(shopt -p nocasematch)" in *"-s nocasematch"*) was_on=1 ;; esac
  shopt -s nocasematch
  if [[ "$line" =~ $MARKER_PATTERN ]]; then
    printf '| %s\n' "$line"
  else
    printf '%s\n' "$line"
  fi
  [ "$was_on" -eq 0 ] && shopt -u nocasematch
  return 0
}

# 8 hex chars from $TAG_BYTES bytes of $URANDOM_SRC. Empty input (unreadable source,
# e.g. tests pointing URANDOM_SRC at /dev/null) yields an empty tag on purpose — the
# caller must treat that as "emit nothing," never as "emit an untagged envelope."
gen_tag() {
  head -c "$TAG_BYTES" "$URANDOM_SRC" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n'
}
