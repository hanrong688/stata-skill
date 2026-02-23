# Proposed Changes

## Summary
The agent scored 51/55 — an excellent result. The sole weakness was unnecessary use of `margins, dydx(*) post`, which overwrites `e()` and forces redundant re-estimations. Neither the limited-dependent-variables reference nor the linear-regression reference warns about this. One small addition addresses the gap.

## Change 1: Add `post` option warning to margins guidance in limited-dependent-variables.md
- File: `references/limited-dependent-variables.md`
- Action: Modify
- Priority: Medium
- Justification: The judge docked points on Option & Usage Correctness (4/5), Gotcha Awareness (4/5), and Idiomaticness (4/5) specifically because the agent used `margins, dydx(*) post` unnecessarily, then had to re-estimate the model twice. The reference file's "Common Mistakes" section and margins guidance contain no warning about `post` overwriting `e()`. Adding one would steer the agent away from this pattern.
- Details: Add the following bullet to the "Common Mistakes" section (after line 276):

```
- Using `margins, post` unnecessarily — `post` replaces `e()` with margins results, forcing re-estimation before any further post-estimation (`estat`, `lroc`, `predict`, or another `margins` call). Only use `post` when you need to run `test` or `lincom` on the margins themselves.
```

And add a brief comment to the margins code example block (~line 162) so the pattern is reinforced in context. Change:

```stata
margins, dydx(*)
```

to:

```stata
margins, dydx(*)                    // Do NOT add `post` unless you need to test margins
```

## No Further Changes Needed
All other scores were 5/5. Command selection, syntax, completeness, and information retrieval were flawless. The single `post` warning is the only actionable gap identified by the judge.
r any estimation command (logit, probit, poisson, etc.), not just limited DV models.
```

## No Further Changes Needed
All other scores were 4-5, and the single weakness is fully addressed by the addition above. The agent's command selection, completeness, and explanatory content were excellent — no structural or routing changes are required.
