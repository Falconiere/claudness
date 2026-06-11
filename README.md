# claudness

Personal collection of [Claude Code](https://claude.com/claude-code) extensions — plugins, skills, hooks, subagents, slash commands, and configuration.

Installable as a plugin: `claudness@falconiere` (see [Install](#install) below).

## Layout

```
.
├── docs/                     # Repo documentation (runtime config, design notes, plans)
└── plugins/
    └── claudness/            # Self-contained plugin (installable from the marketplace)
        ├── .claude-plugin/   # plugin.json manifest
        ├── skills/           # Standalone skills (SKILL.md + supporting files)
        ├── agents/           # Subagent definitions (.md with YAML frontmatter)
        ├── commands/         # Slash commands (.md prompt templates)
        ├── hooks/            # Hook scripts (PreToolUse, PostToolUse, SessionStart, etc.) + hooks.json
        ├── tooling/          # Helper CLIs used by skills (context7, exa-search) + bats tests
        └── settings/         # Reusable settings.json fragments + hook data files
```

Everything a plugin ships lives under its own `plugins/<name>/` directory — no
symlinks, no content outside the plugin root, so marketplace installs get the
whole working tree.

## Conventions

### Skills
- One directory per skill containing `SKILL.md`.
- Frontmatter: `name`, `description` (when-to-trigger phrasing), optional `allowed-tools`.
- Keep `SKILL.md` short; push detail into sibling files (`references/`, `scripts/`, `assets/`).

### Agents
- One `.md` file per agent under the plugin's `agents/`.
- Frontmatter: `name`, `description`, `tools` (comma-separated or `*`), optional `model`.
- Body is the system prompt.

### Commands
- One `.md` file per command under the plugin's `commands/`.
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

Install via the Claude Code plugin marketplace.

From GitHub (public):

```
/plugin marketplace add Falconiere/claudness
/plugin install claudness@falconiere
```

From a local clone:

```
/plugin marketplace add /Volumes/Projects/claudness
/plugin install claudness@falconiere
```

For settings fragments (permissions, denylists, etc.), see `plugins/claudness/settings/README.md`.

## Runtime config

Drop a `~/.claude/claudness.config.json` (or per-project
`$CLAUDE_PROJECT_DIR/.claude/claudness.config.json`) to disable individual
skills, hooks, or MCP servers without uninstalling anything. Defaults are
opt-out — no file is required. Schema and examples: `docs/config.md`.

```json
{ "version": 1, "skills": { "engram": false }, "mcp": { "engram": false } }
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
