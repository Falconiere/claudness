---
name: brainstorm
description: Use BEFORE any creative or build work — new feature, component, refactor, or behavior change. Explores intent, requirements, constraints, and design trade-offs, then records the decision. Native claudness workflow; first phase of brainstorm → plan → execute → test.
---

# Brainstorm

First phase of the claudness workflow. Process skill — runs **before** any implementation skill. Goal: replace assumptions with a written, agreed design before a line of code is touched.

**Trigger phrases:** let's build, add a feature, redesign, how should we, I want to, change the behavior of, new component.

## Hard rule

Do NOT write code, scaffold files, or enter plan mode until intent and constraints are explicit. If a request says only WHAT ("add X"), you still owe the HOW conversation.

## Steps

1. **Restate intent** in one sentence. Confirm it back to the user.
2. **Surface the unknowns.** Ask only decisions you cannot resolve from the code or sensible defaults — auth method, data source, UX shape, scope boundary. Batch them; don't drip.
3. **Find what already exists.** Search for reusable functions, patterns, and prior art (use `code-intel` / `ast-grep`). Prefer extending existing code over new code.
4. **Weigh 2–3 approaches** with trade-offs (simplicity vs performance vs maintainability). Recommend one; don't just enumerate.
5. **Record the decision** — a short decision record: chosen approach, why, rejected alternatives, open risks. Save durable conventions/decisions to memory (`agent-memory`).

## Opinions baked in (carry forward to plan/execute/test)

- **Structure is opinionated and uniform** — code must be legible to both humans and AI. One responsibility per file; name files after what they export.
- **Tests colocate by language** — TS in sibling `__tests__/`, Rust in sibling `tests/`. Decide test strategy here.
- **Real data only** — no mock-data tests; design for real-world data paths.
- **Docs are required but concise** — every module/public symbol gets a one-line doc. Plan for it now.
- **File-size discipline** — default 300 lines (TS) / 500 (Rust), overridable per project. If a design implies a giant file, split it in the design.

## Output

A confirmed intent + decision record. Hand off to `plan`.
