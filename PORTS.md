# Local Port Registry

Machine-wide registry of TCP ports and other host-level resources (system
services, DB instances) that local projects bind to on this machine. Exists
to prevent silent shadowing — e.g. a Homebrew service binding
`127.0.0.1:<port>` specifically, which beats a Docker container's wildcard
bind on the same port and makes the container-backed project fail with
confusing errors (wrong role/database, connection refused, etc.) instead of
a clear "port in use."

This file is **reference data, not a rule** — it is not auto-loaded every
turn. Read it before allocating a new local port or starting a system-level
service; see `allocating-local-ports` for when that's required.

## Registry

| Port | Owner project | Service | Type | Notes |
|---|---|---|---|---|
| 5432 | mtg-wizard | Postgres (`pgvector/pgvector:pg16`) | Docker container | `docker-compose.yml`; hardcoded in CI + service defaults, do not move. |
| 5433 | vibescape | Postgres (`postgresql@18`, Homebrew) | Homebrew service | Moved from 5432 on 2026-07-14 to stop shadowing mtg-wizard's Docker Postgres. Set in `/opt/homebrew/var/postgresql@18/postgresql.conf` (`port = 5433`). vibescape's connection string updated to 5433 in `.env/cloud.env` on 2026-07-14. |
| 5434 | snatch-bracket | Postgres (`postgres:16`) | Docker container | `docker-compose.yml` maps `5434:5432` (allocated 2026-07-14; 5432/5433 taken). In-repo defaults (`config.py`, `tests/conftest.py`) point here; CI unaffected (sets `DATABASE_URL` explicitly). |
| 5198 | vibescape | Presence E2E signaling server (Fastify `buildApp()`, PGlite-backed) | Local dev/test process | Bound only while Playwright presence E2E runs (`packages/client/e2e/support/presenceServer.ts`); proxied via Vite's ws proxy. Allocated 2026-07-14 (Plan 3 Task 13). |
| 8000 | mtg-wizard | `core-api` (FastAPI) | Docker container / local dev | `docker-compose.yml`, desktop app's `API_BASE_URL` default. |
| 8001 | snatch-bracket | backend (FastAPI, `snatch_bracket.main:app`) | Local dev process (`just dev-backend`) | Moved from 8000 on 2026-07-15 — mtg-wizard's `core-api` owns 8000. Set in `justfile`; frontend `BACKEND_URL` default (`frontend/lib/backend.ts`, `.env.example`, `.env.local`) points here. CI unaffected (no live server). |
| 8100 | mtg-wizard | `ai-service` (FastAPI) | Docker container | Internal to compose network; proxied through `core-api`. |
| — | Homebrew `postgresql@15` | Postgres | Homebrew service, **installed but stopped/unused** | Defaults to 5432 (commented out in its `postgresql.conf`) — would collide with the container if ever started. Leave stopped, or assign it a port here first. |

## Conventions

- One row per bound port (or per host-level resource without a fixed TCP
  port, like a named Homebrew service). Include the owning project, what
  binds it, and whether it's a Docker container (wildcard bind, usually
  safe to co-exist) or a native/Homebrew service (binds `127.0.0.1`
  specifically, can silently shadow a container on the same port).
- When a project allocates a new port, add a row here in the same session —
  don't defer it, the gap is what causes the next collision.
- When freeing a port (service removed, project retired), remove its row
  rather than leaving it marked stale.
