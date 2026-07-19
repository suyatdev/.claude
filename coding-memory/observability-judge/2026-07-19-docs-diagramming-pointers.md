# Observability Verdict — docs/diagramming-pointers @ 84a60bf

- **Repo:** `.claude`
- **Branch:** `docs/diagramming-pointers` (base `origin/main` @ b6362ff)
- **HEAD:** 84a60bf7f1670a8c0661084b7aead7462ac0e8d7
- **Stage:** implementation
- **Judged:** 2026-07-19T22:48:11Z
- **Risk:** low — **Confidence:** high

---

## What was changed

Three skill files each gained one sentence telling the reader "when the thing you're
writing has a shape to it, draw it as a Mermaid diagram — see the diagramming skill."
That's it. Plus a bookkeeping update to `CODING_MEMORY.md`.

The analogy: the repo already owned a good camera (`diagramming-technical-docs`, merged
in PR #12), but the camera was sitting in a cupboard that only one person ever opened —
the ADR bullet. This change puts a note on three more doors: the door you walk through
when you write a branch log, the one for writing a spec, and the one for designing an
agent architecture. No new camera, no new rule about when photos are mandatory. Just
signposts at the places you'd actually want one.

Nothing executable changed. No hook, no script, no always-on rule file.

## Does it do what you wanted?

Yes. I verified the core claim rather than taking it on trust: at the base commit,
`diagramming-technical-docs` was referenced from exactly two places outside itself —
the ADR bullet at `managing-session-memory:14`, and the Skills Catalog line in
`CLAUDE.md`. Nothing named it on the `coding-memory/`, spec, or architecture authoring
paths. The gap the user asked about was real.

The triage reasoning is the strongest part of this change. Rejecting a hook is correct
for a precise reason: a script can see whether a ` ```mermaid ` block exists, but not
whether one was warranted — so it would either nag on every single-file bugfix log or
be silent. Rejecting a gate is also correct; I read `rules/gates.md` and every one of
the nine entries guards something irreversible or silently expensive. A missing diagram
can be added any time at zero cost. It genuinely fails that bar, and gates.md is a
scarce resource worth protecting.

I want to give credit for what this change did *not* do: it did not touch `CLAUDE.md`,
`rules/core-conduct.md`, or `rules/gates.md`. All three edited files are on-demand
skills. Zero always-on context was spent. That is exactly the discipline the repo's own
Context Discipline rule asks for, and it's the most common failure mode for changes of
this shape.

## What could go wrong / what I'm unsure about

**The caller asked directly: will "extend three skills with cross-references" actually
change behaviour, or just feel complete? My honest read — it will probably work for two
of the three paths, and the third is a genuine bet.**

For `writing-specs` and `designing-agentic-architecture`, the timing is right. Those
skills load precisely when you are writing a spec or designing an architecture, so the
pointer is in context at the exact moment the decision gets made. Low risk.

`managing-session-memory` is the weak link, and it's the one the user actually cared
about. The trigger chain is three hops with a judgment call in the middle: load the
skill, notice bullet 18, decide whether "structure" exists, then load the diagramming
skill. The realistic failure is timing — memory gets restored at session *start*, but
the branch log gets written at session *end*, possibly after a `/compact` that dropped
the skill text. The pointer can only fire if it's in context when you author. This is
mitigated — the skill's own description also triggers it at save time, which is the
authoring moment — but not eliminated.

**The deeper issue: this change is unfalsifiable by design.** Nothing can ever tell you
it failed. `validate-diagrams.sh` lints diagrams that are present and structurally
cannot detect a warranted-but-absent one — which is the same reason the hook was
correctly rejected. So there is no feedback loop. If these pointers never fire, no
signal will surface it; you'd have to notice by hand. I'm not calling that a defect,
because the alternative (a nagging hook) was rightly rejected. But it means "this
worked" is an assumption you'll be carrying indefinitely, not a fact you'll be told.

**On the specific question of whether the three wordings hold the conditional line —
they mostly do, but not the way the commit message says they do.** I scrutinised each:

- `managing-session-memory:18` — explicit conditional ("when ... describes something
  with structure"), four concrete triggers, *plus* a negative guard saying the index
  itself stays plain pointers. This one holds the line cleanly. Best of the three.
- `writing-specs:26` — carries **no conditional of its own.** It appends to a bullet
  that already unconditionally says "include visual aids"; the new clause only
  constrains the *format* of aids you were already told to include. This is fine, and
  arguably the cleanest possible edit — but it inherits an unconditional parent rather
  than carrying a condition.
- `designing-agentic-architecture:55` — imperative and unconditional: "Draw the graph,
  don't just describe it." The condition comes from *section placement* (it sits inside
  DAG Orchestration), not from wording. Defensible, since a DAG has node-and-edge
  structure by definition, so a diagram is essentially always warranted there.

Net effect is correct — no blanket "always diagram everything" mandate leaks out. But
the commit message's claim that "each pointer carries the when-it-has-structure
condition" is true of one of three. That's a documentation accuracy gap, not a defect
in the edits themselves.

One other small overstatement: the commit says the skill "was reachable only from the
ADR bullet." The always-on `CLAUDE.md:21` catalog entry also names it, and its
description already covers "technical docs, designs, plans, and ADRs." So the skill was
discoverable; it just wasn't named at the point of use. The improvement is real, the
framing is a shade stronger than the evidence.

## What I'd double-check before merging

1. **Nothing blocking.** This is a low-risk, cleanly revertible docs change.
2. Consider softening the two claims above in the commit body or the branch log, so the
   record matches the diff — future-you reading "each pointer carries the condition"
   will be mildly surprised by `designing-agentic-architecture:55`.
3. **Watch the next two or three `coding-memory/` branch logs.** That is the only
   available evidence that the memory-path pointer fires. If a structured one gets
   written with no diagram, the pointer isn't reaching the authoring moment and the
   answer is probably to move it into the save-time procedure section rather than
   leaving it in the index-description bullet.
4. By the repo's own `managing-session-memory` rule, a triage decision that explicitly
   rejects a hook and a gate looks like a class-(a) structural decision, which "also
   earns its own ADR under `docs/decisions/`." The reasoning currently lives in the
   commit body only. Open item 4 already contemplates adopting `docs/decisions/` here —
   this would be a natural first entry.
5. Confirmed and *not* a problem, so you don't need to re-check: no file anywhere cites
   these skills by line number, so the inserted lines shift nothing. `settings.json`
   stayed correctly unstaged. `CODING_MEMORY.md` is 164 lines, inside its 200 budget.
   Item 4 was correctly left half-open rather than closed wholesale.

---

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | pass | Closes the reachability gap the user asked about, plus the two paths item 4 named. |
| `execution` | concern | No executable surface and no possible verification; efficacy is unfalsifiable by design. Nothing to run, and the triage correctly explains why a checker can't exist — but "it works" is unproven. |
| `trajectory` | pass | Triage genuinely reasoned, not lucky. Hook and gate rejections argued from the right principles; I independently confirmed the gates.md never-miss bar. |
| `regression` | pass | Verified no line-number citations into the edited skills exist; no guidance removed; no executable surface touched. |
| `context_budget` | pass | On-demand skills only (66/69/111 lines). `CLAUDE.md`, `core-conduct.md`, `gates.md` all deliberately untouched. Zero always-on cost. |
| `traceability` | concern | Two documented claims overstate the diff: "reachable only from the ADR bullet" omits `CLAUDE.md:21`; "each pointer carries the condition" holds for one of three. |
| `success_masking` | concern | No feedback loop can ever reveal the pointers failing to fire; `validate-diagrams.sh` is structurally unable to detect a warranted-but-absent diagram. |
| `intent_drift` | pass | Tight scope. `settings.json` correctly excluded, item 4 correctly left partially open, no unauthorized deps. |
| `checkpoint` | pass | Single doc-only commit on a dedicated branch off merged `main`; `git revert 84a60bf` undoes it cleanly. |
| `audit_trail` | pass | Unusually strong commit body — defect, fix, design constraint, triage classification with rejected alternatives, and the memory item closed. Attributable. Mild note: arguably ADR-worthy. |

## Concerns

- Efficacy is unfalsifiable: no signal will ever reveal that the pointers failed to fire, and `validate-diagrams.sh` cannot detect a warranted-but-absent diagram (same reason the hook was correctly rejected).
- `managing-session-memory:18` is the weakest of the three trigger paths — memory is restored at session start but branch logs are authored at session end, so a `/compact` can drop the pointer before the authoring moment.
- Commit message claims "each pointer carries the when-it-has-structure condition"; only `managing-session-memory:18` does so in wording. `writing-specs:26` inherits an unconditional parent bullet; `designing-agentic-architecture:55` is imperative and scoped only by section placement.
- Commit message says the skill was "reachable only from the ADR bullet"; the always-on `CLAUDE.md:21` catalog entry also names it, covering "technical docs, designs, plans, and ADRs".
- A triage decision explicitly rejecting a hook and a gate is arguably a class-(a) structural decision that the repo's own rule says earns an ADR under `docs/decisions/`; the rationale currently lives only in the commit body.
- `~~strikethrough~~` in `CODING_MEMORY.md:141` is a first for this repo; the bold `**DONE <date>**` marker beside it does match house style (cf. items 2 and 3).
