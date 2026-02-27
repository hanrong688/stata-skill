*! version 3.1.0  26feb2026
*! Probabilistic record linkage using the Fellegi-Sunter model
*! Full-fidelity implementation matching the Python splink v4 package
*! Supports: configurable comparison levels, multiple comparison functions,
*!   term frequency adjustments, multiple blocking rules (OR), null handling,
*!   pairwise output, user-fixable m/u probabilities, training pipeline,
*!   model persistence, domain-specific comparisons
*! Based on: splink (https://github.com/moj-analytical-services/splink)

program define splink, rclass
    version 14.0

    * --- Subcommand detection ---
    * Check if first token is a known subcommand
    local subcmd ""
    gettoken first rest : 0
    if "`first'" == "train" | "`first'" == "predict" | "`first'" == "cluster" {
        local subcmd "`first'"
        local 0 "`rest'"
    }

    syntax varlist(min=1) [if] [in],           ///
        GENerate(name)                          ///  output cluster ID variable
        [BLOCKvar(varlist)                      ///  1st blocking rule
         BLOCK2(varlist)                        ///  2nd blocking rule (OR)
         BLOCK3(varlist)                        ///  3rd blocking rule (OR)
         BLOCK4(varlist)                        ///  4th blocking rule (OR)
         BLOCKRules(string)                     ///  semicolon-separated blocking rules
         COMPMethod(string)                     ///  method per var: "jw jw lev exact"
         COMPLevels(string)                     ///  thresholds: "0.95,0.88,0.7|0.95,0.88|1,2|"
         COMPare(string)                        ///  extended comparison spec
         TFadjust(varlist)                      ///  term frequency adjustment variables
         TFmin(real 0.001)                      ///  minimum TF u-value
         PRior(real 0.0001)                     ///  prior match probability
         THReshold(real 0.85)                   ///  match probability threshold
         MAXIter(integer 25)                    ///  max EM iterations
         MAXBlocksize(integer 5000)             ///  max records per block (0=no limit)
         LINKvar(varname)                       ///  source indicator for linking
         LINKType(string)                       ///  "dedupe" "link" "link_and_dedupe"
         NULLweight(string)                     ///  "neutral" (default) or "penalize"
         SAVEPairs(string)                      ///  file path for pairwise output
         Mprob(string)                          ///  fixed m-probs: "0.9,0.05,0.03,0.02|..."
         Uprob(string)                          ///  fixed u-probs: "0.01,0.02,0.12,0.85|..."
         UEstimate                              ///  estimate u via random sampling
         UMaxpairs(integer 1000000)             ///  max random pairs for u estimation
         USeed(integer 42)                      ///  seed for random u estimation
         ID(varname)                            ///  unique ID variable for output
         SAVEModel(string)                      ///  save model parameters to JSON
         LOADModel(string)                      ///  load model parameters from JSON
         MODE(string)                           ///  "legacy" "train" "score"
         REPlace                                ///  replace existing output variable
         Verbose]

    * --- Validate inputs ---
    if `threshold' <= 0 | `threshold' >= 1 {
        display as error "threshold() must be between 0 and 1"
        exit 198
    }
    if `maxiter' < 1 {
        display as error "maxiter() must be >= 1"
        exit 198
    }
    if `prior' <= 0 | `prior' >= 1 {
        display as error "prior() must be between 0 and 1"
        exit 198
    }

    * --- Load model (if specified) ---
    * Must happen before config writing so we can inject mprob/uprob/prior
    if `"`loadmodel'"' != "" {
        local n_comp_tmp : word count `varlist'
        _splink_load_model "`loadmodel'" `n_comp_tmp'
        local mprob "`r(mprob)'"
        local uprob "`r(uprob)'"
        local prior = r(lambda)
        * Force score mode
        local subcmd ""
        local mode_code = 2
    }

    * Handle replace
    if "`replace'" != "" {
        capture drop `generate'
    }
    confirm new variable `generate'

    * --- Comparison variables ---
    local compvars `varlist'
    local n_comp : word count `compvars'

    * --- Parse compare() option (overrides compvars/compmethod/complevels) ---
    if `"`compare'"' != "" {
        local compvars ""
        local comp_methods ""
        local all_thresholds ""
        local n_comp = 0
        local _mc_n = 0   /* multi-column tempvar counter */

        * Parse semicolon-separated comparison specs
        local cmp_remaining `"`compare'"'
        while `"`cmp_remaining'"' != "" {
            local scpos = strpos(`"`cmp_remaining'"', ";")
            if `scpos' > 0 {
                local cmp_seg = strtrim(substr(`"`cmp_remaining'"', 1, `scpos' - 1))
                local cmp_remaining = strtrim(substr(`"`cmp_remaining'"', `scpos' + 1, .))
            }
            else {
                local cmp_seg = strtrim(`"`cmp_remaining'"')
                local cmp_remaining ""
            }
            if "`cmp_seg'" == "" continue

            * Split at comma: "var1 var2, method(thresh)" or "var1, method"
            local commapos = strpos("`cmp_seg'", ",")
            if `commapos' > 0 {
                local cmp_vars = strtrim(substr("`cmp_seg'", 1, `commapos' - 1))
                local cmp_spec = strtrim(substr("`cmp_seg'", `commapos' + 1, .))
            }
            else {
                local cmp_vars = strtrim("`cmp_seg'")
                local cmp_spec "jw"
            }

            * Parse method and thresholds from spec: "jw(0.92,0.80)" or "namesw" or "distance_km(10,50,100)"
            local lparen = strpos("`cmp_spec'", "(")
            if `lparen' > 0 {
                local cmp_method = substr("`cmp_spec'", 1, `lparen' - 1)
                local cmp_thresh = substr("`cmp_spec'", `lparen' + 1, .)
                * Strip trailing )
                local rp = strpos("`cmp_thresh'", ")")
                if `rp' > 0 {
                    local cmp_thresh = substr("`cmp_thresh'", 1, `rp' - 1)
                }
            }
            else {
                local cmp_method "`cmp_spec'"
                local cmp_thresh ""
            }
            local cmp_method = strtrim("`cmp_method'")

            * Count vars in this comparison
            local nv : word count `cmp_vars'

            if `nv' > 1 {
                * Multi-column comparison: concatenate vars with tab separator
                local _mc_n = `_mc_n' + 1
                tempvar _mc_`_mc_n'
                quietly gen str244 `_mc_`_mc_n'' = ""
                local first_mc = 1
                foreach mv of local cmp_vars {
                    capture confirm string variable `mv'
                    if _rc == 0 {
                        * String var
                        if `first_mc' {
                            quietly replace `_mc_`_mc_n'' = `mv'
                            local first_mc = 0
                        }
                        else {
                            quietly replace `_mc_`_mc_n'' = `_mc_`_mc_n'' + char(9) + `mv'
                        }
                    }
                    else {
                        * Numeric var — convert to string
                        if `first_mc' {
                            quietly replace `_mc_`_mc_n'' = string(`mv')
                            local first_mc = 0
                        }
                        else {
                            quietly replace `_mc_`_mc_n'' = `_mc_`_mc_n'' + char(9) + string(`mv')
                        }
                    }
                }
                local compvars "`compvars' `_mc_`_mc_n''"
            }
            else {
                * Single-column comparison
                local compvars "`compvars' `cmp_vars'"
            }

            local comp_methods "`comp_methods' `cmp_method'"
            local n_comp = `n_comp' + 1

            * Build thresholds string
            if `n_comp' > 1 {
                local all_thresholds "`all_thresholds'|"
            }
            local all_thresholds "`all_thresholds'`cmp_thresh'"
        }

        local compvars = strtrim("`compvars'")
        local comp_methods = strtrim("`comp_methods'")
        local compmethod "`comp_methods'"
        local complevels "`all_thresholds'"
    }

    * --- Determine string/numeric for each comparison variable ---
    local is_string_flags ""
    foreach v of local compvars {
        capture confirm string variable `v'
        if _rc == 0 {
            local is_string_flags "`is_string_flags' 1"
        }
        else {
            local is_string_flags "`is_string_flags' 0"
        }
    }
    local is_string_flags = strtrim("`is_string_flags'")

    * --- Parse comparison methods ---
    * Default: jw for strings, numeric for numeric variables
    local comp_methods ""
    if "`compmethod'" != "" {
        local comp_methods "`compmethod'"
    }
    else {
        forvalues i = 1/`n_comp' {
            local flag : word `i' of `is_string_flags'
            if "`flag'" == "1" {
                local comp_methods "`comp_methods' jw"
            }
            else {
                local comp_methods "`comp_methods' numeric"
            }
        }
        local comp_methods = strtrim("`comp_methods'")
    }

    * Validate method count matches variable count
    local n_methods : word count `comp_methods'
    if `n_methods' != `n_comp' {
        display as error "compmethod() must specify one method per comparison variable"
        display as error "  expected `n_comp' methods, got `n_methods'"
        exit 198
    }

    * Convert method names to integer codes
    * 0=jw, 1=jaro, 2=lev, 3=dl, 4=jaccard, 5=exact, 6=numeric
    * 7=dob, 8=email, 9=postcode, 10=nameswap, 11=name
    * 12=abs_date, 13=distance, 14=cosine, 15=custom
    local method_codes ""
    forvalues i = 1/`n_comp' {
        local m : word `i' of `comp_methods'
        local m = lower("`m'")
        if "`m'" == "jw" | "`m'" == "jarowinkler" | "`m'" == "jaro_winkler" {
            local method_codes "`method_codes' 0"
        }
        else if "`m'" == "jaro" {
            local method_codes "`method_codes' 1"
        }
        else if "`m'" == "lev" | "`m'" == "levenshtein" {
            local method_codes "`method_codes' 2"
        }
        else if "`m'" == "dl" | "`m'" == "damerau_levenshtein" | "`m'" == "damerau-levenshtein" {
            local method_codes "`method_codes' 3"
        }
        else if "`m'" == "jaccard" {
            local method_codes "`method_codes' 4"
        }
        else if "`m'" == "exact" {
            local method_codes "`method_codes' 5"
        }
        else if "`m'" == "numeric" | "`m'" == "num" | "`m'" == "distance" {
            local method_codes "`method_codes' 6"
        }
        else if "`m'" == "dob" | "`m'" == "dateofbirth" {
            local method_codes "`method_codes' 7"
        }
        else if "`m'" == "email" {
            local method_codes "`method_codes' 8"
        }
        else if "`m'" == "postcode" | "`m'" == "zipcode" {
            local method_codes "`method_codes' 9"
        }
        else if "`m'" == "nameswap" | "`m'" == "namesw" {
            local method_codes "`method_codes' 10"
        }
        else if "`m'" == "name" {
            local method_codes "`method_codes' 11"
        }
        else if "`m'" == "abs_date" | "`m'" == "absdate" {
            local method_codes "`method_codes' 12"
        }
        else if "`m'" == "distance_km" | "`m'" == "haversine" {
            local method_codes "`method_codes' 13"
        }
        else if "`m'" == "cosine" {
            local method_codes "`method_codes' 14"
        }
        else if "`m'" == "custom" {
            local method_codes "`method_codes' 15"
        }
        else {
            display as error "compmethod(): unknown method '`m''"
            display as error "  valid: jw jaro lev dl jaccard exact numeric dob email postcode nameswap name custom"
            exit 198
        }
    }
    local method_codes = strtrim("`method_codes'")

    * --- Parse comparison thresholds ---
    * Default thresholds by method type
    * Format: "thresh1,thresh2,thresh3|thresh4,thresh5|..."  pipe-separated per variable
    local all_thresholds ""
    if "`complevels'" != "" {
        local all_thresholds "`complevels'"
    }
    else {
        * Default thresholds
        forvalues i = 1/`n_comp' {
            local mc : word `i' of `method_codes'
            if `i' > 1 {
                local all_thresholds "`all_thresholds'|"
            }
            if "`mc'" == "0" | "`mc'" == "1" {
                * JW/Jaro: default 0.92, 0.80
                local all_thresholds "`all_thresholds'0.92,0.80"
            }
            else if "`mc'" == "2" | "`mc'" == "3" {
                * Levenshtein/DL: default 1, 2
                local all_thresholds "`all_thresholds'1,2"
            }
            else if "`mc'" == "4" {
                * Jaccard: default 0.80, 0.60
                local all_thresholds "`all_thresholds'0.80,0.60"
            }
            else if "`mc'" == "5" {
                * Exact: no thresholds
                local all_thresholds "`all_thresholds'"
            }
            else if "`mc'" == "6" {
                * Numeric: default 0, 1
                local all_thresholds "`all_thresholds'0,1"
            }
            else if "`mc'" == "7" {
                * DOB: 3 internal levels (year, year+month, exact)
                * No thresholds needed — domain function returns levels directly
                local all_thresholds "`all_thresholds'"
            }
            else if "`mc'" == "8" {
                * Email: 4 internal levels (domain, jw-user, user-exact, exact)
                local all_thresholds "`all_thresholds'"
            }
            else if "`mc'" == "9" {
                * Postcode: 4 internal levels (area, district, sector, exact)
                local all_thresholds "`all_thresholds'"
            }
            else if "`mc'" == "10" {
                * NameSwap: 3 internal levels (jw-swap, exact-swap, exact)
                local all_thresholds "`all_thresholds'"
            }
            else {
                * Other domain/custom: no thresholds
                local all_thresholds "`all_thresholds'"
            }
        }
    }

    * --- Parse blocking rules ---
    * Supports three modes:
    *   1. blockrules("last_name ; city dob_year ; first_name city")  — new syntax
    *   2. blockvar(varlist) + block2/3/4(varlist) — legacy syntax
    *   3. Must specify one of blockvar() or blockrules()

    * Build list of rule varlists: _br_rule_1, _br_rule_2, ...
    local n_block_rules = 0

    local _br_expr_n = 0   /* counter for expression tempvars */

    if `"`blockrules'"' != "" {
        * Parse semicolon-separated blocking rules
        if "`blockvar'" != "" {
            display as text "{txt}note: blockrules() specified; blockvar()/block2-4() ignored"
        }
        local remaining `"`blockrules'"'
        while `"`remaining'"' != "" {
            * Find semicolon
            local scpos = strpos(`"`remaining'"', ";")
            if `scpos' > 0 {
                local segment = strtrim(substr(`"`remaining'"', 1, `scpos' - 1))
                local remaining = strtrim(substr(`"`remaining'"', `scpos' + 1, .))
            }
            else {
                local segment = strtrim(`"`remaining'"')
                local remaining ""
            }
            if "`segment'" != "" {
                * Check for expression tokens (containing parentheses)
                local has_expr = (strpos("`segment'", "(") > 0)
                if `has_expr' {
                    * Parse each space-separated token in the segment
                    local resolved_tokens ""
                    local seg_remaining "`segment'"
                    while "`seg_remaining'" != "" {
                        gettoken tok seg_remaining : seg_remaining
                        local lparen = strpos("`tok'", "(")
                        if `lparen' > 0 {
                            * Expression token — parse function(args)
                            local func = lower(substr("`tok'", 1, `lparen' - 1))
                            local argstr = substr("`tok'", `lparen' + 1, .)
                            * Strip trailing )
                            local rp = strpos("`argstr'", ")")
                            if `rp' > 0 {
                                local argstr = substr("`argstr'", 1, `rp' - 1)
                            }
                            * Generate tempvar
                            local _br_expr_n = `_br_expr_n' + 1
                            tempvar _br_expr_`_br_expr_n'
                            if "`func'" == "substr" {
                                * Parse: varname,start,len
                                tokenize "`argstr'", parse(",")
                                local sv `1'
                                local sstart `3'
                                local slen `5'
                                quietly gen str244 `_br_expr_`_br_expr_n'' = substr(`sv', `sstart', `slen')
                                tokenize  /* clear tokenized locals */
                            }
                            else if "`func'" == "soundex" {
                                quietly gen str244 `_br_expr_`_br_expr_n'' = soundex(`argstr')
                            }
                            else if "`func'" == "year" {
                                quietly gen str244 `_br_expr_`_br_expr_n'' = string(year(`argstr'))
                            }
                            else {
                                * Generic: evaluate as Stata expression
                                capture confirm string variable `argstr'
                                if _rc == 0 {
                                    quietly gen str244 `_br_expr_`_br_expr_n'' = `tok'
                                }
                                else {
                                    quietly gen str244 `_br_expr_`_br_expr_n'' = string(`tok')
                                }
                            }
                            local resolved_tokens "`resolved_tokens' `_br_expr_`_br_expr_n''"
                        }
                        else {
                            * Plain variable name
                            local resolved_tokens "`resolved_tokens' `tok'"
                        }
                    }
                    local resolved_tokens = strtrim("`resolved_tokens'")
                    local n_block_rules = `n_block_rules' + 1
                    local _br_rule_`n_block_rules' "`resolved_tokens'"
                }
                else {
                    * No expressions — plain variable names
                    local n_block_rules = `n_block_rules' + 1
                    local _br_rule_`n_block_rules' "`segment'"
                }
            }
        }
    }
    else if "`blockvar'" != "" {
        * Legacy: blockvar() + optional block2/3/4
        local n_block_rules = 1
        local _br_rule_1 `blockvar'
        if "`block2'" != "" {
            local n_block_rules = 2
            local _br_rule_2 `block2'
        }
        if "`block3'" != "" {
            local n_block_rules = 3
            local _br_rule_3 `block3'
        }
        if "`block4'" != "" {
            local n_block_rules = 4
            local _br_rule_4 `block4'
        }
    }
    else {
        display as error "must specify blockvar() or blockrules()"
        exit 198
    }

    if `n_block_rules' < 1 {
        display as error "at least one blocking rule is required"
        exit 198
    }

    * --- Build blocking key(s) ---
    local block_key_vars ""
    forvalues r = 1/`n_block_rules' {
        local bvars `_br_rule_`r''

        tempvar block_key_`r'
        quietly gen str244 `block_key_`r'' = ""
        local first = 1
        foreach bvar of local bvars {
            capture confirm string variable `bvar'
            if _rc == 0 {
                if `first' {
                    quietly replace `block_key_`r'' = strtrim(strlower(`bvar'))
                    local first = 0
                }
                else {
                    quietly replace `block_key_`r'' = `block_key_`r'' + "||" + strtrim(strlower(`bvar'))
                }
            }
            else {
                if `first' {
                    quietly replace `block_key_`r'' = strtrim(string(`bvar'))
                    local first = 0
                }
                else {
                    quietly replace `block_key_`r'' = `block_key_`r'' + "||" + strtrim(string(`bvar'))
                }
            }
        }
        local block_key_vars "`block_key_vars' `block_key_`r''"
    }
    local block_key_vars = strtrim("`block_key_vars'")

    * --- Mark sample ---
    marksample touse, novarlist
    * Handle blocking variable missingness manually for all rules
    forvalues r = 1/`n_block_rules' {
        local bvars `_br_rule_`r''

        foreach bvar of local bvars {
            capture confirm numeric variable `bvar'
            if _rc == 0 {
                markout `touse' `bvar'
            }
            else {
                quietly replace `touse' = 0 if `bvar' == ""
            }
        }
    }

    * --- Stable merge key ---
    tempvar merge_id
    quietly gen long `merge_id' = _n

    * --- Count sample ---
    quietly count if `touse'
    local N = r(N)
    if `N' < 2 {
        display as error "need at least 2 observations in sample"
        exit 2001
    }

    * --- Create output variable ---
    quietly gen double `generate' = .

    * --- Link variable handling ---
    local has_link = 0
    local link_type_code = 0
    if "`linkvar'" != "" {
        local has_link = 1
        if "`linktype'" == "" | "`linktype'" == "link" {
            local link_type_code = 1
        }
        else if "`linktype'" == "link_and_dedupe" {
            local link_type_code = 2
        }
        else if "`linktype'" == "dedupe" {
            local link_type_code = 0
        }
        else {
            display as error "linktype() must be: dedupe, link, or link_and_dedupe"
            exit 198
        }
    }

    * --- Null weight ---
    local null_code = 0
    if "`nullweight'" != "" {
        if "`nullweight'" == "neutral" {
            local null_code = 0
        }
        else if "`nullweight'" == "penalize" {
            local null_code = 1
        }
        else {
            display as error "nullweight() must be: neutral or penalize"
            exit 198
        }
    }

    * --- Load plugin ---
    _splink_load_plugin

    * --- TF adjustment: identify which variables and compute term frequencies ---
    local tf_flags ""
    forvalues i = 1/`n_comp' {
        local v : word `i' of `compvars'
        local is_tf = 0
        if "`tfadjust'" != "" {
            foreach tfv of local tfadjust {
                if "`tfv'" == "`v'" {
                    local is_tf = 1
                }
            }
        }
        local tf_flags "`tf_flags' `is_tf'"
    }
    local tf_flags = strtrim("`tf_flags'")

    * --- Write TF table files ---
    local tf_files ""
    forvalues i = 1/`n_comp' {
        local tf_flag : word `i' of `tf_flags'
        if "`tf_flag'" == "1" {
            local v : word `i' of `compvars'
            tempfile tf_file_`i'

            * Compute term frequencies for this variable
            preserve
            quietly keep if `touse'
            capture confirm string variable `v'
            if _rc == 0 {
                * String variable: compute freq of each value
                quietly {
                    gen long _tf_n = 1
                    collapse (count) _tf_n, by(`v')
                    egen long _tf_total = total(_tf_n)
                    gen double _tf_freq = _tf_n / _tf_total
                    rename `v' _tf_value
                    keep _tf_value _tf_freq
                    export delimited _tf_value _tf_freq using "`tf_file_`i''", replace
                }
            }
            else {
                * Numeric variable: convert to string for TF lookup
                quietly {
                    gen str50 _tf_value = string(`v')
                    gen long _tf_n = 1
                    collapse (count) _tf_n, by(_tf_value)
                    egen long _tf_total = total(_tf_n)
                    gen double _tf_freq = _tf_n / _tf_total
                    keep _tf_value _tf_freq
                    export delimited _tf_value _tf_freq using "`tf_file_`i''", replace
                }
            }
            restore
            local tf_files "`tf_files' `tf_file_`i''"
        }
        else {
            local tf_files "`tf_files' "
        }
    }

    * --- Write configuration file ---
    tempfile configfile
    tempname cfh
    file open `cfh' using "`configfile'", write text replace

    file write `cfh' "[general]" _n
    file write `cfh' "n_comp=`n_comp'" _n
    file write `cfh' "n_block_rules=`n_block_rules'" _n
    file write `cfh' "link_type=`link_type_code'" _n
    file write `cfh' "null_weight=`null_code'" _n
    file write `cfh' "threshold=`threshold'" _n
    file write `cfh' "prior=`prior'" _n
    file write `cfh' "max_iter=`maxiter'" _n
    file write `cfh' "max_block_size=`maxblocksize'" _n

    local vflag = 0
    if "`verbose'" != "" local vflag = 1
    file write `cfh' "verbose=`vflag'" _n

    * Mode: 0=legacy, 1=train, 2=score
    local mode_code = 0
    if "`subcmd'" == "train" local mode_code = 1
    if "`subcmd'" == "predict" local mode_code = 2
    if "`mode'" == "train" local mode_code = 1
    if "`mode'" == "score" | "`mode'" == "predict" local mode_code = 2
    if "`loadmodel'" != "" local mode_code = 2
    file write `cfh' "mode=`mode_code'" _n

    * u-estimation via random sampling
    local ue_flag = 0
    if "`uestimate'" != "" local ue_flag = 1
    file write `cfh' "estimate_u=`ue_flag'" _n
    file write `cfh' "u_max_pairs=`umaxpairs'" _n
    file write `cfh' "u_seed=`useed'" _n

    if "`savepairs'" != "" {
        file write `cfh' "save_pairs=`savepairs'" _n
    }
    else {
        file write `cfh' "save_pairs=" _n
    }

    * ID variable for output
    if "`id'" != "" {
        file write `cfh' "id_var=`id'" _n
    }
    file write `cfh' _n

    * Write per-variable comparison config
    local tf_file_idx = 0
    forvalues i = 1/`n_comp' {
        local k = `i' - 1
        file write `cfh' "[comparison_`k']" _n

        local v : word `i' of `compvars'
        file write `cfh' "var_name=`v'" _n

        local mc : word `i' of `method_codes'
        file write `cfh' "method=`mc'" _n

        local sf : word `i' of `is_string_flags'
        file write `cfh' "is_string=`sf'" _n

        * Parse thresholds for this variable from pipe-separated string
        * Split all_thresholds by |
        _splink_get_thresh `i' "`all_thresholds'"
        local this_thresh "`r(thresh)'"
        file write `cfh' "thresholds=`this_thresh'" _n

        * TF settings
        local tf_flag : word `i' of `tf_flags'
        file write `cfh' "tf_adjust=`tf_flag'" _n
        file write `cfh' "tf_min=`tfmin'" _n

        if "`tf_flag'" == "1" {
            local tf_file_idx = `tf_file_idx' + 1
            local this_tf_file : word `tf_file_idx' of `tf_files'
            file write `cfh' "tf_file=`this_tf_file'" _n
        }
        else {
            file write `cfh' "tf_file=" _n
        }

        * Fixed m/u probabilities
        if "`mprob'" != "" {
            _splink_get_thresh `i' "`mprob'"
            local this_mprob "`r(thresh)'"
            if "`this_mprob'" != "" {
                file write `cfh' "fix_m=1" _n
                file write `cfh' "fixed_m=`this_mprob'" _n
            }
            else {
                file write `cfh' "fix_m=0" _n
                file write `cfh' "fixed_m=" _n
            }
        }
        else {
            file write `cfh' "fix_m=0" _n
            file write `cfh' "fixed_m=" _n
        }
        if "`uprob'" != "" {
            _splink_get_thresh `i' "`uprob'"
            local this_uprob "`r(thresh)'"
            if "`this_uprob'" != "" {
                file write `cfh' "fix_u=1" _n
                file write `cfh' "fixed_u=`this_uprob'" _n
            }
            else {
                file write `cfh' "fix_u=0" _n
                file write `cfh' "fixed_u=" _n
            }
        }
        else {
            file write `cfh' "fix_u=0" _n
            file write `cfh' "fixed_u=" _n
        }
        file write `cfh' _n
    }

    file close `cfh'

    * --- Diagnostics file ---
    tempfile diagfile

    * --- Verbose flag ---
    if "`verbose'" != "" {
        display as text "Config file written to: `configfile'"
    }

    * --- Preserve and subset ---
    preserve
    quietly keep if `touse'

    * --- Build plugin call ---
    * Variable order: block_keys, compvars, [linkvar], [idvar], generate
    local id_part ""
    if "`id'" != "" local id_part "`id'"

    if `has_link' {
        plugin call splink_plugin `block_key_vars' `compvars' `linkvar' `id_part' `generate', ///
            "`configfile'" "`diagfile'"
    }
    else {
        plugin call splink_plugin `block_key_vars' `compvars' `id_part' `generate', ///
            "`configfile'" "`diagfile'"
    }

    * --- Save results for merge ---
    tempfile results
    quietly keep `merge_id' `generate'
    quietly save `results'
    restore

    * --- Merge predictions back ---
    quietly merge 1:1 `merge_id' using `results', nogenerate update

    * --- Read diagnostics ---
    capture {
        tempname fh
        file open `fh' using "`diagfile'", read text
        file read `fh' line
        while r(eof) == 0 {
            local eqpos = strpos("`line'", "=")
            if `eqpos' > 0 {
                local key = substr("`line'", 1, `eqpos' - 1)
                local val = substr("`line'", `eqpos' + 1, .)
                if "`key'" == "n_pairs" return scalar n_pairs = real("`val'")
                if "`key'" == "n_matches" return scalar n_matches = real("`val'")
                if "`key'" == "n_clusters" return scalar n_clusters = real("`val'")
                if "`key'" == "lambda" return scalar lambda = real("`val'")
                if "`key'" == "em_iterations" return scalar em_iterations = real("`val'")
                * Store m/u params for model saving
                if strpos("`key'", "m_") == 1 | strpos("`key'", "u_") == 1 {
                    local _diag_`key' = "`val'"
                }
                if strpos("`key'", "comp_") == 1 {
                    local _diag_`key' = "`val'"
                }
            }
            file read `fh' line
        }
        file close `fh'
    }

    * --- Save model to JSON (if requested) ---
    if `"`savemodel'"' != "" {
        _splink_save_model "`savemodel'" `n_comp' "`diagfile'"
    }

    * --- Store additional results ---
    return scalar N = `N'
    return scalar threshold = `threshold'
    return scalar prior = `prior'
    return scalar n_block_rules = `n_block_rules'
    return local compvars "`compvars'"
    return local compmethod "`comp_methods'"
    * Store blocking rules
    if "`blockvar'" != "" return local blockvar "`blockvar'"
    forvalues r = 1/`n_block_rules' {
        return local blockrule_`r' "`_br_rule_`r''"
    }
    if "`block2'" != "" return local block2 "`block2'"
    if "`block3'" != "" return local block3 "`block3'"
    if "`block4'" != "" return local block4 "`block4'"

    * --- Summary ---
    display as text ""
    display as text "{hline 60}"
    display as text "  Splink: Probabilistic Record Linkage"
    display as text "{hline 60}"
    display as text "  Observations:     " as result %12.0fc `N'
    capture display as text "  Candidate pairs:  " as result %12.0fc `=r(n_pairs)'
    capture display as text "  Matched pairs:    " as result %12.0fc `=r(n_matches)'
    capture display as text "  Clusters:         " as result %12.0fc `=r(n_clusters)'
    capture display as text "  Lambda (match %): " as result %12.6f `=r(lambda)'
    capture display as text "  EM iterations:    " as result %12.0f `=r(em_iterations)'
    display as text "  Threshold:        " as result %12.3f `threshold'
    display as text "  Prior:            " as result %12.6f `prior'
    display as text "  Blocking rules:   " as result %12.0f `n_block_rules'
    display as text "{hline 60}"
    display as text "  Cluster ID stored in: {res:`generate'}"
    display as text "{hline 60}"
end

* --- Plugin loader ---
program define _splink_load_plugin
    if "${splink_plugin_loaded}" == "1" exit

    capture program splink_plugin, plugin using("splink_plugin.darwin-arm64.plugin")
    if _rc {
        capture program splink_plugin, plugin using("splink_plugin.darwin-x86_64.plugin")
        if _rc {
            capture program splink_plugin, plugin using("splink_plugin.linux-x86_64.plugin")
            if _rc {
                capture program splink_plugin, plugin using("splink_plugin.windows-x86_64.plugin")
                if _rc {
                    display as error "splink: could not load plugin for this platform"
                    display as error "  expected: splink_plugin.{platform}.plugin"
                    exit 601
                }
            }
        }
    }
    global splink_plugin_loaded 1
end

* --- Threshold parser: extract i-th pipe-delimited segment ---
program define _splink_get_thresh, rclass
    args idx all_thresh

    * Parse pipe-separated threshold groups
    local remaining "`all_thresh'"
    local current_idx = 1
    local result ""

    while "`remaining'" != "" & `current_idx' <= `idx' {
        * Find next pipe
        local pipepos = strpos("`remaining'", "|")
        if `pipepos' > 0 {
            local segment = substr("`remaining'", 1, `pipepos' - 1)
            local remaining = substr("`remaining'", `pipepos' + 1, .)
        }
        else {
            local segment "`remaining'"
            local remaining ""
        }

        if `current_idx' == `idx' {
            local result "`segment'"
        }
        local current_idx = `current_idx' + 1
    }

    return local thresh "`result'"
end

* --- Save model parameters to JSON ---
* Reads diagnostics file and writes JSON matching Python splink schema
program define _splink_save_model
    args filepath n_comp diagfile

    * Read all diagnostics into locals
    tempname fh
    file open `fh' using "`diagfile'", read text
    file read `fh' line
    while r(eof) == 0 {
        local eqpos = strpos("`line'", "=")
        if `eqpos' > 0 {
            local key = substr("`line'", 1, `eqpos' - 1)
            local val = substr("`line'", `eqpos' + 1, .)
            local _d_`key' = "`val'"
        }
        file read `fh' line
    }
    file close `fh'

    * Write JSON
    tempname jh
    file open `jh' using "`filepath'", write text replace
    file write `jh' `"{"' _n
    file write `jh' `"  "probability_two_random_records_match": `_d_lambda',"' _n
    file write `jh' `"  "n_comp": `n_comp',"' _n
    file write `jh' `"  "comparisons": ["' _n

    forvalues k = 0/`=`n_comp'-1' {
        local nl = "`_d_comp_`k'_n_levels'"
        local vn = "`_d_comp_`k'_var_name'"
        local meth = "`_d_comp_`k'_method'"
        if "`nl'" == "" local nl = 2
        if "`vn'" == "" local vn = "var_`k'"
        if "`meth'" == "" local meth = 0

        if `k' > 0 file write `jh' `"    ,"' _n
        file write `jh' `"    {"' _n
        file write `jh' `"      "output_column_name": "gamma_`vn'","' _n
        file write `jh' `"      "comparison_description": "`vn'","' _n
        file write `jh' `"      "method": `meth',"' _n
        file write `jh' `"      "comparison_levels": ["' _n

        forvalues l = 0/`=`nl'-1' {
            local mp = "`_d_m_`k'_`l''"
            local up = "`_d_u_`k'_`l''"
            if "`mp'" == "" local mp = 0.5
            if "`up'" == "" local up = 0.5

            if `l' > 0 file write `jh' `"        ,"' _n
            file write `jh' `"        {"' _n
            file write `jh' `"          "sql_condition": "level_`l'","' _n
            file write `jh' `"          "label_for_charts": "Level `l'","' _n
            file write `jh' `"          "m_probability": `mp',"' _n
            file write `jh' `"          "u_probability": `up'"' _n
            file write `jh' `"        }"' _n
        }
        file write `jh' `"      ]"' _n
        file write `jh' `"    }"' _n
    }

    file write `jh' `"  ]"' _n
    file write `jh' `"}"' _n
    file close `jh'

    display as text "Model saved to: `filepath'"
end

* --- Load model parameters from JSON ---
* Reads JSON model file and returns m/u probability strings for config
* Sets locals: _lm_lambda, _lm_mprob, _lm_uprob
program define _splink_load_model, rclass
    args filepath n_comp

    * Simple JSON parser: extract lambda and m/u probabilities
    tempname fh
    file open `fh' using "`filepath'", read text

    local lam = 0.0001
    local in_comp = 0
    local comp_idx = 0
    local in_levels = 0
    local level_idx = 0
    local mprob_all ""
    local uprob_all ""
    local m_str ""
    local u_str ""

    file read `fh' line
    while r(eof) == 0 {
        local line = strtrim(`"`line'"')

        * Extract lambda
        if strpos(`"`line'"', `""probability_two_random_records_match""') > 0 {
            local cpos = strpos(`"`line'"', ":")
            if `cpos' > 0 {
                local vpart = substr(`"`line'"', `cpos' + 1, .)
                local vpart = subinstr("`vpart'", ",", "", .)
                local vpart = strtrim("`vpart'")
                local lam = real("`vpart'")
            }
        }

        * Track comparison array entries
        if strpos(`"`line'"', `""comparison_levels""') > 0 {
            local in_levels = 1
            local level_idx = 0
            local m_str ""
            local u_str ""
        }

        * Extract m_probability
        if `in_levels' & strpos(`"`line'"', `""m_probability""') > 0 {
            local cpos = strpos(`"`line'"', ":")
            if `cpos' > 0 {
                local vpart = substr(`"`line'"', `cpos' + 1, .)
                local vpart = subinstr("`vpart'", ",", "", .)
                local vpart = strtrim("`vpart'")
                if "`m_str'" == "" local m_str "`vpart'"
                else local m_str "`m_str',`vpart'"
            }
        }

        * Extract u_probability
        if `in_levels' & strpos(`"`line'"', `""u_probability""') > 0 {
            local cpos = strpos(`"`line'"', ":")
            if `cpos' > 0 {
                local vpart = substr(`"`line'"', `cpos' + 1, .)
                local vpart = subinstr("`vpart'", ",", "", .)
                local vpart = strtrim("`vpart'")
                if "`u_str'" == "" local u_str "`vpart'"
                else local u_str "`u_str',`vpart'"
            }
            local level_idx = `level_idx' + 1
        }

        * End of comparison_levels array
        if `in_levels' & strpos(`"`line'"', "]") > 0 & strpos(`"`line'"', "[") == 0 {
            local in_levels = 0
            if "`mprob_all'" == "" {
                local mprob_all "`m_str'"
                local uprob_all "`u_str'"
            }
            else {
                local mprob_all "`mprob_all'|`m_str'"
                local uprob_all "`uprob_all'|`u_str'"
            }
            local comp_idx = `comp_idx' + 1
        }

        file read `fh' line
    }
    file close `fh'

    return scalar lambda = `lam'
    return local mprob "`mprob_all'"
    return local uprob "`uprob_all'"
    display as text "Model loaded from: `filepath' (lambda=`lam', `comp_idx' comparisons)"
end
