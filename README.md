# claude-dotfiles

Reusable Claude Code configuration, hooks, skills, and commands — versioned as a git repo.

## Structure

```
claude-dotfiles/
├── CLAUDE.md                           # Non-obvious overrides (commit rules, naming)
├── settings.json                       # Claude Code settings (MCP servers, hooks, permissions)
├── settings.local.example.json         # Template for machine-specific overrides
├── plugins-installed.txt               # Plugins reinstalled by install.sh on new machines
├── install.sh                          # One-shot setup script
├── Makefile                            # make install / make test
├── hooks/
│   ├── block-destructive.sh            # PreToolUse: block rm -rf /, force-push, fork bombs, etc.
│   ├── block-git-main.sh               # PreToolUse: block direct commits/pushes to main/master/prod
│   ├── block-big-binaries.py           # PreToolUse: block committing large or binary result files
│   ├── enforce-uv.py                   # PreToolUse: redirect pip/poetry/conda → uv
│   ├── ruff-after-edit.sh              # PostToolUse: ruff lint+format on every .py edit
│   ├── ty-check.sh                     # PostToolUse: ty type-check on every .py edit
│   ├── nbstripout.sh                   # PostToolUse: strip notebook outputs on .ipynb edits
│   ├── check-claims.sh                 # Stop: block uncertain/speculative responses
│   ├── precompact-backup.sh            # PreCompact: back up transcript before context compaction
│   └── pytest-lf.sh                    # PostToolUse (opt-in): run failing tests after .py edits
├── skills/
│   └── git-pr-message/
│       └── SKILL.md                    # Skill: generate PR descriptions from git log
├── commands/
│   ├── commit.md                       # /user:commit — guided commit helper
│   └── pr.md                           # /user:pr — generate and open a pull request
└── tests/
    └── test_hooks.sh                   # Unit tests for all hooks
```

## Setup (new machine)

```bash
git clone <this-repo> ~/claude-dotfiles
cd ~/claude-dotfiles
bash install.sh
```

`install.sh` does the following:
1. Symlinks (or copies) `settings.json` and `CLAUDE.md` into `~/.claude/`
2. Copies hooks into `~/.claude/hooks/`
3. Copies commands into `~/.claude/commands/`
4. Copies skills into `~/.claude/skills/`
5. Seeds `~/.claude/settings.local.json` from `settings.local.example.json` on first run
6. Reinstalls plugins listed in `plugins-installed.txt`
7. Warms the Serena uvx cache

Then **start a new Claude Code session** — MCP servers and hooks are loaded at startup.

### Windows notes

- Symlinks for files require [Developer Mode](https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development) or admin. Without it, `install.sh` falls back to copying — re-run after changes.
- `uv` installs to `~/.local/bin` — make sure it's on your PATH before starting Claude Code.
- Run `install.sh` in Git Bash (not PowerShell/cmd).
- Several hooks (`block-destructive.sh`, `block-git-main.sh`, `ruff-after-edit.sh`, `ty-check.sh`, `nbstripout.sh`) require `jq`. Claude Code ships jq in its bundled environment; if you also want to run `make test` from Git Bash, install jq separately:
  ```
  winget install jqlang.jq
  ```

### Updating after changes

```bash
bash install.sh   # or: make install
```

If settings.json was symlinked, changes take effect immediately. If it was copied, re-run.

### Machine-specific overrides

Copy the example template after install and fill in machine-specific values:

```bash
cp settings.local.example.json ~/.claude/settings.local.json
# Edit ~/.claude/settings.local.json — add additionalDirectories, per-machine allow rules, etc.
```

`settings.local.json` is gitignored in all projects; it never gets committed.

---

## Testing hooks

Run the test suite from the dotfiles root:

```bash
bash tests/test_hooks.sh   # or: make test
```

Tests pipe crafted JSON payloads into each hook and assert exit codes and JSON output. Hooks that rely on `jq` internally are skipped if jq isn't in PATH (all tests still pass — they're reported as SKIP). Install jq to unlock full coverage.

---

## MCP Servers

### Serena

Code intelligence across 40+ languages via LSP. Gives Claude semantic search, go-to-definition, find-references, and symbol navigation inside any project.

**Dependency:** [`uv`](https://github.com/astral-sh/uv)

```powershell
# Windows
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

Serena is configured globally in `settings.json`, so **every project gets it automatically** — no per-project setup needed. The `--project-from-cwd` flag means Serena auto-detects the active project directory when a Claude Code session starts.

#### First-time startup

The first time Serena runs in a project it downloads dependencies via uvx (~30 seconds) and indexes the project (~5–60 seconds depending on size). Subsequent starts are fast. `install.sh` pre-warms the uvx download so only the indexing happens on first use.

#### Verifying Serena is running

In a Claude Code session, run `/mcp` — `serena` should appear with status `connected`. Or ask Claude to call a Serena tool directly: *"use serena to search for function X"*.

#### Troubleshooting

**Serena doesn't appear in `/mcp`:**

1. Confirm `~/.claude/settings.json` has the `serena` MCP entry — re-run `install.sh` if missing.
2. Start a **new** Claude Code session — MCP servers load at startup, not mid-session.
3. Check that `uv` is on PATH: `uv --version`. If missing, re-install uv and re-run `install.sh`.

**Serena appears but shows as disconnected / errors on tool calls:**

1. Clear the uvx cache and reinstall: `uv cache clean && bash install.sh`
2. On Windows, verify pyright's Node.js dependency was installed. `install.sh` does this automatically, but if it failed silently check the install output for warnings. Re-run `install.sh` to retry.
3. Check for a `.serena/` directory in your project root — Serena creates it on first index. If it's absent, Serena may not have finished starting. Wait ~60s after opening the session.

**Serena is slow / hangs on large repos:**

Serena indexes all files on startup. For repos > 50k files, add a `.serena/config.yaml` to limit scope:

```yaml
project_root: .
exclude_dirs:
  - .git
  - node_modules
  - __pycache__
  - .venv
  - dist
  - build
```

#### Updating Serena

```bash
uv cache clean   # forces a fresh fetch from GitHub on next session start
```

---

## Hooks

Hooks live in `~/.claude/hooks/` and run deterministically on every matching tool call — no Claude judgement involved. PreToolUse hooks output a structured JSON deny decision and exit 0; blocking PostToolUse/Stop hooks exit 2 to feed errors back to Claude.

### PreToolUse

| Hook | Trigger | What it blocks |
|------|---------|----------------|
| `block-destructive.sh` | Any `Bash` | `rm -rf /`, `rm -rf ~`, `git push --force`, `chmod -R 777`, pipe-to-shell, fork bomb, `DROP TABLE` |
| `block-git-main.sh` | Any `Bash` | `git commit`/`push` while on `main`, `master`, `prod`, or `production` |
| `block-big-binaries.py` | `git add` / `git commit -a` | Files >50 MB or with binary result extensions (`.h5`, `.vtk`, `.pkl`, `.npz`, etc.) |
| `enforce-uv.py` | Any `Bash` | `pip install` → `uv add`, `python -m pytest` → `uv run pytest`, `poetry add` → `uv add`, etc. |

### PostToolUse

| Hook | Trigger | What it does |
|------|---------|--------------|
| `ruff-after-edit.sh` | `Write`/`Edit`/`MultiEdit` on `.py` | Runs `ruff check --fix` then `ruff format` in-place; always exits 0 |
| `ty-check.sh` | `Write`/`Edit`/`MultiEdit` on `.py` | Runs `ty check`; exits 2 if type errors found so Claude retries |
| `nbstripout.sh` | `Write`/`Edit`/`MultiEdit`/`NotebookEdit` on `.ipynb` | Strips cell outputs via `nbstripout`; always exits 0 |

#### Opt-in: pytest on save (`pytest-lf.sh`)

`pytest-lf.sh` is available but **not enabled by default** (can be slow for large suites). To enable, add it to `settings.json` under `PostToolUse`:

```json
{
  "matcher": "Write|Edit|MultiEdit",
  "hooks": [{ "type": "command", "command": "bash \"$HOME/.claude/hooks/pytest-lf.sh\"", "timeout": 60 }]
}
```

The hook skips automatically when there's no `tests/` directory or pytest isn't installed in the project venv.

### Stop

| Hook | What it does |
|------|--------------|
| `check-claims.sh` | Scans the last 20 lines of the transcript for uncertain phrases ("I can't access", "probably", "from memory", "I think", "if you could share/provide") and blocks completion if found |

### PreCompact

| Hook | What it does |
|------|--------------|
| `precompact-backup.sh` | Copies the current transcript to `~/.claude/backups/compact-<timestamp>.jsonl` before Claude compacts the context window |

---

## Skills

| Skill | Trigger |
|-------|---------|
| `git-pr-message` | "generate a PR description", "write the PR body" |

## Commands

| Command | Description |
|---------|-------------|
| `/user:commit` | Stage and commit with a well-formed message, no AI footers |
| `/user:pr` | Generate a PR title/body from git log and open the PR with `gh` |
