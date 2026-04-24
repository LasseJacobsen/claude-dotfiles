#!/usr/bin/env bash
input=$(cat)

stop_hook_active=$(echo "$input" | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print(str(d.get('stop_hook_active',False)).lower())" \
  2>/dev/null || echo "false")
[[ "$stop_hook_active" == "true" ]] && exit 0

transcript=$(echo "$input" | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print(d.get('transcript_path',''))" \
  2>/dev/null || echo "")
[[ -f "$transcript" ]] || exit 0

last=$(tail -20 "$transcript")
if echo "$last" | grep -iqE "I (can't|cannot) access|from memory|probably|I think |if you could (share|provide)"; then
  echo "Response contains uncertain or speculative phrasing. Verify before completing." >&2
  exit 2
fi
exit 0
