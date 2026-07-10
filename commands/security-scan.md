Analyze the codebase and identify potential security vulnerabilities.

Search for:
1. **Hardcoded secrets**: API keys, passwords, tokens in code or config files
2. **SQL injection**: Unparameterized queries, string concatenation in SQL
3. **XSS vulnerabilities**: Unsanitized user input rendered as HTML
4. **Dependency vulnerabilities**: Check package.json/requirements.txt/go.mod for known vulnerable packages
5. **Insecure configurations**: Debug mode in production, insecure defaults
6. **Authentication/Authorization issues**: Missing auth checks, privilege escalation
7. **Path traversal**: Unvalidated file paths using user input
8. **Sensitive data exposure**: PII or secrets in logs or error messages

Run relevant checks:
- `git grep -n "password\|secret\|api_key\|token" -- "*.json" "*.yaml" "*.env" "*.config.*"` (look for obvious secrets in tracked files)
- `git log -p --all | grep -i "password\|secret\|api_key\|token" | head -50` (check commit history for leaked secrets)
- Check for `.env` files committed to the repo: `git ls-files | grep -E "^\.env"`
- For comprehensive scanning, recommend running `gitleaks detect --source .` or `trufflehog git file://.` if available

Report findings with:
- **File and line number**
- **Severity**: Critical / High / Medium / Low
- **Description** of the vulnerability
- **Recommendation** to fix it
