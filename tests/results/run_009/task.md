# Task 09: Survey Data Analysis

## Task Prompt

Using `webuse nhanes2`:
1. Set up the survey design with appropriate weight, strata, and PSU variables
2. Compute survey-weighted means of `height`, `weight`, and `bpsystol` with proper standard errors
3. Run a survey-weighted regression of `bpsystol` on `age`, `height`, `weight`, `i.sex`, and `i.race`
4. For a subpopulation analysis, estimate the same model for females only — use `subpop()`, not `if`
5. Explain why you must use `subpop()` instead of `if` for survey data

## Capabilities Exercised

- **Survey data:** `svyset`, `svy: mean`, `svy: regress`, `subpop()`
- **Gotcha: Weights not interchangeable** — must use `pweight` for survey data
- **Factor variables:** `i.sex`, `i.race`
- **Command selection:** `subpop()` vs `if` for correct variance estimation

## Reference Files

- references/survey-data-analysis.md
- references/linear-regression.md
- references/descriptive-statistics.md
