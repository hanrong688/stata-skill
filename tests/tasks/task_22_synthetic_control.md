# Task 22: Synthetic Control Method

## Task Prompt

I'm studying the economic impact of a major policy reform in one state using the synthetic control method. Simulate the dataset and run the analysis:

**Data:** A balanced panel of 20 states over 20 years (2000-2019). State 1 is the treated unit, with the policy starting in 2010. The outcome is GDP growth. Pre-treatment, state 1 looks like a weighted average of states 5, 8, and 12. The true treatment effect is +2.0 percentage points starting in 2010.

Include three predictor variables for the matching: `population` (log), `unemployment_rate`, and `industry_share` (manufacturing share).

**Analysis:**
- Run the synthetic control using the `synth` package. Match on the pre-treatment outcome values and the three predictor variables. The dependent variable is GDP growth, the treated unit is state 1, the treatment year is 2010.
- Show me the pre-treatment fit: how closely does the synthetic control track state 1 before 2010?
- Plot the treated vs synthetic control time series (the classic synth plot)
- Compute and plot the treatment effect (gap) over time
- Run placebo tests: iteratively apply the synthetic control to each donor state as if it were treated (in-space placebo). Plot all the placebo gaps alongside the treated unit's gap.
- Compute the ratio of post/pre-treatment RMSPE for each unit. Where does the treated state rank? Is the effect "significant" by the permutation test criterion?
- Report the average treatment effect for the post-period

## Capabilities Exercised

- Packages: `synth` for synthetic control estimation, `synth_runner` for placebo tests
- Programming: simulating panel data with a known treatment effect
- Gotcha: `synth` requires specific data structure — `tsset` must be declared, treated unit identified by numeric ID
- Graphics: treated vs synthetic plot, gap plot, spaghetti plot of placebos
- Diagnostics: pre-treatment fit, RMSPE ratios, permutation inference

## Reference Files

- packages/synth.md
- references/panel-data.md
- references/graphics.md
- references/programming-basics.md
