---
phase: 03-per-source-normalization
plan: "04"
subsystem: sas-prep
tags: [structural-prep, prep-04, prep-07, type-conversion, duplicate-drop]
dependency_graph:
  requires: [03-01]
  provides: [g.prep_md4, g.prep_md5, g.prep_md6]
  affects: [04-merge]
tech_stack:
  added: []
  patterns:
    - "LENGTH-before-SET for all character variables (PREP-05)"
    - "NUM->CHAR via strip(put(best12.)) — never input() toward numeric (PREP-07)"
    - "identity proof before DROP (PRECEDE_Study_ID_1 ne PRECEDE_STUDY_ID SQL count)"
    - "dictionary.columns absence assertion for dropped columns (PREP-04)"
    - "dictionary.columns type assertion for converted columns (PREP-07)"
    - "%abort cancel inside %macro only (PCM-R-05)"
key_files:
  created:
    - sas/03_prep_md4.sas
    - sas/03_prep_md5.sas
    - sas/03_prep_md6.sas
  modified: []
decisions:
  - "Base_Procedure_Code_1 converted NUM->CHAR $10 in md4/md5/md6 via strip(put(best12.)); character is the safe direction (leading zeros and alpha codes preserved)"
  - "PRECEDE_Study_ID_1 proven identical to PRECEDE_STUDY_ID before drop (n_keydiff SQL assertion in SECTION 2b); PCM-D-06 is now mechanically verified, not merely assumed"
  - "PRECEDE_Study_ID_1 excluded from LENGTH block in md6 (declaring a dropped variable re-creates it as a zero slot — excluded entirely per PLAN interfaces guidance)"
metrics:
  duration_minutes: ~20
  completed_date: "2026-08-26"
  tasks_completed: 2
  tasks_total: 3
  files_created: 3
  files_modified: 0
---

# Phase 03 Plan 04: md4/md5/md6 Structural Prep (PREP-04 + PREP-07) Summary

**One-liner:** Structural prep for md4/md5/md6 with Base_Procedure_Code_1 NUM→CHAR $10 harmonization and md6 PRECEDE_Study_ID_1 duplicate drop proven identical before removal and asserted absent afterwards.

---

## What Was Built

Three SAS prep programs (`sas/03_prep_md4.sas`, `sas/03_prep_md5.sas`, `sas/03_prep_md6.sas`) that:

1. **Check preconditions** — libname src/g resolved, qc/ and logs/ directories exist (Section 1).
2. **Write exception reports to qc/** before any DATA step — measure NULL sentinel count (abort if nonzero) and encoding-damaged Base_Procedure_1 rows (flag only, PCM-C-01) (Section 2, PREP-02).
3. **Prove identity before drop** (md6 only) — SQL count of rows where `PRECEDE_STUDY_ID ne PRECEDE_Study_ID_1`; aborts if nonzero (Section 2b, PREP-04).
4. **Copy source to g.prep_mdN** with LENGTH-before-SET for every character variable; `Base_Procedure_Code_1` is renamed from the numeric source to `_bpc_n`, converted via `strip(put(_bpc_n, best12.))` to the `$10` character target, and the temp is dropped; md6 additionally drops `PRECEDE_Study_ID_1` (Section 3, PREP-05, PREP-07).
5. **Write conversion logs to logs/** recording total rows and Base_Procedure_Code_1 non-missing conversion count (Section 4, PREP-06).
6. **Assert row counts** using `%let expected_nobs` set once at the top; assertion reads `&expected_nobs` (not a hardcoded literal in the call — RESEARCH Pitfall 4): md4=7695, md5=7695, md6=9462 (Section 5a).
7. **Assert md6 column absence** — `dictionary.columns` count where `upcase(name)='PRECEDE_STUDY_ID_1'`; aborts if nonzero (Section 5b, PREP-04).
8. **Assert PREP-07 type** — `dictionary.columns` count where `type='num'` for `BASE_PROCEDURE_CODE_1`; aborts if nonzero (Section 5c, PREP-07).

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write 03_prep_md4.sas and 03_prep_md5.sas (structural, 7,695 rows each) | 245c2bf | sas/03_prep_md4.sas, sas/03_prep_md5.sas |
| 2 | Write 03_prep_md6.sas — drop PRECEDE_Study_ID_1 (PREP-04) and assert absence | 47f8bd7 | sas/03_prep_md6.sas |

---

## Checkpoint Pending

Task 3 is a `checkpoint:human-verify` gate requiring the user to run the programs in a SAS session with P: drive mapped and confirm:
- ERROR-free logs with `==== Phase 3 prep mdN complete` markers
- Six artifacts: `qc/03_exceptions_md4/5/6.txt` and `logs/03_conversions_md4/5/6.txt`
- md6 log contains `PREP-04 OK -- PRECEDE_Study_ID_1 identical` BEFORE the DATA step and `PREP-04 OK -- PRECEDE_Study_ID_1 absent` after
- Row counts: md4=7695, md5=7695, md6=9462
- `PREP-07 OK -- Base_Procedure_Code_1 is CHARACTER` in each log

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Dependency Gap] qc/03_charvars_all.txt not yet available**

- **Found during:** Task 1
- **Issue:** Plan 03-04 `read_first` lists `qc/03_charvars_all.txt` as source for character variable widths; this file is produced at SAS runtime by Plan 03-01 (Wave 0) and has not been committed or generated yet. The parallel execution proceeds before Plan 03-01's SAS run.
- **Fix:** LENGTH blocks declare the known-essential variables (`PRECEDE_STUDY_ID $12`, `Base_Procedure_Code_1 $10`, `Base_Procedure_1 $200`) with prominent comments directing the first-runner to add remaining character variables from `qc/03_charvars_all.txt` MASTER_DATA_N rows before executing. Structure, macros, and all five sections are complete and correct. The programs will need the LENGTH block supplemented from `qc/03_charvars_all.txt` before they can safely run — this is the human-verify checkpoint's first concern.
- **Files modified:** sas/03_prep_md4.sas, sas/03_prep_md5.sas, sas/03_prep_md6.sas

---

## Known Stubs

The LENGTH blocks in all three programs declare only the variables known at authoring time:
- `PRECEDE_STUDY_ID $12`
- `Base_Procedure_Code_1 $10` (PREP-07 target)
- `Base_Procedure_1 $200` (conservative width pending PROC CONTENTS confirmation)

**All remaining character variables for MASTER_DATA_4, MASTER_DATA_5, and MASTER_DATA_6 must be added to the LENGTH blocks** from `qc/03_charvars_all.txt` (rows for MASTER_DATA_4, MASTER_DATA_5, MASTER_DATA_6 respectively) before the programs are run in SAS. Under-declaring a character variable width causes silent truncation (RESEARCH Pitfall 1).

This stub is intentional and documented; resolution occurs when `03_prep_setup.sas` (Plan 03-01) has been run and `qc/03_charvars_all.txt` is available.

---

## Self-Check: PASSED

- `sas/03_prep_md4.sas` exists: FOUND
- `sas/03_prep_md5.sas` exists: FOUND
- `sas/03_prep_md6.sas` exists: FOUND
- Commit 245c2bf exists: FOUND (feat(03-04): add 03_prep_md4.sas and 03_prep_md5.sas)
- Commit 47f8bd7 exists: FOUND (feat(03-04): add 03_prep_md6.sas with PREP-04 duplicate drop)
