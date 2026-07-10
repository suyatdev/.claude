# .claude

My personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration repository.

## Structure

```
.claude/
├── CLAUDE.md              # Global instructions and rules for Claude
├── settings.json          # Claude settings (permissions, MCP servers)
├── commands/              # Custom slash commands
│   ├── commit-message.md  # Generate conventional commit messages
│   ├── explain-codebase.md # Explain project structure and architecture
│   ├── pr-description.md  # Generate PR descriptions
│   ├── review.md          # Code review checklist
│   └── security-scan.md   # Security vulnerability scan
└── README.md              # This file
```

## Setup

Clone this repo as `~/.claude`:

```bash
git clone https://github.com/suyatdev/.claude.git ~/.claude
```

### MCP Servers

The `settings.json` configures the following MCP servers:

| Server | Purpose | Required Env Var |
|--------|---------|-----------------|
| `github` | GitHub API access | `GITHUB_TOKEN` |
| `filesystem` | Local file access | — |
| `brave-search` | Web search | `BRAVE_API_KEY` |
| `memory` | Persistent memory across sessions | — |
| `sequential-thinking` | Structured reasoning | — |

Set the required environment variables in your shell profile (e.g., `~/.zshrc` or `~/.bashrc`):

```bash
export GITHUB_TOKEN="your_github_personal_access_token"
export BRAVE_API_KEY="your_brave_api_key"
```

## Custom Commands

Use slash commands in Claude Code with `/project:<command-name>`:

- `/project:commit-message` — Generate a conventional commit message for staged changes
- `/project:review` — Code review of current branch changes
- `/project:pr-description` — Generate a PR description for current branch
- `/project:security-scan` — Scan for security vulnerabilities
- `/project:explain-codebase` — Explain project structure and architecture
