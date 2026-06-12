# Session Protocol — {{project_name}}

## Behaviour
- Evidence before claims: form hypotheses, then verify with tests, logs, or runtime checks before saying "done".
- Same approach failed twice? STOP — change hypothesis, don't retry harder. Exhaust available tools (skills, MCPs, subagents, ast-grep, docs) before guessing.
- Do only what's asked: no drive-by refactors, no unsolicited files. Exception: the quality gate below.
- On session start, recall project memory via the code-intel plugin's wrapper: `mod.sh comemory search "<topic>"` (`skills/code-intel/scripts/mod.sh` inside the code-intel plugin).

## Orchestrator (mandatory)
The main window is an ORCHESTRATOR, not a worker — keep its context minimal: plan and dispatch here, do the work in subagents.
- **Delegate by default**: exploration, multi-file reads, searches, builds, reviews, and bounded tasks go to subagents, even when you could do them inline. Edit in main only for a trivial single-file change.
- **Return the conclusion, not the bytes**: never pull large files or command output into main when a subagent can hand back just the answer.
- **Parallelize** independent tasks in one turn; synthesize the results, then dispatch the next step.

## Mandatory
- Quality gate: do NOT move to the next task while any error/warning/test failure exists — even in unrelated files. This overrides the no-scope-creep rule.
- Tests exercise real data paths; no fabricated mock data that hides integration behaviour.
