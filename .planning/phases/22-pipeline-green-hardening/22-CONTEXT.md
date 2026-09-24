# Phase 22: Pipeline Green & Hardening - Context

**Gathered:** 2026-09-24
**Status:** Ready for planning
**Revised:** 2026-09-24 (checker feedback — D-03 precedence corrected; D-06/D-09 reversed: reorder program 19 instead of creating 19b; D-15 colon dropped)

<domain>
## Phase Boundary

Harden the existing pipeline before any new programs are added. The 2026-09-24 run stopped
at 16b; every v2.1 program (23, 24, 25) runs downstream of 16b. This phase delivers:
- Confirmed clean end-to-end run (evidence-gated, not just "code looks right")
- Warning count in runner fixed to count only log lines that begin with `WARNING`
- `SAS_EXE` overridable without editing the committed file
- `qc/19_raw_inventory.xlsx` formatted with UF colors, KEY sheet leftmost, FAMILIES sheet second
- Documentation drift closed (MILESTONES.md, STATE.md, PROJECT.md trap list)

No new analytic capability is added in this phase.

</domain>

<decisions>
## Implementation Decisions

### RUN-03: SAS_EXE Override (machine portability)

- **D-01:** Use both config.local.cmd and environment variable, with explicit precedence in `run_pipeline.cmd`:
  ```bat
  if exist "%~dp0config.local.cmd" call "%~dp0config.local.cmd"
  if not defined SAS_EXE set "SAS_EXE=C:\Program Files\SAS94\SASFoundation\9.4\sas.exe"
  if not exist "%SAS_EXE%" (
    echo SAS_EXE not found: "%SAS_EXE%"
    echo SAS_EXE not found: "%SAS_EXE%" >> "%MASTER_LOG%"
    goto :fail
  )
  ```
  The existence guard uses the multi-line `if not exist (...)` form and `goto :fail` (NOT a single-line `^&` form and NOT a bare `exit /b 1`). The `^&` single-line form does not work — cmd echoes the literal text and keeps going. `goto :fail` routes through the `:fail` block so the missing-exe failure is recorded in `99_run_all.log`.
- **D-02:** Commit `config.local.cmd.example` (showing the one-line `set SAS_EXE=...` pattern) and add `config.local.cmd` to `.gitignore`.
- **D-03:** Precedence order: **local file wins → environment variable → hardcoded default.** A stale or invisible environment variable should not silently override the visible file next to the runner. The code runs `call config.local.cmd` first (so a present local file wins), then `if not defined SAS_EXE` supplies the default only when neither the file nor a pre-existing env var set it. The existence check gives a clear message instead of a cryptic launch failure. *(Revised from the original "environment variable wins" — the D-04 visibility rationale already supports file-wins.)*
- **D-04:** Rationale for local file over pure env var: on a two-machine shop, a visible file next to `run_pipeline.cmd` is easier to locate and fix than a Windows user environment variable.

### INV-07: Excel Formatting Tooling

- **D-05:** Stay in SAS. No Python dependency — the pipeline is SAS end to end and runs from `run_pipeline.cmd`. Adding Python means a second runtime to install and version on both machines just for cosmetics.
- **D-06:** **Edit program 19 SECTION 13 in place — move the FAMILIES sheet to second position (immediately after KEY). Do NOT create a standalone 19b program.** *(Reversed.)* The original D-06 rested on a wrong premise: it assumed program 19 promotes inventory datasets to library `g`. Research (reading `sas/19_raw_dir_inventory.sas`) found it does NOT — 19 writes only WORK datasets and four CSV exports (`19_raw_files.csv`, `19_raw_key_columns.csv`, `19_raw_sheets.csv`, `19_raw_variables_md3.csv`). A 19b built on the CSV route would (a) rebuild VARIABLES/FAMILIES from an md3-only subset (wrong data — no full-variables or families CSV exists), and (b) duplicate the family-assignment and RECONCILIATION status logic in a second program (guaranteed to drift). Meanwhile program 19 SECTION 13 already uses `styles.uf_inventory` (#0021A5 headers), `frozen_headers='on'`, `autofilter='all'`, and writes KEY first. The only INV-07 gap is that FAMILIES is written last. Fixing it is a one-block reorder inside SECTION 13.
- **D-07:** Use `ODS EXCEL` for all three formatting requirements (already present in program 19 SECTION 13):
  - Sheet order: KEY leftmost, then FAMILIES second, then the data sheets (FILES, SHEETS, VARIABLES, KEY_COLUMNS, RECONCILIATION).
  - UF blue headers (#0021A5, white text): `styles.uf_inventory` proc template.
  - Usability: `frozen_headers='on'` and `autofilter='all'` options.
- **D-08:** Fall back to openpyxl only if a requirement surfaces that ODS EXCEL cannot satisfy (e.g., formula-driven conditional formatting). This phase does not need it.
- **D-09:** **No 19b wire.** *(Reversed with D-06.)* Because INV-07 is delivered by editing program 19 SECTION 13, there is no new program to insert into `run_pipeline.cmd`. The runner's existing `19 raw_dir_inventory` call already produces the formatted workbook. The scan step (`scan_pipeline_logs.ps1`) is wired in as the runner's last step instead.

### Pipeline Run Scope & Verification

- **D-10:** The "exits clean" criterion requires a real `run_pipeline.cmd` run on the machine with P: drive access. This is a **human-run, agent-verified** checkpoint — Claude Code cannot execute against P: drive.
- **D-11:** Plan includes a committed log-scan step: a PowerShell script that greps `logs\` for known error patterns and writes a pass/fail summary to `qc\22_pipeline_scan.txt` (exit 1 on FAIL). The scan script (`scan_pipeline_logs.ps1`, repo root) is committed and rerunnable; the runner calls it as its last step.
- **D-12:** Error patterns to scan (NOTE-/line-anchored so echoed source code does not match):
  - `^ERROR`
  - `^WARNING` (after RUN-02 fix, this is the canonical warning line start)
  - `^NOTE: Variable .+ is uninitialized`
  - `^NOTE: MERGE statement has more than one data set with repeats of BY values`
  - `^NOTE: Invalid (data|argument)`
  - `^NOTE: .*values have been converted`
- **D-13:** Include an allowlist for known benign warnings so the scan does not fail on every run. At minimum: the benign transcoding note, matched by `character data was lost during transcoding` (the ESOPH transcoding warning surfaces this text — the word ESOPH is in the data, not on the log line). Allowlist is defined in the scan script as patterns, not hardcoded knowledge.
- **D-14:** Phase 22 is only marked complete after the scan summary is read and FIX-02 / RUN-02 are confirmed on that evidence. Phase does not close on "code looks right" alone.

### RUN-02: Warning Count Fix

- **D-15:** Change `findstr /c:"WARNING:"` to `findstr /b /c:"WARNING"` (line-start match, **no trailing colon**) in the `:run_program` subroutine of `run_pipeline.cmd`. `/b` ensures only lines that BEGIN with `WARNING` are counted (echoed SAS source lines start with line numbers, so they are excluded); dropping the colon also catches numbered warnings like `WARNING 1-322: ...`. Do not use the `/r` regex form.
- **D-16:** After the fix, 10b should report 0 warnings. Confirm from the log-scan summary.

### Claude's Discretion

- Exact wording of the MILESTONES.md one-liners, STATE.md metric values, and PROJECT.md trap entries (DOC-05) — Claude writes these from the existing QC outputs and log evidence.
- Specific ODS EXCEL style options (font size, column widths, freeze pane row count) — already set in program 19; leave as-is unless a defect surfaces.
- Log-scan script language — PowerShell chosen (regex allowlist).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Pipeline driver and runner
- `run_pipeline.cmd` — current batch driver; RUN-02 and RUN-03 changes land here, plus the scan wire
- `sas/19_raw_dir_inventory.sas` — program 19; INV-07 is delivered by reordering its SECTION 13 (FAMILIES to second)

### SAS programs with committed fixes (verify these are correct before planning new changes)
- `sas/16b_cohort_rebuild.sas` — FIX-02 already committed in ba3daa1; review SECTION 7 and %measure_h_cols list
- `sas/20_pecan_id.sas` — FIX-02 already committed in ba3daa1; review certutil/output/stop block

### Requirements and decisions
- `.planning/REQUIREMENTS.md` §Pipeline Green & Hardening — FIX-02, RUN-02, RUN-03, INV-07, DOC-05 acceptance criteria
- `docs/DECISIONS.md` — PCM-D-14 through PCM-D-20 (prior resolved decisions); DOC-05 adds PCM-T-14 and PCM-T-15

### Configuration and traps
- `sas/00_config.sas` — gate macros pattern; logs_path and qc_path values
- `PROJECT.md` §Traps to Avoid — PCM-T-14 (`%put` semicolon) and PCM-T-15 (open-code `%local`/`%if`) are the two fixes committed in ba3daa1; DOC-05 adds them here

No external specs — requirements fully captured in decisions above and REQUIREMENTS.md.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `run_pipeline.cmd` `:run_program` subroutine — RUN-02 fix is a one-line change within this subroutine; RUN-03 block goes at the top of `:main`; scan call goes just before the final PASSED block
- `sas/19_raw_dir_inventory.sas` SECTION 13 — already writes the 7-sheet UF-styled workbook; INV-07 is a one-block reorder (FAMILIES to second)
- `sas/00_config.sas` — `%fail_out` macro and path setup patterns

### Established Patterns
- Each program is a separate sas.exe session (PCM-C-05)
- WORK-then-promote pattern for any output dataset (PCM-T-02 guard)
- Gate macros (`DOMAIN_MAP_APPROVED`, `D15_APPROVED`)
- `ODS EXCEL` already used in program 19 SECTION 13, 09_summary_stats.sas and 17_summary_stats_by_domain.sas

### Integration Points
- `run_pipeline.cmd` — RUN-02 + RUN-03 edits; `scan_pipeline_logs.ps1` wired as last step (no 19b wire)
- `config.local.cmd.example` — new file at repo root; `.gitignore` entry for `config.local.cmd`
- `qc\22_pipeline_scan.txt` — new output from the log-scan script; written to existing `qc\` directory

</code_context>

<specifics>
## Specific Ideas

- **config.local.cmd pattern**: one line — `set "SAS_EXE=C:\Program Files\SAS94\SASFoundation\9.4\sas.exe"` — matching the format already used in run_pipeline.cmd.
- **INV-07 delivery**: reorder program 19 SECTION 13 so FAMILIES is the second sheet; no new program. The workbook order becomes KEY -> FAMILIES -> FILES -> SHEETS -> VARIABLES -> KEY_COLUMNS -> RECONCILIATION.
- **Log-scan allowlist**: PowerShell for regex; allowlist entries are patterns, not literal strings, so future benign warnings can be added without restructuring the script.
- **scan_pipeline_logs.ps1**: repo root (not `qc/` — that tree is on P: and never committed); filters logs by LastWriteTime, excludes 99_run_all.log, ascii output, exit 1 on FAIL.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 22-pipeline-green-hardening*
*Context gathered: 2026-09-24 (revised same day per checker feedback)*
