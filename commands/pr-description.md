Analyze the current project and generate a comprehensive PR description.

Run `git diff origin/main...HEAD` and `git log origin/main...HEAD --oneline` to understand the changes.

Generate a PR description with the following sections:

## Summary
Brief description of what this PR does and why.

## Changes
- Bulleted list of key changes made

## Testing
How to test/verify the changes.

## Screenshots (if applicable)
Note if UI changes were made.

## Checklist
- [ ] Tests added/updated
- [ ] Documentation updated (if needed)
- [ ] No breaking changes (or breaking changes are documented)

Keep the description concise but complete. Focus on what reviewers need to understand the change.
