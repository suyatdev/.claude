---
name: treko
description: Use when surveying which feature cards and branches are in flight in a repo — launching Treko to analyze and open the browser tracker UI in one step, or reading the merge order it proposes. Not for editing a card's phase or writing a handoff (see managing-session-memory).
---

# Treko

`treko/` answers one question: **what is in flight in this repo, and in what order can it
land?** It reads every `docs/features/*.md` card (phase, branch, checklist progress — the `.spec.md`
half of a split card is skipped by filename, so it never appears as a card of its own) and every
branch and worktree (ahead/behind, dirty), derives a merge order from that, and renders the result
as a browser page. The page can also drive the Claude session that launched it — three buttons,
`clear`, `handoff` and `reanalyze`.

Three pieces, in dependency order:

- **`analyze.py`** — pure read. Prints one `run` object as JSON on stdout and writes nothing.
- **`store.py`** — writes `tracker-data.js`, the file the page loads. Atomic, so a crashed run
  cannot truncate the store.
- **`server.py`** — serves the page on `127.0.0.1` and owns `POST /command`. This is the whole
  trust boundary, and the launch procedure below is part of it.

## Reading a survey without the UI

```sh
python3 treko/analyze.py <repo-root> --pretty
```

Read three parts of the output, in this order:

- **`questions[]` first.** The analyzer degrades rather than guessing: an unparseable card, a branch
  whose upstream could not be read, a dependency it cannot detect — each becomes a question naming
  the input, and the run still emits. A survey read without its questions looks more certain than it
  is, which is the one failure this tool is built to avoid.
- **`waves[]` is a proposal, not a fact.** Wave 1 means the card's branch exists, is not behind its
  base, and no other card names it as a prerequisite. Dependencies come **only** from an explicit
  `## Depends on` section in a card — never inferred from prose — so a prerequisite mentioned only
  in a paragraph produces a `questions[]` entry instead of a graph edge. `constraints[]` carries the
  reasoning behind an ordering; read it before acting on the order.
- **`branches[]`: `null` is not `0`.** `ahead`/`behind` are `null` when the upstream could not be
  read. Reading that as "in sync" is exactly the wrong answer to the question this tool exists to
  answer.

Runs are keyed by `id` (`--id`, `--name`); re-analysis replaces the run with that id and leaves the
others alone, so switching between surveys and refreshing one are the same operation.

## Launching the UI

One command, run as a **direct child of the Claude session** — its own foreground shell, or the
harness's background-run mode, which keeps the process in the session's tree and its stderr
captured. It resolves the repo via `git rev-parse --show-toplevel` in the cwd, analyzes on first
run only, and opens the browser itself:

```sh
python3 treko/server.py --open
```

`--repo <path>` is optional and overrides the resolved repo when the cwd isn't inside the one you
want surveyed. There is no longer a second step: no URL to copy, no browser tab to open by hand.

It prints its own address, the surface it bound, and its two timers, then one audit line per request:

```
server: http://127.0.0.1:8422/ surface=<uuid> idle=1800s poll=5s
<ISO-8601 UTC> accepted id=- surface=- sent=no status=200 reason=- path=- errno=-
```

Two things about that command are load-bearing, and **both fail silently** — they leave the control
present in the code and inert, where neither a code read nor the test suite notices. Auto-launch
does not retire either warning; it makes both stronger, because the command is now issued by code
rather than typed by a human, so there is no reader left to catch a violation before it runs:

- **Never detach it.** No `nohup`, no `setsid`, no `&` into a disowned shell, no launchd job. The
  server records `os.getppid()` at startup and exits within one poll (5s) of that value changing —
  which is how it dies with the session. Detached, it is reparented immediately and `getppid()` never
  changes again, so the check never fires and a control channel that can type into a
  full-permission session outlives the session that owned it.
- **Never redirect stderr.** No `2>/dev/null`, no `2>server.log`. Every request writes one audit line
  there naming the outcome, the resolved surface, and whether a keystroke was sent. That stream is
  the only record of where keystrokes went — the worst failure this component can have is invisible
  after the fact unless it was recorded as it happened. Redirecting it either discards the record or
  creates the log file the design deliberately does not have.

The port is `8422`, owned by `PORTS.md` (`TREKO_PORT` overrides). The auto-opened tab is
`http://127.0.0.1:8422/` — not the `.dc.html` file. Serving it is what lets the per-launch token be
injected into the page at request time and never written to disk, and what makes the page same-origin
with `/command`. Opening the vendored file over `file://` still renders the survey; it has no control
channel, so the command buttons become copy-to-clipboard chips instead.

`reanalyze` re-runs the analyzer server-side and rewrites the store; it sends no keystroke. It is the
only thing that writes `tracker-data.js`.

## Stopping it

`Ctrl-C` in the foreground. Otherwise it stops itself: a 30-minute idle timeout
(`TREKO_IDLE_SECS`, floor 60s, cannot be disabled) or within ~5s of the session ending. There
is no daemon and no launchd job — nothing to clean up afterwards.

## When it refuses to start

Every case below exits `2` before serving anything, with the reason on stderr. A bind failure is an
abort, never a fallback: a second server on a different port leaves the browser talking to the first
one, which holds a different token, and every button then returns the deliberately uninformative
`403`.

| Message | What actually happened |
|---|---|
| `CMUX_SURFACE_ID is unset or empty` | Launched outside cmux, or detached. The surface is inherited, never deduced — a send at a *deduced* surface once reached a different live Claude session at exit 0. |
| `read-screen --surface … exited N` | That surface is not a terminal (an agent-session surface has no control channel). |
| not inside a git repository (no `--repo`, `git rev-parse --show-toplevel` fails) | `--repo` was omitted and the cwd is not inside a repo. No survey of an arbitrary directory. |
| `port … is already in use -- the probe answered as a Treko page already serving there` | Another session's Treko still holds it. Stop that one; this server will not probe for a free port, and it does not open a browser at the existing one — that server belongs to a different session. |
| `port … is already in use -- the probe did not answer as a Treko page (something else holds this port)` | Something other than Treko holds the port. Same non-fallback rule: pick a different `TREKO_PORT` or free it. |
| `manifest uses extensions absent from EXTENSION_TYPES` | A servable file was added without its content type. The servable set is a closed list in `server.py`. |
| `Treko.dc.html has no <head>` | The token has nowhere to be injected, so the page would load unauthenticated. |

## Phase rules are not here

This skill surveys cards; it never changes one. The `phase` gate, the gate transition, and handoff
discipline belong to `managing-session-memory` — read it there rather than acting on anything this
page displays.

## Trigger Phrases

Positive — this skill should fire:

- "which of these branches can merge first?"
- "launch Treko for this repo"
- "the survey is stale, re-run the analyzer"

Negative — this skill should *not* fire:

- "move this card to implementation phase" → `managing-session-memory`
- "what port should this new dev server use?" → `allocating-local-ports`
- "write the PR description for this branch" → `preparing-pull-requests`
