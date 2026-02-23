# Stata Skill Coverage Map

Capabilities documented in the 37 core reference files, grouped by category. Used to design test tasks that span skill coverage.

## Gotchas (SKILL.md inline)

- Missing values sort to +infinity (comparisons include missing)
- `=` vs `==` (assignment vs comparison)
- Local macro syntax: `` `name' `` (backtick + single-quote)
- `by` requires prior sort (use `bysort`)
- Factor variable notation (`i.` categorical, `c.` continuous)
- `generate` vs `replace`
- String comparison is case-sensitive
- `merge` — always check `_merge`
- `preserve` / `restore`
- Weights are not interchangeable (fweight, aweight, pweight, iweight)
- `capture` swallows errors — check `_rc`
- Line continuation `///`
- Stored results: `r()` vs `e()` vs `s()` — estimation overwrites previous `e()`

## Data Operations (7 files)

| File | Capabilities |
|------|-------------|
| basics-getting-started | `use`, `save`, `describe`, `browse`, `sysuse`, basic workflow |
| data-import-export | `import delimited`, `import excel`, ODBC, `export`, web data |
| data-management | `generate`, `replace`, `merge`, `append`, `reshape`, `collapse`, `recode`, `egen`, `encode`/`decode` |
| variables-operators | Variable types (byte/int/long/float/double), operators, missing values, `if`/`in` qualifiers |
| string-functions | `substr()`, `regexm()`, `strtrim()`, `split`, `ustrlen()`, regex, Unicode |
| date-time-functions | `date()`, `clock()`, `%td`/`%tc` formats, `mdy()`, `dofm()`, business calendars |
| mathematical-functions | `round()`, `log()`, `exp()`, `abs()`, `mod()`, `cond()`, distributions, random numbers |

## Statistics & Econometrics (10 files)

| File | Capabilities |
|------|-------------|
| descriptive-statistics | `summarize`, `tabulate`, `correlate`, `tabstat`, `codebook`, weighted stats |
| linear-regression | `regress`, `vce(robust)`, `vce(cluster)`, `test`, `lincom`, `margins`, `predict`, `ivregress` |
| panel-data | `xtset`, `xtreg fe`/`re`, Hausman test, `xtabond`, dynamic panels |
| time-series | `tsset`, ARIMA, VAR, `dfuller`, `pperron`, `irf`, forecasting |
| limited-dependent-variables | `logit`, `probit`, `tobit`, `poisson`, `nbreg`, `mlogit`, `ologit`, `margins` for nonlinear |
| bootstrap-simulation | `bootstrap`, `simulate`, `permute`, Monte Carlo |
| survey-data-analysis | `svyset`, `svy:`, `subpop()`, complex survey design, replicate weights |
| missing-data-handling | `mi impute`, `mi estimate`, FIML, `misstable`, diagnostics |
| maximum-likelihood | `ml model`, custom likelihood functions, `ml init`, gradient-based optimization |
| gmm-estimation | `gmm`, moment conditions, `estat overid`, J-test |

## Causal Inference (5 files)

| File | Capabilities |
|------|-------------|
| treatment-effects | `teffects ra/ipw/ipwra/aipw`, `stteffects`, ATE/ATT/ATET |
| difference-in-differences | DiD, parallel trends, event studies, staggered adoption |
| regression-discontinuity | Sharp/fuzzy RD, bandwidth selection, `rdplot` |
| matching-methods | PSM, nearest neighbor, kernel matching, `teffects nnmatch` |
| sample-selection | `heckman`, `heckprobit`, treatment models, exclusion restrictions |

## Advanced Methods (5 files)

| File | Capabilities |
|------|-------------|
| survival-analysis | `stset`, `stcox`, `streg`, Kaplan-Meier, parametric models |
| sem-factor-analysis | `sem`, `gsem`, CFA, path analysis, `alpha`, reliability |
| nonparametric-methods | `kdensity`, rank tests, `qreg`, `npregress` |
| spatial-analysis | `spmatrix`, `spregress`, spatial weights, Moran's I |
| machine-learning | `lasso`, `elasticnet`, `cvlasso`, cross-validation |

## Graphics (1 file)

| File | Capabilities |
|------|-------------|
| graphics | `twoway`, `scatter`, `line`, `bar`, `histogram`, `graph combine`, `graph export`, schemes |

## Programming (6 files)

| File | Capabilities |
|------|-------------|
| programming-basics | `local`, `global`, `foreach`, `forvalues`, `program define`, `syntax`, `return` |
| advanced-programming | `syntax`, `mata`, classes, `_prefix`, dialog boxes, `tempfile`/`tempvar` |
| mata-introduction | Mata basics, when to use Mata vs ado, data types |
| mata-programming | Mata functions, flow control, structures, pointers |
| mata-matrix-operations | Matrix creation, decompositions, solvers, `st_matrix()` |
| mata-data-access | `st_data()`, `st_view()`, `st_store()`, performance tips |

## Output & Workflow (3 files)

| File | Capabilities |
|------|-------------|
| tables-reporting | `putexcel`, `putdocx`, `putpdf`, LaTeX integration, `collect` |
| workflow-best-practices | Project structure, master do-files, version control, debugging |
| external-tools-integration | Python via `python:`, R via `rsource`, shell commands, Git |
