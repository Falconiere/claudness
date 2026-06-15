# caveman A/B — system-prompt sources

- **treatment-system.txt** — a *pinned snapshot* of the caveman full-mode
  instruction text, extracted faithfully from the upstream skill:
  `/Users/falconiere/.claude/plugins/marketplaces/caveman/skills/caveman/SKILL.md`
  (the mode body; frontmatter and the lite/ultra/wenyan variants are out of scope —
  the live A/B exercises the **full** default only). Snapshotted so the benchmark
  measures a fixed prompt even if upstream drifts; re-pin deliberately, not silently.
- **baseline-system.txt** — the FAIR baseline: a terse "answer concisely" prompt.
  This is the whole point of the case — caveman is compared against a baseline that
  is *already* asking for brevity, not against a verbose helpful-assistant prompt.

Pinned: 2026-06-15.
