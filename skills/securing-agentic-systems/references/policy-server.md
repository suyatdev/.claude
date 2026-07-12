# The Policy Server: A Two-Layer Gate in Front of Every Tool Call

> Reference for `securing-agentic-systems`. Everything here describes a component **to build** in a system being designed. No policy server exists in this configuration; nothing below is currently enforcing anything.

An agent's decision to call a tool and the tool's actual execution are two different events, and the whole point of a policy server is to put a governed layer between them. Intercept every proposed action before it reaches an external system, evaluate it, and only then let it through.

## Why a Gate at All

- **A system prompt is not a boundary:** the LLM driving an autonomous agent is probabilistic, not deterministic. Constraints hard-coded into a prompt are brittle — contexts overflow, and an agent can be *convinced* out of its rules by prompt injection. Production-grade platforms need external, tamper-proof governance sitting in front of the agent, not merely inside it.
- **Governance is a separate layer from execution:** the policy server sits as a distinct layer between the decision and the call. Fusing the two — scattering permission checks through tool implementations — means every new tool re-implements policy, and every re-implementation is a chance to get it wrong.

## Layer 1: Structural Gating

Fast, deterministic rules based on role and environment, expressed in a declarative config such as `policies.yaml`. Example: a `viewer` role cannot call `send_email`. These rules are cheap, auditable, and cannot be talked out of their answer, which is exactly why they run first — a call that fails structurally never reaches the expensive layer.

## Layer 2: Semantic Gating

A secondary, specialized LLM inspects the *intent and content* of the proposed action against natural-language policy. Example: an admin **may** call `send_email` — but not with unmasked PII in the body, such as plain-text email addresses or API keys.

**Why structural rules alone are insufficient:** deterministic rules enforce "is this tool allowed." They cannot reliably enforce "is *this specific use* of an allowed tool a policy violation." You cannot regex every possible PII leak; the space of ways to phrase a customer's home address is not enumerable. The moment policy depends on what is *inside* the arguments rather than which tool is named, a content-aware layer becomes load-bearing.

## Fail Closed

If either check fails, return a **Policy Violation** message to the agent instead of executing the tool call. Two properties matter here:

- The action does not happen. Silent proceed-on-error is the failure mode that turns a policy server into a logging system.
- The agent is *told*, in-band, so it can self-correct — redact the PII, pick a permitted tool — or fail gracefully with an honest report, rather than retrying blindly against a wall it cannot perceive.

## Validating the Target of an Action

An agent operating without a check on *whether it should* act will optimize for its goal using whatever data is in context — including hallucinating a recipient or URL when none was specified. Before an action like sending a message or email executes, require an explicit, validated target. A hallucinated recipient is not a formatting bug; it is a data leak with a plausible-looking address on it.

## PII Placeholders and Context Hallucination

- **Mask PII in templates:** replace personal data in prompt templates with generic placeholders (e.g. `[[VARIABLE_NAME]]`) and resolve them from validated runtime state or environment configuration. Sensitive values never get hardcoded into specs, skills, or test suites, where they would be committed and shared.
- **Leave unresolved placeholders unresolved:** when a placeholder cannot be found in runtime state or environment, leave it as-is rather than silently substituting a fallback. Silent substitution is the mechanism of **Context Hallucination** — the agent fills the gap with whatever string happens to be nearby, and the string that happens to be nearby is frequently a real email address or a private URL. An unresolved placeholder is a visible, debuggable failure; a silently substituted one is an exfiltration that looks like success.

## Sanitize Output, Not Just Input

- **Agent output is an attack surface:** sanitize everything the agent emits, not only what it ingests, so a manipulated "vibe" never becomes an architectural vulnerability or a rogue UI interaction downstream.
- **Wire sanitization into the pipeline:** intercept tool-call arguments before execution and resolve bracketed or templated variables dynamically as part of the validation step. Sanitization treated as a manual review step is sanitization that gets skipped on the day it matters — the day someone is in a hurry.

## Related Runtime Controls

- **LLM firewall in front of active agents:** dynamically intercept opportunistic prompt injections arriving through tool and MCP responses *before* they reach the agent's reasoning loop. The policy server governs what goes out; the firewall governs what comes in.
- **Centralised agent gateway:** route every agent-to-tool and agent-to-agent call through a single governed gateway that evaluates Contextual Authorisation — verifying the requested action actually aligns with the developer's original intent — so a compromised agent cannot move laterally through the tool estate.

## Human-in-the-Loop at the Gate

- **Gate high-stakes operations behind a mandatory checkpoint:** production deploys, database schema changes, financial transactions. Define the high-risk profile explicitly; a gate that fires on everything is a gate that gets clicked through.
- **Present sanitized intent, not raw output:** surface what the action *will do* to the human supervisor for sign-off, so final responsibility for architectural integrity stays with a person even as the agent does the underlying work. See `seven-pillars.md` on the Vibe Diff and Logic Review for why a bare approve/deny button is not a control.
