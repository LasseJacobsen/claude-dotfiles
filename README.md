# claude-dotfiles

Reusable Claude Code configuration, hooks, skills, and commands — versioned as a git repo.

## Structure

```
claude-dotfiles/
├── CLAUDE.md                           # Non-obvious overrides (commit rules, naming)
├── settings.json                       # Claude Code settings (hooks, permissions, env)
├── settings.local.example.json         # Template for machine-specific overrides
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
│   └── notify.sh                       # Notification: cross-platform desktop notification bridge
├── skills/
│   ├── bro/
│   │   └── SKILL.md                    # Skill: restate last message in plain human language
│   ├── bruh/
│   │   └── SKILL.md                    # Skill: restate last message bluntly, no jargon or hedging
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
7. Installs `nbstripout` and registers it as a global git filter (strips notebook outputs on every `git add`, regardless of who staged the file)

Then **start a new Claude Code session** — hooks are loaded at startup.

### Windows notes

- Symlinks for files require [Developer Mode](https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development) or admin. Without it, `install.sh` falls back to copying — re-run after changes.
- `uv` installs to `~/.local/bin` — make sure it's on your PATH before starting Claude Code.
- Run `install.sh` in Git Bash (not PowerShell/cmd).
- Corporate security tools (EDR/AppLocker) sometimes block execution of `find` on locked-down machines (`/usr/bin/find: Permission denied`). `install.sh` and the test suite avoid `find` for this reason. If a *different* command fails the same way, it's the same class of issue — report it. The most common one is `uv` itself; see [When `uv` is blocked](#when-uv-is-blocked-corporate-edr-or-application-control).
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

## uv

[`uv`](https://github.com/astral-sh/uv) powers the global `nbstripout` git filter (strips notebook outputs on every `git add`). It's optional — everything else installs and runs without it.

**Install uv:**

```powershell
# Windows
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

`install.sh` installs `nbstripout` via uv and registers it as a global git filter. After installing uv, re-run `install.sh`.

#### When `uv` is blocked (corporate EDR or application control)

**Symptom:** `uv …: Permission denied`. `install.sh` prints a single "uv is installed but cannot be executed" warning and skips the nbstripout git filter.

**Why:** some managed/corporate machines run an EDR or application-control product that blocks specific executables by reputation — `uv.exe` is a common target (we've also seen `find.exe` and even `System32\whoami.exe` blocked on the same machine). This is **not** an NTFS-permission or PATH problem, so it can't be fixed by relocating or reinstalling uv.

**Confirm it (read-only, in PowerShell):**

```powershell
uv --version                                          # → "Permission denied" if blocked
(Get-Item (Get-Command uv).Source).GetAccessControl().Owner   # you usually still own the file — rules out an ACL issue
```

**Fix:** ask IT / security to **allowlist `uv.exe` and `uvx.exe`** in the EDR / application-control console. Give them the path printed by `command -v uv` (Git Bash) or `(Get-Command uv).Source` (PowerShell). There is no safe script-side workaround — bypassing the control (renaming/repacking the binary, disabling protection) is out of scope.

**Meanwhile:** the rest of the setup works without uv — hooks, permissions, env, commands, and skills all install and run. You only lose notebook output stripping.

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

## Skills

| Skill | Trigger |
|-------|---------|
| `git-pr-message` | "generate a PR description", "write the PR body" |

## Commands

| Command | Description |
|---------|-------------|
| `/user:commit` | Stage and commit with a well-formed message, no AI footers |
| `/user:pr` | Generate a PR title/body from git log and open the PR with `gh` |
