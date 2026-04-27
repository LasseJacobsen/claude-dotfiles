#!/usr/bin/env bash
set -uo pipefail
# ty version is pinned so the hook doesn't pay a cache-revalidation network
# round-trip on every Python edit. Bump deliberately when ty improves.
TY_VERSION="0.0.32"
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ "$file_path" == *.py && -f "$file_path" ]] || exit 0
output=$(uvx "ty@${TY_VERSION}" check "$file_path" 2>&1)
if [[ $? -ne 0 ]]; then
  echo "ty type errors in $file_path:" >&2
  echo "$output" >&2
  exit 2
fi
exit 0
