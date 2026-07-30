# Observability verdict — `phase-guard.sh` design (architecting)

- **Repo:** `phase-guard-hook` (worktree of `~/.claude`)
- **Branch:** `worktree-phase-guard-hook` @ `ed353a12605ef8cfd9e02a292687a99282fd21a7`
- **Stage:** `architecting` — advisory, does not gate
- **Design judged:** `docs/features/phase-guard-hook.md`
- **Timestamp:** 2026-07-25T21:48:51Z
- **Verdict:** risk `medium`, confidence `high` — no `fail`, five `concern`s, all cheap to close
  before code exists

---

## What was changed

Nothing yet — this is a design, no code exists. The design proposes a new machine-wide
safety catch called `phase-guard.sh`.

Here's the setup. This repo already has a rule that every feature gets a planning document, and
that document has a line at the top saying `phase: planning`, `phase: implementation`, or
`phase: review`. Think of it as a traffic light for the work. Today the light exists but nothing
stops you driving through it — it is written down and then ignored.

This design adds the camera at the intersection. It is a "hook": a small script Claude Code runs
automatically, before every single file edit, in every repo on the machine. When it fires it asks
one question and one question only:

> Does the branch I'm currently on have permission to write code?

If a feature document somewhere in the repo still says `planning`, and the current branch isn't
recorded as the official implementation branch of *any* feature, the edit is refused with an
explanation. Otherwise it silently gets out of the way.

The clever part — and it is genuinely clever — is what the design *refuses* to do. An earlier
decision record (ADR 0010) killed this exact idea for a good reason: during planning there is no
branch yet, so the hook couldn't figure out *which* feature document applies to the file you're
editing, and a guard that gives up whenever it's confused is worse than no guard, because it looks
like protection while providing none.

This design's answer is to stop asking that question. It never tries to match your edit to a
feature. It only asks whether your *branch* is on the approved list — and because the workflow
forbids creating a branch during planning, a planning session is always sitting on a branch that
nobody approved. The absence of an approval isn't confusion; it *is* the answer. That reframing is
what makes the whole thing work, and it's the strongest thing in the document.

Documentation, notes, and the feature file itself are deliberately left unguarded — that's the
escape hatch. If the guard locks you out, you fix it by editing the feature document's traffic
light, which the guard never blocks. There is deliberately no "magic password" environment variable
to skip the check, and the design argues that position well rather than just asserting it.

## Does it do what you wanted?

Yes, and it's above the usual bar. Some specifics I checked rather than took on faith:

- The claim that `git cat-file --batch` behaves asymmetrically — echoing your request line back for
  a missing file but *not* for one that exists — is **correct**. I ran it. This matters a lot,
  because a parser written on the natural assumption ("each answer is labelled") would silently
  mis-attribute every result and hand back the wrong traffic-light colour. Catching that at design
  time is the difference between a working hook and a hook that's confidently wrong.
- The cited prior art is accurate. `doc-guard.sh:149` really is the source-vs-docs split it says to
  reuse, and `git-guard.sh:22` really is the bash-regex trap it says to avoid. Cross-references in
  designs are usually decorative; these hold up.
- The `NotebookEdit` correction is real. That tool carries `notebook_path` and *no* `file_path`, so
  the original draft would have quietly exempted an entire tool from the guard. The design caught
  its own bug and pinned a regression test for it. That's a good sign about the author's habits.

The reasoning throughout is argued rather than asserted — the decision to fail *open* on
infrastructure problems is derived from blast radius (this fires on every write everywhere, so a
false block costs a whole session) rather than from copying its sibling, and the decision is stated
as a deliberate divergence. Scope discipline is unusually good: the reverse direction is explicitly
out of scope, and a genuine contradiction the author noticed between two rules is *recorded as its
own task* instead of drive-by fixed.

So: the design does what was asked. My concerns are about what happens when it goes wrong, not
whether it works when it goes right.

## What could go wrong / what I'm unsure about

**1. A green test suite cannot tell you the guard is alive.** This is the big one and it's the
thing you specifically asked about. The design has eight "get out of the way" exits, and every one
of them is specified as *exit quietly, print nothing*. The test suite for all eight asserts exactly
that: exit 0, nothing on stderr.

Now read that again from the other direction. A guard that is working perfectly and a guard that is
completely dead produce **byte-identical output**: silence, and a passing test suite. There is no
observation you could make, after the fact, that distinguishes them.

For most of those eight exits that's genuinely the right call — "this repo never opted in" is the
common case, it fires on every keystroke-level write machine-wide, and logging it would be noise.
But two of them are different in kind:

- `python3` is missing → the guard is **off**, permanently, everywhere.
- Every feature document fails to parse → this repo **did** opt in, and the guard cannot read it.

Those aren't "not applicable". Those are "you believe you are protected and you are not". And the
house already has the pattern for exactly this: `pane-dispatch-guard.sh` stays silent on its boring
fail-opens but prints a line for the two interesting ones (session-id mismatch, adapter cooldown).
This design departs from that precedent without noticing it had one. The fix is two `printf`s on
paths that, by construction, almost never run — near-zero hot-path cost. To avoid a repeated
message on every write, reuse the same once-per-session flag-file trick the sibling already uses.

**2. The hook can lock you out of the file you'd use to turn it off.** I applied the design's own
path rules to real paths and confirmed it: `settings.json` — where the hook is registered — is on
the **guarded** side. So is `rules/gates.md`. If the hook has a bug that makes it deny
unconditionally, using Edit to disable it is itself denied.

There is a way out (this hook only watches Edit/Write/NotebookEdit, so a Bash `sed` or a
`git revert` still works), but **the design never says so and the refusal message wouldn't tell
you**. For a script registered globally across every repo on the machine, "how do I turn this off"
should not be something you have to derive under pressure. The design has no rollback section at
all.

**3. The performance test measures the wrong thing, and will pass either way.** The design promises
the expensive lookup uses "exactly one subprocess, not one per branch" — correct instinct. But:

- No sibling test file does process counting, and the design doesn't say how to test it. The test
  someone actually writes will likely assert the *answers* are right, and an inefficient
  one-process-per-branch implementation produces identical answers. Green, unverified.
- Subprocess count isn't really the cost anyway. One `cat-file --batch` still streams the full
  contents of every matching document. I measured it: ~26KB and ~26ms here, with only *one* branch
  currently holding a feature file. That scales with (branches holding the file × file size) — so
  the hook gets **more expensive precisely as this workflow succeeds** and feature documents reach
  `main` and get inherited by every branch. Nothing in the design bounds it.

**4. A one-word gap that causes needless lockouts.** The "has this feature already been approved?"
check unlocks a document only if some branch shows it at `implementation`. It does not consider
`review`. So a *finished* feature — every branch advanced to `review` — with one stale `planning`
copy left lying around will keep blocking writes, for no reason at all. Widening that check to
`implementation` **or** `review` costs nothing and removes a whole class of the stale-lockout
problem the design admits it can't otherwise fix.

**5. Two other Claude sessions are running right now.** Registering this globally takes effect
immediately for the two other live worktrees. I checked: they're safe, because their branches carry
no `docs/features/` directory at all. But that's true by accident of timing, not because the design
verified it — and it stops being true the moment this merges to `main`.

**6. Smaller things.** The refusal message is missing the `phase-guard:` name prefix all four
sibling hooks use — it's the only output this hook ever produces, so it's the only chance to say
who spoke. And in this specific repo, the `.claude/*` exemption means source code sitting inside
sibling worktrees (`.claude/worktrees/*/hooks/*.sh`) is unguarded.

**On your question about the two admitted holes:** they are not equal. The branch-granularity hole
is genuinely *mitigated* — it's strictly narrower than today's zero enforcement, and `git-guard.sh`
layers underneath it. Fine to ship. The stale-abandoned-file lock is only *confessed*; its sole
stated remedy is "the error message names the file", which relies on someone reading and acting.
Fixing #4 above converts a good chunk of it from confession to mitigation.

## What I'd double-check before merging

1. **Add `review` to the already-approved check** (concern #4). Smallest change, best
   value-per-character in the whole list.
2. **Write a rollback paragraph** and put the escape route in the refusal message: how to
   unregister, and the fact that Bash edits are outside this hook's watch so recovery is always
   possible. Consider exempting `settings.json` outright.
3. **Print one line on the two "opted in but couldn't evaluate" exits** (missing python, all
   documents unparseable), using the once-per-session flag pattern from `pane-dispatch-guard.sh`.
   Keep the other six silent — that part is right.
4. **Decide what the performance test actually asserts.** Either specify the counting-`git`-on-PATH
   shim, or replace the subprocess count with a wall-clock/bytes budget, which is closer to what
   you care about.
5. **Extend the refusal message to six elements**: the existing four, plus the `phase-guard:`
   prefix, plus an explicit "writes under `docs/**` are still allowed" — so the suggested fix
   visibly *is* executable right now, and nobody stalls thinking everything is frozen.
6. **Amend the existing `Phase gate` stub in `rules/gates.md` rather than adding a new bullet.**
   Line 5 already covers this; the house pattern is to append "Enforced by `hooks/phase-guard.sh`
   (Tier 1)" to the stub that's there. `rules/gates.md` is always-on context in every session.
7. **Say something about the concurrent sessions** before registering globally — even just a note
   that their branches carry no `docs/features/` and are therefore unaffected.
8. **Answer the question the design deliberately left open (Q1):** nobody has actually been caught
   running the gate yet. The design is honest that building now overrides ADR 0010's own
   "wait until it's skipped" rule. That's a legitimate call, but it's yours to make, not the
   design's — and it's the right call to make *before* the ten tasks start.

---

## Dimension scores

| Dimension | Score | Basis |
|---|---|---|
| `intent` | **pass** | Answers ADR 0010's stated objection head-on by reframing it rather than dodging; scope tight; non-goals explicit; Q1 (should this exist at all) honestly surfaced as a user decision rather than assumed. |
| `execution` | **concern** | No code yet (architecting). Design is buildable, toolchain pinned and verified on-machine, `cat-file` parser contract empirically correct. But: the already-approved check omits `review`; Group C has no test mechanism; no rollback procedure specified. |
| `trajectory` | **pass** | Reasoned, not lucky. Fail-open/fail-closed split derived from blast radius, not sibling mimicry. `PHASE_EXEMPT` rejected on a structural argument (the `docs/**` hatch already exists) rather than strictness. Self-caught the `notebook_path` schema bug and pinned a regression test. Process friction recorded as a finding. |
| `regression` | **concern** | Fires on every write in every repo machine-wide, with two concurrent worktrees live. They are safe today only because their branches carry no `docs/features/` — verified by me, not by the design. `settings.json` and `rules/gates.md` land on the guarded side, so the hook can obstruct its own maintenance. |
| `context_budget` | **concern** | Task 8 adds a *new* `rules/gates.md` stub; line 5 already carries a `Phase gate [CRITICAL]` stub lacking only an "Enforced by" clause. House pattern (git-guard, judge-guard) appends to the existing stub. `rules/gates.md` is always-on context (7.3KB, ~1.8k tokens) — a redundant 26th bullet costs attention in every session forever. |
| `traceability` | **pass** | Every open question carries a dated, attributed resolution. Design table maps 1:1 onto Group B scenarios. ADR planned (task 9) and correctly framed as *amending* ADR 0010. Cited line numbers (`doc-guard.sh:149`, `git-guard.sh:22`) verified accurate. |
| `success_masking` | **concern** | The headline finding. All 8 Group A scenarios assert `exit 0 AND empty stderr` — identical output for "correctly out of scope" and "silently dead". Group C's subprocess assertion has no mechanism and passes for an O(branches) implementation. Subprocess count is also the wrong proxy: one `cat-file --batch` streams every matching blob in full (measured 26KB / ~26ms with a single branch holding the file), growing as adoption grows. |
| `intent_drift` | **pass** | Notably disciplined. Reverse enforcement explicitly out of scope. The `writing-specs` vs ADR 0010 contradiction is recorded and deferred to its own task rather than drive-by fixed. No new dependencies — `bash` 3.2.57 / `python3` 3.9.6 / `git` 2.50.1, all present and pinned. |
| `checkpoint` | **concern** | No rollback procedure anywhere for a globally-registered deny hook. `settings.json` — the unregistration point — confirmed guarded by the design's own classification. A recovery path exists (Bash is outside this matcher) but is neither documented nor surfaced in the deny message. |
| `audit_trail` | **pass** | Resolutions dated and attributed to the user; ADR 0011 planned as an explicit amendment; prior art cited by `file:line`. Minor gap: the deny-message contract omits the `phase-guard:` prefix every sibling uses, on the only output this hook ever emits. |

**Risk:** `medium` — global blast radius, a self-lock path through `settings.json`, and a
structural blind spot in detecting its own death. No `fail`: every concern is pre-implementation
and cheap to close.

**Confidence:** `high` — read the full design and all four sibling hooks; verified the `cat-file`
output asymmetry, the branch/worktree state, the path classification, and the `gates.md` overlap by
execution rather than inspection.

## Concerns

1. Group A's 8 scenarios all assert exit 0 + empty stderr — a green suite cannot distinguish a working guard from a silently dead one; the two "opted in but could not evaluate" fail-opens (python missing, all frontmatter unparseable) emit no signal, departing from `pane-dispatch-guard.sh`'s precedent without noting it.
2. The un-superseded filter drops a planning file only when some branch reads `implementation`, omitting `review` — a finished feature with one stale planning copy keeps denying for no reason.
3. `settings.json` is on the GUARDED side of the design's own path classification (verified by execution), so the file used to unregister the hook can be blocked by the hook; no rollback procedure is stated anywhere.
4. Group C's "exactly one `cat-file --batch` subprocess" has no specified test mechanism and no PATH-shim precedent in any sibling `hooks/*.test.sh`; the likely test also passes for an O(branches) implementation.
5. Subprocess count is the wrong hot-path proxy — one `cat-file --batch` still streams every matching blob in full (measured 26KB, ~26ms with one branch holding the file), scaling with branches × file size as adoption grows.
6. Global registration takes effect immediately for two concurrent worktrees/sessions; they are safe today only because their branches carry no `docs/features/`, a property the design never verified or pinned.
7. Task 8 adds a new `rules/gates.md` stub although line 5 already carries a Phase gate stub; house pattern appends "Enforced by `hooks/x.sh` (Tier 1)" to the existing one. `rules/gates.md` is always-on context.
8. Deny-message contract omits the `phase-guard:` prefix used by all four siblings and does not state that `docs/**` writes remain allowed, so the named fix may not read as executable without an unblock.
9. In this repo the `.claude/*` exemption leaves source inside sibling worktrees (`.claude/worktrees/*/hooks/*.sh`) unguarded.
10. The stale-abandoned-planning-file lock is disclosed but only confessed, not mitigated beyond naming the file in the deny message; fixing concern 2 would convert much of it to mitigated.
