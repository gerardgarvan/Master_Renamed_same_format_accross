---
phase: 16-rebuild-the-analytic-cohort
plan: "02"
subsystem: decisions
tags: [decisions, PCM-D-05, attribution, cohort, STATE]
dependency_graph:
  requires: [16-01-SUMMARY.md (measured values), docs/DECISIONS.md, .planning/STATE.md]
  provides: [Resolved PCM-D-05 decision record, Price follow-up item in STATE.md]
  affects: [docs/DECISIONS.md, .planning/STATE.md]
tech_stack:
  added: []
  patterns: []
key_files:
  created: []
  modified:
    - docs/DECISIONS.md
    - .planning/STATE.md
decisions:
  - "PCM-D-05 resolved: admitted-only cohort (INPATIENT+OBSERVATION, N=13,890); BMI-forces-restriction rationale; PCM-F-12 void; Gerard 2026-09-21; Price informed"
  - "Price follow-up item added to STATE.md: inform Price and update DECISIONS.md attribution line on response"
metrics:
  duration: ~10min
  completed: "2026-09-22"
  tasks: 2
  files: 2
---

# Phase 16 Plan 02: PCM-D-05 Resolution and STATE.md Baselines Summary

**One-liner:** PCM-D-05 resolved in DECISIONS.md with BMI-forces-restriction rationale, all five population-shift figures, BMI HAVE/LACK against the 13,890 admitted denominator, and Gerard attribution (Price: informed); STATE.md updated with resolution and follow-up item.

---

## What Was Done

### Task 1 -- docs/DECISIONS.md

Summary table row updated from `Pending -- Phase 7` to `Resolved -- Phase 16, 2026-09-21, Gerard`.

Full detail entry added for PCM-D-05 containing:

1. **Resolution:** admitted-only cohort, N = 13,890 (INPATIENT 13,223 + OBSERVATION 667).
   Dataset g.analytic_cohort rebuilt by sas/16b_cohort_rebuild.sas (Phase 16); HARM-10 satisfied.

2. **True rationale (new):** Admit_BMI forces the restriction -- all 12,726 BMI values are inside
   the admitted cohort, zero ambulatory. The OLD rationale (PCM-F-12: ambulatory patients never
   eligible for geriatric assessments) is VOID after MRG-06 / PCM-F-19.

3. **Population shift (five Phase 13 figures):**
   - Charlson 0: 60.8% -> 34.5%
   - General anaesthesia: 57.6% -> 84.2%
   - GI service: 18.4% -> 1.7%
   - Colonoscopy: 8.5% -> 0.4%
   - RACE=WHITE: 79.8% -> 87.1% (7.3-point shift; required in methods sections)

4. **BMI availability within 13,890 admitted cohort:**
   HAVE: 12,726 (91.6%) | LACK: 1,164 (8.4%) -- denominator named explicitly.

5. **Attribution:** Decided by Gerard, 2026-09-21. Price: informed.

6. **Cross-reference:** sas/16b_cohort_rebuild.sas (Phase 16); qc/16b_cohort_missingness.txt.

### Task 2 -- .planning/STATE.md

- PCM-D-05 removed from "Still open" block.
- Added to Established Decisions as RESOLVED 2026-09-21 with rationale and HARM-10 note.
- Price follow-up item added under Pending Decisions / Follow-ups:
  "Inform Price of PCM-D-05 resolution; update DECISIONS.md attribution line from
  'informed' to reflect Price's response once received."
- Last Updated line updated to reflect Phase 16 completion (2026-09-22).

---

## Measured Baselines Transcribed into STATE.md

(All measured by sas/16b_cohort_rebuild.sas run 2026-09-22; source: 16-01-SUMMARY.md)

| Metric | Value |
|--------|-------|
| admitted_n | 13,890 |
| g.analytic_cohort rows | 13,890 |
| g.analytic_cohort columns | 174 |
| Within-cohort BMI (HAVE) | 12,726 (91.6%) |
| Within-cohort BMI (LACK) | 1,164 (8.4%) |
| Within-cohort Cognitive_Score | 7,252 (52.2%) -- prior merged reference |
| Within-cohort Frailty_Score | 8,150 (58.7%) -- prior merged reference |
| All-three complete-case within cohort | 6,523 (47.0% of 13,890) |

---

## Deviations from Plan

None -- plan executed exactly as written. Price's status was confirmed as "informed" at the
decision checkpoint before this continuation agent was spawned.

---

## Known Stubs

None.

---

## Self-Check: PASSED

- `docs/DECISIONS.md` exists: FOUND
- `.planning/STATE.md` exists: FOUND
- Commit `c42e464` (Task 1) exists: FOUND
- Commit `92ae267` (Task 2) exists: FOUND
