# Review, Fix & Commit Completed Work
Run AFTER all tasks are completed. Reviews changes on the current branch, fixes gaps, and commits. Does NOT merge. Does NOT push.

## 1. Identify scope
- Current branch: `git rev-parse --abbrev-ref HEAD`.
- Committed changes: `git log development..HEAD --oneline` + `git diff development...HEAD --stat`.
- Uncommitted changes: `git status --short` + `git diff --stat HEAD`.
- If no changes exist (committed or working-tree), STOP and report "nothing to review".
- Group changed files by package/crate.

## 2. Launch parallel review subagents
For each package/crate with changes, dispatch a subagent (use `superpowers:dispatching-parallel-agents` skill) that:
- Reads every changed file in its scope — both committed diff and working-tree state.
- Searches for gaps: missing error handling at boundaries, untested paths, dead code, over-engineering, unclear naming.
- Searches for simplification: unnecessary abstractions, duplicated logic, verbose code.
- Verifies tests exist for new/changed behavior and use real data (NO mocks).
- Reports concrete issues with file paths and line numbers — no vague feedback accepted.

## 3. Fix all reported issues
- Fix every gap, simplification, and missing test reported by the subagents.
- Fix any pre-existing errors or warnings in touched files (zero tolerance).
- Same approach failed twice? STOP — change hypothesis, don't retry harder.

## 4. Run full quality gates
- `./tools/yamless/check.sh ts` — ZERO errors, ZERO warnings.
- `./tools/yamless/check.sh rust` — ZERO errors, ZERO warnings (fast gates; tests separate).
- `./tools/yamless/test.sh` — full Rust suite must be green.
- If any gate fails, fix and re-run ALL gates until fully green. No exceptions.

## 5. Commit
- Stage intentionally: `git add` only files that belong in this commit — no drive-by staging.
- Use conventional commit messages: `feat:`, `fix:`, `refactor:`, `test:`, `chore:`, `docs:`.
- One logical change per commit — split into multiple commits if scope requires it.
- Never use `--no-verify`. If hooks fail, fix the underlying issue and retry.
- Never run `git push`.

## 6. Completion
- Report: what was reviewed, what was fixed, final gate status, commit hashes produced.
- Do not mark complete unless all gates are green AND working tree is clean.
