# Task 09: Complex Survey Analysis

## Task Prompt

Using `webuse nhanes2`, set up and analyze this survey data properly.

First, figure out the survey design — I know it has sampling weights, strata, and PSUs but I can never remember which variables are which. Set up `svyset` correctly.

Then:
- Compute survey-weighted means of `height`, `weight`, and `bpsystol` with 95% CIs
- Compare survey-weighted vs unweighted means for `bpsystol` — how different are they and why does it matter?
- Run a survey-weighted regression of `bpsystol` on `age`, `c.age#c.age`, `height`, `weight`, `i.sex`, `i.race`, and `i.diabetes`
- I need the same model but just for people aged 40+. I know I'm not supposed to use `if` for subgroup analysis with survey data — do it the right way with `subpop()` and explain why `if` gives wrong standard errors
- Test whether the race coefficients are jointly significant
- Compute predictive margins for `bpsystol` by race, at age=50 and mean values of everything else

One more thing — I've seen people accidentally use `aweight` or `fweight` when they should use `pweight` for survey data. What would go wrong if I used `regress bpsystol age [aweight=finalwgt]` instead of `svy: regress`?

## Capabilities Exercised

- Survey data: `svyset`, `svy: mean`, `svy: regress`, `subpop()`, `svy: test`
- Gotcha: weights not interchangeable — `pweight` for survey, implications of wrong weight type
- Gotcha: `subpop()` vs `if` — `if` drops obs before variance estimation, underestimates SEs
- Post-estimation: `margins`, `test` after `svy:`
- Factor variables: `i.sex`, `i.race`, `c.age#c.age`
- Descriptive stats: comparing weighted vs unweighted estimates

## Reference Files

- references/survey-data-analysis.md
- references/linear-regression.md
- references/descriptive-statistics.md
- references/variables-operators.md
