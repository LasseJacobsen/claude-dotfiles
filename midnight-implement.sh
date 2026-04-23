#!/bin/bash
# Sleeps until midnight then runs claude -p to implement the five
# remaining hooks/skills/commands identified in research.md.
set -euo pipefail

REPO=/home/user/claude-dotfiles
LOG=$REPO/midnight-run.log
BRANCH=claude/schedule-hooks-skills-4IN7P

MIDNIGHT=$(date -d 'tomorrow 00:00:00' +%s)
NOW=$(date +%s)
SLEEP_SECS=$(( MIDNIGHT - NOW ))

echo "[$(date -Iseconds)] Midnight run scheduled: sleeping ${SLEEP_SECS}s" | tee "$LOG"
sleep "$SLEEP_SECS"
echo "[$(date -Iseconds)] Starting implementation" | tee -a "$LOG"

cd "$REPO"
git checkout "$BRANCH" 2>&1 | tee -a "$LOG"

claude --dangerously-skip-permissions -p "$(cat <<'PROMPT'
Implement the five remaining hooks, commands, and skills from research.md that are not yet in this repo. Work in /home/user/claude-dotfiles on branch claude/schedule-hooks-skills-4IN7P. Read research.md for background. Make a separate git commit for each item, then push.

─────────────────────────────────────────────────────────────
Item 1 — SessionStart context-injection hook
File: hooks/session-start.sh
Trigger: SessionStart (register in settings.json hooks.SessionStart)

On every new session, emit a compact context block to stdout so
Claude sees the project state without being asked:
  • git status --short (skip if not a git repo)
  • cat NEXT.md if it exists in cwd
  • pytest --tb=no -q --co 2>/dev/null | tail -5  (test inventory)
Keep total output ≤ 40 lines. Always exit 0.

─────────────────────────────────────────────────────────────
Item 2 — PreCompact transcript-backup hook
File: hooks/precompact-backup.sh
Trigger: PreCompact (register in settings.json hooks.PreCompact)

Before context compaction, append the full transcript JSON to
  ~/.claude/backups/transcript-$(date +%Y%m%dT%H%M%S).jsonl
Create the directory if absent. Keep only the last 20 backup
files (delete oldest beyond that). Always exit 0.
The hook receives the transcript via STDIN as JSON; write it as-is.

─────────────────────────────────────────────────────────────
Item 3 — pytest last-failed hook
File: hooks/pytest-lf.sh
Trigger: PostToolUse Write|Edit|MultiEdit on *.py files
(register in settings.json hooks.PostToolUse — append after
existing PostToolUse hooks, matcher "Write|Edit|MultiEdit")

After any Python file is written/edited, run:
  pytest --lf --tb=short -q 2>&1 | tail -20
Skip silently (exit 0) if:
  • no pytest found on PATH
  • no .pytest_cache/v/cache/lastfailed present (nothing has run yet)
  • the edited file is not under the repo root
On test failures exit 2 with the tail output so Claude sees
them. On pass or skip exit 0.

─────────────────────────────────────────────────────────────
Item 4 — /regen-regressions command
File: commands/regen-regressions.md

Slash command that guides Claude to regenerate pytest-regressions
snapshots safely. Steps the command should instruct Claude to do:
  1. Run: pytest --snapshot-update -x -q 2>&1 | tee /tmp/regen.log
  2. Show the user a git diff of changed snapshot files
  3. For each changed .txt/.yml snapshot, summarise the numerical
     delta (max/mean absolute change) so the user can judge if the
     physics changed acceptably
  4. Ask the user to confirm before committing
  5. Commit only the snapshot files with message:
       "update regression snapshots: <one-line reason>"
Trigger phrase (frontmatter): user types /regen-regressions

─────────────────────────────────────────────────────────────
Item 5 — /run-params skill
File: skills/run-params/SKILL.md

Skill that runs a Jupyter notebook with papermill parameters.
Trigger: user says something like "run <notebook> with <params>",
         "execute notebook with parameters", "papermill run"

Steps the skill should instruct Claude to do:
  1. Confirm the target .ipynb path and collect key=value pairs
  2. Build the papermill command:
       papermill <input.ipynb> <output.ipynb> -p key val …
     where output path is input stem + timestamp + .ipynb
  3. Run it; stream stdout/stderr
  4. On success, report the output notebook path and offer to
     open it or strip outputs with nbstripout
  5. On failure, show the cell traceback and suggest a fix

─────────────────────────────────────────────────────────────
After all five items are committed, push:
  git push -u origin claude/schedule-hooks-skills-4IN7P

Commit message style: one short imperative line ≤72 chars,
no co-author trailers, no AI footers.
PROMPT
)" 2>&1 | tee -a "$LOG"

echo "[$(date -Iseconds)] Implementation run complete" | tee -a "$LOG"
