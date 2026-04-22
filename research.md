# Claude Code hooks that actually enforce: a 2026 production playbook

**Bottom line:** The Claude Code community has converged on a clear hierarchy — **hooks enforce, skills suggest, CLAUDE.md advises** — and the gap between them is quantifiable. Merlin Mann's 166-session audit found hooks produce ~95% compliance while prose rules in CLAUDE.md land at 25–40%. Anthropic's own docs now explicitly tell you to *"delete the rule or convert it to a hook"* if Claude already does it without prompting. The implication for a `~/.claude/` dotfiles repo: every instruction you care about must be a PreToolUse/PostToolUse/Stop hook with a non-zero blocking exit code, or you should accept it as advisory and not waste tokens on it. This report catalogs the 15 highest-ROI hooks actually running in production across disler, tdd-guard, cc-sessions, citypaul, Trail of Bits, and other audited repos; pairs them with a Python-scientific-computing playbook (ruff, ty, pytest-regressions, nbstripout, uv-enforcement, FEM binary-file blockers); documents the eight anti-patterns that have been observed to fail in real sessions; and gives you a concrete directory layout plus an `install.sh` bootstrap script for the dotfiles repo itself.

---

## The one mental model that matters

From Anthropic's hooks-guide plus Morph's decision framework (corroborated by Dean Blank, OpenAIToolsHub, alexop.dev):

| Need | Use | Enforcement |
|---|---|---|
| Must happen every single time, no exceptions | **Hook** | Deterministic; exit 2 blocks |
| Reusable domain knowledge loaded on demand | **Skill** (`skills/NAME/SKILL.md`) | Model-gated via description |
| Human-triggered reusable prompt | **Slash command** (`commands/*.md`) | User-triggered only |
| Heavy work in isolated context window | **Subagent** | Model-invoked |
| External API / service connection | **MCP server** | Tool-level |
| Bundle of any of the above | **Plugin** | Distribution layer |
| Judgment call that resists mechanization | **CLAUDE.md** | Advisory; ~25–40% compliance |

The rule that matters most: **if a rule can be mechanized, it *must* be a hook**. Blake Crosley's production write-up is unambiguous — "I initially tried adding 'always run black after editing Python files' to my CLAUDE.md, but the instruction worked only about 80% of the time... A PostToolUse hook eliminates the inconsistency entirely." wmedia.es puts it more sharply: *"A hook doesn't negotiate. It runs every time. Without exception."*

### Hook mechanics you must know before writing any

- **Exit codes drive behavior.** Only `0` (success; stdout may be JSON) and `2` (blocking; stderr is fed back to Claude) are acted on. Exit `1` is a non-blocking warning Claude ignores. Every security hook that uses `exit 1` is broken; Blake Crosley has **"seen this mistake in three different teams' hook configurations, each of which believed they had blocked force pushes."**
- **Stdin JSON schema** for every hook: `{session_id, cwd, hook_event_name, tool_name, tool_input, tool_response?}`. For `Write|Edit|MultiEdit`, the path lives at `.tool_input.file_path`. Parse it with `jq -r '.tool_input.file_path // empty'` — this one-liner appears in ~every production hook.
- **`$CLAUDE_PROJECT_DIR` is the only safe path variable.** Relative paths break when Claude changes cwd mid-session. Always write `bash "$CLAUDE_PROJECT_DIR"/.claude/hooks/x.sh`.
- **Stop hooks must guard against infinite loops.** GitHub issues #10205, #3573, and #1288 all document Stop hooks that ran forever. The required pattern: check `stop_hook_active` first and exit 0 if true.
- **Modern permission schema** (late 2025+): `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow|deny|ask|defer","permissionDecisionReason":"..."}}`. A hook `deny` cannot be overridden by `--dangerously-skip-permissions`. Older `{"decision":"block"}` and `{"block":true}` forms still show up in blog tutorials but are deprecated in spirit.
- **PreToolUse can now rewrite inputs** (Claude Code 2.0.10+), not just block — transparent correction instead of retry loops. Use this to inject `--dry-run`, normalize paths, or redact secrets silently.
- **Known bug (#24327):** PreToolUse `exit 2` sometimes makes Claude stop rather than retry. PostToolUse `exit 2` is the more reliable "tell Claude to fix it" channel for quality gates.

---

## The 15 hooks with proven ROI

Ranked by frequency of appearance in audited production configs. Each comes with the actual JSON, the script logic, and failure modes.

### 1. PostToolUse auto-format on file write

The single most-adopted hook across the ecosystem. Appears in Anthropic's own docs, Pixelmojo, Claudefast, ChrisWiles/claude-code-showcase, Blake Crosley's 95-hook production set, DataCamp, Morph, and the Astral plugin. **Never blocks; always exits 0 after best-effort auto-fix.**

```json
{"hooks":{"PostToolUse":[{"matcher":"Write|Edit|MultiEdit","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/ruff-after-edit.sh","timeout":15}]}]}}
```

```bash
#!/usr/bin/env bash
# .claude/hooks/ruff-after-edit.sh
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ "$file_path" == *.py && -f "$file_path" ]] || exit 0
uv run ruff check --fix --quiet "$file_path" 2>/dev/null
uv run ruff format --quiet "$file_path" 2>/dev/null
exit 0
```

**Effect:** Every .py Claude writes is lint-fixed and formatted before Claude's next turn. **5–30 ms per file.** Prefer ruff over black+isort — ruff ≥ 0.3 produces near-identical output and subsumes isort with `--select I`. **Caveat:** auto-formatting can add tokens (one aggregation cites 160k in three rounds); scope matcher tightly and don't chain multiple formatters.

### 2. PreToolUse blocker for destructive bash

Merlin Mann reports ~99% effectiveness with zero false positives after tuning. The key design choice is **targeted patterns, not naive regex**: `rm -rf ~` blocked, `rm -rf /tmp/test-dir` allowed.

```json
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-destructive.sh"}]}]}}
```

```bash
#!/usr/bin/env bash
input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
# Precise deny patterns — each tested against real incidents
deny_patterns=(
  'rm[[:space:]]+-rf?[[:space:]]+/(\s|$)'   # rm -rf /
  'rm[[:space:]]+-rf?[[:space:]]+~(\s|$)'   # rm -rf ~
  'rm[[:space:]]+-rf?[[:space:]]+\$HOME'
  'git[[:space:]]+push[[:space:]]+.*--force'
  'git[[:space:]]+push[[:space:]]+.*-f(\s|$)'
  'git[[:space:]]+reset[[:space:]]+--hard[[:space:]]+origin'
  'chmod[[:space:]]+-R[[:space:]]+777'
  ':\(\)\{.*\|:&.*\};:'                      # fork bomb
  'curl[[:space:]].*\|[[:space:]]*(bash|sh|zsh)'
  'DROP[[:space:]]+TABLE'
)
for p in "${deny_patterns[@]}"; do
  if echo "$cmd" | grep -qE "$p"; then
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by safety policy: matches /$p/"}}
EOF
    exit 0
  fi
done
exit 0
```

**Real incidents this prevents:** the December 2025 "Home Directory Nuke" (`rm -rf ~/` verified in GitHub issue #10077, ran on Ubuntu/WSL2 *without* `--dangerously-skip-permissions`), the November 2025 `~` directory shell-expansion incident (#12637), and the Nx malware campaign that specifically targeted Claude Code. **Defense-in-depth only** — paddo.dev explicitly warns hooks are "one layer, not a silver bullet." Pair with `permissions.deny` and, where available, OS sandboxing.

### 3. Secret-file protection on Read/Edit/Write/Bash

Trail of Bits ships this in their opinionated config. Two layers: declarative permissions (cheap, stateless) **plus** a Bash-level hook (because `permissions.deny` has a bypass bug — issue #6631).

```json
{
  "permissions": {
    "deny": [
      "Read(./.env)","Read(./.env.*)","Read(./secrets/**)",
      "Write(./.env*)","Write(./secrets/**)",
      "Bash(cat .env)","Bash(cat .env.*)","Bash(cat secrets/**)"
    ]
  }
}
```

Combined with a PreToolUse hook that inspects file_path against a blocklist (`.env`, `*.key`, `*.pem`, `credentials.json`, `.mcp.local.json`, `~/.ssh/**`).

**Caveat:** GitHub issue #6631 (open April 2026) shows `permissions.deny` on Read/Write patterns is not 100% enforced — Bash subprocesses can still `cat` protected paths. The Bash-level hook is non-negotiable.

### 4. PostToolUse type-check that blocks

The hook wmedia.es calls "the difference between a junior who hands you broken code and a teammate who builds before pushing." Scope narrowly to changed files.

```bash
#!/usr/bin/env bash
input=$(cat); file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ "$file_path" == *.py && -f "$file_path" ]] || exit 0
output=$(uv run mypy --no-color-output --show-column-numbers "$file_path" 2>&1)
if [[ $? -ne 0 ]]; then
  echo "mypy type errors in $file_path:" >&2
  echo "$output" >&2
  exit 2   # Claude reads stderr and retries
fi
exit 0
```

**For the Python scientific stack, prefer `ty` (Astral's Rust-written checker, 0.0.10 as of April 2026, 1.0 targeted late 2026).** Measured at 0.43s average vs. pyright 0.95s on a 2092-line codebase, and gradual-typing by default produces fewer false positives on `scipy.*`/`ansys.*`. Swap `mypy` → `uvx ty@latest check` in the script above.

**Don't use `--strict` mypy on numpy/scipy code in the inner hook loop** — it's painful and slow. Keep strict mode in CI; run `ty` on every edit for fast feedback.

### 5. pytest on save with `--lf`

The `--lf` (last-failed) flag is the key: after the first failure, subsequent runs test only the failing set, then expand. Combine with `-x` (stop on first fail) and `-q` for terse output Claude can parse.

```bash
#!/usr/bin/env bash
input=$(cat); file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ "$file_path" == *.py ]] || exit 0
[[ -d tests ]] || exit 0
output=$(uv run pytest --lf -x --tb=short -q 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Tests failed after edit:" >&2; echo "$output" >&2; exit 2
fi
exit 0
```

**For large FEM suites**, swap `--lf` for `--testmon` (`uv add --dev pytest-testmon`) which tracks source-line coverage and runs only affected tests — sub-second after warm-up. Add `.testmondata` to `.gitignore`.

### 6. Block `git commit` and push to main

Near-universal in shared `.claude/settings.json` files. ChrisWiles and the Trail of Bits template both ship variants.

```bash
#!/usr/bin/env bash
input=$(cat); cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
branch=$(git branch --show-current 2>/dev/null)
if [[ "$branch" =~ ^(main|master|prod|production)$ ]]; then
  if echo "$cmd" | grep -qE '^git (commit|push)'; then
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Direct $branch modifications are prohibited. Create a feature branch first."}}
EOF
    exit 0
  fi
fi
exit 0
```

### 7. Strip `Co-Authored-By: Claude` attribution

**The correct modern fix is a setting, not a hook.** Claude Code added native support; use it in `~/.claude/settings.json`:

```json
{"includeCoAuthoredBy":false,"attribution":{"commit":"","pr":""}}
```

Empty-string `commit` removes the co-author trailer; empty-string `pr` removes the "Generated with Claude Code" PR footer. Hook-based stripping via `git commit --amend` still shows up in older blog posts but is fragile.

### 8. SessionStart context injection

Merlin Mann's SessionStart runs `git status`, surfaces `NEXT.md` handoff notes, and kicks off a test suite health check at ~1–2% of context budget — replacing 500 lines of CLAUDE.md "remember to check status before you start" rules. Anthropic's `hookify` plugin supports this as a first-class feature via markdown rule files.

```json
{"hooks":{"SessionStart":[{"matcher":"startup|resume|clear","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-start.sh"}]}]}}
```

The script prints to stdout; stdout from SessionStart hooks is injected into Claude's context as system info.

### 9. Notification bridge for "Claude needs input"

Near-universal. Dominant mobile pattern: **ntfy.sh over Tailscale** — your phone gets a push notification when Claude idles or hits a permission prompt, with Allow/Deny action buttons that round-trip via SSE (nickknissen/claude-ntfy-hook, coa00/claude-push). Desktop variants use `osascript` (macOS), `notify-send` (Linux), BurntToast (Windows), or a Go binary like 777genius/claude-notifications-go with click-to-focus into the right tmux pane.

```json
{"hooks":{"Notification":[{"hooks":[{"type":"command","command":"~/.claude/hooks/notify.sh"}]}]}}
```

The script reads `.message`, `.title`, `.tool_name` from stdin JSON and dispatches.

### 10. Stop-hook response-quality gate

Merlin Mann's `check-claims.sh` scans Claude's final output for 79 failure-stereotype phrases ("I can't access," "probably," "from memory," "if you could share…"). **This is his most-triggered hook in production: 1,480 blocks logged as of April 2026.** If matched, it blocks the Stop and forces Claude to verify or clarify.

```bash
#!/usr/bin/env bash
input=$(cat)
[[ "$(echo "$input" | jq -r '.stop_hook_active')" == "true" ]] && exit 0
transcript=$(echo "$input" | jq -r '.transcript_path')
last=$(tail -20 "$transcript")
if echo "$last" | grep -qE "I (can't|cannot) access|from memory|probably|I think |if you could (share|provide)"; then
  echo "Response contains uncertain/speculative phrasing. Verify before completing." >&2
  exit 2
fi
exit 0
```

### 11. PreCompact transcript backup

When Claude is about to compact the conversation and lose context, back the transcript up first. Low cost, high payoff during recovery.

```json
{"hooks":{"PreCompact":[{"hooks":[{"type":"command","command":"cp \"$(jq -r '.transcript_path')\" \"$CLAUDE_PROJECT_DIR/.claude/backups/compact-$(date +%s).jsonl\""}]}]}}
```

### 12. `uv`-enforcement PreToolUse for Python

Blocks `pip install`, `python -m pytest`, bare `pytest`, `poetry add`, `conda install` — redirects to `uv add` / `uv run`. The pydevtools canonical pattern. Saves every Python project from venv drift.

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import json, sys
data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")
redirects = {"pip install":"uv add","pip3 install":"uv add","pip uninstall":"uv remove",
             "poetry add":"uv add","poetry install":"uv sync","conda install":"uv add",
             "python -m pytest":"uv run pytest","python -m ruff":"uv run ruff"}
for pattern, fix in redirects.items():
    if pattern in cmd:
        print(f"Blocked: '{pattern}' — use '{fix}' instead.", file=sys.stderr); sys.exit(2)
```

Note the `#!/usr/bin/env -S uv run --script` + `# /// script` PEP-723 header — **this is disler's canonical single-file Python hook pattern** (from claude-code-hooks-mastery). Hooks are self-contained and don't pollute any project venv.

### 13. Notebook output stripping

Data-science critical. Two layers:

**Layer 1 — git filter (the 10-year-old standard):**
```bash
uv tool install nbstripout
nbstripout --install --attributes .gitattributes
echo "*.ipynb filter=nbstripout diff=ipynb" >> .gitattributes
```

**Layer 2 — Claude hook for immediate stripping:**
```json
{"matcher":"Write|Edit|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/nbstripout.sh","timeout":10}]}
```

```bash
#!/usr/bin/env bash
input=$(cat); fp=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ "$fp" == notebooks/*.ipynb && -f "$fp" ]] || exit 0
uv tool run nbstripout "$fp" 2>/dev/null
exit 0
```

**Scope the hook matcher to `notebooks/` and leave `scratch/` untouched** — otherwise Claude can't see plots it just rendered during iterative work.

### 14. FEM binary-file blocker (speculative but solid)

Highly relevant for Ansys / FEM workflows. No community-vetted hook yet, but the failure mode (losing a 1.9 GB push mid-session — requested in GitHub issue #41927) is real.

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
import json, sys, subprocess, pathlib
BIG_EXT = {".rst",".db",".cdb",".odb",".rth",".rmg",".msh",".vtu",".vtk",".h5",".hdf5",".npz",".pkl"}
MAX_BYTES = 50 * 1024 * 1024
data = json.load(sys.stdin); cmd = data.get("tool_input",{}).get("command","")
if not cmd.startswith(("git add","git commit -a")): sys.exit(0)
result = subprocess.run(["git","status","--porcelain"], capture_output=True, text=True)
offenders = []
for line in result.stdout.splitlines():
    if not line.strip(): continue
    path = pathlib.Path(line[3:].strip().strip('"'))
    if not path.exists(): continue
    if path.suffix.lower() in BIG_EXT or path.stat().st_size > MAX_BYTES:
        offenders.append((path, path.stat().st_size))
if offenders:
    print("Large or binary result files must not be committed directly:", file=sys.stderr)
    for p,s in offenders: print(f"  {p} ({s/1024/1024:.1f} MB)", file=sys.stderr)
    print("\nUse Git LFS or DVC; or commit a manifest/hash instead.", file=sys.stderr)
    sys.exit(2)
```

For district-heating time-series data, prefer `dvc` over LFS (research-group ergonomics) and keep a small `.parquet` sample in-repo with the full dataset in Azure Blob/S3 referenced by config path.

### 15. Environment variable enforcement (matplotlib, PYTHONDONTWRITEBYTECODE, locale)

Not a hook — a settings-level `env` block. Faster than a hook and zero latency.

```json
{"env":{"MPLBACKEND":"Agg","PYTHONDONTWRITEBYTECODE":"1","LC_ALL":"C.UTF-8","UV_NO_SYNC":"0"}}
```

Claude Code 1.0.90+ supports `env` at settings root. Prefer this over a PreToolUse hook for headless-matplotlib or encoding setup.

---

## Deterministic skills and slash commands worth having

Most "slash commands" in the ecosystem are markdown prompt templates — prose, not scripts. **Genuine script-backed commands are rare and high-ROI.** Four worth building:

- **`/regen-regressions`** for FEM workflows — runs `uv run pytest --force-regen && git diff tests/` and forces a review of which numerical snapshots changed so physical deltas can be justified. Pairs with `pytest-regressions` (the SciPy-community standard for numerical snapshot testing; `num_regression`, `ndarrays_regression`, `dataframe_regression` fixtures).
- **`/commit`** — runs `git diff --cached`, generates a Conventional Commits message deterministically, and commits. citypaul/.dotfiles ships a version.
- **`/pr`** — generates a PR body from `git log main..HEAD` and `gh pr create`. citypaul ships `/pr` and `/generate-pr-review`.
- **`/run-params \<notebook\>`** — papermill parameterized execution for heating-model scenario runs: `uv run papermill notebooks/{{n}}.ipynb out/{{n}}_$(date +%Y%m%d).ipynb -f params.yaml`.

The broader skills ecosystem worth importing via `/plugin install`:
- **Astral's official plugin** (`astral-sh/claude-code-plugins`) — installs `/astral:uv`, `/astral:ruff`, `/astral:ty` skills plus a `ty` LSP. Skills only, no hooks — you layer your hooks on top.
- **`tdd-guard`** (nizos, 1,800★) — the most widely-adopted blocking hook in the ecosystem, enforces red-green-refactor with per-language reporters (Vitest/Jest/PHPUnit/nextest/Go/Storybook).
- **`hookify`** (Anthropic official) — creates hooks from plain-markdown rule files instead of JSON. Useful for quick one-offs without touching `settings.json`.
- **`security-guidance`** (Anthropic official) — PreToolUse hook monitoring 9 injection/eval/pickle patterns.

---

## The eight documented anti-patterns

1. **Putting enforceable rules in CLAUDE.md.** Morph's analysis: frontier LLMs reliably follow ~150–200 instructions; Claude Code's built-in prompt consumes ~50, leaving ~100–150 usable slots. Merlin Mann's audit shows ~25–40% compliance on prose rules vs. ~95% on hooks. Anthropic's best-practices doc is explicit: *"Bloated CLAUDE.md files cause Claude to ignore actual instructions."* **Every rule Claude already follows reliably should be deleted; every rule that must be enforced should be a hook.**
2. **Stop hooks without `stop_hook_active` check.** Documented infinite loops in issues #10205, #3573, #1288, #987. Always exit 0 early if `stop_hook_active` is true.
3. **Naive `rm -rf` regex.** Catches `rm -rf test/` (false positive) while missing `rm -rf ~` after shell expansion (false negative). Use targeted patterns tested against the real incidents above.
4. **Security hooks using `exit 1` instead of `exit 2`.** Blake Crosley has seen this mistake in three different teams' hook configs, each believing force-push was blocked. Only `exit 2` enforces.
5. **Over-broad matchers.** Matcher `""` or `.*` on PostToolUse fires on every Grep and Glob read. Be specific: `Write|Edit|MultiEdit`, optionally with the 2026 `"if": "Edit(*.py)"` narrowing field.
6. **Slow hooks on high-frequency tool calls.** ruvnet/ruflo added 13 s per CLI interaction (4.8s → 18.2s) because each PreToolUse spawned a Node process. Blake Crosley's threshold: **>500ms on PostToolUse makes sessions feel sluggish; keep each hook <200ms.** Python startup (~200–400ms) is borderline — use Bash for fast PreToolUse checks, reserve Python for logic that justifies it.
7. **First-month over-engineering.** Blake Crosley: *"My first month produced 25 hooks, many of which added context the agent already had."* paddo.dev's prescription: *"Start with one rule. Watch it trigger for a week. Tune the pattern. Add another."*
8. **Hooks themselves as an attack surface.** Check Point disclosed three CVEs (CVE-2025-59536, CVE-2026-21852, CVE-2026-24887) where malicious repo-level `.claude/settings.json` hooks were an RCE vector — *"the guardrail itself became the entry point."* Consequence: **trust the repo before trusting its hooks.** Enterprise deployments should set `allowManagedHooksOnly: true` in `/etc/claude-code/managed-settings.json` to block plugin and project hooks entirely.

---

## Dotfiles deployment: concrete layout and install script

### Recommended directory layout

```
~/.claude-dotfiles/                  # git repo, symlinked/copied into ~/.claude/
├── CLAUDE.md                        # lean: judgment rules only
├── settings.json                    # committed: env, permissions, hooks refs
├── settings.local.example.json      # template; install.sh copies to .local.json
├── commands/                        # slash commands
├── skills/                          # SKILL.md + scripts/
├── agents/
├── hooks/
│   ├── ruff-after-edit.sh
│   ├── ty-check.sh
│   ├── pytest-lf.sh
│   ├── block-destructive.sh
│   ├── enforce-uv.py
│   ├── block-big-binaries.py
│   ├── nbstripout.sh
│   └── check-claims.sh
├── plugins-installed.txt            # one plugin ID per line; install.sh reinstalls
├── install.sh
├── Makefile
├── .gitignore
├── .gitattributes                   # * text=auto eol=lf; hooks executable
└── README.md
```

### `.gitignore` (allowlist style, safest for public repos)

```gitignore
*
!.gitignore
!.gitattributes
!CLAUDE.md
!settings.json
!settings.local.example.json
!commands/
!commands/**
!skills/
!skills/**
!agents/
!agents/**
!hooks/
!hooks/**
!plugins-installed.txt
!install.sh
!Makefile
!README.md
```

Add explicit blocks too (belt and suspenders): `settings.local.json`, `plugins/`, `cache/`, `history.jsonl`, `projects/`, `sessions/`, `transcripts/`, `.credentials.json`, `.claude.json`, `.env*`, `*.key`, `*.pem`, `.mcp.local.json`.

### Dotfile-manager choice

| Tool | Claude fit | When to choose |
|---|---|---|
| **chezmoi** | 9/10 | You manage other dotfiles too, have TTS/MCP secrets to commit encrypted via age. Best cross-platform. |
| **Dedicated git + install.sh** | 8/10 | `~/.claude/` is the only thing you're versioning. Transparent, forkable, no tool dep. |
| **GNU Stow** | 6/10 | You want symlink farms with zero state. No secrets story. |
| **home-manager (Nix)** | 7/10 if Nix | Ironclad reproducibility, only worth it if you already live in Nix. |
| **Bare git on $HOME** | 5/10 | Avoid — mixes Claude with every dotfile, expanding Claude's surface area. |

For a Nordic Python/FEM developer with likely TTS/MCP API keys, **chezmoi with age encryption** is the strongest default: `chezmoi add --encrypt ~/.claude/settings.local.json` stores it as `encrypted_dot_claude/encrypted_settings.local.json.age` in a public-safe repo.

### `install.sh` bootstrap

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO="${REPO:-$(cd "$(dirname "$0")" && pwd)}"
TARGET="${TARGET:-$HOME/.claude}"
STRATEGY="${STRATEGY:-symlink}"

log(){ printf '\033[1;34m[claude-dotfiles]\033[0m %s\n' "$*"; }
command -v git >/dev/null || { echo "git required"; exit 1; }

# Back up pre-existing ~/.claude once
if [[ -e "$TARGET" && ! -L "$TARGET" && ! -f "$TARGET/.managed-by-dotfiles" ]]; then
  mv "$TARGET" "$TARGET.backup.$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$TARGET"

for item in CLAUDE.md settings.json commands skills agents hooks output-styles; do
  [[ -e "$REPO/$item" ]] || continue
  if [[ "$STRATEGY" == "symlink" ]]; then ln -snf "$REPO/$item" "$TARGET/$item"
  else rm -rf "$TARGET/$item"; cp -R "$REPO/$item" "$TARGET/$item"; fi
done
touch "$TARGET/.managed-by-dotfiles"

# Seed settings.local.json from template on first run
[[ ! -f "$TARGET/settings.local.json" && -f "$REPO/settings.local.example.json" ]] && \
  cp "$REPO/settings.local.example.json" "$TARGET/settings.local.json"

# Restore +x on all hooks (git drops it across some transfers)
find "$TARGET/hooks" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} +

# Reinstall plugins declared in plugins-installed.txt
if [[ -f "$REPO/plugins-installed.txt" ]] && command -v claude >/dev/null; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    claude plugin install "$line" --scope user || true
  done < "$REPO/plugins-installed.txt"
fi

# Pre-populate global git/ignore to remove the surprise-edit from Claude Code (#10230)
mkdir -p "$HOME/.config/git"
grep -qxF '**/.claude/settings.local.json' "$HOME/.config/git/ignore" 2>/dev/null || \
  echo '**/.claude/settings.local.json' >> "$HOME/.config/git/ignore"

log "Done. Run: claude --version"
```

### Settings hierarchy and precedence (2026)

Five sources, highest wins: CLI flags → managed/enterprise settings (`/etc/claude-code/managed-settings.json` + drop-ins) → `.claude/settings.local.json` → `.claude/settings.json` → `~/.claude/settings.json`. **Arrays merge and deduplicate across scopes; single values take the highest-scope wins. Deny beats ask beats allow within a scope.** No hot reload — changes require session restart.

One-liner bootstrap for a new machine (chezmoi path): `sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply <your-github-user>`. The `curl | bash` pattern is standard but should be reserved for the very first machine; subsequent machines should `git clone` and inspect `install.sh` before running it.

### Shared-vs-personal split

- **`~/.claude/`** (personal, this dotfiles repo): your global conventions, personal hooks, personal skills, global `CLAUDE.md` with judgment rules. Committed publicly.
- **`.claude/` per-project** (checked into the work repo): team permission allow/deny, project-specific hooks (e.g., the district-heating pandera schema enforcement), project `CLAUDE.md` with domain conventions. Committed to the product repo.
- **`.claude/settings.local.json`** (gitignored everywhere): machine-specific `additionalDirectories`, per-machine allowlists, API key env refs.
- **Ship team-wide policy as a plugin** to a private marketplace repo, not by manually syncing `~/.claude/` across teammates. Plugins version independently and support `/plugin update`.

---

## Your starter configuration

For a Nordic Python developer doing FEM and district-heating data analysis, the minimum config that delivers ~80% of the value without over-engineering:

**Week 1 (three hooks):**
1. `ruff-after-edit.sh` (PostToolUse, non-blocking auto-format)
2. `enforce-uv.py` (PreToolUse Bash, blocking)
3. `nbstripout` as a git filter (not a Claude hook; one-time setup)

**Week 2 (add two more once week 1 is stable):**
4. `ty-check.sh` (PostToolUse, blocking)
5. `block-destructive.sh` (PreToolUse Bash, blocking)

**Week 3 (the numerical-specific layer):**
6. `pytest-lf.sh` with `pytest-regressions` fixtures (`num_regression`, `ndarrays_regression`) for stiffness matrices and heat-load calculations
7. `block-big-binaries.py` if you work with `.rst`/`.cdb`/`.h5` Ansys artifacts

**Permissions baseline** (in `~/.claude/settings.json`): deny `sudo`, `pip install`, `rm -rf ~`, `.env` reads; ask on `git push`, writes to `pyproject.toml`/`uv.lock`; allow the entire `uv *`, `pytest*`, `ruff *`, `ty *` surface area.

**Install Astral's official plugin** (`/plugin install astral-sh-astral-plugins-astral@astral-sh/claude-code-plugins`) for the `ty` LSP and `/astral:*` skills — skills teach Claude *what* to use, hooks enforce *that* it uses them.

**Don't install**: tdd-guard unless you actually want strict TDD enforcement (blocks every Write without a failing test first — ROI only if you already work TDD-first); cc-sessions unless you want opinionated DAIC workflow gates; any of the 176+ plugins advertised in marketing-heavy marketplaces without personally inspecting their hooks (CVE-2025-59536 class of attack).

---

## Conclusion: what actually moves the needle

**The gap between hooks and CLAUDE.md is an order of magnitude in compliance** — Merlin Mann's 95% vs 25–40%, Blake Crosley's "80% of the time" on prose vs. eliminated inconsistency on hooks, Anthropic's own docs now directing users to convert rules into hooks. For a developer whose explicit constraint is "avoid context bloat and vague directives," the implication is structural: **the dotfiles repo should be ~80% hooks and ~20% CLAUDE.md, not the inverse**, and the CLAUDE.md that remains should be tight judgment calls (array-shape conventions, numerical-test expectations, unit-handling policy) rather than anything mechanizable.

The second non-obvious finding: **distribution has quietly become a solved problem through plugins**, launched GA December 2025 with 36 official Anthropic plugins and thousands of community ones. The historical pattern of git-cloning `~/.claude/` and manually maintaining it across machines is now worth avoiding for anything team-shared — package it as a plugin, publish to a private marketplace repo, and let `/plugin install` handle the deployment. Personal dotfiles still belong in a git repo, but a leaner one focused on machine-identity config rather than shareable automation.

The third, more sobering finding: **hooks are also an attack surface**. Three CVEs in the Claude-Code hook path this year (`CVE-2025-59536`, `CVE-2026-21852`, `CVE-2026-24887`) mean that the next frontier of best practices is less about writing more hooks and more about *trusting fewer of them* — inspect before running, prefer official plugins, set `allowManagedHooksOnly: true` for enterprise, and never blindly clone a `.claude/` tree from a repo you don't personally audit. Determinism cuts both ways: a malicious hook executes just as reliably as a helpful one.