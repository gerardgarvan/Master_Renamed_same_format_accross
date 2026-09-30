---
phase: quick
plan: 260930-mze
subsystem: source-hardening
tags: [HARD-02, hash-guard, sas7bdat, 19c, 00_config, DECISIONS]
requirements: [HARD-02]
key-files:
  created:
    - sas/19c_seed_source_hash_baseline.sas
  modified:
    - sas/00_config.sas
    - sas/19_raw_dir_inventory.sas
    - docs/DECISIONS.md
    - .planning/phases/26-v2.1-carry-forward-source-hardening/26-VALIDATION.md
decisions:
  - "PCM-D-30: HARD-01 covers raw\\master originals (certutil/csv); HARD-02 covers source_path sas7bdat files (%src_hash_compute); two guards because different directories and file formats"
metrics:
  duration: ~20 minutes
  completed: 2026-09-30
  tasks_completed: 4
  files_changed: 5
---

# Quick Task 260930-mze: HARD-02 Source Hash Guard Summary

**One-liner:** HARD-02 implemented -- sas7bdat source-file hash guard via 19c seed program and program 19 SECTION 14, with %src_hash_compute macro in 00_config.sas and PCM-D-30 scope boundary recorded.

---

## What Was Done

**Task 1 -- Fix src_hash_files in 00_config.sas**

Corrected `src_hash_files` from listing `.xlsx` files to listing the 8 `.sas7bdat` files that programs 01-08 actually read via SET statement. Added `src_hash_baseline` macro variable, the Phase 26 HARD-02 comment block, the `%_src_fail` utility macro, and the `%src_hash_compute` DATA step macro (computes SHA256 + byte size for each file in `&src_hash_files` using `HASHING_FILE(..., 4)`). Updated Revised date in header.

**Task 2 -- Create sas/19c_seed_source_hash_baseline.sas**

New one-time seed program modelled on 19b. Key differences from 19b:
- Source of hashes: calls `%src_hash_compute` (live sas7bdat hashes) rather than reading qc/19_raw_files.csv
- Baseline file: `&src_hash_baseline` (docs/source_hash_baseline.csv) not docs/raw_hash_baseline.csv
- Exists-guard: counts DATA ROWS (not just file existence) so a header-only stub from a failed first run does not block re-seeding
- Asserts all 8 files returned `status='OK'` before writing
- Writes header + 8 rows sorted by file_name (stable git diff)
- Verifies 9 total lines after write
- NOT added to run_pipeline.cmd

**Task 3 -- Insert SECTION 14 HARD-02 guard into 19_raw_dir_inventory.sas**

Inserted `%check_source_hash_baseline` macro between SECTION 13 (HARD-01) and the ODS Excel block. The new SECTION 14:
- Asserts `docs/source_hash_baseline.csv` exists and has exactly 8 data rows
- Calls `%src_hash_compute` to compute live hashes
- Joins baseline to live via PROC SQL; writes `qc/19_source_hash_check.csv` on EVERY run (pass or fail) for auditability
- Aborts if any `check_result ne 'OK'` (SHA256_DRIFT, SIZE_DRIFT, or HASH_ERROR)

Old SECTION 14 (ODS Excel) renumbered to SECTION 15. Old SECTION 15 (verify_output) renumbered to SECTION 16. `%verify_output` updated to check for `qc/19_source_hash_check.csv`.

**Task 4 -- Documentation**

- `docs/DECISIONS.md`: PCM-D-30 appended explaining the two-guard scope boundary
- `26-VALIDATION.md`: rows 26-mze-01 and 26-mze-02 added to Per-Task Verification Map; two HARD-02 entries added to Manual-Only Verifications table

---

## Commits

| Hash | Message |
|------|---------|
| 3b7e57d | fix(260930-mze): correct src_hash_files to sas7bdat and add HARD-02 shared macros to 00_config.sas |
| 5f5085e | feat(260930-mze): create 19c_seed_source_hash_baseline.sas for HARD-02 one-time seed |
| bb1f8da | feat(260930-mze): insert SECTION 14 HARD-02 source hash guard into 19_raw_dir_inventory.sas |
| 0d10fdc | docs(260930-mze): add PCM-D-30 to DECISIONS.md and 26-mze rows to 26-VALIDATION.md |

---

## Deviations from Plan

None -- plan executed exactly as written.

---

## Known Stubs

None. All functionality is wired: `%src_hash_compute` is defined in 00_config.sas, called by 19c and by program 19 SECTION 14. The audit CSV `qc/19_source_hash_check.csv` is written on every run.

The only remaining manual step is the one-time execution of 19c after confirming the sas7bdat files in `&source_path` are correct -- this is intentional by design (same pattern as 19b/HARD-01).

## Self-Check: PASSED

- sas/19c_seed_source_hash_baseline.sas: FOUND (commit 5f5085e)
- sas/00_config.sas contains sas7bdat: FOUND (commit 3b7e57d)
- sas/19_raw_dir_inventory.sas contains SECTION 14 / HARD-02: FOUND (commit bb1f8da)
- docs/DECISIONS.md contains PCM-D-30: FOUND (commit 0d10fdc)
- 26-VALIDATION.md contains 26-mze-01 and 26-mze-02: FOUND (commit 0d10fdc)
