# REQUIREMENTS.md — PeCAN Master Dataset Integration

**Project:** PCM | **Version:** 1.0 | **Date:** 2026-08-25

---

## v1 Requirements

### Source Integrity

- [ ] **SRC-01** — User can verify that `PRECEDE_STUDY_ID` is strictly one row per patient in all eight source files (PCM-F-01 asserted in code)
- [ ] **SRC-02** — User can verify that `master_data_3` is a complete superset of all IDs from md1, md2, md4–md8 (PCM-F-02 asserted in code)
- [ ] **SRC-03** — User can view per-source row/ID counts written to `qc/` as committed artifacts
- [ ] **SRC-04** — User can confirm source files are checksummed at the start of every run (freeze point)

### Ownership Map

- [ ] **OWN-01** — User can run `02_ownership.sas` to produce a variable→source ownership table written to disk
- [ ] **OWN-02** — User can review the ownership map before any merge executes (committed artifact)
- [ ] **OWN-03** — User can see all variable name conflicts across sources explicitly named in `docs/DECISIONS.md`
- [ ] **OWN-04** — User can see coalesce-wanted variables explicitly named in `02_ownership.sas` with disagreement checks

### Per-Source Normalization

- [ ] **PREP-01** — User can run one prep program per source (`03_prep_md1.sas` … `03_prep_md8.sas`); each is independently runnable
- [ ] **PREP-02** — User can view an exception report before any type conversion executes; zero rows is the pass condition
- [ ] **PREP-03** — User can verify the md8 literal `NULL` sentinel is cleared and all md8 numerics are correctly typed
- [ ] **PREP-04** — User can verify the `PRECEDE_Study_ID_1` duplicate column in md6 is dropped
- [ ] **PREP-05** — User can see character variable widths declared via explicit `length` statements before every `merge`/`set` (PCM-R-02)
- [ ] **PREP-06** — User can see conversion counts logged to `logs/` for each prep program

### Merge

- [ ] **MRG-01** — User can run `04_merge.sas` to produce `g.master_data_merged` with exactly 41,150 rows and 41,150 distinct IDs
- [ ] **MRG-02** — User can verify zero blank `PRECEDE_STUDY_ID` values in the merged output
- [ ] **MRG-03** — User can verify provenance flags `in_md1`–`in_md8` and `n_sources` are present and match source row counts
- [ ] **MRG-04** — User can verify md3 is listed first (spine); no last-wins overwrite is possible for any variable

### Merge QC

- [ ] **QC-01** — User can run `05_qc_merge.sas` and see it fail loudly (`abort`) if row count deviates from 41,150
- [ ] **QC-02** — User can verify no character variable is truncated (max widths preserved from prep)
- [ ] **QC-03** — User can verify no surviving literal `NULL` strings anywhere in the merged file
- [ ] **QC-04** — User can verify the md8-only hemodynamic block is populated for exactly 22,473 rows
- [ ] **QC-05** — User can verify type-converted variables fall within expected clinical ranges

### Variable Reconciliation

- [ ] **REC-01** — User can see `Death_Date_Y_N`, `IsDead_Y_N`, and `Death` resolved to one canonical flag with Erin's sign-off (PCM-D-01)
- [ ] **REC-02** — User can see frailty component variables (`Feels_Exausted` etc.) resolved to one canonical encoding — char or numeric — for all five items (PCM-D-02)
- [ ] **REC-03** — User can see `ISO_SEV` naming discrepancies across md4 and md8 resolved or explicitly deferred with rationale (PCM-D-03)
- [ ] **REC-04** — User can see `Emergent` usability decision recorded in DECISIONS.md (PCM-D-04)
- [ ] **REC-05** — User can see `Age_at_Encounter` floor investigation recorded (PCM-D-07)
- [ ] **REC-06** — Every reconciliation decision is attributed in `docs/DECISIONS.md` (no silent code choices)

### Cohort & Missingness

- [ ] **COH-01** — User can run `07_cohort.sas` to produce a documented analytic cohort with inclusion/exclusion criteria stated
- [ ] **COH-02** — User can see a missingness profile for all key variables (BMI, Cognitive_Score, Frailty_Score, core covariates)
- [ ] **COH-03** — User can see complete-case Ns (BMI 12,726; Cognitive 20,540; Frailty 23,311; all-three 6,523) re-asserted as code assertions
- [ ] **COH-04** — User can see the INPATIENT/OBSERVATION restriction decision documented with rationale (PCM-D-05)

### Documentation & Handoff

- [ ] **DOC-01** — User can run `08_dictionary.sas` to produce `docs/DATA_DICTIONARY.xlsx` with every variable: source, type, length, coverage, derivation rule
- [ ] **DOC-02** — User can open `docs/DECISIONS.md` and see PCM-D-01 through D-07 resolved and attributed
- [ ] **DOC-03** — User can run `99_run_all.sas` in a clean SAS session against read-only sources and have all programs complete without manual steps
- [ ] **DOC-04** — User can verify git history shows each phase as a reviewable commit

---

## v2 Requirements (deferred)

- Statistical modelling or regression outputs — out of scope for this project
- Re-import from source CSV/XLSX — already validated (PCM-F-08), not needed
- INS abstract / dCDT pipeline — separate project

---

## Out of Scope

- Re-importing from source CSVs/XLSX — validated lossless (PCM-F-08); no re-import needed
- Statistical analysis — project ends at analysis-ready file
- INS abstract / dCDT pipeline — separate project
- UTF-8 encoding repair — encoding damage confined to ≤9 rows of `Base_Procedure_1`; flag only, do not re-encode (PCM-C-01 constraint)

---

## Traceability

| REQ-ID | Phase |
|--------|-------|
| SRC-01, SRC-02, SRC-03, SRC-04 | Phase 1 — Source Verification & Freeze |
| OWN-01, OWN-02, OWN-03, OWN-04 | Phase 2 — Ownership Map |
| PREP-01, PREP-02, PREP-03, PREP-04, PREP-05, PREP-06 | Phase 3 — Per-Source Normalization |
| MRG-01, MRG-02, MRG-03, MRG-04 | Phase 4 — Merge |
| QC-01, QC-02, QC-03, QC-04, QC-05 | Phase 5 — Merge QC |
| REC-01, REC-02, REC-03, REC-04, REC-05, REC-06 | Phase 6 — Variable Reconciliation |
| COH-01, COH-02, COH-03, COH-04 | Phase 7 — Cohort & Missingness |
| DOC-01, DOC-02, DOC-03, DOC-04 | Phase 8 — Documentation & Handoff |
