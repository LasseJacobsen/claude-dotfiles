---
name: pyspark-audit
description: Audit user-selected Python files against the pyspark-style rules and report findings. Use only when the user explicitly invokes this skill.
disable-model-invocation: true
argument-hint: "[file-or-directory]"
---

# PySpark style audit

Audit only the path the user selects, against the numbered rules in the sibling `pyspark-style`
skill. The checks are model-judged readings of the code, not a deterministic linter.

## Workflow

1. Read the path from `$ARGUMENTS`. Ask for a path when none was supplied.
2. State the selected file or directory before reading anything.
3. Treat an explicitly supplied directory as approval to read it. Ask before expanding the
   audit beyond the supplied path.
4. Collect `.py` files that import `pyspark`. Report every other file as out of scope.
5. Read each file in full and check it against every numbered rule in
   `pyspark-style/SKILL.md`.
6. Report every finding with its **file, line, rule number, the offending snippet, and its
   effect** (what can go wrong, e.g. "join without `how=` defaults to inner and silently
   drops unmatched rows"). A count or a verdict is not a finding.
7. Report skipped or unreadable files. Never present an incomplete audit as clean.
8. Do not describe zero findings as proof the code is correct, performant, or
   guide-conformant.
9. Leave the decision to fix, and any fixing itself, to the user.

## Boundaries

- Read `.py` files only; skip notebooks and report them as skipped.
- Do not follow a symbolic link or directory junction; report each one as skipped.
- Do not alter any file unless the user separately requests changes.
- Do not create a report file unless the user requests one and names its location.
- Do not report ruff-owned formatting (line length, quoting, wrapping) as findings.
- Findings are proxies for the Palantir guide's recommendations, not a correctness or
  performance judgement.
