# General Engineering Conventions

## Guiding Principle

Prioritize quality, simplicity, robustness, reliability, and long-term maintainability over development cost and speed. Prefer the simplest solution that fully solves the problem. When a tradeoff must be made, favor the option that will be easier to understand, test, and change six months from now.

## Session Defaults

1. Act as a senior engineer. Prefer sound architectural decisions and established best practices over shortcuts.
2. Be skeptical: verify outputs (including your own and any subagents') before presenting them as done. If tests fail, say so.
3. If a request is ambiguous, ask for clarification rather than assuming.
4. Don't comment self-explanatory code. Only add a comment when the *why* is non-obvious.
5. Match the style, naming, and structure of the surrounding code.

## Coding_MEMORY Style & Quality

- KISS, DRY, YAGNI. Avoid speculative generality and premature optimization.
- Prefer immutable patterns: return new values instead of mutating inputs.
- Many small, focused files over few large ones (aim <400 lines, 800 max).
- Use early returns instead of deep nesting (avoid >4 levels).
- No magic numbers - use named constants for meaningful values.
- Handle errors explicitly; never silently swallow them.
- Validate all input at system boundaries; never trust external data.
- Naming: camelCase for variables/functions, PascalCase for types/components, UPPER_SNAKE_CASE for constants; booleans read as is/has/should/can.

## Testing

- Write tests first (red), implement to pass (green), then refactor.
- Cover the meaningful behavior, including edge cases and error paths.
- Structure tests as Arrange-Act-Assert with descriptive names.
- When a test fails, fix the implementation - only change the test if the test itself is wrong.
- **Reproduce before you fix.** Write a failing test or repro command first, and keep it permanently so the bug cannot silently return.
- **Never edit tests and implementation in the same step.** The test stays an unbiased baseline; editing both turns a build green without fixing anything.

## Working On Existing Code

- **Fix the root cause, and only the root cause.** Debug from evidence — logs, request flow — not symptoms. Drive-by cleanup hides the real fix; a rename is its own task.

## Starting New Work

- **Never scaffold in YOLO mode.** Propose structure and stack, then wait for confirmation — a scaffold's defaults outlive the session.
- **Pin exact library and tool versions.** Unpinned, an agent falls back on training data and picks something outdated.
- **Architecture trade-offs stay human-owned** — consistency vs. availability, complexity vs. flexibility, build vs. buy. They need judgment AI cannot provide.

## Security Engineering Guardrails

## 1. Injection Prevention (SQLi, NoSQLi, Command)
- **Parameterized Queries**: Never use string concatenation, template literals, or interpolation to construct SQL/NoSQL queries. Always use parametrized inputs, ORMs, or query builders.
- **Command Injection**: Avoid using direct shell execution primitives (`exec`, `spawn`, `system`). Use strongly-typed APIs or safe wrapper libraries instead.

## 2. Cross-Site Scripting (XSS) Prevention
- **Contextual Output Encoding**: Automatically encode all user-supplied data before rendering it in the DOM. 
- **Framework Safety**: Never use bypass mechanisms like React's `dangerouslySetInnerHTML`, Vue's `v-html`, or innerHTML assignments unless explicitly instructed with a security justification comment.
- **Content Security Policy (CSP)**: Ensure any new routes or headers support strict, nonce-based CSP configurations.

## 3. Data & Authentication Security
- **Hardcoded Secrets**: Never hardcode API keys, passwords, bearer tokens, or cryptographic keys. Use environment variables exclusively (`process.env` or `.env`).
- **Mass Assignment**: When processing API requests, always use explicit object destructuring or strong parameter validation (e.g., Zod schemas). Never pass raw request bodies directly to database layers.
- **Insecure Direct Object References (IDOR)**: Always validate that the authenticated user owns or has explicit permission to access the requested resource ID before executing lookups or mutations.

## 4. Automated Testing Guardrails
- **Error-Feedback Loop First**: AI-generated changes must be validated by automated local tests so security regressions are caught quickly and fixed with immediate feedback.
- **Implement Strict Contract Validation**: Use schema validators like **Zod**, **Joi**, or **Pydantic** at all data boundaries. Add unit tests that intentionally send malicious payloads (for example, `' OR '1'='1`) and verify requests are rejected or safely escaped.
- **Automate Local SAST via Hooks**: Integrate local SAST scanning (for example, **Semgrep** or **SonarQube**) into the workflow with pre-commit hooks or project scripts.

```json
"scripts": {
	"security:scan": "semgrep scan --config=auto src/"
}
```

- **Pre-Refactor Security Check**: Before accepting a complex refactor from AI assistance, run the local security scan command (for example, `/run npm run security:scan`) and address findings.

## 5. Prompt And Sensitive Data Sanitization
- **Sanitize Prompts Before Model Calls**: Before sending prompts to any AI model, remove, mask, or tokenize sensitive information (for example, API keys, passwords, access tokens, private keys, connection strings, personally identifiable information, customer secrets, and internal-only URLs).
- **Least-Data Prompting**: Share only the minimum context required to complete the task. Prefer placeholders (for example, `<REDACTED_TOKEN>`, `<EMAIL>`) over raw values.
- **No Secret Echoing**: Never return or log full secrets in outputs. If sensitive data is needed for execution, request secure local input methods and keep secrets out of chat history and committed files.
