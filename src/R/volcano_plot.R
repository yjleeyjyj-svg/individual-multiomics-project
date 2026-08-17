#!/usr/bin/env Rscript
#
# Volcano plot from src/R/differential_expression.R's output
# (columns: Protein_ID, Gene_name, logFC, t, P.Value, FDR).
#
# Uses EnhancedVolcano (Bioconductor) -- the de facto standard for
# proteomics/genomics volcano plots (gene/protein labels, configurable
# fold-change and significance cutoffs, built on ggplot2).
#
# Usage:
#   Rscript volcano_plot.R <de_results.csv> <out.png> [--fc=1] [--fdr=0.05] [--title="..."]

suppressMessages(library(EnhancedVolcano))

args <- commandArgs(trailingOnly = TRUE)
positional <- args[!grepl("^--", args)]
flags <- args[grepl("^--", args)]

if (length(positional) < 2) {
  stop("Usage: Rscript volcano_plot.R <de_results.csv> <out.png> [--fc=1] [--fdr=0.05] [--title=...]")
}
input_path <- positional[1]
out_path <- positional[2]

get_flag <- function(name, default) {
  m <- flags[grepl(paste0("^--", name, "="), flags)]
  if (length(m) > 0) sub(paste0("^--", name, "="), "", m[1]) else default
}
fc_cutoff <- as.numeric(get_flag("fc", "1"))
fdr_cutoff <- as.numeric(get_flag("fdr", "0.05"))
plot_title <- get_flag("title", basename(input_path))

df <- read.csv(input_path)
df <- df[!is.na(df$logFC) & !is.na(df$FDR), ]

label_col <- if ("Gene_name" %in% names(df)) "Gene_name" else names(df)[1]
labels <- df[[label_col]]
labels[is.na(labels) | labels == ""] <- df$Protein_ID[is.na(labels) | labels == ""]

n_up <- sum(df$logFC >= fc_cutoff & df$FDR < fdr_cutoff)
n_down <- sum(df$logFC <= -fc_cutoff & df$FDR < fdr_cutoff)
cat(sprintf(
  "%d points | thresholds: |log2FC| >= %.2f, FDR < %.3f | %d up, %d down\n",
  nrow(df), fc_cutoff, fdr_cutoff, n_up, n_down
))

p <- EnhancedVolcano(df,
  lab = labels,
  x = "logFC",
  y = "FDR",
  xlab = bquote(~Log[2] ~ "fold change"),
  ylab = bquote(~-Log[10] ~ "FDR"),
  pCutoff = fdr_cutoff,
  FCcutoff = fc_cutoff,
  title = plot_title,
  subtitle = sprintf("%d up / %d down (|log2FC| >= %.1f, FDR < %.2f)", n_up, n_down, fc_cutoff, fdr_cutoff),
  caption = sprintf("n = %d", nrow(df)),
  pointSize = 2.0,
  labSize = 3.0,
  legendPosition = "right"
)

ggplot2::ggsave(out_path, plot = p, width = 10, height = 8, dpi = 150)
cat(sprintf("Wrote %s\n", out_path))
