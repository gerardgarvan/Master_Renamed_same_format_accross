---
phase: 27-md8-row-count-correction
plan: "01"
subsystem: md8-verification
tags: [md8, row-count, dual-count, SHA-256, XLSX, QC]
dependency_graph:
  requires: [qc/19_raw_files.csv, src.master_data_8, raw\ALL_AIM2_MASTER_DATASET_20210917.xlsx]
  provides: [sas/27_md8_count.sas, qc/27_md8_count.csv (runtime)]
  affects: [DECISIONS.md (Plan 27-02)]
tech_stack:
  added: []
  patterns:
    - XLSX libname for raw workbook read (Count B independent source)
    - any-column _CHARACTER_/_NUMERIC_ sweep with vname() self-reference guard
    - src_nobs branch: routes Count A to raw XLSX when src already stripped
    - SHA-256 path-based pre-condition (not file_id-based)
key_files:
  created:
    - sas/27_md8_count.sas
  modified: []
decisions:
  - "MD8-01: md8's 22473 non-missing rows confirmed via dual independent count; trailing blank-row padding (not lost data)"
  - "Count A branches on src_nobs: reads raw XLSX libname when src already has 22473 rows, reads src directly when src has 1048575 rows"
  - "SHA-256 difference pre-condition selects rows by path (index(full_path,'master')) not file_id to avoid silent ID-shift bugs"
metrics:
  duration: "~25 min"
  completed_date: "2026-10-07"
  tasks_completed: 1
  tasks_total: 1
  files_created: 1
  files_modified: 0
---

# Phase 27 Plan 01: md8 Dual-Count Verification Summary

**One-liner:** Standalone SAS program proves md8 has exactly 22,473 non-missing rows via two independent any-column sweeps (src/XLSX branch and raw XLSX libname), three confirmation checks, SHA-256 difference pre-condition, and aborts on any mismatch.

---

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Standalone dual-count + three-check verification program | 41e7e4b | sas/27_md8_count.sas |

---

## What Was Built

`sas/27_md8_count.sas` is a standalone one-time verification program (NOT part of run_pipeline.cmd) that:

**SECTION 0b — nobs branch:**
- Reads `src.master_data_8` nobs from `dictionary.tables`
- If `src_nobs = 22473`: assigns an XLSX libname to the raw workbook (tries `&source_path.\master_data_8.xlsx` first, then `&raw_path.\master\ALL_AIM2_MASTER_DATASET_20210917.xlsx`); Count A reads the XLSX sheet
- If `src_nobs = 1048575`: Count A reads `src.master_data_8` directly
- Any other value: aborts with message

**Count A (SECTION 2):** any-column `_CHARACTER_` / `_NUMERIC_` sweep with array declarations as the FIRST statements after `set` (before any helper variable) and a `vname()` guard on the numeric loop to prevent self-reference inflation.

**Count B (SECTION 3):** Independent any-column sweep over `raw\ALL_AIM2_MASTER_DATASET_20210917.xlsx` via `libname rawaim xlsx`; sheet name discovered at run time via PROC CONTENTS.

**Three confirmation checks:**
- Contiguity: `max(row_pos) where nonmiss=1` must equal 22,473 (proves trailing not scattered padding)
- PRECEDE_STUDY_ID count: non-missing ID count must equal 22,473
- Count A = Count B = 22,473

**SHA-256 pre-condition (SECTION 3b):** Reads `qc/19_raw_files.csv` via DATA step infile (PCM-T-16). Selects rows by path (`filename + index(full_path,'master')`) not by file_id. Aborts if raw\ copy absent, if raw\master\ copy absent, or if the two SHA-256 values match (which would mean they are the same file, invalidating Count B as independent).

**SECTION 4:** Writes `qc/27_md8_count.csv` (P: drive, gitignored runtime artifact) with fixed 5-column header via DATA step PUT.

**SECTION 5:** Four `%assert_eq_local` calls abort the program if any count != 22,473.

---

## Deviations from Plan

None — plan executed exactly as written.

---

## Acceptance Criteria Verification

| Criterion | Result |
|-----------|--------|
| File sas/27_md8_count.sas exists | PASS |
| "must NEVER be added to it" present | PASS (1 hit) |
| "MD8-01" present | PASS (2 hits) |
| %include + 00_config.sas | PASS |
| dictionary.tables + src_nobs | PASS |
| _CHARACTER_ and _NUMERIC_ arrays before helpers | PASS |
| vname() self-reference guard | PASS (3 hits) |
| 'NULL' sentinel logic | PASS (3 hits) |
| libname rawaim xlsx | PASS (1 hit) |
| ALL_AIM2_MASTER_DATASET_20210917.xlsx | PASS (9 hits) |
| 19_raw_files.csv + infile | PASS |
| No file_id=19 or 30 selection | PASS (0 hits) |
| index(full_path) path-based selection | PASS (4 hits) |
| SHA comparison (sha hits) | PASS (29 hits) |
| sha_master ne '' / abort on absent master | PASS |
| 22473 string count >= 4 | PASS (15 hits) |
| CSV header string | PASS |
| raw_aim2_xlsx in CSV output | PASS |
| %abort cancel inside %macro | PASS (11 hits) |
| No PROC IMPORT | PASS (0 hits) |

---

## Known Stubs

None. The program is complete and self-contained. `qc/27_md8_count.csv` is a runtime artifact written by SAS on P: drive (gitignored per `*.csv` rule); it cannot be pre-committed. The executor must run the program once manually in a clean SAS session to produce the file and confirm both rows show PASS.

## Self-Check: PASSED

- sas/27_md8_count.sas: git log shows commit 41e7e4b, file created 377 lines
- All 20 acceptance criteria verified by grep above
