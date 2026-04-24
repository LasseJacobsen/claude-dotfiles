#!/usr/bin/env bash
# One-shot setup: links or copies this dotfiles repo into ~/.claude.
# Re-run to update hooks after changes. Safe to run multiple times.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.claude"

log() { printf '[claude-dotfiles] %s\n' "$*"; }

command -v uv >/dev/null || { echo "uv is required: https://github.com/astral-sh/uv"; exit 1; }

# jq is required by several hooks for JSON parsing.
# Claude Code bundles jq so hooks work in sessions; install here for 'make test' in the shell.
if ! command -v jq >/dev/null 2>&1; then
  log "jq not found — attempting to install..."
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      if command -v winget >/dev/null 2>&1; then
        winget install --id jqlang.jq -e \
          --accept-source-agreements --accept-package-agreements --silent 2>/dev/null \
          && log "jq installed via winget" \
          || log "Warning: winget install failed — run manually: winget install jqlang.jq"
      else
        log "Warning: winget not found. Install jq: choco install jq  |  scoop install jq"
      fi
      ;;
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew install jq 2>/dev/null && log "jq installed via brew" \
          || log "Warning: brew install jq failed — run manually: brew install jq"
      else
        log "Warning: Homebrew not found. Install jq: https://jqlang.github.io/jq/download/"
      fi
      ;;
    *)
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y jq 2>/dev/null && log "jq installed via apt-get" \
          || log "Warning: apt-get install jq failed"
      elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y jq 2>/dev/null && log "jq installed via yum" \
          || log "Warning: yum install jq failed"
      else
        log "Warning: could not detect package manager. Install jq manually."
      fi
      ;;
  esac
  command -v jq >/dev/null 2>&1 \
    || log "Note: jq unavailable in this shell — hooks work in Claude Code (jq is bundled); 'make test' will skip jq-dependent tests."
fi

# Back up any pre-existing ~/.claude that wasn't created by this script
if [[ -e "$TARGET" && ! -L "$TARGET" && ! -f "$TARGET/.managed-by-dotfiles" ]]; then
  backup="$TARGET.backup.$(date +%Y%m%d-%H%M%S)"
  log "Backing up existing $TARGET → $backup"
  mv "$TARGET" "$backup"
fi

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

# Reinstall plugins declared in plugins-installed.txt
if [[ -f "$REPO/plugins-installed.txt" ]] && command -v claude >/dev/null 2>&1; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    log "Installing plugin: $line"
    claude plugin install "$line" --scope user 2>/dev/null || \
      log "Warning: could not install plugin $line — install manually with: claude plugin install $line"
  done < "$REPO/plugins-installed.txt"
fi

# Seed settings.local.json from example on first run
if [[ ! -f "$TARGET/settings.local.json" && -f "$REPO/settings.local.example.json" ]]; then
  cp "$REPO/settings.local.example.json" "$TARGET/settings.local.json"
  log "Created settings.local.json from example template"
fi

# Warm the uvx cache for Serena so the first MCP startup is fast
log "Warming Serena uvx cache..."
if uvx --from git+https://github.com/oraios/serena serena --version 2>/dev/null; then
  log "Serena cache warmed"
else
  log "Warning: Serena cache warming failed — first session start will be slow (~30s)"
  log "  If Serena never connects, run: uv cache clean && bash install.sh"
fi

# pyright (Serena's Python language server) needs Node.js to run.
# Its default nodeenv fallback fails on some systems (notably Windows).
# Installing the nodejs-wheel-binaries extra directly into Serena's env fixes this.
# Note: --with pyright[nodejs] in uvx args does not work here because pyright is
# launched as a subprocess by serena and does not inherit the uvx overlay's packages.
log "Installing pyright[nodejs] into Serena's env..."
SERENA_PYTHON=$(uvx --from git+https://github.com/oraios/serena python \
  -c "import sys; print(sys.executable)" 2>/dev/null || true)
if [[ -n "$SERENA_PYTHON" ]]; then
  if uv pip install --python "$SERENA_PYTHON" "pyright[nodejs]" --quiet 2>/dev/null; then
    log "pyright[nodejs] installed"
  else
    log "Warning: pyright[nodejs] install failed — go-to-definition may not work"
  fi
else
  log "Warning: could not locate Serena Python env — run 'uv cache clean' then re-run install.sh"
fi

# Prevent settings.local.json from showing up as an untracked file in project repos
mkdir -p "$HOME/.config/git"
if ! grep -qxF '**/.claude/settings.local.json' "$HOME/.config/git/ignore" 2>/dev/null; then
  echo '**/.claude/settings.local.json' >> "$HOME/.config/git/ignore"
  log "Added settings.local.json to global git ignore ($HOME/.config/git/ignore)"
fi

log ""
log "Done. Start a new Claude Code session to activate Serena and hooks."
log ""
log "Verify setup:"
log "  Hooks:  run 'bash tests/test_hooks.sh' from the dotfiles root"
log "  Serena: open a Claude Code session and run /mcp — 'serena' should appear as connected"
