---
phase: 28-r7-r8-r9-linkage-investigation
plan: "02"
subsystem: decisions
tags: [decisions, linkage, LINK-03, PCM-D-28, standalone]
dependency_graph:
  requires:
    - phase: 28-plan-01
      provides: sas/28_linkage_investigation.sas and LINK-01 finding
    - runtime: qc/28_linkage_investigation.csv (produced on P: drive by human-action gate)
  provides:
    - docs/DECISIONS.md (PCM-D-28 appended)
  affects:
    - Phase 29 gap-fill wiring (r7-r9 exclusion documented, tentative)
tech-stack:
  added: []
  patterns:
    - "Decision entry cites specific CSV rows with both-direction rates, matching PCM-D-31 citation style"
    - "PHI guard maintained: no ENCRYPTED_MRN sample/min/max values in decision text"
key-files:
  created: []
  modified:
    - docs/DECISIONS.md
key-decisions:
  - "PCM-D-28 RESOLVED 2026-10-07: r7/r8/r9 have no ENCRYPTED_MRN; MRN linking infeasible with current extracts; 9,215-ID mismatch unrecoverable; v2.3 reopening condition is re-extract with ENCRYPTED_MRN or PRECEDE_STUDY_ID crosswalk table"
  - "md7_vs_md3_2022=100% both directions; r7_vs_md7=0%, r8_vs_md7=0% -- ID-space incompatibility confirmed, not a normalization issue"
requirements: [LINK-03]
duration: 15min
completed: 2026-10-07
---

# Phase 28 Plan 02: Write PCM-D-28 in docs/DECISIONS.md -- Summary

**PCM-D-28 recorded: r7/r8/r9 MRN linking infeasible with current extracts; 9,215-ID mismatch unrecoverable; Phase 29 r7-r9 exclusion documented as tentative with a specific v2.3 reopening condition**

## Performance

- **Duration:** ~15 min (continuation after human-action gate)
- **Started:** 2026-10-07
- **Completed:** 2026-10-07
- **Tasks:** 2 (Task 1: human-action gate; Task 2: write PCM-D-28)
- **Files modified:** 1 (docs/DECISIONS.md)

---

## Task 1 Gate Results (Human-Provided)

SAS program ran ERROR-free. `qc/28_linkage_investigation.csv` was written (19 records).
PHI guard held -- no ENCRYPTED_MRN sample/min/max values appear in the log or CSV.

### Block 1 -- SHA comparison (all 7 pairs)

| source_pair | sha_identical_flag |
|---|---|
| 2018_2019_X_MASTER_DATASET_raw_vs_master | NO |
| 2018_2019_CPT_ROLLUP_X_MASTER_raw_vs_master | NO |
| 2018_2022_X_MASTER_raw_vs_master | NO |
| 2020_X_MASTER_raw_vs_master | NO |
| 2020_CPT_ROLLUP_X_MASTER_raw_vs_master | NO |
| 2021_X_MASTER_raw_vs_master | NO |
| 2022_MASTER_raw_vs_master | NO |

All 7 pairs: sha_identical_flag = NO. The 2020-2022 same-size pairs are confirmed NOT
byte-identical (pre-established from CONTEXT.md; now confirmed by Block 1 runtime).

### Block 3 -- ID match rates (program-derived, both directions)

| source_pair | n_left | n_right | n_matched | match_rate_left | match_rate_right |
|---|---|---|---|---|---|
| md7_vs_md3_2022 | 9,215 | 9,215 | 9,215 | 1.00000 | 1.00000 |
| r7_vs_md3_2022 | 9,215 | 9,215 | 0 | 0.00000 | 0.00000 |
| r8_vs_md3_2022 | 9,485 | 9,215 | 0 | 0.00000 | 0.00000 |
| r9_vs_md3_2022 | 9,215 | 9,215 | 0 | 0.00000 | 0.00000 |
| r7_vs_md7 | 9,215 | 9,215 | 0 | 0.00000 | 0.00000 |
| r8_vs_md7 | 9,485 | 9,215 | 0 | 0.00000 | 0.00000 |
| 2018_2019_MRN_Crypto vs master (PRECEDE_Study_ID) | 14,781 | 14,778 | 14,777 | 0.99973 | 0.99993 |
| Crypto_ENCRYPTED_MRN vs master_ENCRYPTED_MRN (count-only PHI guard) | 14,781 | 14,778 | 0 | . | . |
| 2018_2019_MRN_Crypto vs raw (PRECEDE_Study_ID) | 14,781 | 14,778 | 14,777 | 0.99973 | 0.99993 |
| 2018_2019_ENCOUNTER_Crypto vs master (PRECEDE_Study_ID) | 14,781 | 14,778 | 14,777 | 0.99973 | 0.99993 |
| Crypto_ENCOUNTER_ENCRYPTED_MRN vs master_ENCRYPTED_MRN (count-only PHI guard) | 14,781 | 14,778 | 0 | . | . |

**Key interpretations:**
1. md7_vs_md3_2022 = 100% both ways: md7 IS the 2022 base cohort; same 9,215 IDs as md3-2022.
2. r7_vs_md7 = 0%, r8_vs_md7 = 0%: r7/r8 cannot match even md7 directly. Digits-only
   normalization was tried; result is still 0. This is a fundamental ID-space incompatibility,
   not a formatting issue.
3. ENCRYPTED_MRN count-only: 0 matches -- Crypto and master use different encryption schemes
   or column contents. Does not affect LINK-01 (r7/r8/r9 have no ENCRYPTED_MRN at all).
4. 2018-2019 Crypto PRECEDE_Study_ID: ~100% match to master, but covers 2018-2019 only and
   cannot speak to 2022 linkage.

**Provenance confirmation:** the 14.5%/64%/41% PROJECT.md figures were NOT cited. They have
PROVENANCE NOT FOUND per Plan 01 SUMMARY. Only program-derived CSV rows are cited in PCM-D-28.

---

## PCM-D-28 Summary

PCM-D-28 was appended to docs/DECISIONS.md. Key content:
- Column evidence (Phase 19 inventory): r7/r8/r9 have no ENCRYPTED_MRN; only PRECEDE_STUDY_ID
- Match rate table: md7_vs_md3_2022=100%, all r7/r8/r9-vs-cohort rates=0%
- Recoverability: 9,215-ID mismatch (PCM-D-16) is unrecoverable with current extracts
- 2018-2019 Crypto note: covers 2018-2019 only, cannot speak to 2022 linkage
- SHA: 80,233-byte constant gap for 3 pairs; 2020-2022 pairs same-size but sha_identical_flag=NO
- v2.3 reopening condition (LINK-03): re-extract of r7/r8/r9 with ENCRYPTED_MRN, OR an ID
  crosswalk table mapping r7-r9 PRECEDE_STUDY_IDs to master cohort PRECEDE_STUDY_IDs
- Phase 29 scope: r7-r9 excluded tentatively; permanent exclusion requires resolving v2.3 condition

---

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Human-action gate: run SAS and review CSV | (no commit -- human action, no code) | -- |
| 2 | Write PCM-D-28 in docs/DECISIONS.md | 799985f | docs/DECISIONS.md |

---

## Acceptance Criteria Results

```
grep -c "PCM-D-28" docs/DECISIONS.md                         => 2   (PASS, >= 1)
grep -c "28_linkage_investigation.csv" docs/DECISIONS.md      => 6   (PASS, >= 1)
grep -c "PCM-D-16" docs/DECISIONS.md                         => 7   (PASS, prior count preserved + new refs)
grep -c "9,215" docs/DECISIONS.md                             => 12  (PASS)
grep -c "80,233" docs/DECISIONS.md                            => 1   (PASS)
No ENCRYPTED_MRN sample values in PCM-D-28 text               =>     (PASS -- PHI guard held)
v2.3 reopening condition is specific                           =>     (PASS -- re-extract with ENCRYPTED_MRN or crosswalk table)
```

---

## Deviations from Plan

None -- plan executed exactly as written. Task 1 was a human-action gate; the human ran
the program, confirmed ERROR-free log, confirmed PHI guard held, and provided CSV rows.
Task 2 wrote PCM-D-28 from those real, program-derived values.

---

## Known Stubs

None -- this plan appends a decision record. No UI components, no data pipelines.

---

## Self-Check: PASSED

- docs/DECISIONS.md modified: CONFIRMED (git commit 799985f, +119 lines)
- "PCM-D-28" present: grep -c returns 2
- "28_linkage_investigation.csv" cited: grep -c returns 6
- "9,215" present: grep -c returns 12
- "80,233" present: grep -c returns 1
- No ENCRYPTED_MRN sample values: CONFIRMED (PHI guard maintained throughout)
