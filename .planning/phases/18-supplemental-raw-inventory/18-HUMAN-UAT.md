---
status: partial
phase: 18-supplemental-raw-inventory
source: [18-VERIFICATION.md]
started: 2026-09-22T00:00:00Z
updated: 2026-09-22T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. ID Diagnostic File Content (RAW-08)

**Test:** Run `sas/18_supplemental_raw_gap.sas` in a SAS 9.4 session with D15_APPROVED=0 (default) and access to P: drive.
expected: File qc/18_id_diagnostic.txt contains three 5-ID sample blocks labelled "5 BASE IDs NOT IN r9", "5 r9 IDs NOT IN BASE", "5 r7 IDs (numeric, best32.)"; followed by four LENGTH DISTRIBUTION sections; final line reads "PCM-D-16 remains open -- no cast or fix applied by this program"; program continues past Section A without aborting.
result: [pending]

### 2. Gap Candidates File Content (RAW-09, RAW-10)

**Test:** After the same run, open `qc/18_gap_candidates.txt`.
expected: File contains: header with run date and sentinel rule; per-file summary for r1/r2/r3/r4/r5/r6/r9; IN_BASE detail sorted by pct_fillable DESC with TYPE_DIFF flags; NEW individual columns sorted by pct_raw_populated DESC; four-row r2 family rollup (COM_dCDT, COPY_dCDT, LINUS, paper_neuropsych) with n_cols and median; divider appendix with all 8 names; r7/r8 excluded note.
result: [pending]

### 3. Gate Behavior with D15_APPROVED=0 (RAW-11)

**Test:** With `%let D15_APPROVED = 0;` in `00_config.sas` (default), run program 18, then run program 17.
expected: SAS log for program 18 shows ERROR: PCM-D-15 awaiting approval message after qc/18_gap_candidates.txt written line; SAS log for program 17 shows the same gate ERROR before any work.analysis_base_ext step begins.
result: [pending]

### 4. Gate Pass with D15_APPROVED=1 (RAW-11)

**Test:** Set `%let D15_APPROVED = 1;` in `00_config.sas` and re-run both programs 18 and 17.
expected: Both programs complete without the PCM-D-15 gate error; program 17 produces work.analysis_base_ext.
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
