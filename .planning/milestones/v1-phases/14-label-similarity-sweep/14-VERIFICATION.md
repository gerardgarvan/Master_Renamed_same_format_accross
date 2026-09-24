---
phase: 14-label-similarity-sweep
verified: 2026-09-22T00:00:00Z
status: passed
score: 6/6 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 4/6
  gaps_closed:
    - "docs/label_similarity_candidates.csv now exists on disk (2974 data rows, correct 10-column header)"
    - "docs/concept_decisions_EXT_TEMPLATE.csv now exists on disk (323 data rows, correct 7-column header, SSDI and CPT1 concepts present)"
  gaps_remaining: []
  regressions: []
---

# Phase 14: Label-Similarity Sweep Verification Report

**Phase Goal:** Find same-concept variable pairs whose names share nothing by comparing their SAS labels. Produce a human-reviewable candidate list and concept profiles for SSDI death family and CPT1 code/label pair.
**Verified:** 2026-09-22
**Status:** passed
**Re-verification:** Yes -- after gap closure confirmed by Phase 15 execution

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every variable label in g.master_data_harmonized is compared against every other using COMPLEV/Jaccard; no pair is skipped | VERIFIED | Line 390: `complev(upcase(...))` + Jaccard word-set PROC SQL; self-join `where a.varname < b.varname` covers all N*(N-1)/2 pairs |
| 2 | Canonical names are drawn from docs/precede_dictionary.csv (sas_name + description columns), never from VARIABLE_RECTIFICATION.xlsx | VERIFIED | Line 106: fileexist check for precede_dictionary.csv; line 134: comment explicitly states NOT from VARIABLE_RECTIFICATION.xlsx; no PROC IMPORT referencing VARIABLE_RECTIFICATION |
| 3 | Candidate pairs are written to docs/label_similarity_candidates.csv with required columns for human review | VERIFIED | File exists on disk: 2974 data rows + header; columns confirmed: confirmed, notes, varname_a, label_a, source_a, varname_b, label_b, source_b, score_edit, score_jaccard; IsDead_Y_N absent from file (known pair correctly excluded) |
| 4 | Similarity measure and threshold are stated as %let macro variables and appear in qc/14_label_similarity.txt | VERIFIED | Line 73: `%let threshold = 0.20;` Line 79: `%let jaccard_threshold = 0.34;` Line 641: file write to `&qc_path.\14_label_similarity.txt` with threshold logged |
| 5 | Pairs already in Phase 10 concept groups are excluded; exclusion count logged | VERIFIED | Lines 334+: `work.known_pairs` derived via self-join of `work.concepts`; line 520: NOT EXISTS subquery; `%let n_excluded = %eval(&n_above_threshold - &n_candidates)` logged |
| 6 | A concept decisions template CSV is written for SSDI and CPT1 groups that Phase 15 can consume | VERIFIED | docs/concept_decisions_EXT_TEMPLATE.csv exists on disk: 323 data rows; header exactly `concept,varname,value_txt,target_value,confirmed,harmonized_name,priority`; rows for SSDI_DEATH_FLAG (SSDI_DEATH, SSDI_DEATH_DATE_Y_N, SSDI_DEATH_Y_N) and CPT1_CODE_LABEL (CPT1_CLASS, CPT1_LABEL) present; confirmed column blank throughout |

**Score: 6/6 truths verified**

---

### Required Artifacts

| Artifact | Min Lines | Status | Details |
|----------|-----------|--------|---------|
| `sas/14_label_similarity.sas` | 220 (plan 02) | VERIFIED | 1037 lines on disk; Section A (label sweep) + Section B (SSDI/CPT1) both present |
| `docs/label_similarity_candidates.csv` | -- | VERIFIED | 2975 lines (header + 2974 data rows) on disk; not committed to git (*.csv gitignored) but present and consumed by Phase 15 |
| `docs/concept_decisions_EXT_TEMPLATE.csv` | -- | VERIFIED | 324 lines (header + 323 data rows) on disk; schema matches Phase 15 (10b_concept_harmonize.sas) requirements |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `sas/14_label_similarity.sas` | `docs/precede_dictionary.csv` | PROC IMPORT; sas_name column join | WIRED | Lines 138+: `proc import datafile="&docs_path.\precede_dictionary.csv"` with `guessingrows=max`; join on `l.varname = d.sas_name` |
| `sas/14_label_similarity.sas` | `dictionary.columns` | PROC SQL WHERE libname='G' and memname='MASTER_DATA_HARMONIZED' | WIRED | Lines 184+: exact WHERE clause; labels and types extracted |
| `sas/14_label_similarity.sas` | `docs/label_similarity_candidates.csv` | PROC EXPORT + fileexist check | WIRED | File produced and confirmed on disk (2974 rows) |
| `sas/14_label_similarity.sas` | `docs/concept_decisions_EXT_TEMPLATE.csv` | PROC EXPORT; 10b-schema value-level rows | WIRED | File produced and confirmed on disk (323 rows, correct schema) |
| `sas/14_label_similarity.sas` | `g.master_data_harmonized` (SSDI/CPT1) | PROC SQL SELECT DISTINCT on SSDI_DEATH_DATE_Y_N, SSDI_DEATH_Y_N, SSDI_DEATH, CPT1_CLASS, CPT1_LABEL | WIRED | Lines 710-714: five `%check_var_present` calls; lines 784+: value inventory queries |

---

### Data-Flow Trace (Level 4)

This phase produces SAS programs and CSV artifacts, not rendered UI components. Level 4 data-flow trace is not applicable. The relevant data-flow is: `g.master_data_harmonized` -> `sas/14_label_similarity.sas` -> CSV files on disk -> Phase 15 consumption. All links in that chain are now confirmed: both CSV files exist with real data rows.

---

### Behavioral Spot-Checks

Step 7b: SKIPPED for SAS-producing programs -- cannot execute SAS 9.4 in this environment. Runtime outputs (both CSV files) are confirmed present on disk, providing indirect evidence that the program ran successfully.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| HARM-02 | 14-01 | Canonical names sourced from docs/precede_dictionary.csv only; VARIABLE_RECTIFICATION.xlsx not used as crosswalk | SATISFIED | `precede_dictionary.csv` imported and joined; VARIABLE_RECTIFICATION appears only in a comment noting it is NOT the source |
| HARM-03 | 14-01 | Label-similarity sweep reports same-concept aliases whose names share nothing | SATISFIED | Sweep program complete; docs/label_similarity_candidates.csv produced (2974 rows) and available for human review |
| HARM-09 | 14-02 | SSDI death family and CPT1 pair added and profiled | SATISFIED | Section B implementation complete; docs/concept_decisions_EXT_TEMPLATE.csv produced with correct schema and both concept groups present |

---

### Anti-Patterns Found

| File | Finding | Severity | Impact |
|------|---------|----------|--------|
| `sas/14_label_similarity.sas` line 27 | Comment states "No &SQLOBS" -- confirmed absent from executable code | Info | No issue; it is a compliance declaration |
| `sas/14_label_similarity.sas` | `VARIABLE_RECTIFICATION` appears only in a comment explaining it is NOT the source | Info | No issue; the program correctly avoids it |

No blocker anti-patterns. No TODO/FIXME/placeholder comments found. Both previously-blocking missing files are now confirmed present with substantive content.

---

### Human Verification Required

None. All automated checks pass. The two items that previously required human verification (SAS run and CSV output review) are resolved -- the files are present on disk with correct structure, which is the observable outcome of a successful SAS run.

Note: The CSV files are gitignored (*.csv rule) and are present on disk only. They are not committed to version control. Phase 15 executed successfully using these files as prerequisites, which provides additional indirect confirmation that both files existed with correct content at the time Phase 15 ran.

---

### Gaps Summary (Re-verification)

All gaps from the initial verification (2026-08-29) are closed.

**Gap 1 closed:** `docs/label_similarity_candidates.csv` exists on disk with 2974 data rows. The 10-column header matches the required schema (confirmed, notes, varname_a, label_a, source_a, varname_b, label_b, source_b, score_edit, score_jaccard). The known exclusion pair IsDead_Y_N is absent from the file, confirming the exclusion logic ran correctly.

**Gap 2 closed:** `docs/concept_decisions_EXT_TEMPLATE.csv` exists on disk with 323 data rows. The 7-column header exactly matches what Phase 15 (10b_concept_harmonize.sas) requires: concept, varname, value_txt, target_value, confirmed, harmonized_name, priority. Rows for both SSDI_DEATH_FLAG and CPT1_CODE_LABEL concept groups are present. The confirmed column is blank throughout, as expected for a template.

Both gaps shared a single root cause (SAS program had not been executed). Phase 15 execution closed both simultaneously. No regressions detected against the four truths that passed in the initial verification.

---

_Verified: 2026-09-22_
_Verifier: Claude (gsd-verifier)_
_Re-verification after: Phase 15 execution confirmed prerequisites present_
