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
│   ├── block-big-binaries.sh           # PreToolUse: block committing large or binary result files
│   ├── enforce-uv.sh                   # PreToolUse: redirect pip/poetry/conda → uv
│   ├── ruff-after-edit.sh              # PostToolUse: ruff lint+format on every .py edit
│   ├── nbstripout.sh                   # PostToolUse: strip notebook outputs on .ipynb edits
│   ├── check-claims.sh                 # Stop: block uncertain/speculative responses
│   ├── precompact-backup.sh            # PreCompact: back up transcript before context compaction
│   ├── session-start.sh                # SessionStart: inject branch/status/recent commits as context
│   ├── notify.sh                       # Notification: cross-platform desktop notification bridge
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
git clone <this-repo>
cd <repo-dir>
bash install.sh
```

The clone location doesn't matter — `install.sh` resolves paths relative to its own location.

`install.sh` does the following:
1. Auto-installs `jq` if missing (winget / brew / apt / yum)
2. Symlinks (or copies) `settings.json` and `CLAUDE.md` into `~/.claude/`
3. Copies hooks into `~/.claude/hooks/`
4. Copies commands into `~/.claude/commands/`
5. Copies skills into `~/.claude/skills/`
6. Seeds `~/.claude/settings.local.json` from `settings.local.example.json` on first run
7. Reinstalls plugins listed in `plugins-installed.txt`
8. Installs `nbstripout` and registers it as a global git filter (strips notebook outputs on every `git add`, regardless of who staged the file)
9. Warms the Serena uvx cache and installs `pyright[nodejs]` into Serena's env

Then **start a new Claude Code session** — MCP servers and hooks are loaded at startup.

### Windows notes

- Symlinks for files require [Developer Mode](https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development) or admin. Without it, `install.sh` falls back to copying — re-run after changes.
- `uv` installs to `~/.local/bin` — make sure it's on your PATH before starting Claude Code.
- Run `install.sh` in Git Bash (not PowerShell/cmd).
- Several hooks require `jq`. Claude Code ships jq in its bundled environment so hooks always work in sessions. `install.sh` installs jq automatically via `winget`; if that fails, install it manually before running `make test`:
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
| `block-destructive.sh` | Any `Bash` | `rm -rf /`, `rm -rf ~`, `git push --force`, `chmod -R 777`, pipe-to-shell, fork bomb, `DROP TABLE` (best-effort — see below) |
| `block-git-main.sh` | Any `Bash` | `git commit`/`push` while on `main`, `master`, `prod`, or `production` |
| `block-big-binaries.sh` | `git add` / `git commit -a` | Files >50 MB or with binary result extensions (`.h5`, `.vtk`, `.pkl`, `.npz`, etc.) |
| `enforce-uv.sh` | Any `Bash` | Denies `pip install`, `pip uninstall`, `poetry add`, `poetry install`, `conda install`, `python -m pytest`, `python -m ruff`, and bare `pytest`. The deny reason includes the suggested uv replacement (e.g. `uv add`, `uv run pytest`). |
| `protect-secrets.sh` | Any `Bash` | Read-tools (`cat`/`less`/`head`/`tail`/`awk`/`sed`/`xxd`/`od`/`strings`/`nl`/`tac`/`dd`) and inline interpreters (`python -c`, `ruby -e`, etc.) when targeting `.env*`, `*.pem`, `*.key`, `credentials.json`, `.ssh/` paths. Bash bypass of `permissions.deny` (issue #6631). Best-effort tripwire — see posture note below. |

#### Posture, not protection

`block-destructive.sh` and `protect-secrets.sh` are **tripwires against accidental damage and routine disclosure, not security boundaries.** A motivated caller can bypass them with shell tricks the regexes don't model:

- `block-destructive.sh` doesn't catch `rm -rf "$HOME"`, `rm -rf ${HOME}`, `rm -rf /etc`, `dd if=/dev/zero of=/dev/sda`, `mkfs`, `> /dev/sda`, `find / -delete`, `shred`, `wipefs`, separated `-r -f` flags, etc.
- `protect-secrets.sh` doesn't catch process substitution (`<(cat .env)`), here-docs, base64-piped reads, or arbitrary script files that read secrets at runtime.

If you need a real security boundary, run Claude Code in a sandboxed environment (container, VM, or dedicated user) and rely on filesystem permissions instead of regex matching.

### PostToolUse

| Hook | Trigger | What it does |
|------|---------|--------------|
| `ruff-after-edit.sh` | `Write`/`Edit`/`MultiEdit` on `.py` | Runs `ruff check --fix` then `ruff format` in-place; always exits 0 |
| `nbstripout.sh` | `Write`/`NotebookEdit` on `*/notebooks/*.ipynb` | Strips cell outputs via `nbstripout`; always exits 0. Scoped to `notebooks/` so scratch notebooks keep their outputs for iterative work. The matcher excludes `Edit`/`MultiEdit` because those are line-based operations that don't make sense on a JSON notebook. |

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
| `check-claims.sh` | Parses the transcript JSONL to extract the last assistant text block and checks it for uncertain/speculative phrases ("I can't access", "from memory", "if you could share/provide"). Blocks completion if found. Ignores tool results and file payloads that happen to contain those phrases. |

### PreCompact

| Hook | What it does |
|------|--------------|
| `precompact-backup.sh` | Copies the current transcript to `~/.claude/backups/compact-<timestamp>.jsonl` before Claude compacts the context window |

### SessionStart

| Hook | What it does |
|------|--------------|
| `session-start.sh` | On `startup`, `resume`, or `clear`: prints the current branch, working-tree status, and last 5 commits. Stdout from SessionStart hooks is injected into Claude's context, replacing "remember to check git status" prose rules. Exits silently outside a git repo. |

### Notification

| Hook | What it does |
|------|--------------|
| `notify.sh` | Surfaces "Claude needs input" events as a desktop notification: BurntToast on Windows, `osascript` on macOS, `notify-send` on Linux. Always exits 0; missing notifier is silent. |

#### Enabling Windows toast notifications

`notify.sh` uses [BurntToast](https://github.com/Windos/BurntToast) on Windows. Install it once per user:

```powershell
Install-Module -Name BurntToast -Scope CurrentUser
```

If BurntToast is not installed, `notify.sh` silently falls through — no error. macOS and Linux work out of the box (no install).

---

## Project-level settings (`.claude/settings.json`)

The `.claude/settings.json` inside this repo is a *project-level* settings file — it applies when Claude Code is run from inside the dotfiles directory itself. It contains only the Serena MCP entry so that Serena works here too. Hooks, permissions, and env vars live in the root `settings.json` that `install.sh` deploys to `~/.claude/settings.json`; those apply globally to every project.

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
