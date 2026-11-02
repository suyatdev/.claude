#!/usr/bin/env bash
# dispatch-pane-agent.scratch.test.sh — per-agent work child, prompt.md preamble.
# Run: bash panes/dispatch-pane-agent.scratch.test.sh
#
# File-wide: the `[ cond ] && ok || bad` harness is safe here — ok()/bad() both
# end in `pass=/fail=` arithmetic assignments that always return 0, so `bad`
# never runs after a passing `ok`. SC2015's "C may run when A is true" caveat
# does not apply.
# shellcheck disable=SC2015
set -u
# shellcheck source=/dev/null
. "$(dirname "$0")/test-lib.sh"
PANES="$(cd "$(dirname "$0")" && pwd)"
DISPATCH="$PANES/dispatch-pane-agent.sh"

export PANE_HOME="$PANES"
export PANE_STATE_DIR="$TMP/state"
export PANE_ADAPTERS_DIR="$TMP/adapters"
export PANE_TERMINAL_DETECT="$TMP/detect.sh"
export CLAUDE_CODE_SESSION_ID="test-session-123"

mkdir -p "$PANE_ADAPTERS_DIR"
printf '#!/usr/bin/env bash\necho cmux\n' > "$TMP/detect.sh"; chmod 700 "$TMP/detect.sh"
# ok-adapter records its args and the role env, and succeeds; bad-adapter fails.
# The single quotes around ${PANE_AGENT_ROLE:-unset} are deliberate: it must reach
# the generated stub UNexpanded so the stub reads the dispatcher's exported value.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/adapter-args"\nprintf "%%s\\n" "${PANE_AGENT_ROLE:-unset}" > "%s/adapter-role"\necho surface:99\n' "$TMP" "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
PROMPT="$TMP/prompt.md"; printf 'judge this\n' > "$PROMPT"

# ============================================================================
# Card docs/features/pane-agent-scratch-isolation.md, checklist item 2:
# failing assertions for the dispatch subcommand's new per-run "work" dir and
# preamble-wrapped prompt.md. Self-contained -- fresh adapter/detect stubs and
# marker-based "newer" lookups, matching the house idiom above, rather than
# reusing variables set by earlier sections.
# ============================================================================
printf '#!/usr/bin/env bash\necho cmux\n' > "$TMP/detect.sh"; chmod 700 "$TMP/detect.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/wd-adapter-args"\necho surface:WD1\n' "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"

touch "$TMP/wd-marker1"
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/wd-r1.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "work-dir dispatch happy path exits 0" || bad "work-dir dispatch happy path exits 0" "rc=$rc: $out"
wd_launcher=$(find "$PANE_STATE_DIR/runs" -name launch.sh -newer "$TMP/wd-marker1" | head -n 1)
[ -n "$wd_launcher" ] && ok "work-dir dispatch: run dir located" || bad "work-dir dispatch: run dir located"
wd_run_dir="$(dirname "${wd_launcher:-/nonexistent}")"

[ -d "$wd_run_dir/work" ] && ok "a 'work' child of the run dir exists after dispatch" \
  || bad "a 'work' child of the run dir exists after dispatch" "$wd_run_dir/work"
wd_work_perms=$(stat -f '%Lp' "$wd_run_dir/work" 2>/dev/null)
[ "$wd_work_perms" = "700" ] && ok "the work dir's mode is 700" || bad "the work dir's mode is 700" "$wd_work_perms"
grep -qF "$wd_run_dir/work" "$wd_run_dir/prompt.md" 2>/dev/null \
  && ok "the work dir's absolute path appears in the prompt.md preamble" \
  || bad "the work dir's absolute path appears in the prompt.md preamble" "$(cat "$wd_run_dir/prompt.md" 2>/dev/null)"

# --- the preamble sits at the HEAD of prompt.md, and the caller's bytes
# survive verbatim even when the caller's own prompt contains a line that is
# exactly "---" (the preamble's own delimiter shape).
DASH_PROMPT="$TMP/dash-prompt.md"
printf 'line one\n---\nline two\n' > "$DASH_PROMPT"
touch "$TMP/wd-marker2"
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$DASH_PROMPT" --result-file "$TMP/wd-r2.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "dispatch with a literal '---' line in the caller's prompt exits 0" \
  || bad "dispatch with a literal '---' line in the caller's prompt exits 0" "rc=$rc: $out"
dash_prompt_md=$(find "$PANE_STATE_DIR/runs" -name prompt.md -newer "$TMP/wd-marker2" | head -n 1)
[ -n "$dash_prompt_md" ] && ok "dash-prompt dispatch: prompt.md located" || bad "dash-prompt dispatch: prompt.md located"

head -n 1 "${dash_prompt_md:-/nonexistent}" 2>/dev/null | grep -q 'Your private scratch directory for this dispatch is:' \
  && ok "the preamble occupies the head of prompt.md, ahead of the caller's bytes" \
  || bad "the preamble occupies the head of prompt.md" "$(head -n 1 "${dash_prompt_md:-/nonexistent}" 2>/dev/null)"

delim_line=$(grep -n '^--- end of dispatch preamble; the task follows ---$' "${dash_prompt_md:-/nonexistent}" 2>/dev/null | head -n 1 | cut -d: -f1)
if [ -n "$delim_line" ]; then
  tail -n +"$((delim_line + 1))" "$dash_prompt_md" > "$TMP/dash-actual-body" 2>/dev/null
else
  : > "$TMP/dash-actual-body"
fi
diff -q "$DASH_PROMPT" "$TMP/dash-actual-body" >/dev/null 2>&1 \
  && ok "the caller's prompt bytes are preserved byte-for-byte after the preamble, including its own literal '---' line" \
  || bad "caller's prompt bytes preserved verbatim after the preamble" "no preamble delimiter found, or body diverged from $DASH_PROMPT"

# --- mkdir of the work child failing dies before any pane/adapter opens.
# A PATH-prepended stub `mkdir` fails only on a path ending "/work" (the shape
# the design pins) and defers to the real /bin/mkdir for every other caller
# (mkdir -p "$RUNS_DIR", and new_run_dir's own "mkdir $RUNS_DIR/$run_id"),
# since neither of those paths ends in "/work".
MKDIR_FAIL_BIN="$TMP/mkdir-fail-bin"; mkdir -p "$MKDIR_FAIL_BIN"
cat > "$MKDIR_FAIL_BIN/mkdir" <<'MKEOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    */work) exit 1 ;;
  esac
done
exec /bin/mkdir "$@"
MKEOF
chmod 700 "$MKDIR_FAIL_BIN/mkdir"
rm -f "$TMP/wd-adapter-args"
before_launchers=$(find "$PANE_STATE_DIR/runs" -name launch.sh | wc -l | tr -d ' ')
out=$(PATH="$MKDIR_FAIL_BIN:$PATH" bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/wd-mkdirfail.md" --cwd "$TMP" 2>&1); rc=$?
after_launchers=$(find "$PANE_STATE_DIR/runs" -name launch.sh | wc -l | tr -d ' ')
[ "$rc" -ne 0 ] && ok "a work dir mkdir failure makes dispatch exit non-zero" \
  || bad "a work dir mkdir failure makes dispatch exit non-zero" "rc=$rc: $out"
printf '%s' "$out" | grep -q '/work' && ok "the mkdir-failure message names the work path" \
  || bad "the mkdir-failure message names the work path" "$out"
[ "$before_launchers" = "$after_launchers" ] && ok "a work dir mkdir failure opens no pane (no new launcher)" \
  || bad "a work dir mkdir failure opens no pane" "before=$before_launchers after=$after_launchers"
[ ! -f "$TMP/wd-adapter-args" ] && ok "a work dir mkdir failure never calls the adapter" \
  || bad "a work dir mkdir failure never calls the adapter"

# --- non-discriminating (card checklist item 6): this rides entirely on
# new_run_dir's pre-existing uniqueness guarantee and passes with or without
# the work-dir change. Kept for completeness per the card's own instruction;
# do not count it as coverage for the new work-dir feature.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/wd-adapter-args"\necho surface:WD2\n' "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
touch "$TMP/wd-marker3"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/wd-r3.md" --cwd "$TMP" >/dev/null 2>&1
l3=$(find "$PANE_STATE_DIR/runs" -name launch.sh -newer "$TMP/wd-marker3" | head -n 1)
touch "$TMP/wd-marker4"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/wd-r4.md" --cwd "$TMP" >/dev/null 2>&1
l4=$(find "$PANE_STATE_DIR/runs" -name launch.sh -newer "$TMP/wd-marker4" | head -n 1)
wd3="$(dirname "${l3:-/nonexistent}")/work"; wd4="$(dirname "${l4:-/nonexistent}")/work"
{ [ -n "$l3" ] && [ -n "$l4" ] && [ "$wd3" != "$wd4" ]; } \
  && ok "two dispatches get different work dirs (non-discriminating -- rides on new_run_dir)" \
  || bad "two dispatches get different work dirs" "wd3=$wd3 wd4=$wd4"


tl_finish
