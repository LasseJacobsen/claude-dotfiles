# claude-dotfiles

Reusable Claude Code configuration, hooks, skills, and commands — versioned as a git repo.

## Structure

```
claude-dotfiles/
├── CLAUDE.md                        # Non-obvious overrides (commit rules)
├── settings.json                    # Claude Code settings (MCP servers, hooks)
├── install.sh                       # One-shot setup script
├── hooks/
│   └── black_format.py              # PostToolUse hook: auto-format Python with black
├── skills/
│   └── git-pr-message/
│       └── SKILL.md                 # Skill: generate PR descriptions from git log
├── commands/
│   └── commit.md                    # /user:commit — guided commit helper
└── README.md
```

## Setup (new machine)

```bash
git clone <this-repo> ~/claude-dotfiles
cd ~/claude-dotfiles
bash install.sh
```

`install.sh` does three things:
1. Symlinks (or copies) `settings.json` and `CLAUDE.md` into `~/.claude/`
2. Copies hooks into `~/.claude/hooks/`
3. Warms the Serena uvx cache so the first session starts quickly

Then **start a new Claude Code session** — MCP servers and hooks are loaded at startup.

### Windows notes

- Symlinks for files require [Developer Mode](https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development) or admin. Without it, `install.sh` falls back to copying files — re-run after changes.
- `uv` installs to `~/.local/bin` — make sure it's on your PATH before starting Claude Code.
- Run `install.sh` in Git Bash (not PowerShell/cmd).

### Updating hooks after changes

```bash
bash install.sh   # re-copies hooks to ~/.claude/hooks/
```

If settings.json was symlinked, changes take effect immediately. If it was copied, re-run `install.sh`.

---

## MCP Servers

### Serena

Code intelligence across 40+ languages via LSP. Gives Claude semantic search, go-to-definition, find-references, and symbol navigation inside any project.

**Dependency:** [`uv`](https://github.com/astral-sh/uv)

```powershell
# Windows
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

Serena is configured globally in `settings.json`, so **every project gets it automatically** — no per-project setup needed. The `--project-from-cwd` flag means Serena auto-detects the active project.

#### Verifying Serena is running

In a Claude Code session, run `/mcp` — `serena` should appear with status `connected`. Or ask Claude to use a Serena tool like `search_for_pattern`.

If Serena doesn't appear:
1. Confirm `settings.json` is in `~/.claude/` (run `install.sh` if not)
2. Start a **new** Claude Code session — MCP servers are loaded at startup
3. Check that `uv` is on PATH: `uv --version`

#### Updating Serena

```bash
uv cache clean   # forces a fresh fetch from GitHub on next session start
```

---

## Hooks

### `hooks/black_format.py`

Runs after every `Edit` or `Write` tool call. If the file is a `.py` file, `black` formats it in-place. Requires `uv` on PATH; `black` is fetched automatically via the PEP 723 script header.

The hook runs from `~/.claude/hooks/black_format.py` (placed there by `install.sh`).

```json
"PostToolUse": [{ "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "uv run --script \"$HOME/.claude/hooks/black_format.py\"" }] }]
```

---

## Skills

| Skill | Trigger |
|-------|---------|
| `git-pr-message` | "generate a PR description", "write the PR body" |

## Commands

| Command | Description |
|---------|-------------|
| `/user:commit` | Stage and commit with a well-formed message, no AI footers |
