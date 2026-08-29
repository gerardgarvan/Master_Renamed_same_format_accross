---
phase: 14-label-similarity-sweep
plan: "02"
subsystem: label-similarity
tags: [sas, harm-09, ssdi, cpt1, concept-profiling, label-sweep]
dependency_graph:
  requires: [14-01, 10b-concept-harmonize]
  provides: [concept_decisions_EXT_TEMPLATE, CONCEPT_EVIDENCE_EXT, complete-14_label_similarity]
  affects: [phase-15-harmonize]
tech_stack:
  added: []
  patterns: [type-driven-fmt-macro, dictionary-columns-type-check, cpt1-xtab-cap, 10b-schema-value-level-template]
key_files:
  created: []
  modified:
    - sas/14_label_similarity.sas
decisions:
  - CONCEPT_EVIDENCE_EXT.xlsx written as a separate file (not appended to CONCEPT_EVIDENCE.xlsx) to avoid ODS file-open conflicts and preserve Phase 10 confirmed decisions
  - CPT1 cross-tab capped at 200 rows by n_rows descending; the 159x159 full matrix would be 25k rows in an Excel sheet
  - concept_decisions_EXT_TEMPLATE.csv uses the exact 10b_concept_harmonize.sas schema (concept, varname, value_txt, target_value, confirmed, harmonized_name, priority) at value-level -- NOT cross-tab shape
  - Type-driven fmt_col macro reads dictionary.columns.type ('char'/'num') before building CASE expressions; avoids PCM-T-13 trap
  - Two SSDI/CPT1 concept groups use different priorities per source variable (10b aborts on tied priorities)
metrics:
  duration: "~15 min"
  completed: "2026-08-29"
  tasks: 1
  files: 1
---

# Phase 14 Plan 02: SSDI and CPT1 Concept Profiling (HARM-09) Summary

**One-liner:** Section B added to 14_label_similarity.sas -- SSDI death family and CPT1 code/label pair profiled with type-safe value inventory, pairwise cross-tab (CPT1 capped at 200 rows), and 10b-schema-compliant concept_decisions_EXT_TEMPLATE.csv.

## What Was Built

**sas/14_label_similarity.sas** is now complete (Section A + Section B), 832 lines total.

Section B adds:
- `%check_var_present` macro that aborts if any of the five HARM-09 variables is missing from `g.master_data_harmonized`
- Type detection via `dictionary.columns.type` for all five variables (PCM-T-13 safe)
- `%fmt_col` macro that emits correct CASE expression for char vs numeric variables
- SSDI value inventory: three variables, all values and counts
- SSDI pairwise cross-tabulation: three pairs (SSDI_DEATH_DATE_Y_N x SSDI_DEATH_Y_N, SSDI_DEATH_DATE_Y_N x SSDI_DEATH, SSDI_DEATH_Y_N x SSDI_DEATH)
- CPT1 value inventory: CPT1_CLASS and CPT1_LABEL (159 distinct values each)
- CPT1 cross-tabulation: top 200 rows by n_rows descending (cap documented in title and QC artifact)
- `docs/concept_decisions_EXT_TEMPLATE.csv`: value-level rows for SSDI and CPT1, exact 10b schema
- `docs/CONCEPT_EVIDENCE_EXT.xlsx`: KEY sheet leftmost, four data sheets (SSDI_VALUE_INVENTORY, SSDI_CROSSTAB, CPT1_VALUE_INVENTORY, CPT1_CROSSTAB_TOP200)
- QC artifact appended with Section B counts

## Files Modified

| File | Change |
|------|--------|
| sas/14_label_similarity.sas | Section B placeholder replaced with full implementation (~230 lines added) |

## Files Produced by SAS Run (not committed -- generated at runtime)

| File | Status | Notes |
|------|--------|-------|
| docs/label_similarity_candidates.csv | Committed after human verify | Human-review candidate pairs from Section A |
| docs/concept_decisions_EXT_TEMPLATE.csv | Committed after human verify | SSDI/CPT1 value-level template for Phase 15 |
| docs/LABEL_SIMILARITY_EVIDENCE.xlsx | Not committed | Section A evidence workbook |
| docs/CONCEPT_EVIDENCE_EXT.xlsx | Not committed | Section B evidence workbook |
| qc/14_label_similarity.txt | Not committed (on P:) | QC artifact with all counts and thresholds |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] concept_decisions_EXT_TEMPLATE.csv schema corrected to 10b-compatible value-level format**
- **Found during:** Task 1 implementation
- **Issue:** Plan 02 initially described cross-tab-shaped rows (varname_a, varname_b, n_rows, confirmed). 10b_concept_harmonize.sas validates the header and requires exactly: concept, varname, value_txt, target_value, confirmed, harmonized_name, priority. A wrong-schema file fails immediately with "missing required columns".
- **Fix:** Built the template from the value inventory (one row per source variable per observed non-missing value), not from cross-tab combinations. Cross-tab evidence goes in the workbook only.
- **Files modified:** sas/14_label_similarity.sas (Section B-7)
- **Commit:** 260c3e7

This correction was documented in the plan itself (the "CORRECTED 2026-08-29" block in Step B-4) and was implemented as specified.

## Human Checkpoint Result

PENDING -- Task 2 is a `checkpoint:human-verify`. Human must:
1. Submit `sas/14_label_similarity.sas` in a fresh SAS 9.4 session
2. Verify log shows 0 ERRORs and expected NOTE lines
3. Confirm all five output files exist and are reviewable
4. Confirm CPT1 cross-tab is capped at 200 rows with title stating full count
5. Type "approved" to close the checkpoint

## Known Stubs

None -- Section B is fully implemented. The concept_decisions_EXT_TEMPLATE.csv CONFIRMED column is intentionally blank (human fills it after reviewing CONCEPT_EVIDENCE_EXT.xlsx).

## Next Steps

- Human review and SAS run (checkpoint)
- After human verify: commit docs/label_similarity_candidates.csv and docs/concept_decisions_EXT_TEMPLATE.csv as committed artifacts
- Phase 15 (Extend Harmonized Dataset): human fills CONFIRMED=YES in both template files, then Phase 15 machinery applies via 10b_concept_harmonize.sas

## Self-Check

- [x] sas/14_label_similarity.sas committed: 260c3e7
- [x] File is 832 lines (>= 220 required)
- [x] Contains SSDI_DEATH_DATE_Y_N, SSDI_DEATH_Y_N, SSDI_DEATH
- [x] Contains CPT1_CLASS, CPT1_LABEL
- [x] Contains CONCEPT_EVIDENCE_EXT.xlsx (not CONCEPT_EVIDENCE.xlsx in Section B)
- [x] Contains concept_decisions_EXT_TEMPLATE.csv
- [x] Contains `_n_ <= 200` (CPT1 cross-tab cap)
- [x] Contains `check_var_present` macro that aborts if vars missing
- [x] No bare %abort cancel in open code (only inside fail_out macro)
- [x] Program ends with %restore_log and NOTE for complete

## Self-Check: PASSED
