#!/usr/bin/env bash
set -uo pipefail
# SessionStart: print branch, working-tree state, and recent commits to stdout.
# Stdout from SessionStart hooks is injected into Claude's context as system info,
# so this replaces 'remember to run git status before you start' prose rules.
#
# LC_ALL=C: stable English output regardless of the user's locale (the strings
# below get matched against by other tooling). GIT_OPTIONAL_LOCKS=0: don't take
# the index.lock for read-only commands so a concurrent `git add` from the user
# isn't disturbed by session start.
export LC_ALL=C
export GIT_OPTIONAL_LOCKS=0

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
