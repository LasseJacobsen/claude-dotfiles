#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import json
import pathlib
import subprocess
import sys

BIG_EXT = {
    ".rst", ".db", ".cdb", ".odb", ".rth", ".rmg",
    ".msh", ".vtu", ".vtk", ".h5", ".hdf5", ".npz", ".pkl",
}
MAX_BYTES = 50 * 1024 * 1024

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")

if not cmd.startswith(("git add", "git commit -a")):
    sys.exit(0)

result = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True)
offenders = []
for line in result.stdout.splitlines():
    if not line.strip():
        continue
    path = pathlib.Path(line[3:].strip().strip('"'))
    if not path.exists():
        continue
    size = path.stat().st_size
    if path.suffix.lower() in BIG_EXT or size > MAX_BYTES:
        offenders.append((path, size))

if offenders:
    print("Large or binary result files must not be committed directly:", file=sys.stderr)
    for p, s in offenders:
        print(f"  {p} ({s / 1024 / 1024:.1f} MB)", file=sys.stderr)
    print("\nUse Git LFS or DVC; or commit a manifest/hash instead.", file=sys.stderr)
    sys.exit(2)
