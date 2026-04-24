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

# Multi-word phrases: substring match is safe because none appear inside valid uv commands.
phrase_redirects = {
    "pip install": "uv add",
    "pip3 install": "uv add",
    "pip uninstall": "uv remove",
    "pip3 uninstall": "uv remove",
    "poetry add": "uv add",
    "poetry install": "uv sync",
    "conda install": "uv add",
    "python -m pytest": "uv run pytest",
    "python -m ruff": "uv run ruff",
}

for pattern, fix in phrase_redirects.items():
    if pattern in cmd:
        print(f"Blocked: '{pattern}' — use '{fix}' instead.", file=sys.stderr)
        sys.exit(2)

# Single-word commands: require the word to be a standalone command (start of a
# pipeline stage), not an argument to another tool like `uv run pytest`.
bare_redirects = {
    r"(?:^|&&|\|\||;)\s*pytest\b": "uv run pytest",
}

for pattern, fix in bare_redirects.items():
    if re.search(pattern, cmd):
        print(f"Blocked: bare command — use '{fix}' instead.", file=sys.stderr)
        sys.exit(2)
