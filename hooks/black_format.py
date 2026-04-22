# /// script
# requires-python = ">=3.11"
# dependencies = ["black"]
# ///
"""PostToolUse hook: run black on any .py file that was just written or edited.

Claude Code passes a JSON payload on stdin describing the tool call that fired
the hook.  We extract the file path, skip non-Python files silently, and let
black format in-place.
"""

import json
import subprocess
import sys


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return

    # The tool result carries the path under different keys depending on the tool.
    tool_input = payload.get("tool_input", {})
    file_path: str = tool_input.get("file_path") or tool_input.get("path", "")

    if not file_path.endswith(".py"):
        return

    result = subprocess.run(
        ["black", "--quiet", file_path],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(result.returncode)


if __name__ == "__main__":
    main()
