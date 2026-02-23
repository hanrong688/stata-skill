# Task 04: Factor Variables & Marginal Effects

## Task Prompt

Using `sysuse auto`:
1. Regress `price` on `mpg`, `i.foreign`, and their full interaction (`i.foreign##c.mpg`), with robust standard errors
2. Test whether the interaction is significant using `test`
3. Compute average marginal effects of `mpg` for each level of `foreign` using `margins`
4. Compute predictive margins at mpg = 20, 25, 30 for each foreign level
5. Create a `marginsplot` and export it as PNG

## Capabilities Exercised

- **Gotcha: Factor variable notation** — `i.` for categorical, `c.` for continuous, `##` for interaction
- **Linear regression:** `regress`, `vce(robust)`, `test`
- **Post-estimation:** `margins`, `marginsplot`, `predict`
- **Graphics:** `graph export`

## Reference Files

- references/linear-regression.md
- references/graphics.md
- references/variables-operators.md
