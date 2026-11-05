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
