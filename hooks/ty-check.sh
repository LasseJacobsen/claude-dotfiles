#!/usr/bin/env bash
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ "$file_path" == *.py && -f "$file_path" ]] || exit 0
output=$(uvx ty@latest check "$file_path" 2>&1)
if [[ $? -ne 0 ]]; then
  echo "ty type errors in $file_path:" >&2
  echo "$output" >&2
  exit 2
fi
exit 0
