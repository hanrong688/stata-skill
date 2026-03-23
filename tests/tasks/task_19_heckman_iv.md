# Task 19: Sample Selection and Instrumental Variables

## Task Prompt

I'm studying wages but I only observe wages for people who are employed — classic sample selection. Simulate the scenario and show me two approaches:

**Data:** 2000 individuals with `age`, `education`, `experience`, `married`, `num_children`.
- Selection equation: probability of employment depends on all variables (children especially matter)
- Outcome equation: log wages depend on education, experience, experience² (but NOT children — that's my exclusion restriction)
- Generate data from this DGP with a correlation of 0.5 between the selection and outcome error terms

**Part 1: Heckman selection model**
- Run `heckman` with the full specification. Use `num_children` as the excluded variable (it affects employment but not wages directly).
- Test whether there's actually selection bias — is the inverse Mills ratio (lambda) significant?
- Compare the Heckman estimates to naive OLS on the selected sample. How biased is the naive estimate of the education coefficient?

**Part 2: Instrumental variables**
- Now suppose I also worry that `education` is endogenous (correlated with unobserved ability). Simulate an instrument `college_proximity` that's correlated with education but not with the outcome error.
- Run 2SLS using `ivregress 2sls` with `college_proximity` as the instrument for education
- Run the first-stage F-test — is the instrument strong enough?
- Run `ivreg2` (if available) to get additional diagnostics: the Kleibergen-Paap F-stat, Anderson-Rubin confidence interval
- Compare OLS, Heckman, and IV estimates side by side

## Capabilities Exercised

- Sample selection: `heckman`, inverse Mills ratio, exclusion restrictions
- Gotcha: Heckman requires at least one variable in selection equation not in outcome equation
- Instrumental variables: `ivregress 2sls`, first-stage diagnostics
- Packages: `ivreg2` for additional IV diagnostics
- Programming: simulating correlated errors (Cholesky decomposition or bivariate normal)
- Diagnostics: weak instruments, overidentification tests

## Reference Files

- references/sample-selection.md
- references/linear-regression.md
- packages/ivreg2.md
- references/programming-basics.md
