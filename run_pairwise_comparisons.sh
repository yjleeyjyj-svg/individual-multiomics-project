#!/bin/bash
# Run all pairwise comparisons between the 4 inferred donor groups (PCA-based,
# see docs/PIPELINE.md SS15/SS16) through differential expression -> volcano
# plot -> Reactome (expression mode). EP/LP and control/heat-shock are NOT
# assigned yet (docs/PIPELINE.md SS4) -- this compares donor-group vs
# donor-group as a structural/methodological test, not a biological one.
#
# Usage:
#   ./run_pairwise_comparisons.sh [dataset]

set -euo pipefail

DATASET="${1:-PXD025280_20260816}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

RSCRIPT="$(command -v Rscript 2>/dev/null || true)"
if [ -z "$RSCRIPT" ]; then
  RSCRIPT="/c/Program Files/R/R-4.3.2/bin/Rscript.exe"
fi
RSCRIPT="${RSCRIPT_BIN:-$RSCRIPT}"

RESULTS="results/$DATASET"
PROCESSED="data/processed/$DATASET"
MATRIX="$RESULTS/protein_lfq_matrix.csv"

# Inferred donor groups (PCA + raw-file numbering blocks -- see PIPELINE.md SS15).
# NOTE on naming (Appendix F2): don't use GROUPS/G1 etc. if they risk colliding
# with a bash builtin -- these names are fine, but keep the lesson in mind.
GROUP1="06_JS_JL_01,06_JS_JL_02,06_JS_JL_03,06_JS_JL_04"
GROUP2="06_JS_JL_13,06_JS_JL_14,06_JS_JL_15,06_JS_JL_16"
GROUP3="19_JS_JL_25,19_JS_JL_26,19_JS_JL_27,19_JS_JL_28"
GROUP4="24_JS_JL_37,24_JS_JL_38,24_JS_JL_39,24_JS_JL_40"

declare -A GROUP=( [1]="$GROUP1" [2]="$GROUP2" [3]="$GROUP3" [4]="$GROUP4" )

PAIRS=("1 2" "1 3" "1 4" "2 3" "2 4" "3 4")

for pair in "${PAIRS[@]}"; do
  read -r a b <<< "$pair"
  name="group${a}v${b}"
  out_dir="$RESULTS/pairwise/$name"
  mkdir -p "$out_dir"

  echo ""
  echo "================= $name (Group$a vs Group$b) ================="

  samples_a="${GROUP[$a]}"
  samples_b="${GROUP[$b]}"
  all_samples="$samples_a,$samples_b"

  echo "--- Subsetting matrix ---"
  python src/python/subset_samples.py \
    "$MATRIX" \
    "$all_samples" \
    "$out_dir/protein_lfq_matrix_subset.csv"

  echo "--- Differential expression (Group$a vs Group$b) ---"
  "$RSCRIPT" src/R/differential_expression.R \
    "$out_dir/protein_lfq_matrix_subset.csv" \
    "Group$a,Group$a,Group$a,Group$a,Group$b,Group$b,Group$b,Group$b" \
    "$out_dir/de_results.csv"

  echo "--- Volcano plot ---"
  "$RSCRIPT" src/R/volcano_plot.R \
    "$out_dir/de_results.csv" \
    "$out_dir/volcano.png" \
    --title="$name (donor-group comparison, not EP/LP or ctrl/HS)"

  echo "--- Reactome (expression mode) ---"
  "$RSCRIPT" src/R/reactome_analysis.R \
    "$out_dir/de_results.csv" \
    "$out_dir" \
    --id-col=Protein_ID \
    --value-col=logFC
done

echo ""
echo "All 6 pairwise comparisons complete. Outputs in $RESULTS/pairwise/<groupAvB>/."
echo "Don't forget: dvc add + dvc push $RESULTS, then git add/commit/push the .dvc pointer."
