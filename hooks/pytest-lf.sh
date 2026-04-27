#!/usr/bin/env bash
set -uo pipefail
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ "$file_path" == *.py ]] || exit 0
[[ -d tests ]] || exit 0
uv run python -c "import pytest" 2>/dev/null || exit 0
output=$(uv run pytest --lf -x --tb=short -q 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Tests failed after edit to $(basename "$file_path"):" >&2
  echo "$output" >&2
  exit 2
fi
exit 0
