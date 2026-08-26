#!/usr/bin/env Rscript
#
# PCA of samples from a protein (or peptide) x sample LFQ intensity matrix,
# e.g. results/<dataset>/protein_lfq_matrix.csv. Intended use: sample_mapping
# (docs/PIPELINE.md SS4) is still unfilled, so real condition-based grouping
# isn't possible yet -- PCA lets us look for natural clustering structure in
# the data itself (e.g. 4 donors, or an EP/LP split) that could help infer
# or sanity-check condition labels once a guess is made.
#
# Preprocessing: log2-transform (MaxQuant's 0 = "not quantified" -> NA, not
# log2(0)), then keep only rows with NO missing values across all samples
# (complete-case) for a clean baseline PCA -- no imputation, so the
# component structure isn't an artifact of how missing values were filled
# in. Reports how many rows survive this filter.
#
# Points are labelled by raw-file ID and coloured by the date prefix parsed
# out of the raw filename (e.g. "06", "19", "24" from "06_JS_JL_01") -- this
# is an objectively known covariate (which acquisition batch/day a sample
# was run on), NOT a biological condition guess, and is included specifically
# to help distinguish "this clustering is a batch effect" from "this
# clustering might be biological."
#
# Usage:
#   Rscript pca_plot.R <matrix.csv> <out_dir> [--id-cols=Protein_ID,Gene_name]

suppressMessages(library(ggplot2))

args <- commandArgs(trailingOnly = TRUE)
positional <- args[!grepl("^--", args)]
flags <- args[grepl("^--", args)]
get_flag <- function(name, default) {
  m <- flags[grepl(paste0("^--", name, "="), flags)]
  if (length(m) > 0) sub(paste0("^--", name, "="), "", m[1]) else default
}

if (length(positional) < 2) {
  stop("Usage: Rscript pca_plot.R <matrix.csv> <out_dir> [--id-cols=Protein_ID,Gene_name]")
}
input_path <- positional[1]
out_dir <- positional[2]
id_cols <- strsplit(get_flag("id-cols", "Protein_ID,Gene_name"), ",")[[1]]

df <- read.csv(input_path, check.names = FALSE)
sample_cols <- setdiff(names(df), id_cols)
cat(sprintf("%d samples: %s\n", length(sample_cols), paste(sample_cols, collapse = ", ")))

mat <- as.matrix(df[, sample_cols])
mat[mat == 0] <- NA
log_mat <- log2(mat)

complete <- complete.cases(log_mat)
cat(sprintf("%d / %d rows detected in all samples (complete-case) -- using these for PCA\n", sum(complete), nrow(log_mat)))
pca_input <- t(log_mat[complete, ])

pca <- prcomp(pca_input, center = TRUE, scale. = TRUE)
var_explained <- (pca$sdev^2) / sum(pca$sdev^2) * 100

sample_labels <- sub("^(LFQ_|Intensity )", "", sample_cols)
batch <- sub("^([0-9]{2}).*", "\\1", sample_labels)

scores <- data.frame(
  sample = sample_labels,
  batch = batch,
  pca$x[, 1:min(5, ncol(pca$x))]
)

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
scores_path <- file.path(out_dir, "pca_scores.csv")
write.csv(scores, scores_path, row.names = FALSE)
cat(sprintf("Wrote %s\n", scores_path))

# scree plot
scree_df <- data.frame(PC = factor(seq_along(var_explained)), variance = var_explained)
scree_plot <- ggplot(scree_df[1:min(10, nrow(scree_df)), ], aes(x = PC, y = variance)) +
  geom_col(fill = "steelblue") +
  labs(title = "PCA scree plot", x = "Principal component", y = "Variance explained [%]") +
  theme_minimal()
scree_path <- file.path(out_dir, "pca_scree.png")
ggsave(scree_path, plot = scree_plot, width = 7, height = 5, dpi = 150)
cat(sprintf("Wrote %s\n", scree_path))

# PC1 vs PC2
pc_plot <- ggplot(scores, aes(x = PC1, y = PC2, color = batch, label = sample)) +
  geom_point(size = 3) +
  ggrepel::geom_text_repel(size = 3, show.legend = FALSE) +
  labs(
    title = "PCA of samples (protein LFQ intensity, complete-case)",
    subtitle = sprintf(
      "%d complete-case proteins of %d total | colour = acquisition-date batch (not a biological label)",
      sum(complete), nrow(log_mat)
    ),
    x = sprintf("PC1 (%.1f%%)", var_explained[1]),
    y = sprintf("PC2 (%.1f%%)", var_explained[2]),
    color = "Batch"
  ) +
  theme_minimal()
pc_path <- file.path(out_dir, "pca_pc1_pc2.png")
ggsave(pc_path, plot = pc_plot, width = 9, height = 7, dpi = 150)
cat(sprintf("Wrote %s\n", pc_path))
