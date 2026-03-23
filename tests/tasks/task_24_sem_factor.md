# Task 24: Structural Equation Modeling and Factor Analysis

## Task Prompt

I have a survey with multiple items measuring latent constructs and I need to do a proper psychometric analysis followed by a structural model. Simulate the data:

**Data:** 500 respondents, three latent factors:
- "Satisfaction" measured by 4 items (sat1-sat4)
- "Loyalty" measured by 3 items (loy1-loy3)
- "Quality" measured by 3 items (qual1-qual3)

The true structural model: Quality → Satisfaction → Loyalty, with Quality also having a direct effect on Loyalty. Generate the data from this structure with known factor loadings and path coefficients.

**Analysis:**
- First, compute Cronbach's alpha for each scale using `alpha`. Are the scales reliable?
- Run exploratory factor analysis (`factor`) requesting 3 factors with varimax rotation. Do the items load on the expected factors?
- Run confirmatory factor analysis with `sem`: define the three measurement models and check model fit (chi-squared, RMSEA, CFI, SRMR). Are the factor loadings all significant and above 0.5?
- Estimate the full structural model with `sem`: Quality → Satisfaction, Quality → Loyalty, Satisfaction → Loyalty. Report standardized coefficients.
- Test the indirect effect of Quality on Loyalty through Satisfaction using `estat teffects` — is the mediation significant?
- Compute modification indices with `estat mindices` — are there any large MIs suggesting model misspecification?
- Show a path diagram using `sem` and export it

## Capabilities Exercised

- SEM/Factor analysis: `sem`, `factor`, `alpha`, CFA, path models
- Gotcha: `sem` path notation — `(Satisfaction -> sat1-sat4)`, `(Quality -> Satisfaction)`
- Fit indices: RMSEA, CFI, SRMR interpretation
- Diagnostics: modification indices, standardized loadings, indirect effects
- Post-estimation: `estat gof`, `estat teffects`, `estat mindices`
- Programming: simulating data from a known factor structure

## Reference Files

- references/sem-factor-analysis.md
- references/descriptive-statistics.md
- references/programming-basics.md
