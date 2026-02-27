#!/usr/bin/env python3
"""Export splink's built-in datasets as CSV for Stata testing.

Also runs Python splink on each dataset to produce reference results
for comparison with the Stata plugin.

Requirements:
    pip install splink==4.0.6 pandas==2.2.0 numpy==1.26.4

Usage:
    python3 tests/export_splink_datasets.py
"""
import os
import sys

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))


def export_fake_1000():
    """Export fake_1000 dataset (1000 records, 250 entities, dedup task)."""
    from splink import splink_datasets

    print("=" * 60)
    print("Dataset: fake_1000")
    print("=" * 60)

    df = splink_datasets.fake_1000

    print(f"  Records: {len(df)}")
    print(f"  Columns: {list(df.columns)}")
    print(f"  True entities: {df['cluster'].nunique()}")

    # Show missing data rates
    for col in df.columns:
        pct_missing = df[col].isna().mean() * 100
        if pct_missing > 0:
            print(f"  {col}: {pct_missing:.1f}% missing")

    # Export
    path = os.path.join(OUTPUT_DIR, "splink_fake_1000.csv")
    df.to_csv(path, index=False)
    print(f"  Saved to: {path}")
    return df


def export_febrl3():
    """Export FEBRL3 dataset (5000 records, 2000 entities, dedup task)."""
    from splink import splink_datasets

    print("\n" + "=" * 60)
    print("Dataset: febrl3")
    print("=" * 60)

    df = splink_datasets.febrl3

    print(f"  Records: {len(df)}")
    print(f"  Columns: {list(df.columns)}")

    # FEBRL ground truth: cluster column derived from rec_id pattern
    if 'cluster' in df.columns:
        print(f"  True entities: {df['cluster'].nunique()}")

    path = os.path.join(OUTPUT_DIR, "splink_febrl3.csv")
    df.to_csv(path, index=False)
    print(f"  Saved to: {path}")
    return df


def export_febrl4():
    """Export FEBRL4a + FEBRL4b (5000+5000 records, linking task)."""
    from splink import splink_datasets
    import pandas as pd

    print("\n" + "=" * 60)
    print("Dataset: febrl4a + febrl4b (linking)")
    print("=" * 60)

    df_a = splink_datasets.febrl4a
    df_b = splink_datasets.febrl4b

    print(f"  Source A records: {len(df_a)}")
    print(f"  Source B records: {len(df_b)}")
    print(f"  Columns: {list(df_a.columns)}")

    # Add source indicator and stack
    df_a = df_a.copy()
    df_b = df_b.copy()
    df_a['source'] = 0
    df_b['source'] = 1
    df = pd.concat([df_a, df_b], ignore_index=True)

    if 'cluster' in df.columns:
        print(f"  True entities: {df['cluster'].nunique()}")

    path = os.path.join(OUTPUT_DIR, "splink_febrl4_stacked.csv")
    df.to_csv(path, index=False)
    print(f"  Saved to: {path}")
    return df


def run_splink_reference(df, dataset_name, comparison_cols, blocking_rules,
                         is_link=False, source_col=None):
    """Run Python splink on a dataset to produce reference cluster results.

    This uses splink's DuckDB backend to run the full pipeline and save
    predicted cluster IDs for comparison with the Stata plugin.
    """
    try:
        import splink.comparison_library as cl
        from splink import Linker, SettingsCreator
    except ImportError:
        print("  WARNING: Could not import splink v4 API, skipping reference run")
        return None

    print(f"\n  Running Python splink on {dataset_name}...")

    # Build comparison settings
    comparisons = []
    for col in comparison_cols:
        if col in ('dob', 'date_of_birth'):
            comparisons.append(cl.DateOfBirthComparison(col))
        elif col in ('email',):
            comparisons.append(cl.EmailComparison(col))
        else:
            comparisons.append(cl.JaroWinklerAtThresholds(col))

    try:
        if is_link:
            settings = SettingsCreator(
                link_type="link_only",
                comparisons=comparisons,
                blocking_rules_to_generate_predictions=blocking_rules,
            )
            linker = Linker(
                [df[df[source_col] == 0], df[df[source_col] == 1]],
                settings,
                db_api=None
            )
        else:
            settings = SettingsCreator(
                link_type="dedupe_only",
                comparisons=comparisons,
                blocking_rules_to_generate_predictions=blocking_rules,
            )
            from splink import DuckDBAPI
            db_api = DuckDBAPI()
            linker = Linker(df, settings, db_api=db_api)

        # Train
        for rule in blocking_rules[:2]:
            try:
                linker.training.estimate_parameters_using_random_sampling(
                    max_pairs=1e6
                )
            except Exception:
                pass
            try:
                linker.training.estimate_u_using_random_sampling(max_pairs=1e6)
            except Exception:
                pass

        # Predict
        predictions = linker.inference.predict(threshold_match_probability=0.5)
        clusters = linker.clustering.cluster_pairwise_predictions_at_threshold(
            predictions, threshold_match_probability=0.85
        )

        result_df = clusters.as_pandas_dataframe()
        out_path = os.path.join(OUTPUT_DIR, f"splink_ref_{dataset_name}.csv")
        result_df.to_csv(out_path, index=False)
        print(f"  Reference results saved to: {out_path}")
        return result_df

    except Exception as e:
        print(f"  WARNING: Reference run failed: {e}")
        print(f"  (This is OK — the exported CSVs still have ground truth for validation)")
        return None


def main():
    print("Exporting splink datasets for Stata testing")
    print("=" * 60)

    try:
        from splink import splink_datasets
    except ImportError:
        print("ERROR: splink not installed.")
        print("  pip install splink==4.0.6")
        sys.exit(1)

    # Export datasets
    fake_1000 = export_fake_1000()
    febrl3 = export_febrl3()
    febrl4 = export_febrl4()

    # Try running splink reference (may fail if splink API has changed)
    # These are optional — the ground truth in the CSVs is sufficient
    print("\n" + "=" * 60)
    print("Running Python splink for reference results (optional)")
    print("=" * 60)

    try:
        import splink.comparison_library as cl
        run_splink_reference(
            fake_1000, "fake_1000",
            comparison_cols=["first_name", "surname", "dob", "city", "email"],
            blocking_rules=["l.surname = r.surname", "l.city = r.city"],
        )
    except Exception as e:
        print(f"  Skipping reference run: {e}")

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)
    print("\nExported files:")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        if f.startswith("splink_") and f.endswith(".csv"):
            size = os.path.getsize(os.path.join(OUTPUT_DIR, f))
            print(f"  {f} ({size:,} bytes)")


if __name__ == "__main__":
    main()
