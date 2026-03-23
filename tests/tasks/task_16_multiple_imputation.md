# Task 16: Multiple Imputation for Missing Data

## Task Prompt

I'm working with a health survey where key variables have non-trivial missingness, and my PI insists I can't just do complete-case analysis. Simulate the scenario and walk me through it:

**Data:** 1000 observations with:
- `income` (continuous, 15% MCAR missing)
- `education` (ordinal 1-4, 10% MAR missing — more likely missing for low-income respondents)
- `health_status` (binary, 5% MCAR missing)
- `age`, `gender` (complete — these are auxiliary variables)
- Outcome: `bmi` (continuous, complete)

Create this dataset with the appropriate missingness patterns. Then:

- Use `misstable summarize` and `misstable patterns` to characterize the missingness — how many complete cases do I have? What are the patterns?
- Set up MI with `mi set mlong` and register the imputed variables
- Run chained equations imputation (`mi impute chained`) — use `regress` for income, `ologit` for education, `logit` for health_status. Include all other variables (including the outcome!) as predictors in the imputation models. 20 imputations, set a seed.
- Run `mi estimate: regress bmi income education i.health_status age i.gender` and show me the combined estimates
- Compare the MI estimates to the complete-case estimates — how different are they? Which variables' coefficients changed the most?
- Check imputation diagnostics: are the imputed values plausible? Show me a density plot comparing observed vs imputed values for income.

Why do I include the outcome variable in the imputation model? That seems circular but I've read you're supposed to.

## Capabilities Exercised

- Missing data: `mi set`, `mi register`, `mi impute chained`, `mi estimate`
- Gotcha: must include outcome in imputation model (congeniality requirement)
- Gotcha: choosing the right imputation method for each variable type (continuous vs ordinal vs binary)
- Diagnostics: `misstable`, comparing observed vs imputed distributions
- Programming: simulating data with structured missingness (MAR mechanism)
- Linear regression: comparing complete-case vs MI estimates

## Reference Files

- references/missing-data-handling.md
- references/limited-dependent-variables.md
- references/descriptive-statistics.md
- references/programming-basics.md
