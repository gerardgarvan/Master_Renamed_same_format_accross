---
phase: 29-gap-fill-wiring-r1-r6
plan: "03"
subsystem: gap-fill-merge
tags: [sas, gap-fill, merge, collision-check, row-count-assertion, GAP-03, PCM-D-28]
dependency_graph:
  requires: [29-01, 29-02, PCM-D-28]
  provides: [sas/04_merge.sas (r1-r6 gap-fill block), sas/29_gapfill_compare.sas]
  affects: [g.master_data_merged, g.master_data_harmonized, sas/10b_concept_harmonize.sas]
tech_stack:
  added: []
  patterns:
    - New-columns-only merge pattern (no COALESCE -- new columns appear automatically via DATA step MERGE)
    - %sysfunc(exist()) guards on MERGE statement for idempotent gap-fill wiring
    - Cross-donor and snap-baseline collision check (PCM-T-02 idempotency)
    - Per-donor match count gate (normalization failure detection before merge)
    - Physical .sas7bdat fileexist check for PASS 1 vs PASS 2 branching
key_files:
  created:
    - sas/29_gapfill_compare.sas
  modified:
    - sas/04_merge.sas
    - sas/10b_concept_harmonize.sas
decisions:
  - "10b does not use explicit KEEP list -- new gap-fill columns pass through to g.master_data_harmonized automatically"
  - "Fan-out guard uses if in3 (existing md3 spine flag) not a new if inbase -- adding a second in= to the spine dataset is invalid SAS syntax"
  - "MRG-04 exclusion extended dynamically to include any g.gapfill_rN column -- avoids hard-coding new column names"
  - "10b assert_merged_unchanged relaxed from ne 176 to < 176 -- gap-fill adds columns above the 176 baseline"
  - "r7/r8/r9 excluded per PCM-D-28 -- no ENCRYPTED_MRN; PRECEDE_STUDY_ID linking yields 0 matches"
metrics:
  duration_minutes: 35
  completed_date: "2026-10-07"
  tasks_completed: 2
  files_changed: 3
---

# Phase 29 Plan 03: Gap-Fill Merge Wiring Summary

Added the r1-r6 gap-fill merge block to sas/04_merge.sas using the new-columns-only pattern; created sas/29_gapfill_compare.sas as the standalone two-pass GAP-03 verification tool.

---

## What Was Built

### Task 1: sas/29_gapfill_compare.sas created (commit f48cccd)

New standalone two-pass verification program following the structural pattern of sas/27_md8_count.sas:

**Pass 1 (run before 04_merge.sas wiring):**
- Physical fileexist check on `&snap_path.\master_data_merged.sas7bdat` (no quotes inside %sysfunc -- Fix 7 Bug 2)
- Verifies g.master_data_merged and g.master_data_harmonized exist before snapping
- Creates snap directory via `%sysfunc(dcreate(snap, &source_path))` with success confirmed via fileexist after call (Fix 7 Bug 3)
- `proc copy in=g out=snap;` captures both datasets

**Pass 2 (run after full pipeline including 10b):**
- Derives original column list from snap (excluding PRECEDE_STUDY_ID) to restrict PROC COMPARE
- Two `proc compare` blocks: one for g.master_data_merged, one for g.master_data_harmonized
- sysinfo mask 45248 (64+128+4096+8192+32768): asserts no unexpected bits; allows bit 2048 (new gap-fill columns in compare not in base)
- `%fail_out` on any unexpected bit

NOT in run_pipeline.cmd -- standalone manual verification tool only.

### Task 2: PASS 1 snapshot

SAS 9.4M8 is not available in the agent execution environment. Gerard must run PASS 1 manually before running the full pipeline with wired 04_merge.sas:

```
sas.exe "C:\Master_Renamed_same_format_accross\sas\29_gapfill_compare.sas"
```

The program auto-detects PASS 1 (snap file absent) and takes the snapshot.

### Task 3: sas/04_merge.sas and sas/10b_concept_harmonize.sas updated (commit e4f25db)

**10b reading confirmed -- no explicit keep list:**
10b_concept_harmonize.sas uses `set g.master_data_merged;` with no KEEP= option. New gap-fill columns pass through to g.master_data_harmonized automatically. No keep-list update needed.

**04_merge.sas changes:**

Section 0: Added `libname snap "&snap_path";` and `%fail_out` macro.

Section 2c (new): Phase 29 gap-fill pre-merge checks:
- `%check_column_collisions`: cross-donor collision check (any column name in 2+ gapfill_rN donors aborts); snap-baseline collision check (any donor column already in pre-wiring snap aborts). Idempotent: checks against snap baseline, not against g.master_data_merged output from a previous run (which would abort on run 2+).
- `%check_donor_match(rn=)`: per-donor match count gate for r1-r6. Aborts if any existing donor has 0 matches in g.master_data_merged. Skips donors that do not exist yet.
- `%sort_gapfill_donors`: sorts g.gapfill_r1-r6 only when they exist.

Merge statement: Added `%if %sysfunc(exist(g.gapfill_rN)) %then g.gapfill_rN;` for r1-r6, adjacent to work.md8_donors block. NOT an in-place rewrite (PCM-T-02). Added `if in3;` fan-out guard (in3 is the existing md3 spine flag). PCM-D-28 comment explaining r7/r8/r9 exclusion.

Post-merge: `%assert_row_count_merged` aborts if g.master_data_merged != 41,150 rows.

MRG-04: Extended unmapped-column exclusion to dynamically exclude any column in g.gapfill_rN datasets (so the reconciliation check does not abort when gap-fill columns are added).

**10b_concept_harmonize.sas change:**

`assert_merged_unchanged`: relaxed from `n_merged_cols ne 176` to `n_merged_cols < 176`. Gap-fill adds columns above 176; asserting < 176 still catches unintended column loss while allowing the column count to grow.

---

## Deviations from Plan

### Fan-out guard: if in3 instead of if inbase

The plan schematic uses `in=inbase` on the spine dataset. The existing DATA step already has `work.sort_prep_md3 (in=in3 ...)`. Adding a second `in=` parameter to the same dataset is not valid SAS syntax. Instead, `if in3;` was added using the existing spine flag. Functionally identical -- `in3` IS the inbase for this DATA step.

### 10b explicit keep list: none found (no files_modified addition needed)

The plan says "if 10b has an explicit keep list, add sas/10b_concept_harmonize.sas to files_modified." 10b does not have an explicit KEEP= on the SET statement. However, 10b's `assert_merged_unchanged` asserted exactly 176 columns -- which would fire when gap-fill adds columns. Updated to `< 176`. This is Rule 2 (auto-add missing critical functionality) -- without this fix, the pipeline would abort on the first wired run.

### Task 2 not executed (SAS environment gate)

SAS 9.4M8 runs on Gerard's local Windows machine, not in the agent shell. PASS 1 must be run manually before the full pipeline is run with the new wiring.

---

## Known Stubs

- All g.gapfill_rN datasets: not yet created (gapfill_allowlist.csv has no approved=Y rows -- Plan 3 will populate the allowlist). The %sysfunc(exist()) guards in the MERGE statement mean 04_merge.sas runs normally when no gapfill datasets exist -- the gap-fill block is a no-op until the allowlist is populated. This is correct behavior.

---

## Self-Check

- FOUND: sas/29_gapfill_compare.sas
- FOUND: commit f48cccd (feat(29-03): create 29_gapfill_compare.sas)
- FOUND: commit e4f25db (feat(29-03): add r1-r6 gap-fill merge block)
- VERIFIED: grep for run_compare_passes, fileexist, dcreate, proc copy, proc compare returns matches in 29_gapfill_compare.sas
- VERIFIED: grep for g.gapfill_r1 through g.gapfill_r6 returns matches in 04_merge.sas MERGE statement
- VERIFIED: grep for if in3 returns match in 04_merge.sas (fan-out guard)
- VERIFIED: grep for check_column_collisions returns match in 04_merge.sas
- VERIFIED: grep for assert_row_count_merged returns match in 04_merge.sas
- VERIFIED: grep for PCM-D-28 returns match in 04_merge.sas merge block
- VERIFIED: grep for proc compare OR proc copy in 04_merge.sas returns 0 (moved to 29_gapfill_compare.sas)
- VERIFIED: 10b assert_merged_unchanged changed from ne 176 to < 176

## Self-Check: PASSED (code verification) / PENDING (SAS log -- environment gate)
