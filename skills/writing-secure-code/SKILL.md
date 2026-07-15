---
name: writing-secure-code
description: Use when writing or reviewing code that touches external input, authentication, databases, shell execution, or AI model calls. Covers injection prevention, XSS, secrets handling, mass assignment, IDOR, boundary schema validation, local SAST, and prompt sanitization. Not for agent infrastructure security like sandboxing or supply chain (see securing-agentic-systems).
---

# Writing Secure Code

Be careful not to introduce security vulnerabilities such as command injection, XSS, SQL injection, and other OWASP Top 10 issues. If you notice you've written insecure code, fix it immediately. Prioritize safe, secure, correct code over speed.

## 1. Injection Prevention (SQLi, NoSQLi, Command)

- **Parameterized queries:** never use string concatenation, template literals, or interpolation to construct SQL/NoSQL queries. Always use parameterized inputs, ORMs, or query builders.
- **Command injection:** avoid direct shell execution primitives (`exec`, `spawn`, `system`). Use strongly-typed APIs or safe wrapper libraries instead.

## 2. Cross-Site Scripting (XSS) Prevention

- **Contextual output encoding:** automatically encode all user-supplied data before rendering it in the DOM.
- **Framework safety:** never use bypass mechanisms like React's `dangerouslySetInnerHTML`, Vue's `v-html`, or raw `innerHTML` assignments unless explicitly instructed, with a security justification comment.
- **CSP:** ensure any new routes or headers support strict, nonce-based Content Security Policy configurations.

## 3. Data & Authentication Security

- **Hardcoded secrets:** never hardcode API keys, passwords, bearer tokens, or cryptographic keys. Use environment variables exclusively (`process.env` or `.env`).
- **Mass assignment:** when processing API requests, use explicit object destructuring or strong parameter validation (e.g., Zod schemas) — never pass a raw request body straight to the database layer.
- **IDOR:** always validate that the authenticated user owns or has explicit permission to access the requested resource ID before executing a lookup or mutation.

## 4. Automated Testing Guardrails

- **Error-feedback loop first:** AI-generated changes must be validated by automated local tests, so security regressions are caught and fixed with immediate feedback.
- **Strict contract validation:** use schema validators (Zod, Joi, Pydantic) at every data boundary. Add unit tests that intentionally send malicious payloads (e.g. `' OR '1'='1`) and verify they're rejected or safely escaped.
- **Local SAST via hooks:** wire a local SAST scan (e.g. Semgrep, SonarQube) into pre-commit hooks or project scripts:

```json
"scripts": {
	"security:scan": "semgrep scan --config=auto src/"
}
```

- **Pre-refactor security check:** before accepting a complex AI-assisted refactor, run the local security-scan command and address findings.

## 5. Prompt and Sensitive-Data Sanitization

- **Sanitize before model calls:** strip, mask, or tokenize sensitive information — API keys, passwords, access tokens, private keys, connection strings, PII, customer secrets, internal-only URLs — before sending a prompt to any AI model.
- **Least-data prompting:** share only the minimum context the task needs. Prefer placeholders (`<REDACTED_TOKEN>`, `<EMAIL>`) over raw values.
- **No secret echoing:** never return or log a full secret in output. If sensitive data is needed for execution, use a secure local input method and keep secrets out of chat history and committed files.

## Trigger Phrases

Positive — this skill should fire:

- "add an endpoint that takes a user ID and returns their order history"
- "wire up a call to the Claude API with a user-supplied prompt"
- "review this login form for injection risks"

Negative — this skill should *not* fire:

- "design the sandbox we'll run agent-written code in" → `securing-agentic-systems`
- "what port should this service bind to?" → `allocating-local-ports`
- "write the PR description for this change" → `preparing-pull-requests`
