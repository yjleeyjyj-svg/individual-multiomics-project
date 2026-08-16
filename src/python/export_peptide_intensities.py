"""
Export peptide-level detection intensities from a MaxQuant search, mirroring
the checkpoint described in the reference paper's SI Appendix (Progenesis QI
peptide intensities exported to Excel before downstream statistics).

Input:  MaxQuant combined/txt/peptides.txt (tab-separated)
Output: peptide_detection_intensities.csv and .xlsx, with one row per peptide
        and one column per raw file's intensity.
"""

import argparse
import re
from pathlib import Path

import pandas as pd


def export_peptide_intensities(peptides_txt: Path, out_dir: Path) -> pd.DataFrame:
    df = pd.read_csv(peptides_txt, sep="\t", low_memory=False)

    id_cols = [c for c in ["Sequence", "Proteins", "Leading razor protein", "Unique (Groups)"] if c in df.columns]
    intensity_cols = [c for c in df.columns if re.fullmatch(r"Intensity (?!.*(total|__)).+", c)]

    result = df[id_cols + intensity_cols].copy()

    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "peptide_detection_intensities.csv"
    xlsx_path = out_dir / "peptide_detection_intensities.xlsx"
    result.to_csv(csv_path, index=False)
    result.to_excel(xlsx_path, index=False)

    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("peptides_txt", type=Path, help="Path to MaxQuant combined/txt/peptides.txt")
    parser.add_argument("out_dir", type=Path, help="Directory to write the peptide intensity CSV/XLSX into")
    args = parser.parse_args()

    df = export_peptide_intensities(args.peptides_txt, args.out_dir)
    print(f"Wrote {len(df)} peptides x {len(df.columns)} columns to {args.out_dir}")
