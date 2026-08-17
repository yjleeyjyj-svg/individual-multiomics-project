# individual_multiomics_project

Mass spectrometry data acquisition, fold-change analysis, and validation pipeline,
built around a public proteomics dataset re-processed with an open-source tool
chain and checked against the source paper's reported results.

- **[docs/RUNBOOK.md](docs/RUNBOOK.md)** — every command to reproduce this from scratch, in order (start here to actually run something)
- **[docs/PIPELINE.md](docs/PIPELINE.md)** — the process and why each decision was made, step by step
- **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — problems hit and how they were fixed, cross-referenced from the pipeline doc

## Quick start

```bash
./run_pipeline.sh PXD025280_20260816                          # exports + Reactome ORA (no group labels needed)
./run_pipeline.sh PXD025280_20260816 <sample_groups> [donor]   # + differential expression, volcano, Reactome expression mode
```

Assumes MaxQuant has already been run (docs/RUNBOOK.md Stage 2) and its
output exists at `MaxQuantSearch/<dataset>/output/` (or `dvc pull` it).

## Reference paper

Llewellyn et al., *"Loss of regulation of protein synthesis and turnover
underpins an attenuated stress response in senescent human mesenchymal stem
cells"*, PNAS 2023, 120(14):e2210745120. (PMID 36989307, PMC10083568)

MS datasets (ProteomeXchange / PRIDE):
- **PXD025280** — EP/LP hMSCs, 2h heat shock (primary comparison, in use)
- PXD025305 — EP/LP hMSCs, heat shock + HSPA1A inhibition
- PXD027056 — EP hMSCs, HSP90 inhibition
- PXD025329 — Monobromobimane labelling, EP/LP hMSCs heat stress

RNA-Seq (ArrayExpress): E-MTAB-10415

**Working principle for this project:** when a reference (paper, SI Appendix,
deposited search parameters) specifies a technique or parameter, the pipeline
follows it as closely as the available open-source tools allow. Where the
original tool chain can't be reproduced exactly, the deviation and the reason
for it are recorded explicitly (see "Deviations from the paper" below) rather
than silently substituted.

## Data flow: git + DVC + GCS

```bash
dvc pull             # fetch data referenced by .dvc files into the working tree
dvc push             # upload new/changed data to the GCS remote
dvc add <path>       # start tracking a new file/folder with DVC
git add <path>.dvc   # commit the pointer (not the data itself) to git
```

## Folder structure

```
individual_multiomics_project/
├── docs/
│   ├── PIPELINE.md                 # full process, step by step
│   └── TROUBLESHOOTING.md          # problems + fixes, referenced from PIPELINE.md
├── RawData/
│   └── PXD025280_20260816/         # DVC-tracked raw MS acquisition data (16 .raw + search XML)
│       └── sample_mapping.csv      # raw_file -> donor/passage/treatment (currently empty; see docs/PIPELINE.md §4)
├── reference/                      # DVC-tracked; UniProt human reviewed proteome FASTA
├── MaxQuantSearch/
│   └── PXD025280_20260816/
│       ├── mqpar.xml               # git-tracked MaxQuant search config
│       ├── run.log                 # gitignored
│       └── txt/                    # MaxQuant output tables (DVC-tracked once stable)
├── data/processed/                 # DVC-tracked intermediate tables (e.g. peptide/protein intensities, fold-change)
├── results/                        # DVC-tracked final outputs/figures
├── src/
│   ├── python/
│   │   ├── configure_mqpar.py      # patches a fresh mqpar.xml to this project's parameters
│   │   └── export_peptide_intensities.py
│   └── R/
├── notebooks/
├── tools/                          # gitignored; MaxQuant + ThermoRawFileParser installs
├── requirements.txt
└── dvc.yaml                        # pipeline stages (not yet written)
```

GCS bucket layout (`gs://individual-multiomics-project/`):
- `dvcstore/files/md5/..` — DVC content-addressed data (see docs/PIPELINE.md §1)
- `software/MaxQuant_v2.8.1.0.zip` — kept indefinitely (avoids repeating the
  CAPTCHA-gated manual download)

## Deviations from the paper (tracked for the validation step)

| Paper (Progenesis QI + Mascot) | This pipeline (MaxQuant) | Reason |
|---|---|---|
| Oxidation (D), (K), (N) variable mods | Omitted | Not in MaxQuant's default modification library; custom entries deferred |
| Peptide filter: Mascot-score BH-FDR < 0.2 | MaxQuant default 1% FDR (PSM/protein) | Scores aren't comparable across search engines |
| Progenesis QI cross-run alignment | MaxQuant Match-Between-Runs | Different algorithm, same intent |
| Donor/passage/treatment per raw file | Unknown (raw file ID used as placeholder) | No such mapping exists in any deposited metadata |

## Status

- [x] GCS + DVC + GitHub wired up and round-trip tested
- [x] PXD025280 downloaded (17 files, ~16.5 GB), checksums verified
- [x] SI Appendix reviewed; original protocol and its limits documented (docs/PIPELINE.md §5)
- [x] MaxQuant search complete on the GCE VM — `proteinGroups.txt` (2,623 groups), `peptides.txt` (15,346 peptides) pulled to local via GCS
- [x] Peptide intensity export (CSV/XLSX) run against real output
- [x] Downstream export formats (R matrix, Reactome protein list) in `results/PXD025280_20260816/`
- [x] Differential expression script (limma: empirical Bayes-moderated t-test + BH-FDR), matching the paper's actual significance test — mechanically tested with an arbitrary 8-vs-8 split, ready for real group labels
- [x] VM deleted and local raw-data copy freed (~33 GB) once everything was confirmed safe in GCS; one orphaned test object cleaned out of the bucket
- [x] Volcano plot (`EnhancedVolcano`) from the differential expression output
- [x] Reactome pathway analysis (REST API, ORA mode) on the real 1,477-protein identified list — 421/1,886 pathways at FDR < 0.05; expression-colored mode implemented and ready
- [ ] Validation against the paper's reported summary statistics
- [ ] Remaining PXD datasets (025305, 027056, 025329) processed on the VM
- [ ] Sample/condition mapping filled in (pending, needs a source outside this project) — blocks real (non-arbitrary) differential expression and validation
