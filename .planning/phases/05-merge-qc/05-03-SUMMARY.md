---
phase: 05
plan: 03
subsystem: merge-qc
tags: [qc, operative-intervals, envelope-flag, assertions]
dependency_graph:
  requires: [05-01, 05-02, 03-06, 04-01, 04-02]
  provides: [QC-06, QC-07]
  affects: [sas/05_qc_merge.sas, qc/05_qc_merge_report.txt]
tech_stack:
  added: []
  patterns:
    - "Both-sided IS NOT MISSING guard on every relational comparison (PCM-T-11)"
    - "Report DATA step written before assertion so numbers survive %abort cancel"
    - "Assert zero UNFLAGGED violations, not zero violations — flag covers known-bad rows"
key_files:
  modified:
    - sas/05_qc_merge.sas
  created:
    - qc/05_qc_merge_report.txt
decisions:
  - "PCM-D-08: flag impossible timestamp combinations, do not null them — each value is individually plausible"
  - "PCM-D-09 / QC-07: three operative-interval ceilings removed — never fired on 41,150 rows, no mechanism to fire"
metrics:
  duration: "external execution"
  completed: "2026-08-27"
  tasks_completed: 4
  tasks_total: 4
  files_modified: 2
---

# Phase 05 Plan 03: QC-06 Envelope Assertion and QC-07 Ceiling Removal Summary

QC-06 containment assertion added to 05_qc_merge.sas with both-sided IS NOT MISSING guards; QC-05 reduced from 8 to 5 assertions by dropping three inert operative-interval ceilings (QC-07); all QC-01 through QC-07 pass on 41,150 rows.

---

## What Was Built

### Task 1: SECTION 5b — QC-06 containment assertion

Added SECTION 5b to `sas/05_qc_merge.sas` between QC-05 and the close-out section. The assertion checks that no row escapes the `rt_envelope_flag` with a sub-interval longer than the room occupancy that contains it.

Key design decisions carried into code:
- **Assert zero UNFLAGGED violations**, not zero violations. The 9 known contradictory rows carry `rt_envelope_flag = 1`; the assertion fires only if future re-extracts introduce a violation the flag logic misses.
- **Both-sided IS NOT MISSING guard (PCM-T-11)**. In SAS, `a > b` is TRUE when `b` is missing because missing sorts below every number. An unguarded containment test returned 8,369 rows in diagnostic testing instead of 52.
- **Report DATA step runs before the assertion** so numbers survive an `%abort cancel` (RESEARCH Pitfall 6 pattern).
- Per-variable split (`n_env_rt1` / `n_env_rt2`) written to the report so a composition shift is visible without becoming a second abort point.

One `%assert_eq` call: `actual=&n_unflagged, expected=0, label=QC-06 unflagged envelope violations`.

### Task 2: QC-07 — remove three inert operative-interval ceilings from QC-05

Deleted from SECTION 5:
- `:n_rt1_range` — `rt_INCISE_to_DRESS_mins > 2000`
- `:n_rt2_range` — `rt_RM_START_to_INCISION_mins > 500`
- `:n_rt3_range` — `rt_RM_START_to_RM_END_mins > 2000`

All three `SELECT ... INTO :` blocks, their `%assert_eq` calls, and their report lines were removed. A multi-line explanatory comment was substituted in the PROC SQL block:

> "A bound that has never fired and has no mechanism to fire is not a check; leaving it in invites someone to widen it later to make a run green."

QC-05 dropped from 8 assertions to 5. The five retained checks (Admit_BMI, ASA, Age_at_Encounter, Cognitive_Score, Frailty_Score) are unchanged.

### Task 3: SECTION 5c — distribution report (PCM-D-09 record)

Appended SECTION 5c after SECTION 5b. Report-only block — no `%assert_eq`, no `%abort`. Writes N, min, max, and mean for the three operative-interval variables alongside their former ceilings, so the decision to drop the ceilings is traceable to measured data.

Every aggregate uses a `WHERE variable IS NOT MISSING` guard, making `&dN_n` the count of usable values rather than the total row count.

### Task 4: Human SAS run — all checks passed

Full Phase 5 run after the 03-06 → Phase 4 → Phase 5 re-run chain. Result from `qc/05_qc_merge_report.txt`:

```
ALL QC CHECKS PASSED (QC-01 through QC-07)
```

| Check | Result |
|-------|--------|
| QC-01 row count | 41,150 (expected 41,150) |
| QC-02 truncated char vars | 0 |
| QC-03 NULL strings | 0 |
| QC-04 md8-owned scoping violations | 0 (all 20 pass) |
| QC-05 clinical range assertions (5) | all 0 out-of-range |
| QC-06 unflagged envelope violations | 0 (assertion passes) |
| QC-06 flagged rows (rt_envelope_flag=1) | 9 (5 rt_INCISE, 4 rt_RM_START_to_INCISION) |

SECTION 5c distribution (from the QC report):

| Variable | N | Min | Max | Mean | Former ceiling |
|----------|---|-----|-----|------|----------------|
| rt_INCISE_to_DRESS_mins | 28,858 | -483 | 870 | 110.5 | 2000 (removed) |
| rt_RM_START_to_INCISION_mins | 36,187 | -188 | 334 | 34.8 | 500 (removed) |
| rt_RM_START_to_RM_END_mins | 37,159 | 0 | 1,006 | 145.1 | 2000 (removed) |

Negative mins in the SECTION 5c distribution are pre-PREP-08 rows in the source that were present in the non-missing population counted there; PREP-08 nulls negatives before merge so none appear in the QC-06 containment check (which runs against `g.master_data_merged`). All three maxima are well below the former ceilings, confirming QC-07.

---

## Decisions Made

### PCM-D-08: Flag, do not null (resolved 2026-08-27)

The 9 envelope-violating rows have POSITIVE values inside the former QC-05 bounds and are not touched by PREP-08 (which nulls only negatives). Each timestamp in a violating row is individually plausible; only the combination is impossible, and nothing identifies which of the three timestamps is wrong. Nulling would destroy two good values to punish an unidentifiable one.

Resolution: `rt_envelope_flag = 1` derived in the Phase 4 DATA step (MRG-05). QC-06 asserts zero UNFLAGGED violations.

### PCM-D-09: Drop the operative-interval ceilings (QC-07, resolved 2026-08-27)

The ceilings of 2000 and 500 minutes never fired on any of 41,150 rows. Every QC-05 time failure across both runs was a NEGATIVE value, never an excess. A bound that cannot fire is not a check. Replaced by: PREP-08 (floors at source) and QC-06 (containment by relationship assertion).

---

## Deviations from Plan

None — plan executed exactly as written. PCM-D-08 and PCM-D-09 were already resolved in the AMENDMENT-01 context before coding began, so no mid-task decisions were needed.

---

## Known Stubs

None. All three sections write to the QC report with measured values.

---

## Self-Check: PASSED

- `sas/05_qc_merge.sas` modified — externally committed
- `qc/05_qc_merge_report.txt` exists and ends with `ALL QC CHECKS PASSED (QC-01 through QC-07)`
- Commits present: feat(phases 03-05), fix(prep/merge), qc(05-merge-qc)
