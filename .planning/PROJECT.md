# PROJECT.md — PeCAN Master Dataset Integration

**Project ID:** PCM
**Owner:** Gerard Garvan (ggarvan)
**Working folder:** `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross`
**Repo:** local disk (see PCM-C-04 -- do NOT put the git repo on the P: drive)
**Status:** v2.1 SHIPPED 2026-09-29; ready for v2.2 planning
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

## Current State (after Phase 28, 2026-10-07)

**Pipeline datasets:**
- `g.master_data_merged` -- 41,150 rows, 176 columns, all assertions pass
- `g.master_data_harmonized` -- 41,150 rows, 175 columns (includes pecan_ID)
- `g.analytic_cohort` -- 13,890 rows, 175 columns (INPATIENT+OBSERVATION; includes pecan_ID)
- `g.pecan_id_xwalk` -- append-only crosswalk (ENCRYPTED_MRN → pecan_ID, surrogate integer per PCM-D-17)
- `g.pcnr_harmonized` -- 41,150 rows, same column count as source; all sentinel values set to missing; all analysis variables renamed `pcnr_<original>` per approved decisions
- `g.pcnr_analytic_cohort` -- 13,890 rows; derived from `g.pcnr_harmonized` with PCM-D-05 restriction

**SAS programs:** 17 production programs wired via `run_pipeline.cmd`
- Core pipeline: 01-08
- v2.0 additions: 19 (raw inventory), 20 (pecan_ID derivation)
- Harmonization/cohort: 10b, 16b, 17, 18
- v2.1 additions: 23 (sentinel/name inventory), 24 (pcnr build), 25 (pcnr cohort + dictionary)

**Documentation:**
- `docs/DATA_DICTIONARY.xlsx` -- 175 variables including pecan_ID, KEY sheet leftmost, UF blue headers
- `docs/DECISIONS.md` -- PCM-D-01 through PCM-D-26 resolved and attributed
- `docs/pcnr_name_map.csv` -- original → pcnr column name mapping for all 175 variables
- `docs/sentinel_decisions.csv` -- PCNR_APPROVED=1; every candidate value with action and rationale
- `qc/19_raw_inventory.xlsx` -- raw directory inventory with UF blue headers, KEY sheet leftmost (INV-07 closed)
- `qc/PCNR_DICTIONARY.xlsx` -- pcnr variable dictionary; KEY sheet leftmost, UF blue headers
- `qc/24_pcnr_recode_counts.csv` -- per-variable × per-value recode audit
- `qc/17_summary_stats_by_domain.xlsx` -- D1-D5 including D3 (Cognitive)
- `qc/16b_pecan_id_counts.txt` -- pecan_ID encounter distribution (PID-06)
- `qc/20_pecan_id_linkage_reach.txt` -- PID-07 r7/r8/r9 MRN linkage reach report

---

## Current Milestone: v2.2 pcnr Normalization, Gap-Fill & Linkage

**Goal:** Normalize and type-convert the pcnr datasets, wire r1-r9 gap-fill for linkable files, investigate r7-r9 and raw\ linkage feasibility, harden the source directory against accidental modification, and correct the md8 row-count finding.

**Target features (in build order):**

1. **Normalization + type conversion (pcnr datasets)** — case/whitespace normalization of category levels, then numeric type conversion for character columns that are entirely numeric post-sentinel removal. Exclusion list sourced from `19_raw_key_columns.csv` plus named code columns (CPT, Base_Procedure_Code, ZIP); maintained in one place so a new ID column cannot be converted by accident.

2. **Gap-fill wiring (PCM-D-15)** — limited to r1-r9 files that link on PRECEDE_STUDY_ID; r7-r9 held pending item 3 outcome.

3. **r7/r8/r9 linkage investigation (PCM-D-16 follow-up)** — read `qc\20_linkage_reach.txt` to confirm r7-r9 carry no character ENCRYPTED_MRN. Investigate the 2018_2019 MRN/ENCOUNTER Crypto files and the same-named `raw\` files (2018_2019 X_MASTER/CPT_ROLLUP, 2018_2022 X_MASTER, ALL_AIM2) as evidence of a second encryption scheme; those raw\ copies match the crosswalk at 14.5%, 64%, and 41% respectively. Determine whether r7-r9 use that scheme and whether MRN linking is feasible. Record findings regardless of outcome so no later phase uses a raw\ copy under the wrong encryption assumption.

4. **md8 row-count correction** — verify md8 by counting rows where any of the 68 columns is non-missing (treating the NULL sentinel as missing) and confirm count = 22,473. The raw\ copy is a row-count reference only; its MRNs use a different encryption and the two files are not interchangeable. Update pipeline docs and planning artifacts to reflect the corrected finding.

5. **raw\master source hardening** — read-only file attribute stops Excel re-saves but does not reliably prevent deletion on a network share; full protection (remove write/delete rights on the folder) requires IT engagement. Add a guard in program 19: hash md1-md8 and compare against a stored baseline; any change to a source file fails the run immediately rather than going unnoticed. The baseline hashes file is updated only intentionally (e.g., when an extract is added or replaced), never automatically by program 19. Today's verified hashes from `19_raw_files.csv` are the natural starting baseline.

**Deferred:** Program 17 repoint (PCM-D-26) — depends on Price review and domain map re-approval; defer until after normalization so Price reviews final pcnr values once.

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

### Validated (v2.1 milestone, shipped 2026-09-29)

- ✓ FIX-02, RUN-02, RUN-03, INV-07, DOC-05 -- Pipeline green & hardening; runner warning count corrected, SAS_EXE overridable, raw inventory in UF colors — v2.1
- ✓ PCNR-01 through PCNR-06 -- Sentinel sweep (every column), numeric sentinels reported, ambiguous values reported, case-variant report, name map, sentinel_decisions.csv with PCNR_APPROVED gate — v2.1
- ✓ PCNR-07 through PCNR-11 -- `g.pcnr_harmonized` built with exact recode accounting; per-cell identity assertions; source confirmed unmodified — v2.1
- ✓ PCNR-12 through PCNR-17 -- `g.pcnr_analytic_cohort` (N=13,890); PCNR_DICTIONARY.xlsx; runner wired (17 programs); PCM-D-26 resolved — v2.1

### Next (v2.2 candidates)

- [ ] PCM-D-15 gap-fill wiring -- Integrate r1-r9 extension-column gap candidates into base file (approved 2026-09-22; pcnr datasets regenerate automatically once this lands)
- [ ] r7/r8/r9 linkage resolution -- PID-07 report confirmed 2022 IDs fail on PRECEDE_STUDY_ID (PCM-D-16); follow-up depends on whether MRN linking is feasible
- [ ] Type conversion of character columns that are entirely numeric after sentinel removal
- [ ] Case/whitespace normalization of category values (reported in v2.1, not changed)

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
| PCM-D-21 Sentinel seed list & matching rules | Case-insensitive match on normalized value; compound forms included | ✓ Resolved 2026-09-28 |
| PCM-D-22 Key column prefix handling | PRECEDE_STUDY_ID and pecan_ID keep original names (no pcnr_ prefix) | ✓ Resolved 2026-09-28 |
| PCM-D-23 Long-name shortening rule | Names >27 chars shortened; rule documented in pcnr_name_map.csv | ✓ Resolved 2026-09-28 |
| PCM-D-24 Numeric sentinels | No numeric values approved for recode in v2.1 | ✓ Resolved 2026-09-28 |
| PCM-D-25 Reason codes in sentinel_decisions.csv | Rationale column free-text; decided_by and date required | ✓ Resolved 2026-09-28 |
| PCM-D-26 Program 17 input | g.analytic_cohort retained as program 17 input; g.pcnr_analytic_cohort deferred to v2.2 repoint | ✓ Resolved 2026-09-29 |

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
- **PCM-T-14** -- A semicolon inside `%put` text ends the statement; the rest runs as SAS code (ERROR 180-322), sets OBS=0, and every later assertion reports blank values. Use `--` or `%str(;)`. Root cause of the 2026-09-24 16b failure
- **PCM-T-15** -- `%local` is invalid in open code, and open-code `%if` requires `%do`/`%end`; use `%sysfunc(ifc(%eval(...), A, B))` for a conditional `%let`

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

*Last updated: 2026-10-07 — Phase 28 complete: r7/r8/r9 encryption scheme identified, PCM-D-28 recorded*
