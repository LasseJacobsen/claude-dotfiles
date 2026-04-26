#!/usr/bin/env bash
# Pick a working python: on Windows, `python3` often resolves to the Microsoft
# Store stub which prints an install prompt instead of running. Probe before use.
if python3 -c '' >/dev/null 2>&1; then PY=python3
elif python -c '' >/dev/null 2>&1; then PY=python
else exit 0  # no python — fail open, never block Claude over a missing interpreter
fi

input=$(cat)

stop_hook_active=$(echo "$input" | "$PY" -c \
  "import json,sys; d=json.load(sys.stdin); print(str(d.get('stop_hook_active',False)).lower())" \
  2>/dev/null || echo "false")
[[ "$stop_hook_active" == "true" ]] && exit 0

transcript=$(echo "$input" | "$PY" -c \
  "import json,sys; d=json.load(sys.stdin); print(d.get('transcript_path',''))" \
  2>/dev/null || echo "")
[[ -f "$transcript" ]] || exit 0

# Extract only the last assistant text response from the JSONL transcript.
# A raw tail -20 also catches file-write payloads and tool results, producing
# false positives when written files happen to contain the flagged phrases.
last=$("$PY" - "$transcript" <<'PYEOF'
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
        # Real transcripts wrap the message: {type: "assistant", message: {role, content}}.
        # Fall back to the flat shape so older transcripts and test fixtures still work.
        is_assistant = obj.get("type") == "assistant" or obj.get("role") == "assistant"
        if not is_assistant:
            continue
        msg = obj.get("message", obj)
        content = msg.get("content", obj.get("content", ""))
        if isinstance(content, str):
            texts.append(content)
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    texts.append(block.get("text", ""))

print(texts[-1] if texts else "")
PYEOF
)

if echo "$last" | grep -iqE "I (can't|cannot) access|from memory|I think |if you could (share|provide)"; then
  echo "Response contains uncertain or speculative phrasing. Verify before completing." >&2
  exit 2
fi
exit 0
