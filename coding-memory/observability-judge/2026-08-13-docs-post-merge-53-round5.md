# Observability judge verdict — verification-marker-gate, round 5 (architecting, advisory)

- repo: `tracking-feature-state`
- branch: `docs/post-merge-53`
- head_sha: `f95e94b42c2f914dde057f7f8eadefe8f7c46690`
- stage: `architecting` (advisory — no implementation exists; checklist 0/15, `phase: planning`, `branch: none`)
- ts: `2026-08-13T18:18:19Z`
- doc judged: `docs/features/verification-marker-gate.md` (revision 12, 1,652 lines, `wc -l` confirmed;
  waived past the 800-line ceiling by explicit user decision, §Standing decisions → O3)
- prior verdict: `2026-08-13-docs-post-merge-53-round4.md` (head `33d9ff9`, architecting, risk=low)

## What was changed

Revision 12 answers round 4's finding — that checklist task 14, v1's only pre-PR proof the gate is
armed, tested every block door but never exercised `TEST_EXEMPT`, so a regex that denied every
exemption (exactly what revisions 1–10 shipped) would still have reported the gate "correctly armed."
Two changes: (1) task 14 gains a positive-path case — pipe a payload with a *valid* `TEST_EXEMPT` and
expect exit 0 with an `EXEMPT` line appended; (2) a new subsection states the locale-pin mechanism as
part of the requirement, not an implementation detail, because the natural way to write "pinned to
`LC_ALL=C`" is a crash: `LC_ALL=C [[ ... ]]` fails with `[[: command not found` (assignment prefixes
require a command; `[[` is a bash reserved word, not one). The correct form is a subshell:
`( export LC_ALL=C; [[ ... ]] )`.

## Does it do what you wanted?

Yes, both fixes are real and I did not take the document's word for either — I reproduced both on the
pinned bash 3.2.57:

```
$ bash --version | head -1
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)

$ bash -c 'exempt="vendored upstream"; LC_ALL=C [[ "$exempt" =~ ^[[:print:]]{1,200}$ ]]; echo "exit=$?"'
bash: [[: command not found
exit=127

$ bash -c 'exempt="vendored upstream"; if ( export LC_ALL=C; [[ "$exempt" =~ ^[[:print:]]{1,200}$ ]] ); then echo MATCH; else echo NOMATCH; fi'
MATCH
```

The "WRONG" and "CORRECT" spellings in the doc are exactly that on the pinned interpreter, and the pin
does not leak past its subshell (confirmed: `LC_ALL` is unset again immediately after).

Point by point against your four questions:

**1. Is the task-14 positive path sufficient to catch a uniformly-refusing control?** Yes, for the
specific failure it targets. A regex/checker that denies every exemption fails this case outright
(exit 2, not 0; no `EXEMPT` line), so revisions 1–10's actual defect would now be caught. But the
assertion as written — "expect exit 0 with an `EXEMPT` line appended to the log" — is weaker than it
needs to be: it does not require the line's fields to be correct (field 3 = the actual reason, field 4
= `-`). A writer that appends a malformed or constant `EXEMPT` line on *every* decision, block or
allow, would also pass this reading. The full Gherkin scenario ("an explicit exemption is honoured and
logged... with `-` in field 4") is stronger and lives in task 6, but task 14 — the document's own
"only proof v1 has that the gate is armed" — doesn't inherit that strength. Cheap fix: have task 14
grep the appended line for the reason string and `-` in field 4, not just check a line appeared.

**2. Is a one-shot manual check the right instrument, given `--status` is deferred?** No, and the
document already says so plainly rather than hiding it — the §Scope accepted-cost callout states
inertness is "only PARTLY observable in v1" and that a gate going inert *later*, in a repo where
nothing has tripped it, "is still invisible until someone re-runs task 14 by hand." I have nothing to
add to that self-assessment; it's an honest, disclosed residual risk, tracked as follow-up 1, not a
new finding. It keeps the design's overall risk at medium rather than low.

**3. Is there a third layer — a requirement stated in one execution context that breaks in another?**
Yes, and I found and measured one the document does not yet address. §Decision logging pins the
*read* side hard: it explains at length why `[[:print:]]` guarantees no reason string can forge a tab
or extra field, and gives runnable `cut -f2` / `awk -F'\t'` commands as the maintenance interface. It
never pins the *write* side the same way — no code sample specifies how the tab-separated line is
produced, only that it is "tab-separated." That gap is exploitable by exactly the class of bug this
revision just fixed once already: the natural first idiom for appending a line in bash is `echo`, and
bash's builtin `echo` does **not** interpret `\t` by default. I measured it directly:

```
$ bash -c 'echo "2026-08-13T18:00:00Z\tEXEMPT\tvendored upstream\t-" > /tmp/log_echo.txt'
$ cut -f2 /tmp/log_echo.txt
2026-08-13T18:00:00Z\tEXEMPT\tvendored upstream\t-        # one field -- the whole line, literal backslash-t

$ bash -c "printf '%s\tEXEMPT\t%s\t-\n' '2026-08-13T18:00:00Z' 'vendored upstream' > /tmp/log_printf.txt"
$ cut -f2 /tmp/log_printf.txt
EXEMPT                                                     # correct
```

An `echo`-based writer produces a file with *no real tab byte in it at all* — every one of the
document's own documented maintenance commands (`cut -f2 | sort | uniq -c`, the day-bucketed `awk`)
would silently return one column forever, and nobody would notice because that column would still
print *something*. This is the same defect species as the regex bug this revision just closed: an
idiom that looks right (a "tab-separated" line in prose) and is wrong in the specific interpreter, only
observable by running it. Unlike the regex fix, there is no existing repo precedent to lean on — none
of `git-guard.sh`, `doc-guard.sh`, or `judge-guard.sh` append a tab-separated log today, so this
feature is breaking genuinely new ground and needs its own pinned, measured code sample the way the
locale-pin subsection now has one (`printf '%s\tEXEMPT\t%s\t-\n' ... `, never a bare `echo`).

**4. Anything else claiming a property no check enforces?** One smaller item: §The store states
"`<repo>/hooks/state/` is `0700` and each marker file is `0600`... whichever runs first sets the mode
for both" — i.e. the writer and the gate can each be the first to create the directory, and both call
orders must land on the same mode. I don't see a checklist item or Gherkin scenario asserting *both*
orderings independently (writer-creates-first vs. gate-creates-first); `write-test-marker.test.py` is
said to cover "file mode" but the doc doesn't say it covers both creation orders. Lower severity than
the log-write finding — it's a coverage-completeness gap, not a runtime-idiom trap — but worth a line
in task 4 or 6 while task 14 is being tightened anyway.

## What could go wrong / what I'm unsure about

- **The decision log's write mechanism is unpinned, in the same spot that just got bitten by an idiom
  mismatch once.** Measured above: a bare `echo` implementation silently produces a file with no real
  tab byte, defeating every maintenance command the spec itself documents, while nothing in the
  checklist forces anyone to notice.
- **Task 14's positive-path assertion checks that a line appeared, not that its fields are correct** —
  weaker than the Gherkin scenario it's meant to stand in for as the sole pre-PR arming proof.
- **The 0700/0600 dual-creator race isn't explicitly tested from both orderings**, though the design
  states both orderings must agree.
- Everything above is still a property of the plan. Checklist is 0/15; nothing has run.
- File continues to grow under the existing waiver (1,614 → 1,652 lines this revision, +38, same rate
  as the prior revision) — not a new violation, still worth a glance if this pattern continues.

## What I'd double-check before merging

- Add a pinned, measured code sample for the log-write line (task 3 or 6), spelled with `printf`, and
  explicitly reject `echo` the way the locale-pin subsection now explicitly rejects the bare-assignment
  spelling — the two idioms are the same species of bug and deserve the same treatment.
- Strengthen task 14's positive-path case to check the appended line's field 3 (reason) and field 4
  (`-`), not just that a line appeared.
- Add a Gherkin scenario or checklist line asserting the `0700`/`0600` mode holds under both creation
  orderings (writer-first and gate-first).
- Confirm `write-test-marker.test.py` (task 4/8) actually asserts file mode with `stat`/`os.stat`, not
  just that the file exists — not verified this round, flagging for the implementation stage.

## Dimension scorecard

| dimension | verdict | why |
|---|---|---|
| intent | pass | Both round-4 findings addressed directly and nothing else changed. |
| execution | concern | No code exists yet to execute; and the newly-touched decision-logging area contains an unpinned write-side mechanism I measured to be a live trap (bare `echo` silently drops the tab separator on this exact pinned bash) — the same defect class this revision just fixed once, one layer over. |
| trajectory | pass | Sound, evidence-driven: reproduced the WRONG idiom's crash and the CORRECT idiom's success on the pinned interpreter before trusting either. |
| regression | pass | No code exists; the prose change is scoped to task 14 and the locale-pin subsection. |
| context_budget | pass | `docs/features/`, read on demand; +38 lines this revision, same rate as last, under the already-granted waiver — not a new violation. |
| traceability | pass | Both fixes are stated with exact commands and exact bash version; I reproduced every one independently. |
| success_masking | concern | Two related gaps: task 14's positive-path check accepts a line appearing without checking its fields, and the log-write mechanism itself is unpinned and — measured — silently breaks the document's own read-side maintenance commands if written with a bare `echo`. Both are the same shape as the defect this revision closed: a control that reports armed while the exact property it's meant to certify is quietly wrong. |
| intent_drift | pass | Change is scoped to exactly the two things round 4 asked for; no drive-by edits found. |
| checkpoint | pass | Isolated, revertible commit (`f95e94b`) on the same clean revision chain. |
| audit_trail | pass | Dated, attributed, explicitly cites the round-4 finding it answers ("Noted revision 12 on the round-4 observability advisory"). |

## Concerns

- The decision log's write-side mechanism is never pinned with a code sample; measured directly that a
  bare `echo` (the most natural first implementation) silently produces a file with no real tab byte,
  defeating every one of the document's own documented `cut`/`awk` maintenance commands — the same
  defect species (idiom correct in one context, wrong in the pinned bash) this revision just fixed once
  in the locale-pin passage.
- Task 14's new positive-path case checks that an `EXEMPT` line appeared, not that its fields (reason
  in field 3, `-` in field 4) are correct — weaker than the Gherkin scenario it substitutes for as the
  sole pre-PR arming proof.
- The `0700`/`0600` dual-creator-order claim ("whichever runs first sets the mode for both") has no
  stated test covering both orderings.
- Task 14 remains a one-shot manual check with no automated regression protection once `--status` stays
  deferred — disclosed honestly by the document itself, not a new finding, but still the reason overall
  risk stays at medium rather than low.
- Still 0/15 implemented; every finding here is a property of the plan, verified against the pinned
  toolchain, not of running code.

risk=medium confidence=high
