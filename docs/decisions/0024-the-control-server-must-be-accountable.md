# 0024 — The control server must be accountable: an audit log, a CSP, and a lifetime with a mechanism

**Status:** Accepted, 2026-08-09. **Extends [0022](0022-browser-control-channel-serves-its-own-page.md)**
— it does not replace or contradict it. 0022 decided *that* a browser may drive the session and *that*
the server serves its own page; it did not say what the resulting process owes an operator. Three
rounds of judging found the same shape of gap each time, so it is recorded here rather than left to
the feature card.

## Context

0022 created a process that (a) holds a bearer token for a Claude session with full tool permissions,
(b) is reachable over HTTP, and (c) can type into that session. Every control in the feature card
prevents an unauthorized command. None of them told you what happened after one was authorized.

Three specific gaps, each found by a judge round rather than by design:

1. **No record.** The worst failure this component can have — keystrokes reaching the wrong surface —
   is invisible after the fact unless it was written down as it happened.
2. **No frame defence.** The token stops forged requests. It does nothing about a *genuine* request
   the user was tricked into making: a hostile page framing `http://127.0.0.1:8422/` and positioning
   its own UI over the `clear` button. The click carries the real token because it is the real user.
3. **A lifetime with no mechanism.** "The server exits with the session" was written as a property.
   Nothing implemented it. A full-permission control channel whose parent has exited, with no one
   watching it, is the failure mode that sentence was meant to exclude.

## Decision

**The server is accountable for what it did, confined in what it can talk to, and bounded by a
mechanism rather than an intention.**

- **One audit line per request to stderr**, the stream the launching session already captures.
  Refusals log as loudly as successes. Two fields carry the weight: `reason` records the *internal*
  cause while the wire keeps its single collapsed `403`, and `sent` distinguishes "refused before
  invoking cmux" from "invoked and cannot say" — the timeout/non-zero-exit case that is precisely the
  window in which keystrokes reach the focused tab.
- **A Content-Security-Policy on the token-bearing response**, whose load-bearing clause is
  `frame-ancestors 'none'`.
- **A parent-death check on its own `5`-second poll** (`TASK_TRACKER_POLL_SECS`, minimum 1s, may not
  be disabled): record `os.getppid()` at startup, exit when it changes. It gets its own interval
  rather than riding the 30-minute idle timer, and the interval is a number rather than "a poll" — the
  first draft of this ADR said "on the idle timer" and left the tick unnamed, which would have made
  the real worst case half an hour of an orphaned full-permission control channel. That is the same
  unspecified-timeout mistake this feature had already written down and then made again one control
  later.
- **A launch contract, because two of the controls above are inert without it**: the server runs as a
  **non-detached child** of the session process with **`stderr` inherited**. Neither clause is
  incidental. Detached, `getppid()` never changes and the parent-death check silently never fires;
  with `stderr` redirected, the audit log is written and reaches nobody. Each failure leaves a green
  suite next to a control that does nothing — exactly what this ADR exists to refuse — so the contract
  is recorded here rather than only in the card, where an implementer reading the ADR alone would miss
  it.

## Alternatives rejected

- **Log to a file.** Rejected: the card's own §Out of scope bans persisting the token to a file, and a
  log file invites rotation, shipping, and a collector — three things this feature explicitly does not
  want. stderr has a bounded lifetime for free, because the process does.
- **Log the request for diagnosis.** Rejected, and inverted into a test. `log.debug(request.headers)`
  satisfied every other word of the card while writing the credential to the session scrollback, so
  criterion 10 now searches the captured stderr for the token's raw bytes and requires a refusal in
  the run — the error path being where dumping the request is most tempting.
- **A strict nonce-based CSP with no `'unsafe-eval'`.** Rejected as unreachable in v1, and this is
  written down rather than glossed: the design-system runtime compiles components through two
  `new Function` sites and `@babel/standalone` is on the page for that purpose. The honest claim is
  origin confinement and frame refusal, not script-injection immunity. Removing `'unsafe-eval'` means
  precompiling components at vendor time — a UI-architecture change, out of scope.
- **`prctl(PR_SET_PDEATHSIG)`.** Rejected: it does not exist on macOS, the binding platform. The
  portable `getppid()` poll costs at most one timer tick of overrun, versus a control channel that
  outlives its session indefinitely.
- **Making the `403` distinguishable so the operator can tell causes apart.** Rejected — that was the
  actual temptation, and it would hand an attacker an allowlist oracle. The operator's need is met
  server-side, on a stream the caller cannot read. The two requirements only conflict if you assume
  one channel.

## Consequences

The wire contract is unchanged; every addition here is observable only to whoever launched the
process. The audit log becomes a new surface that can leak the credential, which is why it arrives
together with the criterion-10 clause that asserts it does not — a control that creates a risk and
ships without the test for that risk is how the audit log itself got into this card unasserted.
