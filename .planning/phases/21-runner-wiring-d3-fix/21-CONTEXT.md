# Phase 21: Runner Wiring & D3 Fix - Context

**Gathered:** 2026-09-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Two independent deliverables:

1. **RUN-01** -- Replace the `%include`-based `99_run_all.sas` with a `.cmd` batch driver that calls `sas.exe` separately for programs 1-8, 19, 20, 10b, 16b, 17, and 18 in that order, per PCM-C-05. The SAS file `99_run_all.sas` is retired or repurposed; the driver is a new `.cmd` file.
2. **FIX-01** -- Set `DOMAIN_MAP_APPROVED=1` in `17_summary_stats_by_domain.sas` with attribution (Gerard, 2026-09-23, PCM-D-19), enabling the D3 cognitive domain sheet in `qc/17_summary_stats_by_domain.xlsx`. No structural code changes to the DATALINES or stat_route logic are needed.

</domain>

<decisions>
## Implementation Decisions

### RUN-01: Driver Architecture

- **D-01: .cmd batch script.** Use a `.cmd` file (not PowerShell, not a SAS SYSTASK driver). Rationale: no execution-policy risk on UF-managed machines; readable by anyone; no XCMD dependency in the driver itself (XCMD is a program-level concern, not a driver concern).

- **D-02: sas.exe launch pattern.** Each program is launched with:
  ```
  start "" /wait "C:\Program Files\SASHome\SASFoundation\9.4\sas.exe" ^
      -sysin "<sas_path>\<program>.sas" ^
      -log "<logs_path>\<program>.log" ^
      -nosplash -icon -sasuser WORK ^
      -set RUN_ALL 1
  ```
  The `start "" /wait` idiom is required because `sas.exe` is a GUI application; without it, `cmd` returns immediately and `%ERRORLEVEL%` is unreliable.

- **D-03: Exit-code policy.** After each `start /wait`, read `%ERRORLEVEL%`:
  - 0 or 1 -- continue (exit code 1 = warnings only; programs 19 and 20 reset `syscc` after expected warnings, so 1 is not an error for any program)
  - 2 or above -- stop the run immediately and print the failing program name and exit code to the driver log

- **D-04: Warning visibility.** Continuing on exit code 1 can hide unexpected warnings in programs 1-8. The driver scans each log for `WARNING:` lines after the program exits and writes the count to its summary. Log scanning is summary-only -- it never stops the run; exit code decides that.

- **D-05: `in_pipeline` flag via `RUN_ALL` environment variable.** `-set RUN_ALL 1` creates an OS-level environment variable readable inside each SAS session. `00_config.sas` must be updated to check for it using `envlen` (not `%sysget` directly, which writes a WARNING when the variable is undefined). Correct pattern:
  ```sas
  %if %sysfunc(envlen(RUN_ALL)) > 0 %then %do;
    %if %sysget(RUN_ALL) = 1 %then %let in_pipeline = 1;
  %end;
  ```
  `envlen` returns -1 silently when the variable is absent. The check must set `in_pipeline = 1` unconditionally (not guard with "only if it doesn't already exist"), because `%_set_pipeline_default` today sets `in_pipeline` only when absent. This suppresses each program's internal PROC PRINTTO redirect, so the `-log` path named by the driver is the sole log for that program. The 13 existing programs need no changes.

- **D-06: Master log.** `logs/99_run_all.log` becomes the driver's summary: one line per program with timestamp, exit code, and WARNING count. This replaces the single combined SAS log that the old `%include` runner produced. The per-program logs on the P: drive are the full execution record.

- **D-07: Program order and exact file names.** The driver must enumerate file names explicitly (Phase 3 alone involves multiple prep programs). Take the exact list and order from `sas/99_run_all.sas` (the current %include-based runner). The sas.exe path varies by machine; define it as a variable at the top of the `.cmd` script. Programs 10 (`10_concept_profile.sas`) and 14 (`14_label_similarity.sas`) are human-gated prerequisites, not pipeline steps; they are NOT in the driver.

- **D-07a: `g.analysis_base` provenance -- OPEN QUESTION requiring human input before plan execution.** Program 17 reads `g.analysis_base` as its primary source. No program in the repo writes this dataset -- it is a P: drive artifact of unknown provenance. If no runner program produces it, a clean end-to-end run per RUN-01 depends on a pre-existing file the pipeline cannot rebuild. Two resolution paths:
  - **Option A (v2.0):** Identify what created `g.analysis_base` and confirm it is equivalent to `g.analytic_cohort` (what 16b now produces). If so, add an explicit step or alias before program 17.
  - **Option B (v2.1):** Update program 17 to read `g.analytic_cohort` instead of `g.analysis_base`. Scope this as a v2.1 change and document the dependency explicitly in RUN-01's acceptance criteria.
  **Gerard must decide Option A or B before the plan can finalize program 17's treatment.**

- **D-08: Human-gated programs run as-is.** Program 17 runs with whatever `DOMAIN_MAP_APPROVED` value is set in the source file. Program 18 runs with whatever `D15_APPROVED` value is set in `00_config.sas`. The driver does not inject gate values; those are set by the analyst before the run.

### FIX-01: D3 Cognitive Domain Fix

- **D-09: DOMAIN_MAP_APPROVED=1 is the entire code change (PCM-D-19).** The DATALINES rows for `COGNITIVE_SCORE` and `COGNITIVE_CATEGORY` at lines 1711-1712 of `17_summary_stats_by_domain.sas` are correct: domain=D3, assign_rule=instrument. `stat_route` is computed from `vtype`/`n_levels`, not stored in the lookup, so no structural change is needed. Sequence for this deliverable:
  1. Set the gate (`%let DOMAIN_MAP_APPROVED = 0` → 1) with a comment pointing to PCM-D-19 in DECISIONS.md; do not assert the result in the comment.
  2. Run program 17.
  3. Open the workbook and confirm the D3 sheet is present and populated.
  4. Add PCM-D-19 to `docs/DECISIONS.md` alongside D-17 and D-18, stating that it supersedes the v1 checkpoint-2 approval (which was made when D3 was absent) and recording the confirmed result.

- **D-10: No pecan_ID DATALINES row needed.** `pecan_ID` is not in `g.master_data_merged` (PCM-D-05: merged file is untouched). `g.analysis_base` predates Phase 20 and does not carry pecan_ID. Program 17's two inputs are both pecan_ID-free; Section 3b's identifier regex and GUARD 5 are not triggered. No DATALINES entry is required. (Note: if D-07a resolves to Option B and program 17 is redirected to read `g.analytic_cohort`, this decision must be revisited, since `g.analytic_cohort` does carry pecan_ID.)

- **D-11: Variable name case is not an issue.** The Section 4 join upcases both sides (`upcase(strip(ds.varname)) = dl.varname_u`), so `Cognitive_Score` from 16b matches `COGNITIVE_SCORE` in the lookup. No rename needed.

### Claude's Discretion

- Exact `.cmd` file name and location (e.g., `run_all.cmd` at repo root or `sas/99_run_all.cmd`)
- Whether the driver logs to the console as it runs (recommended: `echo` each program name before launch)
- Log-scanning implementation (findstr or a FOR /F loop over the log file)
- Whether `99_run_all.sas` is renamed, archived, or repurposed as documentation

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Pipeline constraints
- `.planning/PROJECT.md` §Constraints -- PCM-C-05 (restart SAS between programs), PCM-D-12 (exit code 3 on abort, -sasuser WORK)
- `.planning/REQUIREMENTS.md` -- RUN-01 and FIX-01 acceptance criteria
- `.planning/ROADMAP.md` §Phase 21 -- Success Criteria (two items)

### Existing programs
- `sas/99_run_all.sas` -- current %include-based runner being replaced; read for program order and log header text to reuse
- `sas/00_config.sas` -- must add %sysget(RUN_ALL) check for in_pipeline flag (D-05)
- `sas/17_summary_stats_by_domain.sas` line 145 -- DOMAIN_MAP_APPROVED gate to change; lines 1711-1712 -- existing COGNITIVE_SCORE/COGNITIVE_CATEGORY DATALINES rows (correct, no change needed)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/99_run_all.sas` header comment block -- reuse program-order documentation and log path variables for the new driver's echo lines
- `00_config.sas` `%_set_pipeline_default` (or equivalent) -- extend to check `%sysget(RUN_ALL)` rather than adding a new macro

### Established Patterns
- `start "" /wait sas.exe -sysin ... -log ... -nosplash -icon -sasuser WORK` is the correct Windows batch pattern for waiting on a GUI executable and capturing its exit code
- `-set VAR VALUE` creates an OS environment variable; `%sysget(VAR)` reads it inside SAS -- this is the only way to pass a flag across separate sas.exe sessions without modifying program source files
- Use `%sysfunc(envlen(VAR))` to test presence before calling `%sysget`; `envlen` returns -1 silently when absent, whereas `%sysget` writes a WARNING

### Integration Points
- `00_config.sas` is `%include`d as the first statement in every program -- the RUN_ALL check goes there, not in individual programs
- `logs/99_run_all.log` -- new driver summary file; path is `&logs_path.\99_run_all.log` once 00_config.sas macros are available (driver must hardcode the path or derive it from a known convention)
- `qc/17_summary_stats_by_domain.xlsx` -- regenerated by program 17 once gate is opened; D3 sheet should appear alongside D1-D5

</code_context>

<specifics>
## Specific Requirements

- `start "" /wait` is mandatory for `sas.exe` (GUI app); omitting it breaks exit-code capture
- `.cmd` over PowerShell: no execution-policy risk on UF-managed machines
- **`%ERRORLEVEL%` inside `FOR` or parenthesized `IF` blocks is unreliable** -- it is expanded once when the block is parsed, not after each program runs. Use `setlocal EnableDelayedExpansion` with `!ERRORLEVEL!`, or keep each launch and exit-code check as flat (non-nested) lines. The driver must also exit with a nonzero code on overall failure so a scheduler can detect it, and print a single PASS/FAIL summary line at the end.
- The sas.exe path must be a variable at the top of the `.cmd` script (SASHome location varies by machine)
- PCM-D-19 code comment in program 17 points to DECISIONS.md entry; it does not assert the workbook result (which is confirmed post-run, not pre-run)
- DATALINES rules (apply if any new row is ever added): no em dashes (use `--`), no commas inside the description field, ASCII only

</specifics>

<deferred>
## Deferred Ideas

- PCM-D-15 extension-column gap-fill wiring -- deferred to v2.1; depends on PID-07 result (per REQUIREMENTS.md)
- Whether 99_run_all.sas should be archived vs. repurposed -- Claude's discretion; not a user requirement

</deferred>

---

*Phase: 21-runner-wiring-d3-fix*
*Context gathered: 2026-09-23*
