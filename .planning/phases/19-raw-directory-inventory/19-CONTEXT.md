# Phase 19: Raw Directory Inventory — Context

**Gathered:** 2026-09-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a complete, checksummed, variable-level inventory of every file under
`P:\PeCAN Master Data\Gerard\raw` (the `&raw_path` tree, recursive).

Scope is `raw` only. `Master_Renamed_same_format_accross` is explicitly out of scope.
Output: `qc/19_raw_inventory.xlsx` with sheets FILES, SHEETS, VARIABLES,
KEY_COLUMNS, RECONCILIATION, FAMILIES, KEY (KEY leftmost).

Note: INV-07 as written lists FILES, SHEETS, VARIABLES, KEY_COLUMNS, RECONCILIATION —
the FAMILIES sheet (added by D-04) and KEY sheet must be reflected there before Phase 19
plans execute; update REQUIREMENTS.md accordingly.

</domain>

<decisions>
## Implementation Decisions

### D-01: SHA-256 mechanism
- **D-01:** Compute checksums via `certutil -hashfile` called through a
  `FILENAME ... PIPE` statement (not an `X` statement, which cannot return
  output to SAS). Paths must be double-quoted inside the pipe command because
  file names under `raw` contain spaces.
- **Parse guard:** Some Windows builds print the hash with spaces between byte
  pairs. Strip all spaces from the certutil output line before testing for
  64 consecutive hex characters; otherwise the parse finds no hash line on
  those machines.
- Dependency: `XCMD` must be enabled in the SAS batch session. The runner
  (`99_run_all.sas`) will rely on XCMD too (RUN-01), so this is a shared
  constraint, not a Phase 19-specific one. Document it in the program header.

### D-02: raw\master scope and presence checks
- **D-02:** Every file under `raw` (including `raw\master`) receives full
  profiling: a fresh checksum, row/column counts, and variable-level detail.
  No caching from Phase 1 — the inventory must reflect what is on disk now.
  The `raw\master` files are original extracts (CSVs + one XLSX), handled by
  existing `%import_csv` / `%import_xlsx` macros.
- **D-02b (presence assertion):** Before profiling, the program checks that
  each of the eight named known-master extracts is present under `raw\master`.
  If any is absent or renamed, `%abort cancel` fires. New or extra files in
  `raw\master` do NOT abort; they appear as NEW in RECONCILIATION. This
  per-file check follows PCM-T-12 (enumerate each expected item individually,
  do not rely on a count).
  - The md3 source CSV matters most: PID-01 (Phase 20) depends on its
    checksum appearing in the INV-01 record. Treat a missing md3 source as
    a hard blocker.

### D-03: Variable profiling — all columns, one-pass missingness, sentinel separation
- **D-03:** Every column in every readable file appears individually in the
  VARIABLES sheet (satisfies INV-03 literally; 40,000+ rows is well within
  Excel's 1,048,576-row limit).
- **Missingness — one DATA step per file, not PROC MEANS:** Use a single DATA
  step with a `_numeric_` array and a `_character_` array, reading every row
  of the imported dataset in one pass. For each variable accumulate:
  - `n_missing`: count of true SAS missing (`.` for numeric; `' '` for char)
  - `n_sentinel`: count of `-999` for numerics; `upcase(strip(var)) = 'NULL'`
    for character columns
  PROC MEANS is not used for this step — it has no option to count `-999`,
  and adding it would still require a second pass for character sentinels.
  One DATA step handles all four counts in a single read; it is correct for
  r2's 3,987 columns and produces no per-variable queries.
- **Sentinel separation (two columns, not one):** Report `pct_missing` (true
  SAS missing only) and `pct_sentinel` (`-999` / `NULL`) as separate VARIABLES
  columns. Rationale:
  - `-999` is not counted by NMISS, so folding sentinels into `pct_missing`
    would silently understate dCDT missingness.
  - `-999` may be legitimate outside dCDT; a universal recode would overstate
    missingness there.
  - Two columns keep the raw counts transparent; the consumer decides how to
    treat sentinels.
- INV-04 key-column detection sweeps every column name regardless of family,
  because a key column could sit inside a wide family.
- **Type note (KEY sheet):** Column type in VARIABLES reflects the type as
  imported by SAS (PROC IMPORT guessingrows=max for CSV; XLSX engine for
  workbooks), not the source system type. Note this in the KEY sheet legend
  to avoid confusion when, for example, ENCRYPTED_MRN imports as numeric in
  one file and character in another.

### D-04: FAMILIES sheet — DATALINES-defined prefix lookup with longest-match
- **D-04:** A FAMILIES sheet summarises known wide-column families. Families
  are defined in a DATALINES lookup table with columns (prefix, family_name)
  in the program, following the concept_decisions.csv pattern: the program
  applies exactly what is listed; a new family is a one-line edit.
- **Exclusion mechanism — longest-match-wins:** Rather than a plain prefix
  table with a separate exclude flag, use longest-match assignment. The lookup
  table is sorted by descending prefix length in code (not by DATALINES row
  order, which is fragile to one-line insertions) before matching. Example
  assignments after sorting:
  - `COMP10_` → `complications` (length 7, matched first)
  - `complication_sum` → `complications` (exact-match row, also length > 3)
  - `COM` → `dCDT` (length 3, matched only when no longer prefix fires)
  Every column name is uppercased before comparison so that `complication_sum`
  (lowercase) matches `COMPLICATION_SUM` in the lookup without a separate row.
- **COM scouting step (before locking DATALINES):** `COM` is broad — it would
  also capture `COMORBID*`, `COMMENT*`, `COMPLICATION*` (without `10_`), and
  anything else starting with those three letters. Before the planner locks the
  DATALINES prefix list, the researcher must:
  1. List every column name across all files that starts with `COM` (case-
     insensitive) and is not already captured by a longer prefix in the list.
  2. Confirm by inspection that the residual set is dCDT clock columns.
  3. If the dCDT columns share a longer common prefix (e.g., `CLOCK_`), use
     that instead of `COM` and remove `COM` from the lookup.
  This scouting result must be recorded in the plan before coding begins.
- Families identified in Phase 18 (minimum seed; extend after scouting):
  - `COMP10_` / `complication_sum` → complications
  - `COM` → dCDT clock features (subject to scouting result above)
  - `LINUS` → LINUS columns
- Columns matching no prefix go in `unassigned` per source file.
- **Assertion (correct implementation — full join):** After building the
  FAMILIES dataset, use a FULL JOIN so that a file with VARIABLES rows but
  no FAMILIES rows (or the reverse) is not silently dropped by an inner join:
  ```sas
  proc sql noprint;
    select count(*) into :n_bad trimmed
    from (
      select coalesce(f.source_file, v.source_file) as src
      from (select source_file, sum(n_cols) as fam_total from families
            group by source_file) f
      full join
           (select source_file, count(*) as var_total from variables
            group by source_file) v
        on f.source_file = v.source_file
      where coalesce(f.fam_total, 0) ne coalesce(v.var_total, 0)
    );
  quit;
  ```
  Then call `%abort cancel` inside a named macro when `&n_bad > 0`.
  Do NOT use `&SQLOBS` (ruled out in STATE.md) and do NOT use `INTO :check`
  with `GROUP BY` (captures only the first row).
- Each FAMILIES row reports: family_name, source_file, n_cols,
  pct_missing_min, pct_missing_median, pct_missing_max (not median alone —
  a median can hide a block of fully empty columns within a wide family).

### D-05: Excel output — ODS Excel, KEY sheet first
- **D-05:** Output via ODS Excel (established in Phase 17 for UF colors and
  sheet control). Sheet order is controlled by the order of `ods excel
  options(sheet_name=)` calls; write KEY first so it is leftmost in the
  workbook (INV-07). UF blue (#0021A5) column headers throughout.
- **Fallback if ODS Excel is too slow on VARIABLES:** ODS Excel writes the
  entire workbook when it closes, so VARIABLES cannot be swapped to the XLSX
  libname engine within the same file — a post-close XLSX write to the same
  path would append VARIABLES as the last sheet and likely drop ODS styling.
  If the fallback is ever needed, write VARIABLES to a separate workbook
  (`qc/19_raw_variables.xlsx`) and keep all other sheets in the primary
  workbook (`qc/19_raw_inventory.xlsx`). This is a separate-file split, not
  a drop-in swap; the plan should not assume otherwise.

### D-06: File status — three categories, not two
- **D-06:** Every file discovered in the directory traversal lands in exactly
  one of three statuses in the FILES sheet:
  - `profiled` — readable data file (csv, xlsx, xls, sas7bdat) that imported
    successfully and received row/column counts and VARIABLES rows
  - `listed-not-profiled` — extension outside the readable set (pdf, docx,
    zip, etc.); receives a checksum but no data profiling
  - `read-failed` — extension is in the readable set but import failed (file
    locked, corrupt, Excel `~$` temp file, or any other import error); receives
    a checksum and a `fail_reason` column with the error message; no row/column
    counts or VARIABLES rows
  `read-failed` is necessary because a locked or corrupt file is neither
  `listed-not-profiled` (extension says it should be readable) nor silently
  skipped. Without this status, the only choices are aborting the whole
  inventory or producing a silent undercount.
- **Import error handling:** Wrap each import attempt in a macro that uses
  `%sysfunc(open(...))` or a condition on `%sysfunc(exist(work.&dsname))` after
  the import to detect failure; set status and reason without `%abort cancel`.
  The program aborts only if a required file (see D-02b presence check) fails
  to import.
- **INV-06 assertion (three terms):** After all files are processed:
  ```
  n_profiled + n_listed_not_profiled + n_read_failed = n_total_files
  ```
  Assert this with `select count(*) into :n_bad trimmed` on any FILES row
  whose status is not in (`profiled`, `listed-not-profiled`, `read-failed`);
  abort if `&n_bad > 0`.

### D-07: RECONCILIATION sheet — known-file list
- **D-07:** Known files are the eight md1-md8 master extracts (raw\master)
  and the nine Phase 18 supplemental files (r1-r9). Files in raw that match
  a known entry are flagged `known`; all others are flagged `NEW`.
  The known-file list is hardcoded in a DATALINES block — same DATALINES
  pattern as the FAMILIES lookup (D-04) — so it is version-controlled and
  auditable.

### Claude's Discretion
- Directory traversal implementation: `FILENAME pipe "dir /s /b &raw_path"` or
  equivalent Windows command; parse into a FILES dataset before any import
- Macro structure (one macro per file type vs generalised loop over dslist)
- Whether the SHA-256 PIPE call is wrapped in a macro or open-coded per file
- Report ordering within each sheet (FILES sorted by path; VARIABLES sorted
  by file then variable position; KEY_COLUMNS sorted by file then column name)
- Whether SAS7BDAT files under raw (if any are found) are profiled via
  `dictionary.columns` or skipped with a `listed-not-profiled` status;
  use `dictionary.columns` if the libname can be assigned, otherwise
  `listed-not-profiled`

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Pipeline infrastructure
- `sas/00_config.sas` — defines `&raw_path`, `&g_path`, `&qc_path`,
  `&logs_path`, `&sas_path`; `%include` this first
- `sas/macros_raw_import.sas` — `%import_csv`, `%import_xlsx`,
  `%ensure_dslist`; include verbatim, do not redefine
- `sas/16_raw_inventory.sas` — Phase 16 program; reference for key-detection
  pattern, `%fail_out` macro, `%assert_base`, log-routing macros, and
  PCM compliance header style

### Prior phase context
- `.planning/phases/18-supplemental-raw-inventory/18-CONTEXT.md` —
  supplemental file list (r1-r9), family descriptions, PCM-T-12/T-13 traps,
  known pitfalls for wide-file import; read before coding key detection
- `.planning/REQUIREMENTS.md` §Raw Directory Inventory — INV-01 through INV-07
  (note: FAMILIES sheet must be added to INV-07 before planning locks)

### Decision log
- `docs/DECISIONS.md` — no new PCM-D entries needed for Phase 19 itself;
  PCM-D-17/D-18 (Phase 20) are recorded here and Phase 19 must not touch them

### No external ADRs — requirements fully captured in decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/macros_raw_import.sas` — `%import_csv` (PROC IMPORT, guessingrows=max)
  and `%import_xlsx` (XLSX libname, enumerate sheets via dictionary.tables,
  copy via call execute); use without modification
- `sas/16_raw_inventory.sas` — `%fail_out`, `%check_dir`, `%route_log`,
  `%restore_log`, `%assert_base`, key-detection block; all reusable as-is
- `sas/17_summary_stats_by_domain.sas` — ODS Excel with UF color headers;
  `sheet_name=` ordering pattern; reference for KEY-first sheet ordering

### Established Patterns
- `%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas"` first
- `options validvarname=v7 validmemname=extend nofmterr msglevel=i;` second
- `%include "&sas_path.\macros_raw_import.sas";` third
- `libname g "&g_path";` and `%assert_base` before any `g.*` reference
- All `%abort cancel` inside named macros only (PCM-R-05)
- No bare open-code `%IF`; no `%PUT` with apostrophes or embedded semicolons
- `dictionary.columns.type` is char `'char'`/`'num'` (PCM-T-13); never compare
  to numeric 1/2
- One DATA step with `_numeric_` and `_character_` arrays for missingness and
  sentinel counting — not PROC MEANS (cannot count -999), not one query per variable

### Integration Points
- Reads: everything under `&raw_path` (recursive, read-only)
- Writes: `qc/19_raw_inventory.xlsx` (ODS Excel)
- Writes: `logs/19_raw_dir_inventory.log`
- Does NOT write to any `g.*` dataset
- Does NOT read `g.analysis_base` or `g.master_data_merged` — standalone scan
- **Machine-readable FILES output for Phase 20:** In addition to the Excel
  workbook, program 19 writes `qc/19_raw_files.csv` containing the FILES
  dataset — path, filename, checksum, and
  status columns. This is not a `g.*` write. Phase 20 (PID-01) reads this CSV
  to verify the md3 source checksum; it does NOT parse the styled Excel
  workbook, which is fragile to ODS type-guessing and formatting on re-import.
  The Excel workbook remains the human-facing deliverable; the CSV is the
  machine-readable handoff.

### Known Pitfalls (carry-forward from Phase 18)
- Paths with spaces: double-quote in all pipe/certutil calls
- `dictionary.columns.type` is char ('char'/'num'), not numeric — PCM-T-13
- Key detection must enumerate ALL naming variants of PRECEDE_STUDY_ID,
  ENCRYPTED_MRN, ENCRYPTED_ENCOUNTER (spaces vs underscores, mixed case,
  positional VARnn from XLSX engine) — PCM-T-12; sweep every column
- r2 has 3,987 columns and 14,807 rows — one-pass missingness is mandatory
- Sentinel values (`-999` numeric, literal `NULL` char) are NOT SAS missing:
  PROC MEANS NMISS does not count `-999`; blank-test does not catch `NULL`.
  Use the one-DATA-step approach (D-03): `_numeric_` array counts both `.`
  and `-999` in one pass; `_character_` array counts both blank and `'NULL'`.
  Report as `pct_sentinel` separate from `pct_missing`; do not recode.
- `COM` is broader than dCDT — `COMORBID*`, `COMMENT*`, `COMPLICATION*`
  (without `10_`) would all land there under a naïve prefix match. Scout all
  `COM*` columns first (D-04 scouting step); sort the lookup by descending
  prefix length in code; upcase both sides before matching.
- FAMILIES assertion must use a FULL JOIN with `coalesce(..., 0)` so that a
  file with VARIABLES rows but no FAMILIES rows is not dropped. Do NOT use
  an inner join, `INTO :check` with `GROUP BY`, or `&SQLOBS` (see D-04).
- Import failures on readable-extension files are `read-failed`, not silently
  dropped and not cause for aborting the whole inventory (see D-06). An inner
  check on `%sysfunc(exist(work.&dsname))` after each import detects failure.

</code_context>

<specifics>
## Specific Ideas

- PIPE command for certutil: `filename ck pipe "certutil -hashfile ""&fpath"" SHA256"` — two double-quotes around the path to handle embedded spaces; read each output line with INFILE, compress/strip spaces, then test `lengthn(compressed_line) = 64 and notxdigit(compressed_line) = 0` to identify the hash line (guards against Windows builds that print spaces between byte pairs)
- KEY sheet content: column-by-column legend (column name, sheet it appears in, description, units/notes) matching the Phase 17 DATA_DICTIONARY KEY sheet style (UF blue header, leftmost position). Include a note that `type` in VARIABLES reflects the SAS-imported type, not the source system type.
- Program also writes `qc/19_raw_files.csv` via PROC EXPORT from the FILES work dataset before ODS Excel opens — this is the Phase 20 handoff file; write it early so a crash during ODS export does not block Phase 20.

</specifics>

<deferred>
## Deferred Ideas

- Wiring `19_raw_dir_inventory.sas` into `99_run_all.sas` — Phase 21 (RUN-01)
- r7/r8 gap-fill joining (2022 files) — still gated on PCM-D-16 resolution;
  Phase 19 inventory will include r7/r8 in FILES and VARIABLES but makes no
  join decision
- PCM-D-15 extension-column gap-fill wiring — deferred to v2.1 pending PID-07
  result (Phase 20)

</deferred>

---

*Phase: 19-raw-directory-inventory*
*Context gathered: 2026-09-23*
