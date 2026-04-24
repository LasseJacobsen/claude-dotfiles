#!/usr/bin/env bash
input=$(cat)
fp=$(echo "$input" | jq -r '.tool_input.file_path // empty')
# Scope to files inside a notebooks/ directory — leave scratch notebooks untouched
# so Claude can see outputs from iterative runs.
[[ "$fp" == */notebooks/*.ipynb && -f "$fp" ]] || exit 0
uv tool run nbstripout "$fp" 2>/dev/null
exit 0
