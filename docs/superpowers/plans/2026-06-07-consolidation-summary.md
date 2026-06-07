# Consolidation summary — 2026-06-07

- Source repos: `/Volumes/Projects/routo.io`, `/Volumes/Projects/yamless.io`
- Target: `/Volumes/Projects/my-claude`
- Files migrated: 26 divergent (resolved per `2026-06-07-consolidate-resolutions.log`) + 3 identical + 3 routo-only (generic-checked) + 10 yamless-only.
- Files skipped: gitnexus skills, grepai skill, mobile-e2e command, lgpd skill, AGENTS.md, CLAUDE.md, skills-lock.json, `.env` files, `.agents/`, settings.local.json.
- Audit + refactor: every script sources `hooks/lib/detect.sh`; hardcoded lists moved to `settings/*.txt|.json`.
- Settings fragments: `hooks.fragment.json` + `permissions.fragment.json` (sanitized per the security review).
- Tests: bats suite under `hooks/**/__tests__/`, `hooks/lib/detect.bats`, `hooks/{session-start,user-prompt-submit}.bats`, and `tooling/__tests__/`.
- Final agnosticism re-grep (excluding `.bats` regression guards): 0 hits.

Source repos still contain their `.claude/` and `.tooling/` directories. Cleanup of those is out of scope for this plan.
