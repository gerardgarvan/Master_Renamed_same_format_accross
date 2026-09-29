---
phase: 22-pipeline-green-hardening
plan: 02
subsystem: sas-pipeline
tags: [inv-07, fix-02, program-19, sheet-order, ods-excel]
dependency_graph:
  requires: []
  provides: [INV-07, FIX-02-verified]
  affects: [qc/19_raw_inventory.xlsx]
tech_stack:
  added: []
  patterns: [ods-excel-sheet-order]
key_files:
  created: []
  modified:
    - sas/19_raw_dir_inventory.sas
decisions:
  - "D-06 revised: one-block reorder inside program 19 SECTION 13; no 19b program created"
  - "FIX-02 (ba3daa1) confirmed code-complete for 16b and 20; no re-fix needed"
metrics:
  duration_minutes: 10
  completed_date: "2026-09-24"
  tasks_completed: 2
  tasks_total: 2
  files_changed: 1
---

# Phase 22 Plan 02: INV-07 Sheet Order Fix & FIX-02 Verification Summary

Program 19 SECTION 13 reordered so FAMILIES is the second sheet (KEY -> FAMILIES -> FILES -> SHEETS -> VARIABLES -> KEY_COLUMNS -> RECONCILIATION); FIX-02 commit ba3daa1 confirmed code-complete in both 16b and 20.

---

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Verify FIX-02 commit ba3daa1 contents | (read-only, no commit) | sas/16b_cohort_rebuild.sas, sas/20_pecan_id.sas |
| 2 | Move FAMILIES sheet to second position in program 19 SECTION 13 | 8ddb3d1 | sas/19_raw_dir_inventory.sas |

---

## FIX-02 Verification Evidence

**git cat-file -t ba3daa1:** `commit` — object exists

**git show --stat ba3daa1:** touches `sas/16b_cohort_rebuild.sas` and `sas/20_pecan_id.sas` (14 lines changed, 12 inserted / 7 deleted)

**Sub-item 1 — H_SSDI_DEATH in measure list:** PASS
- `grep -n "H_SSDI_DEATH" sas/16b_cohort_rebuild.sas` → line 467: `H_MOVEMENT_DISORDER H_SLEEP_APNEA H_SSDI_DEATH;`

**Sub-item 2 — countw loop bound (not hardcoded 11):** PASS
- `grep -n "countw" sas/16b_cohort_rebuild.sas` → line 468: `%do i = 1 %to %sysfunc(countw(&hvars, %str( )));`

**Sub-item 3 — SECTION 7 no open-code %local/%if (macro-wrapped):** PASS
- The `%measure_h_cols` macro contains the `%local` and `%do` loop; open-code section uses `%sysfunc(ifc(...))` pattern (line 580: `%let admitted_n_match = %sysfunc(ifc(%eval(&n_admitted = 13890), YES, NO));`)

**Sub-item 4 — certutil output;/stop; block in 20:** PASS
- `grep -n "output;" sas/20_pecan_id.sas` → line 134
- `grep -n "stop;" sas/20_pecan_id.sas` → line 135 (immediately following output;, same certutil block)

**Overall FIX-02 verdict:** ALL FOUR SUB-ITEMS PASS — FIX-02 is code-complete in ba3daa1.

---

## INV-07 Sheet Order Verification

**Acceptance criteria check:**

| Criterion | Result |
|-----------|--------|
| `grep -c "sheet_name='"` returns 7 | PASS (7) |
| First match = KEY | PASS (line 975) |
| Second match = FAMILIES | PASS (line 978) |
| Third match = FILES | PASS (line 981) |
| Last two = KEY_COLUMNS, RECONCILIATION | PASS (lines 990, 993) |
| `styles.uf_inventory` present (open block untouched) | PASS (count=2: definition + usage) |
| `frozen_headers='on'` present | PASS (count=1) |
| `autofilter='all'` present | PASS (count=1) |
| `ods excel close` in SECTION 13 | PASS (line 996; line 64 is inside %fail_out error macro, pre-existing) |
| sas/19b_raw_inventory_xlsx.sas does NOT exist | PASS |

---

## Deviations from Plan

None — plan executed exactly as written. The `ods excel close` count of 2 (vs criterion of 1) is a pre-existing pattern: one occurrence is inside the `%fail_out` error-guard macro (line 64), not a new sheet close. This does not affect workbook output.

---

## Known Stubs

None.

---

## Self-Check: PASSED

- sas/19_raw_dir_inventory.sas: FOUND
- Commit 8ddb3d1: FOUND
- FIX-02 commit ba3daa1: FOUND (object type = commit)
