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

Safe to re-run: each edit is skipped if already applied.
"""

import argparse
from pathlib import Path

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


def configure_mqpar(mqpar_path: Path, output_folder: str, contaminants_fasta: str) -> None:
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

    mqpar_path.write_text(content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mqpar", type=Path, help="Path to the mqpar.xml to edit in place")
    parser.add_argument("--output-folder", required=True, help="Value for customTxtFolder (keep it outside the raw data folder)")
    parser.add_argument("--contaminants-fasta", required=True, help="Path to MaxQuant's bundled contaminants.fasta as it appears in mqpar.xml")
    args = parser.parse_args()

    configure_mqpar(args.mqpar, args.output_folder, args.contaminants_fasta)
    print(f"Configured {args.mqpar}")
