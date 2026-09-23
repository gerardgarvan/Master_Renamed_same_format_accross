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
the FAMILIES sheet (added by D-05) and KEY sheet must be reflected there before Phase 19
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
- Missingness is computed in one pass per file:
  - PROC MEANS with `NMISS` option for numeric columns (counts true SAS missing `.`)
  - A single DATA step scanning all character columns in one read for char vars
  Not one query per variable — that would be prohibitively slow on r2 (3,987 cols).
- **Sentinel separation (two columns, not one):** Report `pct_missing` (true SAS
  missing only, as produced by NMISS / char-scan) and `pct_sentinel` (values that
  are `-999` for numerics or the literal string `NULL` for character columns)
  as separate VARIABLES columns. Rationale:
  - PROC MEANS NMISS does not count `-999`, so folding sentinels into
    `pct_missing` would silently understate dCDT missingness.
  - `-999` may be a legitimate non-missing value in files outside dCDT;
    applying a recode universally would overstate missingness there.
  - Two columns keep the raw count transparent without making a silent
    recoding choice. The consumer decides how to treat sentinels.
  - `pct_sentinel` is counted in the same pass: the numeric DATA step or
    PROC MEANS extension counts `n(var = -999)` alongside NMISS; the char
    DATA step counts `upcase(strip(var)) = 'NULL'` alongside blank counts.
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
  table with a separate exclude flag, use longest-match assignment. Map the
  longer specific prefix first, then the shorter general one. Example:
  - `COMP10_` → `complications` (longer, matched first)
  - `complication_sum` → `complications` (exact match row)
  - `COM` → `dCDT` (shorter, matched only when neither longer rule fires)
  This is simpler to audit than an exclude flag: every column's family
  assignment is deterministic and visible by reading the DATALINES rows in
  order of decreasing prefix length.
- Families identified in Phase 18 (minimum list; extend as needed):
  - `COMP10_` / `complication_sum` → complications
  - `COM` → dCDT clock features
  - `LINUS` → LINUS columns
  - (Others discovered during scouting of r2 headers can be added)
- Columns matching no prefix go in `unassigned` per source file.
- **Assertion (correct implementation):** After building the FAMILIES dataset,
  compute:
  ```sas
  proc sql noprint;
    select count(*) into :n_bad trimmed
    from (
      select f.source_file
      from (select source_file, sum(n_cols) as fam_total from families
            group by source_file) f
      join  (select source_file, count(*) as var_total from variables
            group by source_file) v
        on f.source_file = v.source_file
      where f.fam_total ne v.var_total
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

### D-06: Unreadable files (listed-not-profiled)
- **D-06:** Files with extensions outside {sas7bdat, csv, xlsx, xls} (e.g.,
  PDF, DOCX, ZIP) are listed in FILES with status = `listed-not-profiled`.
  They receive a checksum (certutil handles any file type) but no row/column
  counts and no VARIABLES rows.
- INV-06 assertion: total files in FILES = (profiled count) + (listed-not-profiled
  count); zero files of unknown status.

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
- `PROC MEANS NMISS` for numeric missingness; single DATA step for char —
  not one query per variable on wide files

### Integration Points
- Reads: everything under `&raw_path` (recursive, read-only)
- Writes: `qc/19_raw_inventory.xlsx` (ODS Excel)
- Writes: `logs/19_raw_dir_inventory.log`
- Does NOT write to any `g.*` dataset
- Does NOT read `g.analysis_base` or `g.master_data_merged` — standalone scan
- **Machine-readable FILES output for Phase 20:** In addition to the Excel
  workbook, program 19 writes `qc/19_raw_files.csv` (or `work.inv_files` saved
  via PROC EXPORT) containing the FILES dataset — path, filename, checksum, and
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
- Sentinel values (`-999` numeric, literal `NULL` char) are NOT the same as
  true SAS missing: NMISS does not count `-999`; blank-test does not catch
  `NULL`. Report as `pct_sentinel` separate from `pct_missing` (see D-03).
  Do not recode sentinels — that makes a silent choice the consumer should make.
- `COM` prefix includes complication variables (`COMP10_*`, `complication_sum`)
  which are NOT dCDT clock features. Use longest-match DATALINES (D-04):
  map `COMP10_` and `complication_sum` to `complications` before mapping
  `COM` to `dCDT`, so the longer match fires first.
- FAMILIES assertion: do NOT use `INTO :check` with `GROUP BY` (captures only
  first row) and do NOT use `&SQLOBS`. Use `count(*) into :n_bad trimmed` over
  the joined mismatch subquery (see D-04 for correct pattern).

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
