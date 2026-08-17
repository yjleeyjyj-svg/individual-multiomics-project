#!/usr/bin/env Rscript
#
# Submit protein identifiers (optionally with log2FC values) to Reactome's
# Analysis Service REST API (https://reactome.org/dev/analysis) and save
# both a durable local results table and the analysis token, which can be
# used to reopen the same analysis, overlaid on pathway diagrams, in the
# interactive Reactome Pathway Browser -- for up to 7 days, or until
# Reactome's next quarterly data update, whichever comes first.
#
# Two input modes, auto-selected by the input file:
#   - Plain list (one UniProt ID per line, e.g. reactome_protein_list.txt)
#     -> over-representation analysis (ORA): "which pathways are
#     represented by this set of identified proteins."
#   - Two-column CSV/TSV with an ID column and a log2FC-like column (e.g.
#     differential_expression.R's output) -> expression analysis: pathway
#     diagrams get coloured by the supplied values, matching the paper's
#     own Reactome method (SI Appendix, "Reactome graphs and pathway
#     analysis").
#
# Usage:
#   Rscript reactome_analysis.R <input_file> <out_dir> [--id-col=Protein_ID] [--value-col=logFC]

suppressMessages({
  library(httr)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
positional <- args[!grepl("^--", args)]
flags <- args[grepl("^--", args)]
get_flag <- function(name, default) {
  m <- flags[grepl(paste0("^--", name, "="), flags)]
  if (length(m) > 0) sub(paste0("^--", name, "="), "", m[1]) else default
}

if (length(positional) < 2) {
  stop("Usage: Rscript reactome_analysis.R <input_file> <out_dir> [--id-col=Protein_ID] [--value-col=logFC]")
}
input_path <- positional[1]
out_dir <- positional[2]
id_col <- get_flag("id-col", "Protein_ID")
value_col <- get_flag("value-col", "logFC")

is_csv <- grepl("\\.csv$", input_path, ignore.case = TRUE)

if (is_csv) {
  df <- read.csv(input_path)
  if (!(id_col %in% names(df))) stop(sprintf("id column '%s' not found in %s", id_col, input_path))
  if (value_col %in% names(df)) {
    cat(sprintf("Expression mode: %s + %s\n", id_col, value_col))
    sub_df <- df[!is.na(df[[value_col]]), c(id_col, value_col)]
    body_text <- paste0(
      "#", id_col, "\t", value_col, "\n",
      paste(sub_df[[id_col]], sub_df[[value_col]], sep = "\t", collapse = "\n")
    )
    mode <- "expression"
  } else {
    cat(sprintf("Value column '%s' not found -- falling back to plain ID list (ORA) mode.\n", value_col))
    body_text <- paste(unique(df[[id_col]]), collapse = "\n")
    mode <- "ora"
  }
} else {
  ids <- readLines(input_path)
  ids <- ids[nzchar(trimws(ids))]
  cat(sprintf("Plain list mode: %d identifiers\n", length(ids)))
  body_text <- paste(ids, collapse = "\n")
  mode <- "ora"
}

cat("Submitting to Reactome AnalysisService...\n")
resp <- POST(
  url = "https://reactome.org/AnalysisService/identifiers/",
  content_type("text/plain"),
  body = body_text
)
stop_for_status(resp)
result <- fromJSON(content(resp, as = "text", encoding = "UTF-8"), flatten = TRUE)

token <- result$summary$token
cat(sprintf("Token: %s\n", token))

pathways <- result$pathways
if (is.null(pathways) || nrow(pathways) == 0) {
  stop("No pathways returned -- check the input identifiers/format.")
}

pw_out <- data.frame(
  stId = pathways$stId,
  name = pathways$name,
  entities_found = pathways$entities.found,
  entities_total = pathways$entities.total,
  entities_pValue = pathways$entities.pValue,
  entities_fdr = pathways$entities.fdr,
  species = if ("species.name" %in% names(pathways)) pathways$species.name else NA
)
pw_out <- pw_out[order(pw_out$entities_fdr), ]

dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
results_path <- file.path(out_dir, "reactome_pathways.csv")
write.csv(pw_out, results_path, row.names = FALSE)

token_info <- list(
  token = token,
  mode = mode,
  submitted_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  input_file = input_path,
  n_pathways = nrow(pw_out),
  browser_url_overview = sprintf("https://reactome.org/PathwayBrowser/#DTAB=AN&ANALYSIS=%s", token),
  browser_url_top_pathway = sprintf(
    "https://reactome.org/PathwayBrowser/#%s&DTAB=AN&ANALYSIS=%s",
    pw_out$stId[1], token
  ),
  note = "Token valid for ~7 days or until Reactome's next quarterly update, whichever is sooner. The CSV in this folder is the durable record; the token/URLs are a convenience for interactive viewing while still valid."
)
token_path <- file.path(out_dir, "reactome_token.json")
write(toJSON(token_info, pretty = TRUE, auto_unbox = TRUE), token_path)

cat(sprintf("%d pathways -> %s\n", nrow(pw_out), results_path))
cat(sprintf("Token info -> %s\n", token_path))
cat(sprintf("Open in browser (valid ~7 days): %s\n", token_info$browser_url_overview))
