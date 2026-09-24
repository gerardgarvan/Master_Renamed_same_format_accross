# Phase 22: Pipeline Green & Hardening - Context

**Gathered:** 2026-09-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Harden the existing pipeline before any new programs are added. The 2026-09-24 run stopped
at 16b; every v2.1 program (23, 24, 25) runs downstream of 16b. This phase delivers:
- Confirmed clean end-to-end run (evidence-gated, not just "code looks right")
- Warning count in runner fixed to count only log lines that begin with `WARNING`
- `SAS_EXE` overridable without editing the committed file
- `qc/19_raw_inventory.xlsx` formatted with UF colors, KEY sheet leftmost, FAMILIES sheet
- Documentation drift closed (MILESTONES.md, STATE.md, PROJECT.md trap list)

No new analytic capability is added in this phase.

</domain>

<decisions>
## Implementation Decisions

### RUN-03: SAS_EXE Override (machine portability)

- **D-01:** Use both config.local.cmd and environment variable, with explicit precedence in `run_pipeline.cmd`:
  ```bat
  if exist "%~dp0config.local.cmd" call "%~dp0config.local.cmd"
  if not defined SAS_EXE set "SAS_EXE=C:\Program Files\SASHome\SASFoundation\9.4\sas.exe"
  if not exist "%SAS_EXE%" (echo SAS_EXE not found: "%SAS_EXE%" & exit /b 1)
  ```
- **D-02:** Commit `config.local.cmd.example` (showing the one-line `set SAS_EXE=...` pattern) and add `config.local.cmd` to `.gitignore`.
- **D-03:** Precedence order: environment variable wins → local file applies → hardcoded default. The existence check gives a clear message instead of a cryptic launch failure.
- **D-04:** Rationale for local file over pure env var: on a two-machine shop, a visible file next to `run_pipeline.cmd` is easier to locate and fix than a Windows user environment variable.

### INV-07: Excel Formatting Tooling

- **D-05:** Stay in SAS. No Python dependency — the pipeline is SAS end to end and runs from `run_pipeline.cmd`. Adding Python means a second runtime to install and version on both machines just for cosmetics.
- **D-06:** Implement as a new standalone program `sas/19b_raw_inventory_xlsx.sas`. Reads the inventory datasets that program 19 already writes to library `g`; does not modify 19. Keeps data generation separate from presentation; reruns are cheap.
- **D-07:** Use `ODS EXCEL` for all three formatting requirements:
  - Sheet order: write KEY sheet first so it is leftmost; then FAMILIES, then data sheets.
  - UF blue headers (#0021A5, white text): use `PROC REPORT` style overrides.
  - Usability: enable `frozen_headers` and `autofilter` options.
- **D-08:** Fall back to openpyxl only if a requirement surfaces that ODS EXCEL cannot satisfy (e.g., formula-driven conditional formatting). This phase does not need it.
- **D-09:** Wire `19b_raw_inventory_xlsx.sas` into `run_pipeline.cmd` immediately after program 19 (still before program 20). It is a separate sas.exe session per PCM-C-05.

### Pipeline Run Scope & Verification

- **D-10:** The "exits clean" criterion requires a real `run_pipeline.cmd` run on the machine with P: drive access. This is a **human-run, agent-verified** checkpoint — Claude Code cannot execute against P: drive.
- **D-11:** Plan includes a committed log-scan step: a small `.cmd` or PowerShell script that greps `logs\` for known error patterns and writes a pass/fail summary to `qc\22_pipeline_scan.txt`. The scan script is committed; it can be rerun after any pipeline run.
- **D-12:** Error patterns to scan:
  - `^ERROR`
  - `^WARNING` (after RUN-02 fix, this is the canonical warning line start)
  - `uninitialized`
  - `MERGE statement has more than one data set with repeats of BY values`
  - `Invalid data`
  - `character values have been converted`
- **D-13:** Include an allowlist for known benign warnings so the scan does not fail on every run. At minimum: ESOPH transcoding notes (if still present). Allowlist is defined in the scan script, not hardcoded knowledge.
- **D-14:** Phase 22 is only marked complete after the scan summary is read and FIX-02 / RUN-02 are confirmed on that evidence. Phase does not close on "code looks right" alone.

### RUN-02: Warning Count Fix

- **D-15:** Change `findstr /c:"WARNING:"` to `findstr /b /c:"WARNING:"` (or `/r /c:"^WARNING:"`) in the `:run_program` subroutine of `run_pipeline.cmd`. This ensures only lines that BEGIN with `WARNING:` are counted; echoed SAS source lines containing `WARNING:` in string literals are excluded.
- **D-16:** After the fix, 10b should report 0 warnings. Confirm from the log-scan summary.

### Claude's Discretion

- Exact wording of the MILESTONES.md one-liners, STATE.md metric values, and PROJECT.md trap entries (DOC-05) — Claude writes these from the existing QC outputs and log evidence.
- Specific ODS EXCEL style options (font size, column widths, freeze pane row count) — Claude picks sensible defaults consistent with the existing DATA_DICTIONARY.xlsx style.
- Log-scan script language (`.cmd` vs PowerShell) — Claude picks whichever is cleaner for the pattern matching; PowerShell preferred if regex is needed for the allowlist.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Pipeline driver and runner
- `run_pipeline.cmd` — current batch driver; RUN-02 and RUN-03 changes land here
- `sas/19_raw_dir_inventory.sas` — program 19 (produces datasets that 19b reads); do not modify for INV-07

### SAS programs with committed fixes (verify these are correct before planning new changes)
- `sas/16b_cohort_rebuild.sas` — FIX-02 already committed in ba3daa1; review SECTION 7 and %measure_h_cols list
- `sas/20_pecan_id.sas` — FIX-02 already committed in ba3daa1; review certutil/output/stop block

### Requirements and decisions
- `.planning/REQUIREMENTS.md` §Pipeline Green & Hardening — FIX-02, RUN-02, RUN-03, INV-07, DOC-05 acceptance criteria
- `docs/DECISIONS.md` — PCM-D-14 through PCM-D-20 (prior resolved decisions); DOC-05 adds PCM-T-14 and PCM-T-15

### Configuration and traps
- `sas/00_config.sas` — gate macros pattern (reference for any new gate in 19b)
- `PROJECT.md` §Traps to Avoid — PCM-T-14 (`%put` semicolon) and PCM-T-15 (open-code `%local`/`%if`) are the two fixes committed in ba3daa1; DOC-05 adds them here

No external specs — requirements fully captured in decisions above and REQUIREMENTS.md.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `run_pipeline.cmd` `:run_program` subroutine — RUN-02 fix is a one-line change within this subroutine; RUN-03 block goes at the top of `:main`
- `sas/19_raw_dir_inventory.sas` — already writes inventory datasets to library `g`; 19b reads from there, no re-generation needed
- `sas/00_config.sas` — `%fail_out` macro and path setup patterns reusable in 19b

### Established Patterns
- Each program is a separate sas.exe session (PCM-C-05); 19b follows this pattern
- WORK-then-promote pattern for any output dataset (PCM-T-02 guard)
- Gate macros (`DOMAIN_MAP_APPROVED`, `D15_APPROVED`) — 19b does not need a gate but the pattern is established
- `ODS EXCEL` already used in 09_summary_stats.sas and 17_summary_stats_by_domain.sas — reference those for style syntax

### Integration Points
- `run_pipeline.cmd` — 19b inserted after program 19, before program 20
- `config.local.cmd.example` — new file at repo root; `.gitignore` entry for `config.local.cmd`
- `qc\22_pipeline_scan.txt` — new output from the log-scan script; written to existing `qc\` directory

</code_context>

<specifics>
## Specific Ideas

- **config.local.cmd pattern**: one line — `set "SAS_EXE=C:\Program Files\SAS94\SASFoundation\9.4\sas.exe"` — matching the format already used in run_pipeline.cmd.
- **19b program**: small — maybe 60-80 lines. Reads `g.files19`, `g.dirs19`, and any summary dataset program 19 wrote; outputs `qc\19_raw_inventory.xlsx` overwriting the unformatted version.
- **Log-scan allowlist**: PowerShell preferred for regex; allowlist entries are patterns, not literal strings, so future benign warnings can be added without restructuring the script.
- **ODS EXCEL reference**: check `sas/17_summary_stats_by_domain.sas` for existing UF color style usage before writing new styles from scratch.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 22-pipeline-green-hardening*
*Context gathered: 2026-09-24*
