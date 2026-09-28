#!/usr/bin/env Rscript
#
# Within-donor PCA + exhaustive 2x2 label search, to infer which raw file in
# each donor block is EP/LP and control/heat-shock (docs/PIPELINE.md SS19).
#
# Premise (SS19): the paper's design is 4 donors x {EP, LP} x {ctrl, 2 h 42 C},
# one sample per donor per condition, and each metadata donor_group
# (Group1-4, SS15/SS16/SS18) is one donor's full 2x2 set. Donor identity
# dominates the raw PCA (SS15), so it's removed first: every protein is
# centred on its own donor mean, and the PCA is then run on what's left --
# within-donor passage + heat-shock variation. If the premise holds, EP vs LP
# (806 of 1,830 proteins in the paper's Fig. 1A) should appear as one axis
# splitting every donor 2-vs-2 the same way.
#
# Label search (does not assume the PCA is right):
#   Stage 1 (passage): each donor's 4 samples can be split 2-vs-2 in 3 ways,
#     x 2 orientations; donor 1's orientation is fixed (the global EP/LP sign
#     is set afterwards by markers) -> 3 * 6^3 = 648 candidate labellings.
#     Each is scored by limma (~ donor + split) as the number of proteins with
#     BH-FDR < 0.05. The best score is inflated by being a max over 648 tries,
#     so read it relative to the runner-up and to the median, not in absolute
#     terms.
#   Stage 2 (heat shock): given the best passage split, each donor's EP pair
#     and LP pair each have 2 ways to assign ctrl/HS -> 4 per donor; donor 1's
#     EP pair is fixed (global sign set by markers) -> 2 * 4^3 = 128
#     candidates, scored by limma (~ donor + passage + hs).
#   Orientation: LP = the side with lower LMNB1 (lost in senescence, per the
#     paper); HS = the side with higher mean inducible-HSP level (HSPA1A,
#     HSPA1B, HSPA6, DNAJB1, HSPH1 -- whichever are quantified).
#   Validation: with the inferred labels, re-runs the paper's Fig. 1A-C
#     comparisons (donor-blocked limma) and reports hit counts next to the
#     paper's, as a fraction of proteins tested (this uses the complete-case
#     subset, so absolute counts won't match 1,830-protein totals).
#
# Nothing here writes into metadata/ -- the inferred mapping is a candidate
# for review, written to <out_dir>/inferred_sample_mapping.csv.
#
# Usage:
#   Rscript within_donor_pca.R <matrix.csv> <sample_mapping.csv> <out_dir> [--id-cols=Protein_ID,Gene_name]
#
#   matrix.csv         : results/<dataset>/protein_lfq_matrix.csv
#   sample_mapping.csv : metadata/<dataset>_sample_mapping.csv (raw_file, donor_group, ...)
#                        Matched to matrix columns by the trailing "JS_JL_NN" run number.

suppressMessages({
  library(limma)
  library(ggplot2)
})

args <- commandArgs(trailingOnly = TRUE)
positional <- args[!grepl("^--", args)]
flags <- args[grepl("^--", args)]
get_flag <- function(name, default) {
  m <- flags[grepl(paste0("^--", name, "="), flags)]
  if (length(m) > 0) sub(paste0("^--", name, "="), "", m[1]) else default
}

if (length(positional) < 3) {
  stop("Usage: Rscript within_donor_pca.R <matrix.csv> <sample_mapping.csv> <out_dir> [--id-cols=Protein_ID,Gene_name]")
}
input_path <- positional[1]
mapping_path <- positional[2]
out_dir <- positional[3]
id_cols <- strsplit(get_flag("id-cols", "Protein_ID,Gene_name"), ",")[[1]]
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- load + match samples to donors ---------------------------------------
df <- read.csv(input_path, check.names = FALSE)
sample_cols <- setdiff(names(df), id_cols)
mapping <- read.csv(mapping_path, stringsAsFactors = FALSE)

run_id <- function(x) sub(".*(JS_JL_[0-9]+)$", "\\1", x)
col_run <- run_id(sample_cols)
map_run <- run_id(mapping$raw_file)
idx <- match(col_run, map_run)
if (any(is.na(idx))) {
  stop(sprintf("No mapping row for matrix column(s): %s", paste(sample_cols[is.na(idx)], collapse = ", ")))
}
donor <- factor(mapping$donor_group[idx])
if (any(table(donor) != 4)) {
  stop(sprintf("Expected 4 samples per donor, got: %s", paste(names(table(donor)), table(donor), sep = "=", collapse = ", ")))
}
cat(sprintf("%d samples across %d donors (%s)\n", length(sample_cols), nlevels(donor), paste(levels(donor), collapse = ", ")))

# ---- preprocessing: same as differential_expression.R ----------------------
mat <- as.matrix(df[, sample_cols])
mat[mat == 0] <- NA
log_mat <- log2(mat)
log_mat <- sweep(log_mat, 2, apply(log_mat, 2, median, na.rm = TRUE))
rownames(log_mat) <- make.unique(ifelse(is.na(df$Gene_name) | df$Gene_name == "", df$Protein_ID, df$Gene_name))

complete <- complete.cases(log_mat)
x <- log_mat[complete, ]
cat(sprintf("%d / %d proteins detected in all samples (complete-case) -- using these\n", nrow(x), nrow(log_mat)))

# ---- within-donor PCA ------------------------------------------------------
x_centered <- x
for (d in levels(donor)) {
  cols <- donor == d
  x_centered[, cols] <- x[, cols] - rowMeans(x[, cols])
}

pca <- prcomp(t(x_centered), center = FALSE, scale. = FALSE)
var_explained <- (pca$sdev^2) / sum(pca$sdev^2) * 100
n_pc <- min(5, ncol(pca$x))
sample_labels <- sub("^(LFQ_|Intensity )", "", sample_cols)
scores <- data.frame(sample = sample_labels, donor = donor, pca$x[, 1:n_pc])
write.csv(scores, file.path(out_dir, "within_donor_pca_scores.csv"), row.names = FALSE)

# Does each PC split every donor 2-vs-2 around that donor's own mean? Weak on
# its own -- 4 donor-centred points often split 2/2 by chance, even with no
# condition effect -- so read it together with the PC's variance share
# (a real EP/LP axis should stand well above the rest on the scree plot).
cat("\nPer-PC donor split check (necessary but not sufficient -- also check variance share):\n")
for (k in 1:min(3, n_pc)) {
  pos <- tapply(pca$x[, k] > 0, donor, sum)
  cat(sprintf("  PC%d (%.1f%%): positive samples per donor = %s%s\n", k, var_explained[k],
              paste(names(pos), pos, sep = ":", collapse = " "),
              if (all(pos == 2)) "  <- 2v2 in every donor" else ""))
}

scree_df <- data.frame(PC = factor(seq_along(var_explained)), variance = var_explained)
ggsave(file.path(out_dir, "within_donor_pca_scree.png"),
       ggplot(scree_df[1:min(10, nrow(scree_df)), ], aes(PC, variance)) +
         geom_col(fill = "steelblue") +
         labs(title = "Within-donor PCA scree plot", x = "Principal component", y = "Variance explained [%]") +
         theme_minimal(),
       width = 7, height = 5, dpi = 150)

# ---- stage 1: exhaustive passage split search -------------------------------
count_hits <- function(design, coef, data = x) {
  fit <- eBayes(lmFit(data, design))
  sum(p.adjust(fit$p.value[, coef], method = "BH") < 0.05)
}

donor_samples <- split(seq_along(sample_cols), donor)
pairings <- list(c(1, 2), c(1, 3), c(1, 4))  # the 3 ways to pick a 2-subset containing sample 1
# per donor: 6 options = 3 pairings x 2 orientations; each option = indices on side "A"
donor_options <- lapply(donor_samples, function(s) {
  opts <- list()
  for (p in pairings) {
    opts[[length(opts) + 1]] <- s[p]
    opts[[length(opts) + 1]] <- setdiff(s, s[p])
  }
  opts
})
donor_options[[1]] <- donor_options[[1]][c(1, 3, 5)]  # fix donor 1's orientation

grid1 <- expand.grid(lapply(donor_options, seq_along))
cat(sprintf("\nStage 1: scoring %d passage labellings (limma ~ donor + split, BH-FDR < 0.05)...\n", nrow(grid1)))
stage1 <- vapply(seq_len(nrow(grid1)), function(i) {
  side_a <- unlist(mapply(function(opts, j) opts[[j]], donor_options, as.integer(grid1[i, ]), SIMPLIFY = FALSE))
  split_f <- factor(ifelse(seq_along(sample_cols) %in% side_a, "A", "B"))
  count_hits(model.matrix(~ donor + split_f), "split_fB")
}, numeric(1))

ord1 <- order(stage1, decreasing = TRUE)
side_a_of <- function(i) unlist(mapply(function(opts, j) opts[[j]], donor_options, as.integer(grid1[i, ]), SIMPLIFY = FALSE))
stage1_table <- data.frame(
  rank = seq_along(ord1),
  hits_fdr05 = stage1[ord1],
  side_A = vapply(ord1, function(i) paste(sample_labels[sort(side_a_of(i))], collapse = ";"), character(1))
)
write.csv(stage1_table, file.path(out_dir, "passage_split_search.csv"), row.names = FALSE)
cat(sprintf("  best = %d hits, runner-up = %d, median = %.0f (of %d proteins)\n",
            stage1_table$hits_fdr05[1], stage1_table$hits_fdr05[2], median(stage1), nrow(x)))

best_a <- side_a_of(ord1[1])
in_a <- seq_along(sample_cols) %in% best_a

# orientation: LP = side with lower LMNB1
marker_mean <- function(genes, cols) {
  g <- intersect(genes, rownames(log_mat))
  if (length(g) == 0) return(NA_real_)
  mean(log_mat[g, cols, drop = FALSE], na.rm = TRUE)
}
lmnb1_a <- marker_mean("LMNB1", in_a)
lmnb1_b <- marker_mean("LMNB1", !in_a)
if (is.na(lmnb1_a) || is.na(lmnb1_b)) {
  warning("LMNB1 not quantified -- EP/LP orientation left as side A = EP (arbitrary); check markers manually")
  passage <- ifelse(in_a, "EP", "LP")
} else {
  passage <- if (lmnb1_a < lmnb1_b) ifelse(in_a, "LP", "EP") else ifelse(in_a, "EP", "LP")
  cat(sprintf("  orientation: LMNB1 mean side A = %.2f, side B = %.2f -> side %s = LP\n",
              lmnb1_a, lmnb1_b, if (lmnb1_a < lmnb1_b) "A" else "B"))
}
passage <- factor(passage, levels = c("EP", "LP"))

# ---- stage 2: heat-shock assignment within each passage pair ----------------
hs_options <- lapply(donor_samples, function(s) {
  ep <- s[passage[s] == "EP"]
  lp <- s[passage[s] == "LP"]
  # 4 options: which EP sample is HS x which LP sample is HS
  list(c(ep[1], lp[1]), c(ep[1], lp[2]), c(ep[2], lp[1]), c(ep[2], lp[2]))
})
hs_options[[1]] <- hs_options[[1]][1:2]  # fix donor 1's EP choice (global HS sign set by markers)

grid2 <- expand.grid(lapply(hs_options, seq_along))
cat(sprintf("\nStage 2: scoring %d heat-shock labellings (limma ~ donor + passage + hs)...\n", nrow(grid2)))
hs_side_of <- function(i) unlist(mapply(function(opts, j) opts[[j]], hs_options, as.integer(grid2[i, ]), SIMPLIFY = FALSE))
stage2 <- vapply(seq_len(nrow(grid2)), function(i) {
  hs_f <- factor(ifelse(seq_along(sample_cols) %in% hs_side_of(i), "X", "Y"))
  count_hits(model.matrix(~ donor + passage + hs_f), "hs_fY")
}, numeric(1))
ord2 <- order(stage2, decreasing = TRUE)
stage2_table <- data.frame(
  rank = seq_along(ord2),
  hits_fdr05 = stage2[ord2],
  side_X = vapply(ord2, function(i) paste(sample_labels[sort(hs_side_of(i))], collapse = ";"), character(1))
)
write.csv(stage2_table, file.path(out_dir, "heatshock_split_search.csv"), row.names = FALSE)
cat(sprintf("  best = %d hits, runner-up = %d, median = %.0f\n",
            stage2_table$hits_fdr05[1], stage2_table$hits_fdr05[2], median(stage2)))

in_x <- seq_along(sample_cols) %in% hs_side_of(ord2[1])
hsp_genes <- c("HSPA1A", "HSPA1B", "HSPA6", "DNAJB1", "HSPH1")
hsp_found <- intersect(hsp_genes, rownames(log_mat))
hsp_x <- marker_mean(hsp_genes, in_x)
hsp_y <- marker_mean(hsp_genes, !in_x)
if (is.na(hsp_x) || is.na(hsp_y)) {
  warning("No inducible HSP quantified -- ctrl/HS orientation left as side X = HS (arbitrary)")
  treatment <- ifelse(in_x, "HS", "ctrl")
} else {
  treatment <- if (hsp_x > hsp_y) ifelse(in_x, "HS", "ctrl") else ifelse(in_x, "ctrl", "HS")
  cat(sprintf("  orientation: mean HSP (%s) side X = %.2f, side Y = %.2f -> side %s = HS\n",
              paste(hsp_found, collapse = ","), hsp_x, hsp_y, if (hsp_x > hsp_y) "X" else "Y"))
}
treatment <- factor(treatment, levels = c("ctrl", "HS"))

# ---- validation against the paper's Fig. 1A-C -------------------------------
condition <- factor(paste(passage, treatment, sep = "_"))
paired_hits <- function(keep, contrast_f) {
  d <- droplevels(donor[keep])
  f <- droplevels(factor(contrast_f[keep]))
  design <- model.matrix(~ d + f)
  count_hits(design, ncol(design), x[, keep])
}
validation <- data.frame(
  panel = c("1A", "1B", "1C"),
  comparison = c("LP vs EP, ctrl", "EP, HS vs ctrl", "LP, HS vs ctrl"),
  paper_hits = c(806, 86, 59),
  paper_fraction = round(c(806, 86, 59) / 1830, 3),
  inferred_hits = c(
    paired_hits(treatment == "ctrl", passage),
    paired_hits(passage == "EP", treatment),
    paired_hits(passage == "LP", treatment)
  ),
  proteins_tested = nrow(x)
)
validation$inferred_fraction <- round(validation$inferred_hits / validation$proteins_tested, 3)
write.csv(validation, file.path(out_dir, "fig1_validation.csv"), row.names = FALSE)
cat("\nFig. 1 check (donor-blocked limma, BH-FDR < 0.05):\n")
print(validation, row.names = FALSE)

# ---- marker table + inferred mapping + labelled PCA plot --------------------
markers <- intersect(c("LMNB1", "GLB1", hsp_genes), rownames(x_centered))
marker_table <- data.frame(sample = sample_labels, donor = donor, passage = passage, treatment = treatment,
                           t(x_centered[markers, , drop = FALSE]), check.names = FALSE)
write.csv(marker_table, file.path(out_dir, "marker_levels_donor_centered.csv"), row.names = FALSE)

inferred <- data.frame(
  raw_file = mapping$raw_file[idx],
  donor_group = donor,
  passage = passage,
  treatment = treatment,
  notes = sprintf("inferred by within_donor_pca.R (stage1 %d vs runner-up %d hits; stage2 %d vs %d) -- unconfirmed",
                  stage1_table$hits_fdr05[1], stage1_table$hits_fdr05[2],
                  stage2_table$hits_fdr05[1], stage2_table$hits_fdr05[2])
)
inferred <- inferred[order(inferred$raw_file), ]
write.csv(inferred, file.path(out_dir, "inferred_sample_mapping.csv"), row.names = FALSE)

scores$condition <- condition
pc_plot <- ggplot(scores, aes(PC1, PC2, color = donor, shape = condition, label = sample)) +
  geom_hline(yintercept = 0, colour = "grey80") +
  geom_vline(xintercept = 0, colour = "grey80") +
  geom_point(size = 3) +
  ggrepel::geom_text_repel(size = 3, show.legend = FALSE) +
  labs(
    title = "Within-donor PCA (each protein centred on its donor mean)",
    subtitle = sprintf("%d complete-case proteins | shape = INFERRED condition (unconfirmed)", nrow(x)),
    x = sprintf("PC1 (%.1f%%)", var_explained[1]),
    y = sprintf("PC2 (%.1f%%)", var_explained[2]),
    color = "Donor group", shape = "Inferred condition"
  ) +
  theme_minimal()
ggsave(file.path(out_dir, "within_donor_pca_pc1_pc2.png"), pc_plot, width = 9, height = 7, dpi = 150)

cat(sprintf("\nWrote outputs to %s/: within_donor_pca_{scores.csv,scree.png,pc1_pc2.png}, passage_split_search.csv,\n", out_dir))
cat("  heatshock_split_search.csv, fig1_validation.csv, marker_levels_donor_centered.csv, inferred_sample_mapping.csv\n")
