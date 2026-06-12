Save reusable discoveries immediately after every code change (the comemory
wrapper ships in the code-intel plugin: `<code-intel plugin root>/skills/code-intel/scripts/mod.sh`):

    mod.sh comemory save "verb what in file-or-module" \
      "## What\n<what changed or was decided>\n## Why\n<root cause or rationale>\n## Where\n<file:function>\n## Watch Out\n<what to be careful about next time>" \
      --kind bug --tags "area,subtopic"
