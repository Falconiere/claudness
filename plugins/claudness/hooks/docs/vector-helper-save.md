Save reusable discoveries immediately after every code change:

    ${CLAUDE_PLUGIN_ROOT}/skills/code-intel/scripts/mod.sh engram save "verb what in file-or-module" \
      "## What\n<what changed or was decided>\n## Why\n<root cause or rationale>\n## Where\n<file:function>\n## Watch Out\n<what to be careful about next time>" \
      --type bugfix --topic "area/subtopic"
