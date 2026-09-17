# Attribution by source — the 1066 `var/folders` would-deny lines

Method: read every candidate suite under `hooks/`, determine (a) whether it builds a git
repo inside a `mktemp -d` directory and (b) whether it performs a real HEAD-moving git
operation there, then determine whether it isolates itself from the machine's live git
config (`GIT_CONFIG_GLOBAL`, `core.hooksPath` override, or a redirected guard state dir).
A suite that does both (a)+(b) and skips isolation is a leak candidate; its literal fixture
directory names are then matched against the log's target paths.

Population: `docs/features/evidence/worktree-location-guard/layer2-would-deny.tsv`, lines
whose target path contains `var/folders`. Confirmed by direct count:

```
$ grep -c 'var/folders' layer2-would-deny.tsv
1066
```

## Result table

| fixture sub-path (under a `tmp.XXXXXXXX` mktemp root) | lines | attributed suite | confidence |
|---|---:|---|---|
| `repo/…` (shared fixture repo, bare) | 435 | `hooks/git-guard.test.sh:24` (`REPO="$TMP/repo"`) | STRONG |
| `repo.XXXXXX/…` (per-case fixture repo) | 506 | `hooks/git-guard.test.sh:91` (`mk_dir_repo()`) | STRONG |
| `.git/` directly at the mktemp root (no subdir) | 26 | `hooks/git-guard.test.sh:732-739` (`FEATURE_EXAMPLE_DIR`) | STRONG |
| `rebasing/.claude/…` | 76 | `hooks/verify-hook-wiring.test.sh:100` + `:435-441` (`new_home rebasing`) | STRONG |
| `detached/.claude/…` | 19 | `hooks/verify-hook-wiring.test.sh:100` + `:453-454` (`new_home detached`) | STRONG |
| `full/.git/`, `shallow/.git/` (2 roots, 2 lines each) | 4 | **none found** | UNATTRIBUTED |
| **Total** | **1066** | | |

935 of the 1066 lines (435+506+26 — everything but the two `verify-hook-wiring.test.sh`
groups and the 4 unattributed lines) trace to a single suite, `hooks/git-guard.test.sh`.
That suite, plus `verify-hook-wiring.test.sh`, together account for **1062 of 1066 (99.6%)**
STRONG-confidence lines. **4 lines (2 mktemp roots) remain unattributed.**

Every count above was produced by commands actually run against
`layer2-would-deny.tsv`; the exact commands are inlined in each section below so they can
be re-run.

## Step 1/2 — every candidate under `hooks/`, and its isolation status

Enumerated everything matching `hooks/*.test.sh`, `hooks/*.probe.sh`, `hooks/*.measure.sh`,
`hooks/*.replay.sh`, `hooks/lib/*.test.py`, `hooks/lib/*.py`, plus the two review/falsifier
scripts that are not suffixed `.test.sh` but build fixtures (`verify-carveout-hole.sh`,
`shell-segments-falsifier.sh`). For each I checked whether it creates a git repo under a
`mktemp -d` directory, whether it performs a real HEAD-moving operation there (not just
feeds a command string to a hook as JSON — several suites never execute the commands
under test at all), and whether it isolates itself
(`GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`/local `core.hooksPath`/redirected state dir).

Isolation directive counts, machine-checked:

```
$ grep -c "GIT_CONFIG_GLOBAL\|GIT_CONFIG_SYSTEM\|core.hooksPath\|WORKTREE_GUARD_STATE_DIR" \
    hooks/reference-transaction.test.sh hooks/worktree-guard.test.sh hooks/verify-hook-wiring.test.sh
hooks/verify-hook-wiring.test.sh:0
hooks/reference-transaction.test.sh:14
hooks/worktree-guard.test.sh:19
```

This confirms the card's claim: `verify-hook-wiring.test.sh` has zero isolation
directives (it leaks); `reference-transaction.test.sh` and `worktree-guard.test.sh` are
isolated (ruled out).

| suite | builds repo in `mktemp -d`? | real HEAD-move? | isolated? | verdict |
|---|---|---|---|---|
| `hooks/verify-hook-wiring.test.sh` | yes (`new_home()`, L100-108, one shared `TMP` per case) | yes — `checkout -q -b`, `checkout -q <branch>`, `rebase`, `checkout -q --detach` (rebasing/detached cases only) | **no** (0 directives) | **LEAKS** |
| `hooks/git-guard.test.sh` | yes (`REPO="$TMP/repo"` L24; `mk_dir_repo()` L91; `FEATURE_EXAMPLE_DIR` L732) | yes — many real `checkout`/`checkout -b`/`checkout --detach` calls building the detached-head matrix (L42, L102, L139, L156-213, L739) | **no** (0 `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`/`core.hooksPath` hits) | **LEAKS** |
| `hooks/reference-transaction.test.sh` | yes (`$TMP/repos/*`) | yes, including a deliberate `git clone` (N10, L1191-1206) | yes — 14 directives; the N10 clone case additionally forces `-c core.hooksPath="$HOOKS_DIR"` (its own local copy), so even that one exceptional case never touches the real hook or the real log | ruled out |
| `hooks/worktree-guard.test.sh` | yes | yes | yes — 19 directives (`GIT_CONFIG_GLOBAL=/dev/null` etc., L26-27) | ruled out |
| `hooks/phase-guard.test.sh` | yes (`SYMREPO`, `mkrepo`) | not checked in detail — moot | yes — `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` at L18 | ruled out |
| `hooks/create-worktree.test.sh` | yes | not checked in detail — moot | yes — L24 | ruled out |
| `hooks/feature-sync-guard.test.sh` | yes (`REPO="$TMP/repo"`, L33) | not checked in detail — moot | yes — `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` at L31 | ruled out |
| `hooks/install-layer2.test.sh` | yes | yes (it's arming/unarming `core.hooksPath` itself) | yes — every git call pins `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` per-invocation | ruled out |
| `hooks/judge-guard.test.sh` | yes — repo lives **directly at `$TMP`** (`cd "$TMP"; git init -q`, L15-16) | commit only, no checkout/rebase after init | yes — `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` at L14, set *before* `git init` | ruled out (also: even the literal path shape it would have produced, `tmp.XXXXXXXX/.git/…`, is isolated away) |
| `hooks/merge-guard.test.sh` | **no** — comment states explicitly: "every case below runs against a bare scratch directory, not a git repo" (L11-12) | n/a | n/a | ruled out — no repo at all |
| `hooks/doc-guard.test.sh` | yes (`REPO="$TMP/repo"`, L27) | **no** — only `git reset -q` (no target = no-op) and `git checkout -q -- .` (file-restore form, `--` blocks branch interpretation, never touches HEAD) | no isolation found, but moot | ruled out — no HEAD move |
| `hooks/shell-segments-falsifier.sh` | yes (`REPO="$TMP/repo"`, L122) | **no** — only `init` + one `commit` (first commit onto an unborn branch updates `refs/heads/main`, never the `HEAD` ref itself per the hook's rule 2) | no isolation found, but moot | ruled out — no HEAD move |
| `hooks/git-guard.replay.sh` | yes (`REPO="$TMP/repo"`, L146) | **no** — the `CMDS` array is fed to the hook as JSON and never actually executed; `set_state()`'s `git reset -q --hard` (no target) is a no-op ref-wise | no isolation found, but moot | ruled out — commands are data, not executed |
| `hooks/verify-hook-wiring.probe.sh` | yes (`$S/.claude`, built at C section) | **no** — only `init`+`commit` (non-HEAD) and `checkout -- settings.json` (file-restore form) | no isolation found, but moot | ruled out — no HEAD move |
| `hooks/verify-hook-wiring.measure.sh` | yes (similar to probe) | not verified in depth — same repo-building pattern as the probe, no checkout/rebase found | not checked | ruled out on pattern grounds (mirrors the probe) |
| `hooks/verify-carveout-hole.sh` | yes (`$W/r1`, `$W/r2`, `$W/r3`) | yes — real `rebase -i`, `checkout -q -b`, `merge` | **no** isolation found | **would leak in principle, but its fixture names (`r1`/`r2`/`r3`) do not appear anywhere in the population** — confirmed: `grep -E 'tmp\.[A-Za-z0-9]+/r[0-9]/' ` against the extract returns zero lines. This script apparently did not run during the window this log covers, or ran and never hit the deny path for another reason. Not a source of any of the 1066 lines. |
| `hooks/test-marker-guard.test.sh` | yes (`repo="$(mktemp -d "$TMP/r.XXXXXX")"`, L72) | not verified in depth (fixtures only `add`+`commit`, no checkout found) | no isolation found | its `r.XXXXXX` name also does not appear in the population (`grep -c 'tmp\.[A-Za-z0-9]+/r\.[A-Za-z0-9]+'` → 0) — not a source |
| `hooks/merge-guard.test.sh`, `hooks/pane-dispatch-guard.test.sh`, `hooks/scan-secrets.test.sh`, `hooks/context-handoff-watch.test.sh`, `hooks/memsearch-nudge.test.sh` | no `git init`/`git -C "$TMP"` found at all | n/a | n/a | ruled out — no repo built |
| `hooks/feature-sync-guard.sh` (the hook itself, not its test) | its `work="$(mktemp -d)"` (L183) never runs `git init` — only writes plain `.md` files and reads via `git show` against the *caller's* repo | n/a | n/a | ruled out |
| `hooks/argv0-task6-guards.probe.sh`, `hooks/argv0-task9-guards.probe.sh` | yes, but under `/tmp/<label>-probe.XXXXXX` | n/a | n/a | **out of population by construction** — `/tmp/...` on macOS is `/private/tmp`, not `/private/var/folders/...`; these can never appear in this TSV |
| `hooks/lib/write-test-marker.test.py` | yes, `tempfile.mkdtemp(prefix="marker-writer-test-")` | yes (real `git init`) | not evaluated (moot) | **out of population by construction** — Python's `tempfile.mkdtemp` with an explicit prefix never produces the `tmp.XXXXXXXX` name shape; confirmed the whole 1066-line population is 100% `tmp.` prefixed: `awk -F'\t' '{print $6}' … \| grep -vc 'tmp\.'` → 0 |

## Step 3 — matching fixture names to source

**`repo` (435 lines) and `repo.XXXXXX` (506 lines).** `hooks/git-guard.test.sh:24` sets
`REPO="$TMP/repo"` and builds the shared fixture there; `hooks/git-guard.test.sh:91`'s
`mk_dir_repo()` runs `dir="$(mktemp -d "$TMP/repo.XXXXXX")"` for every per-case repo the
detached-HEAD matrix needs (called from `unborn_repo`, `rebase_edit_stopped`, and similar
row-builders further down the file). Both literal names are unique to this one file —
`grep -rn '\$TMP/repo"\|repo\.XXXXXX' hooks/*.sh` turns up `doc-guard.test.sh`,
`feature-sync-guard.test.sh`, `shell-segments-falsifier.sh`, and `git-guard.replay.sh` as
other users of the bare `repo` name, but every one of those was ruled out above (isolated,
or never performs a real HEAD move, or never actually executes the commands). So although
the *string* "repo" is not unique to `git-guard.test.sh`, it is the only suite among the
five that satisfies both leak criteria — attribution here is by elimination on a small,
fully-enumerated set, not by name alone. Root counts also line up:

```
$ awk -F'\t' '{print $6}' wf_lines.tsv | grep -oE 'tmp\.[A-Za-z0-9]+/repo/' | grep -oE '^tmp\.[A-Za-z0-9]+' | sort -u | wc -l
23
$ awk -F'\t' '{print $6}' wf_lines.tsv | grep -oE 'tmp\.[A-Za-z0-9]+/repo\.[A-Za-z0-9]+' | grep -oE '^tmp\.[A-Za-z0-9]+' | sort -u | wc -l
23
```
— the same 23 roots host both `repo/` and one-or-more `repo.XXXXXX/`, exactly as expected
from one `git-guard.test.sh` run producing both the shared `$REPO` and several
`mk_dir_repo()` directories.

**Bare `.git` directly under the mktemp root (26 lines).** This shape means the repo's
`.git` sits *at* the mktemp root, with no subdirectory at all — which rules out `repo`/
`repo.XXXXXX` (both nest one level down) and rules out `judge-guard.test.sh`'s
`cd "$TMP"; git init` (same shape, but isolated, see table). The actual match:
`hooks/git-guard.test.sh:732`:
```
732:FEATURE_EXAMPLE_DIR="$(mktemp -d)"
733:git -C "$FEATURE_EXAMPLE_DIR" init -q -b main
...
739:git -C "$FEATURE_EXAMPLE_DIR" checkout -qb feature/example
```
`init` is exempted by the hook's own rule 3; the initial commit only updates
`refs/heads/main`, not `HEAD` (rule 2); but `checkout -qb feature/example` at L739 *does*
move `HEAD`, and because `$FEATURE_EXAMPLE_DIR` is the repo root itself, the resulting
`HEAD.lock` sits directly at `<mktemp-root>/.git/HEAD.lock` — exactly the observed path
shape, and exactly one line per invocation (one checkout). Root counts: 23 roots produced
`repo/` fixtures but 26 roots produced this bare-`.git` line; the discrepancy (all of it on
2026-09-14: 7 vs. 10 — see below) means three of that day's runs reached line 739 without
also completing the earlier `on_branch`/`detached` matrix section, consistent with the
suite being under active edit that day (2026-09-14 is the day the layer-1 tilde fix, PR
#103, landed) rather than a second source.

```
$ awk -F'\t' '$6 ~ /\/repo\//{...} ' wf_lines.tsv | … | uniq -c   # repo/ roots by date
  12 2026-09-01 | 2 2026-09-02 | 2 2026-09-03 | 7 2026-09-14        (= 23)
$ awk -F'\t' '$6 ~ /tmp\.[A-Za-z0-9]+\/\.git\//{...}' wf_lines.tsv | … | uniq -c   # bare-.git roots by date
  12 2026-09-01 | 2 2026-09-02 | 2 2026-09-03 | 10 2026-09-14       (= 26)
```

**`rebasing/.claude` (76 lines) and `detached/.claude` (19 lines).** Both are literal case
names passed to `hooks/verify-hook-wiring.test.sh:100`'s `new_home()`, which does
`h="$TMP/$1"` and then `git -C "$h/.claude" init …` — so `new_home rebasing` and
`new_home detached` build repos at exactly `$TMP/rebasing/.claude` and
`$TMP/detached/.claude`. The rebasing scenario (`:435-441`) runs `checkout -q -b feature`,
`checkout -q main`, `checkout -q feature`, and `rebase main` — four real HEAD-moving
transactions matching the observed ~4 lines/root average (76÷19 roots = 4.0 exactly). The
detached scenario (`:453-454`) runs exactly one `checkout -q --detach`, matching the
observed 1 line/root (19÷19 roots = 1.0 exactly). These names appear in exactly one file in
the whole `hooks/` tree (`grep -rln rebasing hooks/*.sh hooks/*.py` returns only this file
and `verify-carveout-hole.sh`'s unrelated error-string match) — this is the cleanest,
highest-confidence match in the whole population.

**`full` / `shallow` (4 lines, 2 roots, all on 2026-09-05).** No match found. I searched:
- Every `hooks/*.sh`, `hooks/lib/*.py`, `hooks/lib/*.sh` file for the literal strings
  `"full"`, `"shallow"`, `/full`, `/shallow` — the only hits are prose ("in full", "shallow
  history" as a comment) with no directory ever named either word.
- `git log --all -S'"shallow"' -- hooks/*` and `-S'/shallow'` — zero commits, meaning no
  version of any file under `hooks/` in the tracked history ever contained these fixture
  names, current or deleted.
- `git log --all -S'clone -q' -- hooks/*` and `-S'clone --'` — the only hit is
  `reference-transaction.test.sh`'s N10 case (commit `7142d02`), which clones into
  `$TMP/repos/cloned` (not a bare `full`/`shallow` name) and additionally pins
  `-c core.hooksPath="$HOOKS_DIR"` on that one invocation, so even if the name matched it
  could not have written to the real, machine-wide log.
- The reason this shape *would* produce exactly this log signature is documented in the
  hook itself — `hooks/reference-transaction:437-439` flags `git clone` as "a SECOND
  BREAKAGE OF THIS FAMILY... NOT COVERED" by the `git init` exemption, denied by the same
  `primary-HEAD-lock-held` clause. So this is almost certainly two `git clone` invocations
  (one full, one `--depth 1`/shallow) run directly into a mktemp directory — but I could not
  find the script that ran them anywhere under `hooks/`, tracked or historical.

**Conclusion on the 4 lines: UNATTRIBUTED.** They most likely came from an ad-hoc,
uncommitted investigation (e.g., someone manually comparing a full vs. shallow clone for an
unrelated question) rather than any suite that ships in this repo. I did not search outside
`hooks/` (session scratch directories, other repos' test suites) — that is out of scope for
"attribution by source", which is specifically about matching `hooks/` test/probe code to
log lines.

## Step 4 — accounting for all 1066 lines

See the Result table at the top; it sums to 1066, verified: `435+506+26+76+19+4 = 1066`.

## What breaks if this guard flips from `log` to `deny`

**`hooks/git-guard.test.sh` (959 lines, 967 of the 1066 lines trace to it) would stop being
runnable in its current form.** This is the suite that exists specifically because
`git-guard.sh` shipped with no tests and its guards silently stopped matching chained
commands (see its own header comment) — i.e., it is the regression test for a real
past incident, not a throwaway script. Every `on_branch`, `detached`, `mk_dir_repo`-based
row-builder, and the `feature/example` fixture all perform real `checkout`/`checkout -b`/
`checkout --detach` calls against repos that live in the primary checkout's own git
config (no `GIT_CONFIG_GLOBAL` override). Armed, the reference-transaction hook would
refuse essentially every one of those checkouts with rc=128 and an unmoved `HEAD`, which
would either abort the suite outright (its `on_branch` helper already has an explicit
"could not switch... dirty worktree?" bail that would now fire for the wrong reason) or
silently leave rows built on the wrong branch, corrupting later assertions. Either way,
this is a real cost: the suite guarding against a shipped git-guard regression would go
red or unreliable machine-wide the moment layer 2 arms, unless it is isolated first
(adding the same `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` pair that seven
other suites in this same directory already carry would fix it).

**`hooks/verify-hook-wiring.test.sh` (95 of the 1066 lines) would lose exactly two of its
~40 cases**: the "mid-rebase: check 1 runs, check 2 is skipped without comment" case
(`:441-442`) and the "detached HEAD: drift check skipped" case (`:454`). Both build their
fixture state with real `checkout`/`rebase` calls with no isolation; armed, those two
specific `new_home` calls' git operations would be refused. The other ~38 cases in this
file never call `checkout`/`rebase`/`switch` (only `init`+`commit`, which the hook does not
gate) and would be unaffected.

**The 4 unattributed `full`/`shallow` lines**: unknown impact, because the source is
unknown. If they are a one-off manual investigation, arming changes nothing recurring; if
they come from something that still runs periodically, it is invisible to this method.

## Contradictions with the profile given in the task

- The task's characterization "**23 roots** holding `repo.XXXXXX` suffixed variants (4
  lines each)" undercounts substantially: there are 23 *roots*, but 184 distinct
  `repo.XXXXXX` *directories* across them (not ~23 directories), totaling 506 lines, not
  ~92. The "4 lines each" also does not hold uniformly — the actual distribution is 23
  directories with 1 line, 46 with 2, 69 with 3, and 46 with 4 (verified: `23·1 + 46·2 +
  69·3 + 46·4 = 23+92+207+184 = 506`). Re-verify before using "4 lines each" as a citable
  figure.
- Otherwise the task's headline figures held up under direct re-measurement: 1066 lines,
  70 distinct mktemp roots (23+23+19+19+26... — note roots overlap by category, e.g. the
  same 23 roots host both `repo/` and `repo.XXXXXX/`, and the same 19 roots host both
  `rebasing/.claude` and `detached/.claude`; the true count of *disjoint* roots is 23 (repo
  family) + 19 (rebasing/detached family) + 26 (bare `.git`) + 2 (full/shallow) = 70,
  confirmed by `awk -F'\t' '{print $6}' wf_lines.tsv | grep -oE 'tmp\.[A-Za-z0-9]+' | sort
  -u | wc -l` → 70), and the date buckets (549/94/94/4/15/310) all reproduced exactly.
