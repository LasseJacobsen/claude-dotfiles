#!/usr/bin/env bash
# PreCompact hooks have no recursion risk (Claude doesn't fire them in a loop),
# so no stop_hook_active-style guard is needed here.
input=$(cat)
transcript=$(echo "$input" | jq -r '.transcript_path // ""')
[[ -f "$transcript" ]] || exit 0

backup_dir="$HOME/.claude/backups"
mkdir -p "$backup_dir"
cp "$transcript" "$backup_dir/compact-$(date +%s).jsonl"
exit 0
