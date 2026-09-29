---
phase: 24-build-g-pcnr-harmonized
plan: "03"
subsystem: pcnr-build
tags: [sas, recode, rename, assertions, pcnr, audit-csv]
dependency_graph:
  requires: ["24-02"]
  provides: ["g.pcnr_harmonized", "qc/24_pcnr_recode_counts.csv", "qc/24_pcnr_recode_totals.csv"]
  affects: ["Phase 25 pcnr cohort and dictionary"]
tech_stack:
  added: []
  patterns:
    - "WORK-then-promote for g library writes (PCM-T-02)"
    - "Generated label file with single-quoted values (avoids macro expansion of & and % in label text)"
    - "dsd mod pattern for CSV row output (auto-quoting, no padding)"
    - "Macro-variable loop for per-column missing-math assertion"
    - "call symputx for indexed rule loading into macro variables (sentinel check loop)"
key_files:
  created: []
  modified:
    - sas/24_pcnr_build.sas
decisions:
  - "D-04: rename/label/drop in single DATA step (no PROC DATASETS MODIFY)"
  - "Label file uses single-quoted values written to qc/24_label_stmts_generated.sas and %include'd; no &label_stmts macro variable"
  - "SECTION 8 Check 5 (zero remaining sentinels) uses call symputx loop over rules rows then PROC SQL per rule"
  - "Missing-math assertion builds nmiss per-column via macro loop into indexed macro variables, then joins to recode totals"
metrics:
  duration_minutes: 8
  completed_date: "2026-09-28"
  tasks_completed: 2
  tasks_total: 3
  files_modified: 1
---

# Phase 24 Plan 03: Rename/Promote/CSVs/Assertions Summary

Complete `sas/24_pcnr_build.sas` SECTIONS 5-8: rename+label+drop in one DATA step, WORK-then-promote to g.pcnr_harmonized, two audit CSVs written via dsd mod pattern, and full PCNR-11 seven-check assertion suite — pending human-verified full run (Task 3).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | SECTION 5 rename/label/drop + SECTION 6 WORK-then-promote | ff3d315 | sas/24_pcnr_build.sas |
| 2 | SECTION 7 audit CSVs + SECTION 8 PCNR-11 assertion suite | ff3d315 | sas/24_pcnr_build.sas |
| 3 | Human-verified full run | PENDING | — |

## What Was Built

### Task 1: SECTION 5 + 6

**SECTION 5** builds `rename_list` and `drop_list` from `work._name_map` (already loaded in SECTION 0 — no second file read). Label statements are written to `qc/24_label_stmts_generated.sas` using single-quoted values with embedded apostrophes doubled, then `%include`d inside the DATA step. KEY columns keep their original names via `coalescec(final_name, source_name)`. Three immediate assertions:

- Assert 5a: column count of `work.pcnr_harmonized` = 163
- Assert 5b: variable set = KEY source_names + KEEP final_names exactly (anti-join both directions)
- Assert 5c: type and length of every column unchanged vs `g.master_data_harmonized`

**SECTION 6**: `data g.pcnr_harmonized; set work.pcnr_harmonized;` — pure WORK-then-promote, runs only after all SECTION 5 asserts pass.

### Task 2: SECTION 7 + 8

**SECTION 7**: Builds `work._recode_counts_detail` by left-joining `work._recode_rules` (all MISSING rules, including zero-hit) to per-rule actual counts from `work._compare_out` and `final_name` from the name map. Writes two CSVs via `data _null_; file ... dsd mod` pattern: header in a separate step (no dsd), data rows with dsd for comma-delimiting and auto-quoting.

- `qc/24_pcnr_recode_counts.csv`: columns `variable,final_name,raw_value,raw_hex,var_type,rule_source,n_expected,n_recoded`
- `qc/24_pcnr_recode_totals.csv`: columns `variable,final_name,n_recoded_total` — one row per KEEP+KEY column including zero-hit columns; no TOTAL sentinel row (D-05)

**SECTION 8**: Full PCNR-11 seven-check suite, each check inside a named macro calling `%fail_out`:

1. Row count: `g.pcnr_harmonized` = 41,150
2. Key identity: `PRECEDE_STUDY_ID` distinct count equal and set-identical (anti-join both directions); `pecan_ID` row-by-row identical via parallel SET comparison
3. Column count: `g.pcnr_harmonized` = 163
4. Missing math: per every KEEP column, `nmiss(final) = nmiss(source) + n_recoded_total` (macro loop builds indexed macro variables, joins to totals dataset, counts violations)
5. Zero remaining sentinels: per every rule, `%hexkey(final_name_col) = raw_hex` count in output; total must = 0 (uses `call symputx` to load rules then PROC SQL per rule)
6. Type/length unchanged: re-assert from `dictionary.columns` on `g.pcnr_harmonized`
7. Source unchanged: re-query `dictionary.tables` for `g.master_data_harmonized` nobs/nvar/modate vs SECTION 0 values (`&cur_nobs`, `&cur_nvar`, `&cur_modate`)

Ends with `%put NOTE: [24] PCNR-11 PASS -- all assertions cleared;` then `%restore_log;`.

## Static Checks (all pass)

| Check | Expected | Result |
|-------|----------|--------|
| `grep -ci "proc import"` | 0 | 0 |
| `grep -c '\$hex\.'` | 0 | 0 |
| `grep -ci "%put WARNING"` | 0 | 0 |
| `grep -ci "proc export"` | 0 | 0 |
| `grep -ci "proc compare"` | 0 | 0 |
| `grep -c "label_stmts;"` | 0 | 0 |
| `grep -ci "modify master_data_harmonized"` | 0 | 0 |
| `grep -c "dsd mod"` | 2 | 2 |
| `grep -q "PCNR-11 PASS"` | found | found |

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

The SECTION 8 Check 5 implementation used `call symputx` to load rule fields into indexed macro variables (rather than a PROC SQL query-per-row approach), then looped with a PROC SQL per rule. This is within the discretion boundary noted in CONTEXT.md.

## Task 3 Status

**PENDING human verification.** Full run of `sas/24_pcnr_build.sas` in a clean SAS 9.4 session is required. See checkpoint details in the executor return message.

## Self-Check

- [x] `sas/24_pcnr_build.sas` exists and contains all 8 sections
- [x] Commit ff3d315 exists
- [x] All static grep checks pass
- [x] Task 3 documented as pending

## Self-Check: PASSED (Tasks 1+2; Task 3 awaiting human run)
