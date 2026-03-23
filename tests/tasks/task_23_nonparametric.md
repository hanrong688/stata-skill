# Task 23: Nonparametric and Quantile Methods

## Task Prompt

Using `sysuse auto`, I suspect the relationship between price and weight isn't linear, and I care about the full distribution of prices — not just the mean.

- Start with kernel density estimation: plot the density of `price` separately for domestic and foreign cars using `kdensity`. Use the Epanechnikov kernel and pick an appropriate bandwidth. Overlay both densities on one graph.

- Run a nonparametric regression of `price` on `weight` using `npregress kernel`. Compare the fitted curve to a linear fit and a quadratic fit — plot all three on the same graph. Is the nonparametric fit materially different?

- Now quantile regression: run `qreg` for the 10th, 25th, 50th, 75th, and 90th percentiles of `price` on `weight`, `mpg`, and `foreign`. Is the effect of weight different at the top vs bottom of the price distribution? Run `sqreg` to get simultaneous quantile regression with bootstrapped SEs so I can formally test whether the 10th and 90th percentile coefficients on weight differ.

- Plot the quantile regression coefficients for `weight` across quantiles (the QR coefficient process). This should show how the effect changes across the price distribution.

- Run a Kolmogorov-Smirnov test and a rank-sum (Wilcoxon) test comparing the price distributions of domestic vs foreign cars. How do these compare to a plain t-test?

## Capabilities Exercised

- Nonparametric methods: `kdensity`, `npregress kernel`, `qreg`, `sqreg`, rank tests
- Gotcha: kernel bandwidth selection matters — too narrow = noisy, too wide = oversmoothed
- Packages: `nprobust` for robust nonparametric estimation (if available)
- Diagnostics: comparing parametric vs nonparametric fits
- Graphics: overlaid densities, QR coefficient plots, nonparametric fits
- Hypothesis testing: KS test, rank-sum test, interquantile range test

## Reference Files

- references/nonparametric-methods.md
- packages/nprobust.md
- references/graphics.md
- references/descriptive-statistics.md
