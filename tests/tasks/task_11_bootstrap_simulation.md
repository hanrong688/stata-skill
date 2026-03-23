# Task 11: Power Analysis via Monte Carlo Simulation

## Task Prompt

I'm designing an RCT and need a power analysis. My setup:
- Outcome is continuous, normally distributed
- I expect a treatment effect of 0.3 standard deviations
- I'll use OLS with a few baseline controls (which should improve power by reducing residual variance)
- I want 80% power at the 5% significance level
- I'll cluster randomize at the group level (20 individuals per group)

Build me a Monte Carlo simulation that:

1. Takes as parameters: number of groups, group size, effect size, ICC (intra-class correlation), and R² of controls
2. For each replication: generates clustered data with the right ICC, assigns treatment at the group level, adds controls that explain R² of the residual variance, runs OLS with `vce(cluster group_id)`, and records whether the treatment coefficient is significant at 5%
3. Runs 1000 replications and reports the rejection rate (= power)
4. Sweeps over a range of group counts (10, 20, 30, 40, 50 groups per arm) with ICC = 0.05 and reports power for each
5. Plots a power curve (number of groups vs power) with a horizontal reference line at 80%

I want the simulation to be a proper Stata program using `simulate`, not a manual loop. Set a seed for reproducibility.

## Capabilities Exercised

- Bootstrap/simulation: `simulate`, `program define`, `return scalar`
- Programming: `syntax`, `set seed`, programs that return r-class results
- Gotcha: `simulate` requires the program to be r-class and return named scalars
- Gotcha: stored results — `_b[]`, `_se[]`, accessing results inside programs
- Linear regression: `regress`, `vce(cluster)`
- Graphics: power curve plot
- Mathematical functions: `rnormal()`, generating correlated/clustered data

## Reference Files

- references/bootstrap-simulation.md
- references/programming-basics.md
- references/linear-regression.md
- references/mathematical-functions.md
- references/graphics.md
