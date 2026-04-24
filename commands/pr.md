# /user:pr

Generate and open a pull request for the current branch.

## Steps

1. Identify the base branch (`main` unless the repo uses another default; ask if ambiguous).
2. Run:
   - `git log <base>...HEAD --oneline` — see the commit history
   - `git diff <base>...HEAD --stat` — summarise what changed
3. Draft a PR title (≤70 chars, imperative) and body using the format below.
4. Show the draft to the user for confirmation.
5. Run `gh pr create --title "..." --body "..."` to open the PR.
   If `gh` is not installed or the branch isn't pushed, output the title and body for the user.

## Output format

```markdown
## Summary
<2–4 bullets: what changed and why>

## Changes
<bulleted file/module breakdown from --stat>

## Test plan
<concrete steps a reviewer can follow to verify>
```

## Constraints

- Do not `git push` the branch unless the user asks.
- Do not add "Generated with Claude Code" footers or emoji.
- Derive everything from the diff and log — no speculation.
