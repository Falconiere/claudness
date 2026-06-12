---
name: execute
description: Use when you have a written plan to implement. Drives the plan step by step with verification checkpoints, respects the quality gate, and delegates heavy work to subagents to keep context compact. Native claudness workflow; third phase of brainstorm → plan → execute → test.
---

# Execute

Third phase of the claudness workflow. Carries out a written plan with discipline: small steps, evidence before claims, never skip the gate.

**Trigger phrases:** execute the plan, implement this, start building, work through the plan.

## Precondition

A plan exists (`plan` ran). If there's no plan for non-trivial work, write one first.

## Loop (per step)

1. **Take one step** from the plan — the smallest shippable unit.
2. **Write tests with the code** (see `test`) — real data, colocated. For a bugfix, reproduce first.
3. **Land it clean.** A PostToolUse quality gate runs on every TS/Rust edit. If it reports a violation the gate goes **failing** and blocks further edits until fixed — fix immediately; do not pile on more changes.
4. **Verify, don't assume.** Run the command, read the output. "Done" requires evidence (test pass, log, runtime check), never a guess.
5. **Checkpoint** with the user at meaningful boundaries, or after each independent workstream.

## Rules

- **Global gate** — do NOT move to the next step while any error/warning/test failure stands, even in unrelated files.
- **Delegate to stay compact** — push exploration, large reads, and parallelizable work to subagents; keep the main context lean.
- **No scope creep** — do only what the plan calls for. New needs go back to `plan`, not into this step.
- **Honor the layout** — files named after their export, one responsibility each, under the line limit, docs present and concise.
- **Same approach failed twice? Stop.** Change the hypothesis (`systematic-debugging`), don't retry harder.

## Output

Working, verified increments. When the branch is complete and green, hand off to `test` for the final pass and then to review/finish.
