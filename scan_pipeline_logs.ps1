# scan_pipeline_logs.ps1 -- PeCAN Master Dataset Integration
# Scans per-program SAS logs for known error/warning patterns.
# Writes a PASS/FAIL summary to qc/22_pipeline_scan.txt (ascii).
# Called by run_pipeline.cmd as the last step after all programs complete.
# Exit code: 0 = PASS, 1 = FAIL
#
# Usage: powershell -ExecutionPolicy Bypass -File scan_pipeline_logs.ps1 [-RunStart "<datetime>"]
# RunStart defaults to 30 minutes before now if not supplied.

param([string]$RunStart = "")

# ---- Path configuration (edit these two lines per machine if needed) ----
$logsPath = "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs"
$outFile  = "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc\22_pipeline_scan.txt"

# ---- Run-start threshold ----
if ($RunStart -ne "") {
    $runStart = [datetime]::Parse($RunStart)
} else {
    $runStart = (Get-Date).AddMinutes(-30)
}

# ---- Error/warning patterns (anchored so echoed source code does not match) ----
$errorPatterns = @(
    '^ERROR',
    '^WARNING',
    '^NOTE: MERGE statement has more than one data set with repeats of BY values',
    '^NOTE: Invalid (data|argument)',
    '^NOTE: .*values have been converted'
)

# ---- Allowlist: known pre-existing benign patterns that should not trigger FAIL ----
$allowlist = @(
    # encoding noise (pre-existing, PCM-F-10)
    'character data was lost during transcoding',
    # program 02: pre-existing type mismatch between md3 and md8 for Admit_BMI
    'OWN-04 TYPE MISMATCH -- Admit_BMI',
    # program 08: pre-existing multiple-lengths note on varname column
    'Multiple lengths were specified for the variable varname',
    # program 17: pre-existing guard when cognitive score column is absent from ext_candidates
    'No cognitive score column \(COGNI and SCORE\)',
    # program 19: two xlsx files that cannot be read by the SAS XLSX engine (password-protected or incompatible)
    "Couldn't find range or sheet in spreadsheet",
    'File _XLW\.',
    'WORK\.INV_\d+_S\d+ may be incomplete',
    # program 19: SUBSTR called on a 2-char string when checking 3-char extension -- benign
    'Invalid argument 3 to function SUBSTR'
)

# ---- Collect findings ----
$findings = @()

$logFiles = Get-ChildItem "$logsPath\*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne '99_run_all.log' -and $_.LastWriteTime -ge $runStart }

foreach ($logFile in $logFiles) {
    $lines = Get-Content $logFile.FullName -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        foreach ($pattern in $errorPatterns) {
            if ($line -match $pattern) {
                $allowed = $false
                foreach ($ap in $allowlist) {
                    if ($line -match $ap) {
                        $allowed = $true
                        break
                    }
                }
                if (-not $allowed) {
                    $findings += [PSCustomObject]@{
                        Log     = $logFile.Name
                        Line    = $line.Trim()
                        Pattern = $pattern
                    }
                }
                break
            }
        }
    }
}

# ---- Build summary ----
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$status = if ($findings.Count -eq 0) { "PASS" } else { "FAIL" }

$summaryLines = @(
    "Pipeline Log Scan -- $timestamp",
    "Status: $status",
    "Findings: $($findings.Count)",
    "------------------------------------------------------------"
)

foreach ($f in $findings) {
    $summaryLines += "$($f.Log): $($f.Line)  [pattern: $($f.Pattern)]"
}

# ---- Write summary to file (ascii) ----
$summaryLines | Out-File -FilePath $outFile -Encoding ascii

# ---- Echo to console ----
foreach ($l in $summaryLines) {
    Write-Host $l
}

# ---- Exit with appropriate code ----
if ($findings.Count -gt 0) { exit 1 } else { exit 0 }
