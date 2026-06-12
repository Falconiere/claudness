---
name: spec-review
description: Use to review a design spec BEFORE planning or building it — check it's complete, unambiguous, scoped, and testable. Tells: "review the spec", "is this spec ready", "audit the design", "poke holes in this spec", "did we miss anything". Pairs with the `spec` skill; reviews specs under docs/claudness/specs/. Catches gaps while they're cheap (a paragraph) instead of expensive (a rewrite). Part of the claudness brainstorm → spec → spec-review → plan → plan-review → execution → execution-review → test workflow.
---

# Spec Review

The cheapest place to catch a design flaw is the spec — a missing non-goal is one line here and a week of rework after `execution`. This skill pressure-tests a spec before it becomes a plan. It is adversarial on purpose: the job is to find what's missing or unclear, not to admire what's there.

Read the spec (under `docs/claudness/specs/`) and run it against the checklist. For each item, ask *would a competent builder be blocked or misled by this?* — that's the bar, not stylistic preference.

## Checklist

- **Problem is real and stated** — can you name the user pain in one sentence from the spec alone? A solution in search of a problem fails here.
- **Non-goals are explicit** — is the boundary drawn? Unstated scope is scope that creeps. If the non-goals are empty, that's almost always a gap.
- **Architecture is decided, with the trade-off named** — one chosen approach, not a menu. If the spec hedges between options, the decision was deferred, not made — that's a blocker.
- **Interfaces/schema are concrete** — could you start building from the signatures/types/paths given, or would you have to invent the contract? Vagueness here is rework later.
- **Failure modes and edge cases** — what happens on bad input, partial failure, empty/absent/concurrent cases? A spec that only covers the happy path is half a spec.
- **Acceptance criteria are testable on real data** — does each criterion map to a check `test` could write against real inputs (no mocks)? "Works correctly" is not a criterion; "given real file X, produces Y" is.
- **Open questions are resolved or owned** — anything unresolved must have an owner and not silently block the build.
- **Scope and size are sane** — does the architecture imply a file or module that blows past the size ceilings? If so, the split belongs in the spec, not in a gate complaint later.

## Output

One line per finding, severity-tagged, location + problem + fix — no praise, no restating what's fine:

```
<section>: 🔴 blocker: <what's missing/wrong>. <the fix>.
<section>: 🟡 should-fix: <gap>. <the fix>.
<section>: 🔵 consider: <minor>. <the fix>.
```

End with a verdict and update the spec's `Status:` field:
- **Approved** → set `Status: Approved`. Ready for `plan`.
- **Needs changes** → set `Status: Needs changes`. List the blockers that must close first.

Flag only what blocks a confident plan. A review that finds nothing on a real spec usually means the review wasn't adversarial enough — or the spec is genuinely tight; say which.
