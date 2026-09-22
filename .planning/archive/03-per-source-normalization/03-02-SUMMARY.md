---
phase: 03-per-source-normalization
plan: 02
subsystem: sas-prep
tags: [md8, char-to-num, null-sentinel, exception-report, conversion-log, assertions]
dependency_graph:
  requires: [03-01]
  provides: [sas/03_prep_md8.sas, qc/03_exceptions_md8.txt (at run time), logs/03_conversions_md8.txt (at run time)]
  affects: [04-merge]
tech_stack:
  added: []
  patterns:
    - LENGTH-before-SET for all character variables (PCM-R-02)
    - Two-step NULL sentinel clear then INPUT() conversion (RESEARCH Pattern 2)
    - PROC SQL UNION ALL for pre-conversion exception scan (RESEARCH Pattern 3)
    - FILE/PUT conversion count log (RESEARCH Pattern 4)
    - SELECT COUNT(*) INTO :n TRIMMED for all assertions (never SQLOBS)
    - All %abort cancel inside %macro definitions (PCM-R-05)
key_files:
  created:
    - sas/03_prep_md8.sas
  modified: []
decisions:
  - "Two-step normalization (work.prep_md8_s1 for sentinel clear, g.prep_md8 for conversion) chosen over single-step to keep sentinel clearing and type conversion auditable separately"
  - "Output to g.prep_md8 (persistent library outside repo tree) so Phase 4 can read regardless of session order"
  - "Encoding damage counted separately from n_exc; only n_exc aborts the run (Pitfall 6 compliance)"
  - "LENGTH block covers confirmed-width variables; remaining char vars use TODO placeholders pending qc/03_charvars_all.txt from Plan 01 run"
metrics:
  duration_minutes: 3
  completed_date: "2026-08-26"
  tasks_completed: 2
  tasks_total: 3
  files_created: 1
  files_modified: 0
---

# Phase 3 Plan 02: md8 NULL Sentinel Clear + Forced-Char-to-Numeric Conversion Summary

**One-liner:** Full md8 normalization SAS program — pre-conversion exception scan, NULL sentinel clear via _CHARACTER_ array, eight char-to-num INPUT() conversions into g.prep_md8, conversion count log, and post-conversion assertions on type/sentinels/row count.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Sections 0-2: preconditions + pre-conversion exception report | 93e5829 | sas/03_prep_md8.sas |
| 2 | Sections 3-5: sentinel clear, conversion, log, assertions | 93e5829 | sas/03_prep_md8.sas |

Tasks 1 and 2 were written together in a single file and committed atomically.

---

## Checkpoint Reached

**Task 3: Run md8 prep and confirm conversion + clinical ranges**

- Type: human-verify
- Blocked by: requires SAS session with P: drive mapped

---

## What Was Built

`sas/03_prep_md8.sas` — 388 lines, five sections:

**Section 0 (lines 27-36):** Canonical paths (`source_path`, `qc_path`, `logs_path`, `g_path`) and `%let expected_nobs = 22473`.

**Section 1 (lines 40-94):** Four preconditions — `check_libname(src)`, `check_libname(g)`, `check_dir(qc)`, `check_dir(logs)`, plus md8 identity check (PROC CONTENTS confirms 8 forced-char variables are CHARACTER, abort if not).

**Section 2 (lines 98-182):** Pre-conversion exception scan using PROC SQL UNION ALL across all eight forced-char numerics (notdigit(compress) pattern). Encoding-damage flag via verify() against printable ASCII — counted separately into `&n_enc`, never passed to assert_zero (Pitfall 6). Exception report written to `qc/03_exceptions_md8.txt` before the abort test. Abort only on `&n_exc`.

**Section 3 (lines 196-308):** Two-step normalization.
- Step 1: `data work.prep_md8_s1` — LENGTH-before-SET (confirmed widths for 8 forced-char numerics and PRECEDE_STUDY_ID), `array _charv {*} _CHARACTER_` sentinel clear loop.
- Step 2: `data g.prep_md8` — RENAME= dataset option renames 8 char vars to _c temps; INPUT(strip(var_c), best12.) creates same-named numerics; DROP removes all _c temps.

**Section 4 (lines 312-365):** 17 SELECT COUNT(*) INTO queries (total rows + 2 per variable: converted non-missing and NULL-cleared). Written to `logs/03_conversions_md8.txt`.

**Section 5 (lines 369-401):** Three post-conversion assertions:
1. `n_null_surv` — zero surviving NULL strings in all char vars of g.prep_md8
2. `n_stillchar` — zero of the 8 converted variables still character in dictionary.columns
3. `n_prep` — row count matches `&expected_nobs` (22,473)

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Dependency Gap] Written as combined Tasks 1+2 in single commit**
- **Found during:** Task 1 execution
- **Issue:** Plan specified Tasks 1 and 2 as separate (Task 1 Sections 0-2, Task 2 Sections 3-5 appended below marker). Since both tasks modify the same file and were written in sequence without a checkpoint between them, writing both together is more reliable (no risk of append confusion).
- **Fix:** Single Write operation for complete file; single commit covering both tasks. The Task-2 marker line is preserved in the file for audit traceability.
- **Files modified:** sas/03_prep_md8.sas
- **Commit:** 93e5829

**2. [Rule 2 - Missing Critical Functionality] LENGTH block incomplete for non-forced-char md8 variables**
- **Found during:** Task 1/2 — reading qc/03_charvars_all.txt
- **Issue:** `qc/03_charvars_all.txt` does not exist (it is a run-time artifact of `03_prep_setup.sas` which requires SAS and P: drive). Without it, the complete LENGTH block for md8 character variables cannot be written.
- **Fix:** Wrote LENGTH declarations for all confirmed variables (PRECEDE_STUDY_ID $12, Base_Procedure_1 $200, all eight forced-char numerics at confirmed widths: Admit_BMI $11, others $4). Added TODO comments for remaining char vars with explicit instructions to source widths from qc/03_charvars_all.txt. The _CHARACTER_ array sentinel clear handles all variables dynamically regardless of LENGTH coverage. The NULL-surviving assertion in Section 5 covers PRECEDE_STUDY_ID and Base_Procedure_1 with a TODO comment for remaining variables.
- **Files modified:** sas/03_prep_md8.sas
- **Commit:** 93e5829

**Note for human verifier:** Before running `03_prep_md8.sas`, run `03_prep_setup.sas` first (Plan 01) to produce `qc/03_charvars_all.txt`, then complete the LENGTH block in Section 3 Step 1, the LENGTH block in Section 3 Step 2, and the NULL-surviving WHERE clause in Section 5a. These are marked with TODO comments.

---

## Known Stubs

**1. LENGTH block — undeclared character variables**
- File: `sas/03_prep_md8.sas`, lines ~216-224 (Step 1) and ~246-250 (Step 2)
- Reason: `qc/03_charvars_all.txt` (Wave 0 artifact from Plan 01 SAS run) not available at authoring time
- Resolution plan: Complete after `03_prep_setup.sas` runs (Plan 01 execution with P: drive)

**2. NULL-surviving assertion — WHERE clause incomplete**
- File: `sas/03_prep_md8.sas`, lines ~363-369 (Section 5a)
- Reason: Same as above — complete character variable list not available
- Resolution plan: Add all remaining character variable OR clauses after qc/03_charvars_all.txt is available

---

## Self-Check: PASSED

All acceptance criteria verified via grep:
- File exists: sas/03_prep_md8.sas (388 lines)
- `libname src access=readonly`: present
- `%let expected_nobs = 22473`: present
- `notdigit(compress` count: 8 (one per forced-char numeric)
- `n_forcedchar ne 8`: present
- `03_exceptions_md8.txt`: present
- `assert_zero(n=&n_exc`: present
- `assert_zero(n=&n_enc`: absent (correct — encoding not in abort)
- `verify(Base_Procedure_1`: present
- Task 2 marker: present
- `input(strip(` count: 8
- `array _charv {*} _CHARACTER_`: present
- `PRECEDE_STUDY_ID $12`: present
- `data g.prep_md8` and `data work.prep_md8_s1`: both present
- `rename=(Admit_BMI=Admit_BMI_c`: present
- `03_conversions_md8.txt` under `&logs_path`: present
- `n_null_surv`: present
- `dictionary.columns` and `type='char'`: present
- `assert_row_count(actual=&n_prep, expected=&expected_nobs`: present
- `==== Phase 3 prep md8 complete`: present
- No PROC SQL UPDATE: confirmed absent
- No bare `%abort` outside macro: all 6 abort statements inside macro bodies
- LENGTH before SET: length at line 202, `set src.master_data_8` at line 226
- Spot-check widths: Age_at_Encounter $4, Cognitive_Score $4, Frailty_Score $4, rt_* $4, Admit_BMI $11 — all correct per RESEARCH post-review

Commit 93e5829 verified in git log.
