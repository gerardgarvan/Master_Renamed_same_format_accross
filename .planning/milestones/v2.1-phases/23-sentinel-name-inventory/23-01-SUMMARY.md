---
phase: 23-sentinel-name-inventory
plan: "01"
subsystem: sentinel-inventory
tags: [sas, sentinel, pcnr, hex-key, inventory]
dependency_graph:
  requires: [22-pipeline-green-hardening]
  provides: [23_pcnr_inventory.sas SECTIONS 0-5, %hexkey macro, PCNR_APPROVED gate flag]
  affects: [Phase 24 gate (reads qc/23_sentinel_candidates.csv)]
tech_stack:
  added: ["%hexkey macro (00_config.sas)"]
  patterns: ["single-pass array sweep", "dictionary.columns metadata", "SASHELP.VTABLE fingerprint"]
key_files:
  created:
    - sas/23_pcnr_inventory.sas
  modified:
    - sas/00_config.sas
decisions:
  - "PCNR_APPROVED gate defaults to 0 in 00_config.sas; flip to 1 after human review"
  - "%hexkey uses substr(put(&var,$hex400.),1,2*length(&var)) -- covers 200-byte max char, strips trailing-blank padding, never bare $hex."
  - "freetext_cols = Base_Procedure_1 only (explicit exclusion, not length heuristic)"
  - "Numeric sentinels always candidate_class=REVIEW, never AUTO (D-03)"
  - "Numeric 0 in score_cols is AMBIGUOUS, not AUTO (D-02)"
metrics:
  duration: "~5 minutes"
  completed: "2026-09-28"
  tasks_completed: 3
  tasks_total: 3
  files_modified: 2
---

# Phase 23 Plan 01: Sentinel Inventory SECTIONS 0-5 Summary

PCNR_APPROVED gate flag and shared %hexkey macro added to 00_config.sas; sas/23_pcnr_inventory.sas written with SECTIONS 0-5 (preconditions, fingerprint, char sweep, numeric scan, ambiguous reclassification, case variants) producing three qc/ evidence files.

---

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Add PCNR_APPROVED flag and %hexkey macro to 00_config.sas | 943dd88 | sas/00_config.sas |
| 2 | SECTIONS 0-2 — preconditions, fingerprint, character sentinel sweep | 8354daf | sas/23_pcnr_inventory.sas |
| 3 | SECTIONS 3-5 — numeric scan, ambiguous classification, case variants | 8354daf | sas/23_pcnr_inventory.sas |

---

## What Was Built

### sas/00_config.sas (modified)

- Added `%let PCNR_APPROVED = 0;` with NOTE echo, immediately after `D15_APPROVED` line
- Added `%macro hexkey(var);substr(put(&var, $hex400.), 1, 2*length(&var))%mend hexkey;` at end of file
- No `/` after parameter list, no `;` inside body — macro expands to a bare expression
- `$hex400.` covers values up to 200 bytes; `substr(..., 1, 2*length(&var))` strips trailing-blank hex padding

### sas/23_pcnr_inventory.sas (created)

**SECTION 0 — Preconditions** (in `%check_preconditions` macro — no open-code `%if`):
- Asserts `g.master_data_harmonized` exists in library G
- Asserts row count = 41,150 via SASHELP.VTABLE
- Asserts `docs/concept_decisions.csv` is readable via `%sysfunc(fileexist(...))`
- Asserts max char column length <= 200 from `dictionary.columns` (boundary for `$hex400.`)

**SECTION 1 — Fingerprint:**
- Reads nobs, nvar, modate from SASHELP.VTABLE
- Writes one line to `qc/23_sentinel_fingerprint.txt`: `nobs=N nvars=N modate=DATETIME`

**SECTION 2 — Character sweep:**
- POST-h_-STRIP RULE: resolves demog_cols and score_cols by checking for h_ survivors in dictionary.columns; emits NOTE for any member absent from dataset in either form
- Gets all char columns from `dictionary.columns` (sweep, not sample)
- Single-pass DATA step with `array _c(*) _character_`; emits one row per non-missing cell
- Computes `raw_hex = %hexkey(raw_value)` and `raw_len = length(raw_value)`
- Detects non-ASCII bytes (byte < 32 or > 126) via loop; sets `non_ascii_flag = 1`
- Normalizes: `compbl(strip(upcase(value)))`; control-char tokens for `09`x/`0D`x/`0A`x/`A0`x
- Classifies AUTO (exact match on 17-value list including `<TAB>`, `<CRLF>`, `<NBSP>`) and REVIEW (contains sentinel fragment, excluding `&freetext_cols`)
- Assigns `column_group` from resolved demog_cols and score_cols lists

**SECTION 3 — Numeric scan:**
- Gets numeric column list from `dictionary.columns`
- Single-pass DATA step with `array _n(*) _numeric_`; emits rows where `not missing(_n(_i))` and value is in sentinel list (-999, -99, -9, 99, 999, 777, 888, 9999, 99999)
- `raw_hex = %hexkey(strip(put(value, best32.)))` — hex of text representation
- All numeric sentinel rows: `candidate_class = 'REVIEW'`, `match_rule = 'NUMERIC_SENTINEL'`

**SECTION 4 — Ambiguous reclassification:**
- Reclassifies char rows to AMBIGUOUS for base list (None, Not applicable, Declined, etc.)
- Reclassifies UNKNOWN in demog_cols to AMBIGUOUS (overrides AUTO)
- Scans numeric score_cols for value = 0 (NOT MISSING guard); adds rows with `candidate_class = 'AMBIGUOUS'`, `match_rule = 'AMBIGUOUS_SCORE_ZERO'`
- Asserts uniqueness on (variable, raw_hex) via PROC SQL with `%fail_out` on violation
- Sorts AMBIGUOUS / REVIEW / AUTO (numeric sort key 1/2/3), then by variable and raw_value
- Writes `qc/23_sentinel_candidates.csv` with exact column order from interfaces spec

**SECTION 5 — Case variants:**
- Groups distinct char values by normalized form (upcase + compbl + strip)
- Identifies normalized forms with 2+ distinct raw spellings per variable
- Writes `qc/23_case_variants.csv` (report only, no recoding)

---

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### Notes

- Tasks 2 and 3 were committed together since the file was new; both sections were written in a single pass. Commit 8354daf covers SECTIONS 0-5.
- The `$hex.` occurrences in grep checks appear only in comment lines in both files; no executable code uses bare `$hex.`.

---

## Known Stubs

- `role` column in `qc/23_sentinel_candidates.csv` is blank for all rows. Plan 02 SECTION 6 backfills role from the pcnr_name_map DROP logic. This is intentional per plan spec — not a defect.

---

## Self-Check: PASSED

- sas/00_config.sas: FOUND
- sas/23_pcnr_inventory.sas: FOUND
- Commit 943dd88: `feat(23-01): add PCNR_APPROVED gate flag and %hexkey macro`
- Commit 8354daf: `feat(23-01): write 23_pcnr_inventory.sas SECTIONS 0-5`
