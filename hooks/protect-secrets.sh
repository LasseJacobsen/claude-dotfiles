#!/usr/bin/env bash
set -uo pipefail
# Block shell commands that directly read secrets files.
# permissions.deny covers Read/Write tools; this catches Bash bypasses (issue #6631).
#
# Best-effort tripwire, NOT a security boundary: a determined caller can still
# exfiltrate secrets via inventive shells (compound expansions, here-docs,
# language-runtime bypasses we don't pattern-match). Treat this as a guardrail
# against accidental disclosure, and keep real secrets out of the project tree.
#
# Pattern: a file-display command followed by a secret-file path within the same
# pipeline segment ([^|&;]* stops at the segment boundary).
input=$(cat)

# Fast path: every deny pattern below requires one of these tokens in the
# command. Skip jq + grep spawns when none of them appears in the input.
case "$input" in
  *".env"*|*".pem"*|*".key"*|*".p12"*|*".pfx"*|*"credentials.json"*|*".ssh/"*|*".mcp.local.json"*) ;;
  *) exit 0 ;;
esac

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# Tools that read file contents to stdout. Excludes grep (matches the literal
# string ".env" in arbitrary text — see test "allows grep for .env string").
read_tool='(cat|less|more|head|tail|awk|sed|xxd|od|strings|nl|tac|dd)'
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

# Inline-eval bypass: `python -c "open('.env').read()"`, ruby/perl/node equivalents.
# Match any of those interpreters with -c/-e where the script body anywhere
# afterwards references a secret-file path. Coarse on purpose — the alternative
# would be quote-aware parsing in regex, which doesn't compose with mixed
# inner/outer quoting like open('.env') inside double quotes.
if echo "$cmd" | grep -qE "(python[3]?|ruby|perl|node)[[:space:]]+(-[ce]|--eval)[[:space:]]+.*(\.env|\.pem|\.key|credentials\.json|\.ssh/)"; then
  jq -cn '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked: inline interpreter reading a secrets file. Handle secrets through the application environment, not an inline -c script."}}'
  exit 0
fi
exit 0
