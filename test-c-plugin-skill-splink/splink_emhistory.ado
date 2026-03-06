*! version 4.2.0  06mar2026
*! EM iteration history chart from splink diagnostics
*! Plots lambda convergence and max parameter change per iteration

program define splink_emhistory
    version 14.0

    syntax using/ [, SAVing(string)]

    * Parse diagnostics file for EM history
    tempname fh
    file open `fh' using `"`using'"', read text

    local em_n = 0
    file read `fh' line
    while r(eof) == 0 {
        local eqpos = strpos("`line'", "=")
        if `eqpos' > 0 {
            local key = substr("`line'", 1, `eqpos' - 1)
            local val = substr("`line'", `eqpos' + 1, .)

            if "`key'" == "em_history_n" {
                local em_n = real("`val'")
            }
            else if substr("`key'", 1, 8) == "em_hist_" {
                * Parse em_hist_N_lambda or em_hist_N_maxchange
                local rest = substr("`key'", 9, .)
                local upos = strpos("`rest'", "_")
                if `upos' > 0 {
                    local iter = substr("`rest'", 1, `upos' - 1)
                    local field = substr("`rest'", `upos' + 1, .)
                    local _em_`field'_`iter' = real("`val'")
                }
            }
        }
        file read `fh' line
    }
    file close `fh'

    if `em_n' == 0 {
        display as error "no EM iteration history found in diagnostics file"
        display as error "  run splink with verbose option to generate diagnostics"
        exit 198
    }

    * Build dataset
    preserve
    quietly {
        clear
        set obs `em_n'
        gen int iteration = _n
        gen double lambda = .
        gen double max_change = .

        forvalues i = 1/`em_n' {
            local idx = `i' - 1
            if "`_em_lambda_`idx''" != "" {
                replace lambda = `_em_lambda_`idx'' in `i'
            }
            if "`_em_maxchange_`idx''" != "" {
                replace max_change = `_em_maxchange_`idx'' in `i'
            }
        }
    }

    * Plot with dual y-axes
    twoway (connected lambda iteration, ///
                lcolor(navy) mcolor(navy) msymbol(circle) yaxis(1)) ///
           (connected max_change iteration, ///
                lcolor(cranberry) mcolor(cranberry) msymbol(triangle) yaxis(2)), ///
        ytitle("Lambda (match proportion)", axis(1)) ///
        ytitle("Max Parameter Change", axis(2)) ///
        xtitle("EM Iteration") ///
        title("EM Convergence History") ///
        legend(order(1 "Lambda" 2 "Max Change") rows(1) position(6)) ///
        graphregion(color(white)) scheme(s2color)

    if `"`saving'"' != "" {
        graph export `"`saving'"', replace
        display as text "Chart saved to: `saving'"
    }

    * Display summary
    display as text ""
    display as text "{hline 50}"
    display as text "  EM Iteration History"
    display as text "{hline 50}"
    display as text "  Iterations:       " as result %10.0f `em_n'
    display as text "  Final lambda:     " as result %10.6f lambda[_N]
    quietly summarize max_change
    display as text "  Final max change: " as result %10.8f max_change[_N]
    display as text "{hline 50}"

    restore
end
