# Local Port Registry Enforcement

`~/.claude/PORTS.md` tracks every TCP port and host-level service (Docker
container or native/Homebrew) that a local project on this machine binds to.
It exists because a native service binding `127.0.0.1:<port>` specifically
beats a Docker container's wildcard bind on the same port and silently
shadows it — the container-backed project then fails with a confusing error
(wrong role/database, connection refused) instead of an obvious "port in
use," and the failure looks unrelated to the actual cause.

- **Before allocating a new local port** (a new Docker service mapping, a
  new dev-server port, a new native/Homebrew service) **read
  `~/.claude/PORTS.md` first.** If the port is already registered to a
  different project, flag the conflict to the user instead of proceeding
  silently.
- **Before starting or reconfiguring a system-level service** (Homebrew,
  a local daemon, anything not scoped to one project's Docker network)
  that binds a port another project might depend on, check the registry
  for a collision first.
- **When a port is allocated, add a row to `PORTS.md` in the same session**
  — do not defer it. An unregistered port is what causes the *next*
  collision.
- **When a port is freed** (service removed, project retired), remove its
  row instead of leaving it stale.
- This registry is reference data, not context to preload — read it only
  when doing port-affecting work, per `rules/context-and-token-discipline.md`.
