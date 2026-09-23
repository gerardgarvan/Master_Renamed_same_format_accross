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

### D-03: Variable profiling — all columns, one-pass missingness
- **D-03:** Every column in every readable file appears individually in the
  VARIABLES sheet (satisfies INV-03 literally; 40,000+ rows is well within
  Excel's 1,048,576-row limit).
- Missingness is computed in one pass per file:
  - PROC MEANS with `NMISS` option for numeric columns
  - A single DATA step scanning all character columns in one read for char vars
  Not one query per variable — that would be prohibitively slow on r2 (3,987 cols).
- INV-04 key-column detection sweeps every column name regardless of family,
  because a key column could sit inside a wide family.

### D-04: FAMILIES sheet — DATALINES-defined prefix lookup
- **D-04:** A FAMILIES sheet summarises known wide-column families. Families
  are defined in a DATALINES lookup table (prefix, family_name) in the program,
  following the concept_decisions.csv pattern: the program applies exactly what
  is listed; a new family is a one-line edit to the DATALINES block.
- Families identified in Phase 18 (minimum list; extend as needed):
  - `COM` prefix → dCDT clock features (EXCLUDE `COMP10_*` and
    `complication_sum`, which are complication variables, not clock features)
  - `LINUS` prefix → LINUS columns
  - (Others discovered during scouting of r2 headers can be added)
- Columns matching no prefix go in an `unassigned` row per source file.
- **Assertion:** FAMILIES column counts must sum to the VARIABLES row count
  for each file. If they diverge, `%abort cancel` fires — the summary cannot
  silently drop columns.
- Each FAMILIES row reports: family_name, source_file, n_cols,
  pct_missing_min, pct_missing_median, pct_missing_max.

### D-05: Excel output — ODS Excel, KEY sheet first
- **D-05:** Output via ODS Excel (established in Phase 17 for UF colors and
  sheet control). Sheet order is controlled by the order of `ods excel
  options(sheet_name=)` calls; write KEY first so it is leftmost in the
  workbook (INV-07). UF blue (#0021A5) column headers throughout.
- ODS Excel can be slow on a 40,000-row VARIABLES sheet. If that becomes a
  problem, the VARIABLES data is written using the XLSX libname engine instead
  and then the other sheets use ODS Excel — that is a targeted fallback, not a
  full redesign.

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
- Phase 20 (PID-01) reads the INV-01 checksum record for the md3 source CSV
  from `19_raw_inventory.xlsx`; the FILES sheet must include a checksummed row
  for that file before Phase 20 can run

### Known Pitfalls (carry-forward from Phase 18)
- Paths with spaces: double-quote in all pipe/certutil calls
- `dictionary.columns.type` is char ('char'/'num'), not numeric — PCM-T-13
- Key detection must enumerate ALL naming variants of PRECEDE_STUDY_ID,
  ENCRYPTED_MRN, ENCRYPTED_ENCOUNTER (spaces vs underscores, mixed case,
  positional VARnn from XLSX engine) — PCM-T-12; sweep every column
- r2 has 3,987 columns and 14,807 rows — one-pass missingness is mandatory
- Two missing sentinels: `-999` in dCDT numerics, literal `NULL` in
  Excel-sourced char columns — treat both as missing in pct_missing
- `COM` prefix includes complication variables (`COMP10_*`, `complication_sum`)
  which are NOT dCDT clock features; the FAMILIES DATALINES block must
  exclude these prefixes explicitly

</code_context>

<specifics>
## Specific Ideas

- PIPE command for certutil: `filename ck pipe "certutil -hashfile ""&fpath"" SHA256"` — two double-quotes around the path to handle embedded spaces; read with an INFILE over the PIPE fileref and pick the line that is 64 hex chars
- FAMILIES assertion: `proc sql; select file, sum(n_cols) into :check trimmed from families group by file having calculated check ne var_count; quit;` — if rows returned, fire `%abort cancel`
- KEY sheet content: column-by-column legend (column name, sheet it appears in, description) matching the Phase 17 DATA_DICTIONARY KEY sheet style (UF blue header, leftmost position)

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
