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

`settings.json` is tracked and will be cloned automatically. It is what registers the hooks in
`hooks/` — without it those scripts are inert, so a clone that loses it gets the guard scripts and
none of the guards. Confirm these are active:

- [ ] All 5 plugins show as enabled in `settings.json` → `enabledPlugins`
- [ ] TUI is set to `fullscreen`

**On a machine that already has an untracked `~/.claude/settings.json`,** a pull carrying this file
will refuse to overwrite it unless the bytes match exactly. Move yours aside first, then reconcile
by hand:

```bash
mv ~/.claude/settings.json ~/.claude/settings.json.mine
git -C ~/.claude pull
diff ~/.claude/settings.json.mine ~/.claude/settings.json   # merge anything of yours that matters
```

`model` and `effortLevel` live in this file and are rewritten by `/model`, so expect an occasional
two-line diff after you deliberately switch models. That is accepted, not a bug — see
`docs/decisions/0032-track-settings-json-whole.md`.

---

## 4. Confirm Rules Load

Open Claude Code and verify the rule files under `rules/` are being picked up:

- [ ] `rules/core-conduct.md`
- [ ] `rules/gates.md`
