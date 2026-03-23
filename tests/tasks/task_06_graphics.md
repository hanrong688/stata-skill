# Task 06: Multi-Panel Publication Figure

## Task Prompt

Using `sysuse auto`, I need a 4-panel figure for a journal submission. The journal wants PDF vector graphics, minimum 300 DPI equivalent for raster, and the figure should be interpretable in grayscale.

**Panel A:** Binned scatter of `price` vs `weight` with 15 bins, separate series for domestic and foreign, with linear fit overlay. Use `binsreg` if available, otherwise do it manually with `preserve`/`collapse`.

**Panel B:** Kernel density plot of `mpg` by `foreign`, with shaded areas under the curves (using `twoway area` or similar). Include a vertical line at the overall median.

**Panel C:** Horizontal coefficient plot from a regression of `price` on `mpg`, `weight`, `length`, `turn`, `headroom`, `trunk`, `i.foreign`, with robust SEs. Standardize coefficients by multiplying each by its variable's SD so they're comparable. Use `coefplot` if available.

**Panel D:** Box plots of `price` by `rep78` category (excluding missing), with individual data points overlaid (jittered).

Combine all four into a 2x2 figure with `graph combine`. Use panel labels (a), (b), (c), (d). Export as PDF and PNG (2400px width). Use a clean scheme — `plotplain` or `s2mono` — nothing with a gray background.

## Capabilities Exercised

- Graphics: `twoway`, `graph combine`, `graph export`, schemes
- Packages: `binsreg` for binned scatter, `coefplot` for coefficient plot, `graph-schemes` for clean schemes
- Gotcha: missing values — must exclude missing `rep78`
- Data management: `preserve`/`collapse` for manual binned scatter if package unavailable
- Line continuation: `///` for complex graph commands
- Regression: need to run model and standardize coefficients before plotting

## Reference Files

- references/graphics.md
- packages/binsreg.md
- packages/coefplot.md
- packages/graph-schemes.md
- references/linear-regression.md
