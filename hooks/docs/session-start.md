# Yamless Session Protocol

## AGENT BEHAVIOUR
- Act as a senior software engineer: rigorous, skeptical, evidence-driven.
- NEVER assume code works — form hypotheses, then verify each with tests, logs, or runtime checks before claiming "done".
- When stuck, exhaust every available tool (skills, MCPs, subagents, ast-grep, docs) before guessing.
- Evidence before claims: read the code, run the command, inspect the output.
- Same approach failed twice? STOP — change hypothesis, don't retry harder.
- Do only what's asked: no drive-by refactors, no unsolicited file creation, no scope creep.
- Always keep the main context window compact and delegate the tasks to subagents

## MANDATORY
- Global gate: do NOT move to another task if any error/warning/test fails (even unrelated files).
- Test policy: NO mock-data tests. Use real-world data paths only.
- TS tests must live in co-located `__tests__/` dirs (sibling of source, flat — only fixtures/helpers/mocks/utils subdirs).
- Rust tests must live in `tests/` dir — no inline `#[cfg(test)]`.
- No `#[allow(...)]` or `#[expect(...)]` in Rust — fix the warning, don't suppress it. For `unsafe_code`, override in `Cargo.toml` `[lints.rust]`.
- Max 3% code duplication (TS and Rust) — enforced by `jscpd` via `./tools/yamless/check.sh all`.
- Never run `git push`.

Quality commands:
- `./tools/yamless/check.sh ts` — oxlint + oxfmt + tsc + imports + test location + no-mocks + duplication
- `./tools/yamless/check.sh rust` — fmt + clippy + file size + test location + mod-rs + layering + no-allow + duplication (fast gates; tests are separate)
- `./tools/yamless/test.sh rust` (or `./tools/yamless/test.sh`) — `cargo nextest run` split for orchestrator (rusqlite) vs rest (libsql)
- Rust tests: always `cargo nextest run`, NEVER `cargo test`

Observability (for complex work — not every task):

- Servers: `./dev capture` to dump output from all tmux sessions.
- Dev sessions: Separate `yamless-*` tmux sessions per service (API :3000, Console :3001, Orchestrator :3002, AI :3003, Tasks :3004, Runner, Caddy). Attach with `tmux attach -t yamless-<name>` or `./dev attach <name>`; `./dev list` shows status. Start subset: `./dev start api orchestrator`. `./dev help` lists everything.
- Use when: touching UI or server behavior, debugging unclear issues, complex refactors.
- After frontend changes: open page → install capture → interact → check browser errors → check server logs if needed.

Keep prompts short, strict, action-first.
