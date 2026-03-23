# Task 04: Heterogeneous Treatment Effects with Margins

## Task Prompt

Using `sysuse auto`, I want to understand how the price-weight relationship differs between domestic and foreign cars, and whether mileage moderates that.

Fit a model of `price` on `weight`, `mpg`, `foreign`, with full interactions between `foreign` and both continuous variables (i.e., the price-weight slope and the price-mpg slope can both differ by origin). Use robust standard errors.

Then:
- Test whether the full set of interaction terms is jointly significant
- Show me the marginal effect of a 100-pound increase in weight, separately for domestic and foreign cars, at the mean of all other variables
- Compute predicted prices at weight = 2000, 3000, 4000 for each foreign level, holding mpg at its mean
- Plot those predictive margins (marginsplot) and export as PNG
- Finally, give me the actual slope of weight on price for each group (i.e., not just "the marginal effect" but the actual linear combination of the coefficients)

I keep getting confused about `##` vs `#` and when I need `c.` — make sure the factor variable notation is right.

## Capabilities Exercised

- Gotcha: factor variable notation — `i.` for categorical, `c.` for continuous, `##` includes main effects, `#` is interaction only
- Post-estimation: `margins`, `marginsplot`, `lincom`
- Linear regression: `regress`, `vce(robust)`, `test`
- Gotcha: `margins, dydx()` vs `margins, at()` — different questions
- Graphics: `marginsplot`, `graph export`

## Reference Files

- references/linear-regression.md
- references/variables-operators.md
- references/graphics.md
