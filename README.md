# multiomics_project

Mass spectrometry data acquisition, fold-change analysis, and validation pipeline.

## Reference paper

Llewellyn et al., *"Loss of regulation of protein synthesis and turnover underpins
an attenuated stress response in senescent human mesenchymal stem cells"*,
PNAS 2023, 120(14):e2210745120.

MS datasets (ProteomeXchange / PRIDE):
- **PXD025280** — EP/LP hMSCs, 2h heat shock (primary comparison, in use)
- PXD025305 — EP/LP hMSCs, heat shock + HSPA1A inhibition
- PXD027056 — EP hMSCs, HSP90 inhibition
- PXD025329 — Monobromobimane labelling, EP/LP hMSCs heat stress

RNA-Seq (ArrayExpress): E-MTAB-10415

## Data flow: git + DVC + GCS

Code is tracked in git as usual. Data (raw MS files, processed tables, results)
is tracked with [DVC](https://dvc.org), which stores lightweight pointer files
(`*.dvc`) in git and keeps the actual bytes in the GCS bucket
`gs://individual-multiomics-project/dvcstore`. This keeps the local checkout
small — pull data on demand, push it back, and it doesn't have to live on disk
long-term.

```bash
dvc pull            # fetch data referenced by .dvc files into the working tree
dvc push            # upload new/changed data to the GCS remote
dvc add <path>       # start tracking a new file/folder with DVC
git add <path>.dvc  # commit the pointer (not the data itself) to git
```

GCP project: `gothic-sylph-410801` (bio-med-dent). Auth: `gcloud auth login`
for the CLI, `gcloud auth application-default login` for DVC's client library.

## Folder structure

```
multiomics_project/
├── RawData/                    # DVC-tracked raw MS acquisition data
│   └── (PXDCODE)_(YYYYMMDD)/   # one folder per dataset download, e.g. PXD025280_20260815
├── data/
│   └── processed/              # DVC-tracked intermediate tables (e.g. fold-change results)
├── results/                    # DVC-tracked final outputs/figures
├── src/
│   ├── python/
│   └── R/
├── notebooks/
├── requirements.txt
└── dvc.yaml                    # pipeline stages (to be added: acquisition -> FC -> validation)
```

## Status

- [x] git + DVC initialized, GCS remote connected and round-trip tested
- [ ] Download PXD025280 into `RawData/PXD025280_20260815/`
- [ ] Fold-change computation pipeline
- [ ] Validation pipeline
