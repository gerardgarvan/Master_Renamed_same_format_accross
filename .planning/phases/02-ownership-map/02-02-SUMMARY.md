---
phase: 02-ownership-map
plan: 02
subsystem: ownership-map
tags: [sas, ownership, decisions, coalesce, conflict-detection]
dependency_graph:
  requires: [02-01]
  provides: [sas/02_ownership.sas (Sections 5-7), docs/DECISIONS.md (runtime population)]
  affects: [phase-04, phase-06]
tech_stack:
  added: []
  patterns: [proc-sql-having-count-distinct, file-mod-guarded-append, infile-marker-scan, macro-type-guard, null-sentinel-conditional]
key_files:
  created: []
  modified:
    - sas/02_ownership.sas
decisions:
  - "Re-run guard uses infile scan (not FILENAME PIPE) so Phase 2 has no XCMD dependency at all"
  - "own03_written pre-set to 0 before DATA step so an empty DECISIONS.md cannot leave the guard undefined"
  - "Type guard runs before NULL sentinel guard -- cross-type comparison (md8 Admit_BMI) is a TYPE MISMATCH, not a disagreement"
  - "NULL sentinel strip(upcase()) guard is conditional on type=2 (character only) -- numerics cannot hold 'NULL'"
  - "Admit_BMI and Race iterated across all contributing sources (not one fixed md3-vs-md1 pair that PCM-F-04 already proved identical)"
  - "Admit_BMI md8 call is expected to report TYPE MISMATCH -- that is a correct result, not a failure"
  - "work.allvars_src (not work.allvars) used as the type lookup source for the coalesce macro"
metrics:
  duration: "~15 minutes"
  completed: "2026-08-26"
  tasks_completed: 2
  files_created: 0
  files_modified: 1
---

# Phase 2 Plan 02: OWN-03 Conflict Detection and OWN-04 Coalesce Assertions Summary

**One-liner:** Sections 5-7 appended to 02_ownership.sas: PROC SQL conflict detection with infile-guarded MOD append to DECISIONS.md, type-safe NULL-sentinel-conditional coalesce check macro for Admit_BMI and Race iterated across all contributing sources, and program close-out.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | OWN-03 conflict detection and DECISIONS.md write with re-run guard | e181f9b | sas/02_ownership.sas |
| 2 | OWN-04 coalesce disagreement assertions for BMI and Race, then close src | e181f9b | sas/02_ownership.sas |

---

## What Was Built

### Section 5: OWN-03 Conflict Detection (Task 1)

- `proc sql` groups `work.allvars_src` by `name_u`, uses `HAVING COUNT(DISTINCT memname_u) > 1` to identify multi-source variable names
- `PRECEDE_STUDY_ID` excluded via `WHERE name_u ne 'PRECEDE_STUDY_ID'` (merge key, not a conflict)
- Pipe-delimited `sources_present` column built via `catx` + `min(case when ...)` pattern (identical to RESEARCH Pattern 2)
- Result written to `work.conflicts`; `&n_conflicts` count logged
- Re-run guard: `%let own03_written = 0` pre-sets the variable, then a DATA step reads DECISIONS.md with `infile ... truncover end=eof` and counts occurrences of the greppable marker `OWN-03 CONFLICT ROWS GENERATED`; `call symputx('own03_written', hits, 'G')` fires only on EOF
- Guard is infile-only: no FILENAME PIPE, no XCMD dependency (RESEARCH Pitfall 7)
- When `&own03_written = 0`, macro `%write_own03_block` appends marker line, markdown table header, and one row per conflict variable via `FILE dcsnmd MOD`
- `FILE ... REPLACE` never used (would truncate DECISIONS.md)
- Second run skips write and logs: "OWN-03 conflict block already present in DECISIONS.md -- skipping append (re-run guard)"

### Section 6: OWN-04 Coalesce Assertions (Task 2)

- Macro `%check_coalesce_agreement(var=, dsb=, dsa=master_data_3)` with two sequential guards:
  - Guard 1 (TYPE): reads `type` from `work.allvars_src` for both `&dsa` and `&dsb`; skips if variable absent from either side; emits `WARNING: OWN-04 TYPE MISMATCH` and returns if types differ -- type guard runs before sentinel guard (RESEARCH Pitfall 8)
  - Guard 2 (NULL sentinel, character-conditional): `%if &type_a = 2` wraps `strip(upcase(a.&var)) ne 'NULL'` and `strip(upcase(b.&var)) ne 'NULL'`; numeric variables bypass the sentinel check entirely
- No `VVALUE()` (not reliable in PROC SQL)
- `Admit_BMI` iterated across md1, md2, md4, md5, md6, md7, md8 (7 calls); md8 call expected to report TYPE MISMATCH
- `Race` iterated across md1, md2, md4, md5, md6, md7, md8 (7 calls)
- Total 14 `dsb=master_data_*` calls -- exercises all contributing sources, not one fixed pair
- `%put NOTE: OWN-04` note directs future maintainers to add variables here

### Section 7: Close-out

- `%put NOTE: ==== Phase 2 ownership map complete -- OWN-01..OWN-04 done ====;` (exact VALIDATION log-check marker)
- `libname src clear;` (exactly once, at program end)

---

## Acceptance Criteria Verification

| Check | Result |
|-------|--------|
| `having count(distinct memname_u) > 1` present | PASS |
| `where name_u ne 'PRECEDE_STUDY_ID'` present (key excluded) | PASS |
| `OWN-03 CONFLICT ROWS GENERATED` marker present | PASS |
| `own03_written` guard variable present | PASS |
| `%let own03_written = 0` pre-set present | PASS |
| No FILENAME PIPE / no XCMD dependency | PASS |
| `file dcsnmd mod` (MOD not REPLACE) | PASS |
| No `file dcsnmd replace` | PASS |
| `| Variable | Sources | Declared Owner | Resolution |` table header | PASS |
| `%macro check_coalesce_agreement` defined | PASS |
| `Admit_BMI` named explicitly | PASS |
| `Race` named explicitly | PASS |
| No bare `var=BMI,` (column does not exist) | PASS |
| No `vvalue(` in PROC SQL | PASS |
| `TYPE MISMATCH` guard present | PASS |
| `dsb=master_data_` count >= 10 (actual: 14) | PASS |
| `ne 'NULL'` count >= 2 (actual: 2) | PASS |
| `%if &type_a = 2` sentinel conditional | PASS |
| `not missing(a.` present | PASS |
| `not missing(b.` present | PASS |
| `Phase 2 ownership map complete` marker | PASS |
| `libname src clear` exactly once | PASS |

---

## Deviations from Plan

None -- plan executed exactly as written. The RESEARCH Pattern 5 macro was reproduced verbatim with the plan's specified additions (the md8 `Admit_BMI` expected TYPE MISMATCH comment, the STATE.md note about BMI recovering nothing). No architectural changes needed.

---

## Pending (Requires SAS Session)

- Run `sas -sysin sas/02_ownership.sas -log logs/02_ownership.log` on a machine with P: drive access
- Gate: `grep -c "ERROR:" logs/02_ownership.log` returns 0
- Gate: `grep -q "Phase 2 ownership map complete" logs/02_ownership.log` exits 0
- Gate: `docs/DECISIONS.md` contains the OWN-03 conflict table with one row per multi-source variable
- Gate: running the program a second time does not add a duplicate `OWN-03 CONFLICT ROWS GENERATED` block (`grep -c "OWN-03 CONFLICT ROWS GENERATED" docs/DECISIONS.md` stays 1)
- Note: `docs/DECISIONS.md` is written at run time to the P: drive; the committed stub has the `## OWN-03 Variable Conflicts` anchor but the conflict rows only appear after the first SAS run

---

## Known Stubs

None. The program writes all conflict rows from `work.conflicts` at runtime. The stub `docs/DECISIONS.md` has the section anchor but no conflict rows until the SAS program runs -- this is intentional and documented: the OWN-03 requirement is satisfied at runtime, not at commit time.

---

## Self-Check: PASSED

- sas/02_ownership.sas: modified (confirmed by git status showing CRLF conversion and 164 insertions)
- Commit e181f9b: exists and references both tasks
- All 22 automated acceptance criteria: PASSED
