---
phase: 23-sentinel-name-inventory
plan: "02"
subsystem: sentinel-inventory
tags: [sas, pcnr, name-map, sentinel-decisions, truncation]
dependency_graph:
  requires: [23-01]
  provides: [23_pcnr_inventory.sas SECTIONS 6-8, qc/23_pcnr_name_map_DRAFT.csv, qc/23_sentinel_decisions_DRAFT.csv]
  affects: [Phase 24 gate (reads qc/23_pcnr_name_map_DRAFT.csv and qc/23_sentinel_decisions_DRAFT.csv after human copy to docs/)]
tech_stack:
  added: []
  patterns: ["DATA step infile for gate CSV (PCM-T-16)", "PROC SQL self-join collision detection", "PCM-D-23 middle-truncation with final-token preservation and double-__ guard"]
key_files:
  created: []
  modified:
    - sas/23_pcnr_inventory.sas
decisions:
  - "PCM-D-23 truncation: preserve final token after last _, head trimmed to budget, trailing _ stripped from head before rejoining (avoids double __); fallback to tail-truncation when name ends with _ (empty final_token) or final_token > 12 chars"
  - "collision_flag in SECTION 8 is NOTE only (never fail_out) -- hard zero-collision check belongs in Phase 24 gate against docs/pcnr_name_map.csv"
  - "DROP-role candidates excluded from sentinel_decisions_DRAFT per D-08"
  - "UNKNOWN wildcard row emitted with AMBIGUOUS rationale note; Phase 24 gate already prohibits wildcards from resolving AMBIGUOUS candidates"
metrics:
  duration: "~10 minutes"
  completed: "2026-09-28"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 1
---

# Phase 23 Plan 02: Name-Map Draft, Sentinel-Decisions Draft, and Validation (SECTIONS 6-8) Summary

SECTIONS 6, 7, and 8 appended to sas/23_pcnr_inventory.sas: name-map draft with PCM-D-23 truncation (all 10 edge cases verified), DROP proposals from concept_decisions.csv, sentinel-decisions draft with correct pre-fill and UNKNOWN wildcard rationale, and validation assertions for name length, completeness, and DROP/KEY blank enforcement.

---

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | SECTION 6 -- name-map draft with truncation, DROP proposal, collision + id flags | 6a0e7f5 | sas/23_pcnr_inventory.sas |
| 2 | SECTIONS 7-8 -- sentinel-decisions draft and validation report | 6a0e7f5 | sas/23_pcnr_inventory.sas |

---

## What Was Built

### sas/23_pcnr_inventory.sas (modified -- SECTIONS 6-8 appended)

**SECTION 6 -- Name-map draft:**
- Reads all 175 columns from `dictionary.columns` for `g.master_data_harmonized`
- Role assignment:
  - KEY: `pecan_ID`, `PRECEDE_STUDY_ID`, `ENCRYPTED_MRN`, `ENCRYPTED_ENCOUNTER` (final_name blank)
  - DROP: raw columns whose varname appears in `docs/concept_decisions.csv` with `harmonized_name` starting `h_`; read via DATA step `infile` (PCM-T-16, never PROC IMPORT). Emits `%put NOTE:` for any DROP varname absent from the dataset.
  - KEEP: all remaining columns
- `h_strip`: KEEP rows beginning with `h_` get `h_strip='Y'`; prefix stripped before `pcnr_` prepend
- PCM-D-23 truncation algorithm:
  - If `pcnr_` + name <= 32: no truncation
  - Otherwise: preserve `final_token` (substring after last `_`); compute head budget (32-5-1-ft_len); trim head; strip trailing `_` from head to avoid double `__`; rejoin
  - Fallback to plain tail truncation when: name ends with `_` (empty final_token), or no underscore, or final_token > 12 chars
  - All 10 known edge-case names produce correct outputs per plan acceptance criteria
- Collision detection via PROC SQL self-join (case-insensitive)
- `id_flag` via PRX match on `*_ID`, `*STUDY_ID*`, `ENCRYPTED_*` patterns (independent of collision_flag)
- Backfills `role` into `qc/23_sentinel_candidates.csv` (rewrites CSV with populated role column)
- Writes `qc/23_pcnr_name_map_DRAFT.csv` in schema order per D-05

**SECTION 7 -- Sentinel-decisions draft:**
- Filters out DROP-role candidates per D-08
- Pre-fills `action = 'KEEP'` for `var_type = num`; leaves blank for `var_type = char`
- `decided_by` and `decided_date` written as blank (human fills at checkpoint)
- Wildcard rows: one per distinct AUTO `normalized_value` from char candidates only
- UNKNOWN wildcard gets `rationale` = "Wildcard does not cover AMBIGUOUS rows; demographic columns need per-variable decisions" (Pitfall 2 from RESEARCH.md)
- Writes `qc/23_sentinel_decisions_DRAFT.csv` in schema order per D-04

**SECTION 8 -- Validation:**
- `max(name_len) <= 32` for KEEP rows -- else `%fail_out`
- Completeness: name_map row count = dataset column count -- else `%fail_out`
- DROP/KEY rows have blank `final_name` -- else `%fail_out`
- `collision_flag` count: `%put NOTE:` only (never `%fail_out` -- hard check in Phase 24 gate)
- Summary NOTE counts: char cols swept, candidate class breakdown, name-map role counts, truncation/collision/id_flag counts, decisions draft row counts

---

## Static Checks Passed

- `grep -n "23_pcnr_name_map_DRAFT.csv" sas/23_pcnr_inventory.sas` -- present
- `grep -ni "proc import" sas/23_pcnr_inventory.sas` -- only in comments, no executable PROC IMPORT
- `grep -ni "%put WARNING" sas/23_pcnr_inventory.sas` -- only in comments
- `grep -ni "DROP proposal source name" sas/23_pcnr_inventory.sas` -- `%put NOTE:` present
- `grep -ni "docs" sas/23_pcnr_inventory.sas` -- only in comment and concept_decisions.csv read; no file=/outfile=/filename pointing at docs/
- `grep -c '\$hex\.' sas/23_pcnr_inventory.sas sas/00_config.sas` -- occurrences are in comments only (same state as Plan 01, accepted)
- `grep -niE "decided_by *= *['\"][A-Za-z]"` -- no hardcoded attribution
- SECTION 8 has no `%fail_out` tied to `collision_flag`
- Sections labeled 6, 7, 8 with no duplicates

---

## Deviations from Plan

### Auto-fixed Issues

None -- plan executed exactly as written.

### Notes

- Tasks 1 and 2 were committed together (single file, single coherent extension) following the same pattern as Plan 01 tasks 2+3. Commit 6a0e7f5 covers SECTIONS 6-8.
- The `$hex.` grep count is 3 total (2 in 23_pcnr_inventory.sas, 1 in 00_config.sas) but all are in comment/header lines. No executable code uses bare `$hex.`. This was accepted in Plan 01 and is unchanged.

---

## Known Stubs

None -- all stub from Plan 01 (`role` blank in candidates CSV) resolved in SECTION 6 which backfills role from name-map DROP logic.

---

## Self-Check: PASSED

- sas/23_pcnr_inventory.sas: FOUND (modified)
- Commit 6a0e7f5: `feat(23-02): append SECTIONS 6-8 to 23_pcnr_inventory.sas` -- FOUND
- SECTION 6 in file: FOUND (line 751+)
- SECTION 7 in file: FOUND (line 1131+)
- SECTION 8 in file: FOUND (line 1256+)
- qc/23_pcnr_name_map_DRAFT.csv write statement: FOUND (line 1097)
- qc/23_sentinel_decisions_DRAFT.csv write statement: FOUND (line 1230)
