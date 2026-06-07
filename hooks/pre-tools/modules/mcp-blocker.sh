#!/bin/bash
# Block MCP tool usage — redirect to CLI scripts
# Triggers on: mcp__engram tool calls

: "${tool_name:=}"

case "$tool_name" in
  mcp__engram__*)
    ;;
  *)
    exit 0
    ;;
esac

jq -n '{
  "decision": "block",
  "reason": "MCP tools removed. Use CLI via code-intel scripts:\n  .claude/skills/code-intel/scripts/mod.sh engram search \"query\"\n\nInvoke the code-intel skill for full workflow guidance."
}'
exit 0
