#!/usr/bin/env bash
input=$(cat)
[[ "$(echo "$input" | jq -r '.stop_hook_active')" == "true" ]] && exit 0

transcript=$(echo "$input" | jq -r '.transcript_path // empty')
[[ -f "$transcript" ]] || exit 0

last=$(tail -20 "$transcript")
if echo "$last" | grep -qE "I (can't|cannot) access|from memory|probably|I think |if you could (share|provide)"; then
  echo "Response contains uncertain or speculative phrasing. Verify before completing." >&2
  exit 2
fi
exit 0
