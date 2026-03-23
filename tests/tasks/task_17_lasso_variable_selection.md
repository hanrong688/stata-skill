# Task 17: Lasso and Machine Learning Variable Selection

## Task Prompt

I have a prediction problem with lots of potential predictors and I want to use regularization to figure out which ones matter. Using `sysuse auto`:

- I want to predict `price` using all available numeric predictors (`mpg`, `rep78`, `headroom`, `trunk`, `weight`, `length`, `turn`, `displacement`, `gear_ratio`, `foreign`). Some of these are probably redundant.

- Run a LASSO regression using Stata's built-in `lasso` command. Use cross-validation to select the penalty parameter. Which variables survive the LASSO selection?

- Now run elastic net (`elasticnet`) with alpha = 0.5 as a comparison. Do you get a different set of selected variables?

- Run `lasso` with the `selection(plugin)` option (the plug-in method rather than CV) — how does it compare?

- For inference after selection: I've heard you can't just run OLS on the LASSO-selected variables because of post-selection bias. Use `dsregress` (double-selection LASSO / partialing-out) to estimate the causal effect of `weight` on `price`, treating all other variables as potential controls. How does this compare to a naive OLS of price on weight?

- Show me the cross-validation plot (lambda vs CV MSE) and a coefficient path plot showing how coefficients shrink as lambda increases.

I'm confused about when to use `lasso` vs `dsregress` vs `poregress` — when is each appropriate?

## Capabilities Exercised

- Machine learning: `lasso`, `elasticnet`, `cvlasso`, cross-validation
- Gotcha: post-selection inference — can't do naive OLS on LASSO-selected vars
- Double-selection: `dsregress` for causal inference after variable selection
- Model selection: `selection(cv)` vs `selection(plugin)` vs `selection(adaptive)`
- Graphics: CV plot, coefficient path plot
- Diagnostics: comparing selected variables across methods

## Reference Files

- references/machine-learning.md
- references/linear-regression.md
- references/graphics.md
