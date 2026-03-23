# Task 07: Staggered Difference-in-Differences

## Task Prompt

I'm studying the effect of a policy that rolled out to different states at different times. Simulate a dataset and run the analysis:

**Data setup:** 50 states, 15 years (2005-2019). States adopted the policy in waves: 10 states in 2010, 10 in 2013, 10 in 2016, and 20 never-adopters. The true treatment effect is +3.0 with no anticipation effects and no dynamic treatment effects (constant post-treatment). Generate the outcome with state FE, year FE, and normal noise (sd=2).

**Analysis:**
- First, run the naive TWFE DiD with `reghdfe` — `outcome` on `post_treatment`, absorbing state and year FE, clustered at the state level. Store this result.
- Explain why this estimator is potentially biased with staggered adoption timing (the "bad comparison" problem).
- Now run a proper staggered DiD using Callaway & Sant'Anna (`csdid`). Use the never-treated group as the comparison. Aggregate to an event-study and plot it.
- Compare the TWFE estimate to the CS estimate — how different are they? Given my DGP has a constant treatment effect and no anticipation, should they be similar or different?
- Show the event-study plot with pre-treatment coefficients. Do the pre-trends look clean?

## Capabilities Exercised

- Difference-in-differences: TWFE limitations, staggered adoption
- Packages: `reghdfe` for TWFE, `csdid` for Callaway-Sant'Anna
- Gotcha: TWFE with staggered timing can use already-treated as controls (negative weighting)
- Programming: simulating panel data with staggered treatment
- Graphics: event-study plot from `csdid_plot`
- Factor variables: understanding `absorb()` syntax in reghdfe

## Reference Files

- references/difference-in-differences.md
- packages/reghdfe.md
- packages/did.md
- references/panel-data.md
- references/graphics.md
