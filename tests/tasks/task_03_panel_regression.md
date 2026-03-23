# Task 03: Wage Equation with Multi-Way Fixed Effects

## Task Prompt

Using `webuse nlswork`, I want to estimate a wage equation and I need your help choosing the right specification. My outcome is `ln_wage` and my key predictors are `tenure`, `hours`, and `age` (include `age` squared too).

Here's what I need:
- First, show me the panel structure — how unbalanced is it? What's the within vs between variation in wages?
- Run a basic pooled OLS, a fixed-effects model (individual FE), and then a model with both individual and year fixed effects using `reghdfe`
- Cluster standard errors at the individual level in all specs
- I've heard you should run a Hausman test between FE and RE — do that, but also tell me if you think it's actually informative here or just a formality
- Store all three specifications and show me a comparison table with `esttab`
- Test whether the tenure effect differs for workers with more than 12 years of education (`collgrad`) using an interaction

## Capabilities Exercised

- Panel data: `xtset`, `xtreg fe`, `xtsum`, `xtdescribe`
- Packages: `reghdfe` for multi-way FE, `estout`/`esttab` for tables
- Gotcha: stored results — `e()` overwritten by each estimation, must `estimates store`
- Factor variables: `c.tenure##i.collgrad` interaction
- Linear regression: `vce(cluster)`, `test`, Hausman
- Diagnostics: interpreting within/between variation

## Reference Files

- references/panel-data.md
- references/linear-regression.md
- references/descriptive-statistics.md
- packages/reghdfe.md
- packages/estout.md
