#!/usr/bin/env bash
input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
branch=$(git branch --show-current 2>/dev/null)

if [[ "$branch" =~ ^(main|master)$ ]]; then
  if echo "$cmd" | grep -qE '^git (commit|push)'; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Direct commits/pushes to %s are prohibited. Create a feature branch first."}}\n' "$branch"
    exit 0
  fi
fi
exit 0
