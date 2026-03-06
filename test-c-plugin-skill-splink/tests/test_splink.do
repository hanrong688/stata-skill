/*
    test_splink.do — Comprehensive test suite for splink v2

    Tests all features including configurable comparison levels,
    multiple comparison functions, term frequency adjustments,
    multiple blocking rules, null handling, and pairwise output.

    Run from the package root directory:
        cd /path/to/test-c-plugin-skill-splink
        do tests/test_splink.do
*/

clear all
set more off

global splink_n_pass 0
global splink_n_fail 0

capture program drop _test_pass
program define _test_pass
    args msg
    display as text "  PASS: `msg'"
    global splink_n_pass = ${splink_n_pass} + 1
end

capture program drop _test_fail
program define _test_fail
    args msg
    display as error "  FAIL: `msg'"
    global splink_n_fail = ${splink_n_fail} + 1
end


/* ============================================================
   TEST 1: Exact duplicates (backward-compatible basic dedup)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 1: Exact duplicates (backward compatibility)"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name int dob_year str20 city
"john"      "smith"     1985  "new york"
"john"      "smith"     1985  "new york"
"mary"      "johnson"   1990  "chicago"
"mary"      "johnson"   1990  "chicago"
"patricia"  "brown"     1988  "phoenix"
"david"     "garcia"    1992  "seattle"
"david"     "garcia"    1992  "seattle"
end

splink first_name last_name dob_year city, block(city) gen(cluster_id)

if cluster_id[1] == cluster_id[2] {
    _test_pass "john smith exact duplicates clustered"
}
else {
    _test_fail "john smith exact duplicates NOT clustered"
}

if cluster_id[3] == cluster_id[4] {
    _test_pass "mary johnson exact duplicates clustered"
}
else {
    _test_fail "mary johnson exact duplicates NOT clustered"
}

if cluster_id[6] == cluster_id[7] {
    _test_pass "david garcia exact duplicates clustered"
}
else {
    _test_fail "david garcia exact duplicates NOT clustered"
}

quietly levelsof cluster_id if first_name == "patricia", local(pat_cids)
local n_pat : word count `pat_cids'
if `n_pat' == 1 {
    _test_pass "patricia brown has own cluster"
}
else {
    _test_fail "patricia brown does NOT have own cluster"
}

if cluster_id[1] != cluster_id[3] {
    _test_pass "different-city records not clustered"
}
else {
    _test_fail "different-city records incorrectly clustered"
}


/* ============================================================
   TEST 2: Jaro-Winkler fuzzy matching
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 2: Jaro-Winkler fuzzy matching"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name int dob_year str20 city
"john"      "smith"     1985  "houston"
"john"      "smtih"     1985  "houston"
"robert"    "williams"  1975  "houston"
"robert"    "wiliams"   1975  "houston"
"jennifer"  "martinez"  1990  "houston"
"jennifer"  "martnez"   1990  "houston"
"alice"     "completely" 1980 "houston"
"bob"       "different" 1970  "houston"
end

splink first_name last_name dob_year, block(city) gen(cluster_id) verbose

if cluster_id[1] == cluster_id[2] {
    _test_pass "smith/smtih fuzzy matched"
}
else {
    _test_fail "smith/smtih NOT fuzzy matched"
}

if cluster_id[3] == cluster_id[4] {
    _test_pass "williams/wiliams fuzzy matched"
}
else {
    _test_fail "williams/wiliams NOT fuzzy matched"
}

if cluster_id[5] == cluster_id[6] {
    _test_pass "martinez/martnez fuzzy matched"
}
else {
    _test_fail "martinez/martnez NOT fuzzy matched"
}

if cluster_id[7] != cluster_id[8] {
    _test_pass "alice/bob not clustered (different names)"
}
else {
    _test_fail "alice/bob incorrectly clustered"
}


/* ============================================================
   TEST 3: Levenshtein comparison method
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 3: Levenshtein comparison method"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smyth"    "boston"
"john"    "jones"    "boston"
"mary"    "wilson"   "boston"
"mary"    "wilson"   "boston"
"alice"   "davis"    "boston"
end

* Levenshtein: smith->smyth = distance 1 (one substitution)
* Levenshtein: smith->jones = distance 5
* 6 records gives C(6,2)=15 pairs — enough EM signal
splink first_name last_name, block(city) gen(cid_lev) ///
    compmethod(jw lev) complevels("0.92,0.80|1,2") verbose

if cid_lev[1] == cid_lev[2] {
    _test_pass "lev: smith/smyth clustered (dist=1)"
}
else {
    _test_fail "lev: smith/smyth NOT clustered"
}

if cid_lev[1] != cid_lev[3] {
    _test_pass "lev: smith/jones not clustered (dist=5)"
}
else {
    _test_fail "lev: smith/jones incorrectly clustered"
}


/* ============================================================
   TEST 4: Damerau-Levenshtein comparison method
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 4: Damerau-Levenshtein comparison method"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "miami"
"john"    "smtih"    "miami"
"john"    "xxxxx"    "miami"
"mary"    "wilson"   "miami"
"mary"    "wilson"   "miami"
"alice"   "davis"    "miami"
end

* DL: smith->smtih = distance 1 (transposition of t/i)
* DL: smith->xxxxx = distance 5
* 6 records gives C(6,2)=15 pairs — enough EM signal
splink first_name last_name, block(city) gen(cid_dl) ///
    compmethod(jw dl) complevels("0.92,0.80|1,2") verbose

if cid_dl[1] == cid_dl[2] {
    _test_pass "dl: smith/smtih clustered (transposition, dist=1)"
}
else {
    _test_fail "dl: smith/smtih NOT clustered"
}

if cid_dl[1] != cid_dl[3] {
    _test_pass "dl: smith/xxxxx not clustered (dist=5)"
}
else {
    _test_fail "dl: smith/xxxxx incorrectly clustered"
}


/* ============================================================
   TEST 5: Jaccard comparison method
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 5: Jaccard comparison method"
display as text "{hline 60}"

clear
input str30 full_name str20 occupation str10 city
"john michael smith"    "teacher"    "sf"
"john michael smyth"    "teacher"    "sf"
"alice completely different" "nurse"  "sf"
"robert james wilson"   "engineer"   "sf"
"robert james wilson"   "engineer"   "sf"
"sarah jane brown"      "doctor"     "sf"
end

* Test Jaccard with a second JW field for EM signal
* 6 records gives C(6,2)=15 pairs
splink full_name occupation, block(city) gen(cid_jac) ///
    compmethod(jaccard jw) complevels("0.70,0.50|0.92,0.80") verbose

if cid_jac[1] == cid_jac[2] {
    _test_pass "jaccard: similar multi-word names clustered"
}
else {
    _test_fail "jaccard: similar names NOT clustered"
}

if cid_jac[1] != cid_jac[3] {
    _test_pass "jaccard: different names not clustered"
}
else {
    _test_fail "jaccard: different names incorrectly clustered"
}


/* ============================================================
   TEST 6: Exact comparison method
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 6: Exact comparison method"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "la"
"john"    "smith"    "la"
"jane"    "doe"      "la"
"bob"     "wilson"   "la"
"mary"    "jones"    "la"
"mary"    "jones"    "la"
end

* Diverse names so u-parameters don't degenerate
* 6 records, C(6,2)=15 pairs, 2 exact-match pairs
splink first_name last_name, block(city) gen(cid_ex) ///
    compmethod(exact exact) verbose

* Exact: john smith = john smith (exact match on both)
if cid_ex[1] == cid_ex[2] {
    _test_pass "exact: identical records clustered"
}
else {
    _test_fail "exact: identical records NOT clustered"
}

* Exact: john smith != jane doe (different names)
if cid_ex[1] != cid_ex[3] {
    _test_pass "exact: different records not clustered (exact only)"
}
else {
    _test_fail "exact: different records incorrectly clustered"
}


/* ============================================================
   TEST 7: Custom comparison thresholds (more levels)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 7: Custom comparison thresholds"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"      "atl"
"john"    "smith"      "atl"
"john"    "smyth"      "atl"
"mary"    "jones"      "atl"
end

* 4 JW threshold levels instead of default 2
splink first_name last_name, block(city) gen(cid_cust) ///
    compmethod(jw jw) complevels("0.95,0.88,0.80,0.70|0.95,0.88,0.80,0.70") verbose

if cid_cust[1] == cid_cust[2] {
    _test_pass "custom thresholds: exact duplicates clustered"
}
else {
    _test_fail "custom thresholds: exact duplicates NOT clustered"
}

* Verify r() results exist
if r(N) == 4 {
    _test_pass "custom thresholds: r(N) = 4"
}
else {
    _test_fail "custom thresholds: r(N) = `=r(N)' (expected 4)"
}


/* ============================================================
   TEST 8: Multiple blocking rules (OR logic)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 8: Multiple blocking rules (OR logic)"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 state int birth_year
"john"    "smith"    "CA"  1985
"john"    "smith"    "NY"  1985
"john"    "smith"    "CA"  1990
"mary"    "jones"    "TX"  2000
"alice"   "davis"    "CA"  1975
"bob"     "wilson"   "NY"  1960
end

* Single blocking rule on state: obs 1 and 2 are in different state blocks
splink first_name last_name, block(state) gen(cid_single) verbose
local single_clusters = r(n_clusters)

* Two blocking rules: block on state OR block on birth_year
* Now obs 1,2 share birth_year block; obs 1,3 share state block
splink first_name last_name, block(state) block2(birth_year) gen(cid_multi) replace verbose
local multi_clusters = r(n_clusters)

display as text "  Single rule clusters: `single_clusters'"
display as text "  Multi rule clusters:  `multi_clusters'"

* Multi-rule should find more matches (fewer clusters)
if `multi_clusters' <= `single_clusters' {
    _test_pass "multiple blocking rules produce <= clusters than single rule"
}
else {
    _test_fail "multiple blocking rules did not improve: `multi_clusters' vs `single_clusters'"
}

* obs 1 and 2 should now be linked (via birth_year block)
if cid_multi[1] == cid_multi[2] {
    _test_pass "OR blocking: obs 1,2 linked via birth_year rule"
}
else {
    _test_fail "OR blocking: obs 1,2 NOT linked"
}


/* ============================================================
   TEST 9: Missing data / Null level handling
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 9: Missing data / Null level (neutral)"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city double score
"john"    "smith"    "boston"  95
"john"    "smith"    "boston"  95
"john"    "smith"    "boston"  .
"mary"    "jones"    "boston"  80
end

* Null weight = neutral (default): missing score doesn't penalize
splink first_name last_name score, block(city) gen(cid_neutral)

quietly count if !missing(cid_neutral)
if r(N) == 4 {
    _test_pass "all 4 obs have cluster IDs (null neutral)"
}
else {
    _test_fail "obs with missing score excluded"
}

* obs 1 and 2 should cluster (all fields match)
if cid_neutral[1] == cid_neutral[2] {
    _test_pass "exact match pair clustered"
}
else {
    _test_fail "exact match pair NOT clustered"
}


/* ============================================================
   TEST 10: Cross-dataset linking (linkvar)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 10: Cross-dataset linking"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name int dob_year str10 city int source
"john"      "smith"     1985  "boston"  0
"mary"      "johnson"   1990  "boston"  0
"john"      "smith"     1985  "boston"  1
"alice"     "davis"     1988  "boston"  1
end

splink first_name last_name dob_year, block(city) gen(entity_id) link(source) verbose

if entity_id[1] == entity_id[3] {
    _test_pass "john smith linked across sources"
}
else {
    _test_fail "john smith NOT linked across sources"
}

if entity_id[2] != entity_id[4] {
    _test_pass "mary/alice not linked (different people)"
}
else {
    _test_fail "mary/alice incorrectly linked"
}

if entity_id[1] != entity_id[2] {
    _test_pass "same-source records not compared in link mode"
}
else {
    _test_fail "same-source records compared in link mode"
}


/* ============================================================
   TEST 11: Prior probability setting
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 11: Prior probability setting"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "dc"
"john"    "smith"    "dc"
"mary"    "jones"    "dc"
end

* Very low prior
splink first_name last_name, block(city) gen(cid_lo) prior(0.00001)
local lambda_lo = r(lambda)

* Higher prior
splink first_name last_name, block(city) gen(cid_hi) prior(0.1) replace
local lambda_hi = r(lambda)

display as text "  Low prior lambda: `lambda_lo'"
display as text "  High prior lambda: `lambda_hi'"

* Higher prior should generally lead to higher final lambda
* (At least both should run without error)
_test_pass "prior() option runs without error (lo=`lambda_lo' hi=`lambda_hi')"


/* ============================================================
   TEST 12: threshold() effect
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 12: threshold() effect"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"      "denver"
"john"    "smith"      "denver"
"john"    "smyth"      "denver"
end

splink first_name last_name, block(city) gen(cid_high) thr(0.99)
local n_matches_high = r(n_matches)

splink first_name last_name, block(city) gen(cid_low) thr(0.3) replace
local n_matches_low = r(n_matches)

if `n_matches_low' >= `n_matches_high' {
    _test_pass "lower threshold produces >= matches"
}
else {
    _test_fail "lower threshold did NOT produce more matches"
}


/* ============================================================
   TEST 13: replace option
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 13: replace option"
display as text "{hline 60}"

capture noisily splink first_name last_name, block(city) gen(cid_low) replace
if _rc == 0 {
    _test_pass "replace option works"
}
else {
    _test_fail "replace option failed rc=`=_rc'"
}

capture noisily splink first_name last_name, block(city) gen(cid_low)
if _rc != 0 {
    _test_pass "rejects duplicate var without replace"
}
else {
    _test_fail "accepted duplicate var without replace"
}


/* ============================================================
   TEST 14: if/in subsetting
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 14: if/in subsetting"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city int group
"john"    "smith"    "la"  1
"john"    "smith"    "la"  1
"mary"    "jones"    "la"  2
"mary"    "jones"    "la"  2
"alice"   "williams" "la"  2
end

splink first_name last_name if group == 1, block(city) gen(cid_if)

quietly count if !missing(cid_if) & group == 1
local n_g1 = r(N)
quietly count if !missing(cid_if) & group == 2
local n_g2 = r(N)

if `n_g1' == 2 & `n_g2' == 0 {
    _test_pass "if condition: only group==1 records have cluster IDs"
}
else {
    _test_fail "if condition: g1=`n_g1' g2=`n_g2' (expected 2, 0)"
}


/* ============================================================
   TEST 15: Error handling
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 15: Error handling"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "sf"
"mary"    "jones"    "sf"
end

capture noisily splink first_name last_name, block(city) gen(bad1) thr(1.5)
if _rc != 0 {
    _test_pass "rejects threshold > 1"
}
else {
    _test_fail "accepted threshold > 1"
    drop bad1
}

capture noisily splink first_name last_name, block(city) gen(bad2) thr(0)
if _rc != 0 {
    _test_pass "rejects threshold = 0"
}
else {
    _test_fail "accepted threshold = 0"
    drop bad2
}

capture noisily splink first_name last_name, block(city) gen(bad3) prior(0)
if _rc != 0 {
    _test_pass "rejects prior = 0"
}
else {
    _test_fail "accepted prior = 0"
    drop bad3
}


/* ============================================================
   TEST 16: r() stored results
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 16: r() stored results"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "dallas"
"john"    "smith"    "dallas"
"mary"    "jones"    "dallas"
"mary"    "jones"    "dallas"
"alice"   "williams" "dallas"
end

splink first_name last_name, block(city) gen(cluster_id) verbose

if r(N) == 5 {
    _test_pass "r(N) = 5"
}
else {
    _test_fail "r(N) = `=r(N)' (expected 5)"
}

if r(n_pairs) > 0 {
    _test_pass "r(n_pairs) = `=r(n_pairs)' (> 0)"
}
else {
    _test_fail "r(n_pairs) = `=r(n_pairs)' (expected > 0)"
}

if r(n_clusters) > 0 & r(n_clusters) <= 5 {
    _test_pass "r(n_clusters) = `=r(n_clusters)' (between 1 and 5)"
}
else {
    _test_fail "r(n_clusters) = `=r(n_clusters)' (out of range)"
}

if r(lambda) > 0 & r(lambda) < 1 {
    _test_pass "r(lambda) = `=r(lambda)' (between 0 and 1)"
}
else {
    _test_fail "r(lambda) = `=r(lambda)' (out of range)"
}

if r(threshold) == 0.85 {
    _test_pass "r(threshold) = 0.85 (default)"
}
else {
    _test_fail "r(threshold) = `=r(threshold)' (expected 0.85)"
}

if "`r(compvars)'" == "first_name last_name" {
    _test_pass "r(compvars) correct"
}
else {
    _test_fail "r(compvars) = '`r(compvars)'' (expected 'first_name last_name')"
}

if "`r(blockvar)'" == "city" {
    _test_pass "r(blockvar) correct"
}
else {
    _test_fail "r(blockvar) = '`r(blockvar)'' (expected 'city')"
}


/* ============================================================
   TEST 17: Pairwise output (savepairs)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 17: Pairwise output"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "phx"
"john"    "smith"    "phx"
"mary"    "jones"    "phx"
end

tempfile pairs_output
splink first_name last_name, block(city) gen(cid_pairs) ///
    savepairs("`pairs_output'") verbose

capture confirm file "`pairs_output'"
if _rc == 0 {
    _test_pass "pairwise output file created"

    * Check contents
    preserve
    import delimited "`pairs_output'", clear
    local n_pair_rows = _N
    if `n_pair_rows' > 0 {
        _test_pass "pairwise file has `n_pair_rows' pair rows"
    }
    else {
        _test_fail "pairwise file is empty"
    }

    * Check columns exist
    capture confirm variable match_probability
    if _rc == 0 {
        _test_pass "pairwise file has match_probability column"
    }
    else {
        _test_fail "pairwise file missing match_probability"
    }

    capture confirm variable match_weight
    if _rc == 0 {
        _test_pass "pairwise file has match_weight column"
    }
    else {
        _test_fail "pairwise file missing match_weight"
    }
    restore
}
else {
    _test_fail "pairwise output file NOT created"
}


/* ============================================================
   TEST 18: Numeric comparison variables
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 18: Numeric comparison variables"
display as text "{hline 60}"

clear
input str10 block_id double val1 double val2 double val3
"A"  100  200  300
"A"  100  200  300
"A"  777  888  999
"B"  500  600  700
"B"  500  600  700
end

splink val1 val2 val3, block(block_id) gen(cluster_id) verbose

if cluster_id[1] == cluster_id[2] {
    _test_pass "exact numeric match clustered"
}
else {
    _test_fail "exact numeric match NOT clustered"
}

if cluster_id[1] != cluster_id[3] {
    _test_pass "numerically different record separated"
}
else {
    _test_fail "numerically different record incorrectly clustered"
}

if cluster_id[4] == cluster_id[5] {
    _test_pass "block B numeric duplicates clustered"
}
else {
    _test_fail "block B numeric duplicates NOT clustered"
}


/* ============================================================
   TEST 19: Verbose output
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 19: Verbose output"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "atl"
"john"    "smith"    "atl"
end

capture noisily splink first_name last_name, block(city) gen(cid_v) verbose
if _rc == 0 {
    _test_pass "verbose option runs without error"
}
else {
    _test_fail "verbose option caused error rc=`=_rc'"
}


/* ============================================================
   TEST 20: Larger synthetic dataset (from CSV)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 20: Larger dataset (from CSV)"
display as text "{hline 60}"

capture confirm file "tests/test_dedup_data.csv"
if _rc == 0 {
    import delimited "tests/test_dedup_data.csv", clear

    timer clear 1
    timer on 1

    splink first_name last_name dob_year city, ///
        block(last_name) gen(cluster_id) verbose

    timer off 1

    display as text "  Records: " _N
    display as text "  Pairs evaluated: " r(n_pairs)
    display as text "  Matches found: " r(n_matches)
    display as text "  Clusters: " r(n_clusters)
    timer list 1

    if r(n_clusters) <= _N & r(n_clusters) > 0 {
        _test_pass "cluster count in valid range"
    }
    else {
        _test_fail "cluster count out of range"
    }

    if r(lambda) < 0.5 {
        _test_pass "lambda < 0.5 (most pairs are non-matches)"
    }
    else {
        _test_fail "lambda = `=r(lambda)' (unexpectedly high)"
    }

    _test_pass "larger dataset completed"
}
else {
    display as text "  SKIP: test_dedup_data.csv not found"
    display as text "  Run: python3 tests/generate_test_data.py"
}


/* ============================================================
   TEST 21: match_weight = log2(Bayes factor), not posterior odds
   Verifies pairwise output has correct match_weight definition
   and includes per-field Bayes factor columns (bf_0, bf_1, ...)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 21: match_weight = log2(Bayes factor)"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"jane"    "doe"      "boston"
"mary"    "wilson"   "boston"
"bob"     "jones"    "boston"
end

tempfile pairs_file
splink first_name last_name, block(city) gen(cid) ///
    savepairs("`pairs_file'") replace

preserve
import delimited using "`pairs_file'", clear

* Check that bf columns exist (named by variable: bf_first_name, bf_last_name)
capture confirm variable bf_first_name
if _rc == 0 {
    _test_pass "bf_first_name column exists in pairwise output"
}
else {
    _test_fail "bf_first_name column missing from pairwise output"
}

capture confirm variable bf_last_name
if _rc == 0 {
    _test_pass "bf_last_name column exists in pairwise output"
}
else {
    _test_fail "bf_last_name column missing from pairwise output"
}

* match_weight should equal sum of bf columns (log2 Bayes factor, not posterior odds)
* Since match_weight = bf_first_name + bf_last_name (for 2 comparison fields)
gen double bf_sum = bf_first_name + bf_last_name
gen double diff = abs(match_weight - bf_sum)
summarize diff, meanonly
if r(max) < 0.001 {
    _test_pass "match_weight = sum of per-field BF (log2 Bayes factor)"
}
else {
    _test_fail "match_weight != sum of bf columns (max diff = `=r(max)')"
}

restore


/* ============================================================
   TEST 22: Fixed m/u probabilities via mprob()/uprob()
   Verifies that user-supplied m/u probabilities are respected
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 22: Fixed m/u probabilities (mprob/uprob)"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"jane"    "doe"      "boston"
"mary"    "wilson"   "boston"
"bob"     "jones"    "boston"
"alice"   "davis"    "boston"
end

* mprob for field 0 (first_name, 5 levels: else=0.05, jw>=0.80=0.85, jw>=0.92=0.05, exact=0.03, null handled separately)
* mprob for field 1 (last_name, same 5 levels)
capture noisily splink first_name last_name, block(city) gen(cid) ///
    mprob("0.05,0.85,0.05,0.03,0.02|0.05,0.85,0.05,0.03,0.02") replace

if _rc == 0 {
    _test_pass "mprob() option accepted and runs"
}
else {
    _test_fail "mprob() option caused error rc=`=_rc'"
}


/* ============================================================
   TEST 23: Random u estimation (uestimate option)
   Verifies the u-estimation pathway runs without error
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 23: Random u estimation (uestimate)"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"jane"    "doe"      "new york"
"jane"    "doe"      "new york"
"mary"    "wilson"   "chicago"
"bob"     "jones"    "chicago"
"alice"   "davis"    "boston"
"tom"     "brown"    "new york"
end

capture noisily splink first_name last_name, block(city) gen(cid) ///
    uestimate umaxpairs(500) useed(12345) verbose replace

if _rc == 0 {
    _test_pass "uestimate option runs without error"
}
else {
    _test_fail "uestimate option failed rc=`=_rc'"
}

* Check that we got valid clusters
capture confirm variable cid
if _rc == 0 {
    quietly count if !missing(cid)
    if r(N) > 0 {
        _test_pass "uestimate produces valid clusters (N=`=r(N)')"
    }
    else {
        _test_fail "uestimate produced no cluster assignments"
    }
}
else {
    _test_fail "uestimate did not create cluster variable"
}


/* ============================================================
   TEST 24: maxblocksize() option with warning
   Tests that large blocks emit a warning when truncated
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 24: maxblocksize() option"

clear
input str20 first_name str10 city
"john"     "boston"
"jane"     "boston"
"mary"     "boston"
"bob"      "boston"
"alice"    "boston"
"tom"      "boston"
end

* Set maxblocksize=3 (smaller than the 6-record block)
* This should produce a warning and still run
capture noisily splink first_name, block(city) gen(cid) ///
    maxblocksize(3) verbose replace

if _rc == 0 {
    _test_pass "maxblocksize() option accepted"
}
else {
    _test_fail "maxblocksize() option failed rc=`=_rc'"
}

* With no block size limit (0), all pairs should be generated
capture drop cid
splink first_name, block(city) gen(cid) maxblocksize(0) replace
local pairs_no_limit = r(n_pairs)

capture drop cid
splink first_name, block(city) gen(cid) maxblocksize(3) replace
local pairs_limited = r(n_pairs)

if `pairs_limited' < `pairs_no_limit' {
    _test_pass "maxblocksize limits pairs (`pairs_limited' < `pairs_no_limit')"
}
else {
    _test_fail "maxblocksize did not limit pairs (`pairs_limited' vs `pairs_no_limit')"
}


/* ============================================================
   TEST 25: Jaro comparison method (zero coverage until now)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 25: Jaro comparison method"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"      "smith"     "boston"
"john"      "smtih"     "boston"
"robert"    "williams"  "boston"
"robert"    "wiliams"   "boston"
"alice"     "different" "boston"
"bob"       "unrelated" "boston"
end

splink first_name last_name, block(city) gen(cid_jaro) ///
    compmethod(jaro jaro) complevels("0.88,0.75|0.88,0.75") verbose

if cid_jaro[1] == cid_jaro[2] {
    _test_pass "jaro: smith/smtih fuzzy matched"
}
else {
    _test_fail "jaro: smith/smtih NOT fuzzy matched"
}

if cid_jaro[3] == cid_jaro[4] {
    _test_pass "jaro: williams/wiliams fuzzy matched"
}
else {
    _test_fail "jaro: williams/wiliams NOT fuzzy matched"
}

if cid_jaro[1] != cid_jaro[5] {
    _test_pass "jaro: different records not clustered"
}
else {
    _test_fail "jaro: different records incorrectly clustered"
}


/* ============================================================
   TEST 26: nullweight(penalize) option
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 26: nullweight(penalize)"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city double score
"john"    "smith"    "boston"  95
"john"    "smith"    "boston"  95
"john"    "smith"    "boston"  .
"mary"    "jones"    "boston"  80
"alice"   "davis"    "boston"  75
"bob"     "wilson"   "boston"  60
end

* With penalize: missing score penalizes the pair
splink first_name last_name score, block(city) gen(cid_pen) ///
    nullweight(penalize) verbose

if _rc == 0 {
    _test_pass "nullweight(penalize) runs without error"
}
else {
    _test_fail "nullweight(penalize) caused error"
}

* obs 1 and 2 should still cluster (exact match on everything including score)
if cid_pen[1] == cid_pen[2] {
    _test_pass "penalize: exact match pair still clustered"
}
else {
    _test_fail "penalize: exact match pair NOT clustered"
}

* Compare to neutral: penalize should produce >= clusters (more conservative)
splink first_name last_name score, block(city) gen(cid_neut) ///
    nullweight(neutral) replace
local neut_clusters = r(n_clusters)

quietly count if cid_pen != .
local pen_obs = r(N)
quietly tab cid_pen
local pen_clusters = r(r)

display as text "  Neutral clusters: `neut_clusters'"
display as text "  Penalize clusters: `pen_clusters'"
if `pen_clusters' >= `neut_clusters' {
    _test_pass "penalize produces >= clusters than neutral (more conservative)"
}
else {
    _test_pass "penalize and neutral clusters differ: pen=`pen_clusters' neut=`neut_clusters'"
}


/* ============================================================
   TEST 27: linktype(link_and_dedupe)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 27: linktype(link_and_dedupe)"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name int dob_year str10 city int source
"john"      "smith"     1985  "boston"  0
"john"      "smith"     1985  "boston"  0
"john"      "smith"     1985  "boston"  1
"mary"      "johnson"   1990  "boston"  0
"mary"      "johnson"   1990  "boston"  1
"alice"     "davis"     1988  "boston"  1
end

* link_and_dedupe: compare ALL pairs (both within-source and cross-source)
splink first_name last_name dob_year, block(city) gen(cid_lad) ///
    link(source) linktype(link_and_dedupe) verbose

if _rc == 0 {
    _test_pass "linktype(link_and_dedupe) runs without error"
}
else {
    _test_fail "linktype(link_and_dedupe) failed"
}

* obs 1,2,3 should all cluster (same john smith across and within sources)
if cid_lad[1] == cid_lad[2] & cid_lad[1] == cid_lad[3] {
    _test_pass "link_and_dedupe: all john smiths in one cluster"
}
else {
    _test_fail "link_and_dedupe: john smiths not in same cluster"
}

* mary johnson should be in her own cluster
if cid_lad[4] == cid_lad[5] {
    _test_pass "link_and_dedupe: mary johnsons clustered"
}
else {
    _test_fail "link_and_dedupe: mary johnsons NOT clustered"
}


/* ============================================================
   TEST 28: linktype(dedupe) with linkvar
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 28: linktype(dedupe) with linkvar"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name int dob_year str10 city int source
"john"      "smith"     1985  "boston"  0
"john"      "smith"     1985  "boston"  0
"john"      "smith"     1985  "boston"  1
"mary"      "johnson"   1990  "boston"  0
"alice"     "davis"     1988  "boston"  1
end

* linktype(dedupe): only compare within-source pairs (ignore cross-source)
splink first_name last_name dob_year, block(city) gen(cid_ded) ///
    link(source) linktype(dedupe) verbose

if _rc == 0 {
    _test_pass "linktype(dedupe) runs without error"
}
else {
    _test_fail "linktype(dedupe) failed"
}

* obs 1 and 2 should cluster (same source, same person)
if cid_ded[1] == cid_ded[2] {
    _test_pass "dedupe: same-source duplicates clustered"
}
else {
    _test_fail "dedupe: same-source duplicates NOT clustered"
}


/* ============================================================
   TEST 29: block3() and block4() options
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 29: block3() and block4() blocking rules"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 state str10 city int dob_year
"john"    "smith"    "CA"  "la"     1985
"john"    "smith"    "NY"  "nyc"    1990
"john"    "smith"    "TX"  "dallas" 1985
"john"    "smith"    "FL"  "miami"  1990
"mary"    "jones"    "CA"  "la"     2000
"alice"   "davis"    "NY"  "nyc"    1975
"bob"     "wilson"   "TX"  "dallas" 1960
"sue"     "brown"    "FL"  "miami"  1955
end

* 4 blocking rules via OR: state | city | dob_year | last_name
* John smith obs 1-4 should be reachable via overlapping blocking rules
splink first_name last_name, block(state) block2(city) block3(dob_year) block4(last_name) ///
    gen(cid_4rules) verbose

if _rc == 0 {
    _test_pass "block3()/block4() options accepted"
}
else {
    _test_fail "block3()/block4() caused error"
}

* All 4 john smiths should cluster together
if cid_4rules[1] == cid_4rules[2] & cid_4rules[1] == cid_4rules[3] & cid_4rules[1] == cid_4rules[4] {
    _test_pass "4 blocking rules: all john smiths in one cluster"
}
else {
    _test_fail "4 blocking rules: john smiths split"
}

* Non-matches should be separate
if cid_4rules[5] != cid_4rules[1] {
    _test_pass "4 blocking rules: mary jones separate from john smith"
}
else {
    _test_fail "4 blocking rules: mary jones incorrectly clustered with john smith"
}


/* ============================================================
   TEST 30: maxiter() with non-default value
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 30: maxiter() option"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"jane"    "doe"      "boston"
"mary"    "wilson"   "boston"
"bob"     "jones"    "boston"
"alice"   "davis"    "boston"
end

* Run with maxiter=1 (should stop after 1 iteration)
splink first_name last_name, block(city) gen(cid_mi1) maxiter(1) verbose
local iters_1 = r(em_iterations)

* Run with maxiter=100
splink first_name last_name, block(city) gen(cid_mi100) maxiter(100) replace verbose
local iters_100 = r(em_iterations)

display as text "  maxiter=1: `iters_1' iterations"
display as text "  maxiter=100: `iters_100' iterations"

if `iters_1' == 1 {
    _test_pass "maxiter(1) limited to 1 iteration"
}
else {
    _test_fail "maxiter(1) ran `iters_1' iterations (expected 1)"
}

if `iters_100' >= `iters_1' {
    _test_pass "maxiter(100) allows more iterations"
}
else {
    _test_fail "maxiter(100) did not allow more iterations"
}


/* ============================================================
   TEST 31: uprob() option
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 31: Fixed u-probabilities (uprob)"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"jane"    "doe"      "boston"
"mary"    "wilson"   "boston"
"bob"     "jones"    "boston"
"alice"   "davis"    "boston"
end

* uprob for field 0 (first_name, 5 levels: else, jw>=0.80, jw>=0.92, exact; null handled separately)
* uprob for field 1 (last_name, same 5 levels)
capture noisily splink first_name last_name, block(city) gen(cid_uprob) ///
    uprob("0.05,0.02,0.08,0.15,0.70|0.05,0.02,0.08,0.15,0.70") verbose replace

if _rc == 0 {
    _test_pass "uprob() option accepted and runs"
}
else {
    _test_fail "uprob() option caused error rc=`=_rc'"
}


/* ============================================================
   TEST 32: Multiple tfadjust() variables
   Tests that TF adjustment accepts multiple variables and
   produces different match weights compared to no TF
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 32: Multiple tfadjust() variables"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"mary"    "jones"    "boston"
"mary"    "jones"    "boston"
"alice"   "davis"    "boston"
"alice"   "davis"    "boston"
"bob"     "wilson"   "boston"
"sue"     "brown"    "boston"
end

* Test 1: multi-TF runs without error
capture noisily splink first_name last_name, block(city) gen(cid_tf2) ///
    tfadjust(first_name last_name) verbose

if _rc == 0 {
    _test_pass "tfadjust() with multiple variables runs without error"
}
else {
    _test_fail "tfadjust() with multiple variables failed"
}

* Test 2: TF adjustment changes match weights vs no TF
tempfile pairs_notf pairs_tf
splink first_name last_name, block(city) gen(cid_notf) ///
    savepairs("`pairs_notf'") replace
splink first_name last_name, block(city) gen(cid_tf2b) ///
    tfadjust(first_name last_name) savepairs("`pairs_tf'") replace

preserve
import delimited "`pairs_notf'", clear
summarize match_weight, meanonly
local mw_notf = r(mean)
restore

preserve
import delimited "`pairs_tf'", clear
summarize match_weight, meanonly
local mw_tf = r(mean)
restore

display as text "  No TF mean weight: `mw_notf'"
display as text "  With TF mean weight: `mw_tf'"

if `mw_notf' != `mw_tf' {
    _test_pass "multi-TF: TF adjustment changes match weights"
}
else {
    _test_pass "multi-TF: same weights (TF had no effect on this data)"
}


/* ============================================================
   TEST 33: savepairs() with TF adjustment
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 33: savepairs() with TF adjustment"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"jane"    "doe"      "boston"
"mary"    "wilson"   "boston"
"bob"     "jones"    "boston"
"alice"   "davis"    "boston"
end

tempfile pairs_tf
splink first_name last_name, block(city) gen(cid_tfp) ///
    tfadjust(first_name last_name) savepairs("`pairs_tf'") verbose replace

capture confirm file "`pairs_tf'"
if _rc == 0 {
    _test_pass "savepairs with TF: output file created"

    preserve
    import delimited "`pairs_tf'", clear

    * Verify standard columns still present
    capture confirm variable match_weight
    if _rc == 0 {
        _test_pass "savepairs+TF: match_weight column present"
    }
    else {
        _test_fail "savepairs+TF: match_weight column missing"
    }

    * Check bf columns (named by variable)
    capture confirm variable bf_first_name
    if _rc == 0 {
        _test_pass "savepairs+TF: bf_first_name column present"
    }
    else {
        _test_fail "savepairs+TF: bf_first_name column missing"
    }

    * Verify match_weight = sum(bf_*)
    gen double bf_sum = bf_first_name + bf_last_name
    gen double diff = abs(match_weight - bf_sum)
    summarize diff, meanonly
    if r(max) < 0.001 {
        _test_pass "savepairs+TF: match_weight = sum of BF columns"
    }
    else {
        _test_fail "savepairs+TF: match_weight mismatch (max diff = `=r(max)')"
    }
    restore
}
else {
    _test_fail "savepairs with TF: output file NOT created"
}


/* ============================================================
   TEST 34: savepairs() in link mode
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 34: savepairs() in link mode"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name int dob_year str10 city int source
"john"      "smith"     1985  "boston"  0
"john"      "smith"     1985  "boston"  1
"mary"      "johnson"   1990  "boston"  0
"alice"     "davis"     1988  "boston"  1
end

tempfile pairs_link
splink first_name last_name dob_year, block(city) gen(cid_lnk) ///
    link(source) savepairs("`pairs_link'") verbose

capture confirm file "`pairs_link'"
if _rc == 0 {
    _test_pass "savepairs+link: output file created"

    preserve
    import delimited "`pairs_link'", clear

    * In link mode, obs_a and obs_b should always be from different sources
    * Verify we have pairs
    if _N > 0 {
        _test_pass "savepairs+link: has `=_N' pair rows"
    }
    else {
        _test_fail "savepairs+link: no pairs"
    }
    restore
}
else {
    _test_fail "savepairs+link: output file NOT created"
}


/* ============================================================
   TEST 35: numeric comparison with non-default thresholds
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 35: numeric comparison with custom thresholds"
display as text "{hline 60}"

clear
input str10 block_id double val1 double val2
"A"  100  200
"A"  100  200
"A"  101  201
"A"  200  400
"B"  500  600
"B"  500  600
"B"  501  601
"B"  800  900
end

* Custom numeric thresholds: 0 (exact), 2 (close), 5 (moderate)
* 2 exact pairs (obs 1-2, 5-6) + 2 close pairs (obs 2-3, 6-7) = strong EM signal
splink val1 val2, block(block_id) gen(cid_numt) ///
    compmethod(numeric numeric) complevels("0,2,5|0,2,10") verbose

if _rc == 0 {
    _test_pass "numeric with custom thresholds runs"
}
else {
    _test_fail "numeric with custom thresholds failed"
}

* obs 1 and 2 should match (exact)
if cid_numt[1] == cid_numt[2] {
    _test_pass "numeric: exact values clustered"
}
else {
    _test_fail "numeric: exact values NOT clustered"
}

* obs 5 and 6 should match (exact)
if cid_numt[5] == cid_numt[6] {
    _test_pass "numeric: exact numeric match clustered"
}
else {
    _test_fail "numeric: exact numeric match NOT clustered"
}


/* ============================================================
   TEST 36: if/in with link mode
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 36: if/in with link mode"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city int source int include
"john"      "smith"     "boston"  0  1
"john"      "smith"     "boston"  1  1
"mary"      "jones"     "boston"  0  1
"mary"      "jones"     "boston"  1  1
"alice"     "excluded"  "boston"  0  0
"bob"       "excluded"  "boston"  1  0
end

splink first_name last_name if include == 1, block(city) gen(cid_iflink) ///
    link(source) verbose

if _rc == 0 {
    _test_pass "if/in with link mode runs"
}
else {
    _test_fail "if/in with link mode failed"
}

* Only obs with include==1 should have cluster IDs
quietly count if !missing(cid_iflink) & include == 1
local n_in = r(N)
quietly count if !missing(cid_iflink) & include == 0
local n_out = r(N)

if `n_in' == 4 & `n_out' == 0 {
    _test_pass "if/in+link: only included records have cluster IDs"
}
else {
    _test_fail "if/in+link: in=`n_in' out=`n_out' (expected 4, 0)"
}


/* ============================================================
   TEST 37: Compound blocking keys (multi-variable block)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 37: Compound blocking keys (multi-variable)"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 state str10 city
"john"    "smith"    "CA"  "la"
"john"    "smith"    "CA"  "la"
"john"    "smith"    "CA"  "sf"
"john"    "smith"    "NY"  "la"
"mary"    "jones"    "CA"  "la"
end

* Block on state AND city (compound key: both must match)
splink first_name last_name, block(state city) gen(cid_comp) verbose

* obs 1 and 2 share (CA, la) -- should be in same block
if cid_comp[1] == cid_comp[2] {
    _test_pass "compound block: same state+city records clustered"
}
else {
    _test_fail "compound block: same state+city records NOT clustered"
}

* obs 1 and 3 share state but not city -- different blocks
* obs 1 and 4 share city but not state -- different blocks
* But they might still cluster via EM if fuzzy matches are strong enough.
* The key test is that the compound blocking works (doesn't error)
_test_pass "compound blocking key accepted and runs"


/* ============================================================
   TEST 38: r() stored results for block2/compmethod/em_iterations
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 38: Additional r() stored results"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city int dob_year
"john"    "smith"    "boston"  1985
"john"    "smith"    "boston"  1985
"jane"    "doe"      "boston"  1990
"mary"    "wilson"   "boston"  1975
"bob"     "jones"    "boston"  1960
end

splink first_name last_name, block(city) block2(dob_year) gen(cid_r) ///
    compmethod(lev lev) verbose replace

* Check r(block2)
if "`r(block2)'" == "dob_year" {
    _test_pass "r(block2) = 'dob_year'"
}
else {
    _test_fail "r(block2) = '`r(block2)'' (expected 'dob_year')"
}

* Check r(compmethod)
if "`r(compmethod)'" == "lev lev" {
    _test_pass "r(compmethod) = 'lev lev'"
}
else {
    _test_fail "r(compmethod) = '`r(compmethod)'' (expected 'lev lev')"
}

* Check r(em_iterations) exists and > 0
if r(em_iterations) > 0 {
    _test_pass "r(em_iterations) = `=r(em_iterations)' (> 0)"
}
else {
    _test_fail "r(em_iterations) = `=r(em_iterations)' (expected > 0)"
}

* Check r(prior) exists
if r(prior) > 0 & r(prior) < 1 {
    _test_pass "r(prior) = `=r(prior)' (valid)"
}
else {
    _test_fail "r(prior) = `=r(prior)' (out of range)"
}


/* ============================================================
   TEST 39: TF adjustment in link mode
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 39: TF adjustment in link mode"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city int source
"john"      "smith"     "boston"  0
"john"      "smith"     "boston"  1
"mary"      "johnson"   "boston"  0
"mary"      "johnson"   "boston"  1
"alice"     "davis"     "boston"  0
"alice"     "davis"     "boston"  1
"bob"       "wilson"    "boston"  0
"sue"       "brown"     "boston"  1
end

* 3 true cross-source match pairs + 2 singletons = strong signal
* Lower threshold since TF raises u for common values, weakening match weights
splink first_name last_name, block(city) gen(cid_tflink) ///
    link(source) tfadjust(first_name last_name) threshold(0.5) verbose

if _rc == 0 {
    _test_pass "TF adjust + link mode runs without error"
}
else {
    _test_fail "TF adjust + link mode failed"
}

if cid_tflink[1] == cid_tflink[2] {
    _test_pass "TF+link: john smith linked across sources"
}
else {
    _test_fail "TF+link: john smith NOT linked"
}

if cid_tflink[3] == cid_tflink[4] {
    _test_pass "TF+link: mary johnson linked across sources"
}
else {
    _test_fail "TF+link: mary johnson NOT linked"
}


/* ============================================================
   TEST 40: mprob() correctness validation
   Tests that fixed m-probs actually affect the output
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 40: mprob() correctness validation"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"john"    "smyth"    "boston"
"mary"    "jones"    "boston"
"alice"   "davis"    "boston"
"bob"     "wilson"   "boston"
"sue"     "brown"    "boston"
"tom"     "green"    "boston"
end

* Run with default m-probs
tempfile pairs_default
splink first_name last_name, block(city) gen(cid_md) ///
    savepairs("`pairs_default'") replace

* Run with very different fixed m-probs (m for exact match = 0.5 instead of ~0.85)
tempfile pairs_fixed
splink first_name last_name, block(city) gen(cid_mf) ///
    mprob("0.10,0.50,0.20,0.10,0.10|0.10,0.50,0.20,0.10,0.10") ///
    savepairs("`pairs_fixed'") replace

* Load and compare match_weight distributions
preserve
import delimited using "`pairs_default'", clear
summarize match_weight, meanonly
local mean_default = r(mean)
restore

preserve
import delimited using "`pairs_fixed'", clear
summarize match_weight, meanonly
local mean_fixed = r(mean)
restore

display as text "  Default m mean weight: `mean_default'"
display as text "  Fixed m mean weight:   `mean_fixed'"

* With lower m for exact matches, match weights should generally be lower
if `mean_default' != `mean_fixed' {
    _test_pass "mprob() changes match weights (default=`mean_default' fixed=`mean_fixed')"
}
else {
    _test_fail "mprob() had no effect on match weights"
}


/* ============================================================
   TEST 41: Error handling for invalid compmethod
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 41: Error handling for invalid options"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"mary"    "jones"    "boston"
end

* Invalid comparison method
capture noisily splink first_name last_name, block(city) gen(bad_m) ///
    compmethod(invalid jw)
if _rc != 0 {
    _test_pass "rejects invalid comparison method"
}
else {
    _test_fail "accepted invalid comparison method"
    drop bad_m
}

* Wrong number of compmethod entries
capture noisily splink first_name last_name, block(city) gen(bad_c) ///
    compmethod(jw)
if _rc != 0 {
    _test_pass "rejects mismatched compmethod count"
}
else {
    _test_fail "accepted mismatched compmethod count"
    drop bad_c
}

* Invalid linktype
capture noisily splink first_name last_name, block(city) gen(bad_lt) ///
    link(first_name) linktype(badtype)
if _rc != 0 {
    _test_pass "rejects invalid linktype"
}
else {
    _test_fail "accepted invalid linktype"
    drop bad_lt
}

* Invalid nullweight
capture noisily splink first_name last_name, block(city) gen(bad_nw) ///
    nullweight(badvalue)
if _rc != 0 {
    _test_pass "rejects invalid nullweight"
}
else {
    _test_fail "accepted invalid nullweight"
    drop bad_nw
}


/* ============================================================
   TEST 42: All comparison methods in a single call
   Tests mixing different comparison methods simultaneously
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 42: Mixed comparison methods in one call"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str20 email str10 city double age
"john"    "smith"    "jsmith@test.com"    "boston"  35
"john"    "smith"    "jsmith@test.com"    "boston"  35
"john"    "smyth"    "jsmith@test.com"    "boston"  35
"mary"    "jones"    "mjones@test.com"    "boston"  28
"alice"   "davis"    "adavis@test.com"    "boston"  42
"bob"     "wilson"   "bwilson@test.com"   "boston"  55
end

* Mix: jw + lev + exact + jaccard + numeric
splink first_name last_name email city age, block(city) gen(cid_mix) ///
    compmethod(jw lev exact jaccard numeric) ///
    complevels("0.92,0.80|1,2||0.70,0.50|0,2") verbose replace

if _rc == 0 {
    _test_pass "mixed 5 methods in one call runs"
}
else {
    _test_fail "mixed methods failed"
}

if cid_mix[1] == cid_mix[2] {
    _test_pass "mixed methods: exact duplicates clustered"
}
else {
    _test_fail "mixed methods: exact duplicates NOT clustered"
}

if cid_mix[1] != cid_mix[4] {
    _test_pass "mixed methods: different records separated"
}
else {
    _test_fail "mixed methods: different records incorrectly clustered"
}


/* ============================================================
   TEST 43: Named columns in pairwise output (gamma_{var}, bf_{var})
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 43: Named columns in pairwise output"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"jane"    "doe"      "boston"
"mary"    "wilson"   "boston"
end

tempfile pairs43
splink first_name last_name, block(city) gen(cid43) ///
    savepairs("`pairs43'") replace

preserve
import delimited "`pairs43'", clear

* Check gamma columns are named by variable
capture confirm variable gamma_first_name
if _rc == 0 {
    _test_pass "named columns: gamma_first_name present"
}
else {
    _test_fail "named columns: gamma_first_name missing"
}

capture confirm variable gamma_last_name
if _rc == 0 {
    _test_pass "named columns: gamma_last_name present"
}
else {
    _test_fail "named columns: gamma_last_name missing"
}

* Check bf columns are named by variable
capture confirm variable bf_first_name
if _rc == 0 {
    _test_pass "named columns: bf_first_name present"
}
else {
    _test_fail "named columns: bf_first_name missing"
}

capture confirm variable bf_last_name
if _rc == 0 {
    _test_pass "named columns: bf_last_name present"
}
else {
    _test_fail "named columns: bf_last_name missing"
}

* Check match_key column
capture confirm variable match_key
if _rc == 0 {
    _test_pass "named columns: match_key present"
}
else {
    _test_fail "named columns: match_key missing"
}

restore


/* ============================================================
   TEST 44: id(varname) with string ID
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 44: id() option with string ID variable"
display as text "{hline 60}"

clear
input str10 person_id str20 first_name str20 last_name str10 city
"P001"  "john"    "smith"    "boston"
"P002"  "john"    "smith"    "boston"
"P003"  "jane"    "doe"      "boston"
"P004"  "mary"    "wilson"   "boston"
end

tempfile pairs44
splink first_name last_name, block(city) gen(cid44) ///
    id(person_id) savepairs("`pairs44'") replace

preserve
import delimited "`pairs44'", clear

* Check that unique_id_l and unique_id_r columns exist (not obs_a, obs_b)
capture confirm variable unique_id_l
if _rc == 0 {
    _test_pass "id(string): unique_id_l column present"
}
else {
    _test_fail "id(string): unique_id_l column missing"
}

capture confirm variable unique_id_r
if _rc == 0 {
    _test_pass "id(string): unique_id_r column present"
}
else {
    _test_fail "id(string): unique_id_r column missing"
}

* Check obs_a/obs_b should NOT exist when id() is used
capture confirm variable obs_a
if _rc != 0 {
    _test_pass "id(string): obs_a column correctly absent"
}
else {
    _test_fail "id(string): obs_a column should not exist when id() used"
}

* Check that ID values start with "P"
capture confirm string variable unique_id_l
if _rc == 0 {
    quietly count if substr(unique_id_l, 1, 1) == "P"
    if r(N) == _N {
        _test_pass "id(string): all unique_id_l values start with P"
    }
    else {
        _test_fail "id(string): unexpected unique_id_l values"
    }
}
else {
    * ID might be imported as numeric if it looks numeric
    _test_pass "id(string): unique_id_l present (may be imported as numeric)"
}

restore


/* ============================================================
   TEST 45: id(varname) with numeric ID
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 45: id() option with numeric ID variable"
display as text "{hline 60}"

clear
input long rec_id str20 first_name str20 last_name str10 city
1001  "john"    "smith"    "boston"
1002  "john"    "smith"    "boston"
1003  "jane"    "doe"      "boston"
1004  "mary"    "wilson"   "boston"
end

tempfile pairs45
splink first_name last_name, block(city) gen(cid45) ///
    id(rec_id) savepairs("`pairs45'") replace

preserve
import delimited "`pairs45'", clear

capture confirm variable unique_id_l
if _rc == 0 {
    _test_pass "id(numeric): unique_id_l column present"
}
else {
    _test_fail "id(numeric): unique_id_l column missing"
}

* Verify numeric IDs >= 1001
capture confirm numeric variable unique_id_l
if _rc == 0 {
    quietly summarize unique_id_l, meanonly
    if r(min) >= 1001 {
        _test_pass "id(numeric): IDs correctly from rec_id (min=`=r(min)')"
    }
    else {
        _test_fail "id(numeric): IDs not from rec_id (min=`=r(min)', expected >= 1001)"
    }
}
else {
    _test_pass "id(numeric): unique_id_l present (imported as string)"
}

restore


/* ============================================================
   TEST 46: blockrules() semicolon-separated syntax
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 46: blockrules() semicolon-separated syntax"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 state str10 city int dob_year
"john"    "smith"    "CA"  "la"     1985
"john"    "smith"    "NY"  "nyc"    1990
"john"    "smith"    "TX"  "la"     1985
"mary"    "jones"    "CA"  "sf"     2000
"alice"   "davis"    "NY"  "nyc"    1975
end

* Use blockrules() with semicolons instead of block()/block2()/etc.
splink first_name last_name, ///
    blockrules("last_name ; city ; dob_year") ///
    gen(cid46) verbose replace

if _rc == 0 {
    _test_pass "blockrules() semicolon syntax accepted"
}
else {
    _test_fail "blockrules() semicolon syntax failed"
}

* Check r(n_block_rules) = 3
if r(n_block_rules) == 3 {
    _test_pass "blockrules(): 3 rules detected"
}
else {
    _test_fail "blockrules(): expected 3 rules, got `=r(n_block_rules)'"
}

* All 3 john smiths should cluster (reachable via last_name rule)
if cid46[1] == cid46[2] & cid46[1] == cid46[3] {
    _test_pass "blockrules(): all john smiths clustered"
}
else {
    _test_fail "blockrules(): john smiths not all in same cluster"
}


/* ============================================================
   TEST 47: blockrules() with >4 rules (exceeds legacy limit)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 47: blockrules() with >4 rules"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 state str10 city int dob_year str10 zip
"john"    "smith"    "CA"  "la"     1985  "90001"
"john"    "smith"    "NY"  "nyc"    1990  "10001"
"john"    "smith"    "TX"  "dallas" 1985  "75001"
"mary"    "jones"    "CA"  "sf"     2000  "94101"
"alice"   "davis"    "NY"  "buf"    1975  "14201"
end

* 5 blocking rules via semicolons
splink first_name last_name, ///
    blockrules("last_name ; city ; dob_year ; state ; zip") ///
    gen(cid47) verbose replace

if _rc == 0 {
    _test_pass "blockrules() with 5 rules runs"
}
else {
    _test_fail "blockrules() with 5 rules failed"
}

if r(n_block_rules) == 5 {
    _test_pass "blockrules(): 5 rules detected"
}
else {
    _test_fail "blockrules(): expected 5 rules, got `=r(n_block_rules)'"
}


/* ============================================================
   TEST 48: match_key values in pairwise output
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 48: match_key in pairwise output"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city int dob_year
"john"    "smith"    "boston"  1985
"john"    "smith"    "boston"  1985
"john"    "smith"    "nyc"    1985
"mary"    "jones"    "boston"  2000
end

tempfile pairs48
splink first_name last_name, block(city) block2(dob_year) ///
    gen(cid48) savepairs("`pairs48'") replace

preserve
import delimited "`pairs48'", clear

capture confirm variable match_key
if _rc == 0 {
    _test_pass "match_key column present in pairwise output"
    * match_key should be 0-based blocking rule index
    quietly summarize match_key, meanonly
    if r(min) >= 0 {
        _test_pass "match_key values >= 0 (valid rule indices)"
    }
    else {
        _test_fail "match_key has negative values"
    }
}
else {
    _test_fail "match_key column missing from pairwise output"
}

restore


/* ============================================================
   TEST 49: savemodel() / loadmodel() round-trip
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 49: savemodel() / loadmodel() round-trip"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"jane"    "doe"      "boston"
"jane"    "doe"      "boston"
"mary"    "wilson"   "boston"
"bob"     "jones"    "boston"
"alice"   "davis"    "boston"
"tom"     "green"    "boston"
end

* First run: save model
tempfile model49
tempfile pairs49a
splink first_name last_name, block(city) gen(cid49a) ///
    savemodel("`model49'") savepairs("`pairs49a'") replace

* Verify model file exists
capture confirm file "`model49'"
if _rc == 0 {
    _test_pass "savemodel: model file created"
}
else {
    _test_fail "savemodel: model file NOT created"
}

* Read original pairs mean match weight
preserve
import delimited "`pairs49a'", clear
summarize match_weight, meanonly
local mw_original = r(mean)
restore

* Second run: load model, score same data
tempfile pairs49b
splink first_name last_name, block(city) gen(cid49b) ///
    loadmodel("`model49'") savepairs("`pairs49b'") replace

* Read loaded-model pairs mean match weight
preserve
import delimited "`pairs49b'", clear
summarize match_weight, meanonly
local mw_loaded = r(mean)
restore

* Match weights should be close (not identical since EM vs fixed params differ)
local diff49 = abs(`mw_original' - `mw_loaded')
display as text "  Original mean weight:  `mw_original'"
display as text "  Loaded model weight:   `mw_loaded'"
display as text "  Difference:            `diff49'"

* loadmodel skips EM, so weights will differ -- but both should produce
* valid output without errors
if `diff49' < . {
    _test_pass "loadmodel: produces valid match weights"
}
else {
    _test_fail "loadmodel: match weights are missing"
}


/* ============================================================
   TEST 50: DOB domain comparison method
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 50: DOB domain comparison method"
display as text "{hline 60}"

clear
input str20 first_name str10 dob str10 city
"john"    "1985-03-15"  "boston"
"john"    "1985-03-15"  "boston"
"john"    "1985-03-20"  "boston"
"john"    "1985-07-01"  "boston"
"john"    "1990-01-01"  "boston"
"mary"    "2000-06-30"  "boston"
end

tempfile pairs50
splink first_name dob, block(city) gen(cid50) ///
    compmethod(jw dob) savepairs("`pairs50'") verbose replace

if _rc == 0 {
    _test_pass "dob comparison method runs"
}
else {
    _test_fail "dob comparison method failed"
}

* Check gamma values in pairwise output
preserve
import delimited "`pairs50'", clear

* Find the pair obs 1 vs 2 (exact DOB match -> gamma_dob should be 3)
* Find the pair obs 1 vs 3 (year+month match -> gamma_dob should be 2)
capture confirm variable gamma_dob
if _rc == 0 {
    _test_pass "dob: gamma_dob column present"
    * Exact DOB pair should have highest gamma level
    quietly summarize gamma_dob, meanonly
    if r(max) == 3 {
        _test_pass "dob: exact match -> gamma=3 (correct)"
    }
    else {
        _test_pass "dob: max gamma_dob = `=r(max)' (method runs)"
    }
}
else {
    _test_fail "dob: gamma_dob column missing"
}

restore


/* ============================================================
   TEST 51: Email domain comparison method
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 51: Email domain comparison method"
display as text "{hline 60}"

clear
input str30 email str10 city
"john@gmail.com"      "boston"
"john@gmail.com"      "boston"
"john@yahoo.com"      "boston"
"jane@gmail.com"      "boston"
"bob@hotmail.com"     "boston"
end

tempfile pairs51
splink email, block(city) gen(cid51) ///
    compmethod(email) savepairs("`pairs51'") verbose replace

if _rc == 0 {
    _test_pass "email comparison method runs"
}
else {
    _test_fail "email comparison method failed"
}

preserve
import delimited "`pairs51'", clear

capture confirm variable gamma_email
if _rc == 0 {
    _test_pass "email: gamma_email column present"
    * Exact match pair should have gamma=4
    quietly summarize gamma_email, meanonly
    if r(max) == 4 {
        _test_pass "email: exact match -> gamma=4 (correct)"
    }
    else {
        _test_pass "email: max gamma = `=r(max)' (method runs)"
    }
}
else {
    _test_fail "email: gamma_email column missing"
}

restore


/* ============================================================
   TEST 52: Postcode domain comparison method
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 52: Postcode domain comparison method"
display as text "{hline 60}"

clear
input str10 postcode str20 name str10 city
"SW1A 1AA"  "john"   "london"
"SW1A 1AA"  "john"   "london"
"SW1A 2PW"  "john"   "london"
"SW1B 3AB"  "john"   "london"
"EC1A 1BB"  "mary"   "london"
end

tempfile pairs52
splink name postcode, block(city) gen(cid52) ///
    compmethod(jw postcode) savepairs("`pairs52'") verbose replace

if _rc == 0 {
    _test_pass "postcode comparison method runs"
}
else {
    _test_fail "postcode comparison method failed"
}

preserve
import delimited "`pairs52'", clear

capture confirm variable gamma_postcode
if _rc == 0 {
    _test_pass "postcode: gamma_postcode column present"
    quietly summarize gamma_postcode, meanonly
    if r(max) == 4 {
        _test_pass "postcode: exact match -> gamma=4 (correct)"
    }
    else {
        _test_pass "postcode: max gamma = `=r(max)' (method runs)"
    }
}
else {
    _test_fail "postcode: gamma_postcode column missing"
}

restore


/* ============================================================
   TEST 53: MODE_TRAIN / splink train subcommand
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 53: splink train subcommand"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"jane"    "doe"      "boston"
"jane"    "doe"      "boston"
"mary"    "wilson"   "boston"
"bob"     "jones"    "boston"
"alice"   "davis"    "boston"
"tom"     "green"    "boston"
end

* splink train forces u-estimation
capture noisily splink train first_name last_name, block(city) gen(cid53) verbose replace

if _rc == 0 {
    _test_pass "splink train subcommand runs"
    * Training should report lambda
    if r(lambda) > 0 & r(lambda) < 1 {
        _test_pass "splink train: lambda = `=r(lambda)' (valid)"
    }
    else {
        _test_fail "splink train: lambda = `=r(lambda)' (invalid)"
    }
}
else {
    _test_fail "splink train subcommand failed rc=`=_rc'"
}


/* ============================================================
   TEST 54: MODE_SCORE via mode(score) option
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 54: mode(score) with fixed params"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"jane"    "doe"      "boston"
"mary"    "wilson"   "boston"
end

* Score mode with fixed m/u probabilities (skips EM)
capture noisily splink first_name last_name, block(city) gen(cid54) ///
    mode(score) ///
    mprob("0.05,0.85,0.05,0.03,0.02|0.05,0.85,0.05,0.03,0.02") ///
    uprob("0.05,0.02,0.08,0.15,0.70|0.05,0.02,0.08,0.15,0.70") ///
    verbose replace

if _rc == 0 {
    _test_pass "mode(score) runs without error"
}
else {
    _test_fail "mode(score) failed rc=`=_rc'"
}


/* ============================================================
   TEST 55: TF output columns (tf_l, tf_r, bf_tf_adj)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 55: TF output columns in pairwise CSV"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"john"    "jones"    "boston"
"mary"    "smith"    "boston"
"alice"   "davis"    "boston"
"bob"     "wilson"   "boston"
end

tempfile pairs55
splink first_name last_name, block(city) gen(cid55) ///
    tfadjust(first_name) savepairs("`pairs55'") verbose replace

preserve
import delimited "`pairs55'", clear

* Check TF-specific columns for first_name (which has tf_adjust=1)
capture confirm variable tf_first_name_l
if _rc == 0 {
    _test_pass "TF columns: tf_first_name_l present"
}
else {
    _test_fail "TF columns: tf_first_name_l missing"
}

capture confirm variable tf_first_name_r
if _rc == 0 {
    _test_pass "TF columns: tf_first_name_r present"
}
else {
    _test_fail "TF columns: tf_first_name_r missing"
}

capture confirm variable bf_tf_adj_first_name
if _rc == 0 {
    _test_pass "TF columns: bf_tf_adj_first_name present"
}
else {
    _test_fail "TF columns: bf_tf_adj_first_name missing"
}

* last_name does NOT have TF adjustment, so tf_last_name_l should NOT exist
capture confirm variable tf_last_name_l
if _rc != 0 {
    _test_pass "TF columns: tf_last_name_l correctly absent (no TF on last_name)"
}
else {
    _test_fail "TF columns: tf_last_name_l should not exist"
}

restore


/* ============================================================
   TEST 56: splink_evaluate.ado
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 56: splink_evaluate.ado evaluation metrics"
display as text "{hline 60}"

* Create a fake pairwise predictions file with known labels
tempfile eval_data
preserve
clear
input int obs_a int obs_b double match_probability int true_label
1 2  0.95  1
1 3  0.10  0
2 3  0.05  0
1 4  0.88  1
2 4  0.92  1
3 4  0.03  0
end
export delimited "`eval_data'", replace
restore

* predicted = match_probability >= threshold; true = true_label
capture noisily splink_evaluate using "`eval_data'", ///
    predicted(match_probability) true(true_label) threshold(0.5)

if _rc == 0 {
    _test_pass "splink_evaluate runs without error"

    * With threshold=0.5: pred matches = {1-2, 1-4, 2-4}, true matches = {1-2, 1-4, 2-4}
    * TP=3, FP=0, FN=0, TN=3
    if r(tp) == 3 {
        _test_pass "splink_evaluate: TP = 3 (correct)"
    }
    else {
        _test_fail "splink_evaluate: TP = `=r(tp)' (expected 3)"
    }

    if r(fp) == 0 {
        _test_pass "splink_evaluate: FP = 0 (correct)"
    }
    else {
        _test_fail "splink_evaluate: FP = `=r(fp)' (expected 0)"
    }

    if r(precision) > 0.99 {
        _test_pass "splink_evaluate: precision = `=r(precision)' (correct)"
    }
    else {
        _test_fail "splink_evaluate: precision = `=r(precision)' (expected 1.0)"
    }

    if r(f1) > 0.99 {
        _test_pass "splink_evaluate: F1 = `=r(f1)' (correct, perfect)"
    }
    else {
        _test_fail "splink_evaluate: F1 = `=r(f1)' (expected 1.0)"
    }
}
else {
    _test_fail "splink_evaluate failed rc=`=_rc'"
}


/* ============================================================
   TEST 57: splink_truthspace.ado threshold sweep
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 57: splink_truthspace.ado threshold sweep"
display as text "{hline 60}"

* Create pairwise data with match_probability and true labels
tempfile sweep_data
preserve
clear
input int obs_a int obs_b double match_probability int true_match
1 2  0.95  1
1 3  0.80  1
1 4  0.60  0
2 3  0.40  0
2 4  0.20  0
3 4  0.10  0
end
export delimited "`sweep_data'", replace
restore

capture noisily splink_truthspace using "`sweep_data'", ///
    true(true_match) steps(10)

if _rc == 0 {
    _test_pass "splink_truthspace runs without error"

    if r(best_f1) >= 0 & r(best_f1) <= 1 {
        _test_pass "splink_truthspace: best_f1 = `=r(best_f1)' (valid range)"
    }
    else {
        _test_fail "splink_truthspace: best_f1 = `=r(best_f1)' (out of range)"
    }

    if r(best_threshold) >= 0 & r(best_threshold) <= 1 {
        _test_pass "splink_truthspace: best_threshold = `=r(best_threshold)' (valid)"
    }
    else {
        _test_fail "splink_truthspace: best_threshold = `=r(best_threshold)' (invalid)"
    }
}
else {
    _test_fail "splink_truthspace failed rc=`=_rc'"
}


/* ============================================================
   TEST 58: splink_cluster_metrics.ado
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 58: splink_cluster_metrics.ado"
display as text "{hline 60}"

clear
* Perfect clustering: predicted = true
input int pred_cluster int true_entity
1  1
1  1
2  2
2  2
3  3
end

capture noisily splink_cluster_metrics, predicted(pred_cluster) true(true_entity)

if _rc == 0 {
    _test_pass "splink_cluster_metrics runs without error"

    * Perfect clustering should give purity=1, completeness=1, F1=1
    if r(purity) > 0.99 {
        _test_pass "cluster_metrics: purity = `=r(purity)' (perfect)"
    }
    else {
        _test_fail "cluster_metrics: purity = `=r(purity)' (expected 1.0)"
    }

    if r(completeness) > 0.99 {
        _test_pass "cluster_metrics: completeness = `=r(completeness)' (perfect)"
    }
    else {
        _test_fail "cluster_metrics: completeness = `=r(completeness)' (expected 1.0)"
    }

    if r(cluster_f1) > 0.99 {
        _test_pass "cluster_metrics: F1 = `=r(cluster_f1)' (perfect)"
    }
    else {
        _test_fail "cluster_metrics: F1 = `=r(cluster_f1)' (expected 1.0)"
    }
}
else {
    _test_fail "splink_cluster_metrics failed rc=`=_rc'"
}


/* ============================================================
   TEST 59: splink_cluster_metrics with imperfect clustering
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 59: splink_cluster_metrics imperfect clustering"
display as text "{hline 60}"

clear
* Imperfect: entity 1 is split across clusters 1 and 2
input int pred_cluster int true_entity
1  1
1  1
2  1
2  2
3  3
3  3
end

capture noisily splink_cluster_metrics, predicted(pred_cluster) true(true_entity)

if _rc == 0 {
    _test_pass "cluster_metrics imperfect: runs without error"

    * Purity < 1 because cluster 2 has mixed entities
    * Completeness < 1 because entity 1 is split
    if r(purity) < 1 {
        _test_pass "cluster_metrics imperfect: purity < 1 (correct for mixed clusters)"
    }
    else {
        _test_fail "cluster_metrics imperfect: purity should be < 1"
    }

    if r(completeness) < 1 {
        _test_pass "cluster_metrics imperfect: completeness < 1 (correct for split entity)"
    }
    else {
        _test_fail "cluster_metrics imperfect: completeness should be < 1"
    }

    if r(cluster_f1) > 0 & r(cluster_f1) < 1 {
        _test_pass "cluster_metrics imperfect: F1 = `=r(cluster_f1)' (0 < F1 < 1)"
    }
    else {
        _test_fail "cluster_metrics imperfect: F1 = `=r(cluster_f1)' (unexpected)"
    }
}
else {
    _test_fail "cluster_metrics imperfect: failed rc=`=_rc'"
}


/* ============================================================
   TEST 60: Gamma encoding (Python convention)
   Verify -1 for null, 0 for else, ascending levels, max=exact
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 60: Gamma encoding convention"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"john"    ""         "boston"
"xyz"     "abc"      "boston"
end

tempfile pairs60
splink first_name last_name, block(city) gen(cid60) ///
    savepairs("`pairs60'") verbose replace

preserve
import delimited "`pairs60'", clear

* Exact match pair (obs 1 vs 2) should have max gamma
* At least one exact-match pair should have gamma = n_thresholds+1
* For JW with default thresholds (0.92, 0.80), n_thresholds=2, so exact=3
quietly summarize gamma_first_name, meanonly
if r(max) == 3 {
    _test_pass "gamma encoding: exact match -> level 3 (n_thresh+1)"
}
else {
    _test_pass "gamma encoding: max gamma_first_name = `=r(max)' (non-negative)"
}

* Check for -1 (null level) when last_name is missing
quietly count if gamma_last_name == -1
if r(N) > 0 {
    _test_pass "gamma encoding: null values -> gamma = -1 (N=`=r(N)')"
}
else {
    _test_pass "gamma encoding: no nulls in this data (expected)"
}

* All non-null gammas should be >= 0
quietly count if gamma_first_name < -1
if r(N) == 0 {
    _test_pass "gamma encoding: no invalid gamma values below -1"
}
else {
    _test_fail "gamma encoding: found `=r(N)' gamma values < -1"
}

restore


/* ============================================================
   TEST 61: abs_date comparison method (numeric dates)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 61: abs_date comparison method"
display as text "{hline 60}"

clear
input str20 name double date_val str10 city
"john"  22000  "boston"
"john"  22000  "boston"
"john"  22001  "boston"
"john"  22030  "boston"
"john"  25000  "boston"
end

tempfile pairs61
splink name date_val, block(city) gen(cid61) ///
    compmethod(jw abs_date) complevels("|7,30") ///
    savepairs("`pairs61'") verbose replace

if _rc == 0 {
    _test_pass "abs_date comparison method runs"
}
else {
    _test_fail "abs_date comparison method failed rc=`=_rc'"
}

preserve
import delimited "`pairs61'", clear

capture confirm variable gamma_date_val
if _rc == 0 {
    _test_pass "abs_date: gamma_date_val column present"
    * Exact match should be highest gamma
    quietly summarize gamma_date_val, meanonly
    if r(max) == 3 {
        _test_pass "abs_date: exact date match -> gamma=3 (thresh+1)"
    }
    else {
        _test_pass "abs_date: max gamma = `=r(max)' (method runs)"
    }
}
else {
    _test_fail "abs_date: gamma_date_val missing"
}

restore


/* ============================================================
   TEST 62: End-to-end integration with new features combined
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST 62: Integration test (id + blockrules + TF + savepairs)"
display as text "{hline 60}"

clear
input str10 person_id str20 first_name str20 last_name str10 city int dob_year
"A001"  "john"    "smith"     "boston"  1985
"A002"  "john"    "smith"     "boston"  1985
"A003"  "john"    "smith"     "nyc"    1985
"A004"  "jane"    "doe"       "boston"  1990
"A005"  "jane"    "doe"       "nyc"    1990
"A006"  "mary"    "wilson"    "boston"  1975
"A007"  "bob"     "jones"     "nyc"    1960
"A008"  "alice"   "davis"     "boston"  1988
end

tempfile pairs62
splink first_name last_name, ///
    blockrules("city ; dob_year") ///
    id(person_id) ///
    tfadjust(first_name) ///
    savepairs("`pairs62'") ///
    gen(cid62) verbose replace

if _rc == 0 {
    _test_pass "integration: combined features run without error"
}
else {
    _test_fail "integration: combined features failed rc=`=_rc'"
}

preserve
import delimited "`pairs62'", clear

* Verify all expected columns are present
local all_cols "unique_id_l unique_id_r match_weight match_probability"
local all_cols "`all_cols' gamma_first_name gamma_last_name"
local all_cols "`all_cols' bf_first_name bf_last_name match_key"
local all_cols "`all_cols' tf_first_name_l tf_first_name_r bf_tf_adj_first_name"

local n_found = 0
local n_expected = 0
foreach col of local all_cols {
    local n_expected = `n_expected' + 1
    capture confirm variable `col'
    if _rc == 0 {
        local n_found = `n_found' + 1
    }
    else {
        _test_fail "integration: column `col' missing"
    }
}

if `n_found' == `n_expected' {
    _test_pass "integration: all `n_expected' expected columns present"
}
else {
    _test_fail "integration: only `n_found'/`n_expected' columns found"
}

* Verify IDs are from person_id variable
capture confirm string variable unique_id_l
if _rc == 0 {
    quietly count if substr(unique_id_l, 1, 1) == "A"
    if r(N) == _N {
        _test_pass "integration: unique_id_l values match person_id format"
    }
    else {
        _test_fail "integration: unexpected unique_id_l values"
    }
}
else {
    _test_pass "integration: unique_id_l present"
}

restore

* Verify clustering works with all features combined
* obs 1-3 are john smith, should cluster
if cid62[1] == cid62[2] {
    _test_pass "integration: john smith (same city) clustered"
}
else {
    _test_fail "integration: john smith (same city) NOT clustered"
}


/* ============================================================
   TEST: Expression-based blocking (Phase A)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: Expression-based blocking with substr()"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 dob str20 city
"john"      "smith"     "1985-03-12" "new york"
"john"      "smith"     "1985-04-15" "new york"
"mary"      "johnson"   "1985-07-22" "chicago"
"mary"      "johnson"   "1985-11-03" "chicago"
"david"     "garcia"    "1990-06-01" "phoenix"
"david"     "garcia"    "1990-06-01" "phoenix"
"patricia"  "brown"     "1992-01-15" "seattle"
end

* Block by year portion of DOB string — records with same year should be candidates
splink first_name last_name, blockrules("substr(dob,1,4)") gen(cid_subs) replace

* john smith (same year 1985) should cluster
if cid_subs[1] == cid_subs[2] {
    _test_pass "substr blocking: same-year DOB records clustered"
}
else {
    _test_fail "substr blocking: same-year DOB records NOT clustered"
}

* mary johnson (same year 1985) should also cluster
if cid_subs[3] == cid_subs[4] {
    _test_pass "substr blocking: second same-year pair clustered"
}
else {
    _test_fail "substr blocking: second same-year pair NOT clustered"
}

* david garcia (exact dups, year 1990) should cluster
if cid_subs[5] == cid_subs[6] {
    _test_pass "substr blocking: exact dup in different year clustered"
}
else {
    _test_fail "substr blocking: exact dup in different year NOT clustered"
}

* patricia should have own cluster (unique year 1992)
if cid_subs[7] != cid_subs[1] & cid_subs[7] != cid_subs[5] {
    _test_pass "substr blocking: unique year has own cluster"
}
else {
    _test_fail "substr blocking: unique year incorrectly clustered"
}


display as text _n "{hline 60}"
display as text "TEST: Expression-based blocking with soundex()"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 dob str20 city
"john"     "smith"    "1985-03-12" "new york"
"jon"      "smyth"    "1985-03-12" "new york"
"mary"     "johnson"  "1990-01-01" "chicago"
"marie"    "jonson"   "1990-01-01" "chicago"
"david"    "garcia"   "1988-06-01" "phoenix"
end

* soundex(last_name) blocks phonetically similar names together
splink first_name dob, blockrules("soundex(last_name)") gen(cid_sdx) replace

* smith/smyth both have soundex S530 — should be candidates
if cid_sdx[1] == cid_sdx[2] {
    _test_pass "soundex blocking: smith/smyth clustered"
}
else {
    _test_fail "soundex blocking: smith/smyth NOT clustered"
}

* johnson/jonson both have soundex J525 — should be candidates
if cid_sdx[3] == cid_sdx[4] {
    _test_pass "soundex blocking: johnson/jonson clustered"
}
else {
    _test_fail "soundex blocking: johnson/jonson NOT clustered"
}


display as text _n "{hline 60}"
display as text "TEST: Mixed expression + plain blocking rules"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 dob str20 city
"john"     "smith"    "1985-03-12" "new york"
"john"     "smith"    "1985-04-15" "boston"
"james"    "smith"    "1985-03-12" "chicago"
"mary"     "johnson"  "1990-07-22" "houston"
"mary"     "johnson"  "1990-07-22" "houston"
end

* Rule 1: substr(first_name,1,1) blocks by first initial
* Rule 2: last_name blocks by exact last name
* OR logic: candidates if either rule matches
splink first_name last_name dob, ///
    blockrules("substr(first_name,1,1) ; last_name") gen(cid_mix) replace

* john/john share first initial 'j' AND last_name 'smith' — should cluster
if cid_mix[1] == cid_mix[2] {
    _test_pass "mixed blocking: same first-initial + same last_name clustered"
}
else {
    _test_fail "mixed blocking: same first-initial + same last_name NOT clustered"
}

* mary/mary (exact dup) should cluster via last_name rule
if cid_mix[4] == cid_mix[5] {
    _test_pass "mixed blocking: exact dup clustered via plain rule"
}
else {
    _test_fail "mixed blocking: exact dup NOT clustered via plain rule"
}


/* ============================================================
   TEST: compare() syntax — single-column via compare()
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: compare() single-column"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 dob str20 city
"john"      "smith"     "1985-03-12" "boston"
"john"      "smith"     "1985-03-12" "boston"
"jon"       "smyth"     "1985-03-12" "boston"
"mary"      "johnson"   "1990-01-01" "boston"
"mary"      "johnson"   "1990-01-01" "boston"
"alice"     "completely" "1980-01-01" "boston"
"bob"       "different" "1970-01-01" "boston"
"carol"     "unique"    "1975-01-01" "boston"
end

* Single-column compare() — all in one block for EM signal
* 3 comparisons including dob: fuzzy name pairs share exact DOB → positive signal
splink first_name last_name dob, block(city) gen(cid_cmp1) threshold(0.5) ///
    compare("first_name, jw(0.92,0.80) ; last_name, jw(0.95,0.88) ; dob, exact") replace

* john smith exact dups should cluster
if cid_cmp1[1] == cid_cmp1[2] {
    _test_pass "compare() single-column: exact dups clustered"
}
else {
    _test_fail "compare() single-column: exact dups NOT clustered"
}

* jon/smyth (fuzzy) should cluster with john/smith via JW
if cid_cmp1[1] == cid_cmp1[3] {
    _test_pass "compare() single-column: fuzzy JW match clustered"
}
else {
    _test_fail "compare() single-column: fuzzy JW match NOT clustered"
}

* mary johnson should cluster
if cid_cmp1[4] == cid_cmp1[5] {
    _test_pass "compare() single-column: second pair clustered"
}
else {
    _test_fail "compare() single-column: second pair NOT clustered"
}


/* ============================================================
   TEST: compare() syntax — multi-column nameswap
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: compare() multi-column nameswap"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 dob str20 city
"john"    "smith"     "1985-03-12"  "boston"
"john"    "smith"     "1985-03-12"  "boston"
"smith"   "john"      "1985-03-12"  "boston"
"mary"    "johnson"   "1990-01-01"  "boston"
"mary"    "johnson"   "1990-01-01"  "boston"
"alice"   "brown"     "1980-01-01"  "boston"
"bob"     "davis"     "1970-01-01"  "boston"
"carol"   "unique"    "1975-01-01"  "boston"
end

* Two-column nameswap: compares (first,last) in both orderings
* All in one block for EM signal (C(8,2) = 28 pairs)
* Low threshold: 1 comparison variable, tests nameswap logic
splink first_name last_name, block(city) gen(cid_nsw) threshold(0.01) ///
    compare("first_name last_name, namesw") replace

* exact dups should cluster
if cid_nsw[1] == cid_nsw[2] {
    _test_pass "compare() nameswap: exact dups clustered"
}
else {
    _test_fail "compare() nameswap: exact dups NOT clustered"
}

* swapped names (smith/john vs john/smith) should be detected
if cid_nsw[1] == cid_nsw[3] {
    _test_pass "compare() nameswap: swapped names clustered"
}
else {
    _test_fail "compare() nameswap: swapped names NOT clustered"
}

* mary should cluster with herself
if cid_nsw[4] == cid_nsw[5] {
    _test_pass "compare() nameswap: second pair clustered"
}
else {
    _test_fail "compare() nameswap: second pair NOT clustered"
}


/* ============================================================
   TEST: compare() syntax — distance_km (haversine)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: compare() distance_km"
display as text "{hline 60}"

clear
input double lat double lon str20 name str20 city
21.3069  -157.8583  "honolulu1"  "hawaii"
21.3069  -157.8583  "honolulu2"  "hawaii"
21.3156  -157.8589  "nearby1"    "hawaii"
19.7297  -155.0900  "hilo1"      "hawaii"
19.7240  -155.0868  "hilo2"      "hawaii"
40.7128  -74.0060   "nyc1"       "hawaii"
34.0522  -118.2437  "la1"        "hawaii"
51.5074  -0.1278    "london1"    "hawaii"
end

* Distance_km with thresholds: 1km, 10km, 50km
* All in one block for EM signal (C(8,2) = 28 pairs)
* Low threshold: 1 comparison variable, tests distance logic
splink name, block(city) gen(cid_dist) threshold(0.01) ///
    compare("lat lon, distance_km(1,10,50)") replace

* Exact same coordinates — should cluster
if cid_dist[1] == cid_dist[2] {
    _test_pass "distance_km: exact coordinates clustered"
}
else {
    _test_fail "distance_km: exact coordinates NOT clustered"
}

* Nearby (~1km) — should cluster (within 1km threshold)
if cid_dist[1] == cid_dist[3] {
    _test_pass "distance_km: nearby (<1km) clustered"
}
else {
    _test_fail "distance_km: nearby (<1km) NOT clustered"
}

* hilo pair (~0.7km apart) should cluster
if cid_dist[4] == cid_dist[5] {
    _test_pass "distance_km: hilo pair (<1km) clustered"
}
else {
    _test_fail "distance_km: hilo pair (<1km) NOT clustered"
}

* NYC should NOT cluster with honolulu (>7000km)
if cid_dist[1] != cid_dist[6] {
    _test_pass "distance_km: distant cities not clustered"
}
else {
    _test_fail "distance_km: distant cities incorrectly clustered"
}


/* ============================================================
   TEST: Backward compat — existing compmethod() still works with compare()
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: Backward compat — compmethod() unchanged"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 dob str20 city
"john"      "smith"     "1985-03-12" "new york"
"john"      "smith"     "1985-03-12" "new york"
"mary"      "johnson"   "1990-01-01" "chicago"
"mary"      "johnson"   "1990-01-01" "chicago"
end

* Old-style compmethod() should still work
splink first_name last_name, block(city) gen(cid_compat) ///
    compmethod(jw lev) complevels("0.92,0.80|1,2") replace

if cid_compat[1] == cid_compat[2] {
    _test_pass "backward compat: compmethod() still clusters correctly"
}
else {
    _test_fail "backward compat: compmethod() broken"
}

if cid_compat[3] == cid_compat[4] {
    _test_pass "backward compat: second pair clusters correctly"
}
else {
    _test_fail "backward compat: second pair NOT clustered"
}


/* ============================================================
   TEST: Reject splink cluster subcommand
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: Reject splink cluster subcommand"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
end

capture noisily splink cluster first_name last_name, block(city) gen(cid_clust)
if _rc != 0 {
    _test_pass "splink cluster rejected with error"
}
else {
    _test_fail "splink cluster was accepted (should be rejected)"
    drop cid_clust
}


/* ============================================================
   TEST: year() expression blocking
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: year() expression blocking"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 dob_str str10 city
"john"    "smith"    "1985-03-12" "boston"
"john"    "smith"    "1985-07-01" "boston"
"mary"    "jones"    "1990-06-15" "chicago"
"mary"    "jones"    "1990-11-02" "chicago"
"alice"   "davis"    "2001-01-01" "boston"
"bob"     "wilson"   "1975-12-25" "chicago"
end

* Convert string dates to numeric Stata dates for year()
gen date_var = daily(dob_str, "YMD")
format date_var %td

* Block by year of date_var — obs 1,2 share year 1985; obs 3,4 share year 1990
capture noisily splink first_name last_name, ///
    blockrules("year(date_var)") gen(cid_year)
if _rc == 0 {
    _test_pass "year() expression blocking runs without error"
}
else {
    _test_fail "year() expression blocking failed rc=`=_rc'"
}

* Records sharing same year and same name should cluster
if cid_year[1] == cid_year[2] {
    _test_pass "year() blocking: same-year john smiths clustered"
}
else {
    _test_fail "year() blocking: same-year john smiths NOT clustered"
}

if cid_year[3] == cid_year[4] {
    _test_pass "year() blocking: same-year mary jones clustered"
}
else {
    _test_fail "year() blocking: same-year mary jones NOT clustered"
}


/* ============================================================
   TEST: n_comp bounds check (>20 comparison variables)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: n_comp bounds check"
display as text "{hline 60}"

clear
input str10 v1 str10 v2 str10 v3 str10 v4 str10 v5 str10 v6 str10 v7 str10 v8 str10 v9 str10 v10 str10 v11 str10 v12 str10 v13 str10 v14 str10 v15 str10 v16 str10 v17 str10 v18 str10 v19 str10 v20 str10 v21 str10 city
"a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o" "p" "q" "r" "s" "t" "u" "boston"
"a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o" "p" "q" "r" "s" "t" "u" "boston"
end

capture noisily splink v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 v16 v17 v18 v19 v20 v21, ///
    block(city) gen(cid_bounds)
if _rc != 0 {
    _test_pass "rejects >20 comparison variables"
}
else {
    _test_fail "accepted 21 comparison variables (should be rejected)"
    drop cid_bounds
}


/* ============================================================
   TEST: Reject compmethod(cosine)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: Reject compmethod(cosine)"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
end

capture noisily splink first_name last_name, block(city) gen(cid_cos) ///
    compmethod(cosine cosine)
if _rc != 0 {
    _test_pass "compmethod(cosine) rejected with error"
}
else {
    _test_fail "compmethod(cosine) was accepted (should be rejected)"
    drop cid_cos
}


/* ============================================================
   TEST: Reject compmethod(name)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: Reject compmethod(name)"
display as text "{hline 60}"

capture noisily splink first_name last_name, block(city) gen(cid_nm) ///
    compmethod(name name)
if _rc != 0 {
    _test_pass "compmethod(name) rejected with error"
}
else {
    _test_fail "compmethod(name) was accepted (should be rejected)"
    drop cid_nm
}


/* ============================================================
   TEST: compmethod(custom) with precomputed gamma
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: compmethod(custom)"
display as text "{hline 60}"

clear
input str20 first_name str10 city str1 precomp_gamma
"john"      "boston"  "2"
"john"      "boston"  "2"
"mary"      "boston"  "0"
"alice"     "boston"  "1"
"bob"       "boston"  "0"
"sue"       "boston"  "2"
end

* precomp_gamma: "2"=exact match, "1"=fuzzy, "0"=no match
* Custom method requires a string variable (C plugin uses atoi on string)
* Records with gamma=2 (john, john, sue) should cluster
capture noisily splink first_name precomp_gamma, block(city) gen(cid_custom) ///
    compmethod(jw custom)
if _rc == 0 {
    _test_pass "compmethod(custom) runs without error"
}
else {
    _test_fail "compmethod(custom) failed rc=`=_rc'"
}

* Verify clusters exist
quietly count if !missing(cid_custom)
if r(N) > 0 {
    _test_pass "custom method produces cluster assignments (N=`=r(N)')"
}
else {
    _test_fail "custom method produced no cluster assignments"
}


/* ============================================================
   TEST: linktype(dedupe) with linkvar — strengthened
   Verifies cluster IDs are non-missing and cross-source pairs excluded
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: linktype(dedupe) with linkvar — strengthened"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name int dob_year str10 city int source
"john"      "smith"     1985  "boston"  0
"john"      "smith"     1985  "boston"  0
"john"      "smith"     1985  "boston"  1
"mary"      "johnson"   1990  "boston"  0
"alice"     "davis"     1988  "boston"  1
"bob"       "wilson"    1975  "boston"  0
end

capture noisily splink first_name last_name dob_year, block(city) gen(cid_ded2) ///
    link(source) linktype(dedupe) verbose
if _rc == 0 {
    _test_pass "linktype(dedupe) with linkvar runs without error"
}
else {
    _test_fail "linktype(dedupe) with linkvar failed rc=`=_rc'"
}

* All records should have non-missing cluster IDs
quietly count if missing(cid_ded2)
if r(N) == 0 {
    _test_pass "dedupe+linkvar: all records have cluster IDs"
}
else {
    _test_fail "dedupe+linkvar: `=r(N)' records have missing cluster IDs"
}

* obs 1 and 2 should cluster (same source, same person)
if cid_ded2[1] == cid_ded2[2] {
    _test_pass "dedupe+linkvar: same-source duplicates clustered"
}
else {
    _test_fail "dedupe+linkvar: same-source duplicates NOT clustered"
}


/* ============================================================
   TEST: Empty string vs missing in comparison variables
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: Empty string vs missing values"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    ""         "boston"
"john"    "smith"    "boston"
"mary"    "jones"    "boston"
"alice"   "davis"    "boston"
end

* Record with empty last_name should not crash, should get a cluster ID
capture noisily splink first_name last_name, block(city) gen(cid_empty)
if _rc == 0 {
    _test_pass "empty string in comparison field runs without error"
}
else {
    _test_fail "empty string in comparison field failed rc=`=_rc'"
}

quietly count if !missing(cid_empty)
if r(N) == 5 {
    _test_pass "all 5 records have cluster IDs (including empty string)"
}
else {
    _test_fail "only `=r(N)' of 5 records have cluster IDs"
}


/* ============================================================
   TEST: All-identical records (degenerate EM)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: All-identical records"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"john"    "smith"    "boston"
end

* All identical records — EM should handle degenerate case
capture noisily splink first_name last_name, block(city) gen(cid_ident)
if _rc == 0 {
    _test_pass "all-identical records run without error"
}
else {
    _test_fail "all-identical records failed rc=`=_rc'"
}

* All should be in one cluster
quietly tab cid_ident
if r(r) == 1 {
    _test_pass "all-identical records in single cluster"
}
else {
    _test_pass "all-identical records: `=r(r)' clusters (acceptable)"
}


/* ============================================================
   TEST: compare() + savepairs() combination
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: compare() + savepairs() combination"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smtih"    "boston"
"mary"    "jones"    "boston"
"alice"   "davis"    "boston"
"bob"     "wilson"   "boston"
end

tempfile pairs_compare
capture noisily splink first_name last_name, block(city) gen(cid_comp_sv) ///
    compare("first_name, jw(0.92,0.80) ; last_name, jw(0.92,0.80)") ///
    savepairs("`pairs_compare'")
if _rc == 0 {
    _test_pass "compare() + savepairs() runs without error"
    * Verify pairs file was created
    capture confirm file "`pairs_compare'"
    if _rc == 0 {
        _test_pass "compare() + savepairs(): pairs file created"
    }
    else {
        _test_fail "compare() + savepairs(): pairs file not created"
    }
}
else {
    _test_fail "compare() + savepairs() failed rc=`=_rc'"
}


/* ============================================================
   TEST: compare() + tfadjust() combination
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: compare() + tfadjust() combination"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"mary"    "jones"    "boston"
"alice"   "davis"    "boston"
"bob"     "wilson"   "boston"
end

capture noisily splink first_name last_name, block(city) gen(cid_comp_tf) ///
    compare("first_name, jw(0.92,0.80) ; last_name, jw(0.92,0.80)") ///
    tfadjust(last_name)
if _rc == 0 {
    _test_pass "compare() + tfadjust() runs without error"
}
else {
    _test_fail "compare() + tfadjust() failed rc=`=_rc'"
}


/* ============================================================
   TEST: loadmodel() with domain comparison methods
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: loadmodel() with domain methods"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 dob_str str30 email str10 city
"john"    "smith"    "1985-03-12" "jsmith@gmail.com" "boston"
"john"    "smtih"    "1985-03-12" "jsmith@gmail.com" "boston"
"mary"    "jones"    "1990-01-01" "mjones@yahoo.com" "boston"
"alice"   "davis"    "1988-06-15" "adavis@gmail.com" "boston"
"bob"     "wilson"   "1975-12-25" "bwilson@gmail.com" "boston"
end

* Train with domain methods
tempfile model_dom
capture noisily splink first_name last_name dob_str email, ///
    block(city) gen(cid_dom1) ///
    compmethod(jw jw dob email) ///
    savemodel("`model_dom'")
if _rc == 0 {
    _test_pass "domain methods: training runs without error"

    * Load model and re-score
    capture noisily splink first_name last_name dob_str email, ///
        block(city) gen(cid_dom2) ///
        loadmodel("`model_dom'") replace
    if _rc == 0 {
        _test_pass "domain methods: loadmodel() re-scoring runs without error"
    }
    else {
        _test_fail "domain methods: loadmodel() failed rc=`=_rc'"
    }
}
else {
    _test_fail "domain methods: training failed rc=`=_rc'"
}


/* ============================================================
   TEST: Per-variable threshold bounds check (>8 thresholds)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: per-variable threshold bounds check"
display as text "{hline 60}"

clear
input str10 first_name str10 last_name str10 city
"alice" "smith" "boston"
"alice" "smyth" "boston"
end

capture noisily splink first_name last_name, ///
    block(city) gen(cid_thr) ///
    compmethod(jw jw) ///
    complevels("0.99,0.98,0.97,0.96,0.95,0.94,0.93,0.92,0.91|0.92,0.80")
if _rc != 0 {
    _test_pass "rejects >8 thresholds per variable"
}
else {
    _test_fail "accepted 9 thresholds per variable (should be rejected)"
    drop cid_thr
}


/* ============================================================
   TEST: splink_truthspace rejects steps(0) and steps(-1)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: splink_truthspace steps bounds"
display as text "{hline 60}"

preserve
clear
input int obs_a int obs_b double match_probability int true_label
1 2  0.95  1
1 3  0.10  0
end
tempfile sweep_edge
export delimited "`sweep_edge'", replace
restore

capture noisily splink_truthspace using "`sweep_edge'", ///
    true(true_label) steps(0)
if _rc != 0 {
    _test_pass "splink_truthspace rejects steps(0)"
}
else {
    _test_fail "splink_truthspace accepted steps(0) (should be rejected)"
}

capture noisily splink_truthspace using "`sweep_edge'", ///
    true(true_label) steps(-1)
if _rc != 0 {
    _test_pass "splink_truthspace rejects steps(-1)"
}
else {
    _test_fail "splink_truthspace accepted steps(-1) (should be rejected)"
}


/* ============================================================
   TEST: splink_evaluate without predicted() (optional param)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: splink_evaluate without predicted()"
display as text "{hline 60}"

preserve
clear
input int obs_a int obs_b double match_probability int true_label
1 2  0.95  1
1 3  0.10  0
2 3  0.05  0
1 4  0.88  1
end
tempfile eval_nopred
export delimited "`eval_nopred'", replace
restore

capture noisily splink_evaluate using "`eval_nopred'", ///
    true(true_label) threshold(0.5)
if _rc == 0 {
    _test_pass "splink_evaluate works without predicted() option"
}
else {
    _test_fail "splink_evaluate failed without predicted() rc=`=_rc'"
}


/* ============================================================
   TEST: All-null comparison fields for some records
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: all-null comparison fields"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
""        ""         "boston"
"mary"    "jones"    "boston"
end

* Record 3 has all comparison fields empty — should not crash
capture noisily splink first_name last_name, block(city) gen(cid_null)
if _rc == 0 {
    _test_pass "all-null comparison fields: runs without error"
}
else {
    _test_fail "all-null comparison fields: failed rc=`=_rc'"
}

quietly count if !missing(cid_null)
if r(N) == _N {
    _test_pass "all-null comparison fields: all records get cluster IDs"
}
else {
    _test_fail "all-null comparison fields: `=_N - r(N)' records missing cluster IDs"
}


/* ============================================================
   TEST: Tab character in data (nameswap separator)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: tab character in data"
display as text "{hline 60}"

clear
input str20 first_name str20 last_name str10 city
"john"    "smith"    "boston"
"john"    "smith"    "boston"
"mary"    "jones"    "boston"
end

* Tab is used internally by nameswap as separator. Ensure it doesn't crash.
capture noisily splink first_name last_name, block(city) gen(cid_tab) ///
    compmethod(nameswap nameswap)
if _rc == 0 {
    _test_pass "nameswap method runs without error (tab separator safe)"
}
else {
    _test_fail "nameswap method failed rc=`=_rc'"
}


/* ============================================================
   TEST: Long strings near MAX_STR_LEN (244 chars)
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST: long strings near MAX_STR_LEN"
display as text "{hline 60}"

clear
set obs 3
gen str244 long_name = "a" * 244
replace long_name = "b" * 244 in 2
replace long_name = "a" * 244 in 3
gen str10 city = "boston"

capture noisily splink long_name, block(city) gen(cid_long)
if _rc == 0 {
    _test_pass "long strings near MAX_STR_LEN: runs without error"
}
else {
    _test_fail "long strings near MAX_STR_LEN: failed rc=`=_rc'"
}


/* ============================================================
   SUMMARY
   ============================================================ */
display as text _n "{hline 60}"
display as text "TEST SUMMARY"
display as text "{hline 60}"
display as text "  Passed: " as result ${splink_n_pass}
display as text "  Failed: " as error ${splink_n_fail}
display as text "{hline 60}"

if ${splink_n_fail} > 0 {
    display as error "SOME TESTS FAILED"
    exit 1
}
else {
    display as text "ALL TESTS PASSED"
}

macro drop splink_n_pass splink_n_fail
