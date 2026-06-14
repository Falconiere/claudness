Save reusable discoveries immediately after every code change (the comemory
wrapper ships in the comemory plugin: `<comemory plugin root>/skills/agent-memory/scripts/comemory.sh`):

    comemory.sh save "verb what in file-or-module" \
      "## What\n<what changed or was decided>\n## Why\n<root cause or rationale>\n## Where\n<file:function>\n## Watch Out\n<what to be careful about next time>" \
      --kind bug --tags "area,subtopic"
