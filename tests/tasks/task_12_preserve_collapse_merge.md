# Task 12: Preserve/Restore & Collapse/Merge Back

## Task Prompt

Using `sysuse auto`:
1. Compute the mean price and mean mpg by `foreign` group using `collapse`
2. Merge these group means back onto the original (uncollapsed) dataset as new variables `mean_price_group` and `mean_mpg_group`
3. Create a "demeaned" price variable: each car's price minus its group mean
4. Do this using the `preserve`/`restore` pattern with a `tempfile`

This is a common pattern — compute group statistics and merge them back for within-group analysis.

## Capabilities Exercised

- **Gotcha: preserve/restore** — correctly saving and restoring data
- **Data management:** `collapse`, `merge`, `tempfile`
- **Gotcha: merge always check _merge** — verify the merge
- **Variables/operators:** `generate` with arithmetic on merged variables
- **Programming:** `tempfile` usage

## Reference Files

- references/data-management.md
- references/programming-basics.md
- references/basics-getting-started.md
