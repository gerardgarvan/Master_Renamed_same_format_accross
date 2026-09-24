# PROJECT.md — PeCAN Master Dataset Integration

**Project ID:** PCM
**Owner:** Gerard Garvan (ggarvan)
**Working folder:** `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross`
**Repo:** local disk (see PCM-C-04 -- do NOT put the git repo on the P: drive)
**Status:** v2.0 SHIPPED 2026-09-24
**Supersedes:** all ad-hoc `master_data_*` merge/stack/dedup code written before this document

---

## What This Is

A reproducible, provenance-tracked SAS pipeline that merges eight heterogeneous master
extracts (`master_data_1..8.sas7bdat`) into one analysis-ready patient-level dataset, with
a harmonized overlay, a documented analytic cohort, a patient-level linkage key (pecan_ID),
and a complete raw directory inventory. Every type conversion, name reconciliation,
row-count change, and project decision is traceable to a numbered SAS program in version
control, and the entire pipeline runs end-to-end from a single batch driver (`run_pipeline.cmd`).

## Core Value

A single `run_pipeline.cmd` that runs 14 SAS programs start-to-finish in a clean SAS session
against read-only sources, producing `g.master_data_merged` (41,150 rows), `g.analytic_cohort`
(13,890 rows) with `pecan_ID` attached, passing QC reports, a data dictionary, and a resolved
DECISIONS.md — with no manual steps.

---

## Current State (after v2.0 milestone, 2026-09-24)

**Pipeline datasets:**
- `g.master_data_merged` -- 41,150 rows, 176 columns, all assertions pass
- `g.master_data_harmonized` -- 41,150 rows, 175 columns (includes pecan_ID)
- `g.analytic_cohort` -- 13,890 rows, 175 columns (INPATIENT+OBSERVATION; includes pecan_ID)
- `g.pecan_id_xwalk` -- append-only crosswalk (ENCRYPTED_MRN → pecan_ID, surrogate integer per PCM-D-17)

**SAS programs:** 14 production programs wired via `run_pipeline.cmd`
- Core pipeline: 01-08
- v2.0 additions: 19 (raw inventory), 20 (pecan_ID derivation)
- Harmonization/cohort: 10b, 16b, 17, 18

**Documentation:**
- `docs/DATA_DICTIONARY.xlsx` -- 175 variables including pecan_ID, KEY sheet leftmost, UF blue headers
- `docs/DECISIONS.md` -- PCM-D-01 through PCM-D-20 resolved and attributed
- `qc/19_raw_inventory.xlsx` -- complete variable-level raw directory inventory (INV-01..INV-06)
- `qc/17_summary_stats_by_domain.xlsx` -- D1-D5 including D3 (Cognitive) now populated
- `qc/16b_pecan_id_counts.txt` -- pecan_ID encounter distribution (PID-06)
- `qc/20_pecan_id_linkage_reach.txt` -- PID-07 r7/r8/r9 MRN linkage reach report

**Known gap (v2.1):**
- INV-07: `qc/19_raw_inventory.xlsx` workbook formatting (UF colors, KEY sheet legend, FAMILIES sheet) not yet applied

---

## Requirements

### Validated (v1 milestone, shipped 2026-09-22)

- ✓ SRC-01 through SRC-04 -- Source integrity: checksums, counts, key uniqueness, md3 superset — v1
- ✓ OWN-01 through OWN-04 -- Ownership map: ownership table, conflict naming, coalesce assertions — v1
- ✓ PREP-01 through PREP-09 -- Per-source normalization: all eight prep programs, NULL clearing, type conversions, negative interval handling — v1
- ✓ MRG-01 through MRG-06 -- Merge: 41,150 rows, provenance flags, rt_envelope_flag, md8 gap-fill — v1
- ✓ QC-01 through QC-07 -- Merge QC: row count, truncation, NULL strings, md8 block scoping, clinical ranges, envelope containment — v1
- ✓ REC-01 through REC-04, REC-06 -- Variable reconciliation: all naming conflicts attributed — v1
- ✓ COH-01 through COH-04 -- Cohort & missingness: 07_cohort.sas, missingness profile, PCM-D-05 resolved — v1
- ✓ DOC-01 through DOC-04 -- Documentation & handoff: DATA_DICTIONARY.xlsx, DECISIONS.md, 99_run_all.sas — v1
- ✓ HARM-01 through HARM-10 -- Harmonization: h_* columns, analytic cohort rebuilt — v1
- ✓ SUMM-01, SUMM-02, SUMM-DOMAIN — Summary statistics and domain workbook — v1
- ✓ RAW-08 through RAW-12 -- Supplemental raw inventory, 2022 ID diagnostic — v1

### Validated (v2.0 milestone, shipped 2026-09-24)

- ✓ INV-01 through INV-06 -- Raw directory inventory: file listing with checksums, variable-level profiling, key-column flags, reconciliation against known sources — v2.0
- ✓ PID-01 through PID-08 -- pecan_ID derivation: source audit, append-only crosswalk, cardinality assertions, attachment per PCM-D-18, r7/r8/r9 linkage reach, DATA_DICTIONARY + DECISIONS.md updated — v2.0
- ✓ RUN-01 -- Full pipeline batch driver (`run_pipeline.cmd`): 14 programs, separate sas.exe per PCM-C-05, exit-code gating — v2.0
- ✓ FIX-01 -- D3 cognitive domain fix: DOMAIN_MAP_APPROVED=1, COGNITIVE_SCORE/COGNITIVE_CATEGORY on D3 sheet — v2.0

### Active (v2.1 candidates)

- [ ] INV-07 -- `qc/19_raw_inventory.xlsx` formatting: UF blue headers, KEY sheet legend, FAMILIES sheet, sheet order enforced
- [ ] PCM-D-15 gap-fill wiring -- Integrate r1-r9 extension-column gap candidates into base file (approved 2026-09-22; wiring deferred pending PID-07 result)
- [ ] r7/r8/r9 linkage resolution -- PID-07 report confirmed 2022 IDs fail on PRECEDE_STUDY_ID (PCM-D-16); follow-up depends on whether MRN linking is feasible

### Deferred (intentional)

- REC-05 (PCM-D-07) -- Age floor of 64 investigation: upstream inclusion criterion; out of scope
- v2 dCDT/INS abstract pipeline -- separate project
- Statistical modelling -- this project ends at the analysis-ready file

### Out of Scope

- Re-importing from source CSVs/XLSX -- validated lossless (PCM-F-08); no re-import needed
- UTF-8 encoding repair -- encoding damage confined to <=9 rows of Base_Procedure_1; flag only (PCM-C-01)

---

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| md3 as merge spine | Complete superset (PCM-F-02); 1:1 merge onto md3, not stack-dedup | ✓ Established (Phase 4) |
| No PROC SQL UPDATE | Silent truncation trap (PCM-T-01) | ✓ Established |
| No `data X; set X;` | Destroys dataset (PCM-T-02) | ✓ Established |
| Single ownership per variable | Prevents silent last-wins overwrite (PCM-T-05) | ✓ Established |
| PCM-D-05 Analytic cohort | Admit_BMI forces INPATIENT+OBSERVATION restriction | ✓ N=13,890; Gerard 2026-09-21 |
| PCM-D-12 %abort cancel exit code | Return code needed for batch scheduling | ✓ Exit code = 3; -sasuser WORK required |
| PCM-D-15 Supplement raw gap-fill | Per-column gap candidates for r1-r9 extension columns | ✓ Approved 2026-09-22; wiring deferred |
| PCM-D-16 2022 ID mismatch | r7/r8/r9 2022 IDs match 0 base rows | ✓ Diagnosed; not fixed |
| PCM-D-17 pecan_ID derivation | Surrogate sequential integer, append-only crosswalk, ISO-dated backup | ✓ Resolved 2026-09-23 |
| PCM-D-18 pecan_ID attach point | Attach in 10b (harmonized) and 16b (cohort); g.master_data_merged untouched | ✓ Resolved 2026-09-23 |
| PCM-D-19 DOMAIN_MAP_APPROVED | D3 DATALINES rows confirmed; gate flipped to 1 | ✓ Approved 2026-09-23 |
| PCM-D-20 Program 17 input redirect | g.analysis_base (no pipeline producer) → g.analytic_cohort (pipeline-produced) | ✓ Approved 2026-09-23; 27,260 non-cohort rows correctly excluded |

---

## Constraints

- SAS 9.4M8 on Windows; session encoding is not UTF-8 (source of PCM-F-10 encoding damage)
- Read-only on `master_data_1..8.sas7bdat` and everything under `raw\master`
- No PHI in git: `.gitignore` excludes `*.sas7bdat`, `*.xlsx`, `*.csv`, `data/` tree
- Repo on local disk, not P: drive -- git against network share is slow and prone to index corruption
- Delivery: UF colors (#0021A5, #FA4616) on visual deliverables; KEY sheet leftmost in workbooks
- **PCM-C-05** -- Restart SAS session between programs; each is a separate invocation with exit code 3 on abort

---

## Validated Findings

- **PCM-F-01** -- PRECEDE_STUDY_ID is strictly unique in all eight sources
- **PCM-F-02** -- master_data_3 is a complete superset of all IDs from md1, md2, md4-md8
- **PCM-F-07** -- Coalescing BMI from other sources recovers nothing; 28,424 missing are missing at source
- **PCM-F-10** -- Encoding damage confined to Base_Procedure_1, <=9 rows per file; flag only
- **PCM-F-11** -- md3 42.7% / md8 cognitive/frailty coverage; BMI 91.6% within admitted cohort
- **PCM-F-18** -- md3-owns WAS discarding data from md8 for five variables; five confirmed with zero disagreements
- **PCM-F-20** -- r7/r8/r9 (2022 files) carry ENCRYPTED_MRN but match 0 rows in pecan_id_xwalk on PRECEDE_STUDY_ID; MRN-based linking untested (PCM-D-16 follow-up)

## Traps to Avoid

- **PCM-T-01** -- PROC SQL UPDATE silently truncates character variables to 200 bytes
- **PCM-T-02** -- `data X; set X;` destroys the dataset if SAS is interrupted
- **PCM-T-05** -- Without single-ownership enforcement, MERGE produces silent last-wins overwrites
- **PCM-T-12** -- Spot checks answer ownership questions wrong; enumerate every candidate
- **PCM-T-13** -- `dictionary.columns.type` is CHARACTER ('char'/'num'), not numeric 1/2

---

## Open Todos

- Inform Price of PCM-D-05 resolution (decided by Gerard 2026-09-21; update attribution on Price's response)
- Report to PeCAN data group: source system emits impossible operative timestamp combinations (9 rows) and negative intervals concentrated in percutaneous services

---

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition:** Requirements validated? → move to Validated. Decisions to log? → add to Key Decisions. "What This Is" drifted? → update.

**After each milestone (`/gsd:complete-milestone`):** Full review of all sections; Core Value check; Out of Scope audit; Context update.

---

*Last updated: 2026-09-24 — v2.0 milestone shipped (pecan_ID + Raw Directory Inventory)*
