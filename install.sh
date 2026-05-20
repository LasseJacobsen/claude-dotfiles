#!/usr/bin/env bash
# One-shot setup: links or copies this dotfiles repo into ~/.claude.
# Re-run to update hooks after changes. Safe to run multiple times.
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.claude"

log() { printf '[claude-dotfiles] %s\n' "$*"; }

# jq is required by several hooks for JSON parsing. Install jq first so a
# user missing both jq and uv gets jq automatically before we abort on uv.
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

# uv powers Serena (MCP), the nbstripout git filter, and pyright bootstrapping.
# Probe whether uv can actually RUN — not just whether it's on PATH. On
# locked-down corporate machines, application-control/EDR can block uv.exe from
# executing (the same class of block that hits find.exe and whoami.exe) even
# though uv is installed and owned by the user. When that happens we degrade:
# install the uv-independent core and skip the uv-dependent extras with one
# clear message instead of three confusing failures.
UV_OK=false
if command -v uv >/dev/null 2>&1; then
  if uv --version >/dev/null 2>&1; then
    UV_OK=true
  else
    log "Warning: uv is installed ($(command -v uv)) but cannot be executed —"
    log "  your machine's application-control/EDR policy is blocking it. Serena,"
    log "  the nbstripout git filter, and pyright will be SKIPPED; everything"
    log "  else installs normally and works without uv. To enable them, ask IT"
    log "  to allowlist uv.exe and uvx.exe. See README → 'When uv is blocked'."
  fi
else
  log "Warning: uv not found — Serena, nbstripout, and pyright will be skipped."
  log "  Install uv (https://github.com/astral-sh/uv) and re-run install.sh."
fi

# Back up any pre-existing ~/.claude that wasn't created by this script.
# Abort on backup failure rather than clobber the user's settings: the
# install steps below overwrite ~/.claude in place, so a missing backup
# means lost work. cp -r (not mv) tolerates open file handles from a
# running Claude Code session; if even that fails, ask the user to retry
# from outside Claude Code.
if [[ -e "$TARGET" && ! -L "$TARGET" && ! -f "$TARGET/.managed-by-dotfiles" ]]; then
  backup="$TARGET.backup.$(date +%Y%m%d-%H%M%S)"
  log "Backing up existing $TARGET → $backup"
  if ! cp -r "$TARGET" "$backup"; then
    log "Error: backup failed. Refusing to overwrite $TARGET without one."
    log "If Claude Code is running, exit it and re-run install.sh."
    exit 1
  fi
fi

mkdir -p "$TARGET/hooks"

# Prefer a symlink (so edits in the repo show up live in ~/.claude/) and fall
# back to a copy when symlinks aren't available — Windows without Developer Mode.
link_or_copy() {
  local src="$1" dst="$2" name="$3"
  if ln -snf "$src" "$dst" 2>/dev/null; then
    log "Symlinked $name"
  else
    cp "$src" "$dst"
    log "Copied $name (symlink unavailable — re-run install.sh after changes)"
  fi
}

link_or_copy "$REPO/settings.json" "$TARGET/settings.json" "settings.json"
link_or_copy "$REPO/CLAUDE.md"     "$TARGET/CLAUDE.md"     "CLAUDE.md"

# Hooks — symlink-or-copy each, so editing the repo updates ~/.claude live
# wherever symlinks are available.
for hook in "$REPO/hooks/"*; do
  [[ -f "$hook" ]] || continue
  link_or_copy "$hook" "$TARGET/hooks/$(basename "$hook")" "hook: $(basename "$hook")"
done

# Ensure copied hooks are executable. Use a glob loop, not `find -exec`: some
# locked-down corporate machines block execution of /usr/bin/find (EDR/AppLocker
# flags `find -exec` as a risky binary). chmod is best-effort because it can be
# blocked too — and the bit is not required: Claude Code runs hooks via
# `bash <hook>.sh` (settings.json), and symlinks already inherit the repo's mode.
for hook in "$TARGET/hooks/"*.sh "$TARGET/hooks/"*.py; do
  [[ -e "$hook" ]] || continue          # unmatched glob stays literal; skip it
  chmod +x "$hook" 2>/dev/null || true  # don't abort under set -e if chmod fails/blocked
done

# Commands — symlink-or-copy
mkdir -p "$TARGET/commands"
for cmd_file in "$REPO/commands/"*; do
  [[ -f "$cmd_file" ]] || continue
  link_or_copy "$cmd_file" "$TARGET/commands/$(basename "$cmd_file")" "command: $(basename "$cmd_file")"
done

# Skills — replace any existing target before copying so re-runs don't nest
# (cp -r src dst/ when dst/src already exists copies into dst/src/src).
mkdir -p "$TARGET/skills"
for skill_dir in "$REPO/skills/"*/; do
  [[ -d "$skill_dir" ]] || continue
  skill_name=$(basename "${skill_dir%/}")
  rm -rf "$TARGET/skills/$skill_name"
  if ln -snf "${skill_dir%/}" "$TARGET/skills/$skill_name" 2>/dev/null; then
    log "Symlinked skill: $skill_name"
  else
    cp -r "${skill_dir%/}" "$TARGET/skills/$skill_name"
    log "Copied skill: $skill_name"
  fi
done

# Seed settings.local.json from example on first run
if [[ ! -f "$TARGET/settings.local.json" && -f "$REPO/settings.local.example.json" ]]; then
  cp "$REPO/settings.local.example.json" "$TARGET/settings.local.json"
  log "Created settings.local.json from example template"
fi

if $UV_OK; then
  # nbstripout global git filter — covers humans staging notebooks too, not just Claude.
  # nbstripout --install writes a `clean = nbstripout` filter that relies on the
  # bare command being on PATH. Non-login shells (e.g. GUI git clients, some CI
  # runners) often skip ~/.local/bin, turning every `git add` of a notebook into
  # a fatal error. Resolve to the absolute path so the filter works regardless.
  log "Registering nbstripout as a global git filter..."
  if uv tool install --quiet nbstripout 2>/dev/null && command -v nbstripout >/dev/null 2>&1; then
    if nbstripout --install --global 2>/dev/null; then
      NBS_ABS="$(command -v nbstripout)"
      git config --global filter.nbstripout.clean "$NBS_ABS"
      log "nbstripout registered globally ($NBS_ABS)"
    else
      log "Warning: nbstripout install succeeded but --install --global failed (run it manually)"
    fi
  else
    log "Warning: could not install nbstripout via uv — notebook output stripping limited to the Claude hook"
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
  # Under Git Bash, sys.executable returns a Windows path (C:\...\python.exe).
  # uv pip --python wants a POSIX-style path; cygpath translates it.
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      if [[ -n "$SERENA_PYTHON" ]] && command -v cygpath >/dev/null 2>&1; then
        SERENA_PYTHON=$(cygpath -u "$SERENA_PYTHON" 2>/dev/null || echo "$SERENA_PYTHON")
      fi
      ;;
  esac
  if [[ -n "$SERENA_PYTHON" ]]; then
    if uv pip install --python "$SERENA_PYTHON" "pyright[nodejs]" --quiet 2>/dev/null; then
      log "pyright[nodejs] installed"
    else
      log "Warning: pyright[nodejs] install failed — go-to-definition may not work"
    fi
  else
    log "Warning: could not locate Serena Python env — run 'uv cache clean' then re-run install.sh"
  fi
else
  log "Skipping Serena, nbstripout filter, and pyright (uv unavailable — see note above)."
fi

# Prevent settings.local.json from showing up as an untracked file in project repos
mkdir -p "$HOME/.config/git"
if ! grep -qxF '**/.claude/settings.local.json' "$HOME/.config/git/ignore" 2>/dev/null; then
  echo '**/.claude/settings.local.json' >> "$HOME/.config/git/ignore"
  log "Added settings.local.json to global git ignore ($HOME/.config/git/ignore)"
fi

touch "$TARGET/.managed-by-dotfiles"

log ""
if $UV_OK; then
  log "Done. Start a new Claude Code session to activate Serena and hooks."
else
  log "Done. Start a new Claude Code session to activate hooks (Serena unavailable — uv is blocked)."
fi
log ""
log "Verify setup:"
log "  Hooks:  run 'bash tests/test_hooks.sh' from the dotfiles root"
if $UV_OK; then
  log "  Serena: open a Claude Code session and run /mcp — 'serena' should appear as connected"
else
  log "  Serena: unavailable until uv can run (ask IT to allowlist uv.exe — see README)"
fi
