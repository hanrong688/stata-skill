# Task 15: Mata Performance Optimization

## Task Prompt

I have a computation that's painfully slow in ado-code and I want to speed it up with Mata. The task: for each observation in a dataset, compute its Mahalanobis distance to every other observation, then store the minimum distance (nearest-neighbor distance) as a new variable.

Using `sysuse auto` (just `price`, `mpg`, `weight` as the distance variables):

- First, do it the naive ado way with nested `forvalues` loops so we can see how slow it is on even 74 obs
- Then rewrite it in Mata:
  - Load the three variables into a Mata matrix using `st_data()`
  - Write a Mata function `mahal_nn()` that takes a data matrix, computes the variance-covariance matrix, inverts it, and for each row computes the Mahalanobis distance to all other rows, returning a column vector of minimum distances
  - Use `st_store()` to write the results back to a new Stata variable
  - Time both approaches and compare

- As a bonus, also write a Mata function that computes a robust (median-based) covariance matrix instead of the standard one. This requires writing your own median function in Mata since there isn't a built-in one.

I need to understand: when should I drop into Mata vs staying in ado? What are the gotchas around `st_view()` vs `st_data()` (one is a copy, one is a pointer to the actual data)?

## Capabilities Exercised

- Mata introduction: when to use Mata, entering/exiting Mata
- Mata data access: `st_data()` vs `st_view()`, `st_store()`, `st_addvar()`
- Mata programming: function definition, flow control, local variables
- Mata matrix operations: `variance()`, `invsym()`, `cross()`, matrix arithmetic
- Gotcha: `st_view()` creates a view (pointer), `st_data()` creates a copy — views are faster but can't be used if data changes
- Performance: vectorized operations vs loops in Mata

## Reference Files

- references/mata-introduction.md
- references/mata-programming.md
- references/mata-matrix-operations.md
- references/mata-data-access.md
