# my-claude

Personal collection of [Claude Code](https://claude.com/claude-code) extensions — plugins, skills, hooks, subagents, slash commands, and configuration.

## Layout

```
.
├── plugins/        # Plugin bundles (manifest + grouped extensions)
├── skills/         # Standalone skills (SKILL.md + supporting files)
├── agents/         # Subagent definitions (.md with YAML frontmatter)
├── commands/       # Slash commands (.md prompt templates)
├── hooks/          # Hook scripts (PreToolUse, PostToolUse, SessionStart, etc.)
├── mcp/            # MCP server configs and wrappers
└── settings/       # Reusable settings.json fragments
```

Add or drop directories as needed — nothing here is load-bearing on the layout.

## Conventions

### Skills
- One directory per skill containing `SKILL.md`.
- Frontmatter: `name`, `description` (when-to-trigger phrasing), optional `allowed-tools`.
- Keep `SKILL.md` short; push detail into sibling files (`references/`, `scripts/`, `assets/`).

### Agents
- One `.md` file per agent under `agents/`.
- Frontmatter: `name`, `description`, `tools` (comma-separated or `*`), optional `model`.
- Body is the system prompt.

### Commands
- One `.md` file per command under `commands/`.
- Filename = invocation (e.g. `commands/review.md` → `/review`).
- Frontmatter optional: `description`, `argument-hint`, `allowed-tools`.

### Hooks
- Executable scripts (any language) referenced from `settings.json`.
- Keep them fast and idempotent. Exit non-zero only when you mean to block.
- Document the event (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionStart`, `Stop`, …) at the top of the script.

### Plugins
- One directory per plugin under `plugins/<name>/` with a `plugin.json` manifest.
- Bundle related skills/agents/commands/hooks under the plugin dir.

## Install

### Per-user (global)

```bash
ln -s "$PWD/skills"   ~/.claude/skills
ln -s "$PWD/agents"   ~/.claude/agents
ln -s "$PWD/commands" ~/.claude/commands
ln -s "$PWD/hooks"    ~/.claude/hooks
```

Merge settings fragments — see `settings/README.md`.

### Per-project

```bash
ln -s /Volumes/Projects/my-claude/skills   .claude/skills
ln -s /Volumes/Projects/my-claude/agents   .claude/agents
ln -s /Volumes/Projects/my-claude/commands .claude/commands
ln -s /Volumes/Projects/my-claude/hooks    .claude/hooks
ln -s /Volumes/Projects/my-claude/tooling  .tooling
```

### Plugins via marketplace
If a plugin lives under `plugins/<name>/`, install it from a local marketplace:

```bash
# inside Claude Code
/plugin marketplace add /Volumes/Projects/my-claude
/plugin install claudness@falconiere
```

## Adding something new

1. Pick the right directory (skill vs. agent vs. command vs. hook).
2. Use the existing siblings as templates for frontmatter and structure.
3. Test in a real Claude Code session before committing.
4. Commit with a Conventional Commits subject (`feat(skills): add foo`).

## References

- Claude Code docs: https://docs.claude.com/en/docs/claude-code
- Skills: https://docs.claude.com/en/docs/claude-code/skills
- Subagents: https://docs.claude.com/en/docs/claude-code/sub-agents
- Slash commands: https://docs.claude.com/en/docs/claude-code/slash-commands
- Hooks: https://docs.claude.com/en/docs/claude-code/hooks
- Plugins: https://docs.claude.com/en/docs/claude-code/plugins

## License

Personal use. No warranty.
