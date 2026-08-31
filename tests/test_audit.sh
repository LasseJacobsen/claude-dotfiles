#!/usr/bin/env bash
# Smoke tests for the iso-24495-text-audit CLI. Run from the dotfiles root:
#   bash tests/test_audit.sh
# Requirements: bash, node >= 22.18 (type stripping, so the .ts files run unbuilt)
#
# These cover the CLI contract — exit codes and which rule each fixture trips —
# not the audit engine itself. The engine is vendored verbatim from upstream and
# has its own bun:test suite there; porting it would mean rewriting a file we
# otherwise copy unchanged.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/skills/iso-24495-text-audit/scripts/audit-text-cli.ts"
PASS=0; FAIL=0; SKIP=0
TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ── output helpers ────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; N='\033[0m'
else
  G=''; R=''; Y=''; N=''
fi

ok()   { printf "  ${G}PASS${N}  %s\n" "$1"; ((PASS++)) || true; }
fail() { printf "  ${R}FAIL${N}  %s\n" "$1"; ((FAIL++)) || true; }
skip() { printf "  ${Y}SKIP${N}  %s\n" "$1"; ((SKIP++)) || true; }
section() { printf "\n=== %s ===\n" "$1"; }

# ── capability detection ──────────────────────────────────────────────────────
# Two separate reasons to skip, reported separately: node may be absent, or it
# may be too old to strip types. Both leave the suite green — the audit skill is
# optional tooling, so a machine without a recent node still passes `make test`.
HAS_NODE=false
NODE_WHY="node not in PATH"
if command -v node >/dev/null 2>&1; then
  if echo 'const n: number = 1; console.log(n)' | node --input-type=module-typescript >/dev/null 2>&1; then
    HAS_NODE=true
  else
    NODE_WHY="node $(node --version) cannot strip types — need >= 22.18"
  fi
fi

# ── CLI helpers ───────────────────────────────────────────────────────────────

# Exit code only.
cli_exit() {
  local code=0
  node "$CLI" "$@" >/dev/null 2>&1 || code=$?
  echo "$code"
}

# Stdout only; stderr suppressed.
cli_stdout() { node "$CLI" "$@" 2>/dev/null || true; }

# Stderr only; stdout suppressed.
cli_stderr() { node "$CLI" "$@" 2>&1 >/dev/null || true; }

# ── assertion helpers ─────────────────────────────────────────────────────────

assert_exit() {
  local want="$1" desc="$2"; shift 2
  local got; got=$(cli_exit "$@")
  if [[ "$got" == "$want" ]]; then
    ok "$desc"
  else
    fail "$desc — expected exit $want, got $got"
  fi
}

assert_stdout_has() {
  local needle="$1" desc="$2"; shift 2
  local out; out=$(cli_stdout "$@")
  if grep -qF "$needle" <<<"$out"; then
    ok "$desc"
  else
    fail "$desc — stdout lacked '$needle'; got: $(tr '\n' ' ' <<<"$out" | cut -c1-160)"
  fi
}

assert_stderr_has() {
  local needle="$1" desc="$2"; shift 2
  local err; err=$(cli_stderr "$@")
  if grep -qF "$needle" <<<"$err"; then
    ok "$desc"
  else
    fail "$desc — stderr lacked '$needle'; got: $(tr '\n' ' ' <<<"$err" | cut -c1-160)"
  fi
}

# ── fixtures ──────────────────────────────────────────────────────────────────
# Each fixture isolates one rule, so a failure names the rule that broke rather
# than reporting a count that could drift for any of seventeen reasons.
FIX="$TMPDIR_BASE/fixtures"
mkdir -p "$FIX"

# One sentence over the 30-word limit.
printf '# Title\n\nThe team must send the report to the office before the end of the week so that the manager can read it and then decide whether the plan needs more work before the board meets again next month.\n' > "$FIX/long-sentence.md"

# One paragraph of six sentences, each short enough to trip nothing else.
printf '# Title\n\nThe cat sat. The dog ran. The bird flew. The fish swam. The mouse hid. The horse slept.\n' > "$FIX/long-paragraph.md"

# Trips none of the seventeen rules.
printf '# Title\n\nThe cat sat on the mat. The dog ran home.\n' > "$FIX/clean.md"

# Not an audited extension.
printf 'not text\n' > "$FIX/image.png"

# ── tests ─────────────────────────────────────────────────────────────────────

if ! $HAS_NODE; then
  section "iso-24495-text-audit"
  skip "$NODE_WHY — the audit CLI needs it"
else

section "findings"
assert_stdout_has "sentence-length"  "long sentence trips sentence-length" \
  "$FIX/long-sentence.md" --project-dir "$FIX"
assert_stdout_has "paragraph-length" "six-sentence paragraph trips paragraph-length" \
  "$FIX/long-paragraph.md" --project-dir "$FIX"
assert_stdout_has "Finding count: 0" "clean fixture reports no findings" \
  "$FIX/clean.md" --project-dir "$FIX"
assert_exit 0 "clean fixture exits 0" "$FIX/clean.md" --project-dir "$FIX"

section "directory audit"
assert_stdout_has "Files read: 3" "directory audit reads all three markdown files" \
  "$FIX" --project-dir "$FIX"
assert_stdout_has "Skipped entries: 0" "directory audit skips nothing readable" \
  "$FIX" --project-dir "$FIX"

section "--json"
JSON_OUT="$TMPDIR_BASE/findings.json"
assert_exit 0 "--json exits 0" "$FIX/long-sentence.md" --project-dir "$FIX" --json "$JSON_OUT"
if [[ -s "$JSON_OUT" ]] && grep -qF 'sentence-length' "$JSON_OUT"; then
  ok "--json writes findings to the named file"
else
  fail "--json did not write usable JSON to $JSON_OUT"
fi

section "argument errors (exit 2)"
assert_exit 2 "no arguments"                    # no path supplied
assert_stderr_has "Usage:" "no arguments prints usage"
assert_exit 2 "--json without a value"          "$FIX/clean.md" --json
assert_exit 2 "--project-dir given twice"       "$FIX/clean.md" --project-dir "$FIX" --project-dir "$FIX"
assert_exit 2 "unknown option"                  "$FIX/clean.md" --bogus x
assert_stderr_has "unknown option" "unknown option names the offending flag" \
  "$FIX/clean.md" --bogus x

section "target errors (exit 1)"
assert_exit 1 "path that does not exist"        "$FIX/absent.md" --project-dir "$FIX"
assert_exit 1 "unsupported extension"           "$FIX/image.png" --project-dir "$FIX"
assert_stderr_has "Select a supported text file" "unsupported extension explains why" \
  "$FIX/image.png" --project-dir "$FIX"

section "runtime wiring"
# The SKILL.md tells the agent which runtime to use. It said 'bun' while the
# script was absent; this guards the pair staying consistent.
SKILL="$ROOT/skills/iso-24495-text-audit/SKILL.md"
if grep -qF 'node <skill-directory>/scripts/audit-text-cli.ts' "$SKILL"; then
  ok "SKILL.md invokes the CLI with node"
else
  fail "SKILL.md does not invoke the CLI with node"
fi
if grep -qiF 'bun' "$SKILL"; then
  fail "SKILL.md still mentions bun"
else
  ok "SKILL.md no longer mentions bun"
fi

fi

# ── summary ──────────────────────────────────────────────────────────────────
printf "\n%s\n" "$(printf '─%.0s' {1..50})"
printf "Results: ${G}%d passed${N}, ${R}%d failed${N}, ${Y}%d skipped${N}\n" \
  "$PASS" "$FAIL" "$SKIP"

if ! $HAS_NODE; then
  printf "\n${Y}Note:${N} install Node 22.18 or newer to run the text-audit tests.\n"
  printf "  https://nodejs.org/  |  winget install OpenJS.NodeJS\n"
fi

[[ "$FAIL" -eq 0 ]]
