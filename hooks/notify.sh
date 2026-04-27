#!/usr/bin/env bash
set -uo pipefail
# Notification bridge: surfaces 'Claude needs input' as a desktop notification.
# Always exits 0 — a missing notifier should never block Claude.
#
# Title/message are passed via env vars (PowerShell) and argv (osascript) rather
# than being interpolated into a quoted command, so apostrophes and quotes in
# the message survive intact (e.g. "Don't forget").
input=$(cat)
title=$(echo "$input"  | jq -r '.title   // "Claude Code"' 2>/dev/null)
message=$(echo "$input" | jq -r '.message // "Claude needs input"' 2>/dev/null)

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    # powershell.exe isn't guaranteed to be on PATH (stripped-down Git Bash,
    # custom shells). Probe before invoking; fall through silently otherwise.
    if command -v powershell.exe >/dev/null 2>&1; then
      CC_TITLE="$title" CC_MSG="$message" powershell.exe -NoProfile -Command '
        if (Get-Module -ListAvailable -Name BurntToast) {
          Import-Module BurntToast
          New-BurntToastNotification -Text $env:CC_TITLE,$env:CC_MSG
        }
      ' >/dev/null 2>&1 || true
    fi
    ;;
  Darwin)
    osascript \
      -e 'on run argv
            display notification (item 1 of argv) with title (item 2 of argv)
          end run' \
      -- "$message" "$title" >/dev/null 2>&1 || true
    ;;
  *)
    command -v notify-send >/dev/null 2>&1 && \
      notify-send -- "$title" "$message" >/dev/null 2>&1 || true
    ;;
esac
exit 0
