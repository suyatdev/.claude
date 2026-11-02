# shellcheck shell=bash
# 20-constants-and-fence.sh — sourced by ../handoff-archive.test.sh — not runnable on its own.
# Covers ARCHIVE_ROTATE_AT_BYTES/SCAN_SECRETS_CMD constants and [KEEP] region fence tracking (uses call_lib/SCRATCH_ERR/REAL_SCANNER from the entry file setup).

# --- Constants: ARCHIVE_ROTATE_AT_BYTES and SCAN_SECRETS_CMD --------------------------
CONST_OUT="$(bash -c 'set -u; source "$1"; printf "%s\n%s\n" "$ARCHIVE_ROTATE_AT_BYTES" "$SCAN_SECRETS_CMD"' _ "$LIB")"
CONST_ROTATE="$(printf '%s\n' "$CONST_OUT" | sed -n '1p')"
CONST_SCANNER="$(printf '%s\n' "$CONST_OUT" | sed -n '2p')"
if [ "$CONST_ROTATE" = "1048576" ]; then
  ok "ARCHIVE_ROTATE_AT_BYTES is 1048576"
else
  bad "ARCHIVE_ROTATE_AT_BYTES is 1048576" "got '$CONST_ROTATE'"
fi
# Canonicalize before comparing -- SCAN_SECRETS_CMD is resolved via a relative "../.."
# path, not a canonicalized one, so a raw string compare against REAL_SCANNER would be
# a false negative even when both point at the same file.
CONST_SCANNER_CANON="$(cd "$(dirname "$CONST_SCANNER")" 2>/dev/null && pwd)/$(basename "$CONST_SCANNER")"
if [ "$CONST_SCANNER_CANON" = "$REAL_SCANNER" ] && [ -x "$CONST_SCANNER" ]; then
  ok "SCAN_SECRETS_CMD resolves to hooks/scan-secrets.sh by default"
else
  bad "SCAN_SECRETS_CMD resolves to hooks/scan-secrets.sh by default" \
    "got '$CONST_SCANNER' (canon '$CONST_SCANNER_CANON'), want '$REAL_SCANNER'"
fi

# --- SCAN_SECRETS_CMD resolves from BASH_SOURCE, never $PWD, never git rev-parse ------
# Copy the library and the scanner into a throwaway tree at the SAME relative layout
# (hooks/scan-secrets.sh, hooks/handoff/lib/handoff-archive.sh), source the COPY while
# cwd is elsewhere, and confirm it resolves to the COPY, not the real repo's file. This
# is the only way to actually distinguish BASH_SOURCE resolution from a $PWD-based one.
ALT_ROOT="$TMP/alt-repo"
mkdir -p "$ALT_ROOT/hooks/handoff/lib"
cp "$REAL_SCANNER" "$ALT_ROOT/hooks/scan-secrets.sh"
cp "$LIB" "$ALT_ROOT/hooks/handoff/lib/handoff-archive.sh"
ALT_SCANNER_WANT="$ALT_ROOT/hooks/scan-secrets.sh"
ALT_SCANNER_GOT="$(cd "$TMP" && bash -c 'set -u; source "$1"; printf "%s" "$SCAN_SECRETS_CMD"' _ "$ALT_ROOT/hooks/handoff/lib/handoff-archive.sh")"
ALT_SCANNER_GOT_CANON="$(cd "$(dirname "$ALT_SCANNER_GOT")" 2>/dev/null && pwd)/$(basename "$ALT_SCANNER_GOT")"
if [ "$ALT_SCANNER_GOT_CANON" = "$ALT_SCANNER_WANT" ]; then
  ok "SCAN_SECRETS_CMD resolves relative to BASH_SOURCE, not cwd"
else
  bad "SCAN_SECRETS_CMD resolves relative to BASH_SOURCE, not cwd" \
    "got '$ALT_SCANNER_GOT' (canon '$ALT_SCANNER_GOT_CANON'), want '$ALT_SCANNER_WANT'"
fi

# --- SCAN_SECRETS_CMD is overridable via env for tests -------------------------------
OVERRIDE_OUT="$(env HANDOFF_SCAN_SECRETS_CMD="/nonexistent/fake-scanner.sh" bash -c 'set -u; source "$1"; printf "%s" "$SCAN_SECRETS_CMD"' _ "$LIB")"
if [ "$OVERRIDE_OUT" = "/nonexistent/fake-scanner.sh" ]; then
  ok "SCAN_SECRETS_CMD is overridable via HANDOFF_SCAN_SECRETS_CMD"
else
  bad "SCAN_SECRETS_CMD is overridable via HANDOFF_SCAN_SECRETS_CMD" "got '$OVERRIDE_OUT'"
fi

# ==========================================================================================
# extract_keep_lines -- [KEEP] region extraction with fence tracking. FENCE CASES FIRST:
# these are the load-bearing scenarios, since every other extraction test assumes fence
# tracking already works.
# ==========================================================================================

# --- Fence: a "## " line inside a fenced block inside a KEEP region is body -----------
FENCE_INSIDE_ENDS_MD="$TMP/fence-inside-ends.md"
cat > "$FENCE_INSIDE_ENDS_MD" <<'EOF'
## Standing rules [KEEP]
before fence
```
## not a real heading
still body
```
after fence
## Next
excluded
EOF
FENCE_INSIDE_ENDS_WANT="$TMP/fence-inside-ends.want"
cat > "$FENCE_INSIDE_ENDS_WANT" <<'EOF'
## Standing rules [KEEP]
before fence
```
## not a real heading
still body
```
after fence
EOF
FENCE_INSIDE_ENDS_GOT="$TMP/fence-inside-ends.got"
call_lib "$FENCE_INSIDE_ENDS_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FENCE_INSIDE_ENDS_MD"
if diff -q "$FENCE_INSIDE_ENDS_WANT" "$FENCE_INSIDE_ENDS_GOT" >/dev/null 2>&1; then
  ok "a '## ' line inside a fenced block inside a KEEP region is body, region does not end there"
else
  bad "a '## ' line inside a fenced block inside a KEEP region is body, region does not end there" \
    "$(diff "$FENCE_INSIDE_ENDS_WANT" "$FENCE_INSIDE_ENDS_GOT")"
fi

# --- Fence: a "## Something [KEEP]" line inside a fenced block opens NO region --------
FENCE_INSIDE_OPENS_MD="$TMP/fence-inside-opens.md"
cat > "$FENCE_INSIDE_OPENS_MD" <<'EOF'
## Outer
not protected
```
## Something [KEEP]
also not protected
```
still not protected
## Z
EOF
FENCE_INSIDE_OPENS_GOT="$TMP/fence-inside-opens.got"
call_lib "$FENCE_INSIDE_OPENS_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FENCE_INSIDE_OPENS_MD"
if [ ! -s "$FENCE_INSIDE_OPENS_GOT" ]; then
  ok "a '[KEEP]' heading inside a fenced block opens no region"
else
  bad "a '[KEEP]' heading inside a fenced block opens no region" "$(cat "$FENCE_INSIDE_OPENS_GOT")"
fi

# --- Fence: three tildes do not close a three-backtick fence --------------------------
FENCE_TILDE_MD="$TMP/fence-tilde.md"
cat > "$FENCE_TILDE_MD" <<'EOF'
## R [KEEP]
```
~~~
tilde is body
```
now closed
## End
EOF
FENCE_TILDE_WANT="$TMP/fence-tilde.want"
cat > "$FENCE_TILDE_WANT" <<'EOF'
## R [KEEP]
```
~~~
tilde is body
```
now closed
EOF
FENCE_TILDE_GOT="$TMP/fence-tilde.got"
call_lib "$FENCE_TILDE_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FENCE_TILDE_MD"
if diff -q "$FENCE_TILDE_WANT" "$FENCE_TILDE_GOT" >/dev/null 2>&1; then
  ok "a tilde fence does not close a backtick fence -- fence stays open, tilde line is body"
else
  bad "a tilde fence does not close a backtick fence -- fence stays open, tilde line is body" \
    "$(diff "$FENCE_TILDE_WANT" "$FENCE_TILDE_GOT")"
fi

# --- Fence: a longer closing fence closes a shorter opening one -----------------------
FENCE_LONGER_CLOSES_MD="$TMP/fence-longer-closes.md"
cat > "$FENCE_LONGER_CLOSES_MD" <<'EOF'
## S [KEEP]
```
body
````
after
## End
EOF
FENCE_LONGER_CLOSES_WANT="$TMP/fence-longer-closes.want"
cat > "$FENCE_LONGER_CLOSES_WANT" <<'EOF'
## S [KEEP]
```
body
````
after
EOF
FENCE_LONGER_CLOSES_GOT="$TMP/fence-longer-closes.got"
call_lib "$FENCE_LONGER_CLOSES_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FENCE_LONGER_CLOSES_MD"
if diff -q "$FENCE_LONGER_CLOSES_WANT" "$FENCE_LONGER_CLOSES_GOT" >/dev/null 2>&1; then
  ok "a longer closing fence (4 backticks) closes a shorter opening one (3 backticks)"
else
  bad "a longer closing fence (4 backticks) closes a shorter opening one (3 backticks)" \
    "$(diff "$FENCE_LONGER_CLOSES_WANT" "$FENCE_LONGER_CLOSES_GOT")"
fi

# --- Fence: a shorter closing fence does NOT close a longer opening one ---------------
FENCE_SHORTER_MD="$TMP/fence-shorter.md"
cat > "$FENCE_SHORTER_MD" <<'EOF'
## T [KEEP]
````
body
```
still open (3 doesn't close 4)
````
now closed
## End
EOF
FENCE_SHORTER_WANT="$TMP/fence-shorter.want"
cat > "$FENCE_SHORTER_WANT" <<'EOF'
## T [KEEP]
````
body
```
still open (3 doesn't close 4)
````
now closed
EOF
FENCE_SHORTER_GOT="$TMP/fence-shorter.got"
call_lib "$FENCE_SHORTER_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FENCE_SHORTER_MD"
if diff -q "$FENCE_SHORTER_WANT" "$FENCE_SHORTER_GOT" >/dev/null 2>&1; then
  ok "a shorter closing fence (3 backticks) does not close a longer opening one (4 backticks)"
else
  bad "a shorter closing fence (3 backticks) does not close a longer opening one (4 backticks)" \
    "$(diff "$FENCE_SHORTER_WANT" "$FENCE_SHORTER_GOT")"
fi

# --- Fence: indented up to three spaces opens; four spaces does not -------------------
FENCE_INDENT_MD="$TMP/fence-indent.md"
cat > "$FENCE_INDENT_MD" <<'EOF'
## U [KEEP]
   ```
   indented fence body
   ```
line-after-3space-fence
    ```
four-space line is not a fence, just body
## End
EOF
FENCE_INDENT_WANT="$TMP/fence-indent.want"
cat > "$FENCE_INDENT_WANT" <<'EOF'
## U [KEEP]
   ```
   indented fence body
   ```
line-after-3space-fence
    ```
four-space line is not a fence, just body
EOF
FENCE_INDENT_GOT="$TMP/fence-indent.got"
call_lib "$FENCE_INDENT_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FENCE_INDENT_MD"
if diff -q "$FENCE_INDENT_WANT" "$FENCE_INDENT_GOT" >/dev/null 2>&1; then
  ok "a fence indented up to three spaces opens; a four-space indent does not"
else
  bad "a fence indented up to three spaces opens; a four-space indent does not" \
    "$(diff "$FENCE_INDENT_WANT" "$FENCE_INDENT_GOT")"
fi

# --- YAML front matter is skipped before parsing begins -------------------------------
FRONTMATTER_MD="$TMP/frontmatter.md"
cat > "$FRONTMATTER_MD" <<'EOF'
---
title: doc
tags: [a, b]
---
## V [KEEP]
protected line
## End
EOF
FRONTMATTER_WANT="$TMP/frontmatter.want"
cat > "$FRONTMATTER_WANT" <<'EOF'
## V [KEEP]
protected line
EOF
FRONTMATTER_GOT="$TMP/frontmatter.got"
call_lib "$FRONTMATTER_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$FRONTMATTER_MD"
if diff -q "$FRONTMATTER_WANT" "$FRONTMATTER_GOT" >/dev/null 2>&1; then
  ok "YAML front matter is skipped before parsing begins"
else
  bad "YAML front matter is skipped before parsing begins" "$(diff "$FRONTMATTER_WANT" "$FRONTMATTER_GOT")"
fi

# --- Setext headings are body, not ATX headings ----------------------------------------
SETEXT_MD="$TMP/setext.md"
cat > "$SETEXT_MD" <<'EOF'
## W [KEEP]
Title Text
===
more text
Another Title
---
tail
## End
EOF
SETEXT_WANT="$TMP/setext.want"
cat > "$SETEXT_WANT" <<'EOF'
## W [KEEP]
Title Text
===
more text
Another Title
---
tail
EOF
SETEXT_GOT="$TMP/setext.got"
call_lib "$SETEXT_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$SETEXT_MD"
if diff -q "$SETEXT_WANT" "$SETEXT_GOT" >/dev/null 2>&1; then
  ok "setext headings (=== or --- underline) are body, not ATX headings"
else
  bad "setext headings (=== or --- underline) are body, not ATX headings" "$(diff "$SETEXT_WANT" "$SETEXT_GOT")"
fi

# --- Region ends at the next ATX heading of ANY level ----------------------------------
ANYLEVEL_MD="$TMP/anylevel.md"
cat > "$ANYLEVEL_MD" <<'EOF'
### X [KEEP]
body
# Y
excluded
EOF
ANYLEVEL_WANT="$TMP/anylevel.want"
cat > "$ANYLEVEL_WANT" <<'EOF'
### X [KEEP]
body
EOF
ANYLEVEL_GOT="$TMP/anylevel.got"
call_lib "$ANYLEVEL_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$ANYLEVEL_MD"
if diff -q "$ANYLEVEL_WANT" "$ANYLEVEL_GOT" >/dev/null 2>&1; then
  ok "a region ends at the next ATX heading of any level (level 3 KEEP ended by level 1)"
else
  bad "a region ends at the next ATX heading of any level (level 3 KEEP ended by level 1)" \
    "$(diff "$ANYLEVEL_WANT" "$ANYLEVEL_GOT")"
fi

# --- Region ends at end of file when no later heading exists --------------------------
EOF_END_MD="$TMP/eof-end.md"
cat > "$EOF_END_MD" <<'EOF'
## Z [KEEP]
line1
line2
EOF
EOF_END_GOT="$TMP/eof-end.got"
call_lib "$EOF_END_GOT" "$SCRATCH_ERR" "$LIB" extract_keep_lines "$EOF_END_MD"
if diff -q "$EOF_END_MD" "$EOF_END_GOT" >/dev/null 2>&1; then
  ok "a region with no later heading runs to end of file"
else
  bad "a region with no later heading runs to end of file" "$(diff "$EOF_END_MD" "$EOF_END_GOT")"
fi

# --- Falsifier: fence tracking removed -> the fence-inside-ends test must fail --------
# Mutate a COPY: force `fence` to never open (every "fence = 1;" becomes "fence = 0;"),
# so a "## " line inside what should be a fenced block is tested as a real heading and
# wrongly ends the region early.
FENCE_MUTANT_LIB="$TMP/handoff-archive.fence-mutant.sh"
sed 's/fence = 1;/fence = 0;/g' "$LIB" > "$FENCE_MUTANT_LIB"
if grep -q 'fence = 1;' "$FENCE_MUTANT_LIB"; then
  bad "falsifier setup: fence-mutant copy still contains 'fence = 1;'" "sed did not strip it"
else
  ok "falsifier setup: fence-mutant copy has fence-opening assignments neutralized"
fi
FENCE_MUTANT_GOT="$TMP/fence-inside-ends.mutant.got"
call_lib "$FENCE_MUTANT_GOT" "$SCRATCH_ERR" "$FENCE_MUTANT_LIB" extract_keep_lines "$FENCE_INSIDE_ENDS_MD"
if diff -q "$FENCE_INSIDE_ENDS_WANT" "$FENCE_MUTANT_GOT" >/dev/null 2>&1; then
  bad "falsifier: fence-tracking-removed mutant should mis-end the region, but it still matched" \
    "$(cat "$FENCE_MUTANT_GOT")"
else
  ok "falsifier: with fence tracking removed, the 'inside a fence' extraction test goes red"
fi

