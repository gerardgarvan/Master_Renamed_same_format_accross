# PROJECT.md — PeCAN Master Dataset Integration

**Project ID:** PCM
**Owner:** Gerard Garvan (ggarvan)
**Working folder:** `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross`
**Repo:** local disk (see PCM-C-04 -- do NOT put the git repo on the P: drive)
**Status:** v2.0 IN PROGRESS (v1 SHIPPED 2026-09-22)
**Supersedes:** all ad-hoc `master_data_*` merge/stack/dedup code written before this document

---

## What This Is

A reproducible, provenance-tracked SAS pipeline that merges eight heterogeneous master
extracts (`master_data_1..8.sas7bdat`) into one analysis-ready patient-level dataset, with
a harmonized overlay and a documented analytic cohort. Every type conversion, name
reconciliation, row-count change, and project decision is traceable to a numbered SAS
program in version control.

## Core Value

A single `99_run_all.sas` that runs start-to-finish in a clean SAS session against
read-only sources, producing `g.master_data_merged` (41,150 rows), passing QC reports,
a data dictionary, and a resolved DECISIONS.md -- with no manual steps.

The harmonized overlay (`g.master_data_harmonized`) and rebuilt analytic cohort
(`g.analytic_cohort`, 13,890 rows) are produced by a separate but fully-documented
SAS call sequence outside the single-runner scope boundary.

## Current Milestone: v2.0 pecan_ID + Raw Directory Inventory

**Goal:** Add a patient-level linkage key (pecan_ID, derived from ENCRYPTED_MRN) to pipeline outputs per PCM-D-18, and produce a complete file-and-variable inventory of the raw directory tree.

**Target features:**
- Phase 19: Raw directory inventory (19_raw_dir_inventory.sas) — recursive file listing with checksums, variable-level profiling, key-column flags, reconciliation against known sources, qc/19_raw_inventory.xlsx
- Phase 20: pecan_ID derivation (20_pecan_id.sas) — source audit, crosswalk g.pecan_id_xwalk per PCM-D-17, attachment per PCM-D-18, linkage reach test for r7/r8/r9, DATA_DICTIONARY + DECISIONS.md updates
- Carry-over candidates (optional): 99_run_all.sas wiring, D3 cognitive DATALINES fix, PCM-D-15 gap-fill wiring

**Open decisions:** PCM-D-17 (pecan_ID derivation method + MRN retention), PCM-D-18 (attach point)

---

## Current State (after v1 milestone)

**Pipeline datasets:**
- `g.master_data_merged` -- 41,150 rows, 176 columns, all 14 assertions pass
- `g.master_data_harmonized` -- 41,150 rows, 174 columns (HARM-07: 12 no-info columns dropped)
- `g.analytic_cohort` -- 13,890 rows, 174 columns (INPATIENT+OBSERVATION; rebuilt from harmonized file)

**Documentation:**
- `docs/DATA_DICTIONARY.xlsx` -- 176 variables, KEY sheet leftmost, UF blue headers
- `docs/DECISIONS.md` -- PCM-D-01 through PCM-D-14 resolved and attributed
- `qc/17_summary_stats_by_domain.xlsx` -- D1-D5 descriptive statistics workbook
- `qc/18_gap_candidates.txt` -- supplemental raw gap-fill candidate table

**SAS programs:** 37 programs, 22,319 lines

---

## Requirements

### Validated (v1 milestone)

- v SRC-01 through SRC-04 -- Source integrity: checksums, counts, key uniqueness, md3 superset -- v1
- v OWN-01 through OWN-04 -- Ownership map: ownership table, conflict naming, coalesce assertions -- v1
- v PREP-01 through PREP-09 -- Per-source normalization: all eight prep programs, NULL clearing, type conversions, negative interval handling -- v1
- v MRG-01 through MRG-06 -- Merge: 41,150 rows, provenance flags, rt_envelope_flag, md8 gap-fill -- v1
- v QC-01 through QC-07 -- Merge QC: row count, truncation, NULL strings, md8 block scoping, clinical ranges, envelope containment -- v1
- v REC-01 through REC-04, REC-06 -- Variable reconciliation: all naming conflicts attributed; keep-separate decisions documented -- v1
- v COH-01 through COH-04 -- Cohort & missingness: 07_cohort.sas, missingness profile, complete-case Ns, PCM-D-05 resolved -- v1
- v DOC-01 through DOC-04 -- Documentation & handoff: DATA_DICTIONARY.xlsx, DECISIONS.md, 99_run_all.sas clean run, git history -- v1
- v HARM-01 through HARM-10 -- Variable harmonization: label-similarity sweep, concept_decisions.csv, HARM-07 rule, h_* columns, analytic cohort rebuilt -- v1
- v SUMM-01, SUMM-02 -- Summary statistics: SUMMARY_STATS_HARMONIZED.xlsx -- v1
- v SUMM-DOMAIN-DISC through SUMM-DOMAIN-BOOK -- Domain-stratified statistics workbook -- v1
- v RAW-08 through RAW-12 -- Supplemental raw inventory: 2022 ID diagnostic, per-column gap counts, D15 gate -- v1

### Active (v2 candidates)

- [ ] Wire 10b_concept_harmonize.sas, 16b_cohort_rebuild.sas, 17_summary_stats_by_domain.sas, and 18_supplemental_raw_gap.sas into 99_run_all.sas for a single end-to-end runner
- [ ] Fix D3 (Cognitive assessments) domain in Phase 17 workbook: assign COGNITIVE_SCORE and COGNITIVE_CATEGORY to instrument stat_route in domain lookup
- [ ] Integrate extension-column gap-fill into base file (PCM-D-15 approved 2026-09-22; wiring not yet done)

### Deferred (intentional)

- REC-05 (PCM-D-07) -- Age floor of 64 investigation: upstream inclusion criterion; out of scope for this project
- v2 dCDT/INS abstract pipeline -- separate project
- Statistical modelling -- this project ends at the analysis-ready file

### Out of Scope

- Re-importing from source CSVs/XLSX -- validated lossless (PCM-F-08); no re-import needed
- Statistical analysis -- project ends at analysis-ready file
- INS abstract / dCDT pipeline -- separate project
- UTF-8 encoding repair -- encoding damage confined to <=9 rows of Base_Procedure_1; flag only, do not re-encode (PCM-C-01 constraint)

---

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| md3 as merge spine | Complete superset (PCM-F-02); 1:1 merge onto md3, not stack-dedup | v Established (Phase 4) |
| No PROC SQL UPDATE | Silent truncation trap (PCM-T-01); all mutations in DATA steps with explicit length | v Established |
| No `data X; set X;` | Destroys dataset on completion with no undo (PCM-T-02) | v Established |
| Single ownership per variable | Prevents silent last-wins overwrite (PCM-T-05) | v Established -- map at qclib.ownership_map |
| PCM-D-01 Death variables | Three names for one flag across sources | v Keep-separate (Price 2026-08-27) |
| PCM-D-02 Frailty components | Char Y/N vs numeric encodings of same five items | v Keep-separate (Price 2026-08-27) |
| PCM-D-03 ISO_SEV naming | md4/md8 naming differs; md8 ISO_SEV is a TOTAL | v Keep-separate -- documented |
| PCM-D-04 Emergent usability | Near-zero positives; likely clinician non-completion | v Retain -- caveat in data dictionary |
| PCM-D-05 Analytic cohort | Admit_BMI forces restriction -- all 12,726 values inside admitted cohort | v Restricted to INPATIENT+OBSERVATION (N=13,890); Gerard 2026-09-21 |
| PCM-D-06 PRECEDE_Study_ID_1 | Duplicate column in md6 | v Drop -- proven identical first (PREP-04) |
| PCM-D-07 Age floor | Minimum 64; upstream inclusion criterion | v Deferred -- not pursuing; QC-05 floor stays at 18 |
| PCM-D-08 Envelope violations | 9 rows where sub-interval > room interval | v Flag (rt_envelope_flag), do not null -- 9 rows flagged |
| PCM-D-09 QC-05 ceilings | Three operative-interval ceilings never fired | v Removed (QC-07) -- 8 assertions reduced to 5 |
| PCM-D-10 Negative rt_* | Only anchor-offset variables have expected negatives | v Retain-with-doc -- rt_ANCHOR_to_*_days confirmed legitimate |
| PCM-D-11 md3-owns missingness | md3-owns discarded five variables from md8 | v MRG-06 gap-fill -- zero disagreements; one-way only |
| PCM-D-12 %abort cancel exit code | Return code needed for batch scheduling | v Exit code = 3 on Windows batch; -sasuser WORK required |
| PCM-D-13 CPT1_CODE_LABEL / SSDI | SSDI death family harmonizable; CPT1 not | v h_ssdi_death added; CPT1_CODE_LABEL keep-separate |
| PCM-D-14 Pipeline-column rule | in_md3 constant; eleven h_*_src single-value | v Drop -- HARM-07 DROP= block in 10b |
| PCM-D-15 Supplement raw gap-fill | Per-column gap candidates for r1-r9 extension columns | v Approved 2026-09-22 -- D15_APPROVED=1 in 00_config.sas |
| PCM-D-16 2022 ID mismatch | r7/r8/r9 2022 IDs match 0 base rows | v Diagnosed (schema-change-era format change) -- documented, not fixed |

---

## Constraints

- SAS 9.4M8 on Windows; session encoding is not UTF-8 (source of PCM-F-10 encoding damage)
- Read-only on `master_data_1..8.sas7bdat` and everything under `raw\master`
- No PHI in git: `.gitignore` excludes `*.sas7bdat`, `*.xlsx`, `*.csv`, `data/` tree
- Repo on local disk, not P: drive -- git against network share is slow and prone to index corruption
- Delivery: UF colors (#0021A5, #FA4616) on visual deliverables; KEY sheet leftmost in workbooks
- **PCM-C-05** -- Restart SAS session between programs -- `%abort cancel` leaves an interactive session that swallows the next submit without executing it; in batch, each program is a separate invocation with exit code 3 on abort (PCM-D-12)

---

## Validated Findings

- **PCM-F-01** -- PRECEDE_STUDY_ID is strictly unique in all eight sources (asserted in code, Phase 1)
- **PCM-F-02** -- master_data_3 is a complete superset of all IDs from md1, md2, md4-md8 (asserted in code, Phase 1)
- **PCM-F-07** -- Coalescing BMI from other sources recovers nothing; 28,424 missing are missing at source
- **PCM-F-08** -- Re-import from source CSVs/XLSX is lossless; not needed for this pipeline
- **PCM-F-10** -- Encoding damage confined to Base_Procedure_1, <=9 rows per file; flag only
- **PCM-F-11** -- md3 42.7% / md8 (in cohort) 52.2% / 58.7% cognitive/frailty coverage; BMI 91.6% within admitted cohort
- **PCM-F-18** -- md3-owns WAS discarding data from md8 for five variables; five confirmed with zero disagreements
- **PCM-F-19** -- PCM-F-12 (geriatric assessments restricted to admitted cohort) is void after MRG-06; PCM-D-05 re-decided on BMI evidence

## Traps to Avoid

- **PCM-T-01** -- PROC SQL UPDATE silently truncates character variables to 200 bytes
- **PCM-T-02** -- `data X; set X;` destroys the dataset if SAS is interrupted during the DATA step
- **PCM-T-05** -- Without single-ownership enforcement, MERGE produces silent last-wins overwrites
- **PCM-T-12** -- Spot checks answer ownership questions wrong when not all sources are tested; enumerate every candidate
- **PCM-T-13** -- `dictionary.columns.type` is CHARACTER ('char'/'num'), not numeric; PROC CONTENTS uses numeric 1=NUM / 2=CHAR; comparing them silently never matches

---

## Todos for v2

- Inform Price of PCM-D-05 resolution (decided by Gerard, 2026-09-21; update attribution line on Price's response)
- Report to PeCAN data group: source system emits impossible operative timestamp combinations (9 rows) and negative intervals concentrated in percutaneous services
- Consider whether .planning/PROJECT.md should restore the full PCM-T-01..T-11 trap list (condensed version dropped several traps)

---

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---

*Last updated: 2026-09-23 — v2.0 milestone started (pecan_ID + Raw Directory Inventory)*
