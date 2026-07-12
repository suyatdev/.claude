---
name: designing-agent-commerce
description: Use when an agent must transact autonomously — discovering and ordering via UCP, authorizing payment via AP2, setting spending mandates, and handling payment credentials. Not for general API or tool integration (see integrating-mcp) or non-payment agent interop (see designing-agent-interop).
---

# Designing Agent Commerce

An agent that can spend money is a different kind of system from one that can only read and recommend. A mistaken summary is embarrassing; a mistaken purchase is a chargeback, and an unbounded one is a liability. Two protocols carry the load, and they answer different questions. UCP (Universal Commerce Protocol) answers *what to buy* — how an agent discovers a catalog, builds a cart, and places an order. AP2 (Agent Payments Protocol) answers *how to pay* — authorization, auditability, authenticity of intent, and accountability. This skill is about keeping those two questions apart, and about the guardrails that have to exist before the second one is ever answered in the affirmative.

## Separate What to Buy From How to Pay

- **Two protocols, two concerns:** UCP is the standardized interface for commerce mechanics — catalog discovery, cart management, checkout and order placement against any business provider. AP2 is the standardized interface for payment — authorization, audit, proof of intent, accountability. Conflating them into a single ad-hoc integration means a change to either concern reaches into the other, and the payment path is the one place where an accidental coupling is most expensive to unwind.
- **Transact through a machine interface:** use UCP so the agent queries and transacts with merchant systems through a stable machine surface (catalog, cart, checkout, order) rather than scraping or driving a human-facing web UI. A UI is designed to change; treating it as an API means every visual refresh is an outage, and worse, a silent one that fails mid-transaction.

## Enforce the Mandate Before Any Autonomous Spend

- **Require a mandate first:** an explicit, pre-approved mandate — "you may spend up to $25 at this specific vendor" — should exist before an agent spends anything on its own. The mandate is what makes the spend attributable to a human decision rather than to model output, and an agent should have no authority to spend outside it.
- **Never transmit raw payment credentials:** the agent should not hand a card number to a merchant. AP2's model is a cryptographically signed "promissory note" — a proof of intent the merchant's payment processor can verify — so the underlying payment instrument is never exposed to the agent's execution path or to the merchant's systems. Credentials that are never present cannot be leaked by a prompt injection, a logged request, or a compromised merchant.
- **Block deviation at the protocol level:** a charge that deviates from the mandate — a merchant attempting to bill more than was authorized — should be rejected by the protocol rather than flagged after settlement. Detection after the fact is a reconciliation process with a human on the end of it; refusal at authorization time is the control that actually holds when the agent runs unattended.

## Trigger Phrases

Fires on:

- "let the agent reorder supplies under $50"
- "how do we authorize agent payments safely?"
- "should the agent hold a card number?"

Does not fire on:

- "integrate Stripe's API into our app" — an ordinary payments integration with a human at the checkout, not agentic commerce
- "connect the agent to our product database" — tool integration, see `integrating-mcp`
- "expose our agent to partners" — agent-to-agent interop, see `designing-agent-interop`
