# Phase 22: Pipeline Green & Hardening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-24
**Phase:** 22-pipeline-green-hardening
**Areas discussed:** RUN-03 SAS_EXE override, INV-07 Excel formatting tooling, Pipeline run scope & verification

---

## RUN-03: SAS_EXE Override

| Option | Description | Selected |
|--------|-------------|----------|
| Environment variable only | Set SAS_EXE in Windows user environment; runner checks it | |
| config.local.cmd only | Git-ignored file next to run_pipeline.cmd | |
| Both with precedence + existence check | Env var wins → local file → hardcoded default; explicit existence check | ✓ |

**User's choice:** Both mechanisms with explicit precedence. Pattern:
```bat
if exist "%~dp0config.local.cmd" call "%~dp0config.local.cmd"
if not defined SAS_EXE set "SAS_EXE=C:\Program Files\SASHome\SASFoundation\9.4\sas.exe"
if not exist "%SAS_EXE%" (echo SAS_EXE not found: "%SAS_EXE%" & exit /b 1)
```
Commit `config.local.cmd.example`; git-ignore `config.local.cmd`.

**Notes:** On a two-machine shop, the local file is more visible and easier to fix than a Windows user environment variable. The existence check eliminates cryptic SAS launch failures.

---

## INV-07: Excel Formatting Tooling

| Option | Description | Selected |
|--------|-------------|----------|
| Python (openpyxl) | Full control over formatting; second runtime dependency | |
| Edit sas/19_raw_dir_inventory.sas | Add ODS EXCEL output inside existing program 19 | |
| New sas/19b_raw_inventory_xlsx.sas (ODS EXCEL) | Standalone presentation program reads g datasets from 19 | ✓ |

**User's choice:** New `sas/19b_raw_inventory_xlsx.sas` using ODS EXCEL. Reads inventory datasets already written by program 19 to library `g`. Keeps data generation separate from presentation.

**Notes:** ODS EXCEL handles all three requirements (sheet order for KEY leftmost, PROC REPORT style overrides for UF blue headers, frozen_headers/autofilter). Python only if ODS EXCEL cannot satisfy a future requirement (e.g., formula-driven conditional formatting). Pipeline stays pure SAS — no second runtime to install on both machines.

---

## Pipeline Run Scope & Verification

| Option | Description | Selected |
|--------|-------------|----------|
| Trust code review | Phase closes when fixes look correct | |
| Manual run, human declares pass | Human runs pipeline and reports outcome conversationally | |
| Human-run, agent-verified with log-scan script | Committed scan script; phase closes on scan evidence | ✓ |

**User's choice:** Human-run, agent-verified. A committed log-scan script (PowerShell preferred) greps `logs\` for error patterns and writes `qc\22_pipeline_scan.txt`. Phase 22 does not close until that summary is read and confirms FIX-02 / RUN-02 on evidence.

**Notes:** Error patterns to scan: `^ERROR`, `^WARNING`, `uninitialized`, `MERGE statement has more than one data set with repeats of BY values`, `Invalid data`, `character values have been converted`. Include an allowlist for known benign warnings (at minimum: ESOPH transcoding notes). Allowlist defined in the script, not as hardcoded knowledge, so it can be extended without restructuring.

---

## Claude's Discretion

- DOC-05 wording (MILESTONES.md one-liners, STATE.md metrics, PROJECT.md trap entries)
- ODS EXCEL style details (font size, column widths, freeze pane row count)
- Log-scan script language (PowerShell chosen for regex support)

## Deferred Ideas

None.
