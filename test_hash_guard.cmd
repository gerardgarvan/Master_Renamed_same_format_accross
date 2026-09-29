@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM  test_hash_guard.cmd -- HARD-01 / HARD-02 verification
REM
REM  Steps:
REM    1. Run program 19 to refresh qc/19_raw_files.csv
REM    2. Run 19b to seed docs/raw_hash_baseline.csv (8 rows)
REM    3. Run program 19 again -- expect HARD-01 hash guard PASSED
REM    4. Tamper: corrupt one sha256 in raw_hash_baseline.csv
REM    5. Run program 19 -- expect HARD-01 HASH GUARD FAILED
REM    6. Restore raw_hash_baseline.csv via git restore
REM    7. Run program 19 -- expect HARD-01 hash guard PASSED
REM
REM  Usage: test_hash_guard.cmd
REM  Logs written to: LOGS_PATH (same as run_pipeline.cmd)
REM ============================================================

set SAS_PATH=C:\Master_Renamed_same_format_accross\sas
set DOCS_PATH=C:\Master_Renamed_same_format_accross\docs
set BASELINE=%DOCS_PATH%\raw_hash_baseline.csv
set LOGS_PATH=P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs
set LOG_19=%LOGS_PATH%\19_raw_dir_inventory.log
set LOG_19B=%LOGS_PATH%\19b_seed_hash_baseline.log

REM ---- Machine-specific SAS_EXE override (mirrors run_pipeline.cmd) ----
if exist "%~dp0config.local.cmd" call "%~dp0config.local.cmd"
if not defined SAS_EXE set "SAS_EXE=C:\Program Files\SAS94\SASFoundation\9.4\sas.exe"

if not exist "%SAS_EXE%" (
  echo ERROR: SAS_EXE not found: "%SAS_EXE%"
  exit /b 2
)

echo.
echo ============================================================
echo  HARD-01 / HARD-02 Hash Guard Verification
echo ============================================================

REM ============================================================
REM  STEP 1: Run program 19 to refresh qc/19_raw_files.csv
REM ============================================================
echo.
echo [STEP 1] Running program 19 to refresh qc/19_raw_files.csv ...
start "" /wait "%SAS_EXE%" ^
    -sysin "%SAS_PATH%\19_raw_dir_inventory.sas" ^
    -log  "%LOG_19%" ^
    -nosplash -icon -sasuser WORK ^
    -set RUN_ALL 1

set _EC=!ERRORLEVEL!
echo Step 1 exit code: !_EC!

REM On first run (no baseline yet) program 19 will abort -- that is expected.
REM The important thing is that qc/19_raw_files.csv is refreshed.
REM We do NOT fail the script here.
echo NOTE: exit code != 0 at Step 1 is expected if baseline does not exist yet.

REM ============================================================
REM  STEP 2: Run 19b to seed docs/raw_hash_baseline.csv
REM ============================================================
echo.
echo [STEP 2] Running 19b to seed docs/raw_hash_baseline.csv ...

if exist "%BASELINE%" (
  echo WARNING: %BASELINE% already exists.
  echo          19b will abort without overwriting -- this is by design (D-09).
  echo          If you want to re-seed, delete the file and re-run this script.
  echo          Skipping 19b and continuing to Step 3.
  goto :step3
)

start "" /wait "%SAS_EXE%" ^
    -sysin "%SAS_PATH%\19b_seed_hash_baseline.sas" ^
    -log  "%LOG_19B%" ^
    -nosplash -icon -sasuser WORK ^
    -set RUN_ALL 1

set _EC=!ERRORLEVEL!
if !_EC! NEQ 0 (
  echo ERROR: 19b exited with code !_EC! -- check log: %LOG_19B%
  echo        Common causes: qc/19_raw_files.csv not found, wrong column order,
  echo        or fewer than 8 md-master rows in that file.
  exit /b !_EC!
)

REM Verify baseline was written with 8 data rows (header + 8 = 9 lines)
set _ROWS=0
for /f %%R in ('find /c /v "" "%BASELINE%" 2^>nul') do set _ROWS=%%R
if !_ROWS! LSS 9 (
  echo ERROR: %BASELINE% has only !_ROWS! line(s^) -- expected 9 (header + 8 md rows^).
  exit /b 2
)
echo Step 2 OK: baseline seeded with !_ROWS! line(s^) (header + data^).

:step3
REM ============================================================
REM  STEP 3: Run program 19 -- expect HARD-01 hash guard PASSED
REM ============================================================
echo.
echo [STEP 3] Running program 19 -- expecting hash guard PASSED ...
start "" /wait "%SAS_EXE%" ^
    -sysin "%SAS_PATH%\19_raw_dir_inventory.sas" ^
    -log  "%LOG_19%" ^
    -nosplash -icon -sasuser WORK ^
    -set RUN_ALL 1

set _EC=!ERRORLEVEL!
findstr /c:"HARD-01 hash guard passed" "%LOG_19%" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo FAIL [STEP 3]: "HARD-01 hash guard passed" not found in log.
  echo               SAS exit code: !_EC!. Check: %LOG_19%
  exit /b 2
)
findstr /b /c:"ERROR" "%LOG_19%" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
  echo FAIL [STEP 3]: ERROR line(s^) found in log despite guard passing.
  echo               Check: %LOG_19%
  exit /b 2
)
echo PASS [STEP 3]: Hash guard passed, 0 ERROR lines in log.

REM ============================================================
REM  STEP 4: Tamper -- corrupt one sha256 in the baseline
REM ============================================================
echo.
echo [STEP 4] Tampering: replacing first data sha256 with zeroes ...

REM Write a tampered copy by replacing the first data row's sha256 field
REM (64-char hex) with 64 zeroes.  We do this with a small PowerShell one-liner
REM so we do not need external tools.
powershell -NoProfile -Command ^
  "$f = Get-Content '%BASELINE%'; " ^
  "$header = $f[0]; " ^
  "$first = $f[1] -replace ',[0-9a-fA-F]{64},', (',' + '0'*64 + ','); " ^
  "$rest = $f[2..($f.Length-1)]; " ^
  "($header, $first) + $rest | Set-Content '%BASELINE%' -Encoding utf8"

if !ERRORLEVEL! NEQ 0 (
  echo ERROR: PowerShell tamper step failed.
  exit /b 2
)
echo Step 4: Baseline tampered (first data row sha256 set to 64 zeroes^).

REM ============================================================
REM  STEP 5: Run program 19 -- expect HARD-01 HASH GUARD FAILED
REM ============================================================
echo.
echo [STEP 5] Running program 19 -- expecting hash guard FAILED ...
start "" /wait "%SAS_EXE%" ^
    -sysin "%SAS_PATH%\19_raw_dir_inventory.sas" ^
    -log  "%LOG_19%" ^
    -nosplash -icon -sasuser WORK ^
    -set RUN_ALL 1

set _EC=!ERRORLEVEL!
findstr /c:"HARD-01 HASH GUARD FAILED" "%LOG_19%" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo FAIL [STEP 5]: Expected "HARD-01 HASH GUARD FAILED" in log but did not find it.
  echo               SAS exit code: !_EC!. Check: %LOG_19%
  exit /b 2
)
echo PASS [STEP 5]: Hash guard fired correctly on tampered baseline.

REM ============================================================
REM  STEP 6: Restore docs/raw_hash_baseline.csv via git restore
REM ============================================================
echo.
echo [STEP 6] Restoring baseline via git restore ...
git -C "C:\Master_Renamed_same_format_accross" restore docs/raw_hash_baseline.csv
if !ERRORLEVEL! NEQ 0 (
  echo ERROR: git restore failed. Check that git is on PATH and the file is committed.
  exit /b 2
)
echo Step 6: Baseline restored from git.

REM ============================================================
REM  STEP 7: Run program 19 -- expect HARD-01 hash guard PASSED
REM ============================================================
echo.
echo [STEP 7] Running program 19 -- expecting hash guard PASSED after restore ...
start "" /wait "%SAS_EXE%" ^
    -sysin "%SAS_PATH%\19_raw_dir_inventory.sas" ^
    -log  "%LOG_19%" ^
    -nosplash -icon -sasuser WORK ^
    -set RUN_ALL 1

set _EC=!ERRORLEVEL!
findstr /c:"HARD-01 hash guard passed" "%LOG_19%" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo FAIL [STEP 7]: "HARD-01 hash guard passed" not found in log after restore.
  echo               SAS exit code: !_EC!. Check: %LOG_19%
  exit /b 2
)
findstr /b /c:"ERROR" "%LOG_19%" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
  echo FAIL [STEP 7]: ERROR line(s^) found in log after restore.
  echo               Check: %LOG_19%
  exit /b 2
)
echo PASS [STEP 7]: Hash guard passed after restore, 0 ERROR lines.

REM ============================================================
REM  ALL STEPS PASSED
REM ============================================================
echo.
echo ============================================================
echo  ALL STEPS PASSED -- HARD-01 / HARD-02 verified.
echo  Plan 26-03 Task 3: reply "approved" to continue.
echo ============================================================
echo.
exit /b 0
