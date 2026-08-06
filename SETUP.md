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

## 3. Verify Settings

`settings.json` is tracked and will be cloned automatically. Confirm these are active:

- [ ] All 5 plugins show as enabled in `settings.json` → `enabledPlugins`
- [ ] TUI is set to `fullscreen`

---

## 4. Confirm Rules Load

Open Claude Code and verify the rule files under `rules/` are being picked up:

- [ ] `rules/core-conduct.md`
- [ ] `rules/gates.md`
