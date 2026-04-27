#!/usr/bin/env bash
set -uo pipefail
input=$(cat)

# Fast path: every deny pattern below requires one of these tokens in the
# command. Skip jq + grep spawns when none of them appears in the input.
case "$input" in
  *"rm "*|*"git push"*|*"git reset"*|*"chmod "*|*"curl "*|*"DROP "*|*":(){"*) ;;
  *) exit 0 ;;
esac

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# grep -E does not honor \s. The earlier version used (\s|$), which silently
# matched only the literal letter s or end-of-line, letting `rm -rf / extra`
# slip through. Use [[:space:]] uniformly.
deny_patterns=(
  'rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[fF][a-zA-Z]*|-[a-zA-Z]*[fF][a-zA-Z]*[rR][a-zA-Z]*|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)[[:space:]]+/([[:space:]]|$)'
  'rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[fF][a-zA-Z]*|-[a-zA-Z]*[fF][a-zA-Z]*[rR][a-zA-Z]*|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)[[:space:]]+~([[:space:]]|$)'
  'rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[fF][a-zA-Z]*|-[a-zA-Z]*[fF][a-zA-Z]*[rR][a-zA-Z]*|--recursive[[:space:]]+--force|--force[[:space:]]+--recursive)[[:space:]]+\$HOME'
  'git[[:space:]]+push[[:space:]]+.*--force([[:space:]]|$)'
  'git[[:space:]]+push.*[[:space:]]-f([[:space:]]|$)'
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
