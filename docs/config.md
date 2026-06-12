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
  "mcp":     { "<server>": true | false },
  "lang":    { "ts":   { "maxFileLines": 300, "maxFnLines": 60 },
               "rust": { "maxFileLines": 500, "maxFnLines": 50, "maxImplLines": 200 } }
}
```

`version` is reserved for future schema bumps; v1 is the current value.
See `plugins/claudness/settings/claudness.config.example.json` for a fully-populated example.

### Quality thresholds (`lang`)

The lang-quality gate's line limits are not hardcoded. Each threshold resolves
with this precedence (first hit wins, always a positive integer):

1. **Project / user override** — the `lang.<ts|rust>.<key>` value above.
2. **Native linter config** (TS `maxFileLines` only) — the `max-lines` rule from
   the *active* linter's JSON config: `.oxlintrc.json` when oxc is detected,
   `.eslintrc.json` when eslint is (detection precedence is biome > oxc > eslint;
   biome has no `max-lines`, so it falls through to the default). Only the active
   linter's file is read — a repo carrying both (e.g. mid-migration) does not
   chain between them. All encodings parse: `N`, `["error", N]`,
   `["error", {"max": N}]`. Flat config `eslint.config.{js,mjs,ts}` is JavaScript
   and not parsed — it falls through.
3. **Built-in default** — TS `maxFileLines` 300 / `maxFnLines` 60; Rust
   `maxFileLines` 500 / `maxFnLines` 50 / `maxImplLines` 200.

The file-size limit counts real code only: `count_code_lines`
(`plugins/claudness/hooks/lib/detect.sh`) excludes blank lines and `//` + `/* */`
comments. It is a lexical heuristic, not a parser — a `//` inside a string literal
(e.g. a `"https://…"` URL) is treated as a line-ending comment, so a file dense in
such literals can count slightly low. The gate deliberately fails *toward*
flagging: when the scan ends mid-`/* */` (an unterminated block, or a `/*` inside a
string), it falls back to the raw line count rather than risk under-counting an
oversized file.

A value of `0`, a negative, or `"off"` is treated as "no override" and falls
through to the next layer — it does not mean a limit of zero. A stringified
positive integer (`"maxFileLines": "120"`) is accepted and coerced to a number,
so configs copy-pasted from sources that quote numbers still work. The gate never
invokes biome/oxc/eslint/prettier/clippy/rustfmt; detecting them only tunes
advisory wording. Resolver: `plugins/claudness/hooks/lib/quality-config.sh`.

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
  - **Exception — `session-end` is opt-IN**: the end-of-session engram
    "save your learnings" reminder is OFF by default (the agent-memory
    protocol already saves proactively, so the Stop-time nag is redundant
    noise). It emits only when you set `hooks.session-end: true`. Every other
    hook is opt-out (on unless set to `false`).

- `mcp.<name> = false`
  - Any `mcp__<name>__*` tool invocation is blocked at `PreToolUse` with
    `permissionDecision: "deny"`. The deny reason names the source
    (`see plugins/claudness/settings/mcp-blocklist.txt` for file entries, or
    `disabled via claudness config (mcp.<name>=false …)` for config
    entries) so users know where to undo it.
  - Matcher wiring lives in `plugins/claudness/hooks/hooks.json`, which routes
    the `mcp__` prefix through `plugins/claudness/hooks/pre-tools/modules/mcp-blocker.sh`.

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
