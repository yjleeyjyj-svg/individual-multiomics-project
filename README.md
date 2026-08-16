# individual_multiomics_project

Mass spectrometry data acquisition, fold-change analysis, and validation pipeline,
built around a public proteomics dataset re-processed with an open-source tool
chain and checked against the source paper's reported results.

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

## Process log

### 1. Environment: GCS + DVC + GitHub

- Installed `gcloud` CLI (winget), authenticated with `gcloud auth login`
  (CLI) and `gcloud auth application-default login` (needed separately for
  DVC's Python client library — the two do not share credentials).
- GCP project: `gothic-sylph-410801` (bio-med-dent). GCS bucket:
  `gs://individual-multiomics-project` (asia-northeast3), pre-created by the
  user.
- `git init` + `dvc init`, DVC remote set to
  `gs://individual-multiomics-project/dvcstore`. Verified with a push/delete/pull
  round trip before trusting it with real data.
- DVC stores data content-addressed by MD5 hash (`.dvc/cache/files/md5/..`,
  mirrored to the same path in the bucket) — git only ever holds small `.dvc`
  pointer files, never the raw bytes.
- Project folder was renamed/nested from the original `multiomics_project` to
  `multiomics_project/individual_multiomics_project` (matches the GCS bucket
  name) using `robocopy /MOVE` (plain `Rename-Item` failed on a file lock).
- GitHub remote: `https://github.com/yjleeyjyj-svg/individual-multiomics-project.git`.
  Git identity for this repo: `Young-June-LEE <yjleeyjyj@snu.ac.kr>`. Auth via
  Git Credential Manager (`git push` triggers a browser OAuth prompt the first
  time; the sandboxed shell here can't complete that prompt itself, so the
  first push/auth of any new credential has to be run by the user in their own
  terminal).

### 2. Identifying the MS dataset

- Source paper supplied as PDF; text extracted with `pdfplumber` (`pdftoppm`/
  poppler wasn't available, so the PDF skill's page-render path didn't work —
  used the Python-library path instead).
- Data Availability section lists four PXD accessions (see above); PRIDE file
  listing + `dataProcessingProtocol` metadata pulled via the PRIDE Archive v2
  REST API (`https://www.ebi.ac.uk/pride/ws/archive/v2/...`).
- Chose **PXD025280** as the primary dataset (the paper's core EP vs LP ±
  heat-shock comparison). The other three PXDs are noted but not downloaded.

### 3. Raw data acquisition

- PXD025280 = 16 `.raw` files (~1 GB each) + 1 Mascot search-results XML
  (`F017631.xml`, ~154 MB) = **17 files, ~16.5 GB** (17,680,288,300 bytes per
  PRIDE's reported file sizes).
- Downloaded over HTTPS from `ftp.pride.ebi.ac.uk` (same content as the FTP
  path, but HTTPS supports `curl -C -` resume, which plain FTP in this
  environment did not handle as cleanly) into
  `RawData/PXD025280_20260816/`.
- First download attempt failed entirely (`curl: URL rejected: Malformed
  input`) — the generated URL list had trailing `\r` (CRLF) from Python's
  default text-mode line endings on Windows; stripped with `tr -d '\r'` and
  re-ran.
- Verified integrity against PRIDE's reported SHA1 checksums for all 17
  files; one file (`20170724_JS_JL_38.raw`) failed the first checksum and was
  re-downloaded and re-verified.
- Folder naming convention: `RawData/(PXDCODE)_(download date, YYYYMMDD)/`.

### 4. Sample → condition mapping (open gap)

The 16 raw files are named by an internal lab numbering scheme
(`YYYYMMDD_JS_JL_NN.raw`) that does not encode donor, passage (EP/LP), or
treatment (control/heat-shock). Checked three places for a mapping and found
none:
- PRIDE project/file metadata (`sampleAttributes`, per-file
  `additionalAttributes`) — only generic organism/tissue tags, no per-file
  labels. This project predates PRIDE's SDRF requirement.
- The deposited Mascot search XML (`F017631.xml`) — confirms exact search
  parameters (see below) but only carries raw filenames + scan numbers, no
  condition labels. It also references raw file numbers outside our 16
  (e.g. `..._JL_07`), meaning it's a combined search across more than one of
  the four PXD submissions.
- Raw file embedded Xcalibur metadata (checked via `ThermoRawFileParser`,
  open-source, no login required) — `SampleData` only has autosampler
  position fields (`sample number`, `Vial`, `Row`), no free-text sample name.

16 raw files happens to equal 4 donors × 2 passages × 2 treatments (matches
"n = 4 primary donors" in the paper), so the *design* is inferable, but which
specific file is which condition is not recoverable from any deposited
metadata — this would require asking the original authors.

**Working decision:** `RawData/PXD025280_20260816/sample_mapping.csv` was
created as a template (columns: `raw_file, donor, passage, treatment, notes`,
values empty) and raw filenames are used as the sample identifier everywhere
in the pipeline for now. Real condition labels can be filled in later without
changing anything upstream.

### 5. Reference protocol (SI Appendix)

Extracted the SI Appendix PDF the same way as the main paper. Found the full
original wet-lab + data-processing protocol (`Materials and Methods`, SI
Appendix p.9–10):

- **Acquisition:** Q Exactive HF (Orbitrap), UltiMate 3000 RSLC nanoLC,
  trypsin digestion (immobilized trypsin beads), DTT reduction + IAM
  alkylation, DDA (data-dependent acquisition), shotgun proteomics.
- **Original data processing (not reproduced — see below):** alignment/
  peak-picking in **Progenesis QI** (Waters), search in **Mascot** against
  SwissProt+TrEMBL human. Fixed mod: Carbamidomethyl (C). Variable mods, per
  the actually-deposited Mascot XML search parameters (which take precedence
  over the SI Appendix prose, since the prose additionally mentions Phospho
  (H/D) that the real search did not use): Oxidation (D, K, M, N, P), Phospho
  (ST), Phospho (Y). Missed cleavages ≤ 2, charge >+4 excluded, <2 isotopes
  excluded.
- **Original downstream stats (not reproduced yet — candidate for the
  validation pipeline):** custom MATLAB (R2015a + Bioinformatics Toolbox).
  Proteins with <3 unique peptides excluded from quantification. Peptides
  filtered to Mascot-score BH-FDR < 0.2. Normalization: log-transform +
  within-sample median subtraction. Fold-change: linear regression modeling
  donor variability at peptide and protein level. Significance: empirical
  Bayes-moderated t-test + Benjamini-Hochberg FDR.
- No separate "Dataset S1"-style spreadsheet of processed values exists for
  this paper (checked PNAS/PMC supplementary file listing) — so exact
  numeric ground truth isn't available. The plan is to validate our pipeline
  against the paper's **reported summary statistics** instead (e.g. protein
  counts up/down per comparison, pathway-level results), not a full matrix.

### 6. MaxQuant search pipeline

Progenesis QI and Mascot are both commercially licensed — not reproducible
here. Built an equivalent open pipeline instead:

- **MaxQuant v2.8.1.0** — downloaded manually by the user (registration form
  + CAPTCHA on maxquant.org, which can't be automated/completed by the
  assistant). Requires **.NET 8.0 runtime** (installed via
  `winget install Microsoft.DotNet.Runtime.8`; MaxQuant's own `.ps1` launcher
  is blocked by PowerShell's execution policy, so `MaxQuantCmd.exe` /
  `.cmd` wrappers are invoked directly instead of changing that policy).
- **Reference database:** UniProt human reviewed (Swiss-Prot) proteome,
  20,431 sequences, pulled from the UniProt REST API
  (`rest.uniprot.org/uniprotkb/stream`), plus MaxQuant's bundled
  `contaminants.fasta`.
- **`mqpar.xml`** generated via `MaxQuantCmd.exe --create` (LC-MS type:
  Standard DDA; instrument: Orbitrap), then hand-edited to match the SI
  Appendix protocol as closely as MaxQuant's default modification library
  allows:
  - Enzyme changed from MaxQuant's default `Trypsin/P` to plain **`Trypsin`**
    — the deposited Mascot XML specifies `<CLE>Trypsin</CLE>`, i.e. no
    cleavage before proline, and `Trypsin/P` would not match that.
  - Removed MaxQuant's default `Acetyl (Protein N-term)` variable mod (not
    used in the original search).
  - Variable mods set to **Oxidation (M), Oxidation (P), Phospho (STY)** —
    MaxQuant's built-in modification list does not include Oxidation (D),
    Oxidation (K), or Oxidation (N) by name (these are unusual,
    non-default hydroxylation modifications). Decision: leave them out for
    this run rather than hand-authoring custom modification entries, and
    revisit with custom `modifications.xml` entries later if the fuller
    pipeline review calls for it.
  - `maxMissedCleavages = 2` (already MaxQuant's default, matches the paper).
  - LFQ (label-free quantification) and Match-Between-Runs enabled.
  - FDR left at MaxQuant's standard 1% (PSM/protein/site) rather than the
    paper's unusually permissive Mascot-score BH-FDR < 0.2 — the two search
    engines' score distributions aren't comparable, so carrying the literal
    number across doesn't mean the same thing.
  - Output tables redirected to `MaxQuantSearch/PXD025280_20260816/txt/`
    (`customTxtFolder`) to keep the DVC-tracked `RawData/` folder limited to
    acquisition data — in practice MaxQuant still also writes its working
    `combined/` scratch folder next to the raw files regardless; that scratch
    folder is `.gitignore`d and will be cleaned up / evaluated after the run
    finishes.
- **Two failed run attempts before it started processing correctly:**
  1. `dotnet` not found — MaxQuant spawns worker processes by shelling out to
     the bare `dotnet` command, and the sandboxed shell's `PATH` wasn't
     refreshed after installing .NET in a separate terminal window. Fixed by
     prepending `C:\Program Files\dotnet` to `PATH` in the same command that
     launches MaxQuant.
  2. Failed at "Testing fasta files" (looked like early success — exited 0 —
     but the run log and generated `combined/proc/*.error.txt` showed it
     aborted after 4 of 54 job steps). Cause: the auto-generated
     `identifierParseRule` regex (`>[^|]*\|(.*?)\|`, meant for standard
     UniProt-style headers) doesn't match MaxQuant's own bundled
     `contaminants.fasta`, whose headers look like
     `>P00761 SWISS-PROT:P00761|TRYP_PIG ...` (no leading pipe). Fixed the
     parse rule for that FASTA entry to `>([^ ]*)` and re-ran after cleaning
     up the partial-run artifacts.
- Third attempt is the one currently running (background), progressing
  normally through MaxQuant's standard job sequence (feature detection →
  deisotoping → MS/MS search → LFQ → protein assembly → write tables).

### 7. Peptide-intensity export checkpoint

`src/python/export_peptide_intensities.py` reads MaxQuant's `peptides.txt`
and writes a peptide × sample intensity table to both CSV and XLSX, mirroring
the paper's own checkpoint (Progenesis QI peptide intensities exported to
Excel before downstream statistics). Not yet run against real output — will
be validated once the MaxQuant search finishes.

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
├── RawData/
│   └── PXD025280_20260816/         # DVC-tracked raw MS acquisition data (16 .raw + search XML)
│       └── sample_mapping.csv      # raw_file -> donor/passage/treatment (currently empty, see above)
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
│   │   └── export_peptide_intensities.py
│   └── R/
├── notebooks/
├── tools/                          # gitignored; MaxQuant + ThermoRawFileParser installs
├── requirements.txt
└── dvc.yaml                        # pipeline stages (not yet written)
```

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
- [x] SI Appendix reviewed; original protocol and its limits documented above
- [x] MaxQuant installed, configured, currently running the search
- [ ] MaxQuant search complete; `proteinGroups.txt` / `peptides.txt` produced
- [ ] Peptide intensity export (CSV/XLSX) run against real output
- [ ] Fold-change computation pipeline
- [ ] Validation against the paper's reported summary statistics
- [ ] Sample/condition mapping filled in (pending, needs a source outside this project)
