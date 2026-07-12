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
# Usage: scan-secrets.sh <file> [file...]
#        ... or as a Claude Code PreToolUse hook (reads file_path from stdin JSON).
# Exit:  0 = clean (silent).  2 = credential found (blocks the tool call).

set -u

# Resolve the target file(s): explicit args win, otherwise pull file_path out of
# the PreToolUse JSON payload on stdin.
resolve_targets() {
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
    return
  fi
  if [ ! -t 0 ]; then
    sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
  fi
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

while IFS= read -r target; do
  [ -n "$target" ] || continue
  [ -f "$target" ] || continue

  while IFS='|' read -r name flags regex; do
    [ -n "$name" ] || continue

    # shellcheck disable=SC2086 # $flags is an intentional multi-flag word
    hits=$(grep $flags -e "$regex" -- "$target" 2>/dev/null | cut -d: -f1) || continue
    [ -n "$hits" ] || continue

    while IFS= read -r lineno; do
      [ -n "$lineno" ] || continue
      printf '%s:%s: possible secret [%s]\n' "$target" "$lineno" "$name" >&2
      found=1
    done <<EOF
$hits
EOF
  done <<EOF
$(read_patterns)
EOF
done <<EOF
$(resolve_targets "$@")
EOF

if [ "$found" -ne 0 ]; then
  printf 'scan-secrets: credential material detected — write blocked.\n' >&2
  printf 'If this is a false positive, fix the pattern or move the value to an env var.\n' >&2
  exit 2
fi

exit 0
