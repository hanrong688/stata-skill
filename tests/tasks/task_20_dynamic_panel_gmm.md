# Task 20: Dynamic Panel GMM Estimation

## Task Prompt

I'm estimating a dynamic investment equation where current investment depends on lagged investment (persistence), cash flow, and Tobin's Q. The problem: the lagged dependent variable is correlated with the fixed effect, making FE biased (Nickell bias). I need GMM.

Simulate a panel: 200 firms, 10 years. The DGP is:
- y_it = 0.6 * y_{i,t-1} + 1.5 * x1_it + 0.8 * x2_it + α_i + ε_it
- α_i ~ N(0, 1), ε_it ~ N(0, 1)
- x1 is predetermined (correlated with past ε but not current), x2 is strictly exogenous

Walk me through the GMM estimation:
- Show that FE is biased by running `xtreg y L.y x1 x2, fe` and comparing the coefficient on L.y to the true 0.6
- Run the Arellano-Bond difference GMM estimator using `xtabond2`. Use `L(2/.)` lags of `y` as instruments for `D.y`, treat `x1` as predetermined (`gmm(x1, lag(1 .))`) and `x2` as exogenous (`iv(x2)`). Use the two-step estimator with Windmeijer-corrected standard errors.
- Report the Arellano-Bond test for AR(1) and AR(2) in first differences — what should we expect?
- Report the Hansen J-test for overidentification — too many instruments is a problem. If you have way too many, show how to limit the instrument count with `collapse`
- Run system GMM (Arellano-Bover/Blundell-Bond) with `xtabond2` using the `sys` option and compare
- Show me a comparison: true coefficient = 0.6, FE estimate, difference GMM estimate, system GMM estimate

## Capabilities Exercised

- GMM estimation: moment conditions, instrument validity, overidentification
- Packages: `xtabond2` for Arellano-Bond/Blundell-Bond GMM
- Gotcha: Nickell bias — FE is inconsistent with lagged dependent variable in short panels
- Gotcha: too many instruments weakens Hansen test — use `collapse` option
- Time-series operators: `L.` for lags, `D.` for differences
- Diagnostics: AR(1)/AR(2) tests, Hansen J-test, instrument count
- Panel data: `xtset`, dynamic panel models

## Reference Files

- references/gmm-estimation.md
- packages/xtabond2.md
- references/panel-data.md
- references/linear-regression.md
