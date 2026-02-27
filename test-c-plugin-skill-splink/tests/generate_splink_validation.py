#!/usr/bin/env python3
"""Generate splink validation data for Stata comparison.

Creates a small test dataset (50 records, ~15 true entities with known
duplicates), then runs Python splink under seven configurations and exports
all intermediate results for comparison with Stata output.

Requirements:
    pip install 'splink>=4.0.15' pandas numpy

Usage:
    python tests/generate_splink_validation.py
"""

import json
import os
import sys
import warnings

warnings.filterwarnings("ignore")

# ---------------------------------------------------------------------------
# Check splink is available
# ---------------------------------------------------------------------------
try:
    import splink
    from splink import DuckDBAPI, Linker, SettingsCreator, block_on
    import splink.comparison_library as cl
except ImportError:
    print(
        "ERROR: splink is not installed.\n"
        "  pip install 'splink>=4.0.15'\n"
        "  (version 4.0.6 has a known bug in EM training; use 4.0.15+)"
    )
    sys.exit(1)

import numpy as np
import pandas as pd

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "validation_data")
SEED = 42


# ===================================================================
# 1. Generate test data
# ===================================================================

def generate_test_data(seed=SEED):
    """Generate ~50 records with 15 true entities and known duplicates.

    Each entity has a fixed number of duplicate records (pre-assigned to
    hit exactly 50 total).  Duplicates have realistic variations:
    transpositions, single-char edits, missing values, and alternative
    representations.  City is kept clean so blocking on city works well.

    Returns:
        DataFrame with columns: unique_id, first_name, last_name, dob,
        city, email, entity_id
    """
    rng = np.random.default_rng(seed)

    # Ground-truth entities (15 distinct people across 3 cities)
    entities = [
        # --- chicago (5 entities) ---
        {"first_name": "james",       "last_name": "smith",     "dob": "1985-03-12", "city": "chicago",  "email": "jsmith85@gmail.com"},
        {"first_name": "jennifer",    "last_name": "williams",  "dob": "1992-01-18", "city": "chicago",  "email": "jwilliams92@gmail.com"},
        {"first_name": "david",       "last_name": "martinez",  "dob": "1988-12-01", "city": "chicago",  "email": "dmartinez@yahoo.com"},
        {"first_name": "emily",       "last_name": "thomas",    "dob": "1993-02-17", "city": "chicago",  "email": "ethomas93@gmail.com"},
        {"first_name": "christopher", "last_name": "jackson",   "dob": "1982-07-16", "city": "chicago",  "email": "cjackson82@hotmail.com"},
        # --- houston (5 entities) ---
        {"first_name": "maria",       "last_name": "garcia",    "dob": "1990-07-22", "city": "houston",  "email": "mgarcia90@yahoo.com"},
        {"first_name": "michael",     "last_name": "brown",     "dob": "1983-06-30", "city": "houston",  "email": "mbrown83@hotmail.com"},
        {"first_name": "jessica",     "last_name": "anderson",  "dob": "1991-04-25", "city": "houston",  "email": "janderson91@gmail.com"},
        {"first_name": "william",     "last_name": "hernandez", "dob": "1980-10-28", "city": "houston",  "email": "whernandez@yahoo.com"},
        {"first_name": "amanda",      "last_name": "lee",       "dob": "1994-11-22", "city": "houston",  "email": "alee94@gmail.com"},
        # --- phoenix (5 entities) ---
        {"first_name": "robert",      "last_name": "johnson",   "dob": "1978-11-05", "city": "phoenix",  "email": "rjohnson@outlook.com"},
        {"first_name": "sarah",       "last_name": "davis",     "dob": "1995-09-14", "city": "phoenix",  "email": "sdavis95@gmail.com"},
        {"first_name": "daniel",      "last_name": "taylor",    "dob": "1976-08-09", "city": "phoenix",  "email": "dtaylor76@outlook.com"},
        {"first_name": "ashley",      "last_name": "moore",     "dob": "1987-05-03", "city": "phoenix",  "email": "amoore87@gmail.com"},
        {"first_name": "matthew",     "last_name": "wilson",    "dob": "1979-03-08", "city": "phoenix",  "email": "mwilson79@outlook.com"},
    ]

    # Pre-assign duplicate counts so total = 50 (15 originals + 35 dups)
    # Pattern: some entities get 2 dups, some get 3
    dup_counts = [3, 2, 2, 3, 2, 3, 2, 2, 3, 2, 3, 2, 2, 2, 2]
    assert len(dup_counts) == len(entities)
    assert sum(dup_counts) + len(entities) == 50

    def swap_adjacent(s, rng):
        """Transpose two adjacent characters."""
        if len(s) < 3:
            return s
        pos = rng.integers(0, len(s) - 1)
        chars = list(s)
        chars[pos], chars[pos + 1] = chars[pos + 1], chars[pos]
        return "".join(chars)

    def single_char_edit(s, rng):
        """Replace one character with a random letter."""
        if len(s) < 2:
            return s
        chars = list(s)
        pos = rng.integers(0, len(chars))
        chars[pos] = chr(rng.integers(ord("a"), ord("z") + 1))
        return "".join(chars)

    def delete_char(s, rng):
        """Delete one character."""
        if len(s) < 3:
            return s
        pos = rng.integers(1, len(s))
        return s[:pos] + s[pos + 1:]

    def corrupt_name(value, rng):
        """Apply a realistic corruption to a name field."""
        action = rng.integers(0, 4)
        if action == 0:
            return swap_adjacent(value, rng)
        elif action == 1:
            return single_char_edit(value, rng)
        elif action == 2:
            return delete_char(value, rng)
        else:
            # Nickname / abbreviation
            return value[:3] if len(value) > 4 else value

    def corrupt_dob(value, rng):
        """Off-by-one in day or month."""
        parts = value.split("-")
        which = rng.integers(0, 2)  # month or day
        if which == 0 and int(parts[1]) < 12:
            parts[1] = f"{int(parts[1]) + 1:02d}"
        elif int(parts[2]) < 28:
            parts[2] = f"{int(parts[2]) + 1:02d}"
        return "-".join(parts)

    def corrupt_email(value, rng):
        """Typo in local part or different domain."""
        local, domain = value.split("@")
        action = rng.integers(0, 3)
        if action == 0:
            return swap_adjacent(local, rng) + "@" + domain
        elif action == 1:
            return local + "@gmail.com"
        else:
            return ""  # missing

    records = []
    uid = 0

    for entity_id, (entity, n_dups) in enumerate(
        zip(entities, dup_counts), start=1
    ):
        # Always include the clean original
        uid += 1
        records.append({
            "unique_id": uid,
            "entity_id": entity_id,
            **entity,
        })

        for _ in range(n_dups):
            uid += 1
            rec = {"unique_id": uid, "entity_id": entity_id}

            # Corrupt each field with some probability.
            # City is NEVER corrupted so blocking on city always works.
            rec["first_name"] = (
                corrupt_name(entity["first_name"], rng)
                if rng.random() < 0.5
                else entity["first_name"]
            )
            rec["last_name"] = (
                corrupt_name(entity["last_name"], rng)
                if rng.random() < 0.4
                else entity["last_name"]
            )
            rec["dob"] = (
                corrupt_dob(entity["dob"], rng)
                if rng.random() < 0.25
                else entity["dob"]
            )
            rec["city"] = entity["city"]  # always correct
            rec["email"] = (
                corrupt_email(entity["email"], rng)
                if rng.random() < 0.35
                else entity["email"]
            )

            # Occasionally make a field entirely missing (~10% of dups)
            if rng.random() < 0.10:
                drop_field = rng.choice(
                    ["first_name", "last_name", "dob", "email"]
                )
                rec[drop_field] = ""

            records.append(rec)

    df = pd.DataFrame(records)

    # Shuffle so duplicates are not adjacent
    df = df.sample(frac=1, random_state=seed).reset_index(drop=True)
    # Re-assign sequential unique_id after shuffle
    df["unique_id"] = range(1, len(df) + 1)

    # Replace empty strings with None for splink null handling
    df = df.replace("", None)

    return df


# ===================================================================
# 2. Run splink configurations
# ===================================================================

def run_config(df, config_name, settings, em_blocking_rules, output_dir,
               predict_threshold=0.5, cluster_threshold=0.85):
    """Run a single splink configuration and export all results.

    Args:
        df: Input DataFrame (must have 'unique_id' and 'entity_id' columns)
        config_name: Short identifier for this configuration
        settings: SettingsCreator instance
        em_blocking_rules: List of blocking rules for EM training
        output_dir: Directory for output files
        predict_threshold: Match probability threshold for predictions
        cluster_threshold: Match probability threshold for clustering

    Returns:
        dict with predictions_df, clusters_df, model_json
    """
    print(f"\n{'='*60}")
    print(f"Configuration: {config_name}")
    print(f"{'='*60}")

    linker = Linker(df, settings, db_api=DuckDBAPI())

    # --- Estimate u parameters ---
    linker.training.estimate_u_using_random_sampling(max_pairs=1e6)

    # --- Estimate m parameters using ground-truth labels ---
    # Since we have entity_id, use it for accurate m estimation.
    # This is more reliable than EM on a 50-record dataset.
    linker.training.estimate_m_from_label_column("entity_id")

    # --- Also run EM training for the columns that need it ---
    # EM fills in any parameters not covered by the label-based approach
    for br in em_blocking_rules:
        try:
            linker.training.estimate_parameters_using_expectation_maximisation(br)
        except Exception as e:
            print(f"  WARNING: EM training with {br} failed: {e}")

    # --- Estimate overall match probability ---
    linker.training.estimate_probability_two_random_records_match(
        em_blocking_rules, recall=0.8
    )

    # --- Predict ---
    predictions = linker.inference.predict(
        threshold_match_probability=predict_threshold
    )
    preds_df = predictions.as_pandas_dataframe()
    print(f"  Predictions: {len(preds_df)} pairs above {predict_threshold}")

    # --- Cluster ---
    clusters = linker.clustering.cluster_pairwise_predictions_at_threshold(
        predictions, threshold_match_probability=cluster_threshold
    )
    clusters_df = clusters.as_pandas_dataframe()
    print(
        f"  Clusters: {clusters_df['cluster_id'].nunique()} clusters "
        f"from {len(clusters_df)} records (threshold={cluster_threshold})"
    )

    # --- Export model parameters ---
    model_json = linker.misc.save_model_to_json()

    # --- Save everything ---
    prefix = os.path.join(output_dir, config_name)

    # Predictions CSV
    preds_df.to_csv(f"{prefix}_predictions.csv", index=False)
    print(f"  Saved: {config_name}_predictions.csv ({len(preds_df)} rows)")

    # Clusters CSV
    clusters_df.to_csv(f"{prefix}_clusters.csv", index=False)
    print(f"  Saved: {config_name}_clusters.csv ({len(clusters_df)} rows)")

    # Model parameters JSON
    with open(f"{prefix}_model.json", "w") as f:
        json.dump(model_json, f, indent=2, default=str)
    print(f"  Saved: {config_name}_model.json")

    # m/u parameter summary CSV
    mu_records = []
    for comp in model_json.get("comparisons", []):
        comp_name = comp.get("output_column_name", "unknown")
        for level in comp.get("comparison_levels", []):
            mu_records.append({
                "comparison": comp_name,
                "level": level.get("comparison_vector_value"),
                "label": level.get("label_for_charts", ""),
                "m_probability": level.get("m_probability"),
                "u_probability": level.get("u_probability"),
                "is_null_level": level.get("is_null_level", False),
            })
    mu_df = pd.DataFrame(mu_records)
    mu_df.to_csv(f"{prefix}_m_u_params.csv", index=False)
    print(f"  Saved: {config_name}_m_u_params.csv ({len(mu_df)} rows)")

    # Pairwise predictions with gamma columns CSV
    gamma_cols = [c for c in preds_df.columns if c.startswith("gamma_")]
    if gamma_cols:
        keep_cols = (
            ["unique_id_l", "unique_id_r", "match_weight", "match_probability"]
            + gamma_cols
        )
        # Also keep bf_ (Bayes factor) columns if present
        bf_cols = [c for c in preds_df.columns if c.startswith("bf_")]
        keep_cols += bf_cols
        # Keep tf_ columns if present
        tf_cols = [c for c in preds_df.columns if c.startswith("tf_")]
        keep_cols += tf_cols
        # Only keep columns that actually exist
        keep_cols = [c for c in keep_cols if c in preds_df.columns]
        gamma_df = preds_df[keep_cols].copy()
        gamma_df.to_csv(f"{prefix}_gamma_predictions.csv", index=False)
        print(f"  Saved: {config_name}_gamma_predictions.csv ({len(gamma_df)} rows, {len(gamma_cols)} gamma cols)")

    return {
        "predictions_df": preds_df,
        "clusters_df": clusters_df,
        "model_json": model_json,
    }


# ===================================================================
# 3. Configuration definitions
# ===================================================================

def config_a_jw_city(df, output_dir):
    """Config A: Default Jaro-Winkler comparisons, blocking on city."""
    settings = SettingsCreator(
        link_type="dedupe_only",
        comparisons=[
            cl.JaroWinklerAtThresholds("first_name", [0.92, 0.80]),
            cl.JaroWinklerAtThresholds("last_name", [0.92, 0.80]),
            cl.JaroWinklerAtThresholds("dob", [0.92, 0.80]),
            cl.JaroWinklerAtThresholds("email", [0.92, 0.80]),
        ],
        blocking_rules_to_generate_predictions=[
            block_on("city"),
        ],
        retain_intermediate_calculation_columns=True,
        additional_columns_to_retain=["entity_id"],
    )
    em_rules = [
        block_on("first_name"),
        block_on("last_name"),
    ]
    return run_config(df, "config_a_jw_city", settings, em_rules, output_dir)


def config_b_mixed_methods(df, output_dir):
    """Config B: Mixed methods -- JW on first_name, Levenshtein on last_name."""
    settings = SettingsCreator(
        link_type="dedupe_only",
        comparisons=[
            cl.JaroWinklerAtThresholds("first_name", [0.92, 0.80]),
            cl.LevenshteinAtThresholds("last_name", [1, 2]),
            cl.JaroWinklerAtThresholds("dob", [0.92, 0.80]),
            cl.JaroWinklerAtThresholds("email", [0.92, 0.80]),
        ],
        blocking_rules_to_generate_predictions=[
            block_on("city"),
        ],
        retain_intermediate_calculation_columns=True,
        additional_columns_to_retain=["entity_id"],
    )
    em_rules = [
        block_on("first_name"),
        block_on("last_name"),
    ]
    return run_config(df, "config_b_mixed", settings, em_rules, output_dir)


def config_c_multi_blocking(df, output_dir):
    """Config C: Multiple blocking rules -- city OR dob."""
    settings = SettingsCreator(
        link_type="dedupe_only",
        comparisons=[
            cl.JaroWinklerAtThresholds("first_name", [0.92, 0.80]),
            cl.JaroWinklerAtThresholds("last_name", [0.92, 0.80]),
            cl.JaroWinklerAtThresholds("email", [0.92, 0.80]),
        ],
        blocking_rules_to_generate_predictions=[
            block_on("city"),
            block_on("dob"),
        ],
        retain_intermediate_calculation_columns=True,
        additional_columns_to_retain=["entity_id"],
    )
    em_rules = [
        block_on("first_name"),
        block_on("last_name"),
    ]
    return run_config(df, "config_c_multi_block", settings, em_rules, output_dir)


def config_d_term_freq(df, output_dir):
    """Config D: Term frequency adjustment on last_name."""
    settings = SettingsCreator(
        link_type="dedupe_only",
        comparisons=[
            cl.JaroWinklerAtThresholds("first_name", [0.92, 0.80]),
            cl.JaroWinklerAtThresholds("last_name", [0.92, 0.80]).configure(
                term_frequency_adjustments=True
            ),
            cl.JaroWinklerAtThresholds("dob", [0.92, 0.80]),
            cl.JaroWinklerAtThresholds("email", [0.92, 0.80]),
        ],
        blocking_rules_to_generate_predictions=[
            block_on("city"),
        ],
        retain_intermediate_calculation_columns=True,
        additional_columns_to_retain=["entity_id"],
    )
    em_rules = [
        block_on("first_name"),
        block_on("last_name"),
    ]
    return run_config(df, "config_d_tf_adj", settings, em_rules, output_dir)


def config_e_dob(df, output_dir):
    """Config E: DOB as a comparison variable with date thresholds."""
    settings = SettingsCreator(
        link_type="dedupe_only",
        comparisons=[
            cl.JaroWinklerAtThresholds("first_name", [0.92, 0.80]),
            cl.JaroWinklerAtThresholds("last_name", [0.92, 0.80]),
            cl.JaroWinklerAtThresholds("dob", [0.92, 0.80]),
        ],
        blocking_rules_to_generate_predictions=[
            block_on("city"),
        ],
        retain_intermediate_calculation_columns=True,
        additional_columns_to_retain=["entity_id"],
    )
    em_rules = [
        block_on("first_name"),
        block_on("last_name"),
    ]
    return run_config(df, "config_e_dob", settings, em_rules, output_dir)


def config_f_tf_named(df, output_dir):
    """Config F: TF adjustment with named columns verification."""
    settings = SettingsCreator(
        link_type="dedupe_only",
        comparisons=[
            cl.JaroWinklerAtThresholds("first_name", [0.92, 0.80]).configure(
                term_frequency_adjustments=True
            ),
            cl.JaroWinklerAtThresholds("last_name", [0.92, 0.80]).configure(
                term_frequency_adjustments=True
            ),
            cl.JaroWinklerAtThresholds("dob", [0.92, 0.80]),
        ],
        blocking_rules_to_generate_predictions=[
            block_on("city"),
        ],
        retain_intermediate_calculation_columns=True,
        additional_columns_to_retain=["entity_id"],
    )
    em_rules = [
        block_on("first_name"),
        block_on("last_name"),
    ]
    return run_config(df, "config_f_tf_named", settings, em_rules, output_dir)


def config_g_multi_block(df, output_dir):
    """Config G: Multi-blocking with >4 rules."""
    settings = SettingsCreator(
        link_type="dedupe_only",
        comparisons=[
            cl.JaroWinklerAtThresholds("first_name", [0.92, 0.80]),
            cl.JaroWinklerAtThresholds("last_name", [0.92, 0.80]),
            cl.JaroWinklerAtThresholds("email", [0.92, 0.80]),
        ],
        blocking_rules_to_generate_predictions=[
            block_on("city"),
            block_on("dob"),
            block_on("first_name"),
            block_on("last_name"),
            block_on("email"),
        ],
        retain_intermediate_calculation_columns=True,
        additional_columns_to_retain=["entity_id"],
    )
    em_rules = [
        block_on("first_name"),
        block_on("last_name"),
    ]
    return run_config(df, "config_g_multi_block", settings, em_rules, output_dir)


# ===================================================================
# 4. Main
# ===================================================================

def main():
    print(f"splink version: {splink.__version__}")
    print(f"Output directory: {OUTPUT_DIR}")
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # --- Generate dataset ---
    print("\n" + "=" * 60)
    print("Generating test dataset")
    print("=" * 60)
    df = generate_test_data()
    print(f"  Records: {len(df)}")
    print(f"  True entities: {df['entity_id'].nunique()}")
    n_dups = len(df) - df["entity_id"].nunique()
    print(f"  Duplicate records: {n_dups}")
    print(f"  Cities: {sorted(df['city'].dropna().unique())}")

    # Missing value counts
    for col in ["first_name", "last_name", "dob", "city", "email"]:
        n_miss = df[col].isna().sum()
        if n_miss > 0:
            print(f"  {col}: {n_miss} missing ({100*n_miss/len(df):.1f}%)")

    # Save input data
    input_path = os.path.join(OUTPUT_DIR, "input_data.csv")
    df.to_csv(input_path, index=False)
    print(f"\n  Saved: input_data.csv ({len(df)} rows)")

    # Save ground truth entity mapping
    truth_path = os.path.join(OUTPUT_DIR, "ground_truth.csv")
    df[["unique_id", "entity_id"]].to_csv(truth_path, index=False)
    print(f"  Saved: ground_truth.csv")

    # --- Run all configurations ---
    results = {}
    results["a"] = config_a_jw_city(df, OUTPUT_DIR)
    results["b"] = config_b_mixed_methods(df, OUTPUT_DIR)
    results["c"] = config_c_multi_blocking(df, OUTPUT_DIR)
    results["d"] = config_d_term_freq(df, OUTPUT_DIR)
    results["e"] = config_e_dob(df, OUTPUT_DIR)
    results["f"] = config_f_tf_named(df, OUTPUT_DIR)
    results["g"] = config_g_multi_block(df, OUTPUT_DIR)

    # --- Summary ---
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"\nDataset: {len(df)} records, {df['entity_id'].nunique()} true entities")
    print(f"Ground truth duplicate pairs: ", end="")

    # Count true positive pairs
    from itertools import combinations
    true_pairs = set()
    for eid, group in df.groupby("entity_id"):
        uids = sorted(group["unique_id"].tolist())
        for a, b in combinations(uids, 2):
            true_pairs.add((a, b))
    print(f"{len(true_pairs)}")

    for name, res in results.items():
        config_label = {
            "a": "JW + city blocking",
            "b": "Mixed (JW+Lev) + city blocking",
            "c": "JW + multi-blocking (city OR dob)",
            "d": "JW + TF adj on last_name + city blocking",
            "e": "DOB comparison + city blocking",
            "f": "TF adjustment on first_name+last_name + city blocking",
            "g": "Multi-blocking (city OR dob OR first_name OR last_name OR email)",
        }[name]

        pred_df = res["predictions_df"]
        clust_df = res["clusters_df"]

        # Evaluate predictions against ground truth
        pred_pairs = set()
        for _, row in pred_df.iterrows():
            a, b = int(row["unique_id_l"]), int(row["unique_id_r"])
            pred_pairs.add((min(a, b), max(a, b)))

        tp = len(pred_pairs & true_pairs)
        fp = len(pred_pairs - true_pairs)
        fn = len(true_pairs - pred_pairs)

        precision = tp / (tp + fp) if (tp + fp) > 0 else 0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0
        f1 = (
            2 * precision * recall / (precision + recall)
            if (precision + recall) > 0
            else 0
        )

        print(f"\n  Config {name.upper()}: {config_label}")
        print(f"    Predictions: {len(pred_df)} pairs")
        print(f"    Clusters: {clust_df['cluster_id'].nunique()}")
        print(f"    Precision: {precision:.3f}  Recall: {recall:.3f}  F1: {f1:.3f}")

    # --- List output files ---
    print(f"\n{'='*60}")
    print("Output files")
    print(f"{'='*60}")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        fpath = os.path.join(OUTPUT_DIR, f)
        size = os.path.getsize(fpath)
        print(f"  {f} ({size:,} bytes)")


if __name__ == "__main__":
    main()
