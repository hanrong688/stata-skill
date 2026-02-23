# Task 08: Binary Outcome Model

## Task Prompt

Using `sysuse auto`:
1. Run a logit model of `foreign` on `price`, `mpg`, `weight`, and `trunk`
2. Report odds ratios
3. Compute average marginal effects for each predictor
4. Compute predicted probabilities for a car with mpg=25, weight=3000, trunk=15, price=6000
5. Evaluate model fit using classification table and area under ROC curve
6. Compare with a probit specification — are substantive conclusions similar?

## Capabilities Exercised

- **Limited dependent variables:** `logit`, `probit`, `or` (odds ratios)
- **Post-estimation:** `margins`, `predict`, `estat classification`, `lroc`
- **Command selection:** knowing when logit vs probit matters
- **Gotcha: margins for nonlinear models** — marginal effects differ from coefficients

## Reference Files

- references/limited-dependent-variables.md
- references/linear-regression.md (for margins/predict patterns)
