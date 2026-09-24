---
phase: 06-variable-reconciliation
plan: "03"
subsystem: documentation
tags: [data-dictionary, phase6, decisions, ascii]
dependency_graph:
  requires: [06-01, 06-02]
  provides: [docs/data_dictionary_notes.txt]
  affects: [phase-08-documentation]
tech_stack:
  added: []
  patterns: [prose-stub, ascii-only]
key_files:
  created:
    - docs/data_dictionary_notes.txt
  modified: []
decisions:
  - "docs/data_dictionary_notes.txt is the Phase 8 source of truth for the five deliberate multi-column concepts"
  - "PCM-D-07 age floor is explicitly deferred to Phase 7 -- QC-05 floor stays 18, not tightened"
  - "rt_envelope_flag described as observation-based flagging, not fixed-count invariant"
metrics:
  duration_minutes: 15
  completed_date: "2026-08-27"
  tasks_completed: 1
  tasks_total: 1
  files_created: 1
  files_modified: 0
---

# Phase 6 Plan 03: Data Dictionary Notes Stub -- Summary

**One-liner:** ASCII prose stub documenting five deliberate multi-column concept groups (mortality, frailty, ISO_SEV, Emergent, rt_envelope_flag) with decision IDs for Phase 8 consumption.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create docs/data_dictionary_notes.txt | 8ed1f54 | docs/data_dictionary_notes.txt (created, 185 lines) |

---

## What Was Built

`docs/data_dictionary_notes.txt` -- a committed ASCII prose stub covering:

**Section 1 -- Deliberate multi-column concepts (D-01, D-02, D-03)**
- Mortality flag: Death_Date_Y_N (md1-md5), IsDead_Y_N (md6), Death (md7) -- kept separate because equivalence is unverified; _30_DAY_MORTALITY and Death_Days_After_Surgery are separate measures.
- Frailty components: ten columns for five concepts (five char Y/N + five numeric _Value); width difference ($3 vs $1) cited as evidence encodings are not interchangeable.
- ISO_SEV exposure: ISO_SEV_Exp_IntraOp_MAC_Average (md1-md3), ISO_SEV_IntraOp_MAC_Average (md4), ISO_SEV_MAC_TOTAL_Exp (md8) -- md8 is a TOTAL not an average.

**Section 2 -- Emergent caveat (D-04)**
- Values: Y / N / blank. Merged column is md3-owned.
- Source-level positive counts (PCM-F-06) explicitly NOT presented as the merged distribution.
- Refers analysts to qc/06_reconcile_summary.txt for the observed merged distribution.

**Section 3 -- rt_envelope_flag (D-08/MRG-05)**
- Flags rows where an operative sub-interval exceeds the room-occupancy interval.
- Values retained, not nulled. Flagged count is observation-based, not a fixed invariant.
- QC-06 asserts zero UNFLAGGED violations.

**Section 4 -- Deferred and closed decisions**
- PCM-D-07: age floor deferred to Phase 7; QC-05 floor stays 18, must not be tightened to 64.
- PCM-D-09: three inert operative-interval ceilings dropped (QC-07); QC-05 now has 5 assertions.
- PCM-D-11: md3-owns missingness closed -- zero recoverable values for BMI, Cognitive_Score, Frailty_Score.

**Section 5 -- PCM-D-10 pointer**
- rt_ANCHOR_to_ADMIT_days, rt_ANCHOR_to_SURGERY_days, rt_ANCHOR_to_DISCHG_days legitimately carry negatives (offsets from anchor date, not durations).

---

## Acceptance Criteria Verification

| Check | Result |
|-------|--------|
| File exists | PASS |
| >= 40 lines (185 lines) | PASS |
| Contains Death_Date_Y_N | PASS |
| Contains Feels_Exausted_Value | PASS |
| Contains ISO_SEV_MAC_TOTAL_Exp | PASS |
| Contains rt_envelope_flag | PASS (4 occurrences) |
| Contains PCM-D-07 + Phase 7 reference | PASS |
| Contains PCM-D-09 | PASS |
| Contains PCM-D-11 | PASS |
| Contains Emergent | PASS |
| Contains "Y / N / blank" | PASS |
| "7 positives in md1" absent | PASS (source counts not presented as merged distribution) |
| "always 9" invariant absent | PASS |
| ASCII only | PASS (Python byte scan -- no bytes > 127) |

---

## Deviations from Plan

None -- plan executed exactly as written.

---

## Known Stubs

`docs/data_dictionary_notes.txt` is itself a stub by design -- it is the input for Phase 8's `08_dictionary.sas`, which will fold its content into `docs/DATA_DICTIONARY.xlsx`. This is the intended artifact; Phase 6's goal is to create it, not to replace it.

---

## Self-Check: PASSED

- `docs/data_dictionary_notes.txt` exists: CONFIRMED
- Commit 8ed1f54 exists: CONFIRMED (git log output above)
