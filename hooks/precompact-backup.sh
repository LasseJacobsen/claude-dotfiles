#!/usr/bin/env bash
input=$(cat)

precompact_hook_active=$(echo "$input" | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print(str(d.get('precompact_hook_active',False)).lower())" \
  2>/dev/null || echo "false")
[[ "$precompact_hook_active" == "true" ]] && exit 0

transcript=$(echo "$input" | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print(d.get('transcript_path',''))" \
  2>/dev/null || echo "")
[[ -f "$transcript" ]] || exit 0

backup_dir="$HOME/.claude/backups"
mkdir -p "$backup_dir"
cp "$transcript" "$backup_dir/compact-$(date +%s).jsonl"
exit 0
