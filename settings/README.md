# settings/

Reusable Claude Code settings fragments plus data files consumed by hooks.

## Fragments

- `hooks.fragment.json` — `PreToolUse` / `PostToolUse` / `SessionStart` / `Stop` / `UserPromptSubmit` / `PreCompact` wiring.
- `permissions.fragment.json` — sanitized union of permission allowlists/denylists from the source repos.

### Merge into your settings

```bash
jq -s '.[0] * .[1]' ~/.claude/settings.json settings/hooks.fragment.json \
  > ~/.claude/settings.json.new && mv ~/.claude/settings.json.new ~/.claude/settings.json

jq -s '.[0] * .[1]' ~/.claude/settings.json settings/permissions.fragment.json \
  > ~/.claude/settings.json.new && mv ~/.claude/settings.json.new ~/.claude/settings.json
```

> Never add a path that contains secrets (e.g. `.env`) to `additionalDirectories`.

## Security note

The settings.json deny matcher is substring-based and unreliable for argv
shapes like `node -e`, `git push --force`, or `git push origin main`. The
`hooks/pre-tools/modules/bash-commands.sh` hook performs argv-aware
enforcement using `bash-denylist.txt`. Both layers must be installed for
the security model to hold:

- Settings denies catch obvious cases at the matcher layer.
- `bash-commands.sh` parses argv and reliably rejects the listed tokens
  even when they are embedded mid-command-line.

## Data files (read by hooks)

| File                          | Consumer                                          | Purpose                                                            |
|-------------------------------|---------------------------------------------------|--------------------------------------------------------------------|
| `bash-allowlist.txt`          | `hooks/pre-tools/modules/bash-commands.sh`        | Explicit overrides on top of the denylist (deny + allow → allowed). |
| `bash-denylist.txt`           | `hooks/pre-tools/modules/bash-commands.sh`        | Tokens the bash guard rejects via argv-aware parsing.              |
| `code-edit-rules.json`        | `hooks/pre-tools/modules/code-edit-rules.sh`      | Pattern rules for Write/Edit gating on source files.               |
| `commit-prefixes.txt`         | `hooks/pre-tools/modules/commit-gate.sh`          | Allowed Conventional Commits prefixes for `git commit` messages.   |
| `mcp-blocklist.txt`           | `hooks/pre-tools/modules/mcp-blocker.sh`          | MCP server prefixes blocked unconditionally (plain text).          |
| `claudness.config.example.json` | (reference — copy to `~/.claude/claudness.config.json`) | Example runtime opt-out config (skills/hooks/mcp). See `docs/config.md`. |
| `protected-files.txt`         | `hooks/pre-tools/modules/protected-files.sh`      | Paths the edit guard refuses to modify (lockfiles, secrets, etc.). |
| `rust-unsafe-exemptions.txt`  | `hooks/post-tools/modules/rust-quality.sh`        | Files/paths exempt from the `unsafe` Rust check.                   |

Each plain-text file is one entry per line, `#` for comments. JSON files
follow whatever schema the consuming script documents.

Allow/deny semantics for the bash guard: the denylist is checked first; a
command that matches a deny rule is still allowed if it also matches an
allowlist rule (the allowlist is an explicit override, not a default gate).
Commands that match no deny rule are allowed by default.

Lookup order (see `detect_settings_dir` in `hooks/lib/detect.sh`):
`$MY_CLAUDE_SETTINGS_DIR` (if set) → `~/.claude/settings` (if it exists) →
this repo's `settings/` directory, resolved relative to the hooks. There is
no per-project `.claude/settings/` lookup — to override per project, point
`MY_CLAUDE_SETTINGS_DIR` at a project-local directory.

## Env vars

| Variable                  | Effect                                  |
|---------------------------|-----------------------------------------|
| `MY_CLAUDE_SETTINGS_DIR`  | Directory the hooks read data files from |
| `MY_CLAUDE_QUALITY`       | `off` to disable `quality-gate.sh`       |
| `MY_CLAUDE_ENGRAM_PROJECT`| Overrides the engram project scope used by the code-intel wrapper (`skills/code-intel/scripts/modules/engram.sh`). Not read by any hook. |

## Runtime config

For per-skill, per-hook, or per-MCP opt-out without touching the data
files above, see `docs/config.md`. The config file lives at
`~/.claude/claudness.config.json` (or the project-local override) and is
deep-merged at runtime. The `mcp-blocklist.txt` blocklist still works in
parallel; either source can block a server.
