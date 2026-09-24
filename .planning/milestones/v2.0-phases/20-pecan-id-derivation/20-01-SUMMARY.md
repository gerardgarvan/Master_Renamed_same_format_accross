---
phase: 20-pecan-id-derivation
plan: 01
subsystem: database
tags: [sas, pecan_id, crosswalk, checksum, certutil, proc-append, linkage-reach]

requires:
  - phase: 19-raw-directory-inventory
    provides: qc/19_raw_files.csv SHA-256 record for md3 source CSV (PID-01 precondition)

provides:
  - sas/20_pecan_id.sas -- full program with checksum, cross-check, cardinality, crosswalk build, linkage reach
  - sas/19_raw_dir_inventory.sas amended to emit three additional Phase 20 CSV handoffs
  - sas/00_config.sas has xwalk_backup_path macro variable for PHI-safe dated backup
  - docs/DECISIONS.md records PCM-D-17 (surrogate integer, append-only xwalk) and PCM-D-18 (attach in 10b/16b)

affects: [20-02, 21-runner-wiring]

tech-stack:
  added: []
  patterns:
    - "certutil INFILE PIPE FILEVAR= checksum pattern reused from program 19"
    - "PROC APPEND append-only crosswalk with two-way NOT EXISTS backup guard"
    - "Dated backup name via %sysfunc(datetime(), B8601DT15.) for sort-chronological ISO stamps"
    - "CALL EXECUTE loop for per-file PID-07 linkage reach processing"
    - "PUT-to-fileref text report pattern reused from programs 03 and 18"

key-files:
  created:
    - sas/20_pecan_id.sas
    - .planning/phases/20-pecan-id-derivation/20-01-SUMMARY.md
  modified:
    - sas/19_raw_dir_inventory.sas
    - sas/00_config.sas
    - docs/DECISIONS.md

key-decisions:
  - "PCM-D-17 resolved: pecan_ID is surrogate sequential integer ordered by smallest numeric PRECEDE; crosswalk is append-only with dated backup on P:"
  - "PCM-D-18 resolved: pecan_ID attached by 10b and 16b at build time; g.master_data_merged untouched; 174->175 column update in both producers"
  - "Backup naming uses B8601DT15. format (e.g. 20260923T140500) for SAS-valid, chronologically sortable dataset names"
  - "CASE 3 guard: if xwalk missing but backup exists, abort immediately -- never rebuild from scratch when backup present"

requirements-completed: [PID-01, PID-02, PID-03, PID-04, PID-07, PID-08]

duration: 35min
completed: 2026-09-23
---

# Phase 20 Plan 01: pecan_ID Source Program and Phase 19 Amendment Summary

**Program 20 checksums md3 source CSV via certutil, cross-checks it against g.master_data_merged, asserts one-MRN cardinality, builds append-only g.pecan_id_xwalk with ISO-dated backup on P:, writes PID-07 linkage reach report for all ENCRYPTED_MRN-carrying raw files including r7/r8/r9 PCM-D-16 YES/NO, and program 19 now emits three additional CSV handoffs (key_columns, sheets, variables_md3) that PID-07 and D-11 consume**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-09-23T00:00:00Z
- **Completed:** 2026-09-23
- **Tasks:** 4
- **Files modified:** 4 (19_raw_dir_inventory.sas, 00_config.sas, 20_pecan_id.sas [new], docs/DECISIONS.md)

## Accomplishments
- Program 19 amended to export key_columns, sheets, and md3-filtered variables CSVs alongside 19_raw_files.csv; SECTION 14 verify_output checks all four individually (PCM-T-12)
- 00_config.sas has xwalk_backup_path pointing to P: directory outside qc/ and git (PHI-safe)
- sas/20_pecan_id.sas created with full 10-section structure: certutil SHA-256 match, D-12 truncation guard, D-14 cross-check with md3 prep normalization, PID-02 source audit, PID-03 cardinality abort gate, %build_or_append_xwalk with all four cases, PID-07 CALL EXECUTE linkage reach loop with r7/r8/r9 YES/NO, SECTION 10 PID-08 completion note
- PCM-D-17 and PCM-D-18 recorded in docs/DECISIONS.md with full rationale bodies, attributed to Gerard Garvan, dated 2026-09-23

## Task Commits

1. **Task 1: Amend program 19 for three additional CSV handoffs** - `07e6204` (feat)
2. **Task 2: Add xwalk_backup_path to 00_config.sas** - `590f2a9` (feat)
3. **Task 3: Create sas/20_pecan_id.sas** - `0a15e1f` (feat)
4. **Task 4: Record PCM-D-17 and PCM-D-18 in DECISIONS.md** - `320c5fa` (feat)

## Files Created/Modified
- `sas/19_raw_dir_inventory.sas` - Added three PROC EXPORT steps in SECTION 12 and three additional fileexist checks in SECTION 14
- `sas/00_config.sas` - Added xwalk_backup_path %let and matching %put NOTE
- `sas/20_pecan_id.sas` - New program: PID-01 through PID-04, PID-07, PID-08 (909 lines)
- `docs/DECISIONS.md` - PCM-D-17 and PCM-D-18 table rows and resolved-entry bodies

## Decisions Made
- PCM-D-17: surrogate sequential integer; append-only xwalk; ENCRYPTED_MRN retained; dated backup on P: using B8601DT15. format
- PCM-D-18: attachment by 10b and 16b; 174->175 column count; _gate5 expects n_dict_meta + 1; g.master_data_merged untouched
- Used CALL EXECUTE for PID-07 loop to drive one import+join+write macro call per key_column row without requiring open-code %DO %UNTIL
- CASE 3 of %build_or_append_xwalk aborts if xwalk missing but backup present -- preserves append-only guarantee even when xwalk file is accidentally deleted

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness
- Wave 2 (Plan 20-02) can execute: program 20 exists and will build g.pecan_id_xwalk when run
- 10b, 16b, and 08 ready for amendment (Plan 20-02 tasks)
- Phase 21 runner wiring still blocked until Phase 20 and 21 programs are complete

---
*Phase: 20-pecan-id-derivation*
*Completed: 2026-09-23*
