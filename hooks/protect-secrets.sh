#!/usr/bin/env bash
# Block shell commands that directly read secrets files.
# permissions.deny covers Read/Write tools; this catches Bash bypasses (issue #6631).
#
# Pattern: a file-display command followed by a secret-file path within the same
# pipeline segment ([^|&;]* stops at the segment boundary).
input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

read_tool='(cat|less|more|head|tail)'
secret_patterns=(
  '\.env($|[[:space:]])'
  '\.env\.[a-zA-Z0-9]'
  '\.(pem|key|p12|pfx)($|[[:space:]])'
  'credentials\.json($|[[:space:]])'
  '\.mcp\.local\.json($|[[:space:]])'
  '\.ssh/'
)

for p in "${secret_patterns[@]}"; do
  if echo "$cmd" | grep -qE "${read_tool}[[:space:]]+[^|&;]*${p}"; then
    jq -cn '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: shell read of a secrets file. Handle secrets through the application environment, not the shell."}}'
    exit 0
  fi
done
exit 0
