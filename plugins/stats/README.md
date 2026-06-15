# stats

An on-demand `/stats` report of your **measured** Claude Code usage — tokens, estimated cost, and cache-hit rate — read straight from the session transcripts on disk. The first-party, no-estimate counterpart to the statusline's `wk:` sliver.

The default view is a glyph dashboard: a boxed header with a cache-hit gauge, a 14-day sparkline trend, and bar charts per project/model — glyph-only (no ANSI), so it renders identically wherever it is shown. `--html` exports the same report as a self-contained, `prefers-color-scheme`-aware HTML file and opens it in the browser.

Standalone: only needs `jq`, no always-on hooks. It only reads `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/**` and memoizes a small per-session rollup under `${CLAUDE_CONFIG_DIR:-~/.claude}/stats/`.

## Usage

```sh
/stats                       # full digest: economics + all breakdowns
/stats --today               # today only
/stats --week                # current ISO week
/stats --all                 # all-time (default window)
/stats --project toolu.sh    # one project (grouped on exact path)
/stats --model opus          # one model tier (windows n/a under this filter)
/stats --session <id>        # one session
/stats --this-session        # newest session in this directory (caveman-stats style)
/stats --since 2026-06-01    # only sessions active on/after a date
/stats --limit 20            # widen the top-N tables (default 10)
/stats --html                # write a self-contained HTML report and open it
/stats --json                # machine-readable aggregate
/stats --rescan              # ignore the cache, recompute from transcripts
```

## What it reports

- **Economics** — tokens, estimated $ cost (per-model rates), cache-hit %.
- **Windows** — today, this week, all-time.
- **Per project** — grouped on the working directory (`.cwd`), so repos sharing a basename stay separate.
- **Per model** — Opus / Sonnet / Haiku split.
- **Per session** — top sessions by tokens.
- **Activity** — tool-mix, attributed-skill (toolu phase) counts, current quality-gate status, comemory count.

## How it works

The transcript is the source of truth (`usage.sh`): assistant messages are deduped by `message.id` keeping the **final** streamed frame, priced per model (`pricing.sh`), and bucketed by local day. Each session is rolled up once and cached (`scan.sh`), keyed on the transcript mtime plus `schema_version` + `pricing_id` — so a pricing change recomputes rather than serving stale cost, an actively-written session busts its own cache (its mtime advances), and a deleted transcript drops from the totals (orphan caches are GC'd). `aggregate.sh` reduces the rollups into the report views (including a 14-day daily series for the trend); `render.sh` draws the glyph dashboard (via the `widgets.sh` bar/gauge/sparkline/box primitives) or emits `--json`, and `render_html.sh` fills `templates/report.html` for `--html`.

`tokens` is the rate-limit-pacing total (`input + output + cache_write`); `cache_read` is tracked separately (it dominates volume but is billed ~0.1×). **Cost is a sticker-price estimate, not an Anthropic bill.**

## Tests

`bats plugins/stats/__tests__` — real Claude Code transcripts projected to the fields stats reads, with all text stripped (see `__tests__/fixtures/README.md`). No mocks.
