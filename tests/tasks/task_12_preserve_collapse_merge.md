# Task 12: Regression Discontinuity Design

## Task Prompt

I'm studying the effect of a scholarship program that's awarded to students who score above 75 on an entrance exam. Simulate a dataset and run a proper RD analysis:

**Data:** 2000 students with a running variable `exam_score` (uniform 50-100), treatment `scholarship` = 1 if score >= 75, and an outcome `gpa` that has a true discontinuity of +0.4 at the cutoff, with a linear relationship to exam score on both sides (different slopes) plus noise.

**Analysis:**
- Plot the raw data: binned scatter of GPA vs exam score, showing the discontinuity visually
- Run `rdrobust` to estimate the treatment effect with optimal bandwidth selection. Report the point estimate, robust CI, and effective sample size
- Show the `rdplot` — the RD plot with fitted polynomials on each side
- Run a manipulation test (`rddensity`) to check whether students gamed the cutoff
- As a robustness check, run the analysis with half and double the optimal bandwidth
- Also show the naive OLS estimate from a simple regression with the treatment dummy and a linear control for exam score (and their interaction) — how does it compare to `rdrobust`?

## Capabilities Exercised

- Regression discontinuity: sharp RD, bandwidth selection, manipulation testing
- Packages: `rdrobust` for estimation, `rdplot` for visualization, `rddensity` for McCrary test
- Programming: simulating RD data with a known discontinuity
- Linear regression: OLS comparison with `c.exam_score##i.scholarship`
- Graphics: binned scatter, RD plots
- Gotcha: factor variables — `c.` prefix needed for continuous vars in interactions

## Reference Files

- references/regression-discontinuity.md
- packages/rdrobust.md
- references/linear-regression.md
- references/graphics.md
