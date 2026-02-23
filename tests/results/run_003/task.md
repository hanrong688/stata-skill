# Task 03: Panel Data Regression

## Task Prompt

Using `webuse nlswork`, set up a panel data analysis:
1. Declare the panel structure with `xtset`
2. Summarize the panel — how balanced is it? What's the within vs between variation in `ln_wage`?
3. Run a fixed effects regression of `ln_wage` on `age`, `tenure`, `hours`, and `not_smsa`
4. Run a random effects regression with the same specification
5. Perform a Hausman test to choose between FE and RE
6. Cluster standard errors at the individual level in the preferred specification
7. Store the results

## Capabilities Exercised

- **Panel data:** `xtset`, `xtreg fe`, `xtreg re`, `xtdescribe`, `xtsum`
- **Linear regression:** `vce(cluster)`, `estimates store`
- **Gotcha: Stored results** — `e()` overwritten by each estimation, must store
- **Diagnostics:** Hausman test

## Reference Files

- references/panel-data.md
- references/linear-regression.md
- references/descriptive-statistics.md
