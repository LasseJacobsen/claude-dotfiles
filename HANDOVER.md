# Handover — `feature/research-completion-and-cleanup`

This branch contains the result of a multi-step review. Goal: bring the codex-written
dotfiles repo to ship-quality. Status: most of the way there; several reviewer
findings remain open and need a follow-up agent.

---

## What this branch did

### Research.md feature gap-fill
- Added `hooks/session-start.sh` — SessionStart context injection (branch, status, recent commits)
- Added `hooks/notify.sh` — cross-platform desktop notification bridge (BurntToast / osascript / notify-send)
- Added `nbstripout --install --global` step to `install.sh` (Layer 1 git filter)
- **Deferred:** Astral plugin (`astral-sh/claude-code-plugins`) — pending user decision
- **Skipped:** `/regen-regressions`, `/run-params` slash commands (user does not use those workflows)

### /simplify pass — fixed bugs/cleanups
- `block-destructive.sh` — `\s` was being interpreted as literal `s` by `grep -E` (ERE has no `\s`). Replaced with `[[:space:]]`. Added `--recursive --force` long-form patterns. Verified against 16 deny + 9 allow cases.
- `notify.sh` — apostrophes/quotes in messages no longer mangled. PowerShell receives via `$env:CC_TITLE`/`$env:CC_MSG`; osascript via `argv`; notify-send via `--`.
- `block-big-binaries.py` → `block-big-binaries.sh` (Python startup ~250–400ms removed from hot path).
- `enforce-uv.py` → `enforce-uv.sh` (same).
- Both new bash hooks have a cheap-substring pre-filter that skips jq+grep entirely on commands that can't possibly match. On Windows Git Bash: enforce-uv fast-path 1.8s → 377ms; block-big-binaries fast-path 650ms → 354ms.
- `install.sh` — extracted `link_or_copy()` helper. Hooks/commands/skills now symlink-or-copy (matches the README promise that "edits in the repo show up live"). Skill installs no longer nest on re-runs.
- `nbstripout.sh` matcher tightened: `Write|Edit|MultiEdit|NotebookEdit` → `Write|NotebookEdit` (Edit/MultiEdit are line-based and don't match notebook JSON).
- `check-claims.sh` regex: dropped `probably` (too broad — false-positives on legit completion summaries).

### /review pass — fixed BLOCKERS
- **`check-claims.sh` was a silent no-op in production.** Real Claude Code transcripts wrap messages: `{type:"assistant", message:{role, content}}`. The hook was looking at top-level `role` which doesn't exist. Verified against an actual transcript; fixed parser to handle wrapped + flat shapes; added a list-of-content-blocks fixture to the test suite.
- **`enforce-uv.sh` exit semantics violated the documented PreToolUse convention.** README says PreToolUse hooks "output a structured JSON deny decision and exit 0" — this hook printed to stderr and exited 2. Switched to JSON `permissionDecision: deny` with the suggested uv replacement in the reason field. Tests updated from `assert_hook_exit 2` to `assert_deny`.
- **`install.sh` order bug.** `uv` check ran *before* the jq auto-install, so a fresh user missing both got an abort and never reached the jq install. Reordered: jq first, then uv check.
- **`precompact_hook_active` was fictional.** That field doesn't exist in the Claude Code hook schema; PreCompact hooks don't recurse so no guard needed. Removed.
- **README claimed `enforce-uv.sh` "redirects" pip → uv.** It doesn't — it denies the call and includes the suggested replacement in the deny message. README updated to match the code.

**Test result on this branch: 73 pass, 0 fail, 1 skip (ruff PATH).**

---

## Open findings (for the next agent)

Severity tiers from the review. Pick a batch, address, leave the rest.

### BLOCKERS / SHIP-IF-IN-PROD

1. **`block-destructive.sh` posture-not-protection.** The `rm -rf` patterns:
   - Catch `rm -rf $HOME` literal but bypass `rm -rf "$HOME"`, `rm -rf ${HOME}`, `rm -rf "${HOME}"`.
   - Catch `rm -rf /` only when `/` is followed by space or EOL — bypass with `rm -rf /;ls`, `rm -rf /etc`, `rm -rf /var`, `rm -rf /System`.
   - Miss entirely: `dd if=/dev/zero of=/dev/sda`, `mkfs`, `> /dev/sda`, `find / -delete`, `shred`, `wipefs`, `rm -r -f /` (separate flags).
   Decision needed: tighten or own as posture in the README.

2. **`enforce-uv.sh` blocks legitimate `pytest-watch` / `pytest-watcher`.** The bare `pytest` alternation paired with `END=([^a-zA-Z0-9_]|$)` matches `pytest` followed by `-` (since `-` is non-alphanumeric/underscore). Decision needed: anchor more aggressively (`pytest($|[[:space:]])`), drop bare `pytest` from deny list, or accept the false positive.

3. **`check-claims.sh` `I think ` is still aggressive.** Any final response containing "I think the issue is X" gets blocked. Now that the hook actually works (was a no-op before this branch), this is going to start firing on legitimate analysis. Options: drop `I think `, narrow to specific anti-patterns ("I think but I'm not sure"), or document the escape valve.

4. **`ty-check.sh` does `uvx ty@latest` on every Python edit.** That revalidates the latest version against PyPI when the cache TTL elapses, paying network round-trips on the hot path. Pin to a specific version (e.g. `ty@0.0.10`).

### NICE-TO-FIX

5. `install.sh` backup-then-continue swallows failures: if the `cp -r` backup fails (Claude Code holds files open), the script prints "Warning: backup failed — continuing anyway" and clobbers the original anyway. Should abort on backup failure.

6. `nbstripout --install --global` writes a filter referencing the bare `nbstripout` command. If the user later runs git from a non-login shell that doesn't have `~/.local/bin` on PATH, the global filter becomes a fatal error on every `git add`. Resolve to absolute path.

7. `protect-secrets.sh` bypassable: doesn't catch `awk '{print}' .env`, `xxd .env`, `python -c "open('.env').read()"`, `<(cat .env)`. Either own as best-effort in the README or expand the tool list.

8. `block-big-binaries.sh`:
   - Bypasses `git -C /path add` (fast-path checks for `"git add` literal).
   - `git status --porcelain` octal-escapes non-ASCII paths under default `core.quotePath=true`. Fix: use `--porcelain=v1 -z` and read NUL-delimited.

9. `enforce-uv.sh` allows `uvx pytest` (no stage anchor matches the space before `pytest`). Inconsistent if "uv run pytest" is the only blessed form.

10. `notify.sh` doesn't probe for `powershell.exe` on Windows — assumes it's on PATH. Wrap in `command -v powershell.exe || true`.

11. `session-start.sh` runs git without `LC_ALL=C` or `GIT_OPTIONAL_LOCKS=0`. Cheap to add.

12. Inconsistent `set -euo pipefail` across hooks. Some have it, some don't.

13. `SERENA_PYTHON=$(uvx … python -c …)` may return a Windows path with backslashes; pipe through `cygpath -u` on Git Bash.

14. README at line 41 says `git clone <this-repo> ~/claude-dotfiles` — `~/claude-dotfiles` is not enforced anywhere; the script uses `$(dirname "$0")`. Misleading.

### NITs (low value)

15. `settings.json` `Bash(rm -rf /*)` permission deny — pattern `*` is Claude-pattern, not shell glob. Annotate.
16. Multiple PreToolUse entries with the same `"matcher": "Bash"` — could be one entry with five hooks. Cosmetic.
17. `tests/test_hooks.sh` `precompact-backup` test mutates `~/.claude/backups/`. Should redirect to `$TMPDIR_BASE`.
18. `Makefile` has no jq probe — `make test` reports SKIP-as-pass even when jq is missing entirely.
19. `CLAUDE.md` is generic Python preamble; says nothing repo-specific. Could be expanded with hook-design rules ("PreToolUse → JSON deny + exit 0" etc) for future contributors.
20. `research.md` is committed and 31 KB — dead weight unless someone wants it as a docs/ artifact.
21. `plugins-installed.txt` is comments only; the install.sh loop walks an empty file.
22. `.gitattributes` lines 3-4 are redundant with line 1 (`* text=auto eol=lf`).
23. `tests/test_hooks.sh` doesn't use `-z` NUL handling for the porcelain test fixture.

---

## State of the working tree at handover

Branch: `feature/research-completion-and-cleanup`, pushed.

Working tree: clean after the upcoming commit.

Test suite: 73 pass, 0 fail, 1 skip (ruff not on this machine's PATH — passes in CI/where ruff is available).

`jq` was installed via `winget` during this session; PATH update only takes effect in new shells. If you run `make test` here without restarting Git Bash, you'll need:
```
export PATH="/c/Users/AZ90450/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe:$PATH"
```

---

## Suggested next steps for follow-up agent

1. Show this doc to the user. Ask which open findings to address — most need a judgement call (tighten vs. own as posture, drop a rule vs. narrow it).
2. **Highest value first:** open finding #3 (`I think` regex). The hook now actually works, so it's about to start firing. User should confirm intent before the next session.
3. Then #4 (pin `ty` version) — quick fix, eliminates intermittent network stalls.
4. Then #2 (`pytest-watcher` false positive) — also quick.
5. Then `install.sh` correctness items #5, #6, #13.
6. Defer the NITs unless the user asks.

After: open the PR (use `/user:pr` or the `git-pr-message` skill — both are checked in). Title suggestion: `feat: hook completion, simplify, schema fixes`. Body: summarise the three pass categories above.
