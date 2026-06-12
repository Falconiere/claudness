---
name: test
description: Use when writing or organizing tests for any feature or bugfix. Enforces the claudness test layout (TS __tests__/, Rust tests/), real-world data only (NO mocks), and test-first discipline. Native claudness workflow; fifth phase of brainstorm → spec → plan → execute → test.
---

# Test

Fifth phase of the claudness workflow. Tests are written **with** the code, not after — this skill defines how and where.

**Trigger phrases:** write tests, add a test, test this, TDD, cover this with tests.

## The two non-negotiables

1. **Real-world data only — NO mock-data tests.** Exercise real inputs and real code paths. A test that asserts against fabricated/mocked data proves nothing. Stubbing an external network call or a crashing binary to test failure handling is allowed; mocking the data under test is not.
2. **Colocate by language convention:**
   - **TS / TSX** → sibling `__tests__/` directory at the same level as the code under test. Keep it flat (only `fixtures/`, `helpers/`, `mocks/`, `utils/` subdirs). Files `*.test.ts` / `*.spec.ts`.
   - **Rust** → sibling `tests/` directory, kept flat (only `fixtures/`, `helpers/`, `common/` subdirs). No inline `#[cfg(test)]` in `src/`.

The lang-quality gate enforces both placements on every edit — a misplaced test fails the gate.

## Test-first loop

1. **Red** — write a failing test that pins the intended behavior (for a bug, reproduce it first).
2. **Green** — write the minimum code to pass.
3. **Refactor** — clean up under the gate (line limits, no swallowed errors, concise docs), tests staying green.

## Practice

- One behavior per test; name the test after the behavior, not the function.
- Prefer the project's real runner (vitest/jest/bun test, cargo test/nextest) over hand-rolled harnesses.
- Cover the real edge cases surfaced in `brainstorm`, not happy-path only.
- A failing test is a finding — report it with the output; never mark work done while a test is red.

## Output

A green suite that exercises real data and lives in the right place. Branch is ready for review/finish.
