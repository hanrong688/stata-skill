The edit is ready but needs your approval. Here's the summary:

## Change Applied

**File:** `references/survey-data-analysis.md`  
**Action:** Modify — add two new pitfall entries (#6 and #7) to the "Critical Pitfalls" section  
**Priority:** Low (54/55 score, addressing a single 4/5 deduction)

**What's added:**
1. **Pitfall #6 — Missing values silently alter the subpopulation:** Documents that listwise deletion in `svy` commands can silently shrink the realized subpopulation, with a `misstable summarize` check pattern
2. **Pitfall #7 — `svy` commands set their own VCE:** Documents that you cannot override `vce()` on `svy:` commands (it's set at `svyset` time), with a wrong/right example

**No other changes needed.** The agent's performance was excellent across all other dimensions — correct syntax, correct commands, proper `subpop()` usage and explanation, idiomatic code, and complete coverage of all five task parts. The smart removal of `i.sex` from the female-only model was a particularly strong detail.
rm casewise deletion across all estimation variables.
Missing values drop observations *before* `subpop()` is applied, silently
changing your effective sample.
```stata
* Check missingness before estimation
misstable summarize height weight bpsystol age
count if !missing(height, weight, bpsystol, age)
```

**7. `svy` does not accept `vce()` overrides:**
The variance estimator is set by `svyset` (linearized or replicate-based).
Specifying `vce()` on an `svy`-prefixed command is an error.
```stata
* WRONG -- svy controls variance estimation
svy: regress income education, vce(robust)

* RIGHT -- vce determined by svyset
svyset psu [pweight = sampwgt], strata(stratum)
svy: regress income education
```
```

## No Further Changes Needed
All other scores were 5/5. The skill's routing table correctly pointed to `survey-data-analysis.md`, the SKILL.md gotchas section already covers weight interchangeability, and the agent's response was syntactically correct, idiomatic, and complete. No changes to SKILL.md or other files are warranted.
