# Runbook

Every command needed to reproduce this project from a bare Windows machine,
in order. [`PIPELINE.md`](PIPELINE.md) explains *why* each decision was
made; this document is the *how* — copy-pasteable commands, grouped into
stages. Problems referenced by ID (e.g. *Appendix A1*) are in
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

Shell: bash (git-bash on Windows) unless marked `# PowerShell`. Paths use
`C:\Users\yjlee\...` for this machine — substitute your own.

---

## Stage 0 — One-time environment setup

### 0.1 gcloud CLI

```bash
winget install --id Google.CloudSDK
```

```bash
# Run in your OWN terminal window, not through an automated/sandboxed shell —
# both of these open a browser for OAuth (Appendix A4).
gcloud auth login                          # CLI credentials
gcloud auth application-default login      # separate store, needed by DVC's Python client (Appendix A1)
```

```bash
gcloud config set project gothic-sylph-410801
```

If `gcloud compute ssh` will be used later (Stage 2b), also do this once
(persists at the User env-var level, PowerShell only — Appendix A6):

```powershell
# PowerShell
[Environment]::SetEnvironmentVariable("CLOUDSDK_CORE_USE_OPENSSH", "true", "User")
```

### 0.2 git + GitHub

```bash
git init
git config user.name "Young-June-LEE"
git config user.email "yjleeyjyj@snu.ac.kr"
git remote add origin https://github.com/yjleeyjyj-svg/individual-multiomics-project.git
```

First `git push` needs to run in a real (non-sandboxed) terminal once, to
complete Git Credential Manager's browser OAuth flow (Appendix A4); it's
cached after that.

### 0.3 Python

```bash
pip install -r requirements.txt
```

(`pandas`, `numpy`, `scipy`, `statsmodels`, `matplotlib`, `seaborn`,
`requests`, `pyteomics`, `openpyxl`, `dvc[gs]`.)

### 0.4 DVC + GCS remote

```bash
dvc init
dvc remote add -d gcsremote gs://individual-multiomics-project/dvcstore
```

Verify before trusting it with real data:

```bash
echo "connectivity test" > _dvc_test.txt
dvc add _dvc_test.txt && dvc push
rm _dvc_test.txt && rm -rf .dvc/cache && dvc pull
cat _dvc_test.txt   # should print "connectivity test"
rm _dvc_test.txt _dvc_test.txt.dvc
```

### 0.5 R + Bioconductor packages

R 4.3.2 was already installed but not on `PATH` (Appendix F1) — call
`Rscript.exe` by full path, or use `run_pipeline.sh`, which resolves it
automatically.

```powershell
# PowerShell
$Rscript = "C:\Program Files\R\R-4.3.2\bin\Rscript.exe"
& $Rscript -e "if (!requireNamespace('BiocManager', quietly=TRUE)) install.packages('BiocManager', repos='https://cloud.r-project.org'); BiocManager::install(c('limma','EnhancedVolcano'), update=FALSE, ask=FALSE)"
& $Rscript -e "install.packages(c('httr','jsonlite'), repos='https://cloud.r-project.org')"
```

(`httr`, not `httr2` — Appendix F3.)

---

## Stage 1 — Data acquisition (per PXD dataset)

Example throughout: **PXD025280**, downloaded 2026-08-16 →
`RawData/PXD025280_20260816/`.

### 1.1 Get the file list + checksums from PRIDE

```bash
curl -s "https://www.ebi.ac.uk/pride/ws/archive/v2/projects/PXD025280/files?pageSize=200" \
  -o pxd_files.json
```

### 1.2 Build a clean URL list and download

Generate `_urls.txt` (one HTTPS URL per file, `ftp.pride.ebi.ac.uk` mirrored
over HTTPS for resumable `curl -C -`), **with LF line endings** — a
Windows-text-mode Python write leaves CRLF and breaks curl (Appendix B2):

```bash
tr -d '\r' < _urls.txt > _urls_fixed.txt && mv _urls_fixed.txt _urls.txt
```

```bash
mkdir -p "RawData/PXD025280_20260816"
cd "RawData/PXD025280_20260816"
while IFS= read -r url; do
  fname=$(basename "$url")
  curl -sS -C - --retry 10 --retry-delay 5 -o "$fname" "$url"
done < _urls.txt
cd -
```

### 1.3 Verify checksums (PowerShell — `Get-FileHash`)

```powershell
# PowerShell
$dir = "RawData\PXD025280_20260816"
foreach ($line in Get-Content "$dir\_checksums_sha1.txt") {
    $expected, $fname = $line -split '\s+', 2
    $actual = (Get-FileHash -Path "$dir\$fname" -Algorithm SHA1).Hash
    if ($actual -ine $expected) { Write-Output "MISMATCH: $fname" }
}
```

Re-download and re-verify any mismatches (Appendix B3).

### 1.4 Track with DVC and push

```bash
dvc add RawData/PXD025280_20260816
dvc push RawData/PXD025280_20260816.dvc
git add RawData/PXD025280_20260816.dvc RawData/.gitignore
git commit -m "Add PXD025280 raw data"
git push origin master
```

Reference proteome FASTA (once per project, not per dataset):

```bash
mkdir -p reference
curl -s -o reference/uniprot_human_reviewed.fasta \
  "https://rest.uniprot.org/uniprotkb/stream?query=organism_id:9606+AND+reviewed:true&format=fasta"
dvc add reference && dvc push reference.dvc
git add reference.dvc && git commit -m "Add reference proteome" && git push
```

---

## Stage 2 — MaxQuant search

MaxQuant itself (registration + CAPTCHA at maxquant.org) and .NET 8 must be
obtained manually the first time — see [PIPELINE.md §6](PIPELINE.md). Once
downloaded, keep `MaxQuant_v2.8.1.0.zip` in
`gs://individual-multiomics-project/software/` permanently so future setup
(local or a fresh VM) never needs the CAPTCHA again.

### 2a. Local run

```bash
mkdir -p "MaxQuantSearch/PXD025280_20260816"
```

```powershell
# PowerShell — generate mqpar.xml
$MQ = "tools\MaxQuant\MaxQuant_v2.8.1.0"
& "$MQ\bin\MaxQuantCmd.exe" --create `
  --newMqpar "MaxQuantSearch\PXD025280_20260816\mqpar.xml" `
  --LCMSType ST --instrumentType TO `
  --pathFasta "reference\uniprot_human_reviewed.fasta" "$MQ\bin\conf\contaminants.fasta" `
  --pathRawFileFolder "RawData\PXD025280_20260816" `
  --useLFQ --useMBR --numThreads 4
```

Apply this project's parameters (enzyme, variable mods, output folder,
contaminants.fasta parse-rule fix — Appendix C2):

```bash
python src/python/configure_mqpar.py \
  "MaxQuantSearch/PXD025280_20260816/mqpar.xml" \
  --output-folder "$(pwd)/MaxQuantSearch/PXD025280_20260816/output" \
  --contaminants-fasta "$(pwd)/tools/MaxQuant/MaxQuant_v2.8.1.0/bin/conf/contaminants.fasta"
```

Run (`numThreads` sized to available RAM — MaxQuant wants ~4 GB/thread,
Appendix C3):

```bash
export PATH="/c/Program Files/dotnet:$PATH"   # Appendix C1
MQ="tools/MaxQuant/MaxQuant_v2.8.1.0"
dotnet "$MQ/bin/MaxQuantCmd.dll" "MaxQuantSearch/PXD025280_20260816/mqpar.xml"
```

### 2b. GCE VM run (recommended for anything beyond ~16 GB RAM / a few hours)

**Create the VM** (Spec chosen — see [PIPELINE.md §7](PIPELINE.md) for the
why):

```bash
gcloud compute instances create individual-multiomics-project \
  --project=gothic-sylph-410801 --zone=asia-northeast3-a \
  --machine-type=c2d-standard-16 \
  --provisioning-model=SPOT --instance-termination-action=STOP \
  --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud \
  --boot-disk-size=150GB --boot-disk-type=pd-balanced \
  --scopes=storage-rw
```

One-time per project: narrow the default SSH firewall rule to Google's IAP
range (Appendix D2):

```bash
gcloud compute firewall-rules update default-allow-ssh \
  --project=gothic-sylph-410801 --source-ranges=35.235.240.0/20
```

**SSH in** (PowerShell, `CLOUDSDK_CORE_USE_OPENSSH` set per Stage 0.1):

```powershell
# PowerShell
$env:CLOUDSDK_CORE_USE_OPENSSH = "true"
gcloud compute ssh individual-multiomics-project \
  --project=gothic-sylph-410801 --zone=asia-northeast3-a --tunnel-through-iap \
  --command="<command>"
```

**Install .NET 8 + get MaxQuant from GCS** (relayed through GCS instead of
re-downloading — Appendix D-series):

```bash
# on the VM
curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
sudo bash /tmp/dotnet-install.sh --channel 8.0 --runtime dotnet --install-dir /opt/dotnet
sudo apt-get install -y unzip   # Appendix D7
mkdir -p ~/tools && gcloud storage cp gs://individual-multiomics-project/software/MaxQuant_v2.8.1.0.zip ~/tools/
cd ~/tools && unzip -q MaxQuant_v2.8.1.0.zip
```

**Pull data via a git-free DVC checkout** (Appendix D4 — avoids putting
GitHub credentials on an ephemeral VM):

```bash
# locally: relay the two small pointer files through GCS
cd "$(git rev-parse --show-toplevel)"   # or your project root
gcloud storage cp RawData/PXD025280_20260816.dvc gs://individual-multiomics-project/software/pointers_tmp/
gcloud storage cp reference.dvc gs://individual-multiomics-project/software/pointers_tmp/
```

```bash
# on the VM
mkdir -p ~/work/RawData && cd ~/work
python3 -m venv .venv && .venv/bin/pip install -q 'dvc[gs]'
gcloud storage cp gs://individual-multiomics-project/software/pointers_tmp/PXD025280_20260816.dvc RawData/
gcloud storage cp gs://individual-multiomics-project/software/pointers_tmp/reference.dvc .
.venv/bin/dvc init --no-scm -f
.venv/bin/dvc remote add -d gcsremote gs://individual-multiomics-project/dvcstore
.venv/bin/dvc pull
```

**Configure and run** (same `configure_mqpar.py` as the local path, just
run on the VM; `numThreads` sized to the VM's larger RAM):

```bash
# on the VM
export PATH=/opt/dotnet:$PATH
mkdir -p ~/work/MaxQuantSearch/output
dotnet ~/tools/MaxQuant_v2.8.1.0/bin/MaxQuantCmd.dll --create \
  --newMqpar ~/work/MaxQuantSearch/mqpar.xml --LCMSType ST --instrumentType TO \
  --pathFasta ~/work/reference/uniprot_human_reviewed.fasta ~/tools/MaxQuant_v2.8.1.0/bin/conf/contaminants.fasta \
  --pathRawFileFolder ~/work/RawData/PXD025280_20260816 \
  --useLFQ --useMBR --numThreads 14

python3 ~/work/configure_mqpar.py ~/work/MaxQuantSearch/mqpar.xml \
  --output-folder /home/yjlee/work/MaxQuantSearch/output \
  --contaminants-fasta /home/yjlee/tools/MaxQuant_v2.8.1.0/bin/conf/contaminants.fasta
# (copy src/python/configure_mqpar.py to the VM first, e.g. via the same
# GCS-relay pattern used for the .dvc pointer files above)

# launch detached so it survives SSH disconnect (Appendix D8)
cd ~/work/MaxQuantSearch
setsid nohup dotnet ~/tools/MaxQuant_v2.8.1.0/bin/MaxQuantCmd.dll mqpar.xml > run.log 2>&1 < /dev/null & disown -a
```

**Monitor** (poll periodically; `run.log`'s last line names the current
job — see [PIPELINE.md §6](PIPELINE.md) for the full 54-step list):

```bash
# on the VM
tail -20 ~/work/MaxQuantSearch/run.log
ps aux | grep dotnet | grep -v grep
free -h
```

**Retrieve results, then tear down** (once
`~/work/MaxQuantSearch/output/proteinGroups.txt` exists):

```bash
# on the VM
cd ~/work && .venv/bin/dvc add MaxQuantSearch/output && .venv/bin/dvc push MaxQuantSearch/output.dvc
gcloud storage cp MaxQuantSearch/output.dvc gs://individual-multiomics-project/software/pointers_tmp/
```

```bash
# locally
gcloud storage cp gs://individual-multiomics-project/software/pointers_tmp/output.dvc \
  MaxQuantSearch/PXD025280_20260816/output.dvc
dvc pull MaxQuantSearch/PXD025280_20260816/output.dvc
git add MaxQuantSearch/PXD025280_20260816/output.dvc MaxQuantSearch/PXD025280_20260816/.gitignore
git commit -m "Track PXD025280 MaxQuant output" && git push
```

```bash
# delete the VM once results are confirmed safe in GCS (Stage 4 has the
# local-cache cleanup commands, if also freeing local disk)
gcloud compute instances delete individual-multiomics-project \
  --project=gothic-sylph-410801 --zone=asia-northeast3-a --quiet
```

---

## Stage 3 — Downstream pipeline (one command)

```bash
./run_pipeline.sh <dataset> [sample_groups] [donor_labels]
```

```bash
# Exports + Reactome ORA only (no group comparison yet):
./run_pipeline.sh PXD025280_20260816

# Full pipeline once sample_mapping.csv (docs/PIPELINE.md §4) is filled in:
./run_pipeline.sh PXD025280_20260816 EP,EP,LP,LP,EP,EP,LP,LP,EP,EP,LP,LP,EP,EP,LP,LP 1,2,3,4,1,2,3,4,1,2,3,4,1,2,3,4
```

This runs, in order: `export_peptide_intensities.py` →
`export_for_downstream.py` → `differential_expression.R` →
`volcano_plot.R` → `reactome_analysis.R`. See the script's header comment
or `docs/PIPELINE.md §§9–14` for what each stage does.

---

## Stage 4 — DVC / git housekeeping pattern

After any step that produces or changes tracked data:

```bash
dvc add <path>              # e.g. data/processed/PXD025280_20260816, results/PXD025280_20260816
dvc push <path>.dvc
git add <path>.dvc <path's-sibling-.gitignore-if-new>
git commit -m "..."
git push origin master
```

Periodically verify nothing was missed (Appendix E1) and that no
non-tracked scratch got swept in (Appendix E2 — MaxQuant especially likes
to pollute `RawData/`):

```bash
git status --short
dvc status
dvc status -c   # vs. the GCS remote
```

To free local disk for data that's fully confirmed safe in GCS, without
losing the ability to `dvc pull` it back later (Appendix E3 — cache objects
are read-only, `chmod` before `rm`):

```bash
dvc status -c <path>.dvc   # confirm "in sync" first
rm -rf <path>               # working copy
# then remove the specific cache objects listed in <path>.dvc's dir manifest
# (see the Python snippet in PIPELINE.md §10 / git history commit f2db215 area)
```
