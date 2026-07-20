# Compliance verdict — Deterministic Judge Enforcement + Per-Judge Terminal Sessions

Spec: `docs/superpowers/specs/2026-07-20-judge-terminal-enforcement-design.md`
Repo: `.claude` · Branch: `feature/judge-terminal-enforcement`

---

## Round 1 — 2026-07-20T15:57:47Z — **FAIL** (5 violations)

Head sha: `8aed77a39287e728a0a133039ead423d588bef91`
Spec blob sha: `f157d436e4dd83cacc7e2a6c3514ecdbfab99827`
Confidence: **high** (versions, agent contracts, skill cap, and repo file sizes verified directly against the machine and repo)

### Layman summary

This is a strong spec. It has real Gherkin scenarios across good, bad, and edge paths, two Mermaid
diagrams, a failure matrix where every branch ends closed rather than hanging, accurate pinned
versions (all five verified on this machine), and it surfaces its one amendment to the approved
design at the top instead of slipping it in. The security thinking around the terminal spawn —
never interpolating a prompt into an AppleScript command, executing only `run.sh` — is genuinely
good.

Five things block it.

The biggest is a plumbing gap that would break the feature in a way tests would not catch: both
judge agents document required inputs that the new launcher has no way to pass them. The compliance
judge is told to judge YAGNI "against this stated need" using a context summary, and on round 2+ to
reuse violation ids from the prior round's violations array; the observability judge requires a
decisions summary. The launcher's argument list has none of these, and the spec's own security
invariant §9.3 forbids building the prompt from anything but that argument list. So the prompt
template — the actual interface between launcher and judge — is never specified and, as specified,
structurally cannot carry what the judges need.

That gap has a knock-on effect which is its own violation: the capped revise loop. Today the skill
escalates to the user when the same violation id appears twice running, or when round 3 still has
anything outstanding. The spec moves the loop into the hook but the hook has no memory between
separate `git commit` invocations, and without prior violations reaching the judge the id-reuse that
powers persistence detection cannot happen. §6.2 asserts "the revise loop survives" without saying
who now owns the cap. `rules/gates.md` requires persistent violations to escalate, never be silently
waived — as designed, they would be silently waived.

The remaining three are scope and hygiene: a five-rung terminal ladder where the spec itself admits
the rung-selection mechanism is unmeasured and three rungs cannot be tested automatically; a single
launcher script carrying about seven distinct responsibilities in a repo where no existing hook
exceeds 211 lines; and a new generated run directory holding frozen prompts, full model output, and
stderr that gets a gitignore entry but no permission posture, leaving §9.6's "No secrets in run
dirs" asserted with no mechanism behind it.

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | API contracts give the agent real interface boundaries instead of letting it improvise shapes other components then fail to match | §6.1 launcher signature; §5.1 `prompt.txt` | The launcher→judge prompt template is never specified, and the validated arg set (§6.1) cannot carry the inputs both agent definitions document as required — compliance's context summary and prior-round violations, observability's decisions summary. |
| `gates/escalation-not-preserved` | `rules/gates.md` (spec-compliance gate) | Persistent violations escalate to the user, never silently waived | §6.2 decision order / revise loop | Moving the revise loop into a hook with no cross-invocation attempt state drops the skill's escalation tripwires (same id twice, round-3 cap) and no new owner for them is named. |
| `core-conduct/yagni` | `rules/core-conduct.md` | KISS, DRY, YAGNI — prefer the simplest solution that fully solves the problem | §6.1 terminal ladder | Five spawn rungs are committed to when the stated need (own window, own session, visually trackable) is met by the measured rung plus headless; S2 concedes the env-var selection mechanism is unmeasured, and rungs 3–4 are the sole reason the osascript injection surface must be designed around. |
| `core-conduct/small-focused-files` | `rules/core-conduct.md` | Many small, focused files (<400 lines, 800 max) over few large ones | §6.1 `bin/judge-launch.sh` | One script is scoped to carry arg validation, preflight, run-dir/manifest creation, `run.sh` generation, a five-rung ladder, full lock lifecycle, and poll/liveness/exit mapping, with no decomposition or size budget stated, in a repo whose largest hook is 211 lines. |
| `core-conduct/default-deny-stores` | `rules/core-conduct.md` | Default-deny every generated data store | §5.1 run directory; §9.6 | `coding-memory/judge-runs/` stores frozen prompts, full model output, stderr, and argv but is given only a gitignore entry — no permission posture — so gitignore (which governs committing, not access) is the only control behind the "No secrets in run dirs" invariant. |

### Notes (non-blocking)

- Launcher exit code `2` is never defined (0, 1, 3, 4, 5 are used, consistently). Presumably reserved
  to avoid collision with the hook's own exit 2, but the implementer must infer that.
- `round = max(stored round for this spec) + 1` is undefined for a spec with no stored verdicts. The
  natural reading yields round 1; it is still left to inference.
- `.gitignore` currently has no `coding-memory/judge-runs/` entry, and §12's documentation
  obligations do not list adding one.
- Verified accurate: `claude 2.1.215`, `bash 3.2.57(1)`, `python 3.9.6`, `tmux 3.6a`, `git 2.50.1`,
  and both agents' tool lists match §4.1 exactly.
- The `--bare` amendment is handled well — flagged at the top, justified in §4.2, and gated behind
  blocking spike S1. That is a human-owned design change surfaced, not silently decided.
- A `git commit` can now block for up to 840s. §6.5 explains why the ordering must be that way, but
  the operator-facing cost is not called out for the user's review gate.

### Waivers

None. No waived ids supplied for this round.
