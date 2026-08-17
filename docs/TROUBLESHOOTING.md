# Troubleshooting log

Problems hit while building the pipeline (see [`PIPELINE.md`](PIPELINE.md)
for the process itself), grouped by area. Referenced from there by ID.

## A. Environment / auth / shell

- **A1 — `gcloud auth login` isn't enough for DVC.** DVC's Python client
  library needs separate Application Default Credentials:
  `gcloud auth application-default login`. The two commands write to
  different credential stores.
- **A2 — PowerShell execution policy blocks `gcloud.ps1`.** MaxQuant/gcloud
  wrapper scripts run through `gcloud.ps1` are blocked by Windows'
  default PowerShell execution policy. Fix: call `gcloud.cmd` directly
  instead of changing the policy.
- **A3 — Folder rename failed mid-restructure.** `Rename-Item` on
  `multiomics_project` failed with "file in use" (something — likely
  OneDrive sync or a lingering shell — held a handle). Fixed with
  `robocopy /MOVE` (which tolerates this better) followed by a plain
  `Move-Item` for the final nesting step.
- **A4 — `git push` needs a real browser for OAuth.** Git Credential
  Manager's browser-based OAuth flow can't complete inside this sandboxed,
  non-interactive shell. Fix: the user ran the first `git push` (and later,
  `gcloud auth login`) once in their own terminal window; the resulting
  cached credential then works for subsequent pushes from here.
- **A5 — Korean-character absolute paths break some `gcloud` invocations.**
  Commands like `gcloud storage cp` intermittently failed with a garbled
  "not recognized as an internal or external command" error when an
  absolute path containing the (Korean) `바탕 화면` desktop folder name was
  passed as an argument — but the exact same command with a **relative**
  path (after `cd`ing into the directory) works reliably. Root cause not
  fully diagnosed (likely a codepage/argument-encoding issue somewhere in
  gcloud's Windows wrapper); the relative-path workaround is now standard
  practice for all `gcloud storage` calls in this project.
- **A6 — `gcloud compute ssh` hangs / fails on Windows.** By default it
  shells out to PuTTY/Plink, which (a) prompts interactively to cache the
  host key on first connection — hangs forever in a non-interactive shell —
  and (b) intermittently threw the same garbled-path error as A5, likely
  because the Cloud SDK's own install path contains a space
  (`Google\Cloud SDK\`). Fix: `$env:CLOUDSDK_CORE_USE_OPENSSH = "true"`
  (also persisted at the User env-var level) to use Windows' built-in
  OpenSSH client instead — no more interactive prompt, no more path issue.

## B. Data acquisition

- **B1 — PDF skill's page-render path unavailable.** `pdftoppm` (poppler)
  wasn't installed, so the PDF skill's `Read(..., pages=...)` path failed.
  Worked around by using the `pdfplumber` Python library directly to
  extract text.
- **B2 — All 17 raw-file downloads rejected by curl.** `curl: (3) URL
  rejected: Malformed input to a URL function` on every file. Cause: the
  Python script that generated the URL list wrote Windows-style CRLF line
  endings by default, leaving a trailing `\r` on every URL. Fixed with
  `tr -d '\r'` on the URL list file before retrying; confirmed with a
  byte-level check (`b'\r' in data`) rather than trusting `grep`, which gave
  misleading results here.
- **B3 — One raw file failed checksum verification.**
  `20170724_JS_JL_38.raw`'s SHA1 didn't match PRIDE's reported checksum
  after the first download. Re-downloaded and re-verified; all 17 files
  passed on the second check.

## C. Local MaxQuant

- **C1 — `dotnet` not found.** MaxQuant's worker processes shell out to the
  bare `dotnet` command. .NET was installed in a separate terminal window,
  and the sandboxed shell's `PATH` wasn't refreshed to see it. Fixed by
  prepending the dotnet install dir to `PATH` in the same command that
  launches MaxQuant, every time.
- **C2 — Silent-looking failure at "Testing fasta files."** The run
  appeared to start, then stopped after only 4 of 54 job steps with no
  obvious error at first glance. Cause: the auto-generated
  `identifierParseRule` regex (`>[^|]*\|(.*?)\|`, written for standard
  UniProt-style `sp|ACCESSION|NAME` headers) doesn't match MaxQuant's own
  bundled `contaminants.fasta`, whose headers look like
  `>P00761 SWISS-PROT:P00761|TRYP_PIG ...` (no leading pipe). Fixed the
  parse rule for that FASTA entry to `>([^ ]*)`.
- **C3 — System froze, requiring a hard reboot.** `numThreads=8` needs
  roughly **32 GB RAM** by MaxQuant's own guidance (~4 GB/thread), but the
  machine has 16 GB total and only ~6 GB free at idle (before MaxQuant even
  started) — a >5x oversubscription that drove the system into memory
  thrashing until it became fully unresponsive. Reduced to `numThreads=4`
  (~16 GB needed) and cleaned up the partial run's scratch folder before
  restarting.

## D. Cloud (GCE VM)

- **D1 — Same garbled-path bug as A5**, hit again on
  `gcloud compute machine-types list --filter=...`; same relative-path
  workaround.
- **D2 — Project-wide SSH exposure found while setting up IAP.** The
  default network's `default-allow-ssh` firewall rule allowed
  `0.0.0.0/0` on port 22 for every VM in the project — pre-existing, not
  something this project created, but it would have undermined the "IAP
  only" access story for the new VM (and any future one). Confirmed no
  existing VMs depended on it, then narrowed the rule's source range to
  Google's IAP relay CIDR (`35.235.240.0/20`).
- **D3 — Boot disk resize warning.** `gcloud compute instances create`
  warned that the requested 150 GB boot disk was larger than the 10 GB
  Ubuntu image. Not an actual problem: Ubuntu 22.04's cloud image
  auto-grows the root partition on first boot; confirmed with `df -h`
  (146 GB usable) after creation.
- **D4 — `git clone` of the private repo failed on the VM.** No git
  credentials were configured there (deliberately — didn't want to put
  GitHub auth on an ephemeral VM). Rather than solve git auth, sidestepped
  it: copied just the two small `.dvc` pointer files
  (`RawData/PXD025280_20260816.dvc`, `reference.dvc`) to GCS, then ran
  `dvc init --no-scm` + `dvc remote add` + `dvc pull` on the VM — a
  git-free, read-only DVC checkout.
- **D5 — Inline heredoc scripts got mangled.** Passing a Python script as
  an inline heredoc through `PowerShell → gcloud → SSH → remote bash` (four
  layers of shell quoting) corrupted the script every time. Fixed by
  writing fixups as standalone `.py` files, uploading them to GCS, and
  pulling + running them as files on the VM instead of trying to inline
  them.
- **D6 — Same contaminants.fasta bug as C2, on the VM.** The VM's
  `mqpar.xml` was generated fresh (not copied from local), so it had the
  same broken default `identifierParseRule` and failed at the same
  "Testing fasta files" step. Reapplied the C2 fix directly on the VM.
  (This is exactly the gap `src/python/configure_mqpar.py` now closes for
  future runs — apply it once, on either machine, right after
  `--create`.)
- **D7 — `unzip` missing.** Ubuntu's minimal cloud image doesn't include
  it by default; `sudo apt-get install -y unzip`.
- **D8 — Background MaxQuant run didn't survive session teardown.** A
  first attempt using `nohup dotnet ... & disown` appeared to launch, but
  the process (and its many child workers) were gone by the time of a later
  check. Fixed by using `setsid nohup ... & disown -a` for a fully
  detached session, which survived subsequent SSH disconnects.

## E. DVC / git housekeeping

- **E1 — `RawData/*.dvc` was never committed.** `dvc add` and `dvc push`
  had been run successfully, but the resulting `.dvc` pointer file and
  `.gitignore` were left uncommitted — so GitHub had no record of what was
  in GCS. Caught by routinely checking `git status` before moving on;
  committed the missing files.
- **E2 — `dvc add` swept up ~18 GB of MaxQuant's own scratch files.**
  MaxQuant writes working data directly into whatever folder holds the raw
  files, regardless of `customTxtFolder`: a shared `combined/` folder, a
  per-raw-file working directory (same basename as each `.raw` file, no
  extension), a `.index` file per raw file, and its own copy of
  `mqpar.xml`. None of that is raw acquisition data, but a routine
  `dvc status` check (prompted by wanting to re-verify DVC state before the
  VM work) showed the tracked directory had ballooned from 21 files
  (~16.5 GB) to 4,677 files (~34 GB) mid-search. Fixed with explicit
  `.dvcignore` patterns (`combined/`, `*.index`, `mqpar.xml`, and a glob
  matching the per-file scratch directories by the lab's raw-file naming
  convention); confirmed the directory hash matched the original clean
  state and that GCS already had the correct content (no re-push needed).
- **E3 — DVC cache objects are read-only.** Manually deleting specific
  cache objects (E2's approach, applied to `RawData` in §10 to free local
  disk without losing remote-tracked data) failed with `PermissionError:
  [WinError 5]` on some files. DVC marks its cache objects read-only by
  design (to stop accidental in-place edits); fixed by clearing the
  read-only attribute (`os.chmod(path, stat.S_IWRITE)`) immediately before
  each `os.remove()`.

## F. R / statistics

- **F1 — R installed but not on `PATH`; `limma` not installed.** R 4.3.2
  was already installed (`C:\Program Files\R\R-4.3.2\`) but `Rscript` wasn't
  resolvable via `Get-Command` — same class of issue as the .NET/dotnet
  `PATH` problem (Appendix C1), fixed the same way: call `Rscript.exe` by
  its full path rather than relying on `PATH`. Bioconductor's `limma`
  (needed for the empirical Bayes-moderated t-test — the paper's actual
  significance test, §12) isn't part of base R; installed via
  `BiocManager::install('limma')` (pulls in `statmod` as a dependency).
- **F2 — bash's `$GROUPS` is a reserved special variable.** A script
  invocation used a shell variable named `GROUPS` to hold a comma-separated
  sample-group label string (e.g. `"A,A,A,A,B,B,B,B"`) to pass to the R
  script. Silently wrong: bash has a built-in special variable `GROUPS`
  (the list of Unix groups the current user belongs to), so `"$GROUPS"`
  expanded to that instead of the intended assignment — the R script
  received a single numeric group ID (`"197609"`, the same GID visible in
  every `ls -la` listing all session) instead of 16 comma-separated labels,
  and failed with a confusing "group has 1 entries" error. Renaming the
  shell variable (`SAMPLE_GROUPS`) fixed it immediately. General lesson:
  avoid all-caps shell variable names here without first checking they
  don't collide with a bash built-in (`UID`, `PPID`, `GROUPS`, `BASH*`,
  `HOST*`, ... are all reserved/special).
