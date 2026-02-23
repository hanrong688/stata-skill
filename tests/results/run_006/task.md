# Task 06: Publication-Quality Graphics

## Task Prompt

Using `sysuse auto`, create three publication-quality figures:

1. **Scatter with fit line:** `mpg` vs `weight`, colored by `foreign`, with separate linear fit lines for each group. Use semi-transparent markers. Add proper titles and axis labels.
2. **Bar chart:** Mean `price` by `rep78` category (excluding missing), with error bars showing 95% confidence intervals.
3. **Combined figure:** Combine the two plots into a single figure with a shared title, using `graph combine`.

Export the combined figure as both PDF and PNG (2400px width).

## Capabilities Exercised

- **Graphics:** `twoway scatter`, `lfit`, `by()`, `graph bar`, `graph combine`, `graph export`
- **Graphics options:** `mcolor()`, `%` transparency, `msize()`, `lcolor()`, schemes
- **Gotcha: Missing values** — must exclude missing `rep78` from bar chart
- **Line continuation:** `///` for readable multi-line graph commands

## Reference Files

- references/graphics.md
- references/descriptive-statistics.md
