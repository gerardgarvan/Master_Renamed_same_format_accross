# v1 Requirements Archive — PeCAN Master Dataset Integration

**Archived:** 2026-09-22
**Milestone:** v1 — PeCAN Master Dataset Integration Pipeline (SHIPPED)
**Phases covered:** 1-8, 14-18

This file archives the full requirements record for milestone v1. All requirements marked
[x] were satisfied and verified. REC-05 was deliberately deferred (PCM-D-07 age floor
deferred as not pursuing). RAW-08 through RAW-12 (Phase 18) were registered in ROADMAP.md
and RESEARCH.md but not in the body requirements; they are complete and verified at code
level and noted here for traceability completeness.

For the live requirements document for the next milestone, see .planning/REQUIREMENTS.md.

---

# REQUIREMENTS.md — PeCAN Master Dataset Integration

**Project:** PCM | **Version:** 1.0 | **Date:** 2026-08-25

---

## v1 Requirements

### Source Integrity

- [x] **SRC-01** — User can verify that `PRECEDE_STUDY_ID` is strictly one row per patient in all eight source files (PCM-F-01 asserted in code)
- [x] **SRC-02** — User can verify that `master_data_3` is a complete superset of all IDs from md1, md2, md4-md8 (PCM-F-02 asserted in code)
- [x] **SRC-03** — User can view per-source row/ID counts written to `qc/` as committed artifacts
- [x] **SRC-04** — User can confirm source files are checksummed at the start of every run (freeze point)

### Ownership Map

- [x] **OWN-01** — User can run `02_ownership.sas` to produce a variable->source ownership table written to disk
- [x] **OWN-02** — User can review the ownership map before any merge executes (committed artifact)
- [x] **OWN-03** — User can see all variable name conflicts across sources explicitly named in `docs/DECISIONS.md`
- [x] **OWN-04** — User can see coalesce-wanted variables explicitly named in `02_ownership.sas` with disagreement checks

### Per-Source Normalization

- [x] **PREP-01** — User can run one prep program per source (`03_prep_md1.sas` through `03_prep_md8.sas`); each is independently runnable
- [x] **PREP-02** — User can view an exception report before any type conversion executes; zero rows is the pass condition
- [x] **PREP-03** — User can verify the md8 literal `NULL` sentinel is cleared and all md8 numerics are correctly typed
- [x] **PREP-04** — User can verify the `PRECEDE_Study_ID_1` duplicate column in md6 is dropped
- [x] **PREP-05** — User can see character variable widths declared via explicit `length` statements before every `merge`/`set` (PCM-R-02)
- [x] **PREP-06** — User can see conversion counts logged to `logs/` for each prep program
- [x] **PREP-07** — User can verify `Base_Procedure_Code_1` is harmonized from NUM to CHAR $10 in md4, md5, md6, and md7; CHARACTER type asserted via `dictionary.columns` in each prep program
- [x] **PREP-08** — Negative operative intervals nulled at source and asserted zero afterwards (AMENDMENT-01, 03-06)
- [x] **PREP-09** — Every other `rt_*` variable scanned for negatives; report written; nothing modified (AMENDMENT-01, 03-06)

### Merge

- [x] **MRG-01** — User can run `04_merge.sas` to produce `g.master_data_merged` with exactly 41,150 rows and 41,150 distinct IDs
- [x] **MRG-02** — User can verify zero blank `PRECEDE_STUDY_ID` values in the merged output
- [x] **MRG-03** — User can verify provenance flags `in_md1`-`in_md8` and `n_sources` are present and match source row counts
- [x] **MRG-04** — User can verify md3 is listed first (spine); no last-wins overwrite is possible for any variable
- [x] **MRG-05** — User can verify `rt_envelope_flag` marks the rows where an operative sub-interval exceeds the room interval containing it, values retained rather than nulled (PCM-D-08)
- [x] **MRG-06** — User can verify md3's blanks are filled from md8 for the five variables where ownership was discarding data, one-way only (an md3 value is never overwritten), with the donor columns dropped so the column list still reconciles against the ownership map (PCM-D-11, PCM-F-18)

### Merge QC

- [x] **QC-01** — User can run `05_qc_merge.sas` and see it fail loudly (`abort`) if row count deviates from 41,150
- [x] **QC-02** — User can verify no character variable is truncated (max widths preserved from prep)
- [x] **QC-03** — User can verify no surviving literal `NULL` strings anywhere in the merged file
- [x] **QC-04** — User can verify the md8-only hemodynamic block is populated only within md8 rows (monitored, not asserted at fixed N)
- [x] **QC-05** — User can verify type-converted variables fall within expected clinical ranges (5 assertions, calibrated to observed data)
- [x] **QC-06** — User can verify zero UNFLAGGED envelope violations (9 flagged rows reported; unflagged = 0 asserted) (AMENDMENT-01)
- [x] **QC-07** — Three inert operative-interval ceilings removed; QC-05 reduced from 8 to 5 assertions (AMENDMENT-01)

### Variable Reconciliation

- [x] **REC-01** — Death variable naming resolved: three source-specific columns retained (keep-separate, Price 2026-08-27) (PCM-D-01)
- [x] **REC-02** — Frailty component encoding resolved: char Y/N and numeric _Value both retained (keep-separate, Price 2026-08-27) (PCM-D-02)
- [x] **REC-03** — ISO_SEV naming discrepancies resolved: keep-separate; md8 ISO_SEV is a TOTAL not an average (PCM-D-03)
- [x] **REC-04** — Emergent usability decision recorded in DECISIONS.md (PCM-D-04)
- [ ] **REC-05** — Age_at_Encounter floor investigation recorded (PCM-D-07)
      **OUTCOME:** Deliberately deferred. PCM-D-07 resolution: "not pursuing." QC-05 floor stays at 18 as type-sanity guard. Age floor of 64 is an upstream inclusion criterion; investigating it is out of scope for this project.
- [x] **REC-06** — Every reconciliation decision is attributed in `docs/DECISIONS.md` (no silent code choices)

### Cohort & Missingness

- [x] **COH-01** — User can run `07_cohort.sas` to produce a documented analytic cohort with inclusion/exclusion criteria stated. Delivered: 07_cohort.sas, 453 lines, INPATIENT/OBSERVATION filter, 13,890 rows.
- [x] **COH-02** — User can see a missingness profile for all key variables. Delivered: pct_bmi_have/lack measured; qc/07_cohort_missingness.txt.
- [x] **COH-03** — User can see complete-case Ns re-asserted as code assertions. Delivered: assert_complete_case_n for BMI 12,726; Cognitive 20,540; Frailty 23,311; all-three 6,523.
- [x] **COH-04** — User can see the INPATIENT/OBSERVATION restriction decision documented with rationale. Delivered: PCM-D-05 entry in DECISIONS.md with BMI-forces-restriction rationale, five population-shift figures.

### Documentation & Handoff

- [x] **DOC-01** — User can run `08_dictionary.sas` to produce `docs/DATA_DICTIONARY.xlsx` with every variable: source, type, length, coverage, derivation rule. Delivered: 176 variables, KEY sheet leftmost, UF blue headers.
- [x] **DOC-02** — User can open `docs/DECISIONS.md` and see PCM-D-01 through D-14 resolved and attributed. Delivered: all 14 decisions resolved.
- [x] **DOC-03** — User can run `99_run_all.sas` in a clean SAS session against read-only sources and have all programs complete without manual steps. Delivered: clean run confirmed 2026-09-22.
- [x] **DOC-04** — User can verify git history shows each phase as a reviewable commit. Delivered: phase-01 through phase-08 commits present.

---

## Milestone v1.1 Requirements — Variable Harmonization

### Already delivered (verified, not re-specified)

- [x] **HARM-01** — Every variable's presence across master_data_1..8 is inventoried. Delivered by Phase 2 (qclib.ownership_map).
- [x] **HARM-05** — g.master_data_harmonized exists with one canonical column per confirmed concept. Delivered by 10b_concept_harmonize.sas (11 h_ columns).
- [x] **HARM-06** — Eleven alias columns dropped, each PROVEN redundant (0 rows added, 0 disagreements). g.master_data_merged verified unmodified: 176 columns.
- [x] **HARM-08** — Row count asserted at 41,150 in code, key still unique.
- [x] **SUMM-01** — Every variable summarised. Delivered by 09_summary_stats.sas.
- [x] **SUMM-02** — Written to docs/SUMMARY_STATS_HARMONIZED.xlsx.
- [x] **SUMM-DOMAIN-DISC** — Wave 0 discovery run, qc/17_discovery.txt. Delivered by 17_summary_stats_by_domain.sas SS.0-1.
- [x] **SUMM-DOMAIN-MAP** — g.var_domain_map with domain assignment and four guards. Delivered by 17_summary_stats_by_domain.sas SS.2-4.
- [x] **SUMM-DOMAIN-STATS** — Pooled and per-year statistics with small-cell suppression. Delivered by 17_summary_stats_by_domain.sas SS.5-9.
- [x] **SUMM-DOMAIN-BOOK** — qc/17_summary_stats_by_domain.xlsx with KEY leftmost, UF blue headers, D1-D5, Crosswalk, QC. Delivered by 17_summary_stats_by_domain.sas SS.10-11.

### New work added by this milestone

- [x] **HARM-02** — Canonical names sourced from docs/precede_dictionary.csv, read programmatically. Delivered by 14_label_similarity.sas.
- [x] **HARM-03** — LABEL-similarity sweep (COMPGED) over all variable labels. Delivered by 14_label_similarity.sas; docs/label_similarity_candidates.csv.
- [x] **HARM-04** — Every canonical-name decision in concept_decisions.csv, attributed and dated. Delivered by 15-01 (39 YES rows; PCM-D-13 attributed).
- [x] **HARM-07** — Pipeline-derived column rule enforced in code: in_md3 + eleven h_*_src dropped. Delivered by 15-02 (DROP= block + %assert_harm07). Rule recorded as PCM-D-14.
- [x] **HARM-09** — SSDI death family and CPT1_CLASS/CPT1_LABEL profiled. Delivered by 14_label_similarity.sas Section B.
- [x] **HARM-10** — g.analytic_cohort rebuilt from g.master_data_harmonized (174 cols, 13,890 rows). Delivered by 16b_cohort_rebuild.sas.

### Phase 18 Requirements (registered in ROADMAP.md, not formally in this document)

- [x] **RAW-08** — 2022 ID diagnostic written to qc/18_id_diagnostic.txt. Delivered by 18_supplemental_raw_gap.sas Section A.
- [x] **RAW-09** — Per-column gap counts (n_fillable, n_equal, n_conflict) for r1/r2/r3/r4/r5/r6/r9. Delivered by 18_supplemental_raw_gap.sas Section B.
- [x] **RAW-10** — r2 dCDT/LINUS family rollups with divider exclusion. Delivered by 18_supplemental_raw_gap.sas Section B.
- [x] **RAW-11** — qc/18_gap_candidates.txt written; D15_APPROVED gate committed. Delivered by 18_supplemental_raw_gap.sas Section B.
- [x] **RAW-12** — No g.* datasets modified; nothing under raw\ written. Verified by 18-VERIFICATION.md.

---

## v2 Requirements (deferred)

- Statistical modelling or regression outputs -- out of scope for this project
- Re-import from source CSV/XLSX -- already validated (PCM-F-08), not needed
- INS abstract / dCDT pipeline -- separate project

---

## Out of Scope

- Re-importing from source CSVs/XLSX -- validated lossless (PCM-F-08); no re-import needed
- Statistical analysis -- project ends at analysis-ready file
- INS abstract / dCDT pipeline -- separate project
- UTF-8 encoding repair -- encoding damage confined to <=9 rows of Base_Procedure_1; flag only, do not re-encode (PCM-C-01 constraint)
- Age floor investigation (PCM-D-07) -- upstream inclusion criterion; out of scope for this project (deliberate deferral)

---

## Traceability

| Requirement | Phase | Final Status |
|-------------|-------|--------------|
| SRC-01 | Phase 1 -- Source Verification & Freeze | Complete |
| SRC-02 | Phase 1 -- Source Verification & Freeze | Complete |
| SRC-03 | Phase 1 -- Source Verification & Freeze | Complete |
| SRC-04 | Phase 1 -- Source Verification & Freeze | Complete |
| OWN-01 | Phase 2 -- Ownership Map | Complete |
| OWN-02 | Phase 2 -- Ownership Map | Complete |
| OWN-03 | Phase 2 -- Ownership Map | Complete |
| OWN-04 | Phase 2 -- Ownership Map | Complete |
| PREP-01 | Phase 3 -- Per-Source Normalization | Complete |
| PREP-02 | Phase 3 -- Per-Source Normalization | Complete |
| PREP-03 | Phase 3 -- Per-Source Normalization | Complete |
| PREP-04 | Phase 3 -- Per-Source Normalization | Complete |
| PREP-05 | Phase 3 -- Per-Source Normalization | Complete |
| PREP-06 | Phase 3 -- Per-Source Normalization | Complete |
| PREP-07 | Phase 3 -- Per-Source Normalization | Complete |
| PREP-08 | Phase 3 -- Per-Source Normalization (03-06, AMENDMENT-01) | Complete |
| PREP-09 | Phase 3 -- Per-Source Normalization (03-06, AMENDMENT-01) | Complete |
| MRG-01 | Phase 4 -- Merge | Complete |
| MRG-02 | Phase 4 -- Merge | Complete |
| MRG-03 | Phase 4 -- Merge | Complete |
| MRG-04 | Phase 4 -- Merge | Complete |
| MRG-05 | Phase 4 -- Merge | Complete |
| MRG-06 | Phase 4 -- Merge | Complete |
| QC-01 | Phase 5 -- Merge QC | Complete |
| QC-02 | Phase 5 -- Merge QC | Complete |
| QC-03 | Phase 5 -- Merge QC | Complete |
| QC-04 | Phase 5 -- Merge QC | Complete |
| QC-05 | Phase 5 -- Merge QC | Complete |
| QC-06 | Phase 5 -- Merge QC (05-03, AMENDMENT-01) | Complete |
| QC-07 | Phase 5 -- Merge QC (05-03, AMENDMENT-01) | Complete |
| REC-01 | Phase 6 -- Variable Reconciliation | Complete |
| REC-02 | Phase 6 -- Variable Reconciliation | Complete |
| REC-03 | Phase 6 -- Variable Reconciliation | Complete |
| REC-04 | Phase 6 -- Variable Reconciliation | Complete |
| REC-05 | Phase 6 -- Variable Reconciliation | Deferred (by design -- PCM-D-07 not pursuing) |
| REC-06 | Phase 6 -- Variable Reconciliation | Complete |
| COH-01 | Phase 7 -- Cohort & Missingness | Complete |
| COH-02 | Phase 7 -- Cohort & Missingness | Complete |
| COH-03 | Phase 7 -- Cohort & Missingness | Complete |
| COH-04 | Phase 7 -- Cohort & Missingness | Complete |
| DOC-01 | Phase 8 -- Documentation & Handoff | Complete |
| DOC-02 | Phase 8 -- Documentation & Handoff | Complete |
| DOC-03 | Phase 8 -- Documentation & Handoff | Complete |
| DOC-04 | Phase 8 -- Documentation & Handoff | Complete |
| HARM-01 | Phase 2 -- Ownership Map | Complete |
| HARM-02 | Phase 14 -- Label Similarity Sweep | Complete |
| HARM-03 | Phase 14 -- Label Similarity Sweep | Complete |
| HARM-04 | Phase 15 -- Extend Harmonized Dataset | Complete |
| HARM-05 | Phase 10 -- Harmonized Dataset (pre-audit) | Complete |
| HARM-06 | Phase 10 -- Harmonized Dataset (pre-audit) | Complete |
| HARM-07 | Phase 15 -- Extend Harmonized Dataset | Complete |
| HARM-08 | Phase 10 -- Harmonized Dataset (pre-audit) | Complete |
| HARM-09 | Phase 14 -- Label Similarity Sweep | Complete |
| HARM-10 | Phase 16 -- Rebuild the Analytic Cohort | Complete |
| SUMM-01 | Phase 9 -- Summary Statistics (pre-audit) | Complete |
| SUMM-02 | Phase 9 -- Summary Statistics (pre-audit) | Complete |
| SUMM-DOMAIN-DISC | Phase 17 -- Summary Stats by Domain | Complete |
| SUMM-DOMAIN-MAP | Phase 17 -- Summary Stats by Domain | Complete |
| SUMM-DOMAIN-STATS | Phase 17 -- Summary Stats by Domain | Complete |
| SUMM-DOMAIN-BOOK | Phase 17 -- Summary Stats by Domain | Complete |
| RAW-08 | Phase 18 -- Supplemental Raw Inventory | Complete |
| RAW-09 | Phase 18 -- Supplemental Raw Inventory | Complete |
| RAW-10 | Phase 18 -- Supplemental Raw Inventory | Complete |
| RAW-11 | Phase 18 -- Supplemental Raw Inventory | Complete |
| RAW-12 | Phase 18 -- Supplemental Raw Inventory | Complete |
