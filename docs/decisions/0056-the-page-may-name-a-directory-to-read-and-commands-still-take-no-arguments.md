# 0056 — The page may name a directory for the server to read, `/command` still takes no arguments, and git runs in scanned repositories with its program routes switched off

- **Status:** Proposed (2026-11-05). Becomes Accepted when task 1d's judge round passes
  (decision D32 of the card); no browser-reachable Ledger work starts before then (D31).
- **Context:** `treko/server.py`, `treko/ledger_jobs.py` (new), `treko/Ledger.dc.html` (new),
  `treko/Treko.dc.html`. Full design, scenarios, acceptance criteria and measurements:
  `docs/features/treko-ledger.md` (the card) and `docs/features/treko-ledger.spec.md` (the spec;
  its §2 is the gate this record discharges, its §3 the wire contract).
- **Amends** two records by name:
  - **ADR 0034** (the store leaves the repo): its statement that "the browser cannot name" a path
    and that no verb "takes a filesystem path" (its section "The trust boundary that actually moved,
    and the one that did not") is reversed **for reads only**.
  - **ADR 0024** (the control server must be accountable): its first bullet, "One audit line per
    request", gains one exception, an accepted status poll.
  ADR 0022 (the server serves its own page) and ADR 0055 (a missing control channel degrades the
  board) are not reopened. Also amended, in the old feature spec rather than in an ADR: the rules
  listed under "Where the old spec changes" below.
- **Note:** ADR number **0056** was confirmed free before writing: `git fetch -q origin && git log
  --all --name-only --pretty=format: -- 'docs/decisions/0056*'` printed nothing across every ref,
  with `origin/main` at `fc08216`, whose highest number is 0055. Recorded as the command, not a
  ref tally, as ADR 0055 does.
- **Line numbers.** Citations into `docs/features/tracking-feature-state.spec.md` are the
  numbers *before* this record's own six pointers were added to that file (they now sit at lines 412,
  549, 710, 1075, 1110 and 1118), so they match the file at `e75b3df`. Citations into
  `treko/server.py`, `treko/analyze.py` and `treko/test_server.py` were re-opened on this branch,
  also at `e75b3df`, when this was written.

## Context

Treko's control server may be told to do exactly one of three things, and never anything with an
argument. The old feature spec says so three times: "Commands take no arguments, in v1 or after"
(`tracking-feature-state.spec.md:408-411`), an allowlist of exactly three ids (`:691-703`), and
"Command arguments of any kind" out of scope for ever (`:1101`). `treko/server.py:592-598` enforces
it: one key, `id`, a string; anything else is `400`. The old spec calls changing that "a spec change
and a new judge round, never an implementation decision" (`:410-411`).

The Ledger needs arguments. It lets the user type a directory, optionally narrow it to a repo, a
branch or a worktree, and hands that to a queue that scans the directory and analyses what it
finds. It also sends ids: remove, retry, delete, re-analyze a run. None of that fits a bare command
name. So the first task of the Ledger card is this record, and nothing a browser can reach is built
until a judge has passed it (decisions D10, D31).

The change is direction-pivoting because it **lets a web page choose a directory the server then
reads and runs git in**. That is the whole risk, and most of this record is about the three things
that keep it small: the arguments go to one new route that never reaches the terminal session; the
server reads the named directory and writes nowhere but its own store; and every git command that
touches a scanned repository runs with the ways a repository can make git run a program switched
off, so a hostile `.git/config` cannot turn a "scan this folder" request into code execution.

## Decision

### 1. The amendment, and how narrow it is

- **`POST /command` keeps its rule unchanged: no arguments, ever.** Its allowlist **shrinks** from
  `clear`, `handoff`, `reanalyze` to `clear` and `handoff`. `reanalyze` leaves it. The board's
  Re-analyze becomes "re-queue the run on screen", which needs a run id, and an argument on the
  route that types into the session is exactly what the old rule forbids. Keeping the old
  `reanalyze` beside the queue would leave a second writer of the store racing the job runner,
  still minting the folder-name ids that run ids replace. `{"id": "reanalyze"}` is now `403`,
  audit reason `unknown_id` (`server.py:550-552` is today's refusal of an id outside the set).
- **Arguments are allowed only on the new `POST /ledger`, which never reaches the session.** No
  `/ledger` operation invokes `cmux`; acceptance criterion A5 checks that the fake cmux log stays
  empty across every `/ledger` and `/ledger/status` test.
- **ADR 0034's "the browser cannot name a path" is reversed for reads only.** The browser now names
  a directory that the server scans and runs read-only git in. It never names a directory the
  server writes or serves. The store directory still comes only from the server's own process
  environment (`TREKO_STORE_DIR`), and the Ledger shows it read-only. ADR 0034 also warned that a
  path field in the deferred Configuration drawer ("accepting a directory from the browser means
  the server creates and writes at an address the page supplied") needs its own design and judge
  round. This record does not discharge that warning, because nothing here lets the browser name a
  directory the server writes or serves.
- **ADR 0024's "one audit line per request" gains one exception**: an accepted `GET /ledger/status`
  poll writes none (section 6). Every other request, including every refused poll, is audited as today.
- **`/command` gets the protections `/ledger` is built with** (section 7): a catch-all that answers
  `500 internal_error`, `403 bad_token` for a token header that is not ASCII, `400 malformed` for a
  body nested too deeply to parse. Its arguments rule is unchanged.

### 2. Routes

| Path | GET | POST | OPTIONS | Any other method |
|---|---|---|---|---|
| `/` | the board page, as today (the board keeps its address) | 405 | 405 | 405 |
| `/ledger` | the Ledger page | the five ops | 204 | 405 |
| `/ledger/status` | status JSON | 405 | 204 | 405 |
| `/command` | 405 | `clear`, `handoff` | 204 | 405 |
| a `STATIC_MANIFEST` row | the asset, as today | 405 | 405 | 405 |
| anything else | 404 | 404 | 405 | 405 |

Routing reads only the path, so a query string never changes the route. A `204` carries no
`Access-Control-Allow-*` header, as `/command`'s does today. `STATIC_MANIFEST` gains one row,
`board-commands.js`, the board's command code split out of `Treko.dc.html` into a file the page
loads (the spec's split 3, which keeps the board under the repo's 800-line cap).

`GET /ledger` is served exactly as the board is: `Host` must be `127.0.0.1:<port>`, one
substitution injects the `tracker-token` and `tracker-channel` metas, with `Cache-Control:
no-store`, the existing CSP unchanged, and `nosniff`. Both pages get both metas through one
function. The Ledger shares the path its own ops post to, the way a form posts to its own page; a
`GET` never reaches an op, and a `POST` still needs the token and a JSON body, so sharing the path
widens nothing. Launching with `--open` now opens `<origin>/ledger`; `origin` itself is unchanged
because the `Origin` check compares against it.

### 3. `GET /ledger/status`

Checks, in order: `Host`; `Origin` and `Sec-Fetch-Site`, each only when present; the token, refused
at once when not all ASCII and otherwise compared with `hmac.compare_digest`. Every failure is the
collapsed `403 forbidden`. Success is `200`, `application/json`, `no-store`, `nosniff`, with:

- `storeDir`: the server's store directory, home-collapsed (shown read-only);
- `queue`: items with `item`, `state`, `label`, `queuedAt`, `run`; plus `stage` (`done`, `total`,
  `label`) on the running item only (`total` is `null` until the scan has finished), `error` on a
  failed item only, and `detail` on a failed or interrupted one;
- `runs`: the visible runs' summary rows, and `runsError`, which is `"store_unreadable"` (with
  `runs` null) when the store cannot be parsed. The queue is still returned then, so a running job
  stays visible.

### 4. `POST /ledger`: the ops, the argument shapes, the validation

Checks run in this order. Each failure answers once and writes one audit line.

1. `Host` (`403 host_mismatch`), then `Origin` and `Sec-Fetch-Site` (`403 origin_mismatch`), then the
   token (`403 bad_token`).
2. `Content-Type` is `application/json` (`415`).
3. The body: `Transfer-Encoding` refused, `Content-Length` required, at most
   `LEDGER_MAX_BODY_BYTES = 4096` bytes read (`413`). 4096, not `/command`'s 1024
   (`server.py:64`): a macOS path alone can be 1024 bytes, and JSON quoting can double it.
4. The body is a JSON object with a string `op` (`400 malformed`); a body nested too deeply to parse
   is `400 malformed` too.
5. `op` is one of the five below (`403 forbidden`, reason `unknown_op`). As with `/command`, an
   unknown op is indistinguishable from a bad token.
6. The key set is exactly the op's own keys, every value a string (`400 malformed`). Unknown keys are
   refused, never ignored.
7. The field rules below (`422`), starting with the UTF-8 rule.
8. The op itself. `analyze`, `reanalyze` and `retry` first read the startup git check (section 9,
   floor): when git is too old the answer is `503 git_too_old`, before any scan or state change.

| `op` | Keys: required, optional | Effect |
|---|---|---|
| `analyze` | `directory`; `repo`, `branch`, `worktree` | runs the scan at once; if it finds work, queues the request |
| `reanalyze` | `run` | queues the request recorded for that run |
| `remove` | `item` | removes a waiting, failed or interrupted item |
| `retry` | `item` | puts a failed or interrupted item back to waiting, unless another item for the same run is waiting or running |
| `delete` | `run` | adds the run to the hide list; nothing on disk is erased |

| Field | Rule, checked before anything touches the filesystem or git |
|---|---|
| `directory` | at most 1024 UTF-8 bytes. No U+0000-U+001F or U+007F (`422 invalid_input`). After `os.path.expanduser` (a leading `~` only, the rule `store_location` uses) it is absolute (`422 relative_path`). Its `os.path.realpath` is an existing directory (`422 no_such_directory`). That real path is the canonical directory. Nothing is created |
| `repo` | `""` means absent. At most 255 bytes, no control characters, no `/` (`422 invalid_input`). Only ever compared with folder names |
| `branch` | `""` means absent. At most 255 bytes, no control characters (`422 invalid_input`). Only ever compared with card `branch:` values |
| `worktree` | `""` means absent. At most 1024 bytes, no control characters (`422 invalid_input`). Only ever compared with worktree paths and folder names |
| `item` | matches `^[0-9a-f]{16}$` (`400 malformed`: the page only ever sends ids the server gave it) |
| `run` | 1-255 bytes, no control characters (`400 malformed`), and equal to the `id` of a run in the store (`404 no_such_run`) |

**Every field must be encodable as UTF-8.** Before any rule in the table each of the six string
fields is encoded; a value that cannot be, because it holds a lone surrogate such as
`"/tmp/\ud800x"`, is refused with that field's own code (`422 invalid_input` for `directory`,
`repo`, `branch`, `worktree`; `400 malformed` for `run` and `item`). The byte-length rules run only
on a value that passed it. Why: a JSON `\ud800` escape is plain ASCII on the wire, so the strict
UTF-8 decode of the body accepts it, `json.loads` returns a `str` holding the lone surrogate, and
`.encode("utf-8")` raises `UnicodeEncodeError`. Measured on `/usr/bin/python3` 3.9.6: before this
rule that error escaped with no code and no audit line, and the client saw the connection closed.

**No value reaches a shell.** `repo`, `branch`, `worktree`, `item` and `run` never reach git at
all. The canonical directory reaches git only as `git -C <absolute path>`, which cannot begin with
`-`. The scan subprocess receives the request as one JSON object on stdin, never as argv, so no
value can be read as a flag.

Success bodies: `analyze` and `reanalyze` return `{"ok": true, "op": "<op>", "item": "<id>",
"started": <bool>}`, where `started` is true when no other item was running or waiting; `remove`,
`retry` and `delete` return `{"ok": true, "op": "<op>"}`. `reanalyze` goes through exactly what
`analyze` does at submit: the field rules, so a run whose directory has been deleted gets
`422 no_such_directory`, then the scan. A run narrowed to a worktree that has since been removed
gets `422 no_such_worktree`. Either way nothing is queued.

### 5. Every failure, with its audit reason

The body is always `{"ok": false, "error": "<error>"}` and echoes nothing from the request. Every
row has a reason and every reason has a row (criterion A2 checks both directions).

| Status | `error` | Cause | Audit `reason` |
|---|---|---|---|
| 400 | `malformed` | steps 3, 4, 6 of section 4 (a body nested too deeply to parse among them); a bad `item` or `run` shape | `malformed` |
| 403 | `forbidden` | host, origin, token (one not all ASCII included), unknown op | `host_mismatch`, `origin_mismatch`, `bad_token`, `unknown_op` |
| 404 | `no_such_item` | `remove`/`retry`: no item with that id | `no_such_item` |
| 404 | `no_such_run` | `delete`/`reanalyze`: no run with that id | `no_such_run` |
| 405 | `method_not_allowed` | section 2 | `method_not_allowed` |
| 409 | `item_running` | `remove` of the running item | `item_running` |
| 409 | `not_retryable` | `retry` of a waiting or running item | `not_retryable` |
| 409 | `already_queued` | `analyze`/`reanalyze`: an item with the same run id is already waiting or running; `retry`: another item with the retried item's run id is waiting or running. Checked under the ledger lock | `already_queued` |
| 409 | `queue_full` | the queue already holds `MAX_QUEUE_ITEMS = 20` items, any state | `queue_full` |
| 409 | `last_run` | `delete` of the only visible run | `last_run` |
| 413 | `too_large` | body over 4096 bytes | `too_large` |
| 415 | `unsupported_media_type` | not `application/json` | `unsupported_media_type` |
| 422 | `invalid_input` | a field length or character rule | `invalid_input` |
| 422 | `relative_path` | `directory` not absolute after expansion | `relative_path` |
| 422 | `no_such_directory` | not an existing directory; for `reanalyze`, the run's recorded directory no longer exists | `no_such_directory` |
| 422 | `no_repository` | the scan found no repository | `no_repository` |
| 422 | `no_matching_repository` | repositories found, none with that `repo` folder name | `no_matching_repository` |
| 422 | `no_such_worktree` | `worktree` names no worktree of any repository the scan found; for `reanalyze`, the run's narrowing worktree has been removed | `no_such_worktree` |
| 422 | `nothing_matched` | no card matches `branch`/`worktree` | `nothing_matched` |
| 500 | `scan_timeout` | the scan passed `TREKO_SCAN_SECS` | `scan_timeout` |
| 500 | `scan_failed` | the scan exited non-zero or printed something that is not its contract | `scan_failed` |
| 500 | `launch_failed` | the submit-time scan subprocess could not be started at all (an `OSError` from the spawn). Nothing is queued | `launch_failed` |
| 500 | `ledger_write_failed` | the request's own write of `ledger.json` failed, so nothing changed | `ledger_write_failed` |
| 500 | `store_unreadable` | `delete`/`reanalyze`: the store does not parse | `store_unreadable` |
| 500 | `internal_error` | any unexpected exception while a request is handled, caught by the request catch-all (section 7) | `internal_error` |
| 503 | `git_too_old` | `analyze`, `reanalyze`, `retry`: the startup check found git older than 2.45, or read no version (section 9). Nothing is queued and no scan runs | `git_too_old` |

`GET /` and `GET /ledger` keep today's `500 asset_unreadable` for an unreadable page. `/command`
changes in two ways beyond its shrunken allowlist, both in section 7.

Five codes are carried by a **failed queue item** (the `error` field, written to `ledger.json` and
shown from it) and answer no request, apart from `launch_failed` and `internal_error`, which are
also request answers above: `analysis_failed`, `store_write_failed`, `merge_failed`,
`launch_failed` and `internal_error`. Each carries a `detail.stage`. `ledger_write_failed` and the
scan outcomes (`no_such_directory` through `scan_failed`) are likewise both a request answer at
submit and an item's `error` at job time. Their causes and stages are in the spec's section 3.5.

### 6. Audit lines, and the exception to ADR 0024's rule

- The audit format (`server.py:134-147`) is unchanged: one line per request. `id=` carries the op
  for `/ledger` once step 5 has accepted it as one of the five, `status` for the poll, and `-`
  everywhere else, **an unknown op included**. An unknown op is client text and `audit` formats
  every field with `%s` and no escaping (`server.py:143-144`), so writing it would let a token holder
  put a newline into the log: a stub call with a newline-bearing value wrote three lines, and
  `server_harness.parse_audit` read the middle one as a normal accepted entry (measured by the
  round-5 compliance judge).
- **Field values are never logged.** The directory is request content, and the old spec bans
  logging request bodies "in whole or in part" (`tracking-feature-state.spec.md:547-551`).
- **An accepted status poll writes no audit line.** At the page's 2-second poll, auditing every
  accepted poll would add up to 1,800 lines an hour to the only record of what the server did and
  bury the state-changing ones. Every other request, **including every refused poll**, is audited
  exactly as today: "a run of refusals is the only evidence a hostile page ever probed the
  endpoint" (`tracking-feature-state.spec.md:503-504`). This is the one exception to ADR 0024's
  one-line-per-request rule.
- Job events go to stderr as `server: job <item> <event>`, naming item and run ids, fixed words
  (codes, stages, exception classes, errno names) and, in a reap-timeout line only, a process id;
  never request content. For `merge_failed` and `internal_error` a line names the exception's
  **class**, never its message, which can carry a path or a field value.

### 7. `/command`'s changes, and requests that crash

Today an exception that escapes a route goes to `socketserver`'s default handling: a traceback on
stderr, the connection closed, no response and no audit line. Two inputs do this on the real server
under `/usr/bin/python3` 3.9.6, through `/command`, whose code `/ledger` reuses (measured by the
round-5 compliance judge): a token header holding byte `0xE9` (no valid token needed) and a body of
1024 `[` (valid token). Both exist today, so this card inherits them rather than causing them.

- **A token that is not all ASCII** is refused `403 forbidden`, reason `bad_token`, without calling
  `hmac.compare_digest`, which raises `TypeError` on non-ASCII strings. The server's own token comes
  from `secrets.token_urlsafe(32)` and is ASCII.
- **A body nested too deeply to parse**: `json.loads` raises `RecursionError` (a `RuntimeError`, not a
  `ValueError`, so the catch at `server.py:589` does not see it). The reader catches it beside the
  other two and answers `400 malformed`, with one audit line. The rule names the exception, not a
  depth, because the depth depends on the call stack.
- **One token check and one body reader**, shared by `/command` and `/ledger`; the reader takes the
  cap as a parameter. Each route keeps its own shape check: exactly `id` for `/command`
  (`server.py:595-598`), section 4 steps 4-6 for `/ledger`.
- **One request catch-all**, around the dispatch of every method in `ControlHandler` (not around
  `handle_one_request`, which also reads the next request line of a kept-alive connection and would
  turn a client that closes between requests into a failed request). It catches `Exception`;
  `KeyboardInterrupt` and `SystemExit` pass through. It answers `500` with
  `{"ok": false, "error": "internal_error"}` when no response has started (dropping a status line
  that `send_response` has only buffered, so one reply never holds two status lines); writes exactly
  one audit line `failed id=- surface=- sent=<sent> status=500 reason=internal_error path=-
  errno=<name>`; writes one stderr line `server: request internal_error <ExceptionClass>`; and
  closes the connection. It echoes no request content anywhere. It replaces no named refusal.
  A request target such as `http://[`, whose path decode (`server.py:445`) raises before any route
  runs, stays with the catch-all's generic `500` and has no code of its own.
- **`sent=unknown` on `/command`; `no` on every other route.** `/command` is the one route that
  reaches `cmux send`, and the catch-all cannot tell whether the exception came before the send or
  after it: every route answers first and audits last, so a client that hangs up while the answer is
  written raises after the keystrokes have gone (measured by the round-6 compliance judge with a
  stub `send_keys`). **This widens the old spec's `unknown`**, defined as "`cmux send` was invoked
  and did not exit 0" (`tracking-feature-state.spec.md:541-544`): the catch-all is a third case beside
  a timeout kill and a non-zero exit, and it fits the reason that definition gives, a case "where
  the server genuinely cannot say whether anything was typed". `no` keeps its meaning, a refusal
  before invocation.

### 8. Status polling never resets the idle timer

`ControlServer.process_request` resets the idle timer once per accepted **connection**
(`server.py:650-652`); the handler speaks HTTP/1.1 (`server.py:360`), so further requests on a
kept-alive connection do not reset it again (read, not run). A polling tab that opens connections as
it polls would keep the server alive for ever. The reset moves to the point where the request line
has been parsed and is skipped only when the path is `/ledger/status`, whatever the outcome. A
request whose line cannot be parsed still resets it, as today.

### 9. Git in scanned repositories: the protective settings, the probes, the floor

A scanned repository is not trusted. Its own `.git/config` can name a program for git to run, and
the analyzer runs `git status --porcelain` in each worktree (`analyze.py:437`). Measured 2026-11-03
on git 2.50.1: with a repository's `core.fsmonitor` set to a script that writes a marker file, plain
`git status --porcelain` ran the script, and `git -c core.fsmonitor=false status --porcelain` did
not. `git help config` documents that `GIT_CONFIG_COUNT` pairs "override values in configuration
files", and the analyzer's `_git` (`analyze.py:92-103`) passes no `env=`, so its git children inherit
whatever the scan and analyzer processes are given, with no change to `analyze.py`.

**Every scan and analyzer subprocess gets the variables in this table, unconditionally.** "The
protective settings" means exactly these rows.

| Variable | Value | Stops |
|---|---|---|
| `GIT_CONFIG_COUNT` | `3` | |
| `GIT_CONFIG_KEY_0`, `GIT_CONFIG_VALUE_0` | `core.fsmonitor`, `false` | a repo-named fsmonitor program |
| `GIT_CONFIG_KEY_1`, `GIT_CONFIG_VALUE_1` | `core.hooksPath`, `/dev/null` | a repo-named hook |
| `GIT_CONFIG_KEY_2`, `GIT_CONFIG_VALUE_2` | `log.showSignature`, `false` | a repo-named `gpg.program`, which `git log` runs to check a signed commit when the repo sets `log.showSignature=true` (probes 17-20) |
| `GIT_OPTIONAL_LOCKS` | `0` | `git status`'s optional index write, and the `post-index-change` hook it fires |
| `GIT_NO_LAZY_FETCH` | `1` | a lazy fetch from a promisor remote, which runs the repo-named `remote.<name>.uploadpack` and downloads objects into the scanned repo (probes 21-26) |

**The builder.** One function in `ledger_jobs.py` builds the child environment, and every scan and
analyzer launch goes through it, the submit-time scan included. Its base is the server's own
environment, read once in `main()` and passed in as a plain dict. The builder copies it, **removes**
`GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT` and every `GIT_CONFIG_KEY_<n>` and
`GIT_CONFIG_VALUE_<n>`, whatever `<n>`, then sets the table's rows. Everything else passes through,
because git needs `PATH` and `HOME`. The only way to run without the protection is to pass a
different builder as a parameter in code, which is what criterion C8's falsifier does in-process.
No request field, command-line flag or repository config key can switch it off. Dropping
`GIT_CONFIG_PARAMETERS` is what the protection depends on (probes 3 and 4); dropping the count
family is hygiene, kept because it makes the child's `GIT_CONFIG_*` set exactly the builder's own
(probes 7, 15, 16). **Not measured:** other git environment variables that change what git runs or
where it looks, such as `GIT_EXEC_PATH` or `GIT_DIR`. They pass through from the server's launch
environment, which only the person launching the server sets.

**Probes.** All on git 2.50.1, in scratch repositories; each group has a baseline that had to
fire, and did. The spec names the scripts: `probe_git.sh` (1-11), `probe_analyzer_writes.sh`
(12-14), `probe_count_overwrite.sh` (15-16), and `probe_r3.sh` and `probe_partial_clone.sh` for the
round-3 probes. **These rows are the spec's recorded measurements; they were not re-run for this
record.** "Round-2 settings" is the table above without the
`log.showSignature` row and `GIT_NO_LAZY_FETCH`, with `GIT_CONFIG_COUNT=2`; "all settings" is the
table above.

| Probe | Setup | Result |
|---|---|---|
| 1 | repo config names an fsmonitor script; plain `git status --porcelain` (baseline) | script ran |
| 2 | plus the fsmonitor pair | did not run |
| 3 | plus an inherited `GIT_CONFIG_PARAMETERS` naming the script | **ran** |
| 4 | as probe 3, with `GIT_CONFIG_PARAMETERS` removed | did not run |
| 5 | script named only in a `GIT_CONFIG_GLOBAL` file (baseline) | script ran |
| 6 | that file plus the fsmonitor pair | did not run |
| 7 | an inherited `GIT_CONFIG_COUNT` family naming the script, no protective pair | **ran** |
| 8 | repo-set `core.hooksPath` with a `post-index-change` hook, a stat-dirty file, fsmonitor pair only (baseline) | hook ran, index rewritten |
| 9 | plus `GIT_OPTIONAL_LOCKS=0` | neither |
| 10 | plus the `core.hooksPath=/dev/null` pair, no `GIT_OPTIONAL_LOCKS` | hook did not run, **index rewritten** |
| 11 | the round-2 settings | neither |
| 12 | the real `analyze.py` over a repo with one worktree, a stat-dirty file in each checkout, the same hook; no protection (baseline) | hook ran; `.git/index` and `.git/worktrees/wt-feat/index` rewritten |
| 13 | fsmonitor pair only | the same as probe 12 |
| 14 | the round-2 settings | hook did not run; every file under `.git` identical in content and mtime; exit 0, run complete |
| 15 | inherited `GIT_CONFIG_COUNT=3` whose `KEY_2` names the script (baseline) | script ran |
| 16 | that, with the count and pairs 0 and 1 overwritten by the round-2 settings | did not run |
| 17 | branch `feat` whose tip carries a `gpgsig` header; `log.showSignature=true`, `gpg.program` = a marker script; plain `git log -1 --format=%cr feat` (baseline) | marker ran once |
| 18 | the real analyzer, the round-2 settings | **marker ran twice**, exit 0 |
| 19 | the real analyzer, all settings | did not run, exit 0 |
| 20 | all settings except the `log.showSignature` pair (falsifier) | ran twice |
| 21 | a `--filter=blob:none` clone with a local `feat` whose blobs are missing; `remote.origin.uploadpack` = a marker script; plain `git diff --shortstat main...feat` (baseline) | marker ran, exit 128 |
| 22 | the real analyzer, the round-2 settings | **marker ran**, exit 0 |
| 23 | the real analyzer, all settings | did not run, exit 0 |
| 24 | all settings except `GIT_NO_LAZY_FETCH` (falsifier) | ran |
| 25 | a working partial clone (the real upload-pack), all settings | `feat`'s `diff` is `""`; the 2 missing objects are still missing |
| 26 | the same clone, the round-2 settings | `feat`'s `diff` is `"+3 −1"`; the analyzer downloaded both missing objects into the scanned repo |
| 27 | `diff.external` = a marker script; plain `git diff main...feat` (baseline) | ran |
| 28 | the same, `git diff --shortstat main...feat` (the analyzer's form, `analyze.py:163`), round-2 settings | did not run |
| 29 | `.gitattributes` `diff=x` and `diff.x.textconv` = a marker script; plain `git diff main...feat` (baseline) | ran |
| 30 | the same, `git diff --shortstat main...feat`, round-2 settings | did not run |
| 31 | `filter.x.clean` = a marker script, `.gitattributes` `filter=x`, a stat-dirty tracked file; `git status --porcelain`, all settings | **ran**: no setting in the table stops a filter |
| 32 | the same, with `filter.x.clean`, `.smudge` and `.process` set empty and `.required=false` | did not run |
| 33 | an ordinary repo with a worktree: the real analyzer, round-2 settings versus all settings | stdout byte-identical (2182 bytes) |

**What a partial clone shows (probes 25, 26).** With `GIT_NO_LAZY_FETCH=1` the analyzer never
fetches. A branch whose changed blobs are not local makes its `git diff --shortstat` exit 128, which
the analyzer turns into an empty diffstat, the value the board shows for a branch with no diff;
the Ledger instead shows "diff unknown" (spec section 6.4). Under the round-2 settings the same run
fetched over the network and wrote the downloaded objects into the scanned repository's `.git`, so
the setting closes a write as well as a program route, and the claim "git writes nothing in a
scanned repository" depends on it.

**Version floor: git 2.45 (decision D33).** git(1) says `--no-lazy-fetch` "is equivalent to setting
the `GIT_NO_LAZY_FETCH` environment variable to `1`", and the earliest release notes that name it
are 2.45.0's; 2.44.0's name nothing of the kind (read from `Documentation/RelNotes/2.44.0.adoc` and
`2.45.0.adoc` in git's repository on 2026-11-03). The variable's own first release was not
separately established. The pinned git, 2.50.1, honours it (probes 23 and 25), so the pin does not
predate it, and the stated floor rises from 2.31 to 2.45. **Below that floor the Ledger starts no
analysis.** Once, at startup and before the runner starts, a function in `ledger_jobs.py` runs
`git --version` through the child registry's launch method (so with the builder's environment and
the `PATH` every scan and analyzer gets), under `GIT_TIMEOUT_SECS`, and reads `git version
<major>.<minor>` from its first line. Below 2.45, an answer with no such version, a non-zero exit, a
timeout or a spawn error all count as too old. Then the runner is not started (waiting items stay
`waiting` and do not count as busy for the idle exit); `analyze`, `reanalyze` and `retry` answer
`503 git_too_old` as the first thing each op does, before any scan or state change, with nothing
queued; first launch queues nothing; and startup writes one stderr line, `server: git 2.45 or newer
needed; the Ledger will not start analyses (found <x.y>)`, with `unreadable` for `<x.y>` when no
version was read. Nothing else changes: the board, `GET /tracker-data.js`, `/command`, the status
poll, `remove` and `delete` work as with a newer git. It runs at startup because one probe per
process, before anything can launch, is the least that holds the floor. Criterion A9.

### 10. Which git config routes were tried, and the lower bound

**Tried**, by the probes above or by the judges' reads they reproduce: `core.fsmonitor` (probes 1-7);
hooks through `core.hooksPath` (8-14); `gpg.program` through `log.showSignature` (17-20); a promisor
lazy fetch through `remote.<name>.uploadpack` (21-26); `diff.external` and `diff.<driver>.textconv`
(27-30; neither runs on the analyzer's `--shortstat`); and file filters (31-32, which the table does
not stop, and which stay on: section 11).

**The routes closed here are a lower bound until the config-key check below has run.** Before the
user's spec review (2026-11-04) the spec said that git's other config keys that can name a program
had not been checked one by one, and that each review round so far had found more (fsmonitor first,
hooks at round 2, `gpg.program` and the lazy fetch at round 3). That statement stands until the
table in section 12 is complete. Afterwards the routes closed cover one documented list of keys at
the pinned git, not everything git can do.

### 11. File filters stay on, and are the user's accepted risk

A scanned repository's own config can name a filter program, and file filters run when `git status`
checks a repository. None of the protective settings stops a filter (probe 31). Git runs a clean
filter when it has to re-hash a tracked file whose stat data differs from the index; a fresh clone
is stat-clean and runs none, and `GIT_OPTIONAL_LOCKS=0` means the analyzer never refreshes that
state itself. **Filters stay on, decided by the user (decision D20, 2026-11-03), and remain his
accepted risk**: his own `git status` in a terminal runs the same filters on the same repositories.
Repositories that use Git LFS are never skipped.

Why it was decided without a test. The task had been to try switching filter drivers off by name on
a real Git LFS repository (decisions D15, D17). The observability judge's round-4 read showed the
answer in advance, using a fake LFS-shaped driver through the real analyzer (`git-lfs` is not
installed on this host, so real LFS has not been measured anywhere): with filters off, a stat-dirty
LFS-shaped file reads as modified (`1 uncommitted`, `dirty: true`, against `clean` with the filter
on), so a "blanked run must match an unblanked one" rule could not pass; and git ignores
`filter.<driver>.clean` when `.process` is set, so a falsifier that wrapped `.clean` could not fire
where `.process` is set (a working `.process` driver ran once and its `.clean` wrapper 0 times). The
user chose to decide now: no LFS test, no `git-lfs` install, so no tool whose vetting checks did not
run is installed. Probe 32 stays as a measurement, not a plan.

### 12. The config-key check: procedure and table

Decided at the user's spec review (decision D28); the procedure is the spec author's. One pass over
one documented list, at the pinned git (2.50.1), recorded as the table below. The table is filled by
tasks 1b (reading and sorting) and 1c (measuring); this record is written with the heading and
column headers only.

- **Source.** The keys `git help --config` prints, each read in the `git-config(1)` page installed
  with that git, `$(git --man-path)/man1/git-config.1`, where each key has its own entry; a key
  printed without an entry of its own is read in its group's entry. Plus the driver keys
  `gitattributes(5)` documents that the list lacks (`man5/gitattributes.5` in the same folder),
  because attributes choose the drivers `git status` and `git diff` run. Measured 2026-11-04: 954
  keys, 699 of them with an entry of their own, and three driver keys found only in
  `gitattributes(5)`: `diff.<driver>.algorithm`, `filter.<driver>.process` and
  `filter.<driver>.required`. The list alone would miss a route already named, `filter.<driver>.process`.
- **Candidates, mechanically.** A key is a candidate when its text matches, case-insensitively at the
  start of a word, any of `program`, `command`, `executable`, `script`, `helper`, `hook`, `editor`,
  `pager`, `shell`, `tool`, `driver`, `invok`, `spawn`, `execut` or `run`; the three driver keys are
  candidates by rule. At 2.50.1 the words select 262 of the 699 (measured), among them every key a
  probe measured naming a program: `core.fsmonitor`, `core.hooksPath`, `gpg.program`,
  `remote.<name>.uploadpack`, `diff.external`, `diff.<driver>.textconv`, `filter.<driver>.clean` and
  `.smudge`. The word list's falsifier: one that loses any of them is too narrow, and without
  `command` it loses the two filter keys (measured). **The set the test compares** is exactly the keys
  with an entry of their own whose text matches the words, plus the three driver keys. **The 255
  keys printed without an entry of their own (954 - 699, read in the `advice.*`, `color.*`, `fsck.*`
  and `receive.fsck.*` group entries) are not candidates, and were not checked one by one.**
- **Judging, by reading.** Each candidate's text is read once. A key **names a program** when the text
  says git runs its value, a program its value names, or a program found through it (a hook in a
  directory it names), as a process or a shell command; otherwise its row quotes the sentence that
  says what the value is. A key that only switches on a program another key names, such as
  `log.showSignature` for `gpg.program`, is judged with that key.
- **Check.** Each key that names a program is checked against the git commands the scan and the
  analyzer run: the scan's three (`rev-parse --show-toplevel`, `rev-parse --path-format=absolute
  --git-common-dir --show-toplevel`, `worktree list --porcelain`; spec section 4.1) and the
  analyzer's (`grep -n '_git(' treko/analyze.py`: the definition at `:92` and eight calls, at `:126`,
  `:143`, `:150`, `:163`, `:177`, `:437`, `:440` and `:468`). A key whose text names the commands that
  read it, none of them one of those, is recorded as unreachable on that sentence (`sendemail.*`,
  which only `git send-email` reads). A key a probe above already measured is recorded from that
  probe. Every other key is measured in a scratch repository under `mktemp -d`, never this one: set,
  in the repository's own `.git/config`, to a marker-writing script (for a key naming a directory, a
  directory holding one), with the trigger its text names built in wherever those commands can meet
  it (a signed tip, a missing blob, a stat-dirty file); then the three scan commands and the real
  `analyze.py` run with every protective setting. The fixture's baseline must fire first: a plain git
  command its text says runs it, without the settings, writes the marker. A row whose baseline
  cannot be built says why and counts as not measured, never as checked.
- **Outcomes.** A key that fires is switched off by a protective setting like the rows of section 9,
  added there with a probe and a criterion like C10, or is recorded as an accepted risk only with
  the user's OK, as file filters are. A key measured as not firing is recorded as "does not fire",
  with its trigger, the commands run and the result. A row left not measured needs the user's OK too.
  **When a key fires, or a row stays not measured (decision D34), the builder stops and brings it to
  the user**; the spec, this table and the criteria change only with his OK.
- **Bound.** One pass over that list at the pinned git, and nothing more. It does not cover a key git
  documents only in another page, behaviour its documentation does not describe, or another git
  version. When the pinned git changes, the check runs again, and criterion C12 fails until it has.

**Verdict vocabulary** (five, and only these): `does not name a program`, `unreachable`,
`does not fire`, `fires`, `not measured`. A `fires` row names either a protective setting from
section 9 or the user's decision accepting the risk; a `not measured` row names the user's decision.

#### Config-key table

<!-- Filled by tasks 1b and 1c. Test C12 reads this table's Key column; keep the heading and column headers. -->

| Key | Verdict | Evidence: the quoted sentence, the probe, or the measurement | Setting or decision |
|---|---|---|---|
| `alias.*` | unreachable | A leading `!` makes an alias a shell command, but "aliases that hide existing Git commands are ignored"; every command the scan and the analyzer run (rev-parse, worktree, for-each-ref, rev-list, diff, log, status) is an existing git command. |  |
| `am.keepcr` | does not name a program | "If true, git-am will call git-mailsplit for patches in mbox format with parameter --keep-cr." |  |
| `am.threeWay` | does not name a program | "When set to true, this setting tells git am to fall back on 3-way merge" |  |
| `attr.tree` | does not name a program | "A reference to a tree in the repository from which to read attributes" |  |
| `blame.ignoreRevsFile` | does not name a program | "Ignore revisions listed in the file, one unabbreviated object name per line" |  |
| `branch.<name>.rebase` | does not name a program | `"When true, rebase the branch <name> on top of the fetched branch"` |  |
| `browser.<tool>.cmd` | unreachable | Names a program: "Specify the command to invoke the specified browser." The entry sends the reader to "(See git-web--browse(1).)", which is neither a scan command nor one of the analyzer's. |  |
| `browser.<tool>.path` | unreachable | Names a program path, for commands the text names: "that may be used to browse HTML help (see -w option in git-help(1)) or a working repository in gitweb (see git-instaweb(1))". Neither git help -w nor git instaweb is run. |  |
| `bundle.heuristic` | does not name a program | "The only value currently understood is creationToken." |  |
| `checkout.defaultRemote` | does not name a program | "This setting allows for setting the name of a preferred remote that should always win when it comes to disambiguation." |  |
| `checkout.thresholdForParallelism` | does not name a program | "This setting allows you to define the minimum number of files for which parallel checkout should be attempted." |  |
| `checkout.workers` | does not name a program | "The number of parallel workers to use when updating the working tree." |  |
| `clone.defaultRemoteName` | does not name a program | "The name of the remote to create when cloning a repository." |  |
| `clone.rejectShallow` | does not name a program | "Reject cloning a repository if it is a shallow one" |  |
| `color.diff` | does not name a program | "Whether to use ANSI escape sequences to add color to patches." |  |
| `color.pager` | does not name a program | "A boolean to specify whether auto color modes should colorize output going to the pager." |  |
| `color.ui` | does not name a program | "This variable determines the default value for variables such as color.diff and color.grep" |  |
| `column.ui` | does not name a program | "Specify whether supported commands should output in columns." |  |
| `commit.status` | does not name a program | "A boolean to enable/disable inclusion of status information in the commit message template" |  |
| `completion.commands` | does not name a program | "This is only used by git-completion.bash to add or remove commands from the list of completed commands." |  |
| `core.alternateRefsCommand` | fires | Names a program: "When advertising tips of available history from an alternate, use the shell to execute the specified command instead of git-for-each-ref(1)." Task 1c probes `alternateRefsCommand` and `alt_partial` (scratch repositories, the key set in `.git/config` to a marker script, `.git/objects/info/alternates` naming another repository, git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`). Baseline, no settings: a plain `git fetch origin` ran it (2 marker lines) and `git receive-pack` into the repository ran it (1). In a partial clone with the same alternate, rebuilt before each phase: a plain `git diff --shortstat main...feat` ran it by lazy fetch (1) and the analyzer without the settings ran it (1); the scan's three commands and the analyzer with all section 9 settings did not (0 lines, exit 0, JSON valid). In a full clone, with no lazy fetch to start, the analyzer without the settings did not run it (0). | `GIT_NO_LAZY_FETCH` set to `1` (section 9) |
| `core.askPass` | fires | Names a program: "Some commands (e.g. svn and http interfaces) that interactively ask for a password can be told to use an external program given via the value of this variable." Task 1c probe `askPass`: a `--filter=blob:none` clone whose local `feat` lacks its blobs, `origin` a local HTTP server answering every request 401, the key a marker script, git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`. Baseline, no settings: a plain `git fetch origin` ran it (2 marker lines) and a plain `git diff --shortstat main...feat` ran it by lazy fetch (2); the analyzer without the settings ran it (2); the scan's three commands (0 lines) and the analyzer with all section 9 settings (0 lines, exit 0, JSON valid) did not. | `GIT_NO_LAZY_FETCH` set to `1` (section 9) |
| `core.bare` | does not name a program | "If true this repository is assumed to be bare and has no working directory associated with it." |  |
| `core.bigFileThreshold` | does not name a program | "The size of files considered "big"" |  |
| `core.commentChar` | does not name a program | "consider a line that begins with this character commented" |  |
| `core.commentString` | does not name a program | "consider a line that begins with this character commented" |  |
| `core.editor` | unreachable | Names a program, for commands the text names: "Commands such as commit and tag that let you edit messages by launching an editor use the value of this variable". Neither commit nor tag is run. |  |
| `core.fileMode` | does not name a program | "Tells Git if the executable bit of files in the working tree is to be honored." |  |
| `core.fsmonitor` | fires | Probes 1-7: "Otherwise, this variable contains the pathname of the "fsmonitor" hook command." Baseline probe 1: a plain `git status --porcelain` ran the script; probe 2: with the pair it did not (probes 6 and 14 agree). | `core.fsmonitor` set to `false` (section 9) |
| `core.fsmonitorHookVersion` | does not name a program | "Sets the protocol version to be used when invoking the "fsmonitor" hook." A version number; the program itself is `core.fsmonitor`'s (probes 1-7). |  |
| `core.fsync` | does not name a program | "A comma-separated list of components of the repository that should be hardened via the core.fsyncMethod" |  |
| `core.gitProxy` | fires | Names a program: "A "proxy command" to execute (as command host port) instead of establishing direct connection to the remote server when using the Git protocol for fetching." Task 1c probe `proxy`: a `--filter=blob:none` clone whose local `feat` lacks its blobs, `origin` set to `git://127.0.0.1:1/repo.git`, the key a marker script, git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`. Baseline, no settings: a plain `git fetch origin` ran it (1 marker line) and a plain `git diff --shortstat main...feat` ran it by lazy fetch (1); the analyzer without the settings ran it (1); the scan's three commands (0 lines) and the analyzer with all section 9 settings (0 lines, exit 0, JSON valid) did not. | `GIT_NO_LAZY_FETCH` set to `1` (section 9) |
| `core.hooksPath` | fires | Probes 8-14: "Set this to different path, e.g. /etc/git/hooks, and Git will try to find your hooks in that directory". Baseline probe 8: the hook ran and the index was rewritten; probe 10 (the pair alone): the hook did not run, the index was rewritten; probe 9 (`GIT_OPTIONAL_LOCKS=0` alone) and probes 11 and 14 (both): neither. | `core.hooksPath` set to `/dev/null`, with `GIT_OPTIONAL_LOCKS` (section 9) |
| `core.pager` | does not fire | Names a program: "The value is meant to be interpreted by the shell." The trigger is git's stdout being a terminal (the `pager.<cmd>` entry: "when writing to a tty"). Task 1c probe `core.pager` (the key a marker script that drains stdin; git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`). Baseline, no settings, git's stdout a pty: `log -1`, `diff main...feat`, `diff --shortstat main...feat` and `log -1 --format=%cr feat` each ran it (1 marker line); `status`, `rev-parse --show-toplevel`, `worktree list --porcelain`, `for-each-ref` and `rev-list --left-right --count` did not. The scan's three commands and the analyzer with all section 9 settings, git's stdout a pipe as launched (the analyzer's `_git` passes `capture_output=True`): 0 lines; the analyzer with its own stdout a pty: 0; the analyzer without the settings, pipes: 0. Control, not how they are launched: with all settings and git's stdout a pty, the `log` and `diff` forms ran it again, so **no section 9 setting stops it; the captured output does**. `ledger_scan.py` is not written yet, so the scan's pipes are the spec's (section 4.1 reads each command's output), not measured. | none: no section 9 setting applies; holds while git's stdout is not a terminal |
| `core.preferSymlinkRefs` | does not name a program | "Instead of the default "symref" format for HEAD and other symbolic reference files, use symbolic links." |  |
| `core.quotePath` | does not name a program | "will quote "unusual" characters in the pathname" |  |
| `core.restrictinheritedhandles` | does not name a program | "Windows-only: override whether spawned processes inherit only standard file handles" |  |
| `core.safecrlf` | does not name a program | "If true, makes Git check if converting CRLF is reversible when end-of-line conversion is active." |  |
| `core.sshCommand` | fires | Names a program: "git fetch and git push will use the specified command instead of ssh when they need to connect to a remote system." Task 1c probe `sshCommand`: a `--filter=blob:none` clone whose local `feat` lacks its blobs, `origin` set to `ssh://127.0.0.1:1/repo.git`, the key a marker script, git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`. Baseline, no settings: a plain `git fetch origin` ran it (2 marker lines) and a plain `git diff --shortstat main...feat` ran it by lazy fetch (2); the analyzer without the settings ran it (2); the scan's three commands (0 lines) and the analyzer with all section 9 settings (0 lines, exit 0, JSON valid) did not. | `GIT_NO_LAZY_FETCH` set to `1` (section 9) |
| `core.unsetenvvars` | does not name a program | "Windows-only: comma-separated list of environment variables" |  |
| `core.useReplaceRefs` | does not name a program | "If set to false, behave as if the --no-replace-objects option was given on the command line." |  |
| `core.worktree` | does not name a program | "Set the path to the root of the working tree." |  |
| `credential.helper` | fires | Names a program: "Specify an external helper to be called when a username or password credential is needed"; the value may be "an absolute path with arguments or, if preceded by !, shell commands". Task 1c probe `credential.helper`: a `--filter=blob:none` clone whose local `feat` lacks its blobs, `origin` a local HTTP server answering every request 401, the key a marker script, git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`. Baseline, no settings: a plain `git fetch origin` ran it (1 marker line) and a plain `git diff --shortstat main...feat` ran it by lazy fetch (1); the analyzer without the settings ran it (1); the scan's three commands (0 lines) and the analyzer with all section 9 settings (0 lines, exit 0, JSON valid) did not. | `GIT_NO_LAZY_FETCH` set to `1` (section 9) |
| `credential.interactive` | does not name a program | "To avoid the possibility of user interactivity from Git, set credential.interactive=false." |  |
| `credential.protectProtocol` | does not name a program | "By default, Carriage Return characters are not allowed in the protocol that is used when Git talks to a credential helper." |  |
| `diff.<driver>.algorithm` | does not name a program | gitattributes(5): `"Then, define a "diff.<name>.algorithm" configuration to specify the diff algorithm, choosing from myers, patience, minimal, or histogram."` |  |
| `diff.<driver>.binary` | does not name a program | "Set this option to true to make the diff driver treat files as binary." |  |
| `diff.<driver>.cachetextconv` | does not name a program | "Set this option to true to make the diff driver cache the text conversion outputs." A boolean about the output of `diff.<driver>.textconv` (probes 29 and 30); it names no program. |  |
| `diff.<driver>.command` | does not fire | Names a program: "The custom diff driver command." `"If diff.<name>.command is defined for path with the diff=<name> attribute, it is executed as an external diff driver"` (gitattributes(5)). Task 1c probe `diff.command` (committed `.gitattributes` `* diff=x`, `diff.x.command` a marker script, a stat-dirty file in each checkout re-made before every phase, git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`). Baseline, no settings: `git --no-pager diff main...feat` ran it (1 marker line). The analyzer's form `git diff --shortstat main...feat` did not run it even without the settings (0), nor did a worktree `git diff` over stat-dirty files whose content is unchanged (0); the scan's three commands and the analyzer, with all section 9 settings and without, ran it 0 times (exit 0, JSON valid). As probes 27-30 found for `diff.external` and `.textconv`. | none needed: `--shortstat` starts no diff driver |
| `diff.<driver>.textconv` | does not fire | Probes 29-30: "The command that the diff driver should call to generate the text-converted version of a file." Baseline probe 29: `.gitattributes` `diff=x` and `diff.x.textconv` a marker script, plain `git diff main...feat` ran it; probe 30: the analyzer's form `git diff --shortstat main...feat` under the round-2 settings did not. |  |
| `diff.<driver>.trustExitCode` | does not name a program | `"If this boolean value is set to true then the diff.<driver>.command command is expected to return exit code 0 if it considers the input files to be equal"` A boolean about an exit code; the program is `diff.<driver>.command`'s. |  |
| `diff.<driver>.wordRegex` | does not name a program | "The regular expression that the diff driver should use to split words in a line." |  |
| `diff.<driver>.xfuncname` | does not name a program | "The regular expression that the diff driver should use to recognize the hunk header." |  |
| `diff.autoRefreshIndex` | does not name a program | "When using git diff to compare with work tree files, do not consider stat-only changes as changed." |  |
| `diff.dirstat` | does not name a program | "A comma separated list of --dirstat parameters" |  |
| `diff.external` | does not fire | Probes 27-28: "If this config variable is set, diff generation is not performed using the internal diff machinery, but using the given command." Baseline probe 27: a plain `git diff main...feat` ran the script; probe 28: the analyzer's form `git diff --shortstat main...feat` under the round-2 settings did not. |  |
| `diff.guitool` | unreachable | Names a program through `difftool.<guitool>.cmd`, for the command the text names: "Controls which diff tool is used by git-difftool(1) when the -g/--gui flag is specified." git difftool is not run. |  |
| `diff.ignoreSubmodules` | does not name a program | "Sets the default value of --ignore-submodules." |  |
| `diff.interHunkContext` | does not name a program | "Show the context between diff hunks, up to the specified number of lines" |  |
| `diff.renames` | does not name a program | "Whether and how Git detects renames." |  |
| `diff.statGraphWidth` | does not name a program | "Limit the width of the graph part in --stat output." |  |
| `diff.statNameWidth` | does not name a program | "Limit the width of the filename part in --stat output." |  |
| `diff.tool` | unreachable | Names a program through `difftool.<tool>.cmd`, for the command the text names: "Controls which diff tool is used by git-difftool(1)." git difftool is not run. |  |
| `diff.trustExitCode` | does not name a program | "If this boolean value is set to true then the diff.external command is expected to return exit code 0 if it considers the input files to be equal" A boolean about an exit code; the program is `diff.external`'s (probes 27 and 28). |  |
| `diff.wsErrorHighlight` | does not name a program | "Highlight whitespace errors in the context, old or new lines of the diff." |  |
| `difftool.<tool>.cmd` | unreachable | Names a program, for the command the text names: "Specify the command to invoke the specified diff tool." `"See the --tool=<tool> option in git-difftool(1) for more details."` git difftool is not run. |  |
| `difftool.<tool>.path` | unreachable | Names a program path but no command: "Override the path for the given tool." It overrides the tool that `difftool.<tool>.cmd` runs, whose entry names git-difftool(1); git difftool is not run. Judged from that pairing, not from a command this entry names. |  |
| `difftool.guiDefault` | does not name a program | "Set true to use the diff.guitool by default (equivalent to specifying the --gui argument)" |  |
| `difftool.prompt` | does not name a program | "Prompt before each invocation of the diff tool." |  |
| `difftool.trustExitCode` | does not name a program | "Exit difftool if the invoked diff tool returns a non-zero exit status." |  |
| `feature.manyFiles` | does not name a program | "Enable config options that optimize for repos with many files in the working directory." |  |
| `fetch.parallel` | does not name a program | "Specifies the maximal number of fetch operations to be run in parallel at a time" |  |
| `fetch.prune` | does not name a program | "If true, fetch will automatically behave as if the --prune option was given on the command line." |  |
| `fetch.showForcedUpdates` | does not name a program | "Set to false to enable --no-show-forced-updates in git-fetch(1) and git-pull(1) commands." |  |
| `fetch.writeCommitGraph` | does not name a program | "Set to true to write a commit-graph after every git fetch command that downloads a pack-file from a remote." |  |
| `filter.<driver>.clean` | fires | Probes 31-32: "The command which is used to convert the content of a worktree file to a blob upon checkin." Probe 31: `filter.x.clean` a marker script, `.gitattributes` `filter=x`, a stat-dirty tracked file, `git status --porcelain` with all settings: ran, so no setting in section 9 stops a filter. Probe 32 (not adopted): emptying `.clean`, `.smudge` and `.process` and setting `.required=false` stopped it. | the user's accepted risk, decision D20 (section 11) |
| `filter.<driver>.process` | fires | Names a program, gitattributes(5): `"If the filter command (a string value) is defined via filter.<driver>.process then Git can process all blobs with a single filter invocation for the entire life of a single Git command."` Task 1c probe `filter.process` (committed `.gitattributes` `* filter=x`, `filter.x.process` a marker script that is no real filter, a stat-dirty tracked file in the repository and in its worktree, re-made before every phase, git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`). Baseline, no settings: a plain `git status --porcelain` ran it (1 marker line; exit 128, git hung up on the handshake). The analyzer with all section 9 settings ran it (2 lines, one per checkout, exit 0, JSON valid) and without them too (2); the scan's three commands did not (0). So no section 9 setting stops a process filter, as for `.clean` (probe 31). It falls under the accepted filter risk, which the user must confirm covers this key. | the user's accepted risk, decision D20 (section 11); to be confirmed for this key by the user, decision D34 |
| `filter.<driver>.required` | does not name a program | gitattributes(5): `"You can declare that a filter turns a content that by itself is unusable into a usable content by setting the filter.<driver>.required configuration variable to true."` |  |
| `filter.<driver>.smudge` | does not fire | Names a program: "The command which is used to convert the content of a blob object to a worktree file upon checkout." Task 1c probe `filter.smudge` (committed `.gitattributes` `* filter=x`, `filter.x.smudge` a marker script, a stat-dirty tracked file in each checkout re-made before every phase, git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`). Baseline, no settings: deleting `README.md` and running `git checkout -- README.md` ran it (1 marker line). The scan's three commands and the analyzer, with all section 9 settings and without, ran it 0 times (exit 0, JSON valid): none of them checks a file out, and a stat-dirty file makes `git status` run `.clean` (probe 31), not `.smudge`. | none needed: no scan or analyzer command checks a file out |
| `format.coverLetter` | does not name a program | "A boolean that controls whether to generate a cover-letter when format-patch is invoked" |  |
| `format.filenameMaxLength` | does not name a program | "The maximum length of the output filenames generated by the format-patch command" |  |
| `format.pretty` | does not name a program | "The default pretty format for log/show/whatchanged command." |  |
| `fsck.skipList` | does not name a program | "The path to a list of object names (i.e. one unabbreviated SHA-1 per line)" |  |
| `fsmonitor.socketDir` | does not name a program | "specifies the directory in which to create the Unix domain socket used for communication between the fsmonitor daemon and various Git commands" "Only respected when core.fsmonitor is set to true." |  |
| `gc.auto` | does not name a program | "When there are approximately more than this many loose objects in the repository, git gc --auto will pack them." |  |
| `gc.autoDetach` | does not name a program | "Make git gc --auto return immediately and run in the background if the system supports it." |  |
| `gc.bigPackThreshold` | does not name a program | "If non-zero, all non-cruft packs larger than this limit are kept when git gc is run." |  |
| `gc.logExpiry` | does not name a program | "unless that file is more than gc.logExpiry old." |  |
| `gc.maxCruftSize` | does not name a program | "Limit the size of new cruft packs when repacking." |  |
| `gc.packRefs` | does not name a program | "This variable determines whether git gc runs git pack-refs." |  |
| `gc.pruneExpire` | does not name a program | "Override the grace period with this config variable." |  |
| `gc.recentObjectsHook` | unreachable | Names a program: "When considering whether or not to remove an object (either when generating a cruft pack or storing unreachable objects as loose), use the shell to execute the specified command(s)." Only gc and repack remove objects or write cruft packs; neither is run, and the scan and the analyzer write no objects. |  |
| `gc.rerereResolved` | does not name a program | "Records of conflicted merge you resolved earlier are kept for this many days when git rerere gc is run." |  |
| `gc.rerereUnresolved` | does not name a program | "Records of conflicted merge you have not resolved are kept for this many days when git rerere gc is run." |  |
| `gc.worktreePruneExpire` | does not name a program | "This config variable can be used to set a different grace period." |  |
| `gc.writeCommitGraph` | does not name a program | "If true, then gc will rewrite the commit-graph file when git-gc(1) is run." |  |
| `gitcvs.dbDriver` | unreachable | Names a Perl module, for the command the text names: "Used Perl DBI driver." "See git-cvsserver(1)." git cvsserver is not run. |  |
| `gitcvs.dbName` | does not name a program | "Database used by git-cvsserver to cache revision information derived from the Git repository." |  |
| `gpg.<format>.program` | fires | Names a program: "Use this to customize the program used for the signing format you chose." "The default value for gpg.x509.program is "gpgsm" and gpg.ssh.program is "ssh-keygen"." Task 1c probe `gpg.program` for the `ssh`, `x509` and `openpgp` formats (branch tips carrying a `gpgsig` header of each kind, built as in probe 17; the repository sets `log.showSignature=true`, one marker script per format key, and `gpg.ssh.allowedSignersFile` to an empty file, without which git refuses an SSH check before it runs the program; git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`). Baseline, no settings: a plain `git log -1 --format=%cr <branch>` ran the ssh program (2 marker lines), the x509 program (1) and the openpgp program (1). The analyzer without the settings ran them 4, 2 and 2 times; the scan's three commands (repository and worktree) and the analyzer with all section 9 settings ran none (exit 0, JSON valid). Probes 17-20 measured the `gpg.program` synonym. | `log.showSignature` set to `false` (section 9) |
| `gpg.program` | fires | Probes 17-20, with `log.showSignature`, which only switches the program on and is judged here: "Pathname of the program to use instead of "gpg" when making or verifying a PGP signature." Baseline probe 17: a tip with a `gpgsig` header, `log.showSignature=true`, `gpg.program` a marker script, plain `git log -1 --format=%cr feat` ran it once; probe 18: the analyzer under the round-2 settings ran it twice; probe 19: all settings, did not run; probe 20: all settings except the `log.showSignature` pair, ran twice. | `log.showSignature` set to `false` (section 9) |
| `gpg.ssh.defaultKeyCommand` | does not fire | Names a program: "This command will be run when user.signingkey is not set and a ssh signature is requested." Task 1c probe `gpg.ssh.defaultKeyCommand` (`gpg.format=ssh`, the key a marker script, an SSH-signed tip on `feat`, `log.showSignature=true`, `gpg.ssh.allowedSignersFile` an empty file, git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`). Baseline, no settings: a plain `git commit -S --allow-empty` ran it (1 marker line; the commit then failed, exit 128, the script gave no key). Verifying does not request it: a plain `git log -1 --show-signature feat` wrote 0 lines. The scan's three commands and the analyzer, with all section 9 settings and without, ran it 0 times (exit 0, JSON valid): neither runs a command that signs. | none needed: no scan or analyzer command signs |
| `grep.fallbackToNoIndex` | does not name a program | "If set to true, fall back to git grep --no-index if git grep is executed outside of a git repository." |  |
| `gui.blamehistoryctx` | does not name a program | "Specifies the radius of history context in days to show in gitk(1) for the selected commit" |  |
| `gui.encoding` | does not name a program | "Specifies the default character encoding to use for displaying of file contents in git-gui(1) and gitk(1)." |  |
| `guitool.<name>.argPrompt` | does not name a program | "Request a string argument from the user, and pass it to the tool through the ARGS environment variable." |  |
| `guitool.<name>.cmd` | unreachable | Names a program, for the command the text names: "Specifies the shell command line to execute when the corresponding item of the git-gui(1) Tools menu is invoked." git gui is not run. |  |
| `guitool.<name>.confirm` | does not name a program | "Show a confirmation dialog before actually running the tool." |  |
| `guitool.<name>.needsFile` | does not name a program | "Run the tool only if a diff is selected in the GUI." |  |
| `guitool.<name>.noConsole` | does not name a program | "Run the command silently, without creating a window to display its output." |  |
| `guitool.<name>.noRescan` | does not name a program | "rescan the working directory for changes after the tool finishes execution." |  |
| `guitool.<name>.prompt` | does not name a program | "Specifies the general prompt string to display at the top of the dialog" |  |
| `guitool.<name>.revUnmerged` | does not name a program | "Show only unmerged branches in the revPrompt subdialog." |  |
| `guitool.<name>.title` | does not name a program | "Specifies the title to use for the prompt dialog." |  |
| `help.autoCorrect` | does not name a program | "If git detects typos and can identify exactly one valid command similar to the error, git will try to suggest the correct command or even run the suggestion automatically." The value is a number or a word, and the command run is a git command, not one the value names. |  |
| `http.<url>.*` | does not name a program | `"Any of the http.* options above can be applied selectively to some URLs."` |  |
| `http.minSessions` | does not name a program | "The number of curl sessions (counted across slots) to be kept across requests." |  |
| `http.noEPSV` | does not name a program | "A boolean which disables using of EPSV ftp command by curl." |  |
| `http.proactiveAuth` | does not name a program | "Attempt authentication without first making an unauthenticated attempt and receiving a 401 response." |  |
| `http.schannelCheckRevoke` | does not name a program | "Used to enforce or disable certificate revocation checks in cURL when http.sslBackend is set to "schannel"." |  |
| `http.sslBackend` | does not name a program | "Name of the SSL backend to use (e.g. "openssl" or "schannel")." |  |
| `i18n.logOutputEncoding` | does not name a program | "Character encoding the commit messages are converted to when running git log and friends." |  |
| `imap.authMethod` | does not name a program | "Specify the authentication method for authenticating with the IMAP server." |  |
| `imap.tunnel` | unreachable | Names a program but no command: "Command used to set up a tunnel to the IMAP server". An IMAP server is only reached by the command the sibling entry names, "If this is not set then git imap-send uses the basic IMAP plaintext LOGIN command." (the `imap.authMethod` entry) git imap-send is not run. Judged from that pairing, not from a command this entry names. |  |
| `index.skipHash` | does not name a program | "When enabled, do not compute the trailing hash for the index file." |  |
| `index.threads` | does not name a program | "Specifies the number of threads to spawn when loading the index." |  |
| `init.defaultObjectFormat` | does not name a program | "Allows overriding the default object format for new repositories." |  |
| `init.defaultRefFormat` | does not name a program | "Allows overriding the default ref storage format for new repositories." |  |
| `instaweb.browser` | unreachable | Names a program, for the command the text names: "Specify the program that will be used to browse your working repository in gitweb. See git-instaweb(1)." git instaweb is not run. |  |
| `instaweb.httpd` | unreachable | Names a program, for the command the text names: "The HTTP daemon command-line to start gitweb on your working repository. See git-instaweb(1)." git instaweb is not run. |  |
| `interactive.diffFilter` | unreachable | Names a program, for the commands the text names: "When an interactive command (such as git add --patch) shows a colorized diff, git will pipe the diff through the shell command defined by this configuration variable." No interactive command is run. |  |
| `interactive.singleKey` | does not name a program | "When set to true, allow the user to provide one-letter input with a single key" |  |
| `log.date` | does not name a program | "Set the default date-time mode for the log command." |  |
| `log.decorate` | does not name a program | "Print out the ref names of any commits that are shown by the log command." |  |
| `log.excludeDecoration` | does not name a program | "Exclude the specified patterns from the log decorations." |  |
| `log.showRoot` | does not name a program | "If true, the initial commit will be shown as a big creation event." |  |
| `mailinfo.scissors` | does not name a program | "If true, makes git-mailinfo(1) (and therefore git-am(1)) act by default as if the --scissors option was provided on the command-line." |  |
| `maintenance.<task>.enabled` | does not name a program | `"This boolean config option controls whether the maintenance task with name <task> is run when no --task option is specified to git maintenance run."` |  |
| `maintenance.<task>.schedule` | does not name a program | "The value must be one of "hourly", "daily", or "weekly"." |  |
| `maintenance.auto` | does not name a program | "This boolean config option controls whether some commands run git maintenance run --auto after doing their normal work." |  |
| `maintenance.autoDetach` | does not name a program | "This boolean config option controls whether this automatic maintenance shall happen in the foreground or whether the maintenance process shall detach and continue to run in the background." |  |
| `maintenance.commit-graph.auto` | does not name a program | "This integer config option controls how often the commit-graph task should be run as part of git maintenance run --auto." |  |
| `maintenance.incremental-repack.auto` | does not name a program | "This integer config option controls how often the incremental-repack task should be run as part of git maintenance run --auto." |  |
| `maintenance.loose-objects.auto` | does not name a program | "This integer config option controls how often the loose-objects task should be run as part of git maintenance run --auto." |  |
| `maintenance.reflog-expire.auto` | does not name a program | "This integer config option controls how often the reflog-expire task should be run as part of git maintenance run --auto." |  |
| `maintenance.rerere-gc.auto` | does not name a program | "This integer config option controls how often the rerere-gc task should be run as part of git maintenance run --auto." |  |
| `maintenance.strategy` | does not name a program | "This string config option provides a way to specify one of a few recommended schedules for background maintenance." |  |
| `maintenance.worktree-prune.auto` | does not name a program | "This integer config option controls how often the worktree-prune task should be run as part of git maintenance run --auto." |  |
| `man.<tool>.cmd` | unreachable | Names a program, for the command the text names: "Specify the command to invoke the specified man viewer." "(See git-help(1).)" git help is not run. |  |
| `man.<tool>.path` | unreachable | Names a program path, for the command the text names: "Override the path for the given tool that may be used to display help in the man format. See git-help(1)." git help is not run. |  |
| `man.viewer` | unreachable | Names programs, for the command the text names: "Specify the programs that may be used to display help in the man format. See git-help(1)." git help is not run. |  |
| `merge.<driver>.driver` | unreachable | Names a program but no command: "Defines the command that implements a custom low-level merge driver. See gitattributes(5) for details." A merge driver runs when git merges; none of the scan's or the analyzer's commands merges (the analyzer's `diff A...B` reads a merge base only). Judged from the command list, not from a sentence naming a command. |  |
| `merge.<driver>.name` | does not name a program | "Defines a human-readable name for a custom low-level merge driver." |  |
| `merge.<driver>.recursive` | unreachable | Only names another driver, so it is judged with `merge.<driver>.driver` (see that row): "Names a low-level merge driver to be used when performing an internal merge between common ancestors." |  |
| `merge.autoStash` | does not name a program | "When set to true, automatically create a temporary stash entry before the operation begins, and apply it after the operation ends." |  |
| `merge.ff` | does not name a program | "When set to only, only such fast-forward merges are allowed" |  |
| `merge.guitool` | unreachable | Names a program through `mergetool.<guitool>.cmd`, for the command the text names: "Controls which merge tool is used by git-mergetool(1) when the -g/--gui flag is specified." git mergetool is not run. |  |
| `merge.tool` | unreachable | Names a program through `mergetool.<tool>.cmd`, for the command the text names: "Controls which merge tool is used by git-mergetool(1)." git mergetool is not run. |  |
| `merge.verifySignatures` | unreachable | Only switches on signature checking, whose program is `gpg.program`'s (see that row), for the command the text names: "If true, this is equivalent to the --verify-signatures command line option. See git-merge(1) for details." git merge is not run. |  |
| `mergetool.<tool>.cmd` | unreachable | Names a program but no command: "Specify the command to invoke the specified merge tool." The sibling entry names the command: "Controls which merge tool is used by git-mergetool(1)." (the `merge.tool` entry) git mergetool is not run. Judged from that pairing, not from a command this entry names. |  |
| `mergetool.<tool>.hideResolved` | does not name a program | "Allows the user to override the global mergetool.hideResolved value for a specific tool." |  |
| `mergetool.<tool>.path` | unreachable | Names a program path but no command: "Override the path for the given tool. This is useful in case your tool is not in the $PATH." It overrides the tool that `mergetool.<tool>.cmd` runs, whose sibling entry names git-mergetool(1); git mergetool is not run. Judged from that pairing, not from a command this entry names. |  |
| `mergetool.<tool>.trustExitCode` | does not name a program | "specify whether the exit code of the merge command can be used to determine whether the merge was successful." |  |
| `mergetool.<variant>.layout` | does not name a program | "which is any of vimdiff, nvimdiff, gvimdiff." |  |
| `mergetool.guiDefault` | does not name a program | "Set true to use the merge.guitool by default (equivalent to specifying the --gui argument)" |  |
| `mergetool.hideResolved` | does not name a program | "This flag causes $LOCAL and $REMOTE to be overwritten so that only the unresolved conflicts are presented to the merge tool." |  |
| `mergetool.keepTemporaries` | does not name a program | "If the tool returns an error and this variable is set to true, then these temporary files will be preserved" |  |
| `mergetool.prompt` | does not name a program | "Prompt before each invocation of the merge resolution program." |  |
| `notes.displayRef` | does not name a program | "Which ref (or refs, if a glob or specified more than once), in addition to the default set by core.notesRef or GIT_NOTES_REF, to read notes from" |  |
| `notes.rewrite.<command>` | does not name a program | "if this variable is false, git will not copy notes from the original to the rewritten commit." |  |
| `notes.rewriteMode` | does not name a program | "Must be one of overwrite, concatenate, cat_sort_uniq, or ignore." |  |
| `notes.rewriteRef` | does not name a program | "specifies the (fully qualified) ref whose notes should be copied." |  |
| `pack.depth` | does not name a program | "The maximum delta depth used by git-pack-objects(1)" |  |
| `pack.packSizeLimit` | does not name a program | "The maximum size of a pack." |  |
| `pack.threads` | does not name a program | "Specifies the number of threads to spawn when searching for best delta matches." |  |
| `pack.window` | does not name a program | "The size of the window used by git-pack-objects(1)" |  |
| `pack.windowMemory` | does not name a program | "The maximum size of memory that is consumed by each thread in git-pack-objects(1) for pack window memory" |  |
| `pager.<cmd>` | does not fire | Names a program: `"Otherwise, turns on pagination for the subcommand using the pager specified by the value of pager.<cmd>."` The text limits it to "when writing to a tty". Task 1c probe `pager.cmd` (`pager.log`, `.diff`, `.status`, `.rev-parse`, `.worktree`, `.for-each-ref`, `.rev-list`, `.show` and `.branch` each a marker script that drains stdin; git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`). Baseline, no settings, git's stdout a pty: `log`, `diff`, `diff --shortstat`, `status`, `worktree list`, `for-each-ref` and `rev-list` each ran it (1 marker line), `rev-parse --show-toplevel` did not, so the key reaches the scan's `worktree list` as `core.pager` does not. The scan's three commands and the analyzer with all section 9 settings, git's stdout a pipe as launched (the analyzer's `_git` passes `capture_output=True`): 0 lines; the analyzer with its own stdout a pty: 0; the analyzer without the settings, pipes: 0. Control, not how they are launched: with all settings and git's stdout a pty, the same commands ran it again, so **no section 9 setting stops it; the captured output does**. `ledger_scan.py` is not written yet, so the scan's pipes are the spec's (section 4.1 reads each command's output), not measured. Judged with `core.pager`. | none: no section 9 setting applies; holds while git's stdout is not a terminal |
| `pretty.<name>` | does not name a program | "Alias for a --pretty= format string, as specified in git-log(1)." |  |
| `protocol.<name>.allow` | does not name a program | `"Set a policy to be used by protocol <name> with clone/fetch/push commands."` |  |
| `protocol.allow` | does not name a program | "If set, provide a user defined default policy for all protocols" |  |
| `pull.ff` | does not name a program | "This setting overrides merge.ff when pulling." |  |
| `pull.rebase` | does not name a program | "When true, rebase branches on top of the fetched branch" |  |
| `push.default` | does not name a program | "Defines the action git push should take if no refspec is given" |  |
| `push.gpgSign` | unreachable | Only switches on signing, whose program is `gpg.program`'s (see that row), for the command the text names: "A true value causes all pushes to be GPG signed, as if --signed is passed to git-push(1)." git push is not run. |  |
| `push.pushOption` | does not name a program | `"When no --push-option=<option> argument is given from the command line, git push behaves as if each <value> of this variable is given as --push-option=<value>."` |  |
| `push.useForceIfIncludes` | does not name a program | "If set to "true", it is equivalent to specifying --force-if-includes as an option to git-push(1) in the command line." |  |
| `rebase.abbreviateCommands` | does not name a program | "If set to true, git rebase will use abbreviated command names in the todo list" |  |
| `rebase.autoStash` | does not name a program | "When set to true, automatically create a temporary stash entry before the operation begins, and apply it after the operation ends." |  |
| `rebase.missingCommitsCheck` | does not name a program | "If set to "warn", git rebase -i will print a warning if some commits are removed" |  |
| `rebase.rebaseMerges` | does not name a program | "Whether and how to set the --rebase-merges option by default." |  |
| `rebase.rescheduleFailedExec` | does not name a program | "Automatically reschedule exec commands that failed." |  |
| `receive.autogc` | does not name a program | "By default, git-receive-pack will run "git maintenance run --auto" after receiving data from git-push and updating refs." |  |
| `receive.certNonceSlop` | does not name a program | "When a git push --signed sends a push certificate with a "nonce" that was issued by a receive-pack serving the same repository within this many seconds" |  |
| `receive.denyCurrentBranch` | does not name a program | "If set to true or "refuse", git-receive-pack will deny a ref update to the currently checked out branch of a non-bare repository." |  |
| `receive.procReceiveRefs` | unreachable | Names reference prefixes, and through them a hook, for the command the text names: "This is a multi-valued variable that defines reference prefixes to match the commands in receive-pack." "Commands matching the prefixes will be executed by an external hook "proc-receive"" git receive-pack is not run. |  |
| `receive.updateServerInfo` | does not name a program | "If set to true, git-receive-pack will run git-update-server-info after receiving data from git-push and updating refs." |  |
| `remote.<name>.mirror` | does not name a program | "If true, pushing to this remote will automatically behave as if the --mirror option was given on the command line." |  |
| `remote.<name>.prune` | does not name a program | "When set to true, fetching from this remote by default will also remove any remote-tracking references that no longer exist on the remote" |  |
| `remote.<name>.receivepack` | unreachable | Names a program, for the command the text names: "The default program to execute on the remote side when pushing. See option --receive-pack of git-push(1)." git push is not run. |  |
| `remote.<name>.serverOption` | does not name a program | "The default set of server options used when fetching from this remote." |  |
| `remote.<name>.uploadpack` | fires | Probes 21-26: "The default program to execute on the remote side when fetching. See option --upload-pack of git-fetch-pack(1)." Baseline probe 21: a `--filter=blob:none` clone, a local `feat` with missing blobs, plain `git diff --shortstat main...feat`: the marker ran, exit 128; probe 22: the analyzer under the round-2 settings, ran; probe 23: all settings, did not run; probe 24: all settings except `GIT_NO_LAZY_FETCH`, ran. | `GIT_NO_LAZY_FETCH` set to `1` (section 9) |
| `remote.<name>.vcs` | fires | Names a program through the value: `"Setting this to a value <vcs> will cause Git to interact with the remote with the git-remote-<vcs> helper."` Task 1c probes `vcs` and `vcs_ext`: a `--filter=blob:none` clone whose local `feat` lacks its blobs, `remote.origin.vcs=treko1c`, a marker script named `git-remote-treko1c` in a directory the fixture put first on `PATH` (a repository cannot put one there), git under `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1`. Baseline, no settings: a plain `git fetch origin` ran it (1 marker line) and a plain `git diff --shortstat main...feat` ran it by lazy fetch (1); the analyzer without the settings ran it (1); the scan's three commands (0 lines) and the analyzer with all section 9 settings (0 lines, exit 0, JSON valid) did not. The helper that ships with git needs no `PATH` entry, `remote.origin.vcs=ext` with url `ext::<marker script>`, but git refused it, "transport 'ext' not allowed" (0 lines on fetch and on lazy fetch). | `GIT_NO_LAZY_FETCH` set to `1` (section 9) |
| `repack.cruftDepth` | does not name a program | "Parameters used by git-pack-objects(1) when generating a cruft pack and the respective parameters are not given over the command line." |  |
| `repack.cruftThreads` | does not name a program | "Parameters used by git-pack-objects(1) when generating a cruft pack and the respective parameters are not given over the command line." |  |
| `repack.cruftWindow` | does not name a program | "Parameters used by git-pack-objects(1) when generating a cruft pack and the respective parameters are not given over the command line." |  |
| `repack.cruftWindowMemory` | does not name a program | "Parameters used by git-pack-objects(1) when generating a cruft pack and the respective parameters are not given over the command line." |  |
| `repack.updateServerInfo` | does not name a program | "If set to false, git-repack(1) will not run git-update-server-info(1)." |  |
| `repack.writeBitmaps` | does not name a program | "When true, git will write a bitmap index when packing all objects to disk" |  |
| `safe.bareRepository` | does not name a program | "Specifies which bare repositories Git will work with." |  |
| `safe.directory` | does not name a program | "These config entries specify Git-tracked directories that are considered safe even if they are owned by someone other than the current user." |  |
| `sendemail.<identity>.*` | unreachable | Names no command itself: `"Identity-specific versions of the sendemail.* parameters found below"`. The parameters' entries say "These configuration variables all provide a default for git-send-email(1) command-line options." (the `sendemail.annotate` entry) git send-email is not run. |  |
| `sendemail.aliasFileType` | does not name a program | "Format of the file(s) specified in sendemail.aliasesFile. Must be one of mutt, mailrc, pine, elm, gnus, or sendmail." |  |
| `sendemail.annotate` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.bcc` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.cc` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.ccCmd` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.chainReplyTo` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.envelopeSender` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.from` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.headerCmd` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.multiEdit` | does not name a program | "If true (default), a single editor instance will be spawned to edit files you have to edit" |  |
| `sendemail.signedOffByCc` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.smtpDomain` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.smtpPass` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.smtpServer` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.smtpServerOption` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.smtpServerPort` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.smtpUser` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.suppressCc` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.suppressFrom` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.thread` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.to` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.toCmd` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.transferEncoding` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.validate` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sendemail.xmailer` | unreachable | Names no command itself; its text is "These configuration variables all provide a default for git-send-email(1) command-line options." Only git send-email reads it, and it is not run. |  |
| `sequence.editor` | unreachable | Names a program, for the command the text names: "Text editor used by git rebase -i for editing the rebase instruction file." git rebase is not run. |  |
| `ssh.variant` | does not name a program | "The config variable ssh.variant can be set to override this detection. Valid values are ssh (to use OpenSSH options), plink, putty, tortoiseplink, simple" A variant name; the ssh command itself is `core.sshCommand`'s (see that row). |  |
| `stash.showIncludeUntracked` | does not name a program | "If this is set to true, the git stash show command will show the untracked files of a stash entry." |  |
| `stash.showPatch` | does not name a program | "If this is set to true, the git stash show command without an option will show the stash entry in patch form." |  |
| `stash.showStat` | does not name a program | "If this is set to true, the git stash show command without an option will show a diffstat of the stash entry." |  |
| `status.showUntrackedFiles` | does not name a program | "So, this variable controls how the commands display the untracked files." |  |
| `status.submoduleSummary` | does not name a program | "If this is set to a non-zero number or true (identical to -1 or an unlimited number), the submodule summary will be enabled" |  |
| `submodule.<name>.active` | does not name a program | "Boolean value indicating if the submodule is of interest to git commands." |  |
| `submodule.<name>.fetchRecurseSubmodules` | does not name a program | "This option can be used to control recursive fetching of this submodule." |  |
| `submodule.<name>.ignore` | does not name a program | "Defines under what circumstances "git status" and the diff family show a submodule as modified." |  |
| `submodule.<name>.update` | unreachable | Names a method, for the command the text names: "The method by which a submodule is updated by git submodule update, which is the only affected command". git submodule update is not run. |  |
| `submodule.<name>.url` | does not name a program | "The URL for a submodule." |  |
| `submodule.active` | does not name a program | "A repeated field which contains a pathspec" |  |
| `submodule.propagateBranches` | does not name a program | "A boolean that enables branching support when using --recurse-submodules or submodule.recurse=true." |  |
| `submodule.recurse` | does not name a program | "A boolean indicating if commands should enable the --recurse-submodules option by default." |  |
| `tag.forceSignAnnotated` | unreachable | Only switches on signing, whose program is `gpg.program`'s (see that row), for the operation the text names: "A boolean to specify whether annotated tags created should be GPG signed." Creating a tag is not something the scan or the analyzer does. |  |
| `tag.gpgSign` | unreachable | Only switches on signing, whose program is `gpg.program`'s (see that row), for the operation the text names: "A boolean to specify whether all tags should be GPG signed." Creating a tag is not something the scan or the analyzer does. |  |
| `trailer.<keyAlias>.cmd` | unreachable | Names a program, for the command the text names: `"This option can be used to specify a shell command that will be called once to automatically add a trailer with the specified <keyAlias>"` "at the beginning of the "git interpret-trailers" command" git interpret-trailers is not run. |  |
| `trailer.<keyAlias>.command` | unreachable | Names a program, for the command its sibling's text names: `"Deprecated in favor of trailer.<keyAlias>.cmd."` "at the beginning of the "git interpret-trailers" command" (the `trailer.<keyAlias>.cmd` entry) git interpret-trailers is not run. |  |
| `trailer.<keyAlias>.key` | does not name a program | `"Defines a <keyAlias> for the <key>."` |  |
| `trailer.separators` | does not name a program | "This option tells which characters are recognized as trailer separators." |  |
| `transfer.bundleURI` | does not name a program | "When true, local git clone commands will request bundle information from the remote server (if advertised)" |  |
| `transfer.credentialsInUrl` | does not name a program | "allow (default): Git will proceed with its activity without warning." |  |
| `transfer.fsckObjects` | does not name a program | "When fetch.fsckObjects or receive.fsckObjects are not set, the value of this variable is used instead." |  |
| `transfer.hideRefs` | does not name a program | "String(s) receive-pack and upload-pack use to decide which refs to omit from their initial advertisements." |  |
| `uploadpack.allowRefInWant` | does not name a program | "If this option is set, upload-pack will support the ref-in-want feature of the protocol version 2 fetch command." |  |
| `uploadpack.packObjectsHook` | unreachable | Names a program, for the command the text names, and limits where it is read: "If this option is set, when upload-pack would run git pack-objects to create a packfile for a client, it will run this shell command instead." "Note that this configuration variable is only respected when it is specified in protected configuration". A scanned repository's own config is not protected configuration, and git upload-pack is not run. |  |
| `url.<base>.insteadOf` | does not name a program | `"Any URL that starts with this value will be rewritten to start, instead, with <base>."` |  |
| `web.browser` | unreachable | Names a program, for the commands the text names: "Specify a web browser that may be used by some commands. Currently only git-instaweb(1) and git-help(1) may use it." Neither is run. |  |

## Alternatives considered

| Option | Verdict | Why |
|---|---|---|
| **Arguments only on a new `POST /ledger` that never reaches cmux; `/command` unchanged apart from a shorter allowlist (chosen)** | **Accepted** | The old rule exists so that no untrusted text reaches the session. That is preserved exactly on the route that types, and the new route is tested never to reach it (A5). |
| Add arguments to `/command` | Rejected | An argument on the route that types into a full-permission session is what the old rule forbids. |
| Keep `reanalyze` on `/command` beside the queue | Rejected | It would be a second writer of the store racing the job runner, still minting folder-name ids. The board's Re-analyze needs a run id, which `/command` cannot carry. |
| Serve the Ledger at `/` and move the board to `/board` | Rejected (the user chose, round 2) | It forced edits to five test modules that load the board at `/`, one of them 1,054 lines. The board keeps `/`, the Ledger gets `/ledger`, and launch opens the Ledger. |
| Audit every status poll | Rejected | Up to 1,800 lines an hour from one open tab, burying the state-changing lines in the only record. Refused polls are still audited. |
| Reset the idle timer on every request, as today | Rejected | A tab polling every 2 seconds would keep the server alive for ever. |
| Switch file filters off by blanking drivers by name | Rejected (D20) | Makes a stat-dirty LFS file read as modified, and `.clean` is ignored while `.process` is set. |
| Skip repositories that use Git LFS | Rejected (the user: never skipped) | Recorded as his decision with filters kept on (section 11). |
| Set only `core.fsmonitor=false` | Rejected | Probe 13: with the fsmonitor pair alone, a repo-set hook still ran and the index was still rewritten. Probes 18 and 22: with the round-2 settings, a signature program and a lazy fetch still ran. |
| Claim the closed routes are complete | Rejected | Each review round up to round 3 found another route (fsmonitor, then hooks, then `gpg.program` and the lazy fetch). Section 10 says "lower bound" until section 12 is filled. |

## Consequences

- **The server reads what the page names.** A page the server itself served, holding the token, can
  make the server read any directory the user can read and show repo, card and branch names and
  paths. The token limits this to those pages; inputs are validated before any syscall; reads are
  bounded in depth and time. The server writes only inside the store directory: the store,
  `ledger.json` and its lock.
- **Git writes nothing in a scanned repository**, on the evidence of probe 14 (the analyzer's
  commands, one fixture) and probe 26 (the lazy fetch, closed by `GIT_NO_LAZY_FETCH`). The scan's own
  git calls are `rev-parse` and `worktree list`; that they write nothing is reasoned, not measured,
  until criterion C9's whole-job check covers them.
- **Not covered:** a file filter (section 11); any config route outside the section 12 list; the 255
  keys with no entry of their own; `GIT_EXEC_PATH`, `GIT_DIR` and other environment variables the
  launcher sets; another git version.
- **A hostile repository's text is rendered as text only.** Status and run data come partly from
  scanned repositories; both pages render them without markup.
- **Nothing new reaches the session.** `/command` shrinks; `/ledger` never invokes cmux.
- **Unchanged:** the token's lifetime and handling, the collapsed `403`, no CORS headers, the CSP and
  `frame-ancestors 'none'`, the `Host` guard, failure bodies that echo nothing, the parent-death
  check, and one audit line per request apart from the accepted poll.
- **Git older than 2.45 disables analysis, not the board.** The cost is one `git --version` at
  startup.
- **Where the old spec changes.** Each rule below carries a one-line dated pointer to this record in
  `docs/features/tracking-feature-state.spec.md`, as that file's "Superseded paths" note (`:1158`)
  does for the rename:
  - `:404-411`, "Commands take no arguments, in v1 or after": still true of `/command`, arguments
    allowed on `/ledger` only.
  - `:541-544`, the definition of `sent=unknown`: widened by the catch-all (section 7).
  - `:691-703`, the three-row allowlist: now two rows.
  - `:933-1064`, criterion 13's expected request sets: both gain `/board-commands.js`. Criterion 13
    is an agent-run browser enumeration, not a pytest test (`test_server.py:16-20`), so no test
    module pins those sets.
  - `:1079-1096`, criterion 15: loses its `500` row for `reanalyze` and the board's reload after a
    successful Re-analyze; after a `200` the board goes to the Ledger.
  - `:1101`, "Command arguments of any kind": still true of `/command`.
- **Re-run on a git change.** When the pinned git changes, the section 12 check runs again; criterion
  C12 fails until it has.
