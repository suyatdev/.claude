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
- **`store.py`** — writes `tracker-data.js` into the configured store directory (below), never
  into the repo. Atomic, so a crashed run cannot truncate the store.
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

It prints its own address, the surface it bound, its two timers and its resolved store directory,
then one audit line per request:

```
no legacy store to adopt
server: http://127.0.0.1:8422/ surface=<uuid> idle=1800s poll=5s store=/Users/you/.local/state/treko
<ISO-8601 UTC> accepted id=- surface=- sent=no status=200 reason=- path=- errno=-
```

The first line is the store migration reporting itself; the banner is always the last line before
the audit stream. See "Where the survey is stored".

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
with `/command`. **Opening the vendored file over `file://` no longer shows your survey.** The store
now lives outside the repo, so nothing answers the page's `tracker-data.js` request and the bundled
`tracker-data-fallback.js` loads `tracker-data.sample.js` instead — and the page does not say so: its
source dot stays green and reads "tracker-data.js loaded" over sample data. The only tell is the
timestamp beside it. That mode also has no control channel, so the command buttons become
copy-to-clipboard chips. Use the served URL, not the file.

`reanalyze` re-runs the analyzer server-side and rewrites the store; it sends no keystroke. It is the
only thing that writes `tracker-data.js`, and it writes it in the store directory below — never in
the repo being surveyed.

## Where the survey is stored

**`${XDG_STATE_HOME:-~/.local/state}/treko/tracker-data.js`**, outside every repository.
`TREKO_STORE_DIR` names the **directory** and overrides that default; the filename is fixed by the
page's `<script src>` and is not configurable.

This is the point of the location: surveying a repo must never write to one. `--repo` can point the
analyzer at any repo, and the store holds runs from several side by side, so a store inside any one
checkout would dirty it — and `tracker-data.js` is regenerated whole on every `reanalyze`, which is
a guaranteed merge conflict on any branch that runs one.

| Rule | Behaviour |
|---|---|
| Variable | `TREKO_STORE_DIR` — a directory, never a file path |
| Default | `$XDG_STATE_HOME/treko`, or `~/.local/state/treko` when that is unset |
| Expansion | a leading `~` only. A literal `$VAR` inside the value is **not** expanded |
| Relative values | resolved against the process cwd, then canonicalized (symlinks followed) |
| Created | if absent, with parents, at mode **`0o700`** |
| Existing directory | used as-is; its mode is **never** changed |

**`0o700` on creation, and only on creation.** One directory aggregates surveys of every repo you
analyse — branch names, card titles, filesystem paths, and what is in flight — so a directory this
tool creates is owner-only. A directory you already made is left at whatever mode you gave it;
silently tightening it is not the tool's call.

**The store is validated before anything is served.** A path that exists and is not a directory, or
one that cannot be created or written, aborts the launch with the reason on stderr — never a silent
fallback to somewhere else. The writability check is a real write into the directory, so the errno
it reports is the one the real write would get.

**One line on every launch says what happened to the old in-repo store**, because a migration that
silently did not run looks exactly like one that did:

| Line | Meaning |
|---|---|
| `copied N runs from <path>` | A pre-move `treko/tracker-data.js` was found and adopted. Runs through the store module, so it is parse-checked and atomic. Happens once. |
| `store already present, legacy file ignored` | The configured store exists, so the legacy file was left alone. A real store is never overwritten by a stale one. |
| `no legacy store to adopt` | The normal line on a clean checkout. |

A legacy file that does not parse **aborts the launch** rather than starting empty — that store may
hold snapshots the analyzer cannot regenerate, since it reports the present.

`treko/tracker-data.js` is untracked and gitignored. `tracker-data.sample.js` and
`tracker-data-fallback.js` stay tracked: they are vendored assets the page loads, not artifacts the
tool writes.

**Two view preferences live in the browser instead — `localStorage`, not the store.** Nothing
server-side reads or writes them, so they never travel with a survey: `reanalyze`, a new
`TREKO_STORE_DIR`, and a different repo all leave them alone.

| Key | Holds | Absent, or not usable |
|---|---|---|
| `taskTracker.theme` | `dark` or `light` — written only by the drawer's two Appearance cards | **`dark`.** Anything but the literal `light` falls back, so a hand-edited value cannot leave both cards unselected |
| `taskTracker.sideW` | sidebar width in px — written on drag mouseup, and by Layout → Reset | **`236`**, and any stored number is clamped to `190`–`440` at mount, not only while dragging |

**Both themes are contrast-guarded, and the two guards cover different halves of the page.**
`treko/test_theme.py`'s criterion 5 scores every element that paints **text** in its own `color`,
in **light** only. `treko/test_nontext_contrast.py` scores **non-text marks** — fills, border
sides, outset shadows, SVG fills and strokes — against a named 23-token allowlist, in **both**. A
palette edit that dulls one of those tokens fails the suite rather than shipping quietly. (The
exact per-theme mark counts live in that module's own constants and in the card, where an
assertion catches them going stale; repeating them here would be a copy nothing checks.)

**A green run there means those 23 tokens have not regressed. It does not mean the board is
accessible** — marks that appear only after an interaction (the settings drawer and its scrim,
the agent panel, hover and focus states) are outside both populations, and three tokens are
recorded as known defects rather than fixed. `docs/decisions/0037-*` has the reasoning;
`docs/features/treko-non-text-contrast.md` has the table.

Both are keyed to the served origin, port included, so a changed `TREKO_PORT` — or the `file://`
mode above — starts again from those defaults.

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
| `<path> exists and is not a directory` | `TREKO_STORE_DIR` points at a file. It names a directory; the filename is fixed. |
| `<path> is not writable (errno N: …)` | The store directory exists but cannot be written. The errno comes from a real write, not a guess. |
| `cannot create <path> (errno N: …)` | The store directory is absent and could not be created — a missing parent you lack permission on, or a read-only filesystem. |
| `<path> is not a valid legacy store: …` | A pre-move `treko/tracker-data.js` exists but does not parse. Deliberately fatal: it may hold runs the analyzer cannot regenerate. Move it aside to launch without it. |

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
