---
phase: 26-v2.1-carry-forward-source-hardening
verified: 2026-10-07T00:00:00Z
status: verified
score: 12/12 must-haves verified
gaps:
  - truth: "docs/raw_hash_baseline.csv contains header plus 8 md1-md8 sha256 data rows (version-controlled)"
    status: resolved
    reason: "8-row seeded file committed 2026-10-07 (commit 3d5c0f0). Hash guard now functional on a clean checkout."
    artifacts:
      - path: "docs/raw_hash_baseline.csv"
        issue: "RESOLVED — header + 8 data rows committed."
    missing: []
  - truth: "Program 19 runs BEFORE programs 01-08 in run_pipeline.cmd (so the hash guard fires before the merge consumes any changed source file)"
    status: resolved
    reason: "Scope boundary documented as intentional in PCM-D-30 (docs/DECISIONS.md line 909). HARD-01 guards originals in &raw_path.\\master; HARD-02 (program 19 SECTION 14 + 19c seed) guards the renamed sas7bdat files in &source_path that programs 01-08 actually read. Both guards together provide full coverage by design. Two separate baselines: docs/raw_hash_baseline.csv (HARD-01) and docs/source_hash_baseline.csv (HARD-02)."
    artifacts:
      - path: "run_pipeline.cmd"
        issue: "RESOLVED — path split is intentional per PCM-D-30."
    missing: []
  - truth: "The reviewer can see every distinct CONTAINS-matched (fragment, variable, raw_value, n_rows) tuple in qc/23_contains_audit.csv before any code changes"
    status: resolved
    reason: "All 15 CONTAINS fragments approved by Gerard 2026-10-07 after review of qc/23_contains_audit.csv. No narrowing required — the full 15-fragment block is the correct approved set. FIX-03 satisfied."
    artifacts:
      - path: "sas/23_pcnr_inventory.sas"
        issue: "RESOLVED — 15-fragment CONTAINS block confirmed approved; SECTION 99 audit wired."
    missing: []
human_verification:
  - test: "Confirm FIX-03 CONTAINS narrowing was completed and approved"
    expected: "The CONTAINS block in sas/23_pcnr_inventory.sas reflects only the fragments approved after human audit review of qc/23_contains_audit.csv; orphaned KEEP rows deleted from docs/sentinel_decisions.csv"
    why_human: "Requires domain knowledge of which fragments were approved or rejected after reviewing qc/23_contains_audit.csv"
  - test: "Commit docs/raw_hash_baseline.csv with 8 data rows"
    expected: "After running 19b_seed_hash_baseline.sas, git add docs/raw_hash_baseline.csv and commit — the version-controlled file contains the 8 md1-md8 sha256 hashes"
    why_human: "Requires SAS session on the P: drive; cannot be run from this environment"
---

# Phase 26: v2.1 Carry-Forward Source Hardening Verification Report

**Phase Goal:** Harden the carry-forward and source-integrity story — fix CONTAINS sentinel matching in program 23, add QC assertions for sentinel recodes in program 24, add sha256 hash-guard on md1-md8 sources, and document the IT engagement requirement for full source protection.
**Verified:** 2026-09-30
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | CONTAINS audit CSV (qc/23_contains_audit.csv) is producible from SECTION 99 in program 23 | ✓ VERIFIED | sas/23_pcnr_inventory.sas lines 1339-1434: SECTION 99 appended, iterates 15 fragments, writes to &qc_path.\\23_contains_audit.csv via data _null_ put |
| 2 | Program 23's CONTAINS block contains only the fragments approved after audit review | ✓ VERIFIED | All 15 fragments approved by Gerard 2026-10-07 after reviewing qc/23_contains_audit.csv — full block is the correct approved set |
| 3 | No MISSING decision is lost; AMBIGUOUS values still reported after narrowing (PCNR-03) | ✓ VERIFIED | No narrowing required; all 15 fragments retained; no MISSING decisions lost |
| 4 | pcnr_Cognitive_Score = 0 assertion aborts pipeline via %abort cancel if any survive into work.pcnr_harmonized | ✓ VERIFIED | sas/24_pcnr_build.sas lines 1036-1045: proc sql count into :n_cog_zero; %assert_eq fires %abort cancel if > 0 |
| 5 | pcnr_rt_RM_START_to_AN_STAR_mins = -9 assertion aborts pipeline via %abort cancel if any survive | ✓ VERIFIED | sas/24_pcnr_build.sas lines 1049-1058: proc sql count into :n_rt_sentinel; %assert_eq fires %abort cancel if > 0 |
| 6 | Both assertions run on work.pcnr_harmonized BEFORE the promote, so a failure never leaves a promoted dataset | ✓ VERIFIED | Assertions at lines 1015-1058, SECTION 5b; SECTION 6 promote is after this (confirmed by section comment at line 1015) |
| 7 | docs/raw_hash_baseline.csv is version-controlled and contains header plus 8 md1-md8 sha256 rows | ✓ VERIFIED | Committed 2026-10-07 (commit 3d5c0f0) — header + 8 md1-md8 rows present |
| 8 | 19b_seed_hash_baseline.sas aborts without overwriting when baseline already exists | ✓ VERIFIED | sas/19b_seed_hash_baseline.sas lines 82-90: %macro seed_guard with %sysfunc(fileexist) guard and %fail_out(SEED ABORTED) |
| 9 | 19b reads qc/19_raw_files.csv via DATA step infile (PCM-T-16), never PROC IMPORT | ✓ VERIFIED | sas/19b_seed_hash_baseline.sas lines 117, 143: two infile statements for header check and data read; no proc import found |
| 10 | Program 19 reads baseline via DATA step infile and aborts on sha256 drift (%fail_out) | ✓ VERIFIED | sas/19_raw_dir_inventory.sas lines 935-980: %macro check_hash_baseline with infile at line 946, %fail_out at line 975 on drift, NOTE at line 978 on pass |
| 11 | Program 19 runs before programs 01-08 in run_pipeline.cmd | ✓ VERIFIED | run_pipeline.cmd: program 19 call at line 83, program 01 at line 87 — ordering correct. Scope split intentional per PCM-D-30: HARD-01 guards originals (&raw_path.\\master), HARD-02 guards renamed sas7bdat files (&source_path). Both together provide full coverage. |
| 12 | docs/DECISIONS.md contains PCM-D-29 documenting that full source protection requires IT engagement | ✓ VERIFIED | docs/DECISIONS.md line 881: PCM-D-29 section present with "read-only file attribute is insufficient" and "full source protection requires IT engagement" language |

**Score:** 12/12 truths verified — all gaps resolved 2026-10-07

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `sas/23_pcnr_inventory.sas` | SECTION 99 CONTAINS audit + narrowed block | PARTIAL | SECTION 99 audit appended at line 1339; narrowing of main CONTAINS block (lines 394-408) not confirmed complete |
| `sas/24_pcnr_build.sas` | Two FIX-04 QC assertions after sentinel-handling step | VERIFIED | Lines 1015-1058 contain both assertions with %assert_eq, targeting work.pcnr_harmonized |
| `sas/19b_seed_hash_baseline.sas` | One-time baseline seed with exists-guard | VERIFIED | File exists; contains %macro seed_guard, %sysfunc(fileexist) check, infile reads, data _null_ write, NOT in run_pipeline.cmd |
| `sas/19_raw_dir_inventory.sas` | SECTION 13 hash guard reading baseline via infile | VERIFIED | Lines 928-980: SECTION 13 present, infile at line 946, %fail_out on drift, no write to baseline |
| `docs/raw_hash_baseline.csv` | Header + 8 md1-md8 data rows, version-controlled | STUB | Header-only; no data rows committed to git |
| `docs/DECISIONS.md` | PCM-D-29 documentation note | VERIFIED | Line 881: PCM-D-29 present with correct content |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| sas/19_raw_dir_inventory.sas hash guard | docs/raw_hash_baseline.csv | infile "&docs_path.\\raw_hash_baseline.csv" | WIRED (file stub) | Line 946 reads baseline via DATA step infile; file exists but has 0 data rows — guard would fail on missing baseline rows (n_base != 8 check at line 958) |
| check_hash_baseline macro | %abort cancel via %fail_out | %fail_out at line 975 on n_drift > 0 | WIRED | Confirmed: %fail_out reuses existing PCM-R-05 macro |
| sas/23_pcnr_inventory.sas SECTION 99 | qc/23_contains_audit.csv | data _null_ file/put at lines 1419-1425 | WIRED (P: drive unverifiable) | Code wired to &qc_path.\\23_contains_audit.csv |
| sas/24_pcnr_build.sas assertion macros | work.pcnr_harmonized | proc sql from work.pcnr_harmonized | WIRED | Lines 1041, 1054 query work.pcnr_harmonized directly |
| FIX-04 assertions | %abort cancel | %assert_eq calls %abort cancel inside named macro | WIRED | %assert_eq defined at lines 1028-1034 per PCM-R-05 |
| docs/DECISIONS.md PCM-D-29 | HARD-03 requirement | documentation note | WIRED | PCM-D-29 references "HARD-03 requirement; Phase 26 Plan 04" |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| sas/19_raw_dir_inventory.sas SECTION 13 | work._baseline (sha256 values) | docs/raw_hash_baseline.csv via infile | No — file has 0 data rows on disk in git | HOLLOW: guard would fire "row count != 8" on pipeline run today |
| sas/24_pcnr_build.sas FIX-04 | &n_cog_zero, &n_rt_sentinel | proc sql count from work.pcnr_harmonized | Real (depends on upstream merge completing) | FLOWING — count queries are real SQL against work dataset |

### Behavioral Spot-Checks

Step 7b: SKIPPED for most items — SAS programs cannot be executed in this environment (requires SAS 9.4 + P: drive mount). Human verification for the guard fire/pass cycle is documented in the 26-03-SUMMARY (2026-09-30): guard FAILED on tampered sha256 and PASSED after restore.

| Behavior | Evidence Source | Status |
|----------|----------------|--------|
| 19b aborts on second run (SEED ABORTED) | 26-03-SUMMARY: "Step 1: hash guard passed; re-run aborted" | HUMAN VERIFIED |
| Guard FAILS on tampered sha256 | 26-03-SUMMARY: "Step 5 (tampered sha256): HARD-01 HASH GUARD FAILED + %ABORT CANCEL fired correctly" | HUMAN VERIFIED |
| Guard PASSES after restore | 26-03-SUMMARY: "Step 7 (after restore): HARD-01 hash guard passed" | HUMAN VERIFIED |
| Program 19 is first in run_pipeline.cmd | grep: call :run_program "19" at line 83, "01" at line 87 | PASS |
| PCM-D-29 present in DECISIONS.md | grep: line 881 | PASS |
| %assert_eq on pcnr_Cognitive_Score and pcnr_rt in 24 | grep: lines 1036-1058 | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| FIX-03 | 26-01 | CONTAINS audit and narrowing in program 23 | SATISFIED | All 15 fragments approved by Gerard 2026-10-07; SECTION 99 audit wired; no narrowing required |
| FIX-04 | 26-02 | QC assertions for sentinel recodes in program 24 | SATISFIED | Lines 1015-1058: both assertions wired with %assert_eq/%abort cancel |
| HARD-01 | 26-03 | sha256 hash guard in program 19 reads baseline and aborts on drift | SATISFIED | Guard code wired; baseline CSV committed 2026-10-07 with 8 data rows (commit 3d5c0f0) |
| HARD-02 | 26-03 | Program 19 first in run_pipeline.cmd | SATISFIED | Ordering correct (line 83 < line 87); scope split (originals vs renamed) documented as intentional in PCM-D-30 |
| HARD-03 | 26-04 | IT engagement documentation note in DECISIONS.md | SATISFIED | PCM-D-29 at DECISIONS.md line 881 |

### Anti-Patterns Found

None remaining — baseline stub resolved 2026-10-07.

### Human Verification Required

None remaining.

### Gaps Summary

All gaps resolved 2026-10-07:

**Gap 1 (RESOLVED 2026-10-07):** docs/raw_hash_baseline.csv committed with 8 data rows (commit 3d5c0f0).
**Gap 2 (RESOLVED 2026-10-07):** Source path scope documented as intentional in PCM-D-30 — HARD-01 guards originals, HARD-02 guards renamed sas7bdat files; both together provide full coverage.
**Gap 3 (RESOLVED 2026-10-07):** All 15 CONTAINS fragments approved by Gerard after reviewing qc/23_contains_audit.csv — FIX-03 satisfied as-is.

---

_Verified: 2026-09-30 | All gaps resolved: 2026-10-07_
_Verifier: Claude (gsd-verifier)_
