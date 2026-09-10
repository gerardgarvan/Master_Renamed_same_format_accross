---
phase: 14-label-similarity-sweep
verified: 2026-08-29T00:00:00Z
status: gaps_found
score: 4/6 must-haves verified
re_verification: false
gaps:
  - truth: "Candidate pairs are written to docs/label_similarity_candidates.csv with the required columns so a human can judge the match"
    status: failed
    reason: "The CSV file does not exist in docs/. It is a runtime output of the SAS program, and it is also excluded by the *.csv .gitignore rule. The SUMMARY notes it must be force-added with `git add -f`. As of this verification no committed artifact exists."
    artifacts:
      - path: "docs/label_similarity_candidates.csv"
        issue: "File absent from disk entirely -- SAS program has not been run, or run output was never committed"
    missing:
      - "Run sas/14_label_similarity.sas in a SAS 9.4 session against g.master_data_harmonized to produce the file"
      - "Force-commit with: git add -f docs/label_similarity_candidates.csv && git commit"
  - truth: "A concept decisions template CSV is written for SSDI and CPT1 groups that Phase 15 can consume"
    status: failed
    reason: "docs/concept_decisions_EXT_TEMPLATE.csv does not exist on disk. Same cause as label_similarity_candidates.csv -- runtime output not yet produced or committed. HARM-09 requires this artifact to be present for Phase 15 to run."
    artifacts:
      - path: "docs/concept_decisions_EXT_TEMPLATE.csv"
        issue: "File absent from disk -- SAS program not yet run or runtime outputs not committed"
    missing:
      - "Run sas/14_label_similarity.sas to produce the file"
      - "Force-commit with: git add -f docs/concept_decisions_EXT_TEMPLATE.csv && git commit"
human_verification:
  - test: "Run sas/14_label_similarity.sas in a fresh SAS 9.4 session"
    expected: "Log shows 0 ERRORs; NOTE: ==== 14_label_similarity.sas complete (Section A + Section B) ==== appears; docs/label_similarity_candidates.csv and docs/concept_decisions_EXT_TEMPLATE.csv written to docs_path"
    why_human: "Cannot execute SAS in this environment; requires live SAS 9.4 session with g.master_data_harmonized loaded"
  - test: "Open docs/label_similarity_candidates.csv after SAS run and count rows"
    expected: "Fewer than 100 rows (tractable); columns: varname_a, label_a, source_a, varname_b, label_b, source_b, score_edit, score_jaccard, confirmed, notes; Death_Date_Y_N / IsDead_Y_N pair does NOT appear (it is a known pair, excluded)"
    why_human: "File does not exist until SAS runs; threshold calibration is empirical"
  - test: "Open docs/concept_decisions_EXT_TEMPLATE.csv after SAS run"
    expected: "Header row exactly: concept,varname,value_txt,target_value,confirmed,harmonized_name,priority; rows for SSDI_DEATH_FLAG and CPT1_CODE_LABEL concepts present; CONFIRMED column blank"
    why_human: "File does not exist until SAS runs; schema correctness cannot be verified from code alone"
---

# Phase 14: Label-Similarity Sweep Verification Report

**Phase Goal:** Find same-concept variable pairs whose names share nothing by comparing their SAS labels. Produce a human-reviewable candidate list and concept profiles for SSDI death family and CPT1 code/label pair.
**Verified:** 2026-08-29
**Status:** gaps_found
**Re-verification:** No -- initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every variable label in g.master_data_harmonized is compared against every other using COMPLEV/Jaccard; no pair is skipped | VERIFIED | Line 390: `complev(upcase(...))` + Jaccard word-set PROC SQL; self-join `where a.varname < b.varname` covers all N*(N-1)/2 pairs |
| 2 | Canonical names are drawn from docs/precede_dictionary.csv (sas_name + description columns), never from VARIABLE_RECTIFICATION.xlsx | VERIFIED | Line 106: fileexist check for precede_dictionary.csv; line 134: comment explicitly states NOT from VARIABLE_RECTIFICATION.xlsx; no PROC IMPORT referencing VARIABLE_RECTIFICATION |
| 3 | Candidate pairs are written to docs/label_similarity_candidates.csv with required columns for human review | FAILED | File absent from disk. Program writes it at runtime; `.gitignore` excludes `*.csv`. SUMMARY acknowledges it requires `git add -f`. No committed artifact exists. |
| 4 | Similarity measure and threshold are stated as %let macro variables and appear in qc/14_label_similarity.txt | VERIFIED | Line 73: `%let threshold = 0.20;` Line 79: `%let jaccard_threshold = 0.34;` Line 641: file write to `&qc_path.\14_label_similarity.txt` with threshold logged |
| 5 | Pairs already in Phase 10 concept groups are excluded; exclusion count logged | VERIFIED | Lines 334+: `work.known_pairs` derived via self-join of `work.concepts`; line 520: NOT EXISTS subquery; `%let n_excluded = %eval(&n_above_threshold - &n_candidates)` logged |
| 6 | A concept decisions template CSV is written for SSDI and CPT1 groups that Phase 15 can consume | FAILED | docs/concept_decisions_EXT_TEMPLATE.csv absent from disk. Same runtime-output cause as truth 3. |

**Score: 4/6 truths verified**

---

### Required Artifacts

| Artifact | Min Lines | Status | Details |
|----------|-----------|--------|---------|
| `sas/14_label_similarity.sas` | 220 (plan 02) | VERIFIED | 1037 lines on disk; Section A (label sweep) + Section B (SSDI/CPT1) both present |
| `docs/label_similarity_candidates.csv` | -- | MISSING | Not on disk; runtime output excluded by `*.csv` in .gitignore; not force-committed |
| `docs/concept_decisions_EXT_TEMPLATE.csv` | -- | MISSING | Not on disk; same cause |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `sas/14_label_similarity.sas` | `docs/precede_dictionary.csv` | PROC IMPORT; sas_name column join | WIRED | Lines 138+: `proc import datafile="&docs_path.\precede_dictionary.csv"` with `guessingrows=max`; join on `l.varname = d.sas_name` |
| `sas/14_label_similarity.sas` | `dictionary.columns` | PROC SQL WHERE libname='G' and memname='MASTER_DATA_HARMONIZED' | WIRED | Lines 184+: exact WHERE clause; labels and types extracted |
| `sas/14_label_similarity.sas` | `docs/label_similarity_candidates.csv` | PROC EXPORT + fileexist check | PARTIAL | Code is wired and correct; file not yet produced (requires SAS run) |
| `sas/14_label_similarity.sas` | `docs/concept_decisions_EXT_TEMPLATE.csv` | PROC EXPORT; 10b-schema value-level rows | PARTIAL | Code is wired; file not yet produced |
| `sas/14_label_similarity.sas` | `g.master_data_harmonized` (SSDI/CPT1) | PROC SQL SELECT DISTINCT on SSDI_DEATH_DATE_Y_N, SSDI_DEATH_Y_N, SSDI_DEATH, CPT1_CLASS, CPT1_LABEL | WIRED | Lines 710-714: five `%check_var_present` calls; lines 784+: value inventory queries |

---

### Data-Flow Trace (Level 4)

This phase produces SAS programs and CSV artifacts, not rendered UI components. Level 4 data-flow trace is not applicable. The relevant data-flow is: `g.master_data_harmonized` -> SAS program -> CSV files on disk. The SAS program wiring is verified (Level 3 above); the CSV files are absent because the SAS program has not been run.

---

### Behavioral Spot-Checks

Step 7b: SKIPPED for SAS-producing programs -- cannot execute SAS 9.4 in this environment. Human verification required (see below).

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| HARM-02 | 14-01 | Canonical names sourced from docs/precede_dictionary.csv only; VARIABLE_RECTIFICATION.xlsx not used as crosswalk | SATISFIED | `precede_dictionary.csv` imported and joined; VARIABLE_RECTIFICATION appears only in a comment noting it is NOT the source |
| HARM-03 | 14-01 | Label-similarity sweep reports same-concept aliases whose names share nothing | PARTIAL | Sweep program is complete and substantive; candidate output CSV not yet produced/committed |
| HARM-09 | 14-02 | SSDI death family and CPT1 pair added and profiled | PARTIAL | Section B implementation is complete (check_var_present, value inventory, cross-tab, EXT template); template CSV not yet on disk |

No orphaned requirements: REQUIREMENTS.md maps HARM-02 (Phase 9) and HARM-03 (Phase 9) and HARM-09 (Phase 14). All three are claimed by the 14-01 and 14-02 PLANs. The traceability table in REQUIREMENTS.md lists HARM-02 and HARM-03 as Phase 9, which is an artifact of the original numbering described in the v1.1 scope note ("Phases 14-16 renumbered from 9-11"). Both are marked [x] (complete) in REQUIREMENTS.md body text, consistent with the program being written. HARM-09 is also marked [x].

---

### Anti-Patterns Found

| File | Finding | Severity | Impact |
|------|---------|----------|--------|
| `sas/14_label_similarity.sas` line 27 | Comment states "No &SQLOBS" -- confirmed absent from executable code | Info | No issue; it is a compliance declaration |
| `sas/14_label_similarity.sas` | `VARIABLE_RECTIFICATION` appears only in a comment explaining it is NOT the source | Info | No issue; the program correctly avoids it |
| `docs/label_similarity_candidates.csv` | File entirely absent | Blocker | Phase goal requires a human-reviewable committed artifact; it does not exist |
| `docs/concept_decisions_EXT_TEMPLATE.csv` | File entirely absent | Blocker | Phase 15 cannot run without this decision template |

No TODO/FIXME/placeholder comments found in Section A or Section B of the SAS program. The Section B placeholder from Plan 01 was correctly replaced in Plan 02. No empty handlers, no hardcoded return null/[]/{}. PCM compliance rules verified: `%abort cancel` only inside named macros (fail_out, check_var_present, assert_one_row_per_var, check_csv_written, check_dict, check_pairs); no `&SQLOBS`; no `data g.master_data_harmonized` as a write target.

---

### Human Verification Required

#### 1. SAS Program Execution

**Test:** Open a fresh SAS 9.4 session; ensure `g` library is assigned and points to the harmonized dataset; submit `C:\Master_Renamed_same_format_accross\sas\14_label_similarity.sas`
**Expected:** Log has 0 ERROR lines; ends with `NOTE: ==== 14_label_similarity.sas complete (Section A + Section B) ====`; five NOTE lines confirm presence of SSDI and CPT1 variables; `NOTE: [14] CONFIRMED: docs/label_similarity_candidates.csv written.` and `NOTE: [14] CONFIRMED: docs/concept_decisions_EXT_TEMPLATE.csv written.` appear
**Why human:** Cannot execute SAS in this environment

#### 2. Candidate CSV Review

**Test:** After SAS run, open `docs/label_similarity_candidates.csv`
**Expected:** Fewer than 100 rows (tractable at threshold=0.20); columns present: varname_a, label_a, source_a, varname_b, label_b, source_b, score_edit, score_jaccard, confirmed, notes; `Death_Date_Y_N` / `IsDead_Y_N` pair does NOT appear (must be excluded as a known pair)
**Why human:** File requires SAS run to exist; threshold calibration and pair exclusion must be verified empirically

#### 3. Concept Decisions Template Schema

**Test:** After SAS run, open `docs/concept_decisions_EXT_TEMPLATE.csv`
**Expected:** Header row exactly: `concept,varname,value_txt,target_value,confirmed,harmonized_name,priority`; rows for SSDI_DEATH_FLAG (SSDI_DEATH_DATE_Y_N, SSDI_DEATH_Y_N, SSDI_DEATH) and CPT1_CODE_LABEL (CPT1_CLASS, CPT1_LABEL) present; CONFIRMED column blank throughout; priorities are non-tied within each concept group
**Why human:** File requires SAS run; schema correctness against 10b_concept_harmonize.sas is a functional dependency that cannot be verified by static analysis

#### 4. Force-commit the CSV artifacts

**Test:** After verifying outputs, run: `git add -f docs/label_similarity_candidates.csv docs/concept_decisions_EXT_TEMPLATE.csv && git commit -m "feat(14): commit label similarity candidates and SSDI/CPT1 decision template"`
**Expected:** Both files appear in `git show --stat HEAD`
**Why human:** Requires judgment that the file contents are correct before committing; `git add -f` bypasses .gitignore and should only be run after review

---

### Gaps Summary

The SAS program (`sas/14_label_similarity.sas`, 1037 lines) is complete, substantive, and correctly wired. Both Section A (label sweep, HARM-02 / HARM-03) and Section B (SSDI/CPT1 profiling, HARM-09) are fully implemented with PCM-compliant patterns.

The two blocker gaps share a single root cause: **the SAS program has not been executed against a live SAS session, so its runtime outputs do not exist on disk**. The phase goal requires two committed CSV artifacts (`docs/label_similarity_candidates.csv` and `docs/concept_decisions_EXT_TEMPLATE.csv`) that are produced only when the program runs. Both are excluded by the project's `*.csv` .gitignore rule and require a manual `git add -f` after the SAS run.

The SUMMARY for Plan 02 records a human checkpoint as "APPROVED" and documents this exact situation, including the `git add -f` command needed. The gap is not a code defect -- it is an unfinished deployment step. Closing the gaps requires: (1) running the SAS program in a live session, (2) verifying the outputs are correct, and (3) force-committing the two CSVs.

---

_Verified: 2026-08-29_
_Verifier: Claude (gsd-verifier)_
