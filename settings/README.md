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
| `bash-allowlist.txt`          | `hooks/pre-tools/modules/bash-commands.sh`        | Commands the bash guard treats as always-allowed.                  |
| `bash-denylist.txt`           | `hooks/pre-tools/modules/bash-commands.sh`        | Tokens the bash guard rejects via argv-aware parsing.              |
| `code-edit-rules.json`        | `hooks/pre-tools/modules/code-edit-rules.sh`      | Pattern rules for Write/Edit gating on source files.               |
| `commit-prefixes.txt`         | `hooks/pre-tools/modules/commit-gate.sh`          | Allowed Conventional Commits prefixes for `git commit` messages.   |
| `mcp-blocklist.txt`           | `hooks/pre-tools/modules/mcp-blocker.sh`          | MCP tool names that should never be invoked.                       |
| `protected-files.txt`         | `hooks/pre-tools/modules/protected-files.sh`      | Paths the edit guard refuses to modify (lockfiles, secrets, etc.). |
| `rust-unsafe-exemptions.txt`  | `hooks/post-tools/modules/rust-quality.sh`        | Files/paths exempt from the `unsafe` Rust check.                   |

Each plain-text file is one entry per line, `#` for comments. JSON files
follow whatever schema the consuming script documents.

Per-project overrides: drop a file of the same name into the project's
`.claude/settings/` directory. The hook prefers `$MY_CLAUDE_SETTINGS_DIR`
(if set) before falling back to the global location.

## Env vars

| Variable                  | Effect                                  |
|---------------------------|-----------------------------------------|
| `MY_CLAUDE_SETTINGS_DIR`  | Directory the hooks read data files from |
| `MY_CLAUDE_QUALITY`       | `off` to disable `quality-gate.sh`       |
| `MY_CLAUDE_ENGRAM_PROJECT`| Override the project name for engram     |
