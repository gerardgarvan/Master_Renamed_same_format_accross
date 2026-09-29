---
gsd_state_version: 1.0
milestone: v2.1
milestone_name: pcnr_ Clean Analysis Dataset
status: unknown
last_updated: "2026-09-29T01:29:43.560Z"
last_activity: 2026-09-29
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 9
  completed_plans: 9
  percent: 89
---

# STATE.md — PeCAN Master Dataset Integration

**Project:** PCM | **Last Updated:** 2026-09-24 | **Milestone:** v2.1 STARTED

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-24 after v2.1 milestone defined)

**Core value:** A single `run_pipeline.cmd` that runs start-to-finish as separate sas.exe sessions per PCM-C-05, producing `g.master_data_merged` (41,150 rows), passing QC reports, a data dictionary, and a resolved DECISIONS.md -- with no manual steps.

**Current focus:** Phase 24 — build-g-pcnr-harmonized

---

## Current Position

Phase: 25
Plan: Not started
Last activity: 2026-09-29

### v2.1 Phase Status

| Phase | Name | Status |
|-------|------|--------|
| 22 | Pipeline Green & Hardening | Complete (2026-09-28) |
| 23 | Sentinel & Name Inventory | Not started |
| 24 | Build g.pcnr_harmonized | Not started |
| 25 | pcnr Cohort, Dictionary & Wiring | Not started |

**Progress:** [█████████░] 89%

### v2.0 Phase Status (shipped 2026-09-24)

| Phase | Name | Status |
|-------|------|--------|
| 19 | Raw Directory Inventory | Complete (2026-09-23) |
| 20 | pecan_ID Derivation | Complete (2026-09-23) |
| 21 | Runner Wiring & D3 Fix | Complete (2026-09-24) |

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
| pecan_ID distinct count (harmonized) | — | **33,031** | PID-02, 20_pecan_id.log 2026-09-24 |
| pecan_ID distinct count (cohort) | — | see 16b_pecan_id_counts.txt | PID-06, 16b_pecan_id_counts.txt, Phase 22 run 2026-09-28 (pipeline PASSED; count in P: qc file, not committed) |
| r7/r8/r9 MRN linkage reach | — | see report | qc/20_linkage_reach.txt |
| pcnr recoded cells | reported | — | Phase 24 (PCNR-10) |
| g.pcnr_harmonized | 41,150 rows | — | Phase 24 |
| g.pcnr_analytic_cohort | 13,890 rows | — | Phase 25 |

---
| Phase 23 P01 | 5 | 3 tasks | 2 files |
| Phase 23 P02 | 10 | 2 tasks | 1 files |
| Phase 23-sentinel-name-inventory P03 | 10 | 1 tasks | 1 files |
| Phase 24 P02 | 125 | 2 tasks | 1 files |
| Phase 24 P03 | 8 | 2 tasks | 1 files |

## Accumulated Context

### Roadmap Evolution

**v2.1 (2026-09-24):**

- Phase 22 added: Pipeline Green & Hardening (FIX-02, RUN-02, RUN-03, INV-07, DOC-05) -- first, because the 2026-09-24 run stopped at 16b
- Phase 23 added: Sentinel & Name Inventory (PCNR-01..06); human checkpoint, PCNR_APPROVED gate
- Phase 24 added: Build g.pcnr_harmonized (PCNR-07..11)
- Phase 25 added: pcnr Cohort, Dictionary & Wiring (PCNR-12..17)
- PCM-D-15 gap-fill and r7/r8/r9 linkage moved to v2.2 candidates

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

- RUN-01 SATISFIED 2026-09-24: run_pipeline.cmd wires all 14 programs (01-08, 19, 20, 10b, 16b, 17, 18) as separate sas.exe sessions per PCM-C-05; full end-to-end run PASSED; stop-path verified; in_pipeline=1 confirmed via envlen(RUN_ALL) in 00_config.sas
- PCM-D-19 APPROVED 2026-09-23: DOMAIN_MAP_APPROVED=1 in program 17; D3 DATALINES rows confirmed; supersedes v1 Checkpoint 1 hold
- PCM-D-20 APPROVED 2026-09-23: program 17 redirected from g.analysis_base (no pipeline producer) to g.analytic_cohort (produced by 16b); keyed comparison writes qc/17_pcm_d20_compare.txt; pecan_ID excluded via existing regex mechanism (a)
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

### Open Decisions (v2.1)

PCM-D-17 and PCM-D-18 resolved 2026-09-23 (see PROJECT.md Key Decisions).

- **PCM-D-21** -- which candidate values become missing, per variable (sentinel_decisions.csv). Before Phase 24.
- **PCM-D-22** -- prefix scope (all non-key columns vs recoded-only) and which key columns stay unprefixed. Before Phase 23 name map.
- **PCM-D-23** -- shortening rule for names over 27 characters. Before Phase 23 name map.
- **PCM-D-24** -- whether any numeric sentinels are recoded. Before Phase 24.
- **PCM-D-25** -- whether reason codes (Declined/Refused/Not applicable) are preserved. RESOLVED 2026-09-28: no companion columns in v2.1; values become MISSING per sentinel_decisions.csv. (Gerard)
- **PCM-D-27** -- ambiguous-value column scope (demographic + score/count lists). RESOLVED 2026-09-28: lists hardcoded in sas/23_pcnr_inventory.sas header; confirmed at Phase 23 checkpoint. (Gerard)
- **PCM-D-26** -- program 17 input: g.pcnr_analytic_cohort vs g.analytic_cohort. Before Phase 25.

### Pending Todos

- Inform Price of PCM-D-05 resolution (decided by Gerard 2026-09-21; update attribution on Price's response)
- Report to PeCAN data group: source system emits impossible operative timestamp combinations (9 rows) and negative intervals concentrated in percutaneous services
- Decide whether `.planning/PROJECT.md` should restore the full PCM-T-01..T-11 trap list
- Commit the 2026-09-24 fixes to 16b_cohort_rebuild.sas and 20_pecan_id.sas (FIX-02)
- Copy `ownership_map.sas7bdat` to P: qc path if running Phase 5 on a machine that did not run Phase 2

### Blockers

- Phase 21 is blocked on completion of Phase 20 (programs 19 and 20 must exist before runner wiring) -- RESOLVED: Phase 20 complete 2026-09-23

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
*Last updated: 2026-09-28 — Phase 22 pipeline green; full run_pipeline.cmd PASSED; scanner operational (pre-existing xlsx-read findings noted as known); Phase 22 complete*
