# Eval Results: Full Skill vs Runner-Only Baseline

**Date:** 2026-03-22
**Model:** claude-sonnet-4-6
**Runs per task:** 5
**Total cost:** ~$160 (full skill ~$81, runner-only ~$79)

## Test Design

Two-arm comparison across 24 tasks:

- **Full skill**: All reference docs, package guides, and gotcha warnings loaded via `plugins` parameter
- **Runner-only**: Minimal plugin with only Stata execution instructions (binary paths, batch mode syntax), no reference docs

Both arms use identical environments: `cwd=tempfile.mkdtemp()`, no system prompt, `bypassPermissions` mode. The only difference is which plugin is loaded. See [How It Works](#how-it-works) for details.

### Code and Rubric

| File | Description |
|------|-------------|
| [`tests/eval.py`](eval.py) | Evaluation harness (Claude Agent SDK, `query()` calls) |
| [`tests/rubric.md`](rubric.md) | 7-category scoring rubric (max 55 points) |
| [`tests/tasks/`](tasks/) | 24 task definitions |
| [`tests/runner-only-plugin/`](runner-only-plugin/) | Runner-only baseline plugin |
| [`tests/results/`](results/) | All run directories and aggregate JSON files |

### Rubric Categories (max 55)

| # | Category | Weight | Max contribution |
|---|----------|--------|------------------|
| 1 | Syntax Correctness | PRIMARY (2x) | 10 |
| 2 | Command Selection | PRIMARY (2x) | 10 |
| 3 | Option & Usage Correctness | PRIMARY (2x) | 10 |
| 4 | Information Retrieval | PRIMARY (2x) | 10 |
| 5 | Gotcha Awareness | SECONDARY (1x) | 5 |
| 6 | Completeness | SECONDARY (1x) | 5 |
| 7 | Idiomaticness | SECONDARY (1x) | 5 |

Weighted total = (sum of PRIMARY scores) * 2 + (sum of SECONDARY scores) = max 55

## Full Comparison Table

```
#    Task                          Full Skill           Runner Only          Delta
                                N  Mean  Min  Max  SD   N  Mean  Min  Max  SD
─────────────────────────────────────────────────────────────────────────────────
 01  data_cleaning              5  53.8   49   55  2.7  5  37.8   14   52 14.6  +16.0
 02  merge_reshape              5  54.8   54   55  0.4  5  11.8   11   13  0.8  +43.0
 03  panel_regression           5  54.0   51   55  1.7  5  38.6   11   54 17.4  +15.4
 04  factor_variables_margins   5  55.0   55   55  0.0  5  55.0   55   55  0.0   +0.0
 05  macro_loop_program         5  54.6   53   55  0.9  5  42.4   24   55 14.2  +12.2
 06  graphics                   5  49.4   44   55  5.2  5  46.6   32   53  9.2   +2.8
 07  did                        5  45.6   20   54 14.5  5  28.4   11   54 20.3  +17.2
 08  logit_margins              5  53.4   50   55  2.3  5  52.8   51   54  1.3   +0.6
 09  survey_data                5  55.0   55   55  0.0  5  45.2   37   51  6.4   +9.8
 10  string_date_cleaning       5  55.0   55   55  0.0  5  40.4   21   55 17.7  +14.6
 11  bootstrap_simulation       5  55.0   55   55  0.0  5  23.2   10   39 11.9  +31.8
 12  preserve_collapse_merge    5  50.2   46   55  3.8  5  13.0   11   18  3.1  +37.2
 13  time_series                5  53.4   50   55  2.3  5  45.8   40   52  5.4   +7.6
 14  mata_basics                5  54.4   53   55  0.9  5  39.2   29   45  6.5  +15.2
 15  mata_optimization          5  55.0   55   55  0.0  5  35.2   14   55 18.0  +19.8
 16  multiple_imputation        5  49.8   43   53  4.1  5  52.0   49   55  2.8   -2.2
 17  lasso_variable_selection   5  53.6   49   55  2.6  5  38.2   30   53  9.0  +15.4
 18  custom_mle                 5  54.6   53   55  0.9  5  50.0   36   55  8.0   +4.6
 19  heckman_iv                 4  53.8   53   54  0.5  5  41.6   25   52 10.3  +12.1
 20  dynamic_panel_gmm          5  54.6   53   55  0.9  5  48.6   43   55  5.3   +6.0
 21  publication_tables         5  53.4   51   55  1.8  5  27.2   11   54 20.6  +26.2
 22  synthetic_control          5  44.0   21   54 13.1  5  13.4    9   17  2.9  +30.6
 23  nonparametric              4  52.2   50   55  2.1  5  46.2   32   55  9.5   +6.0
 24  sem_factor                 5  45.8   13   55 18.3  5  36.6   11   55 23.0   +9.2
─────────────────────────────────────────────────────────────────────────────────
     OVERALL                  118  52.5              120  37.9              +14.6
     Skill wins: 21/24 | Ties: 2 | Losses: 1
```

## Run Directory Index

Each run produces a `tests/results/run_NNN/` directory containing `transcript.json`, `judge_findings.md`, `metadata.json`, and any code files the agent wrote.

### Full Skill Runs

| Task | Scores | Run directories |
|------|--------|-----------------|
| 01 data_cleaning | 55, 49, 55, 55, 55 | run_137, run_150, run_153, run_158, run_166 |
| 02 merge_reshape | 55, 54, 55, 55, 55 | run_087, run_111, run_121, run_128, run_132 |
| 03 panel_regression | 51, 55, 54, 55, 55 | run_092, run_114, run_122, run_127, run_131 |
| 04 factor_variables_margins | 55, 55, 55, 55, 55 | run_091, run_112, run_116, run_120, run_125 |
| 05 macro_loop_program | 53, 55, 55, 55, 55 | run_088, run_113, run_118, run_124, run_129 |
| 06 graphics | 47, 55, 46, 55, 44 | run_179, run_192, run_200, run_212, run_215 |
| 07 did | 54, 20, 48, 52, 54 | run_177, run_189, run_195, run_203, run_210 |
| 08 logit_margins | 55, 55, 55, 52, 50 | run_138, run_148, run_155, run_161, run_167 |
| 09 survey_data | 55, 55, 55, 55, 55 | run_140, run_147, run_156, run_162, run_165 |
| 10 string_date_cleaning | 55, 55, 55, 55, 55 | run_178, run_186, run_202, run_209, run_211 |
| 11 bootstrap_simulation | 55, 55, 55, 55, 55 | run_143, run_149, run_154, run_159, run_164 |
| 12 preserve_collapse_merge | 50, 46, 47, 53, 55 | run_218, run_222, run_224, run_227, run_230 |
| 13 time_series | 50, 55, 55, 52, 55 | run_103, run_115, run_119, run_126, run_134 |
| 14 mata_basics | 55, 55, 54, 55, 53 | run_142, run_151, run_157, run_163, run_169 |
| 15 mata_optimization | 55, 55, 55, 55, 55 | run_217, run_219, run_221, run_223, run_226 |
| 16 multiple_imputation | 52, 43, 53, 49, 52 | run_216, run_220, run_225, run_228, run_229 |
| 17 lasso_variable_selection | 49, 55, 54, 55, 55 | run_145, run_152, run_160, run_168, run_170 |
| 18 custom_mle | 53, 55, 55, 55, 55 | run_102, run_117, run_123, run_130, run_133 |
| 19 heckman_iv | 54, 54, 53, None, 54 | run_172, run_181, run_190, run_201, run_213 |
| 20 dynamic_panel_gmm | 55, 53, 55, 55, 55 | run_173, run_180, run_187, run_194, run_206 |
| 21 publication_tables | 51, 55, 55, 54, 52 | run_171, run_182, run_191, run_196, run_204 |
| 22 synthetic_control | 49, 49, 21, 47, 54 | run_174, run_185, run_198, run_207, run_214 |
| 23 nonparametric | 55, 52, 52, 50, None | run_176, run_183, run_188, run_199, run_208 |
| 24 sem_factor | 13, 55, 54, 54, 53 | run_175, run_184, run_193, run_197, run_205 |

### Runner-Only Runs

| Task | Scores | Run directories |
|------|--------|-----------------|
| 01 data_cleaning | 38, 47, 38, 14, 52 | run_232, run_252, run_266, run_278, run_287 |
| 02 merge_reshape | 12, 11, 12, 13, 11 | run_233, run_243, run_246, run_253, run_258 |
| 03 panel_regression | 54, 37, 38, 11, 53 | run_231, run_244, run_260, run_263, run_275 |
| 04 factor_variables_margins | 55, 55, 55, 55, 55 | run_234, run_245, run_261, run_267, run_277 |
| 05 macro_loop_program | 55, 31, 47, 55, 24 | run_235, run_251, run_259, run_262, run_273 |
| 06 graphics | 32, 53, 53, 43, 52 | run_236, run_250, run_268, run_283, run_288 |
| 07 did | 11, 54, 20, 46, 11 | run_239, run_257, run_272, run_286, run_298 |
| 08 logit_margins | 53, 51, 52, 54, 54 | run_237, run_254, run_265, run_274, run_279 |
| 09 survey_data | 51, 37, 51, 40, 47 | run_238, run_256, run_271, run_276, run_285 |
| 10 string_date_cleaning | 21, 53, 52, 21, 55 | run_242, run_248, run_269, run_280, run_284 |
| 11 bootstrap_simulation | 14, 31, 22, 10, 39 | run_241, run_247, run_255, run_270, run_282 |
| 12 preserve_collapse_merge | 18, 11, 11, 14, 11 | run_240, run_249, run_264, run_281, run_289 |
| 13 time_series | 40, 52, 42, 44, 51 | run_322, run_324, run_326, run_329, run_331 |
| 14 mata_basics | 45, 44, 29, 41, 37 | run_323, run_325, run_328, run_332, run_334 |
| 15 mata_optimization | 55, 53, 14, 26, 28 | run_321, run_327, run_330, run_333, run_335 |
| 16 multiple_imputation | 54, 49, 55, 49, 53 | run_338, run_346, run_351, run_357, run_368 |
| 17 lasso_variable_selection | 32, 30, 53, 37, 39 | run_336, run_347, run_355, run_362, run_370 |
| 18 custom_mle | 52, 55, 36, 52, 55 | run_337, run_345, run_352, run_364, run_374 |
| 19 heckman_iv | 44, 40, 52, 47, 25 | run_339, run_349, run_361, run_372, run_378 |
| 20 dynamic_panel_gmm | 48, 53, 43, 44, 55 | run_341, run_348, run_359, run_369, run_377 |
| 21 publication_tables | 54, 45, 13, 13, 11 | run_340, run_350, run_358, run_366, run_371 |
| 22 synthetic_control | 14, 9, 17, 13, 14 | run_343, run_356, run_367, run_373, run_379 |
| 23 nonparametric | 32, 51, 41, 55, 52 | run_342, run_353, run_360, run_365, run_376 |
| 24 sem_factor | 12, 55, 50, 11, 55 | run_344, run_354, run_363, run_375, run_380 |

## Analysis: What We Learned

### Where the skill adds the most value

The 5 largest deltas (+26 to +43 points) share a common pattern: the runner-only agent either writes code for an entirely different task or uses Python/pandas idioms instead of Stata syntax.

**Task 02 (merge_reshape, +43.0):** All 5 runner-only runs produced either no `.do` file or files for unrelated tasks. run_233 (score=12) wrote a markdown narrative using pandas terminology (`groupby().diff()` instead of `bysort id (time): gen change = var[_n-1]`). The full-skill agent (run_087, score=55) used correct `merge m:1` with `assert _merge != 2`, `reshape long`, and `tempfile` patterns — all documented in `references/data-management.md`.

**Task 12 (preserve_collapse_merge, +37.2):** All runner-only runs scored 11-18. The agent could not execute the preserve/restore → collapse → tempfile → merge-back workflow without the reference docs. The `rdrobust` and `rdplot` package syntax was completely unavailable.

**Task 11 (bootstrap_simulation, +31.8):** Runner-only scores ranged 10-39. The `simulate` command's comma placement gotcha (`simulate stat=r(stat), reps(#): program`) and the `rclass` program requirement tripped the agent repeatedly. run_270 (score=10) wrote `smoking_analysis.do` instead of power analysis code.

**Task 22 (synthetic_control, +30.6):** Runner-only scored 9-17 consistently. The `synth` package requires specific `xtset` setup, output variable names (`_Y_treated`, `_Y_synthetic`), and the manual placebo loop pattern — none of which the model knows from training. Full-skill run_214 (score=54) implemented all of these correctly.

**Task 21 (publication_tables, +26.2):** Runner-only variance was extreme (11-54). run_340 scored 54 when the agent happened to recognize the task; run_371 scored 11 when it wrote `mi_health_survey.do` instead. The skill's `estout` package docs and `putdocx begin`/`save` wrapper pattern provide reliable guidance.

### Where the skill adds no value

**Task 04 (factor_variables_margins, +0.0):** Both conditions scored 55/55 on all 5 runs with zero variance. This is a ceiling effect — the task is too easy. `i.`/`c.`/`##` factor notation and `margins, dydx()` are thoroughly covered in Sonnet's training data. The reference content in `linear-regression.md` is correct but adds nothing measurable.

**Task 08 (logit_margins, +0.6):** Near-tie within noise. The `treatment-effects.md` reference file uses `cattaneo2` as its primary example — the same dataset the task specifies. The model already knows this canonical example. Full-skill runs were actually *more expensive* ($0.34-0.56 vs $0.15-0.37) and took more turns without improving scores.

### Where the skill actively hurt: Task 16 (multiple_imputation, -2.2)

The only task where the full skill scored lower than runner-only. Root cause: **two bugs in `missing-data-handling.md`** that taught wrong patterns.

**Bug 1 — `mi estimate:` without `post` then `estimates store`:** The Sensitivity Analysis section (line ~448) showed:
```stata
mi estimate: regress wage age grade hours
estimates store mi_est
```
Without `post`, `e(b)`/`e(V)` aren't populated, so `estimates store` silently stores nothing. run_220 (score=43) copied this verbatim, hit `r(111)` on `_b[income]`, and spent 3-4 more files trying to fix it. The runner-only agent (run_351, score=55) correctly used `mi estimate, post:` from training data — the skill literally overrode correct base knowledge.

**Bug 2 — `tsset iter` on panel-structured `savetrace` output:** The Convergence Checking section (line ~246) showed `use trace, clear; tsset iter` but the savetrace file has m × iter panel structure, requiring `reshape wide` first. Causes `r(451)` ("repeated time values").

### High-variance tasks: community package syntax

Three tasks had SD > 13, all involving community packages:

**Task 07 (DiD, SD=14.5):** run_189 (score=20) exhibited "context collapse" — wrote `psychometric_sem.do` and `synth_analysis.do` instead of DiD code. run_177 (score=54) correctly encoded `first_treat = 0` for never-treated units (the key `csdid` gotcha). Middle-scoring runs (32-48) hit event-study dummy construction bugs: hyphenated variable names (`lead-3` parsed as subtraction), wrong factor interaction order, `test` failing with negative factor levels.

**Task 22 (synthetic_control, SD=13.1):** run_198 (score=21) failed because `ssc install synth_runner` errored with `r(601)` — `synth_runner` is not on SSC. The agent then fabricated results in the transcript. run_214 (score=54) used a manual `foreach` placebo loop instead of `synth_runner`, avoiding the installation issue entirely.

**Task 24 (SEM/factor, SD=18.3):** run_175 (score=13) was pure context collapse — wrote `dynamic_panel_gmm.do` instead of SEM code. run_184 (score=55) correctly used `(Quality -> qual1 qual2 qual3)` path notation and re-estimated before `estat mindices` after `nlcom`.

### The anchoring effect

The runner-only agent's dominant failure mode across all low-scoring runs is **writing code for entirely different tasks** — not syntax errors. This "context collapse" accounts for the majority of the +14.6 overall delta. Examples:

- run_233 (task 02, score=12): wrote pandas-style narrative instead of Stata merge code
- run_270 (task 11, score=10): wrote `smoking_analysis.do` instead of power analysis
- run_356 (task 22, score=9): wrote `gmm_panel.do` + `lasso_analysis.do`
- run_371 (task 21, score=11): wrote `mi_health_survey.do` instead of publication tables

The full skill almost never exhibits this behavior. Even when reference content is "redundant" (the model already knows the material), loading it appears to anchor the agent's attention to the correct domain. This suggests that skills serve a dual purpose: teaching new information AND focusing the agent on the right task. See [ROADMAP.md](../ROADMAP.md#the-anchoring-effect) for implications.

## Changes Made Based on These Results

### Bugs fixed

| File | Bug | Evidence | Fix |
|------|-----|----------|-----|
| `references/missing-data-handling.md` | `mi estimate:` without `post` before `estimates store` — silently stores nothing, crashes on `_b[]` | run_220 (task 16, score=43): copied doc verbatim, hit `r(111)`. Runner-only run_351 (score=55) got it right without docs. | Added `post` to all 3 instances of `mi estimate` + `estimates store` |
| `references/missing-data-handling.md` | `tsset iter` on panel-structured `savetrace` output — causes `r(451)` | run_220 (task 16): hit "repeated time values" error on trace plot | Added `reshape wide *_mean *_sd, i(iter) j(m)` before `tsset iter` in 2 locations |
| `packages/synth.md` | `ssc install synth_runner` — package is NOT on SSC | run_198 (task 22, score=21): `r(601)` installation failure, then fabricated results | Changed to `net install synth_runner, from("https://raw.githubusercontent.com/...")` in 2 locations + added fallback note |
| `packages/binsreg.md` | Wrong `savedata()` variable names (`bins_x` vs actual `dots_x`) | Task 06 runs: agents using `savedata()` would get crashing code if they followed the doc literally | Fixed to actual names: `dots_x`, `dots_fit`, `poly_x`, `poly_fit`, `CI_l`, `CI_r` |

### Gotchas added

| File | Gotcha | Evidence |
|------|--------|----------|
| `references/graphics.md` | `graph box` is incompatible with `twoway` — cannot overlay jittered points | Task 06: every failed run tried `twoway (graph box ...)`. run_215 (score=44) also hit `r(459)` from merging observation-level data instead of group-level stats |
| `packages/did.md` | Event-study dummy construction: hyphenated names parsed as subtraction, wrong `ib()` prefix order, `testparm` needed for negative factor levels | Task 07: run_195 (score=48) and run_046 (score=32) both hit these exact bugs when building manual event-study dummies |
| `references/sem-factor-analysis.md` | `nlcom` clobbers `e()` — must re-estimate before `estat mindices`/`estat teffects`. Indirect effects require unstandardized coefficients. | Task 24: inconsistent behavior across runs when `nlcom` was followed by other post-estimation commands |

### Content added

| File | Addition | Evidence |
|------|----------|----------|
| `packages/coefplot.md` | Standardized coefficient workflow: rescale-before-regression approach + `ereturn post` inside `eclass` program | Task 06: run_236 (runner-only, score=32) failed building custom VCV matrix with `diag(vecdiag(rowvec))`. Multiple full-skill runs also struggled with `ereturn post` pattern |

### Documentation updated

| File | What changed |
|------|-------------|
| `tests/README.md` | Added runner-only baseline docs, eval results summary, bugs found, changes made, key lessons |
| `ROADMAP.md` | Added: gotchas-only skill variant idea, better test prompt design, harder tests needed, the anchoring effect lesson |

## How It Works

The evaluation harness (`tests/eval.py`) uses the Claude Agent SDK:

1. **Test agent** receives the task prompt, runs with the plugin loaded via `ClaudeAgentOptions.plugins`. Working directory is a fresh `tempfile.mkdtemp()`. No system prompt. Unlimited turns, `bypassPermissions` mode.

2. **File collection**: After the test agent finishes, `collect_code_files()` scans the working directory and `/tmp` for `.do` and `.log` files created during the run (filtered by timestamp).

3. **Judge agent** receives the task, rubric, transcript, AND the actual code files. The judge evaluates code quality primarily from the files, not just the chat transcript. Scores 7 categories (1-5 each), computes weighted total out of 55.

4. **Skill isolation**: The `plugins` parameter loads the skill without leaking repo context. Both arms use `cwd=/tmp`. No biasing system prompt ("You are a Stata expert") is used — the skill content itself must carry the weight.

### Running the comparison

```bash
# Full skill (default)
python tests/eval.py tests/tasks/task_01_data_cleaning.md --runs 5 --save tests/results/v2_task01.json

# Runner-only baseline
python tests/eval.py tests/tasks/task_01_data_cleaning.md --runs 5 --runner-only --save tests/results/v2_runner_task01.json
```

### Aggregate result files

| File | Description |
|------|-------------|
| `tests/results/v2_task{NN}.json` | Full-skill results for each task (list of 5 run results) |
| `tests/results/v2_runner_task{NN}.json` | Runner-only results for each task |
| `tests/results/run_NNN/` | Individual run directories with transcripts, judge findings, code files, metadata |
