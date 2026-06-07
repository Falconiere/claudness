# Consolidate Claude tooling from routo.io and yamless.io into my-claude

**Date:** 2026-06-07
**Status:** Draft (awaiting user review)
**Owner:** falconiere

## Goal

Merge the Claude Code configuration that currently lives in two project repos (`/Volumes/Projects/routo.io` and `/Volumes/Projects/yamless.io`) into the standalone `/Volumes/Projects/my-claude` repo so it can be reused across any project. Every artifact must be **project-agnostic**: no hardcoded repo names, paths, or tool assumptions.

Source inventory:

- `routo.io/.claude/` (agents, commands, hooks, settings, skills) + `routo.io/.tooling/` + `routo.io/.agents/skills/lgpd/` + routo-specific `AGENTS.md`, `CLAUDE.md`, `skills-lock.json`.
- `yamless.io/.claude/` (same shape, partial overlap) + `yamless.io/.tooling/` (includes `__tests__/` bats suite and `.env`).

Target: a single home in `my-claude` that any future project can symlink into `.claude/` and `tooling/`.

## Non-goals

- Plugin manifest (`plugins/falconiere/plugin.json`). Cheap to add later when there is more than one profile; out of scope now.
- Source-repo cleanup. Routo and yamless keep their copies until the consolidated version is verified.
- CLAUDE.md extraction. Both source CLAUDE.md files are project-specific; each repo keeps its own.
- Migration of routo-only `gitnexus`, `grepai`, `mobile-e2e`, `lgpd`, `AGENTS.md`, `skills-lock.json`, `.agents/` — explicitly skipped.
- Migration of `.env` files. Required env vars are documented instead.

## Layout

Follows the existing `my-claude/README.md` layout (`skills/`, `agents/`, `commands/`, `hooks/`, `mcp/`, `settings/`) and adds a top-level `tooling/` for the shared helper scripts that today live under `.tooling/`.

```
my-claude/
├── skills/
│   ├── code-intel/          # SKILL.md + scripts/ (ast-grep + engram modules only) + references/
│   ├── context7/            # SKILL.md
│   ├── exa-search/          # SKILL.md
│   ├── agent-memory/        # SKILL.md (from routo, verify generic)
│   └── ast-grep/            # SKILL.md (from routo, verify generic)
├── agents/
│   └── deep-explore.md
├── commands/
│   ├── commit.md
│   └── review-and-commit.md
├── hooks/
│   ├── session-start.sh
│   ├── session-end.sh
│   ├── pre-compact.sh
│   ├── user-prompt-submit.sh
│   ├── pre-tools/
│   │   ├── mod.sh
│   │   └── modules/
│   │       ├── bash-commands.sh
│   │       ├── code-edit-rules.sh
│   │       ├── commit-gate.sh
│   │       ├── mcp-blocker.sh        # yamless-only originally
│   │       ├── protected-files.sh
│   │       ├── push-review.sh        # yamless-only originally
│   │       ├── quality-gate.sh
│   │       ├── search-nudge.sh
│   │       └── __tests__/            # bats suites from yamless
│   ├── post-tools/
│   │   ├── mod.sh
│   │   └── modules/
│   │       ├── gate-status.sh
│   │       ├── rust-quality.sh       # yamless-only originally
│   │       └── ts-quality.sh
│   └── docs/                         # union of both repos' hook docs
├── tooling/
│   ├── context7/search.sh
│   ├── exa-search/search.sh
│   ├── __tests__/                    # bats suites from yamless
│   └── README.md                     # required env vars + setup
├── settings/
│   ├── hooks.fragment.json           # PreToolUse / PostToolUse / SessionStart / etc.
│   ├── permissions.fragment.json     # allowlist (union of both repos)
│   ├── protected-files.txt           # data extracted from protected-files.sh
│   ├── bash-allowlist.txt            # data extracted from bash-commands.sh
│   ├── mcp-blocklist.txt             # data extracted from mcp-blocker.sh
│   └── README.md                     # jq merge recipe
└── mcp/                              # placeholder (empty for now)
```

## File resolution (per-file diff loop)

For each filename present in both source repos:

1. Run `diff` on the two versions.
2. If identical, copy once into `my-claude`.
3. If different, present the diff to the user inline, ask which to keep or how to merge. Default lean: yamless where it adds a feature routo lacks (push-review, rust-quality, mcp-blocker, bats tests). Routo where routo has a fix yamless lacks.
4. Record the resolution choice in the consolidation plan output so it is auditable.

Routo-only files that DO migrate (verify generic first):

- `skills/agent-memory/SKILL.md`
- `skills/ast-grep/SKILL.md`
- `skills/code-intel/references/cypher.md` (only if it does not reference GitNexus internals — otherwise drop)

Routo-only files that DO NOT migrate:

- `skills/gitnexus/**`, `skills/grepai/**`
- `skills/code-intel/scripts/modules/gitnexus.sh`, `grepai.sh`
- `commands/mobile-e2e.md`
- `.agents/skills/lgpd/**`
- `AGENTS.md`, `CLAUDE.md`, `skills-lock.json`

Yamless-only files that DO migrate: all of them (push-review, rust-quality, mcp-blocker, bats tests, ast-grep helpers).

Yamless-only files that DO NOT migrate: `.tooling/.env`, `.tooling/.env.example` (secrets handled separately, see below).

## Agnosticism audit and refactor

Every shell script is audited for repo-specific coupling before it lands. Audit method:

```bash
grep -rEn 'routo|yamless|/Volumes/Projects/(routo|yamless)|console-app' \
  hooks/ tooling/ skills/
```

Suspected coupling per file and the refactor strategy:

| File | Suspected coupling | Refactor strategy |
|---|---|---|
| `hooks/session-start.sh` | Loads project name, paths, custom welcome | Detect project root via `git rev-parse --show-toplevel`; project name from `basename`. Remove hardcoded names. |
| `hooks/user-prompt-submit.sh` | May grep project-specific files for context injection | Make context injection opt-in via a per-repo `.claude/context.sh` that the global hook sources when present. No-op when absent. |
| `hooks/post-tools/modules/ts-quality.sh` | `bun`/`turbo` and specific tsconfig paths | Detect package manager from lock files (`bun.lock`/`pnpm-lock.yaml`/`package-lock.json`). Detect tsconfig via `git ls-files '**/tsconfig*.json'`. No-op when nothing matches. |
| `hooks/post-tools/modules/rust-quality.sh` | `cargo` and workspace assumptions | No-op if no `Cargo.toml`. Detect workspace root via `cargo locate-project --workspace`. |
| `hooks/pre-tools/modules/push-review.sh` | Branch naming, base branch | Read base from `git symbolic-ref refs/remotes/origin/HEAD`. Fall back to `main` only when remote is absent. |
| `hooks/pre-tools/modules/commit-gate.sh` | Conventional commits prefix list | If prefix list is hardcoded, move to `settings/commit-prefixes.txt` and source. |
| `hooks/pre-tools/modules/protected-files.sh` | Path patterns | Move patterns to `settings/protected-files.txt`. Script reads the list. |
| `hooks/pre-tools/modules/code-edit-rules.sh` | Repo-specific lint rules | Extract rules to `settings/code-edit-rules.json`. Script reads and applies. |
| `hooks/pre-tools/modules/bash-commands.sh` | Allowlist / denylist | Move to `settings/bash-allowlist.txt` / `bash-denylist.txt`. |
| `hooks/pre-tools/modules/quality-gate.sh` | Tool invocations | Tool-detect with `command -v`; skip silently when missing. |
| `hooks/pre-tools/modules/mcp-blocker.sh` | MCP server names | Move to `settings/mcp-blocklist.txt`. |
| `tooling/context7/search.sh` | API key from env | Should already be env-based — verify, add `command -v jq curl` guards. |
| `tooling/exa-search/search.sh` | Same | Same. |
| `skills/code-intel/scripts/modules/ast-grep.sh` | Project language assumptions | Auto-detect language from file extension on the target. |
| `skills/code-intel/scripts/modules/engram.sh` | Mostly a CLI wrapper | Verify no hardcoded port (default 7437) or database path; respect `ENGRAM_*` env vars. |

### Refactor principles

- **Auto-detect over hardcode.** Repo root via `git rev-parse`. Package manager via lock files. Languages via file extensions.
- **Graceful no-op.** Hook exits 0 if tooling is absent — for example, no `cargo` means `rust-quality.sh` is silent.
- **Data over code.** Lists (protected paths, MCP blocklist, conventional-commit prefixes) live in `settings/*.txt` or `.json`. Scripts source them. Per-project overrides go in the project's own `.claude/` files of the same name.
- **Env-driven config.** `MY_CLAUDE_PROFILE=lite|full`, `MY_CLAUDE_QUALITY=strict|warn|off`. Documented in `settings/README.md`.
- **Shellcheck clean.** Add `.shellcheckrc` (routo has one — verify it is generic, copy it).
- **Bats tests stay.** Yamless's `__tests__/` covers push-review and the tooling scripts. Extend to cover every refactored script that has non-trivial logic.

## Secrets

No `.env` files are committed. `tooling/README.md` documents required environment variables:

- `CONTEXT7_API_KEY` — Context7 search.
- `EXA_API_KEY` — Exa search.
- Any other keys discovered during the audit.

Recommended setup: export in the user's shell rc (`~/.config/fish/config.fish` or `~/.zshrc`) or use a secret manager (`pass`, `1password-cli`, `keyring`). Scripts read from `$ENV` directly. If any current script only reads from `.env`, refactor it to prefer the env var and fall back to a sibling `.env` only when explicitly opted in.

## settings.json strategy

Two JSON fragments live in `settings/` so projects can pick what they need:

- `settings/hooks.fragment.json` — `PreToolUse`, `PostToolUse`, `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreCompact` wiring. Hook paths reference the installed location (either `~/.claude/hooks/...` for global install or `${CLAUDE_PROJECT_DIR}/.claude/hooks/...` for per-project install).
- `settings/permissions.fragment.json` — union of allowlists from `routo.io/.claude/settings.json` and `yamless.io/.claude/settings.json`. Deduplicated.

`settings/README.md` shows the `jq` merge recipe:

```bash
jq -s '.[0] * .[1]' ~/.claude/settings.json my-claude/settings/hooks.fragment.json \
  > ~/.claude/settings.json.new && mv ~/.claude/settings.json.new ~/.claude/settings.json
```

And warns: do not add `.env` paths or secret files to `additionalDirectories`.

## Install

Update `my-claude/README.md` install section to cover the full set:

```bash
# Per-user (global)
ln -s "$PWD/skills"   ~/.claude/skills
ln -s "$PWD/agents"   ~/.claude/agents
ln -s "$PWD/commands" ~/.claude/commands
ln -s "$PWD/hooks"    ~/.claude/hooks

# Per-project (run from project root)
ln -s /Volumes/Projects/my-claude/skills   .claude/skills
ln -s /Volumes/Projects/my-claude/agents   .claude/agents
ln -s /Volumes/Projects/my-claude/commands .claude/commands
ln -s /Volumes/Projects/my-claude/hooks    .claude/hooks
ln -s /Volumes/Projects/my-claude/tooling  .tooling     # scripts expect .tooling at repo root
```

Tooling lives at the project's `.tooling/` (not `~/.tooling`) because the search scripts and bats tests use repo-relative paths. The refactor phase will verify and, where reasonable, prefer `$MY_CLAUDE_TOOLING` env var with `.tooling/` as fallback so a global install becomes possible.

Merge `settings/*.fragment.json` with `jq` per the recipe above.

## Process

1. **Copy phase.** Per-file diff loop per the resolution rules. Each conflict pauses for a decision.
2. **Audit phase.** Run the grep across all `.sh` and `.md` files. Triage every hit.
3. **Refactor phase.** Apply refactor principles file-by-file. Write bats tests for non-trivial logic.
4. **Verify phase.** Drop symlinks into a scratch repo (or routo/yamless after backup) and run hooks. Confirm no-op behavior on missing tooling.
5. **Document phase.** Update `README.md`, write `tooling/README.md`, write `settings/README.md`.
6. **Commit phase.** One commit per phase, conventional commits.

## Open questions

None at present. All decisions captured above.

## Out of scope

- Plugin manifest.
- Source-repo cleanup (delete `.claude/`/`.tooling/` from routo and yamless after migration is verified). Will be a separate task.
- CLAUDE.md template extraction.
