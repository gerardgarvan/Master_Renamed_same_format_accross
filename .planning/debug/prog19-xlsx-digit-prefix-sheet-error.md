---
status: awaiting_human_verify
trigger: "sas/19_raw_dir_inventory.sas logs ERROR lines when reading XLSX sheets whose SAS memnames start with a digit, causing scan_pipeline_logs.ps1 to report Status: FAIL"
created: 2026-09-29T00:00:00
updated: 2026-09-29T00:00:00
---

## Current Focus

hypothesis: digit-prefix sheet names in XLSX files trigger ERROR from DATA step set _xlw."MEMNAME"n before the %syserr check can suppress them
test: replace %else %do block with %sysfunc(open()) pre-check to avoid DATA step ERROR entirely
expecting: no ERROR lines in log; n_fail incremented silently via NOTE
next_action: apply fix to lines 332-336 of sas/19_raw_dir_inventory.sas

## Symptoms

expected: scan_pipeline_logs.ps1 reports Status: PASS (or program 19 sheet-read failures are silent NOTEs, not ERRORs)
actual: Status: FAIL with two ERROR pairs in 19_raw_dir_inventory.log -- ERROR: Couldn't find range or sheet in spreadsheet; ERROR: File _XLW.'2018_2019_PRECEDE_DATABASE'.DATA does not exist; and same pair for 2020_PRECEDE_DATABASE_EDU
errors: ERROR: Couldn't find range or sheet in spreadsheet / ERROR: File _XLW.'2018_2019_PRECEDE_DATABASE'.DATA does not exist (pages 27 and 53 of log)
reproduction: run run_pipeline.cmd; run scan_pipeline_logs.ps1
started: pre-existing before Phase 25; not caused by recent changes

## Eliminated

- hypothesis: error comes from after the %syserr check
  evidence: %syserr check is AFTER the DATA step -- the ERROR is logged before %syserr is even evaluated; the guard cannot suppress it retroactively
  timestamp: 2026-09-29

## Evidence

- timestamp: 2026-09-29
  checked: sas/19_raw_dir_inventory.sas lines 327-344
  found: %else %do block (lines 332-336) executes DATA step unconditionally for digit-prefix names; %syserr > 4 cleanup on line 337 runs after ERROR is already in the log
  implication: must pre-check accessibility before the DATA step using %sysfunc(open()) which fails silently

## Resolution

root_cause: The %else branch for digit-prefix XLSX sheet names executes a DATA step with a name literal ("SHEETNAME"n) unconditionally. The XLSX engine case-sensitivity mismatch causes the DATA step to log ERROR before %syserr can catch it. The existing %syserr > 4 guard removes the partial dataset but cannot erase the ERROR already written to the log.
fix: Replace %else %do block body with %sysfunc(open()) pre-check. If open returns 0, log NOTE and increment n_fail without a DATA step. If open succeeds, close the handle and run the DATA step with existing %syserr cleanup intact.
verification: structural code review -- grep for ^ERROR in log after next pipeline run should return 0 matches for program 19
files_changed: [sas/19_raw_dir_inventory.sas]
