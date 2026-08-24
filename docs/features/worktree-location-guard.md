---
phase: planning
model_tier: xhigh
branch: none
---

# worktree-guard.sh — worktrees are mandatory, and they live in one place

> Closes the TODO recorded at `session-state.md:79-82`: the standing worktree rule (memory
> `feedback_always_work_in_a_worktree`, 2026-08-23) has lived only in memory and prose. Memory is
> advisory and does not survive into every session's attention; this feature gives the rule a
> computational home.

## Problem

Two related rules currently hold only by convention, and both fail the same way — silently, in the
exact session that forgot them.

**Rule 1 — work happens in a worktree, never the primary checkout.** Several Claude sessions run
against one repo at once. The primary checkout has a single HEAD, so a session that parks it on a
new branch changes the branch out from under every other session sharing it. This has already
happened: one session moved `/Users/marksuyat/.claude` to a new branch while another had
uncommitted `panes/*.sh` edits in that same checkout, so that session's next commit would have
landed on a branch it never chose.

**Rule 2 — every worktree lives at `~/.worktrees/<repo-name>/<worktree-name>`.** Today they nest
*inside* the working tree at `.claude/worktrees/`, which puts checkouts inside the repo they are
checkouts of. Centralizing them gets worktrees out of the tree entirely and makes "what am I
working on, machine-wide" a single `ls`.

## Decisions taken (user, 2026-08-24)

All four settled explicitly via `AskUserQuestion` before any design work. Recorded here because
several are deliberate acceptances of a known cost, and a later reader will otherwise re-litigate
them.

| Decision | Choice | Note |
|---|---|---|
| Enforcement | **Hard deny** (exit 2), no bypass variable | `phase-guard.sh` shape, not a warning |
| Trigger surface | Write/Edit/NotebookEdit **+ a heuristic Bash arm** | Bash arm is best-effort — see Non-goals |
| Path exemptions | **Reuse `phase-guard.sh:294-298` verbatim** | `docs/*`, `.claude/*`, `settings.json`, `projects/*/memory/*`, `rules/*`, `skills/*` |
| Repo opt-in | **None — every git repo on this machine** | Deliberate divergence from `phase-guard.sh:248`; blast radius accepted, see below |
| `<repo-name>` segment | **Directory basename** | Collision risk accepted, see Open questions |
| Existing 4 worktrees | **Not migrated** | Guard applies to new `git worktree add` only |

### The accepted blast radius

`phase-guard.sh:248` exits silently unless the repo has a `docs/features/` directory — an opt-in
signal, so a repo that never heard of the phase workflow is never blocked by it. **This hook has no
such signal, by explicit user decision.** The consequence was stated plainly before the choice and
is restated here so it is not discovered later as a bug:

> Every fresh `git clone` on this machine will deny guarded writes from its primary checkout until
> a worktree exists for it.

That is the intended behavior, not an oversight. The escape hatch is that `settings.json` is on the
exemption list, so the hook's own registration always remains editable — the same reasoning
`phase-guard.sh:280-283` gives for exempting it there ("a guard that can block edits to its own off
switch is a footgun").

## Detection — verified, not assumed

The primary-vs-linked test is `git rev-parse --git-dir` against `--git-common-dir`. Probed on
git 2.50.1 (Apple Git-155):

| Where | `--git-dir` | `--git-common-dir` |
|---|---|---|
| Primary checkout, at root | `.git` | `.git` |
| Primary checkout, **in a subdirectory** | `/Users/marksuyat/.claude/.git` | `../../.git` |
| Linked worktree | `<common>/worktrees/close-model-re` | `/Users/marksuyat/.claude/.git` |

**The naive string compare is a fail-open, and it is the first thing to get right.** From any
subdirectory of a primary checkout the two values differ *in form only* — absolute vs. relative —
so `[ "$d" != "$c" ]` reads "these differ" → "this is a linked worktree" → **allow**. The guard
would be silently off in every subdirectory of every primary checkout, which is most writes. This
is the same fail-open class that cost `phase-guard.sh` six judge rounds, arriving here on day one.

**Fix:** `git rev-parse --path-format=absolute --git-dir` and `--git-common-dir`, which normalize
both sides. Verified above — primary-in-subdirectory collapses to two identical absolute paths, and
the linked worktree still differs. `--path-format` requires git ≥ 2.31; the version floor needs an
explicit check and a fail-open below it (task 2).

## Scope of rule 2 — where worktrees may live

Target layout, nested in this order:

```
~/.worktrees/<repo-name>/<worktree-name>
```

`git worktree add` accepts an arbitrary `<path>` (verified: `git worktree add --help`), so git
itself imposes no obstacle. The obstacle is the harness.

### RESOLVED — `WorktreeCreate` is the mechanism; re-entry is one-shot

Probe complete (pane `general-purpose`, against installed Claude Code **2.1.241**). Two claims
independently re-verified here against the binary before being built on, per zero-trust: subagent
output is data.

**There is no setting that moves the CLI's worktree directory.** A `worktree.location` key exists
in the schema, and its own description rules itself out — re-verified verbatim by
`strings <binary> | grep "Directory under which"`:

> "Directory under which **Claude Code Desktop** creates the worktrees of **SSH sessions** … Read
> by the desktop app from the SSH host user settings … **The CLI (`--worktree`, `EnterWorktree`,
> agent isolation) does not read it yet.**"

Complete `worktree.*` key set (probe, from the settings zod schema): `symlinkDirectories`,
`sparsePaths`, `baseRef`, `bgIsolation`, `location`. Only `location` concerns paths, and the CLI
ignores it. The managed path is hardcoded as `join(repoRoot, ".claude", "worktrees")`, taking no
settings or env lookup. No `CLAUDE_CODE_WORKTREE_*` env var exists.

**`WorktreeCreate` / `WorktreeRemove` hooks DO work inside a git repo, and are the only supported
relocation mechanism.** Both re-verified as real event literals in the binary. The tool description
("outside a git repository") is misleading: the creator checks for the hook *before* it checks for
a git repo, so the hook branch wins everywhere. All three creation surfaces — `--worktree`,
`EnterWorktree name:`, and Agent/workflow `isolation: "worktree"` — route through it.

**This inverts the design.** A `WorktreeCreate` hook *redirects* rather than blocks, which is
strictly better than a `PreToolUse` deny: the session gets a worktree in the right place instead of
an error telling it to go make one.

#### The limitation to design around

`EnterWorktree path:` into a path outside the repo, by case:

| Case | Verdict | Detail |
|---|---|---|
| (a) First entry from launch directory | **works** | Only gate is `git worktree list` registration. But `checkPermissions` returns `ask` for any path outside `.claude/worktrees/`, and it is **not** auto-approvable — expect an interactive prompt |
| (b) Switching while already in a worktree | **blocked** | "Switching from this session is limited to worktrees managed by Claude Code" |
| (c) Pinned / `Agent(isolation:"worktree")` subagent | **blocked** | Same error |

Critically, the `requireManagedLocation` branch computes its allowed root as
`<repo>/.claude/worktrees` **with no `WorktreeCreate` hook consultation at all** — so even a
worktree our own hook legitimately created at `~/.worktrees/…` is unreachable in (b) and (c).

Two consequences:
- No mid-session switching between centralized worktrees. Route through a fresh session launched
  with `cwd` at the worktree instead.
- `Agent(isolation: "worktree")` cannot reach one. **Note this is not the same as pane dispatch** —
  `dispatch-pane-agent.sh` passes `--cwd`, launching a fresh session, which is unaffected. Worth
  confirming before relying on it (task 1a).

**The cost of taking the hook path:** our hook owns the entire lifecycle — creating the git
worktree, choosing the branch, and cleanup on `WorktreeRemove`. `worktree.baseRef` and
`worktree.sparsePaths` are **not applied** on the hook path; the hook branch returns before that
code runs. Today `baseRef` is unset (no `worktree` key in `settings.json`), so nothing is lost yet,
but re-implementing `fresh`-vs-`head` base selection is now our job.

## Design sketch

Two guards, or one hook with two arms — the split is an open question (see below).

**Arm A — the worktree requirement** (`PreToolUse` on `Edit|Write|NotebookEdit`):

1. Read the payload's `file_path` / `notebook_path`; no path → allow, silently.
2. Resolve the owning repo **from the write target**, never from the session cwd —
   `phase-guard.sh:191-197` records this as its one bug class, found in round 6.
3. Not in a git repo → allow, silently.
4. Path matches the exemption list → allow, silently.
5. `--path-format=absolute` compare: git-dir == common-dir → **deny**.

**Arm B — the location, by redirect** (`WorktreeCreate` hook — *not* a deny):

Registered with no `matcher`:

```json
"WorktreeCreate": [ { "hooks": [ { "type": "command", "command": "<abs path>/create-worktree.sh" } ] } ]
```

Contract (probe-reported; re-verify each before relying on it — task 1b):
- **Input** on stdin: base hook fields (`session_id`, `transcript_path`, `cwd`, `prompt_id?`,
  `permission_mode?`, `agent_id?`, `agent_type?`, `effort?`) plus
  `hook_event_name: "WorktreeCreate"` and `name: string`.
- **Output:** echo the absolute worktree path to stdout; the **last non-empty trimmed line** is
  taken. Must be normalized and absolute — no dot segments. A symlink-ancestry screen runs against
  the repo root, and its error text explicitly offers *"(or emit a path outside the repository)"*,
  so `~/.worktrees/…` is a first-class intended case.
- **The hook must create the worktree itself.** Claude does not. `hookBased: true` means no branch
  is created and none is reported — branch selection becomes ours.
- **`WorktreeRemove`** receives `worktree_path: string`; success is exit 0, no structured output.

Behavior: resolve repo root from `cwd`, compute
`$HOME/.worktrees/<basename-of-repo-root>/<name>`, `git worktree add` it, echo the path.

**Arm B2 — hand-rolled `git worktree add`** (`PreToolUse` on `Bash`), to stop the other route:

1. Lex into segments via `hooks/lib/shell_segments.py`, as `git-guard`/`merge-guard`/`doc-guard`
   already do, so `foo && git worktree add ...` is caught and a flag binds to its own segment.
2. Classify `git worktree add` — extend `hooks/lib/classify-git-command.py` rather than writing a
   fourth inline classifier (ADR 0029 moved `merge-guard` off exactly that pattern).
3. Extract `<path>`, skipping option arguments (`-b <branch>`, `--reason <string>` both take values).
4. Require the resolved absolute path to be under `$HOME/.worktrees/<basename-of-repo-root>/`.
   Anything else → **deny**, naming the correct path in the message.

**Arm C — the heuristic Bash write arm** — user-requested; scoped as best-effort in Non-goals.

### Deny message contract

`phase-guard.sh:537-561` sets the house shape and it should be followed: what was blocked, why,
the current state that caused it, the legitimate fixes, and a *narrow* closing claim. Element 5
must differ here — phase-guard says "no bypass environment variable" and can, because its escape
hatch is editing a `docs/` file. This hook's escape hatch is `settings.json`, so the message must
name that instead of implying there is no way out.

## Non-goals

- **The Bash arm is not a guarantee.** A `PreToolUse` hook on `Bash` receives the command *text*,
  never its effects. Whether `npm install`, `make`, `./gen.sh`, or a heredoc dirties the tree is not
  decidable from a string. The arm matches a literal list (`mv`, `cp`, `rm`, `touch`, `mkdir`,
  `tee`, output redirection) and will both over-block (a read-only script whose name looks writey)
  and under-block (every generator and installer). It was chosen with that stated. **The deny
  message must not claim the Bash surface is covered** — `phase-guard.sh:544-545` declines to
  overclaim for the same reason: "a safety message that overclaims teaches sessions to distrust its
  true parts too."
- Not a security boundary. A momentum guardrail, like every Tier 1 guard here.
- Does not migrate the 4 existing worktrees.
- Does not police worktree *removal* or `git worktree move`.

## Open questions

1. ~~**Is the harness worktree location overridable?**~~ **RESOLVED** — yes, via a `WorktreeCreate`
   hook only. See above.
2. **`<repo-name>` collisions.** Basename was chosen. Two repos named `api` in different orgs share
   `~/.worktrees/api/`, and two worktrees named `main` under them collide outright. Accepted for
   now; decide whether to detect-and-refuse or silently allow.
3. **One hook or two?** Arm A (write guard) and Arm B (`git worktree add` guard) share no logic and
   fire on different matchers. Two files is probably right; a shared `worktree-guard.sh` name for
   both invites the reader to expect coupling that does not exist.
4. **Bare repos and submodules.** `--git-common-dir` in a submodule points into the superproject's
   `.git/modules/`. Untested. Needs a case before shipping.
5. **Does `~/.worktrees` itself need creating**, and by whom? It does not exist yet (verified).
6. **Interaction with `phase-guard`.** Both are `PreToolUse` on the same matchers and both deny.
   A write can fail one, then the other — two sequential blocks for one write. Acceptable, but the
   messages should not be confusable.

## Tasks

- [x] 1. Read the probe result; settle open question 1. **DONE** — `WorktreeCreate` hook is the
      mechanism; `worktree.location` is Desktop-SSH-only. Two claims re-verified against the binary.
- [ ] 1a. Confirm `dispatch-pane-agent.sh --cwd` is unaffected by the (b)/(c) re-entry block — it
      launches a fresh session rather than calling `EnterWorktree`, so it should be, but the whole
      pane workflow depends on it.
- [ ] 1b. Re-verify the `WorktreeCreate` payload and stdout contract first-hand in a throwaway repo
      before writing the hook against it. The probe's claims are detailed and internally consistent,
      but they are subagent output, and the contract is load-bearing.
- [ ] 2. Establish the git version floor for `--path-format` (≥ 2.31) and the fail-open below it.
- [ ] 3. Write the failing test suite first — `hooks/worktree-guard.test.sh`, house style per
      `hooks/lib/guard_test_helpers.sh`. Must include: primary-at-root, **primary-in-subdirectory**
      (the fail-open above), linked worktree, each exempt path, non-git directory, detached HEAD,
      missing git, missing `--path-format` support.
- [ ] 4. Implement Arm A.
- [ ] 5. Extend `classify-git-command.py` for `git worktree add` + its own tests.
- [ ] 6. Implement Arm B against the extended classifier.
- [ ] 7. Implement Arm C, with the best-effort limitation stated in the message.
- [ ] 8. Register in `settings.json`. **Do this last** — an armed guard blocks edits to its own
      source from the primary checkout, since `hooks/*` is not on the exemption list.
- [ ] 9. ADR under `docs/decisions/` — this changes a machine-wide invariant and pivots the
      standing worktree rule from advisory to enforced. Verify the next free number against the
      deciding ref, not stale local `main`.
- [ ] 10. Update `rules/gates.md` with a stub, and `CLAUDE.md` if a skill is warranted.
- [ ] 11. Observability judge, then PR.

## Notes

- Live demonstration of the blast radius, this session: writing to root-level `session-state.md`
  was denied by `phase-guard` because three *unrelated* parked cards
  (`falsify-harness-signatures`, `treko-branch-graph-traversal`, `treko-degraded-no-cmux`) sit at
  `phase: planning`. Repo-global, no path scoping — unrelated work blocks unrelated work. The hook
  designed here is broader still.
- `claude-code-guide` **cannot be pane-dispatched** — the headless pane session does not register
  it. Available there: `claude, code-simplifier, compliance-judge, Explore, general-purpose,
  observability-judge, pane-echo, Plan, standards-extractor, statusline-setup`. Use
  `general-purpose` for harness-documentation probes.
- Session pane policy recorded this session: `panes max=3`.
- `cmux-layout` warns that cmux 0.64.22 is not the verified 0.64.20; pane placement rides an
  unverified heuristic. Not blocking, but `panes/cmux-layout-probe.sh` is stale.
