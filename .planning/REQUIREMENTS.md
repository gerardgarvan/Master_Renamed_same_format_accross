# REQUIREMENTS.md — PeCAN Master Dataset Integration

**Project:** PCM | **Version:** 1.0 | **Date:** 2026-08-25

---

## v1 Requirements

### Source Integrity

- [x] **SRC-01** — User can verify that `PRECEDE_STUDY_ID` is strictly one row per patient in all eight source files (PCM-F-01 asserted in code)
- [x] **SRC-02** — User can verify that `master_data_3` is a complete superset of all IDs from md1, md2, md4–md8 (PCM-F-02 asserted in code)
- [x] **SRC-03** — User can view per-source row/ID counts written to `qc/` as committed artifacts
- [x] **SRC-04** — User can confirm source files are checksummed at the start of every run (freeze point)

### Ownership Map

- [x] **OWN-01** — User can run `02_ownership.sas` to produce a variable→source ownership table written to disk
- [x] **OWN-02** — User can review the ownership map before any merge executes (committed artifact)
- [x] **OWN-03** — User can see all variable name conflicts across sources explicitly named in `docs/DECISIONS.md`
- [x] **OWN-04** — User can see coalesce-wanted variables explicitly named in `02_ownership.sas` with disagreement checks

### Per-Source Normalization

- [x] **PREP-01** — User can run one prep program per source (`03_prep_md1.sas` … `03_prep_md8.sas`); each is independently runnable
- [x] **PREP-02** — User can view an exception report before any type conversion executes; zero rows is the pass condition
- [x] **PREP-03** — User can verify the md8 literal `NULL` sentinel is cleared and all md8 numerics are correctly typed
- [x] **PREP-04** — User can verify the `PRECEDE_Study_ID_1` duplicate column in md6 is dropped
- [x] **PREP-05** — User can see character variable widths declared via explicit `length` statements before every `merge`/`set` (PCM-R-02)
- [x] **PREP-06** — User can see conversion counts logged to `logs/` for each prep program
- [x] **PREP-07** — User can verify `Base_Procedure_Code_1` is harmonized from NUM to CHAR $10 in md4, md5, md6, and md7; CHARACTER type asserted via `dictionary.columns` in each prep program

### Merge

- [x] **MRG-01** — User can run `04_merge.sas` to produce `g.master_data_merged` with exactly 41,150 rows and 41,150 distinct IDs
- [x] **MRG-02** — User can verify zero blank `PRECEDE_STUDY_ID` values in the merged output
- [x] **MRG-03** — User can verify provenance flags `in_md1`–`in_md8` and `n_sources` are present and match source row counts
- [x] **MRG-04** — User can verify md3 is listed first (spine); no last-wins overwrite is possible for any variable
- [x] **MRG-05** — User can verify `rt_envelope_flag` marks the rows where an operative sub-interval exceeds the room interval containing it, values retained rather than nulled (PCM-D-08)
- [x] **MRG-06** — User can verify md3's blanks are filled from md8 for the five variables where ownership was discarding data, one-way only (an md3 value is never overwritten), with the donor columns dropped so the column list still reconciles against the ownership map (PCM-D-11, PCM-F-18)

### Merge QC

- [x] **QC-01** — User can run `05_qc_merge.sas` and see it fail loudly (`abort`) if row count deviates from 41,150
- [x] **QC-02** — User can verify no character variable is truncated (max widths preserved from prep)
- [x] **QC-03** — User can verify no surviving literal `NULL` strings anywhere in the merged file
- [x] **QC-04** — User can verify the md8-only hemodynamic block is populated for exactly 22,473 rows
- [x] **QC-05** — User can verify type-converted variables fall within expected clinical ranges

### Variable Reconciliation

- [x] **REC-01** — User can see the `Death_Date_Y_N`, `IsDead_Y_N`, and `Death` naming discrepancy RESOLVED — the resolution (with Price's sign-off, 2026-08-27) is keep-separate with documented rationale: three source-specific columns are retained because nothing verifies they measure the same thing (PCM-D-01). "Resolved" means the decision is made and attributed, not that the columns are collapsed into one.
- [x] **REC-02** — User can see the frailty component variables (`Feels_Exausted` etc.) encoding discrepancy RESOLVED — the resolution (with Price's sign-off, 2026-08-27) is keep-separate: both the char Y/N and numeric `_Value` encodings are retained for all five items because the width signal ($3 md7 vs $1 md6) shows they are not interchangeable (PCM-D-02). "Resolved" means the decision is made and attributed, not that one canonical encoding is chosen.
- [x] **REC-03** — User can see `ISO_SEV` naming discrepancies across md4 and md8 resolved or explicitly deferred with rationale (PCM-D-03)
- [x] **REC-04** — User can see `Emergent` usability decision recorded in DECISIONS.md (PCM-D-04)
- [ ] **REC-05** — User can see `Age_at_Encounter` floor investigation recorded (PCM-D-07)
- [x] **REC-06** — Every reconciliation decision is attributed in `docs/DECISIONS.md` (no silent code choices)

### Cohort & Missingness

- [ ] **COH-01** — User can run `07_cohort.sas` to produce a documented analytic cohort with inclusion/exclusion criteria stated
- [ ] **COH-02** — User can see a missingness profile for all key variables (BMI, Cognitive_Score, Frailty_Score, core covariates)
- [ ] **COH-03** — User can see complete-case Ns (BMI 12,726; Cognitive 20,540; Frailty 23,311; all-three 6,523) re-asserted as code assertions
- [ ] **COH-04** — User can see the INPATIENT/OBSERVATION restriction decision documented with rationale (PCM-D-05)

### Documentation & Handoff

- [x] **DOC-01** — User can run `08_dictionary.sas` to produce `docs/DATA_DICTIONARY.xlsx` with every variable: source, type, length, coverage, derivation rule
- [ ] **DOC-02** — User can open `docs/DECISIONS.md` and see PCM-D-01 through D-07 resolved and attributed
- [ ] **DOC-03** — User can run `99_run_all.sas` in a clean SAS session against read-only sources and have all programs complete without manual steps
- [ ] **DOC-04** — User can verify git history shows each phase as a reviewable commit

---

## Milestone v1.1 Requirements — Variable Harmonization

**Phases 14-16** (renumbered from 9-11, which are taken by existing programs).

**Scope corrected 2026-08-29.** As first written, this milestone re-specified work that
Phases 9-11 had already delivered. The harmonized dataset exists; what does NOT exist is a
sweep on variable LABELS, and that is where the remaining risk lives. Requirements already
met are marked Complete with the program that met them, rather than deleted -- the record
should show they were considered, not that they were never raised.

### Already delivered (verified, not re-specified)

- [x] **HARM-01** — Every variable's presence across master_data_1..8 is inventoried.
      Delivered by Phase 2 (`qclib.ownership_map`, 163 variables with `sources_present`)
- [x] **HARM-05** — `g.master_data_harmonized` exists with one canonical column per
      confirmed concept. Delivered by `10b_concept_harmonize.sas` (11 `h_` columns).
      NOTE: the program is `10b_concept_harmonize.sas`, not `14_harmonize.sas`
- [x] **HARM-06** — Eleven alias columns dropped, each PROVEN redundant in the run itself
      (0 rows added, 0 disagreements) rather than assumed. `g.master_data_merged` verified
      unmodified: 176 columns before and after
- [x] **HARM-08** — Row count asserted at 41,150 in code, and the key asserted still unique
- [x] **SUMM-01** — Every variable summarised: n, n-missing, coverage %, distinct count;
      min/P25/median/mean/P75/max/std for numerics; observed lengths for characters.
      Delivered by `09_summary_stats.sas`
- [x] **SUMM-02** — Written to `docs/SUMMARY_STATS_HARMONIZED.xlsx`, not the log

### Open — the work this milestone actually adds

- [x] **HARM-02** — Canonical names are sourced from `docs/precede_dictionary.csv`, the
      310-variable PRECEDE data dictionary, read programmatically.
      **CORRECTED**: an earlier draft named `VARIABLE_RECTIFICATION.xlsx` as the crosswalk.
      That workbook is a REGISTER OF OPEN QUESTIONS -- its columns are Variable, Status,
      Priority, Issue, Evidence, Action. It holds no source-to-canonical name pairs and
      cannot serve as a mapping. The dictionary can, and already has: it settled
      `ISO_SEV_IntraOp_MAC_Average` as canonical and established that only the `_YN`
      comorbidity forms are documented
- [x] **HARM-03** — A LABEL-similarity sweep over all variable labels reports same-concept
      aliases whose NAMES share nothing. **This is the one genuinely new capability in the
      milestone.** Every sweep to date has matched on names, so a pair with unrelated names
      and near-identical labels is structurally invisible -- the class that hid
      `Cognitive_Category` until a full sweep ran
- [ ] **HARM-04** — Every canonical-name decision recorded in a committed artifact,
      attributed and dated. `concept_decisions.csv` is the existing pattern: a human
      confirms, the program applies exactly that and fails on anything unmapped
- [ ] **HARM-07** — A stated rule governs pipeline-derived columns (`in_md1`..`in_md8`,
      `n_sources`, `rt_envelope_flag`, `rt_*_neg`, `h_*_src`), enforced in code.
      Note `in_md3` is constant (md3 is the spine) and the eleven `h_*_src` columns each
      hold a single repeated value -- all twelve carry no information, and the rule should
      say so explicitly rather than carrying them by default
- [x] **HARM-09** — Concept groups the profiler has never seen are added and profiled:
      the SSDI death family (`SSDI_DEATH_DATE_Y_N`, `SSDI_DEATH_Y_N`, `SSDI_DEATH` --
      the same three-variant shape as the death flags already harmonised), and
      `CPT1_CLASS` / `CPT1_LABEL` (a code/label pair, both 159 distinct)
- [ ] **HARM-10** — `g.analytic_cohort` is rebuilt from `g.master_data_harmonized`.
      It is currently 176 columns, built in Phase 7 before harmonisation existed, so it
      carries the eleven dropped aliases and none of the `h_` columns. Any analysis using
      it gets pre-harmonisation encodings

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

| Requirement | Phase | Status |
|-------------|-------|--------|
| SRC-01 | Phase 1 — Source Verification & Freeze | Complete |
| SRC-02 | Phase 1 — Source Verification & Freeze | Complete |
| SRC-03 | Phase 1 — Source Verification & Freeze | Complete |
| SRC-04 | Phase 1 — Source Verification & Freeze | Complete |
| OWN-01 | Phase 2 — Ownership Map | Complete |
| OWN-02 | Phase 2 — Ownership Map | Complete |
| OWN-03 | Phase 2 — Ownership Map | Complete |
| OWN-04 | Phase 2 — Ownership Map | Complete |
| PREP-01 | Phase 3 — Per-Source Normalization | Complete |
| PREP-02 | Phase 3 — Per-Source Normalization | Complete |
| PREP-03 | Phase 3 — Per-Source Normalization | Complete |
| PREP-04 | Phase 3 — Per-Source Normalization | Complete |
| PREP-05 | Phase 3 — Per-Source Normalization | Complete |
| PREP-06 | Phase 3 — Per-Source Normalization | Complete |
| MRG-01 | Phase 4 — Merge | Complete |
| MRG-02 | Phase 4 — Merge | Complete |
| MRG-03 | Phase 4 — Merge | Complete |
| MRG-04 | Phase 4 — Merge | Complete |
| MRG-05 | Phase 4 — Merge | Complete |
| MRG-06 | Phase 4 — Merge | Complete |
| QC-01 | Phase 5 — Merge QC | Complete |
| QC-02 | Phase 5 — Merge QC | Complete |
| QC-03 | Phase 5 — Merge QC | Complete |
| QC-04 | Phase 5 — Merge QC | Complete |
| QC-05 | Phase 5 — Merge QC | Complete |
| REC-01 | Phase 6 — Variable Reconciliation | Complete |
| REC-02 | Phase 6 — Variable Reconciliation | Complete |
| REC-03 | Phase 6 — Variable Reconciliation | Complete |
| REC-04 | Phase 6 — Variable Reconciliation | Complete |
| REC-05 | Phase 6 — Variable Reconciliation | Pending |
| REC-06 | Phase 6 — Variable Reconciliation | Complete |
| COH-01 | Phase 7 — Cohort & Missingness | Pending |
| COH-02 | Phase 7 — Cohort & Missingness | Pending |
| COH-03 | Phase 7 — Cohort & Missingness | Pending |
| COH-04 | Phase 7 — Cohort & Missingness | Pending |
| DOC-01 | Phase 8 — Documentation & Handoff | Complete |
| DOC-02 | Phase 8 — Documentation & Handoff | Pending |
| DOC-03 | Phase 8 — Documentation & Handoff | Pending |
| DOC-04 | Phase 8 — Documentation & Handoff | Pending |
| HARM-01 | Phase 9 — Variable Harmonization | Pending |
| HARM-02 | Phase 9 — Variable Harmonization | Complete |
| HARM-03 | Phase 9 — Variable Harmonization | Complete |
| HARM-04 | Phase 9 — Variable Harmonization | Pending |
| HARM-05 | Phase 10 — Harmonized Dataset | Pending |
| HARM-06 | Phase 10 — Harmonized Dataset | Pending |
| HARM-07 | Phase 10 — Harmonized Dataset | Pending |
| HARM-08 | Phase 10 — Harmonized Dataset | Pending |
| SUMM-01 | Phase 11 — Summary Statistics | Pending |
| SUMM-02 | Phase 11 — Summary Statistics | Pending |
