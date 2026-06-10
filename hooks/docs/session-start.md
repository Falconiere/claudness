# Session Protocol — {{project_name}}

## Behaviour
- Evidence before claims: form hypotheses, then verify with tests, logs, or runtime checks before saying "done".
- Same approach failed twice? STOP — change hypothesis, don't retry harder. Exhaust available tools (skills, MCPs, subagents, ast-grep, docs) before guessing.
- Do only what's asked: no drive-by refactors, no unsolicited files. Exception: the quality gate below.
- For multi-file exploration or large tasks, delegate to subagents to keep the main context compact.
- On session start, recall project memory: `${CLAUDE_PLUGIN_ROOT}/skills/code-intel/scripts/mod.sh engram context`

## Mandatory
- Quality gate: do NOT move to the next task while any error/warning/test failure exists — even in unrelated files. This overrides the no-scope-creep rule.
- Tests exercise real data paths; no fabricated mock data that hides integration behaviour.
