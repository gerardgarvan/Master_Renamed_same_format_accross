---
gsd_state_version: 1.0
milestone: v2.2
milestone_name: pcnr Normalization, Gap-Fill & Linkage
status: verifying
last_updated: "2026-10-07T16:25:41.472Z"
last_activity: 2026-10-07
progress:
  total_phases: 2
  completed_phases: 2
  total_plans: 6
  completed_plans: 6
  percent: 100
---

# STATE.md — PeCAN Master Dataset Integration

**Project:** PCM | **Last Updated:** 2026-09-29 | **Milestone:** v2.2 in progress

---

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-29 after v2.1 milestone shipped)

**Core value:** A single `run_pipeline.cmd` that runs all SAS programs start-to-finish as separate sas.exe sessions per PCM-C-05, producing `g.master_data_merged` (41,150 rows), `g.pcnr_harmonized` (41,150 rows), `g.pcnr_analytic_cohort` (13,890 rows), passing QC reports, a data dictionary, and a resolved DECISIONS.md — with no manual steps.

**Current focus:** Phase 27 — md8-row-count-correction

---

## Current Position

Phase: 27
Plan: Not started
Status: Phase complete — ready for verification
Last activity: 2026-10-07

### v2.2 Phase Status

| Phase | Name | Status |
|-------|------|--------|
| 26 | v2.1 Carry-Forward & Source Hardening | Not started |
| 27 | md8 Row-Count Correction | Not started |
| 28 | r7/r8/r9 Linkage Investigation | Not started |
| 29 | Gap-Fill Wiring (r1-r6) | Not started |
| 30 | pcnr Normalization & Type Conversion | Not started |

**Progress:** [██████████] 100%

### v2.1 Phase Status (shipped 2026-09-29)

| Phase | Name | Status |
|-------|------|--------|
| 22 | Pipeline Green & Hardening | Complete (2026-09-28) |
| 23 | Sentinel & Name Inventory | Complete (2026-09-28) |
| 24 | Build g.pcnr_harmonized | Complete (2026-09-28) |
| 25 | pcnr Cohort, Dictionary & Wiring | Complete (2026-09-29) |

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
| pecan_ID distinct count (cohort) | — | see 16b_pecan_id_counts.txt | PID-06, 16b_pecan_id_counts.txt, Phase 22 run 2026-09-28 |
| r7/r8/r9 MRN linkage reach | — | see report | qc/20_linkage_reach.txt |
| pcnr recoded cells | reported | — | Phase 24 (PCNR-10) |
| g.pcnr_harmonized | 41,150 rows | **41,150** | Phase 24; all sentinel values set to missing; all analysis variables renamed pcnr_* |
| g.pcnr_analytic_cohort | 13,890 rows | **13,890** | Phase 25; PRECEDE_STUDY_ID set identical to g.analytic_cohort |
| md8 non-missing rows | 22,473 | **22,473** | Phase 27 (MD8-01); dual count + contiguity, PCM-D-31 |

---
| Phase 26 P02 | 20 | 2 tasks | 2 files |
| Phase 26 P04 | 10 | 1 tasks | 1 files |
| Phase 27 P01 | 25 | 1 tasks | 1 files |
| Phase 27 P02 | 15 | 2 tasks | 4 files |

## Accumulated Context

### Roadmap Evolution

**v2.2 (2026-09-29):**

- Phase 26 added: v2.1 Carry-Forward & Source Hardening (FIX-03, FIX-04, HARD-01, HARD-02, HARD-03) — FIX-03 done first because GAP-02 later edits program 23
- Phase 27 added: md8 Row-Count Correction (MD8-01, MD8-02)
- Phase 28 added: r7/r8/r9 Linkage Investigation (LINK-01, LINK-02, LINK-03) — produces PCM-D-28; must precede gap-fill to confirm r7-r9 exclusion scope
- Phase 29 added: Gap-Fill Wiring r1-r6 (GAP-01, GAP-02, GAP-03) — depends on PCM-D-28
- Phase 30 added: pcnr Normalization & Type Conversion (NORM-01, NORM-02, NORM-03, NORM-04, NORM-05) — depends on Phase 29 final column set

**v2.1 (2026-09-24):**

- Phase 22 added: Pipeline Green & Hardening (FIX-02, RUN-02, RUN-03, INV-07, DOC-05) -- first, because the 2026-09-24 run stopped at 16b
- Phase 23 added: Sentinel & Name Inventory (PCNR-01..06); human checkpoint, PCNR_APPROVED gate
- Phase 24 added: Build g.pcnr_harmonized (PCNR-07..11)
- Phase 25 added: pcnr Cohort, Dictionary & Wiring (PCNR-12..17)
- PCM-D-15 gap-fill and r7/r8/r9 linkage moved to v2.2

**v2.0 (2026-09-23):**

- Phase 19 added: Raw Directory Inventory (INV-01 through INV-07)
- Phase 20 added: pecan_ID Derivation (PID-01 through PID-08); depends on Phase 19
- Phase 21 added: Runner Wiring & D3 Fix (RUN-01, FIX-01); must follow Phases 19 and 20

### Established Decisions

- RUN-01 SATISFIED 2026-09-24: run_pipeline.cmd wires all 14 programs (01-08, 19, 20, 10b, 16b, 17, 18) as separate sas.exe sessions per PCM-C-05; full end-to-end run PASSED; stop-path verified; in_pipeline=1 confirmed via envlen(RUN_ALL) in 00_config.sas
- PCM-D-19 APPROVED 2026-09-23: DOMAIN_MAP_APPROVED=1 in program 17; D3 DATALINES rows confirmed; supersedes v1 Checkpoint 1 hold
- PCM-D-20 APPROVED 2026-09-23: program 17 redirected from g.analysis_base to g.analytic_cohort; keyed comparison writes qc/17_pcm_d20_compare.txt
- PCM-D-21 RESOLVED 2026-09-28: sentinel seed list and matching rules; case-insensitive match on normalized value; compound forms included
- PCM-D-22 RESOLVED 2026-09-28: PRECEDE_STUDY_ID and pecan_ID keep original names (no pcnr_ prefix)
- PCM-D-23 RESOLVED 2026-09-28: names >27 chars shortened; rule in pcnr_name_map.csv
- PCM-D-24 RESOLVED 2026-09-28: no numeric values approved for recode in v2.1
- PCM-D-25 RESOLVED 2026-09-28: rationale column free-text; decided_by and date required
- PCM-D-26 RESOLVED 2026-09-29: program 17 reads g.analytic_cohort unchanged; repointing deferred to v2.2 pending Price review
- md3 is the merge spine (complete superset, PCM-F-02); operation is 1:1 merge, not stack-dedup
- No PROC SQL UPDATE anywhere (silent truncation trap, PCM-T-01)
- No `data X; set X;` patterns (destroys dataset, PCM-T-02)
- Single ownership per variable (prevents last-wins overwrite, PCM-T-05)
- PCM-D-15 APPROVED 2026-09-22: per-column gap candidates for r1-r9; r1-r6 wired in Phase 29; r7-r9 pending PCM-D-28
- PCM-D-16 DIAGNOSED: r7/r8/r9 2022 IDs match 0 base rows -- PCM-D-28 investigation in Phase 28

### Open Decisions (v2.2)

- **PCM-D-28** — which encryption scheme r7-r9 use and whether the 9,215-ID mismatch (PCM-D-16) is recoverable; recorded in Phase 28

### Pending Todos

- Inform Price of PCM-D-05 resolution (decided by Gerard 2026-09-21; update attribution on Price's response)
- Report to PeCAN data group: source system emits impossible operative timestamp combinations (9 rows) and negative intervals concentrated in percutaneous services

### Blockers

None at roadmap definition.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260930-mze | HARD-02 source hash guard: 00_config.sas macros, 19c seed, SECTION 14 guard, PCM-D-30 | 2026-09-30 | 820c4d1 | [260930-mze-implement-hard-02-source-hash-guard-add-](.planning/quick/260930-mze-implement-hard-02-source-hash-guard-add-/) |

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
*Last updated: 2026-09-29 — v2.2 roadmap defined; Phases 26-30 planned; 18 requirements mapped; ready to plan Phase 26*
