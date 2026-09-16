# 30-membership.sh — sourced by ../handoff-archive.test.sh — not runnable on its own.
# Covers missing_protected_lines() set-membership between a snapshot's protected [KEEP] lines and the current file.

# ==========================================================================================
# missing_protected_lines -- set membership between the snapshot's protected lines and
# the current file, using grep -F -x (fixed-string, whole-line), never a regex.
# ==========================================================================================

MEMBER_SNAP="$TMP/member-snap.md"
cat > "$MEMBER_SNAP" <<'EOF'
## Standing rules [KEEP]
- Always work in a worktree.
- Never skip hooks.
- Pattern .* matches [any] char $end (test)
- Always work in a worktree.
## Other
not protected
EOF

# --- Membership: reordering, re-nesting and moving all PASS ---------------------------
MEMBER_REORDER="$TMP/member-reorder.md"
cat > "$MEMBER_REORDER" <<'EOF'
## Different heading
- Never skip hooks.
### Nested somewhere else
- Always work in a worktree.
- Pattern .* matches [any] char $end (test)
## Standing rules [KEEP]
extra line
EOF
MEMBER_REORDER_OUT="$TMP/member-reorder.out"
call_lib "$MEMBER_REORDER_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_SNAP" "$MEMBER_REORDER"
MEMBER_REORDER_RC=$?
if [ "$MEMBER_REORDER_RC" -eq 0 ] && [ ! -s "$MEMBER_REORDER_OUT" ]; then
  ok "reordering, re-nesting and moving protected lines all PASS (rc 0, nothing missing)"
else
  bad "reordering, re-nesting and moving protected lines all PASS (rc 0, nothing missing)" \
    "rc=$MEMBER_REORDER_RC out=$(cat "$MEMBER_REORDER_OUT")"
fi

MEMBER_MOVED="$TMP/member-moved.md"
cat > "$MEMBER_MOVED" <<'EOF'
# New Parent
## Standing rules [KEEP]
- Always work in a worktree.
- Never skip hooks.
- Pattern .* matches [any] char $end (test)
EOF
MEMBER_MOVED_OUT="$TMP/member-moved.out"
call_lib "$MEMBER_MOVED_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_SNAP" "$MEMBER_MOVED"
MEMBER_MOVED_RC=$?
if [ "$MEMBER_MOVED_RC" -eq 0 ] && [ ! -s "$MEMBER_MOVED_OUT" ]; then
  ok "moving a protected block under a different parent heading PASSES"
else
  bad "moving a protected block under a different parent heading PASSES" \
    "rc=$MEMBER_MOVED_RC out=$(cat "$MEMBER_MOVED_OUT")"
fi

# --- Membership: deleting a protected line FAILS ---------------------------------------
MEMBER_DELETED="$TMP/member-deleted.md"
cat > "$MEMBER_DELETED" <<'EOF'
## Standing rules [KEEP]
- Always work in a worktree.
- Pattern .* matches [any] char $end (test)
EOF
MEMBER_DELETED_OUT="$TMP/member-deleted.out"
call_lib "$MEMBER_DELETED_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_SNAP" "$MEMBER_DELETED"
MEMBER_DELETED_RC=$?
if [ "$MEMBER_DELETED_RC" -eq 1 ] && [ "$(cat "$MEMBER_DELETED_OUT")" = "- Never skip hooks." ]; then
  ok "deleting a protected line FAILS and names exactly that line"
else
  bad "deleting a protected line FAILS and names exactly that line" \
    "rc=$MEMBER_DELETED_RC out=$(cat "$MEMBER_DELETED_OUT")"
fi

# --- Membership: stripping the [KEEP] tag off the heading FAILS (heading is protected) -
MEMBER_STRIPPED="$TMP/member-stripped-tag.md"
cat > "$MEMBER_STRIPPED" <<'EOF'
## Standing rules
- Always work in a worktree.
- Never skip hooks.
- Pattern .* matches [any] char $end (test)
EOF
MEMBER_STRIPPED_OUT="$TMP/member-stripped-tag.out"
call_lib "$MEMBER_STRIPPED_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_SNAP" "$MEMBER_STRIPPED"
MEMBER_STRIPPED_RC=$?
if [ "$MEMBER_STRIPPED_RC" -eq 1 ] && [ "$(cat "$MEMBER_STRIPPED_OUT")" = "## Standing rules [KEEP]" ]; then
  ok "stripping the [KEEP] tag off the heading FAILS -- the heading is itself protected"
else
  bad "stripping the [KEEP] tag off the heading FAILS -- the heading is itself protected" \
    "rc=$MEMBER_STRIPPED_RC out=$(cat "$MEMBER_STRIPPED_OUT")"
fi

# --- Membership: a duplicated protected line surviving once PASSES (set, not multiset) -
MEMBER_DUP_SNAP="$TMP/member-dup-snap.md"
cat > "$MEMBER_DUP_SNAP" <<'EOF'
## Dup [KEEP]
same line
same line
EOF
MEMBER_DUP_CURRENT="$TMP/member-dup-current.md"
cat > "$MEMBER_DUP_CURRENT" <<'EOF'
## Dup [KEEP]
same line
EOF
MEMBER_DUP_OUT="$TMP/member-dup.out"
call_lib "$MEMBER_DUP_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_DUP_SNAP" "$MEMBER_DUP_CURRENT"
MEMBER_DUP_RC=$?
if [ "$MEMBER_DUP_RC" -eq 0 ] && [ ! -s "$MEMBER_DUP_OUT" ]; then
  ok "a protected line duplicated in the snapshot surviving once PASSES (set membership)"
else
  bad "a protected line duplicated in the snapshot surviving once PASSES (set membership)" \
    "rc=$MEMBER_DUP_RC out=$(cat "$MEMBER_DUP_OUT")"
fi

# --- Membership: a protected line with regex metacharacters is matched LITERALLY -------
MEMBER_META_SNAP="$TMP/member-meta-snap.md"
cat > "$MEMBER_META_SNAP" <<'EOF'
## Meta [KEEP]
a.b*c$
list: [a](b) end
EOF
MEMBER_META_PASS="$TMP/member-meta-pass.md"
cat > "$MEMBER_META_PASS" <<'EOF'
list: [a](b) end
random other line
a.b*c$
## Meta [KEEP]
EOF
MEMBER_META_PASS_OUT="$TMP/member-meta-pass.out"
call_lib "$MEMBER_META_PASS_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_META_SNAP" "$MEMBER_META_PASS"
MEMBER_META_PASS_RC=$?
if [ "$MEMBER_META_PASS_RC" -eq 0 ] && [ ! -s "$MEMBER_META_PASS_OUT" ]; then
  ok "a protected line containing regex metacharacters matches when present verbatim"
else
  bad "a protected line containing regex metacharacters matches when present verbatim" \
    "rc=$MEMBER_META_PASS_RC out=$(cat "$MEMBER_META_PASS_OUT")"
fi

# 'axbc' would satisfy the BRE/ERE regex `a.b*c$` (. = any char, b* = zero-or-more b,
# $ = end anchor) even though it is a completely different literal string. If the
# matcher were ever a regex instead of -F, this line would be found and NOT reported
# missing -- so this is the discriminating case for fixed-string matching.
MEMBER_META_FAIL="$TMP/member-meta-fail.md"
cat > "$MEMBER_META_FAIL" <<'EOF'
list: [a](b) end
## Meta [KEEP]
axbc
EOF
MEMBER_META_FAIL_OUT="$TMP/member-meta-fail.out"
call_lib "$MEMBER_META_FAIL_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_META_SNAP" "$MEMBER_META_FAIL"
MEMBER_META_FAIL_RC=$?
if [ "$MEMBER_META_FAIL_RC" -eq 1 ] && [ "$(cat "$MEMBER_META_FAIL_OUT")" = 'a.b*c$' ]; then
  ok "a regex-confusable line ('axbc') does not satisfy the literal 'a.b*c\$' -- fixed-string match"
else
  bad "a regex-confusable line ('axbc') does not satisfy the literal 'a.b*c\$' -- fixed-string match" \
    "rc=$MEMBER_META_FAIL_RC out=$(cat "$MEMBER_META_FAIL_OUT")"
fi

# --- Membership: a missing CURRENT file means every protected line is missing ---------
MEMBER_NO_CURRENT="$TMP/does-not-exist.md"
MEMBER_NO_CURRENT_OUT="$TMP/member-no-current.out"
call_lib "$MEMBER_NO_CURRENT_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_SNAP" "$MEMBER_NO_CURRENT"
MEMBER_NO_CURRENT_RC=$?
MEMBER_NO_CURRENT_LINES="$(wc -l < "$MEMBER_NO_CURRENT_OUT" | tr -d ' ')"
if [ "$MEMBER_NO_CURRENT_RC" -eq 1 ] && [ "$MEMBER_NO_CURRENT_LINES" -eq 4 ]; then
  ok "a missing CURRENT file means every one of the 4 protected lines is reported missing"
else
  bad "a missing CURRENT file means every one of the 4 protected lines is reported missing" \
    "rc=$MEMBER_NO_CURRENT_RC lines=$MEMBER_NO_CURRENT_LINES out=$(cat "$MEMBER_NO_CURRENT_OUT")"
fi

# --- Membership: blank lines are excluded from the protected set ----------------------
MEMBER_BLANK_SNAP="$TMP/member-blank-snap.md"
cat > "$MEMBER_BLANK_SNAP" <<'EOF'
## Blank [KEEP]
line one

line two
EOF
MEMBER_BLANK_CURRENT="$TMP/member-blank-current.md"
cat > "$MEMBER_BLANK_CURRENT" <<'EOF'
## Blank [KEEP]
line one
line two
EOF
MEMBER_BLANK_OUT="$TMP/member-blank.out"
call_lib "$MEMBER_BLANK_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_BLANK_SNAP" "$MEMBER_BLANK_CURRENT"
MEMBER_BLANK_RC=$?
if [ "$MEMBER_BLANK_RC" -eq 0 ] && [ ! -s "$MEMBER_BLANK_OUT" ]; then
  ok "a blank line inside a KEEP region is excluded from the protected set"
else
  bad "a blank line inside a KEEP region is excluded from the protected set" \
    "rc=$MEMBER_BLANK_RC out=$(cat "$MEMBER_BLANK_OUT")"
fi

# --- Membership: trailing whitespace is stripped from BOTH sides before comparing -----
MEMBER_TRAIL_SNAP="$TMP/member-trail-snap.md"
printf '## Trail [KEEP]\npadded line   \n' > "$MEMBER_TRAIL_SNAP"
MEMBER_TRAIL_CURRENT="$TMP/member-trail-current.md"
printf '## Trail [KEEP]\npadded line\n' > "$MEMBER_TRAIL_CURRENT"
MEMBER_TRAIL_OUT="$TMP/member-trail.out"
call_lib "$MEMBER_TRAIL_OUT" "$SCRATCH_ERR" "$LIB" missing_protected_lines "$MEMBER_TRAIL_SNAP" "$MEMBER_TRAIL_CURRENT"
MEMBER_TRAIL_RC=$?
if [ "$MEMBER_TRAIL_RC" -eq 0 ] && [ ! -s "$MEMBER_TRAIL_OUT" ]; then
  ok "trailing whitespace is stripped from both sides before comparing"
else
  bad "trailing whitespace is stripped from both sides before comparing" \
    "rc=$MEMBER_TRAIL_RC out=$(cat "$MEMBER_TRAIL_OUT")"
fi

# --- Falsifier: grep -F changed to a regex match -> the metachar test must fail -------
GREP_MUTANT_LIB="$TMP/handoff-archive.grep-mutant.sh"
sed 's/grep -F -x -q/grep -x -q/' "$LIB" > "$GREP_MUTANT_LIB"
if grep -q 'grep -F -x -q' "$GREP_MUTANT_LIB"; then
  bad "falsifier setup: grep-mutant copy still contains 'grep -F -x -q'" "sed did not strip it"
else
  ok "falsifier setup: grep-mutant copy has -F stripped from the membership match"
fi
GREP_MUTANT_OUT="$TMP/member-meta-fail.mutant.out"
call_lib "$GREP_MUTANT_OUT" "$SCRATCH_ERR" "$GREP_MUTANT_LIB" missing_protected_lines "$MEMBER_META_SNAP" "$MEMBER_META_FAIL"
GREP_MUTANT_RC=$?
if [ "$GREP_MUTANT_RC" -eq 1 ] && [ "$(cat "$GREP_MUTANT_OUT")" = 'a.b*c$' ]; then
  bad "falsifier: dropping -F should let the regex-confusable line pass, but the test still failed correctly" \
    "rc=$GREP_MUTANT_RC out=$(cat "$GREP_MUTANT_OUT")"
else
  ok "falsifier: with -F dropped, the regex-metacharacter membership test goes red (rc=$GREP_MUTANT_RC out=$(cat "$GREP_MUTANT_OUT"))"
fi

