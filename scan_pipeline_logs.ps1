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
    '^NOTE: Variable .+ is uninitialized',
    '^NOTE: MERGE statement has more than one data set with repeats of BY values',
    '^NOTE: Invalid (data|argument)',
    '^NOTE: .*values have been converted'
)

# ---- Allowlist: benign patterns that should not trigger FAIL ----
$allowlist = @(
    'character data was lost during transcoding'
    # add more benign patterns here
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
