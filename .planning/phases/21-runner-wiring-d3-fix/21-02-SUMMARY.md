---
phase: 21-runner-wiring-d3-fix
plan: "02"
subsystem: pipeline-runner
tags: [runner, batch, cmd, config, in-pipeline]
dependency_graph:
  requires: [21-01]
  provides: [run_pipeline.cmd, in_pipeline-env-detection]
  affects: [sas/00_config.sas, sas/99_run_all.sas]
tech_stack:
  added: []
  patterns: [start-wait-sas-exe, envlen-RUN_ALL, DelayedExpansion-ERRORLEVEL]
key_files:
  created:
    - run_pipeline.cmd
  modified:
    - sas/00_config.sas
    - sas/99_run_all.sas
decisions:
  - RUN-01 satisfied pending human end-to-end verification (stop-path test + PASSED run)
metrics:
  duration: ~15 min
  completed_date: "2026-09-24"
  tasks_completed: 3
  tasks_total: 4
  files_created: 1
  files_modified: 2
---

# Phase 21 Plan 02: Runner Wiring Summary

**One-liner:** run_pipeline.cmd wires all 14 pipeline programs as separate sas.exe sessions with exit-code gating and RUN_ALL env-var detection in 00_config.sas.

---

## Tasks Completed

### Task 1 -- Extend %_set_pipeline_default in 00_config.sas (commit 3309bc9)

Extended the macro with an `envlen(RUN_ALL)` check. When `run_pipeline.cmd` launches SAS with `-set RUN_ALL 1`, the OS env var is present and `envlen` returns > 0, triggering `%sysget(RUN_ALL) = 1` and setting `in_pipeline = 1`. The `%symexist` guard is preserved for backward compatibility. A `%put NOTE: [00_config] in_pipeline = &in_pipeline;` line was added so every per-program log confirms the flag value.

### Task 2 -- Create run_pipeline.cmd (commit fe5aabd)

Created `run_pipeline.cmd` at repo root. Key properties:
- `setlocal EnableDelayedExpansion` on line 2; `!ERRORLEVEL!` used throughout (never `%ERRORLEVEL%` inside subroutine)
- `:run_program` subroutine: `start "" /wait sas.exe -sysin ... -set RUN_ALL 1`; captures `!ERRORLEVEL!`; counts WARNING: lines via findstr; writes one summary line to `99_run_all.log`; exits nonzero on code >= 2
- Program order in `:main`: 01, 02, 03, 04, 05, 06, 07, 08, 19, 20, 10b, 16b, 17, 18
- Machine-configurable `SAS_EXE`, `SAS_PATH`, `LOGS_PATH` at top
- MASTER_LOG: `P:\PeCAN Master Data\Gerard\...\merge\logs\99_run_all.log`

### Task 3 -- Update 99_run_all.sas header (commit e49eff6)

Header updated to list all 14 programs (phases 1-8, 19, 20, 10b, 16b, 17, 18). Canonical batch entry point is now `run_pipeline.cmd`; single-session usage demoted to legacy / not recommended. No `%include` statements changed.

---

## Pending: Task 4 -- Human Verification (checkpoint:human-verify)

**Awaiting human sign-off on:**

A. Static review of `run_pipeline.cmd` -- program order, paths, `-set RUN_ALL 1`

B. Stop-path test:
   1. Create `sas/zz_abort_test.sas` containing: `%macro t; %abort cancel; %mend t; %t;`
   2. Copy `run_pipeline.cmd` to a scratch file; replace `:main` calls with a single `call :run_program "zz abort_test" "zz_abort_test.sas"`
   3. Run it -- expect: console shows PIPELINE STOPPED with program name and exit code >= 2
   4. Delete scratch driver and `zz_abort_test.sas`

C. Full end-to-end run:
   1. Run `run_pipeline.cmd` from a fresh cmd prompt
   2. `99_run_all.log` ends with "Pipeline PASSED"
   3. Each per-program log contains `NOTE: [00_config] in_pipeline       = 1`
   4. No PROC PRINTTO redirect to a second log file per program

Resume signal: type "approved" with the final `99_run_all.log` status line, or describe what failed.

---

## Deviations from Plan

None -- plan executed exactly as written.

---

## Self-Check: PARTIAL

Tasks 1-3 committed and verified. Task 4 (checkpoint) pending human action.

Files created/modified:
- FOUND: C:\Master_Renamed_same_format_accross\run_pipeline.cmd
- FOUND: C:\Master_Renamed_same_format_accross\sas\00_config.sas
- FOUND: C:\Master_Renamed_same_format_accross\sas\99_run_all.sas

Commits:
- FOUND: 3309bc9 (Task 1)
- FOUND: fe5aabd (Task 2)
- FOUND: e49eff6 (Task 3)
