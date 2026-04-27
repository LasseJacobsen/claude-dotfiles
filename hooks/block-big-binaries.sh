#!/usr/bin/env bash
set -uo pipefail
# Block staging large or binary result files (FEM artifacts, HDF5, pickles).
# Bash rather than Python so non-`git add` Bash calls bail in <10ms instead of
# paying Python startup just to early-return.
input=$(cat)

# Fast path: if the input doesn't even mention git add / commit -a / -C,
# we don't need to parse JSON or shell out to git. Avoids jq+git spawns on
# every unrelated Bash call. `git -C <path> add ...` is also valid, so let
# any `"git -C` through the fast path; the slow path verifies it's actually
# an add/commit -a operation.
case "$input" in
  *'"git add'*|*'"git commit -a'*|*'"git -C'*) ;;
  *) exit 0 ;;
esac

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
# Recognise `git add`, `git commit -a`, and `git -C <path> (add|commit -a)`.
if ! [[ "$cmd" =~ ^git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(add|commit[[:space:]]+-a)([[:space:]]|$) ]]; then
  exit 0
fi

MAX_BYTES=$((50 * 1024 * 1024))
BIG_EXT_RE='\.(rst|db|cdb|odb|rth|rmg|msh|vtu|vtk|h5|hdf5|npz|pkl)$'

# --porcelain=v1 -z: NUL-delimited records, no quoting/octal-escaping. Avoids
# the default core.quotePath=true mangling non-ASCII paths into "\303\244"
# escapes that we'd then fail to stat. Each record is "XY <path>"; rename/copy
# entries add a second NUL-delimited source path which we tolerate (it'll
# either be a real file or skipped by the [[ -f ]] guard).
offenders=""
while IFS= read -r -d '' entry; do
  [[ -z "${entry// }" ]] && continue
  path="${entry:3}"
  [[ -f "$path" ]] || continue
  # GNU coreutils first (Linux + Git Bash); BSD stat second (macOS).
  size=$(stat -c '%s' "$path" 2>/dev/null || stat -f '%z' "$path" 2>/dev/null || echo 0)
  big_ext=false
  shopt -s nocasematch
  [[ "$path" =~ $BIG_EXT_RE ]] && big_ext=true
  shopt -u nocasematch
  if $big_ext || [[ $size -gt $MAX_BYTES ]]; then
    mb=$(awk -v s="$size" 'BEGIN{printf "%.1f", s/1024/1024}')
    offenders+="  $path (${mb} MB)
"
  fi
done < <(git status --porcelain=v1 -z 2>/dev/null)

if [[ -n "$offenders" ]]; then
  reason="Large or binary result files must not be committed directly:
${offenders}
Use Git LFS or DVC; or commit a manifest/hash instead."
  jq -cn --arg reason "$reason" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$reason}}'
fi
exit 0
