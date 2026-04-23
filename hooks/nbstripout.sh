#!/usr/bin/env bash
input=$(cat)
fp=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ "$fp" == *.ipynb && -f "$fp" ]] || exit 0
uv tool run nbstripout "$fp" 2>/dev/null
exit 0
