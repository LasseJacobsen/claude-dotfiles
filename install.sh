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

# Warm the uvx cache for Serena so the first MCP startup is fast
log "Warming Serena uvx cache..."
uvx --from git+https://github.com/oraios/serena serena --version || true

log ""
log "Done. Start a new Claude Code session to activate Serena and hooks."
