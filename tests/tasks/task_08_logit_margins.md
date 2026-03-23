# Task 08: Treatment Effect Estimation

## Task Prompt

Using `webuse cattaneo2` (birthweight data), I want to estimate the effect of maternal smoking (`mbsmoke`) on low birthweight (`lbweight`).

The problem is selection: smokers differ from non-smokers on observables. I want to see how sensitive the estimate is across methods:

1. **Naive comparison:** Just compare mean `lbweight` between smokers and non-smokers. What's the raw difference?

2. **Logit with controls:** Run a logit of `lbweight` on `mbsmoke` controlling for `mage`, `c.mage#c.mage`, `medu`, `mmarried`, `alcohol`, `fbaby`, `prenatal1`. Report odds ratios and average marginal effects.

3. **IPW:** Use `teffects ipw` to estimate the ATE of `mbsmoke` on `lbweight`, with the same controls in the treatment model.

4. **AIPW:** Use `teffects aipw` (doubly robust) with the same covariates in both the outcome and treatment models.

5. **Comparison table:** Put all four estimates (raw diff, logit AME, IPW ATE, AIPW ATE) side by side. How much does selection bias account for? Are the estimates stable across methods?

Don't just run the commands — I want to understand whether the overlap assumption is plausible. Show me a propensity score histogram by treatment group.

## Capabilities Exercised

- Treatment effects: `teffects ipw`, `teffects aipw`, ATE/ATT
- Limited dependent variables: `logit`, `margins, dydx()`
- Gotcha: margins for nonlinear models — AME ≠ coefficients
- Gotcha: overlap/common support — propensity score distribution
- Graphics: propensity score histogram
- Diagnostics: comparing estimates across methods for robustness

## Reference Files

- references/treatment-effects.md
- references/limited-dependent-variables.md
- references/matching-methods.md
- references/linear-regression.md
- references/graphics.md
