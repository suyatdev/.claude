# 0054 — An approval lasts until the list changes, and attendedness uses the measured signal

- **Status:** Accepted (2026-10-29). Two decisions the user made after task 4 on
  `docs/features/guard-loosening-approval.md` surfaced them. Both **amend**
  `docs/superpowers/specs/2026-09-20-guard-loosening-approval-design.md`; neither is recorded in the
  spec, because no design content in it is edited under `phase: implementation`. The card is the
  status of record and points here, as it does for ADR 0052 (task 1) and ADR 0053 (task 2).
- **Note on the number:** `0054` was checked free on 2026-10-29 across **all remote and local
  heads** plus the working tree, not just `origin/main`; the highest found anywhere was `0053`.
  Re-check at merge time, per ADR 0050.
- **Why these are ADRs and not card notes:** decision 1 resolves a **self-contradiction in the
  spec**, and decision 2 **reverses** an assertion the test suite already pins. Both change
  behaviour a reader would otherwise derive from §2, §5.1 or §7.

## Decision 1 — an approval is scoped to the permission-list state, not consumed by one commit

**The approval is keyed to the permission-list state and stays valid until that state changes.** It
is **not** deleted by the first commit that uses it.

⚠️ **This was already settled, and should not have been re-asked.** §2 of the spec records it as a
settled decision dated **2026-09-16**, in these words: *"Until that rule changes again — fingerprinted
to the list's exact new state."* That is state-scoping, stated exactly. The card's "Decisions
settled — do not relitigate" section names approval lifetime among them.

This session nonetheless put it to the user as an open choice, because task 4 reported it as a
spec self-inconsistency and the inconsistency was taken at face value instead of being traced to
which half was authoritative. The user's answer matched the settled decision, so nothing was lost —
but the correct handling was to resolve the conflict **against the settled decision**, not to
re-open it. Recorded here because a decision re-asked once is a decision that can be re-answered
differently next time.

So the real content of decision 1 is narrower than "the user chose state-scoping": **the §5.1
flowchart's `consume record` node is the drift, and §2 is authoritative.**

### The contradiction this resolves

The spec said both things:

| Source | Says |
|---|---|
| §2, settled decisions (2026-09-16) — **authoritative** | "Until that rule changes again — fingerprinted to the list's exact new state" |
| §5.1 flowchart | `approval on record? → yes → allow — **consume record**` |
| §6.1, fourth scenario | "re-committing the same approved list state does not re-prompt" |
| `hooks/lib/secret_approval.py` | single-use: the record is deleted on first `consume` |

§6.1's scenario and the flowchart cannot both hold. If the record is consumed by the first commit,
the second commit of the same state re-prompts, which is exactly what that scenario forbids.

### Why state-scoped wins

Three of the four sources agree, and the dissenting one is a diagram node rather than a decision:
§2 settles it explicitly, §6.1's scenario demands it behaviourally, and §8's Gherkin keys the
approval to a state. Only the §5.1 flowchart says "consume record".

Beyond the count: the thing the human approved is **a state of the rules**, not one particular commit
object. Amending a commit, rebasing it, or re-running it does not un-approve the loosening.

The single-use property in `secret_approval.py` exists for approving **shell command text**, where
replay is the threat being contained. For a permission-list state the state *is* the identity, so
re-presenting the same state is not a replay — it is the same fact.

### What stays unchanged

**An approval never transfers across states.** An approval for state S1 must not satisfy a different
loosened state S2 — spec §6.2's fourth scenario, and spec §8's Gherkin. Decision 1 widens lifetime
**across commits**, never **across states**. That is the whole security property, and task 3's probe
already measured that the key discriminates S1 from S2 (33 assertions, both stubs failing).

### Consequences

- `secret_approval.py`'s `grant`/`consume` keep working, but the watcher must not call `consume` in
  the sense of deleting. The new `state-id` entry point task 3 specified is where this lands.
- Task 4's `G4` is strengthened from one silent re-commit to several, **and must assert the record
  still exists afterwards** — silence alone is also what a hook that never ran produces.
- A control that consumes on first use must exist in the matrix, or nothing in the suite
  discriminates this decision from the rejected one.

## Decision 2 — attendedness reads two independent signals, and the fallback refuses

**`permission_mode` is the primary signal** — measured present on `PreToolUse`, see below.
**Subagent markers (`agent_id` / `agent_type`) are a second, independent leg.** If neither signal
identifies the session as attended, the hook **exits 2**. Any path that concludes "unattended" exits
**2** and never emits an `ask`.

### The measurement that settled this, 2026-10-29

A temporary probe hook was registered on `PreToolUse`/`Bash` in the primary `settings.json`, two
payloads were captured, and it was removed. The probe recorded **key names only** — never values,
except `permission_mode` and `agent_type`, the two fields in question — and was falsified against a
canary string in the command text, which did not appear in its output. It always exited 0 with empty
stdout, so it could not alter any tool call. `settings.json` was restored and verified
**byte-identical by SHA-256** afterwards.

| Session | Keys | `permission_mode` | Subagent markers |
|---|---|---|---|
| Main | `cwd`, `effort`, `hook_event_name`, `permission_mode`, `prompt_id`, `scratchpad_dir`, `session_id`, `tool_input`, `tool_name`, `tool_use_id`, `transcript_path` | `'bypassPermissions'` | absent |
| In-process subagent | the same, **plus `agent_id` and `agent_type`** | `'bypassPermissions'` | `agent_type='general-purpose'` |

⚠️ **Scope this honestly: only one mode value was ever observed.** This session runs bypassed, so
every captured payload read `'bypassPermissions'`. What is established is that **the key exists on
`PreToolUse` and reported bypass correctly**. That the field reports `'default'` in a normal session
is **not** measured — it is inferred from the key being present and from `PostToolUse` and
`UserPromptSubmit` behaving that way. A hook must therefore still treat an unexpected or absent
value as unattended rather than assuming the value space is closed.

Second confirmed fact: **an in-process subagent inherits the parent's `permission_mode`**. So the
mode alone cannot distinguish a subagent from its parent — which is exactly why the subagent markers
are a separate leg rather than a redundant one.

### How this decision arrived in two steps, and what the first step shipped

The decision was taken **twice**, and the record should show both.

**Step one (rejected premise).** With `permission_mode` unmeasured on `PreToolUse`, "refuse when the
field is absent" was rejected on the grounds that *if the field never appears, every loosening
refuses* — a feature that refuses unconditionally being indistinguishable from one switched off. The
repo has that exact failure on record: ADR 0035 found a `PostToolUse` `model` branch that would have
been dead code, silently falling through, invisible because the fallback usually agreed. So the
fallback was set to **ask**.

**That intermediate state shipped an active fail-open**, and task 4's second pass caught it: under a
bypass session an `ask` is silently allowed and the command runs, so a fallback that asks lets the
loosening through with no prompt reaching anyone. It was pinned by `R1e`/`R1k` and noted in the
suite's `A3` comment, so it was visible rather than latent — but it was the wrong behaviour.

**Step two (after measuring).** The field is present. The dead-feature risk that justified the
hedge does not exist, so the fallback was made strict: **exit 2**. The fallback is now a defensive
branch for a state not observed to occur, and making it refuse costs nothing.

The lesson worth keeping: the first decision was sound reasoning on an unmeasured premise, and one
cheap measurement dissolved the trade-off entirely. The hedge was reasoning where measuring was
available.

### Why exit 2 and not `ask`

Task 0 measured both halves in one session from one hook: under a bypass-permissions session an
`ask` decision is **silently allowed and the command runs**, while a `deny` blocks. So "refuse when
unattended" is only real if it is exit 2. This is already §7's requirement; decision 2 does not
loosen it.

### Residual risk, after the measurement

**The fail-open is closed.** Two earlier drafts of this section were wrong in opposite directions
and both are superseded: the first called a bypass session merely "not detected as unattended"
(too soft — the fallback's `ask` actively waved the commit through), the second called that an
active fail-open and said `permission_mode` "remains unmeasured" (true when written, false now).
As it stands: the field is present, a bypass session reads `'bypassPermissions'`, the hook
classifies it unattended and exits 2, and the fallback refuses rather than asking.

What remains open is narrower, and none of it is a fail-open:

1. **The mode value space is not enumerated.** Only `'bypassPermissions'` was observed. Treat an
   unrecognised value as unattended; do not switch on a closed set of strings.
2. **A non-default mode other than bypass is undecided.** `acceptEdits` and `plan` are neither
   measured nor classified. The suite keeps the existing "any non-default value is unattended"
   reading, which is conservative but unverified.
3. **The probe measured this machine, this Claude Code version, two payloads.** A schema is not a
   contract. If the key disappears in a later version the fallback refuses, which is the safe
   direction — and the reason the fallback is strict rather than permissive.
4. **`agent_type` alone, without `agent_id`, is untested** as a subagent indicator. Dumping one real `PreToolUse` payload would settle it, and needs a hook in the
**primary** `settings.json`, since hooks load from the primary checkout and a branch edit is inert.
That measurement is open work, not a blocker.

## Consequences for the spec

- §2's "until the rule changes" is correct; §5.1's flowchart node "consume record" is **wrong** and
  must be revised when §5 is next edited (it is already out of date on two counts from ADR 0052).
- §6.2's "an approval does not transfer to a different list state" is unaffected and still binding.
- §7's fail-closed table gains no row, but "unattended" now has a defined detection order rather
  than a single field lookup: `permission_mode` first, subagent markers second, exit 2 if neither
  establishes an attended session.
- Task 9 may describe the unattended check as reading `permission_mode`, which is measured present
  on `PreToolUse` — but must say that the subagent markers are a separate leg and why (a subagent
  inherits the parent's mode, so the mode alone cannot tell them apart).
- **The measurement procedure is reusable and worth keeping.** A key-only `PreToolUse` probe,
  canary-falsified against leaking command text, exiting 0 with empty stdout, installed with a
  backup and restored to a verified identical hash, is the cheap way to settle any future "does the
  payload carry X" question. This repo had three such questions open across ADR 0035,
  `git-guard-quiet.md` and this card, each answered separately and partially.
