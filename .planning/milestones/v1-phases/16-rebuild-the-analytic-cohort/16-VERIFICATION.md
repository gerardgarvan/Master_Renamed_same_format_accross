---
phase: 16-rebuild-the-analytic-cohort
verified: 2026-09-22T00:00:00Z
status: human_needed
score: 7/8 must-haves verified (1 requires human confirmation)
human_verification:
  - test: "Confirm STATE.md non-ASCII introduction was pre-approved or acceptable"
    expected: "The three em-dash characters added by Plan 02 are acceptable given pre-existing non-ASCII in STATE.md, OR the file is corrected to pure ASCII"
    why_human: "Plan 02 requires 'Pure ASCII only' for STATE.md edits. Phase 16 introduced 3 additional non-ASCII bytes (UTF-8 em-dashes in status lines and progress bar). Pre-existing non-ASCII was 291 bytes; HEAD is 294. Cannot programmatically determine if this was intentional or an oversight."
  - test: "Confirm SAS run log shows 0 ERRORs and all assertions passed"
    expected: "16b_cohort_rebuild.log has 0 lines beginning with ERROR (excluding the cosmetic ERROR 180-322 noted in SUMMARY); g.analytic_cohort has 13,890 rows and 174 columns; g.master_data_harmonized confirmed unmodified post-run"
    why_human: "Log and runtime datasets are on the P: drive, not committed to git. Cannot verify log file programmatically from this codebase."
---

# Phase 16: Rebuild the Analytic Cohort -- Verification Report

**Phase Goal:** `g.analytic_cohort` is rebuilt from `g.master_data_harmonized` so all three datasets are in step, and the cohort decision itself is settled -- producing a verified g.analytic_cohort (13,890 rows, 174 columns) with a clean SAS run log, and PCM-D-05 resolved and attributed.

**Verified:** 2026-09-22
**Status:** human_needed
**Re-verification:** No -- initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria and PLAN must_haves)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | sas/16b_cohort_rebuild.sas reads g.master_data_harmonized and never writes it | VERIFIED | `set g.master_data_harmonized` appears 2x; DATA step writes only `work.cohort_candidate` and `g.analytic_cohort`; PCM-T-02 explicitly listed in header |
| 2 | g.analytic_cohort is rebuilt from g.master_data_harmonized restricted to INPATIENT+OBSERVATION rows (13,890) | VERIFIED (code) / HUMAN for runtime N | Filter `upcase(strip(Patient_Type)) in ('INPATIENT','OBSERVATION')` present; `data g.analytic_cohort; set work.cohort_candidate` at line 370-372; SUMMARY records 13,890 confirmed |
| 3 | g.analytic_cohort carries all 174 columns including every h_* column and no dropped alias | VERIFIED (code) | No KEEP/DROP in promotion DATA step; `%verify_cohort_cols` asserts `n_cohort_cols ne 174`; 11 h_* columns measured (H_SSDI_DEATH removed -- never harmonized, documented in SUMMARY) |
| 4 | Full-file complete-case Ns 12,726 / 20,540 / 23,311 are asserted and pass | VERIFIED | `%assert_complete_case_n` called 3x with `expected=12726`, `expected=20540`, `expected=23311`; SUMMARY records all three assertions PASSED |
| 5 | g.master_data_harmonized is confirmed unmodified (174 cols, 41,150 rows) after the run | VERIFIED (code) / HUMAN for runtime | `%assert_harmonized_unchanged` checks `n_cols ne 174 or n_rows ne 41150`; SUMMARY records PASS |
| 6 | docs/DECISIONS.md PCM-D-05 entry is resolved with attribution, BMI-forces-restriction rationale, PCM-F-12 named void, all five figures, BMI HAVE/LACK against 13,890 denominator | VERIFIED | All acceptance criteria greps pass; entry present at lines 29-71 of DECISIONS.md |
| 7 | STATE.md records measured within-cohort and all-three baselines; PCM-D-05 removed from Still open; Price follow-up item present | VERIFIED | grep confirms presence; "Still open: None" at line 226; Price follow-up at line 230-232 |
| 8 | STATE.md edits are pure ASCII | UNCERTAIN -- HUMAN NEEDED | 3 non-ASCII bytes introduced by Phase 16 edits (em-dashes in status/progress lines); plan required pure ASCII; pre-existing count was 291, HEAD is 294 |

**Score:** 7/8 truths verified (1 uncertain pending human confirmation)

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `sas/16b_cohort_rebuild.sas` | Cohort rebuild program, 200+ lines, reads g.master_data_harmonized | VERIFIED | 500 lines; all key patterns present; committed at 24cf514 |
| `docs/DECISIONS.md` | Resolved PCM-D-05 entry with full attribution and figures | VERIFIED | Entry present at lines 29-71; all acceptance criteria pass |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| sas/16b_cohort_rebuild.sas | g.master_data_harmonized | `set g.master_data_harmonized` in DATA step | WIRED | Line 156 (filter step); also queried in SECTION 4 assertions |
| sas/16b_cohort_rebuild.sas | g.analytic_cohort | `data g.analytic_cohort;` promote after gate | WIRED | Line 370-372; gate at line 367 runs BEFORE promotion |
| docs/DECISIONS.md PCM-D-05 entry | 16-01 QC output (16b_cohort_missingness.txt) | BMI HAVE/LACK percentages transcribed from measured QC values | WIRED | DECISIONS.md line 61-63: "HAVE Admit_BMI: 12,726 of 13,890 = 91.6% / LACK: 1,164 of 13,890 = 8.4%" matching 16-01-SUMMARY |

---

## Data-Flow Trace (Level 4)

Not applicable. The primary artifact is a SAS program (not a web component or dashboard). Data flow is verified structurally: the program reads g.master_data_harmonized via `set g.master_data_harmonized`, filters it, and writes to g.analytic_cohort. The SUMMARY records the verified runtime output.

---

## Behavioral Spot-Checks (Step 7b)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| SAS file has correct filter | `grep -c "upcase(strip(Patient_Type)) in ('INPATIENT','OBSERVATION')" sas/16b_cohort_rebuild.sas` | 1 | PASS |
| Gate runs before promotion | gate_on_status call at line 367; data g.analytic_cohort at line 370 | Gate precedes promotion | PASS |
| No SQLOBS | `grep -c "SQLOBS" sas/16b_cohort_rebuild.sas` | 0 | PASS |
| No assert_all_three | `grep -c "assert_all_three" sas/16b_cohort_rebuild.sas` | 0 | PASS |
| Log and runtime datasets | P: drive QC file not in repo | Cannot verify | SKIP (human) |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| HARM-10 | 16-01, 16-02 | g.analytic_cohort rebuilt from g.master_data_harmonized, carries h_* columns, no dropped aliases | SATISFIED | sas/16b_cohort_rebuild.sas exists and implements the full rebuild; 11 h_* columns measured; 174-column pass-through with no KEEP/DROP; SUMMARY records SAS run passed |
| PCM-D-05 | 16-02 | Cohort restriction resolved and attributed with correct rationale | SATISFIED | docs/DECISIONS.md entry resolved with: BMI-forces-restriction rationale, PCM-F-12 named void, all five Phase 13 population-shift figures, BMI HAVE/LACK against 13,890 denominator, Gerard attribution 2026-09-21, Price status "informed" |

**Orphaned requirements check:** REQUIREMENTS.md traceability table maps HARM-10 to "Phase 9 -- Variable Harmonization" with status "Pending" (the table was not updated). COH-01 through COH-04 (Phase 7, Pending) are the v1 cohort requirements. Phase 16 satisfies the spirit of COH-01 through COH-04 and HARM-10, but the traceability table in REQUIREMENTS.md still shows these as Pending. This is a documentation gap in REQUIREMENTS.md (not a code gap) and does not affect goal achievement.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `sas/16b_cohort_rebuild.sas` | 53 | `%abort cancel` inside `%macro check_dir` without a named wrapper | INFO | PCM-R-05 requires every `%abort cancel` inside a named macro; `%check_dir` IS a named macro, so this technically satisfies PCM-R-05. The pattern differs from `%fail_out` in that it does not restore ODS/PRINTTO first -- but `check_dir` runs before PRINTTO is redirected (per the comment at line 48), so no restore is needed. Not a violation. |
| `.planning/STATE.md` | 32, 34, 54 | Non-ASCII em-dash and Unicode block characters introduced by Phase 16 edits | WARNING | Plan 02 acceptance criteria requires `grep -nP "[^\x00-\x7F]" .planning/STATE.md introduces no new non-ASCII`. Phase 16 added 3 non-ASCII bytes. Pre-existing count was 291; HEAD is 294. New bytes appear in: "Phase complete -- ready for verification" (em-dash), progress bar (Unicode block), and "Last updated" line (em-dash). |

---

## H_SSDI_DEATH Deviation (Documented, Not a Gap)

Plan 16-01 specified measuring 12 h_* columns including H_SSDI_DEATH. Commit `0deaf18` removed H_SSDI_DEATH from the measurement loop with message "remove H_SSDI_DEATH from h_* measurement loop -- never harmonized." The SUMMARY explicitly records this: "H_SSDI_DEATH removed -- never harmonized into g.master_data_harmonized." The plan acceptance criteria `grep -c "H_SSDI_DEATH" >= 1` now fails, but this is an intentional documented fix. The RESEARCH.md called for 12 columns; the execution correctly determined only 11 exist in the harmonized dataset. This is resolved deviation, not a gap.

---

## Human Verification Required

### 1. STATE.md ASCII Compliance

**Test:** Review the three non-ASCII characters introduced by Phase 16 into STATE.md (lines 32, 34, and the "Last updated" line) and confirm whether this is acceptable given pre-existing non-ASCII content, or correct the file to pure ASCII.
**Expected:** Either (a) the 3 new bytes are deemed acceptable (pre-existing non-ASCII was already present so the file was already not pure ASCII, and the plan acceptance criteria was aspirational), or (b) the status/progress lines are rewritten replacing em-dashes with "--" and the progress bar with ASCII characters.
**Why human:** Cannot determine intent from code alone. The plan required pure ASCII but the file had 291 non-ASCII bytes before Phase 16's edits. Determining whether the 3 new bytes are a violation or an acceptable continuation requires a judgment call.

### 2. SAS Run Log Confirmation

**Test:** Confirm `P:\...\logs\16b_cohort_rebuild.log` has 0 lines starting with "ERROR" (excluding the cosmetic ERROR 180-322 for a split %put, documented in SUMMARY). Confirm g.analytic_cohort has 13,890 rows and 174 columns in the P: library.
**Expected:** Log shows 0 true ERRORs; g.analytic_cohort = 13,890 rows, 174 cols; g.master_data_harmonized = 41,150 rows, 174 cols post-run.
**Why human:** Run-time artifacts (log file, g.* datasets) are on the P: drive and excluded from git. The SUMMARY records a human-verified run on 2026-09-22 with all assertions passing; this item confirms the record is accurate.

---

## Gaps Summary

No blocking gaps were found. All must-have SAS program patterns are verified in code. The PCM-D-05 DECISIONS.md entry passes all acceptance criteria greps. STATE.md records the required baselines and has PCM-D-05 removed from the "Still open" block.

Two items are routed to human verification:
1. A minor ASCII compliance question in STATE.md (3 em-dash chars introduced by Phase 16; pre-existing non-ASCII already existed).
2. Confirmation that the documented SAS run log (referenced in SUMMARY) matches expected outcomes -- a standard runtime verification that cannot be confirmed from the git-committed codebase alone.

Neither item is expected to block goal achievement; the SUMMARY documents a clean human-verified SAS run with all assertions passing.

---

_Verified: 2026-09-22_
_Verifier: Claude (gsd-verifier)_
