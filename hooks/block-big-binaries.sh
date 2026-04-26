#!/usr/bin/env bash
# Block staging large or binary result files (FEM artifacts, HDF5, pickles).
# Bash rather than Python so non-`git add` Bash calls bail in <10ms instead of
# paying Python startup just to early-return.
input=$(cat)

# Fast path: if the input doesn't even mention `git add` or `git commit -a`,
# we don't need to parse JSON or shell out to git. Avoids jq+git spawns on
# every unrelated Bash call.
case "$input" in
  *'"git add'*|*'"git commit -a'*) ;;
  *) exit 0 ;;
esac

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
case "$cmd" in
  "git add"*|"git commit -a"*) ;;
  *) exit 0 ;;
esac

MAX_BYTES=$((50 * 1024 * 1024))
BIG_EXT_RE='\.(rst|db|cdb|odb|rth|rmg|msh|vtu|vtk|h5|hdf5|npz|pkl)$'

offenders=""
while IFS= read -r line; do
  [[ -z "${line// }" ]] && continue
  path="${line:3}"
  path="${path%\"}"; path="${path#\"}"
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
done < <(git status --porcelain 2>/dev/null)

if [[ -n "$offenders" ]]; then
  reason="Large or binary result files must not be committed directly:
${offenders}
Use Git LFS or DVC; or commit a manifest/hash instead."
  jq -cn --arg reason "$reason" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$reason}}'
fi
exit 0
