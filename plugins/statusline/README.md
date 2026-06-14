# statusline

An optional Claude Code statusline. One line, assembled defensively from the
statusline JSON Claude Code sends on stdin:

```
model | effort:high | ctx:45k/200k (22%) | ✗ gate:failing | my-folder | main | [CAVEMAN]
```

| Segment | Source | Shows when |
|---------|--------|------------|
| model | `.model.display_name` | always |
| effort | `.effort.level` | the model reports an effort level |
| ctx | `.context_window.*` | always |
| `✗ gate:failing` | `.claude/tmp/quality-gate-status.json` at the git root | a **gate writer** (e.g. the `lang-quality` / `claudness` plugins) marks the gate failing |
| folder + branch | git, from the workspace dir | inside a git repo |
| `[CAVEMAN]` | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active` | the **caveman** plugin is active |

The gate and caveman segments degrade gracefully — if the file they read is
absent, the segment simply doesn't render. So statusline is **standalone**: it
declares no plugin dependencies. Those two segments just light up automatically
when the relevant plugins are also installed.

## Install & wire up

Claude Code does not let a plugin declare `statusLine` in its manifest, so the
SessionStart hook symlinks the script to a stable, version-independent path:

```
~/.claude/statusline/statusline.sh   (→ the installed plugin's statusline.sh)
```

1. Install the plugin:

   ```
   /plugin install statusline@falconiere
   ```

2. Wire it once in your `settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline/statusline.sh"
     }
   }
   ```

   (Use `$CLAUDE_CONFIG_DIR/statusline/statusline.sh` if you run with a custom
   config dir.) The symlink is refreshed every session, so plugin updates are
   picked up automatically with no settings change. The hook never clobbers a
   real file you place at that path — it only owns its own symlink.

## Migrating from claudness ≤ 1.5.0

The statusline used to ship inside the `claudness` plugin and auto-symlinked to
`~/.claude/claudness/statusline.sh`. It now lives here. To keep your statusline:

- `/plugin install statusline@falconiere`, and
- re-point `settings.json` from `~/.claude/claudness/statusline.sh` to
  `~/.claude/statusline/statusline.sh`.

Claudness no longer creates the old symlink and sweeps away the dangling one it
used to own, so an un-migrated `settings.json` will fail loudly (missing file)
rather than silently pointing into a cleaned plugin cache.
