---
phase: 25-pcnr-cohort-dictionary-wiring
plan: "01"
subsystem: pcnr-cohort
tags: [sas, cohort, pcnr, assertions, qc-csv]
dependency_graph:
  requires: [g.pcnr_harmonized, g.analytic_cohort, qc/24_pcnr_recode_totals.csv]
  provides: [g.pcnr_analytic_cohort, qc/25_complete_case_n.csv]
  affects: [run_pipeline.cmd, sas/25_pcnr_cohort.sas]
tech_stack:
  added: []
  patterns: [WORK-then-promote, DATA-step-infile-CSV, errorabend-guard, SELECT-COUNT-TRIMMED]
key_files:
  created: [sas/25_pcnr_cohort.sas]
  modified: []
decisions:
  - "PCNR_APPROVED gate and errorabend set before first gate check (in_pipeline=1 guard)"
  - "00_config.sas included in open code (not inside macro) to keep %let variables global"
  - "PRECEDE_STUDY_ID set identity asserted in both directions via PROC SQL subquery"
  - "recode_totals.csv read with DATA step infile (PCM-T-16 -- no PROC IMPORT)"
metrics:
  duration_minutes: 15
  completed_date: "2026-09-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 0
---

# Phase 25 Plan 01: pcnr Cohort Build and Complete-Case N Assertions Summary

**One-liner:** PCM-D-05 cohort subset (13,890 rows) promoted to g.pcnr_analytic_cohort with N assertion, bidirectional PRECEDE_STUDY_ID set identity check, complete-case N benchmarks (12726/7252/8150/6523), and qc/25_complete_case_n.csv written via DATA step PUT.

## What Was Built

`sas/25_pcnr_cohort.sas` — Sections 0 through 5 complete; Sections 6-7 stubbed for Plan 25-02.

**Section 0:** Options, open-code `%include` of 00_config.sas, `libname g`, errorabend guard
(conditioned on `in_pipeline = 1`, placed before any gate), `%fail_out` macro, `%check_dir`
macro, directory gate calls for qc and logs, log redirect (standalone only), PCNR_APPROVED gate,
existence gates for g.pcnr_harmonized and g.analytic_cohort.

**Section 1:** Subsets `g.pcnr_harmonized` to `work._pcnr_cohort_candidate` where
`pcnr_Patient_Type IN ('INPATIENT', 'OBSERVATION')`; counts candidate rows into `&n_candidate`.

**Section 2:** Asserts `&n_candidate = 13890` via `%fail_out`; asserts PRECEDE_STUDY_ID set
identity vs `g.analytic_cohort` using two PROC SQL subqueries (IDs in candidate but not in
original; IDs in original but not in candidate) — both counts must be 0.

**Section 3:** WORK-then-promote: `data g.pcnr_analytic_cohort; set work._pcnr_cohort_candidate;`
followed by post-promote count assertion (`ne 13890` aborts).

**Section 4:** PROC SQL computes six counts: n_before for BMI, Cognitive, Frailty, and all-three
from `g.analytic_cohort` (original column names); n_after from `g.pcnr_analytic_cohort` (pcnr_
names).

**Section 5:** `%_assert_n_after` macro called for all four measures; reads
`qc/24_pcnr_recode_totals.csv` via DATA step infile and asserts n_after = n_before for measures
with 0 recodes (PCM-D-24 approved no numeric recodes); benchmark assertions
(12726/7252/8150/6523); writes `qc/25_complete_case_n.csv` via `DATA _null_ / file / PUT`.

## Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write Sections 0-3 (cohort build and promote) | 8e92b7a | sas/25_pcnr_cohort.sas (created, 190 lines) |
| 2 | Add Sections 4-5 (complete-case Ns + CSV) | 2e38cc2 | sas/25_pcnr_cohort.sas (+118 lines) |

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

- **SECTION 6** (`sas/25_pcnr_cohort.sas`, placeholder comment): PCNR_DICTIONARY.xlsx build — implemented in Plan 25-02.
- **SECTION 7** (`sas/25_pcnr_cohort.sas`, placeholder comment): qc/25_pcnr_variables.csv — implemented in Plan 25-02.

These stubs are intentional; the plan's goal (PCNR-12, PCNR-13) is fully achieved by Sections 0-5.

## Self-Check: PASSED

- sas/25_pcnr_cohort.sas: FOUND (306 lines)
- Commit 8e92b7a: confirmed in git log
- Commit 2e38cc2: confirmed in git log
- errorabend guard: PRESENT (options errorabend inside %macro _set_errorabend guarded by in_pipeline=1)
- PCNR_APPROVED gate: PRESENT
- N assertion ne 13890: PRESENT
- PRECEDE_STUDY_ID not in: PRESENT (2 occurrences, both directions)
- data g.pcnr_analytic_cohort: PRESENT
- Benchmark assertions 12726/7252/8150/6523: ALL PRESENT
- CSV header measure,n_before,n_after,n_difference: PRESENT
- No PROC IMPORT (functional): CONFIRMED (only mention is in header comment under "violations avoided")
- Sections 6-7 placeholders: PRESENT
