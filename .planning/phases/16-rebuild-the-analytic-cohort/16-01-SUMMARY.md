---
phase: 16-rebuild-the-analytic-cohort
plan: "01"
subsystem: cohort
tags: [sas, cohort, harmonized, analytic_cohort, HARM-10, PCM-D-05]
dependency_graph:
  requires: [g.master_data_harmonized (Phase 15), sas/00_config.sas]
  provides: [sas/16b_cohort_rebuild.sas, g.analytic_cohort (at runtime)]
  affects: [g.analytic_cohort, qc/16b_cohort_missingness.txt, qc/16b_cohort_tables.txt]
tech_stack:
  added: []
  patterns: [07_cohort.sas macro pattern, assert_harmonized_unchanged from 10b, gate-before-promote ordering fix]
key_files:
  created: [sas/16b_cohort_rebuild.sas]
  modified: []
decisions:
  - "Gate runs BEFORE promotion (fixes latent ordering flaw in 07_cohort.sas where ZERO_ROWS candidate could overwrite g.analytic_cohort before gate fired)"
  - "Full 174-column pass-through to g.analytic_cohort -- no KEEP, no DROP (D-09)"
  - "assert_bmi_rationale asserts n_bmi_cohort = n_bmi_harm (equality, not a hardcoded value) -- tests the PCM-D-05 rationale itself"
  - "assert_all_three removed entirely -- 6,523 was stale pre-coalesce; measure only (D-06)"
  - "Within-cohort Cognitive and Frailty are measured not asserted -- most values are ambulatory after MRG-06 (PCM-F-19)"
metrics:
  duration: ~25min
  completed: "2026-09-22"
  tasks: 2
  files: 1
---

# Phase 16 Plan 01: Cohort Rebuild Program Summary

**One-liner:** Standalone SAS program rebuilds g.analytic_cohort from g.master_data_harmonized via INPATIENT+OBSERVATION filter, with full 174-column pass-through, gate-before-promote ordering, and post-run source-unchanged assertion.

---

## What Was Built

`sas/16b_cohort_rebuild.sas` (500 lines) — a standalone SAS 9.4M8 program that:

1. Reads `g.master_data_harmonized` (174 cols, 41,150 rows) — never modifies it
2. Applies `where upcase(strip(Patient_Type)) in ('INPATIENT','OBSERVATION')` to produce `work.cohort_candidate` (expected 13,890 rows)
3. Measures missingness profiles (full-file and within-cohort)
4. Asserts full-file complete-case Ns: Admit_BMI=12,726 / Cognitive_Score=20,540 / Frailty_Score=23,311
5. Asserts PCM-D-05 rationale: `n_bmi_cohort` must equal `n_bmi_harm` (zero ambulatory BMI values)
6. Gates on degenerate cohort status (ZERO_ROWS / ALL_ROWS / QUERY_FAILED) **before** promoting
7. Promotes to `g.analytic_cohort` with 174-column and row-count verification
8. Asserts `g.master_data_harmonized` unchanged post-run (174 cols, 41,150 rows)
9. Measures all 12 h_* within-cohort Ns (D-07, QC file only, no assertion)
10. Writes grep-able key=value summary to `&qc_path.\16b_cohort_missingness.txt` and PROC tables to `&qc_path.\16b_cohort_tables.txt`

**Program prefix:** `16b_` (the `16_` prefix is taken by `16_raw_inventory.sas` and `16_summary_docx.sas` — consistent with the `10b_` precedent).

---

## Measured Values (to be filled after SAS run)

These values are unknown until `16b_cohort_rebuild.sas` runs in a fresh SAS 9.4M8 session.
Plan 02 records them in `DECISIONS.md` and `STATE.md`.

| Metric | Value | Notes |
|--------|-------|-------|
| admitted_n | TBD | Expected 13,890 |
| BMI_complete_case_n_harmonized | TBD | Expected 12,726 (assertion) |
| Cognitive_complete_case_n_harmonized | TBD | Expected 20,540 (assertion) |
| Frailty_complete_case_n_harmonized | TBD | Expected 23,311 (assertion) |
| all_three_complete_case_n_harmonized | TBD | Measured only (D-06 new baseline) |
| BMI_complete_case_n_cohort | TBD | Expected = n_bmi_harm (assertion) |
| Cognitive_complete_case_n_cohort | TBD | Measured (prior merged: 7,252) |
| Frailty_complete_case_n_cohort | TBD | Measured (prior merged: 8,150) |
| all_three_complete_case_n_cohort | TBD | Measured baseline (D-06) |
| pct_admitted_HAVE_bmi | TBD | Expected ~91.6% |
| pct_admitted_LACK_bmi | TBD | Expected ~8.4% |
| H_DEATH_YN within cohort | TBD | Measured (full-file: 22,917) |
| H_DIABETES within cohort | TBD | Measured (full-file: 5,983) |
| H_FRAILTY_ACTIVITY within cohort | TBD | Measured (full-file: 14,025) |
| H_FRAILTY_EXHAUST within cohort | TBD | Measured (full-file: 14,181) |
| H_FRAILTY_GRIP within cohort | TBD | Measured (full-file: 13,699) |
| H_FRAILTY_WALKING within cohort | TBD | Measured (full-file: 13,989) |
| H_FRAILTY_WEIGHT within cohort | TBD | Measured (full-file: 14,156) |
| H_HYPERLIPIDEMIA within cohort | TBD | Measured (full-file: 11,207) |
| H_HYPERTENSION within cohort | TBD | Measured (full-file: 12,546) |
| H_MOVEMENT_DISORDER within cohort | TBD | Measured (full-file: 1,357) |
| H_SLEEP_APNEA within cohort | TBD | Measured (full-file: 3,812) |
| H_SSDI_DEATH within cohort | TBD | Measured (full-file: 29,316) |
| cohort_cols | TBD | Expected 174 (assertion) |
| harmonized unchanged post-run | TBD | Expected PASS |

---

## Deviations from Plan

### Auto-fixed Issues

None.

### Structural Deviations

**1. Tasks 1 and 2 committed as a single atomic commit**
- The plan described two tasks (SECTIONS 0-4 then SECTIONS 5-7) but the SAS program is a single file. Writing sections 0-4 and committing a partial file would leave a non-runnable artifact in version control. Both tasks were written together and committed as one complete, runnable program.

---

## Known Stubs

None — the program is complete and runnable. Measured values in the table above are TBD because the SAS run has not yet occurred (Task 3 is a human-verify checkpoint).

---

## Self-Check: PASSED

- `sas/16b_cohort_rebuild.sas` exists: FOUND
- Commit `24cf514` exists: FOUND
