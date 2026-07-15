---
name: allocating-local-ports
description: Use before allocating a new local port — a Docker service mapping, a dev-server port, or a native/Homebrew service — or before starting/reconfiguring a system-level service that might collide with one. Reads and updates PORTS.md, the machine-wide port registry. Not for cloud or production port/firewall configuration.
---

# Allocating Local Ports

`~/.claude/PORTS.md` tracks every TCP port and host-level service (Docker container or native/Homebrew) that a local project on this machine binds to. It exists because a native service binding `127.0.0.1:<port>` specifically beats a Docker container's wildcard bind on the same port and silently shadows it — the container-backed project then fails with a confusing error (wrong role/database, connection refused) instead of an obvious "port in use," and the failure looks unrelated to the actual cause.

## Before Allocating

- **Read `~/.claude/PORTS.md` first**, before mapping a new Docker service port, choosing a new dev-server port, or configuring a new native/Homebrew service. If the port is already registered to a different project, flag the conflict to the user instead of proceeding silently.
- **Before starting or reconfiguring a system-level service** (Homebrew, a local daemon, anything not scoped to one project's Docker network) that binds a port another project might depend on, check the registry for a collision first.

## Keeping the Registry Current

- **When a port is allocated, add a row to `PORTS.md` in the same session** — don't defer it. An unregistered port is what causes the *next* collision.
- **When a port is freed** (service removed, project retired), remove its row instead of leaving it marked stale.
- One row per bound port (or per host-level resource without a fixed TCP port, like a named Homebrew service). Include the owning project, what binds it, and whether it's a Docker container (wildcard bind, usually safe to co-exist) or a native/Homebrew service (binds `127.0.0.1` specifically, can silently shadow a container on the same port).

`PORTS.md` is reference data, not context to preload — read it only when doing port-affecting work.

## Trigger Phrases

Positive — this skill should fire:

- "I need to map a new port for this docker-compose service"
- "what port should the dev server use, something else is already on 5432"
- "I want to start a Homebrew Postgres service on this port"

Negative — this skill should *not* fire:

- "what port does our production load balancer listen on" → out of scope, this registry is local-machine only
- "review this branch for vulnerabilities" → `/security-review`
- "should this be one agent or three?" → `designing-agentic-architecture`
