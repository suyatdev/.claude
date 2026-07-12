#!/usr/bin/env bash
#
# scan-secrets.sh — block writes that introduce credential material.
#
# Why this is a hook and not an instruction: "never commit secrets" is the most
# repeated rule in every codebase and still the most violated one. An instruction
# is advisory — a long session, a compacted context, or a confidently-wrong model
# will drop it. A hook cannot be talked out of it.
#
# Reports file, line number, and the NAME of the pattern that fired. It never
# echoes the matched text: printing the secret into stderr, a transcript, or a
# log is the leak we are trying to prevent.
#
# TWO MODES — and the difference is the whole point:
#
#   Hook mode (no args; PreToolUse JSON on stdin)
#     Scans the content the tool is ABOUT TO WRITE: `tool_input.content` (Write),
#     `tool_input.new_string` (Edit), `tool_input.edits[].new_string` (MultiEdit).
#     PreToolUse fires BEFORE the write lands, so the file on disk does not exist
#     yet (Write) or still holds the pre-edit text (Edit). Scanning the path would
#     certify the wrong bytes and pass every secret through. The payload is the
#     only place the new content exists at the moment the decision has to be made.
#
#   CLI mode (file paths as args)
#     Scans those files on disk. For pre-commit hooks and manual sweeps, where the
#     content has already landed and the file IS the artifact.
#
# Usage: scan-secrets.sh <file> [file...]      # CLI mode
#        <payload.json scan-secrets.sh         # hook mode
# Exit:  0 = clean (silent).
#        2 = credential found, OR the payload could not be read (see below).
#
# Fails CLOSED: an unparseable payload, or a missing python3, blocks the write and
# says why. A scanner that cannot see the content cannot certify it, and a security
# control that waves through what it failed to inspect manufactures confidence it
# has not earned.

set -u

TMPROOT=""
cleanup() { [ -n "$TMPROOT" ] && rm -rf -- "$TMPROOT"; }
trap cleanup EXIT

die_unreadable() {
  printf 'scan-secrets: %s\n' "$1" >&2
  printf 'The content being written could not be inspected, so it cannot be certified clean — write blocked.\n' >&2
  exit 2
}

# name|grep flags|extended regex
read_patterns() {
  cat <<'PATTERNS'
AWS access key id|-nE|AKIA[0-9A-Z]{16}
Private key header|-nE|-----BEGIN [A-Z ]*PRIVATE KEY-----
Generic API key assignment|-niE|api[_-]?key[[:space:]]*[:=][[:space:]]*["'][^"']{16,}["']
Bearer token|-niE|bearer[[:space:]]+[A-Za-z0-9._~+/-]{16,}
Password assignment|-niE|password[[:space:]]*[:=][[:space:]]*["'][^"']+["']
PATTERNS
}

found=0

# scan_one <label> <file-holding-the-bytes>
# The label is what gets reported; in hook mode the bytes live in a temp file but
# the operator needs to see the destination path, not the temp path.
scan_one() {
  label=$1
  file=$2

  while IFS='|' read -r name flags regex; do
    [ -n "$name" ] || continue

    # shellcheck disable=SC2086 # $flags is an intentional multi-flag word
    hits=$(grep $flags -e "$regex" -- "$file" 2>/dev/null | cut -d: -f1) || continue
    [ -n "$hits" ] || continue

    while IFS= read -r lineno; do
      [ -n "$lineno" ] || continue
      printf '%s:%s: possible secret [%s]\n' "$label" "$lineno" "$name" >&2
      found=1
    done <<EOF
$hits
EOF
  done <<EOF
$(read_patterns)
EOF
}

# Reads $TMPROOT/payload.json, writes each string the tool is about to commit into
# its own segment file, and prints "label<TAB>segment-path" lines.
#
# A real JSON parser is mandatory here, not a sed one-liner: the payload arrives
# escaped, so a secret can reach the file through \n, \", or \uXXXX sequences that
# a text-level extractor never resolves.
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

segments = []
for key in ("content", "new_string"):
    value = tool_input.get(key)
    if isinstance(value, str) and value:
        segments.append((path, value))

edits = tool_input.get("edits")       # MultiEdit
if isinstance(edits, list):
    for i, edit in enumerate(edits, 1):
        if isinstance(edit, dict):
            value = edit.get("new_string")
            if isinstance(value, str) and value:
                segments.append(("%s (edit %d)" % (path, i), value))

for i, (label, text) in enumerate(segments):
    seg = os.path.join(tmproot, "segment-%d" % i)
    with open(seg, "wb") as fh:
        fh.write(text.encode("utf-8"))
    sys.stdout.write("%s\t%s\n" % (label, seg))
PY

  rc=$?
  [ "$rc" -eq 3 ] && die_unreadable 'the payload on stdin is not valid JSON'
  [ "$rc" -eq 0 ] || die_unreadable "the payload parser exited $rc"
}

if [ "$#" -gt 0 ]; then
  for target in "$@"; do
    [ -n "$target" ] || continue
    if [ ! -f "$target" ]; then
      printf 'scan-secrets: no such file: %s\n' "$target" >&2
      continue
    fi
    scan_one "$target" "$target"
  done
elif [ ! -t 0 ]; then
  TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/scan-secrets.XXXXXX") || die_unreadable 'could not create a temp directory'
  cat > "$TMPROOT/payload.json" || die_unreadable 'could not read the payload from stdin'

  # Not a command substitution: die_unreadable must be able to exit the real shell.
  extract_segments > "$TMPROOT/segments.tsv"

  while IFS=$'\t' read -r label seg; do
    [ -n "${seg:-}" ] || continue
    scan_one "$label" "$seg"
  done < "$TMPROOT/segments.tsv"
fi

if [ "$found" -ne 0 ]; then
  printf 'scan-secrets: credential material detected — write blocked.\n' >&2
  printf 'If this is a false positive, fix the pattern or move the value to an env var.\n' >&2
  exit 2
fi

exit 0
