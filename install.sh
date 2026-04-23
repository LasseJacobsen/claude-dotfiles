#!/usr/bin/env bash
# One-shot setup: links or copies this dotfiles repo into ~/.claude.
# Re-run to update hooks after changes. Safe to run multiple times.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.claude"

log() { printf '[claude-dotfiles] %s\n' "$*"; }

command -v uv >/dev/null || { echo "uv is required: https://github.com/astral-sh/uv"; exit 1; }

mkdir -p "$TARGET/hooks"

# settings.json — try symlink, fall back to copy (Windows without Developer Mode)
if ln -snf "$REPO/settings.json" "$TARGET/settings.json" 2>/dev/null; then
  log "Symlinked settings.json"
else
  cp "$REPO/settings.json" "$TARGET/settings.json"
  log "Copied settings.json (symlink unavailable — re-run install.sh after changes)"
fi

# CLAUDE.md — same approach
if ln -snf "$REPO/CLAUDE.md" "$TARGET/CLAUDE.md" 2>/dev/null; then
  log "Symlinked CLAUDE.md"
else
  cp "$REPO/CLAUDE.md" "$TARGET/CLAUDE.md"
  log "Copied CLAUDE.md"
fi

# Hooks — copy individually so they stay in sync on re-runs
for hook in "$REPO/hooks/"*; do
  [[ -f "$hook" ]] || continue
  cp "$hook" "$TARGET/hooks/$(basename "$hook")"
  log "Copied hook: $(basename "$hook")"
done

# Ensure all hook scripts are executable (git drops +x across some transfers)
find "$TARGET/hooks" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +

# Commands — copy individually so /user:* commands work from any project
mkdir -p "$TARGET/commands"
for cmd_file in "$REPO/commands/"*; do
  [[ -f "$cmd_file" ]] || continue
  cp "$cmd_file" "$TARGET/commands/$(basename "$cmd_file")"
  log "Copied command: $(basename "$cmd_file")"
done

# Skills — copy directory structure so skills are available globally
mkdir -p "$TARGET/skills"
for skill_dir in "$REPO/skills/"*/; do
  [[ -d "$skill_dir" ]] || continue
  skill_name=$(basename "${skill_dir%/}")
  cp -r "${skill_dir%/}" "$TARGET/skills/"
  log "Copied skill: $skill_name"
done

# Warm the uvx cache for Serena so the first MCP startup is fast
log "Warming Serena uvx cache..."
uvx --from git+https://github.com/oraios/serena serena --version || true

# pyright (Serena's Python language server) needs Node.js to run.
# Its default nodeenv fallback fails on some systems (notably Windows).
# Installing the nodejs-wheel-binaries extra directly into Serena's env fixes this.
# Note: --with pyright[nodejs] in uvx args does not work here because pyright is
# launched as a subprocess by serena and does not inherit the uvx overlay's packages.
log "Installing pyright[nodejs] into Serena's env..."
SERENA_PYTHON=$(uvx --from git+https://github.com/oraios/serena python \
  -c "import sys; print(sys.executable)" 2>/dev/null || true)
if [[ -n "$SERENA_PYTHON" ]]; then
  uv pip install --python "$SERENA_PYTHON" "pyright[nodejs]" --quiet
  log "pyright[nodejs] installed"
else
  log "Warning: could not locate Serena Python — pyright language server may not start"
fi

log ""
log "Done. Start a new Claude Code session to activate Serena and hooks."
