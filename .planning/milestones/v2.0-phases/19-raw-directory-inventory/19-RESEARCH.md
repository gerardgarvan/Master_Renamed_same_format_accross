# Phase 19: Raw Directory Inventory — Research

**Researched:** 2026-09-23
**Domain:** SAS 9.4M8 — directory traversal, checksumming, PROC IMPORT profiling, ODS Excel
**Confidence:** HIGH (all findings from existing project code and locked CONTEXT.md decisions)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01: SHA-256 via certutil PIPE**
Compute checksums via `FILENAME ... PIPE "certutil -hashfile ""&fpath"" SHA256"` (not X statement). Strip all spaces from certutil output before testing for 64 consecutive hex characters — some Windows builds print the hash with spaces between byte pairs. XCMD must be enabled; document in program header.

**D-02: raw\master scope and presence checks**
Every file under `raw` (including `raw\master`) gets full profiling: fresh checksum, row/column counts, variable-level detail. No Phase 1 cache reuse. Before profiling, assert each of the eight named master extracts (md1-md8) is present under `raw\master`; any absence fires `%abort cancel`. New/extra files do NOT abort — they appear as NEW in RECONCILIATION. md3 absence is a hard blocker (PID-01 depends on its checksum).

**D-03: Variable profiling — one-pass DATA step, sentinel separation**
One DATA step with `_numeric_` and `_character_` arrays reads every row in a single pass, accumulating `n_missing` (true SAS missing: `.` for num, `' '` for char) and `n_sentinel` (`-999` for num; `upcase(strip(var))='NULL'` for char). PROC MEANS is NOT used. Report `pct_missing` and `pct_sentinel` as separate VARIABLES columns. Key detection sweeps every column regardless of family.

**D-04: FAMILIES sheet — DATALINES lookup, longest-match, COM scouting**
Families defined in a DATALINES lookup (prefix, family_name). Sort lookup by descending prefix length in code before matching. Upcase both sides before comparison. Seed families: `COMP10_`/`complication_sum` → complications; `COM` → dCDT (subject to scouting); `LINUS` → LINUS. COM scouting must be recorded in the plan before coding. FAMILIES assertion uses a FULL JOIN with `coalesce(..., 0)` — NOT inner join, NOT `&SQLOBS`, NOT `INTO :check` with GROUP BY. FAMILIES row reports: family_name, source_file, n_cols, pct_missing_min, pct_missing_median, pct_missing_max.

**D-05: ODS Excel, KEY sheet leftmost**
Output via ODS Excel (Phase 17 pattern). KEY sheet written first (ODS Excel `sheet_name=` ordering). UF blue (#0021A5) column headers. Fallback for slow VARIABLES write: separate workbook `qc/19_raw_variables.xlsx` — this is a separate-file split, not a drop-in swap.

**D-06: Three file statuses — profiled / listed-not-profiled / read-failed**
Every file lands in exactly one status. `read-failed` = extension is in the readable set but import failed. Set `options nosyntaxcheck noerrorabend;` before any import. After each import, check `&syserr`; non-zero = `read-failed`. Reset `%let syscc = 0;` after failure. Delete `work.&dsname` with PROC DATASETS before each import (stale dataset trap). Multi-sheet XLSX success = datasets produced matches sheet count from `dictionary.tables`. Program aborts only if a D-02b required file fails. INV-06 assertion: `n_profiled + n_listed_not_profiled + n_read_failed = n_total_files`.

**D-07: RECONCILIATION — DATALINES known-file list**
Known files: eight md1-md8 master extracts + nine Phase 18 supplemental files (r1-r9). Known-file list hardcoded in DATALINES. Files matching a known entry → `known`; all others → `NEW`.

### Claude's Discretion

- Directory traversal: `FILENAME pipe "dir /s /b /a-d ""&raw_path"""` — `/a-d` excludes subdirectory names; parse into FILES dataset before any import
- Macro structure (one macro per file type vs generalised loop over dslist)
- Whether SHA-256 PIPE call is wrapped in a macro or open-coded per file
- Report ordering within each sheet (FILES by path; VARIABLES by file then variable position; KEY_COLUMNS by file then column name)
- Whether SAS7BDAT files under raw are profiled via `dictionary.columns` or skipped as `listed-not-profiled`; use `dictionary.columns` if libname can be assigned, otherwise `listed-not-profiled`

### Deferred Ideas (OUT OF SCOPE)

- Wiring `19_raw_dir_inventory.sas` into `99_run_all.sas` — Phase 21 (RUN-01)
- r7/r8 gap-fill joining — gated on PCM-D-16 resolution; Phase 19 includes them in FILES/VARIABLES but makes no join decision
- PCM-D-15 extension-column gap-fill wiring — deferred to v2.1 pending PID-07
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INV-01 | Recursive file listing of `raw` with path, name, extension, size, last-modified, SHA-256; no file opened for write | D-01 certutil PIPE; D-06 three-status model; dir /s /b /a-d traversal |
| INV-02 | Row count, column count, sheet names for every readable data file; multi-sheet workbooks profiled per sheet in SHEETS sheet | D-02 full profiling; %import_xlsx SHEETS pattern; D-06 status model |
| INV-03 | Variable name, type, length, label/header, pct_missing for every variable in every readable file | D-03 one-pass DATA step; dictionary.columns for SAS7BDAT; pct_missing + pct_sentinel two columns |
| INV-04 | Key-column detection for PRECEDE_STUDY_ID, ENCRYPTED_MRN, ENCRYPTED_ENCOUNTER with all naming variants (PCM-T-12) | D-03 full-sweep key detection; PCM-T-12 variant enumeration pattern from Phase 16 |
| INV-05 | Known/NEW flag per file; known = md1-md8 or r1-r9; NEW = anything else | D-07 DATALINES known-file list; RECONCILIATION sheet |
| INV-06 | Every file has a resolved status; three-term assertion: profiled + listed-not-profiled + read-failed = total | D-06 three-status model; INV-06 assertion SQL pattern |
| INV-07 | `qc/19_raw_inventory.xlsx` with KEY leftmost, UF blue headers, sheets: KEY, FILES, SHEETS, VARIABLES, KEY_COLUMNS, RECONCILIATION, FAMILIES | D-05 ODS Excel KEY-first; D-04 FAMILIES sheet; CLAUDE.md UF colors |
</phase_requirements>

---

## Summary

Phase 19 builds `sas/19_raw_dir_inventory.sas` — a standalone SAS 9.4M8 program that recursively scans `P:\PeCAN Master Data\Gerard\raw`, checksums every file with certutil, imports every readable file (csv, xlsx/xls, sas7bdat), and profiles each at the row/column/variable level. Output is a seven-sheet workbook (`qc/19_raw_inventory.xlsx`) and a machine-readable CSV handoff (`qc/19_raw_files.csv`) for Phase 20.

All major design decisions are locked in CONTEXT.md. Research confirms that every pattern required (certutil PIPE, dir /s /b, ODS Excel KEY-first, one-pass missingness, FAMILIES FULL JOIN assertion, three-status file model) has precedent in the existing codebase (Programs 16, 17, macros_raw_import.sas) and no external libraries are needed.

**Primary recommendation:** Write one cohesive SAS program that follows the locked decisions exactly. Divide into numbered sections (traversal → checksum → import loop → variable profiling → key detection → family assignment → sheet assembly → assertions). Reuse `%import_csv`, `%import_xlsx`, `%fail_out`, `%route_log`, `%restore_log`, and `%assert_base` verbatim from existing programs.

---

## Standard Stack

### Core

| Component | Version / Source | Purpose | Why Standard |
|-----------|-----------------|---------|--------------|
| SAS 9.4M8 | Project constraint | All computation | Only available runtime |
| ODS Excel | Built into SAS 9.4M8 | Multi-sheet .xlsx output | Established in Phase 17; UF color support |
| FILENAME PIPE | Built into SAS 9.4M8 | certutil invocation; dir traversal | Only way to return shell output to SAS (X stmt cannot) |
| PROC IMPORT | Built into SAS 9.4M8, guessingrows=max | CSV and XLSX import | Wrapped in %import_csv / %import_xlsx (shared macros) |
| XLSX libname engine | Built into SAS 9.4M8 | Sheet enumeration | Used by %import_xlsx |
| PROC EXPORT | Built into SAS 9.4M8 | Write qc/19_raw_files.csv | Machine-readable Phase 20 handoff |
| certutil | Windows built-in | SHA-256 checksums | No external tools needed; XCMD required |

### Supporting

| Component | Source | Purpose | When to Use |
|-----------|--------|---------|-------------|
| `sas/macros_raw_import.sas` | Existing project file | %import_csv, %import_xlsx, %ensure_dslist | Include verbatim; do not redefine |
| `sas/16_raw_inventory.sas` | Existing project file | Pattern source for %fail_out, %check_dir, %route_log, %restore_log, %assert_base, key-detection block | Copy / adapt these macros |
| `sas/17_summary_stats_by_domain.sas` | Existing project file | ODS Excel KEY-first sheet ordering pattern | Reference for sheet_name= call sequence |
| `sas/00_config.sas` | Existing project file | &raw_path, &qc_path, &logs_path, &sas_path, &g_path | %include first in every program |

**Installation:** No packages to install. All components are built-in SAS 9.4M8 or existing project files.

---

## Architecture Patterns

### Recommended Program Structure

```
sas/19_raw_dir_inventory.sas
│
├── Section 0: Header, %include 00_config.sas, options, %include macros_raw_import.sas
│   options nosyntaxcheck noerrorabend;   ← MUST come before any import
├── Section 1: Utility macros (%route_log, %restore_log, %fail_out, %check_dir)
├── Section 2: Preconditions (check dirs exist, route log)
├── Section 3: Directory traversal — FILENAME PIPE "dir /s /b /a-d ""&raw_path"""
│             Build work.files_raw (full_path, filename, extension, fsize, fdate)
├── Section 4: D-02b presence assertion — assert md1-md8 all found; %abort cancel if missing
├── Section 5: SHA-256 checksums — loop over work.files_raw via macro; call certutil per file
├── Section 6: Import loop — for each file in readable-extension set:
│   ├── PROC DATASETS delete work.&dsname (stale dataset guard)
│   ├── Attempt import (reuse %import_csv / %import_xlsx)
│   ├── Check &syserr; set status = profiled / read-failed
│   ├── Collect row count, column count (dictionary.columns)
│   └── Record SHEETS rows for multi-sheet XLSX
├── Section 7: Variable profiling (INV-03) — one-pass DATA step per imported dataset
│             _numeric_ array: n_missing (.), n_sentinel (-999)
│             _character_ array: n_missing (' '), n_sentinel (upcase(strip())='NULL')
├── Section 8: Key-column detection (INV-04) — sweep all VARIABLES rows for PCM-T-12 variants
├── Section 9: FAMILIES assignment (D-04) — DATALINES lookup, sort desc by prefix length,
│             upcase both sides, longest-match; FULL JOIN assertion
├── Section 10: RECONCILIATION (D-07) — DATALINES known-file list; flag known vs NEW
├── Section 11: INV-06 three-term assertion
│             n_profiled + n_listed_not_profiled + n_read_failed = n_total_files
├── Section 12: PROC EXPORT → qc/19_raw_files.csv (write BEFORE ODS Excel opens)
├── Section 13: ODS Excel assembly — sheet order: KEY, FILES, SHEETS, VARIABLES,
│             KEY_COLUMNS, RECONCILIATION, FAMILIES; UF blue (#0021A5) headers
└── Section 14: Output verification and log restore
```

### Pattern 1: Directory Traversal with /a-d Flag

**What:** Read `dir /s /b /a-d` output through FILENAME PIPE into a SAS dataset of file paths.
**When to use:** Always — `/a-d` excludes subdirectory name lines, preventing certutil failures and false FILES rows.

```sas
/* Source: CONTEXT.md D-01/Claude's Discretion */
filename dirpipe pipe "dir /s /b /a-d ""&raw_path""";
data work.files_raw;
  infile dirpipe truncover lrecl=500;
  length full_path $500 filename $200 ext $20;
  input full_path $500.;
  full_path = strip(full_path);
  filename  = scan(full_path, -1, '\');
  ext       = lowcase(scan(filename, -1, '.'));
  /* fsize and fdate require a separate dir /s call or FINFO -- see Pattern 2 */
run;
filename dirpipe clear;
```

### Pattern 2: File Metadata (Size and Last-Modified)

**What:** Obtain fsize and last-modified date using SAS FOPEN/FINFO functions (no extra PIPE needed).
**When to use:** For each file path in work.files_raw.

```sas
/* Source: SAS FOPEN/FINFO — established SAS 9.4 approach */
data work.files_meta;
  set work.files_raw;
  length fsize 8 fdate $30;
  fid = fopen(full_path);
  if fid > 0 then do;
    fsize = input(finfo(fid, 'File Size (bytes)'), best32.);
    fdate = finfo(fid, 'Last Modified');
    fid   = fclose(fid);
  end;
run;
```

### Pattern 3: certutil SHA-256 via PIPE

**What:** Compute SHA-256 for one file path; parse output defensively.
**When to use:** Per-file inside a macro loop over work.files_raw.

```sas
/* Source: CONTEXT.md D-01 and Specifics */
%macro get_sha256(fpath=, outvar=);
  %local ck_id line hash;
  %let &outvar = FAILED;
  filename ck pipe "certutil -hashfile ""&fpath"" SHA256";
  data _null_;
    infile ck truncover lrecl=200;
    input line $200.;
    /* Strip all spaces (guards Windows builds that print spaces between byte pairs) */
    compressed = compress(line, ' ');
    if lengthn(compressed) = 64 and notxdigit(compressed) = 0 then
      call symputx("&outvar", compressed);
  run;
  filename ck clear;
%mend get_sha256;
```

### Pattern 4: One-Pass Missingness and Sentinel Count (D-03)

**What:** Single DATA step over an imported dataset, using `_numeric_` and `_character_` arrays.
**When to use:** For every profiled dataset (mandatory — PROC MEANS cannot count -999).

```sas
/* Source: CONTEXT.md D-03 */
data work.vars_&dsname;
  set work.&dsname end=_eof;
  array _num  {*} _numeric_;
  array _char {*} _character_;
  /* Accumulators in RETAIN */
  array n_miss_n   {*} _temporary_;
  array n_sent_n   {*} _temporary_;
  array n_miss_c   {*} _temporary_;
  array n_sent_c   {*} _temporary_;
  if _n_ = 1 then do;
    do _i = 1 to dim(_num);  n_miss_n{_i}=0; n_sent_n{_i}=0; end;
    do _i = 1 to dim(_char); n_miss_c{_i}=0; n_sent_c{_i}=0; end;
  end;
  do _i = 1 to dim(_num);
    if missing(_num{_i})           then n_miss_n{_i} + 1;
    else if _num{_i} = -999        then n_sent_n{_i} + 1;
  end;
  do _i = 1 to dim(_char);
    if missing(_char{_i})                            then n_miss_c{_i} + 1;
    else if upcase(strip(_char{_i})) = 'NULL'        then n_sent_c{_i} + 1;
  end;
  if _eof then do;
    /* Output one row per numeric variable */
    ...
  end;
run;
```

### Pattern 5: FAMILIES FULL JOIN Assertion (D-04)

**What:** Verify that every file's column count in VARIABLES matches its FAMILIES total.
**When to use:** After building work.families — abort if any mismatch.

```sas
/* Source: CONTEXT.md D-04 (verbatim from decisions) */
%macro assert_families;
  %local n_bad;
  %let n_bad = 0;
  proc sql noprint;
    select count(*) into :n_bad trimmed
    from (
      select coalesce(f.source_file, v.source_file) as src
      from (select source_file, sum(n_cols) as fam_total from work.families
            group by source_file) f
      full join
           (select source_file, count(*) as var_total from work.variables
            group by source_file) v
        on f.source_file = v.source_file
      where coalesce(f.fam_total, 0) ne coalesce(v.var_total, 0)
    );
  quit;
  %if &n_bad > 0 %then %do;
    %fail_out(msg=FAMILIES column totals do not match VARIABLES for &n_bad source files);
  %end;
%mend assert_families;
```

### Pattern 6: INV-06 Three-Term Assertion (D-06)

```sas
/* Source: CONTEXT.md D-06 */
%macro assert_inv06;
  %local n_bad;
  %let n_bad = 0;
  proc sql noprint;
    select count(*) into :n_bad trimmed
    from work.files_out
    where status not in ('profiled', 'listed-not-profiled', 'read-failed');
  quit;
  %if &n_bad > 0 %then %do;
    %fail_out(msg=INV-06 violated -- &n_bad files have unrecognized status);
  %end;
%mend assert_inv06;
```

### Pattern 7: ODS Excel KEY-First Sheet Order (D-05)

```sas
/* Source: sas/17_summary_stats_by_domain.sas ODS Excel pattern */
ods excel file="&qc_path.\19_raw_inventory.xlsx"
    style=styles.pearl
    options(embedded_titles='yes');
/* KEY written first — it will be leftmost */
ods excel options(sheet_name='KEY');
proc print data=work.key_legend noobs; run;
/* Then remaining sheets in order */
ods excel options(sheet_name='FILES');
proc print data=work.files_out noobs; run;
/* ... SHEETS, VARIABLES, KEY_COLUMNS, RECONCILIATION, FAMILIES ... */
ods excel close;
```

### Pattern 8: Import Error Trapping (D-06)

```sas
/* Source: CONTEXT.md D-06 */
/* Before each import attempt */
proc datasets lib=work nolist;
  delete &dsname;
quit;
/* Attempt import */
%import_csv(&rid, &fname)
/* Check result */
%let import_ok = 0;
%if &syserr = 0 %then %let import_ok = 1;
%if &import_ok = 0 %then %do;
  /* status = read-failed; record &syserr as fail_reason */
  %let syscc = 0;  /* reset accumulated error code */
%end;
```

### Anti-Patterns to Avoid

- **Using X statement for certutil:** Cannot return output to SAS. Use FILENAME PIPE only.
- **Omitting `options nosyntaxcheck noerrorabend`:** A PROC IMPORT ERROR puts SAS into syntax-check mode silently; all subsequent steps run on zero rows without aborting.
- **Relying on `%sysfunc(exist(work.&dsname))` alone after import:** A stale dataset from a prior iteration returns true even after a failed import. Delete with PROC DATASETS first.
- **Using PROC MEANS for missingness:** Cannot count -999 sentinel values. One-pass DATA step is mandatory.
- **FAMILIES inner join:** Silently drops files that have VARIABLES rows but no FAMILIES rows. Must be FULL JOIN with coalesce.
- **Using `&SQLOBS`:** Banned project-wide (STATE.md). Always use explicit `SELECT COUNT(*) INTO :macvar TRIMMED`.
- **Bare open-code %IF / %THEN:** All conditional logic must be inside named macros (PCM-R-05).
- **`dir /s /b` without `/a-d`:** Subdirectory name lines appear as FILES rows; certutil fails on them; INV-06 assertion trips.
- **Not double-quoting paths in certutil:** File names under `raw` contain spaces. Use `""&fpath""` inside the PIPE string.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CSV import | Custom INFILE reader | `%import_csv` from macros_raw_import.sas | Already handles guessingrows=max, dslist tracking |
| XLSX multi-sheet import | Manual libname loops | `%import_xlsx` from macros_raw_import.sas | Already handles sheet enumeration via dictionary.tables, call execute, dslist tracking |
| SHA-256 | Any SAS-native hash attempt | certutil via FILENAME PIPE | certutil is Windows built-in; SAS 9.4 has no native SHA-256 function |
| Log routing | Manual PROC PRINTTO each time | `%route_log` / `%restore_log` macros from 16_raw_inventory.sas | Already handles in_pipeline flag correctly |
| Abort-with-message | `%abort cancel` in open code | `%fail_out` macro from 16_raw_inventory.sas | PCM-R-05 requirement; fail_out closes ODS if open |
| Variable type lookup | Dictionary queries with numeric comparison | `dictionary.columns` with `type in ('char','num')` | type is character in SAS — PCM-T-13 |

---

## Common Pitfalls

### Pitfall 1: SAS Syntax-Check Mode on Import Error

**What goes wrong:** PROC IMPORT ERROR puts SAS into `OBS=0` syntax-check mode. All subsequent steps "run" on zero rows. The inventory appears to complete but is entirely empty.
**Why it happens:** Default SAS batch behavior on ERROR is `syntaxcheck` mode.
**How to avoid:** Set `options nosyntaxcheck noerrorabend;` in the program header, before any import.
**Warning signs:** Log shows "NOTE: The SAS System processed 0 observations" for all steps after a failed import.

### Pitfall 2: Stale Dataset Masking Import Failure

**What goes wrong:** `%sysfunc(exist(work.&dsname))` returns 1 even after a failed import because a dataset of the same name exists from a prior loop iteration.
**How to avoid:** `PROC DATASETS lib=work; delete &dsname; quit;` before every import attempt.
**Warning signs:** Status shows `profiled` for a file that should be `read-failed`; row count equals prior file's count.

### Pitfall 3: certutil Hash Parse Failure on Some Windows Builds

**What goes wrong:** Some Windows versions print the SHA-256 hash with spaces between byte pairs. A naive 64-character test finds no match and the hash field stays blank.
**How to avoid:** `compressed = compress(line, ' ')` before testing `lengthn(compressed) = 64 and notxdigit(compressed) = 0`.
**Warning signs:** All checksum fields are blank or `FAILED`.

### Pitfall 4: dir Without /a-d Includes Subdirectory Name Lines

**What goes wrong:** Subdirectory paths appear as FILES rows. certutil -hashfile on a directory path fails. The INV-06 three-term assertion finds rows with no valid status and aborts.
**How to avoid:** Always use `dir /s /b /a-d ""&raw_path""`.
**Warning signs:** FILES contains rows where `filename` looks like a folder name with no extension.

### Pitfall 5: COM Prefix Overmatch in FAMILIES

**What goes wrong:** A naive `COM` prefix also captures `COMORBID*`, `COMMENT*`, `COMPLICATION*` (without `10_`) columns. These are assigned to dCDT family incorrectly.
**How to avoid:** Scouting step: list all columns starting with `COM` not already captured by a longer prefix. Sort DATALINES lookup by descending prefix length in code before matching. Upcase both sides before comparison.
**Warning signs:** Complications columns showing up in dCDT family row counts.

### Pitfall 6: FAMILIES FULL JOIN vs Inner Join

**What goes wrong:** An inner join silently drops files that have VARIABLES rows but no family assignments, making the assertion pass when it should fail.
**How to avoid:** Use FULL JOIN with `coalesce(f.fam_total, 0)` and `coalesce(v.var_total, 0)` as shown in D-04.
**Warning signs:** n_bad = 0 even when a file's columns are all `unassigned` and FAMILIES has no row for it.

### Pitfall 7: Multi-Sheet XLSX Success Undercounting

**What goes wrong:** For an XLSX with N sheets, `%sysfunc(exist(work.&rid_s1))` returns true even if sheets 2 through N failed to import.
**How to avoid:** Compare count of datasets created in WORK for that rid against the sheet count from `dictionary.tables` for the libname. Any shortfall = `read-failed`.

### Pitfall 8: Key Column Variant Detection Gaps (PCM-T-12)

**What goes wrong:** Only checking `PRECEDE_STUDY_ID` misses `PRECEDE Study ID` (with spaces), `studyid`, positional `VARnn` names from XLSX engine when the original header had spaces.
**How to avoid:** Enumerate all known naming variants explicitly (PCM-T-12 sweep-all requirement). Reference the key-detection block from 16_raw_inventory.sas.

### Pitfall 9: PROC EXPORT Written After ODS Excel Close

**What goes wrong:** If ODS Excel crashes or takes very long, `qc/19_raw_files.csv` is never written. Phase 20 (PID-01) cannot verify the md3 checksum.
**How to avoid:** Write PROC EXPORT → `qc/19_raw_files.csv` before `ods excel file=...` opens. A crash during ODS export does not block the Phase 20 handoff file.

### Pitfall 10: %abort cancel in Open Code (PCM-R-05)

**What goes wrong:** Bare `%abort cancel;` in open code is a PCM violation and in some contexts behaves unexpectedly.
**How to avoid:** All abort calls go through `%fail_out(msg=...)` only.

---

## Runtime State Inventory

> Not a rename/refactor phase. No stored data, live service config, OS-registered state, secrets, or build artifacts carry Phase 19 strings. SKIPPED.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| SAS 9.4M8 | All computation | Assumed (project constraint) | 9.4M8 | None — hard requirement |
| certutil | SHA-256 (D-01) | Yes (Windows built-in on Win 10) | Windows 10 built-in | None — XCMD must be enabled |
| XCMD option | certutil PIPE | Must verify at session start | SAS site option | If disabled, checksum step cannot run — document in program header |
| P:\PeCAN Master Data\Gerard\raw | Directory traversal | Assumed present per project setup | — | Program aborts via %check_dir if absent |
| ODS Excel destination | Sheet output (D-05) | Built into SAS 9.4M8 | 9.4M8 | Separate-file split per D-05 fallback |

**Missing dependencies with no fallback:**
- XCMD disabled: certutil PIPE cannot execute. Program header must document this; the runner (Phase 21) must ensure XCMD is enabled in the batch session.

**Missing dependencies with fallback:**
- ODS Excel too slow on VARIABLES (40,000+ rows): write VARIABLES to `qc/19_raw_variables.xlsx` separately (D-05 approved fallback).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Manual SAS log inspection + assertion macros embedded in program |
| Config file | None — assertions are inline SAS macros |
| Quick run command | Submit `sas/19_raw_dir_inventory.sas` in a SAS batch session; inspect log for ERROR and NOTE counts |
| Full suite command | Same — program is self-contained with embedded assertions |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INV-01 | Every file in raw has path, size, date, SHA-256; no file silently skipped | Embedded assertion: n_total = nobs(files_raw); certutil check per file | Inspect log: no `FAILED` checksum; no missing rows | ❌ Wave 0 (new program) |
| INV-02 | Row/col count and sheet names for every readable file; SHEETS sheet populated | Embedded: compare dslist counts to SHEETS rows | Inspect log; open SHEETS tab in workbook | ❌ Wave 0 |
| INV-03 | Variable-level detail for every variable; pct_missing and pct_sentinel separate | Embedded: VARIABLES nobs = sum of column counts across profiled files | Inspect VARIABLES tab | ❌ Wave 0 |
| INV-04 | Key-column detection; all PCM-T-12 variants covered | Embedded: KEY_COLUMNS populated for known key-bearing files (md3, r2, r9 etc.) | Cross-check KEY_COLUMNS against known Phase 16/18 findings | ❌ Wave 0 |
| INV-05 | All md1-md8 and r1-r9 flagged known; any others flagged NEW | Embedded: RECONCILIATION nobs = nobs(files_raw); no null status | Inspect RECONCILIATION tab | ❌ Wave 0 |
| INV-06 | Three-term assertion passes | Embedded: `%assert_inv06` macro aborts if violated | Log shows no abort at assertion step | ❌ Wave 0 |
| INV-07 | Workbook exists with correct sheets; KEY leftmost; UF blue headers | Manual: open `qc/19_raw_inventory.xlsx` in Excel | Visual inspection | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** Submit program in SAS batch; verify log shows 0 ERRORs and assertions pass; open workbook for spot-check
- **Per wave merge:** Full program submission + open workbook + verify `qc/19_raw_files.csv` exists and contains md3 row
- **Phase gate:** Full log review + workbook all-tabs inspection + CSV row count before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `sas/19_raw_dir_inventory.sas` — main deliverable; does not exist yet
- [ ] `qc/19_raw_inventory.xlsx` — produced by the program
- [ ] `qc/19_raw_files.csv` — Phase 20 handoff; produced by the program

---

## Code Examples

### Verified: Program Header Pattern (from 16_raw_inventory.sas and 17_summary_stats_by_domain.sas)

```sas
/* Source: sas/16_raw_inventory.sas lines 30-31 */
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
options validvarname=v7 validmemname=extend nofmterr msglevel=i;
/* Phase 19 addition — must come before any import: */
options nosyntaxcheck noerrorabend;
%include "&sas_path.\macros_raw_import.sas";
```

### Verified: %fail_out Pattern (from 16_raw_inventory.sas lines 47-52)

```sas
%macro fail_out(msg=);
  %put ERROR: &msg;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;
```

Note: Phase 19 must extend `%fail_out` to also close `ods excel` if it is open (same as Phase 17 R5 fix). Add `ods excel close;` before `%restore_log;`.

### Verified: ODS Excel UF Colors Pattern (from 17_summary_stats_by_domain.sas)

```sas
/* Source: sas/17_summary_stats_by_domain.sas — ODS Excel with UF blue headers */
ods excel options(sheet_name='KEY');
/* Column header color #0021A5 applied via style= or PROC TEMPLATE override */
```

### Verified: SELECT COUNT(*) INTO Pattern (project-wide — STATE.md)

```sas
/* Source: STATE.md established decisions — no &SQLOBS anywhere */
%let n_bad = 0;
proc sql noprint;
  select count(*) into :n_bad trimmed
  from work.files_out
  where status not in ('profiled', 'listed-not-profiled', 'read-failed');
quit;
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| X statement for shell commands | FILENAME PIPE | Established Phase 16 | PIPE returns output; X statement cannot |
| PROC MEANS for missingness | One-pass DATA step with arrays | Locked D-03 | Counts -999 and NULL sentinels correctly |
| Inner join for FAMILIES assertion | FULL JOIN with coalesce | Locked D-04 | Prevents silent undercount |
| Single "unreadable" status | Three statuses: profiled / listed-not-profiled / read-failed | Locked D-06 | Makes locked-or-corrupt files visible |

---

## Open Questions

1. **COM prefix scouting result**
   - What we know: `COM` is the proposed prefix for dCDT clock features; it is broad and could capture COMORBID*, COMMENT*, COMPLICATION* columns
   - What's unclear: What column names actually starting with COM exist across all raw files that are NOT already captured by `COMP10_` or `complication_sum`? Do dCDT columns share a longer common prefix (e.g., `CLOCK_`)?
   - Recommendation: The plan's Wave 0 task must include a scouting query against the VARIABLES output of any earlier inventory (e.g., Phase 16/18 results) or defer to an early program section that prints all COM* column names before locking DATALINES. This result must be documented before the FAMILIES DATALINES block is coded.

2. **SAS7BDAT files under raw**
   - What we know: The context decision allows either `dictionary.columns` profiling or `listed-not-profiled` for any SAS7BDAT files found under raw
   - What's unclear: Whether any SAS7BDAT files actually exist under `raw` (Phase 16/18 programs only reference CSV and XLSX)
   - Recommendation: The import loop should attempt to assign a libname; succeed = profile via dictionary.columns; fail = listed-not-profiled. This is low-risk given the established discretion.

3. **INV-07 REQUIREMENTS.md note about FAMILIES sheet**
   - What we know: CONTEXT.md notes "INV-07 as written lists FILES, SHEETS, VARIABLES, KEY_COLUMNS, RECONCILIATION — the FAMILIES sheet (added by D-04) and KEY sheet must be reflected there before Phase 19 plans execute; update REQUIREMENTS.md accordingly"
   - What's unclear: REQUIREMENTS.md INV-07 currently lists only the original five sheets; it does not mention FAMILIES or KEY
   - Recommendation: Plan Wave 0 must include a task to update REQUIREMENTS.md INV-07 to add FAMILIES and KEY sheets before any implementation task runs. This is a documentation gate, not a blocker.

---

## Project Constraints (from CLAUDE.md)

| Directive | Applies To |
|-----------|------------|
| SAS 9.4M8 on Windows; session encoding is NOT UTF-8 | All SAS code — ASCII only in program text |
| Read-only on master_data_1..8.sas7bdat and everything under raw\master | No write operations on source files |
| No PHI in git: .gitignore excludes *.sas7bdat, *.xlsx, *.csv, data/ tree | `qc/19_raw_inventory.xlsx` and `qc/19_raw_files.csv` go to P: path only; never committed |
| Repo on local disk, not P: drive | sas/19_raw_dir_inventory.sas is in C:\Master_Renamed_same_format_accross\sas\ |
| UF colors (#0021A5, #FA4616) on visual deliverables | ODS Excel column headers use #0021A5 |
| KEY sheet leftmost in workbooks | Enforced by ODS Excel sheet_name= call order (KEY first) |
| Single 99_run_all.sas runs start-to-finish | Phase 19 defers wiring to Phase 21; program must be self-contained |

---

## Sources

### Primary (HIGH confidence)
- `sas/16_raw_inventory.sas` — all utility macro patterns (%fail_out, %route_log, %restore_log, %check_dir, key-detection block)
- `sas/macros_raw_import.sas` — %import_csv, %import_xlsx, %ensure_dslist (exact interface and behavior)
- `sas/00_config.sas` — all path macro variables (&raw_path, &qc_path, &logs_path, &g_path, &sas_path)
- `sas/17_summary_stats_by_domain.sas` — ODS Excel KEY-first sheet ordering pattern, UF color header approach
- `.planning/phases/19-raw-directory-inventory/19-CONTEXT.md` — all locked decisions D-01 through D-07

### Secondary (MEDIUM confidence)
- `.planning/phases/18-supplemental-raw-inventory/18-CONTEXT.md` — Phase 18 pitfall carry-forwards confirmed against Phase 16 code

### Tertiary (LOW confidence)
- None — all findings verified against project source code

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components exist in project codebase; no new libraries
- Architecture: HIGH — all patterns verified against existing working programs
- Pitfalls: HIGH — all pitfalls either locked in CONTEXT.md decisions or observed in prior phase code

**Research date:** 2026-09-23
**Valid until:** 2026-12-23 (stable — SAS 9.4M8 and Windows certutil are not fast-moving)
