#!/usr/bin/env bash
input=$(cat)

precompact_hook_active=$(echo "$input" | jq -r '.precompact_hook_active // false')
[[ "$precompact_hook_active" == "true" ]] && exit 0

transcript=$(echo "$input" | jq -r '.transcript_path // ""')
[[ -f "$transcript" ]] || exit 0

backup_dir="$HOME/.claude/backups"
mkdir -p "$backup_dir"
cp "$transcript" "$backup_dir/compact-$(date +%s).jsonl"
exit 0
