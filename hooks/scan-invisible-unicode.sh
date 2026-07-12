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
# TWO MODES — and the difference is the whole point:
#
#   Hook mode (no args; PreToolUse JSON on stdin)
#     Scans the content the tool is ABOUT TO WRITE: `tool_input.content` (Write),
#     `tool_input.new_string` (Edit), `tool_input.edits[].new_string` (MultiEdit).
#     PreToolUse fires BEFORE the write lands, so the file on disk does not exist
#     yet (Write) or still holds the pre-edit text (Edit). Scanning the path would
#     certify the wrong bytes and pass every hidden payload through. Reported byte
#     offsets are offsets into the payload string being written.
#
#   CLI mode (file paths as args)
#     Scans those files on disk. For pre-commit hooks and manual sweeps. Byte
#     offsets are offsets into the file.
#
# Usage: scan-invisible-unicode.sh <file> [file...]    # CLI mode
#        <payload.json scan-invisible-unicode.sh       # hook mode
# Exit:  0 = clean (silent).
#        2 = invisible codepoint found, OR the payload could not be read.
#
# Fails CLOSED: an unparseable payload, or a missing python3, blocks the write and
# says why. A scanner that cannot see the bytes cannot certify them.

set -u

TMPROOT=""
cleanup() { [ -n "$TMPROOT" ] && rm -rf -- "$TMPROOT"; }
trap cleanup EXIT

die_unreadable() {
  printf 'scan-invisible-unicode: %s\n' "$1" >&2
  printf 'The content being written could not be inspected, so it cannot be certified clean — write blocked.\n' >&2
  exit 2
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

# scan_one <label> <file-holding-the-bytes> <bom-at-offset-0-is-legitimate: 1|0>
#
# A BOM at byte 0 of a whole file (CLI mode) or of a whole-file Write is legitimate.
# A BOM at offset 0 of an *edit fragment* is not — that fragment is being spliced
# into the middle of an existing file — so the exemption is passed in, not assumed.
scan_one() {
  label=$1
  file=$2
  bom_ok=$3

  while IFS='|' read -r cp name bytes; do
    [ -n "$cp" ] || continue

    pat=$(printf '%b' "$bytes")

    # -a: treat as text.  -b -o: byte offset of each match.  -F: literal bytes.
    # LC_ALL=C keeps grep byte-oriented so offsets are true byte offsets.
    offsets=$(LC_ALL=C grep -o -b -a -F -e "$pat" -- "$file" 2>/dev/null | cut -d: -f1) || continue
    [ -n "$offsets" ] || continue

    while IFS= read -r off; do
      [ -n "$off" ] || continue
      if [ "$cp" = "U+FEFF" ] && [ "$off" -eq 0 ] && [ "$bom_ok" -eq 1 ]; then
        continue
      fi
      printf '%s: byte offset %s: invisible codepoint %s (%s)\n' "$label" "$off" "$cp" "$name" >&2
      found=1
    done <<EOF
$offsets
EOF
  done <<EOF
$(read_codepoints)
EOF
}

# Reads $TMPROOT/payload.json, writes each string the tool is about to commit into
# its own segment file, and prints "label<TAB>segment-path<TAB>bom_ok" lines.
#
# A real JSON parser is mandatory here, and doubly so for this scanner: a zero-width
# codepoint is routinely carried in the payload as a six-character \u-escape, which is
# plain ASCII on the wire. A byte-level or sed-based extractor sees six harmless
# characters and reports the content clean — the exact failure this hook exists to
# prevent. Only a JSON decode turns the escape back into the bytes to be scanned.
#
# The segment file holds the decoded string as raw UTF-8, so a byte offset into it is
# a byte offset into the payload string.
extract_segments() {
  py=$(command -v python3 || command -v python) || py=""
  [ -n "$py" ] || die_unreadable 'python3 is not on PATH (required to parse the hook payload)'

  "$py" - "$TMPROOT" <<'PY'
import json, os, sys

tmproot = sys.argv[1]
raw = open(os.path.join(tmproot, "payload.json"), "rb").read().decode("utf-8", "replace")

if not raw.strip():
    sys.exit(0)                      # nothing on stdin — nothing to scan

try:
    payload = json.loads(raw)
except ValueError:
    sys.exit(3)                      # cannot parse => cannot certify => caller blocks

tool_input = payload.get("tool_input")
if not isinstance(tool_input, dict):
    sys.exit(0)                      # not a Write/Edit shape — nothing to scan

path = tool_input.get("file_path") or "<write payload>"

# (label, text, bom_at_zero_is_legitimate)
segments = []

content = tool_input.get("content")   # Write: the whole file
if isinstance(content, str) and content:
    segments.append((path, content, 1))

new_string = tool_input.get("new_string")   # Edit: a fragment spliced into a file
if isinstance(new_string, str) and new_string:
    segments.append((path, new_string, 0))

edits = tool_input.get("edits")        # MultiEdit
if isinstance(edits, list):
    for i, edit in enumerate(edits, 1):
        if isinstance(edit, dict):
            value = edit.get("new_string")
            if isinstance(value, str) and value:
                segments.append(("%s (edit %d)" % (path, i), value, 0))

for i, (label, text, bom_ok) in enumerate(segments):
    seg = os.path.join(tmproot, "segment-%d" % i)
    with open(seg, "wb") as fh:
        fh.write(text.encode("utf-8"))
    sys.stdout.write("%s\t%s\t%d\n" % (label, seg, bom_ok))
PY

  rc=$?
  [ "$rc" -eq 3 ] && die_unreadable 'the payload on stdin is not valid JSON'
  [ "$rc" -eq 0 ] || die_unreadable "the payload parser exited $rc"
}

if [ "$#" -gt 0 ]; then
  for target in "$@"; do
    [ -n "$target" ] || continue
    if [ ! -f "$target" ]; then
      printf 'scan-invisible-unicode: no such file: %s\n' "$target" >&2
      continue
    fi
    scan_one "$target" "$target" 1
  done
elif [ ! -t 0 ]; then
  TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/scan-unicode.XXXXXX") || die_unreadable 'could not create a temp directory'
  cat > "$TMPROOT/payload.json" || die_unreadable 'could not read the payload from stdin'

  # Not a command substitution: die_unreadable must be able to exit the real shell.
  extract_segments > "$TMPROOT/segments.tsv"

  while IFS=$'\t' read -r label seg bom_ok; do
    [ -n "${seg:-}" ] || continue
    scan_one "$label" "$seg" "${bom_ok:-0}"
  done < "$TMPROOT/segments.tsv"
fi

if [ "$found" -ne 0 ]; then
  printf 'scan-invisible-unicode: hidden codepoints detected — write blocked.\n' >&2
  printf 'These are invisible in a diff. Strip them before proceeding.\n' >&2
  exit 2
fi

exit 0
