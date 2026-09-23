---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: pecan_ID + Raw Directory Inventory
status: roadmap_ready
last_updated: "2026-09-23T00:00:00Z"
last_activity: 2026-09-23
progress:
  total_phases: 3
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# STATE.md — PeCAN Master Dataset Integration

**Project:** PCM | **Last Updated:** 2026-09-23 | **Milestone:** v2.0 IN PROGRESS

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-23 after v2.0 roadmap created)

**Core value:** A single `99_run_all.sas` that runs start-to-finish in a clean SAS session against read-only sources, producing `g.master_data_merged` (41,150 rows), passing QC reports, a data dictionary, and a resolved DECISIONS.md -- with no manual steps.

**Current focus:** Phase 19 — Raw Directory Inventory. Run `/gsd:plan-phase 19` to begin.

---

## Current Position

Phase: Not started (roadmap defined; ready to plan Phase 19)
Plan: —
Status: Roadmap ready
Last activity: 2026-09-23 — v2.0 roadmap created (3 phases, 17 requirements)

### v2.0 Phase Status

| Phase | Name | Status |
|-------|------|--------|
| 19 | Raw Directory Inventory | Not started |
| 20 | pecan_ID Derivation | Not started |
| 21 | Runner Wiring & D3 Fix | Not started |

**Progress:** [░░░░░░░░░░] 0%

### v1.0 Position (preserved)

All 13 v1 phases complete. See .planning/milestones/v1-ROADMAP.md.

| Phase | Name | Status |
|---|---|---|
| 1 | Source Verification & Freeze | Complete (2026-08-26) |
| 2 | Ownership Map | Complete (2026-08-26) |
| 3 | Per-Source Normalization | Complete (2026-09-14) |
| 4 | Merge | Complete (2026-08-27) |
| 5 | Merge QC | Complete (2026-09-14) |
| 6 | Variable Reconciliation | Complete (2026-09-14) |
| 7 | Cohort & Missingness | Complete (2026-09-22) |
| 8 | Documentation & Handoff | Complete (2026-09-22) |
| 14 | Label-Similarity Sweep | Complete (2026-09-21) |
| 15 | Extend the Harmonized Dataset | Complete (2026-09-21) |
| 16 | Rebuild the Analytic Cohort | Complete (2026-09-22) |
| 17 | Summary Stats by Domain | Complete (2026-09-22) |
| 18 | Supplemental Raw Inventory | Complete (2026-09-22) |

---

## Performance Metrics

| Metric | Target | Actual | Source |
|--------|--------|--------|--------|
| Source row count (md3 spine) | 41,150 | **41,150** | qc/src_counts.txt |
| Merged row count | 41,150 | **41,150** | QC-01, 2026-08-26 |
| Distinct merged IDs | 41,150 | **41,150** | Phase 4 assertions |
| Blank PRECEDE_STUDY_ID | 0 | **0** | MRG-02 |
| Surviving NULL strings | 0 | **0** | QC-03, all char vars |
| Char vars missing from width ref | 0 | **0** | QC-02 |
| Truncated char vars | 0 | **0** | QC-02 |
| md8-owned variables (derived) | ~20 | **20** | QC-04 |
| QC-04 scoping violations | 0 | **0** | 20 of 20 passed |
| QC-05 range assertions | 5 | 8 → **5** | three inert ceilings dropped (QC-07, PCM-D-09) |
| Negative operative intervals | 0 | **67** → nulled by PREP-08 | 52 rt1 + 15 rt2, disjoint |
| QC-06 unflagged violations | 0 | **0** (after MRG-05) | assertion passes |
| rt_envelope_flag = 1 | reported | **9** | 5 rt1 + 4 rt2 -- flagged, not nulled (PCM-D-08) |
| MRG-06 gap-fill variables | 5 | **5** | md8 donor, 0 disagreements (PCM-F-18) |
| Complete-case N (BMI), merged | — | **12,726** | unchanged by MRG-06 |
| Complete-case N (Cognitive), merged | — | 12,128 → **20,540** | +8,412 from md8 (MRG-06) |
| Complete-case N (Frailty), merged | — | 14,043 → **23,311** | +9,268 from md8 (MRG-06) |
| Complete-case N (all three), merged | — | **6,523** | 47.0% of 13,890 cohort |
| Admitted cohort N | — | **13,890** | INPATIENT 13,223 + OBSERVATION 667 |
| Within-cohort BMI | — | **12,726** (91.6%) | ALL BMI values inside admitted cohort |
| Within-cohort Cognitive | — | **7,252** (52.2%) | verified 2026-09-22 |
| Within-cohort Frailty | — | **8,150** (58.7%) | verified 2026-09-22 |
| g.analytic_cohort (harmonized) | — | **13,890 rows, 174 cols** | rebuilt 2026-09-22 from g.master_data_harmonized |
| pecan_ID distinct count (merged) | TBD | — | Phase 20 |
| pecan_ID distinct count (cohort) | TBD | — | Phase 20 |
| r7/r8/r9 MRN linkage reach | TBD | — | Phase 20 (PID-07) |

---

## Accumulated Context

### Roadmap Evolution

**v2.0 (2026-09-23):**
- Phase 19 added: Raw Directory Inventory (INV-01 through INV-07)
- Phase 20 added: pecan_ID Derivation (PID-01 through PID-08); depends on Phase 19 (INV-01 checksum, INV-04 key-column flags)
- Phase 21 added: Runner Wiring & D3 Fix (RUN-01, FIX-01); must follow Phases 19 and 20 to include programs 19 and 20 in 99_run_all.sas

**v1.0 (archived):**
- Phase 5 added: Merge QC (QC-01 through QC-05)
- AMENDMENT-01 raised 2026-08-26: adds PREP-08, PREP-09 (Phase 3) and QC-06 (Phase 5)
- Phase 17 added: summary-stats-by-domain
- Phase 18 added: Supplemental Raw Inventory

### Established Decisions

- md3 is the merge spine (complete superset, PCM-F-02); operation is 1:1 merge, not stack-dedup
- No PROC SQL UPDATE anywhere (silent truncation trap, PCM-T-01)
- No `data X; set X;` patterns (destroys dataset, PCM-T-02)
- Single ownership per variable (prevents last-wins overwrite, PCM-T-05)
- md8 stores literal `NULL` where others store blank; md8 numerics were forced to CHAR $4/$11 in prior work
- Coalescing BMI from other sources recovers nothing; 28,424 missing are missing at source
- `PRECEDE_Study_ID_1` in md6 is a duplicate column identical to `PRECEDE_STUDY_ID` -- proven, then dropped
- Encoding damage confined to `Base_Procedure_1`, <=9 rows per file -- flag only, do not re-encode
- SRC-05 runs before SRC-01: blank key is "unique" when it occurs once and must be caught first
- `&SQLOBS` not used anywhere; all counts use explicit `SELECT COUNT(*) INTO :macvar TRIMMED`
- KEEP= lists generated from `qclib.ownership_map` at run time, never hand-transcribed
- Ownership resolution is a RULE (md3 if present, else highest-row-count source, ties to lowest number), with md7 override for five frailty components
- QC-05 bounds calibrated to OBSERVED data: Admit_BMI 10-100, Cognitive_Score 0-3
- Age_at_Encounter floor of 18 is a type-sanity guard only; do NOT tighten to 64 (PCM-D-07 deferred)
- g library lives OUTSIDE the git working tree -- `git clean -xdf` deletes ignored files
- Impossible VALUES are nulled at source (PREP-08); impossible COMBINATIONS are flagged, not nulled (MRG-05)
- PCM-D-05 RESOLVED 2026-09-21: analytic cohort restricted to INPATIENT+OBSERVATION (N=13,890); BMI forces restriction
- PCM-D-15 APPROVED 2026-09-22: per-column gap candidates for r1-r9 extension columns; wiring deferred to v2.1 pending PID-07 result
- PCM-D-16 DIAGNOSED: r7/r8/r9 2022 IDs match 0 base rows -- schema-change-era format change; documented, not fixed
- PCM-T-12 (method): sweep ALL candidates, do not spot check -- Cognitive_Category and Frailty_Category were found only by full sweep

### Open Decisions (v2.0 blockers)

- **PCM-D-17** -- pecan_ID derivation method + MRN retention: surrogate integer vs hash; whether raw ENCRYPTED_MRN is retained alongside pecan_ID. Must be resolved before Phase 20 plan executes.
- **PCM-D-18** -- pecan_ID attach point: which datasets receive pecan_ID (merged only, or also harmonized and analytic cohort). Must be resolved before Phase 20 plan executes.

### Pending Todos

- Inform Price of PCM-D-05 resolution (decided by Gerard 2026-09-21; update attribution on Price's response)
- Report to PeCAN data group: source system emits impossible operative timestamp combinations (9 rows) and negative intervals concentrated in percutaneous services
- Decide whether `.planning/PROJECT.md` should restore the full PCM-T-01..T-11 trap list
- Copy `ownership_map.sas7bdat` to P: qc path if running Phase 5 on a machine that did not run Phase 2

### Blockers

- PCM-D-17 and PCM-D-18 must be resolved before Phase 20 plans can execute (they are referenced in PID-04 and PID-05 assertions)
- Phase 21 is blocked on completion of Phases 19 and 20 (programs 19 and 20 must exist before runner wiring)

---

## Session Continuity

To resume: read this file, then `.planning/ROADMAP.md`, then `.planning/REQUIREMENTS.md`.

**Key file locations:**

- Source data: `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\` (read-only)
- g library: P: merge tree -- **outside the git working tree** (PCM-C-04)
- SAS programs: `sas/` (version-controlled, local disk)
- QC outputs: `qc/` on the P: merge tree
- Logs: `logs/` on the P: merge tree
- Docs: `docs/`
- Planning: `.planning/`

**Do NOT** put the git repo on the P: drive (slow + index corruption risk).
**Do NOT** commit `*.sas7bdat`, `*.xlsx`, `*.csv`, or anything under `data/` (PHI).
**Do** restart the SAS session between programs -- `%abort cancel` leaves an interactive session that swallows the next submit without executing it.

---
*Last updated: 2026-09-23 — v2.0 roadmap created; 3 phases (19-21), 17 requirements mapped; ready for `/gsd:plan-phase 19`*
