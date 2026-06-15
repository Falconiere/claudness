# Usage stats

Report measured Claude Code token / cost / cache usage and toolu activity from the session transcripts.

Run the report and show its output verbatim:

```sh
bash ${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh $ARGUMENTS
```

Pass any arguments the user gave through unchanged. Common flags:
`--today | --week | --all`, `--project <label|path>`, `--model <substr>`, `--session <id>`, `--this-session`, `--json`, `--rescan`, `--since <YYYY-MM-DD>`, `--limit N`.

Do not summarize or reformat the output — print exactly what the script emits. Cost figures are sticker-price estimates, not a bill.
