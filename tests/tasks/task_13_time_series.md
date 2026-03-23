# Task 13: VAR Model and Impulse Response Analysis

## Task Prompt

Using `webuse lutkepohl2`, I want to analyze the dynamic relationships between investment (`ln_inv`), income (`ln_inc`), and consumption (`ln_consump`).

- Declare the time series and check each variable for unit roots using ADF tests. If non-stationary, take first differences and re-test.
- Determine the optimal VAR lag length using information criteria (AIC, BIC, HQIC). Show me the lag selection table.
- Estimate a VAR model with the chosen lag order on the (possibly differenced) variables. Check residual diagnostics — are there remaining autocorrelation problems? Use Lagrange multiplier tests.
- Compute impulse response functions: what happens to investment and consumption when there's a 1-SD shock to income? Plot the IRFs with 95% CIs out to 10 periods.
- Compute forecast error variance decomposition — after 10 periods, how much of the variation in investment is explained by shocks to each variable?
- Run Granger causality tests: does income Granger-cause investment? Does investment Granger-cause consumption?

## Capabilities Exercised

- Time series: `tsset`, `dfuller`, `var`, `varsoc`, `varlmar`, `vargranger`
- Time-series operators: `L.` (lag), `D.` (difference)
- IRF analysis: `irf create`, `irf graph`, `irf table`, `fevd`
- Gotcha: unit root testing — must use appropriate trend/drift specifications
- Gotcha: differencing introduces missing at start
- Graphics: IRF plots, FEVD plots
- Diagnostics: residual autocorrelation, lag selection

## Reference Files

- references/time-series.md
- references/graphics.md
- references/descriptive-statistics.md
