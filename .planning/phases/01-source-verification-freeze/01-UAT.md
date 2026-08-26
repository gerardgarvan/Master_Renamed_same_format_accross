---
status: complete
phase: 01-source-verification-freeze
source: [01-01-SUMMARY.md, 01-02-SUMMARY.md]
started: 2026-08-25T00:00:00Z
updated: 2026-08-25T00:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Program runs clean on good data
expected: |
  Run `sas/01_verify_sources.sas` with P: drive mapped and XCMD enabled.
  The log should show no ERROR lines and no ABORT. You should see these NOTE lines:
    NOTE: XCMD enabled -- FILENAME PIPE available for SRC-04.
    NOTE: SRC-06 OK -- PRECEDE_STUDY_ID is Char 12 in all eight sources.
    NOTE: SRC-05 OK -- no blank PRECEDE_STUDY_ID in master_data_1. (x8)
    NOTE: PCM-F-01 OK -- PRECEDE_STUDY_ID unique in master_data_1. (x8)
    NOTE: PCM-F-02 OK -- md3 is a complete superset of md1,md2,md4-md8.
result: pass

### 2. qc/checksums.txt populated with real hashes
expected: |
  After the run, open `qc/checksums.txt`. It should contain:
  - A timestamp line at the top
  - The regeneration caveat paragraph ("not evidence of corruption")
  - 8 lines of the form: master_data_N  <64 hex characters>
  - No placeholder text
result: pass

### 3. qc/src_counts.txt populated with real counts
expected: |
  Open `qc/src_counts.txt`. It should contain:
  - A timestamp line
  - A header row: Source / NOBS / Distinct_IDs
  - 8 data rows, one per source, with two integer columns each
  - master_data_3 row should show NOBS = 41150 (or a WARNING appears in the log if different)
result: pass

### 4. Abort fires on P: drive unavailable
expected: |
  (Static check — no need to test live if inconvenient)
  Open `sas/01_verify_sources.sas` and confirm the libname check block contains:
    %if %sysfunc(libref(&lib)) ne 0 %then %do;
      %put ERROR: LIBNAME ... Check P: drive availability.
      %abort cancel;
  The program would abort with a legible message if P: is not mapped, rather than
  crashing silently downstream.
result: pass

### 5. Abort fires on NOXCMD with correct message
expected: |
  (Static check)
  In `sas/01_verify_sources.sas`, the XCMD gate should contain the text "NOXCMD" in
  its ERROR message — so the message blames the SAS option, not certutil. Confirm
  `grep NOXCMD sas/01_verify_sources.sas` returns at least one match.
result: pass

### 6. &SQLOBS absent from program
expected: |
  `grep -c SQLOBS sas/01_verify_sources.sas` returns 0.
  Every abort decision in the program uses an explicitly counted macro variable
  (:n_blank, :n_dups, :n_orphan), never the unreliable &SQLOBS automatic variable.
result: pass

## Summary

total: 6
passed: 6
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none yet]
