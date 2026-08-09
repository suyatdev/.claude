# Observability judge — `feat/tracking-feature-state`, round 4 (architecting)

- **Repo:** `tracking-feature-state` (worktree of `suyatdev/.claude`)
- **Branch:** `feat/tracking-feature-state`
- **HEAD:** `81d98dc82a8f8b622ce9cf3e39e00b2aa56d1e17`
- **Base:** `origin/main`
- **Stage:** architecting — advisory, non-blocking. The compliance judge holds the gate.
- **Artifact:** `docs/features/tracking-feature-state.md` (752 lines), ADRs `0022`, `0023`, **`0024` (new)**
- **Timestamp:** 2026-08-09T18:52:14Z

> Filename note: rounds 2 and 3 were recorded as separate `-roundN` files in this directory, so this
> round follows that precedent rather than appending into
> `2026-08-09-feat-tracking-feature-state.md`. The dispatch named
> `2026-08-09-tracking-feature-state.md`, which does not exist — the branch slug is
> `feat-tracking-feature-state`.

---

## What was changed

Picture the card as the blueprint for a doorbell wired into a room where Claude has every tool
switched on. Round 3 found that the *doorbell camera* existed but recorded the wrong thing: it wrote
down which door the server **meant** to open, not which one actually opened, and it labelled every
refusal with the same useless word.

Round 4 fixes the camera and, more importantly, goes after the *reason* the card keeps getting things
wrong. The recurring mistake was never a wrong fact — it was a **search narrowed to one file used to
answer a question about the whole page**. Two of those were live in the card:

- The list of things the page downloads from the internet said "two stylesheets, no remote
  JavaScript". The real answer is **six assets** — React, ReactDOM and Babel are pulled in at runtime
  by `support.js`, where no search of the HTML could ever see them.
- The list of files the server is allowed to hand out was missing `tracker-data.sample.js`, which a
  small shim writes into the page on the very first run — so a first-time user would have got a broken
  page.

Both lists are now derived with a repo-wide search that is written into the card as *the rule*, not
as an answer to copy. Alongside that: a new `sent=` field in the log that admits when the server
genuinely cannot say whether keystrokes landed; a real mechanism for "the server dies with the
session" (it watches for its parent going away); a browser policy header that stops a hostile page
framing the UI and tricking you into clicking `clear`; and a new ADR 0024 recording all of it.

## Does it do what you wanted?

Yes on all five of my round-3 items. I re-ran every derivation rather than trusting the text:

| Round-3 item | Verdict | Evidence I ran |
|---|---|---|
| 1. `reason=` should carry the **internal** cause | **Closed** | Card:330–337 enumerates ten internal causes; wire keeps the single collapsed `403` (Card:304–306). ADR 0024:57–60 records the temptation and why it was refused. |
| 2. `surface` logged intent, not effect | **Closed, and well** | Card:338–347 adds `sent=yes\|no\|unknown`, where `unknown` = "cmux was invoked and did not exit 0 — I cannot say whether anything was typed". That is precisely the unreconstructable case I named. |
| 3. "Exits with the session" had no mechanism | **Closed on paper** | Card:447–457 — `os.getppid()` recorded at startup, polled on the idle timer. `prctl(PR_SET_PDEATHSIG)` correctly rejected as absent on macOS. **See concern 1 — nothing tests it.** |
| 4. Card cited no ADR; 0022 omitted the audit log | **Closed** | Card:127–136 now cites 0022, 0023, 0024. ADR 0024 (67 lines) records the audit log, the CSP and the lifetime, and declares itself an extension of the immutable 0022. |
| 5. Do not split into a `.spec.md` pair | **Honored** | Revision history cut from 86 → 19 lines (Card:733–752), with the reasoning kept. No split proposed. **But see concern 4 — the card still grew.** |

And the factual claims hold up. I re-ran every command the card prescribes:

| Claim | Command I ran | Result |
|---|---|---|
| Six remote assets across nine reference sites | the card's repo-wide `grep -rn 'https\?://' task-tracker/ …` | **Exactly six distinct assets; exactly nine sites** (phosphor ×2 files ×2 = 4, three `support.js` URLs = 3, Google Fonts ×2 = 2) |
| All three scripts carry `sha384` SRI | `grep -n 'sha384' task-tracker/support.js` | **True** — `support.js:1144,1146,1148`. The card corrects its own earlier "no SRI" claim. |
| Vendoring hook is `window.__resources`, no edit to `support.js` | `grep -n '__resources' task-tracker/support.js` | **True** — `support.js:1150-1152` reads the map and uses a non-empty string as `src` |
| Two `new Function` sites force `'unsafe-eval'` | `grep -n 'new Function' task-tracker/support.js` | **True** — lines 844 and 1218 |
| Closure includes `tracker-data.sample.js` | `grep -rnE '(src\|href)=' task-tracker/ --include='*.html' --include='*.js'` | **True** — `tracker-data-fallback.js:19` `document.write`s it |
| `nocturne.css` is *not* in the closure | same | **True** — only `Task Tracker Directions.dc.html:12` loads it, and that file is not served |
| "53 passed on 2026-08-09" | `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q -rs` | **53 passed**, 0 skipped, 4.77s |
| Python 3.9.6 / uv 0.11.28 / node v26.5.0 / cmux 0.64.20 (100) [14e3400b9] | each `--version` | **all four exact** |

That is the best-evidenced round this card has had.

## What could go wrong / what I'm unsure about

### 1. The lifetime mechanism repeats last round's mistake, one layer out — and it is on the security control

This is the finding I would act on before anything else.

Round 3's criticism was: *you added the audit log and no test asserts it.* Round 4 fixed that
(criterion 10 now scans captured stderr — Card:549–571). But **the same round added a second
security control, the bounded lifetime, and gave it no test at all.**

I grepped the whole card. `idle`, `getppid`, `parent-death`, `TASK_TRACKER_IDLE_SECS` appear only in
§Security (Card:443–457) and in task 8's checklist line (Card:604). **Not one of the eleven acceptance
criteria mentions the lifetime.** Task 9 lists criteria 6, 7, 9, 10, 11 — none is a lifetime test.

So the entire suite goes green with a server that never exits. The card's own argument for the
in-memory token is *"dying process, dead token"* (Card:439) — the security of the credential rests on
a bound that nothing checks.

Three concrete ways it fails silently:

- **The poll period has no number.** "Worst case the server outlives its session by one timer tick"
  (Card:455) reads as negligible, but the only interval in the card is the **30-minute** idle
  threshold. If the tick is the threshold, "one tick" is half an hour of an orphaned full-permission
  control channel. The card itself argues, two sentences earlier, that *"an unspecified timeout is
  implemented as no timeout"* (Card:445–446) — the lesson was applied to the threshold and not to the
  interval that now leans on it.
- **"Launch it as a child of the session" has no launch contract.** Round 3 asked how the server is
  launched; the card still does not say (the only pointer is task 11's SKILL.md, Card:358). The
  `getppid()` check is now load-bearing on that unspecified detail, and both plausible launches break
  it in opposite, silent directions: started from a transient tool shell, the parent exits immediately
  and the server suicides on the first tick; `nohup`/`setsid`'d to survive, the parent is already
  `launchd` at startup and the check **never fires**. Neither shows up as an error.
- **The same unspecified launch underwrites the audit log.** "stderr, which the launching session
  already captures" (Card:322) is still an assumption about the harness, carried over unexamined from
  round 3.

One acceptance criterion — *given a server whose parent has exited, then it exits within N seconds and
a subsequent POST is refused* — converts all three from stated to proven, and forces the interval to
get a number.

### 2. "No other file is reachable" is untested for files *inside* `task-tracker/`

Criterion 11 (Card:572–574) tests only paths resolving **outside** the directory — `../../`, absolute
paths, symlinks. Nothing asserts that a path *inside* `task-tracker/` but outside the closure is
`404`ed. The files that would leak are not hypothetical:

```
task-tracker/analyze.py  store.py  test_analyze.py  test_store.py  github.md
tracker-data.json  .thumbnail
```

Given the servable list has now been wrong **three separate times**, this is the one directory where
"it isn't in the list" deserves an assertion rather than trust.

Related, smaller: the closure is written as `_ds/**` (Card:250) while the section calls itself a
"closed, enumerated set" (Card:193). `_ds/` actually holds **five** files — `_ds_manifest.json`,
`_adherence.oxlintrc.json` and `readme.md` beyond the two the page loads. A glob is not an enumeration.

### 3. The closure derivation has the same blind spot it was written to fix — for the assets task 14 adds

The new rule is `grep -rnE '(src|href)=' … --include='*.html' --include='*.js'`. **It cannot see CSS
`url(...)` references.** Today that costs nothing — I checked, the only `url(` hits are the two
`@import`s already tracked as asset 6 (`nocturne.css:2`, `_ds/…/styles.css:2`) plus a parser
internal at `support.js:1499`.

But task 14 vendors the two `@phosphor-icons` stylesheets locally, and the card itself notes "the icon
font files they reference must come along" (Card:637). Those fonts are referenced from inside the
vendored CSS by `url()` — invisible to the prescribed derivation. An implementer who follows the rule
as written builds a server that `404`s its own icon fonts. The card hedges with "plus whatever local
paths task 14's vendoring creates" (Card:251), which is honest but is exactly the kind of
judgment-shaped gap this round set out to eliminate. Adding `--include='*.css'` and a `url\(` branch
closes it.

### 4. The card got bigger, not smaller — the cut was outweighed 2:1

| | Round 3 | Round 4 |
|---|---|---|
| Lines | 662 | **752** |
| Bytes | 45,121 | **52,146** |
| Revision history | 86 | 19 |
| §Design | 201 | **276** |
| §Security | 53 | **97** |

The 87-line cut landed exactly as recommended. It was then outweighed by ~177 lines of additions. The
additions are substantive — the six-asset table, the CSP and its caveat, the closure rule, `sent=` —
so this is not padding. But the card is now the largest it has ever been, it is read at session start,
and it sits at `phase: planning`. If you want the cut to have meant something, the six-asset table and
the closure derivation are the two blocks that could move into ADR 0024 with a pointer left behind.

### 5. Three round-3 findings survive verbatim

I diffed `41b586c..HEAD` and confirmed these were not touched:

- **The analyzer failure table still contradicts its own first row.** Card:152–153 — *"Every case
  below yields a `questions[]` entry … and the run still emits"* — followed immediately by
  Card:157: *"Abort this run … **Nothing is written**."* Same blanket-claim-versus-enumeration shape
  the round fixed in the wire contract, left in place two hundred lines above it.
- **§Design 2's "by construction" claim is still false as written.** Card:174–176 says the store
  module has no access to the token *"by construction, since the token exists only inside the running
  server process"* — but `reanalyze` runs the store **inside that very process**, so the stated reason
  argues the opposite of the claim. What is actually true is narrower and verifiable: `store.py`
  never reads the token (I re-grepped — clean).
- **ADR 0023's owner pointer is still unresolvable.** Line 46 says a missing field means "a
  conversation with whoever owns the export" while the card has (correctly) removed the export path.
  `task-tracker/github.md` exists and would close it.

### 6. Smaller enumeration gaps in the new log spec

- **`sent=` is undefined for accepted `reanalyze`** — one of the three allowlisted commands, and the
  one that never invokes `cmux` at all. It is neither `yes`, nor a refusal, nor an invocation that
  failed.
- **`sent=no` is defined as "every `409`, every `403`"** (Card:342) but the contract table also has
  `400`, `404`, `405`, `413`, `415` and `500`. Same blanket-then-narrower-list shape as concern 5.
- **`outcome` has no mapping to status codes** — is `502` `failed` or `refused`? Is `409`?

### 7. The phase gate still blocks task 8, and the record of why is now gone

I re-ran the hook against the next file task 8 creates:

```
$ printf '{"tool_name":"Write","tool_input":{"file_path":".../task-tracker/server.py"}}' \
    | bash hooks/phase-guard.sh
phase-guard: write blocked — task-tracker/server.py
...
There is no bypass environment variable; this guard ships without one by design.
EXIT=2
```

Unchanged from round 3: frontmatter says `phase: planning` with 7 of 14 tasks `[x]` and ~1,000 lines
of committed Python. My round-3 recommendation was to record the `implementation → planning`
regression in the revision history — that section has since been deleted, so the anomaly a restoring
session will hit is now documented nowhere at all. It needs a line in the card body or the ADR, not
in a history that no longer exists.

### 8. `analyze.py` is 8 lines from the hard ceiling

`wc -l task-tracker/analyze.py` → **792**. The card's note (Card:585–588) says "over the 400-line
target though under the 800 hard max … raise it if the file grows again". Accurate, but understated:
the next meaningful edit trips the limit. The proposed `git_facts.py` split is a human-owned call and
correctly not scheduled — just be aware there is no headroom left.

## What I'd double-check before merging

1. **Add an acceptance criterion for the bounded lifetime**, covering both halves, and **give the poll
   interval a number.** This is the round's headline gap and it sits on the security control.
2. **Specify how the server is launched** — the `getppid()` check and "stderr is already captured"
   both depend on it, and both fail silently if it is wrong.
3. **Extend criterion 11 to in-directory paths**: assert `/analyze.py`, `/store.py` and
   `/tracker-data.json` return `404`.
4. **Add `--include='*.css'` and a `url\(` branch to the closure derivation** before task 14 runs.
5. **Fix the two surviving self-contradictions** — the analyzer failure-table intro, and §Design 2's
   "by construction" reason.
6. **Record the `implementation → planning` phase regression somewhere that still exists**, and expect
   to reopen the gate with the literal phrase `gate confirmed` before task 8.
7. **Close the `sent=` enumeration** for `reanalyze` and for the non-`403`/`409` refusals.
8. **Run the outstanding `cmux send` → live Claude TUI probe.** Owed since round 2; still owed; a
   negative result changes task 8's design.
9. Optional: move the six-asset table and the closure rule into ADR 0024 to make the 87-line cut net
   out.

---

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| `intent` | pass | All five round-3 items addressed on their own terms; items 1–3 closed cleanly, item 4 closed via a new ADR 0024 rather than by mutating the immutable 0022, item 5 honored with no split proposed. |
| `execution` | pass | 53 passed reproduced exactly; all five pinned versions verified byte-for-byte; every prescribed derivation re-run and held — six assets across nine sites confirmed, closure confirmed including `tracker-data.sample.js` and excluding `nocturne.css`, SRI and `__resources` and both `new Function` sites confirmed. |
| `trajectory` | pass | The round deliberately targeted the defect *class* (mis-scoped derivation) rather than the cited instances, corrected one of its own prior claims ("no SRI") against evidence, and warns the reader up front to ask what each derivation cannot see. Recurrences are listed as concerns, not luck. |
| `regression` | concern | Three round-3 findings survive verbatim: the analyzer failure-table self-contradiction, §Design 2's false "by construction" reason, ADR 0023's unresolvable owner pointer. The phase-guard denial is unchanged. |
| `context_budget` | concern | 662 → 752 lines, 45 KB → 52 KB. The recommended 87-line cut landed and was outweighed ~2:1 by additions; the card is the largest it has ever been and is read at session start. |
| `traceability` | pass | Card now cites 0022/0023/0024; ADR 0024 records the accountability reasoning with five rejected alternatives including the one that was actually tempting; `sent=unknown` makes the worst failure reconstructable instead of merely plausible. Minor: no forward link 0022 → 0024, though that matches repo precedent (0013 has none to 0015). |
| `success_masking` | concern | The bounded-lifetime control added this round has zero acceptance-criterion coverage, an unspecified poll interval, and an unspecified launch mechanism with two silent failure modes — the identical shape round 3 caught on the audit log, applied to the audit log only. Criterion 11 tests traversal outside `task-tracker/` but never asserts that `analyze.py`/`store.py` inside it are unreachable. |
| `intent_drift` | pass | Every change maps to a round-3 advisory, a compliance finding, or a recorded user decision. No new dependencies; task 14 removes six remote fetches rather than adding any. The `.spec.md` split was explicitly declined per the user's settled call. |
| `checkpoint` | pass | Single clean commit `81d98dc`, working tree clean, obvious revert point at `2c8d56d`. Commit message enumerates each change with its rationale. |
| `audit_trail` | concern | The `implementation → planning` frontmatter regression at `badd4f8` remains recorded nowhere, and the revision history that was its natural home has now been deleted. Verified consequence unchanged: `phase-guard.sh` denies `task-tracker/server.py`, exit 2. |

**Risk:** medium — the design is materially better than round 3 and the evidence behind it is
excellent, but the one control added this round that guards the credential's lifetime is entirely
unasserted, and that control sits on the component that can type into a full-permission session.

**Confidence:** high — suite re-run, all five pinned versions verified, every derivation in the card
re-executed, hook denial reproduced, ADR 0024 read in full, round diffed commit-to-commit.

## Concerns

- bounded-lifetime control has no acceptance criterion; the whole suite goes green with a server that never exits
- parent-death poll interval has no number; "one timer tick" is unbounded, and the only stated interval is 30 minutes
- "launch it as a child of the session" has no launch contract; getppid check fails silently in both directions
- "stderr is already captured by the launching session" still an unverified harness assumption, now load-bearing twice
- criterion 11 tests traversal outside `task-tracker/` only; `analyze.py`, `store.py`, `tracker-data.json` unasserted
- closure derivation `(src|href)=` cannot see CSS `url()`, exactly the refs task 14's vendored phosphor fonts will add
- closure written as `_ds/**` while claiming a closed enumeration; `_ds/` holds five files, the page loads two
- analyzer failure table's "every case yields questions[] and the run still emits" still contradicted by its own first row
- §Design 2's "store has no access to the token by construction" reason still argues the opposite of the claim
- ADR 0023's "whoever owns the export" still unresolvable; `task-tracker/github.md` would close it
- `sent=` undefined for accepted `reanalyze`; `sent=no` enumerates only 403/409, omitting 400/404/405/413/415/500
- `outcome` values have no mapping to status codes
- card grew 662 → 752 lines despite the 87-line cut; largest it has ever been, read at session start
- implementation→planning frontmatter regression still undocumented; phase-guard denies `task-tracker/server.py` (verified exit 2)
- `analyze.py` at 792 lines, 8 below the 800 hard max
- `cmux send` into a live Claude TUI still unproven, owed before task 8
