# Task 14: Survival Analysis with Cox PH Model

## Task Prompt

Using `webuse cancer` (patient survival data), run a full survival analysis:

- Set up the survival data with `stset`. The outcome is `died`, the time variable is `studytime`. Make sure you specify the failure event correctly.
- Show me Kaplan-Meier survival curves by treatment group (`drug`). Include the number at risk table below the graph. Test whether the curves are significantly different using the log-rank test.
- Fit a Cox proportional hazards model of survival on `drug`, `age`, and their interaction. Report hazard ratios.
- The proportional hazards assumption is critical for Cox models. Test it formally using Schoenfeld residuals (`estat phtest`) and visually using log-log plots. If any variable violates PH, tell me what to do about it.
- Compute and plot the baseline cumulative hazard function and the adjusted survival function at the mean of all covariates.
- Finally, predict the martingale residuals and plot them against `age` to check for nonlinearity — do I need a polynomial or different functional form for age?

## Capabilities Exercised

- Survival analysis: `stset`, `stcox`, `sts graph`, `sts test`, `stcurve`
- Diagnostics: PH assumption (`estat phtest`), Schoenfeld residuals, log-log plots, martingale residuals
- Gotcha: `stset` syntax — must specify `failure()` event correctly
- Graphics: K-M curves with risk table, log-log plots, residual plots
- Post-estimation: hazard ratios, `predict` after `stcox`, baseline hazard
- Factor variables: `i.drug`, `i.drug##c.age` interaction

## Reference Files

- references/survival-analysis.md
- references/graphics.md
- references/linear-regression.md
