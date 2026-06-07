# Claudness Config

Runtime opt-out for individual claudness components.

## Locations

- User-global: `~/.claude/claudness.config.json`
- Project override: `$CLAUDE_PROJECT_DIR/.claude/claudness.config.json`

Project values win on conflict. Missing keys default to **enabled**.

## Schema

See `settings/claudness.config.example.json`. Categories: `skills`, `hooks`,
`mcp`. Each entry is a boolean.

## Effects

- `skills.<name> = false` — claudness hooks behave as if the skill's CLI is
  not installed and suppress the "not installed" warning. Skill files
  themselves stay on disk.
- `hooks.<name> = false` — the named hook exits early and emits nothing.
- `mcp.<name> = false` — the named MCP server is blocked at `PreToolUse`
  (the hook returns `permissionDecision: deny`).

Agents and commands are loaded by Claude Code from the plugin manifest at
session start, so they cannot be toggled at runtime. A future `claudness
sync` command may rewrite the manifest from config; until then, install or
uninstall the plugin to control them.

## Examples

Disable engram completely:

```json
{ "version": 1, "skills": { "engram": false }, "mcp": { "engram": false } }
```

Disable a single hook only in this project:

```json
{ "version": 1, "hooks": { "user-prompt-submit": false } }
```
