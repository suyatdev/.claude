#!/usr/bin/env bash
# secret-filename-fold.probe.sh -- sources every number
# docs/features/secret-filename-case-blindness.md states about folding
# hooks/lib/classify-secret-command.py's DOTFILE_PATTERNS case-insensitive.
#
# WHY THIS EXISTS. Three earlier rounds of that card each shipped a confident
# table built on a population with a hole: variant spellings derived from a
# pattern's human label rather than its regex source (an empty case-count row
# for the Application Support pattern, printing identically to a passing
# row); substitutions applied only at the first occurrence of a letter; and
# only single substitutions, never two homoglyphs in one name. This probe is
# the replacement the card's task 3 requires, ordered ahead of the code
# change (task 5) so it can reproduce the "before" numbers that justified the
# decision.
#
# TWO-ORACLE STRUCTURE. Filesystem ground truth comes from decoy files
# written under a fresh tempfile.mkdtemp() scratch directory; guard verdict
# comes from hooks/lib/classify-secret-command.py's own DOTFILE_PATTERNS,
# imported rather than retyped. The two never check each other.
#
# It never creates, reads, or names a real secret-bearing file -- no
# ~/.zshrc, ~/.terminal_aliases, .env, credentials.json. Only literal-derived
# candidate spellings, written under a scratch directory removed on exit.
#
# It is a PROBE, not a test: it prints measurements and does not assert or
# fix anything. The suite that asserts is hooks/secret-command-guard.test.sh.
#
# Run: hooks/secret-filename-fold.probe.sh   (from anywhere; no arguments)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

exec python3 "$HERE/lib/secret-filename-fold-probe.py" "$REPO"
