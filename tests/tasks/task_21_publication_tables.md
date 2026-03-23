# Task 21: Publication-Ready Tables and Data Pipeline

## Task Prompt

I'm writing a paper and my advisor wants a specific set of tables. Using `webuse nlswork`:

**Table 1: Summary statistics** with means, SDs, min, max, and N for `ln_wage`, `age`, `tenure`, `hours`, `ttl_exp`, `collgrad`, `race`, `union`. I want it exported to a Word doc using `putdocx` and also to LaTeX. Split the table by `union` status so there are three columns: All, Union, Non-Union, plus a column for the difference (with a t-test p-value).

**Table 2: Balance table** — compare means of all covariates between `collgrad` groups (college vs non-college). Show the difference, t-statistic, and p-value for each variable. This is like the "Table 1" in every applied micro paper.

**Table 3: Regression table** — three specifications of `ln_wage`:
1. Just `collgrad` and `race`
2. Add `age`, `c.age#c.age`, `tenure`, `hours`
3. Add `union` and `i.ind_code` (industry FE)

All with clustered SEs at the individual level. Export with `esttab` to LaTeX with proper formatting: stars at 10/5/1%, SEs in parentheses, an observation count row, R² row, and a "Controls" / "Industry FE" indicator row at the bottom.

Also: before running regressions, the data has some extreme `hours` values. Winsorize `hours` at the 1st and 99th percentile using `winsor2`. And use `gtools`' `gegen` to create group means (mean wage by industry) faster than `egen`.

## Capabilities Exercised

- Tables/reporting: `putdocx`, `putexcel`, LaTeX output
- Packages: `estout`/`esttab` for regression tables, `winsor2` for winsorizing, `gtools`/`gegen` for fast group operations
- Gotcha: `putdocx` requires `putdocx begin`/`save` wrapper
- Descriptive stats: `tabstat`, balance tables, t-tests
- Data manipulation: winsorizing, fast egen alternatives
- Linear regression: multiple specs, clustered SEs, storing estimates

## Reference Files

- references/tables-reporting.md
- packages/estout.md
- packages/winsor.md
- packages/data-manipulation.md
- references/descriptive-statistics.md
- references/linear-regression.md
