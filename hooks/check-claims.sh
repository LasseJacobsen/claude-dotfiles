#!/usr/bin/env bash
input=$(cat)

# Guard: prevent infinite loop if Stop hook fires while hook is already active.
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false')
[[ "$stop_hook_active" == "true" ]] && exit 0

transcript=$(echo "$input" | jq -r '.transcript_path // empty')
[[ -f "$transcript" ]] || exit 0

# Extract only the last assistant text block to avoid false positives from
# file-write payloads and tool results containing the flagged phrases.
last=$(python3 - "$transcript" <<'PYEOF'
import json, sys

path = sys.argv[1]
texts = []
with open(path, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("role") != "assistant":
            continue
        content = obj.get("content", "")
        if isinstance(content, str):
            texts.append(content)
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    texts.append(block.get("text", ""))

print(texts[-1] if texts else "")
PYEOF
)

if echo "$last" | grep -iqE "I (can't|cannot) access|from memory|probably|I think |if you could (share|provide)"; then
  echo "Response contains uncertain or speculative phrasing. Verify before completing." >&2
  exit 2
fi
exit 0
