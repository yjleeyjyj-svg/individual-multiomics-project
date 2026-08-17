#!/bin/bash
# Downstream analysis pipeline: MaxQuant output -> exports -> differential
# expression -> volcano plot -> Reactome pathway analysis.
#
# Assumes MaxQuant has already been run (locally or on the GCE VM -- see
# docs/RUNBOOK.md "Stage 2") and MaxQuantSearch/<dataset>/output/ exists.
#
# Usage:
#   ./run_pipeline.sh <dataset> [sample_groups] [donor_labels]
#
#   dataset       Folder name under RawData/ and MaxQuantSearch/, e.g.
#                 PXD025280_20260816. Defaults to PXD025280_20260816.
#   sample_groups Comma-separated group label per sample column, in the
#                 same left-to-right order MaxQuant lists raw files
#                 (check the header of results/<dataset>/protein_lfq_matrix.csv).
#                 Required for the differential-expression/volcano/
#                 expression-mode-Reactome steps -- omit to run only the
#                 export steps + a plain-list (ORA) Reactome run.
#   donor_labels  Optional comma-separated donor/blocking label per sample
#                 column, same order, for limma's duplicateCorrelation.
#
# Examples:
#   ./run_pipeline.sh                                    # exports + ORA only
#   ./run_pipeline.sh PXD025280_20260816 A,A,A,A,A,A,A,A,B,B,B,B,B,B,B,B
#   ./run_pipeline.sh PXD025280_20260816 EP,EP,LP,LP,... 1,2,1,2,...
#
# NOTE on variable naming (see docs/TROUBLESHOOTING.md Appendix F2): never
# name a shell variable GROUPS -- it's a bash built-in (list of Unix groups
# the current user belongs to) and silently shadows any assignment to it.

set -euo pipefail

DATASET="${1:-PXD025280_20260816}"
SAMPLE_GROUPS="${2:-}"
DONOR_LABELS="${3:-}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# R isn't reliably on PATH in this environment (see Appendix F1) -- resolve
# Rscript.exe explicitly, preferring PATH if it happens to be there.
RSCRIPT="$(command -v Rscript 2>/dev/null || true)"
if [ -z "$RSCRIPT" ]; then
  RSCRIPT="/c/Program Files/R/R-4.3.2/bin/Rscript.exe"
fi
if [ ! -f "$RSCRIPT" ]; then
  echo "Rscript not found (checked PATH and $RSCRIPT). Set RSCRIPT_BIN env var to override." >&2
  exit 1
fi
RSCRIPT="${RSCRIPT_BIN:-$RSCRIPT}"

MQ_OUTPUT="MaxQuantSearch/$DATASET/output"
PROCESSED="data/processed/$DATASET"
RESULTS="results/$DATASET"

if [ ! -f "$MQ_OUTPUT/proteinGroups.txt" ]; then
  echo "No MaxQuant output at $MQ_OUTPUT/proteinGroups.txt -- run MaxQuant first (docs/RUNBOOK.md Stage 2), or 'dvc pull' if it's already been pushed to GCS." >&2
  exit 1
fi

echo "=== [1/5] Peptide intensity export ==="
python src/python/export_peptide_intensities.py "$MQ_OUTPUT/peptides.txt" "$PROCESSED"

echo "=== [2/5] Downstream export (R matrix + Reactome protein list) ==="
python src/python/export_for_downstream.py "$MQ_OUTPUT/proteinGroups.txt" "$RESULTS"

if [ -z "$SAMPLE_GROUPS" ]; then
  echo ""
  echo "No sample_groups given -- skipping differential expression / volcano plot."
  echo "Running Reactome in plain-list (ORA) mode only."
  echo "=== [3/5] Reactome pathway analysis (ORA) ==="
  "$RSCRIPT" src/R/reactome_analysis.R "$RESULTS/reactome_protein_list.txt" "$RESULTS"
  echo ""
  echo "Done. To run differential expression + volcano + expression-mode Reactome,"
  echo "rerun with sample_groups once available:"
  echo "  ./run_pipeline.sh $DATASET <group_labels> [<donor_labels>]"
  exit 0
fi

DONOR_FLAG=()
if [ -n "$DONOR_LABELS" ]; then
  DONOR_FLAG=(--donor="$DONOR_LABELS")
fi

echo "=== [3/5] Differential expression (limma: empirical Bayes + BH-FDR) ==="
"$RSCRIPT" src/R/differential_expression.R \
  "$RESULTS/protein_lfq_matrix.csv" \
  "$SAMPLE_GROUPS" \
  "$PROCESSED/de_results.csv" \
  "${DONOR_FLAG[@]}"

echo "=== [4/5] Volcano plot ==="
"$RSCRIPT" src/R/volcano_plot.R \
  "$PROCESSED/de_results.csv" \
  "$RESULTS/volcano.png" \
  --title="$DATASET"

echo "=== [5/5] Reactome pathway analysis (expression mode) ==="
"$RSCRIPT" src/R/reactome_analysis.R \
  "$PROCESSED/de_results.csv" \
  "$RESULTS" \
  --id-col=Protein_ID \
  --value-col=logFC

echo ""
echo "Pipeline complete. Outputs in $PROCESSED/ and $RESULTS/."
echo "Don't forget: dvc add + dvc push the updated data/processed and results folders,"
echo "then git add/commit/push the .dvc pointers (see docs/RUNBOOK.md Stage 4)."
