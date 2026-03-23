# Task 05: Automated Regression Table Pipeline

## Task Prompt

Using `webuse nlswork`, I run the same model across different subgroups all the time and I'm sick of copy-pasting. Build me an automated pipeline:

1. Define my specification: outcome is `ln_wage`, controls are `age c.age#c.age tenure hours i.race`. I want robust standard errors.

2. Write a loop that estimates this model separately for each level of `collgrad` (college graduate vs not) and also for the full sample (3 models total). Store each set of estimates with a clear name.

3. Export all three side-by-side in a single `esttab` table to both a `.csv` and a `.tex` file. I want standard errors in parentheses, stars at 10/5/1%, and clear column headers like "All", "No College", "College".

4. Now make it reusable: write a Stata program called `subgroup_table` that takes a `varlist` (outcome), a required option `controls(string)`, a required option `by(varname)`, and an optional `export(string)` option. It should do the same thing — run the model for each level of the `by` variable plus the full sample, and if `export()` is specified, write the table there. Make sure it uses `syntax` properly.

5. Test the program: call it with `ln_wage` as the outcome, the same controls, grouped by `race`, exporting to a file.

## Capabilities Exercised

- Gotcha: local macro syntax — `` `name' `` backtick + single-quote
- Programming: `local`, `foreach`, `levelsof`, `program define`, `syntax`
- Gotcha: stored results overwritten — must `estimates store` inside loop
- Packages: `estout`/`esttab` — formatting options, file export
- Advanced programming: `syntax varlist, controls(string) by(varname) [export(string)]`
- Gotcha: macros inside double quotes need compound quotes `"`macname'"` in some contexts

## Reference Files

- references/programming-basics.md
- references/advanced-programming.md
- references/linear-regression.md
- packages/estout.md
