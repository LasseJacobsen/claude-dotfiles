#!/usr/bin/env bash
# Redirect pip/poetry/conda/bare-pytest to their uv equivalents.
# Bash rather than Python so we don't pay Python startup on every Bash call —
# this hook fires on the PreToolUse Bash hot path. A cheap substring pre-filter
# also lets us skip jq+grep entirely for ~all commands that don't even mention
# the deprecated tools.
input=$(cat)

# Fast path: if none of the deprecated tool names appear anywhere in the input,
# the regex below cannot match. Avoids ~1 jq + 1 grep spawn on every Bash call.
case "$input" in
  *pip*|*poetry*|*conda*|*pytest*|*ruff*) ;;
  *) exit 0 ;;
esac

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

# One combined alternation = one grep spawn (vs. one per pattern). The stage
# anchor keeps matches scoped to the start of a pipeline segment so that text
# like 'pip install' inside an argument string (e.g. gh pr create --body
# "...pip install...") does not trigger.
STAGE='(^|&&|\|\||;)[[:space:]]*'
END='([^a-zA-Z0-9_]|$)'
ALT='pip[3]?[[:space:]]+install|pip[3]?[[:space:]]+uninstall|poetry[[:space:]]+add|poetry[[:space:]]+install|conda[[:space:]]+install|python[[:space:]]+-m[[:space:]]+pytest|python[[:space:]]+-m[[:space:]]+ruff|pytest'

match=$(echo "$cmd" | grep -oE "${STAGE}(${ALT})${END}" | head -1)
[[ -z "$match" ]] && exit 0

# Map the matched pattern back to a suggested replacement.
case "$match" in
  *pip*install*)     fix='uv add' ;;
  *pip*uninstall*)   fix='uv remove' ;;
  *poetry*add*)      fix='uv add' ;;
  *poetry*install*)  fix='uv sync' ;;
  *conda*install*)   fix='uv add' ;;
  *python*pytest*)   fix='uv run pytest' ;;
  *python*ruff*)     fix='uv run ruff' ;;
  *pytest*)          fix='uv run pytest' ;;
  *)                 fix='the uv equivalent' ;;
esac

jq -cn --arg fix "$fix" --arg matched "$match" \
  '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":("Blocked: \($matched | ascii_downcase | rtrimstr(" ")) — use \"\($fix)\" instead.")}}'
exit 0
