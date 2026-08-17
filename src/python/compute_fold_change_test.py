"""
MECHANICAL TEST ONLY — not a real biological comparison.

Pairs up the 16 raw-file intensity columns two at a time, in list order
(arbitrary — sample_mapping.csv is still unfilled, see docs/PIPELINE.md §4,
so real condition-based comparisons (EP vs LP, control vs heat-shock) aren't
possible yet). This exists purely to exercise the fold-change computation
end to end (log2FC, basic summary stats) against real data before the real
comparisons can be wired up.

Input: peptide_detection_intensities.csv (from export_peptide_intensities.py)
Output: fold_change_test_pairs.csv, one log2FC column per arbitrary pair,
plus a printed summary per pair.
"""

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


def compute_test_fold_changes(intensities_csv: Path, out_dir: Path) -> pd.DataFrame:
    df = pd.read_csv(intensities_csv)

    id_cols = [c for c in ["Sequence", "Proteins", "Leading razor protein", "Unique (Groups)"] if c in df.columns]
    intensity_cols = [c for c in df.columns if c.startswith("Intensity ")]

    if len(intensity_cols) % 2 != 0:
        print(f"Warning: {len(intensity_cols)} intensity columns (odd) — last one is left unpaired and dropped.")
        intensity_cols = intensity_cols[:-1]

    result = df[id_cols].copy()
    pair_num = 0
    for i in range(0, len(intensity_cols), 2):
        pair_num += 1
        col_a, col_b = intensity_cols[i], intensity_cols[i + 1]
        log2fc = np.log2(df[col_b] + 1) - np.log2(df[col_a] + 1)
        col_name = f"log2FC_pair{pair_num}_({col_a.replace('Intensity ', '')}_vs_{col_b.replace('Intensity ', '')})"
        result[col_name] = log2fc

        finite = log2fc[np.isfinite(log2fc) & (log2fc != 0)]
        n_up = (finite > 1).sum()
        n_down = (finite < -1).sum()
        print(
            f"Pair {pair_num} ({col_a} vs {col_b}): "
            f"n={len(finite)} nonzero, median log2FC={finite.median():.2f}, "
            f"|log2FC|>1: {n_up} up / {n_down} down"
        )

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "fold_change_test_pairs.csv"
    result.to_csv(out_path, index=False)
    print(f"\nWrote {out_path}")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("intensities_csv", type=Path)
    parser.add_argument("out_dir", type=Path)
    args = parser.parse_args()
    compute_test_fold_changes(args.intensities_csv, args.out_dir)
