---
name: vetting-dependencies
description: Use before proposing or running a package install, a dependency edit, or an import of a package not yet installed — run the vetter, relay its report with a ✅/⚠️/⛔ call. Not for reviewing code you wrote (see writing-secure-code).
---

# Vetting Dependencies

A package you install runs with your permissions the moment it lands, so "it looked right" is not a check. Mark's rule (2026-10-09): before any package, module or library is installed or used as a dependency, it is vetted and scanned. Two things carry that rule. `hooks/dependency-guard.sh` stops an install it can see and asks Mark; this skill is the part no hook can see: running the vetter, telling Mark what it found, and the judgment checks below. Design, thresholds and the full decision table: `docs/features/dependency-vetting-guard.md` — read it for detail, not at session start.

**State of the hook.** `dependency-guard.sh` is registered in `settings.json` and runs from the primary checkout once that is merged and pulled there; it stops the install it can see. It is a speed bump, not a boundary, so follow this procedure anyway.

**What the guard is.** A speed bump. The vetting record is written by the agent and so is forgeable from inside the session; Mark's approval at the permission prompt is the control. Never describe a record as proof a package is safe. `VET_EXEMPT=<reason>` is Mark's bypass, not yours: do not add it to a command on your own authority.

## The flow (vet, then install)

1. The guard denies the first install attempt and prints the exact vetter command. Copy that command from the denial message rather than retyping it — a retyped name is where a typo gets in.
2. Run it. The usage is `<vetter-path> <ecosystem> <name> <version>`, with `hooks/bin/vet-dependency` as the vetter. Ecosystems: `npm`, `pypi`, `crates.io`, `go`, `rubygems`, `homebrew`. For `homebrew` give no version — the vetter reads the current stable one itself.
3. A non-zero exit means no record was written (OSV unreachable, package or version not found, bad argument). Report that to Mark as it is. A "not found" is often a typo — go to check (a) before anything else.
4. On success (exit 0) the vetter prints a one-line summary, an `INCOMPLETE:` line when checks did not run, and the paths after `report:` and `record:`. Read the report file at that path and relay it (next section) in chat, with your recommendation, **before** retrying the install.
5. Retry the install. The retry reaches Mark's permission prompt; his answer decides.

A version must be exact (`zod@3.23.8`, not `latest` or `^3`); the guard refuses anything else and the message names the spelling for that tool.

## The report you relay

Plain language first: what the package is for, then the verdict, then the evidence. Use this layout:

- **Verdict line** — ✅ / ⚠️ / ⛔, the ecosystem, name and exact version.
- **Why** — one sentence naming the checks that decided it.
- **Checks table** — every check and its result as the report states it: `direct_vulns`, `transitive_vulns`, `deprecated`, `typosquat`, `release_age`, `popularity`, `install_scripts`, `source_link`. Quote the raw values the report gives (counts, ages, downloads), never a figure it does not contain.
- **Advisories** — every advisory ID with its `https://osv.dev/vulnerability/<id>` link, and the transitive counts (packages scanned, packages with advisories).
- **Not run** — every check marked `not_run` and why. A check that did not run is a gap, not a pass; say "not checked", never "clean".
- **Alternative** — required for ⛔ (below).

## The recommendation

- ⛔ **Do not install.** Any check came back `stop` (an advisory, a deprecated or yanked release, a name that looks like a much more popular package). Give the reason in the report's own words and name a safer alternative — see check (b).
- ⚠️ **Install only if Mark accepts the named risk.** No `stop`, but one or more `caution` (brand-new release, low downloads, install scripts, no source link, a similarly named package exists). Say which, and what each means in practice.
- ✅ **No stop and no caution.** If the record is `complete: false` (it always is for Homebrew, and for PyPI, crates.io, Go and RubyGems, whose transitive scan is not run in v1), name the checks that did not run in the same sentence as the ✅.

A ✅ means "nothing this vetter can see", not "safe". Say so when it matters.

## Judgment checks no hook can see

Each comes from Mark's request (verbatim in the card's `## Mark's request`).

**(a) Spelling** — pillar 1, "Typosquatting Prevention: Double-check the exact spelling of every library, package manager command (npm, pip, cargo, etc.), and import statement." Before you propose or run any package name, package-manager command or `import` line, re-check each spelling against the registry's own entry (for npm, `npm view <name>`; for the others, the registry's page or JSON endpoint). A name that exists is not thereby the right one: typosquats are published precisely so that a misspelling resolves. Compare it with what Mark asked for and with the project's official documentation, character by character, including `-` vs `_` and doubled letters. The vetter's typosquat check compares download counts for npm only; for other ecosystems it reports only that a similar name exists, so the spelling check is yours.

**(b) Provenance** — pillar 1, "Validated Packages Only: Only recommend or use highly trusted, actively maintained, and official libraries. Never suggest obscure, deprecated, or unverified packages." Prefer the library the language or framework's own documentation names. Do not propose a package you cannot point to a maintained source repository for. When the vetter returns ⛔ or several ⚠️, name an established alternative — one the official documentation recommends or that the ecosystem's own tooling ships — and say why it is safer, or say plainly that you know of none and leave the decision to Mark. Do not invent an alternative to fill the slot.

**(c) Scanner list** — pillar 4, "Automated Scanning Recommendations: Whenever providing a list of dependencies (e.g., package.json, requirements.txt), explicitly list the specific automated scanning tools … the user should run." Whenever you present a list of dependencies — a `package.json` or `requirements.txt` you write, or a proposed stack — end it with the scanners to run on it: `osv-scanner` for every ecosystem, `npm audit` for npm, `pip-audit` for PyPI. Name them; do not claim you ran them. Check with `osv-scanner --version`; if the command is missing, say so rather than imply a scan happened. (Snyk and SonarQube, named in the request, are left out on purpose: Snyk needs a hosted account and SonarQube scans source code, not dependencies.)

**(d) Imports** — pillar 1, "…before any packages, modules, libraries … are installed **or used as a dependency**." Writing `import x` (or `require`, `use`, `from x import`) for a package that is not installed commits the project to it just as an install does, and no hook sees an `import`. Before you write the import or propose the install, run the vetter on that package, relay the report, then propose the install. Check the spelling of the `import` against the registry first: the import name and the package name often differ.

## Fail closed

If you cannot run the vetter, or it errors, say so and stop. Do not substitute your own memory of the package, do not skip to the install, and do not add `VET_EXEMPT`. With no record the guard keeps the install denied, which is correct.

<!-- Triggers (verified before shipping):
positive: "add zod to this project", "pip install requests", "import pandas in this script" (pandas not installed)
negative: "review this SQL query for injection" (that's writing-secure-code), "sandbox the agent that runs this code" (that's securing-agentic-systems), "npm run build" (no install, no new dependency) -->
