# Session Protocol — {{project_name}}

## Behaviour
- Evidence before claims: verify (tests/logs/runtime).
- Failed twice? STOP — change hypothesis; exhaust tools first.
- Only what's asked: no drive-by refactors or unsolicited files (gate excepted).
- Match effort to task: low + thinking off for routine work; full for hard.

## Orchestrator (mandatory)
Orchestrate from main; work in subagents; keep context minimal.
- Delegate exploration, search, builds, reviews; edit inline only for trivial single-file work.
- Return conclusions, not bytes; parallelize independent tasks.
- Broad/multi-step? `orchestrator` skill.

## Mandatory
- Quality gate: never advance while any error/warning/test failure stands, even unrelated.
- Tests use real data; no mocks hiding integration.
