*! version 1.0.0  26feb2026
*! Evaluation metrics for probabilistic record linkage
*! Computes precision, recall, F1 at pair level from labeled data

program define splink_evaluate, rclass
    version 14.0

    syntax using/, PREDicted(string) TRUE(string) ///
        [THReshold(real 0.5) Detail]

    * Load pairwise output
    preserve
    quietly {
        import delimited `using', clear

        * Predicted match: match_probability >= threshold
        gen byte _pred_match = match_probability >= `threshold'

        * True match from labels
        rename `predicted' _pred_id
        rename `true' _true_id
    }

    * Compute confusion matrix
    quietly {
        count if _pred_match == 1 & _true_id == 1
        local tp = r(N)
        count if _pred_match == 1 & _true_id == 0
        local fp = r(N)
        count if _pred_match == 0 & _true_id == 1
        local fn = r(N)
        count if _pred_match == 0 & _true_id == 0
        local tn = r(N)
    }

    * Compute metrics
    local precision = 0
    local recall = 0
    local f1 = 0
    local accuracy = 0

    if `tp' + `fp' > 0 local precision = `tp' / (`tp' + `fp')
    if `tp' + `fn' > 0 local recall = `tp' / (`tp' + `fn')
    if `precision' + `recall' > 0 {
        local f1 = 2 * `precision' * `recall' / (`precision' + `recall')
    }
    local total = `tp' + `fp' + `fn' + `tn'
    if `total' > 0 local accuracy = (`tp' + `tn') / `total'

    restore

    * Display results
    display as text ""
    display as text "{hline 50}"
    display as text "  Splink Evaluation (threshold = " as result %5.3f `threshold' as text ")"
    display as text "{hline 50}"
    display as text "  True Positives:   " as result %10.0fc `tp'
    display as text "  False Positives:  " as result %10.0fc `fp'
    display as text "  False Negatives:  " as result %10.0fc `fn'
    display as text "  True Negatives:   " as result %10.0fc `tn'
    display as text "{hline 50}"
    display as text "  Precision:        " as result %10.6f `precision'
    display as text "  Recall:           " as result %10.6f `recall'
    display as text "  F1 Score:         " as result %10.6f `f1'
    display as text "  Accuracy:         " as result %10.6f `accuracy'
    display as text "{hline 50}"

    * Return scalars
    return scalar tp = `tp'
    return scalar fp = `fp'
    return scalar fn = `fn'
    return scalar tn = `tn'
    return scalar precision = `precision'
    return scalar recall = `recall'
    return scalar f1 = `f1'
    return scalar accuracy = `accuracy'
    return scalar threshold = `threshold'
end
