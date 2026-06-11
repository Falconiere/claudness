# Claudness Config

Runtime opt-out for individual claudness components. No config file is
required — every component defaults to enabled. Drop in a file only to
disable what you do not want.

## Locations

- User-global: `~/.claude/claudness.config.json`
- Project override: `$CLAUDE_PROJECT_DIR/.claude/claudness.config.json`

Both are optional. When both exist they are deep-merged via `jq '. * .'`;
project values win on conflict. Missing keys default to **enabled**.

Requires `jq` (already a hard dependency of every claudness hook). With `jq`
absent or the JSON malformed, the loader warns once on stderr and falls
back to "all enabled".

## Schema

```json
{
  "version": 1,
  "skills":  { "<name>": true | false },
  "hooks":   { "<name>": true | false },
  "mcp":     { "<server>": true | false }
}
```

`version` is reserved for future schema bumps; v1 is the current value.
See `plugins/claudness/settings/claudness.config.example.json` for a fully-populated example.

### Recognized names

| Category | Names                                                                              |
|----------|------------------------------------------------------------------------------------|
| `skills` | `engram`, `ast-grep` (the only skill keys any hook reads)                          |
| `hooks`  | `session-start`, `user-prompt-submit`, `pre-tools`, `post-tools`, `pre-compact`, `session-end` |
| `mcp`    | any MCP server name — e.g. `engram`, `canva`, `figma`                              |

Unknown names are silently ignored (forward compatible).

## Effects

- `skills.<name> = false`
  - The hooks that reference the skill behave as if its CLI is not
    installed AND they suppress the "not installed" warning. Skill files
    themselves stay on disk.
  - Concretely: `skills.engram = false` silences the `MANDATORY: recall`
    hint in `UserPromptSubmit`, the engram entry in the `SessionStart`
    "missing tools" warning, and the engram reminder in `PreCompact` and
    `SessionEnd`. `skills.ast-grep = false` removes the ast-grep STOP /
    install-hint advisories in `search-nudge` (a registry module shipped
    by the code-intel plugin); the generic `grep/rg → Grep tool` advisory
    still fires.

- `hooks.<name> = false`
  - The named hook exits early and emits nothing. Its stdin is drained
    first so Claude Code's IPC does not stall.

- `mcp.<name> = false`
  - Any `mcp__<name>__*` tool invocation is blocked at `PreToolUse` with
    `permissionDecision: "deny"`. The deny reason names the source
    (`see plugins/claudness/settings/mcp-blocklist.txt` for file entries, or
    `disabled via claudness config (mcp.<name>=false …)` for config
    entries) so users know where to undo it.
  - Matcher wiring lives in `plugins/claudness/settings/hooks.fragment.json`
    and `plugins/claudness/hooks/hooks.json`; both route the `mcp__` prefix
    through `plugins/claudness/hooks/pre-tools/modules/mcp-blocker.sh`.

Agents and commands are loaded by Claude Code from the plugin manifest at
session start, so they cannot be toggled at runtime. A future `claudness
sync` command may rewrite the manifest from config; until then, install or
uninstall the plugin to control them.

## Examples

Disable engram completely (no recall hint, no install nag, no MCP calls):

```json
{ "version": 1, "skills": { "engram": false }, "mcp": { "engram": false } }
```

Disable a single hook only in this project:

```json
{ "version": 1, "hooks": { "user-prompt-submit": false } }
```

Block several MCP servers without touching the blocklist file:

```json
{ "version": 1, "mcp": { "canva": false, "figma": false } }
```

User-global disables, project-local re-enable:

```jsonc
// ~/.claude/claudness.config.json
{ "version": 1, "skills": { "ast-grep": false } }

// <repo>/.claude/claudness.config.json
{ "version": 1, "skills": { "ast-grep": true } }
```
