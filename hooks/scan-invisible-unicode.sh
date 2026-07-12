#!/usr/bin/env bash
#
# scan-invisible-unicode.sh — reject zero-width and bidirectional-control
# codepoints in source files.
#
# WHY THIS MUST BE A HOOK, NOT A RULE:
#
# This is the one class of defect that human review structurally CANNOT catch.
# A zero-width joiner or a right-to-left override carries no glyph: an
# instruction hidden inside a source file renders as nothing in a diff, nothing
# in a PR review, and nothing in an editor with default settings. A reviewer
# reading carefully and in good faith sees clean code and approves it.
#
# The blast radius is what makes it urgent. These payloads are not merely read
# by an agent — they are *copied* by one. Once an agent ingests a file carrying
# a hidden instruction and begins using that file as a pattern to imitate, it
# replicates the invisible bytes into every file it touches. What starts as one
# poisoned fixture is spread across hundreds of files within minutes, and each
# copy is just as invisible as the original. By the time anything is noticeable
# from behavior, the payload is in the git history in a hundred places.
#
# Detection therefore has to be mechanical and it has to run before the write
# lands. A human cannot see these bytes, so a human cannot be the control. Only
# a byte-level scanner can be.
#
# Usage: scan-invisible-unicode.sh <file> [file...]
#        ... or as a Claude Code PreToolUse hook (reads file_path from stdin JSON).
# Exit:  0 = clean (silent).  2 = invisible codepoint found (blocks the tool call).

set -u

resolve_targets() {
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
    return
  fi
  if [ ! -t 0 ]; then
    sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
  fi
}

# codepoint|name|UTF-8 bytes
read_codepoints() {
  cat <<'CODEPOINTS'
U+200B|ZERO WIDTH SPACE|\xe2\x80\x8b
U+200C|ZERO WIDTH NON-JOINER|\xe2\x80\x8c
U+200D|ZERO WIDTH JOINER|\xe2\x80\x8d
U+2060|WORD JOINER|\xe2\x81\xa0
U+FEFF|BYTE ORDER MARK (mid-file)|\xef\xbb\xbf
U+202A|LEFT-TO-RIGHT EMBEDDING|\xe2\x80\xaa
U+202B|RIGHT-TO-LEFT EMBEDDING|\xe2\x80\xab
U+202C|POP DIRECTIONAL FORMATTING|\xe2\x80\xac
U+202D|LEFT-TO-RIGHT OVERRIDE|\xe2\x80\xad
U+202E|RIGHT-TO-LEFT OVERRIDE|\xe2\x80\xae
U+2066|LEFT-TO-RIGHT ISOLATE|\xe2\x81\xa6
U+2067|RIGHT-TO-LEFT ISOLATE|\xe2\x81\xa7
U+2068|FIRST STRONG ISOLATE|\xe2\x81\xa8
U+2069|POP DIRECTIONAL ISOLATE|\xe2\x81\xa9
CODEPOINTS
}

found=0

while IFS= read -r target; do
  [ -n "$target" ] || continue
  [ -f "$target" ] || continue

  while IFS='|' read -r cp name bytes; do
    [ -n "$cp" ] || continue

    pat=$(printf '%b' "$bytes")

    # -a: treat as text.  -b -o: byte offset of each match.  -F: literal bytes.
    # LC_ALL=C keeps grep byte-oriented so offsets are true byte offsets.
    offsets=$(LC_ALL=C grep -o -b -a -F -e "$pat" -- "$target" 2>/dev/null | cut -d: -f1) || continue
    [ -n "$offsets" ] || continue

    while IFS= read -r off; do
      [ -n "$off" ] || continue
      # A BOM at byte 0 is legitimate; only flag one appearing mid-file.
      if [ "$cp" = "U+FEFF" ] && [ "$off" -eq 0 ]; then
        continue
      fi
      printf '%s: byte offset %s: invisible codepoint %s (%s)\n' "$target" "$off" "$cp" "$name" >&2
      found=1
    done <<EOF
$offsets
EOF
  done <<EOF
$(read_codepoints)
EOF
done <<EOF
$(resolve_targets "$@")
EOF

if [ "$found" -ne 0 ]; then
  printf 'scan-invisible-unicode: hidden codepoints detected — write blocked.\n' >&2
  printf 'These are invisible in a diff. Strip them before proceeding.\n' >&2
  exit 2
fi

exit 0
