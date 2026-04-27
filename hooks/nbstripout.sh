#!/usr/bin/env bash
set -uo pipefail
input=$(cat)
fp=$(echo "$input" | jq -r '.tool_input.file_path // empty')
# Scope to notebooks/ — scratch notebooks keep outputs so Claude can see plots
# from iterative runs. Adjust the glob if you nest deeper than one level.
[[ "$fp" == */notebooks/*.ipynb && -f "$fp" ]] || exit 0
uv tool run nbstripout "$fp" 2>/dev/null
exit 0
