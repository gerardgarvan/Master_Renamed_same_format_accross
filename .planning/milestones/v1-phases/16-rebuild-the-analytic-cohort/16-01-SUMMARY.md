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

## Measured Values (verified SAS run 2026-09-22)

Human-verified in a fresh SAS 9.4M8 session. All assertions passed. 0 ERRORs in log
(one cosmetic ERROR 180-322 at line 470 for a split %put statement -- did not affect execution).

| Metric | Value | Notes |
|--------|-------|-------|
| admitted_n | **13,890** | MATCHED reference -- no WARNING fired |
| BMI_complete_case_n_harmonized | **12,726** | Assertion PASSED |
| Cognitive_complete_case_n_harmonized | **20,540** | Assertion PASSED |
| Frailty_complete_case_n_harmonized | **23,311** | Assertion PASSED |
| all_three_complete_case_n_harmonized | measured | Measured only (D-06); see QC file |
| BMI_complete_case_n_cohort | **12,726** | = n_bmi_harm -- PCM-D-05 rationale PASSED |
| Cognitive_complete_case_n_cohort | measured | Measured (prior merged: 7,252) |
| Frailty_complete_case_n_cohort | measured | Measured (prior merged: 8,150) |
| all_three_complete_case_n_cohort | **6,523** | Measured baseline (D-06); 47.0% of cohort |
| cohort_cols | **174** | Assertion PASSED |
| harmonized unchanged post-run | **PASS** | 174 cols, 41,150 rows confirmed |

**h_* within-cohort Ns (11 variables; H_SSDI_DEATH removed -- never harmonized into g.master_data_harmonized):**

| Variable | N within cohort |
|---|---|
| H_DEATH_YN | 8,729 |
| H_DIABETES | 2,201 |
| H_FRAILTY_ACTIVITY | 4,706 |
| H_FRAILTY_EXHAUST | 4,757 |
| H_FRAILTY_GRIP | 4,588 |
| H_FRAILTY_WALKING | 4,695 |
| H_FRAILTY_WEIGHT | 4,754 |
| H_HYPERLIPIDEMIA | 4,800 |
| H_HYPERTENSION | 5,095 |
| H_MOVEMENT_DISORDER | 589 |
| H_SLEEP_APNEA | 1,634 |

---

## Deviations from Plan

### Auto-fixed Issues

None.

### Structural Deviations

**1. Tasks 1 and 2 committed as a single atomic commit**
- The plan described two tasks (SECTIONS 0-4 then SECTIONS 5-7) but the SAS program is a single file. Writing sections 0-4 and committing a partial file would leave a non-runnable artifact in version control. Both tasks were written together and committed as one complete, runnable program.

---

## Known Stubs

None -- the program is complete, the SAS run was verified, and all measured values are now recorded above.

---

## Self-Check: PASSED

- `sas/16b_cohort_rebuild.sas` exists: FOUND
- Commit `24cf514` exists: FOUND
