# Agnosticism audit (2026-06-07)

Phase 4 must address every hit below. Each row maps to a refactor task (Tasks 36–50 in the implementation plan) or is fixed inline here if trivial.

Severity legend:
- `Refactor` — real coupling that needs Phase 4 work.
- `Inline` — trivial; fixed in this commit.
- `Ignore` — false positive (self-documenting agnostic regex, intentional sentinel keyword, fenced code-block example).

| File:line | Hit | Severity | Refactor task | Notes |
|---|---|---|---|---|
| hooks/docs/session-start.md:1 | "Yamless Session Protocol" title (implicit — title row) | Refactor | Task 36 | Doc is loaded verbatim by session-start.sh; brand string must come from detect_project_name or be removed |
| hooks/docs/session-start.md:18 | `./tools/yamless/check.sh all` path | Refactor | Task 36 | Replace with `tools/<project>/check.sh` or generic phrasing driven by detect.sh |
| hooks/docs/session-start.md:18 | `jscpd` tool name | Refactor | Task 36 | Tooling assumption; soften wording or gate behind detect_node_pm/detect_ts |
| hooks/docs/session-start.md:22 | `./tools/yamless/check.sh ts` path | Refactor | Task 36 | Same as line 18; uses yamless wrapper |
| hooks/docs/session-start.md:23 | `./tools/yamless/check.sh rust` path | Refactor | Task 36 | Same as line 18 |
| hooks/docs/session-start.md:24 | `./tools/yamless/test.sh rust` path | Refactor | Task 36 | Same as line 18 |
| hooks/docs/session-start.md:24 | `cargo nextest run` | Refactor | Task 36 | Mention only if detect_rust returns rust |
| hooks/docs/session-start.md:25 | `cargo nextest run` / `cargo test` | Refactor | Task 36 | Same as line 24 |
| hooks/docs/session-start.md:30 | `yamless-*` tmux session naming | Refactor | Task 36 | Project-specific dev orchestration — drop or template via detect_project_name |
| hooks/pre-tools/modules/bash-commands.sh:6 | `Use bun, not npm/yarn/pnpm/npx` (comment) | Refactor | Task 39 | Comment describes hardcoded rule; extract rule data to settings/ |
| hooks/pre-tools/modules/bash-commands.sh:8 | `Use yamless wrapper scripts` (comment) | Refactor | Task 39 | Comment describes hardcoded rule; extract |
| hooks/pre-tools/modules/bash-commands.sh:5 | `Block cargo test (use nextest)` (comment) | Refactor | Task 39 | Comment describes hardcoded rule; gate via detect_rust |
| hooks/pre-tools/modules/bash-commands.sh:38 | `Block cargo test` (comment) | Refactor | Task 39 | Same as line 5 |
| hooks/pre-tools/modules/bash-commands.sh:39 | `cargo\s+test` regex | Refactor | Task 39 | Rule should only apply if detect_rust |
| hooks/pre-tools/modules/bash-commands.sh:44 | `cargo nextest run` in error message | Refactor | Task 39 | Error message hardcoded; data-extract |
| hooks/pre-tools/modules/bash-commands.sh:50 | `Block npm/npx/yarn/pnpm` (comment) | Refactor | Task 39 | Same as line 6 |
| hooks/pre-tools/modules/bash-commands.sh:51 | `(npm\|npx\|yarn\|pnpm)` regex | Refactor | Task 39 | Should use detect_node_pm; only block PMs that aren't the project's choice |
| hooks/pre-tools/modules/bash-commands.sh:56 | `uses bun, not npm/npx/yarn/pnpm` error message | Refactor | Task 39 | Same as line 51; message references hardcoded `bun` |
| hooks/pre-tools/modules/bash-commands.sh:68 | `bun run lint` error message | Refactor | Task 39 | PM-specific; extract |
| hooks/pre-tools/modules/bash-commands.sh:74 | `Enforce yamless wrapper scripts` (comment) | Refactor | Task 39 | Same as line 8 |
| hooks/pre-tools/modules/bash-commands.sh:76 | `tools/yamless/(check\|test\|format)\.sh` + `bun run` + `yamless\s+check` | Refactor | Task 39 | Yamless path + PM keyword baked in; extract to data file |
| hooks/pre-tools/modules/bash-commands.sh:81 | `yamless wrapper scripts...` long error message | Refactor | Task 39 | Same as line 76 |
| hooks/pre-tools/modules/quality-gate.sh:35 | `bun run variants` (comment) | Refactor | Task 43 | Comment references hardcoded PM in allow-list regex |
| hooks/pre-tools/modules/quality-gate.sh:36 | `bun run`/`bun test`/`vitest`/`tsc`/`oxlint`/`oxfmt` allow-list regex | Refactor | Task 43 | Allow-list must come from detect_node_pm + detect_ts |
| hooks/pre-tools/modules/protected-files.sh:29 | `*/tools/yamless/cmd/check.sh` / `*/tools/yamless/lib/checker.sh` paths | Refactor | Task 42 | Protected-file list contains yamless paths; extract to settings/protected-files.txt |
| hooks/pre-tools/modules/protected-files.sh:34 | `tools/yamless/cmd/check.sh, tools/yamless/lib/checker.sh` in error message | Refactor | Task 42 | Same as line 29 |
| hooks/post-tools/modules/rust-quality.sh:4 | `cargo clippy, nextest` (comment) | Refactor | Task 50 | Documentation reference to Rust toolchain |
| hooks/post-tools/modules/rust-quality.sh:44 | `*yamless-secrets-runtime*` / `*yamless-sandbox*` allow-list | Refactor | Task 50 | Project-specific FFI crate names; extract to settings/rust-unsafe-allowlist.txt |
| hooks/post-tools/modules/ts-quality.sh:176 | `jscpd` (comment) | Refactor | Task 38 | Documentation comment for jscpd block |
| hooks/post-tools/modules/ts-quality.sh:178 | `bun run check` (comment) | Refactor | Task 38 | Comment references hardcoded PM |
| hooks/post-tools/modules/ts-quality.sh:186 | `.jscpd.json` config gate | Refactor | Task 38 | Skip jscpd block when binary absent (already partially gated by config file) |
| hooks/post-tools/modules/ts-quality.sh:187 | `bunx jscpd` invocation | Refactor | Task 38 | Use detect_node_pm to choose bunx/pnpm dlx/npx; guard on command -v jscpd |
| hooks/post-tools/modules/ts-quality.sh:188 | `.jscpd.json` config path | Refactor | Task 38 | Same as line 186 |
| hooks/post-tools/modules/ts-quality.sh:193 | `bun run check` in warning message | Refactor | Task 38 | PM-specific; templated message |
| hooks/post-tools/modules/gate-status.sh:41 | `TS/JS: bun run script aliases, bun test, vitest, jest, tsc` (comment) | Ignore | n/a | Comment documents intent of the regex below; the regex itself is the sentinel-detection pattern, and the file already explicitly states the wrapper-path portion is project-agnostic |
| hooks/post-tools/modules/gate-status.sh:42 | `Rust: cargo clippy/test/build/nextest` (comment) | Ignore | n/a | Same as line 41 — comment-block describing sentinel keywords used to detect quality commands |
| hooks/post-tools/modules/gate-status.sh:45 | combined `bun run`/`bun test`/`vitest`/`jest`/`tsc`/`cargo (clippy\|test\|build\|nextest)` detection regex | Ignore | n/a | Self-documented as agnostic ("wrapper-path regex is project-agnostic; per-project naming lives in the wrapper script"). Tool keywords here are intentional sentinels for identifying quality commands across all supported toolchains, not project coupling |
| hooks/session-start.sh:76 | `jscpd` in reminder string | Refactor | Task 36 | Hardcoded tool name in reminder text; gate via detect_node_pm/detect_ts |
| hooks/user-prompt-submit.sh:73 | `jscpd` in refactor-intent hint | Refactor | Task 37 | Same as session-start.sh:76; hint string assumes jscpd is in use |
| skills/ast-grep/SKILL.md:106 | `bun run check:quick` step in workflow doc | Refactor | Task 47 | Skill doc adjacent to ast-grep refactor; rewrite to project-agnostic phrasing (or auto-detect via detect_node_pm in helper that the doc points to) |

## Summary

- Total rows: 40
- Refactor: 37
- Inline: 0
- Ignore: 3

All `Refactor` hits map to a Phase 4 task (Tasks 36, 37, 38, 39, 42, 43, 47, 50). No trivial inline fixes were possible — every hit reflects a real assumption (project name, package manager, language toolchain, or wrapper-script naming) that Phase 4 will replace with detect.sh + settings/ data files.

The 3 `Ignore` rows are inside `hooks/post-tools/modules/gate-status.sh`, where the file already declares itself project-agnostic in comments and uses tool keywords purely as sentinel patterns for command detection.
