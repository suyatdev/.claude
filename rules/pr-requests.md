# Pull Request & Branching Etiquette

- **Default Branch Safety:** Never commit code directly to the default branch (`main`/`master`). The only exception is committing `CODING_MEMORY.md` updates after a brainstorming session (see Brainstorm-Then-Branch Rule below).
- **Branch Naming**: Enforce `feature/ticket-id-summary`, `bugfix/ticket-id-summary`, or `chore/summary`.
- **Commit Messages**: When running the `commit` slash command, format messages via the Conventional Commits specification (e.g., `feat(api): add validation checks`).
- **PR/Remote First Workflow:** Before any pull/sync step, first check whether an open PR already exists for the current repo/branch and whether a remote already exists for pushing updates.
- **PR/Remote Creation Rule:** If no PR/remote exists yet, create the remote/PR first, then record that PR state in memory for future runs.
- **PR Descriptions**: Every PR output must explicitly outline:
  1. A description of all changes in layman's terms.
  2. Why the change was made.
  3. Links to related PRs, if any (otherwise state "None").
  4. Screenshot(s) of the changes, if the PR is UI-related (otherwise state "N/A - non-UI change").
  5. Step-by-step testing instructions used to verify the changes.
- **PR Memory Tracking:** Track PR status per repository/project in `CODING_MEMORY.md`.
- **PR Memory Fields:** For each repository, store: repo identifier, branch name, remote name/url, PR URL or number, and whether the PR is currently open.
- **Branch Implementation Memory:** For each active branch, maintain a branch-specific implementation log in `CODING_MEMORY.md` that captures what is already implemented, what is pending, and the latest checkpoint.
- **PR Continuity Artifact Rule:** Commit and push branch implementation memory updates as part of the same branch so continuity context is included in the PR.
- **Branch Resume Rule:** Before continuing work on an existing branch, read the memory associated with that branch in `CODING_MEMORY.md` and resume from the latest checkpoint.
- **Working Branch Freshness Rule:** If already on a working branch, make sure that branch is up to date with its tracked remote/base before adding more implementation commits, while still following the existing PR/remote-first checks.
- **Main-To-Feature Rule:** If currently on `main`/`master`, first update that default branch, then conduct the brainstorming session, then create and switch to a new feature branch before any implementation.
- **Brainstorm-Then-Branch Rule:** Brainstorming/planning is done while on `main`/`master`. When the brainstorm is complete, commit the updated `CODING_MEMORY.md` (and only `CODING_MEMORY.md` — no code) to `main`/`master`, then checkout the feature branch. This ensures every future branch forked from `main` inherits the full brainstorm context automatically.
- **No Pull-First Rule:** Never start by pulling from remote to "update first."
- **Existing PR Update Rule:** If an open PR and remote already exist, update that existing branch/PR.
- **First PR Persistence Rule:** If no PR exists yet, push once, create the PR, and immediately save this first-created PR metadata in `CODING_MEMORY.md` for future reference.
- **Future Session Check Rule:** On later sessions, consult saved PR metadata before deciding whether any pull action is necessary.
- **Verification Rule**: Never approve or request a PR generation unless local tests pass successfully first.
