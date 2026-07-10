Review the staged git changes (`git diff --cached`) and provide a concise, informative commit message following conventional commits format.

Rules:
- Use imperative mood ("Add feature" not "Added feature")
- Keep the subject line under 72 characters
- Use conventional commit type prefix: feat, fix, docs, style, refactor, test, chore, ci, perf, build, revert
- If there are multiple logical changes, suggest splitting into separate commits
- Output only the commit message, no explanations

Format:
```
<type>(<optional scope>): <description>

<optional body>
```
