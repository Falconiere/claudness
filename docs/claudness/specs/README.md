# Claudness Specs

Design specs for claudness work, authored by the `spec` skill and audited by `spec-review`.
They sit between brainstorm (decide the shape) and plan (implementation steps) in the
`brainstorm → spec → spec-review → plan → plan-review → execution → execution-review → test`
workflow.

## Conventions

- **Filename**: `<YYYY-MM-DD>-<slug>-design.md` (date authored, kebab-case slug).
- **Status header**: `Draft` → `Approved` (or `Needs changes`) — `spec-review` flips it.
- **Template**: see the `spec` skill (`plugins/claudness/skills/spec/SKILL.md`). Sections:
  Problem · Non-Goals · Architecture · Interfaces / Schema · Acceptance criteria · Open Questions.

A spec is a contract: precise enough that `plan` can turn it into steps and `test` into
real-data checks, without re-arguing the design. Keep each section tight — cut anything that
isn't load-bearing.
