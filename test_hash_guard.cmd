@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM  test_hash_guard.cmd -- HARD-01 + HARD-02 verification
REM
REM  HARD-01 = program 19 SECTION 13: &raw_path.\master originals
REM            baseline docs\raw_hash_baseline.csv   (seeded by 19b)
REM  HARD-02 = program 19 SECTION 14: &source_path renamed masters
REM            baseline docs\source_hash_baseline.csv (seeded by 19c)
REM
REM  Steps:
REM    1. Run program 19 to refresh qc/19_raw_files.csv
REM    2. Seed raw baseline via 19b if it has < 8 data rows
REM       (a header-only git stub is removed first -- 19b refuses
REM       to overwrite any existing file)
REM    3. Seed source baseline via 19c if it has < 8 data rows
REM       (19c seeds over a header-only stub itself)
REM    4. Run 19 -- expect BOTH guards passed, 0 ERROR lines
REM    5. HARD-01 cycle: tamper raw baseline -> expect HARD-01 FAILED
REM       -> restore -> expect both passed
REM    6. HARD-02 cycle: tamper source baseline -> expect HARD-01
REM       passed AND HARD-02 FAILED -> restore -> expect both passed
REM
REM  Revised 2026-09-30:
REM    - Adds 19c seeding and the SECTION 14 (HARD-02) tamper cycle.
REM    - Seeding decided by line count, not file existence (stub trap).
REM    - Tamper/restore factored into :tamper_cycle; any failure after
REM      a tamper restores that baseline before exiting.
REM  Kept from 2026-09-29: /b-anchored findstr, local backup restore,
REM    ASCII tamper, one log per step in logs\hash_guard_test.
REM
REM  Usage: test_hash_guard.cmd
REM ============================================================

set SAS_PATH=C:\Master_Renamed_same_format_accross\sas
set DOCS_PATH=C:\Master_Renamed_same_format_accross\docs
set RAW_BASE=%DOCS_PATH%\raw_hash_baseline.csv
set SRC_BASE=%DOCS_PATH%\source_hash_baseline.csv
set LOGS_PATH=P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs
set TEST_LOGS=%LOGS_PATH%\hash_guard_test
set PROG19=%SAS_PATH%\19_raw_dir_inventory.sas

REM Anchored patterns: %put output starts in column 1; echoed source
REM lines start with a line number, so they can never match /b.
set PAT_PASS1=NOTE: HARD-01 hash guard passed
set PAT_FAIL1=ERROR: HARD-01 HASH GUARD FAILED
set PAT_PASS2=NOTE: HARD-02 source hash guard passed
set PAT_FAIL2=ERROR: HARD-02 SOURCE HASH GUARD FAILED
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
set LOG=%TEST_LOGS%\19_step1.log
call :run_sas "%PROG19%" "!LOG!"
echo Step 1 exit code: !_EC!
findstr /b /c:"NOTE: qc/19_raw_files.csv written" "!LOG!" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo FAIL [STEP 1]: qc/19_raw_files.csv was not refreshed. Check: !LOG!
  exit /b 2
)
echo Step 1 OK: qc/19_raw_files.csv refreshed ^(a guard abort here is expected if a baseline is unseeded^).

REM ============================================================
REM  STEP 2: Seed raw baseline via 19b if needed
REM ============================================================
echo.
echo [STEP 2] Checking %RAW_BASE% ...
call :count_lines "%RAW_BASE%"
if !_ROWS! GEQ 9 (
  echo Step 2 OK: raw baseline already seeded ^(!_ROWS! lines^) -- 19b skipped.
  goto :step3
)
if exist "%RAW_BASE%" (
  echo Step 2: raw baseline has only !_ROWS! line^(s^) -- treating as header-only stub.
  echo         Removing it so 19b can seed. Recover with: git checkout -- docs/raw_hash_baseline.csv
  del "%RAW_BASE%"
)
set LOG=%TEST_LOGS%\19b_seed_hash_baseline.log
call :run_sas "%SAS_PATH%\19b_seed_hash_baseline.sas" "!LOG!"
call :count_lines "%RAW_BASE%"
if !_ROWS! LSS 9 (
  echo FAIL [STEP 2]: raw baseline has !_ROWS! line^(s^) after 19b -- expected 9. Check: !LOG!
  exit /b 2
)
echo Step 2 OK: raw baseline seeded ^(!_ROWS! lines^).

:step3
REM ============================================================
REM  STEP 3: Seed source baseline via 19c if needed
REM ============================================================
echo.
echo [STEP 3] Checking %SRC_BASE% ...
call :count_lines "%SRC_BASE%"
if !_ROWS! GEQ 9 (
  echo Step 3 OK: source baseline already seeded ^(!_ROWS! lines^) -- 19c skipped.
  goto :step4
)
set LOG=%TEST_LOGS%\19c_seed_source_hash_baseline.log
call :run_sas "%SAS_PATH%\19c_seed_source_hash_baseline.sas" "!LOG!"
findstr /b /c:"NOTE: [19c] SEED COMPLETE" "!LOG!" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo FAIL [STEP 3]: 19c did not report SEED COMPLETE. Check: !LOG!
  echo                Common cause: a master_data_N.xlsx open in Excel ^(OPEN_FAILED^).
  exit /b 2
)
call :count_lines "%SRC_BASE%"
if !_ROWS! LSS 9 (
  echo FAIL [STEP 3]: source baseline has !_ROWS! line^(s^) -- expected 9.
  exit /b 2
)
echo Step 3 OK: source baseline seeded ^(!_ROWS! lines^).

:step4
REM ============================================================
REM  STEP 4: Run 19 -- expect both guards PASSED, 0 ERROR lines
REM ============================================================
echo.
echo [STEP 4] Running program 19 -- expecting HARD-01 and HARD-02 PASSED ...
set LOG=%TEST_LOGS%\19_step4.log
call :run_sas "%PROG19%" "!LOG!"
call :expect_clean "!LOG!" "STEP 4"
if !ERRORLEVEL! NEQ 0 exit /b 2
echo PASS [STEP 4]: both guards passed, 0 ERROR lines.

REM ============================================================
REM  STEP 5: HARD-01 tamper cycle (raw baseline)
REM ============================================================
call :tamper_cycle "%RAW_BASE%" "%PAT_FAIL1%" "%PAT_PASS1%" "5" "HARD-01" ""
if !ERRORLEVEL! NEQ 0 exit /b 2

REM ============================================================
REM  STEP 6: HARD-02 tamper cycle (source baseline)
REM  SECTION 13 must pass first, or SECTION 14 never runs.
REM ============================================================
call :tamper_cycle "%SRC_BASE%" "%PAT_FAIL2%" "%PAT_PASS2%" "6" "HARD-02" "%PAT_PASS1%"
if !ERRORLEVEL! NEQ 0 exit /b 2

echo.
echo ============================================================
echo  ALL STEPS PASSED -- HARD-01 and HARD-02 guards verified
echo  ^(seed, pass, tamper-fail, restore-pass for each^).
echo  If either baseline was seeded by this run, commit it:
echo    git add docs/raw_hash_baseline.csv docs/source_hash_baseline.csv
echo ============================================================
echo.
exit /b 0


REM ============================================================
REM  SUBROUTINES
REM ============================================================

REM ---- :run_sas <sysin> <log>  -> sets _EC ----
:run_sas
start "" /wait "%SAS_EXE%" ^
    -sysin "%~1" ^
    -log  "%~2" ^
    -nosplash -icon -sasuser WORK ^
    -set RUN_ALL 1
set _EC=!ERRORLEVEL!
exit /b 0

REM ---- :count_lines <file>  -> sets _ROWS (0 if missing) ----
:count_lines
set _ROWS=0
if not exist "%~1" exit /b 0
for /f %%R in ('find /c /v "" "%~1" 2^>nul') do set _ROWS=%%R
exit /b 0

REM ---- :expect_clean <log> <label>  -> both PASS lines, no ERROR ----
:expect_clean
findstr /b /c:"%PAT_PASS1%" "%~1" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo FAIL [%~2]: "%PAT_PASS1%" not found. SAS exit code: !_EC!. Check: %~1
  exit /b 1
)
findstr /b /c:"%PAT_PASS2%" "%~1" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo FAIL [%~2]: "%PAT_PASS2%" not found. SAS exit code: !_EC!. Check: %~1
  exit /b 1
)
findstr /b /c:"ERROR" "%~1" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
  echo FAIL [%~2]: ERROR line^(s^) found in log despite both guards passing. Check: %~1
  exit /b 1
)
exit /b 0

REM ---- :tamper_cycle <baseline> <fail_pat> <own_pass_pat> <step> <label> <required_other_pass_pat or ""> ----
:tamper_cycle
set _TB=%~1
set _TBAK=%~1.testbak
echo.
echo [STEP %~4a] %~5: backing up and tampering first data row of %~nx1 ...
copy /y "!_TB!" "!_TBAK!" >nul
if !ERRORLEVEL! NEQ 0 (
  echo ERROR: could not back up !_TB! -- tamper not attempted.
  exit /b 1
)
powershell -NoProfile -Command ^
  "$f = Get-Content '!_TB!'; " ^
  "$header = $f[0]; " ^
  "$first = $f[1] -replace ',[0-9a-fA-F]{64},', (',' + '0'*64 + ','); " ^
  "$rest = $f[2..($f.Length-1)]; " ^
  "($header, $first) + $rest | Set-Content '!_TB!' -Encoding ASCII"
if !ERRORLEVEL! NEQ 0 (
  echo ERROR: PowerShell tamper step failed.
  goto :tc_fail
)
findstr /c:"%ZEROS%" "!_TB!" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo ERROR: tamper did not change the baseline -- sha256 pattern not matched in row 1.
  goto :tc_fail
)

echo [STEP %~4b] %~5: running program 19 -- expecting guard FAILED ...
set LOG=%TEST_LOGS%\19_step%~4b_%~5_tampered.log
call :run_sas "%PROG19%" "!LOG!"
findstr /b /c:"%~2" "!LOG!" >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  echo FAIL [STEP %~4b]: expected "%~2" but did not find it. SAS exit code: !_EC!. Check: !LOG!
  goto :tc_fail
)
findstr /b /c:"%~3" "!LOG!" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
  echo FAIL [STEP %~4b]: %~5 guard reported PASSED on a tampered baseline. Check: !LOG!
  goto :tc_fail
)
if not "%~6"=="" (
  findstr /b /c:"%~6" "!LOG!" >nul 2>&1
  if !ERRORLEVEL! NEQ 0 (
    echo FAIL [STEP %~4b]: "%~6" missing -- run did not get past the earlier guard. Check: !LOG!
    goto :tc_fail
  )
)
echo PASS [STEP %~4b]: %~5 guard fired on tampered baseline ^(exit code !_EC!^).

echo [STEP %~4c] %~5: restoring baseline ...
copy /y "!_TBAK!" "!_TB!" >nul
fc /b "!_TBAK!" "!_TB!" >nul
if !ERRORLEVEL! NEQ 0 (
  echo ERROR: restored baseline differs from backup. Backup kept at !_TBAK!
  exit /b 1
)

echo [STEP %~4d] %~5: running program 19 -- expecting both guards PASSED ...
set LOG=%TEST_LOGS%\19_step%~4d_%~5_restored.log
call :run_sas "%PROG19%" "!LOG!"
call :expect_clean "!LOG!" "STEP %~4d"
if !ERRORLEVEL! NEQ 0 exit /b 1
del "!_TBAK!" >nul 2>&1
echo PASS [STEP %~4d]: %~5 restored -- both guards passed, 0 ERROR lines.
exit /b 0

:tc_fail
if exist "!_TBAK!" (
  copy /y "!_TBAK!" "!_TB!" >nul
  echo Baseline restored from !_TBAK! after failure.
)
exit /b 1
