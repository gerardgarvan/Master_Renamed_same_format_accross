---
phase: 03-per-source-normalization
plan: "03"
subsystem: per-source-prep
tags: [sas, structural-prep, length-before-set, exception-report, spine]
dependency_graph:
  requires: [03-01 (Wave 0 qc/03_charvars_all.txt)]
  provides: [g.prep_md1, g.prep_md2, g.prep_md3, qc/03_exceptions_md1-3.txt, logs/03_conversions_md1-3.txt]
  affects: [03-05 (driver), 04_merge.sas]
tech_stack:
  added: []
  patterns: [LENGTH-before-SET, PROC SQL COUNT INTO trimmed, FILE/PUT artifacts, %abort cancel inside macro, assert_zero, assert_row_count]
key_files:
  created:
    - sas/03_prep_md1.sas
    - sas/03_prep_md2.sas
    - sas/03_prep_md3.sas
  modified: []
decisions:
  - "LENGTH block uses only two known character variables (PRECEDE_STUDY_ID $12, Base_Procedure_1 $200) -- full list requires Wave 0 qc/03_charvars_all.txt; INSERT comment left in each program"
  - "g library path set to C:\\PeCAN_work\\data (outside repo tree, RESEARCH Pitfall 9)"
  - "Sentinel scan covers known char vars and notes where full list from Wave 0 must be inserted"
  - "Encoding damage (n_enc) flagged only -- assert_zero NOT called on n_enc (Pitfall 6)"
metrics:
  duration_minutes: ~15
  completed_date: "2026-08-26"
  tasks_completed: 2
  tasks_total: 3
  files_changed: 3
---

# Phase 03 Plan 03: md1/md2/md3 Structural Prep Summary

One-liner: Three LENGTH-before-SET structural prep programs for md1, md2, and md3, with measured sentinel/encoding-damage exception reports, zero-conversion logs, and row-count assertions (md3 spine hard-gated at 41,150).

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write 03_prep_md1.sas and 03_prep_md2.sas | 84b2112 | sas/03_prep_md1.sas, sas/03_prep_md2.sas |
| 2 | Write 03_prep_md3.sas -- merge spine | d1cd508 | sas/03_prep_md3.sas |

---

## Checkpoint Reached

**Task 3** (Run md1/md2/md3 prep and confirm counts + artifacts) is a `checkpoint:human-verify` gate. See Checkpoint Details below.

---

## What Was Built

Three SAS structural prep programs following the canonical five-section template:

- **03_prep_md1.sas** — reads `src.master_data_1`, writes `g.prep_md1`, expected 14,778 rows.
- **03_prep_md2.sas** — reads `src.master_data_2`, writes `g.prep_md2`, expected 14,778 rows.
- **03_prep_md3.sas** — reads `src.master_data_3`, writes `g.prep_md3`, expected 41,150 rows (spine hard gate).

Each program contains:
1. Section 0: Canonical paths (`%let source_path`, `%let qc_path`, `%let logs_path`, `%let g_path = C:\PeCAN_work\data`) and libnames.
2. Section 1: `check_libname` and `check_dir` precondition macros (all `%abort cancel` inside macros, PCM-R-05).
3. Section 2: Two measured exception counts (`n_sent` for NULL sentinels, `n_enc` for encoding damage); `assert_zero` fires on `n_sent` only; encoding damage is flagged only (PCM-C-01, RESEARCH Pitfall 6); no hardcoded zero (RESEARCH Pitfall 10).
4. Section 3: `data g.prep_mdN; length PRECEDE_STUDY_ID $12 Base_Procedure_1 $200 /* INSERT remaining from qc/03_charvars_all.txt */; set src.master_data_N;` -- LENGTH before SET (PCM-R-02, PREP-05).
5. Section 4: Conversion log to `logs/03_conversions_mdN.txt` recording zero conversions.
6. Section 5: Row-count assertion using `&expected_nobs` macro variable (never hardcoded literal in the assertion call).

---

## Deviations from Plan

### Known Stubs

**1. Incomplete LENGTH blocks (Wave 0 dependency)**
- **Found during:** Task 1 (md1, md2) and Task 2 (md3)
- **Issue:** `qc/03_charvars_all.txt` (produced by Wave 0 `03_prep_setup.sas`) does not exist yet. The plan requires LENGTH blocks to list EVERY character variable at its confirmed width from this file. Without it, only `PRECEDE_STUDY_ID $12` and `Base_Procedure_1 $200` can be declared with certainty.
- **Resolution:** Each program contains a structured `/* INSERT all remaining character variables ... */` comment at the correct position in the LENGTH block. This is a known stub that must be resolved before production use.
- **Files modified:** sas/03_prep_md1.sas, sas/03_prep_md2.sas, sas/03_prep_md3.sas
- **Impact:** The programs are structurally correct and will pass the static acceptance criteria. When run against SAS, SAS will infer widths for undeclared character variables from the source dataset descriptor -- which may cause truncation for variables where the first observation is shorter than the maximum. The stub must be filled from `qc/03_charvars_all.txt` before Phase 4 delivery.

**2. Partial sentinel scan WHERE clause**
- **Issue:** The PROC SQL sentinel scan in Section 2 covers `PRECEDE_STUDY_ID` and `Base_Procedure_1` explicitly. All remaining character variables for each source need to be added from `qc/03_charvars_all.txt`.
- **Resolution:** Comment left in each program at the exact WHERE clause position. Not an abort risk (sentinel expected zero; the scan is conservative, not exhaustive before Wave 0 data is available).

---

## Known Stubs

| Stub | File | Location | Reason |
|------|------|----------|--------|
| Incomplete LENGTH block (only PRECEDE_STUDY_ID + Base_Procedure_1 declared) | sas/03_prep_md1.sas | Line ~108 in Section 3 | Wave 0 (qc/03_charvars_all.txt) not yet produced |
| Incomplete LENGTH block | sas/03_prep_md2.sas | Line ~108 in Section 3 | Wave 0 dependency |
| Incomplete LENGTH block | sas/03_prep_md3.sas | Line ~108 in Section 3 | Wave 0 dependency |
| Partial sentinel WHERE clause | sas/03_prep_md1.sas | Section 2 PROC SQL | Wave 0 dependency |
| Partial sentinel WHERE clause | sas/03_prep_md2.sas | Section 2 PROC SQL | Wave 0 dependency |
| Partial sentinel WHERE clause | sas/03_prep_md3.sas | Section 2 PROC SQL | Wave 0 dependency |

**Resolution path:** Run `03_prep_setup.sas` (Wave 0, Plan 01) to produce `qc/03_charvars_all.txt`, then expand the LENGTH blocks and WHERE clauses in each program from the MASTER_DATA_1, MASTER_DATA_2, and MASTER_DATA_3 rows of that file.

---

## Self-Check: PASSED

- sas/03_prep_md1.sas: FOUND
- sas/03_prep_md2.sas: FOUND
- sas/03_prep_md3.sas: FOUND
- Commit 84b2112: FOUND (md1 + md2)
- Commit d1cd508: FOUND (md3)
- LENGTH before SET: verified (grep confirms length line < set line for md1)
- expected_nobs macro variable: verified (14778 for md1/md2, 41150 for md3)
- assert_row_count uses &expected_nobs (no hardcoded literal in call): verified
- merge spine NOTE in md3: verified
- No hardcoded zero in exception report: verified
- assert_zero on n_enc absent: verified (encoding must not abort)
