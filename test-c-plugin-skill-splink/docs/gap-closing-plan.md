# Gap-closing plan: Stata `splink` C plugin vs Python `splink`

This document audits the current Stata implementation (`splink.ado` + `c_source/splink_plugin.c`) against the Python `splink` package and lays out a prioritized plan to close remaining gaps.

## Target baseline (Python `splink`)

This plan targets the modern `splink` v4+ API and feature set (as used in `tests/generate_splink_validation.py`, which recommends `splink>=4.0.15`), including:

- `splink.comparison_library` comparison creators (and “out-of-the-box” comparisons)
- SQL-style blocking rules (multiple rules with de-duplication and `match_key`)
- Training pipeline:
  - `estimate_u_using_random_sampling()`
  - `estimate_parameters_using_expectation_maximisation()` (often with fixed `u`)
  - `estimate_probability_two_random_records_match()` (lambda)
  - round-robin EM across multiple blocking rules
- Term frequency adjustments (`tf_*` columns and `bf_tf_adj_*`)
- Prediction output columns (`match_weight`, `match_probability`, `gamma_*`, `bf_*`, `match_key`, and optional tf/intermediate columns)
- Model persistence (`save_model_to_json`, `save_settings_to_json`, loading a pre-trained model)
- Evaluation tooling (`linker.evaluation.*` accuracy analysis, ROC/PR, truth space tables)

## Current Stata implementation snapshot (what exists today)

### Files reviewed

- `splink.ado`: user-facing wrapper; writes an INI-style config; calls the plugin; merges a single output variable (cluster id) back into the original dataset; optionally writes a pairwise CSV via `savepairs()`.
- `c_source/splink_plugin.c`: single-pass implementation that:
  - builds candidate pairs from up to 4 exact-equality blocking keys (OR’d) and deduplicates pairs across rules
  - computes per-field comparison levels (“gamma”) using one of: JW/Jaro/Levenshtein/Damerau-Levenshtein/Jaccard/Exact/Numeric
  - runs EM to estimate `m`, `u`, and `lambda` jointly on the candidate pairs
  - scores pairs, clusters above `threshold()` using union-find, and writes a cluster id per record
  - optionally writes a pairwise CSV: `obs_a, obs_b, match_weight, match_probability, gamma_0..gamma_{k}`
- `splink.sthlp`: documents current syntax/options and features.
- `tests/test_splink.do`: unit-style tests for current features.
- `tests/test_splink_benchmarks.do`: benchmarks on exported `splink` datasets (purity/completeness/F1 at the cluster level).

### High-impact divergences vs Python `splink`

1. **Training pipeline mismatch**: Stata estimates `m/u/lambda` via EM directly on prediction candidate pairs; Python `splink` typically (a) estimates `u` by random sampling, (b) estimates `m` via EM using *training* blocking rules (often fixing `u`), and (c) estimates lambda via deterministic rules + recall.
2. **Gamma encoding mismatch**: Python `splink` uses `gamma=-1` for null and `gamma` increasing with agreement (else=0, exact=max). The plugin currently uses `0=null, 1=exact, …, else=max`.
3. **Blocking system gap**: Python uses SQL blocking rules (arbitrary expressions), unlimited rules, `match_key`, and has analysis tools; Stata supports only up to 4 varlist-equality rules via concatenated keys. Also, the plugin silently caps per-block comparisons (`MAX_BLOCK_SIZE=5000`), dropping pairs (recall loss).
4. **Comparison library gap**: only a subset of `splink.comparison_library` is implemented; “out-of-the-box” comparisons like `EmailComparison`, `PostcodeComparison`, `DateOfBirthComparison`, etc. are missing.
5. **Term frequency adjustments are not fully aligned**: Stata only adjusts `u` for exact matches and uses a combined TF table; Python supports richer semantics (per-level TF, fuzzy TF uses `max(tf_l, tf_r)`, weights, and explicit tf columns in outputs).
6. **Output format gap**: Stata’s `savepairs()` output does not match Python’s standard prediction columns (no `unique_id_l/r`, `gamma_{name}` columns, `bf_*`, `match_key`, optional tf/intermediate columns).
7. **Model persistence & evaluation tooling missing**: no save/load of trained model; no `evaluation`-style commands.

## Python `splink.comparison_library` inventory (and Stata parity status)

The modern Python comparison library exposes the following comparison creators (names as used in `splink.comparison_library`). This table is a concrete “checklist” for parity work.

| Python comparison creator | What it provides (high level) | Current Stata support | Planned priority |
|---|---|---:|---:|
| `ExactMatch` | exact agreement vs else (+ null) | ✅ (method `exact`) | P0/P1 (output parity) |
| `JaroWinklerAtThresholds` | JW similarity with thresholds | ✅ (method `jw`) | P0-1 (gamma parity), P1-1 (columns) |
| `JaroAtThresholds` | Jaro similarity with thresholds | ✅ (method `jaro`) | P0-1, P1-1 |
| `LevenshteinAtThresholds` | Levenshtein edit distance thresholds | ✅ (method `lev`) | P0-1, P1-1 |
| `DamerauLevenshteinAtThresholds` | DL distance thresholds | ✅ (method `dl`) | P0-1, P1-1 |
| `JaccardAtThresholds` | Jaccard similarity thresholds | ✅ (method `jaccard`) | P0-1, P1-1 |
| `DistanceFunctionAtThresholds` | generic distance-based comparison | ⚠️ Partial (numeric-only `numeric`) | P2-1 |
| `PairwiseStringDistanceFunctionAtThresholds` | generic string distance-based comparison | ❌ | P2-1 |
| `AbsoluteTimeDifferenceAtThresholds` | absolute time/datetime difference | ❌ | P2-1 (or fold into P0-5 if common) |
| `AbsoluteDateDifferenceAtThresholds` (alias) | absolute date difference | ❌ | P2-1 (or fold into P0-5 if common) |
| `DistanceInKMAtThresholds` | haversine/km distance thresholds | ❌ | P0-5 (if postcode km variant), else P2-1 |
| `DateOfBirthComparison` | domain-specific DOB logic | ❌ | P0-5 |
| `NameComparison` | domain-specific name logic (optionally phonetic) | ❌ | P0-5 |
| `ForenameSurnameComparison` | multi-column name logic | ❌ | P0-5 + P1-2 (needs multi-col comparisons) |
| `PostcodeComparison` | postcode component levels (+ optional km) | ❌ | P0-5 |
| `EmailComparison` | email username/domain logic | ❌ | P0-5 |
| `ArrayIntersectAtSizes` | overlap size thresholds for array-like fields | ❌ | P2-1 |
| `CosineSimilarityAtThresholds` | cosine similarity thresholds (vector features) | ❌ | P2-1 |
| `CustomComparison` | arbitrary user-defined comparison levels | ❌ | P1-2/P2-1 (via precomputed gamma) |

## Effort scale used in this plan

- **Small**: localized change; ≤1–2 files; mostly straightforward parsing/output.
- **Medium**: multi-file change; new option(s); moderate new logic; new tests.
- **Large**: architecture changes (new modes/subcommands, new file formats, substantial C changes, extensive tests/validation).

## Priority plan

### P0 (critical for matching quality)

#### P0-1: Align comparison level (“gamma”) encoding + null semantics with Python `splink`

**What Python `splink` does**
- Uses `gamma=-1` for null comparisons.
- Uses `gamma` such that higher values mean *more agreement*; else is typically `0`, exact match is typically `max_gamma`.

**What we do today**
- `compute_comparison_level()` encodes `0=null, 1=exact, 2..=threshold levels, else=max`.
- EM and output are built around this encoding.

**Code changes**
- `c_source/splink_plugin.c`
  - Update `compute_comparison_level()` to return Python-style `gamma`:
    - return `-1` when either side missing (when `nullweight(neutral)`), otherwise treat missing as else-level when `nullweight(penalize)`.
    - return `max_gamma` for exact matches.
    - return descending threshold levels mapped to ascending gamma (e.g., for JW thresholds `[0.92,0.8]`: else=0, 0.8+=1, 0.92+=2, exact=3).
  - Update EM/scoring loops in `em_estimate()` to treat `gamma=-1` as neutral Bayes factor (skip factor) when null is neutral.
  - Update pairwise output writer to emit the new gamma values.
- `splink.ado`
  - Update any documentation/help assertions about gamma meaning (if/when we expose gamma in Stata outputs beyond CSV).
- `tests/test_splink.do`
  - Add at least one `savepairs()`-based assertion that `gamma_*` includes `-1` when a field is missing and uses `0` for else, `max` for exact.

**Effort**: Medium  
**Dependencies**: Unblocks P0-6 (model save/load) and P1-1 (prediction output parity).

---

#### P0-2: Implement Python-style training pipeline parity (u via random sampling, lambda via deterministic rules, EM for m with u fixed)

**What Python `splink` does**
- `estimate_u_using_random_sampling(max_pairs=...)`: estimates `u` directly from randomly sampled record pairs.
- `estimate_parameters_using_expectation_maximisation(blocking_rule, fix_u_probabilities=True by default)`: estimates `m` (and possibly other params) using EM on *training* candidate pairs, often with `u` fixed from the random sampling step.
- `estimate_probability_two_random_records_match(deterministic_rules, recall=...)`: estimates lambda from high-precision deterministic rules, adjusted for expected recall.
- Supports *multiple EM runs* (“round robin”) over different blocking rules and averages parameter estimates across runs.

**What we do today**
- Single EM run on prediction candidate pairs estimates `m`, `u`, and `lambda` jointly; no random sampling; no deterministic lambda estimation; no multi-pass EM averaging.

**Code changes**
- `splink.ado`
  - Add an explicit training workflow. Two viable API shapes:
    1) **Subcommands (recommended)**:
       - `splink train, ...` (produces a model file)
       - `splink predict, model(...) ...` (produces pairwise predictions)
       - `splink cluster, using(predictions) ...` (produces cluster ids)
    2) **Single command with modes**:
       - `splink ..., train(...) model(...)` vs `splink ..., loadmodel(...)`.
  - Add options to specify:
    - `id(varname)` (unique id)
    - `linkvar(varname)` and `linktype()`
    - `blocking_rules_to_generate_predictions()` (existing `blockvar/block2...` can remain as a shorthand)
    - `emblockrules()` (training blocking rules; may be different from prediction rules)
    - `deterministic_rules()` + `recall(#)` for lambda estimation
    - `u_sampling_max_pairs(#)` + `u_sampling_seed(#)`
    - control flags matching splink defaults: `fix_u`, `fix_lambda`, `estimate_without_tf`
  - Serialize the above into the config/model file(s).
- `c_source/splink_plugin.c`
  - Introduce plugin “modes” in config, at minimum:
    - `MODE_ESTIMATE_U_RANDOM_SAMPLING`
    - `MODE_ESTIMATE_LAMBDA_DETERMINISTIC`
    - `MODE_EM_TRAIN` (estimate `m`, optionally `lambda`, with `u` typically fixed)
    - `MODE_SCORE_ONLY` (compute `p_match` without running EM)
  - Implement **random sampling u-estimation**:
    - Sample pairs uniformly from the allowed comparison universe (respecting `link_type`: cross-source only for `link_only`).
    - Compute gamma vectors for sampled pairs.
    - Set `u[k][g] = count(level=g)/n_samples`, with safeguards for zeros.
  - Implement **deterministic lambda estimation**:
    - Generate candidate “deterministic match” pairs based on user-specified deterministic rules (initially support exact-match-on-columns rules; later broaden).
    - Count unique deterministic pairs; compute:
      - `total_possible_pairs = n*(n-1)/2` for dedupe; `n_left*n_right` for link-only.
      - `lambda = min(1, deterministic_pairs/(total_possible_pairs*recall))`.
  - Update EM to support “fix u” and “fix lambda” behaviors, and to allow excluding comparisons that appear in an EM blocking rule (if/when blocking rules can reference comparison variables).
- `splink.sthlp`
  - Document the training vs prediction pipeline and defaults (e.g., “EM fixes u by default” to match splink).
- `tests/`
  - Add tests that compare Stata-trained `u` against Python `estimate_u_using_random_sampling()` on the same dataset (within tolerance).
  - Add tests that compare lambda estimation to Python outputs for deterministic rules (using `tests/validation_data/*_model.json` as the benchmark).

**Effort**: Large  
**Dependencies**: P0-1 (gamma parity) is required. P0-3 (blocking rules) affects the expressiveness of training blocking/deterministic rules.

---

#### P0-3: Remove silent recall loss in blocking (large blocks) + support Splink-style blocking rule lists

**What Python `splink` does**
- Uses a list of blocking rules (`blocking_rules_to_generate_predictions`), de-duplicates pairs across rules, and records `match_key`.
- Does not silently drop comparisons; users control scale via blocking design; Spark backend supports “salting” to manage skew.
- Separates **prediction** blocking rules from **training** blocking rules.

**What we do today**
- Supports up to 4 blocking rules (`blockvar`, `block2`–`block4`) that are exact equality on concatenated keys.
- The plugin caps each block to `MAX_BLOCK_SIZE=5000` and only compares the first 5000 rows in the block—pairs beyond that are silently ignored.
- No `match_key` in output.

**Code changes**
- `splink.ado`
  - Add `blockrules()` accepting a semicolon-separated list of varlists (or a more explicit syntax), removing the hard limit of 4.
  - Add `emblockrules()` similarly for training.
  - Add `maxblocksize(#)` with explicit behavior:
    - default should not silently truncate; if we must cap, default should **error** or **warn loudly** and write diagnostics.
  - Add `salting_partitions(#)` (or similar) as an optional skew-handling strategy: deterministically split large blocks into partitions before pair generation.
- `c_source/splink_plugin.c`
  - Replace `MAX_BLOCK_RULES` fixed arrays with dynamically allocated rule/key structures.
  - Implement `match_key`:
    - Extend `PairSet` to store `match_key` (the first blocking rule index that generated the pair).
    - When inserting a pair that already exists, preserve the existing (earlier) `match_key` to match Splink’s order-dependent semantics.
  - Replace “truncate first 5000” with one of:
    - (Preferred) salting/chunked pair generation that covers the full cartesian within block without materializing everything at once, or
    - an explicit “skipped comparisons” counter + diagnostics + option to error.
- `splink.sthlp` / `tests/test_splink_benchmarks.do`
  - Document and test behavior on blocks larger than `maxblocksize()`.

**Effort**: Large  
**Dependencies**: P1-1 output parity (for `match_key`), P0-2 (training/pred blocking separation).

---

#### P0-4: Term frequency adjustment parity (side-specific TF, fuzzy TF, weights, robust parsing)

**What Python `splink` does**
- Supports term frequency adjustments as an additive component to match weights, configurable per comparison level.
- Outputs TF columns (`tf_*_l`, `tf_*_r`) and TF-adjusted bayes factor columns (`bf_tf_adj_*`) when intermediate retention is enabled.
- For fuzzy matches, uses `max(tf_l, tf_r)` for the adjustment.
- Supports `tf_minimum_u_value` to avoid extreme weights.

**What we do today**
- `tfadjust(varlist)` only affects exact matches; plugin replaces `u` with a frequency looked up from a single combined TF table.
- No side-specific TF in link mode.
- TF tables are exported as CSV and parsed with a simplistic comma split (breaks on quoted values containing commas).
- No tf adjustment weight; no `tf_*` columns output.

**Code changes**
- `splink.ado`
  - Compute TF **per record** and (when `linkvar()` is used) separately by source (`*_l` vs `*_r`) to match Splink semantics.
  - Write TF lookup tables in a robust format (tab-delimited with escaping; or a binary `.dta`-like structure; or JSON).
  - Extend TF options:
    - `tfweight(#)` (default 1.0)
    - `tfapply(levels=...)` (optional; default should mirror Splink for the relevant comparison creator)
    - `tfmin(#)` already exists.
- `c_source/splink_plugin.c`
  - Replace per-pair TF value storage (`tf_pair_values`) with per-record TF lookup arrays per comparison:
    - `tf_freq[k][i] = tf(value_of_record_i)`
    - For a pair, `tf_pair = max(tf_freq[k][ai], tf_freq[k][bi])` (or side-specific values in link mode).
  - Apply TF adjustment at scoring time in a way that matches Splink’s decomposition:
    - compute base bayes factor `bf = m/u`
    - compute tf-adjustment factor `bf_tf_adj = (u / tf_pair)^tfweight` (subject to `tfmin`)
    - overall bayes factor = `bf * bf_tf_adj`
  - Fix TF file parsing (handle quoting/escaping) if CSV remains in use.
- `tests/test_splink.do`
  - Add cases with commas/quotes in TF-adjusted values.
  - Add link-mode test verifying side-specific TF behavior.

**Effort**: Medium–Large  
**Dependencies**: P0-1 (gamma parity), P1-1 (output parity if we output tf columns).

---

#### P0-5: Implement missing “out-of-the-box” comparisons that materially affect match quality

**What Python `splink` provides**
- Out-of-the-box comparisons (from `splink.comparison_library` and the topic guide):
  - `DateOfBirthComparison`
  - `NameComparison`
  - `ForenameSurnameComparison`
  - `PostcodeComparison` (including area/district/sector levels; optional km-based distance if lat/long are available)
  - `EmailComparison`

**What we do today**
- Only per-column string similarity/distance thresholds or exact/numeric. Users must hand-approximate domain logic (and cannot express multi-column comparisons like `ForenameSurnameComparison`).

**Code changes**
- `splink.ado`
  - Extend comparison specification so a comparison can optionally consume:
    - 1 column (DOB/name/email/postcode) or
    - multiple columns (forename+surname, lat+long pairs).
  - This likely requires moving beyond the current “one method per var in varlist” approach to a `compare()`-style option (see P1-2).
- `c_source/splink_plugin.c`
  - Add new comparison methods and supporting parsers:
    - DOB parsing and multi-level DOB comparison (including invalid-as-null behavior)
    - email username extraction, full-vs-username matching, JW thresholds
    - postcode parsing into components, and component-level agreement levels
    - optional haversine distance for km thresholds
    - optional phonetic algorithm (double metaphone) used by some name comparisons
- `tests/`
  - Add targeted unit tests for each out-of-the-box comparison.
  - Add a Python-vs-Stata parity test using `tests/validation_data/*_predictions.csv` as an oracle for a small dataset.

**Effort**: Large  
**Dependencies**: P1-2 (multi-column comparison specs) for `ForenameSurnameComparison` and km-based postcode variants.

---

#### P0-6: Expose fixed m/u parameters (and validation) through the Stata wrapper

**What Python `splink` does**
- Supports fixing `m` and/or `u` probabilities at the comparison level (and training often fixes `u` by default).
- Model JSON stores `fix_m_probability`/`fix_u_probability` per comparison level.

**What we do today**
- The plugin supports `fix_m`/`fix_u` in config and respects it in EM updates, but `splink.ado` never sets them (and does not parse `mprob()`/`uprob()` options).

**Code changes**
- `splink.ado`
  - Implement parsing for fixed probabilities:
    - either activate the existing `mprob()`/`uprob()` options, or
    - replace with a clearer `fixm()` / `fixu()` syntax that maps to comparison+level arrays.
  - Validate:
    - number of values matches number of levels for the comparison
    - probabilities are in (0,1)
    - probabilities sum to ~1.0 (epsilon)
  - Write `fix_m`, `fix_u`, `fixed_m`, `fixed_u` to config for each comparison.
- `c_source/splink_plugin.c`
  - Add config validation and clearer error messages when fixed arrays are malformed.
  - Add the ability to *populate* fixed values from a loaded model file (see P1-3).
- `splink.sthlp` + `tests/test_splink.do`
  - Document and test fixed-parameter behavior.

**Effort**: Medium  
**Dependencies**: P0-2 (training pipeline) and P1-3 (model persistence) benefit from this.

---

### P1 (important for usability / parity, but not strictly required for core match quality)

#### P1-1: Prediction output parity (Splink-like columns; frame/file outputs; separate predict vs cluster thresholds)

**What Python `splink` does**
- `linker.inference.predict(threshold_match_probability=...)` returns a pairwise predictions table with standard columns:
  - `match_weight`, `match_probability`
  - `unique_id_l`, `unique_id_r` (and `source_dataset_l/r` when relevant)
  - original columns with `_l/_r` suffix (when `retain_matching_columns=True`)
  - `gamma_{comparison_name}`, `bf_{comparison_name}`
  - optional `tf_*` and `bf_tf_adj_*` (when TF enabled and intermediate columns retained)
  - `match_key` identifying blocking rule
- Clustering is a separate operation on pairwise predictions at a threshold.

**What we do today**
- A single `splink` run produces only cluster ids in the active dataset.
- `savepairs()` writes a minimal CSV with observation indices and `gamma_0..`.

**Code changes**
- `splink.ado`
  - Add options to output pairwise predictions:
    - `predictframe(name)` (Stata 16+), or `predictfile(filename)` for older versions
    - `threshold_predict(#)` vs `threshold_cluster(#)` (mirror Python’s separation)
  - Add an `id(varname)` option and use it as `unique_id` in outputs (see P1-4).
  - Rename gamma columns to `gamma_{output_column_name}`.
- `c_source/splink_plugin.c`
  - Emit `match_key` and (optionally) `bf_*`, `tf_*`, `bf_tf_adj_*` in pairwise output.
  - Consider output format beyond CSV (e.g., write a `.dta`-readable delimited format; or write multiple files for large outputs).
- `splink.sthlp` + `tests/test_splink.do`
  - Document output columns.
  - Add tests that compare the column set against `tests/validation_data/*_predictions.csv` for a known config.

**Effort**: Medium–Large  
**Dependencies**: P0-1 (gamma parity), P0-3 (match_key), P0-4 (tf columns).

---

#### P1-2: Add a `compare()` spec (comparison objects) to support multi-column comparisons and future custom comparisons

**What Python `splink` does**
- Comparisons are objects composed of comparison levels (arbitrary SQL conditions), not restricted to a single input column.
- Built-in comparisons like `ForenameSurnameComparison` and km-distance postcode variants inherently require multiple columns.

**What we do today**
- `splink.ado` assumes “one comparison variable = one comparison method”. This blocks multi-column comparisons and limits parity.

**Code changes**
- `splink.ado`
  - Introduce a new `compare()` option (keep `compmethod()`/`complevels()` for backward compatibility):
    - one `compare()` entry per *comparison output column*
    - allow `inputs()` to reference 1+ Stata variables
    - allow `levels()` defined either as thresholds (for similarity/distance) or as named out-of-the-box patterns (email/postcode)
  - Write the richer comparison definitions to config/model files (likely JSON for flexibility).
- `c_source/splink_plugin.c`
  - Update config parser to accept multi-column comparisons:
    - store a list of input variable indices per comparison
    - implement method-specific logic that consumes those inputs
  - Add scaffolding for “custom comparisons” by allowing the wrapper to pass a precomputed `gamma_*` variable (see P2-1).

**Effort**: Large  
**Dependencies**: Enables P0-5 full out-of-the-box parity and future expansion.

---

#### P1-3: Model persistence (save/load) compatible with `save_model_to_json`

**What Python `splink` does**
- Saves a complete model (settings + trained parameters) to JSON via `linker.misc.save_model_to_json()`.
- Loads a pre-trained model by passing settings/model JSON into a new `Linker`, enabling predict-only runs on new data.

**What we do today**
- No persistence. Every run re-trains and clusters; diagnostics are written to a temporary diag file but not structured for reuse.

**Code changes**
- `splink.ado`
  - Add:
    - `savemodel(filename)` to write a JSON model in a Splink-like structure:
      - `probability_two_random_records_match`
      - blocking rules
      - comparisons with per-level `m_probability/u_probability`, null flags, and labels
      - prefixes and column name conventions
    - `loadmodel(filename)` to run in score-only mode (no EM), producing predictions and/or clusters.
- `c_source/splink_plugin.c`
  - Add a `MODE_SCORE_ONLY` that skips EM and uses fixed parameters from config/model.
  - Optionally implement JSON parsing in C; alternatively, keep JSON parsing in `splink.ado` and pass fixed arrays via config.
- `tests/`
  - Train once, save model, reload, and confirm predictions match within tolerance.

**Effort**: Large  
**Dependencies**: P0-1 (gamma parity), P0-6 (fixed params), P1-4 (stable ids).

---

#### P1-4: Stable identifiers (`unique_id`) and source dataset handling (`source_dataset`)

**What Python `splink` does**
- Requires a unique id column (`unique_id`) and optionally a `source_dataset` column for linking jobs.
- Outputs `unique_id_l/r` (and `source_dataset_l/r`) in predictions.

**What we do today**
- Uses observation indices in `savepairs()` and does not require an id variable.
- Linking is supported via `linkvar()`, but outputs don’t carry ids/sources.

**Code changes**
- `splink.ado`
  - Add `id(varname)`; default to `_n` only if the user explicitly opts in (to avoid unstable outputs).
  - Ensure `linkvar()` is treated as `source_dataset`.
  - Use `id()` values in any pairwise output and in saved models.
- `c_source/splink_plugin.c`
  - Read the id variable (and linkvar if present) and output id values rather than row numbers.

**Effort**: Small–Medium  
**Dependencies**: Strongly recommended for P1-1 (output parity) and P1-3 (model persistence).

---

#### P1-5: Evaluation tooling parity (accuracy analysis, ROC/PR, truth-space tables)

**What Python `splink` does**
- Provides `linker.evaluation.*` methods, including:
  - `accuracy_analysis_from_labels_column/table`
  - `roc_chart_from_labels_*`
  - `precision_recall_chart_from_labels_*`
  - `truth_space_table_from_labels_*`
  - `calculate_recall`

**What we do today**
- Only ad hoc evaluation in `tests/test_splink_benchmarks.do` (purity/completeness/F1 at cluster level), no reusable user-facing evaluation command.

**Code changes**
- Add new Stata programs:
  - `splink_evaluate.ado`: consumes a predictions dataset (from P1-1) plus a truth label (pairwise match indicator or shared entity id) and produces tables/graphs.
  - `splink_truthspace.ado`: produces threshold sweep outputs (precision/recall vs threshold, confusion matrix).
  - `splink_cluster_metrics.ado`: purity/completeness/F1 for clusters (generalize the benchmark logic).
- Add `splink_evaluate.sthlp` docs.
- Add tests that validate metric computations on `tests/validation_data/*` datasets.

**Effort**: Medium  
**Dependencies**: P1-1 (need pairwise predictions with ids) or at least a standard predictions file.

---

### P2 (nice-to-have / advanced parity)

#### P2-1: Implement the remainder of `splink.comparison_library` comparison creators

**What Python `splink` provides (comparison creators)**
- `AbsoluteTimeDifferenceAtThresholds` / `AbsoluteDateDifferenceAtThresholds`
- `ArrayIntersectAtSizes`
- `CosineSimilarityAtThresholds`
- `CustomComparison`
- `DistanceFunctionAtThresholds`
- `DistanceInKMAtThresholds`
- `PairwiseStringDistanceFunctionAtThresholds`
…in addition to the ones we already partially cover (`JaroWinklerAtThresholds`, `JaroAtThresholds`, `LevenshteinAtThresholds`, `DamerauLevenshteinAtThresholds`, `JaccardAtThresholds`, `ExactMatch`).

**What we do today**
- Covers only a subset and only for single-column comparisons.

**Code changes**
- `splink.ado` + `c_source/splink_plugin.c`
  - Add method handlers for each missing creator where feasible in Stata.
  - For creators that require non-scalar types (arrays, vector embeddings), add “user supplies similarity/feature” escape hatches:
    - accept precomputed similarity variables and threshold them
    - accept tokenized/string-list columns with a defined delimiter

**Effort**: Medium–Large (depending on creator)  
**Dependencies**: P1-2 (multi-column comparisons) for some creators; otherwise independent.

---

#### P2-2: Visualisation/dashboard parity (comparison viewer, cluster studio) via export + optional Python integration

**What Python `splink` does**
- Rich interactive dashboards and charts for parameter inspection, blocking analysis, and cluster review.

**What we do today**
- No integrated visual tooling.

**Code changes**
- Export predictions + model in a Splink-compatible format and provide helper scripts to:
  - launch Splink dashboards against exported artifacts, or
  - generate static charts (e.g., Vega/Altair) from Stata outputs.

**Effort**: Large  
**Dependencies**: P1-1 output parity, P1-3 model persistence.

---

#### P2-3: Scaling/performance improvements (streaming pair generation; memory reductions; parallelism)

**What Python `splink` does**
- Executes blocking, comparisons, and scoring in SQL engines (DuckDB/Spark/etc.), allowing large-scale runs.

**What we do today**
- Materializes all candidate pairs in memory (`pair_a`, `pair_b`, `comp_vec`, `p_match`) and caps large blocks, limiting scale and risking silent recall loss.

**Code changes**
- `c_source/splink_plugin.c`
  - Refactor candidate pair processing to stream block-by-block:
    - compute gamma + score on the fly
    - optionally write pairwise outputs incrementally
    - avoid storing all pairs unless clustering is requested (and even then, consider edge streaming).
  - Consider multi-threading for independent blocks if safe within Stata’s plugin constraints.

**Effort**: Large  
**Dependencies**: Easiest once P1-1 has a file-based pairwise output path.

---

## Suggested implementation sequence (dependency-aware)

1. **P0-1** gamma/null parity (enables matching Python outputs/model import).
2. **P0-3** blocking safety + `match_key` + remove silent truncation (prevents recall loss and aligns output).
3. **P0-6** fixed parameters from wrapper (enables “fix u” training).
4. **P0-2** training pipeline parity (u sampling + lambda + EM-for-m).
5. **P1-4** stable ids in outputs (required for persistence/eval).
6. **P1-1** predictions output parity (frame/file outputs; columns).
7. **P1-3** model persistence save/load (now feasible with fixed params + gamma parity).
8. **P1-5** evaluation tools (now have standardized predictions and stable ids).
9. **P0-5 / P1-2** expand comparison library and multi-column comparisons.
10. **P2** dashboards + scaling work.
