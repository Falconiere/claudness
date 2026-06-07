# Claudness Config

Runtime opt-out for individual claudness components.

## Locations

- User-global: `~/.claude/claudness.config.json`
- Project override: `$CLAUDE_PROJECT_DIR/.claude/claudness.config.json`

Project values win on conflict. Missing keys default to **enabled**.

## Schema

See `settings/claudness.config.example.json`. Categories: `skills`, `hooks`,
`agents`, `commands`, `mcp`. Each entry is a boolean.

## Effects

- `skills.<name> = false` — claudness hooks behave as if the skill's CLI is
  not installed and suppress the "not installed" warning. Skill files
  themselves stay on disk.
- `hooks.<name> = false` — the named hook exits early and emits nothing.
- `mcp.<name> = false` — the named MCP server is blocked at `PreToolUse`
  (a block decision is returned with reason "MCP server ... is blocked").
- `agents.*` and `commands.*` — read but not enforced in v1. Claude Code
  loads agents and commands from the plugin manifest at session start;
  there is no runtime hook to unregister them. v2 may add a sync command.

## Examples

Disable engram completely:

```json
{ "version": 1, "skills": { "engram": false }, "mcp": { "engram": false } }
```

Disable a single hook only in this project:

```json
{ "version": 1, "hooks": { "user-prompt-submit": false } }
```
