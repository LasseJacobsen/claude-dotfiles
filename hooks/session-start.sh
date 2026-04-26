#!/usr/bin/env bash
# SessionStart: print branch, working-tree state, and recent commits to stdout.
# Stdout from SessionStart hooks is injected into Claude's context as system info,
# so this replaces 'remember to run git status before you start' prose rules.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

branch=$(git branch --show-current 2>/dev/null)
status=$(git status --short 2>/dev/null | head -n 20)
recent=$(git log --oneline -n 5 2>/dev/null)

echo "## Project context"
[[ -n "$branch" ]] && echo "Branch: $branch"
if [[ -n "$status" ]]; then
  printf '\nWorking tree:\n%s\n' "$status"
fi
if [[ -n "$recent" ]]; then
  printf '\nRecent commits:\n%s\n' "$recent"
fi
exit 0
