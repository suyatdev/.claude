# Attribution by time — the 1066 `var/folders` lines in `layer2-would-deny.tsv`

Method: timing correlation only (burst structure, `git log`, `hooks/state/worktree-guard.log`,
session-transcript command timestamps). Deliberately independent of reading any hook test suite's
source — a separate review (`attribution-by-source.md`, not read here) does that half.

All timestamps are UTC (`Z`). The local machine clock is `EDT` (`UTC-4`) — every `git log` author
date and every session-transcript timestamp below has been converted to UTC before comparison.
`find -newermt` interprets its argument as **local** time; an early pass in this review used it
without correcting for that offset and got the wrong 4-hour window twice before the mistake was
caught (see "Errors caught" at the end). All final numbers here come from a Python script reading
`os.path.getmtime()` / JSONL `timestamp` fields directly in UTC, not from `find -newermt`.

## Step 4 table — every one of the 1066 lines

| # | Burst (UTC) | Lines | Roots | Attributed activity | Evidence | Confidence |
|---|---|---|---|---|---|---|
| 1 | 2026-09-01 22:56:01–23:49:58 | 504 | 12 (P1+paired P4) | `hooks/git-guard.test.sh`, run repeatedly during `fix/argv0-spelling-blindness` (PR #93) implementation, by session `8d556587` and its dispatched pane subagents | 3 of 12 instances match a literal `bash hooks/git-guard.test.sh` command in session `c52f52d0`'s transcript to within ~1s (22:56:00.772→22:56:01Z fixture; 22:56:59.984→22:57:00Z; 22:57:37.779→22:57:38Z — see detail below). All 12 share an identical, deterministic fixture fingerprint (one `repo` root, 19 lock events, plus 8 randomly-named `repo.XXXXXX` variant repos with lock counts `{4,4,3,3,3,2,2,1}` summing to 22, total 41) found nowhere else in the 6-week log except adjacent to other confirmed `git-guard.test.sh` runs. | STRONG |
| 2 | 2026-09-01 23:09:31–23:51:56 | 45 | 9 (P2) | `hooks/worktree-guard.test.sh`, run later in the same full-suite sweep as row 1 | Each of the 9 roots starts 108–154s after the nearest preceding row-1 (git-guard) root — a tight, repeatable delta, consistent with `worktree-guard.test.sh` sitting ~10 suites later in an alphabetical `for f in hooks/*.test.sh` sweep (one such sweep is directly observed in session `388ae163` at 23:06:39, and its own timing places `git-guard.test.sh` at ≈23:06:57 and `worktree-guard.test.sh` at ≈23:09:31 — an exact match to the row's first instance). **Correction, logged below**: an earlier pass in this review matched this to a *different*, standalone `bash hooks/worktree-guard.test.sh` command at 23:09:35.602Z in the same session — but that command was issued 4 seconds *after* the fixture (23:09:31Z), the wrong causal direction, so it cannot be the cause. The delta-consistency evidence above replaces that claim. | STRONG |
| 3 | 2026-09-02 02:55:01 | 41 | 1 (P1) | `hooks/git-guard.test.sh` | `python3 .../run_all_tests.py` issued 02:54:46.560Z in session `8d556587`, fixture 02:55:01Z (15s lag — consistent with git-guard being several suites deep in the runner's order) | STRONG |
| 4 | 2026-09-02 02:55:19 | 1 | 1 (paired P4) | same run as row 3 | 18s after row 3's root, matching the ~18–22s P1→P4 pairing seen in every other instance | STRONG |
| 5 | 2026-09-02 02:56:52 | 5 | 1 (P2) | `hooks/worktree-guard.test.sh`, same sweep as row 3 | 111s after row 3, matching the row-2 delta signature | STRONG |
| 6 | 2026-09-02 23:52:44 | 41 | 1 (P1) | `hooks/git-guard.test.sh` | Session `8d556587`'s own `count_assertions.py` scratch script issued 23:51:21.843Z, fixture 23:52:44Z (83s lag — longer than row 3's 15s, not independently confirmed to invoke git-guard.test.sh internally, since the script is an ephemeral scratchpad file no longer on disk); identical fingerprint to rows 1–5, same session | STRONG (fingerprint + session match; script-internals not directly verified) |
| 7 | 2026-09-02 23:53:02 | 1 | 1 (paired P4) | same run as row 6 | 18s after row 6, matching the pairing signature | STRONG |
| 8 | 2026-09-02 23:54:34 | 5 | 1 (P2) | `hooks/worktree-guard.test.sh`, same sweep as row 6 | 110s after row 6, matching the row-2 delta signature | STRONG |
| 9 | 2026-09-03 05:23:31 | 41 | 1 (P1) | `hooks/git-guard.test.sh` | Session `8d556587`'s `sweep_all_counts.py` issued 05:22:09.553Z and again 05:22:50.960Z; fixture 05:23:31Z (41–82s lag); same fingerprint, same session; same "script internals not directly verified" caveat as row 6 | STRONG (same caveat as row 6) |
| 10 | 2026-09-03 05:23:49 | 1 | 1 (paired P4) | same run as row 9 | 18s after row 9 | STRONG |
| 11 | 2026-09-03 05:25:20 | 5 | 1 (P2) | `hooks/worktree-guard.test.sh`, same sweep as row 9 | 109s after row 9 | STRONG |
| 12 | 2026-09-03 05:27:20 | 41 | 1 (P1) | `hooks/git-guard.test.sh` | `git push ...; python3 .../run_all_tests.py` issued 05:27:03.475Z, fixture 05:27:20Z (17s lag — matches row 3's confirmed lag almost exactly) | STRONG |
| 13 | 2026-09-03 05:27:38 | 1 | 1 (paired P4) | same run as row 12 | 18s after row 12 | STRONG |
| 14 | 2026-09-03 05:29:10 | 5 | 1 (P2) | `hooks/worktree-guard.test.sh`, same sweep as row 12 | 110s after row 12 | STRONG |
| 15 | 2026-09-05 14:55:41–14:55:42 | 2 | 1 (P3: `full`+`shallow`) | Plausibly a compliance-judge pane subagent's clone test (full clone + shallow clone) during `pane-scratch` two-layer scratch-isolation design work | Session `2266cb34` (secret-command-guard worktree) shows a dispatched judge scratch dir running `git clone --no-hardlinks -q ... "$S/clone"` (14:49:54Z) and `git clone -q --depth 1 --no-hardlinks ... "$S/shallow"` (14:50:41Z) — ~5 minutes before the fixture, and under a **fixed scratchpad path**, not a `mktemp -d` root. Naming ("shallow") matches; the actual mktemp roots in the population do not appear in any session transcript I could search. | WEAK — temporal proximity and naming similarity only; no exact-path or exact-time match |
| 16 | 2026-09-05 16:58:01–16:58:02 | 2 | 1 (P3: `full`+`shallow`) | Same activity as row 15, second occurrence | Session `d7f4ccb4` mtime 16:58:59Z, ~1 min after the fixture; same reasoning as row 15 | WEAK |
| 17 | 2026-09-11 05:29:37–05:30:51 | 10 | 2 (P2, isolated — no nearby P1) | Unknown | No session transcript found active in this window (nearest sessions in unrelated projects, mtimes 05:19–05:22, ~10 min early); no `git log` commit within ±20 min touches guard code; `worktree-guard.log` has no session activity in this window at all | UNATTRIBUTED |
| 18 | 2026-09-11 20:27:03 | 5 | 1 (P2, isolated) | Unknown | Session `f46858fd` was active 20:24–20:33 (covers this timestamp) but its Bash commands only grep `settings.json` and feature-card docs — no test-suite invocation found | UNATTRIBUTED |
| 19 | 2026-09-14 20:40:37–20:41:03 | 39 | 1 (P1, 17+22 lock events, 2 fewer than the usual 19+22) | `hooks/git-guard.test.sh` — occurs 6 seconds after `git log`'s merge of PR #103 (`1d2a475c8c`, 20:41:44 in a *different*, primary-checkout session `28ddd1b0` — that merge is unrelated to this fixture, see note) | Same deterministic fingerprint family as rows 1–14 (minor count variance, 39 vs 41, is within the fingerprint's own natural range — one other instance in the full dataset also showed 39); no exact command match located in either session active that afternoon | STRONG (fingerprint) but command source unconfirmed |
| 20 | 2026-09-14 20:40:59 | 1 | 1 (paired P4) | same run as row 19 | 22s after row 19 | STRONG |
| 21 | 2026-09-14 20:43:26–20:45:30 | 10 | 2 (P2) | `hooks/worktree-guard.test.sh`, same sweep as row 19 | 169s and 292s after row 19 — same delta family as rows 2/5/8/11/14, though the second instance's 292s is looser than the ~110–170s band seen elsewhere | STRONG (first), MODERATE (second — looser delta) |
| 22 | 2026-09-14 20:46:04 | 1 | 1 (P4, unpaired) | Unknown | No preceding P1 within 60s; no matching command found in the two sessions active that afternoon (`dc17a9f0`, `3455ca2b` had not started yet) | UNATTRIBUTED |
| 23 | 2026-09-14 20:47:58–20:48:25 | 41 | 1 (P1+paired P4) | `hooks/git-guard.test.sh` | Session `dc17a9f0` ran `bash hooks/handoff/handoff-keep-guard.test.sh` at 20:47:09 (49s before), a different, unrelated suite — not a confirmed match; same fingerprint as rows 1–14 is the only real evidence | STRONG (fingerprint only) |
| 24 | 2026-09-14 20:48:20 | 1 | (counted in row 23) | paired P4 | 22s after row 23's start | STRONG |
| 25 | 2026-09-14 20:51:45 | 1 | 1 (P4, unpaired) | Unknown | No preceding P1 within 60s; no matching command found | UNATTRIBUTED |
| 26 | 2026-09-14 20:52:11–20:52:37 | 41 | 1 (P1+paired P4) | `hooks/git-guard.test.sh` | Fingerprint match only; no command located | STRONG (fingerprint only) |
| 27 | 2026-09-14 20:52:32 | 1 | (counted in row 26) | paired P4 | 21s after row 26 | STRONG |
| 28 | 2026-09-14 20:56:12–20:56:39 | 41 | 1 (P1+paired P4) | `hooks/git-guard.test.sh` | Fingerprint match only; no command located | STRONG (fingerprint only) |
| 29 | 2026-09-14 20:56:34 | 1 | (counted in row 28) | paired P4 | 22s after row 28 | STRONG |
| 30 | 2026-09-14 20:58:21–20:58:22 | 5 | 1 (P2) | `hooks/worktree-guard.test.sh` | 129s after row 28, matching the delta family | STRONG |
| 31 | 2026-09-14 20:59:37 | 1 | 1 (P4, unpaired) | Unknown | No preceding P1 within 60s; no matching command found | UNATTRIBUTED |
| 32 | 2026-09-14 21:12:48–21:13:15 | 41 | 1 (P1+paired P4) | `hooks/git-guard.test.sh`, part of `chore/judge-ledger-commitability` verification after the 496-commit merge | Session `3455ca2b`: `bash hooks/git-guard.test.sh` issued **21:12:47.704Z**, fixture **21:12:48Z** — under 1 second. | STRONG (exact match) |
| 33 | 2026-09-14 21:13:10 | 1 | (counted in row 32) | paired P4 | 22s after row 32 | STRONG |
| 34 | 2026-09-14 21:13:19–21:13:46 | 41 | 1 (P1+paired P4) | `hooks/git-guard.test.sh`, same session as row 32 | Session `3455ca2b`: `bash hooks/git-guard.test.sh >/dev/null 2>&1; ...; bash gitattributes.test.sh ...` issued **21:13:19.273Z**, fixture **21:13:19Z** — same second. | STRONG (exact match) |
| 35 | 2026-09-14 21:13:41 | 1 | (counted in row 34) | paired P4 | 22s after row 34 | STRONG |
| 36 | 2026-09-14 21:40:09–21:40:35 | 41 | 1 (P1+paired P4) | `hooks/git-guard.test.sh` | Fingerprint match only; `3455ca2b`'s transcript ends at 21:35:49, before this instance, so it is not the source; no other session located | STRONG (fingerprint only) |
| 37 | 2026-09-14 21:40:30 | 1 | (counted in row 36) | paired P4 | 21s after row 36 | STRONG |

**Sum check:** 504+45+41+1+5+41+1+5+41+1+5+41+1+5+2+2+10+5+39+1+10+1+41+1+1+41+1+41+1+5+1+41+1+41+1+41+1
= **1066**. Matches the population exactly (verified by re-running the arithmetic in the script
below, not by hand).

### Confidence rollup

| Confidence | Lines | % |
|---|---|---|
| STRONG | 1044 | 98.0% |
| WEAK | 4 | 0.4% |
| UNATTRIBUTED | 18 | 1.7% |

Within STRONG, two evidence tiers exist and are called out per-row above:
- **Exact-second command match** (rows 1's three sub-instances, 32, 34): a literal
  `bash hooks/git-guard.test.sh` (or the `run_all_tests.py` wrapper) appears in a session transcript
  within 0–1 second of the fixture's timestamp, in the correct causal direction (command before
  fixture).
- **Fingerprint match with no located command** (several 09-14 instances): the exact deterministic
  lock-count multiset (`19+{4,4,3,3,3,2,2,1}=41`, or the single `17+22=39` variant seen once, row 19)
  appears nowhere else in six weeks of log except adjacent to confirmed instances, so the same
  generator is overwhelmingly likely even where the specific invoking command could not be found in
  an available transcript (some subagent transcripts are not retrievable, or the command never
  printed the tmp path so a text grep across sessions could not find it directly).

## Step 1 — burst structure (re-derived from the population, to the minute)

Command: `python3` scripts reading `docs/features/evidence/worktree-location-guard/layer2-would-deny.tsv`
filtered to lines containing `var/folders` (1066 of 1226 lines; verified via
`grep -c "var/folders" layer2-would-deny.tsv`).

Four fixture *shapes* exist, identified by the sub-path structure below the mktemp root
(this is a structural observation from the paths themselves, not from reading any test source):

- **P1** — `repo/.git/HEAD.lock` plus exactly 8 `repo.XXXXXX/.git/HEAD.lock` (random-suffixed
  variants) in every one of the 23 instances (verified by counting distinct variant sub-paths per
  root, not assumed): 23 roots, 941 lines total. The base `repo` root gets 19 lock events (17 in one
  instance, row 19); the 8 variants get the same lock-count multiset `{4,3,3,3,2,2,1,4}` (sum 22)
  every time — this fixed shape, reproduced identically across 23 independent invocations spanning
  two weeks, is itself strong evidence of one deterministic script.
- **P4** — a single `.git/HEAD.lock` directly under the mktemp root, no subdirectory: 26 roots,
  26 lines. 23 of these pair with a P1 root 17–22 seconds later (tight, consistent — see the pairing
  table below); 3 (all on 09-14) have no P1 partner.
- **P2** — `rebasing/.claude/.git/HEAD.lock` (×4) + `detached/.claude/.git/HEAD.lock` (×1): 19 roots,
  95 lines, always exactly this 4+1 shape.
- **P3** — `full/.git/HEAD.lock` (×1) + `shallow/.git/HEAD.lock` (×1): 2 roots, 4 lines, both on
  2026-09-05.

Bursts, resolved to the minute (grouped by a >10-minute gap between one root's last event and the
next root's first — computed by script, not by eye):

| # | Time range (UTC) | Lines | Distinct roots | Shape(s) present |
|---|---|---|---|---|
| 1 | 2026-09-01 22:56:01–23:51:57 | 549 | 33 | P1 (12), P4 (12), P2 (9) |
| 2 | 2026-09-02 02:55:01–02:56:52 | 47 | 3 | P1 (1), P4 (1), P2 (1) |
| 3 | 2026-09-02 23:52:44–23:54:34 | 47 | 3 | P1 (1), P4 (1), P2 (1) |
| 4 | 2026-09-03 05:23:31–05:29:11 | 94 | 6 | P1 (2), P4 (2), P2 (2) |
| 5 | 2026-09-05 14:55:41–14:55:42 | 2 | 1 | P3 |
| 6 | 2026-09-05 16:58:01–16:58:02 | 2 | 1 | P3 |
| 7 | 2026-09-11 05:29:37–05:30:51 | 10 | 2 | P2 only |
| 8 | 2026-09-11 20:27:03 | 5 | 1 | P2 only |
| 9 | 2026-09-14 20:40:37–20:59:37 | 184 | 14 | P1 (4), P4 (7, incl. 3 unpaired), P2 (3) |
| 10 | 2026-09-14 21:12:48–21:13:46 | 84 | 4 | P1 (2), P4 (2) |
| 11 | 2026-09-14 21:40:09–21:40:35 | 42 | 2 | P1 (1), P4 (1) |

Row sums: 549+47+47+94+2+2+10+5+184+84+42 = **1066**, matching the population total exactly (script
output, not hand-added — an earlier hand-added pass of this same table put row 9 at 175 instead of
184 and the table total 9 lines short; re-running the grouping as a script rather than re-adding by
eye is what caught it, logged under "Errors caught" below).

## Step 2 — independent clocks used

1. **`git log --all --date=iso-strict`** (1778 commits), converted from `-04:00` author-date to UTC
   and compared against each burst window (±20 minutes). Command:
   `git log --all --date=iso-strict --pretty=format:"%H|%ad|%an|%s"`.
2. **`hooks/state/worktree-guard.log`** (2242 lines, read directly from
   `/Users/marksuyat/.claude/hooks/state/`, not the committed extract, since the extract is a
   post-fix subset). **Finding, load-bearing**: none of the 70 mktemp root names in the population
   appear anywhere in this 3.9MB log — confirmed by substring-searching all 70 root basenames
   against the full log text. This is expected, not mysterious, once you notice what layer 1 logs:
   the literal Bash command text (e.g. `bash hooks/git-guard.test.sh`), not anything the script
   creates while it runs — the `mktemp -d` path is generated *inside* the test script at execution
   time and never appears in the invoking command line, so layer 1's log was never going to contain
   it regardless of how the suite was launched. (Session ids *do* appear in `worktree-guard.log` in
   the right time windows — e.g. `8d556587`, `388ae163`, `28ddd1b0`, `dc17a9f0` — which is how the
   candidate sessions below were found; the useful signal from this log is "which sessions were
   active then," not path matching.)
3. **`hooks/state/test-marker.log`** — read in full (81 lines). It records only
   commit-time BLOCK/EXEMPT decisions from `test-marker-guard.sh`, not test-suite run timestamps,
   and it stops at 2026-09-09T02:58:30 — before the 09-11 and 09-14 bursts. Not useful for this
   population.
4. **`hooks/state/test-markers/*`** — per-file JSON records of the *last* time a suite passed
   against a committed blob (written at commit time, not at every run). Checked
   `hooks%2Fworktree-guard.sh`: `written_at: 2026-09-01T16:29:54Z`, before every burst in this
   population — confirms these markers do not update on every test run and are not usable as a
   burst-timing source here.
5. **Session transcripts** (`/Users/marksuyat/.claude/projects/*/*.jsonl`), searched three ways:
   - by file mtime (via `os.path.getmtime`, converted to UTC — **not** `find -newermt`, whose
     argument is local time; this cost two wasted searches before being caught, see below);
   - by grepping Bash `tool_use` command text for `git-guard.test.sh`, `worktree-guard.test.sh`,
     `run_all_tests`, `mktemp`, `full`/`shallow`;
   - by grepping raw file text for a specific mktemp root's basename (worked once, trivially, for
     this review's own transcript; never matched a real developer session, meaning none of them
     ever echoed the mktemp path to stdout in a way that survived `tail -N` truncation).

## Step 3 — the causal-direction check (the trap named in the brief)

For every STRONG row backed by a specific command, I checked: **is the command's timestamp before
or after the fixture's timestamp?** Two cases:

- **Passed the check**: session `c52f52d0`'s three `git-guard.test.sh` calls (22:56:00.772,
  22:56:59.984, 22:57:37.779) each precede their matching fixture by 0–1 second. Session `3455ca2b`'s
  two calls (21:12:47.704, 21:13:19.273) precede or coincide with their fixtures to the same second.
  Correct direction in all five cases — a real causal link, not a coincidence.
- **Failed the check, and the finding was retracted**: my first pass matched row 2's first instance
  to session `388ae163`'s `bash hooks/worktree-guard.test.sh` command at 23:09:35.602Z. The fixture
  (tmp.cnNWZhWRAd) is timestamped **23:09:31Z — four seconds before the command was even issued**.
  A command cannot cause an event that already happened. I re-derived the actual cause from the
  delta-consistency pattern (row 2's real evidence above) instead of the specific command, and
  flagged the retraction inline in the Step-4 table rather than deleting the wrong reasoning
  silently.

This second case is exactly the trap described in the task brief ("two things happening in the same
minute is a lead, not a finding") and is reported here as a correction, not smoothed over.

## What this means for the arm-tomorrow question

If layer 2 flips from `log` to `deny` tomorrow:

- **1044 of 1066 lines (98%)** represent a developer's own habitual full-hook-regression-suite runs
  (`hooks/git-guard.test.sh` and `hooks/worktree-guard.test.sh`, run together, repeatedly, whenever
  hook code changes anywhere in the repo — confirmed across three separate branches over two weeks:
  `fix/argv0-spelling-blindness`, `fix/worktree-guard-tilde-path`'s aftermath, and
  `chore/judge-ledger-commitability`). **This is a real cost, not noise to wave away**: a `deny`-mode
  layer 2 would refuse every `git commit`/`git merge` a test fixture performs inside its own throwaway
  `mktemp` repo, because that mktemp repo still resolves to a "primary checkout" by the guard's own
  logic (it has no worktree registered for it). Arming the guard as currently written would break
  `hooks/git-guard.test.sh` and `hooks/worktree-guard.test.sh` outright — every developer run of the
  hook regression suite would start failing, not just logging. That is a concrete, named breakage a
  person would notice immediately (the suite would go from "222 passed" to hard failures), not
  "just tests, ignore it."
- **4 lines (0.4%)** are WEAK — plausibly a similar judge/scratch clone check, not confirmed.
- **18 lines (1.7%)** are genuinely UNATTRIBUTED after checking every session transcript with a
  plausible time overlap and finding no matching command in any of them.

None of the 1066 lines were confirmed as a real accidental primary-checkout write a person would
have wanted blocked — but that is a limitation of what this file's population *can* show (it was
pre-filtered to `var/folders`, i.e. exactly the mktemp-fixture population), not a finding that the
guard has no real catches elsewhere in the log.

## Errors caught during this review (logged per the "correction is a finding" instruction)

1. **Timezone bug in the first `find -newermt` searches.** The local machine clock is `EDT`
   (`UTC-4`), and `find -newermt "<UTC-looking string>"` silently interprets it as local time. Two
   early searches (for 09-14 and for a 09-01 sub-window) used UTC timestamps directly and returned
   either the wrong 4-hour window or nothing. Fixed by writing a Python script that reads
   `os.path.getmtime()` and compares in explicit UTC.
2. **Wrong causal-direction attribution for burst row 2** (see Step 3): a specific command was
   matched to a fixture it postdated by 4 seconds. Retracted and replaced with the delta-consistency
   evidence.
3. **A hand-collated version of the Step-1 burst table drifted from the machine-summed Step-4 total**
   by 9 lines (it had put the 09-14 20:40–20:59 window at 175 instead of 184). Caught by re-running
   the burst grouping as a script instead of re-adding the table by eye, and fixed in place — the
   Step-1 table above is the corrected, script-verified version (row sums 1066, matching Step 4).

## Corrections to the profile given in the task

- **1066 lines, 70 distinct mktemp roots** — confirmed exactly
  (`grep -c "var/folders" layer2-would-deny.tsv` → 1066; distinct root count via Python → 70).
- **Date totals 549/94/94/4/15/310** — confirmed exactly for every date.
- **`repo` (435), `rebasing/.claude` (76), `detached/.claude` (19)** — confirmed exactly.
- **"~23 roots with `repo.XXXXXX` variants (4 each)"** — the root count (23) is right; "4 each" is
  wrong. Actual: every one of those 23 roots has exactly 8 variant sub-repos (counted directly, not
  assumed), whose lock counts form the same fixed multiset `{4,4,3,3,3,2,2,1}` (sum 22) every time,
  not a flat 4 per variant. Total P1-variant lines are 506, not the ~92 (23 roots × 4) the "4 each"
  phrasing would imply.
- **The profile's sub-path breakdown omitted two shapes entirely**: the 26-line "singleton
  `.git/HEAD.lock` directly under the mktemp root" pattern (P4), and the 4-line `full`/`shallow`
  pattern (P3) on 09-05. Both are accounted for in the Step-4 table above.
