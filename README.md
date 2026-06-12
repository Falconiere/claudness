# claudness

Personal collection of [Claude Code](https://claude.com/claude-code) extensions — plugins, skills, hooks, subagents, slash commands, and configuration.

Installable as a plugin: `claudness@falconiere` (see [Install](#install) below).

## Layout

```
.
├── docs/                     # Repo documentation (runtime config, design notes, plans)
└── plugins/
    ├── claudness/            # Core plugin: hook engine + security/process gates
    │   ├── .claude-plugin/   # plugin.json manifest
    │   ├── skills/           # Standalone skills (context7, exa-search, brainstorm, spec, spec-review, plan, execute, test)
    │   ├── agents/           # Subagent definitions (.md with YAML frontmatter)
    │   ├── commands/         # Slash commands (.md prompt templates)
    │   ├── hooks/            # Hook scripts (PreToolUse, PostToolUse, SessionStart, etc.) + hooks.json
    │   ├── tooling/          # Helper CLIs used by skills (context7, exa-search) + bats tests
    │   └── settings/         # Reusable settings.json fragments + hook data files
    ├── code-intel/           # Domain plugin: ast-grep + engram skills, registry-driven hooks
    │   ├── .claude-plugin/   # plugin.json manifest
    │   ├── skills/           # code-intel, agent-memory, ast-grep
    │   └── hooks/            # register.sh (SessionStart) + pre-tools.d/ source modules
    └── lang-quality/         # Domain plugin: Rust + TypeScript PostToolUse quality checks
        ├── .claude-plugin/   # plugin.json manifest
        └── hooks/            # register.sh (SessionStart) + post-tools.d/ source modules
```

Everything a plugin ships lives under its own `plugins/<name>/` directory — no
symlinks, no content outside the plugin root, so marketplace installs get the
whole working tree. Domain plugins contribute hook modules to the core
dispatcher through the runtime registry: their `register.sh` (SessionStart)
mirrors `hooks/<event>.d/*.sh` into `~/.claude/claudness/<event>.d/` as
`<plugin-spec>__<name>.sh`, and the claudness core executes those copies only
while the owning plugin is installed.

## Conventions

### Skills
- One directory per skill containing `SKILL.md`.
- Frontmatter: `name`, `description` (when-to-trigger phrasing), optional `allowed-tools`.
- Keep `SKILL.md` short; push detail into sibling files (`references/`, `scripts/`, `assets/`).
- **Workflow skills** — `brainstorm → spec → plan → execute → test` are native, opinionated
  process skills. They bake in the house conventions: one-responsibility files named
  after their export, tests colocated by language (TS `__tests__/`, Rust `tests/`),
  real-world data only (no mocks), concise-but-required docs, and per-project line
  limits. The lang-quality gate enforces those conventions on every edit. `spec` writes a
  design contract to `docs/claudness/specs/`; `spec-review` audits it before planning.

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

## Plugin dependencies

Declared via the official `dependencies` field in each `plugin.json`. Their
marketplaces must be configured before install (Claude Code auto-installs a
declared dependency only from an already-added marketplace); the root
`marketplace.json` allowlists the cross-marketplace sources via
`allowCrossMarketplaceDependenciesOn`.

| Plugin | Depends on | Why |
|--------|-----------|-----|
| `claudness` | `code-simplifier@claude-plugins-official` | review/simplify pipelines (`review-and-commit`, `push-review`, `address-pr-comments`) delegate simplification to the `code-simplifier` subagent |
| `claudness` | `caveman@caveman` | review pipelines delegate diff review to `caveman:cavecrew-reviewer` |
| `code-intel` | `claudness@falconiere` | its registry hook modules execute through the claudness core dispatcher and source `hooks/lib` via `CLAUDNESS_LIB_DIR` |
| `lang-quality` | `claudness@falconiere` | its PostToolUse quality modules execute through the claudness core dispatcher and source `hooks/lib` via `CLAUDNESS_LIB_DIR` |

Add the upstream marketplaces first:

```
/plugin marketplace add anthropics/claude-plugins-official
/plugin marketplace add JuliusBrussee/caveman
```

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
