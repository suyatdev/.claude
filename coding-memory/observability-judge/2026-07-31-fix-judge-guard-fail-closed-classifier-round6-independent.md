# Observability judge — RUN 6, independent re-measurement (implementation)

- **repo:** `jg-failclosed` (worktree `~/.claude/.claude/worktrees/jg-failclosed` — every measurement below was taken here, never in the primary checkout)
- **branch:** `fix/judge-guard-fail-closed-classifier`
- **head_sha judged:** `d51a4311a060396d067096d2a41fe380ba5a80c0`
- **base:** `origin/main` @ `2b8564b` (also the merge-base)
- **stage:** implementation
- **tests, run by me at this HEAD:** `bash hooks/judge-guard.test.sh` → **81 passed, 0 failed**; `python3 hooks/lib/classify-pr-command.test.py` → **51 passed, 0 failed**. Both reproduce the dispatch's numbers.

## Filename and dispatch note — read this first

The dispatch told me to write `…-round6.md`, believing that name was free. It was not: a peer
judge completed RUN 6 at `d51a431` (verdict ts `02:23:46Z`) and the primary session **committed it
as `eab1138` while I was mid-measurement**. Overwriting a committed verdict would destroy exactly
the audit trail this branch exists to defend, so this file takes a distinct name. Nothing was
overwritten.

Two further facts about the state I found, both material:

1. **HEAD moved under me, twice.** At my first command HEAD was `d51a431`; by the time I finished
   probing it was `0839485` ("test(hooks): pin that a live command is read whatever the tool is
   called (red)"), with `hooks/judge-guard.sh` modified and uncommitted. The primary session has
   **already accepted the peer's F1 finding and is mid-fix**. So this is a late/duplicate dispatch
   against a superseded SHA.
2. **I was anchored.** The peer's concerns list appeared in my very first `git diff` output before I
   could form independent findings. I therefore treated my job as *verifying each claim by
   measurement* rather than restating it, and I flag below which findings are mine and which are
   confirmations. One of the peer's claims I could not reproduce as stated, and I nearly published a
   wrong mitigation of my own before measuring it — both recorded.

Because the working-tree hook was being rewritten as I worked, **every load-bearing probe below was
re-run against the committed `d51a431` blob** (`git show d51a431:hooks/judge-guard.sh`, staged in a
temp dir with its `lib/`), not against the working-tree file.

---

## What was changed

The repo has a bouncer script, `judge-guard.sh`, that stands in front of `gh pr create` and refuses
to let a pull request out until a fresh review verdict exists for the exact commit you're shipping.
This branch is a long clean-up of one embarrassing habit: when the bouncer's own equipment broke, it
waved everyone through instead of stopping them. Earlier rounds fixed four such cases.

This round did two things. First, it corrected a **false sentence in its own documentation** — three
places claimed "every Edit, Read and Write reaches this hook," and they don't; the bouncer is only
posted on the Bash door. Second, acting on that correction, it added a rule: if a *Bash* call shows
up with nothing runnable in it, block, because the only thing that sends Bash calls is this session
and it always has a reason to send a real command.

## Does it do what you wanted?

Yes for the thing you asked for, and it quietly broke a neighbouring thing you didn't.

The requested rule works. Measured against the committed blob, with an empty verdict store:

| payload | base `2b8564b` | `d51a431` |
|---|---|---|
| `Bash` + `gh pr create --fill` | block | block ✔ |
| `Bash`, command absent | **pass** | **block** ✔ (the fix) |
| `Bash`, command `""` | **pass** | **block** ✔ (the fix) |
| `Edit`, no command | pass | pass ✔ |

But the same commit made the guard **weaker than what it replaced** in one direction, and it is the
exact direction the change's own justification cites as its reason for existing.

## What could go wrong / what I'm unsure about

**F1 — a real `gh pr create` walks straight through under any tool name but `Bash`. Confirmed by my
own measurement, not taken on trust.** `judge-guard.sh:85` (`if tn != "Bash"`) returns *before the
command is ever read*, so the command is never examined. Same payload, same empty store:

| `tool_name` carrying `command: "gh pr create --fill"` | base `2b8564b` | `d51a431` |
|---|---|---|
| `Bash` (control) | block (2) | block (2) |
| `mcp__shell__exec` | block (2) | **pass (0)** |
| `Shell` | block (2) | **pass (0)** |
| `bash` (lowercase) | block (2) | **pass (0)** |
| `BashOutput` | block (2) | **pass (0)** |
| `"Bash "` (trailing space) | block (2) | **pass (0)** |

This is a **regression**, not merely an uncovered case: the base hook read `tool_input.command`
regardless of the tool's name and blocked all six. **Not live today** — I re-enumerated the
registrations myself rather than trusting the dispatch: exactly one live registration
(`~/.claude/settings.json`, `PreToolUse`, matcher `Bash`), duplicated in two worktree
`settings.json` files, all matcher `Bash`, all pointing at `$HOME/.claude/hooks/judge-guard.sh` —
the primary checkout's older copy. Nothing on this branch is armed.

**F2 — a live false claim in the fix's own commentary, third consecutive round for this class.**
`judge-guard.sh:62` says reading the payload "keeps this file correct under any matcher." Measured
false in the coverage direction: under a wider matcher the new code is *strictly less covering* than
the code it replaced, for precisely the tools a wider matcher would newly admit. It is true only in
the *outage* direction (a `*` matcher won't block every editor call). `judge-guard.sh:69` ("any
other named tool → SKIP, pass: nothing here is a shell command to guard") and ADR `0012:158`
("any other named tool | pass — no shell command to guard") state the same thing as fact. ADR
`0012:167` states the accurate, narrower version. Treat the doc sites as as much the defect as the
code — that is the branch's own stated lesson.

**F3 — the green suite structurally could not see F1.** The three pass-through cases,
`judge-guard.test.sh:332-334`, are `Edit`, `Read`, `Write` — **all with no `command` field at all**.
Nothing in 81 passing tests builds the one shape that fails open: a non-`Bash` name *carrying a
runnable command*. One assertion would have caught it. This is the clearest success-masking on the
branch.

**F4 — mine, not in the peer verdict: four "nothing runnable" payloads that ALLOW, contradicting the
rule this commit shipped.** `judge-guard.sh:66-68` and ADR `0012:157` promise *Bash + nothing
runnable → block*. Measured against the committed blob:

| `Bash`, `command` = | result | expected by the shipped rule |
|---|---|---|
| `"\x00"` (lone NUL) | block — *"internal error"* | block |
| `"\x00   "` (NUL + spaces) | **ALLOW (0)** | block |
| `"\x01"` (lone SOH) | **ALLOW (0)** | block |
| `"\x01  "` | **ALLOW (0)** | block |
| `"\x7f"` (DEL) | **ALLOW (0)** | block |
| `" "` (NBSP) / `"\x0b"` (VT) | block | block |

Mechanism: `judge-guard.sh:94` uses Python `str.strip()`, which treats NBSP and VT as whitespace but
**not** NUL, SOH or DEL. So `"\x00   "` survives `strip()`, the parser emits `OK`, bash command
substitution then silently drops the NUL, and `"   "` reaches the assertion at `:127` as non-empty —
so the fail-closed assertion never fires, the classifier returns `NO`, and the call passes. A lone
NUL blocks; a NUL followed by a space passes. That asymmetry is undocumented and it is the same
class of hole this commit was written to close. Not reachable from the real session today, but the
rule as documented is stronger than the rule as coded.

**F5 — confirmed: `judge-guard.sh:123` "Unreachable by construction" is wrong.** The lone-NUL payload
reaches the inverted assertion at `:127` and fires it (measured rc=2, *"internal error — parser
reported OK with no command"*). The direction is right — it blocks — so the inversion earns its
keep; only the comment is false.

**F6 — mine: more ways to block every Bash call on the machine from a cause outside this repo.** The
ADR pins only the stdout-noise instance, via a *fake* `python3`. The parser runs as `python3 -c`,
whose `sys.path[0]` is `''` — the session's current directory. Measured on the committed blob, benign
command `git status`:

| condition | result |
|---|---|
| clean cwd (control) | pass |
| **a `json.py` file sitting in the session's cwd** | **every Bash call blocks** |
| `PYTHONPATH` containing a `json.py` | every Bash call blocks |
| `PYTHONPATH` containing a `shlex.py` | every Bash call blocks (names the classifier — the good failure) |
| `PYTHONPATH` with a `usercustomize.py` that prints | every Bash call blocks |
| `PYTHONIOENCODING=ascii` + an em-dash commit message | every Bash call blocks |

The first is the dangerous one: `cd` into almost any Python project with a top-level `json.py` and
the entire Bash tool dies, with a message blaming the payload, where nothing is wrong. You cannot
run a shell command to recover.

**A mitigation I nearly got wrong, and the correction.** My first pass appeared to show
`PYTHONSAFEPATH=1` immunising this. It does not — that run was a false negative (I had deleted the
poison file before testing the mitigation). Re-measured properly: this machine's `python3` is
**3.9.6**, where `PYTHONSAFEPATH` is ignored and `-P` is an unknown option. **`python3 -I -c` is the
flag that actually works** — measured: in a shadowed cwd the hook as shipped returns 2, and with
`-I` added to the parser it returns 0, loading stdlib `json`. Recording the wrong attempt because on
this branch a wrong correction in an audit trail is worse than the original wrong claim.

**F7 — structural, and it is biting right now: committing the verdict invalidates the verdict.**
Freshness is strict (stored `head_sha` must equal current HEAD), and verdicts are committed
documents. So the act of committing a verdict advances HEAD and staleness the verdict it just
recorded. Measured: **zero** committed verdict lines match current HEAD. The branch has already
burned commits on this — `d51a431` exists solely to re-point RUN 6 at a moving HEAD, and `eab1138`
invalidated it again the moment it landed. The escape is to open the PR *before* committing the
verdict, which fights the documentation-checkpoint discipline pulling the other way. This predates
the diff under judgment, so it is context rather than a defect of this change — but it is the reason
this gate keeps costing round-trips.

**Carried, re-read and accurate, not re-litigated:** fails-closed machine-wide by design, with no
bypass variable; residual 8 (ADR `0012:299-304`); residual 9 — the gate checks a verdict *exists*,
not what it *says*, against an agent-writable store (ADR `0012:307`); quoted `PR_URL="$(gh pr
create)"`; no classifier timeout. The old "every Edit, Read and Write" phrasing surviving at
`judge-guard.sh:60` and ADR `0012:140` is **quoted and immediately contradicted** — correct audit
trail, checked in context, not reported as unfixed.

## What I'd double-check before merging

1. **Do not open a PR at `d51a431`.** It carries a measured coverage regression. HEAD has already
   moved past it with the fix in flight — judge the fix, not this SHA.
2. When the in-flight fix lands, **add the assertion F3 is missing**: a non-`Bash` `tool_name`
   carrying a live `gh pr create` must block. Without it the same hole reopens silently.
3. **Fix the doc sites in the same commit as the code** — `judge-guard.sh:62`, `:69`, `:123` and ADR
   `0012:158`. Three rounds running, the overclaim has migrated into the commentary of the fix for
   the previous overclaim.
4. **Decide F4 deliberately**: either widen "nothing runnable" to cover non-printable commands, or
   narrow the documented promise to match `str.strip()`. Right now the docs promise more than the
   code delivers.
5. **Consider `-I` on the parser's `python3 -c`** (measured to work on this 3.9.6 interpreter) before
   installing this hook machine-wide, and name the cwd-shadowing trigger in ADR 0012 alongside the
   stdout-noise one.
6. **Re-verify in a quiet worktree.** A peer was committing to this checkout throughout my run;
   confirm nothing here raced.

## Dimensions

| dimension | verdict | why |
|---|---|---|
| intent | concern | user's rule ("empty Bash call blocks") implemented correctly, but the same commit silently changed non-`Bash` behaviour, which was not asked for |
| execution | concern | 81/0 + 51/0 reproduced by me; TDD red→green genuine; but F1 regression and four allow-when-documented-to-block payloads (F4) |
| trajectory | concern | evidence-driven throughout, `tool_name` verified before use, harness fidelity split out and measured neutral — yet the change's central justification ("correct under any matcher") was never itself tested, and is false |
| regression | concern | measured block→allow flip on six shapes vs base. Unreachable under the sole live matcher (`Bash`) and the hook is not installed; **this is a `fail` the day the matcher widens** |
| context_budget | concern | `CODING_MEMORY.md` ~1470 lines against the 200-line cap stated on its own line 3; hook now 248 lines, ~90 of them comment; one rationale restated in hook + suite + ADR |
| traceability | concern | ADR 0012 + per-commit narrative are exemplary, but carry two live false claims (`:62`, `:123`) |
| success_masking | concern | strongest concern: 81 green tests while the three pass-through cases (`:332-334`) all omit `command`, so the suite structurally cannot see F1 |
| intent_drift | pass | confined to `hooks/`, `docs/`, memory artifacts; no new dependencies; harness change split from the behaviour change and measured neutral |
| checkpoint | pass | clean TDD sequence; `685f2af` isolates the behaviour change; every step revertable |
| audit_trail | pass | attributable commits, ADR updated, superseded claims labelled rather than deleted, prior verdicts preserved |

**risk: medium — confidence: high** (every assertion above measured against this worktree's
committed `d51a431` blob; confidence held at high rather than raised because the checkout was being
written by a peer throughout).
