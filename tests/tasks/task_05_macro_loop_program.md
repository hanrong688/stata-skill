# Task 05: Macros, Loops, and Programming

## Task Prompt

Using `sysuse auto`, write a do-file that:
1. Define a local macro `outcomes` containing `price mpg weight`
2. Define a local macro `controls` containing `i.foreign trunk turn`
3. Loop over each outcome, regressing it on the controls with robust SEs
4. Store each set of estimates with a meaningful name
5. After the loop, create a comparison table using `estimates table`
6. Then write a small Stata program `summarize_by` that takes a varlist and a `by()` option, and displays `tabstat` of those variables by the grouping variable

## Capabilities Exercised

- **Gotcha: Local macro syntax** — backtick + single-quote `` `name' ``
- **Programming basics:** `local`, `foreach`, `program define`, `syntax`
- **Gotcha: Stored results overwritten** — must `estimates store` inside loop
- **Linear regression:** `regress`, `vce(robust)`
- **Advanced programming:** `syntax varlist, by(varname)`

## Reference Files

- references/programming-basics.md
- references/advanced-programming.md
- references/linear-regression.md
