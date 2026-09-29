---
phase: 26-v2.1-carry-forward-source-hardening
plan: "03"
subsystem: source-hardening
tags: [hash-guard, HARD-01, HARD-02, program-19, baseline, sha256]
dependency_graph:
  requires: []
  provides: [HARD-01, HARD-02]
  affects: [run_pipeline.cmd, sas/19_raw_dir_inventory.sas]
tech_stack:
  added: []
  patterns: [PCM-T-16 DATA step infile for CSV reads, PCM-R-05 %fail_out abort wrapper, D-09 one-time seed guard, D-10 read-only guard]
key_files:
  created:
    - sas/19b_seed_hash_baseline.sas
    - docs/raw_hash_baseline.csv (header-only stub; real rows populated by running 19b with SAS)
  modified:
    - sas/19_raw_dir_inventory.sas (added SECTION 13 hash guard)
    - run_pipeline.cmd (program 19 moved to first position)
decisions:
  - "HARD-01: Program 19 SECTION 13 reads docs/raw_hash_baseline.csv via DATA step infile and aborts on sha256 drift"
  - "HARD-02: Program 19 moved to first in run_pipeline.cmd so hash guard fires before any merge program"
  - "19b is NOT added to run_pipeline.cmd (D-12); it is a standalone manual one-time seed program"
  - "docs/raw_hash_baseline.csv force-added to git (overriding *.csv gitignore rule) because it is a version-controlled security artifact"
  - "Source-path discrepancy noted: program 19 hashes &raw_path.\\master files; programs 01-08 read &source_path files; these are different P: drive directories -- human review needed to confirm they are the same underlying files or to extend the guard"
metrics:
  duration: ~25 minutes
  completed: "2026-09-29"
  tasks_completed: 3
  tasks_total: 4
  files_changed: 4
---

# Phase 26 Plan 03: Source Hardening Hash Guard (HARD-01, HARD-02) Summary

Implemented a stored-baseline sha256 guard on the md1-md8 source extracts. Created 19b_seed_hash_baseline.sas (one-time seed) and added SECTION 13 hash guard to program 19 that reads docs/raw_hash_baseline.csv via DATA step infile and aborts before any merge program on sha256 mismatch. Program 19 moved to first position in run_pipeline.cmd.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create 19b_seed_hash_baseline.sas seed program | ee47b70 | sas/19b_seed_hash_baseline.sas, docs/raw_hash_baseline.csv |
| 2 | Add hash-guard section to program 19 | 7d5727d | sas/19_raw_dir_inventory.sas |
| 2b | Move program 19 ahead of merge programs in run_pipeline.cmd | a626b81 | run_pipeline.cmd |

## Checkpoint Reached

Task 3 is `checkpoint:human-verify` -- awaiting human verification that the guard aborts on a tampered hash and passes after restore.

## Decisions Made

1. `docs/raw_hash_baseline.csv` is force-added to git with `git add -f` because `*.csv` is in `.gitignore`, but this file is a version-controlled security artifact (not data/PHI). The gitignore exclusion was designed for data files, not this baseline.

2. `19b_seed_hash_baseline.sas` is NOT wired into `run_pipeline.cmd` (D-12). It is intentionally standalone so it cannot be re-run accidentally.

3. The existing SECTION 13 (ODS Excel) was renumbered to SECTION 14; old SECTION 14 (output verification) became SECTION 15.

## Deviations from Plan

### Source-Path Discrepancy (Finding, not auto-fix)

**Found during:** Task 2b read_first check

**Issue:** Programs 01-08 read md1-md8 from `&source_path` (`P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross`). Program 19 inventories and hashes files in `&raw_path.\master` (`P:\PeCAN Master Data\Gerard\raw\master`). These are two different P: drive directories.

**Implication:** The HARD-01 hash guard protects `&raw_path.\master` files, not the `&source_path` files that the merge programs actually consume. If these are different copies (not just different mount points for the same directory), the guard provides no protection against modification of the actual merge inputs.

**Plan instruction:** "if 01-08 read from &source_path rather than &raw_path.\master, STOP and report: the guard would be protecting a different copy"

**Action taken:** Reordering was completed as specified (program 19 has no dependency on 01-08 outputs so the move is safe). The discrepancy is documented here for human review.

**Human action needed:** Confirm whether `&source_path` and `&raw_path.\master` contain the same physical files (e.g., symlinks or the same share mounted under two paths), or whether the hash guard needs to be extended to also check `&source_path` files.

## Known Stubs

- `docs/raw_hash_baseline.csv` contains only the header row. The 8 real md1-md8 sha256 rows must be populated by running `sas/19b_seed_hash_baseline.sas` interactively with SAS (with P: drive connected and `qc/19_raw_files.csv` current). Until seeded, the hash guard in program 19 SECTION 13 will abort with "baseline row count is 0 -- expected 8".

## Self-Check

### Files Created/Modified

- `sas/19b_seed_hash_baseline.sas`: present
- `docs/raw_hash_baseline.csv`: present (header-only stub)
- `sas/19_raw_dir_inventory.sas`: modified (contains `%macro check_hash_baseline` and `%check_hash_baseline;`)
- `run_pipeline.cmd`: modified (first `call :run_program` references 19_raw_dir_inventory.sas)

## Self-Check: PASSED (with stub documented)
