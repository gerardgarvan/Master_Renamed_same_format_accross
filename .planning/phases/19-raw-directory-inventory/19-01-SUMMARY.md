---
phase: 19-raw-directory-inventory
plan: 01
subsystem: raw-inventory
tags: [sas, inventory, checksums, profiling, xlsx, families, reconciliation]
dependency_graph:
  requires: []
  provides:
    - sas/19_raw_dir_inventory.sas
    - .planning/REQUIREMENTS.md (INV-03/06/07 updated)
  affects:
    - Phase 20 (PID-01 reads qc/19_raw_files.csv for md3 checksum)
tech_stack:
  added: []
  patterns:
    - certutil SHA-256 via FILENAME PIPE with compress(line,' ') parse guard
    - one-pass missingness+sentinel DATA step with explicit temporary array sizes
    - FAMILIES FULL JOIN assertion with coalesce
    - three-status file model (profiled / listed-not-profiled / read-failed)
    - ODS Excel KEY-first sheet ordering
key_files:
  created:
    - sas/19_raw_dir_inventory.sas
  modified:
    - .planning/REQUIREMENTS.md
decisions:
  - D-01 certutil PIPE with compress(line,' ') parse guard for space-padded Windows builds
  - D-06 &syserr le 4 success threshold (not = 0) to handle transcoding warnings on master CSVs
  - B-05 FOPEN via fileref always (never pass path string directly)
  - R2-W-02 upcase both sides of full_path MASTER check for Windows capitalisation variants
metrics:
  duration: ~30 minutes
  completed: 2026-09-23
  tasks_completed: 2
  files_created: 1
  files_modified: 1
---

# Phase 19 Plan 01: Raw Directory Inventory Program Summary

**One-liner:** Complete 14-section SAS inventory pipeline producing a checksummed, variable-level scan of all files under &raw_path with seven-sheet ODS Excel workbook and machine-readable CSV handoff for Phase 20.

---

## What Was Built

### Task 1 (committed 8df6c74): Update REQUIREMENTS.md INV-03/06/07

- **INV-07** updated to list all seven sheets in order: KEY (legend), FILES, SHEETS, VARIABLES, KEY_COLUMNS, RECONCILIATION, FAMILIES
- **INV-06** updated to three-term form: n_profiled + n_listed_not_profiled + n_read_failed = n_total_files; read-failed covers any readable-extension file whose import failed
- **INV-03** updated to explicitly name pct_missing and pct_sentinel as separate columns

### Task 2 (committed 0238925): Write sas/19_raw_dir_inventory.sas

Complete program with 14 numbered sections implementing all locked decisions D-01 through D-07.

---

## Program Structure

| Section | Purpose |
|---------|---------|
| 0 | Header, %include 00_config.sas, options nosyntaxcheck noerrorabend |
| 1 | %route_log, %restore_log, %fail_out (with ods excel close), %check_dir |
| 2 | Preconditions: check logs/qc/raw dirs; no g.* references |
| 3 | dir /s /b /a-d traversal; fileref+FINFO for fsize/fdate (B-05) |
| 4 | D-02b md1-md8 presence assertion with upcase MASTER path filter (R2-W-02) |
| 5 | certutil SHA-256 per file; compress(line,' ') parse guard (D-01) |
| 6 | Import loop: &syserr le 4 threshold (B-02); syswarningtext (R2-S-01); syscc reset |
| 7 | One-pass missingness+sentinel; explicit temp array sizes (B-03); B04-NOSTOP-VERIFIED |
| 8 | Key-column detection: compress(upcase,' _-') normalization; UNENC_MRN/UNENC_ENCOUNTER |
| 9 | FAMILIES longest-match; COM_SCOUT DATA _null_ (R2-B-03); FULL JOIN assertion |
| 10 | RECONCILIATION DATALINES with 17 known files (md1-md8 + r1-r9) |
| 11 | assert_inv06 three-term; assert_masters_profiled (W-04) |
| 12 | PROC EXPORT 19_raw_files.csv before ODS Excel opens |
| 13 | ODS Excel: KEY first, 7 sheets, styles.pearl |
| 14 | fileexist() without double-quotes inside %sysfunc() (B-06); %restore_log |

---

## Bugs Fixed (from REVIEWS.md)

| ID | Fix | Location |
|----|-----|----------|
| B-01 | Section 4 DATALINES uses exact Phase 1 CSV names; xlsx variant not required | Section 4 |
| B-02 | &syserr le 4 (not = 0) as import success threshold; syswarningtext captured | Section 6 |
| B-03 | Explicit temp array sizes with max(...,1) guard; never {*} | Section 7 |
| B-04 | No stop; in main loop body; B04-NOSTOP-VERIFIED comment present | Section 7 |
| B-05 | FOPEN via fileref: filename('_fr_', path) / fopen('_fr_') / filename('_fr_') | Section 3 |
| B-06 | fileexist(&qc_path.\file) with no double-quotes inside %sysfunc() | Section 14 |
| R2-B-01 | No =: in PROC SQL; substr(upcase(compress(...))) used instead | Section 8 |
| R2-B-02 | &dsname._ period terminates macro var name before underscore in XLSX copy | Section 6 |
| R2-B-03 | COM_SCOUT uses DATA _null_ PUT to log (not PROC PRINT to ODS) | Section 9 |

## Correctness Issues Fixed (from REVIEWS.md)

| ID | Fix | Location |
|----|-----|----------|
| W-01 | UNENC_MRN distinct from ENCRYPTED_MRN; UNENC_ENCOUNTER for ENCOUNTERID | Section 8 |
| W-02 | compress(upcase,' _-') normalization; var_type restriction removed | Section 8 |
| W-03 | sheet_name column in work.variables for XLSX sheet distinction | Section 7 |
| W-04 | assert_masters_profiled macro aborts if any md1-md8 did not profile | Section 11b |
| R2-W-01 | ENCOUNTERID -> UNENC_ENCOUNTER; label ENCRYPTEDENCOUNTER -> ENCRYPTED_ENCOUNTER | Section 8 |
| R2-W-02 | upcase both sides of full_path MASTER check for Windows folder capitalisation | Section 4 |
| R2-S-01 | &syswarningtext (not &sysmsg) for transcoding warning text | Section 6 |
| R2-S-02 | %let syscc = 0; in both read-failed branch and warning-only branch | Section 6 |
| R2-S-03 | coalesce(nobs,0) guard in pct_missing/pct_sentinel calculation | Section 7 |

---

## Deviations from Plan

None — plan executed exactly as written. All 14 sections implemented per PLAN.md specifications.

---

## Known Stubs

None. All data flows are wired. The COM scouting section produces log output (COM_SCOUT: lines) that must be reviewed before treating FAMILIES sheet as final — this is by design (documented in D-04), not a stub.

---

## Self-Check

- `sas/19_raw_dir_inventory.sas` exists: confirmed (1,115 lines)
- Task 1 commit 8df6c74 exists in git log
- Task 2 commit 0238925 exists in git log
- All acceptance criteria grep checks passed (verified above)
- No &SQLOBS in program (grep returns 0)
- No =: operator in program (grep returns 0)
- ods excel close appears 2 times (in %fail_out and at end of Section 13)
- %let syscc = 0 appears 2 times (warning branch and read-failed branch)
- B04-NOSTOP-VERIFIED appears 2 times (CSV dataset and XLSX sheet profiling)

## Self-Check: PASSED
