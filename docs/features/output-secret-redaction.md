---
phase: planning
model_tier: high
branch: none
---

# Output secret redaction — blank known secret values out of what a command printed

## Why

Two real credentials leaked out of `~/.terminal_aliases` into a session transcript on
2026-08-27. `secret-command-guard.sh` shipped in response, and it works — but it judges
the **text of a command**, never what came back. Every one of the seven shapes in that
card's Known-gaps table is the same defect wearing a different hat: put the read inside a
script file, behind a variable, behind a glob, or in a file not named `.env`, and the
classifier has nothing to match on. Widening the pattern list cannot close a gap whose
root cause is that the guard is looking at the wrong artefact.

This card looks at the other artefact. A `PostToolUse` hook receives the command's output
and can replace it before the model ever reads it. That closes the shapes whose defect is
*how the file was reached* — script file, variable, glob, `$(…)` — because output redaction
does not care about the route. It does **not** close the two whose defect is *which file*:
`cat foo.zshrc` / `cat my.env` and `cat config/prod.env` name files that are absent from the
Sources table below, so a known-values design never harvests them either. Five of seven, not
seven; the Known-gaps table records the remainder.

**The premise that said this was impossible is false. It is written in three places, and a
fourth site rests on a separate objection that is also obsolete.**
`docs/features/secret-command-guard.md:20-23` claims "a `PostToolUse` hook cannot
retroactively redact output already returned to the model", citing a survey of this repo's
own two `PostToolUse` hooks. The observation was right — both only ever add context — but
the inference generalised two local hooks to the whole platform. Measured false on CLI
2.1.251 (evidence in Verification below). The same claim is repeated verbatim at
`docs/decisions/0039-…:24-26` and `hooks/secret-command-guard.sh:10-15` — three sites for one
premise. Separately, `docs/features/secret-command-guard.md:78-79` rejects output scanning on
different grounds ("a pipe wrapper risks swallowing exit codes"), which is equally obsolete
here for its own reason: a `PostToolUse` rewrite is not a pipe wrapper and touches no exit
code. Four edits, three of them the same sentence.

## Shape

```mermaid
flowchart TD
    A[Model issues a Bash command] --> B{PreToolUse<br/>secret-command-guard.sh}
    B -->|blocks a named secret path<br/>in the command TEXT| X[Refused, nothing runs]
    B -->|allows| C[Command runs]
    C --> D[tool_response<br/>stdout / stderr]
    D --> E{PostToolUse<br/>output-secret-redaction.sh}
    E -->|harvest known values<br/>scan, blank exact matches| F[updatedToolOutput]
    F --> G[Model reads redacted text]
    F --> H[Transcript JSONL stores<br/>the redacted text]
    C -.command text persists verbatim.-> H
```

The dotted edge is the boundary between the two layers: this hook never touches the
command text, and the existing guard never touches the output. Neither replaces the other.

## Scope

1. **A new `PostToolUse` hook on matcher `Bash`**, `hooks/output-secret-redaction.sh`, with
   its classifier logic in `hooks/lib/redact-known-secrets.py`, matching the wrapper +
   python-lib split the sibling guard already uses.
2. **Harvest** the real secret values from an explicit list of files (below), per
   invocation, with no cache.
3. **Filter** harvested values so only plausible credentials become redaction targets.
4. **Scan** `stdout` and `stderr` for exact occurrences and replace them with a named
   placeholder.
5. **Emit** `hookSpecificOutput.updatedToolOutput` containing a mutated copy of the received
   `tool_response`.
6. **Correct the false premise** in the three sites that state it, plus the fourth site whose
   separate objection is also obsolete — one commit, with this card as the single authority
   the other three point at.

### Pinned versions

| Thing | Version | Why pinned |
| --- | --- | --- |
| Claude Code CLI | `2.1.251` | every platform behaviour below was measured against this build; `updatedToolOutput` is not documented publicly and its contract may move |
| python3 | `3.9.6` (macOS system, `/usr/bin/python3`) | the sibling guard resolves `python3` then `python` from PATH; 3.9 is the floor — no `match`, no `str.removeprefix` in hot paths |
| `sqlite3` | `3.51.0` (`/usr/bin/sqlite3`, 2025-06-12) | required to read gcloud's `credentials.db` / `access_tokens.db`; a line-oriented parser on those produces binary garbage |
| `jq` | `1.7.1-apple` | used by the registration self-test, per house convention |
| No third-party libraries | — | the hook runs on every Bash call; an import outside the stdlib is a supply-chain surface and a startup cost |

If `sqlite3` is absent the harvester **skips those two sources and records the skip** — it
must not fall back to a text parser, and it must not abort the whole harvest.

## Contracts

### Input — the `PostToolUse` payload

```yaml
session_id: string
transcript_path: string
cwd: string
hook_event_name: "PostToolUse"
tool_name: "Bash"
tool_input:
  command: string          # NOT redactable by this hook; see Known gaps
  description: string
tool_response:
  stdout: string           # truncated to 30000 chars BEFORE the hook sees it
  stderr: string
  interrupted: boolean
  isImage: boolean
  noOutputExpected: boolean
  # optional, present only in some cases — see the mutate-a-copy rule
  returnCodeInterpretation: string
  persistedOutputPath: string
  persistedOutputSize: number
  backgroundTaskId: string
  backgroundedByUser: boolean
tool_use_id: string
duration_ms: number
```

### Output — the replacement envelope

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "updatedToolOutput": { "...": "a mutated COPY of the received tool_response" }
  }
}
```

**The single most important implementation rule.** Build the replacement by copying the
received `tool_response` dict and overwriting `stdout`/`stderr` on the copy. Never construct
a fresh object from a fixed field list. Two independent readings of the field set disagree
(five fields observed from a simple `echo`, nine in the binary's schema), and the harness
validates the replacement against the Bash tool's `outputSchema`; **on mismatch it logs and
silently uses the original output**, which for a redaction hook means the secret ships.
Mutating a copy is correct under both readings.

### Placeholder format

`[REDACTED:<LABEL>]` — e.g. `[REDACTED:GITHUB_TOKEN]`.

`<LABEL>` is `[A-Z0-9_]+`, uppercased, with any other character replaced by `_`. Where a
harvested value has a key name, the label **is** that key name. Many mandated sources are
keyless, so each gets a fixed symbolic label — never a filename or path, which would leak
the source location (and, for the gcloud path, an email address):

| Source | Label |
| --- | --- |
| `~/.ssh/id_*` (PEM body) | `SSH_PRIVATE_KEY` |
| `~/.vault-token`, `*.token` | `VAULT_TOKEN`, `SERVICE_TOKEN` |
| `~/.pgpass` field 5 | `PGPASS_PASSWORD` |
| `~/.netrc` / `~/.authinfo` password token | `NETRC_PASSWORD` |
| `~/.git-credentials` line, and its URL password component | `GIT_CREDENTIAL` |
| a URL password slot inside any keyed value | the enclosing key name, suffixed `_URL_PASSWORD` |
| a base64-decoded `auths.*.auth` from `~/.docker/config.json` | `DOCKER_REGISTRY_AUTH` |
| anything else keyless | `UNNAMED_SECRET` |

Two labels colliding is harmless; a label revealing where the value lives is not.

Named, not opaque. An opaque `[REDACTED]` produces exactly the undiagnosable failure this
work exists to avoid: the model cannot tell a redaction from a broken command and retries in
a loop. The key name is a small disclosure (it confirms such a credential exists locally, in
a transcript that is already local) and is worth the diagnosability. **Emit the key name
only — never the value, never a prefix, and never a length hint**, because a length hint
measurably narrows a brute-force space.

## Sources to harvest

An **explicit list, never filesystem discovery.** A `find` over `$HOME` at depth 4 for
`.env` files did not complete in two minutes and was killed; discovery is not viable inside
a hook that runs on every command.

| Group | Members |
| --- | --- |
| zsh | `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.zlogin`, `~/.zlogout` (honour `$ZDOTDIR`) |
| bash | `~/.bash_profile`, `~/.bash_login`, `~/.profile`, `~/.bashrc`, `~/.bash_aliases`, `~/.bash_logout` |
| sourced fragments | every file reachable by a `source`/`.` directive from the above — **required, not optional**: `~/.terminal_aliases` is in no shell's native load order, so a harvester that skips chain-following misses the file that actually leaked |
| env | `.env`, `.env.local`, `.env.<stage>` (incl. `.env.test`, `.env.ci`), `.envrc` |
| INI/other | `~/.aws/credentials`, `~/.netrc`, `~/.pgpass`, `~/.npmrc`, `~/.my.cnf`, `~/.pypirc`, `~/.git-credentials` |
| YAML/TOML/XML | `~/.config/gh/hosts.yml`, `~/.kube/config`, `~/.gem/credentials`, `~/.bundle/config`, `~/.cargo/credentials.toml`, `~/.m2/settings.xml` |
| JSON | `~/.docker/config.json`, `~/.claude.json`, `~/.config/gcloud/legacy_credentials/*/adc.json`, `~/.aws/sso/cache/*.json`, `*/Application Support/*/credentials*.json` |
| whole-file secrets | `~/.ssh/id_*` (excluding `*.pub`), `~/.vault-token`, `*.token` |

**Excluded, and the reason matters.** `.env.example`, `.env.template`, `.env.sample`,
`.env.dist`, `.env.defaults`, `.env.schema`, `.env.vault` are excluded **as a
false-positive control, not a secrecy control** — they hold placeholders like `changeme`
and `your-api-key-here`, and harvesting those would blank those literals out of all command
output forever. Also never harvested: `~/.ssh/*.pub`, `~/.ssh/known_hosts*`,
`~/.docker/daemon.json`, `/etc/paths` and `/etc/paths.d/*` (PATH fragments — harvesting them
blanks directory names out of every command), and all Apple-shipped `/etc/*`.

**Format traps** that a naive implementation gets wrong: `.npmrc` is INI, not JSON;
`~/.kube/config` and `~/.config/gh/hosts.yml` are YAML, not JSON; `~/.pgpass` is
colon-positional (the secret is field 5); gcloud's `credentials.db` and `access_tokens.db`
are **SQLite**, where a line-oriented parser produces short binary garbage — the worst
possible candidate values. Read those with `sqlite3` in read-only mode or not at all.

**Never log a scanned path.** `~/.config/gcloud/legacy_credentials/<google-account>/adc.json`
embeds an email address in its directory name; a hook that logs which files it read writes
that address into its log. Log counts and hashes, not paths.

## The filter

Harvesting every value from every profile and config would collect `true`, `8080`,
`localhost`, `main`, and the username, and then blank those words out of all output — a
failure that is far more disruptive, and far harder to diagnose, than the leak it prevents.

**Entropy cannot be the filter, and this is measured rather than argued.** Shannon entropy
over a string's own characters measures repetition, not unpredictability, and is capped at
log₂(length):

| Value | Entropy (bits/char) | Actually |
| --- | --- | --- |
| 64-char hex token | 3.82 (mean of 500 sha256 digests; min 3.54, max 3.96) | a real secret |
| `s3cr3t` | 2.25 | a real secret |
| `localhost` | 2.73 | innocent |
| a real URL (35 chars) | 4.08 | innocent |

Secrets span **2.25–3.82**; innocent values span **2.73–4.08**. The two ranges overlap
across [2.73, 3.82], so no single threshold separates them: any cut high enough to exclude
`localhost` also excludes `s3cr3t`, and any cut low enough to keep the hex token also keeps
the URL. At H≥4.0 you keep 9/19 secrets; at H≥2.5 you wrongly blank 19/23 innocent values.

⚠️ **Correction, and the reason it is left visible.** An earlier revision of this table
recorded the hex token at 2.43 and argued it "scores lower than `localhost` because hex has
only 16 symbols". Both were wrong — a 16-symbol alphabet caps entropy at log₂(16) = 4.0, and
a random hex string lands just under it. The compliance judge caught the figure and it was
re-measured here (`cache/spike/ent.py`). The conclusion is unchanged, but it now rests on an
overlap rather than on an inversion that does not exist. Use a **character-class count** (how many of
lower/upper/digit/other appear) instead — cheap, and it does not pretend to measure
randomness.

### The rule

A harvested value becomes a redaction target when **either** arm fires, and the denylist
overrides both.

- **Strong evidence** — the key name matches the credential pattern, **or** the value sits
  in a URL password slot → minimum length **6**, no character-class test.
- **Weak evidence** — no key match → minimum length **24** **and** at least 2 character
  classes.

Key pattern, case-insensitive:
`TOKEN | SECRET | PASSW(OR)?D | _PW\b | PASS\b | CREDENTIAL | PRIVATE | APIKEY | API_?KEY |
ACCESS_KEY | AUTH | SESSION | SIGNING | CLIENT_SECRET | DSN | _PAT\b | PAT_ | SALT | CERT |
LICENSE | WEBHOOK`

Measured on a 41-entry corpus:

**Every row below is in-sample.** All five were scored on the same 41-entry corpus the
winning rule was tuned against, so the table ranks the candidates but predicts nothing about
unseen input.

| Rule | Secrets caught (in-sample) | Innocent wrongly blanked (in-sample) |
| --- | --- | --- |
| key name only | 15/17 | 3/24 |
| length floor only | 14/17 | 7/24 |
| AND | 12/17 | 1/24 |
| OR, symmetric thresholds | 17/17 | 9/24 |
| **OR, asymmetric (this rule)** | **17/17 — fitted** | **0/24 — fitted** |

AND is disqualified by two shapes it structurally cannot see: `MY_THING=ghp_…` (a real
token under an innocent key name) and `DB_PASSWORD=hunter2` (7 characters, below any useful
floor). Symmetric OR is disqualified by 9 false blanks.

⚠️ **17/17 · 0/24 is a fitted number.** The rule was tuned on the corpus it is scored
against, so it is not a generalization estimate. Re-measuring against a held-out corpus is a
task below, not an optional extra.

### Two rules the measurements forced

1. **Decompose URLs; never harvest one whole.**
   `DATABASE_URL=postgres://user:hunter2@localhost:5432/db` must yield `hunter2`, not the
   URL. Harvesting the URL blanks every log line that names your database host. The password
   slot counts as positional evidence equal to a key-name match — without that, `hunter2`
   falls to the 24-character floor and is missed.
2. **"contains a slash → it is a path" is wrong.** That test drops
   `AWS_SECRET_ACCESS_KEY`, because AWS secret keys are base64 and legitimately contain `/`.
   Anchor the path test at the start: `^(/|~/|\./|\$)`.

### Denylist — never blanked, whatever the key says

Exact set `{true, false, yes, no, on, off, null, none, default, localhost, 127.0.0.1,
0.0.0.0, ::1, main, master, develop, head, development, production, staging, test, debug,
info, warn, error}`, plus the username, repo name, hostname, and current branch names;
anything starting `/ ~ ./ ../ $ -`; and all-digit values.

**Weak arm only, additionally:** single dictionary words from `/usr/share/dict/words`
(218,004 entries ≥6 chars), and — critically — `^[0-9a-f]{7,}$`, UUIDs, and `sha256:`
digests. Blanking a pinned git SHA corrupts every subsequent `git log`, which is precisely
the maddening failure mode this filter exists to prevent. Adding those three shapes fixed 4
of 5 such false blanks with zero new misses.

## Runtime

**Re-read and re-parse every invocation. No cache, no daemon, no hashes.** The premise that
parsing is too slow is false, and not narrowly:

| Operation | Measured |
| --- | --- |
| `python3 -c pass` | 16 ms |
| `python3 -c 'import json,re,os,sys'` | 22 ms |
| **read + parse the real corpus** (3 files, 21,846 bytes, 58 assignments) | **0.16 ms** |
| parse 200 KB synthetic shell corpus | 1.24 ms |
| parse 1 MB synthetic shell corpus | 6.35 ms |
| in-hook total (parse 0.12 + 40-needle scan 0.102) | ≈ 0.25 ms |

Harvesting costs 0.7% of the interpreter startup already being paid. Every caching option
therefore trades a measurable security regression for an unmeasurable speedup:

- **Plaintext cache at 0600** — concentrates every credential on the machine into one file,
  in one format, at a predictable path. Today an attacker must find and parse N scattered
  files; afterwards they read one. Rejected: it makes the thing this hook prevents *easier*,
  to save 0.16 ms.
- **Salted hashes + lengths** — structurally impossible, not merely slow. You cannot
  substring-search for a value you hold only a hash of; you must hash every window of every
  candidate length. For 100 KB of output across 22 realistic credential lengths that is
  2,251,931 windows: **556 ms** (sha256), 678 ms (blake2b), 2,402 ms (HMAC), against
  **0.45 ms** for naive replacement — ~1,200× slower. A Rabin-Karp rolling hash restores
  O(1) per window only for an *unkeyed* polynomial hash, which is brute-forceable and defeats
  the reason for hashing. And a hash hit is unconfirmable: holding no value, a collision
  forces redacting innocent output with no way to check.
- **mtime-keyed cache** — the only defensible cache, but it still writes plaintext to disk
  and adds a real bug class: editors and `direnv` commonly rewrite `.env` files with the
  *same* mtime, so a stale cache silently stops redacting a **rotated** secret.
- **Daemon** — memory-only is better hygiene, but it adds a lifecycle, an IPC surface
  readable by any local process, and a liveness failure that fails open. Disproportionate to
  a 0.16 ms problem.

**Growth is bounded by a budget, not a cache**, with three named constants:

| Constant | Value | Why this value |
| --- | --- | --- |
| `MAX_TOTAL_BYTES` | 2 MB | ~95× the measured real corpus (21,846 bytes); at 1 MB parsing still costs 6.35 ms, so 2 MB stays inside one interpreter startup |
| `MAX_FILE_BYTES` | 256 KB | `~/.claude.json` is 92,847 bytes — the largest real source — so 256 KB clears it with headroom while excluding runaway logs |
| `MAX_SOURCE_DEPTH` | 8 | `~/.zshrc` → oh-my-zsh → `lib/*.zsh` → a custom fragment is 4 levels; 8 doubles it. Enforced together with a visited-inode set, since dotfile repos contain `source` cycles |

On exceeding `MAX_TOTAL_BYTES` the harvester stops reading further sources and proceeds with
what it has — it does **not** abort, because an abort would mean no redaction at all.

## Matching mechanics

- **Exact substring, case-sensitive, on raw bytes**, plus a defined set of encoded forms.
  Exact matching already survives shell quoting and JSON escaping for free. Hex is skipped as
  rare for credential echo. **Never case-fold** — folding breaks base64 matching, where case
  is data, and blanks far more innocent text.

  "base64" is not one string, and leaving it unspecified is a silent coverage hole. Generate:

  | Needle | Form |
  | --- | --- |
  | 1 | the raw value |
  | 2–4 | RFC 4648 **standard** alphabet (`+/`), padded, at byte offsets 0, 1 and 2 — a value embedded mid-stream encodes differently per alignment, and only one of three would otherwise match |
  | 5–7 | RFC 4648 **url-safe** alphabet (`-_`), padded, same three offsets |
  | 8 | standard alphabet, **unpadded** (trailing `=` stripped) |
  | 9 | `%`-encoding per RFC 3986, encoding every character outside `A-Za-z0-9-._~` |

  For offsets 1 and 2, match only the **interior** run of the encoded form — the first and
  last encoded character are contaminated by neighbouring bytes and must be dropped. If an
  offset variant falls below the 20-character floor after that trim, discard it rather than
  lowering the floor. Nine needles at ~0.011 ms each keeps the scan near the measured
  0.102 ms for 40 secrets.
- **Minimum match length 20 characters**, including for partial matches. Allow any ≥20-char
  contiguous substring of a harvested secret, which covers line wrapping and mid-truncation.
  False-blank rates at 2,000 Bash calls/day and ~102,400 windows per scan:

  | Match length | with a 4-char vendor prefix (`ghp_`) | with a 13-char prefix (`sk-ant-api03-`) |
  | --- | --- | --- |
  | 8 | **13.9 false blanks/day** | ~2×10⁸/day |
  | 12 | 9.4×10⁻⁷/day | ~2×10⁸/day |
  | 16 | negligible | 859/day |
  | 20 | negligible | 5.8×10⁻⁵/day |

  The honest consequence: **the first-8-characters form that many tools print cannot be
  caught safely** — a 4-character vendor prefix leaves only 4 random characters. Truncated
  tokens go unredacted, and the spec says so rather than implying coverage.
- **Scan `stdout` and `stderr`, always.** Credentials surface in stderr at least as often as
  stdout, because auth failures echo the token back.
- **`isImage: true` → return the output unmodified.** The payload is base64 image data; a
  spurious match would corrupt the image.
- **Redact longest needle first**, so an overlapping short value cannot blank half a longer
  one.
- **Use `str.replace` in a loop, not one compiled alternation** — 100 KB with 40 secrets:
  **0.45 ms** naive vs **3.31 ms** compiled regex, because `str.replace` is a tight C
  `memmem` and a 40-branch alternation is not.

## Failure direction

**This is only half ours to choose, and the spec must not claim otherwise.** There is no
"abort the tool result" signal at `PostToolUse`. Measured — the canary reached the model in
every failure case:

| Hook behaviour | Canary leaked? |
| --- | --- |
| correct envelope | no — redacted |
| crash (exit 1) | **yes** |
| malformed JSON on stdout | **yes** |
| `updatedToolOutput` carrying only `stdout` | **yes** |
| `updatedToolOutput` as a bare string | **yes** |
| exit code 2 | **yes** |

**Fail closed by construction, inside the band we control.** Wrap the entire hook body in a
catch-all that, on any internal exception, emits a **well-formed envelope with every field
present** whose `stdout`/`stderr` read `[redaction hook failed — output withheld]`. That
turns an internal error from a silent leak into a visible, self-describing blank.

Outside that band — `python3` missing, hook timeout, process killed, the harness's own
schema rejection — the platform falls back to the original output and the secret is printed.
Nothing the hook can do changes that.

**Why fail-closed here and fail-open in the sibling.** `secret-command-guard.sh` fails open
because it sits at `PreToolUse` on nearly every Bash call, where a fail-closed bug is a
shell ban. Here the command has already run and its side effects have landed; only the text
is withheld, and a re-run recovers it. A bug in this redactor is loud and quickly diagnosed
— much the better failure than a silent leak.

## Scenarios

```gherkin
Feature: Redact known secret values from Bash output

  Scenario: The original incident shape, reached through a script file
    Given ~/.terminal_aliases assigns API_TOKEN a 40-character value
    When a command runs "bash diag.sh" and that script prints the environment
    Then the model receives "[REDACTED:API_TOKEN]" in place of the value
    And the transcript JSONL stores the redacted text, not the value

  Scenario: The value is reached through a variable, defeating the PreToolUse guard
    Given ~/.zshrc assigns GH_PAT a 40-character value
    When a command runs 'F=~/.zshrc; cat "$F"'
    Then the value is replaced by "[REDACTED:GH_PAT]"

  Scenario: A secret in stderr
    Given a harvested value V under the key AWS_SECRET_ACCESS_KEY
    When a command fails and writes V to stderr
    Then stderr is scanned and V is replaced

  Scenario: A base64-encoded occurrence
    Given a harvested value V
    When output contains base64(V) rather than V
    Then base64(V) is replaced

  # Bad-path and edge scenarios

  Scenario: A pinned git SHA is not blanked
    Given a harvested weak-evidence value that is a 40-character hex string
    When "git log --oneline" prints commit SHAs
    Then no SHA is replaced
    And the weak-arm hex denylist is the assertion that fires

  Scenario: A placeholder from .env.example is never harvested
    Given .env.example contains API_KEY=your-api-key-here
    When any command prints the words "your-api-key-here"
    Then the text is unchanged
    And .env.example contributed no needle to the scan

  Scenario: A short innocent value under a secret-sounding key is still blanked
    Given a shell profile assigns AUTH_MODE the value "oauth2"
    When a command prints "oauth2"
    Then it IS replaced, because the strong arm has a floor of 6 and no class test
    # This is an accepted false positive, recorded here rather than hidden

  Scenario: The hook crashes internally
    Given the classifier raises an unexpected exception
    When the hook runs
    Then it emits a well-formed envelope with every received field present
    And stdout and stderr read "[redaction hook failed — output withheld]"

  Scenario: The replacement must not drop optional fields
    Given a tool_response carrying backgroundTaskId and persistedOutputPath
    When the hook redacts stdout
    Then the emitted updatedToolOutput still carries both fields
    And the harness does not log an output-shape mismatch
    # The single most likely implementation bug; leaks with no error surfaced

  Scenario: Image output is passed through untouched
    Given tool_response.isImage is true
    When the hook runs
    Then the hook returns no replacement at all

  # NOT YET A REQUIREMENT — blocked on Open Question 1. Written here so the shape is
  # reviewable, but it must not be implemented until the question is answered, and the
  # mechanism is deliberately absent from Scope, Contracts and Runtime until then.
  @pending-open-question-1
  Scenario: An exempted command is not scanned
    Given a command prefixed with SECRET_EXEMPT=<reason>
    When the command runs and prints a harvested value
    Then the output is returned unmodified
    And the exemption is logged
```

## Non-goals

- **Redacting the command text.** Structurally impossible here: `tool_input.command` is a
  sibling of `tool_response`, and `updatedToolOutput` replaces only the latter. That remains
  `secret-command-guard.sh`'s job. The two hooks are complementary, not redundant.
- **Shape/regex detection of unknown credentials** (`sk-…`, `AKIA…`, JWT, PEM). Deliberate
  user decision: known values only. Revisit only with evidence that the known-value list is
  routinely incomplete.
- **Non-Bash tool surfaces** — `Read`, `Edit` diffs, MCP results. `updatedMCPToolOutput` is a
  separate field with a separate contract.
- **Retroactively redacting anything already in the session.** Forward-only, per tool result.

## Known gaps — measured, disclosed, not fixed

This hook raises the floor on the accidental echo of a **known, listed, unrotated,
unencoded** credential. It is **not a security boundary**, and no deny message or document
may claim otherwise.

| Shape | Why it is not covered |
| --- | --- |
| A secret in the command text itself | `tool_input.command` is a sibling of `tool_response`; `updatedToolOutput` cannot reach it. The PreToolUse sibling's remaining job. |
| A secret in a file nobody listed | "Known values only" means exactly that. Discovery is not a fix — a `find` over `$HOME` at depth 4 did not finish in 2 minutes. |
| A secret fetched mid-command | `vault read`, `aws sts assume-role`, `gh auth token`, `op read` never existed in a file at harvest time. Large and **growing** — short-lived fetched credentials are the modern pattern. |
| A credential rotated by the command that prints it | The new value did not exist when the hook harvested, moments earlier. |
| A secret straddling the 30,000-char truncation | `stdout` is cut mid-token before the hook sees it; the fragment falls below the 20-char floor. Content past 30,000 chars never reaches the model either, so it is not itself a leak. |
| A keychain-backed credential | `~/.docker/config.json` is 78 bytes with a `credsStore`; the value lives in Keychain. Same for `~/.authinfo.gpg`, `~/.mylogin.cnf`, Chrome's `Login Data`. No plaintext exists to harvest. |
| Truncated tokens (first 8 chars) | Catching them costs ~13.9 false blanks/day with a 4-char vendor prefix. Deliberately out of reach at the 20-char floor. |
| Encodings beyond raw/base64/URL | hex, gzip, encrypted, chunked across lines, one character per line. |
| A future sibling hook that also rewrites output | `PostToolUse` hooks run **in parallel on the original output, last write wins by completion time**. A second rewriting hook on `Bash` would race this one non-deterministically and could restore the unredacted text. No hook can defend against this; it must be a standing rule. |
| Any value below the strong arm's 6-char floor, or a weak-arm value under 24 chars with a non-matching key | e.g. `BUILD_ID=a1b2c3d4`. The direct, accepted price of not corrupting git SHAs and short innocent values. |

## Verification plan

1. **Reproduce the platform contract before writing the hook.** The `updatedToolOutput`
   behaviour is undocumented publicly and was read from the binary and then measured. Re-run
   the end-to-end spike on the CLI version in use and confirm: the model receives the
   replacement, and the transcript JSONL stores the replacement.
2. **Falsify each failure row.** Build a deliberately broken hook for each row of the
   failure-direction table and confirm the canary leaks — a fail-open you have not seen fail
   is a fail-open you have not measured.
3. **Synthetic fixtures are mandatory, not optional.** A bounded search — `find` for `.env*`
   across `~/.worktrees` and `~/Documents`, `-maxdepth 5`, `node_modules` excluded — returned
   **zero files**, and most conventional credential paths listed in Sources were measured
   absent. That is the scope of the claim: **no `.env` file was found within those two trees
   at that depth.** A separate unbounded `find` over `$HOME` at depth 4 was killed at two
   minutes without completing, so "zero anywhere on this machine" is *not* established and
   must not be written down. Either way the consequence holds: a suite run only against the
   real home directory would report a perfect score with most parsers never executed. Every
   format in the sources table needs a fixture.
4. **Re-measure the filter against a held-out corpus** built after the rule is frozen. The
   17/17 · 0/24 figure is fitted and must not be quoted as a generalization estimate.
5. **A dedicated regression test for the dropped-field bug** — assert that a `tool_response`
   carrying optional fields round-trips them all.
6. **Registration self-test plus a mutation control**, per house convention
   (`hooks/secret-command-guard.test.sh:226-255`): jq the real `settings.json` for
   `.hooks.PostToolUse[]?.hooks[]?.command`, then re-run the identical query against a copy
   with the hook deleted and assert it reports missing.
7. **A test asserting this is the only `updatedToolOutput` emitter** registered on Bash, so
   the parallel-clobber hazard fails loudly the day someone adds a second one.

## Tasks

- [ ] 1. Re-measure the platform contract on the current CLI; record the version measured.
- [ ] 2. Write the failing test suite `hooks/output-secret-redaction.test.sh` — harness
      boilerplate from `hooks/secret-command-guard.test.sh:15-64` plus `assert_stdout` from
      `hooks/lib/guard_test_helpers.sh:31-38`; a `payload()` carrying `tool_response` and
      `hook_event_name:"PostToolUse"`.
- [ ] 3. Build the synthetic fixture tree — one file per format in the sources table.
- [ ] 4. Implement the harvester: explicit file list, source-chain following with a depth cap
      and visited-inode set, per-format parsers, 2 MB budget.
- [ ] 5. Implement the filter exactly as specified, including both URL rules and the weak-arm
      SHA/UUID denials.
- [ ] 6. Implement the scanner: 3 needles, longest-first, `str.replace` loop, both streams,
      `isImage` passthrough.
- [ ] 7. Implement the wrapper and the catch-all that emits a withheld-output envelope.
- [ ] 8. Register in `settings.json` under `PostToolUse` / matcher `Bash`.
- [ ] 9. Correct the false premise in all four sites in one commit; make this card the single
      authority the other three point at.
- [ ] 10. Add the parallel-rewrite hazard to `rules/gates.md`.
- [ ] 11. Build the held-out corpus and re-measure the filter; record both numbers.
- [ ] 12. Write the ADR. **Re-fetch `origin` and re-check the next free number first** — the
      candidate `0040` came from a snapshot roughly a day stale, `git fetch origin` failed
      with `Permission denied (publickey)` in that environment, and two `0026-*` files already
      coexist on `origin/main`, so collisions here are real rather than hypothetical.

## Open questions for the user

1. **Should `SECRET_EXEMPT` also disable output redaction?** The sibling guard uses it to
   permit a blocked command. Reusing it here means one flag turns off both layers, which is
   simple but blunt. My recommendation: **yes, reuse it** — a user who has justified reading
   a secret file does not want the output blanked either, and a second flag name is a
   memorisation cost for a rare case.
2. **Is the strong arm's 6-character floor acceptable?** It will blank short innocent values
   under credential-sounding keys (the `AUTH_MODE=oauth2` scenario). My recommendation:
   **accept it** — missing `DB_PASSWORD=hunter2` is the worse error, and the denylist already
   catches the common English-word cases.

## Not verified

- The stdout/stderr split on a **failing** command was not measured; the nested test session
  rewrapped the command differently on each attempt and then declined to issue it verbatim.
  The design scans both fields, which is correct under either behaviour, but the underlying
  split remains unmeasured.
- `persistedOutputPath` — whether a spilled-to-disk output file is also rewritten when
  `stdout` is replaced. Subagent measurement shows `stdout` is truncated to 30,000 chars
  before the hook sees it, which suggests the spill happens elsewhere, but the interaction
  was not tested directly.
- **Provenance of every number in this card, stated once so no table reads as first-hand.**
  Reproduced independently by me: the entropy figures only (`cache/spike/ent.py`, after the
  compliance judge caught an error in them). Measured by me directly: the `updatedToolOutput`
  replacement, its absence from the transcript JSONL, and the parallel/last-write-wins
  clobber. **Everything else — the runtime table, the hashing costs, the false-blank rates,
  the 30,000-char truncation, the failure-direction matrix, and all filter figures — comes
  from subagent measurement that I have not reproduced.** The filter figures additionally
  come from a corpus the same agent tuned against.
- The claim that this hook closes five of the sibling card's seven gap shapes is a reading of
  that card's table, not a measurement. It should be re-derived against the shapes as they
  stand when implementation starts.
