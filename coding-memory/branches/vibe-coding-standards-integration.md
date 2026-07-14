# Branch Implementation Log: feature/vibe-coding-standards-integration (MERGED)

**Status:** MERGED to main 2026-07-12 (PR #4, merge commit 5904702). The three-tier standards
integration is now LIVE in every session.

Shipped:
- **Always-on rules (Tier 2), 3,473 / 3,500-word ceiling.** 3 new files
  (`context-and-token-discipline.md`, `zero-trust-and-agent-safety.md`), 4 existing files extended
  (general-engineering, pr-requests, parallel-agent-guardrails, session-state-management).
- **`CLAUDE.md` (Tier 1), 213 words.** Router only: imports + an 8-entry skills catalog + a pointer to
  `skills/_standards/authoring-skills-and-agents.md`.
- **8 on-demand skills (Tier 3).** writing-specs, designing-agentic-architecture, integrating-mcp,
  securing-agentic-systems (+2 references), designing-agent-interop, designing-agent-commerce,
  evaluating-agents-and-skills (+1 reference), setting-up-a-new-project (+template asset).
- **4 hook scripts in `hooks/`, deliberately NOT installed.** `settings.json` never committed on this
  branch (verified). See `hooks/README.md` for per-repo opt-in wiring.

**The project opt-in register is live.** `rules/pr-requests.md` carries an always-on blocking trigger:
a new repo — or first substantial work in an existing repo with no `.claude/project-standards.md` —
runs the `setting-up-a-new-project` skill before any project code is written. Ten questions
(rigor tier, review gate, hooks, spec requirement, sandboxing, security:scan, MCP scoping, eval-in-CI,
model routing, project CLAUDE.md); answers are written into that repo, not just remembered here.

Mid-execution amendments (all recorded in the plan's Global Constraints):
- The original per-task word targets summed to ~4,300 against a 3,500 ceiling. **The ceiling won.**
  Trimming cut *words*, never *rationale* — a rationale-free imperative is the context-debt
  anti-pattern the source material names.
- `authoring-skills-and-agents.md` moved OUT of always-on into `skills/_standards/`; only a pointer
  stays always-on. It only matters when authoring a skill, so paying for it every turn was waste.
- Two rules the coverage map promised to always-on (structured docstrings, "show the exact query")
  moved into skills instead — no budget cost, topically at home.

**Two defects found by verification that would otherwise have shipped as false confidence:**
1. The `rtk` shell hook mangles `grep`/`head` output on this machine. An empty `grep` does NOT mean
   "no match." The first coverage audit was a **false pass** because of this; a control check against
   a known-present string exposed it. **Always control-check a negative grep result in this repo.**
2. The two scanner hooks originally read the target file *from disk*, but `PreToolUse` fires *before*
   the write lands — so they could never see the content being written. They passed their fixtures only
   because the fixtures exercised the CLI path, not the hook path. Now fixed: they parse
   `tool_input.content` / `new_string` from the stdin payload. 8/8 hook-path tests pass.
   **Lesson: test the code path that will actually run, not one that resembles it.**

Known honest gap: skill *trigger routing accuracy* is unmeasured. The verification confirmed the 24
trigger phrases are textually distinct and collision-free — that is not an accuracy measurement, and
measuring it needs a live eval harness this setup does not have.

See coding-memory/decisions.md for the always-on rules budget rationale.
