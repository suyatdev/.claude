---
name: verifying-durable-claims
description: Use before writing a factual claim into a durable artifact — commit message, ADR, spec, PR body, memory file, handoff. Verify what a citation DID, not that it exists; scope quantifiers to what you measured. Not for whether code works or tests pass (see superpowers:verification-before-completion).
---

# Verifying Durable Claims

`rules/core-conduct.md` states the invariant: verification precedes the write-down. This
skill is the procedure behind it — the specific checks that turn "I believe this" into "I
ran this." It exists because knowing the rule has repeatedly not been enough: the claims
that get written unverified are rarely the ones that *feel* risky, they are the incidental
supporting details nobody thought to run a command against.

Reach for this at the moment of writing, not after. Once a claim is pushed, correcting it
costs a commit; leaving it costs every later decision that trusts it.

## The distinction that catches the most: liveness vs. behaviour

A citation can be perfectly valid and still be wrong about what it claims.

```
git rev-parse <sha>            # proves the object EXISTS      — liveness
git show <sha> -- <path>       # proves it DID the thing        — behaviour
```

A self-audit built on the first is not a verification. In one recorded case a commit
message credited a sha with backfilling a field; the sha resolved fine, and the diff showed
it had *created* the row with that field still null — a different commit did the backfill.
"Every citation resolves" was true and useless.

**Check the referent's behaviour, not its existence.** The same split appears everywhere:
a file exists vs. contains the quoted line; a PR exists vs. was merged; a hook is present
vs. is registered and runs; a test exists vs. would fail if the code were wrong.

## Match the claim to the command that settles it

| The claim asserts | Run |
|---|---|
| a commit did / changed something | `git show <sha> -- <path>`, `git show --stat <sha>` |
| a commit is the first/last/next to do X | `git log -S'<string>' -- <path>`, `git log <a>..<b>` |
| a PR merged, or was reviewed | `gh pr view <n> --json state,mergedAt,reviews` |
| CI passed or failed at a sha | `gh run list --json headSha,conclusion` then `gh run view <id>` |
| a file:line says something | read that range — never cite a line number you have not opened |
| a count, or any quantifier | count the **whole** set programmatically, not the part you read |
| a hook or rule is enforced | find its registration, not just its file |

## Quantifiers are the most-missed class

"All", "every", "none", "never", "only", and any bare number are claims about a whole
population. They are almost never verified against the whole population, because the part
you were already looking at feels representative.

Two failures of this shape, both from one branch: "the exclusion fires nowhere in this
ledger" (it fired on every row that branch had labelled) and "all four `clean` rows" (the
ledger held nine; four was merely the subset that branch touched). Both were one `python3`
count away.

**Scope the sentence to what you measured, or measure wider.** "All four rows this branch
labelled `clean`" is both true and more useful than a false ledger-wide claim.

## A subagent's finding is evidence to check, not a citation to copy

This includes a judge, a reviewer, and any report that reads authoritative. Their findings
are usually right — that is exactly what makes copying them feel safe. Two specific traps:

- **Copying the claim instead of running its check.** If the report says a commit orphaned
  a CSS class, run the grep at that sha before writing it down. A report is a lead.
- **Dropping the hedge in transit.** A source that said "row 6's follow-ups *include* X"
  becomes "the follow-up is X" in the retelling, and the qualifier that made it true is
  gone. When compressing someone else's finding, the hedge is load-bearing.

## When you cannot verify, write the gap

An explicit gap is cheap and honest; a false certainty is neither. Write what you checked
and what you did not — "not re-run this round; no source byte changed since <sha>" beats
silence, and beats implying a check you skipped.

Two related traps worth naming:

- **Absence of a record is not absence of evidence.** "No memory entry attests this" is a
  narrow, checkable statement. "There is no evidence" is a much larger claim, and querying
  the live source (`gh pr view`, the API, the file) often refutes it immediately.
- **A number true when written goes stale silently.** Stamp any count of a shared or
  growing dataset with when it was measured, and say re-measure rather than carry forward.

## Before you write, ask

1. Which sentence here would change someone's decision if it were wrong?
2. For each: what command proves it? Have I run *that* command, this session?
3. Is any of it a quantifier or a count over a set I only partially read?
4. Did any of it arrive from a subagent, a report, or an earlier draft of my own?

If a sentence survives all four, write it. If it cannot, either run the command or write
the gap. Do not write the confident version and plan to check later — later is after it is
durable.

<!-- Triggers (recorded; routing accuracy NOT measured — no eval harness in this repo):
positive: "record this decision in an ADR", "write the commit message for this fix",
          "update the memory file with what we learned"
negative: "do the tests pass?" (superpowers:verification-before-completion),
          "review this PR for bugs" (/code-review),
          "write a spec for this feature" (writing-specs)
-->
