# Task 13: Time Series Analysis

## Task Prompt

Using `webuse lutkepohl2`:
1. Declare the time series structure with `tsset`
2. Plot the `ln_inv` series over time
3. Test for a unit root using the Augmented Dickey-Fuller test (`dfuller`)
4. If non-stationary, take first differences and re-test
5. Fit an ARIMA(1,1,1) model to `ln_inv`
6. Check residual diagnostics (autocorrelation)
7. Produce a 4-period ahead forecast and plot it

## Capabilities Exercised

- **Time series:** `tsset`, `dfuller`, `arima`, `predict`, `tsline`
- **Time-series operators:** `L.` (lag), `D.` (difference), `F.` (lead)
- **Graphics:** `tsline`, time series plots
- **Diagnostics:** residual autocorrelation, `estat`
- **Gotcha: Missing values** — differencing introduces missing at start

## Reference Files

- references/time-series.md
- references/graphics.md
- references/descriptive-statistics.md
