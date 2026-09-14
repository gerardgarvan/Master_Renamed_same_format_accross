---
phase: 03-per-source-normalization
plan: "06"
subsystem: sas-prep
tags: [prep-08, prep-09, negative-intervals, rt-variables, operative-time, PCM-T-11, PCM-D-10, MRG-07]
dependency_graph:
  requires: [03-01, 03-02, 03-03, 03-04, 03-05]
  provides: [PREP-08-handling, PREP-09-scan, 03_negtime_logs]
  affects: [Phase4-merge, Phase5-qc]
tech_stack:
  added: []
  patterns: [IS-NOT-MISSING-guard, dictionary-columns-rt-scan, scan_negtime-macro, report_negtime-macro, MRG-07-flag-dont-null]
key_files:
  created: []
  modified:
    - sas/03_prep_md1.sas
    - sas/03_prep_md2.sas
    - sas/03_prep_md3.sas
    - sas/03_prep_md4.sas
    - sas/03_prep_md5.sas
    - sas/03_prep_md6.sas
    - sas/03_prep_md7.sas
    - sas/03_prep_md8.sas
decisions:
  - "PREP-08 revised to flag-dont-null: negative operative intervals RETAINED in g.prep_mdN; Phase 4 (MRG-07) derives rt_INCISE_to_DRESS_neg, rt_RM_START_to_INCISION_neg, rt_RM_START_to_RM_END_neg flag columns. Consistent with PCM-D-08 -- cannot identify which timestamp is wrong without destroying good values."
  - "PREP-09 implemented as report-only scan: derives rt_* variable list from dictionary.columns at run time; IS NOT MISSING guard on every count (PCM-T-11); logs/03_negtime_mdN.txt written per source."
  - "PCM-D-10 remains open -- awaiting SAS run to produce logs/03_negtime_md1..8.txt with actual negative counts per rt_* variable."
metrics:
  duration_minutes: 30
  completed_date: "2026-08-26T21:28:33Z"
  tasks_completed: 2
  tasks_pending_human: 1
  files_created: 0
  files_modified: 8
---

# Phase 3 Plan 06: PREP-08 / PREP-09 Operative Interval Negatives Summary

**One-liner:** PREP-08 negative operative intervals handled via flag-dont-null in MRG-07 (revised from nulling after PCM-D-08); PREP-09 report-only rt_* scan macro added to all eight prep programs with IS NOT MISSING guards and dictionary-derived variable lists.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | PREP-08 -- negative operative intervals in all eight prep programs | 6748020 (original null) then revised via 6157c83 | sas/03_prep_md1..8.sas |
| 2 | PREP-09 -- report-only negative scan of every other rt_* variable | f2e9c47, then 00d2f6d (md8 mdnum fix) | sas/03_prep_md1..8.sas |

**Task 3 (checkpoint:human-verify):** Awaiting SAS re-run of Phase 3 → Phase 4 → Phase 5 and review of logs/03_negtime_md*.txt.

---

## What Was Built

### PREP-08 (Revised Design)

The plan originally specified nulling negatives in the three operative-interval variables. After execution, a design revision was applied (2026-08-27) to flag-dont-null, consistent with PCM-D-08.

**Current implementation in all eight prep programs:**
- SECTION 3 DATA step: a `%report_negtime` comment block documents the design rationale. No nulling occurs — negatives are RETAINED.
- SECTION 5c: `proc sql` counts surviving negatives with IS NOT MISSING guards. `%report_negtime` macro puts a NOTE (not abort) when negatives exist.
- SECTION 5d: `%scan_negtime` macro writes `logs/03_negtime_mdN.txt` for PREP-09.

**Phase 4 (MRG-07) derives three flag columns:**
- `rt_INCISE_to_DRESS_neg` = 1 where value is negative (expected 52 rows)
- `rt_RM_START_to_INCISION_neg` = 1 where value is negative (expected 15 rows)
- `rt_RM_START_to_RM_END_neg` = 1 where value is negative (expected 0 rows)

### PREP-09 (As Planned)

Each prep program appends a `%scan_negtime` macro (SECTION 5d):
- Queries `dictionary.columns` for all numeric variables with `name like 'RT!_%' escape '!'` (literal underscore, PCM-T-11)
- Iterates over every such variable
- Counts negatives with `IS NOT MISSING` guard on every count query
- Writes `logs/03_negtime_mdN.txt` per source with header, variable list, and per-variable counts
- **Modifies nothing** — report only
- rt_ANCHOR_to_*_days negatives documented as expected (offsets, not durations)

**md8 fix:** `%let mdnum = 8;` was missing initially (commit 00d2f6d); fixed so the dictionary.columns lookup resolves correctly for md8.

---

## Deviations from Plan

### Design Change -- PREP-08 flag-dont-null (post-plan revision)

**Found during:** Post-Task-1, applying PCM-D-08 consistency check

**Issue:** The plan specified nulling negatives and asserting zero survivors (`assert_no_negtime`). After Task 1 was committed, a review noted that:
1. `rt_RM_START_to_INCISION_mins` is one of the `rt_RM_START_to_*` family where negativity may be meaningful (anesthesia routinely begins before OR entry)
2. Nulling is inconsistent with PCM-D-08 (flag-dont-null for envelope violations) -- same principle: cannot identify which timestamp is wrong

**Fix:** Revised all eight programs to retain negatives; Phase 4 MRG-07 derives flag columns. `assert_no_negtime` replaced by `report_negtime` (reports count, does not abort). Phase 4 and Phase 5 updated consistently (MRG-05 envelope flag, QC-06, QC-07).

**Files modified:** sas/03_prep_md1..8.sas, sas/04_merge.sas, sas/05_qc_merge.sas

**Commits:** 6157c83 (MRG-07 + QC-06/QC-07), 00d2f6d (md8 mdnum fix), 35771be (runtime logs)

**Plan acceptance criteria NOT met (by design):**
- `grep -q "assert_no_negtime" sas/03_prep_md*.sas` -- no match (replaced by `report_negtime`)
- The "no negative survived" assertion is not present (negatives are flagged, not nulled)

**Plan acceptance criteria MET:**
- `grep -c "PREP-08" sas/03_prep_md*.sas` >= 7 per file (all eight have PREP-08 references)
- `grep -q "rt_ANCHOR_to_ADMIT_days.*= .;"` -- NO MATCH (anchor vars not touched)
- `grep -c "PREP-09" sas/03_prep_md*.sas` >= 4 per file -- all eight pass
- `grep -q "03_negtime_md"` -- all eight pass
- `grep -q "escape '!'"` -- all eight pass
- `grep -q "rtvars"` -- all eight pass
- `grep -q "%let mdnum"` in md3 -- passes
- No rt_ assignment in SECTION 5d -- confirmed

---

## Known Stubs

**PCM-D-10 (open):** The PREP-09 report cannot be evaluated until the SAS pipeline runs and produces `logs/03_negtime_md1..8.txt`. Negatives in `rt_ANCHOR_to_*_days` are expected and correct. Any other `rt_*_mins` variable showing negatives requires a domain decision before being added to the flag list.

**Task 3 checkpoint:** Phase 3 → Phase 4 → Phase 5 re-run is required (with SAS session restart between each). Until that completes, `g.prep_mdN`, `g.master_data_merged`, and all Phase 5 QC results are stale relative to the revised PREP-08 / MRG-07 design.

---

## Self-Check

Verified files exist:
- sas/03_prep_md1.sas: FOUND (with PREP-08/PREP-09 code)
- sas/03_prep_md3.sas: FOUND (with PREP-08/PREP-09 code)
- sas/03_prep_md8.sas: FOUND (with %let mdnum=8 fix)
- sas/04_merge.sas: FOUND (with MRG-07 flag derivation)

Verified commits:
- 6748020: feat(03-06): PREP-08 -- null negative operative intervals (original Task 1 commit)
- f2e9c47: feat(03-06): PREP-09 -- report-only negative scan (Task 2 commit)
- d85c8b8: chore(03-06): STATE.md updated Tasks 1+2 complete
- 6157c83: feat(phases 03-05): MRG-07, QC-06, QC-07 (design revision commit)
- 00d2f6d: fix(prep-md8): add missing %let mdnum=8

## Self-Check: PASSED
