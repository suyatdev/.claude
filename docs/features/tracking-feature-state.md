---
phase: planning
model_tier: high
branch: feat/tracking-feature-state
---

# Feature-state tracking with a browser UI

**The spec half of this feature lives in `tracking-feature-state.spec.md`** — design, the injection
route, security, and all fourteen acceptance criteria. It carries no `phase:` key, so it is not a
card and the analyzer skips it (criterion 1). Read it when a task sends you there; it is not
session-start reading, which is the whole reason for the split.

**Every `§` reference below resolves in the spec half except `§Verification`, which is in this
file** — deliberately, because task 13 writes measurements into it during implementation, when the
phase gate forbids editing a spec. The two files are one document: a task's `§Design 3` is the
manifest in the spec half, and the spec half's criteria are closed by the checklist here.

This adds a skill that derives a feature/worktree survey for a given repo, writes it as a versioned
run into a data file, and drives an **already-built** browser UI that renders it — with a control
channel that lets the UI drive the Claude session that launched it. `server.py` is the whole of the
new trust boundary.

⚠️ **The one discipline that governs both files, because it is the defect this feature keeps
producing: no count, test total or phase tally is pinned anywhere, and every code citation carries
the command that re-finds it.** Every audit and judge round here found defects overwhelmingly of one
species — a stored result that had gone stale — twice inside the correction written to fix the
previous round, and once inside a judge's own verdict. A derivation is only as good as its scope:
twice this feature prescribed a `grep` narrowed to one file to answer a question about the whole
page, and once counted *references* where the question was *files*, and was off by 4×. **Before
trusting any derivation, ask what it cannot see** — a wrong scope returns cleanly and looks exactly
like a correct result.

## Tasks

- [x] 1 — **Spike — fully done, do not re-run.** Route is `cmux send --surface`. All four probes ran
      2026-08-09 and **nothing is outstanding**; §Verification tabulates the results and
      §"Injection route" carries each finding beside its reproducing command. Two of them change the
      design rather than confirming it: `send` errors on an unresolvable ref (so the fall-through
      fear does not apply to this verb), and a resolvable-but-wrong ref delivers at exit 0 (so the
      send-time check must confirm **identity**, not existence).
- [x] 2 — Vendor the UI: copy the Nocturne export to `task-tracker/`, preserving `_ds/`. Verify the
      copied `Task Tracker.dc.html` opens and renders from the bundled `tracker-data.js`.
- [x] 3 — `task-tracker/analyze.py`: features + branches only, importing `hooks/lib/feature_tasks.py`.
      Emit schema-valid JSON. No waves yet.
      - `analyze.py` is over the 400-line target though under the 800 hard max (`wc -l` it). The clean
        split is a `task-tracker/git_facts.py` holding the worktree/ahead-behind/dirty readers. **Not
        scheduled** — a structural split is a human-owned call, not a drive-by; raise it if the file
        grows again.
- [x] 4 — `task-tracker/test_analyze.py`: criteria 1 and 2 against a fixture repo, not this one.
      (Named `test_*.py`, not `*.test.py` — pytest collects only the former.)
- [x] 5 — Waves, constraints and graph derivation, including the `## Depends on` reader and the
      "undetectable dependency becomes a question" rule.
- [x] 6 — `task-tracker/store.py` + `task-tracker/test_store.py`: atomic emit of `tracker-data.js`,
      run upsert by id. Criteria 3-5.
- [x] 7 — `PORTS.md` entry for the control server, per `allocating-local-ports`, before any bind.
      - Port is **8422**, `TASK_TRACKER_PORT` overrides. Picked clear of the 8000-8100 block other
        projects own; `lsof -nP -iTCP:8422 -sTCP:LISTEN` was empty at allocation. Task 8 reads the
        number from `PORTS.md`, it is not re-decided there.
- [ ] 8 — **Task 14 runs immediately after this one, before 9 and 10** — it keeps its number for
      reference stability, not its position; read that entry before starting 9.
      `task-tracker/server.py` to the wire contract in §Design 3: `127.0.0.1` bind on the port
      from `PORTS.md`, in-memory token injected into `GET /`, static serving confined to **the
      manifest table in §Design 3** (an explicit list — `_ds/` enumerated, not globbed; do not
      re-derive it by grep, and let criterion 13 tell you if it is wrong), the three-row allowlist,
      `X-Tracker-Token` requirement, Origin check on `/command`, **`Host` check,
      `Cache-Control: no-store` and the `Content-Security-Policy` on `GET /`**, the 30-minute idle
      timeout **and the 5-second parent-death poll that makes "exits with the session" real**, the
      **audit log** (`reason=` carries the internal cause; the wire keeps the collapsed `403`), and
      **surface binding and confirmation** exactly as §Security tabulates it: capture
      `$CMUX_SURFACE_ID` at startup, validate it with `cmux read-screen` under a 5-second timeout,
      abort on unset/non-zero/timeout, hold the UUID in memory, pass it as `--surface` on **every**
      `cmux send`, and re-confirm it against `cmux tree` before each send — `409` when confirmed
      absent, `502` when the check itself could not run. Never infer the target from `cmux tree`
      markers and never take it from a request; task 1's fourth probe delivered to the wrong live
      Claude session with a ref that resolved fine, and an omitted `--surface` types into the
      launching session rather than failing. Route is settled and every probe is closed
      (task 1) — do not re-run them. Python 3.9 — see §Toolchain before writing any annotation.
      - **Bind failure aborts the launch** (§Security): `EADDRINUSE` exits non-zero naming the port,
        no probing for a free one, nothing served. The state that prevents — two live servers with
        the browser pointed at the first while holding the second's token — is invisible from the UI,
        which sees only the collapsed `403`.
      - **Static responses carry an explicit `Content-Type` from the fixed extension map, plus
        `X-Content-Type-Options: nosniff`** (§Design 3). Not `mimetypes.guess_type`: a served type
        that varies with the host's `/etc/mime.types` is a rendering failure that reproduces on one
        machine and not the next.
      - This file carries bind + token + static serving + allowlist + header check + surface
        re-resolution + subprocess, and will land near the 400-line target. If it crosses, the split
        is `task-tracker/serve_static.py`; raise it rather than taking it as a drive-by.
- [ ] 9 — `task-tracker/test_server.py`: criteria 6, 7, 9, 10, 11, **12 and 14**, including every
      negative case and each status code in the contract table. A test that only proves the happy path
      does not close this task — **and neither does one that only proves refusals**, which is the
      failure criteria 12–14 were added to catch.
      **Criterion 13 is deliberately not in that list** — it is an agent-run browser verification, not
      a pytest test, and belongs to task 14. Do not write a source-search stand-in for it here; that
      stand-in is the thing four rounds of judging removed.
      - **The contract table carries two `500` rows** — `reanalyze_failed` and `asset_unreadable` —
        so "each status code" is satisfied by neither on its own. Assert `asset_unreadable`
        separately: make a manifest member unreadable, require `500`, an audit line whose `path=`
        carries the **manifest** path and whose `errno=` carries the symbolic name, and **no
        filesystem detail in the body**. It arrived in round 5 with nothing exercising it — the same
        shape as the audit log and the parent-death check before it, a control shipped by the round
        that was fixing the previous one and left unasserted.
      - **Two more controls that are written down and checked by nothing** — the pattern above,
        caught a round later, so they are pinned here rather than described again:
        - **`X-Content-Type-Options: nosniff` on every static response.** Criterion 13 asserts the
          `Content-Type` but not this header, and a missing `nosniff` is invisible in a passing
          render — it only matters against a browser that would have sniffed.
        - **The unmapped-extension startup abort.** Add a manifest row whose extension is absent
          from the fixed Content-Type map and require the server to **exit non-zero having served
          nothing**, proven by a `GET /` that gets no answer. This is the control that keeps the
          manifest and the map in lockstep; unasserted, the two silently drift and the first symptom
          is a stylesheet served as the wrong type.
      - Criterion 10 must assert **every** clause it lists — the token absent from files, argv, child
        environments **and the captured stderr**, and present exactly once in the served HTML
        alongside `no-store` and the CSP. Capture the server's stderr for the whole test and include
        the deliberate refusal; a criterion-10 test that never reads the log stream leaves the audit
        log unasserted, which is how it got there unasserted in the first place.
      - Criterion 12 must assert `cmux send` was **invoked**, not merely that a `200` came back. Fake
        the binary rather than typing into a real session.
        ⚠️ **The fake proves the server's decision, never that keystrokes arrive** — and writing it
        without saying so moves the live path from *visibly* untested to *apparently* tested, which is
        worse than where it started. Task 1's probe closed the *transport* half of that gap
        (`send` does reach a live Claude TUI composer — §Verification), so this task no longer waits
        on it. What the fake still cannot prove is the half task 1 also exposed: that the keystrokes
        reached the **intended** session. A fake binary records the ref it was handed; it cannot tell
        a right ref from a resolvable wrong one. Assert that the `--surface` the fake received is
        **byte-identical to the `$CMUX_SURFACE_ID` the server was started with** — that is the whole
        identity claim, and a `200` plus an invocation is not proof of correct delivery.
      - **The surface binding and confirmation are asserted here, in the same task that builds
        them** — six of them, because a control that reaches the tables one round after it reaches
        the prose is this card's second recurring shape, and the fix for it is not another paragraph:
        the three startup aborts (`$CMUX_SURFACE_ID` unset; the `read-screen` probe exiting non-zero;
        that probe timing out — each must exit non-zero, name its cause, and serve **nothing**,
        proven by a `GET /` that gets no answer), and the three send-time outcomes (confirmed
        present → `send` invoked once; confirmed absent → `409 unresolved_surface`; check
        unrunnable → `502` with `confirm_failed`/`confirm_timeout`). Drive the last one by making
        the faked `cmux tree` exit non-zero and, separately, hang past the timeout; require `cmux
        send` to be invoked **zero** times in both, and the audit line to read `sent=no`. An
        unconfirmable target that gets sent to anyway is the one bug this control exists to stop,
        and it is invisible from the wire — both refusals look identical to a caller.
      - Criterion 14 needs short `TASK_TRACKER_POLL_SECS`/`TASK_TRACKER_IDLE_SECS` overrides and a
        real parent exit; a mocked `getppid()` proves the branch compiles, not that the server dies.
      - **Bind failure has no criterion of its own, so it is asserted here.** Start a server, start a
        second on the same port; require the second to exit non-zero, to have served nothing, and to
        name the port, **and the first to still answer `GET /` with its original token**. It is a
        launch property rather than a wire property, which is why it is a task bullet — but left
        unasserted it would be this card's recurring shape exactly: a control described in prose and
        never once run.
- [ ] 10 — Wire the UI's command buttons to `POST /command` per the contract, reading the token from
      the injected `<meta name="tracker-token">`. Where `terminal-detect.sh` prints `none`, render the
      same three commands as copyable text instead (criterion 8).
- [ ] 11 — `skills/tracking-feature-state/SKILL.md`, following
      `skills/_standards/authoring-skills-and-agents.md`. Points at `managing-session-memory`; does
      not restate phase rules.
      - **This skill owns the launch, so it owns two security controls whether or not it knows it.**
        It must start `server.py` as a non-detached child with `stderr` inherited, per §Security —
        no `nohup`, no `setsid`, no `&` into a disowned shell. Detaching disables the parent-death
        shutdown silently; redirecting `stderr` sends the audit log nowhere. Both leave the code
        looking correct. Write the reason beside the command, not just the command.
- [ ] 12 — Add the skill to the Skills Catalog in `CLAUDE.md`.
- [ ] 13 — Run every suite, record before/after counts in `## Verification`. Capture before-counts
      first so a pre-existing failure is not read as a regression. Record `node --version` beside the
      counts and report the three node-guarded tests per §Verification's wording.
- [ ] 14 — **Do this immediately after task 8 and before tasks 9 and 10** — it keeps its number
      because renumbering a checklist mid-feature breaks every reference to it, but it is second in
      execution order, not last. **This task owns criterion 13.** The earlier instruction to run that
      criterion "before task 14" was unsatisfiable and is withdrawn: before the vendoring the page
      still fetches six third-party assets, so "no non-`127.0.0.1` host" fails by construction, and a
      criterion whose first directed run must fail is a criterion that gets weakened until it passes.
      Running task 14 directly after task 8 closes the window instead — the manifest is never relied
      on while unproven.

      Vendor **all six** remote assets — which is **nine local files**, because three of the six are
      stylesheets with a second hop; the §Design 3 manifest names all nine and criterion 13 asserts
      exactly them. **Criterion 13 is the
      proof, not the grep** — the grep below drafts the list, and a clean grep has twice been a wrong
      answer that looked right:
      ```sh
      grep -rn 'https\?://' task-tracker/ --include='*.js' --include='*.css' --include='*.html' | grep -v prUrl
      ```
      - React, ReactDOM, `@babel/standalone` — vendor the files and point at them by defining
        `window.__resources` in **`task-tracker/vendor-resources.js`**, pulled in by a `<script>` tag
        inserted **ahead of line 6's `support.js`** in `Task Tracker.dc.html`. A served file, not an
        inline block: the CSP carries no nonce and no `'unsafe-inline'` in `script-src`, so an inline
        map is refused (§Design 3, where the file is on the manifest and in both criterion-13 sets).
        **Do not edit `support.js`**; it is vendored third-party code with a supported hook
        (§Security).
      - The two `@phosphor-icons` stylesheets — rewrite the `<link>` hrefs in **both** `.dc.html`
        files (lines 13–14 of `Task Tracker.dc.html`; re-find with
        `grep -n phosphor task-tracker/*.dc.html`) to `vendor/phosphor/{regular,fill}/style.css`,
        and bring the font files along or the CSS resolves to nothing.

        ⚠️ **"The font files they reference" is four files per stylesheet, and vendoring all four
        breaks the build twice over.** Each `@font-face` names `.woff2`, `.woff`, `.ttf` and `.svg`
        in one `src` list, and the browser fetches only the first format it supports. Re-read with:
        ```sh
        curl -s https://unpkg.com/@phosphor-icons/web@2.1.1/src/regular/style.css | sed -n '1,10p'
        ```
        **Vendor `.woff2` only — one file per stylesheet, two in total.** Every browser that runs
        this UI supports woff2, and the other three formats are pure legacy fallback. Recorded as a
        decision rather than taken quietly, because taking the bullet literally is what a correct
        implementation would do: eight rows, six with extensions the §Design 3 map does not carry
        (startup abort) and six no browser requests (criterion 13 set-equality failure). Serving
        `.svg` would also put script-capable SVG on the token-bearing origin for no benefit.

        Keep each font beside its stylesheet — `vendor/phosphor/regular/Phosphor.woff2` and
        `vendor/phosphor/fill/Phosphor-Fill.woff2` — so the vendored `src: url("./Phosphor.woff2")`
        resolves unchanged and the only edit to either stylesheet is **deleting the three
        non-woff2 `src` entries**.
      - The Google Fonts `@import` — rewrite in **both** `nocturne.css` and
        `_ds/nocturne-<uuid>/styles.css`. The second is the one the served page actually loads;
        fixing only the first leaves the served page still fetching from `fonts.googleapis.com`.

        ⚠️ **The `@import` is only the first hop, and the second one is where the font files are.**
        The stylesheet Google returns carries **28 `woff2` references that resolve to 7 distinct
        files** — 7 unicode-range subsets × 4 weights, but Inter v20 is a *variable* font, so all
        four weights of a subset name the **same** URL. Re-read both numbers, not just the first:
        ```sh
        UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'
        curl -sA "$UA" 'https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap' \
          | tee /tmp/inter.css | grep -c woff2                      # 28 references
        grep -o 'https://fonts.gstatic.com[^)]*' /tmp/inter.css | sort -u | wc -l   # 7 files
        ```
        The browser UA is load-bearing — Google serves a different, older stylesheet to `curl`'s
        default agent. Rewriting the `@import` without bringing those files along leaves the page
        fetching a **second** remote host that no reading of the `@import` line would reveal: the
        same second-hop shape as the phosphor fonts one bullet above.

        **Vendor the `latin` subset only — which is _one_ file, not four.** ⚠️ An earlier revision
        of this bullet said "4 files, one per weight", read straight off the 28-reference count; the
        `sort -u` above is what falsifies it. Three of those four rows would be files no browser
        ever requests, and criterion 13's set equality fails on an unexpected *absence* exactly as it
        does on an unexpected `200`. **The subset scope is a product decision and carries the user's
        explicit sign-off (2026-08-10)**, not an implementation default: the UI's own strings are
        ASCII, and the realistic source of non-Latin text is a repo or branch name, which falls back
        to the system stack — visibly, not silently. Vendoring all 7 is the alternative the moment
        that stops being true, and re-widening it is a spec change, not a drive-by.

        Write the four `@font-face` blocks into **`vendor/inter/inter.css`**, all four pointing at
        the single `vendor/inter/inter-latin.woff2`, and point each `@import` at that file.
        ⚠️ **Keep each block's `unicode-range` from the upstream stylesheet.** Dropping it is the
        easy mistake and it inverts the decision above: without a range the face claims *every*
        codepoint, so a Cyrillic name renders as tofu out of the latin file instead of falling back
        to the system stack. The fallback this bullet promises only exists because of that
        descriptor.
        ⚠️ **The two `@import`s need different relative paths** — `vendor/inter/inter.css` from
        `nocturne.css`, `../../vendor/inter/inter.css` from `_ds/nocturne-<uuid>/styles.css`. A
        root-relative `/vendor/...` would work when served and break criterion 8's `file://` path,
        where it resolves against the filesystem root.
      - Close the task by **running criterion 13 in both store states** with the Claude browser
        extension, and record both request lists plus the browser version in §Verification. A grep
        returning nothing is necessary, not sufficient — the vendored font files are referenced from
        CSS, which is the exact shape four rounds of greps could not see.

      Closes the remote fetches on the token-bearing page and is what makes criterion 8's offline path
      actually pass. The CSP added in task 8 is what keeps it closed.

## Verification

**Task 1 — injection route. Closed 2026-08-09; nothing is outstanding.** Route is
`cmux send --surface`. All four probes ran live against `cmux 0.64.20 (100) [14e3400b9]`; each
reproducing command is in §"Injection route" beside the finding it produced.

| Probe | Result | Bearing on the design |
|---|---|---|
| `send` into a live Claude TUI (terminal surface), no newline | Delivered to the composer, exit 0, not submitted | The control channel works. This was the premise five rounds of spec work sat on top of |
| `send` at an unresolvable ref (`surface:9999`) | `not_found`, **exit 1**, delivered nowhere | `send` does **not** inherit `rename-tab`'s silent fall-through — the card's central fear does not apply to this verb |
| `send` at an `agent-session` surface | `invalid_params: Surface is not a terminal`, exit 1 | Clean refusal; the channel exists only for a Claude TUI in a `[terminal]` surface |
| `send` at a ref that resolved to the **wrong live Claude session** | Delivered, exit 0, `OK` on stdout | The actual hazard. A successful send reports delivery, never destination — so the send-time check must confirm *identity*, not existence |

The fourth row was not a designed probe; it happened, to a parallel session, because the operator's
own surface was inferred from `cmux tree`'s `[focused]`/`[selected]` markers while `cmux identify`
returned `surface_ref: null`. Nothing was submitted (no newline) and the composer was restored. It is
recorded here rather than tidied away because it is the only direct evidence this repo has of the
failure the whole §Security section exists to prevent, and it says something no reasoning had: the
mis-delivery is indistinguishable from success at the call site.

**Tasks 2–6 suites.** Run the pinned invocation above. It reported **53 passed** on 2026-08-09; that
number is a measurement with a date, not a contract — re-run it rather than trusting it. There is no
system `pytest` here, so `uv run` is the only invocation that works.

⚠️ **Three of those tests are conditionally skipped on a host without `node`.**
`task-tracker/test_store.py` guards three tests with `@pytest.mark.skipif(NODE is None, ...)`
(`grep -n skipif task-tracker/test_store.py`), one of them criterion 5's JS-loadability check. This
is why `node` is pinned in §Toolchain.

Precisely what is lost, since overstating it is its own defect: each node-guarded test has an
**unguarded Python sibling** asserting byte-identity and a real envelope parse
(`grep -n 'def test_' task-tracker/test_store.py`), so on a node-less host criterion 5 is *partially*
verified, not unverified. What goes missing is the independent JavaScript-engine oracle — exactly the
U+2028/U+2029 class of bug that `store.dumps`'s own docstring names as the reason it escapes them.
Task 13 must record `node --version` beside the counts, and report a skip of these three as
**"criterion 5 verified without a JS-engine oracle"** rather than either a clean pass or a failure.

⚠️ **Task 13 must record before-counts per suite, captured before touching anything**, so a
pre-existing failure is not read as a regression introduced by this feature.

`task-tracker/` carries **no pytest configuration of any kind** — the repo's only `pyproject.toml`
governs `memsearch/` alone (`find . -name pyproject.toml`), so no `addopts` and no mark deselection
applies here. Stated because an earlier revision warned about exactly that, having read a different
package's config as this one's.

