# Observability judge — `feat/tracking-feature-state`, round 3 (architecting)

- **Repo:** `tracking-feature-state` (worktree of `suyatdev/.claude`, verified `PUBLIC`)
- **Branch:** `feat/tracking-feature-state`
- **HEAD:** `41b586cb07f6486feebd5f82866e56d1f69af997`
- **Stage:** architecting — advisory, non-blocking. The compliance judge holds the gate.
- **Artifact:** `docs/features/tracking-feature-state.md` (662 lines), `docs/decisions/0022`, `0023`
- **Timestamp:** 2026-08-09T18:00:18Z

---

## What was changed

Think of the card as the blueprint for a small doorbell that can press keys inside a room where
Claude has every tool switched on. Round 2 said the blueprint had no *doorbell camera* — nothing
recorded who rang, or which door opened. Round 3 adds one: a single line of text per request, printed
to the terminal, saying what happened, which command, and which window the keystroke went to.

Alongside that: the credential-bearing page now refuses requests addressed to the wrong hostname, the
browser is told not to save that page to its own cache, the idle shutdown got a real number
(30 minutes), the leak test got much stricter, and the two decisions worth outliving the card were
written down as ADRs 0022 and 0023.

## Does it do what you wanted?

Largely yes, and the evidence is unusually good. I re-ran everything rather than trusting the text:

| Claim in the card | How I checked it | Result |
|---|---|---|
| "53 passed on 2026-08-09" | `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q -rs` | **53 passed**, 0 skipped |
| Python `3.9.6`, `uv 0.11.28`, `node v26.5.0`, `cmux 0.64.20 (100) [14e3400b9]` | ran each `--version` | all four **exact** |
| "two `@phosphor-icons` stylesheets and no remote JavaScript" | `grep -n 'https://'` on the vendored page | **correct** — the card was right and the compliance judge's "three executable scripts" was wrong |
| "the repository is public" (ADR 0022) | `gh repo view --json visibility` | **PUBLIC** |
| `store.py` cannot see the token | `grep -n "token\|secret" task-tracker/store.py` | **clean** |

Your five round-2 items: four landed, one (the live-TUI probe) is honestly deferred and still tracked.
That is a good round.

## What could go wrong / what I'm unsure about

### 1. The audit log is substance, not theatre — but it is untested, and it repeats one mistake

Asked directly: **does it close the gap?** Mostly. It records the thing that matters — the *resolved*
surface, which is the field that answers "where did that keystroke go" — and it logs refusals as
loudly as successes. The token prohibition is now explicit in two places. That is a real fix.

Three holes remain:

- **Nothing tests it.** Criterion 10 scans files under `task-tracker/`, the process command line, and
  child-process environments. It does **not** scan the log stream — the leak surface added in the
  same commit. An implementer could write `log.debug(request.headers)` on every request and
  criterion 10 goes green. The prohibition moved from "absent" to "written down but unasserted."
  Given the card's own standard — *"Criterion 10 asserts this rather than trusting it"* — the log
  deserves the same treatment.
- **`reason=<error-code>` re-collapses the three `403` causes.** My round-2 point was that hiding bad
  token / unknown id / bad origin *from the caller* is a security win, and hiding them *from the
  operator* is an incident-response loss. The log's `reason` field is specified as the wire error
  code, and the wire code for all three is the single word `forbidden`. So the log preserves exactly
  the ambiguity the log was supposed to resolve. One word — `reason=<internal-cause>` — fixes it.
- **The log records intent, not effect.** `surface` is the ref the server resolved and confirmed.
  The dangerous case the card itself names is the surface dying *between* confirmation and send, so
  `cmux` falls through to the focused tab. In that incident the log says `surface=X` and the keys
  went to Y. Recording the *requested* ref alongside the resolved one, plus whatever `cmux send`
  returns, would make the wrong-surface case reconstructable instead of merely plausible.

One unverified premise underneath it: *"one line per request to stderr, which the launching session
already captures."* The card never specifies **how the server is launched**, so "already captures" is
an assumption about the harness, and "bounded lifetime means bounded logs" is in tension with it — a
captured stream outlives the process it came from. This is the card's own recurring defect species
(a stored inference outrunning its evidence), showing up in text written this round.

### 2. Anything still permitting the token to reach a log? Not in the prose — but the prose is all there is

§Design 3 and §Out of scope both ban it, in strong language. I found no wording that permits it. The
residual risk is entirely the missing assertion above, made worse by stderr being captured to disk by
the launching session — a violation would be durable, not ephemeral.

### 3. The wire contract contradicts itself, and task 8 is the next task

- Line 172: **"Exactly two routes. Anything else is `404`."**
- Line 230: `404 | not_found | Any path other than the two routes above`
- Lines 189–193: five static assets **must** be served.

A server built literally to this contract `404`s its own stylesheet. This is the *same shape* as the
round-2 finding that caught `tracker-data-fallback.js` — the enclosing rule was never reconciled with
the exception. Also unspecified: which method table row covers `POST /nocturne.css`, and whether the
`Host` check applies to asset routes.

### 4. Was any round-2 fix applied narrowly? Yes — three instances, all the same pattern

The fix landed exactly where cited; the class survived one step out.

| Fix | What landed | What the same class still permits |
|---|---|---|
| Servable-asset list | `tracker-data-fallback.js` added | Its prescribed re-derivation is `grep -n 'tracker-data'`, which by construction only finds that one class. The correct command is `grep -oE '(src\|href)="[^"]+"'` — I ran it; the list happens to be complete today, and `nocturne.css` is on it while the page never loads it |
| Idle timeout | got a number, a floor, and no disable value | The *other half* of that recommendation — no stated mechanism for "exits with the session" — is untouched, and the audit log now depends on it |
| Criterion 10 | raw bytes, child env, `reanalyze` precondition | Not extended to the log stream; files outside `task-tracker/` still unscanned; and §Design 2's *"the store module has no access to the token by construction"* is still false as written, since `reanalyze` runs the store inside the token-holding process |

A fourth, pre-existing instance of the same shape: the analyzer failure table opens *"Every case below
yields a `questions[]` entry … and the run still emits"* and its own first row says *"Nothing is
written."* Blanket claim, contradicted by the enumeration beneath it — twice in one document.

### 5. The ADRs — 0022's rejected alternative is genuinely good; both have one real omission

**0022 does the hard part well.** The closing paragraph is addressed directly at the future
re-introducer — *"If you are reading this because you are about to simplify the server into a plain
static file and write the token somewhere: that is the rejected alternative"* — and it gives both
reasons the sidecar fails (credential on disk; `file://` sends `Origin: null`, so the Origin check
becomes decorative). That is concrete enough to stop the re-introduction. Keep it.

What both get wrong:

- **The card cites neither ADR.** `grep -n "decisions/\|ADR\|0022\|0023"` on the card returns nothing.
  The link is one-directional — the ADRs point at the card, the card points nowhere. An ADR you can
  only find by already knowing it exists is half an ADR, and the card is the document that will be
  read first.
- **0022 omits the audit log entirely** — the headline addition of the very commit that created it.
  0022 is the durable record of the trust boundary; if the card is superseded, "never log the token,
  and here is why a log file isn't covered by 'no file, no env, no argv'" dies with it. That
  reasoning belongs in the ADR more than almost anything else in it.
- **0022 never mentions the 30-minute idle timeout**, though "dying process, dead token" is the whole
  argument for an in-memory credential. The bound on that lifetime is load-bearing.
- **0022 reads as though the server exists.** Status `accepted`, present tense, no note that tasks
  8–10 are unbuilt.
- **0023** is sound and low-risk. One gap: it says a missing field means "a conversation with whoever
  owns the export," and the card deliberately (and correctly) removed the absolute export path — so
  "whoever owns it" is now unresolvable. Pointing at `task-tracker/github.md` would close it.

### 6. The 662-line question — my read: **do not split; cut the revision history instead**

Measured composition: Design 201 · Revision history 86 · Tasks 54 · Criteria 53 · Security 53 ·
Injection route 51. Repo precedent runs both ways — `memsearch-freshness.md` (136 KB) and
`phase-guard-hook.md` (132 KB) are unsplit; this card is 45 KB, mid-pack.

Three reasons against a split, in order of weight:

1. **A synced pair is the ideal habitat for this card's one disease.** Four rounds have found ten
   defects, every one the same species: a stored fact that went stale, twice inside the corrections
   written to fix the previous round. A split creates a standing sync obligation between two files.
   You would be introducing the exact structure that has bitten this document ten times.
2. **It would not actually save the session-start read.** Tasks 8, 9, 10 and 14 each name §Design 3,
   §Security or a specific criterion. For the seven remaining tasks the reader opens both halves
   anyway, so the checklist-only file is a saving on paper.
3. **The weight is not in the spec.** 86 lines — 13% — is revision-history archaeology that git, the
   session archive, and three judge verdict files already hold in more detail. Collapsing the two
   older entries to a one-line pointer recovers most of the cost with zero cross-reference risk.

If you ever do split, the moment is *after* task 8 lands and the wire contract stops moving.

### 7. Housekeeping with teeth: the phase gate will block task 8 right now

The frontmatter says `phase: planning` while 7 of 14 tasks are `[x]` with 1,500+ lines of committed
Python. Tracing it: the card read `implementation` through `48f7db4` and was flipped back to
`planning` at `badd4f8`, the compliance-round-1 fix. Flipping back on a failed spec is defensible —
but it is recorded nowhere in the 86-line revision history, and the consequence is real. I ran the
hook against the next file task 8 creates:

```
$ printf '{"tool_name":"Write","tool_input":{"file_path":".../task-tracker/server.py"}}' \
    | bash hooks/phase-guard.sh
phase-guard: write blocked — task-tracker/server.py
...
There is no bypass environment variable; this guard ships without one by design.
EXIT=2
```

Task 8 cannot be written until the gate reopens on the literal phrase `gate confirmed`. A restoring
session sees `planning` plus seven finished tasks and, per the restore discipline, must stop and
report rather than guess.

## What I'd double-check before merging

1. **Extend criterion 10 to the log stream** — capture stderr during the test and assert the token
   is absent from it, as raw bytes. One clause; it converts the round's headline fix from stated to
   proven.
2. **Change the log's `reason` to an internal cause**, so `forbidden` in the log distinguishes bad
   token from unknown id from bad origin while the wire keeps its single `403`.
3. **Reconcile "exactly two routes / anything else is 404" with the five servable assets**, and
   replace the re-derivation grep with `grep -oE '(src|href)="[^"]+"'`.
4. **Add the audit log and the idle-timeout bound to ADR 0022, and link both ADRs from the card.**
5. **Say how the server is launched and how it dies with the session** — the audit log's "stderr is
   already captured" rests on it.
6. **Record the `implementation → planning` regression in the revision history**, and expect to
   re-open the gate before task 8.
7. **Run the outstanding `cmux send` → live Claude TUI probe.** Unchanged from round 2; still owed
   before task 8; a negative result changes task 8's design.
8. Optional, cheap: trim the two older revision-history entries to a git pointer.

---

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| `intent` | pass | Four of five round-2 items landed; the fifth is honestly deferred and tracked. Compliance items addressed, two judge claims corrected with verified evidence rather than accepted. |
| `execution` | pass | 53 passed reproduced exactly; all five pinned versions verified byte-for-byte on this host; the card's re-derivation commands re-run and held. |
| `trajectory` | pass | Reasoning is sound and self-correcting — the card rebuts its own judges with commands, not assertions. Narrow-fix pattern is a concern, not luck. |
| `regression` | concern | The wire contract contradicts itself on static assets, and the analyzer failure table contradicts its own first row. Both live inside the contract task 8 builds against. |
| `context_budget` | concern | 662 lines read at session start, 86 of them archaeology. Below repo outliers and the split is a MAY — but the revision history is unearned weight. |
| `traceability` | concern | Card cites neither ADR; 0022 omits the audit log it was written beside; the "stderr is captured" premise rests on an unspecified launch mechanism. |
| `success_masking` | concern | Criterion 10 goes green with the token in every log line. The log's `reason` field re-collapses the three `403` causes. Design 2's "by construction" claim remains false as written. |
| `intent_drift` | pass | Every change maps to a judge finding or a recorded user decision. No new dependencies; task 14 removes two remote fetches rather than adding any. |
| `checkpoint` | pass | Single clean commit, working tree clean, obvious revert point at `badd4f8`. |
| `audit_trail` | concern | Frontmatter regressed `implementation → planning` at `badd4f8` with no note anywhere; verified consequence is that `phase-guard.sh` denies `task-tracker/server.py` (exit 2). |

**Risk:** medium — nothing here is stop-work, but two concerns land directly on the component that
can type into a full-permission session, and that component is the next task.
**Confidence:** high — tests run, versions verified, hook denial reproduced, asset list re-derived,
repo visibility confirmed, round diffed commit-to-commit.

## Concerns

- criterion 10 does not scan the audit log — the leak surface added in the same commit
- audit log `reason=` reuses the collapsed `403` wire code; server-side cause distinction still absent
- audit log records the resolved (intended) surface, not the delivered one; TOCTOU wrong-surface case stays unreconstructable
- wire contract says "exactly two routes, anything else 404" while requiring five static assets be served
- card references neither ADR 0022 nor 0023; 0022 omits the audit log and the idle-timeout bound
- frontmatter regressed implementation→planning at `badd4f8` undocumented; phase-guard denies `task-tracker/server.py` (verified exit 2)
- servable-list re-derivation grep finds only `tracker-data` files, not the full `(src|href)` asset set
- "exits with the session" mechanism unspecified, yet the audit log's stderr capture depends on it
- Design 2's "store has no access to the token by construction" still false while `reanalyze` runs the store in-process
- analyzer failure table's "every case yields questions[] and the run still emits" contradicted by its own first row
- 662-line card read at session start; 86 lines are revision-history archaeology
- `cmux send` into a live Claude TUI still unproven, owed before task 8
