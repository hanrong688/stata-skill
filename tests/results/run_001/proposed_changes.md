# Proposed Changes

## Summary
The agent scored 52/55 with no errors. The only repeated deduction (Command Selection 4/5, Idiomaticness 4/5) was for using `_pctile` + manual gen/replace instead of `xtile` for tercile creation. One small change addresses both deductions.

## Change 1: Add `xtile` to data-management routing table entry and Data Cleaning Pipeline pattern
- File: `SKILL.md`
- Action: Modify
- Priority: Low
- Justification: Both 4/5 scores (Command Selection and Idiomaticness) cite the same gap — the agent used a 5-line `_pctile` chain instead of `xtile price_category = price, nq(3)`. Adding `xtile` to the routing table ensures it's visible during task routing, and adding it to the common pattern provides a concrete example.
- Details:

In the routing table, add `xtile` to the data-management row:

```
| `references/data-management.md` | `generate`, `replace`, `merge`, `append`, `reshape`, `collapse`, `recode`, `egen`, `encode`/`decode`, `xtile` |
```

In the Data Cleaning Pipeline common pattern, add a tercile/quantile line after the `replace income` line:

```stata
* Categorize into quantile groups
xtile income_q = income, nq(4)      // quartile groups (1-4) in one step
```

## Change 2: Ensure `xtile` is documented in data-management.md reference
- File: `references/data-management.md`
- Action: Modify (verify and add if missing)
- Priority: Low
- Justification: Same judge finding — if `xtile` isn't covered in the reference file, the agent won't know to prefer it over `_pctile` + manual categorization.
- Details: Add a brief section (if not already present):

```stata
** Quantile groups — xtile **
* Create quantile-based categories in one step
xtile price_q3 = price, nq(3)       // terciles: 1, 2, 3
xtile income_q5 = income, nq(5)     // quintiles: 1, 2, 3, 4, 5

* Custom cutpoints
xtile age_grp = age, cutpoints(cutvar)

* Note: xtile handles missing values correctly (codes them as .)
* Prefer xtile over _pctile + manual gen/replace for creating quantile groups
```

## No Further Changes Needed
All other scores were 5/5. The missing-value handling, labeling workflow, `compress`/`save` pattern, and gotcha awareness were all excellent, reflecting strong coverage in SKILL.md's Critical Gotchas section and the existing reference files.
