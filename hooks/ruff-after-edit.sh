#!/usr/bin/env bash
set -uo pipefail
# Fix and format an edited .py file, then hand whatever ruff did not fix back
# to Claude as additionalContext. A clean file prints nothing, so this costs no
# context unless there is something to act on. Always exits 0.
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ "$file_path" == *.py && -f "$file_path" ]] || exit 0
# F401 stays report-only: an import added one edit before its first use must
# survive. In a repo that ignores F821, a lost import fails only at runtime.
uv run ruff check --fix --unfixable F401 --quiet "$file_path" >/dev/null 2>&1
# Format with black where the file's repo pins black, since ruff format would
# use ruff's line-length (e.g. 120 where black uses 88); ruff format elsewhere.
repo_root=$(git -C "$(dirname "$file_path")" rev-parse --show-toplevel 2>/dev/null)
if [[ -n "$repo_root" ]] && grep -qsE '"black(\[[^]]*\])?[=<>~!]' "$repo_root/pyproject.toml"; then
  # python -m black, not black.exe: uv writes a new launcher into each venv, and
  # application control can deny running a new one (seen in a fresh worktree).
  uv run python -m black --quiet "$file_path" 2>/dev/null
else
  uv run ruff format --quiet "$file_path" 2>/dev/null
fi
# Check again after formatting so the reported line numbers match the file.
# Capped: a file with hundreds of findings needs a human, not more context.
remaining=$(uv run ruff check --quiet --output-format concise "$file_path" 2>/dev/null | head -n 20)
[[ -n "$remaining" ]] || exit 0
jq -cn --arg findings "$remaining" \
  '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":("ruff found issues it did not fix automatically:\n" + $findings)}}'
exit 0
