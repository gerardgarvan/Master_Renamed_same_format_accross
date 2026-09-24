@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM  run_pipeline.cmd -- PeCAN Master Dataset Integration
REM  Full pipeline batch driver. Calls sas.exe separately for
REM  each program per PCM-C-05 (restart SAS between programs).
REM
REM  Program order:
REM    01 verify_sources   02 ownership        03 prep_all
REM    04 merge            05 qc_merge         06 reconcile
REM    07 cohort           08 dictionary
REM    19 raw_dir_inventory  20 pecan_id
REM    10b concept_harmonize  16b cohort_rebuild
REM    17 summary_stats_by_domain  18 supplemental_raw_gap
REM
REM  Exit codes: 0/1 = continue (1 = warnings only)
REM              2+  = STOP (abort detected in program)
REM
REM  Usage: run_pipeline.cmd
REM  Log:   see LOGS_PATH\99_run_all.log for per-program summary
REM ============================================================

REM ---- Machine-specific paths (edit if SASHome location differs) ----
set SAS_EXE=C:\Program Files\SAS94\SASFoundation\9.4\sas.exe
set SAS_PATH=C:\Master_Renamed_same_format_accross\sas
set LOGS_PATH=P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs
set MASTER_LOG=%LOGS_PATH%\99_run_all.log

REM ---- Initialise master log ----
echo Pipeline started: %DATE% %TIME% > "%MASTER_LOG%"
echo ============================================================ >> "%MASTER_LOG%"

REM ---- Internal macro: run one SAS program ----
REM    Usage: call :run_program <label> <sas_file_basename>
REM    Writes one summary line to MASTER_LOG; stops driver on exit code >= 2.
goto :main

:run_program
  set _LABEL=%~1
  set _PROG=%~2
  set _SAS_FILE=%SAS_PATH%\%_PROG%
  set _LOG_FILE=%LOGS_PATH%\%_PROG:.sas=%.log

  echo Running %_LABEL% ...
  start "" /wait "%SAS_EXE%" ^
      -sysin "%_SAS_FILE%" ^
      -log "%_LOG_FILE%" ^
      -nosplash -icon -sasuser WORK ^
      -set RUN_ALL 1

  set _EC=!ERRORLEVEL!

  REM Count WARNING: lines in the program log (summary only -- does not stop run)
  set _WARNS=0
  for /f %%W in ('findstr /c:"WARNING:" "%_LOG_FILE%" 2^>nul ^| find /c /v ""') do set _WARNS=%%W

  echo %DATE% %TIME%  [%_LABEL%]  exit=%_EC%  warnings=%_WARNS% >> "%MASTER_LOG%"

  if !_EC! GEQ 2 (
    echo.
    echo PIPELINE STOPPED: %_LABEL% exited with code !_EC!
    echo See log: %_LOG_FILE%
    echo PIPELINE STOPPED: %_LABEL% exit=!_EC! >> "%MASTER_LOG%"
    exit /b !_EC!
  )
  exit /b 0

:main

REM ---- Programs 1-8: core pipeline ----
call :run_program "01 verify_sources"   "01_verify_sources.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

call :run_program "02 ownership"        "02_ownership.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

call :run_program "03 prep_all"         "03_prep_all.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

call :run_program "04 merge"            "04_merge.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

call :run_program "05 qc_merge"         "05_qc_merge.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

call :run_program "06 reconcile"        "06_reconcile.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

call :run_program "07 cohort"           "07_cohort.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

call :run_program "08 dictionary"       "08_dictionary.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

REM ---- Programs 19-20: v2.0 additions (raw inventory + pecan_ID) ----
call :run_program "19 raw_dir_inventory" "19_raw_dir_inventory.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

call :run_program "20 pecan_id"         "20_pecan_id.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

REM ---- Programs 10b, 16b: concept harmonize + cohort rebuild ----
call :run_program "10b concept_harmonize" "10b_concept_harmonize.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

call :run_program "16b cohort_rebuild"  "16b_cohort_rebuild.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

REM ---- Program 17: domain summary stats (DOMAIN_MAP_APPROVED gate must be 1) ----
call :run_program "17 summary_stats"    "17_summary_stats_by_domain.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

REM ---- Program 18: supplemental raw gap (D15_APPROVED gate must be 1) ----
call :run_program "18 supplemental_raw" "18_supplemental_raw_gap.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

REM ---- All programs complete ----
echo ============================================================ >> "%MASTER_LOG%"
echo Pipeline PASSED: %DATE% %TIME% >> "%MASTER_LOG%"
echo.
echo PIPELINE PASSED -- all programs completed successfully.
echo Summary log: %MASTER_LOG%
exit /b 0

:fail
echo ============================================================ >> "%MASTER_LOG%"
echo Pipeline FAILED: %DATE% %TIME% >> "%MASTER_LOG%"
echo.
echo PIPELINE FAILED -- see master log: %MASTER_LOG%
exit /b 1
