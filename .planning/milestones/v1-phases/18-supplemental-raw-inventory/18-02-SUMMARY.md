---
phase: 18-supplemental-raw-inventory
plan: "02"
subsystem: gap-diagnostic
tags: [gap-fill, raw-inventory, PCM-D-15, r2-families, sentinel]
dependency_graph:
  requires: ["18-01"]
  provides: ["qc/18_gap_candidates.txt", "PCM-D-15 gate in programs 17 and 18"]
  affects: ["sas/17_summary_stats_by_domain.sas", "sas/18_supplemental_raw_gap.sas"]
tech_stack:
  added: []
  patterns:
    - "call execute per-column merge with keep=/rename= on both sides (type-safe, never wide)"
    - "single PROC MEANS + array pass for NEW column counts (no per-column loop)"
    - "-999 numeric and NULL char sentinel handling via raw_miss expression"
    - "COMP10 exclusion before COM prefix in r2 family assignment"
    - "DATA _NULL_ report writer with mod lrecl=250 appends"
key_files:
  created: []
  modified:
    - sas/18_supplemental_raw_gap.sas
    - sas/17_summary_stats_by_domain.sas
decisions:
  - "D15_APPROVED lives only in 00_config.sas -- no local %let in programs 17 or 18"
  - "r2 section dividers identified by name; populated dividers flagged REVIEW rather than silently excluded"
  - "r2 families assigned by prefix rule with COMP10/complication_sum exclusion first"
metrics:
  duration_minutes: 45
  completed_date: "2026-09-16"
  tasks_completed: 3
  tasks_total: 3
  files_modified: 2
---

# Phase 18 Plan 02: Gap-Fill Candidate Table and PCM-D-15 Gate Summary

**One-liner:** Per-column gap-fill counts for r1/r2/r3/r4/r5/r6/r9 with r2 family rollups, divider exclusion, and D15 gate wired into programs 17 and 18.

---

## What Was Built

### Task 1: Section B -- %gap_file for r1, r3, r4, r5, r6, r9

Added to `sas/18_supplemental_raw_gap.sas`:

- **B-0** one-time setup: `work.base_k` (g.analysis_base with `_k = strip(cats(PRECEDE_STUDY_ID))` sorted by `_k`), `work.base_cols` (from `dictionary.columns` filtered to `type='char'` or `type='num'`), empty `work.gap_results` with the full column schema.

- **%gap_file macro**: parameterised by `rid=`, `fname=`, `ds=`, `key=`. The macro:
  1. Skips import if dataset already exists (guards `work.r9` from Section A).
  2. Builds `work.raw_k` with `_k = strip(cats(&key))`, drops the key column, sorts `nodupkey` (asserts with `%put NOTE`, no abort).
  3. Queries `dictionary.columns` for the raw dataset into `work.raw_cols_&rid`, left-joining to `work.base_cols` on `upcase(name) = uname` to assign `bucket = IN_BASE / NEW` and carry `base_type`.
  4. `n_matched` via `SELECT COUNT(*) INTO :mac TRIMMED` inner join on `_k`.
  5. **IN_BASE loop**: `call execute` over `work.raw_cols_&rid (where=(bucket='IN_BASE'))` generating one `data work.gap_one` merge per column with `keep=_k &col rename=(&col=base_val)` on the base side and `keep=_k &col rename=(&col=raw_val)` on the raw side (never a wide merge), applying the sentinel-aware `raw_miss` expression, then `SELECT SUM(fillable), SUM(equal), SUM(conflict)` and INSERT into `work.gap_results`.
  6. **NEW columns**: one `proc means ... n` after `-999 -> .` recode for numeric columns; one array pass for char columns. No per-column loop.

- `%gap_file` called for: r1, r3, r4, r5, r6, r9. Not called for r7 or r8.

### Task 2: r2 gap counts with family rollups and divider exclusion

- `%gap_file(rid=r2, fname=2018_2019_Precede_Database.xlsx, ds=work.r2_s1, key=studyid)` produces 101 IN_BASE rows and 3,885 NEW rows in `work.gap_results`.

- **Divider separation**: `work.r2_dividers` holds columns on the eight-name divider list. Columns with `n_raw_populated = 0` get note `section divider -- excluded`; populated ones get `on divider list but populated -- REVIEW`.

- **Family assignment**: prefix rules applied in order -- COMP10_/complication_sum excluded first (individual row), then COM -> COM_dCDT, COPY -> COPY_dCDT, LINUS_ -> LINUS, paper_neuropsych prefixes (hvlt, mmse, wais_iii, ...) -> paper_neuropsych. Everything else stays as an individual row.

- **Family rollup**: `proc means ... n median min max` over `work.r2_family_input` (family ne '') produces `work.r2_family_rollup` with four rows.

- **`work.gap_report`**: gap_results minus r2 NEW rows, plus r2 individual NEW rows (family='' and not a divider). This is the source for the sorted detail sections.

- **`qc\18_gap_candidates.txt`** written by `%write_gap_candidates` macro via `DATA _NULL_`:
  - Header: run date, missing-value rule, r7/r8 excluded note.
  - Per-file summary: rid, n_matched, n_IN_BASE, n_NEW, n_rolled_up.
  - IN_BASE detail: sorted by `pct_fillable DESC` then `n_fillable DESC`; TYPE_DIFF flagged where `raw_type ne base_type`.
  - NEW detail: sorted by `pct_raw_populated DESC` then `n_raw_populated DESC`.
  - r2 family rollup: four rows (family, n_cols, median, min, max).
  - Appendix: `work.r2_dividers` (column, n_raw_populated, note).

### Task 3: PCM-D-15 gate in programs 18 and 17

**Program 18** (`sas/18_supplemental_raw_gap.sas`):
- `%macro gate_d15` defined at Section C; body calls `%fail_out` when `&D15_APPROVED ne 1`.
- `%gate_d15;` placed after `qc\18_gap_candidates.txt` write and before the final `%restore_log;`.
- No `%let D15_APPROVED` in this program -- the flag is read from `00_config.sas`.

**Program 17** (`sas/17_summary_stats_by_domain.sas`):
- Identical `%macro gate_d15` definition added to the macro library section.
- `%gate_d15;` placed immediately before `data work.analysis_base_ext;` (the step that consumes PCM-D-15 approved columns).
- No `%let D15_APPROVED` in this program.

With `D15_APPROVED=0` in `00_config.sas`: program 18 writes both QC files then aborts at the gate; program 17 aborts before building `analysis_base_ext`. Setting the flag to 1 lets both complete.

---

## Deviations from Plan

None - plan executed exactly as written.

---

## Known Stubs

None. The report writer generates all sections. At SAS runtime `qc\18_gap_candidates.txt` will contain real counts; the program code itself is complete.

---

## Self-Check: PASSED

- `sas/18_supplemental_raw_gap.sas` exists and contains Section B + Section C.
- `sas/17_summary_stats_by_domain.sas` exists and contains `%gate_d15` definition and call.
- `grep -c "%abort cancel"` returns 1 for program 18 (executable); program 17 has 1 executable occurrence inside `%fail_out` (3 additional in comment header).
- Neither program contains `%let D15_APPROVED`.
- `%gate_d15;` in program 17 is before `data work.analysis_base_ext;`.
- Commits: `15fa7d4` (Section B six-file gap counts), `9de210a` (gate_d15 in program 17).
