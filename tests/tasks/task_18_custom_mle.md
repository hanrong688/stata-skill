# Task 18: Custom Maximum Likelihood Estimation

## Task Prompt

I need to estimate a model that doesn't have a canned command in Stata. Specifically, I want to fit a zero-inflated Poisson model from scratch using `ml` (I know `zip` exists, but I want to understand the machinery).

The zero-inflated Poisson has two components:
- A logit model for the "always zero" group (probability π)
- A Poisson model for the "at risk" group (rate λ)

The log-likelihood for observation i is:
- If y_i = 0: log(π_i + (1 - π_i) * exp(-λ_i))
- If y_i > 0: log(1 - π_i) + y_i * log(λ_i) - λ_i - lnfactorial(y_i)

Steps:
- Simulate data: 1000 obs, two covariates `x1` and `x2`. The inflation probability depends on `x1` (via logit), the Poisson rate depends on both `x1` and `x2` (via log link). Generate `y` from this DGP.
- Write an `ml` evaluator program (method `lf`) that computes the observation-level log-likelihood
- Use `ml model` to declare the model with two equations (one for the Poisson rate, one for the inflation logit)
- Use `ml init` to set starting values (you can get reasonable starting values from a plain Poisson and a logit on a zero indicator)
- Run `ml maximize` and display results
- Compare your estimates to Stata's built-in `zip` command on the same data — they should match
- Show me the gradient convergence and iteration log

## Capabilities Exercised

- Maximum likelihood: `ml model`, `ml init`, `ml maximize`, method `lf` evaluator
- Gotcha: `ml model lf` requires the program to compute observation-level log-likelihood
- Gotcha: `ml init` — must set sensible starting values or optimizer may not converge
- Programming: `program define`, `args`, accessing equation parameters with `$ML_y1` or `ml_theta`
- Mathematical functions: `exp()`, `ln()`, `lnfactorial()`, `invlogit()`
- Diagnostics: iteration log, convergence criteria

## Reference Files

- references/maximum-likelihood.md
- references/limited-dependent-variables.md
- references/programming-basics.md
- references/mathematical-functions.md
