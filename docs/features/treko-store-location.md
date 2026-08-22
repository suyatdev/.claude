---
phase: implementation
model_tier: high
branch: feat/treko-store-location
compliance_verdict: pass  # rounds 2-5, 2026-08-22; subject blob 348364d (content at 4fc3479)
adr: 0034  # verified free against origin/main; 0026 is duplicated, 0028 unused
---

# Treko: give the analysis store a home outside every repo

Planned 2026-08-22 on `docs/close-treko-rename` @ `bedb65f`, immediately after card 1 merged
(PR #64). Model-switch checkpoint 1 (entering planning): **asked and answered** — stay on Opus 5,
because the change touches the server's path-containment guard.

> **Gate status: OPEN.** `gate confirmed` given 2026-08-22 after PR #65 merged (`e6a9bb6`), with
> compliance PASS on rounds 2-5. Branch `feat/treko-store-location` cut from `origin/main` @
> `e6a9bb6`. **Model-switch checkpoint 2 (planning -> implementation): asked and answered — stay
> on Opus 5. Do not re-ask.** The spec is frozen from here: an edit during implementation is a
> phase violation *and* invalidates the compliance verdict by blob. If it proves wrong, stop and
> say "GATE: Spec change needed — switch back to the high-tier model."

This is a **follow-on to card 1**, not one of the numbered cards 2-5. It ships no new tracker
behaviour and no UI change: the browser asks for the same URL and renders the same page.

## Why

Treko writes exactly one artifact — `tracker-data.js`, the file the page loads — and it writes it
into its own source directory, `treko/`, which is inside a git repository that tracks it. So the act
of surveying a repo dirties that repo. Observed 2026-08-22: pressing `reanalyze` once produced a
**6,170-line diff** on a tracked file in a checkout whose only open PR was a docs-only closeout. The
change had to be reverted by hand before the branch could be pushed.

Two things make this worse than untidiness:

- **The tool surveys other repos.** `--repo` points the analyzer anywhere, but the result is always
  written back into `treko/` — so a survey of repo B dirties repo A. The store already holds runs
  from `.claude`, `memsearch` and others side by side (`repoUrls` in the envelope).
- **A tracked artifact invites a bad merge.** `tracker-data.js` is generated, large, and conflicts
  on any branch that regenerates it. The two `verdicts.jsonl` ledgers already cost this repo
  repeated merge-union work for exactly this reason.

## Decisions taken during brainstorming (2026-08-22)

Each was a user decision, recorded here so the implementation does not relitigate it.

1. **The default moves out of the repo**, rather than staying put behind an opt-in flag. A default
   that must be remembered every session does not solve a problem that appears silently.
2. **The four existing runs are copied once**, not abandoned. `analyze.py` reports the present, so
   the snapshots dated `2026-08-20T03:07:28Z` (`guard-memsearch`, `pane-orchestration-v2`,
   `statusline-wrap`, `statusline-followups`) cannot be regenerated.
3. **Configuration is one environment variable**, matching the four the server already reads. No
   CLI flag, no config file — a second precedence rule is a second thing to get subtly wrong.
4. **A corrupt legacy file aborts the launch** rather than starting empty. Silently beginning with
   no data is how four unreproducible snapshots disappear unnoticed.

## Scope

### In

- A configurable store **directory**, canonicalized; the filename stays constant.
- Startup validation of that directory, on the existing `StartupAbort` path, creating it `0o700`.
- A new module `treko/store_location.py` holding all three (D5) — `server.py` is at 790 of 800 lines.
- One serving branch so `GET /tracker-data.js` reads the configured file.
- A one-time, validated copy of the legacy store, announcing which outcome occurred.
- Removing `treko/tracker-data.js` from git and ignoring it.
- **ADR 0034**, and the `TREKO_STORE_DIR` row in `skills/treko/SKILL.md`.

### Out

- **Per-repo store directories.** One store holding several repos' runs is the current behaviour and
  arguably the feature; keying by repo is a separate design.
- **A `--store-dir` flag or a config file** (decision 3).
- **Renaming the file or changing the envelope.** ADR 0023: the data contract is owned externally.
- **Anything the numbered cards 2-5 own** — the Ledger, the dashboard upgrades, the agent panel,
  the analyzer's up/down traversal.

## Deferred — the UI half, from the updated prototype

Added 2026-08-22 at the user's direction: **record it here, build it later.** Source of truth is the
prototype revision dated that day at
`~/Other Docs/AI/AI_Projx/Prototypes/Treko/Treko/`. None of it is in this card's scope; it is written
down so the later cards inherit a decision instead of rediscovering one.

**On the Ledger page (card 2).** An `Artifacts path · where snapshots are written` field, placeholder
`~/.treko/runs` — **placeholder text, not the default this card sets** (see D1) — beside the queue
form's directory / repo / branch / worktree inputs (`Ledger.dc.html:41-54`).

**On the board, as a Configuration drawer (card 3).** A gear button opens a right-hand drawer
(`Task Tracker.dc.html:112`, `:406-460`) with three sections: **Artifacts** (the same directory path
plus a Save button and a "Saved" confirmation), **Appearance** (Dark / Light cards driving
`body[data-theme="light"]`, persisted, defaulting to dark), and **Layout** (sidebar width with a
reset).

### The one thing that must be settled before either ships

**The prototype stores the path in `localStorage` (`taskTracker.artifactsPath`), and that cannot
work here.** The prototype is a `file://` page with no server; in this repo the *server* decides
where it writes. A path typed into the page changes a browser key and nothing on disk — the field
would read as configuration while configuring nothing, which is precisely the failure
`rules/core-conduct.md` names: a control that looks like a measurement and is not.

Making it real means a **new `/command` verb** carrying the path to the server, and today that
endpoint does exactly three things — `clear`, `handoff`, `reanalyze` — none of which take a
filesystem path. Accepting one from the page means the server creates and writes a directory at an
address the browser supplied. That is a trust-boundary extension of the same weight as D3, and it
earns its own design and its own judge round. **Until it exists, the path field is display-only or
absent — never an input that silently does nothing.**

**Appearance is not in that trap.** A theme is genuinely browser-local state, so `localStorage` is
the right home for it and no server change is needed. It can ship on its own, cheaply, ahead of the
path field.

**Port, never copy.** Our `Treko.dc.html` is a *sibling revision* of the prototype's
`Task Tracker.dc.html`, not a stale copy of it — overwriting ours with theirs already cost a rework
once during card 1. Whoever builds these takes the markup deliberately, diffing both.

## Background: the three facts the design turns on

Read these before the design; each is load-bearing and each was verified in the tree at `bedb65f`.

**1. The page names the file, the server resolves it.** `Treko.dc.html:16` is a plain
`<script src="tracker-data.js"></script>`. Over `http://` that is a request for the *URL*
`/tracker-data.js`, and nothing in the page constrains which file on disk answers it. This is the
seam the whole design rests on: the store can move without the page changing at all.

**2. Serving is containment-checked against one root.** `server.py:505-523`, condensed — the
`resolve()` call carries its own `except OSError` in the real body:

```python
def _serve_static(self, path):
    relative = path.lstrip("/")
    if relative not in STATIC_MANIFEST:
        return self._fail(404, "not_found", "not_found")
    target = SERVE_ROOT / relative
    resolved = target.resolve()
    if SERVE_ROOT not in resolved.parents:
        return self._fail(403, "forbidden", "path_escape", path=relative)
```

`SERVE_ROOT` is `treko/` (`server.py:123`) and `STATIC_MANIFEST` is a deliberately closed list of 17
rows. A file outside `SERVE_ROOT` is refused today — so moving the store is a change to a security
check, not to a path constant. That is why this card exists rather than a one-line edit.

**3. `tracker-data.js` is already the one special row.** `FIRST_RUN_OPTIONAL = "tracker-data.js"`
(`server.py:121`) is the single manifest row permitted to answer `404` instead of `500` when absent,
because before the first analysis it does not exist. The design extends a special case that is
already there rather than inventing one.

## Design

### D1 — Resolution: one directory, one constant filename

`TREKO_STORE_DIR` names a **directory**. The filename stays `tracker-data.js`, pinned by the page's
`<script src>` and by ADR 0023.

```yaml
store_dir:
  env: TREKO_STORE_DIR
  default: "${XDG_STATE_HOME:-$HOME/.local/state}/treko"
  value_is: directory          # never a file path
  expansion: [user (~) via expanduser]
  no_expansion: [environment variables inside the value are NOT expanded]
  relative_paths: resolved against the process cwd
  canonicalization: Path(value).expanduser().resolve()   # symlinks followed, see below
  stored_as: the canonical absolute path, in config["store_dir"]
store_file:
  name: tracker-data.js        # constant; ADR 0023 owns the contract
  full_path: <canonical store_dir>/tracker-data.js
  dir_mode: 0o700              # on creation only; see D2
  file_mode: unchanged         # store.py's DEFAULT_FILE_MODE (0o644), preserved on replace
```

**`XDG_STATE_HOME` is the right variable of the XDG set**: a survey is regenerable state — data
you would be annoyed to lose but that can be rebuilt — which is neither cache nor configuration.
`~/.local/state` is its documented fallback, and honoring the variable means the machine's
convention wins without Treko needing to know what it is.

**The prototype's `~/.treko/runs` is illustrative, not a decision.** It appears as placeholder text
in the Configuration drawer and the Ledger; the user confirmed on 2026-08-22 that the real default
is ours to set. A middle revision of this card read it as authoritative and adopted it — recorded
here so the next reader does not re-derive that mistake from the prototype.

The discoverability argument for a visible `~/.treko/` does not survive contact with D2: the startup
banner names the resolved directory on **every** launch, and the deferred Configuration drawer will
display it once card 3 ships. Nobody has to guess where the data went, which was the only thing the
home-directory dotdir bought.

**Canonicalization is not cosmetic — it is the whole correctness of D3.** The containment check
compares against `target.resolve()`, which always returns a symlink-free path. If `store_dir` were
stored as given, a directory reached through a symlink would never appear in `resolved.parents` and
**every** request for the store would 403. This is not hypothetical on the target platform:
`Path("/tmp").resolve()` is `/private/tmp` on macOS, so `TREKO_STORE_DIR=/tmp/treko` breaks the tool
completely unless the stored value is canonical too. Both sides of the comparison are canonical, or
the feature does not work.

Resolution lives in `read_store_dir(environ=None)`, taking `environ` for the same reason `read_port`
and `read_timeout` do — so tests inject rather than mutate the process. It lives in a **new module**,
not in `server.py`; see D5.

### D2 — Startup validation, on the existing abort path

Order matters: validation runs inside the `try` block in `main()` that already wraps `read_port`,
`read_timeout`, `check_manifest_types`, `check_index_injectable`, `resolve_repo` and `bind_surface`,
so a bad value exits `2` with its reason on stderr **before anything is served**.

| Condition | Outcome |
|---|---|
| directory absent | created **mode `0o700`**, parents included; launch continues |
| path exists and is a directory, writable | launch continues; existing mode is left alone |
| path exists and is **not** a directory | `StartupAbort`, naming the path |
| directory cannot be created or is not writable | `StartupAbort`, naming the path and the errno |

Creating a missing state directory is standard for the XDG state location and is not a silent
fallback: it creates the configured target, never a different one.

**Why `0o700`, and why only on creation.** The old store was one file inside one repo. The new one
is a single shared home-directory location aggregating surveys of *every* repo the user analyses —
branch names, feature-card titles, filesystem paths, and which work is in flight. That is a broader
collection than what it replaces, so it is created owner-only, per the default-deny rule in
`rules/core-conduct.md`. An **existing** directory's mode is never changed: silently tightening a
directory the user already made and may share is not this card's call.

The store *file* keeps `store.py`'s existing behaviour unchanged — `DEFAULT_FILE_MODE = 0o644`
(`store.py:39`), with an existing file's mode preserved across the atomic replace (`:148-150`,
`:180`). A `0o700` parent already prevents other users from reaching it, and changing the file mode
would alter documented behaviour in a module this card otherwise only calls.

**Startup says which directory it chose.** The existing banner
(`server: http://127.0.0.1:8422/ surface=… idle=…s poll=…s`) gains the resolved store directory. A
`TREKO_STORE_DIR` with a typo in it is a *valid* path — it starts cleanly and writes real data
somewhere the operator is not looking, producing stderr identical to a correct launch. One line
removes the whole class. Raised by the observability judge, round 1.

**Stderr order is pinned, because two lines now claim the same slot.** The banner is written at
`server.py:777` -- after `webbrowser.open`, after the watchdog starts, immediately before
`serve_forever`. The copy in D4 runs during startup validation, near the top of `main()`. So the
order is **copy outcome first, banner last**, and the banner is the final line before the audit
stream begins. Neither line is "the first line"; a spec that said so would be false on the machine
it describes.

### D3 — Serving: one branch, containment preserved

`_serve_static` gains a single branch. The manifest check stays first and unchanged, so **no URL
becomes reachable that was not reachable before** — the store's URL is already a manifest row.

```python
if relative == FIRST_RUN_OPTIONAL:
    root, target = self.config["store_dir"], self.config["store_path"]
else:
    root, target = SERVE_ROOT, SERVE_ROOT / relative
# ... resolve(), then: if root not in resolved.parents -> 403 path_escape
```

The containment check is **re-pointed, not removed**: a symlink planted in the store directory that
resolves outside it is still a `403 path_escape`. `FIRST_RUN_OPTIONAL`'s existing `404`-when-absent
behaviour is unchanged, which is what keeps a first launch from reporting `500`.

`build_config` (`server.py:691`) grows `store_dir` alongside the existing `store_path`; every other
consumer — `run_reanalyze` (`:345`), the `reanalyze` command handler (`:624`) — already takes the
path as an argument and needs no change.

### D4 — The one-time copy

Runs once, at startup, before serving:

```
Given the configured store does not exist
And   treko/tracker-data.js does exist
Then  read it through store.read_store and write it through store.write_store
```

Going through the store module rather than copying bytes means the copy is **validated** (it must
parse as an envelope) and **atomic** (`write_store` writes a temp file in the target directory and
`os.replace`s it — `store.py:160-181`). A `StoreError` from the read aborts the launch, naming the
file, per decision 4.

The guard is the conjunction: a legacy file is copied **only** when the destination is absent, so a
later launch can never overwrite a real store with a stale one.

**The copy announces which of its three outcomes happened.** `copied N runs from <path>`,
`store already present, legacy file ignored`, and `no legacy store to adopt` are three different
states that would otherwise all print nothing — and the one that matters, a migration that silently
did not run, would be indistinguishable from one that did. On a one-shot data move that is the
difference between noticing four lost snapshots and not. One stderr line, on the same stream as the
banner and the audit lines. Raised by the observability judge, round 1.

> **Atomicity note.** `write_store` places its temp file in the *target's* directory, so the temp
> and the target are always on one filesystem and `os.replace` stays atomic. The copy therefore does
> not become a cross-device move. Do not "optimise" this into a temp file elsewhere.

### D5 — Where the new code lives: a new module, not `server.py`

**`treko/server.py` is 790 lines against this repo's 800-line hard maximum** (`rules/core-conduct.md`;
`analyze.py` is 797, tighter still). Measured 2026-08-22 at `bedb65f`. The file is deliberately
comment-heavy — most of its bulk is the reasoning behind its security decisions — so three new blocks
of logic land it over the limit on the task that adds them, not eventually.

So D1, D2 and D4 ship as **`treko/store_location.py`**, a new module with one job: decide where the
store lives, prove that place is usable, and adopt a legacy store once.

```
read_store_dir(environ=None)        -> canonical absolute Path      (D1)
ensure_store_dir(path)              -> Path, or raises StartupAbort (D2)
adopt_legacy_store(store_path, legacy_path) -> one of three outcomes (D4)
```

It imports `store` for reading and writing, and raises the `StartupAbort` `server.py` already
defines — so the abort type moves to a place both can import rather than being duplicated. `server.py`
gains only an import, one call in `main()`, one key in `build_config`, and D3's branch: **roughly a
dozen lines, keeping it under 800.** Verify with `wc -l` in task 11, don't assume.

This also makes the delicate parts testable without a server: resolution, validation and the copy are
pure functions over paths, so their tests need no socket, no port, and no cmux surface.

### D6 — What leaves git

`git rm --cached treko/tracker-data.js` plus a `.gitignore` entry. The file stays on disk so the
copy in D4 can find it, and is ignored from then on. `tracker-data.sample.js` and
`tracker-data-fallback.js` **stay tracked**: they are vendored assets the page depends on, not
artifacts the tool generates.

## Scenarios

Good, bad, and edge, in the order they run.

```gherkin
Scenario: default location, nothing configured
  Given TREKO_STORE_DIR is unset
  When  the server starts
  Then  the store path is <XDG_STATE_HOME or ~/.local/state>/treko/tracker-data.js
  And   the directory exists afterwards

Scenario: configured location wins
  Given TREKO_STORE_DIR is set to a writable directory
  When  the server starts
  Then  the store path is inside that directory
  And   no file is written under treko/

Scenario: the configured path is a regular file
  Given TREKO_STORE_DIR names an existing regular file
  When  the server starts
  Then  it exits 2 naming that path
  And   nothing is served

Scenario: the configured directory cannot be created
  Given TREKO_STORE_DIR is under an unwritable parent
  When  the server starts
  Then  it exits 2 naming the path and the errno

Scenario: the legacy store is adopted exactly once
  Given the configured store does not exist
  And   treko/tracker-data.js holds 4 runs
  When  the server starts
  Then  the configured store holds those same 4 runs, by id
  And   a second start does not rewrite it

Scenario: a real store is never overwritten by the legacy file
  Given the configured store exists and holds 1 run
  And   treko/tracker-data.js holds 4 different runs
  When  the server starts
  Then  the configured store still holds exactly its 1 run

Scenario: a corrupt legacy file stops the launch
  Given the configured store does not exist
  And   treko/tracker-data.js is not parseable as an envelope
  When  the server starts
  Then  it exits 2 naming that file
  And   the configured store is not created as an empty envelope

Scenario: the browser reads the configured store
  Given the configured store holds a run
  When  the browser requests /tracker-data.js
  Then  the response is 200 with that file's bytes
  And   the Content-Type is text/javascript with nosniff

Scenario: first run, before any analysis
  Given the configured store does not exist
  And   no legacy file exists
  When  the browser requests /tracker-data.js
  Then  the response is 404, not 500
  And   the page falls back to the vendored sample

Scenario: a symlink planted in the store directory
  Given <store_dir>/tracker-data.js is a symlink to a file outside <store_dir>
  When  the browser requests /tracker-data.js
  Then  the response is 403 and the audit line reads path_escape

Scenario: the manifest is still closed
  When  the browser requests any path not in STATIC_MANIFEST
  Then  the response is 404
  And   no path outside SERVE_ROOT or <store_dir> is readable

Scenario: a store directory reached through a symlink still serves
  Given TREKO_STORE_DIR is /tmp/treko-test on macOS, where /tmp is a symlink to /private/tmp
  When  the server starts and the browser requests /tracker-data.js
  Then  the response is 200, not 403
  And   config["store_dir"] holds the canonical /private/tmp/... form

Scenario: a newly created store directory is owner-only
  Given TREKO_STORE_DIR names a directory that does not exist
  When  the server starts
  Then  that directory exists with mode 0o700

Scenario: an existing store directory keeps its mode
  Given TREKO_STORE_DIR names an existing directory with mode 0o755
  When  the server starts
  Then  its mode is still 0o755

Scenario: the banner names the directory it resolved
  When  the server starts
  Then  the banner line -- the last line before serving -- includes the resolved store directory
  And   it is preceded by the copy's outcome line, never followed by it

Scenario: the copy says which of its three outcomes happened
  When  the server starts
  Then  exactly one of "copied N runs from <path>", "store already present, legacy file
        ignored", or "no legacy store to adopt" appears on stderr
```

## Acceptance criteria

1. `TREKO_STORE_DIR` unset resolves to `${XDG_STATE_HOME:-$HOME/.local/state}/treko`; set, it wins.
2. A surveyed repo is never written to: after a `reanalyze` against any repo, `git status` in both
   that repo and this one is unchanged.
3. All four scenarios in D2's table hold, each exiting `2` before serving where specified.
4. The legacy copy runs exactly once, preserves all 4 run ids, and never overwrites an existing
   store; a corrupt legacy file aborts the launch.
5. `GET /tracker-data.js` serves the configured file with `text/javascript` + `nosniff`; absent, it
   is `404`; symlinked out of the store directory, it is `403 path_escape`.
6. `STATIC_MANIFEST` remains the closed list; no probe reaches a file outside `SERVE_ROOT` or the
   store directory.
7. `treko/tracker-data.js` is untracked and ignored; `tracker-data.sample.js` and
   `tracker-data-fallback.js` remain tracked.
8. The full suite passes with **no test lost** — node-ID set diff against the pre-change set, per
   the lesson recorded in card 1's criterion 4. A changed total is not a regression; a lost node is.
9. `skills/treko/SKILL.md` documents `TREKO_STORE_DIR` and the default, and its live test
   (no `nohup`/`setsid`/`2>`/`&` on any `server.py` line) still passes.
10. `config["store_dir"]` is canonical: a symlinked `TREKO_STORE_DIR` serves `200`, not `403`.
11. A directory this card creates is mode `0o700`; one that already existed is left at its own mode.
12. Startup stderr names the resolved store directory, and exactly one of the copy's three outcome
    lines is printed on every launch.
13. `wc -l treko/server.py` is **under 800** after the change, measured rather than assumed, and
    `treko/store_location.py` is a file of its own.

## Pinned versions

| Tool | Version | Where it is fixed |
|---|---|---|
| Python | 3.9.6 | the interpreter this repo's suite runs under; `server.py` is stdlib-only |
| pytest | 8.4.2 | test runner |

No new dependency. `pathlib`, `os` and `shutil` are stdlib. Adding a dependency would need a
separate ask (`rules/core-conduct.md`, Parallel-Agent Invariants).

## Tasks

- [x] 1. Record the pre-change suite: full node-ID set and per-module counts, and `wc -l` of
      `server.py`, from a run in this tree.
- [x] 2. Red tests (`test_store_location.py`) for D1: default when unset, env var wins, `~` expanded,
      relative resolved, **and the canonical form for a symlinked path**.
- [x] 3. Red tests for D2: the four table rows, plus `0o700` on creation and mode untouched when the
      directory already exists.
- [x] 4. Create `treko/store_location.py` with `read_store_dir` + `ensure_store_dir`; move
      `StartupAbort` somewhere both modules import; tasks 2-3 go green.
- [x] 5. Red tests for D4: copy once, never overwrite, abort on corrupt, and one line per outcome.
- [x] 6. Implement `adopt_legacy_store`; task 5's tests go green.
- [x] 7. Red tests for D3: serves configured bytes, 404 absent, **403 on a symlink out of the store
      dir**, **200 through a symlinked store dir**, manifest still closed. **Plus the banner's new
      content**: the line names the resolved store directory, and it follows the copy's outcome
      line. Criterion 12 has two halves and both get a red test -- task 5 covers the copy's, this
      covers the banner's.
- [x] 8. Wire `server.py`: import, `main()` call, `build_config`'s `store_dir`, `_serve_static`'s
      branch, and the banner line. Task 7's tests go green.
- [x] 9. Untrack `treko/tracker-data.js`, add the `.gitignore` entry, verify the sample and fallback
      are still tracked.
- [x] 10. **ADR 0034** — the trust-boundary change, where the tool's data lives, and the accepted
      `file://` degradation. **0034 is verified free against `origin/main`** (which tops out at
      0033); note that "next free number" is ambiguous here because **0026 is duplicated**
      (`…symbolic-ref…` and `…the-gate-does-no-json-parsing…`) and 0028 is unused.
- [ ] 11. `skills/treko/SKILL.md`: the `TREKO_STORE_DIR` row, the default path, and the `0o700` note.
- [ ] 12. Post-change suite: node-ID set diff vs task 1, per-module counts, zero lost nodes, and
      `wc -l treko/server.py` under 800.
- [ ] 13. Launch for real (`--open`), press `reanalyze`, and confirm by `git status` that neither
      repo was touched — the criterion-2 check nothing automated can make.
- [ ] 14. Observability judge, then the PR.

## Risks

- **Weakening the traversal guard by accident.** The whole design hinges on re-pointing one
  containment check rather than removing it. Task 6's symlink and closed-manifest tests are the
  guard on the guard, and both must be seen failing before D3 is written.
- **A second store appearing.** If any consumer keeps deriving `SERVE_ROOT / "tracker-data.js"`
  independently, the page and the writer drift onto different files and the UI silently shows stale
  data. `build_config` must remain the only place the path is constructed.
- **`file://` mode degrades.** Opening `Treko.dc.html` directly will no longer find a real store
  beside it, so `tracker-data-fallback.js` loads the sample and the page shows its
  `TRACKER_DATA_SOURCE = 'sample'` state with the amber source dot. Accepted, not solved: that mode
  has no control channel and is already degraded by design. It must be stated in the ADR, because a
  reader who opens the page directly will otherwise read sample data as their survey.
- **`server.py` is 10 lines from the hard maximum.** 790 of 800, measured at `bedb65f`. D5 exists
  to keep the new logic out of it, but the wiring in task 8 still adds lines to the file that is
  nearly full. If task 12's `wc -l` comes back at 800 or more, the answer is to move more logic into
  `store_location.py` — never to delete comments, which in this file carry the reasoning behind its
  security decisions.
- **The migration runs in a repo that no longer has the legacy file.** After task 8 a fresh clone has
  no `treko/tracker-data.js` at all, so the copy is a no-op — correct, but it means the migration
  path is exercised on exactly one machine. Task 4's tests must synthesise the legacy file rather
  than relying on the real one.

## Verification

### Task 1 — pre-change baseline

Measured 2026-08-22 in this worktree at `a0326ee`, tree clean, Python 3.9.6 / pytest 8.4.2.

```
cd treko && python3 -m pytest -q                    # 192 passed in 118.62s
cd treko && python3 -m pytest --collect-only -q | grep '::' | sort   # the node-ID set
```

**The full suite is 192 tests across 7 modules, not the 163 carried in earlier notes.** That
figure came from a five-file invocation that omitted `test_autolaunch.py` (10) and
`test_rename.py` (19) — 29 tests, both real card-1 modules that collect and pass. Criterion 8
diffs against the 192-node set below; a subset would have hidden 29 nodes from the "no test lost"
check.

| Module | Collected = passed |
|---|---|
| `test_analyze.py` | 26 |
| `test_autolaunch.py` | 10 |
| `test_rename.py` | 19 |
| `test_server.py` | 83 |
| `test_server_lifetime.py` | 9 |
| `test_store.py` | 30 |
| `test_ui_commands.py` | 15 |
| **total** | **192** |

Sorted node-ID set, `sha256`: `16d7aca052e5f9fd2cf107931d82f2eeafea76f164b2408e1db073b82ba50e24`.
The set itself is regenerable from this commit — collect at `a0326ee` and re-sort — so task 12
compares sets, not just totals. There is no `pytest.ini`, `pyproject.toml` or `setup.cfg` in
`treko/` or the repo root, so no `addopts` deselects anything.

Line counts at `a0326ee`: `server.py` **790**, `analyze.py` **797**, `store.py` **212** — D5's
premise holds, and criterion 13's budget is 10 lines.

### Tasks 2-3 — red tests for D1 and D2

`treko/test_store_location.py` added, 13 tests, importing `read_store_dir`, `ensure_store_dir`
and `StartupAbort` from the not-yet-created `treko/store_location.py`.

```
cd treko && python3 -m pytest test_store_location.py -q
```

Collection fails as expected: `ModuleNotFoundError: No module named 'store_location'`
(`test_store_location.py:41`).

A collection error cannot distinguish "13 tests red" from "one broken file", so a throwaway
stub (`store_location.py`, both functions raising `NotImplementedError`, never committed) was
added, the file re-run, and all 13 tests confirmed failing individually, each on
`NotImplementedError` and none on a collection error — then the stub was deleted and
`git status` confirmed only `test_store_location.py` remained untracked.

Full suite with the new file's collection error allowed through
(`python3 -m pytest -q --continue-on-collection-errors`): **192 passed, 1 error** — the 192
matches task 1's baseline exactly (zero regressions in the existing modules), and the 1 error
is `test_store_location.py`'s expected `ModuleNotFoundError`.

### Task 4 — `store_location.py` implemented, tasks 2-3 green

Measured 2026-08-22 in this worktree, Python 3.9.6 / pytest 8.4.2.

```
cd treko && python3 -m pytest test_store_location.py -q     # 13 passed in 0.01s
cd treko && python3 -m pytest -q                             # 205 passed in 118.60s
wc -l treko/server.py                                        # 787
python3 -c "import server; print('server import OK')"        # server import OK
```

205 = task 1's 192 baseline + these 13, with zero pre-existing test lost or changed.
`server.py` moved from 790 to 787 lines: the `StartupAbort` class definition was removed and
replaced with a one-line import from `store_location`. `ensure_store_dir`'s "existing
directory not writable" branch reports `errno.EACCES` rather than a value read off a failed
syscall, since `os.access` itself never raises — no test exercises that branch; the mkdir
failure path (which a test does cover) reports the real `OSError.errno`.

### Closing D2's untested row — `EACCES` was assumed, never observed

Not a bug fix: on this machine no case was found where the assumed `errno.EACCES` was wrong,
because `os.access` also consults macOS ACLs and a real write there does fail with `EACCES`.
It is a change from an assumed value to an observed one — the prior code named a specific
errno with the authority of a measurement while it was a constant the code chose, since
`os.access` only ever answers yes/no and never reports why.

Step 1, 2026-08-22, this worktree: `test_reports_the_path_and_an_errno_when_an_existing_directory_is_not_writable`
added to `treko/test_store_location.py`, pinned green against the current `os.access`
implementation — it asserts the row's shape (an abort naming the path and *an* errno) and
deliberately not `EACCES` specifically, so step 2 needs no test edit.

```
cd treko && python3 -m pytest test_store_location.py -q     # 14 passed in 0.02s
```

Commit `99dbf1a4b7108c52f547d6b1e96efb8abaf3f29d`, `treko/test_store_location.py` only.

Step 2, 2026-08-22, this worktree: the `os.access` check replaced with a real write attempt —
`tempfile.NamedTemporaryFile(dir=str(path))`, the same directory `store.py`'s `write_store`
writes its temp file into before `os.replace`, so the probe fails exactly when the real write
would. On `OSError` the message now carries `exc.errno` / `exc.strerror`, not `errno.EACCES`.
The now-unused `import errno` was removed from `store_location.py`.

```
cd treko && python3 -m pytest test_store_location.py -q     # 14 passed in 0.01s
cd treko && python3 -m pytest -q                             # 206 passed in 118.99s
wc -l treko/server.py treko/store_location.py                # 787, 88
```

206 = task 4's 205 + the one test step 1 added, zero pre-existing test lost or changed. Neither
test in `test_store_location.py` needed editing for step 2 to pass. `server.py` is unchanged at
787 lines; `store_location.py` moved from 81 to 88 lines.

### Task 5 — red tests for D4

`treko/test_store_location.py` gained 6 tests covering `adopt_legacy_store(store_path,
legacy_path)`: adopts once (compared by run id, not count), a second launch does not rewrite
(bytes and `st_mtime_ns` both unchanged), an existing real store is never overwritten by a
different legacy file (the destructive-overwrite guard, tested directly rather than as a
corollary), a corrupt legacy file raises `StartupAbort` naming the file and never creates the
destination, no legacy file yields `"no_legacy"` with no file created, and the `copied N runs`
line is checked against a 2-run fixture (distinct from the other tests' 4) so a hardcoded
`"copied 4 runs"` cannot pass. Every stderr assertion checks `capsys`'s captured lines equal a
one-element list, not merely that the expected text appears. D4 does not spell out the return
value's exact form, so this file pins one: three plain strings, `"copied"`, `"already_present"`
and `"no_legacy"` — the contract task 6 is being given.

**Red for the right reason**, 2026-08-22, this worktree: a throwaway stub
(`adopt_legacy_store` raising `NotImplementedError`, never committed) was added to
`treko/store_location.py` so the 6 new tests' failures could be told apart from the existing
14's, then removed.

```
cd treko && python3 -m pytest test_store_location.py -v
# 6 failed, 14 passed in 0.05s — each new test fails on its own assertion or on
# NotImplementedError; none on a collection error; all 14 D1/D2 tests still pass
git diff HEAD -- treko/store_location.py   # empty after the stub was reverted
```

Without the stub, `adopt_legacy_store` does not exist at all, so the module-level import at
the top of `test_store_location.py` fails and the *whole file* — including the 14 tests tasks
2-3 already turned green — errors at collection, the same shape task 1's baseline had before
task 4 landed:

```
cd treko && python3 -m pytest -q --continue-on-collection-errors
# 192 passed, 1 error in 119.27s — the 192 matches task 1's baseline exactly; the 1 error is
# test_store_location.py's ImportError: cannot import name 'adopt_legacy_store'
```

192 + 1 error is expected and correct for a tests-only commit: `adopt_legacy_store` is task 6's
job. The 14 tests hidden behind that collection error are proven still-passing above, by the
stub run, per this task's instructions.

### Task 6 — `adopt_legacy_store` implemented, task 5's tests green

Measured 2026-08-22 in this worktree, Python 3.9.6 / pytest 8.4.2.

```
cd treko && python3 -m pytest test_store_location.py -q     # 20 passed in 0.02s
cd treko && python3 -m pytest -q                             # 212 passed in 117.37s
wc -l treko/server.py treko/store_location.py                # 787, 143
```

212 = task 5's 206 baseline + these 6, zero pre-existing test lost or changed.
`treko/server.py` is untouched at 787 lines (this task edits `store_location.py` only, per
its scope); `store_location.py` moved from 88 to 143 lines.

The guard is the conjunction from D4: `store_path.exists()` is checked first (a present
destination is never overwritten, regardless of what the legacy file holds), then
`legacy_path.exists()` (never `store.read_store`, which returns a fresh empty envelope for
a missing file instead of raising — treating that as "found" would report every ordinary
launch as a successful adoption of nothing). Only when both checks pass does the function
read through `store.read_store` and write through `store.write_store`; a `StoreError` from
the read becomes a `StartupAbort` naming the legacy file, and since `write_store` is never
reached on that path, `store_path` is never created.

**The fourth state D4 does not name — a configured store already present and no legacy
file at all — was not asked for a new outcome.** It falls into the existing
`store_path.exists()` branch: outcome `"already_present"`, stderr line
`"store already present, legacy file ignored"`. This is the ordinary case on every launch
after the first, and on a fresh clone forever once task 9 untracks
`treko/tracker-data.js`. No test in `test_store_location.py` pins this specific
combination directly — the closest is
`test_an_existing_real_store_is_never_overwritten_by_the_legacy_file`, which covers
"store present, legacy also present" (checked to end at the same `"already_present"`
branch, but with a legacy file that exists), not "store present, legacy absent". The
branch is exercised only incidentally, by `test_a_second_launch_does_not_rewrite_the_
already_adopted_store`'s second call — at that point the fixture's legacy file still
exists on disk, so even that call does not isolate the "no legacy at all" combination.
Stated plainly: this exact combination is implemented but not directly tested.

### Task 6 follow-up — the fourth state's line was false

The paragraph above was wrong to accept: routing "store present, legacy absent" into the
`"already_present"` branch means `adopt_legacy_store` prints "store already present, legacy
file ignored" when there is no legacy file to ignore. That is not a rare corner — it is what
prints on every launch after the first, and permanently on every fresh clone once
`treko/tracker-data.js` is untracked. `rules/core-conduct.md`: a message that reads as a
measurement must be one.

Fixed by reordering the guard: ask `legacy_path.exists()` first. All four states still land
on D4's three lines (absent/absent and present/absent both report `"no_legacy"`), so
acceptance criterion 12 still holds, and every line is true whenever it prints. Red test
added first, in its own commit (`99c22dc`): store present, legacy absent → outcome
`"no_legacy"`, stderr exactly `["no legacy store to adopt"]`, store left byte-identical —
confirmed failing against the pre-fix order (`'already_present' == 'no_legacy'`) before the
reorder landed.

Measured 2026-08-22 in this worktree, Python 3.9.6 / pytest 8.4.2.

```
cd treko && python3 -m pytest test_store_location.py -q   # 21 passed
cd treko && python3 -m pytest -q                           # 213 passed in 118.37s
```

213 = task 6's 212 baseline + this one new test. The other 20 tests in
`test_store_location.py` are unaffected by the reorder: it is a straight conjunction with
distinct early returns per branch, and the swap only changes behavior for the one combination
(store present, legacy absent) that had no test pinning it before this commit.

### Tasks 7-8 — D3's serving branch, and the banner

Measured 2026-08-22 in this worktree, Python 3.9.6 / pytest 8.4.2.

**Task 7 (`5ca769d`).** Seven new nodes, split along the seam `test_server.py` and
`test_server_lifetime.py` already document: the five wire-shape ones and the two
manifest-closed controls in the first, criterion 12's banner half in the second. Putting the
banner test in `test_server.py` would have taken that file to ~800 itself; it is 770 as it
stands, and the banner is a launch-shape property by the same rule that put criterion 14 there.

```
cd treko && python3 -m pytest -q     # 215 passed, 5 failed in 120.67s
```

Five drivers, each failing on its own assertion, none on collection:

| Node | Failed on |
|---|---|
| `test_the_configured_store_directory_is_what_is_served` | served the tree's bytes, not the store's |
| `test_a_configured_store_that_does_not_exist_yet_is_404_not_500` | store written where configured, still `404` |
| `test_a_store_file_symlinking_out_of_the_store_directory_is_403` | `200`, not `403 path_escape` |
| `test_a_symlinked_store_directory_serves_200_not_403` | served the tree's bytes |
| `test_the_banner_names_the_resolved_store_directory_after_the_copys_outcome` | zero of D4's three lines printed |

The two `test_a_file_planted_in_the_store_directory_stays_off_the_manifest` nodes passed before
the change and after it — recorded as controls, not drivers, because a criterion-6 test that
only starts passing once D3 lands would be asserting the wrong thing.

`404`-when-absent is not falsifiable on its own: a server still reading the tree answers `404`
for the same request, since that is the file the test unlinks. So the test writes the store
where the configuration points and repeats the request; only a server reading the configured
directory answers `200`.

`server_harness.server_env` now points `TREKO_STORE_DIR` at the per-test `tree`. Left to the
default, every launch in the suite would resolve to the machine's real
`$XDG_STATE_HOME/treko` — the suite would read, and `reanalyze` would rewrite, the live
survey. Naming the tree also leaves every pre-existing test's store at `<tree>/tracker-data.js`,
which is why none of them changed.

**Task 8.** `server.py`: `import store_location`; `ensure_store_dir(read_store_dir())` and
`adopt_legacy_store` inside `main()`'s existing `try`; `store_dir` in `build_config` with
`store_path` derived from it; D3's two-line branch in `_serve_static`; `store=%s` on the banner.
The token and `config` lines moved inside the `try` so the copy takes its destination from
`config` — `build_config` stays the only place the store path is constructed.

```
cd treko && python3 -m pytest -q     # 220 passed in 119.70s
wc -l treko/server.py                # 799
```

**Criterion 13 measured, not assumed: `server.py` is 799 lines — one under the ceiling.** The
first wiring landed at 801. Two comments of this change's own were cut to fit; no surrounding
code was touched to make room. `store_location.py` is a file of its own at 146 lines. There is
now one line of headroom, so any further work on `server.py` moves logic out rather than adding.

220 = the 213 at `d5804fb` plus these 7. Criterion 8's node-ID set diff is task 12.

### Task 9 — what leaves git

```
git rm --cached treko/tracker-data.js
git check-ignore -v treko/tracker-data.js   # .gitignore:109
git ls-files treko/ | grep tracker-data
```

Untracked and ignored; still 207,489 bytes on disk, which is what lets D4 adopt it. Still
tracked, per D6: `tracker-data-fallback.js`, `tracker-data.sample.js` — and
`tracker-data.json`, which D6 does not name and this card therefore does not touch. Whether
that file is generated too is worth a look, but it is a separate question from this one.

The suite could not have caught the fresh-clone consequence on its own: `build_tree` copied
the real store into every test tree, so the tests that read it passed here and would have
failed on a clone that has no such file. `d935185` builds the tree's store from the tracked
sample instead, verified with the real file moved aside (96 passed, 1 skipped; restored
byte-identical) and with the counterfactual (disabling the sample copy fails exactly the two
nodes that read the tree's store).

### Task 10 — ADR 0034

`docs/decisions/0034-the-store-leaves-the-repo-and-the-guard-is-repointed.md`, 224 lines, one
Mermaid flowchart (validated with `skills/diagramming-technical-docs/scripts/validate-diagrams.sh`:
`1 block(s), 0 failed`).

**Number re-verified at the moment of writing, not trusted from the card.** `0034` is free against
`origin/main` (`e6a9bb6`, tops out at `0033`), against every local and remote ref
(`git for-each-ref` + `git ls-tree` over `refs/heads` and `refs/remotes`, zero hits for
`003[4-9]`), and against the working tree of all four checked-out worktrees. Local `main`
(`e937006`) is a **stale ancestor** of `origin/main`, so a local `ls` or a `main`-relative check
would have been reading the wrong ref.

**Every citation resolved before it was written down.** All 29 `file:line` refs were extracted from
the finished ADR and checked to resolve inside a real file at a real line; the nine bare `:N` refs
were each opened by hand. Three errors of my own were caught by that sweep and fixed:

| Claim as first drafted | Measured | Fix |
|---|---|---|
| the `file://` sample is "nine-month-stale" | sample `generatedAt` is `2026-08-09T02:41:07Z`, **13 days** before today | rewritten — and the point is *stronger*: a 13-day-old stamp is a weak signal, not an obvious one |
| "the server already reads four environment variables" | `server.py` reads four `TREKO_*` vars (`:43`, `:47-49`) **plus** `CMUX_BIN` (`:54`) and `CMUX_SURFACE_ID` | narrowed to "four `TREKO_*` variables", with the `environ`-injection shape cited |
| "four of the runs ... are dated `2026-08-20T03:07:28Z`" | that stamp is the **envelope's** `generatedAt`; the four run objects carry no such field | reworded, and the four run ids named |

**A claim in this card's own §Risks does not hold, and the ADR records the measured version
instead.** §Risks states that over `file://` the page "shows its `TRACKER_DATA_SOURCE = 'sample'`
state with the amber source dot." Measured on this branch: `TRACKER_DATA_SOURCE` is written at
`treko/tracker-data-fallback.js:18` and **read nowhere** — `git grep` over the whole repo returns
that one assignment in code and no reader. The indicator is driven by a different variable,
`srcDot: window.TRACKER_DATA ? 'var(--ok)' : 'var(--warn)'` (`Treko.dc.html:633`), and the shim sets
`window.TRACKER_DATA` by loading the sample. So the dot is **green** and the tooltip reads
**"tracker-data.js loaded"** over vendored sample data. There is no amber state to reach.

Not a design error and not a criterion: no acceptance criterion, and no part of D1-D6, depends on
it. The card is frozen, so §Risks is **left unedited** — the correction lives in the ADR, which is
where §Risks itself says this must be stated. Flagged rather than fixed: the page is out of this
card's scope, and how the UI reports its own data provenance belongs with the deferred
Configuration drawer.

Mitigation that does hold: over `http://` with `--open`, `server.py:773-774` runs the analyzer when
the store has no runs, so a real store exists before the browser opens. The silent-sample case
remains reachable over `file://`, and over `http://` when started without `--open` against an empty
store.
