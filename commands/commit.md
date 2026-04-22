# /user:commit

Stage and commit the current changes with a well-formed message.

## What this command does

1. Run `git status` and `git diff --stat` to understand what has changed.
2. Draft a short imperative commit subject (≤72 chars).
3. Add a body paragraph only when the *why* is non-obvious from the diff.
4. Show the draft to the user for confirmation before committing.
5. Stage the relevant files and create the commit.

## Constraints (enforced automatically)

- No "Co-Authored-By" trailers.
- No AI footers ("Generated with Claude Code", emoji, etc.).
- No `--no-verify`; if a hook fails, fix the underlying issue instead.
- Prefer `git add <specific files>` over `git add -A`.

## Example output

```
fix: prevent divide-by-zero when count is zero

Guard added in compute_ratio() so callers never receive NaN.
```
