*! version 4.2.0  06mar2026
*! Graph-level metrics for record linkage clusters
*! Computes node degree, cluster density from savepairs output

program define splink_graph_metrics, rclass
    version 14.0

    syntax using/ [, THReshold(real 0.5) CLuster(string) Detail]

    preserve
    quietly import delimited `"`using'"', clear

    capture confirm variable match_probability
    if _rc {
        display as error "CSV must contain match_probability column"
        restore
        exit 198
    }

    quietly {
        * Keep only pairs above threshold
        keep if match_probability >= `threshold'
        local n_edges = _N
    }

    if `n_edges' == 0 {
        display as error "no pairs above threshold `threshold'"
        restore
        exit 198
    }

    quietly {

        * Determine ID columns
        local id_l "unique_id_l"
        local id_r "unique_id_r"
        capture confirm variable unique_id_l
        if _rc {
            local id_l "obs_a"
            local id_r "obs_b"
        }
        capture confirm variable `id_l'
        if _rc {
            display as error "CSV must contain unique_id_l/unique_id_r or obs_a/obs_b columns"
            restore
            exit 198
        }
        capture confirm variable `id_r'
        if _rc {
            display as error "CSV must contain `id_r' column"
            restore
            exit 198
        }

        * Determine cluster column
        local clust_var "cluster_id"
        if `"`cluster'"' != "" {
            local clust_var "`cluster'"
        }
        capture confirm variable `clust_var'
        local has_cluster = (_rc == 0)

        if `has_cluster' {
            * --- Per-cluster metrics ---
            * Count edges and nodes per cluster
            tempfile edges
            save `edges'

            * Get unique nodes per cluster: stack left and right IDs
            keep `id_l' `clust_var'
            rename `id_l' _node_id
            tempfile left_nodes
            save `left_nodes'
            use `edges', clear
            keep `id_r' `clust_var'
            rename `id_r' _node_id
            append using `left_nodes'
            duplicates drop _node_id `clust_var', force

            * Count nodes per cluster
            bysort `clust_var': gen long _n_nodes = _N
            bysort `clust_var': gen byte _first = (_n == 1)
            keep if _first
            keep `clust_var' _n_nodes
            tempfile node_counts
            save `node_counts'

            * Count edges per cluster
            use `edges', clear
            bysort `clust_var': gen long _n_edges = _N
            bysort `clust_var': gen byte _first = (_n == 1)
            keep if _first
            keep `clust_var' _n_edges
            merge 1:1 `clust_var' using `node_counts', nogenerate

            * Compute density: 2*edges / (nodes*(nodes-1))
            gen double density = .
            replace density = 1 if _n_nodes <= 1
            replace density = 2 * _n_edges / (_n_nodes * (_n_nodes - 1)) if _n_nodes > 1

            local n_clusters = _N
        }
        else {
            * --- Global metrics (no cluster info) ---
            * Stack all node IDs to compute degree
            keep `id_l' `id_r'
            tempfile edges
            save `edges'

            keep `id_l'
            rename `id_l' _node_id
            tempfile left_ids
            save `left_ids'
            use `edges', clear
            keep `id_r'
            rename `id_r' _node_id
            append using `left_ids'

            bysort _node_id: gen long _degree = _N
            bysort _node_id: gen byte _first = (_n == 1)
            keep if _first

            local n_nodes = _N
        }
    }

    * Display results
    display as text ""
    display as text "{hline 60}"
    display as text "  Splink Graph Metrics (threshold >= " as result %5.3f `threshold' as text ")"
    display as text "{hline 60}"
    display as text "  Total edges (pairs): " as result %10.0fc `n_edges'

    if `has_cluster' {
        display as text "  Clusters:            " as result %10.0fc `n_clusters'
        quietly {
            summarize _n_nodes
            local mean_nodes = r(mean)
            local max_nodes = r(max)
            summarize _n_edges
            local mean_edges = r(mean)
            local max_edges = r(max)
            summarize density
            local mean_density = r(mean)
            local min_density = r(min)
        }
        display as text ""
        display as text "  Nodes per cluster:"
        display as text "    Mean:              " as result %10.1f `mean_nodes'
        display as text "    Max:               " as result %10.0f `max_nodes'
        display as text "  Edges per cluster:"
        display as text "    Mean:              " as result %10.1f `mean_edges'
        display as text "    Max:               " as result %10.0f `max_edges'
        display as text "  Cluster density:"
        display as text "    Mean:              " as result %10.4f `mean_density'
        display as text "    Min:               " as result %10.4f `min_density'

        * Flag potential hairball clusters (low density + many nodes)
        quietly count if density < 0.5 & _n_nodes > 3
        local n_hairballs = r(N)
        if `n_hairballs' > 0 {
            display as text ""
            display as text "  Warning: " as result `n_hairballs' as text " cluster(s) with density < 0.5 and > 3 nodes"
            display as text "  These may be 'hairball' clusters worth reviewing."
        }

        if "`detail'" != "" {
            display as text ""
            display as text "  {hline 50}"
            display as text "  " _col(5) "Cluster" _col(18) "Nodes" _col(28) "Edges" _col(40) "Density"
            display as text "  {hline 50}"
            local n_show = min(_N, 20)
            gsort -_n_nodes
            forvalues i = 1/`n_show' {
                local cid = `clust_var'[`i']
                local nn = _n_nodes[`i']
                local ne = _n_edges[`i']
                local dd = density[`i']
                display as text "  " _col(5) "`cid'" ///
                    _col(18) as result %5.0f `nn' ///
                    _col(28) as result %5.0f `ne' ///
                    _col(38) as result %8.4f `dd'
            }
            if _N > 20 {
                display as text "  ... (`=_N - 20' more clusters)"
            }
        }

        return scalar n_clusters = `n_clusters'
        return scalar mean_density = `mean_density'
        return scalar min_density = `min_density'
        return scalar max_nodes = `max_nodes'
        return scalar n_hairballs = `n_hairballs'
    }
    else {
        display as text "  Total nodes:         " as result %10.0fc `n_nodes'
        quietly {
            summarize _degree
            local mean_degree = r(mean)
            local max_degree = r(max)
            local min_degree = r(min)
        }
        display as text "  Node degree:"
        display as text "    Mean:              " as result %10.2f `mean_degree'
        display as text "    Max:               " as result %10.0f `max_degree'
        display as text "    Min:               " as result %10.0f `min_degree'

        return scalar n_nodes = `n_nodes'
        return scalar mean_degree = `mean_degree'
        return scalar max_degree = `max_degree'
    }

    display as text "{hline 60}"

    return scalar n_edges = `n_edges'
    return scalar threshold = `threshold'

    restore
end
