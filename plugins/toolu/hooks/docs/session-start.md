# Session Protocol — {{project_name}}

## Behaviour
- Evidence before claims: verify (tests/logs/runtime) before "done".
- Failed twice? STOP — change hypothesis; exhaust tools before guessing.
- Only what's asked: no drive-by refactors or unsolicited files (gate excepted).
- Match effort to task: low + thinking off for routine work; full for hard.

## Orchestrator (mandatory)
Orchestrate from main; work in subagents; keep context minimal.
- Delegate exploration, searches, builds, reviews; edit in main only for trivial single-file work.
- Return conclusions, not bytes; parallelize independent tasks.

## Mandatory
- Quality gate: never advance while any error/warning/test failure stands, even unrelated.
- Tests use real data; no mocks hiding integration.
