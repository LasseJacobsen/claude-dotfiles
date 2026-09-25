#!/usr/bin/env bash
# Skill tests: every file a SKILL.md names exists, the invocation settings hold,
# and the vendored book-to-skill extractor runs. Run from the dotfiles root:
#   bash tests/test_skills.sh
# Requirements: bash, python >= 3.9 (book-to-skill). Without python the
# extractor section SKIPs; the rest runs.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1  # the extractor run must not leave __pycache__ in the repo

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
# book-to-skill's extractor is stdlib Python >= 3.9. `python` is tried before
# `python3` because on Windows `python3` may be the Store stub, which exits
# non-zero without running anything; the version probe filters that out.
HAS_PYTHON=false
PYTHON_WHY="python >= 3.9 not in PATH"
PY=""
for candidate in python python3; do
  if command -v "$candidate" >/dev/null 2>&1 \
     && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 9))' >/dev/null 2>&1; then
    PY="$candidate"; HAS_PYTHON=true; break
  fi
done

# ── assertion helpers ─────────────────────────────────────────────────────────

# Every scripts/, references/, assets/ or tools/ path a SKILL.md names must
# exist. Vendored skills have shipped pointing at files the copy never brought
# over, and nothing caught it until someone invoked the skill.
#
# No `sort -u` here on purpose: sort.exe is EDR-blocked on some corporate
# machines (see README → "When uv is blocked"), and a failed pipeline would
# yield zero references, so every skill would pass vacuously. `found` makes
# that failure mode loud rather than green.
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
  done < <(grep -oE '(scripts|references|assets|tools)/[A-Za-z0-9._-]+\.(ts|md|py)' "$skill_dir/SKILL.md" || true)
  if [[ "$found" -eq 0 ]]; then
    fail "$skill_name — extracted no file references, so this test proved nothing"
  elif [[ "$missing" -eq 0 ]]; then
    ok "$skill_name names $found file references, all present"
  fi
}

# True when the SKILL.md frontmatter (between the first two '---' lines) has $2.
frontmatter_has() {
  awk 'NR==1 && $0=="---" {inside=1; next} inside && $0=="---" {exit} inside' "$1" \
    | grep -qxF "$2"
}

# ── tests ─────────────────────────────────────────────────────────────────────
BTS="$ROOT/skills/book-to-skill"

section "SKILL.md references"
assert_skill_refs "$ROOT/skills/domain-modeling"             "domain-modeling/SKILL.md"
assert_skill_refs "$ROOT/.claude/skills/writing-for-agents"  "writing-for-agents/SKILL.md"
assert_skill_refs "$BTS"                                      "book-to-skill/SKILL.md"

section "invocation"
# book-to-skill's description is long; keeping it out of the model's skill list
# is the point of this flag, so a re-vendor that drops it should fail here.
if frontmatter_has "$BTS/SKILL.md" "disable-model-invocation: true"; then
  ok "book-to-skill loads only on /book-to-skill"
else
  fail "book-to-skill frontmatter lacks disable-model-invocation: true"
fi
# grill-with-docs calls two skills by name; both must resolve. grilling is the
# built-in anthropic-skills one, domain-modeling ships here.
GWD="$ROOT/skills/grill-with-docs/SKILL.md"
if grep -qF '"anthropic-skills:grilling"' "$GWD" && [[ -f "$ROOT/skills/domain-modeling/SKILL.md" ]]; then
  ok "grill-with-docs calls anthropic-skills:grilling and a shipped domain-modeling"
else
  fail "grill-with-docs names a skill that does not resolve"
fi

section "book-to-skill extractor"
if ! $HAS_PYTHON; then
  skip "$PYTHON_WHY — the extractor needs it"
else
  if "$PY" "$BTS/scripts/extract.py" --check >/dev/null 2>&1; then
    ok "extract.py --check exits 0"
  else
    fail "extract.py --check did not exit 0"
  fi

  # --install-missing no keeps the run offline; BOOK_SKILL_WORKDIR pins the
  # output so the test need not parse the "Workdir ->" line from stdout.
  FIXTURE="$TMPDIR_BASE/clean.md"
  printf '# Title\n\nThe cat sat on the mat. The dog ran home.\n' > "$FIXTURE"
  BTS_WORK="$TMPDIR_BASE/bts-work"
  if BOOK_SKILL_WORKDIR="$BTS_WORK" "$PY" "$BTS/scripts/extract.py" "$FIXTURE" \
       --mode text --install-missing no >/dev/null 2>&1 \
     && [[ -s "$BTS_WORK/full_text.txt" && -s "$BTS_WORK/metadata.json" ]] \
     && grep -qF '"sources"' "$BTS_WORK/metadata.json"; then
    ok "extract.py writes full_text.txt and metadata.json for a markdown fixture"
  else
    fail "extract.py did not produce full_text.txt + metadata.json in $BTS_WORK"
  fi

  # Step 9.5 runs this scanner on every generated skill; a benign one must pass.
  GEN="$TMPDIR_BASE/gen-skill"
  mkdir -p "$GEN/chapters"
  printf -- '---\nname: test-book\ndescription: A test skill.\n---\n\n# Test Book\n\nOne framework, plainly stated.\n' > "$GEN/SKILL.md"
  printf '# Chapter 1\n\nA short summary.\n' > "$GEN/chapters/ch01-intro.md"
  if "$PY" "$BTS/tools/scan_generated_skill.py" "$GEN" >/dev/null 2>&1; then
    ok "scan_generated_skill.py passes a benign generated skill"
  else
    fail "scan_generated_skill.py flagged or crashed on a benign generated skill"
  fi
fi

# ── summary ──────────────────────────────────────────────────────────────────
printf "\n%s\n" "$(printf '─%.0s' {1..50})"
printf "Results: ${G}%d passed${N}, ${R}%d failed${N}, ${Y}%d skipped${N}\n" \
  "$PASS" "$FAIL" "$SKIP"

if ! $HAS_PYTHON; then
  printf "\n${Y}Note:${N} install Python 3.9 or newer to run the book-to-skill tests.\n"
fi

[[ "$FAIL" -eq 0 ]]
