#!/usr/bin/env bash
# install.sh tests. Run from the dotfiles root: bash tests/test_install.sh
#
# Installs into a temp dir via CLAUDE_DOTFILES_TARGET, with
# CLAUDE_DOTFILES_SKIP_TOOLS=1 so nothing on this machine (jq, uv, nbstripout,
# global git config) is touched. Covers the prune step: the four managed dirs
# must mirror the repo, and everything else under the target must survive.
#
# No `find` or `sort` here: both are EDR-blocked on some corporate machines
# (see README → "When uv is blocked"). Glob loops only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0; SKIP=0
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

if [[ -t 1 ]]; then
  G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; N='\033[0m'
else
  G=''; R=''; Y=''; N=''
fi
ok()   { printf "  ${G}PASS${N}  %s\n" "$1"; ((PASS++)) || true; }
fail() { printf "  ${R}FAIL${N}  %s\n" "$1"; ((FAIL++)) || true; }
skip() { printf "  ${Y}SKIP${N}  %s\n" "$1"; ((SKIP++)) || true; }
section() { printf "\n=== %s ===\n" "$1"; }

# Run the installer against $1; stdout+stderr captured into $2.
run_install() {
  local target="$1" logfile="$2"
  CLAUDE_DOTFILES_TARGET="$target" CLAUDE_DOTFILES_SKIP_TOOLS=1 \
    bash "$ROOT/install.sh" >"$logfile" 2>&1
}

assert_absent() { [[ ! -e "$1" && ! -L "$1" ]] && ok "$2" || fail "$2 — still exists: $1"; }
assert_present() { [[ -e "$1" ]] && ok "$2" || fail "$2 — missing: $1"; }
assert_log_has() { grep -qF "$1" "$2" && ok "$3" || fail "$3 — log lacked '$1'"; }

# ── managed target: prune + install ──────────────────────────────────────────
section "prune stale entries from the four managed dirs"
T="$TMPDIR_BASE/managed/.claude"
mkdir -p "$T/hooks" "$T/commands" "$T/skills/stale-skill" "$T/output-styles" \
         "$T/projects/x" "$T/plans" "$T/backups"
touch "$T/.managed-by-dotfiles"
echo "stray" > "$T/hooks/stray.py"
echo "keep"  > "$T/hooks/.keep"
echo "stray" > "$T/commands/stray.md"
echo "stray" > "$T/skills/stale-skill/SKILL.md"
echo "stray" > "$T/output-styles/stray.md"
echo "user notes"      > "$T/projects/x/notes.md"
echo "a plan"          > "$T/plans/p.md"
echo "{\"t\":1}"       > "$T/backups/b.jsonl"
echo "{\"local\":true}" > "$T/settings.local.json"

LOG="$TMPDIR_BASE/install-1.log"
if run_install "$T" "$LOG"; then
  ok "install.sh exits 0 on a managed target"
else
  fail "install.sh failed (see below)"; cat "$LOG"
fi

assert_absent "$T/hooks/stray.py"              "prunes a hook the repo does not ship"
assert_absent "$T/hooks/.keep"                 "prunes dotfiles too"
assert_absent "$T/commands/stray.md"           "prunes a command the repo does not ship"
assert_absent "$T/skills/stale-skill"          "prunes a skill directory the repo does not ship"
assert_absent "$T/output-styles/stray.md"      "prunes an output style the repo does not ship"
assert_log_has "Pruned hook: stray.py"         "$LOG" "logs the pruned hook"
assert_log_has "Pruned skill: stale-skill"     "$LOG" "logs the pruned skill"
assert_log_has "Pruned command: stray.md"      "$LOG" "logs the pruned command"
assert_log_has "Pruned output style: stray.md" "$LOG" "logs the pruned output style"

section "every repo entry is installed"
missing=0; count=0
for dir in hooks commands skills output-styles; do
  for src in "$ROOT/$dir"/*; do
    [[ -e "$src" ]] || continue
    count=$((count + 1))
    name=$(basename "$src")
    if [[ ! -e "$T/$dir/$name" ]]; then
      fail "$dir/$name not installed"; missing=1
    fi
  done
done
if [[ "$count" -eq 0 ]]; then
  fail "found no repo entries to check, so this test proved nothing"
elif [[ "$missing" -eq 0 ]]; then
  ok "all $count repo entries present in the target"
fi
assert_present "$T/settings.json" "settings.json installed"
assert_present "$T/CLAUDE.md"     "CLAUDE.md installed"
assert_present "$T/skills/domain-modeling/SKILL.md" "skill directories are installed with their contents"

section "unmanaged state survives"
[[ "$(cat "$T/projects/x/notes.md")" == "user notes" ]] && ok "projects/ untouched" || fail "projects/ changed"
[[ "$(cat "$T/plans/p.md")" == "a plan" ]]              && ok "plans/ untouched"    || fail "plans/ changed"
[[ "$(cat "$T/backups/b.jsonl")" == '{"t":1}' ]]         && ok "backups/ untouched"  || fail "backups/ changed"
[[ "$(cat "$T/settings.local.json")" == '{"local":true}' ]] && ok "settings.local.json untouched" || fail "settings.local.json changed"
stray_backup=0
for b in "$TMPDIR_BASE/managed/.claude.backup."*; do
  [[ -e "$b" ]] && stray_backup=1
done
[[ "$stray_backup" -eq 0 ]] && ok "no backup made when the marker is present" || fail "a backup was made despite the marker"

section "second run is idempotent"
LOG2="$TMPDIR_BASE/install-2.log"
if run_install "$T" "$LOG2"; then
  ok "install.sh exits 0 on re-run"
else
  fail "install.sh failed on re-run"; cat "$LOG2"
fi
if grep -q "Pruned" "$LOG2"; then
  fail "re-run pruned something: $(grep Pruned "$LOG2" | tr '\n' ' ')"
else
  ok "re-run prunes nothing"
fi

# ── symlink safety ────────────────────────────────────────────────────────────
section "pruning a symlinked entry never follows it into the repo"
S="$TMPDIR_BASE/symlink/.claude"
mkdir -p "$S/skills"; touch "$S/.managed-by-dotfiles"
if ln -s "$ROOT/skills/domain-modeling" "$S/skills/gone" 2>/dev/null; then
  run_install "$S" "$TMPDIR_BASE/install-3.log" || fail "install.sh failed on symlink target"
  assert_absent  "$S/skills/gone"          "stale symlink removed"
  assert_present "$ROOT/skills/domain-modeling/SKILL.md" "symlink target in the repo untouched"
else
  skip "symlinks unavailable here (Windows without Developer Mode) — symlink prune test skipped"
fi

# ── unmanaged target: backup first ────────────────────────────────────────────
section "an unmanaged target is backed up before install"
U="$TMPDIR_BASE/unmanaged/.claude"
mkdir -p "$U/hooks"
echo "precious" > "$U/hooks/mine.sh"
run_install "$U" "$TMPDIR_BASE/install-4.log" || fail "install.sh failed on unmanaged target"
backup_found=0
for b in "$TMPDIR_BASE/unmanaged/.claude.backup."*; do
  [[ -d "$b" ]] || continue
  backup_found=1
  [[ "$(cat "$b/hooks/mine.sh")" == "precious" ]] && ok "backup holds the original content" || fail "backup lacks original content"
done
[[ "$backup_found" -eq 1 ]] && ok "backup directory created" || fail "no .claude.backup.* created"
assert_absent  "$U/hooks/mine.sh"          "unmanaged hook pruned from the live target after backup"
assert_present "$U/.managed-by-dotfiles"   "target marked as managed afterwards"

# ── summary ───────────────────────────────────────────────────────────────────
printf "\n──────────────────────────────────────────────────\n"
printf "Results: %d passed, %d failed, %d skipped\n" "$PASS" "$FAIL" "$SKIP"
[[ "$FAIL" -eq 0 ]]
