# Task 07: Difference-in-Differences

## Task Prompt

Write Stata code to implement a classic difference-in-differences analysis:
1. Simulate a panel dataset: 200 units, 10 time periods, half treated starting at period 6. The outcome has a unit FE, time FE, treatment effect of 2.5, and normal noise.
2. Create the necessary DiD variables (`post`, `treated`, `treat_post`)
3. Run the 2x2 DiD regression with clustered standard errors at the unit level
4. Test for parallel pre-trends by interacting treatment with pre-period dummies
5. Create an event-study plot of the pre-trend coefficients with confidence intervals
6. Interpret the results

## Capabilities Exercised

- **Difference-in-differences:** DiD setup, parallel trends testing, event study plot
- **Linear regression:** `regress`, `vce(cluster)`, `test`
- **Gotcha: Factor variables** — `i.` notation for time dummies and interactions
- **Programming:** `set seed`, `set obs`, data simulation with `generate`
- **Graphics:** coefficient plot or manual event study plot

## Reference Files

- references/difference-in-differences.md
- references/linear-regression.md
- references/programming-basics.md
- references/graphics.md
