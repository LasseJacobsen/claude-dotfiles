---
name: pyspark-style
description: "PySpark DataFrame style rules adapted from the Palantir PySpark style guide. Applied when writing or restructuring PySpark code (pyspark.sql, DataFrame transforms), not when explaining it and not for plain Python, pandas, or Polars."
metadata:
  source: "palantir/pyspark-style-guide"
  source-license: "MIT, Copyright (c) 2020 Palantir Technologies, Inc."
---

# PySpark style

PySpark transforms are read far more often than they are written, and a subtle style mistake
(an implicit join type, a missing window frame) changes results silently rather than failing.
These rules make each transform state its intent explicitly.

**Scope**. This skill governs how PySpark DataFrame code is written: column references, schema
contracts, joins, windows, and chaining. It does not govern formatting (the `ruff-after-edit`
hook owns line layout), performance tuning, cluster configuration, or non-Spark Python.
General naming rules come from CLAUDE.md and `iso-24495-code`; this skill adds only what is
Spark-specific.

**Adapted from the [Palantir PySpark style guide](https://github.com/palantir/pyspark-style-guide)
(MIT). The rules are its recommendations, not a Palantir endorsement of this project.**

## Rules

### 1. Import functions as `F`

**Use `from pyspark.sql import functions as F`** and refer to every function through that alias.
One consistent alias makes Spark calls recognisable at a glance in any file.

### 2. Refer to columns by name, not by dataframe attribute

**Write `F.col('col_a')` or a plain string, never `df.col_a` or `df['col_a']`.**
Attribute access ties the expression to one dataframe variable, breaks on renamed or
special-character columns, and blocks reuse of the expression across frames.

```
Bad:   df.select(F.lower(df.col_a))
Good:  df.select(F.lower('col_a'))
```

The exception is disambiguation after a join, where a frame alias plus `F.col('alias.col_a')`
does the job (rule 7).

### 3. Name complex logic before using it

**Keep any single logical expression to about three operations.** Past that, extract named
boolean variables and combine those. The name documents the business rule; the expression no
longer needs decoding.

```
Bad:   df.filter((F.col('status') == 'Delivered') & F.col('date').isNotNull()
                 & (F.col('qty') > 0) & (F.col('region') != 'EU'))
Good:  is_delivered = (F.col('status') == 'Delivered') & F.col('date').isNotNull()
       is_open_non_eu = (F.col('qty') > 0) & (F.col('region') != 'EU')
       df.filter(is_delivered & is_open_non_eu)
```

### 4. Use `select` as the schema contract

**Open or close a transform with a `select()` that lists its columns.** The select is the
readable contract of what the transform consumes or produces. Keep it simple: at most one
function per column plus an `.alias()`, and move conditional logic (`F.when`) out of it.

### 5. Empty means `F.lit(None)`

**Use `F.lit(None)` for an empty value, never `''` or `'NA'`.** Only a real null keeps
`isNull()` checks and null-handling utilities correct downstream.

### 6. Avoid UDFs

**Prefer native `pyspark.sql` functions over a UDF**; a Python UDF serialises every row through
the Python interpreter and is drastically slower. Where a UDF is genuinely unavoidable, add a
comment saying why no native equivalent works.

### 7. Make joins explicit

- **Always pass `how=` explicitly**, even for the default inner join.
- **Prefer `left` over `right`**: swap the frame order instead, so joins read one way
  throughout a codebase.
- **Disambiguate with frame aliases**, not bulk column renames:
  `flights.alias('f').join(aircraft.alias('a'), on='id', how='left')` then
  `F.col('f.start_time')`.
- **Check key uniqueness before joining.** Duplicate keys multiply rows silently; a join
  explosion is a data bug, not a style choice.

### 8. Make window frames explicit

- **Always give a window an explicit frame** with `rowsBetween()` or `rangeBetween()`.
  Spark's implicit default frame differs by function and has produced wrong-answer bugs.
- **Pass `ignorenulls=True`** to `F.first()` / `F.last()` when nulls may be present.
- **Order nulls deliberately** with `F.asc_nulls_first()` / `F.asc_nulls_last()`.
- **Avoid an empty `partitionBy()`**: it forces all data through a single partition.

### 9. Keep chains short

**Chain at most about five method calls**, grouped by what they do (filter block, derive block,
select block). Extract a longer chain into named functions whose names describe the step.
Wrap a multi-line chain in parentheses; never use backslash continuation.

### 10. Keep the transform honest

- **No `.otherwise()` as a blind catch-all** — an unexpected value should surface, not be
  absorbed into a default.
- **Name magic literals**: thresholds, codes, and category strings become constants.
- **Delete commented-out code**; comments explain why, not how (see `iso-24495-code`).

## What this skill does not do

- It does not restyle line layout or quoting — ruff runs on every `.py` edit and wins.
- It does not judge performance beyond the UDF and window rules; no partition or caching advice.
- It does not apply to pandas, Polars, or plain-Python code in the same file.
- It does not review existing files on its own — invoke `/pyspark-audit` for that.

## Applying it to existing code

Apply these rules to lines you are already changing. Do not restyle a whole file in a pass
that also changes behaviour; a style migration is its own diff.
