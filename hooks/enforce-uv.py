#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import json
import sys

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")

redirects = {
    "pip install": "uv add",
    "pip3 install": "uv add",
    "pip uninstall": "uv remove",
    "poetry add": "uv add",
    "poetry install": "uv sync",
    "conda install": "uv add",
    "python -m pytest": "uv run pytest",
    "python -m ruff": "uv run ruff",
}

for pattern, fix in redirects.items():
    if pattern in cmd:
        print(f"Blocked: '{pattern}' — use '{fix}' instead.", file=sys.stderr)
        sys.exit(2)
