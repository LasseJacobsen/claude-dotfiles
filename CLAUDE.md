## Commits

- One short imperative subject line, ≤72 chars.
- No merge commits; rebase onto the target branch instead.

## Naming

- Python: `snake_case` for functions/variables, `PascalCase` for classes.
- Prefer explicit over implicit: name arrays by what they contain (`node_ids`, not `data`).

## Numerical code

- Carry physical units in variable names when ambiguous (`force_N`, `temp_K`).
- Array shapes: document as comments only when the shape is non-obvious or changes across a call chain.
