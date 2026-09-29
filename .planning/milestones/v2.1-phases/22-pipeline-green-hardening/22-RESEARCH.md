# Phase 22: Pipeline Green & Hardening - Research

**Researched:** 2026-09-24
**Domain:** SAS 9.4 batch pipeline hardening, CMD batch scripting, ODS EXCEL formatting
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**RUN-03: SAS_EXE Override**
- D-01: Use both config.local.cmd and environment variable with explicit precedence in run_pipeline.cmd:
  ```bat
  if exist "%~dp0config.local.cmd" call "%~dp0config.local.cmd"
  if not defined SAS_EXE set "SAS_EXE=C:\Program Files\SASHome\SASFoundation\9.4\sas.exe"
  if not exist "%SAS_EXE%" (echo SAS_EXE not found: "%SAS_EXE%" & exit /b 1)
  ```
- D-02: Commit `config.local.cmd.example`; add `config.local.cmd` to `.gitignore`.
- D-03: Precedence: environment variable wins → local file applies → hardcoded default.
- D-04: Local file preferred over pure env var for a two-machine shop.

**INV-07: Excel Formatting Tooling**
- D-05: Stay in SAS. No Python dependency.
- D-06: Implement as new standalone `sas/19b_raw_inventory_xlsx.sas`. Reads from `g` library datasets written by program 19. Does not modify 19.
- D-07: Use ODS EXCEL: KEY sheet first (leftmost), then FAMILIES, then data sheets. UF blue (#0021A5) headers via PROC REPORT style overrides. `frozen_headers` and `autofilter` enabled.
- D-08: Fall back to openpyxl only if a requirement surfaces ODS EXCEL cannot satisfy. Not needed this phase.
- D-09: Wire 19b into run_pipeline.cmd immediately after program 19, before program 20.

**Pipeline Run Scope & Verification**
- D-10: "Exits clean" requires a real run_pipeline.cmd run on the machine with P: drive access. Human-run, agent-verified checkpoint.
- D-11: Committed log-scan step: a small .cmd or PowerShell script that greps logs\ for known error patterns and writes a pass/fail summary to qc\22_pipeline_scan.txt.
- D-12: Error patterns to scan: `^ERROR`, `^WARNING`, `uninitialized`, `MERGE statement has more than one data set with repeats of BY values`, `Invalid data`, `character values have been converted`.
- D-13: Include an allowlist for known benign warnings. At minimum: ESOPH transcoding notes. Allowlist defined in the scan script.
- D-14: Phase 22 only marked complete after scan summary is read and FIX-02 / RUN-02 confirmed on evidence.

**RUN-02: Warning Count Fix**
- D-15: Change `findstr /c:"WARNING:"` to `findstr /b /c:"WARNING:"` (or `/r /c:"^WARNING:"`) in the `:run_program` subroutine of `run_pipeline.cmd`.
- D-16: After the fix, 10b should report 0 warnings. Confirmed from the log-scan summary.

### Claude's Discretion
- Exact wording of MILESTONES.md one-liners, STATE.md metric values, and PROJECT.md trap entries (DOC-05).
- Specific ODS EXCEL style options (font size, column widths, freeze pane row count) — consistent with existing DATA_DICTIONARY.xlsx style.
- Log-scan script language (.cmd vs PowerShell) — PowerShell preferred if regex is needed for the allowlist.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

## Summary

Phase 22 is a hardening-and-cleanup phase with five distinct deliverables: (1) FIX-02 verified clean via a real pipeline run, (2) the warning-count regex narrowed to line-start matches only (RUN-02), (3) SAS_EXE made overridable without editing the committed file (RUN-03), (4) the raw inventory workbook formatted in UF colors with KEY sheet leftmost (INV-07), and (5) documentation drift closed (DOC-05). No new analytic logic is introduced.

The most important implementation insights are: the fix commits (ba3daa1) are already in the repo for 16b and 20, so FIX-02 is code-complete and needs a verified run, not new code. The warning-count fix is a one-character CMD change (`/c:` to `/b /c:`). RUN-03 is a three-line block at the top of `:main`. INV-07 requires a new ~60-80 line SAS program (19b) that reads from the `g` library datasets that program 19 already promotes there -- confirmed by reading 19_raw_dir_inventory.sas. The ODS EXCEL style pattern is already established in both program 19 (via `styles.uf_inventory` template) and program 17 (via inline `style(header)` overrides) -- 19b can follow either approach.

The log-scan script is the only genuinely new design problem. PowerShell is preferred (D-13) because the allowlist needs regex patterns. The script must be committed so it is reproducible across machines.

**Primary recommendation:** Execute the five deliverables as parallel waves where possible: FIX-02 verification (human-gated), RUN-02+RUN-03 (pure code edits in run_pipeline.cmd), INV-07 (new SAS file + runner wire), DOC-05 (documentation updates), and the log-scan script. INV-07 is independent of the pipeline run result per the CONTEXT.md note.

---

## Standard Stack

### Core
| Tool/Library | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| SAS 9.4M8 | 9.4M8 | All SAS programs | Project constraint; session encoding is not UTF-8 |
| ODS EXCEL | (SAS built-in) | Excel workbook output | Already used in programs 19 and 17; no Python dependency (D-05) |
| PROC REPORT | (SAS built-in) | Styled table rendering inside ODS EXCEL | Used in program 17 for UF blue headers; same approach for 19b |
| CMD batch | Windows built-in | run_pipeline.cmd driver | Existing project convention; PCM-C-05 |
| PowerShell | Windows built-in | Log-scan script | Preferred for regex allowlist matching (D-13 discretion) |

### Supporting
| Tool/Library | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| findstr /b /c: | CMD built-in | Line-start WARNING match | RUN-02 fix in run_pipeline.cmd |
| certutil | Windows built-in | SHA-256 hashing in program 20 | Already used; the fix (ba3daa1) adds output/stop |
| `config.local.cmd` | New file | Machine-specific SAS_EXE path | RUN-03; gitignored; one line per machine |

**Version verification:** No npm packages involved; all tooling is Windows/SAS built-in. No `npm view` needed.

---

## Architecture Patterns

### Key Pattern: ODS EXCEL with PROC REPORT (UF Blue Headers)

Program 19 uses a `proc template` approach (creates `styles.uf_inventory`):

```sas
/* From sas/19_raw_dir_inventory.sas SECTION 13 */
ods path(prepend) work.templat(update);
proc template;
  define style styles.uf_inventory;
    parent = styles.pearl;
    class header /
      backgroundcolor = cx0021A5
      color           = white
      fontweight      = bold;
  end;
run;

ods excel file="&qc_path.\19_raw_inventory.xlsx"
    style=styles.uf_inventory
    options(sheet_interval='proc' frozen_headers='on' autofilter='all');

ods excel options(sheet_name='KEY');
proc print data=work.key_legend noobs; run;
```

Program 17 uses an inline `style(header)` override on each PROC REPORT:

```sas
/* From sas/17_summary_stats_by_domain.sas SECTION 9.4 */
ods excel file="&qc_path.\17_summary_stats_by_domain.xlsx"
    options(sheet_name="KEY"
            autofilter="all"
            frozen_headers="1"
            sheet_interval="none");

proc report data=work.key nowd
    style(header)=[background=CX0021A5 color=white fontweight=bold]
    style(column)=[fontsize=9pt];
  columns item detail;
  define item   / display "Item"   style(column)=[width=1.8in fontweight=bold];
  define detail / display "Detail" style(column)=[width=5.5in];
run;
```

**For 19b:** The `styles.uf_inventory` template approach (program 19's own pattern) is the right model because 19b is a presentation layer on top of 19's data. Use `style=styles.uf_inventory` on the ODS EXCEL statement, then set `sheet_interval='proc'` (so each PROC produces a tab). Sheet order is controlled by the order PROC statements execute: KEY first, then FAMILIES, then the data sheets.

**Critical sheet-order detail:** ODS EXCEL sheets appear in the order their first output is written. Writing KEY first makes it leftmost. The existing program 19 already writes KEY first (line 975: `ods excel options(sheet_name='KEY')`), but program 19 uses `sheet_interval='proc'` which opens a new tab for every PROC. In 19b, do the same -- write `ods excel options(sheet_name='KEY')` before the first PROC, and the rest in order.

**FAMILIES sheet placement (INV-07 requirement):** FAMILIES must appear as the second sheet (after KEY, before data sheets). In program 19, FAMILIES is the last sheet written. In 19b, restructure the output order: KEY → FAMILIES → FILES → SHEETS → VARIABLES → KEY_COLUMNS → RECONCILIATION.

### Key Pattern: run_pipeline.cmd `:run_program` Subroutine

Current warning-count line (line 56):
```bat
for /f %%W in ('findstr /c:"WARNING:" "%_LOG_FILE%" 2^>nul ^| find /c /v ""') do set _WARNS=%%W
```

RUN-02 fix -- change `/c:` to `/b /c:` (or `/r /c:"^WARNING:"`):
```bat
for /f %%W in ('findstr /b /c:"WARNING:" "%_LOG_FILE%" 2^>nul ^| find /c /v ""') do set _WARNS=%%W
```

`/b` restricts the match to lines where `WARNING:` occurs at the start of the line, which is how SAS formats its own warning lines. This prevents SAS source code echoed in the log (which may contain the string `WARNING:` in a string literal or comment) from inflating the count.

### Key Pattern: RUN-03 SAS_EXE Override Block

Insert at the top of `:main` (after `goto :main` but before the first `call :run_program`):

```bat
:main

REM ---- Machine-specific SAS_EXE override (RUN-03) ----
if exist "%~dp0config.local.cmd" call "%~dp0config.local.cmd"
if not defined SAS_EXE set "SAS_EXE=C:\Program Files\SASHome\SASFoundation\9.4\sas.exe"
if not exist "%SAS_EXE%" (
  echo SAS_EXE not found: "%SAS_EXE%"
  exit /b 1
)
```

The existing hardcoded `set SAS_EXE=` at the top of the file (line 25, currently `C:\Program Files\SAS94\...`) becomes the fallback default that the `if not defined` line sets only when neither the env var nor config.local.cmd defined it. Keep the existing line as the default to avoid breaking the current machine, but move it into an `if not defined` guard:

```bat
REM ---- Machine-specific paths ----
set SAS_PATH=C:\Master_Renamed_same_format_accross\sas
set LOGS_PATH=P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs
set MASTER_LOG=%LOGS_PATH%\99_run_all.log
```

Then in `:main`:
```bat
if exist "%~dp0config.local.cmd" call "%~dp0config.local.cmd"
if not defined SAS_EXE set "SAS_EXE=C:\Program Files\SAS94\SASFoundation\9.4\sas.exe"
if not exist "%SAS_EXE%" (echo SAS_EXE not found: "%SAS_EXE%" & exit /b 1)
```

`config.local.cmd.example`:
```bat
@echo off
set "SAS_EXE=C:\Program Files\SASHome\SASFoundation\9.4\sas.exe"
```

### Key Pattern: 19b Reads from g Library (Not Raw Files)

Program 19 promotes all its output datasets to the `g` library at the end of a run. Program 19b must assume those datasets exist. The relevant g-library outputs from program 19 are the WORK datasets it produces before the ODS EXCEL section -- specifically `work.files_out`, `work.sheets_rpt`, `work.variables`, `work.key_columns`, `work.reconciliation`, `work.families`, and `work.key_legend`.

**Critical finding:** Program 19 does NOT promote these WORK datasets to `g`. It only writes them to the XLSX workbook. This means 19b cannot simply read `g.files_out` -- those datasets only exist in the WORK library during program 19's session.

**Resolution:** Program 19b must either (a) re-read the CSV files that program 19 exports (qc\19_raw_files.csv, qc\19_raw_key_columns.csv, qc\19_raw_sheets.csv, qc\19_raw_variables_md3.csv, qc\19_raw_families.csv) via PROC IMPORT, or (b) have program 19 promote the datasets to g. The CONTEXT.md says "Reads the inventory datasets that program 19 already writes to library g" -- but inspection of 19_raw_dir_inventory.sas shows no `libname g` assignment and no `data g.*` steps. This is a gap that the planner must resolve.

**Most likely correct interpretation:** Program 19 should promote key datasets to g at the end of its run (a small addition), or 19b re-reads the CSV exports. Option (b) (read CSVs) is safer because it does not modify program 19 (which CONTEXT.md says to leave alone). FAMILIES data is not exported as a CSV currently -- this is a gap.

**Alternate interpretation:** The CONTEXT.md statement about "writes to library g" may have been written in anticipation of a change being made to program 19. Check whether program 19 has a `libname g` call or `data g.*` steps before treating the statement as authoritative.

### Key Pattern: Log-Scan PowerShell Script

```powershell
# scan_pipeline_logs.ps1
# Scans all .log files under LOGS_PATH for known error/warning patterns.
# Writes pass/fail summary to qc\22_pipeline_scan.txt.

$logsPath  = "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs"
$outFile   = "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc\22_pipeline_scan.txt"

$errorPatterns = @(
    '^ERROR',
    '^WARNING',
    'uninitialized',
    'MERGE statement has more than one data set with repeats of BY values',
    'Invalid data',
    'character values have been converted'
)

# Allowlist: benign patterns that should NOT count as failures
$allowlist = @(
    'WARNING.*ESOPH'       # encoding transcoding note -- known benign
    # add more here as discovered
)

$findings = @()

Get-ChildItem -Path $logsPath -Filter "*.log" | ForEach-Object {
    $logFile = $_.FullName
    $logName = $_.Name
    $content = Get-Content $logFile -ErrorAction SilentlyContinue
    foreach ($line in $content) {
        foreach ($pat in $errorPatterns) {
            if ($line -match $pat) {
                $benign = $false
                foreach ($allow in $allowlist) {
                    if ($line -match $allow) { $benign = $true; break }
                }
                if (-not $benign) {
                    $findings += [PSCustomObject]@{
                        Log   = $logName
                        Line  = $line.Trim()
                        Pattern = $pat
                    }
                }
            }
        }
    }
}

# Write summary
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$status    = if ($findings.Count -eq 0) { "PASS" } else { "FAIL" }

"Pipeline Log Scan -- $timestamp" | Out-File $outFile
"Status: $status  Findings: $($findings.Count)" | Out-File $outFile -Append
"====================================" | Out-File $outFile -Append
foreach ($f in $findings) {
    "$($f.Log): $($f.Line)  [pattern: $($f.Pattern)]" | Out-File $outFile -Append
}
```

The script is committed to the repo root as `scan_pipeline_logs.ps1`. It is run by the human after the pipeline run and produces `qc\22_pipeline_scan.txt` on the P: drive.

### Key Pattern: PCM compliance for 19b

Every SAS program in this repo follows these rules (from 19_raw_dir_inventory.sas header):
- No bare open-code `%IF/%THEN` -- wrap in named macros
- No apostrophes or embedded semicolons in `%PUT` text
- Every `%abort cancel` inside `%fail_out` only
- No `data X; set X;` (PCM-T-02)
- No `PROC SQL UPDATE`
- `dictionary.columns.type` is `char`/`num` not `1`/`2` (PCM-T-13)
- ASCII only (session encoding is not UTF-8)
- `options nosyntaxcheck noerrorabend` before any PROC IMPORT
- `%local` and `%if` not used in open code (PCM-T-15, the fix committed in ba3daa1)
- No `%put` with a trailing semicolon inside the text (PCM-T-14, the other ba3daa1 fix)

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| UF blue Excel headers | Custom xlsm writer, openpyxl | ODS EXCEL + PROC REPORT style override | Already works in programs 17 and 19; SAS-native |
| SHA-256 in SAS | Perl FCB macro, custom hash | certutil via INFILE PIPE FILEVAR= | Program 20 already uses this; Windows built-in |
| Sheet ordering in ODS EXCEL | Post-process with Python | Write sheets in the desired order (ODS writes sequentially) | ODS EXCEL sheet order = execution order |
| Regex log scanning | Batch findstr loops | PowerShell `-match` operator | Batch findstr cannot do allowlists cleanly |
| Machine-local path config | Environment variable registry | config.local.cmd next to run_pipeline.cmd | Visible, portable, already the D-04 decision |

**Key insight:** The entire pipeline is SAS + CMD. Every new deliverable should stay in that stack unless it provably cannot.

---

## Common Pitfalls

### Pitfall 1: ODS EXCEL Sheet Order Is Write Order
**What goes wrong:** The FAMILIES sheet ends up after the data sheets because it was the last PROC written in program 19's Section 13. If 19b copies program 19's ODS block verbatim, KEY will be first but FAMILIES will be last.
**Why it happens:** ODS EXCEL opens a new tab when it first writes to a new sheet name. Tab order = first-write order.
**How to avoid:** In 19b, restructure the PROC order: KEY → FAMILIES → FILES → SHEETS → VARIABLES → KEY_COLUMNS → RECONCILIATION.
**Warning signs:** Open the output xlsx and count the sheet tabs from left to right.

### Pitfall 2: 19b Reads Data That Doesn't Exist in g
**What goes wrong:** CONTEXT.md says "reads from library g" but program 19 does not promote datasets to g. Running 19b after 19 in a fresh session will fail with "dataset not found" if 19b reads `g.files_out`.
**Why it happens:** Program 19's WORK library is destroyed when its sas.exe session ends (PCM-C-05 -- each program is a separate session).
**How to avoid:** Either (a) add g-promotion steps at the end of program 19, or (b) have 19b re-read the CSV exports. Resolve this before writing 19b. Option (b) does not require modifying program 19.
**Warning signs:** `ERROR: File G.FILES_OUT.DATA does not exist.` in the 19b log.

### Pitfall 3: findstr /b vs /r for Line-Start Match
**What goes wrong:** Using `/r /c:"^WARNING:"` may not work as expected in all CMD versions -- findstr's regex is limited. The `^` anchor in findstr regex mode anchors to the start of the line, which is correct, but `^` inside `/c:` with `/r` is the regex version.
**Why it happens:** CMD findstr `/r` enables regex but its regex is a simplified POSIX subset, not full Perl regex.
**How to avoid:** Use `/b /c:"WARNING:"` which is simpler and well-documented as "match at the start of the line" without regex mode. This is CONTEXT.md D-15's preferred form.
**Warning signs:** The 10b warning count changes unexpectedly after the fix.

### Pitfall 4: config.local.cmd Must Use Quoted set
**What goes wrong:** Paths with spaces break if the `set` command does not use quoted syntax.
**Why it happens:** `set SAS_EXE=C:\Program Files\...` (unquoted) works in isolation but may be ambiguous in some contexts.
**How to avoid:** Always `set "SAS_EXE=..."` (quotes wrap the entire name=value, not just the value) as shown in the CONTEXT.md D-01 block.
**Warning signs:** SAS_EXE is defined but points to the wrong path, or the `if not exist` check fails unexpectedly.

### Pitfall 5: PCM-T-14 / PCM-T-15 in New SAS Code
**What goes wrong:** Writing `%put NOTE: message;` with a semicolon in the message text, or using `%local`/`%if` in open code, repeats the exact bugs that ba3daa1 fixed.
**Why it happens:** These look syntactically normal and SAS doesn't error immediately -- the damage shows up as swallowed subsequent statements.
**How to avoid:** All `%local` and `%if` must live inside a named `%macro ... %mend` block. All `%put` text must not contain semicolons.
**Warning signs:** SAS log shows `ERROR 180-322` or steps after a `%put` are silently skipped.

### Pitfall 6: DOC-05 Metrics Must Come from Run Evidence
**What goes wrong:** Filling STATE.md pecan_ID metrics from memory or prior-run notes rather than from the actual Phase 22 run logs.
**Why it happens:** The pecan_ID distinct count (cohort) is still "pending" -- it requires a clean 16b run, which Phase 22 delivers.
**How to avoid:** DOC-05 is the last deliverable. Fill the metrics after the log-scan confirms the run passed.
**Warning signs:** STATE.md pecan_ID distinct count (cohort) row still shows "pending" at phase close.

---

## Code Examples

### 19b: Program Structure (skeleton)

```sas
/*==========================================================================
  Program : 19b_raw_inventory_xlsx.sas
  Purpose : Presentation layer for the raw directory inventory.
            Reads datasets from library g (promoted by 19) or CSV exports
            from qc/; writes qc/19_raw_inventory.xlsx with:
              - KEY sheet leftmost
              - FAMILIES sheet second
              - UF blue (#0021A5) headers
              - frozen_headers and autofilter enabled
  Reads   : g.files19 / qc/19_raw_files.csv etc.  (no raw files touched)
  Writes  : qc/19_raw_inventory.xlsx  (overwrites unformatted version)
  PCM compliance: [same header as 19]
==========================================================================*/
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
options validvarname=v7 nofmterr;

%macro fail_out(msg=);
  %put ERROR: &msg;
  ods excel close;
  ods listing;
  %abort cancel;
%mend fail_out;

/* Preconditions: verify CSV exports from program 19 exist */
%macro check_inputs;
  %if %sysfunc(fileexist(&qc_path.\19_raw_files.csv)) = 0 %then
    %fail_out(msg=19_raw_files.csv not found -- re-run program 19 first);
  /* ... check others ... */
%mend check_inputs;
%check_inputs;

/* Import CSVs */
proc import datafile="&qc_path.\19_raw_files.csv"
    out=work.files_out dbms=csv replace;
  guessingrows=max;
run;
/* ... import sheets, variables, key_columns, reconciliation, families ... */

/* KEY legend (static -- replicate from program 19 Section 13) */
data work.key_legend; ... run;

/* UF style */
ods path(prepend) work.templat(update);
proc template;
  define style styles.uf_inventory;
    parent = styles.pearl;
    class header /
      backgroundcolor = cx0021A5
      color           = white
      fontweight      = bold;
  end;
run;

ods listing close;
ods excel file="&qc_path.\19_raw_inventory.xlsx"
    style=styles.uf_inventory
    options(sheet_interval='proc' frozen_headers='on' autofilter='all');

ods excel options(sheet_name='KEY');
proc print data=work.key_legend noobs; run;

ods excel options(sheet_name='FAMILIES');
proc print data=work.families noobs; run;

ods excel options(sheet_name='FILES');
proc print data=work.files_out noobs; run;

/* ... SHEETS, VARIABLES, KEY_COLUMNS, RECONCILIATION ... */

ods excel close;
ods listing;

/* Verify output */
%macro verify_output;
  %if %sysfunc(fileexist(&qc_path.\19_raw_inventory.xlsx)) = 0 %then
    %fail_out(msg=OUTPUT MISSING -- 19_raw_inventory.xlsx was not created);
%mend verify_output;
%verify_output;
%put NOTE: ==== Program 19b complete ====;
```

### run_pipeline.cmd: 19b insertion point

```bat
REM ---- Programs 19-20: v2.0 additions (raw inventory + pecan_ID) ----
call :run_program "19 raw_dir_inventory" "19_raw_dir_inventory.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

call :run_program "19b raw_inventory_xlsx" "19b_raw_inventory_xlsx.sas"
if !ERRORLEVEL! NEQ 0 goto :fail

call :run_program "20 pecan_id"         "20_pecan_id.sas"
if !ERRORLEVEL! NEQ 0 goto :fail
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `findstr /c:"WARNING:"` | `findstr /b /c:"WARNING:"` | Phase 22 (RUN-02) | 10b warning count drops to 0 |
| Hardcoded SAS_EXE in run_pipeline.cmd | config.local.cmd + env var override | Phase 22 (RUN-03) | Portable across machines |
| 19 writes unformatted xlsx inline | 19 writes data; 19b writes formatted xlsx | Phase 22 (INV-07) | Separation of data and presentation |
| open-code `%local`/`%if` in 16b | All conditional logic inside named macros | ba3daa1 (committed) | PCM-T-15 compliance |

**Deprecated/outdated:**
- `%put NOTE: msg;` with semicolons inside text: replaced with semicolon-free `%put` (PCM-T-14, ba3daa1)

---

## Open Questions

1. **Does program 19 actually promote datasets to the g library?**
   - What we know: The CONTEXT.md says 19b "reads the inventory datasets that program 19 already writes to library g." Program 19's source code has no `libname g` and no `data g.*` steps. It only writes WORK datasets.
   - What's unclear: Whether the CONTEXT.md statement describes an intended change to program 19 or a misremembering of its current state.
   - Recommendation: The planner should check whether adding g-promotion to program 19 is intended (small addition at the end of Section 12), or whether 19b should read CSVs. Reading CSVs is safer because it does not touch program 19. FAMILIES data is not currently exported as a CSV, so if the CSV route is taken, either program 19 must export it, or 19b must rebuild it from the other data.

2. **Which logs does the scan script cover?**
   - What we know: D-11 says "greps `logs\`" and D-16 says "confirm 10b reports 0." The logs directory is on P: drive. The scan script needs the path hardcoded or parameterized.
   - What's unclear: Whether to scan all `.log` files in `logs\` or only the per-program logs (not 99_run_all.log).
   - Recommendation: Scan all per-program logs; 99_run_all.log is the summary and should be skipped or treated separately.

3. **What are the current MILESTONES.md one-liner placeholders?**
   - What we know: DOC-05 requires filling them; the wording is Claude's discretion.
   - What's unclear: Exact current content of MILESTONES.md (not in the read list).
   - Recommendation: Planner should add a task to read MILESTONES.md before writing DOC-05.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| SAS 9.4 | All SAS programs | On P:-access machine (human-run) | 9.4M8 | None (machine constraint) |
| PowerShell | scan_pipeline_logs.ps1 | Windows 10 built-in | 5.1+ | .cmd with findstr (less regex power) |
| certutil | Program 20 SHA-256 | Windows 10 built-in | OS-bundled | None (Windows-only; already used) |
| P: drive | All pipeline outputs | Human-access only | — | None; agent cannot run pipeline |
| `config.local.cmd` | RUN-03 | New file (to be created) | — | Environment variable alone |

**Missing dependencies with no fallback:**
- P: drive access: Claude Code cannot run the pipeline. This is expected per D-10. The pipeline run is human-executed.

**Missing dependencies with fallback:**
- None beyond the above.

---

## Validation Architecture

nyquist_validation is enabled in .planning/config.json.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | No automated test framework — SAS 9.4 batch with internal assertions |
| Config file | None (assertions inline in SAS programs) |
| Quick run command | Human runs `run_pipeline.cmd` then `scan_pipeline_logs.ps1` |
| Full suite command | Same; output is `qc\22_pipeline_scan.txt` |

This project uses SAS batch programs with internal `%fail_out` guards and explicit count assertions as its test layer. There is no pytest, jest, or vitest infrastructure.

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FIX-02 | 16b writes `qc/16b_pecan_id_counts.txt` with 12 `h_within_cohort_*` lines; 20 log has no `SHA-256 FAILED` | smoke (human run) | `scan_pipeline_logs.ps1` → `22_pipeline_scan.txt` | 19b new / scan new |
| RUN-02 | 10b warning count = 0 in `99_run_all.log` | smoke (human run) | `scan_pipeline_logs.ps1` | same |
| RUN-03 | `SAS_EXE` resolved without editing committed file | manual verify | Run `run_pipeline.cmd` after deleting SAS_EXE env var | new `config.local.cmd` |
| INV-07 | `19_raw_inventory.xlsx` has KEY leftmost, FAMILIES second, UF blue headers | manual verify | Open xlsx and inspect | 19b new |
| DOC-05 | MILESTONES.md, STATE.md, PROJECT.md updated accurately | manual review | — | existing docs |

### Sampling Rate
- **Per task commit:** n/a (no fast automated suite; SAS takes minutes per program)
- **Per wave merge:** Human runs `run_pipeline.cmd`; agent reads scan output
- **Phase gate:** `qc\22_pipeline_scan.txt` shows PASS; all five success criteria confirmed

### Wave 0 Gaps
- [ ] `sas/19b_raw_inventory_xlsx.sas` -- new program for INV-07
- [ ] `scan_pipeline_logs.ps1` -- new log-scan script for D-11
- [ ] `config.local.cmd.example` -- new example file for RUN-03
- [ ] `.gitignore` entry for `config.local.cmd`

*(No existing test infrastructure to extend; all gaps are new deliverables, not missing test files.)*

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase 22 |
|-----------|-------------------|
| SAS 9.4M8 on Windows; session encoding not UTF-8 | 19b must be ASCII-only; no special chars in string literals |
| Read-only on `master_data_1..8.sas7bdat` and everything under `raw\master` | 19b reads only qc\ exports or g\ datasets; never touches raw\ |
| No PHI in git: `.gitignore` excludes `*.sas7bdat`, `*.xlsx`, `*.csv`, `data/` | `config.local.cmd` must be added to `.gitignore`; scan output on P: drive is never committed |
| Repo on local disk, not P: drive | run_pipeline.cmd and all sas/ programs stay on C:; logs/qc on P: |
| Delivery: UF colors (#0021A5, #FA4616) on visual deliverables; KEY sheet leftmost | 19b must use #0021A5 for headers; KEY sheet must be the first sheet written |
| GSD Workflow Enforcement: use Edit/Write/GSD commands, not direct edits | All file changes go through GSD execute-phase workflow |

---

## Sources

### Primary (HIGH confidence)
- Direct read of `run_pipeline.cmd` -- current warning-count regex, SAS_EXE location, `:run_program` subroutine structure
- Direct read of `sas/19_raw_dir_inventory.sas` -- Section 13 ODS EXCEL pattern, sheet names, promoted datasets (none found)
- Direct read of `sas/17_summary_stats_by_domain.sas` -- inline `style(header)=[background=CX0021A5]` pattern at lines 3338, 3371, 3416, 3457, 3564, 3576
- Direct read of `sas/00_config.sas` -- gate macro pattern, path variables, in_pipeline flag mechanism
- `git show ba3daa1 --stat` -- confirmed FIX-02 commits are already in repo for 16b and 20
- `.planning/phases/22-pipeline-green-hardening/22-CONTEXT.md` -- all locked decisions
- `.planning/REQUIREMENTS.md` -- FIX-02, RUN-02, RUN-03, INV-07, DOC-05 acceptance criteria
- `.planning/config.json` -- nyquist_validation: true confirmed

### Secondary (MEDIUM confidence)
- Program 19 header comments and SECTION 13 naming -- datasets produced are WORK-only; no g-promotion observed (requires confirming no `data g.*` exists elsewhere in the file)

### Tertiary (LOW confidence)
- findstr /b behavior: documented in Windows help; behavior consistent with project's existing findstr usage but not separately verified against the SAS log format

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools are in-repo or Windows built-in; verified by reading source
- Architecture patterns: HIGH for ODS EXCEL, CMD, and PCM rules (read directly from source); MEDIUM for 19b data source (gap identified)
- Pitfalls: HIGH -- all derived from reading actual source code and commit history

**Research date:** 2026-09-24
**Valid until:** Stable; pipeline and SAS version are fixed. Re-research not needed within v2.1.
