#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import json
import re
import sys

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")

# Only block when the pattern is a standalone command invocation — i.e. at the
# start of a pipeline stage.  Substring matching fires on phrases that appear
# as text inside arguments to other tools (e.g. `gh pr create --body "pip install"`).
STAGE = r"(?:^|&&|\|\||;)\s*"

redirects = [
    (r"pip3?\s+install\b",      "uv add"),
    (r"pip3?\s+uninstall\b",    "uv remove"),
    (r"poetry\s+add\b",         "uv add"),
    (r"poetry\s+install\b",     "uv sync"),
    (r"conda\s+install\b",      "uv add"),
    (r"python\s+-m\s+pytest\b", "uv run pytest"),
    (r"python\s+-m\s+ruff\b",   "uv run ruff"),
    (r"pytest\b",               "uv run pytest"),
]

for pattern, fix in redirects:
    m = re.search(STAGE + r"(" + pattern + r")", cmd)
    if m:
        print(f"Blocked: '{m.group(1)}' — use '{fix}' instead.", file=sys.stderr)
        sys.exit(2)
