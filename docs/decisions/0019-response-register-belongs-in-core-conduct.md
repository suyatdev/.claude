# 0019 — Response register is a static rule in `core-conduct.md`, not auto memory

- **Status:** Accepted (2026-08-07)
- **Context:** `rules/core-conduct.md` § Session Defaults; retires the auto-memory files
  `feedback_explain_in_laymen_terms.md` and `feedback_always_give_a_recommendation.md`
- **Note:** ADR number 0018 is reserved by `docs/features/memsearch-freshness.md` task 2, which
  already cites it by number. This decision takes 0019 rather than renumber a spec mid-judging.

## Context

Two standing requests about how the assistant talks to the user:

1. **Plain language on every reply**, while still showing real code, diffs, and command output where
   the explanation depends on reading them.
2. **Every prompt carries a recommendation** — which option the assistant would pick, and why.

Neither was reliably held. An audit on 2026-08-07 found why:

- The plain-language rule existed only as auto memory
  (`projects/-Users-marksuyat--claude/memory/feedback_explain_in_laymen_terms.md`), and its first
  six words scoped it to *"When asking the user a question"*. Ordinary explanations, findings, and
  status reports were never covered, so the rule read as already-followed while being routinely
  missed. The user asked for it three separate times (2026-08-02, and again in sessions 33 and 35).
- The recommendation rule did not exist at all. `grep -riE "recommend" CLAUDE.md rules/ agents/`
  returned zero matches. The only adjacent guidance is the `AskUserQuestion` tool's own convention,
  phrased conditionally (*"**if** you recommend a specific option…"*), so it obligated nothing.

`triaging-new-instructions` classified both at tier 2 — they must hold on every turn and no script
can judge whether prose is jargon-free or whether a recommendation was given — so both belong in
`rules/core-conduct.md`, which loads in every session in every project on the machine.

## Options weighed

1. **Leave them in auto memory.** Rejected on scope. Auto memory is keyed per project
   (`~/.claude/projects/<project>/memory/`); four such directories exist on this machine, and only
   the current repo's `MEMORY.md` loads at session start. It is also gitignored (`.gitignore:43`),
   so it never commits and never syncs. A rule about how the assistant speaks must not be
   repo-specific.
2. **Copy the memory files into all four project directories.** Rejected: four copies of one rule
   that must never diverge is precisely the failure `feedback_delete_the_duplicate_dont_sync_it`
   records, and it still would not cover the fifth project.
3. **Managed-policy `/Library/Application Support/ClaudeCode/CLAUDE.md`.** Verified to work — it
   applies to every session in every repo and sits outside this git repo, so `phase-guard.sh`
   returns exit 0 for it (falsifier: `rules/core-conduct.md` returns exit 2, so the check can fail).
   Rejected anyway: it requires `sudo`, the directory does not exist, it cannot be overridden
   per-project by design, and it would become a third copy to reconcile.
4. **A claude.ai response Style.** Rejected: Styles govern formatting and voice. The recommendation
   rule is about the *substance* of a reply, not its presentation.
5. **`rules/core-conduct.md` § Session Defaults (chosen).** One file, loaded in every session in
   every project, colocated with the other permanent invariants it sits beside.

## The two-system boundary

claude.ai (web, desktop, mobile) and Claude Code share nothing. Claude Code loads instructions only
from managed policy, `~/.claude/CLAUDE.md`, `~/.claude/rules/`, project `CLAUDE.md` /
`.claude/rules/`, `CLAUDE.local.md`, and auto memory — no account-level setting from the website
reaches it, and nothing on disk here reaches the website. Covering both therefore requires two
edits, not one. The claude.ai half lives under **Settings → "Instructions for Claude"** (account
initials, lower left), which applies to all conversations there.

Both mechanisms load **at session start only**; a mid-session edit changes nothing until a new
session or `/clear`. Instructions given only in conversation are lost on `/compact`.

## Consequences

- The two auto-memory files are now duplicates of an authoritative rule and are to be deleted,
  along with their `MEMORY.md` index lines. One fact, one home.
- `rules/core-conduct.md` grows by one paragraph. It is a permanent invariant, which is what that
  file is for; no gate stub or skill is warranted, since there is no procedure to carry.
- The edit was made by hand rather than by the assistant. `phase-guard.sh` is registered
  `PreToolUse` with matcher `Edit|Write|NotebookEdit`, so it intercepts agent tool calls only; a
  human editing the same file is unaffected. The guard was blocking correctly by its own contract —
  it matches on path, not intent, and `rules/` is not on its exempt list — but the block was a
  false positive here, since neither planning feature (`memsearch-freshness`,
  `verification-marker-gate`) has any relationship to the assistant's response register.
- `rules/` is also outside `git-guard.sh`'s documentation allowlist for `main`, so committing the
  change requires a feature branch. Until that branch exists the rule is live on disk but absent
  from git history.
