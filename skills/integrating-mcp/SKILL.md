---
name: integrating-mcp
description: Use when connecting an agent to an MCP server, choosing a transport, debugging a failing or hallucinated tool call, or building an MCP server for a data source. Covers trust tiers, scoping, auth, and governance. Not for agent-to-agent protocols (see designing-agent-interop).
---

# Integrating MCP

The Model Context Protocol is the tool layer: a standardized, structured interface between a model and the systems it acts on. Most MCP work is *consumption* — finding a server that already exists, deciding whether it can be trusted, scoping it down to the least access that still does the job, and confirming the wire actually carries what you think it carries. Building a server is the rarer case, and it is worth doing only when nothing already speaks for the data source you own. This skill covers discovery, trust, configuration, transports, debugging, governance, and the narrow build case — in that order, because that is the order the decisions come in.

## Consume Before You Build

- **Look for an existing server first:** a pre-built MCP server for a common data source is almost always faster to adopt than a custom connector is to write, and it carries no ongoing maintenance tax on your side. Prioritize consumption over creation, especially for prototyping.
- **A custom REST wrapper is a step backward:** wrapping an API by hand re-creates exactly the bespoke integration MCP exists to eliminate, and it only works for the one agent you wrote it for. Search for a server before you reach for a wrapper.

## Source by Trust Tier

- **Public registries are prototype-grade:** servers from `registry.modelcontextprotocol.io`, `github.com/mcp`, and similar catalogs are unvetted. They are fine for rapid local prototyping, at your own risk, and they are not a foundation for core business logic.
- **Official third-party remote servers are the preferred default:** a server published and maintained by the vendor whose product it fronts has a named owner, a release process, and a reason to keep its schemas correct. Prefer these over a community reimplementation of the same thing.
- **Internal registries are best where they exist:** an organization's own tools, cataloged and exposed through an API gateway or private portal, give you a governed schema and an accountable owner. If your org has one, consume from it before you look outward.
- **Security is the first filter, not a later review:** the choice of server determines what an attacker gets if the server is hostile, so trust is a *selection* criterion. Filtering for security after you have already picked on convenience means re-litigating a decision you have started building on.
- **Never hand credentials to an unverified server:** an unvetted public or community server that receives your token has your token, and you have no way to know what it does with it. If a public server genuinely must be used, route its traffic through a security/filtering layer — and assume no such layer exists unless you built one, because none is present by default.

## Configuration

- **Scope and permissions come before connection:** check the server's prerequisites, identify the access criteria it actually requires, and write those specifications explicitly into the agent's configuration. Connecting first and narrowing later means the broad grant is live while you are still deciding what it should have been.
- **Credentials live in environment variables:** hold Personal Access Tokens, OAuth secrets, and API keys in the environment, never inline in a prompt, a script, or a checked-in config file. Anything pasted into a prompt is in transcript history and anything in config is in version control — both are places a secret cannot be retracted from.
- **Declare read/write filesystem permissions explicitly:** decide what the server may read and what it may write *before* granting access. An undeclared permission set defaults to whatever the host process happens to have, which is almost never what you intended.

## Verify With a Handshake

- **Confirm the connection rather than assuming it:** after configuring a server, have the host client run a basic handshake that lists the available tools and validates the output schema. A misconfigured connection often fails silently or partially — the agent sees a shorter tool list, or a schema shaped differently than the docs promised — and every downstream failure you debug afterward will be a symptom of that, not a cause.

## Why MCP At All — The NxM Problem

- **Bespoke connectors scale multiplicatively:** integrating N models against M tools ad hoc requires O(N × M) integration points. Five models against ten tools is fifty integrations, each of which is a thing to build, test, and maintain against two independently changing sides.
- **A standard interface makes it additive:** MCP reduces the same problem to O(N + M) by giving every model and every tool one standardized interface to speak. Adding the eleventh tool is one server, not five new connectors — which is the whole reason to accept the protocol's overhead in the first place.

## Transports

- **Use stdio for local development and prototyping:** the host client launches the server as a local background subprocess and exchanges JSON-RPC 2.0 messages over stdin/stdout. There is no network setup, no ports, and no deployment, so the cost of trying a server is close to zero.
- **Use SSE over HTTP when the client is deployed or needs a remote connection:** Server-Sent Events over HTTP suit a host client that runs somewhere other than the developer's laptop, or that needs an always-up-to-date connection to a centrally maintained server. The trade is a higher operational burden on the hosted server in exchange for fewer client-side dependencies, a smaller client footprint, and a simpler lifecycle.

## Debugging

- **Suspect the transport layer before the prompt:** when an agent hallucinates parameters, calls the wrong tool, or fails to parse a payload, the cause is frequently a schema the agent never received correctly or a payload shaped differently than declared. Blindly editing system instructions in that situation tunes the model around a wire-level defect, which hides the bug and makes the prompt worse.
- **Use the MCP Inspector to see the wire:** it lets you query a local or remote server directly, view the active tool schemas, test payload inputs, and inspect raw JSON-RPC 2.0 packets — all without invoking the full agent workflow. Removing the agent from the loop is what separates "the tool is broken" from "the model is misusing a working tool."
- **Use browser DevTools for SSE connections:** for web-based environments and SSE transports, DevTools traces the incoming stream and shows server latency, which is where an intermittent or slow connection reveals itself rather than in the agent's output.

## Governance — Do

- **Audit open-source servers before attaching them:** read the code of any publicly available server before you connect it to an agent that holds filesystem access or credentials. Once connected, the server's code is running with your agent's reach, and an audit afterward is a post-mortem.
- **Load tools dynamically and drop them when done:** pull tools from a registry only when the current task needs them, and remove them from context once the task completes. Tools that linger dilute the model's attention across a search space that no longer contains the right answer.
- **Prefer internal API gateways and registries:** consuming approved, governed schemas beats consuming an unvetted connector someone reinvented, because the governed schema has an owner who is on the hook when it changes.
- **Show tool inputs to the user before the call:** a human-in-the-loop confirmation step on the *inputs* is what catches a malicious or accidental exfiltration before the data leaves — after the call, the data is already gone.
- **Show the exact query that ran:** when a tool queries tables or moves files, display the specific SQL statement or command that produced the output, not just the output. A result presented without its query is unfalsifiable — the reviewer cannot tell a correct answer from a plausible one drawn from the wrong table, and the check the human is there to perform becomes impossible.
- **Log all tool usage:** an audit later is only possible if the record exists now. Tool-call logs are what let you reconstruct why an agent did something, which is otherwise unrecoverable.

## Governance — Don't

- **Don't build what you can consume:** a custom REST wrapper written per agent discards the universal-interface property that makes MCP worth using.
- **Don't put unverified public servers in production:** they are acceptable for a weekend prototype. Tying core business logic to an unverified public endpoint means an upstream change — or an upstream compromise — lands directly in production.
- **Don't hardcode credentials in prompts or scripts:** pass them through environment variables to the server instead. A key in a prompt or a local script is a key you have lost track of.
- **Don't connect an MCP server to production data:** point it at a development project with non-production or obfuscated data. Agents are experimental by nature; let them design and test somewhere a mistake is survivable.
- **Don't grant write when only reads are needed:** if a connection to real data is unavoidable, set the server read-only so every query executes as a read. Read-only mode makes a destructive mistake structurally impossible rather than merely unlikely.
- **Don't grant project-wide access:** scope each server to the specific project and the minimum resources it needs. Broad scope means the blast radius of any compromise is the whole project rather than one dataset.

## Building a Server

- **One server per data source, not one integration per framework:** MCP is an open standard, so a single server for a database, an API, or a filesystem is consumable by any MCP-compatible agent. Writing a per-framework integration instead means rewriting the same access logic every time the agent stack changes.
- **Validate the query type before executing it:** when a tool runs SQL on an agent's behalf, check the operation before execution — reject anything that is not a `SELECT`, for example — so the tool cannot mutate or destroy data through a path nobody intended. The validation belongs in the tool, where it is deterministic, not in the prompt, where it is advisory.
- **Declare every tool's input schema explicitly:** state parameter names, types, and which parameters are required. The schema is what tells the agent — and any validation layer sitting in front of it — what a valid call looks like *before* the call executes, and it is the artifact you will be reading when a call goes wrong.

## Trigger Phrases

Positive — this skill should fire:

- "hook this agent up to Postgres via MCP"
- "the agent keeps passing the wrong params to my tool"
- "stdio or SSE for this MCP server?"

Negative — this skill should *not* fire:

- "how do two agents talk to each other?" → `designing-agent-interop`
- "design the security model for our agent fleet" → `securing-agentic-systems`
- "write a spec for this API" → `writing-specs`
