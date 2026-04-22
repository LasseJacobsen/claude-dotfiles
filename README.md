# claude-dotfiles

Reusable Claude Code configuration, hooks, skills, and commands — versioned as a git repo.

## Structure

```
claude-dotfiles/
├── CLAUDE.md                        # Non-obvious overrides (commit rules)
├── settings.json                    # Claude Code settings (hooks, permissions)
├── hooks/
│   └── black_format.py              # PostToolUse hook: auto-format Python with black
├── skills/
│   └── git-pr-message/
│       └── SKILL.md                 # Skill: generate PR descriptions from git log
├── commands/
│   └── commit.md                    # /user:commit — guided commit helper
└── README.md
```

## Usage

### Symlink into your Claude config directory

```bash
# Back up any existing files first, then symlink:
ln -sf ~/claude-dotfiles/CLAUDE.md ~/.claude/CLAUDE.md
ln -sf ~/claude-dotfiles/settings.json ~/.claude/settings.json
ln -sf ~/claude-dotfiles/hooks ~/.claude/hooks
ln -sf ~/claude-dotfiles/skills ~/.claude/skills
ln -sf ~/claude-dotfiles/commands ~/.claude/commands
```

### Or copy and adapt per-project

Copy individual files into a project's `.claude/` directory and adjust as needed.

## MCP Servers

### Serena

Code intelligence across 40+ languages via LSP. Gives Claude semantic search, go-to-definition, find-references, and symbol navigation inside any project.

**Dependency:** [`uv`](https://github.com/astral-sh/uv) — language servers are fetched automatically by Serena on first use (no separate Node.js or LSP install needed).

The config in `settings.json` uses `--project-from-cwd` so Serena always targets the active project directory, making it safe to symlink globally.

To update Serena to the latest version, clear the `uvx` cache:

```bash
uv cache clean
```

## Hooks

### `hooks/black_format.py`

Runs after every `Edit` or `Write` tool call.  If the file is a `.py` file,
`black` formats it in-place.  Requires [uv](https://github.com/astral-sh/uv) on
`PATH`; dependencies (`black`) are fetched automatically via the PEP 723 script
header.

```json
"PostToolUse": [{ "matcher": "Edit|Write", "hooks": [{ "type": "command", "command": "uv run --script hooks/black_format.py" }] }]
```

## Skills

| Skill | Trigger |
|-------|---------|
| `git-pr-message` | "generate a PR description", "write the PR body" |

## Commands

| Command | Description |
|---------|-------------|
| `/user:commit` | Stage and commit with a well-formed message, no AI footers |

