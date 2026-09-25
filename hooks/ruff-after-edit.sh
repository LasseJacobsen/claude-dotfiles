#!/usr/bin/env bash
set -uo pipefail
# Fix and format an edited .py file, then hand whatever ruff could not fix back
# to Claude as additionalContext. A clean file prints nothing, so this costs no
# context unless there is something to act on. Always exits 0.
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ "$file_path" == *.py && -f "$file_path" ]] || exit 0
uv run ruff check --fix --quiet "$file_path" >/dev/null 2>&1
uv run ruff format --quiet "$file_path" 2>/dev/null
# Check again after formatting so the reported line numbers match the file.
# Capped: a file with hundreds of findings needs a human, not more context.
remaining=$(uv run ruff check --quiet --output-format concise "$file_path" 2>/dev/null | head -n 20)
[[ -n "$remaining" ]] || exit 0
jq -cn --arg findings "$remaining" \
  '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":("ruff found issues it could not fix automatically:\n" + $findings)}}'
exit 0
