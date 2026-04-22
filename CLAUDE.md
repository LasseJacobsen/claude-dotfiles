# Claude Code — Global Conventions

## Commit messages

- One short imperative line, ≤72 characters.
- No "Co-Authored-By" trailers.
- No AI-generated footers ("Generated with Claude Code", "🤖", etc.).
- Body is optional; use it only for non-obvious context (the *why*, not the *what*).

## Code style

- Python files are formatted with `black` automatically via the PostToolUse hook.
- No unnecessary comments; code should be self-explanatory.

## General behaviour

- Prefer editing existing files over creating new ones.
- Do not add features beyond what is asked.
- Ask before any destructive or hard-to-reverse action.
