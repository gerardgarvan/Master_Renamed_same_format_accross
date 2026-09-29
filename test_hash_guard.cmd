@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM  test_hash_guard.cmd -- HARD-01 / HARD-02 verification
REM
REM  Steps:
REM    1. Run program 19 to refresh qc/19_raw_files.csv
REM       (aborts at Section 13 on first run -- expected)
REM    2. Run 19b to seed docs/raw_hash_baseline.csv (8 rows)
REM    3. Run program 19 again -- expect HARD-01 hash guard PASSED
REM    4. Back up baseline, then corrupt one sha256
REM    5. Run program 19 -- expect HARD-01 HASH GUARD FAILED
REM    6. Restore baseline from the step-4 backup
REM    7. Run program 19 -- expect HARD-01 hash guard PASSED
REM
REM  Revised 2026-09-29:
REM    - findstr checks anchored to line start (/b). Unanchored
REM      patterns matched the macro source echoed into the log, so
REM      Step 5 passed even when the guard did not fire.
REM    - Restore uses a local backup copy instead of git restore
REM      (a freshly seeded baseline is not yet committed).
REM    - Any failure after the tamper restores the baseline first.
REM    - Tamper is verified; ASCII output (no UTF-8 BOM).
REM    - One log per step in logs\hash_guard_test so evidence is
REM      kept and expected ERROR lines stay out of the main logs.
REM
REM  Usage: test_hash_guard.cmd
REM ============================================================

set SAS_PATH=C:\Master_Renamed_same_format_accross\sas
set DOCS_PATH=C:\Master_Renamed_same_format_accross\docs
set BASELINE=%DOCS_PATH%\raw_hash_baseline.csv
set BASELINE_BAK=%DOCS_PATH%\raw_hash_baseline.csv.testbak
set LOGS_PATH=P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs
set TEST_LOGS=%LOGS_PATH%\hash_guard_test
set LOG_19B=%TEST_LOGS%\19b_seed_hash_baseline.log

REM Anchored patterns: %put output starts in column 1; echoed source
REM lines start with a line number, so they can never match /b.
set PAT_PASS=NOTE: HARD-01 hash guard passed
set PAT_FAIL=ERROR: HARD-01 HASH GUARD FAILED
set ZEROS=0000000000000000000000000000000000000000000000000000000000000000

REM ---- Machine-specific SAS_EXE override (mirrors run_pipeline.cmd) ----
if exist "%~dp0config.local.cmd" call "%~dp0config.local.cmd"
if not defined SAS_EXE set "SAS_EXE=C:\Program Files\SAS94\SASFoundation\9.4\sas.exe"

if not exist "%SAS_EXE%" (
  echo ERROR: SAS_EXE not found: "%SAS_EXE%"
  exit /b 2
)
if not exist "%TEST_LOGS%" mkdir "%TEST_LOGS%"

echo.
echo ============================================================
echo  HARD-01 / HARD-02 Hash Guard Verification
echo  Step logs: %TEST_LOGS%
echo ============================================================

REM ============================================================
REM  STEP 1: Run program 19 to refresh qc/19_raw_files.csv
REM ============================================================
echo.
echo [STEP 1] Running program 19 to refresh qc/19_raw_files.csv ...
set LOG_19=%TEST_LOGS%\19_step1.log
start "" /wait "%SAS_EXE%" ^
    -sysin "%SAS_PATH%\19_raw_dir_inventory.sas" ^
    -log  "!LOG_19!" ^
    -nosplash -icon -sasuser WORK ^
    -set RUN_ALL 1

set _EC=!ERRORLEVEL!
echo Step 1 exit code: !_EC!
findstr /b /c:"NOTE: qc/19_raw_files.csv written" "!LOG_19!" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo FAIL [STEP 1]: qc/19_raw_files.csv was not refreshed. Check: !LOG_19!
  exit /b 2
)
echo Step 1 OK: qc/19_raw_files.csv refreshed ^(abort at Section 13 is expected without a baseline^).

REM ============================================================
REM  STEP 2: Run 19b to seed docs/raw_hash_baseline.csv
REM ============================================================
echo.
echo [STEP 2] Running 19b to seed docs/raw_hash_baseline.csv ...

if exist "%BASELINE%" (
  echo WARNING: %BASELINE% already exists.
  echo          19b will abort without overwriting -- this is by design ^(D-09^).
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
  echo ERROR: %BASELINE% has only !_ROWS! line^(s^) -- expected 9 ^(header + 8 md rows^).
  exit /b 2
)
echo Step 2 OK: baseline seeded with !_ROWS! line^(s^) ^(header + data^).

:step3
REM ============================================================
REM  STEP 3: Run program 19 -- expect HARD-01 hash guard PASSED
REM ============================================================
echo.
echo [STEP 3] Running program 19 -- expecting hash guard PASSED ...
set LOG_19=%TEST_LOGS%\19_step3.log
start "" /wait "%SAS_EXE%" ^
    -sysin "%SAS_PATH%\19_raw_dir_inventory.sas" ^
    -log  "!LOG_19!" ^
    -nosplash -icon -sasuser WORK ^
    -set RUN_ALL 1

set _EC=!ERRORLEVEL!
findstr /b /c:"%PAT_PASS%" "!LOG_19!" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo FAIL [STEP 3]: "%PAT_PASS%" not found in log.
  echo               SAS exit code: !_EC!. Check: !LOG_19!
  exit /b 2
)
findstr /b /c:"ERROR" "!LOG_19!" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
  echo FAIL [STEP 3]: ERROR line^(s^) found in log despite guard passing.
  echo               Check: !LOG_19!
  exit /b 2
)
echo PASS [STEP 3]: Hash guard passed, 0 ERROR lines in log.

REM ============================================================
REM  STEP 4: Back up baseline, then corrupt one sha256
REM ============================================================
echo.
echo [STEP 4] Backing up baseline and tampering first data row ...

copy /y "%BASELINE%" "%BASELINE_BAK%" >nul
if !ERRORLEVEL! NEQ 0 (
  echo ERROR: could not back up %BASELINE% -- tamper step not attempted.
  exit /b 2
)

powershell -NoProfile -Command ^
  "$f = Get-Content '%BASELINE%'; " ^
  "$header = $f[0]; " ^
  "$first = $f[1] -replace ',[0-9a-fA-F]{64},', (',' + '0'*64 + ','); " ^
  "$rest = $f[2..($f.Length-1)]; " ^
  "($header, $first) + $rest | Set-Content '%BASELINE%' -Encoding ASCII"

if !ERRORLEVEL! NEQ 0 (
  echo ERROR: PowerShell tamper step failed.
  goto :fail_restore
)
findstr /c:"%ZEROS%" "%BASELINE%" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo ERROR: tamper did not change the baseline -- sha256 pattern not matched in row 1.
  goto :fail_restore
)
echo Step 4: Baseline tampered ^(first data row sha256 set to 64 zeroes^).

REM ============================================================
REM  STEP 5: Run program 19 -- expect HARD-01 HASH GUARD FAILED
REM ============================================================
echo.
echo [STEP 5] Running program 19 -- expecting hash guard FAILED ...
set LOG_19=%TEST_LOGS%\19_step5.log
start "" /wait "%SAS_EXE%" ^
    -sysin "%SAS_PATH%\19_raw_dir_inventory.sas" ^
    -log  "!LOG_19!" ^
    -nosplash -icon -sasuser WORK ^
    -set RUN_ALL 1

set _EC=!ERRORLEVEL!
findstr /b /c:"%PAT_FAIL%" "!LOG_19!" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo FAIL [STEP 5]: Expected "%PAT_FAIL%" in log but did not find it.
  echo               SAS exit code: !_EC!. Check: !LOG_19!
  goto :fail_restore
)
findstr /b /c:"%PAT_PASS%" "!LOG_19!" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
  echo FAIL [STEP 5]: guard reported PASSED on a tampered baseline.
  echo               Check: !LOG_19!
  goto :fail_restore
)
echo PASS [STEP 5]: Hash guard fired correctly on tampered baseline ^(exit code !_EC!^).

REM ============================================================
REM  STEP 6: Restore baseline from the step-4 backup
REM ============================================================
echo.
echo [STEP 6] Restoring baseline from backup ...
copy /y "%BASELINE_BAK%" "%BASELINE%" >nul
if !ERRORLEVEL! NEQ 0 (
  echo ERROR: restore failed. Backup kept at %BASELINE_BAK%
  exit /b 2
)
fc /b "%BASELINE_BAK%" "%BASELINE%" >nul
if !ERRORLEVEL! NEQ 0 (
  echo ERROR: restored baseline differs from backup. Backup kept at %BASELINE_BAK%
  exit /b 2
)
echo Step 6: Baseline restored and byte-identical to backup.

REM ============================================================
REM  STEP 7: Run program 19 -- expect HARD-01 hash guard PASSED
REM ============================================================
echo.
echo [STEP 7] Running program 19 -- expecting hash guard PASSED after restore ...
set LOG_19=%TEST_LOGS%\19_step7.log
start "" /wait "%SAS_EXE%" ^
    -sysin "%SAS_PATH%\19_raw_dir_inventory.sas" ^
    -log  "!LOG_19!" ^
    -nosplash -icon -sasuser WORK ^
    -set RUN_ALL 1

set _EC=!ERRORLEVEL!
findstr /b /c:"%PAT_PASS%" "!LOG_19!" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo FAIL [STEP 7]: "%PAT_PASS%" not found in log after restore.
  echo               SAS exit code: !_EC!. Check: !LOG_19!
  exit /b 2
)
findstr /b /c:"ERROR" "!LOG_19!" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
  echo FAIL [STEP 7]: ERROR line^(s^) found in log after restore.
  echo               Check: !LOG_19!
  exit /b 2
)
del "%BASELINE_BAK%" >nul 2>&1
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

REM ============================================================
REM  Failure after tamper: put the good baseline back first
REM ============================================================
:fail_restore
if exist "%BASELINE_BAK%" (
  copy /y "%BASELINE_BAK%" "%BASELINE%" >nul
  echo Baseline restored from %BASELINE_BAK% after failure.
)
exit /b 2
