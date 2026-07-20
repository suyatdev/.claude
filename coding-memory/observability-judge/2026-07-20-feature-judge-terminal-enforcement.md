# Observability Judge — architecting verdict

- **ts:** 2026-07-20T15:57:51Z
- **repo:** `.claude`
- **branch:** `feature/judge-terminal-enforcement`
- **head_sha:** `8aed77a39287e728a0a133039ead423d588bef91`
- **stage:** architecting (advisory, non-blocking)
- **artifact:** `docs/superpowers/specs/2026-07-20-judge-terminal-enforcement-design.md` (464 lines, sole commit on branch)
- **base:** `main`
- **test command:** none supplied; nothing executable exists at design stage. Verification was done by
  reading the design's load-bearing claims back against the real files they describe.

---

## What was changed

Right now the two judges are run because a *skill* tells the model to run them. A skill is a note on
the fridge — the model can walk past it. Only one judge has a real lock on the door: `judge-guard.sh`
stops `gh pr create` when there's no fresh verdict. The spec judge has no lock at all.

This design adds the missing lock and moves both judges out of the main chat window:

- `bin/judge-launch.sh` — one shared launcher that opens a judge in its own terminal pane and its
  own Claude session, so judging no longer eats the main conversation's context.
- `hooks/spec-guard.sh` — a new lock on `git commit` whenever the commit stages a file under
  `docs/superpowers/specs/`. That commit is the "the spec is finished" moment ADR-0003 said didn't
  exist.
- `hooks/judge-guard.sh` — instead of just refusing the PR, it can now start the judge and wait.
- Both judge skills switch from "spawn a subagent" to "call the launcher".

The verdict files keep their exact current shape. The terminal pane is treated as a window you can
watch, never as the answer — the hook always re-reads the verdict file to decide.

## Does it do what you wanted?

Yes. It closes the asymmetry it set out to close, it says plainly what it is *not* doing (it does not
judge every code commit), and it lists what it's deliberately leaving for later. The scope table is
tight and I found no drive-by extras.

I checked the design's claims about existing code rather than taking them on trust, and they hold up:
`judge-guard.sh` really does have the shlex/`rtk`/env-assignment classifier described, ADR-0003 really
does defer the spec hook for the stated reason, and both verdict schemas already carry the fields the
design leans on (`spec_blob_sha` is genuinely there — no migration needed, as claimed).

Two decisions are better than average and worth calling out:

- **The `--bare` reversal (§4.2).** The previously approved design said use `claude --bare`. The spec
  reverses that, in public, with reasons: `--bare` only accepts an API key, this machine uses
  subscription auth, forcing it would bill judge runs as separate API credits, and it would skip the
  CLAUDE.md discovery the compliance judge needs. Then it traces the *consequence* — without
  `--bare`, hooks run inside the judge session, so the `JUDGE_SESSION=1` recursion guard stops being
  a nicety and becomes load-bearing — and makes verifying it a blocking spike (S1). That is a
  deviation surfaced rather than smuggled, and it's reasoning, not luck.
- **Falsification is mandatory (§10),** and it's grounded in a specific past failure on this very
  branch lineage: a lock test planted a PID file with a trailing newline the real writer can't
  produce, so re-introducing the bug still passed 44/44. The design names that and forbids it.

## What could go wrong / what I'm unsure about

**Lead concern — the revise loop lost its brake.** Today `skills/running-the-compliance-judge/SKILL.md`
caps the loop: escalate to the user if the same violation `id` appears in two consecutive rounds, and
hard-stop if round 3 ends with anything outstanding. This design moves the loop onto the hook — §6.2
says "the revise loop survives, now driven through the hook" and computes
`round = max stored round + 1`. Nowhere in the 464 lines is there a cap, a tripwire, or an escalation
on the hook path. The whole premise of this change is that skills are skippable; the cap lives only
in the skill, so the deterministic path inherits none of it.

Each round is a *full judge Claude session* — real tokens, up to 14 minutes. An agent that oscillates
(fixing one violation while re-introducing another) can spin that indefinitely with nobody being
asked. The design's line 174 ("forces a new judging round; this is what makes the revise loop
terminate honestly") is about blob-sha uniqueness preventing a *stale pass* — it is not a bound on
loop count, and shouldn't be read as one.

**The 900s hook timeout is load-bearing and unverified.** The entire fail-closed guarantee is the
sentence in §6.5: harness timeout 900s, launcher deadline 840s, so our own timer always fires first.
That rests on two unproven assumptions — that the harness honours a 900s hook timeout, and that a
timed-out hook fails *open*. No hook in `settings.json` currently sets an explicit timeout at all;
every one runs on the default. So 900 is unprecedented here. If the harness silently caps hook
timeouts lower, the gate fails open *exactly when the judge is slow* — the case it exists for — and
it fails open silently, which is the worst possible shape: a commit that looks judged and never was.
S1 and S2 are correctly marked as spikes; this assumption, which is more load-bearing than S2, is not.

**The classifier's blast radius grows a lot.** `judge-guard` matches `gh pr create` — rare, three
tokens. `spec-guard` matches `git commit`, the most-run command in the repo. §6.2 calls the reuse
"verbatim", and the shlex/`rtk`/env-walk part fairly is, but the `git -C <dir>` handling is genuinely
new code — I read `judge-guard.sh` and it has no `-C` handling whatsoever. Also, only `-C` is named:
`git -c foo=bar commit` and `git --git-dir=... commit` would slip past. That's consistent with the
accepted momentum-guardrail tradeoff, but a bug in this new classifier blocks *every commit*, not an
occasional PR.

**Smaller things.** A second PreToolUse/Bash hook means a second python spawn on every single Bash
tool call. The design never says what the main session shows during a 14-minute blocked `git commit`.
And the test seam is a fake `claude` on `PATH` writing canned verdicts — good for cost and speed, but
it means no automated test ever exercises a real judge, and rungs 1/3/4 rest on a manual checklist.

## What I'd double-check before merging

1. **Add a round cap and an escalation path to the hook itself** — mirror the skill's
   same-violation-twice and round-3 rules, or state explicitly why the hook path is allowed to be
   unbounded. This is the one gap I'd want closed before implementation starts.
2. **Promote the hook-timeout question to a blocking spike alongside S1.** Register a hook with
   `"timeout": 900`, make it sleep past the harness limit, and observe whether the tool call is
   blocked or allowed. Everything in §6.5 depends on the answer, and no existing hook here has ever
   set an explicit timeout.
3. **Run S1 first, exactly as the design demands.** If `JUDGE_SESSION=1` doesn't reach hooks inside
   the judge session, stop — the design is deadlock-shaped and the spec says so.
4. Decide whether `git -c` and `--git-dir` belong in the classifier, and make sure the `spec-guard`
   test harness covers a malformed/exotic `git commit` that must still be allowed through.
5. Confirm `coding-memory/judge-runs/` is actually in `.gitignore` before any run dir is written.

---

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Builds exactly the two gates + terminal sessions asked for; explicit non-goal; closes ADR-0003's deferral on its stated terms. |
| execution | concern | Design stage, nothing runnable. Test strategy is strong (falsification mandate, env seams, fake `claude`), but the 900s hook timeout and fail-open premise are load-bearing and unspiked. |
| trajectory | pass | The `--bare` reversal is reasoned in public with consequence traced to a blocking spike. Falsification rule grounded in a named prior failure. |
| regression | concern | Classifier widens from `gh pr create` to `git commit`; `git -C` handling is new code, not verbatim reuse; only `-C` of git's global options is covered; second python spawn per Bash call. |
| context_budget | pass | Net positive — moves judge work out of the main window. No always-on rule bloat; hook/skill edits are small. |
| traceability | pass | Two Mermaid diagrams, exit-code table, failure matrix, manifest fields, run-dir layout, pinned+dated toolchain, design-of-record cited and present. |
| success_masking | concern | Hook-driven revise loop has no round cap or escalation — the skill's round-3 tripwire does not transfer to the deterministic path, and each round is a full judge session. Compounded by a silent fail-open if 900s isn't honoured. |
| intent_drift | pass | Tight scope table, explicit non-goal, deferred list, no new dependencies (`no jq` stated). Single docs-only commit. |
| checkpoint | pass | One commit, docs only, on a feature branch — trivially revertible. Nothing modified in place. |
| audit_trail | pass | §12 lists a new ADR, an ADR-0003 update, and `rules/gates.md` + skill updates. Attributable and ADR-worthy. |

## Concerns

- Hook-driven revise loop has no round cap or escalation; the skill's same-violation-twice and round-3 tripwire do not transfer to the deterministic path
- Each uncapped round costs a full judge Claude session (tokens + up to 14 min); oscillating agent can spin it indefinitely with no user escalation
- `"timeout": 900` is unverified and unprecedented — no hook in settings.json sets an explicit timeout today
- The "harness timeout fails OPEN" premise underpinning all of §6.5 is asserted, never measured, and is not in the spike list
- If the harness caps hook timeout below 900s, the gate fails open silently exactly when the judge is slow
- `git -C` global-option handling is new code, described as "verbatim" reuse of a proven classifier that has no `-C` handling
- Only `-C` covered; `git -c foo=bar commit` and `git --git-dir=... commit` evade the gate
- Classifier blast radius widens from rare `gh pr create` to the highest-frequency command in the repo; a bug blocks all commits
- Second PreToolUse/Bash hook adds a python spawn to every Bash tool call
- No automated test exercises a real judge (fake `claude` on PATH); rungs cmux/iTerm2/Terminal rest on a manual checklist
- Design does not say what the main session displays during a 14-minute blocked `git commit`

**risk:** medium · **confidence:** high
