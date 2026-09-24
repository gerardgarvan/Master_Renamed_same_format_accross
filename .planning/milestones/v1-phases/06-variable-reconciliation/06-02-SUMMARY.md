---
phase: 06-variable-reconciliation
plan: "02"
subsystem: reconciliation-qc
tags: [sas, reconciliation, qc, read-only, phase6]
dependency_graph:
  requires: [06-01, 05-03, 04-02]
  provides: [qc/06_reconcile_summary.txt (on P:), sas/06_reconcile.sas]
  affects: [99_run_all.sas, Phase 8 handoff]
tech_stack:
  added: []
  patterns: [assert_col macro, FILE/PUT DATA _NULL_ summary, dictionary.columns schema check]
key_files:
  created:
    - sas/06_reconcile.sas
  modified: []
decisions:
  - "qc/06_reconcile_summary.txt was written by SAS to the P: merge tree (qc_path), not to the local git working directory -- consistent with the established pipeline convention (all QC outputs on P:, committed to repo only when copied manually)"
  - "All 16 deliberate columns (3 mortality, 10 frailty, 3 ISO_SEV) plus Emergent and rt_envelope_flag confirmed present per human verification of 18 PASS lines in the log"
  - "SAS program is strictly read-only: reads g.master_data_merged only, writes only qc/06_reconcile_summary.txt via FILE/PUT; no dataset created or modified"
metrics:
  duration: "human checkpoint approx 1 session"
  completed_date: "2026-08-27"
  tasks: 2
  files: 1
---

# Phase 06 Plan 02: Write and Run sas/06_reconcile.sas — Summary

**One-liner:** Read-only Phase 6 reconciliation QC program confirms 16 deliberate multi-column concepts and Emergent/rt_envelope_flag distributions, writing prose summary to P: qc tree.

---

## What Was Built

`sas/06_reconcile.sas` — a five-section read-only SAS program that:

- **SECTION 0:** Asserts the g library is accessible and `g.master_data_merged` exists; defines paths via macros.
- **SECTION 1:** Calls `%assert_col` 18 times — 16 deliberately-separate columns (D-01/D-02/D-03) plus Emergent (D-04) and rt_envelope_flag (MRG-05). Each success emits a `PASS`-tagged NOTE; any absent column triggers `%abort cancel`.
- **SECTION 2:** Counts Emergent as Y/N/blank (NOT 1/0 — PCM-F-06). Reports without asserting.
- **SECTION 3:** Reports rt_envelope_flag distribution (0 / 1) without hard-asserting the flagged count of 9 (PCM-D-08 observation, not invariant).
- **SECTION 3b:** Spot-checks non-missing counts for six representative columns (one per concept group) to catch a present-but-empty column that SECTION 1 structurally cannot see.
- **SECTION 4:** Records the PCM-D-10 note that rt_ANCHOR_to_*_days negatives are legitimate anchor offsets, not nulled.
- **SECTION 5:** Writes `qc/06_reconcile_summary.txt` via FILE/PUT DATA _NULL_ with all findings, the Emergent caveat (D-04 wording calibrated to the md3-owned merged column, not the md1/md8 source rates), and the PCM-D-10 anchor-offset note.

---

## Acceptance Criteria Verified (by human)

| Criterion | Result |
|---|---|
| `grep -E "ERROR\|ASSERTION FAILED" logs/06_reconcile.log` returns nothing | PASS |
| `grep -c "PASS" logs/06_reconcile.log` >= 18 | PASS (18 lines) |
| `qc/06_reconcile_summary.txt` exists on P: | PASS |
| `grep "Emergent" qc/06_reconcile_summary.txt` | PASS |
| `grep "rt_envelope_flag" qc/06_reconcile_summary.txt` | PASS |
| `grep "PCM-D-10" qc/06_reconcile_summary.txt` | PASS |

---

## QC File Location

`qc/06_reconcile_summary.txt` was written to the P: merge tree (`&qc_path.`) by SAS, consistent with the pipeline convention established in Phase 3 (all pipeline QC outputs on P:). The file is NOT in the local git working directory. The human reviewer confirmed its existence and correct content before approving the checkpoint.

To commit it as a versioned artifact, copy it manually from P: to `qc/` in the local git working tree and run `git add qc/06_reconcile_summary.txt`.

---

## Commits

| Task | Commit | Description |
|---|---|---|
| Task 1 | 1f53056 | feat(06-02): write sas/06_reconcile.sas -- read-only Phase 6 reconciliation QC |
| Task 1 (revised) | b8784bd | fix(06-reconcile): update 06_reconcile.sas with revised version |

---

## Deviations from Plan

**1. [Rule 1 - Convention] qc/06_reconcile_summary.txt not committed to git**

- **Found during:** Task 2 completion
- **Issue:** The plan specified committing `qc/06_reconcile_summary.txt` to git. SAS writes this file to `&qc_path.` on the P: merge tree, which is outside the git working directory — consistent with the pipeline-wide convention (see STATE.md: "All pipeline paths are on P: — g_path, logs_path, qc_path. QC reports are therefore NOT version-controlled").
- **Fix:** Documented in SUMMARY. The human confirmed the file exists with correct content. A git commit of this file requires a manual copy step from P: to the local `qc/` directory.
- **Files modified:** None (no incorrect commit made)

---

## Known Stubs

None. The program is complete and correct. The missing git commit of `qc/06_reconcile_summary.txt` is a workflow gap, not a stub — the file exists and has been verified by the human reviewer.

---

## Self-Check: PASSED

- `sas/06_reconcile.sas` exists in git (commits 1f53056, b8784bd verified above)
- Human-verified: 18 PASS lines in log, QC summary on P: with all required content
- No dataset written by the program (read-only verified by reviewer)
