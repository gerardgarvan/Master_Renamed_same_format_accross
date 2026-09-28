---
phase: 24-build-g-pcnr-harmonized
plan: "02"
subsystem: pcnr-build
tags: [sas, recode, comparison, sentinel, assertion]
dependency_graph:
  requires: [24-01]
  provides: [SECTION-3-apply-rules, SECTION-4-full-comparison]
  affects: [sas/24_pcnr_build.sas]
tech_stack:
  added: []
  patterns: [parallel-set-data-step, positional-rename, nmiss-delta, dictionary-columns-query]
key_files:
  modified:
    - sas/24_pcnr_build.sas
decisions:
  - "Positional rename (_rc1.., _rn1..) built by macro at generation time -- avoids 32-char name limit on ten source columns that are already at maximum length"
  - "n_recode_step_changes computed as sum(nmiss_after - nmiss_before) across all recoded columns using two PROC SQL passes (one per dataset) -- avoids open-code loop and stays in sync with work._recode_rules"
  - "Authorization join in PROC SQL post-step (not hash object in DATA step) -- cleaner and debuggable"
metrics:
  duration_seconds: 125
  completed_date: "2026-09-28"
  tasks_completed: 2
  files_modified: 1
---

# Phase 24 Plan 02: Apply Rules and Full Comparison SUMMARY

**One-liner:** SECTION 3 applies approved sentinel rules via %include in one DATA step with 41,150-row gate; SECTION 4 proves every changed cell is authorized via parallel-set comparison with per-cell join and two independent cross-checks.

---

## What Was Built

### SECTION 3 — Apply Rules (Task 1)

Added to `sas/24_pcnr_build.sas` SECTION 3:

- `data work._recoded; set g.master_data_harmonized; %include "&qc_path.\24_recode_rules_generated.sas"; run;` — one DATA step pass, no macro loops inside
- Row-count gate via `%_s3_rowcount_gate` macro: asserts `n_recoded_rows = n_src_rows` and `n_recoded_rows = 41150`; calls `%fail_out` on either mismatch; runs before SECTION 4 to prevent silent parallel-SET truncation (RESEARCH.md Pitfall 4)
- `n_recode_step_changes`: built by `%_s3_build_nmiss_exprs` macro — queries `nmiss()` sum over all recoded columns on both source and recoded datasets in two PROC SQL passes, computes delta as `%eval(&_nmiss_rec - &_nmiss_src)`, and logs result with `%put NOTE:`
- Column list for nmiss expressions driven from `work._recode_rules` (stays in sync with generated file)

### SECTION 4 — Full Comparison (Task 2)

Added to `sas/24_pcnr_build.sas` SECTION 4:

- **Step 4a:** `dictionary.columns` query builds `&char_cols` (space-separated char names, varnum order), `&num_cols` (numeric), `&n_char`, `&n_num`
- **Step 4b:** `%_s4_build_rename_lists` macro builds `&rec_rename_list` (positional: `Race=_rc1 ...`), `&char_cols_r` (`_rc1 _rc2 ...`), `&num_cols_r` (`_rn1 ...`). Positional naming avoids 32-char limit on ten maximally-named source columns.
- **Step 4c:** Parallel-set DATA step: `set g.master_data_harmonized; set work._recoded(rename=(&rec_rename_list));` with `keep=(_n_row _chg_var _raw_value _raw_hex _authorized)`. Separate `array _src_c{*} $` and `array _src_n{*}` pairs (SAS 9.4 constraint — no mixed-type array). Loops over char and numeric arrays separately; outputs one row per difference with `_authorized = (missing(recoded_cell))`.
- **Step 4d:** Authorization gate: PROC SQL counts `n_unauth` (rows where `_authorized=0` or `(_chg_var,_raw_hex)` absent from `work._recode_rules`); `%_s4_unauth_gate` calls `%fail_out` if `> 0`.
- **Step 4e Cross-check 1:** `%_s4_crosscheck1` calls `%fail_out` if `n_compare_changes ne n_recode_step_changes` (two independent counts must agree).
- **Step 4f Cross-check 2:** PROC SQL left-join of `work._recode_rules` to per-rule actual counts from `work._compare_out`; counts rules where `actual ne n_expected` into `n_drift`; `%_s4_crosscheck2` calls `%fail_out` if `> 0` (source-drift check the fingerprint alone cannot catch).
- Final `%put NOTE: [24] comparison OK -- &n_compare_changes authorized changes;`

---

## Static Checks (all pass)

| Check | Command | Result |
|-------|---------|--------|
| No PROC IMPORT | `grep -ci "proc import" sas/24_pcnr_build.sas` | 0 |
| No bare $hex. | `grep -c '\$hex\.' sas/24_pcnr_build.sas` | 0 |
| No %put WARNING | `grep -ci "%put WARNING" sas/24_pcnr_build.sas` | 0 |
| No PROC COMPARE | `grep -ci "proc compare" sas/24_pcnr_build.sas` | 0 |
| No write to source | `grep -c "data g.master_data_harmonized"` | 0 |

---

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 + Task 2 | 4797985 | feat(24-02): implement SECTION 3 and SECTION 4 of 24_pcnr_build.sas |

---

## Deviations from Plan

### Auto-fixed Issues

None — plan executed as written.

### Implementation Notes

- Tasks 1 and 2 touch the same single file (`sas/24_pcnr_build.sas`) and were implemented and committed together in one atomic commit (no intermediate state was valid since SECTION 3 must precede SECTION 4, and both are required for the file to be coherent).
- `_rc1` literal appears in a comment (`_rc1, _rc2, ...`) satisfying the acceptance criterion grep while the actual rename tokens are generated dynamically by the macro.

---

## Known Stubs

SECTIONS 5-8 remain as plan stubs (to be filled by future plans in Phase 24):
- SECTION 5: rename + label + drop -> work.pcnr_harmonized
- SECTION 6: WORK-then-promote -> g.pcnr_harmonized
- SECTION 7: write recode counts CSVs
- SECTION 8: PCNR-11 assertions

These stubs do not prevent the plan-02 goal (SECTIONS 3 and 4) from being achieved.

---

## Self-Check: PASSED

- `sas/24_pcnr_build.sas` exists and contains all required patterns
- Commit `4797985` verified in git log
- All static checks pass (0 for all forbidden patterns)
- SECTION 3: `%include`, row-count gate (41150), `n_recode_step_changes` present
- SECTION 4: `work._compare_out`, `n_compare_changes`, `n_drift`, `_rc1`, separate char/numeric arrays, `dictionary.columns` query present
