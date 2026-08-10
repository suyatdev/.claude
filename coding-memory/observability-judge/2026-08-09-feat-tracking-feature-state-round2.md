# Observability judge — `feat/tracking-feature-state` (architecting, round 2, advisory)

- **repo:** `tracking-feature-state` (worktree of `.claude`) · **branch:** `feat/tracking-feature-state`
- **HEAD:** `badd4f81899e11528665d411e95400b2fa6eb72d` · **base:** `origin/main`
  (merge-base `65ebf819e2307f76e3abce1f090ff936f0507ecf`)
- **stage:** `architecting` · **round:** 2 · **ts:** 2026-08-09T17:26:07Z
- **doc judged:** `docs/features/tracking-feature-state.md` (544 lines, was 286 at round 1)
- **prior round:** `2026-08-09-feat-tracking-feature-state.md` (HEAD `24ff8da`) — kept, not overwritten;
  the `-round2` suffix follows this directory's existing multi-round convention.
- **advisory only** — runs alongside the blocking compliance judge; gates nothing by itself.
- **test evidence:** I ran `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q` myself →
  **53 passed in 4.55s, 0 skipped, 0 failed**, `node --version` → `v26.5.0`. Same total as round 1;
  this revision is doc-only (`git diff --stat 24ff8da..HEAD` → the card plus memory/verdict files).

---

## What was changed

Round 1 found a live grenade: the design planned to write a password for the control server into
`task-tracker/tracker-data.js` — a file git tracks, in a repository that is public. The compliance
judge failed the card on the same point, plus six more, all in the one component nobody had written
down yet: the little web server.

This revision doesn't put a lid on that grenade, it **removes it**. The server now hands out the web
page itself at `http://127.0.0.1:8422/` and stamps the password into that page as it goes out the
door. The password lives only in the server's memory for as long as the server runs. There is no file
to leak, no file to remember to gitignore, and nothing to clean up when the process dies. That is the
right shape of fix — deleting the exposure beats guarding it.

Around that, the card grew the missing detail: a full wire contract (two routes, one header, eight
error codes), pinned tool versions, a table of every way the analyzer can fail and what it does about
each, a picture of the trust boundary, and two new acceptance tests. The command list is now fixed at
exactly three, and "commands never carry arguments" is written down as permanent, not as a v1
limitation.

## Does it do what you wanted?

**Yes. All seven compliance violations are genuinely addressed, and two of them are addressed better
than the judge asked for.**

The seven, checked against the card:

| violation | fix in the card | my read |
|---|---|---|
| secret in a committed file | server serves the UI; token injected per-request, never on disk (§Design 3, §Security) | ✅ exposure removed, not mitigated |
| no API contract | §Design 3 wire contract: 2 routes, schemas, 8 status codes | ✅ implementable as written |
| no pinned versions | new §Toolchain: Python `3.9.6`, `uv 0.11.28`, `pytest 9.1.1`, `cmux 0.64.20` | ✅ each row carries its re-read command |
| error handling unstated | analyzer failure table; server timeout + exit-code + refusal path | ✅ `null`-vs-`0` for a missing upstream is the standout call |
| absolute path committed | export path deleted, `TRACKER_UI_SOURCE` in its place | ✅ verified: no `/Users/` in the card |
| placeholder allowlist | three-row table that *is* the authorization set | ✅ |
| no diagram | Mermaid trust-boundary flowchart | ✅ |

Two details I'd single out. The **single `403`** — bad token, unknown command, and bad origin all
return byte-identical bodies, so the endpoint can't be used to guess your way to a valid command list.
And the **`null` vs `0`** rule: a branch whose upstream can't be read reports `null`, never `0`,
because "0 behind" is a confident lie about the exact question this whole feature exists to answer.

The self-correction habit held again. This revision found two defects the compliance judge never
cited (the `addopts` warning pointed at `memsearch/pyproject.toml`, which never governed this suite;
and the node-skipped tests), and corrected the card's own opening boast that it pinned no line
numbers — it had pinned four. Catching your own claim is the hardest kind.

## The four questions you asked

### 1. ADRs — still owed, and there are now three of them

**My view is unchanged, and the revision makes the case stronger, not weaker.** Next free number is
`0022` (confirmed: `docs/decisions/` ends at `0021`). Nothing in the card references
`docs/decisions/` at all.

- **External schema ownership** — still owed. Unchanged by this revision.
- **HTTP endpoint driving a fully-permissioned session** — still owed, and now *more* owed. The card
  went from a vague paragraph to a precise contract with eight status codes and a threat model. That
  is exactly the reasoning that must outlive the card, because cards get superseded and ADRs don't.
- **Server-serves-the-UI — yes, this is a third ADR-shaped decision**, and it is the one I would
  least want to lose. It is direction-pivoting (the UI is no longer a file you open; `file://`
  becomes a documented degraded mode), it was a **user decision**, and — critically — its *rejected*
  alternative was "gitignore a token sidecar." Without a durable record, the very next person to
  touch this will look at "server serves static files" and think *why not just write the token to a
  small file and skip the HTTP serving?* That is precisely the violation the compliance judge caught,
  reintroduced by someone who couldn't see why the shape was chosen.

**Recommendation:** two ADRs, not three. `0022` = "HTTP control channel into a fully-permissioned
session", carrying the server-serves-UI / in-memory-token decision as its mechanism section and the
token-sidecar alternative as its rejected option — they are one decision chain, and splitting them
buries the *why*. `0023` = "ceding schema ownership to an external design-system export", which is
unrelated and stands alone.

### 2. Observability of the control server — you were right, this is the thin spot

**This is my main new finding, and it is squarely this judge's business.**

In 544 lines about a component that can type into a session holding full tool permissions, there is
**exactly one sentence about logging** (`docs/features/tracking-feature-state.md:227`):

> A non-zero exit is `502` with the exit code logged server-side (not returned).

That's it. Nothing else in the card says anything is recorded at runtime. Specifically missing:

- **Accepted commands.** Nothing requires the server to record *which* of the three ids was accepted,
  when, or which surface ref it resolved to. If keystrokes ever land somewhere unexpected, there is
  no record to reconstruct from — and "keystrokes reaching the focused tab" is named by the card
  itself as the worst failure this feature can have.
- **Refusals, with cause.** The single-`403`-to-the-caller decision is correct. But the caller and
  the *log* are different audiences, and the card never says the server-side record distinguishes
  bad token / unknown id / bad origin. Collapsing them on the wire is a security win; collapsing them
  in the log is an incident-response loss. Nothing currently says they are separated.
- **Surface re-resolution outcomes.** Criterion 9 requires a `409` when a ref fails to re-resolve.
  Nothing requires recording *what* ref was tried and *what* it resolved to on the success path —
  which is the single fact you'd want after a misdirected keystroke.
- **Where the record goes and how long it lives.** No destination, no format, no retention. The
  server is explicitly session-scoped with no daemon, so a stdout-only log dies with the process —
  possibly acceptable, but it should be a stated decision rather than an omission.
- **Nothing forbids logging the token.** §Out of scope bans persisting the token in "no file, no
  environment variable, no command-line argument" — a log file is none of those three. An
  implementer adding `log.debug(request.headers)` for a bad-token refusal would satisfy every word of
  the card and write the credential to disk anyway.

Concretely, I'd want one clause in §Design 3 along the lines of: *every request to `/command` emits
one line — timestamp, id (or `<rejected>`), outcome code, internal refusal cause, resolved surface —
to stderr; no request header or body content is ever logged.* And an acceptance criterion asserting
the refusal-cause distinction exists server-side while staying invisible on the wire, which would
also lock in that the single-`403` is a deliberate wire property rather than an information vacuum.

### 3. Criterion 10 — testable, but it has a real wrong-reason hole

**Testable, yes.** A test can extract the token from the served HTML with a regex on the `<meta>` tag,
count its occurrences in that response, then scan files. Both halves are mechanical. Two things that
*don't* break it, which I checked: an empty token would make the absence scan fail loudly (`"" in
anything` is true), and a failed injection makes the extraction fail rather than pass silently. Good.

**But it can pass for the wrong reason, and the path is specific:**

The `reanalyze` command "re-runs the analyzer and re-emits the store, **server-side**"
(`:303`). That means `tracker-data.js` gets rewritten **by the one process that holds the token in
memory**. That is the single most plausible route by which the token could ever reach that file — and
criterion 10 only requires the disk scan after `GET /` has been served **at least once**. A test that
launches the server, fetches `/`, and greps `task-tracker/` passes without ever exercising the
re-emit. The fix is one clause: *…and after a `reanalyze` command has been accepted.*

Relatedly, §Design 2 claims the store module "has no access to the token **by construction**, since
the token exists only inside the running server process." Those two halves contradict each other once
`reanalyze` exists: the store is called *from inside* that very process. The property is true if the
token is held somewhere `store.py` can't reach, but nothing in the card structurally guarantees it
(no "store runs as a subprocess", no "the token lives in a closure, never a module global"). Today
`task-tracker/store.py` is clean — pure stdlib, no token anywhere — so this is a claim that outruns
its evidence, not a bug.

Three smaller gaps in the scan's reach, worth one line each:

- **Scope mismatch with §Out of scope.** The prohibition covers "no file, no environment variable, no
  command-line argument." Criterion 10 checks files under `task-tracker/` and the process command
  line. **The environment is never checked** — including the environment handed to the `cmux send`
  child, which is the one child process this server spawns.
- **Files outside `task-tracker/`.** A temp file, a log, `/tmp` — all out of scan range.
- **Binary files.** `_ds_bundle.js`, `.thumbnail` and friends are under `task-tracker/`; a naive
  `read_text()` walk raises `UnicodeDecodeError`, and the obvious fix (wrap in `try/except: continue`)
  silently shrinks the search. Read bytes and search bytes.

Criterion 11 (path traversal) is well-formed as written — it names three distinct attacks (relative,
absolute, symlink) and asserts on the response body, not just the status.

### 4. Test-verification honesty — better than the card says, and better than a note

**The card is honest, but it under-sells its own protection and over-states the loss.** §Verification
says a node-less host "reports green with that assertion never executed," leaving criterion 5
"unverified." I checked the suite, and that's too alarming. Each of the three node-guarded tests has
an **unguarded Python-side sibling**:

| node-guarded (skipped without node) | unguarded sibling that always runs |
|---|---|
| `test_emitted_file_executes_in_a_real_js_engine:151` | structural parse tests via `store.loads` |
| `test_replace_failure_leaves_a_file_a_js_engine_still_accepts:362` | `test_replace_failure_leaves_a_parseable_store:349` |
| `test_store_survives_sigkill_as_loadable_js:413` | `test_sigkill_between_temp_write_and_replace_leaves_the_store_intact:384` |

That last sibling asserts `store_path.read_bytes() == before` *and* re-reads the run through
`store.read_store`. And `store.loads` (`store.py:83`) is a real parser — it checks the
`window.TRACKER_DATA` prefix, the `=`, strips the `;`, `json.loads` the body, and validates the
`runs[]` envelope.

So on a node-less host criterion 5 is **partially** verified, not unverified: what's lost is the
independent JS-engine oracle — the one that would catch `store.loads` and a real browser disagreeing.
That is not hypothetical; `store.dumps`'s own docstring names the U+2028/U+2029 case, "the one place
JSON is not a subset of JS," which a Python parser accepts and a pre-ES2019 engine rejects. Exactly
the class of bug the node test exists to catch.

**Verdict on the mitigation: substantively adequate, but the stated form of it is cosmetic.** The
real protection is the sibling coverage, which the card doesn't mention; what the card offers instead
is an instruction to a future task-13 operator, and nothing fails if that operator skips it.

Two cheap upgrades, both better than a note: state the sibling coverage in §Verification so the next
reader neither over- nor under-reacts; and have task 13 run with `-rs` so skips are *printed* in the
recorded output rather than depending on someone remembering to check `node --version` separately.

## What could go wrong / what I'm unsure about

**Nothing here is a stop-work item.** The round-1 hazard is gone. Ranked by what I'd act on:

1. **No runtime audit trail for the control channel** (§2 above). The highest-value thing you can
   add for the least text.
2. **Criterion 10's ordering hole** — add `reanalyze` to the precondition, and extend the scan to the
   child environment. One sentence each.
3. **Three ADRs' worth of reasoning living only in a card that will be superseded.**
4. **No `Host` header validation.** The card checks `Origin`/`Sec-Fetch-Site` on POST (good, and it
   defeats the straightforward DNS-rebinding path). But `GET /` — the route that *hands out the
   token* — has no stated origin or `Host` check at all. The standard localhost defense is rejecting
   any request whose `Host` isn't `127.0.0.1:<port>` or `localhost:<port>`. Given how thorough the
   rest of §Security is, this is the one conventional control I'd expect to see and don't. One line.
5. **`idle timeout` has no number.** "Exits with the session and on idle timeout" — no duration, and
   no mechanism for the "exits with the session" half (parent-pid watch? signal?). A named constant
   is house style; an unspecified timeout will be improvised at task 8.
6. **`analyze.py` is 792 lines against the 800 hard cap** — eight lines of headroom, unchanged since
   round 1. The `git_facts.py` split is correctly deferred as a human call, but nothing mechanical
   stops tasks 8–10 pushing it over, and the split-in-waiting for `server.py` has the same shape.
7. **`cmux send` into a live Claude TUI is still unproven.** Card is honest; probe still owed before
   task 8. I can't resolve it — it needs a live surface.

**A round-1 claim of mine I have to withdraw.** I said the committed `tracker-data.js` was "genuine
output — the run-the-tool-commit-the-result loop has already happened once," inferring that from its
`generatedAt` timestamp. That inference was wrong. Its `dir` values are `~/dev/.claude` and
`~/dev/cmux`; `~/dev` **does not exist on this host**, and its `tool` line is byte-identical to
`tracker-data.sample.js`. It is the vendored demo payload, not this repo's analyzer output. The
security conclusion I drew from it (a token would land in a tracked public file) was correct and is
now moot; the supporting claim was not. Same defect species this card has spent four rounds
eliminating — a stored inference that outran its evidence — so it belongs in the record.

## What I'd double-check before merging

1. **Add the logging clause to §Design 3** before task 8 is written. After the fact it is a rewrite;
   now it is a paragraph.
2. **Amend criterion 10:** precondition includes an accepted `reanalyze`; scan covers the child
   process environment; scan reads bytes, not text.
3. **Write ADR 0022** (control channel + server-serves-UI + rejected token-sidecar) **and 0023**
   (external schema ownership). The rejected alternative is the load-bearing part.
4. **Add the `Host` header check** to §Security, and give the idle timeout a number.
5. **Run the outstanding probe** — `cmux send` into a live Claude TUI, not a shell prompt — and record
   the result either way. A negative result changes task 8's design.
6. **Reconcile §Design 2's "no access by construction" claim** with `reanalyze` running the store
   in-process, or state the structural mechanism that makes it true.

---

## Dimensions

| dimension | verdict | why |
|---|---|---|
| `intent` | **pass** | All 7 compliance violations addressed, and the headline one by *removing* the exposure (no on-disk token) rather than guarding it. Revision history maps each change to its violation id. Scope escalated to the user, not decided in the card. |
| `execution` | **pass** | I ran the pinned suite myself: **53 passed, 0 skipped**, node `v26.5.0`. Matches the card's recorded number. Doc-only revision, so no new tests expected; coverage remains scoped to the built (read-only) half by design sequence. |
| `trajectory` | **pass** | Reasoning, not luck. Found two defects the judge never cited (`addopts` misattribution; the node skips) and corrected the card's own false "no pinned line numbers" boast. `null`-vs-`0`, the single-`403`, and "commands never carry arguments, permanently" are each the harder-but-right call. |
| `regression` | **pass** | Round-1's concern is resolved: no design path now routes a secret into a tracked file. `tracker-data.js` remains git-tracked and unignored (`git check-ignore` → no match), so analyses still dirty a tracked file — noise, not hazard, now that it carries no credential. Worktree clean; no `/Users/` paths in the card or the store. |
| `context_budget` | **pass** | Card doubled (286→544 lines) but it is an on-demand feature card, not always-on context. Always-on cost is unchanged: one Skills Catalog line at task 12; the SKILL.md points at `managing-session-memory` rather than restating it. |
| `traceability` | **concern** | **Design-time traceability is excellent; runtime traceability is near-absent.** One sentence about logging in 544 lines (`:227`), for a component that can type into a fully-permissioned session. No record of accepted commands, refusal causes, or surface re-resolution outcomes; no destination or retention; and nothing forbids logging the token itself, which §Out of scope's three-way ban (file/env/argv) does not cover. |
| `success_masking` | **concern** | Criterion 10 can pass without exercising `reanalyze`, the one path that re-writes the store from the token-holding process. Its scan also misses the child environment that §Out of scope explicitly bans. The skipif disclosure is honest but the *stated* mitigation is a manual task-13 note; the real protection (unguarded Python siblings at `test_store.py:349,384`) goes unmentioned, and the card overstates the loss as "unverified" when it is partially verified by a weaker oracle. 53 green tests still cover none of criteria 6–11. |
| `intent_drift` | **pass** | Diff since round 1 is the card plus memory/verdict files — nothing else touched. Allowlist fixed at exactly three with "adding a fourth is a spec change." Arbitrary-command endpoint and command arguments both named permanently out of scope. No new dependency; the deferred `git_facts.py` split still deliberately not taken as a drive-by. |
| `checkpoint` | **pass** | This revision is one clean doc-only commit (`badd4f8`) on a clean worktree, trivially revertible, frontmatter `branch:` matching reality. Round-1's concern about `37a8e38` (8.3k insertions, tasks 2–6) persists in history but is not this change's doing. |
| `audit_trail` | **concern** | Three ADR-shaped decisions, zero ADRs, against a live 21-ADR convention — and the newest one (server-serves-UI over a gitignored token sidecar) is precisely the decision whose rejected alternative must survive, or the compliance violation gets reintroduced by someone who can't see why. Attribution otherwise strong: per-violation revision history, user decision named and dated. |

**risk: medium** — down in substance from round 1 even though the label is the same. The one concrete
hazard (a live token headed for a tracked file in a public repo) is *removed*, not mitigated, and
that is a real reduction. Still medium because the entire security surface remains unbuilt, the
security-critical component has no runtime audit trail, criterion 10 has a specific wrong-reason
path, and none of the reasoning is anchored in an ADR. Not high: nothing is broken today, the design
quality is well above average, and every remaining item is cheap to fix at spec time.

**confidence: high** — I ran the pinned test command myself and observed the real result; read the
card end to end; verified tracked/ignored status, repo visibility (`isPrivate: false`), ADR numbering,
the three `skipif` test names *and* their unguarded siblings, `store.loads`'s actual leniency, the
absence of `Host`/logging/ADR language by grep, and the `~/dev` path claim that made me withdraw a
round-1 statement.

## Concerns

- control server has no runtime audit trail — one logging sentence in 544 lines; accepted commands, refusal causes, and surface re-resolution outcomes all unrecorded
- nothing forbids logging the token; §Out of scope's ban covers file/env/argv, not a log file
- criterion 10 can pass without exercising `reanalyze`, the one path that rewrites the store from the token-holding process
- criterion 10's scan misses the child process environment, which §Out of scope explicitly bans
- §Design 2's "store has no access to the token by construction" is contradicted by `reanalyze` running the store in-process
- three ADR-shaped decisions, zero ADRs (schema ownership; HTTP control channel; server-serves-UI) — next free number 0022
- no `Host` header validation on `GET /`, the route that hands out the token
- idle timeout has no duration and "exits with the session" has no mechanism
- skipif mitigation is a manual task-13 note, not a mechanism; card overstates the loss and omits the unguarded Python siblings that actually cover criterion 5
- entire security surface (criteria 6, 7, 9, 10, 11) unbuilt — 53 green tests cover only the read-only half
- `analyze.py` at 792/800 lines with no mechanical trigger for the deferred split
- `cmux send` into a live Claude TUI still unproven; probe owed before task 8
- round-1 verdict's claim that committed `tracker-data.js` is genuine analyzer output was wrong — `~/dev` does not exist; it is the vendored demo payload
