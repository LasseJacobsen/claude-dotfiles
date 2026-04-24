#!/usr/bin/env bash
input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

deny_patterns=(
  'rm[[:space:]]+-[rRfF]*[[:space:]]+/(\s|$)'
  'rm[[:space:]]+-[rRfF]*[[:space:]]+~(\s|$)'
  'rm[[:space:]]+-[rRfF]*[[:space:]]+\$HOME'
  'git[[:space:]]+push[[:space:]]+.*--force(\s|$)'
  'git[[:space:]]+push[[:space:]]+-f(\s|$)'
  'git[[:space:]]+reset[[:space:]]+--hard[[:space:]]+origin'
  'chmod[[:space:]]+-R[[:space:]]+777'
  ':\(\)\{.*\|:&.*\};:'
  'curl[[:space:]].*\|[[:space:]]*(bash|sh|zsh)'
  'DROP[[:space:]]+TABLE'
)

for p in "${deny_patterns[@]}"; do
  if echo "$cmd" | grep -qE "$p"; then
    jq -cn --arg reason "Blocked by safety policy: matches pattern /$p/" \
      '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$reason}}'
    exit 0
  fi
done
exit 0
