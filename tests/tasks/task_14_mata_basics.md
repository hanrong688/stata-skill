# Task 14: Mata Programming Basics

## Task Prompt

Write Stata code that uses Mata to:
1. Load the `price` and `mpg` variables from `sysuse auto` into a Mata matrix using `st_data()`
2. Write a Mata function `colstats()` that takes a matrix and returns a 2-row matrix where row 1 is column means and row 2 is column standard deviations
3. Call `colstats()` on the loaded data
4. Return the results to Stata as a matrix using `st_matrix()`
5. Display the results in Stata using `matrix list`

## Capabilities Exercised

- **Mata introduction:** when to use Mata, entering/exiting Mata
- **Mata data access:** `st_data()`, `st_matrix()`
- **Mata programming:** function definition, flow control, matrix operations
- **Mata matrix operations:** `mean()`, `diagonal()`, `variance()`, or manual computation
- **Programming:** interaction between Stata and Mata

## Reference Files

- references/mata-introduction.md
- references/mata-data-access.md
- references/mata-programming.md
- references/mata-matrix-operations.md
