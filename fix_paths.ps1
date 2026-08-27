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

$DryRun = $false    # <-- set to $false to actually write

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
