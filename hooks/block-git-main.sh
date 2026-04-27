#!/usr/bin/env bash
set -uo pipefail
input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
branch=$(git branch --show-current 2>/dev/null || true)

if [[ "$branch" =~ ^(main|master|prod|production)$ ]]; then
  if echo "$cmd" | grep -qE '^git (commit|push)'; then
    jq -cn --arg branch "$branch" \
      '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Direct commits/pushes to \($branch) are prohibited. Create a feature branch first."}}'
    exit 0
  fi
fi
exit 0
