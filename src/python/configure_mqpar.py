"""
Apply this project's reference-paper-matched search parameters to a
freshly `MaxQuantCmd.exe --create`-generated mqpar.xml, and work around two
MaxQuant defaults that don't fit:

1. Enzyme/variable mods: MaxQuant's --create default is Trypsin/P with
   Oxidation (M) + Acetyl (Protein N-term). The paper's deposited Mascot
   search used plain Trypsin (no cleavage before proline) and a broader
   set of variable mods; this project uses the subset available in
   MaxQuant's default modification library: Oxidation (M), Oxidation (P),
   Phospho (STY). Oxidation (D)/(K)/(N) are not in MaxQuant's default
   library and are intentionally omitted (see README "Deviations from
   the paper").
2. Output folder: redirect MaxQuant's final result tables (customTxtFolder)
   away from the raw data folder.
3. contaminants.fasta parse rule: MaxQuant's own bundled contaminants.fasta
   uses headers like ">P00761 SWISS-PROT:P00761|TRYP_PIG ..." (no leading
   pipe), which the default UniProt-style identifierParseRule doesn't
   match. Without this fix MaxQuant fails at the "Testing fasta files" step.

Optionally also patches peptideFdr (--peptide-fdr): MaxQuant's own default
is a 1% target-decoy FDR for peptide identification, applied at the search
stage -- a different mechanism entirely from the paper's peptide-inclusion
filter (Mascot-score Benjamini-Hochberg FDR < 0.2, much more permissive).
The two aren't directly interchangeable (different scoring, different FDR
estimation), but setting --peptide-fdr=0.2 loosens MaxQuant's own filter to
the same *numeric* permissiveness the paper used, letting more peptides
through to quantification. Left at MaxQuant's default (0.01) unless passed.

Safe to re-run: each edit is skipped if already applied.
"""

import argparse
import re
from pathlib import Path
from typing import Optional

ENZYME_MODS_OLD = """         <enzymes>
            <string>Trypsin/P</string>
         </enzymes>
         <enzymesFirstSearch>
         </enzymesFirstSearch>
         <enzymeModeFirstSearch>0</enzymeModeFirstSearch>
         <useEnzymeFirstSearch>False</useEnzymeFirstSearch>
         <useVariableModificationsFirstSearch>False</useVariableModificationsFirstSearch>
         <variableModifications>
            <string>Oxidation (M)</string>
            <string>Acetyl (Protein N-term)</string>
         </variableModifications>"""

ENZYME_MODS_NEW = """         <enzymes>
            <string>Trypsin</string>
         </enzymes>
         <enzymesFirstSearch>
         </enzymesFirstSearch>
         <enzymeModeFirstSearch>0</enzymeModeFirstSearch>
         <useEnzymeFirstSearch>False</useEnzymeFirstSearch>
         <useVariableModificationsFirstSearch>False</useVariableModificationsFirstSearch>
         <variableModifications>
            <string>Oxidation (M)</string>
            <string>Oxidation (P)</string>
            <string>Phospho (STY)</string>
         </variableModifications>"""

CONTAMINANTS_RULE_OLD = r"<identifierParseRule>>[^|]*\|(.*?)\|</identifierParseRule>"
CONTAMINANTS_RULE_NEW = "<identifierParseRule>>([^ ]*)</identifierParseRule>"


def configure_mqpar(mqpar_path: Path, output_folder: str, contaminants_fasta: str, peptide_fdr: Optional[float] = None) -> None:
    content = mqpar_path.read_text()

    if ENZYME_MODS_NEW not in content:
        assert ENZYME_MODS_OLD in content, "enzyme/variable-mods block not found (unexpected mqpar.xml layout)"
        content = content.replace(ENZYME_MODS_OLD, ENZYME_MODS_NEW)

    old_txt_folder = "<customTxtFolder></customTxtFolder>"
    new_txt_folder = f"<customTxtFolder>{output_folder}</customTxtFolder>"
    if old_txt_folder in content:
        content = content.replace(old_txt_folder, new_txt_folder)
    elif new_txt_folder not in content:
        raise AssertionError("customTxtFolder tag not found as expected")

    contaminants_block_old = f"<fastaFilePath>{contaminants_fasta}</fastaFilePath>\n         {CONTAMINANTS_RULE_OLD}"
    contaminants_block_new = f"<fastaFilePath>{contaminants_fasta}</fastaFilePath>\n         {CONTAMINANTS_RULE_NEW}"
    if contaminants_block_new not in content:
        assert contaminants_block_old in content, "contaminants.fasta fastaFileInfo block not found as expected"
        content = content.replace(contaminants_block_old, contaminants_block_new)

    if peptide_fdr is not None:
        content = re.sub(r"<peptideFdr>[^<]*</peptideFdr>", f"<peptideFdr>{peptide_fdr}</peptideFdr>", content)

    mqpar_path.write_text(content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mqpar", type=Path, help="Path to the mqpar.xml to edit in place")
    parser.add_argument("--output-folder", required=True, help="Value for customTxtFolder (keep it outside the raw data folder)")
    parser.add_argument("--contaminants-fasta", required=True, help="Path to MaxQuant's bundled contaminants.fasta as it appears in mqpar.xml")
    parser.add_argument("--peptide-fdr", type=float, default=None, help="Override peptideFdr (MaxQuant default: 0.01). Pass 0.2 to match the numeric permissiveness of the paper's peptide-inclusion filter.")
    args = parser.parse_args()

    configure_mqpar(args.mqpar, args.output_folder, args.contaminants_fasta, args.peptide_fdr)
    print(f"Configured {args.mqpar}")
