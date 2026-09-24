---
phase: 22-pipeline-green-hardening
plan: "01"
subsystem: pipeline-runner
tags: [runner, hardening, log-scan, machine-portability, RUN-02, RUN-03, D-11]
dependency_graph:
  requires: []
  provides: [RUN-02, RUN-03, D-11-scan-wire]
  affects: [run_pipeline.cmd, scan_pipeline_logs.ps1, config.local.cmd.example, .gitignore]
tech_stack:
  added: [PowerShell log scanner]
  patterns: [cmd guard blocks, config.local.cmd override pattern]
key_files:
  created:
    - config.local.cmd.example
    - scan_pipeline_logs.ps1
  modified:
    - run_pipeline.cmd
    - .gitignore
decisions:
  - "RUN-02: findstr /b /c:\"WARNING\" (line-start, no colon) counts only real warning lines"
  - "RUN-03: SAS_EXE resolved via local file -> env var -> hardcoded default; goto :fail if exe missing"
  - "D-11: scan_pipeline_logs.ps1 committed at repo root, wired as last runner step"
metrics:
  duration: "~15 minutes"
  completed: "2026-09-24"
  tasks_completed: 3
  tasks_total: 3
  files_changed: 4
---

# Phase 22 Plan 01: Pipeline Runner Hardening and Log Scanner Summary

**One-liner:** Runner now counts only line-start WARNING lines via `/b` flag, resolves SAS_EXE from a machine-local config file before falling back to hardcoded default, and calls a committed PowerShell log scanner as its final step.

---

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | RUN-02 + RUN-03 edits to run_pipeline.cmd, plus scan wire | 24b853b | run_pipeline.cmd |
| 2 | config.local.cmd.example + .gitignore entry | e9e5ddc | config.local.cmd.example, .gitignore |
| 3 | scan_pipeline_logs.ps1 log scanner (D-11, D-12, D-13) | 24e9d3f | scan_pipeline_logs.ps1 |

---

## What Was Done

### Task 1: run_pipeline.cmd (RUN-02 + RUN-03 + scan wire)

Three targeted edits with no changes to SAS analytic logic:

**RUN-02 (D-15):** Changed the warning-count line in `:run_program` from `findstr /c:"WARNING:"` to `findstr /b /c:"WARNING"`. The `/b` flag restricts matches to lines that BEGIN with `WARNING`, excluding echoed SAS source lines (which start with line numbers). Dropping the trailing colon also catches numbered warnings like `WARNING 1-322:`.

**RUN-03 (D-01, D-03):** Removed the bare `set SAS_EXE=...` from the top-level section and inserted a guarded block at the top of `:main`. Precedence: local file wins, then any pre-existing env var, then hardcoded default. Uses `goto :fail` (not bare `exit /b 1`) so the failure is recorded in `99_run_all.log` by the `:fail` block.

**Scan wire (D-11):** Inserted `powershell -ExecutionPolicy Bypass -File "%~dp0scan_pipeline_logs.ps1"` immediately before the final success block. Pipeline exit code is not gated on scan result here.

### Task 2: config.local.cmd.example + .gitignore

`config.local.cmd.example` at repo root shows the SASHome path (visibly different from the committed SAS94 default) with the quoted-set pattern. The example file is tracked; the actual `config.local.cmd` is git-ignored via a new entry under `# Machine-local SAS path (RUN-03)`.

### Task 3: scan_pipeline_logs.ps1

PowerShell script at repo root implementing D-11 through D-13:

- Accepts optional `-RunStart` datetime parameter; defaults to 30 minutes before now
- Paths at the top for single-place machine configuration
- Six anchored error patterns: `^ERROR`, `^WARNING`, four `^NOTE:`-anchored patterns
- Allowlist entry: `'character data was lost during transcoding'` for the known benign ESOPH transcoding note
- Filters `*.log` files by `LastWriteTime >= $runStart`; excludes `99_run_all.log`
- Writes `Status: PASS` / `Status: FAIL` summary to `qc\22_pipeline_scan.txt` with `Out-File -Encoding ascii`
- Echoes summary to console via `Write-Host`
- Exits 1 on FAIL, 0 on PASS

---

## Verification Results

All acceptance criteria passed:

- `grep -c 'findstr /b /c:"WARNING"' run_pipeline.cmd` = 1
- `grep -c "if not defined SAS_EXE" run_pipeline.cmd` = 1
- `grep -c "SAS_EXE not found" run_pipeline.cmd` = 2 (echo + log append)
- `grep -c "scan_pipeline_logs.ps1" run_pipeline.cmd` = 1
- `grep -c "19b" run_pipeline.cmd` = 0 (no 19b reference)
- No bare top-level `set SAS_EXE=` remains
- `git check-ignore config.local.cmd` = `config.local.cmd` (ignored)
- `git check-ignore config.local.cmd.example` = empty (tracked)
- All six D-12 patterns present and anchored in scan_pipeline_logs.ps1
- Transcoding allowlist, 99_run_all.log exclusion, LastWriteTime filter, ascii encoding, exit 1 all confirmed

---

## Deviations from Plan

None -- plan executed exactly as written.

Note: The P: drive logs were not accessible from the bash shell during execution (network drive not mounted in the agent environment). The transcoding allowlist pattern `'character data was lost during transcoding'` was used as documented in D-13 without live grep confirmation from a real log. This is the pattern specified in the plan and context decisions.

---

## Known Stubs

None -- all files are wired. The scan script will produce a real PASS/FAIL result when run on a machine with P: drive access.

## Self-Check: PASSED

Files created/modified:
- run_pipeline.cmd -- FOUND (modified)
- config.local.cmd.example -- FOUND (created)
- scan_pipeline_logs.ps1 -- FOUND (created)
- .gitignore -- FOUND (modified)

Commits:
- 24b853b -- FOUND
- e9e5ddc -- FOUND
- 24e9d3f -- FOUND
