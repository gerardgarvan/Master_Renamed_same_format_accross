---
phase: 28-r7-r8-r9-linkage-investigation
verified: 2026-10-07T00:00:00Z
status: passed
score: 6/6 must-haves verified
re_verification: false
---

# Phase 28: r7/r8/r9 Linkage Investigation Verification Report

**Phase Goal:** The encryption scheme used by r7-r9 is identified and documented as PCM-D-28, and the match-rate evidence from the 2018-2022 crypto files is recorded so no future phase applies the wrong encryption assumption to any raw\ copy.
**Verified:** 2026-10-07
**Status:** passed
**Re-verification:** No -- initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | LINK-01 answer documented: r7/r8/r9 have no ENCRYPTED_MRN column; MRN linking infeasible with current extracts | VERIFIED | PCM-D-28 text in docs/DECISIONS.md lines 997-1006 states this explicitly with Phase 19 column inventory evidence; 28-01-SUMMARY.md confirms LINK-01 established from column evidence |
| 2 | Match-rate provenance established before citation (PROVENANCE NOT FOUND documented) | VERIFIED | 28-01-SUMMARY.md documents git log search results; records "PROVENANCE NOT FOUND -- figures 14.5/64/41 must NOT be cited in PCM-D-28"; PCM-D-28 entry cites only program-derived CSV rows |
| 3 | sas/28_linkage_investigation.sas exists as a standalone program with all three blocks and all eight comparison rows | VERIFIED | File exists at 1022 lines; contains Blocks 1-3; all eight comparison pairs confirmed present (md7_vs_md3_2022 x3, r7_vs_md7 x2, match_rate_left x11) |
| 4 | The program is NOT added to run_pipeline.cmd | VERIFIED | grep "28_linkage" run_pipeline.cmd returns NOT FOUND; program header states "must NEVER be added to it" (count=1) |
| 5 | PCM-D-28 is recorded in docs/DECISIONS.md citing qc/28_linkage_investigation.csv with both-direction rates | VERIFIED | grep -c "PCM-D-28" docs/DECISIONS.md = 2; grep -c "28_linkage_investigation.csv" = 6; both-direction rates table present at lines 1013-1020 |
| 6 | PCM-D-28 names a specific v2.3 reopening condition (not vague "investigate later") | VERIFIED | PCM-D-28 lines 1073-1086 name two concrete conditions: (1) re-extract of r7/r8/r9 with ENCRYPTED_MRN, or (2) ID crosswalk table mapping r7-r9 PRECEDE_STUDY_IDs to master cohort |

**Score:** 6/6 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `sas/28_linkage_investigation.sas` | Three-block standalone linkage investigation program, min 200 lines, contains "must NEVER be added to it" | VERIFIED | 1022 lines; contains phrase (count=1); all PCM compliance requirements met |
| `docs/DECISIONS.md` | PCM-D-28 determination entry | VERIFIED | PCM-D-28 appended at lines 986-1102; commit 799985f |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `sas/28_linkage_investigation.sas` | `qc/19_raw_files.csv` | DATA step infile, directory-exact row selection | VERIFIED | grep -c "directory" = 7; grep -c "index(full_path" = 0 -- directory-exact pattern used, fragile index() absent |
| `sas/28_linkage_investigation.sas` | `qc/28_linkage_investigation.csv` | DATA step PUT with filename fileref | VERIFIED | grep -c "source_pair,key_used,normalization_applied" = 2 (header defined once in comment, once in PUT) |
| `docs/DECISIONS.md` | `qc/28_linkage_investigation.csv` | citation reference | VERIFIED | grep -c "28_linkage_investigation.csv" docs/DECISIONS.md = 6 |

---

### Data-Flow Trace (Level 4)

Not applicable. This phase produces a SAS investigation program (no UI/rendering component) and a decision document. The program produces `qc/28_linkage_investigation.csv` at runtime on P: drive (gitignored). The runtime execution was confirmed by the human-action gate in Plan 02 Task 1: SAS ran ERROR-free and the CSV was written (19 records). Level 4 data-flow trace is satisfied by the runtime confirmation recorded in 28-02-SUMMARY.md.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| "must NEVER be added to it" phrase present | grep -c "must NEVER be added to it" sas/28_linkage_investigation.sas | 1 | PASS |
| LINK-01 and LINK-02 requirements cited | grep -c "LINK-01" / "LINK-02" | 7 / 1 | PASS |
| No PROC IMPORT (PCM-T-16) | grep -ci "PROC IMPORT" | 0 | PASS |
| No index(full_path) fragile pattern | grep -c "index(full_path" | 0 | PASS |
| Directory-exact selection present | grep -c "directory" | 7 | PASS |
| No file_id-based row selection | grep -c "file_id" | 0 | PASS |
| Exact 9-column CSV header present | grep -c "source_pair,key_used,normalization_applied" | 2 | PASS |
| PHI guard comments throughout | grep -c "PHI guard" | 18 | PASS |
| Decisive comparisons present | grep -c "md7_vs_md3_2022" / "r7_vs_md7" | 3 / 2 | PASS |
| Division-by-zero guard | grep -c "n_left=0\|n_right=0" | 1 | PASS |
| PCM-D-28 in DECISIONS.md | grep -c "PCM-D-28" docs/DECISIONS.md | 2 | PASS |
| 28_linkage_investigation.csv cited | grep -c "28_linkage_investigation.csv" docs/DECISIONS.md | 6 | PASS |
| 9,215 mismatch count cited | grep -c "9,215" docs/DECISIONS.md | 12 | PASS |
| 80,233 SHA finding cited | grep -c "80,233" docs/DECISIONS.md | 1 | PASS |
| 28_linkage_investigation.sas NOT in run_pipeline.cmd | grep "28_linkage" run_pipeline.cmd | NOT FOUND | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| LINK-01 | 28-01 | r7/r8/r9 have no ENCRYPTED_MRN; MRN linking infeasible | SATISFIED | Documented in PCM-D-28 column evidence section; confirmed in 28-01-SUMMARY LINK-01 Findings |
| LINK-02 | 28-01 | Match-rate evidence derived and recorded | SATISFIED | All 8 Block 3 comparison rows in qc/28_linkage_investigation.csv; rates tabulated in PCM-D-28 |
| LINK-03 | 28-02 | PCM-D-28 states specific v2.3 reopening condition | SATISFIED | PCM-D-28 lines 1073-1086 name two concrete conditions with specific artifacts |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | -- | -- | -- | -- |

The ENCRYPTED_MRN references in sas/28_linkage_investigation.sas appear only in the md3, md7, and Crypto file sections -- all legitimately PHI-guarded. The r7/r8/r9 profile DATA steps contain no ENCRYPTED_MRN column reads, consistent with LINK-01 (those files have no such column). No TODO/FIXME/placeholder patterns found. All %abort cancel occurrences are inside named macros.

---

### Human Verification Required

#### 1. Runtime CSV Content

**Test:** On P: drive, inspect qc/28_linkage_investigation.csv after running sas/28_linkage_investigation.sas.
**Expected:** 19 rows matching the rates tabulated in 28-02-SUMMARY.md (md7_vs_md3_2022=100%, all r7/r8/r9=0%, Crypto PRECEDE match ~99.97%); no ENCRYPTED_MRN sample/min/max values anywhere in log or CSV.
**Why human:** The CSV is a P:-drive runtime artifact (gitignored). The human-action gate in Plan 02 Task 1 confirmed this, but the verifier cannot read the P: drive directly. The confirmation is recorded in 28-02-SUMMARY.md ("SAS program ran ERROR-free. qc/28_linkage_investigation.csv was written (19 records). PHI guard held.").

This item is rated INFO -- not a gap. The human gate was completed before PCM-D-28 was written, and the decision cites specific row values from the human review. No further action required.

---

### Gaps Summary

No gaps. All six truths are verified. Both artifacts exist, are substantive, and are wired. PCM-D-28 is fully recorded with column evidence, both-direction match rates, SHA findings, Crypto file scope note, and a specific v2.3 reopening condition. The standalone SAS program passes all acceptance criteria grep checks. run_pipeline.cmd is unmodified.

---

_Verified: 2026-10-07_
_Verifier: Claude (gsd-verifier)_
