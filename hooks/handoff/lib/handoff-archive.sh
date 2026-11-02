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

# ==========================================================================================
# Everything below was added by the step of docs/features/handoff-trim-safety.md that grows
# this file from the extraction above into the full library the card calls for: snapshot,
# [KEEP] region extraction with fence tracking, protected-line membership, archive append,
# rotation, secret flagging, quarantine. Named by what it does and never by number — that
# card renumbers, states the rule outright, and enforces it with a search over both halves.
#
# Pure library, same contract as above: no hook wiring lives here, sourcing this file still
# runs nothing and prints nothing. The functions below are called by future consumers
# (live-handoff.sh, pre-compact-handoff.sh, the Stop-hook keep-guard) that this task does
# not touch.
# ==========================================================================================

ARCHIVE_ROTATE_AT_BYTES=1048576

# Resolved from THIS file's own location, exactly like slim-session-start.sh's HOOK_DIR
# above it — never $PWD and never `git rev-parse`, because the test suite sources this
# library from throwaway trees elsewhere on disk. Overridable so tests can point it at a
# stub, a broken binary, or nothing at all without touching the real scanner.
SCAN_SECRETS_CMD="${HANDOFF_SCAN_SECRETS_CMD:-$(dirname -- "${BASH_SOURCE[0]}")/../../scan-secrets.sh}"

# snapshot_notepad SRC DEST — an atomic, byte-identical copy. Writes to a temp path beside
# DEST (same directory, so the final `mv` is a same-filesystem rename, not a cross-device
# copy) and moves it into place, so a failure partway through never leaves a truncated file
# at DEST that a caller could mistake for a real snapshot. rc 0 on success; non-zero on any
# failure (unreadable SRC, a DEST directory that does not exist or is not writable). Silent
# on stdout in every case; any diagnostic from cp/mv is discarded, matching this library's
# existing failures being signalled by rc alone.
snapshot_notepad() {
  local src="$1" dest="$2" tmp

  [ -r "$src" ] || return 1

  tmp="$(mktemp "${dest}.XXXXXX" 2>/dev/null)" || return 1
  if ! cp -- "$src" "$tmp" 2>/dev/null; then
    rm -f -- "$tmp" 2>/dev/null
    return 1
  fi
  if ! mv -- "$tmp" "$dest" 2>/dev/null; then
    rm -f -- "$tmp" 2>/dev/null
    return 1
  fi
  return 0
}

# extract_keep_lines FILE — prints every line of every [KEEP] region in FILE to stdout,
# heading line included, in file order. One awk pass with explicit fence-state variables
# (`fence`/`fchar`/`flen`), per the house rule that region extraction needs one pass with
# state that `grep` cannot carry.
#
# Grammar (docs/features/handoff-trim-safety.spec.md, "[KEEP] marker (D13) -- full
# grammar"):
#   - ATX headings only: ^#{1,6}[[:space:]].*\[KEEP\][[:space:]]*$ opens a region; any
#     ATX heading (with or without the tag) ends the region that came before it.
#   - Setext headings (a text line underlined with === or ---) are NOT supported and are
#     never specially recognized here -- they simply never match the ATX pattern above, so
#     they fall straight through to "ordinary body," neither opening nor closing anything.
#     No separate state is needed to implement that: it falls out of matching only the ATX
#     form.
#   - Fence tracking runs before any line is tested as a heading. An opening fence is three
#     or more backticks or tildes, indented at most three spaces. A closing fence must use
#     the SAME character and be AT LEAST AS LONG as the opening one -- a tilde run never
#     closes a backtick fence, and a shorter run of the same character never closes a
#     longer one. A heading (KEEP-tagged or not) inside an open fence neither opens nor
#     closes a region, in either direction.
#   - YAML front matter (a literal "---" on line 1 through the next literal "---") is
#     skipped before any of the above runs.
#   - An indented code block (four or more leading spaces, or a leading tab) is body, not a
#     heading. This needs no separate tracking either: the heading regex above has no
#     leading-whitespace tolerance at all, so an indented "#..." line already never matches
#     it, blank line before it or not.
#
# The {n,m} interval expressions below were measured against THIS machine's /usr/bin/awk
# (the BWK "one true awk" Apple ships, confirmed a real Mach-O binary, not a gawk symlink)
# before being relied on here -- `/^[ ]{0,3}`+/` and dynamic `"{" n ",}"` patterns were run
# directly and matched exactly as ERE intervals should. Do not assume this on a machine
# that has not been measured; count characters with substr/loops instead if it turns out
# not to hold there.
#
# Also measured: this awk does NOT treat `--` as an end-of-options marker (it tried to
# open a file literally named `--` and failed), unlike GNU tools, so the call below passes
# FILE directly with no `--` guard against a dash-leading filename.
extract_keep_lines() {
  local file="$1"
  awk '
    {
      line = $0

      # --- YAML front matter: only recognized when line 1 is exactly "---" ------------
      if (first_line == 0) {
        first_line = 1
        if (line == "---") { front = 1; next }
      } else if (front == 1) {
        if (line == "---") { front = 0 }
        next
      }

      # --- Fence tracking, before any heading test -------------------------------------
      if (fence == 0) {
        if (match(line, /^[ ]{0,3}`{3,}/) > 0) {
          full = substr(line, RSTART, RLENGTH)
          cnt = gsub(/`/, "`", full)
          fence = 1; fchar = "`"; flen = cnt
          if (keep == 1) print line
          next
        }
        if (match(line, /^[ ]{0,3}~{3,}/) > 0) {
          full = substr(line, RSTART, RLENGTH)
          cnt = gsub(/~/, "~", full)
          fence = 1; fchar = "~"; flen = cnt
          if (keep == 1) print line
          next
        }
      } else {
        closepat = "^[ ]{0,3}" fchar "{" flen ",}[ \t]*$"
        if (line ~ closepat) { fence = 0 }
        if (keep == 1) print line
        next
      }

      # --- Not in a fence, not front matter: test as an ATX heading --------------------
      if (line ~ /^#{1,6}[[:space:]]/) {
        if (line ~ /^#{1,6}[[:space:]].*\[KEEP\][[:space:]]*$/) {
          keep = 1
          print line
        } else {
          keep = 0
        }
        next
      }

      if (keep == 1) print line
    }
  ' "$file"
}

# missing_protected_lines SNAPSHOT CURRENT — prints, to stdout, the protected lines from
# SNAPSHOT that are absent from CURRENT. rc 0 when none are missing, rc 1 when some are.
#
# Protected set = every [KEEP]-region line of SNAPSHOT (heading included), blank lines
# excluded, trailing whitespace stripped, deduplicated (SET membership: a line appearing
# twice in the snapshot needs to survive once, not twice).
#
# Matching is `grep -F -x` -- fixed-string, whole-line -- never a regex: a notepad line
# routinely contains regex metacharacters (`.`, `*`, `[`, `$`, `(`...) and a non-fixed
# match would both false-pass a deleted line and be influenceable by the file under test.
# A CURRENT file that does not exist at all is treated as empty, so every protected line
# reports missing.
missing_protected_lines() {
  local snapshot="$1" current="$2"
  local protected_tmp current_tmp missing_count line

  protected_tmp="$(mktemp)" || return 1
  current_tmp="$(mktemp)" || { rm -f -- "$protected_tmp"; return 1; }

  if [ -f "$snapshot" ] && [ -r "$snapshot" ]; then
    extract_keep_lines "$snapshot" \
      | sed 's/[[:space:]]*$//' \
      | awk 'length($0) > 0 && !seen[$0]++' > "$protected_tmp"
  fi

  if [ -f "$current" ] && [ -r "$current" ]; then
    sed 's/[[:space:]]*$//' "$current" > "$current_tmp"
  fi

  missing_count=0
  while IFS= read -r line || [ -n "$line" ]; do
    if ! grep -F -x -q -- "$line" "$current_tmp" 2>/dev/null; then
      printf '%s\n' "$line"
      missing_count=$((missing_count + 1))
    fi
  done < "$protected_tmp"

  rm -f -- "$protected_tmp" "$current_tmp"
  [ "$missing_count" -eq 0 ]
}

# archive_rotate_if_needed ARCHIVE_PATH PENDING_BYTES — rotates ARCHIVE_PATH when its
# current size plus PENDING_BYTES would exceed ARCHIVE_ROTATE_AT_BYTES (strictly greater
# than; exactly at the threshold does not rotate). Rotation renames ARCHIVE_PATH to
# <prefix>.<N>.md, where <prefix> is ARCHIVE_PATH's own basename with a trailing ".md"
# stripped, and N is one above the highest existing rotation number, tolerating gaps
# (given .1. and .4., the new name is .5.). A rename never loses a byte -- this is `mv`,
# not copy-then-delete. rc 0 when no rotation was needed or the rotation succeeded;
# non-zero if the rotation itself fails, or if either size argument cannot be read as a
# non-negative integer.
#
# No ARCHIVE_PATH yet (first-ever append) is not a failure: there is nothing to rotate.
archive_rotate_if_needed() {
  local archive_path="$1" pending_bytes="$2"
  local current_size total dir base prefix highest f fbase num n candidate

  [ -f "$archive_path" ] || return 0

  current_size="$(wc -c < "$archive_path" 2>/dev/null | tr -d ' ')"
  case "$current_size" in ''|*[!0-9]*) return 1 ;; esac
  case "$pending_bytes" in ''|*[!0-9]*) return 1 ;; esac

  total=$(( current_size + pending_bytes ))
  [ "$total" -le "$ARCHIVE_ROTATE_AT_BYTES" ] && return 0

  dir="$(dirname -- "$archive_path")"
  base="$(basename -- "$archive_path")"
  case "$base" in
    *.md) prefix="${base%.md}" ;;
    *) prefix="$base" ;;
  esac

  highest=0
  for f in "$dir/$prefix".*.md; do
    [ -e "$f" ] || continue
    fbase="$(basename -- "$f")"
    num="${fbase#"$prefix".}"
    num="${num%.md}"
    case "$num" in ''|*[!0-9]*) continue ;; esac
    [ "$num" -gt "$highest" ] && highest=$num
  done

  n=$(( highest + 1 ))
  candidate="$dir/$prefix.$n.md"

  mv -- "$archive_path" "$candidate" 2>/dev/null
}

# block_has_secret LINES_FILE — rc 0 when LINES_FILE looks like credential material, rc 1
# when it is clean. Runs $SCAN_SECRETS_CMD (hooks/scan-secrets.sh's CLI mode) over the
# file; that mode exits 2 on a hit, 0 on clean. Both stdout (normally empty in CLI mode)
# and stderr are discarded here -- the caller gets a boolean, never the scanner's own
# diagnostic text, so this function's own stderr always stays clean.
#
# Fails CLOSED: a scanner that is missing, not executable, or exits with anything other
# than 0 or 2 gets treated as a hit. A scanner that cannot see the content cannot certify
# it, and archiving on an uncertain scan is exactly the risk this function exists to
# remove.
block_has_secret() {
  local lines_file="$1" rc

  [ -x "$SCAN_SECRETS_CMD" ] || return 0

  "$SCAN_SECRETS_CMD" "$lines_file" >/dev/null 2>/dev/null
  rc=$?

  case "$rc" in
    0) return 1 ;;   # clean
    2) return 0 ;;   # credential material found
    *) return 0 ;;   # unexpected exit: fail closed, treat as flagged
  esac
}

# secret_labels LINES_FILE — prints the pattern NAMES $SCAN_SECRETS_CMD reported against
# LINES_FILE (the "[Name]" part of its "path:lineno: possible secret [Name]" stderr
# lines), deduplicated, comma-separated. Never prints the matched text (scan-secrets.sh
# itself never emits it either) and never prints LINES_FILE's own path -- reporting either
# one would be the exact leak this function exists to prevent from reaching the archive or
# a block-reason message.
secret_labels() {
  local lines_file="$1" err_tmp

  [ -x "$SCAN_SECRETS_CMD" ] || return 0

  err_tmp="$(mktemp)" || return 1
  "$SCAN_SECRETS_CMD" "$lines_file" >/dev/null 2>"$err_tmp"

  sed -n 's/.*possible secret \[\(.*\)\]$/\1/p' "$err_tmp" \
    | awk '!seen[$0]++' \
    | paste -sd, -

  rm -f -- "$err_tmp"
}

# quarantine_block QUARANTINE_PATH LINES_FILE HEADING_TEXT — appends HEADING_TEXT followed
# by the verbatim content of LINES_FILE to QUARANTINE_PATH. rc non-zero on any write
# failure.
quarantine_block() {
  local quarantine_path="$1" lines_file="$2" heading_text="$3" ok=1

  { printf '%s\n' "$heading_text"; cat -- "$lines_file"; } >> "$quarantine_path" 2>/dev/null || ok=0

  [ "$ok" -eq 1 ]
}

# archive_append ARCHIVE_PATH HEADING_TEXT LINES_FILE — rotates ARCHIVE_PATH first (using
# the size of what is about to be written as the pending size), then appends HEADING_TEXT
# followed by the verbatim content of LINES_FILE. rc non-zero on ANY write failure --
# callers depend on this to know not to delete a snapshot whose text did not actually make
# it to disk anywhere else.
archive_append() {
  local archive_path="$1" heading_text="$2" lines_file="$3"
  local lines_bytes pending ok=1

  lines_bytes=0
  if [ -f "$lines_file" ]; then
    lines_bytes="$(wc -c < "$lines_file" 2>/dev/null | tr -d ' ')"
    case "$lines_bytes" in ''|*[!0-9]*) lines_bytes=0 ;; esac
  fi
  # +1 for the heading's own trailing newline. ${#heading_text} is a character, not a
  # byte, count -- headings here are ISO8601 timestamps, session ids and ASCII prose, so
  # this is exact in the cases that matter and only ever over-estimates otherwise, which
  # can only rotate a little earlier than strictly necessary, never lose a byte.
  pending=$(( ${#heading_text} + 1 + lines_bytes ))

  archive_rotate_if_needed "$archive_path" "$pending" || return 1

  { printf '%s\n' "$heading_text"; cat -- "$lines_file"; } >> "$archive_path" 2>/dev/null || ok=0

  [ "$ok" -eq 1 ]
}

# file_removed_block ARCHIVE_PATH QUARANTINE_PATH LINES_FILE SESSION_ID — the orchestrator
# for a mechanically-removed block. Runs the secret check; a clean block is appended to
# the archive under an "Auto-captured" heading naming the ISO8601 UTC time, the session,
# the line count and "secrets: none". A flagged block is written verbatim to
# QUARANTINE_PATH instead (never the archive), and the archive instead gets a heading-only
# stub recording that a block was quarantined and naming the pattern labels -- so one
# flagged block never removes the whole archive file from the index (finding C9's "one
# false positive silently removes the entire archive from search").
#
# A block the model files by hand uses a "## Filed by session <iso>" heading instead
# (a later task's concern, not written here) -- deliberately a different literal prefix
# from both headings below, so the two are distinguishable on sight and by grep.
file_removed_block() {
  local archive_path="$1" quarantine_path="$2" lines_file="$3" session_id="$4"
  local iso n labels heading empty_tmp rc

  iso="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" || return 1
  n="$(awk 'END { print NR }' "$lines_file" 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac

  if block_has_secret "$lines_file"; then
    labels="$(secret_labels "$lines_file")"
    heading="## Quarantined ${iso} (session ${session_id}, ${n} lines, secrets: ${labels})"
    quarantine_block "$quarantine_path" "$lines_file" "$heading" || return 1

    heading="## Auto-captured ${iso} (session ${session_id}, ${n} lines, secrets: quarantined -- ${labels})"
    empty_tmp="$(mktemp)" || return 1
    archive_append "$archive_path" "$heading" "$empty_tmp"
    rc=$?
    rm -f -- "$empty_tmp"
    [ "$rc" -eq 0 ] || return 1
  else
    heading="## Auto-captured ${iso} (session ${session_id}, ${n} lines, secrets: none)"
    archive_append "$archive_path" "$heading" "$lines_file" || return 1
  fi

  return 0
}
