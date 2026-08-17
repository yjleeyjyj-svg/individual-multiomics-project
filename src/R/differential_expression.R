#!/usr/bin/env Rscript
#
# Differential expression via empirical Bayes-moderated t-test + Benjamini-
# Hochberg FDR, matching the reference paper's SI Appendix statistics
# (Materials and Methods -> "Proteomics data processing"):
#   - log-transform intensities
#   - within-sample normalization by median subtraction
#   - fold-change / significance via a linear model + empirical Bayes
#     moderation (limma::eBayes is the standard R implementation of this)
#   - Benjamini-Hochberg FDR correction
#
# The paper's model also blocked on donor (repeated-measures design across
# 4 donors). This script supports that via --donor, but donor assignment
# isn't available yet (see docs/PIPELINE.md SS4 -- sample_mapping.csv is
# still unfilled), so it's optional here.
#
# Usage:
#   Rscript differential_expression.R <input_matrix.csv> <group_csv> <out_csv> [--donor=<donor_csv>]
#
#   input_matrix.csv : protein/peptide x sample matrix (first column(s) are
#                       IDs, rest are numeric intensity columns), e.g.
#                       results/PXD025280_20260816/protein_lfq_matrix.csv
#   group_csv        : comma-separated group label per sample column, in
#                       the same left-to-right order as the intensity
#                       columns in input_matrix.csv (e.g. "A,A,A,A,B,B,B,B")
#   out_csv           : where to write the results table
#   --donor=          : optional comma-separated donor/blocking label per
#                       sample column, same order (e.g. "1,2,3,4,1,2,3,4")

suppressMessages(library(limma))

args <- commandArgs(trailingOnly = TRUE)
positional <- args[!grepl("^--", args)]
flags <- args[grepl("^--", args)]

if (length(positional) < 3) {
  stop("Usage: Rscript differential_expression.R <input_matrix.csv> <group_csv> <out_csv> [--donor=<donor_csv>]")
}
input_path <- positional[1]
group_arg <- positional[2]
out_path <- positional[3]

donor_flag <- flags[grepl("^--donor=", flags)]
donor_arg <- if (length(donor_flag) > 0) sub("^--donor=", "", donor_flag[1]) else NULL

df <- read.csv(input_path, check.names = FALSE)
id_cols <- names(df)[!sapply(df, is.numeric)]
intensity_cols <- names(df)[sapply(df, is.numeric)]

group <- strsplit(group_arg, ",")[[1]]
if (length(group) != length(intensity_cols)) {
  stop(sprintf(
    "group has %d entries but there are %d numeric intensity columns (%s)",
    length(group), length(intensity_cols), paste(intensity_cols, collapse = ", ")
  ))
}
group <- factor(group)
cat(sprintf("Groups: %s\n", paste(levels(group), collapse = " vs ")))
cat(sprintf("Samples per group: %s\n", paste(table(group), collapse = ", ")))

mat <- as.matrix(df[, intensity_cols])
mat[mat == 0] <- NA # MaxQuant's 0 means "not quantified in this sample", not a true zero
log_mat <- log2(mat)

# within-sample median normalization (subtract each sample's own median)
sample_medians <- apply(log_mat, 2, median, na.rm = TRUE)
norm_mat <- sweep(log_mat, 2, sample_medians, "-")

if (!is.null(donor_arg)) {
  donor <- factor(strsplit(donor_arg, ",")[[1]])
  if (length(donor) != length(intensity_cols)) {
    stop(sprintf("donor has %d entries but expected %d", length(donor), length(intensity_cols)))
  }
  cat("Blocking on donor (duplicateCorrelation).\n")
  design <- model.matrix(~group)
  corfit <- duplicateCorrelation(norm_mat, design, block = donor)
  fit <- lmFit(norm_mat, design, block = donor, correlation = corfit$consensus)
} else {
  cat("No donor blocking (unpaired design).\n")
  design <- model.matrix(~group)
  fit <- lmFit(norm_mat, design)
}

fit <- eBayes(fit)
results <- topTable(fit, coef = 2, number = Inf, sort.by = "none", adjust.method = "BH")

out <- cbind(df[, id_cols, drop = FALSE], results[, c("logFC", "t", "P.Value", "adj.P.Val")])
names(out)[names(out) == "adj.P.Val"] <- "FDR"

n_sig <- sum(out$FDR < 0.05, na.rm = TRUE)
cat(sprintf(
  "%d rows tested, %d with FDR < 0.05 (%s)\n",
  nrow(out), n_sig, basename(input_path)
))

write.csv(out, out_path, row.names = FALSE)
cat(sprintf("Wrote %s\n", out_path))
