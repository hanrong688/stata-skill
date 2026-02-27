/*
    test_splink_benchmarks.do — Benchmark against splink's real datasets

    Tests the Stata plugin against splink's built-in datasets which have
    known ground truth entity IDs, allowing precision/recall measurement.

    Prerequisite: run export_splink_datasets.py first to create CSVs.

    v2: Updated to exercise configurable comparison methods, multiple
    blocking rules, and other v2 features.

    Metrics:
      Purity    = fraction of predicted clusters containing only one true entity
                  (precision proxy: are the clusters clean?)
      Completeness = fraction of true entities contained in only one cluster
                  (recall proxy: did we find all the matches?)
*/

clear all
set more off

/* ============================================================
   UTILITY: Compute pairwise precision/recall
   ============================================================ */
capture program drop _linkage_metrics
program define _linkage_metrics, rclass
    * Computes purity and completeness given cluster_id and true_entity_id
    * Assumes these variables exist in the current dataset
    args cluster_var entity_var

    tempvar tag1 n_entities tag2 n_clusters

    * --- Purity: fraction of predicted clusters with only 1 true entity ---
    * Tag first occurrence of each (cluster, entity) combination
    bysort `cluster_var' `entity_var': gen byte `tag1' = (_n == 1)
    bysort `cluster_var': egen int `n_entities' = total(`tag1')

    * A cluster is "pure" if it contains records from only 1 true entity
    tempvar is_pure
    bysort `cluster_var': gen byte `is_pure' = (`n_entities' == 1)
    * Count distinct clusters
    tempvar cluster_tag
    bysort `cluster_var': gen byte `cluster_tag' = (_n == 1)
    quietly count if `cluster_tag' == 1
    local total_clusters = r(N)
    quietly count if `cluster_tag' == 1 & `is_pure' == 1
    local pure_clusters = r(N)
    local purity = `pure_clusters' / `total_clusters'

    * --- Completeness: fraction of true entities in only 1 predicted cluster ---
    bysort `entity_var' `cluster_var': gen byte `tag2' = (_n == 1)
    bysort `entity_var': egen int `n_clusters' = total(`tag2')

    tempvar is_complete
    bysort `entity_var': gen byte `is_complete' = (`n_clusters' == 1)
    tempvar entity_tag
    bysort `entity_var': gen byte `entity_tag' = (_n == 1)
    quietly count if `entity_tag' == 1
    local total_entities = r(N)
    quietly count if `entity_tag' == 1 & `is_complete' == 1
    local complete_entities = r(N)
    local completeness = `complete_entities' / `total_entities'

    * --- F1 ---
    local f1 = 2 * `purity' * `completeness' / (`purity' + `completeness')

    display as text ""
    display as text "  Linkage Quality Metrics:"
    display as text "  {hline 40}"
    display as text "  Purity (precision):     " as result %6.3f `purity'  ///
        as text "  (`pure_clusters'/`total_clusters' clusters)"
    display as text "  Completeness (recall):  " as result %6.3f `completeness' ///
        as text "  (`complete_entities'/`total_entities' entities)"
    display as text "  F1 score:               " as result %6.3f `f1'
    display as text "  {hline 40}"

    return scalar purity = `purity'
    return scalar completeness = `completeness'
    return scalar f1 = `f1'
    return scalar total_clusters = `total_clusters'
    return scalar total_entities = `total_entities'
end


/* ============================================================
   BENCHMARK 1: splink fake_1000 (dedup, 1000 records, 251 entities)
   High missing data rates (~17-21%), realistic name typos
   ============================================================ */
display as text _n "{hline 60}"
display as text "BENCHMARK 1: splink fake_1000 (dedup)"
display as text "{hline 60}"

capture confirm file "tests/splink_fake_1000.csv"
if _rc != 0 {
    display as error "  SKIP: tests/splink_fake_1000.csv not found"
    display as error "  Run: python3 tests/export_splink_datasets.py"
}
else {
    import delimited "tests/splink_fake_1000.csv", clear

    display as text "  Records: " _N

    * Count actual entities
    tempvar etag
    bysort cluster: gen byte `etag' = (_n == 1)
    quietly count if `etag' == 1
    display as text "  True entities: " as result r(N)

    * dob is a string "YYYY-MM-DD" — extract year for blocking
    gen dob_year = real(substr(dob, 1, 4))

    * Show missing data rates
    foreach v in first_name surname city email {
        quietly count if missing(`v') | `v' == ""
        local pct = r(N) / _N * 100
        display as text "  `v': " as result %4.1f `pct' "% missing"
    }

    * --- Run 1a: Default JW (backward compatible), block on dob ---
    display as text _n "  Run 1a: Default JW, blocking on dob"

    timer clear 1
    timer on 1

    splink first_name surname city email, ///
        block(dob) gen(cluster_id_1a) thr(0.85) verbose

    timer off 1

    display as text "  Candidate pairs: " as result r(n_pairs)
    display as text "  Matches: " as result r(n_matches)
    display as text "  Lambda: " as result %8.6f r(lambda)
    timer list 1

    _linkage_metrics cluster_id_1a cluster
    local f1_1a = r(f1)

    * --- Run 1b: Mixed methods (JW + Levenshtein) ---
    display as text _n "  Run 1b: Mixed methods (JW + Lev), blocking on dob"

    timer clear 2
    timer on 2

    splink first_name surname city email, ///
        block(dob) gen(cluster_id_1b) thr(0.85) ///
        compmethod(jw lev jw jw) complevels("0.92,0.80|1,2|0.92,0.80|0.92,0.80") ///
        verbose

    timer off 2

    display as text "  Candidate pairs: " as result r(n_pairs)
    display as text "  Matches: " as result r(n_matches)
    timer list 2

    _linkage_metrics cluster_id_1b cluster
    local f1_1b = r(f1)

    * --- Run 1c: Multiple blocking rules (OR logic) ---
    display as text _n "  Run 1c: OR blocking (dob OR surname)"

    timer clear 3
    timer on 3

    splink first_name surname city email, ///
        block(dob) block2(surname) gen(cluster_id_1c) thr(0.85) verbose

    timer off 3

    display as text "  Candidate pairs: " as result r(n_pairs)
    display as text "  Matches: " as result r(n_matches)
    timer list 3

    _linkage_metrics cluster_id_1c cluster
    local f1_1c = r(f1)

    display as text _n "  Summary for fake_1000:"
    display as text "  Default JW, block dob:     F1 = " as result %6.3f `f1_1a'
    display as text "  Mixed methods, block dob:  F1 = " as result %6.3f `f1_1b'
    display as text "  OR blocking (dob|surname): F1 = " as result %6.3f `f1_1c'
}


/* ============================================================
   BENCHMARK 2: FEBRL3 (dedup, 5000 records, 2000 entities)
   Standard academic benchmark, no missing data
   ============================================================ */
display as text _n "{hline 60}"
display as text "BENCHMARK 2: FEBRL3 (dedup, 5000 records)"
display as text "{hline 60}"

capture confirm file "tests/splink_febrl3.csv"
if _rc != 0 {
    display as error "  SKIP: tests/splink_febrl3.csv not found"
    display as error "  Run: python3 tests/export_splink_datasets.py"
}
else {
    import delimited "tests/splink_febrl3.csv", clear

    display as text "  Records: " _N
    tempvar etag2
    bysort entity_id: gen byte `etag2' = (_n == 1)
    quietly count if `etag2'
    display as text "  True entities: " as result r(N)

    * Show sample
    list rec_id given_name surname date_of_birth entity_id in 1/5, sep(0)

    * --- Run 2a: Default, block on surname ---
    display as text _n "  Run 2a: Default, blocking on surname"

    timer clear 4
    timer on 4

    splink given_name date_of_birth suburb postcode, ///
        block(surname) gen(cluster_id_2a) thr(0.85) verbose

    timer off 4

    display as text "  Candidate pairs: " as result r(n_pairs)
    display as text "  Matches: " as result r(n_matches)
    display as text "  Lambda: " as result %8.6f r(lambda)
    timer list 4

    _linkage_metrics cluster_id_2a entity_id
    local f1_2a = r(f1)

    * --- Run 2b: Fine-grained thresholds (4 levels per field) ---
    display as text _n "  Run 2b: Fine-grained thresholds, blocking on surname"

    timer clear 5
    timer on 5

    splink given_name date_of_birth suburb postcode, ///
        block(surname) gen(cluster_id_2b) thr(0.85) ///
        complevels("0.95,0.88,0.80,0.70|0.95,0.88,0.80,0.70|0.95,0.88,0.80,0.70|0.95,0.88,0.80,0.70") ///
        verbose

    timer off 5

    display as text "  Candidate pairs: " as result r(n_pairs)
    display as text "  Matches: " as result r(n_matches)
    timer list 5

    _linkage_metrics cluster_id_2b entity_id
    local f1_2b = r(f1)

    * --- Run 2c: OR blocking (surname OR state) ---
    display as text _n "  Run 2c: OR blocking (surname OR state)"

    timer clear 6
    timer on 6

    splink given_name date_of_birth suburb postcode, ///
        block(surname) block2(state) gen(cluster_id_2c) thr(0.85) verbose

    timer off 6

    display as text "  Candidate pairs: " as result r(n_pairs)
    display as text "  Matches: " as result r(n_matches)
    timer list 6

    _linkage_metrics cluster_id_2c entity_id
    local f1_2c = r(f1)

    display as text _n "  Summary for FEBRL3:"
    display as text "  Default, surname:         F1 = " as result %6.3f `f1_2a'
    display as text "  Fine thresholds, surname: F1 = " as result %6.3f `f1_2b'
    display as text "  OR blocking (surname|st): F1 = " as result %6.3f `f1_2c'
}


/* ============================================================
   BENCHMARK 3: FEBRL4 (linking, 5000+5000 records)
   Tests cross-dataset linking with linkvar()
   ============================================================ */
display as text _n "{hline 60}"
display as text "BENCHMARK 3: FEBRL4 (linking, 10000 records)"
display as text "{hline 60}"

capture confirm file "tests/splink_febrl4_stacked.csv"
if _rc != 0 {
    display as error "  SKIP: tests/splink_febrl4_stacked.csv not found"
    display as error "  Run: python3 tests/export_splink_datasets.py"
}
else {
    import delimited "tests/splink_febrl4_stacked.csv", clear

    display as text "  Total records: " _N
    display as text "  Source 0: " as result _N / 2
    display as text "  Source 1: " as result _N / 2

    tempvar etag3
    bysort entity_id: gen byte `etag3' = (_n == 1)
    quietly count if `etag3'
    display as text "  True entities: " as result r(N)

    * --- Run 3a: Default linking ---
    display as text _n "  Run 3a: Default linking, block on surname"

    timer clear 7
    timer on 7

    splink given_name surname date_of_birth suburb, ///
        block(surname) gen(entity_link_3a) link(source) thr(0.85) verbose

    timer off 7

    display as text "  Candidate pairs: " as result r(n_pairs)
    display as text "  Matches: " as result r(n_matches)
    display as text "  Lambda: " as result %8.6f r(lambda)
    timer list 7

    _linkage_metrics entity_link_3a entity_id
    local f1_3a = r(f1)

    * --- Run 3b: Mixed methods + fine thresholds ---
    display as text _n "  Run 3b: Mixed methods + fine thresholds"

    timer clear 8
    timer on 8

    splink given_name surname date_of_birth suburb, ///
        block(surname) gen(entity_link_3b) link(source) thr(0.85) ///
        compmethod(jw jw jw jaccard) ///
        complevels("0.95,0.88,0.80|0.95,0.88,0.80|0.95,0.88,0.80|0.70,0.50") ///
        verbose

    timer off 8

    display as text "  Candidate pairs: " as result r(n_pairs)
    display as text "  Matches: " as result r(n_matches)
    timer list 8

    _linkage_metrics entity_link_3b entity_id
    local f1_3b = r(f1)

    display as text _n "  Summary for FEBRL4 (linking):"
    display as text "  Default:                  F1 = " as result %6.3f `f1_3a'
    display as text "  Mixed methods + fine thr: F1 = " as result %6.3f `f1_3b'
}


/* ============================================================
   SUMMARY
   ============================================================ */
display as text _n "{hline 60}"
display as text "BENCHMARK SUMMARY"
display as text "{hline 60}"
display as text ""
display as text "  Dataset            Config              F1"
display as text "  {hline 50}"
capture display as text ///
    "  fake_1000 (1K)     Default JW, dob     " as result %6.3f `f1_1a'
capture display as text ///
    "  fake_1000 (1K)     Mixed methods, dob  " as result %6.3f `f1_1b'
capture display as text ///
    "  fake_1000 (1K)     OR block dob|sur    " as result %6.3f `f1_1c'
capture display as text ///
    "  FEBRL3 (5K)        Default, surname    " as result %6.3f `f1_2a'
capture display as text ///
    "  FEBRL3 (5K)        Fine thresholds     " as result %6.3f `f1_2b'
capture display as text ///
    "  FEBRL3 (5K)        OR block sur|state  " as result %6.3f `f1_2c'
capture display as text ///
    "  FEBRL4 (10K link)  Default linking     " as result %6.3f `f1_3a'
capture display as text ///
    "  FEBRL4 (10K link)  Mixed + fine thr    " as result %6.3f `f1_3b'
display as text "  {hline 50}"
display as text ""
display as text "  v2 features tested: configurable comparison methods,"
display as text "  fine-grained thresholds, multiple blocking rules (OR),"
display as text "  and cross-dataset linking."
display as text "{hline 60}"
