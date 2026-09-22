# Milestone v1: PeCAN Master Dataset Integration Pipeline

**Status:** SHIPPED 2026-09-22
**Phases:** 1-8, 14-18 (active); 1-5 pre-archived
**Total Plans:** 23 plans across active phases (6-8: 8 plans, 14-18: 10 plans, plus 5 pre-archived)
**Total SAS programs:** 37 programs, 22,319 lines
**Git range:** 471011a (2026-08-25) -> 3d2a83d (2026-09-22), 245 commits, 28 days

---

## Overview

Complete, reproducible, provenance-tracked SAS pipeline that merges eight heterogeneous
master extracts into one analysis-ready patient-level dataset. Every type conversion, name
reconciliation, and row-count change is traceable to a numbered SAS program in version
control. The pipeline runs start-to-finish from `99_run_all.sas` in a clean SAS session
against read-only sources with no manual steps.

**Delivered datasets:**

- `g.master_data_merged` — 41,150 rows, 176 columns, all 14 assertions pass
- `g.master_data_harmonized` — 41,150 rows, 174 columns, 11 h_* harmonized columns, HARM-07 enforced
- `g.analytic_cohort` — 13,890 rows (INPATIENT + OBSERVATION), 174 columns, rebuilt from harmonized file
- `docs/DATA_DICTIONARY.xlsx` — 176 variables, KEY sheet leftmost, UF blue headers
- `docs/DECISIONS.md` — PCM-D-01 through PCM-D-14 all resolved and attributed
- `qc/17_summary_stats_by_domain.xlsx` — Domain-stratified descriptive statistics workbook (D1-D5)
- `qc/18_gap_candidates.txt` — Supplemental raw inventory for PCM-D-15 gap-fill decision

---

## Phases

### Phase 1: Source Verification & Freeze (Pre-archived)

**Goal**: Checksum and freeze all eight source files; assert PCM-F-01 (unique key) and PCM-F-02 (md3 superset) in executable code
**Plans**: 2 plans
Plans:
- [x] 01-01-PLAN.md -- Preconditions (libname + XCMD), SHA-256 checksums, per-source counts (SRC-03, SRC-04, SRC-06)
- [x] 01-02-PLAN.md -- SRC-05 blank-key assertion, SRC-01 uniqueness, SRC-02 superset anti-join (SRC-01, SRC-02, SRC-05)

### Phase 2: Ownership Map (Pre-archived)

**Goal**: Declare one owner per variable; name every conflict; assert coalesce-wanted variables
**Plans**: 2 plans
Plans:
- [x] 02-01-PLAN.md -- DECISIONS.md stub + ownership enumeration (OWN-01, OWN-02)
- [x] 02-02-PLAN.md -- Conflict detection + Admit_BMI/Race coalesce assertions (OWN-03, OWN-04)

### Phase 3: Per-Source Normalization (Pre-archived)

**Goal**: Eight standalone prep programs resolve all type, encoding, and structural anomalies
**Plans**: 6 plans
Plans:
- [x] 03-01-PLAN.md -- Wave 0 setup: g library, PROC CONTENTS inventory (PREP-01, PREP-05, PREP-06)
- [x] 03-02-PLAN.md -- md8 normalization: NULL sentinel + numeric conversions (PREP-01-03, PREP-05-06)
- [x] 03-03-PLAN.md -- md1/md2/md3 structural prep; md3 spine 41,150 asserted (PREP-01-02, PREP-05-06)
- [x] 03-04-PLAN.md -- md4/md5/md6 prep; prove-then-drop PRECEDE_Study_ID_1; Base_Procedure_Code_1 to CHAR (PREP-01-02, PREP-04-07)
- [x] 03-05-PLAN.md -- md7 prep + 03_prep_all.sas driver (PREP-01-02, PREP-05-07)
- [x] 03-06-PLAN.md -- AMENDMENT-01: null negative operative intervals; scan all rt_* (PREP-08, PREP-09)

### Phase 4: Merge (Pre-archived)

**Goal**: Produce g.master_data_merged with exactly 41,150 rows, provenance flags, no last-wins overwrites
**Plans**: 2 plans
Plans:
- [x] 04-01-PLAN.md -- 04_merge.sas: KEEP= lists from ownership_map, LENGTH block, provenance flags, rt_envelope_flag, MRG-06 gap-fill, 14 assertions (MRG-01, MRG-04-06)
- [x] 04-02-PLAN.md -- Static validation + human-verify SAS run; qc/04_merge_provenance.txt (MRG-02, MRG-03)

### Phase 5: Merge QC (Pre-archived)

**Goal**: Assert row count, no truncation, no NULL strings, md8-owned block scoping, clinical ranges, envelope containment
**Plans**: 3 plans
Plans:
- [x] 05-01-PLAN.md -- 05_qc_merge.sas Sections 0-6: assert_eq macro, QC-01 to QC-05 (QC-01...QC-05)
- [x] 05-02-PLAN.md -- Static validation + human SAS run; QC-01 through QC-04 passed; QC-05 aborted at PREP-08 gap
- [x] 05-03-PLAN.md -- AMENDMENT-01: QC-06 unflagged-containment assertion, QC-07 ceiling removal (QC-06, QC-07)

### Phase 6: Variable Reconciliation

**Goal**: Resolve all naming conflicts with Price's sign-off; document deliberate multi-column concepts
**Depends on**: Phase 5
**Requirements**: PCM-D-01 through PCM-D-10, D-11 resolved 2026-08-27
**Plans**: 3 plans
Plans:
- [x] 06-01-PLAN.md -- PCM-D-10 triage: read PREP-09 report, record resolution in DECISIONS.md (PCM-D-10)
- [x] 06-02-PLAN.md -- 06_reconcile.sas: 16 deliberate columns, Emergent count, rt_envelope_flag doc, qc/06_reconcile_summary.txt (D-01-04, MRG-05)
- [x] 06-03-PLAN.md -- data_dictionary_notes.txt stub: five concept groups, D-07 inherited, D-09/D-11 cross-referenced (D-07-09, D-11)

**Details:**
All three DECISIONS.md multi-column families (mortality, frailty, ISO_SEV) documented as deliberate.
PCM-D-10 closed: rt_ANCHOR_to_*_days negatives are legitimate workflow offsets; no additional rt_* variables of concern.
PCM-D-07 (Age floor of 64) deferred as not pursuing -- QC-05 floor of 18 is a type-sanity guard only.

### Phase 7: Cohort & Missingness

**Goal**: Define analytic cohort on pre-specifiable criterion; document missingness profile and complete-case Ns
**Depends on**: Phase 6
**Requirements**: PCM-D-05, PCM-F-11, PCM-F-19
**Plans**: 2 plans
Plans:
- [x] 07-01-PLAN.md -- 07_cohort.sas: Patient_Type distribution, g.analytic_cohort (initial), four complete-case assertions, qc/07_cohort_missingness.txt (PCM-D-05, PCM-F-11)
- [x] 07-02-PLAN.md -- Update DECISIONS.md PCM-D-05 resolution; human-verify SAS run (PCM-D-05, PCM-F-11)

**Details:**
g.analytic_cohort: 13,890 rows (INPATIENT 13,223 + OBSERVATION 667).
Complete-case Ns: BMI 12,726 (91.6%), Cognitive 7,252 (52.2%), Frailty 8,150 (58.7%), all-three 6,523 (47.0%).
PCM-D-05 rationale: Admit_BMI forces the restriction -- all 12,726 BMI values are inside the admitted cohort, zero ambulatory. PCM-F-12 (geriatric assessments criterion) is void after MRG-06.

### Phase 8: Documentation & Handoff

**Goal**: 99_run_all.sas verified clean; DATA_DICTIONARY.xlsx complete; DECISIONS.md resolved through D-12
**Depends on**: Phase 7
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04
**Plans**: 3 plans
Plans:
- [x] 08-01-PLAN.md -- 08_dictionary.sas: PROC CONTENTS + PROC MEANS + ownership join + ODS EXCEL with KEY leftmost and UF colors (DOC-01)
- [x] 08-02-PLAN.md -- Phase 8 block added to 99_run_all.sas; PCM-D-12 (%abort cancel returns exit code 3) added to DECISIONS.md (DOC-02, DOC-03)
- [x] 08-03-PLAN.md -- Human-verify full pipeline run and DATA_DICTIONARY.xlsx; git history completeness confirmed (DOC-01, DOC-04)

**Details:**
DATA_DICTIONARY.xlsx: 176 variables, KEY sheet leftmost, UF blue (#0021A5) headers, all spot-checks passed.
99_run_all.sas runs clean, zero ERRORs, all eight phases wired.
PCM-D-12 settled: %abort cancel returns OS exit code 3 on Windows batch; -sasuser WORK required in headless runs.

### Phase 14: Label-Similarity Sweep

**Goal**: Find same-concept variables whose names share nothing by comparing variable labels (COMPGED)
**Depends on**: Phase 13 (pre-audit)
**Requirements**: HARM-02, HARM-03, HARM-09
**Plans**: 2 plans
Plans:
- [x] 14-01-PLAN.md -- 14_label_similarity.sas Section A: COMPGED pairwise sweep, docs/label_similarity_candidates.csv + CONCEPT_EVIDENCE workbook (HARM-02, HARM-03)
- [x] 14-02-PLAN.md -- Section B: SSDI death family and CPT1 concept profiling, concept_decisions_EXT_TEMPLATE.csv (HARM-09)

**Details:**
Label similarity sweep found no new harmonizable pairs beyond those already in concept_decisions.csv.
SSDI death family (SSDI_DEATH_DATE_Y_N, SSDI_DEATH_Y_N, SSDI_DEATH) and CPT1_CLASS/CPT1_LABEL profiled.
CPT1_CODE_LABEL: keep-separate (PCM-D-13); SSDI death family merged into h_ssdi_death in Phase 15.

### Phase 15: Extend the Harmonized Dataset

**Goal**: Apply confirmed concept decisions to g.master_data_harmonized; enforce HARM-07 pipeline-column rule
**Depends on**: Phase 14
**Requirements**: HARM-04, HARM-07
**Plans**: 2 plans
Plans:
- [x] 15-01-PLAN.md -- HARM-04: concept_decisions.csv extended with SSDI/CPT1 confirmations; PCM-D-13 attribution in DECISIONS.md (HARM-04)
- [x] 15-02-PLAN.md -- HARM-07: pipeline-column rule + DROP block for in_md3 + eleven h_*_src columns; 176-column merged assertion; fresh-session re-run (HARM-07, HARM-04)

**Details:**
h_ssdi_death added: 29,316 non-missing values (71.2% coverage). All 7 assertion NOTEs pass.
g.master_data_harmonized: 174 columns (12 pipeline columns dropped per HARM-07 rule).
g.master_data_merged confirmed unmodified: 176 columns, 41,150 rows, before and after.

### Phase 16: Rebuild the Analytic Cohort

**Goal**: Rebuild g.analytic_cohort from g.master_data_harmonized; resolve PCM-D-05 with evidence
**Depends on**: Phase 15
**Requirements**: HARM-10, PCM-D-05
**Plans**: 2 plans
Plans:
- [x] 16-01-PLAN.md -- 16b_cohort_rebuild.sas: read g.master_data_harmonized, INPATIENT+OBSERVATION filter, promote g.analytic_cohort (174 cols, 13,890 rows), all assertions pass (HARM-10)
- [x] 16-02-PLAN.md -- PCM-D-05 in DECISIONS.md: BMI-forces-restriction rationale, five population-shift figures, attribution; STATE.md updated (PCM-D-05, HARM-10)

**Details:**
g.analytic_cohort: 13,890 rows, 174 columns -- carries all h_* columns, no dropped aliases.
Population shift documented: Charlson 0 falls 60.8% to 34.5%; GA rises 57.6% to 84.2%; RACE=WHITE 79.8% to 87.1%.
PCM-D-05 decided by Gerard 2026-09-21; Price follow-up item recorded.

### Phase 17: Summary Statistics by Variable Domain

**Goal**: Descriptive statistics for every PRECEDE-dictionary variable in five clinical domains, output as Excel workbook with pooled and per-year columns, sentinel recoding, small-cell suppression
**Depends on**: Phase 16
**Requirements**: SUMM-DOMAIN-DISC, SUMM-DOMAIN-MAP, SUMM-DOMAIN-STATS, SUMM-DOMAIN-BOOK
**Plans**: 4 plans
Plans:
- [x] 17-01-PLAN.md -- Wave 0: scaffold, year variable discovery, extension KEEP= list, per-year N (SUMM-DOMAIN-DISC)
- [x] 17-02-PLAN.md -- Wave 1: work.analysis_base_ext, dictionary match, domain assignment g.var_domain_map, Checkpoint 1 (SUMM-DOMAIN-MAP)
- [x] 17-03-PLAN.md -- Wave 2: sentinel recode, PROC MEANS + PROC FREQ pooled and per-year, small-cell suppression <=11 (SUMM-DOMAIN-STATS)
- [x] 17-04-PLAN.md -- Wave 3: ODS EXCEL workbook (KEY leftmost, D1-D5, Crosswalk, QC), UF colors, Checkpoint 2 approved (SUMM-DOMAIN-BOOK)

**Details:**
Workbook: qc/17_summary_stats_by_domain.xlsx -- KEY, D1 Sociodemographics, D2 Preoperative, D4 Intraoperative, D5 Outcomes, Crosswalk, QC sheets.
D3 (Cognitive assessments) absent: COGNITIVE_SCORE and COGNITIVE_CATEGORY not assigned instrument stat_route in domain lookup. Known gap acknowledged at Checkpoint 2; not a blocker.
Checkpoint 2 approved by Gerard 2026-09-10.

### Phase 18: Supplemental Raw Inventory

**Goal**: 2022 ID mismatch diagnostic + per-column gap-fill candidate table for raw supplement files; %let D15_APPROVED gate
**Depends on**: Phase 16
**Requirements**: RAW-08, RAW-09, RAW-10, RAW-11, RAW-12
**Plans**: 2 plans
Plans:
- [x] 18-01-PLAN.md -- Section A: 2022 ID diagnostic (qc/18_id_diagnostic.txt), reconstructed %import_csv/%import_xlsx macros (RAW-08, RAW-12)
- [x] 18-02-PLAN.md -- Section B: per-column gap counts for r1/r2/r3/r4/r5/r6/r9; r2 family rollups; qc/18_gap_candidates.txt; D15_APPROVED=0 gate (RAW-09-11)

**Details:**
PCM-D-15 gate: D15_APPROVED set to 1 in 00_config.sas (approved 2026-09-22) -- unblocks Phase 17 extension columns.
PCM-D-16 (2022 ID mismatch for r7/r8/r9): diagnosed as schema-change-era ID format; documented, not fixed.
All 4 UAT tests pass. Phase 18 is diagnostic-only; no g.* datasets modified; nothing under raw\ written.

---

## Milestone Summary

### Key Decisions

- PCM-D-01: Death variable naming -- keep separate; three source-specific columns retained (Price 2026-08-27)
- PCM-D-02: Frailty component encoding -- keep separate; char Y/N and numeric _Value both retained (Price 2026-08-27)
- PCM-D-03: ISO_SEV naming -- keep separate; md8 ISO_SEV is a TOTAL, not an average
- PCM-D-04: Emergent -- retain despite near-zero positives; caveat in data dictionary
- PCM-D-05: Analytic cohort restricted to INPATIENT+OBSERVATION (N=13,890); BMI-forces-restriction rationale; PCM-F-12 void (Gerard 2026-09-21)
- PCM-D-06: PRECEDE_Study_ID_1 in md6 -- drop; proven identical first (Phase 3)
- PCM-D-07: Age floor of 64 -- deferred; QC-05 floor stays at 18 as type-sanity guard
- PCM-D-08: 9 envelope-violating rows -- flag, do not null (rt_envelope_flag, MRG-05)
- PCM-D-09: QC-05 operative-interval ceilings -- dropped (QC-07); 8 assertions reduced to 5
- PCM-D-10: Negative rt_* durations -- retain-with-doc; only anchor-offset variables have expected negatives
- PCM-D-11: md3-owns missingness -- MRG-06 gap-fill for five variables from md8; one-way, zero disagreements
- PCM-D-12: %abort cancel return code = 3 on Windows batch; -sasuser WORK required in headless runs
- PCM-D-13: CPT1_CODE_LABEL -- keep separate; SSDI death family harmonized to h_ssdi_death (Phase 15)
- PCM-D-14: Pipeline-derived column rule -- in_md3 and eleven h_*_src columns carry no information and are dropped (HARM-07)
- PCM-D-15: Supplemental raw gap-fill -- approved 2026-09-22; D15_APPROVED=1 in 00_config.sas
- PCM-D-16: 2022 ID mismatch (r7/r8/r9) -- diagnosed as schema-change-era format; documented, not fixed

### Issues Resolved

- AMENDMENT-01 (operative timestamp integrity): negative intervals flagged-not-nulled (PREP-08); QC-06 unflagged assertion passes (QC-07); Phase 3->4->5 re-run chain clean
- PCM-F-17 WITHDRAWN: md3-owns cost claim was false; PCM-F-18 proved md8 donated five variables
- PCM-F-18: md3-owns DID discard data from md8 for five variables; resolved by MRG-06 gap-fill with zero disagreements
- PCM-F-19: PCM-F-12 (geriatric assessments restricted to admitted cohort) is void after MRG-06; PCM-D-05 re-decided on BMI evidence

### Issues Deferred

- D3 (Cognitive assessments) domain absent from Phase 17 workbook -- one-line DATALINES fix needed before next run
- PCM-D-07 (Age floor investigation) -- deferred as not pursuing; type-sanity guard at 18 retained
- Phase 14 VERIFICATION.md re-verified as passed after Phase 15 confirmed CSV prerequisite artifacts present
- 99_run_all.sas covers Phases 1-8 only; v1.1 programs (10b, 16b, 17, 18) not wired into single runner (expected scope)

### Technical Debt Incurred

- 04_merge.sas retains inline copy of ownership resolution rule (PCM-T-03 maintenance concern); updating requires Phase 4+5 re-run; deferred intentionally
- %macro assert_col defined twice in 06_reconcile.sas; both definitions are identical; SAS uses last definition silently
- Phase 14 VERIFICATION.md status was gaps_found (stale); re-verified and flipped to passed (commit eaf1c8e)
- DOMAIN_MAP_APPROVED=0 committed in 17_summary_stats_by_domain.sas; operationally fragile; requires manual override for each statistics run
- RAW-08 through RAW-12 not registered in REQUIREMENTS.md (Phase 18 requirements exist only in ROADMAP.md and RESEARCH.md)

---

_For current project status, see .planning/ROADMAP.md_
