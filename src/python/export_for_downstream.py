"""
Turn MaxQuant's proteinGroups.txt into two downstream-ready formats:

1. A protein x sample LFQ intensity matrix (CSV) — the standard wide-matrix
   input expected by R bioinformatics packages (limma, DEP, MSstats, etc.):
   one row per protein group, one column per sample.
2. A plain UniProt accession list (TXT, one per line) for Reactome's
   Pathway Analysis tool (reactome.org/PathwayBrowser — "Analyse Data"),
   which accepts UniProt IDs directly for over-representation analysis.

Filtering (matches this project's quantification criteria — see
docs/PIPELINE.md "Deviations from the paper"): excludes decoy hits,
potential contaminants, and protein groups with fewer than 3 unique
peptides (the paper's own quantification threshold).

Column headers use the raw-file ID (e.g. "06_JS_JL_01") as the sample
name — see docs/PIPELINE.md §4: real condition labels (donor/passage/
treatment) aren't available yet, so this is the only stable identifier.
"""

import argparse
from pathlib import Path

import pandas as pd


def export_for_downstream(protein_groups_txt: Path, out_dir: Path, min_unique_peptides: int = 3) -> pd.DataFrame:
    df = pd.read_csv(protein_groups_txt, sep="\t", low_memory=False)

    n_total = len(df)
    keep = (df["Decoy"] != "+") & (df["Potential contaminant"] != "+") & (df["Unique peptides"] >= min_unique_peptides)
    df = df[keep].copy()
    print(f"{n_total} protein groups -> {len(df)} after excluding decoys/contaminants/<{min_unique_peptides} unique peptides")

    df["Protein_ID"] = df["Majority protein IDs"].str.split(";").str[0]
    df["Gene_name"] = df["Gene names"].str.split(";").str[0]

    lfq_cols = [c for c in df.columns if c.startswith("LFQ intensity ")]
    matrix = df[["Protein_ID", "Gene_name"] + lfq_cols].copy()
    matrix.columns = ["Protein_ID", "Gene_name"] + [c.replace("LFQ intensity ", "LFQ_") for c in lfq_cols]

    out_dir.mkdir(parents=True, exist_ok=True)

    matrix_path = out_dir / "protein_lfq_matrix.csv"
    matrix.to_csv(matrix_path, index=False)
    print(f"Wrote {matrix_path} ({len(matrix)} proteins x {len(lfq_cols)} samples)")

    reactome_path = out_dir / "reactome_protein_list.txt"
    reactome_path.write_text("\n".join(df["Protein_ID"].dropna().unique()) + "\n")
    print(f"Wrote {reactome_path} ({df['Protein_ID'].nunique()} unique UniProt IDs)")

    return matrix


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("protein_groups_txt", type=Path, help="Path to MaxQuant's proteinGroups.txt")
    parser.add_argument("out_dir", type=Path, help="Directory to write protein_lfq_matrix.csv and reactome_protein_list.txt into")
    parser.add_argument("--min-unique-peptides", type=int, default=3)
    args = parser.parse_args()

    export_for_downstream(args.protein_groups_txt, args.out_dir, args.min_unique_peptides)
