# Observability judge — RUN 7 (implementation)

- **repo / worktree:** `jg-failclosed` — `~/.claude/.claude/worktrees/jg-failclosed`
  (measured in THIS checkout; `git rev-parse --show-toplevel` confirmed before any measurement)
- **branch:** `fix/judge-guard-fail-closed-classifier`
- **head_sha:** `249beee1fc6585d8ad760cc55f70415332b9e372`
- **base:** `origin/main` @ `2b8564b68f38e242c39b3cce368c41a81859cc3e` (also the merge-base)
- **stage:** implementation
- **judged:** 2026-08-01T03:02:59Z (UTC). Filename carries the local date `2026-07-31` as instructed
  by the invocation, so the file sorts with RUNs 1–6; the JSONL `ts` is the true UTC clock.
- **tests, run by me at this HEAD:** `bash hooks/judge-guard.test.sh` → **101 passed, 0 failed**;
  `python3 hooks/lib/classify-pr-command.test.py` → **51 passed, 0 failed**. Both match the numbers
  in the invocation. Python 3.9.6.

---

## What was changed

`hooks/judge-guard.sh` is the doorman that refuses to let `gh pr create` run until a judge has
signed off on exactly the code you are about to ship. The whole branch is about the doorman having
been asleep in several different ways. This round fixes the last four.

Think of it as four separate holes in one wall:

1. **The doorman was checking the visitor's uniform instead of what they were carrying.** It looked
   at the *tool name* on the payload and, if it wasn't literally `Bash`, waved it through without
   ever reading the command. So a real `gh pr create` arriving under any other label walked past.
   Now it reads the command first, always; the name is only consulted to decide what an *empty*
   payload means.
2. **A stray file could shut down the whole house.** The hook shells out to Python, and Python was
   putting whatever directory you happened to be standing in onto its import path. An innocent file
   called `json.py` sitting in some scratch folder replaced Python's real `json` module, the hook
   choked, and — because it fails closed — *every Bash command on the machine* got blocked, with an
   error message blaming the payload, where nothing was wrong. All three Python calls now run with
   `-I` (isolated mode), which drops that directory.
3. **A comment claimed a code path was "unreachable by construction" when it wasn't.** Rewritten to
   say what is actually true.
4. **"Nothing runnable" was defined as "nothing but whitespace."** A command made of pure control
   characters (NUL, SOH, DEL) isn't whitespace, so it counted as runnable and was *allowed* — the
   same fail-open, through the back door. Now runnable means at least one character that is neither
   whitespace nor a control character.

Nothing else moved. The classifier source itself (`hooks/lib/classify-pr-command.py`) is
**untouched** by this branch; all four fixes live in `judge-guard.sh`, plus tests and documentation.

## Does it do what was intended?

Yes, and I checked it harder than reading the diff.

- **Every "red" commit was genuinely red.** I rebuilt the tree at each of the three test-first
  commits and ran the suite: `0839485` → 83/4, `2b2132c` → 88/4, `4d79114` → 97/4. The red→green
  pairs are real, not decorative.
- **Mutation testing: I undid each fix one at a time and the suite noticed.** Forcing `PY_ISOLATED=""`
  (undo fix 2) → 4 failures. Reverting the runnable test to `.strip()` (undo fix 4) → 4 failures, and
  they are exactly the four intended cases (`NUL + spaces`, `SOH`, `SOH + spaces`, `DEL`). Restoring
  the tool-name-keyed early skip (undo fix 1) → 4 failures. Removing the classifier exit-status check
  (an earlier round's fix) → 2 failures.
- **Differential test against real bash.** I put a stub `gh` on `PATH` and, for 26 command shapes,
  compared *what the hook allows* against *what bash actually executes*. **No new fail-open.** The
  only shapes that really run `gh pr create` while the hook waves them through are the four already
  enumerated in ADR 0012 as accepted-open: a quoted `PR="$(gh pr create)"`, backticks, a
  path-qualified `/usr/bin/gh`, and an `env` prefix.
- **I could not break the new runnable rule.** 21 exotic payloads — NBSP, ideographic space, ZWSP,
  soft hyphen, RLO, private-use, unassigned, BOM, U+2028, lone surrogate — all block correctly under
  `tool_name: Bash`. Where the hook *allows* an odd-separator command (`gh<NBSP>pr create`,
  `gh<VT>pr create`, `git push<CR>gh pr create`), bash agrees: it does not run `gh` either, because
  none of those characters is a bash word separator. A trailing lone surrogate blocks via the parse
  arm (Python cannot encode it), which is the correct direction. Commands of 1 KB, 100 KB and 1 MB
  are all classified correctly.
- **Fix 1 did not weaken any adjacent arm.** The change is strictly *more* blocking: a named non-Bash
  tool carrying a live command now blocks where it used to pass, and the "editor payload with no
  command passes" arm is unchanged and still asserted. I verified `Edit`/`Read`/`Write`/`SlashCommand`
  with no command still exit 0.
- **`-I` is correct at all three sites** and the probe-and-drop fallback is sound: the probe at
  `judge-guard.sh:62` runs `python3 -I -c ''`, so an interpreter that rejects `-I` *or* that needs a
  `PYTHONHOME` which `-I` suppresses will fail the probe and the flag is dropped. All three programs
  import stdlib only. I confirmed encoding is unaffected: an em-dash and a CJK command both pass
  under `LC_ALL=C`, `LC_ALL=POSIX`, `LANG=C`, `PYTHONIOENCODING=ascii` and `PYTHONUTF8=0`.
- **shellcheck at HEAD is identical to the `origin/main` baseline** (2× SC2016, 1× SC2181, all in
  pre-existing lines). The `6c5acd6` self-correction landed properly, and the corrected claim is now
  accurate.

## What could go wrong / what I'm unsure about

Three concerns. None is a behavioural defect; all three are about the *evidence*, which on this
branch is the point.

### C1 — the control-character tests assert only an exit code, so a wrong test looks identical to a right one (success_masking)

`run_payload` (`hooks/judge-guard.test.sh:300-306`) compares nothing but `$?`. The hook has two
different fail-closed doors that both exit 2: arm 4 ("a Bash call arrived with no runnable command",
`judge-guard.sh:142-146`) and arm `*` ("could not read the PreToolUse payload",
`judge-guard.sh:147-151`). The five F4 tests intend to exercise arm 4. I measured that today they
do. But nothing pins it.

This is not hypothetical — it is exactly the near-miss recorded in the invocation. Measured:

| payload as written | vs FIXED hook | vs BUGGY (`.strip()`) hook |
|---|---|---|
| `{"...","command":"\x01  "}` (committed, escaped) | exit 2 | **exit 0 — catches the bug** |
| `{"...","command":"<raw 0x01>  "}` (the rejected draft) | exit 2 | **exit 2 — misses the bug** |

The rejected raw-byte draft would have been a **vacuous** regression test: green against the very
defect it was written for, because the raw byte makes the JSON invalid and the hook blocks on a parse
error instead of on the rule. The author caught that by inspection. The suite could not have. (For a
raw NUL specifically the mechanism differs again — `payload=$(cat)` at `judge-guard.sh:42` silently
deletes NUL bytes, so the payload degrades to all-spaces and reaches arm 4 by accident.)

Two related mutations the suite does **not** catch, both left fully green at 101/0:

- removing the parser's exit-status check (`judge-guard.sh:139`, `case "$parse_rc:$parse_ok"` →
  status ignored). Note the *classifier's* twin check **is** pinned, because the suite installs
  `answer_then_fail` / `answer_then_crash` stub classifiers (`judge-guard.test.sh:248-251`). There is
  no equivalent stub **parser**, which is the asymmetry.
- reverting the post-parse assertion (`judge-guard.sh:162-165`) to the silent `exit 0` it replaced.

Cheap fix, and the suite already does it three times elsewhere: assert the message, not just the code.

### C2 — two live comments state more than the code supports (traceability)

Distinguishing live claims from the quoted, labelled-false audit trail, these two are live:

1. **`judge-guard.sh:55-57`** (repeated verbatim at **`judge-guard.test.sh:462-463`**): *"The
   classifier takes it too: it is a script file, so its own directory heads sys.path rather than the
   caller's."* Measured on this worktree's Python 3.9.6:

   ```
   python3        /tmp/showpath.py  -> sys.path[0] = <the script's directory>
   python3 -I     /tmp/showpath.py  -> sys.path[0] = .../python39.zip   (script dir ABSENT)
   ```

   Isolated mode removes the script's directory from `sys.path` entirely. The sentence describes the
   *pre-`-I`* world in a comment explaining the `-I` invocation. The conclusion it draws ("it imports
   nothing local for `-I` to hide") is true today, but the stated reason is false of the code as it
   runs, and it would tell the next editor that a sibling-module import will resolve. It will not —
   adding `import helper` beside `classify-pr-command.py` would fail closed machine-wide.

2. **`judge-guard.sh:171-172`**: *"A `$(...)`-substituted `gh pr create` is likewise caught, since it
   too really runs."* Measured: `echo $(gh pr create)` → caught (exit 2); `PR="$(gh pr create)"` →
   **not caught** (exit 0), and ADR 0012 lists that exact string in its accepted-open set. The claim
   is true of one form and false of the form the ADR calls out. The nearby header (`:15-20`) and the
   pointer to ADR 0012 (`:179`) do scope it, so this is a precision nit rather than a repeat of the
   old header overclaim — but it is the same shape, on a branch where that shape has been corrected
   three times.

### C3 — a committed verdict file is binary, so the PR will not show it (audit_trail)

`coding-memory/observability-judge/2026-07-31-fix-judge-guard-fail-closed-classifier-round6.md`
contains a **raw NUL byte at offset 6360**:

```
context: b'h` payload whose command is a lone NUL\n(`"\x00"`) survives the '
```

A prior judge wrote a literal NUL into the prose while *describing* the NUL finding. Git therefore
classifies the file as binary — `git diff --numstat` reports `-  -` for it instead of line counts,
and it will render as "Binary files differ" in the PR rather than as reviewable text. Every other
file added on this branch is clean. This is the *third* instance of the same raw-control-byte class
on this branch (test draft, my own probe script, this file), and it degrades precisely the artifact
the branch exists to protect. One byte to fix.

Not a defect in the change itself, and it predates this HEAD's four fixes — but it arrived in this
branch's diff (commit `eab1138`), so it is in scope. (For the record: an identical single-NUL file,
`2026-07-19-feature-statusline-command-round3.md`, already exists on `main`.)

### Re-confirmed, not re-reported

Verified as still true and deliberately **not** raised as findings: fails closed machine-wide by
design with no bypass variable; residual 8 (`JUDGE_VERDICTS_FILE` is test-only); residual 9 (the
matcher reads stage/repo/branch/head_sha only — I re-read `judge-guard.sh:261-262` — so a
`risk=high` verdict still opens the gate); quoted `PR_URL="$(...)"` accepted; the stdout-noise
trigger is genuinely not retired by `-I` and the ADR says so; the strict-freshness circularity;
`sudo`/`xargs`/`env`/path-qualified `gh` all enumerated in ADR 0012 as measured-open. I also
confirmed the live installed hook at `~/.claude/hooks/judge-guard.sh` is the primary checkout's Jul
17 copy (no `lib/`, no `classify_rc`), with that checkout parked on `feat/pane-split-policy` @
`8190c40` — nothing on this branch is armed on the machine, and `origin/main` does carry
`hooks/lib/classify-pr-command.py`, so arming on merge is a single atomic checkout.

## What I'd double-check before merging

1. Add a message assertion to at least the five F4 payload cases so they pin **arm 4**, not merely
   "exit 2". `run_payload` already has the shape for it; three other checks in the file do exactly
   this. Without it, the class of mistake the author caught by hand stays uncatchable by CI.
2. Fix the two sentences in C2 — one of them appears twice (hook and test file).
3. Replace the single raw NUL in the RUN 6 verdict file with the text `\x00` (or `NUL`) so the
   audit trail is diffable in the PR.
4. Confirm the endgame ordering still holds: leave the verdict commit pending, run `gh pr create` at
   `249beee` (which this verdict matches), then commit. This file plus the JSONL line are
   deliberately left **uncommitted** by me.

---

## Dimensions

| dimension | verdict | basis |
|---|---|---|
| `intent` | pass | All four RUN 6 findings addressed; diff confined to `judge-guard.sh` + tests + docs; classifier source untouched. |
| `execution` | pass | 101/0 and 51/0 run by me at this HEAD. Six mutations applied; the four that undo a real fix all go red. No new fail-open in a 26-shape differential test against real bash. |
| `trajectory` | pass | Three red commits verified genuinely red (83/4, 88/4, 97/4). `-I` probed-and-dropped rather than assumed. Two self-caught author errors recorded rather than buried; shellcheck at HEAD == `main` baseline confirms the `6c5acd6` correction. |
| `regression` | pass | Fix 1 is strictly more blocking, verified in both directions; editor pass-through arm intact; encoding unaffected under five locale/env combinations; installed hook untouched. |
| `context_budget` | pass | No rule, skill, or `CLAUDE.md` change in the diff; a hook does not load into always-on context. (`judge-guard.sh` is now ~60% comment by line — a maintainability observation, not a context cost.) |
| `traceability` | concern | C2: `judge-guard.sh:55-57` / `judge-guard.test.sh:462-463` state a `sys.path` fact that measures false under `-I`; `judge-guard.sh:171-172` claims `$(...)` substitution is caught, which is false for the quoted form the ADR lists as accepted-open. |
| `success_masking` | concern | C1: `run_payload` (`judge-guard.test.sh:300-306`) asserts exit code only and cannot separate arm 4 from arm `*`. Measured: the rejected raw-byte draft is green against the buggy hook. Two further mutations (parser exit-status check; the fail-closed assertion) leave the suite at 101/0. |
| `intent_drift` | pass | 13 files, all in scope. No dependency added, removed or upgraded. No drive-by edits. |
| `checkpoint` | pass | Strict red→green pairs, each independently revertible; the shellcheck error corrected in a follow-up commit rather than an amend, preserving history. |
| `audit_trail` | concern | C3: `...round6.md` carries a raw NUL at offset 6360, so git treats it as binary and the PR will not render it as a diff. Otherwise exemplary — both RUN 6 verdicts kept, no prior verdict overwritten, ADR 0012 records every correction including the superseded ones. |

**risk: low — confidence: high.**

Risk is low because every finding is about evidence quality, not behaviour: adversarial probing,
mutation testing and differential testing against real bash all agree the four fixes hold, and the
change is strictly stronger than what it replaced. Confidence is high because I ran both suites,
rebuilt and re-ran three historical commits, applied six mutations, and measured every claim I make
above in this worktree rather than inferring it.

### Concerns (short form)

- Control-character tests assert exit code only; cannot distinguish arm 4 from a parse failure, so the rejected raw-byte draft would have been green against the bug it targeted.
- Parser exit-status check and the post-parse fail-closed assertion are both unpinned — reverting either leaves the suite at 101/0.
- `judge-guard.sh:55-57` and `judge-guard.test.sh:462-463`: the `sys.path` claim measures false under `-I` (script dir is dropped, not prepended).
- `judge-guard.sh:171-172`: `$(...)`-substitution "is caught" is false for the quoted form ADR 0012 lists as accepted-open.
- `...round6.md` holds a raw NUL byte at offset 6360; git classifies it binary, so the PR will not render the verdict as a diff.
