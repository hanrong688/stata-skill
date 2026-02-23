# Stata Skill Test Rubric

Score each category 1-5. The primary goal is minimizing errors that would cause code to fail or produce wrong results.

---

## PRIMARY Categories

### 1. Syntax Correctness (weight: high)

Does the code have valid Stata syntax that would actually run?

| Score | Criteria | Example |
|-------|----------|---------|
| 1 | Multiple syntax errors; code would not run | `gen employed = 1 if status = 1` (uses `=` instead of `==`) |
| 2 | One or two syntax errors in key lines | Missing closing quote on a local macro: `` regress y `controls `` |
| 3 | Minor syntax issues that are easily fixable | Wrong option separator (comma in wrong place), minor typo |
| 4 | Syntactically correct with one trivial issue | Extra space or cosmetic inconsistency |
| 5 | Clean, error-free syntax throughout | All commands, macros, options syntactically correct |

### 2. Command Selection (weight: high)

Did the agent choose the right command/approach for the task?

| Score | Criteria | Example |
|-------|----------|---------|
| 1 | Fundamentally wrong command | Using `regress` for a binary outcome instead of `logit`/`probit` |
| 2 | Suboptimal command that may give wrong results | Using `ttest` when data requires `svy: mean` with survey weights |
| 3 | Reasonable command but not idiomatic | Using manual dummy variables instead of `i.` factor notation |
| 4 | Correct command with minor suboptimality | Using `xtreg, fe` instead of `reghdfe` when absorbing multiple FE |
| 5 | Best available command for the task | Correct estimation, correct SE adjustment, correct post-estimation |

### 3. Option & Usage Correctness (weight: high)

Are command options, variable types, and arguments used correctly?

| Score | Criteria | Example |
|-------|----------|---------|
| 1 | Critical option errors that change results | Omitting `vce(cluster id)` when clustering is needed; wrong weight type |
| 2 | Missing important options | Forgetting `replace` on `save`, missing `clear` on `use` |
| 3 | Options present but imprecise | Using `vce(robust)` when `vce(cluster)` is more appropriate |
| 4 | All important options correct, one minor omission | Missing `label` option on `esttab` |
| 5 | All options correct and well-chosen | Robust SEs, correct weight type, appropriate format options |

### 4. Information Retrieval (weight: medium)

Did the agent find and use the right reference information, or did it get confused about which package/command to use?

| Score | Criteria | Example |
|-------|----------|---------|
| 1 | Completely wrong reference frame | Suggests a command that doesn't exist in Stata |
| 2 | Confused between similar commands | Mixes up `merge` and `joinby` semantics; wrong `teffects` estimator |
| 3 | Right general area but imprecise | Knows to use DiD but unsure of exact syntax for staggered case |
| 4 | Correct information with minor gaps | Right command, right options, misses one relevant diagnostic |
| 5 | Precise, authoritative information | Correct command, options, diagnostics, and caveats mentioned |

---

## SECONDARY Categories

### 5. Gotcha Awareness (weight: medium)

Did the agent handle known Stata pitfalls without being prompted?

| Score | Criteria | Example |
|-------|----------|---------|
| 1 | Falls into multiple gotchas | `gen high = (x > 100)` without handling missing; unchecked `_merge` |
| 2 | Falls into one major gotcha | Forgets missing value check on a comparison |
| 3 | Handles obvious gotchas, misses subtle ones | Checks `_merge` but doesn't handle extended missing values |
| 4 | Handles most gotchas proactively | Missing value checks, `_merge` tab, correct macro quoting |
| 5 | Handles all relevant gotchas | All comparisons guard missing, merges checked, macros correct, weights correct |

### 6. Completeness (weight: low)

Did the agent address all parts of the user's request?

| Score | Criteria |
|-------|----------|
| 1 | Addressed less than half the request |
| 2 | Addressed about half |
| 3 | Addressed most parts, missed one |
| 4 | Addressed all parts, one could be more thorough |
| 5 | Fully addressed every part of the request |

### 7. Idiomaticness (weight: low)

Does the code follow Stata conventions and best practices?

| Score | Criteria | Example |
|-------|----------|---------|
| 1 | Code looks like it was written by someone who doesn't know Stata | R-style or Python-style patterns forced into Stata |
| 2 | Functional but unidiomatic | Excessive use of loops where `egen` or vectorized ops work |
| 3 | Mostly idiomatic with some odd choices | Works but doesn't use `compress`, `label`, or `///` continuation |
| 4 | Idiomatic with minor style issues | Good patterns, maybe missing `notes` or `codebook` |
| 5 | Clean, idiomatic Stata code | Proper use of `///`, labels, variable naming, `compress`, `describe` |

---

## Scoring Instructions for Judge

1. Read the original task prompt carefully
2. Read the full agent transcript
3. Score each of the 7 categories independently (1-5)
4. For each score, provide a 1-2 sentence justification with specific code examples
5. Compute a weighted total: PRIMARY categories count 2x, SECONDARY count 1x
   - Weighted total = (syntax + command + options + retrieval) * 2 + (gotchas + completeness + idiom)
   - Max possible: 8*5 + 3*5 = 55
6. List specific errors found (with line references if possible)
7. Note which gotchas from the SKILL.md were relevant and whether the agent handled them
