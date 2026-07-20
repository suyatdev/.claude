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

---

## Round 2 — 2026-07-20T16:20:33Z — **FAIL** (3 violations)

Head sha: `ccd02fca57f9dd94e356fb0545efd463c46a1d47`
Spec blob sha: `f52cd4779b4c7581fe329e5a76418da9650dc898`
Confidence: **high** (agent input lists, the cmux binary's real existence, and the round-1 store entry all verified directly against the machine and repo)

### Layman summary

Three of round 1's five violations are cleanly and convincingly closed. The launcher is now six
files with per-file line budgets enforced by the test harness, not by good intentions
(`core-conduct/small-focused-files`). The run directory gets a real permission posture — `umask 077`,
`0700`/`0600`, asserted with `stat` after creation rather than assumed, with a preflight failure if
the modes are wrong (`core-conduct/default-deny-stores`). And the terminal ladder is down to four
rungs, each mapped to a terminal the user actually works in plus a headless correctness floor; that
was the user's own decision and it is recorded where a reader will find it (`core-conduct/yagni`).
The revision also found and fixed a defect nobody asked about — the gate and the judge hashed
different content, which would have livelocked the revise loop — and §6.5's S3 spike is a model of
how to surface a design fork as human-owned rather than quietly picking a branch. The growth from
464 to 855 lines is substance, not padding.

Two round-1 violations persist, both for a narrower reason than before, and one new one appears.

The persistent one is the same plumbing gap, one layer down. Round 1 said the launcher's argument
set could not carry what the judges need; round 2 fixed that by adding `--context-file`,
`--prior-violations-file`, and `--decisions-file`, and by specifying a prompt template. But nothing
says where the *hook* gets those files. `--context-file` is mandatory for a compliance launch, and
the deterministic path — a `git commit` that spec-guard intercepts — has no main-agent reasoning to
draw a context summary from. The skill path can author one; the hook path, which is the entire point
of this change, cannot. The observability side has the same hole for `--decisions-file` in §6.3, and
the prompt template additionally has no slot at all for two arguments §6.1.2 accepts: observability's
`--spec` (the template marks `spec_path` "compliance only") and `--test-cmd-file`.

The escalation cap persists for a related but distinct reason. The cap fires when the same violation
id appears in the two most recent rounds. That depends on the judge *reusing* ids, which its
definition only does when it is handed the prior round's violations array — and nothing in §6.2.1
specifies the hook extracting that array from the store into `--prior-violations-file`. §6.2.1 does
establish that attempt history is reconstructible from the store, but it uses that only to count
rounds, not to feed the judge. Without the feed, each round mints fresh slugs, "same id twice" never
matches, and the only surviving tripwire is the round-3 cap. `rules/gates.md` requires persistent
violations to escalate; two thirds of the mechanism designed to do that would silently no-op.

The new one is small and concrete: cmux is rung 1, the user's primary environment, and it is missing
from §4's pinned-version table entirely — while tmux, git, python, bash, and the Claude CLI are all
pinned. Its spawn is given as the words "cmux pane", not a command, where rung 2 gets
`tmux split-window -d` and rung 4 gets `nohup`. cmux is a real binary on this machine
(`/Applications/cmux.app/Contents/Resources/bin`, invoked elsewhere in this repo as
`${CMUX_CLAUDE_HOOK_CMUX_BIN:-cmux}`), so this is a fillable blank, not an unknowable — but as
written the highest-priority rung is the one an implementer cannot build.

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | API contracts give the agent real interface boundaries instead of letting it improvise shapes other components then fail to match | §6.1.2 argument contract; §6.1.3 prompt template; §6.2 decision order | The hook path never specifies how it produces the mandatory `--context-file` (or §6.3's `--decisions-file`), and the prompt template has no slot for observability's `--spec` or `--test-cmd-file`, so a deterministic launch cannot satisfy the launcher's own required-argument contract. |
| `gates/escalation-not-preserved` | `rules/gates.md` (spec-compliance gate) | Persistent violations escalate to the user, never silently waived | §6.2.1 round accounting and the escalation cap | The "same id in the two most recent rounds" tripwire depends on the judge reusing ids, which requires the prior round's `violations` array in the prompt, yet nothing specifies the hook building `--prior-violations-file` from the store — so that half of the cap can never fire. |
| `writing-specs/pinned-versions` | `skills/writing-specs/SKILL.md` | Pin the exact version of every library and tool the spec names | §4 pinned toolchain table; §6.1 terminal ladder rung 1 | cmux is the ladder's first and primary rung but is absent from the pinned table that covers every other named tool, and its spawn is specified only as "cmux pane" with no command, leaving the highest-priority rung unimplementable. |

### Notes (non-blocking)

- §5.2 is placed before §5.1 in document order. Cosmetic, but a reader following section numbers
  will stumble.
- The git global-option pass-through (`-C`, `-c`, `--git-dir`, `--work-tree`, `--namespace`,
  `--exec-path`, `--config-env`) is a fair amount of surface and four test cases for a gate whose
  stated need is spec commits in this repo — and §6.2 already accepts fail-open-with-a-warning for
  unclassifiable invocations, which would cover `-C` at zero cost. Not cited as YAGNI because
  `git -C ~/.claude commit` is a plausible real pattern in this setup, but it is worth a KISS pass.
- Round 1's four notes are all addressed: exit code `2` is now explicitly reserved and explained, the
  empty-store round is defined as `1`, `.gitignore` is in §12's obligations with an ordering
  constraint, and §6.7 states the operator-facing 840s cost.
- §6.5's handling of S3 is exemplary — an unmeasured assumption named as blocking, with the fallback
  design fork spelled out and explicitly reserved for measurement rather than implementation-time
  improvisation.
- §6.2.1's decision to keep `SPEC_ESCALATION_ACK` out of `prompt.txt`, and the reasoning for it, is
  the strongest single paragraph in the revision.

### Waivers

None. No waived ids supplied for this spec in any round.
