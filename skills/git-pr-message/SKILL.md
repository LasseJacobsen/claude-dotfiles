# Skill: git-pr-message

Generate a clean markdown PR description from the commits on the current branch.

## Trigger

Use this skill when the user asks to generate, write, or draft a PR description,
pull request message, or PR body.

## Steps

1. Identify the base branch (default `main`; ask if ambiguous).
2. Run:
   ```
   git log <base>...HEAD --oneline
   git diff <base>...HEAD --stat
   ```
3. Produce a PR title and a markdown PR description with the sections below.
   Keep it factual — derive everything from the diff and log.
   Do **not** add AI footers or "Generated with" lines.

## Output format

Always start with a title line (≤70 chars, imperative), then the body:

```markdown
# <PR title>

## Summary
<2–4 bullet points covering what changed and why>

## Changes
<bulleted file/module breakdown drawn from `--stat` output>

## Test plan
<concrete steps a reviewer can follow to verify correctness>
```

## Rules

- Use plain imperative language ("Add", "Fix", "Remove" — not "This PR adds…").
- The title is mandatory — never emit a body without one.
- Omit sections that are genuinely not applicable rather than leaving them blank.
- If the diff is large, summarise by module rather than listing every file.
