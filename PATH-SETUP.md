# Path setup after moving the repo to `C:\Master_Renamed_same_format_accross`

**Read this before running anything.** All 17 programs currently have every path
pointing at `C:\Master_Renamed_same_format_accross`. Running them as-is does two bad
things and one useless one.

---

## Why you can't just run them

**1. PHI would land inside the git working tree.**

```
%let g_path = C:\Master_Renamed_same_format_accross;
```

`g` holds `prep_md1..8` and `master_data_merged` — full patient records. Inside the repo
folder, one `git add -f`, one mis-scoped `git add -A`, or one edited `.gitignore` commits
PHI into history where removing it needs a rewrite. And `git clean -xdf`, a routine
tidy-up, **deletes ignored files** — it would wipe every prep dataset.

This is RESEARCH Pitfall 9 and PCM-C-04. The repo moved to local disk; the data must not
follow it.

**2. The read-only sources aren't on C:.**

```
%let source_path = C:\Master_Renamed_same_format_accross;
```

`master_data_1..8.sas7bdat` live on P:. Phase 1 and Phase 3 would fail at `libname src`
or find nothing.

**3. All your existing work is on P: and would be ignored.**

`g.prep_md1..8`, `g.master_data_merged`, the qc artifacts and the logs are all under
`P:\...\merge`. Pointed at C:, the programs would rebuild from scratch — or fail because
the sources aren't there either.

---

## The correct split

| Variable | Value | Why |
|---|---|---|
| `sas_path` | `C:\Master_Renamed_same_format_accross\sas` | repo — code is version-controlled |
| `docs_path` | `C:\Master_Renamed_same_format_accross\docs` | repo — `DECISIONS.md` is a committed doc |
| `source_path` | `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross` | read-only masters |
| `g_path` | `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge` | **PHI — outside the repo** |
| `qc_path` | `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc` | beside the data it describes |
| `logs_path` | `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs` | beside the data |

Code and docs on C: (in git). Data, QC output and logs on P: (not in git). That is exactly
what PCM-C-04 specified before the paths drifted.

**Trade-off on `qc_path`:** QC artifacts on P: are not version-controlled, so there is no
commit history for them. PCM-R-11 wants them committed. Two options:

- **Keep them on P:** (the table above). Zero migration, works immediately. If you want
  history, copy finished `qc\*.txt` into the repo as a separate step.
- **Move `qc_path` into the repo:** `C:\Master_Renamed_same_format_accross\qc`. Then copy
  the existing artifacts across, and make sure `.gitignore` excludes `*.sas7bdat` — the
  qc folder holds `ownership_map.sas7bdat`, which must never be committed.

The script below uses the first. Change one line to use the second.

---

## Fix all 17 files

Save as `fix_paths.ps1` in the repo root and run it. It shows a dry run first.

```powershell
# fix_paths.ps1 -- set every path macro variable across all programs
$sasDir = "C:\Master_Renamed_same_format_accross\sas"
$pBase  = "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross"

$paths = @{
  'source_path' = $pBase
  'g_path'      = "$pBase\merge"
  'qc_path'     = "$pBase\merge\qc"
  'logs_path'   = "$pBase\merge\logs"
  'sas_path'    = "C:\Master_Renamed_same_format_accross\sas"
  'docs_path'   = "C:\Master_Renamed_same_format_accross\docs"
}

$DryRun = $true    # <-- set to $false to actually write

Get-ChildItem "$sasDir\*.sas" | ForEach-Object {
  $file    = $_.FullName
  $lines   = Get-Content $file
  $changed = $false

  $new = $lines | ForEach-Object {
    $line = $_
    foreach ($k in $paths.Keys) {
      if ($line -match "^\s*%let\s+$k\s*=") {
        $replacement = "%let $k = $($paths[$k]);"
        if ($line.Trim() -ne $replacement) {
          Write-Host "$($_.Length -gt 0)" -NoNewline:$false
          Write-Host ("  {0,-22} {1}" -f $k, $paths[$k])
          $changed = $true
        }
        $line = $replacement
      }
    }
    $line
  }

  if ($changed) {
    Write-Host "== $($_.Name)" -ForegroundColor Cyan
    if (-not $DryRun) { $new | Set-Content $file -Encoding ASCII }
  }
}

if ($DryRun) { Write-Host "`nDRY RUN -- set `$DryRun = `$false to apply" -ForegroundColor Yellow }
```

---

## Verify before running any SAS

```powershell
# 1. No path variable should still point at the C: root (sas_path and docs_path are fine)
Select-String -Path "C:\Master_Renamed_same_format_accross\sas\*.sas" `
  -Pattern '^%let (source_path|g_path|qc_path|logs_path)\s*=\s*C:' |
  Select-Object Filename, Line
# EXPECT: no output. Any hit means PHI or source data is pointed at the repo.

# 2. Confirm the split is right
Select-String -Path "C:\Master_Renamed_same_format_accross\sas\*.sas" -Pattern '^%let \w+_path' |
  ForEach-Object { $_.Line.Trim() } | Sort-Object -Unique

# 3. The four P: directories must exist
"$pBase", "$pBase\merge", "$pBase\merge\qc", "$pBase\merge\logs" |
  ForEach-Object { "{0,-70} {1}" -f $_, (Test-Path $_) }

# 4. The sources must actually be where source_path says
Get-ChildItem "$pBase\master_data_*.sas7bdat" | Select-Object Name, Length
# EXPECT: eight files.

# 5. Existing work must be where g_path says
Get-ChildItem "$pBase\merge\*.sas7bdat" | Select-Object Name
# EXPECT: prep_md1..8, master_data_merged, analytic_cohort.
```

---

## Then check git can't see the data

```powershell
cd C:\Master_Renamed_same_format_accross
git status --ignored --short | Select-String '\.sas7bdat|\.xlsx'
```

Expect no output. If any `.sas7bdat` shows up — even as ignored — something under the repo
is holding data, and that needs sorting before your next commit.

---

## Standing recommendation: one config file

Path drift has now broken this pipeline three times — the C:/P: `sas_path` mismatch that
made `03_prep_all.sas` silently include nothing, the `qc_path` move that separated
`ownership_map` from the program reading it, and this. Seventeen files each declaring its
own copy of six paths is the cause.

The fix is one `00_config.sas` holding the six `%let` statements, with every other program
starting:

```sas
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
```

Only that one `%include` line carries a hardcoded path. Everything else is defined once,
and a future move is a one-line edit rather than a 17-file sweep with a verification pass.

Worth doing before Phase 8, since `99_run_all.sas` will need consistent paths anyway.
