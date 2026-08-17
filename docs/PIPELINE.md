# Pipeline

The process this project follows, step by step. Problems hit along the way
are cross-referenced by ID (e.g. *Appendix A1*) into
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) rather than inlined here.

## 1. Environment: git + DVC + GCS + GitHub

- `gcloud` CLI installed and authenticated: `gcloud auth login` (CLI) +
  `gcloud auth application-default login` (DVC's Python client library —
  these two are separate credential stores). *(Appendix A1, A2)*
- GCP project: `gothic-sylph-410801` (bio-med-dent). GCS bucket:
  `gs://individual-multiomics-project` (asia-northeast3).
- `git init` + `dvc init`, DVC remote set to
  `gs://individual-multiomics-project/dvcstore`, verified with a
  push/delete/pull round trip before trusting it with real data.
- DVC stores data content-addressed by MD5 hash: `<hash[:2]>/<hash[2:]>`
  under `dvcstore/files/md5/`, mirrored between the local cache and the
  bucket. Git only ever holds small `.dvc` pointer files (which hash maps to
  which named path), never the raw bytes.
- Project folder nested: `multiomics_project/individual_multiomics_project`
  (matches the GCS bucket name). *(Appendix A3)*
- GitHub remote: `https://github.com/yjleeyjyj-svg/individual-multiomics-project.git`
  (private). Git identity for this repo: `Young-June-LEE <yjleeyjyj@snu.ac.kr>`.
  *(Appendix A4)*

## 2. Identifying the MS dataset

- Source paper supplied as PDF; text extracted with `pdfplumber`. *(Appendix B1)*
- Data Availability section lists four PXD accessions (see main
  [README](../README.md)); PRIDE file listing + `dataProcessingProtocol`
  metadata pulled via the PRIDE Archive v2 REST API
  (`https://www.ebi.ac.uk/pride/ws/archive/v2/...`).
- Chose **PXD025280** as the primary dataset (the paper's core EP vs LP ±
  heat-shock comparison). The other three PXDs are noted but not yet
  downloaded — planned for the GCE VM (§7).

## 3. Raw data acquisition

- PXD025280 = 16 `.raw` files (~1 GB each) + 1 Mascot search-results XML
  (`F017631.xml`, ~154 MB) = **17 files, ~16.5 GB**.
- Downloaded over HTTPS from `ftp.pride.ebi.ac.uk` into
  `RawData/PXD025280_20260816/` (folder convention:
  `RawData/(PXDCODE)_(download date, YYYYMMDD)/`). *(Appendix B2)*
- Verified integrity against PRIDE's reported SHA1 checksums for all 17
  files. *(Appendix B3)*

## 4. Sample → condition mapping (open gap)

The 16 raw files are named by an internal lab numbering scheme
(`YYYYMMDD_JS_JL_NN.raw`) that does not encode donor, passage (EP/LP), or
treatment (control/heat-shock). Checked three places for a mapping and found
none:
- PRIDE project/file metadata — only generic organism/tissue tags, no
  per-file labels (this project predates PRIDE's SDRF requirement).
- The deposited Mascot search XML (`F017631.xml`) — confirms exact search
  parameters (§5) but only carries raw filenames + scan numbers. It also
  references raw file numbers outside our 16 (e.g. `..._JL_07`), meaning
  it's a combined search across more than one of the four PXD submissions.
- Raw file embedded Xcalibur metadata (via `ThermoRawFileParser`) —
  `SampleData` only has autosampler position fields (`sample number`,
  `Vial`, `Row`), no free-text sample name.

16 raw files happens to equal 4 donors × 2 passages × 2 treatments (matches
"n = 4 primary donors" in the paper), so the *design* is inferable, but which
specific file is which condition is not recoverable from any deposited
metadata — would require asking the original authors.

**Working decision:** `RawData/PXD025280_20260816/sample_mapping.csv` is a
template (columns: `raw_file, donor, passage, treatment, notes`, values
empty) and raw filenames are used as the sample identifier everywhere in the
pipeline for now.

## 5. Reference protocol (SI Appendix)

Extracted the SI Appendix PDF the same way as the main paper. Found the full
original wet-lab + data-processing protocol (`Materials and Methods`, SI
Appendix p.9–10):

- **Acquisition:** Q Exactive HF (Orbitrap), UltiMate 3000 RSLC nanoLC,
  trypsin digestion, DTT reduction + IAM alkylation, DDA (data-dependent
  acquisition), shotgun proteomics.
- **Original data processing (not reproduced — commercial tools, see §6):**
  alignment/peak-picking in **Progenesis QI** (Waters), search in **Mascot**
  against SwissProt+TrEMBL human. Fixed mod: Carbamidomethyl (C). Variable
  mods, per the actually-deposited Mascot XML search parameters (which take
  precedence over the SI Appendix prose — the prose additionally mentions
  Phospho (H/D) that the real search did not use): Oxidation (D, K, M, N, P),
  Phospho (ST), Phospho (Y). Missed cleavages ≤ 2, charge >+4 excluded, <2
  isotopes excluded.
- **Original downstream stats (not reproduced yet — candidate for the
  validation pipeline):** custom MATLAB (R2015a + Bioinformatics Toolbox).
  Proteins with <3 unique peptides excluded from quantification. Peptides
  filtered to Mascot-score BH-FDR < 0.2. Normalization: log-transform +
  within-sample median subtraction. Fold-change: linear regression modeling
  donor variability at peptide and protein level. Significance: empirical
  Bayes-moderated t-test + Benjamini-Hochberg FDR.
- No separate "Dataset S1"-style spreadsheet of processed values exists for
  this paper — exact numeric ground truth isn't available. Validation plan:
  check this pipeline's output against the paper's **reported summary
  statistics** (protein counts up/down per comparison, pathway-level
  results), not a full matrix.

## 6. Local MaxQuant search (PXD025280)

Progenesis QI and Mascot are both commercially licensed — not reproducible
here. Built an equivalent open pipeline instead:

- **MaxQuant v2.8.1.0** — downloaded manually by the user (registration form
  + CAPTCHA on maxquant.org can't be automated). Requires **.NET 8.0
  runtime**.
- **Reference database:** UniProt human reviewed (Swiss-Prot) proteome,
  20,431 sequences (`rest.uniprot.org/uniprotkb/stream`), plus MaxQuant's
  bundled `contaminants.fasta`.
- **`mqpar.xml`** generated via `MaxQuantCmd.exe --create` (Standard DDA,
  Orbitrap), then patched by `src/python/configure_mqpar.py`:
  - Enzyme: MaxQuant's default `Trypsin/P` → **`Trypsin`** (the deposited
    Mascot XML specifies `<CLE>Trypsin</CLE>` — no cleavage before proline).
  - Variable mods: MaxQuant's default (`Oxidation (M)` +
    `Acetyl (Protein N-term)`) → **`Oxidation (M)`, `Oxidation (P)`,
    `Phospho (STY)`** — the closest match to the paper's mods available in
    MaxQuant's default modification library (see "Deviations" in the main
    README for what's omitted and why).
  - `maxMissedCleavages = 2` (already MaxQuant's default, matches the paper).
  - LFQ (label-free quantification) and Match-Between-Runs enabled.
  - Output tables redirected out of the raw data folder via
    `customTxtFolder`.
  - FDR left at MaxQuant's standard 1% (PSM/protein/site) — see "Deviations."
- `numThreads`: started at 8, reduced to **4** after a hardware freeze.
  *(Appendix C3)*
- Two configuration bugs fixed before it ran cleanly: a `PATH` issue
  *(Appendix C1)* and a `contaminants.fasta` parsing failure *(Appendix C2)*.
- **Status:** stopped intentionally once the GCE VM (§7) pulled ahead on the
  same dataset — see §7. `RawData/PXD025280_20260816/` was cleaned back to
  its original 21-file/16.47 GB state (MaxQuant's own scratch removed) and
  reconfirmed against the DVC/GCS remote before stopping, so there's nothing
  local left to reconcile once the VM's results are pulled down.

### MaxQuant's job sequence (54 steps)

Whether run locally or on the VM, `MaxQuantCmd.exe mqpar.xml` walks through
the same fixed sequence of named jobs (from `--dryrun`); `run.log` shows
progress as one line per completed step. Grouped here by phase for
readability — MaxQuant itself doesn't label the groups.

**Setup & input validation (1–5):** Configuring · Assemble run info ·
Finish run info · Testing fasta files · Testing raw files

**Per-file feature extraction (6–10):** Feature detection · Deisotoping ·
MS/MS preparation · Calculating peak properties · Combining apl files for
first search

**First-pass search & recalibration (11–15):** Preparing searches ·
MS/MS first search · Read search results for recalibration · Mass
recalibration · Calculating masses

**Main search (16–18):** MS/MS preparation for main search · Combining apl
files for main search · MS/MS main search

**Identification & FDR filtering (19–27):** Preparing combined folder ·
Correcting errors · Reading search engine results · Preparing reverse hits ·
Finish search engine results · Filter identifications (MS/MS) · Calculating
PEP · Copying identifications · Applying FDR

**Second peptide search (28–34):** Assembling second peptide MS/MS ·
Combining second peptide files · Second peptide search · Reading search
engine results (SP) · Finish search engine results (SP) · Filtering
identifications (SP) · Applying FDR (SP)

**Quantification & cross-run matching (35–41):** Re-quantification ·
Reporter quantification · Retention time alignment · Matching between runs
1–4

**Protein assembly (42–46):** Prepare protein assembly · Assembling
proteins · Assembling unidentified peptides · Finish protein assembly ·
Updating identifications

**Label-free quantification (47–51):** Label-free preparation · Label-free
normalization · Label-free quantification · Label-free collect · Estimating
complexity

**Writing output (52–54):** Prepare writing tables · Writing tables ·
Finish writing tables — after this, `proteinGroups.txt` / `peptides.txt` /
`evidence.txt` etc. appear in the configured output folder.

## 7. Cloud (GCE VM) MaxQuant search

Decided to move future datasets (and, in parallel, re-run PXD025280 as a
speed comparison) to a GCE VM rather than the local machine, after the local
run's memory-pressure freeze.

**Spec chosen** (walked through machine type, provisioning model, boot disk,
API scope, and SSH access one at a time with the user):

| Setting | Value | Why |
|---|---|---|
| Name / zone | `individual-multiomics-project` / `asia-northeast3-a` | same region as the GCS bucket |
| Machine type | `c2d-standard-16` (16 vCPU / 64 GB) | compute-optimized (AMD EPYC) for Andromeda's CPU-bound search; 4 GB/vCPU matches MaxQuant's own per-thread RAM guidance |
| Provisioning | Spot, `--instance-termination-action=STOP` | ~80–91% cheaper than on-demand; if preempted, `MaxQuantCmd --partial-processing` can resume rather than restart |
| Boot disk | 150 GB, `pd-balanced` | raw data + scratch + install headroom |
| OS | Ubuntu 22.04 LTS | MaxQuant runs on Linux via `dotnet MaxQuantCmd.dll` (no GUI, which is fine — CLI-only usage anyway) |
| API scope | `storage-rw` only | least privilege needed (GCS pull/push) |
| SSH | IAP tunneling, no public port | see firewall fix, Appendix D2 |

- Billing model: Compute Engine bills **per second the instance is
  `RUNNING`**, regardless of utilization — not by data processed. Practice
  going forward: create the VM for a job, delete it when done, rather than
  leaving it running or merely stopped (a stopped VM still bills for its
  disk). Estimated at realistic per-job usage (a few hours per dataset, not
  24/7): roughly $1–5 total across all four PXD datasets, vs. ~$100–500/month
  if left running continuously.
- Pre-existing project firewall gap found and fixed: `default-allow-ssh` was
  open to `0.0.0.0/0`. *(Appendix D2)*
- SSH access: `gcloud compute ssh --tunnel-through-iap`, switched from the
  default PuTTY/Plink backend to Windows' built-in OpenSSH
  (`CLOUDSDK_CORE_USE_OPENSSH=true`). *(Appendix A6)*
- **Software transfer:** .NET 8 installed directly via Microsoft's install
  script. MaxQuant can't be re-downloaded on the VM (same CAPTCHA issue), so
  the already-downloaded zip was relayed **local → GCS
  (`gs://individual-multiomics-project/software/`) → VM**.
- **Data transfer:** rather than `git clone` the (private) repo on the VM,
  copied just the two small `.dvc` pointer files to GCS and ran a
  git-free `dvc init --no-scm` + `dvc pull` on the VM. *(Appendix D4)*
  Pulled PXD025280 (~16.5 GB) from GCS to the VM in ~2m22s (~116 MB/s) — much
  faster than the original PRIDE download.
- `mqpar.xml` built the same way as §6 (`--create` + `configure_mqpar.py`),
  `numThreads=14` (of 16 vCPU, leaving headroom).
  `fixedCombinedFolder` (which would fully separate MaxQuant's working
  scratch from the raw folder) doesn't exist as a settable tag in this
  MaxQuant version — but on the VM this doesn't matter, since the whole
  `~/work/` directory is ephemeral and gets deleted after the job (unlike
  the local machine, where `RawData/` is DVC-tracked and needs to stay
  clean — see Appendix E2).
- Launched detached (`setsid nohup ... & disown -a`) so it survives SSH
  disconnection. *(Appendix D8)*
- Same `contaminants.fasta` parsing fix needed again (the VM's mqpar.xml was
  generated fresh, not copied from local). *(Appendix D6)*
- **Status:** running, `numThreads=14`. Pulled ahead of the local run (§6)
  well before the local one was stopped, and is now the sole run for
  PXD025280 — monitored hourly (§8) until `MaxQuantSearch/output/` is
  populated.

## 8. Monitoring

- Hourly cron check (session-only, `:07` past the hour) reports job step,
  process liveness, and memory headroom for **both** the local run and the
  VM run — including flagging (not auto-fixing) if the VM's Spot instance
  gets preempted mid-run.
- Considered Claude Code's mobile "Remote Control" (`claude remote-control`
  + iOS/Android app) for phone-based monitoring — deferred by the user for
  now (currently a Research Preview feature).

## 9. Peptide-intensity export checkpoint

`src/python/export_peptide_intensities.py` reads MaxQuant's `peptides.txt`
and writes a peptide × sample intensity table to both CSV and XLSX, mirroring
the paper's own checkpoint (Progenesis QI peptide intensities exported to
Excel before downstream statistics). Run against the real VM output (§10):
15,346 peptides × 16 samples.

## 10. VM run completion and housekeeping

The VM run (§7) finished all 54 MaxQuant job steps (see the job sequence
above) while the local run was still stuck partway through — the local run
was stopped intentionally rather than left competing for the same result.

- **Pulling results down:** on the VM, `dvc add MaxQuantSearch/output` +
  `dvc push` (using the VM's git-free DVC checkout from §7); the resulting
  `output.dvc` pointer was relayed back through GCS (same pattern as
  sending the two pointer files *to* the VM, reversed) and placed at
  `MaxQuantSearch/PXD025280_20260816/output.dvc` locally, then `dvc pull`.
  17 files, ~1.06 GB: `proteinGroups.txt` (2,623 protein groups),
  `peptides.txt` (15,346 peptides), `evidence.txt`, `msms.txt`, and the
  rest of MaxQuant's standard output.
- **Freed local disk (~33 GB):** with `RawData/PXD025280_20260816` fully
  confirmed in sync with the GCS remote (`dvc status -c`), both the working
  copy and the corresponding local DVC cache objects were removed — the
  `.dvc` pointer stays, so `dvc pull` restores it later if needed. (DVC has
  no single built-in "evict but keep tracked" command; the cache objects
  were identified and removed directly by reading the tracked directory's
  `.dir` manifest for the exact hash list, rather than deleting the whole
  cache indiscriminately.) *(Appendix E3)*
- **VM deleted** (not just stopped) — full delete rather than
  stop-and-keep-the-disk, consistent with the cost practice in §7, since
  MaxQuant's installer is kept in GCS specifically to make re-setup on a
  fresh VM fast (see "Deleted vs. stopped" trade-off, §7).
- **GCS orphan check:** compared every object actually in the bucket
  against every object referenced by the three current `.dvc` pointers
  (`RawData`, `reference`, `output`) by walking each `.dir` manifest. Found
  exactly one unreferenced object (41 bytes) — a leftover from the original
  DVC↔GCS connectivity test done in §1, before any real data existed.
  Removed it; everything else in the bucket was confirmed to be exactly
  what the pointers expect, nothing missing.

## 11. Downstream export formats

`src/python/export_for_downstream.py` reads `proteinGroups.txt` and writes
two formats into `results/PXD025280_20260816/`, applying this project's
quantification filter (exclude decoys and potential contaminants, require
≥3 unique peptides — the paper's own threshold, see §5): 2,623 protein
groups → 1,477 after filtering.

- **`protein_lfq_matrix.csv`** — protein × sample LFQ intensity matrix
  (`Protein_ID`, `Gene_name` + one column per sample), the standard wide
  format expected as input by R packages (limma, DEP, MSstats, ...).
- **`reactome_protein_list.txt`** — plain UniProt accession list (one per
  line), for Reactome's Pathway Analysis "Analyse Data" tool
  (reactome.org/PathwayBrowser), matching the pathway analysis approach the
  paper used (§5).

Column/identifier headers are still raw-file IDs, not conditions — real
group-based analysis is blocked on §4.

## 12. Differential expression: empirical Bayes + Benjamini-Hochberg FDR

The paper's actual significance test (§5) — empirical Bayes-moderated
t-test with BH-FDR correction — hadn't been implemented yet; everything
before this was either MaxQuant's own search-level FDR (a different thing,
see "Deviations") or fold-changes with no significance test at all (§9's
arbitrary-pair test). Paused the volcano-plot request specifically to build
this first, since a volcano plot's y-axis depends on it.

`src/R/differential_expression.R` (R + Bioconductor `limma`, installed via
`BiocManager::install('limma')` — not present by default *(Appendix F1)*):

1. Log2-transforms intensities (MaxQuant's `0` = "not quantified in this
   sample" → treated as `NA`, not `log2(0)`).
2. Within-sample median normalization (subtract each sample's own median),
   matching the paper's normalization step.
3. `limma::lmFit` + `eBayes` for the moderated t-test, optionally blocking
   on a donor/pairing variable via `duplicateCorrelation` (`--donor=`) —
   matching the paper's donor-blocked linear model, supported but unused
   for now since real donor assignments aren't available (§4).
4. `topTable(..., adjust.method = "BH")` for Benjamini-Hochberg FDR.

Takes a generic `<matrix.csv> <group_labels> <out.csv>` interface (group
labels are a comma-separated vector, one per sample column, so it isn't
tied to any particular comparison) *(Appendix F2)*. Tested — same spirit
as §9's arbitrary pairing — with an even 8-vs-8 split of the 16 samples in
list order (no biological meaning, no donor blocking): 1,477 proteins
tested, 17 with FDR < 0.05. Ready to rerun with real group (and donor) labels once §4 is
resolved; also ready to feed directly into a volcano plot (`logFC` +
`FDR` columns) once that's picked back up.
