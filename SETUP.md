# New Machine Setup Checklist

Steps to restore this Claude configuration on a new computer.

## 1. Clone This Repo

```bash
git clone <your-repo-url> ~/.claude
```

---

## 2. Install Plugins

All plugins are from the official marketplace (`anthropics/claude-plugins-official`).
Run each install command inside Claude Code:

- [ ] `/plugins install superpowers@claude-plugins-official`
- [ ] `/plugins install frontend-design@claude-plugins-official`
- [ ] `/plugins install skill-creator@claude-plugins-official`
- [ ] `/plugins install code-simplifier@claude-plugins-official`
- [ ] `/plugins install typescript-lsp@claude-plugins-official`

---

## 3. Install RTK (Token-Optimized CLI Proxy)

RTK is used as a shell command wrapper to reduce token usage. Install it and verify it is on your PATH:

```bash
# Check the RTK.md in this repo for the install source and usage instructions
cat ~/.claude/RTK.md
```

- [ ] RTK installed and available as `rtk` in terminal

---

## 4. Verify Settings

`settings.json` is tracked and will be cloned automatically. Confirm these are active:

- [ ] RTK pre-tool hook is active (`settings.json` → `hooks.PreToolUse`)
- [ ] All 5 plugins show as enabled in `settings.json` → `enabledPlugins`
- [ ] TUI is set to `fullscreen`

---

## 5. Confirm Rules Load

Open Claude Code and verify the rule files under `rules/` are being picked up:

- [ ] `rules/general-engineering.md`
- [ ] `rules/session-state-management.md`
- [ ] `rules/pr-requests.md`
- [ ] `rules/parallel-agent-guardrails.md`
