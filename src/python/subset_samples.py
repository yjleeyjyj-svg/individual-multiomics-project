"""
Subset a protein/peptide x sample matrix CSV to only the given samples, in
the given order, keeping the non-sample ID columns. Used to carve out a
two-group comparison from a larger matrix (e.g. testing one pair of
inferred donor groups out of four) without touching the original file.

Usage:
  python subset_samples.py <matrix.csv> <sample1,sample2,...> <out.csv> [--id-cols=Protein_ID,Gene_name]

  Each entry in the sample list is matched against column names by suffix
  (so "06_JS_JL_01" matches a column named "LFQ_06_JS_JL_01" or
  "Intensity 06_JS_JL_01").
"""

import argparse
from pathlib import Path

import pandas as pd


def subset_samples(matrix_csv: Path, samples: list[str], out_csv: Path, id_cols: list[str]) -> pd.DataFrame:
    df = pd.read_csv(matrix_csv)
    cols = []
    for s in samples:
        matches = [c for c in df.columns if c.endswith(s)]
        if not matches:
            raise ValueError(f"No column found for sample '{s}' in {matrix_csv} (columns: {list(df.columns)})")
        cols.append(matches[0])

    out = df[id_cols + cols]
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(out_csv, index=False)
    print(f"Wrote {out_csv}: {len(out)} rows x {len(cols)} samples ({', '.join(cols)})")
    return out


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("matrix_csv", type=Path)
    parser.add_argument("samples", help="Comma-separated sample IDs, in the order they should appear")
    parser.add_argument("out_csv", type=Path)
    parser.add_argument("--id-cols", default="Protein_ID,Gene_name")
    args = parser.parse_args()

    subset_samples(
        args.matrix_csv,
        args.samples.split(","),
        args.out_csv,
        args.id_cols.split(","),
    )
