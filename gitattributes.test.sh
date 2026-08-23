#!/usr/bin/env bash
# gitattributes.test.sh — proves the `merge=union` entries in .gitattributes by MERGING REAL
# COMMITS in throwaway repos. Run: bash gitattributes.test.sh
#
# The whole point of this file is that "merge=union makes concurrent ledger appends concatenate"
# is a claim about git's behaviour, not about our text. Reading the attribute back with
# `check-attr` only proves the pattern matches; it says nothing about what a merge does. So every
# behavioural case below builds a real repo in a temp dir, commits divergent appends on two
# branches, runs `git merge`, and reads the resulting file.
#
# The positive cases COPY the repo's real .gitattributes rather than re-typing its two lines. A
# test that re-types the patterns passes forever after someone typos the shipped file.
#
# Three falsifiers, because "no conflict" is the trivially-passing answer and a union test that
# passes without the attribute is testing nothing:
#
#   * NO .gitattributes at all           -> the same merge must CONFLICT.
#   * .gitattributes with the two ledger lines stripped, comments kept
#                                        -> must still CONFLICT (it is those lines, not the file).
#   * .gitattributes intact, a NEIGHBOURING path under coding-memory/
#                                        -> must CONFLICT (the attribute is scoped, not repo-wide).
#
# Two limits are pinned as PASSING assertions, not left as prose. Both are real and neither is
# closed by this change; a later reader who assumes otherwise is the failure this guards:
#
#   * FAST-FORWARD. Uncommitted local changes meeting a fast-forward pull is the failure that
#     prompted this whole card, and NO merge driver runs on a fast-forward. `merge=union` is
#     inert there. The case asserts git still refuses.
#   * DUPLICATE ROWS. Union concatenates and never dedupes -- but measured, that is NOT the same
#     as "any byte-identical row duplicates". Both sides appending the same single row collapses
#     to one row (the three-way merge resolves an identical change before a driver is consulted);
#     a row repeated across two hunks the merge cannot align survives twice. Both halves are
#     asserted, alongside the case the card asked for: rows differing only in `ts` are both kept
#     intact, which is why the real ledgers do not hit this.
#
# No marker is written at the end. The receipt convention pairs X.test.sh with a sibling X.sh
# (hooks/lib/write-test-marker.py, PAIR_SUFFIXES); the subject here is `.gitattributes`, which is
# neither .sh nor .py, forms no pair, and is therefore never gated by test-marker-guard.sh. A
# call here would only emit a "no tracked subject gitattributes.sh" notice about a file that will
# never exist.
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
ATTRS="$ROOT/.gitattributes"

# Physical path: on macOS `mktemp -d` hands back the /var symlink form while git resolves to
# /private/var. Same note as hooks/feature-sync-guard.test.sh / hooks/phase-guard.test.sh.
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# The throwaway repos must not inherit the developer's merge.conflictStyle, commit.gpgsign,
# core.autocrlf or user identity -- any of those would make the assertions depend on the machine.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

OBS='coding-memory/observability-judge/verdicts.jsonl'
CMP='coding-memory/compliance-judge/verdicts.jsonl'
NEIGHBOUR='coding-memory/some-other-judge/verdicts.jsonl'   # deliberately NOT in .gitattributes

pass=0; fail=0
ok()  { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s\n%s\n' "$1" "$2"; fail=$((fail+1)); }

eq() { # $1 desc, $2 got, $3 want
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "  got: <$2>  want: <$3>"; fi
}

# --- file readers ------------------------------------------------------------------------
# awk, not grep: `grep` on this machine is shadowed by ugrep, which applies .gitignore rules.
# Exact whole-line matching also means a row that came through mangled does not count as present.
nmatch()  { awk -v want="$2" '$0==want{n++} END{print n+0}' "$1"; }
nlines()  { awk 'NF{n++} END{print n+0}' "$1"; }
conflicted() { awk '/^(<<<<<<<|=======|>>>>>>>)/{f=1} END{exit !f}' "$1"; }

json_ok() { # every non-blank line still parses -- catches a row cut in half by a bad merge
  python3 -c 'import json, sys
for line in open(sys.argv[1]):
    if line.strip():
        json.loads(line)' "$1" 2>/dev/null
}

# --- fixtures ----------------------------------------------------------------------------
# A realistic verdict row. No trailing newline: every writer below adds its own, so a row is
# always exactly one line and command substitution cannot silently eat the terminator.
row() { printf '{"ts":"%s","repo":"%s","head_sha":"%s","stage":"implementation","outcome":"%s"}' \
  "$1" "$2" "$3" "$4"; }

BASE_ROW="$(row 2026-08-20T09:00:00Z base-repo 0000000 pass)"

# Every fixture command runs through this. A fixture that fails silently is worse than a red
# suite: the first draft of this file lost its repo counter to a subshell, every case reused one
# repo, and four assertions went GREEN against a repo whose two "branches" were the same branch.
# A broken fixture must stop the run, not hand the assertions a plausible-looking file.
must() {
  "$@" || { printf 'FIXTURE FAILED — %s\n' "$*" >&2; exit 3; }
}

# Sets $REPO. Deliberately NOT `REPO=$(new_repo ...)`: a counter incremented inside a command
# substitution increments a subshell's copy and is lost, which is exactly the bug above.
seq=0
REPO=''
new_repo() { # $1 = attrs | noattrs | stripped
  seq=$((seq+1))
  local dir="$TMP/repo$seq" mode="$1" f
  must mkdir -p "$dir/coding-memory/observability-judge" \
                "$dir/coding-memory/compliance-judge" \
                "$dir/coding-memory/some-other-judge"
  must git -C "$dir" init -q -b main
  must git -C "$dir" config user.email test@example.com
  must git -C "$dir" config user.name  test
  case "$mode" in
    attrs)    must cp "$ATTRS" "$dir/.gitattributes" ;;
    # Comments kept, both `merge=union` lines dropped: isolates the two lines from the file's
    # mere existence, so a future .gitattributes that keeps the prose and loses the rules fails.
    stripped) awk '!/merge=union/' "$ATTRS" > "$dir/.gitattributes" || exit 3 ;;
    noattrs)  ;;
  esac
  for f in "$OBS" "$CMP" "$NEIGHBOUR"; do printf '%s\n' "$BASE_ROW" > "$dir/$f" || exit 3; done
  must git -C "$dir" add -A
  must git -C "$dir" commit -q -m 'base ledgers'
  REPO="$dir"
}

diverge() { # $1 repo, $2 file, $3 our row, $4 their row -- leaves HEAD on main, branch `side` behind
  local dir="$1" f="$2"
  must git -C "$dir" checkout -q -b side
  printf '%s\n' "$4" >> "$dir/$f" || exit 3
  must git -C "$dir" commit -q -am 'side append'
  must git -C "$dir" checkout -q main
  printf '%s\n' "$3" >> "$dir/$f" || exit 3
  must git -C "$dir" commit -q -am 'main append'
  # The merge below is only a merge if the two sides really diverged. Assert it, do not assume:
  # a fixture that quietly produced a fast-forward makes "no conflict" mean nothing.
  if git -C "$dir" merge-base --is-ancestor side main; then
    printf 'FIXTURE FAILED — side is an ancestor of main; no real merge in %s\n' "$dir" >&2
    exit 3
  fi
}

merge_side() { # $1 repo -> MERGE_RC, MERGE_OUT. --no-edit so a merge never blocks on an editor.
  MERGE_OUT="$(git -C "$1" merge --no-edit side 2>&1)"; MERGE_RC=$?
}

# ── 1. The claim itself: both ledgers, both appends survive, no conflict, no duplicate ──────
for pair in "observability:$OBS" "compliance:$CMP"; do
  name="${pair%%:*}"; file="${pair#*:}"
  ours="$(row   2026-08-21T10:00:00Z repo-a 1111111 pass)"
  theirs="$(row 2026-08-21T11:30:00Z repo-b 2222222 fail)"

  new_repo attrs; repo="$REPO"
  diverge "$repo" "$file" "$ours" "$theirs"
  merge_side "$repo"

  eq "$name: merge exits 0"                    "$MERGE_RC"                        "0"
  if conflicted "$repo/$file"; then
    bad "$name: no conflict markers in the merged ledger" "$(cat "$repo/$file")"
  else
    ok "$name: no conflict markers in the merged ledger"
  fi
  eq "$name: our row survives exactly once"    "$(nmatch "$repo/$file" "$ours")"   "1"
  eq "$name: their row survives exactly once"  "$(nmatch "$repo/$file" "$theirs")" "1"
  eq "$name: the base row is not duplicated"   "$(nmatch "$repo/$file" "$BASE_ROW")" "1"
  eq "$name: exactly three rows, nothing invented" "$(nlines "$repo/$file")"       "3"
  if json_ok "$repo/$file"; then ok "$name: every merged row still parses as JSON"
  else bad "$name: every merged row still parses as JSON" "$(cat "$repo/$file")"; fi
done

# ── 2. Falsifier A — with no .gitattributes at all, the very same merge must conflict ───────
# Without this the whole file is vacuous: a merge that never conflicts proves nothing about
# a driver that is supposed to be preventing the conflict.
ours="$(row   2026-08-21T10:00:00Z repo-a 1111111 pass)"
theirs="$(row 2026-08-21T11:30:00Z repo-b 2222222 fail)"
new_repo noattrs; repo="$REPO"
diverge "$repo" "$OBS" "$ours" "$theirs"
merge_side "$repo"

if [ "$MERGE_RC" -ne 0 ]; then ok "falsifier: no .gitattributes -> merge fails"
else bad "falsifier: no .gitattributes -> merge fails" "  rc=0, output: $MERGE_OUT"; fi
if conflicted "$repo/$OBS"; then ok "falsifier: no .gitattributes -> conflict markers in the ledger"
else bad "falsifier: no .gitattributes -> conflict markers in the ledger" "$(cat "$repo/$OBS")"; fi
case "$MERGE_OUT" in
  (*CONFLICT*) ok "falsifier: git reports CONFLICT for the ledger" ;;
  (*) bad "falsifier: git reports CONFLICT for the ledger" "  output: $MERGE_OUT" ;;
esac

# ── 3. Falsifier B — the two lines are what does it, not the file's existence ───────────────
new_repo stripped; repo="$REPO"
diverge "$repo" "$CMP" "$ours" "$theirs"
merge_side "$repo"
if [ "$MERGE_RC" -ne 0 ] && conflicted "$repo/$CMP"; then
  ok "falsifier: .gitattributes minus the merge=union lines -> conflict"
else
  bad "falsifier: .gitattributes minus the merge=union lines -> conflict" \
      "  rc=$MERGE_RC, output: $MERGE_OUT"
fi

# ── 4. Falsifier C — the attribute is SCOPED. A neighbouring judge path still conflicts. ────
# This is the test for the "two exact literals, not coding-memory/*/verdicts.jsonl" decision.
# If someone widens the pattern, this case is what tells them they did.
new_repo attrs; repo="$REPO"
diverge "$repo" "$NEIGHBOUR" "$ours" "$theirs"
merge_side "$repo"
if [ "$MERGE_RC" -ne 0 ] && conflicted "$repo/$NEIGHBOUR"; then
  ok "scope: an unlisted coding-memory/*/verdicts.jsonl path still conflicts"
else
  bad "scope: an unlisted coding-memory/*/verdicts.jsonl path still conflicts" \
      "  rc=$MERGE_RC, output: $MERGE_OUT"
fi

# ── 5. Rows differing only in `ts` — the case the card says must be demonstrated, not assumed ─
# Same repo, same head_sha, same outcome; only the timestamp differs. Both must survive whole.
TS_A="$(row 2026-08-21T12:00:00Z repo-a 3333333 pass)"
TS_B="$(row 2026-08-21T12:00:01Z repo-a 3333333 pass)"
new_repo attrs; repo="$REPO"
diverge "$repo" "$OBS" "$TS_A" "$TS_B"
merge_side "$repo"

eq "near-duplicate rows (ts only): merge exits 0"       "$MERGE_RC"                       "0"
eq "near-duplicate rows (ts only): the earlier ts is kept intact" "$(nmatch "$repo/$OBS" "$TS_A")" "1"
eq "near-duplicate rows (ts only): the later ts is kept intact"   "$(nmatch "$repo/$OBS" "$TS_B")" "1"
eq "near-duplicate rows (ts only): three rows, neither mangled"   "$(nlines "$repo/$OBS")"         "3"
if json_ok "$repo/$OBS"; then ok "near-duplicate rows (ts only): both still parse as JSON"
else bad "near-duplicate rows (ts only): both still parse as JSON" "$(cat "$repo/$OBS")"; fi

# ── 6. LIMIT, pinned — when a repeated row DOES and does NOT duplicate. Measured, not assumed. ─
# The card's open question predicted that any byte-identical row on both sides survives twice.
# Measured here, it does not, and the distinction is the whole practical answer:
#
#   * Both sides append the SAME single row  -> ONE copy. The three-way merge sees an identical
#     change on both sides and resolves it itself; no merge driver is ever consulted.
#   * The same row sits in two hunks the merge cannot align (ours ...,SHARED,A / theirs
#     ...,B,SHARED) -> TWO copies. Union concatenates both hunks verbatim and never dedupes.
#
# So the duplicate risk is about hunk alignment, not byte equality. Both halves are asserted,
# because either one alone would leave the wrong general rule in a reader's head.
SAME="$(row 2026-08-21T13:00:00Z repo-a 4444444 pass)"
new_repo attrs; repo="$REPO"
diverge "$repo" "$OBS" "$SAME" "$SAME"
merge_side "$repo"
eq "LIMIT: an identical single append on both sides merges cleanly" "$MERGE_RC"          "0"
eq "LIMIT: ...and collapses to ONE row, before any merge driver runs" \
   "$(nmatch "$repo/$OBS" "$SAME")" "1"
eq "LIMIT: ...leaving two rows in total"                 "$(nlines "$repo/$OBS")"         "2"

OURS_ONLY="$(row   2026-08-21T13:00:01Z repo-a 5555555 pass)"
THEIRS_ONLY="$(row 2026-08-21T13:00:02Z repo-b 6666666 fail)"
new_repo attrs; repo="$REPO"
diverge "$repo" "$OBS" "$(printf '%s\n%s' "$SAME" "$OURS_ONLY")" \
                       "$(printf '%s\n%s' "$THEIRS_ONLY" "$SAME")"
merge_side "$repo"
eq "LIMIT: a repeated row across unalignable hunks merges cleanly" "$MERGE_RC"            "0"
eq "LIMIT: ...and union keeps it TWICE — it does not deduplicate" \
   "$(nmatch "$repo/$OBS" "$SAME")" "2"
eq "LIMIT: ...the two one-sided rows each survive once (ours)" \
   "$(nmatch "$repo/$OBS" "$OURS_ONLY")" "1"
eq "LIMIT: ...the two one-sided rows each survive once (theirs)" \
   "$(nmatch "$repo/$OBS" "$THEIRS_ONLY")" "1"
eq "LIMIT: ...for five rows in total"                    "$(nlines "$repo/$OBS")"         "5"
if json_ok "$repo/$OBS"; then ok "LIMIT: ...and every row still parses as JSON"
else bad "LIMIT: ...and every row still parses as JSON" "$(cat "$repo/$OBS")"; fi

# ── 7. LIMIT, pinned — merge=union does nothing for the fast-forward case that prompted it ──
# No merge driver runs on a fast-forward. This reproduces the original failure WITH the
# attribute in place, so nobody reads .gitattributes as having closed it.
new_repo attrs; repo="$REPO"
must git -C "$repo" checkout -q -b side
printf '%s\n' "$theirs" >> "$repo/$OBS"
must git -C "$repo" commit -q -am 'side append'
must git -C "$repo" checkout -q main        # main has NOT diverged: merging `side` fast-forwards
# Assert the setup really is a fast-forward. If main had diverged this case would be testing the
# union driver again, and its "still refused" pass would mean the opposite of what it claims.
must git -C "$repo" merge-base --is-ancestor main side
printf '%s\n' "$ours" >> "$repo/$OBS"      # ...but there is an UNCOMMITTED local append
merge_side "$repo"

if [ "$MERGE_RC" -ne 0 ]; then ok "LIMIT: fast-forward + uncommitted local rows is still refused"
else bad "LIMIT: fast-forward + uncommitted local rows is still refused" "  rc=0: $MERGE_OUT"; fi
case "$MERGE_OUT" in
  (*"would be overwritten by merge"*)
    ok "LIMIT: git gives the same 'would be overwritten' abort as before this change" ;;
  (*) bad "LIMIT: git gives the same 'would be overwritten' abort as before this change" \
          "  output: $MERGE_OUT" ;;
esac
eq "LIMIT: the fast-forward abort left the local row in place" "$(nmatch "$repo/$OBS" "$ours")" "1"
eq "LIMIT: the fast-forward abort did not bring in the branch row" \
   "$(nmatch "$repo/$OBS" "$theirs")" "0"

# ── 8. The shipped file: it resolves to union HERE, and only for the two named paths ────────
attr_of() { git -C "$ROOT" check-attr merge -- "$1" | sed 's/.*: //'; }
eq "shipped: observability ledger resolves to merge=union"  "$(attr_of "$OBS")" "union"
eq "shipped: compliance ledger resolves to merge=union"     "$(attr_of "$CMP")" "union"
eq "shipped: an unlisted judge path is unspecified"         "$(attr_of "$NEIGHBOUR")" "unspecified"
eq "shipped: a non-ledger file in the same dir is unspecified" \
   "$(attr_of coding-memory/observability-judge/notes.md)" "unspecified"
eq "shipped: nothing at the repo root is affected"          "$(attr_of README.md)" "unspecified"

# The check-attr assertions must be able to fail: run the identical query in a repo that has no
# .gitattributes and confirm it answers `unspecified` for the very path that answered `union`.
new_repo noattrs; repo="$REPO"
eq "shipped: the check-attr assertion can fail (same query, no .gitattributes)" \
   "$(git -C "$repo" check-attr merge -- "$OBS" | sed 's/.*: //')" "unspecified"

# ── 9. Anti-typo — every pattern in .gitattributes names a file that is actually tracked ────
# A misspelled path is silently inert: check-attr would still report `union` for the string in
# the file, and the ledger that matters would merge as plain text. This is the only assertion
# that reads the shipped patterns rather than the paths this test happens to believe in.
patterns="$(awk '!/^[[:space:]]*#/ && NF {print $1}' "$ATTRS")"
eq "shipped: .gitattributes carries exactly two rules" \
   "$(printf '%s\n' "$patterns" | awk 'NF{n++} END{print n+0}')" "2"
for p in $patterns; do
  if git -C "$ROOT" ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
    ok "shipped: pattern names a tracked file — $p"
  else
    bad "shipped: pattern names a tracked file — $p" "  not tracked in $ROOT"
  fi
done

printf '\ngitattributes: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
