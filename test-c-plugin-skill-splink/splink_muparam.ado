*! version 4.2.0  06mar2026
*! M/U parameter chart for probabilistic record linkage
*! Reads a splink model JSON and plots m vs u probabilities

program define splink_muparam
    version 14.0

    syntax using/ [, SAVing(string)]

    * Parse JSON line-by-line to extract m/u parameters
    * Track current comparison name and collect m, u per level
    tempname fh
    file open `fh' using `"`using'"', read text

    local n_levels = 0
    local cur_comp ""
    local cur_m ""
    local cur_u ""
    local level_idx = 0

    file read `fh' line
    while r(eof) == 0 {
        local trimmed = strtrim(`"`line'"')

        * Detect comparison name
        if strpos(`"`trimmed'"', `""output_column_name""') > 0 {
            * Extract value after colon between quotes
            local after = substr(`"`trimmed'"', strpos(`"`trimmed'"', ":") + 1, .)
            local after = subinstr(`"`after'"', `"""', "", .)
            local after = subinstr(`"`after'"', ",", "", .)
            local cur_comp = strtrim(`"`after'"')
            local level_idx = 0
        }

        * Detect m_probability
        if strpos(`"`trimmed'"', `""m_probability""') > 0 {
            local after = substr(`"`trimmed'"', strpos(`"`trimmed'"', ":") + 1, .)
            local after = subinstr(`"`after'"', ",", "", .)
            local cur_m = strtrim(`"`after'"')
        }

        * Detect u_probability -- this follows m, so save the level
        if strpos(`"`trimmed'"', `""u_probability""') > 0 {
            local after = substr(`"`trimmed'"', strpos(`"`trimmed'"', ":") + 1, .)
            local after = subinstr(`"`after'"', ",", "", .)
            local cur_u = strtrim(`"`after'"')

            * Only store if we have both m and u (skip null levels)
            if "`cur_m'" != "" {
                local level_idx = `level_idx' + 1
                local n_levels = `n_levels' + 1
                local comp_`n_levels' "`cur_comp'"
                local mval_`n_levels' "`cur_m'"
                local uval_`n_levels' "`cur_u'"
                local lidx_`n_levels' = `level_idx'
            }
            local cur_m ""
            local cur_u ""
        }

        * Reset m when hitting is_null_level (null levels lack m_probability)
        if strpos(`"`trimmed'"', `""is_null_level""') > 0 {
            local cur_m ""
        }

        file read `fh' line
    }
    file close `fh'

    if `n_levels' == 0 {
        display as error "no m/u parameters found in model"
        exit 198
    }

    * Build dataset
    preserve
    quietly {
        clear
        set obs `n_levels'
        gen str80 comp = ""
        gen str100 label = ""
        gen double m_prob = .
        gen double u_prob = .

        forvalues i = 1/`n_levels' {
            replace comp = "`comp_`i''" in `i'
            replace label = "`comp_`i'' L`lidx_`i''" in `i'
            replace m_prob = real("`mval_`i''") in `i'
            replace u_prob = real("`uval_`i''") in `i'
        }

        gen int bar_pos = _n
        gen double m_pos = bar_pos - 0.15
        gen double u_pos = bar_pos + 0.15

        * Create value labels for bar positions (replace to avoid stale labels)
        capture label drop _mu_params
        forvalues i = 1/`n_levels' {
            label define _mu_params `i' "`comp_`i'' L`lidx_`i''", add
        }
        label values bar_pos _mu_params
    }

    * Generate grouped bar chart
    local gopts ""
    if `"`saving'"' != "" {
        local gopts `"saving(`saving', replace)"'
    }

    twoway (bar m_prob m_pos, barwidth(0.28) color(navy) fintensity(80)) ///
           (bar u_prob u_pos, barwidth(0.28) color(cranberry) fintensity(80)), ///
        legend(order(1 "m (match)" 2 "u (non-match)") rows(1)) ///
        xlabel(1(1)`=_N', valuelabel angle(45) labsize(vsmall)) ///
        xtitle("Comparison Level") ytitle("Probability") ///
        title("M and U Probabilities by Comparison Level") ///
        ylabel(0(0.2)1) scheme(s2color) `gopts'

    display as text ""
    display as text "M/U parameter chart created from: `using'"
    display as text "Levels plotted: " as result _N

    restore
end
