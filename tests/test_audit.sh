#!/usr/bin/env bash
# Smoke tests for the vendored ISO 24495 audit tooling: the iso-24495-text-audit
# CLI and the four iso-24495-4 gap-analysis CLIs. Run from the dotfiles root:
#   bash tests/test_audit.sh
# Requirements: bash, node >= 22.18 (type stripping, so the .ts files run unbuilt)
#
# These cover the CLI contract — exit codes and which rule each fixture trips —
# not the audit engines themselves. Those are vendored verbatim from upstream and
# have their own bun:test suites there; porting them would mean rewriting files we
# otherwise copy unchanged.
#
# The "SKILL.md references" section guards the bug that prompted this file: both
# skills shipped pointing at scripts that vendoring had never copied, so invoking
# either one always failed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/skills/iso-24495-text-audit/scripts/audit-text-cli.ts"
S4="$ROOT/skills/iso-24495-4/scripts"
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

# The same three assertions for any vendored script, not just the text-audit CLI.
assert_script_exit() {
  local want="$1" script="$2" desc="$3"; shift 3
  local got=0
  node "$script" "$@" >/dev/null 2>&1 || got=$?
  if [[ "$got" == "$want" ]]; then
    ok "$desc"
  else
    fail "$desc — expected exit $want, got $got"
  fi
}

assert_script_stderr_has() {
  local needle="$1" script="$2" desc="$3"; shift 3
  local err; err=$(node "$script" "$@" 2>&1 >/dev/null || true)
  if grep -qF "$needle" <<<"$err"; then
    ok "$desc"
  else
    fail "$desc — stderr lacked '$needle'; got: $(tr '\n' ' ' <<<"$err" | cut -c1-160)"
  fi
}

# Every scripts/, references/ or assets/ path a SKILL.md names must exist. This
# is the regression guard: both skills once named files that vendoring had
# dropped, and nothing caught it until someone invoked the skill.
#
# No `sort -u` here on purpose: sort.exe is EDR-blocked on some corporate
# machines (see README → "When uv is blocked"), and a failed pipeline would
# yield zero references, so every skill would pass vacuously. Checking a
# duplicate reference twice costs nothing; a silent pass costs the whole test.
# `found` makes that failure mode loud rather than green.
assert_skill_refs() {
  local skill_dir="$1" skill_name="$2"
  local missing=0 found=0 ref
  while read -r ref; do
    [[ -z "$ref" ]] && continue
    found=$((found + 1))
    if [[ ! -e "$skill_dir/$ref" ]]; then
      fail "$skill_name names $ref, which does not exist"
      missing=1
    fi
  done < <(grep -oE '(scripts|references|assets)/[A-Za-z0-9._-]+\.(ts|md)' "$skill_dir/SKILL.md" || true)
  if [[ "$found" -eq 0 ]]; then
    fail "$skill_name — extracted no file references, so this test proved nothing"
  elif [[ "$missing" -eq 0 ]]; then
    ok "$skill_name names $found file references, all present"
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

# Interview answers for score-maturity. Shaped to MATURITY_MODEL in lib/types.ts:
# five dimensions, four ordered criteria each. Measurement is all false, so the
# overall score (the weakest dimension) must be 0 — a fixed number to assert on.
cat > "$TMPDIR_BASE/answers.json" <<'JSON'
{
  "organisation": "Test Ltd",
  "dimensions": {
    "governance":  {"policy-documented": true, "owner-accountable": true,
                    "resourced-mandated": false, "executive-review-cycle": false},
    "capability":  {"style-guide-available": true, "training-delivered": false,
                    "competence-maintained": false, "roles-embedded": false},
    "process":     {"review-step-exists": true, "checks-in-workflow": true,
                    "signoff-gates": false, "all-document-types-covered": false},
    "measurement": {"corpus-baseline-taken": false, "regular-sampling": false,
                    "user-testing": false, "metrics-drive-decisions": false},
    "culture":     {"leadership-aware": true, "leadership-champions": false,
                    "feedback-loops": false, "improvement-cycles": false}
  }
}
JSON

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

section "iso-24495-4 gap-analysis CLIs"
EV="$TMPDIR_BASE/evidence.json"
FD="$TMPDIR_BASE/findings.json"
MT="$TMPDIR_BASE/maturity.json"
RP="$TMPDIR_BASE/gap-report.md"

assert_script_exit 0 "$S4/audit-evidence-cli.ts"  "audit-evidence sweeps a workspace" \
  "$ROOT" --json "$EV"
assert_script_exit 0 "$S4/audit-corpus-cli.ts"    "audit-corpus reads a corpus directory" \
  "$FIX" --json "$FD"
assert_script_exit 0 "$S4/score-maturity-cli.ts"  "score-maturity reads answers" \
  "$TMPDIR_BASE/answers.json" --json "$MT"
assert_script_exit 0 "$S4/generate-report-cli.ts" "generate-report chains all three" \
  "$FD" "$EV" "$MT" --state "$TMPDIR_BASE/state.json" --out "$RP"

# Scoring is deterministic, so the weakest dimension is a fixed number. If this
# drifts, the maturity model changed and references/maturity-model.md is stale.
if grep -qF 'Overall (weakest dimension): 0' <<<"$(node "$S4/score-maturity-cli.ts" "$TMPDIR_BASE/answers.json" 2>/dev/null)"; then
  ok "score-maturity is deterministic (weakest dimension: 0)"
else
  fail "score-maturity did not report the expected overall level"
fi

if [[ -s "$RP" ]] && grep -qF '# Plain Language Gap Analysis' "$RP"; then
  ok "generate-report writes a gap report"
else
  fail "generate-report did not write a usable report to $RP"
fi

section "iso-24495-4 argument errors (exit 2)"
for pair in "audit-evidence-cli.ts:audit-evidence" \
            "audit-corpus-cli.ts:audit-corpus" \
            "score-maturity-cli.ts:score-maturity" \
            "generate-report-cli.ts:generate-report"; do
  cli="${pair%%:*}"; label="${pair##*:}"
  assert_script_exit 2 "$S4/$cli" "$label with no arguments"
  # The usage text names the runtime the reader must actually type. It said
  # 'bun' upstream, which nobody here has installed.
  assert_script_stderr_has "Usage: node" "$S4/$cli" "$label usage names node"
done

section "SKILL.md references"
assert_skill_refs "$ROOT/skills/iso-24495-text-audit" "iso-24495-text-audit/SKILL.md"
assert_skill_refs "$ROOT/skills/iso-24495-4"          "iso-24495-4/SKILL.md"

section "runtime wiring"
# Each SKILL.md tells the agent which runtime to use. Both said 'bun' while the
# scripts were absent; this guards the pair staying consistent.
SKILL="$ROOT/skills/iso-24495-text-audit/SKILL.md"
if grep -qF 'node <skill-directory>/scripts/audit-text-cli.ts' "$SKILL"; then
  ok "text-audit SKILL.md invokes the CLI with node"
else
  fail "text-audit SKILL.md does not invoke the CLI with node"
fi
if grep -cE '`node scripts/.*-cli\.ts' "$ROOT/skills/iso-24495-4/SKILL.md" | grep -qx 4; then
  ok "iso-24495-4 SKILL.md invokes all four CLIs with node"
else
  fail "iso-24495-4 SKILL.md does not invoke all four CLIs with node"
fi
# lexicon.ts is a word list; "bun" is a legitimate entry in it.
STRAY=$(grep -rlniE '\bbun\b' "$ROOT/skills/" | grep -v 'lexicon.ts' || true)
if [[ -z "$STRAY" ]]; then
  ok "no skill file still mentions bun"
else
  fail "these still mention bun: $(tr '\n' ' ' <<<"$STRAY")"
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
