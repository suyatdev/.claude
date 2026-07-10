Perform a thorough code review of the changes in the current branch compared to the main branch.

Run: `git diff origin/main...HEAD`

Evaluate:
1. **Correctness**: Does the code do what it's supposed to do?
2. **Edge cases**: Are error conditions and edge cases handled?
3. **Security**: Are there any security vulnerabilities (injection, auth bypass, data exposure)?
4. **Performance**: Are there obvious performance issues?
5. **Readability**: Is the code clear and maintainable?
6. **Tests**: Is there adequate test coverage for the changes?

Format your response as:
- **Summary**: One paragraph describing what the changes do
- **Issues** (if any): Bulleted list of problems found, with severity (critical/major/minor)
- **Suggestions**: Optional improvements that are not blocking
- **Verdict**: APPROVE / REQUEST CHANGES
