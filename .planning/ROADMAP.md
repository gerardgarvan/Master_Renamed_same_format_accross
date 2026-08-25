# ROADMAP.md — PeCAN Master Dataset Integration

**Project:** PCM | **Milestone:** 1 | **Date:** 2026-08-25
**Granularity:** Standard (8 phases matching program structure 01–08)

---

## Phases

- [ ] **Phase 1: Source Verification & Freeze** — Assert PCM-F-01/F-02 in code; checksum and freeze all eight source files
- [ ] **Phase 2: Ownership Map** — Produce and commit variable→source ownership table; name all conflicts in DECISIONS.md
- [ ] **Phase 3: Per-Source Normalization** — Run eight prep programs; clear md8 NULL sentinel; log all conversion counts
- [ ] **Phase 4: Merge** — Produce `g.master_data_merged` (41,150 rows) via 1:1 merge onto md3 spine
- [ ] **Phase 5: Merge QC** — Run `05_qc_merge.sas`; assert row count, no truncation, no NULL strings, md8-only block counts
- [ ] **Phase 6: Variable Reconciliation** — Resolve death/frailty/ISO_SEV naming with Erin's sign-off; document all decisions
- [ ] **Phase 7: Cohort & Missingness** — Define analytic cohort; produce missingness profile; re-assert complete-case Ns
- [ ] **Phase 8: Documentation & Handoff** — Produce data dictionary; finalize DECISIONS.md; verify `99_run_all.sas` from clean session

---

## Phase Details

### Phase 1: Source Verification & Freeze
**Goal**: All eight source files are checksummed and their structural properties (unique IDs, spine completeness) are asserted in executable code — establishing an immutable freeze point before any mutation occurs
**Depends on**: Nothing
**Requirements**: SRC-01, SRC-02, SRC-03, SRC-04
**Success Criteria** (what must be TRUE):
  1. `01_verify_sources.sas` runs without error and writes per-source row/ID count reports to `qc/`
  2. The program emits an `abort` (or equivalent loud failure) if `PRECEDE_STUDY_ID` uniqueness fails for any source (PCM-F-01)
  3. The program emits an `abort` if md3 is not a complete superset of all IDs from md1, md2, md4–md8 (PCM-F-02)
  4. SHA-256 (or equivalent) checksums for all eight `.sas7bdat` files are written to a committed artifact in `qc/` at the start of every run
**Plans**: 2 plans
Plans:
- [ ] 01-01-PLAN.md — Setup, checksums (SRC-04), and per-source counts (SRC-03)
- [ ] 01-02-PLAN.md — Uniqueness (SRC-01) and md3-superset (SRC-02) assertions

### Phase 2: Ownership Map
**Goal**: Every variable in the pipeline has exactly one declared owner source, and every conflict is named — so no silent last-wins overwrite is possible in downstream merge steps
**Depends on**: Phase 1
**Requirements**: OWN-01, OWN-02, OWN-03, OWN-04
**Success Criteria** (what must be TRUE):
  1. `02_ownership.sas` runs and writes a variable→source ownership table to disk as a committed artifact
  2. The ownership table is reviewable before any merge program executes (artifact exists in `qc/` or `docs/`)
  3. Every variable name conflict across sources is explicitly listed in `docs/DECISIONS.md` (none are silently resolved in code)
  4. Coalesce-wanted variables (e.g., BMI, Race) are explicitly named in `02_ownership.sas` with disagreement-check assertions
**Plans**: TBD

### Phase 3: Per-Source Normalization
**Goal**: Each of the eight sources is independently cleaned, type-corrected, and ready for merge — with all exceptions reported before any conversion executes and all conversion counts logged
**Depends on**: Phase 2
**Requirements**: PREP-01, PREP-02, PREP-03, PREP-04, PREP-05, PREP-06
**Success Criteria** (what must be TRUE):
  1. Each of the eight prep programs (`03_prep_md1.sas` … `03_prep_md8.sas`) runs independently without error
  2. Each prep program writes an exception report to `qc/` before any type conversion; zero rows is the pass condition
  3. The md8 literal `NULL` sentinel is fully cleared and all md8 numeric fields are correctly typed in the md8 prep output
  4. The `PRECEDE_Study_ID_1` duplicate column is absent from the md6 prep output
  5. Every character variable in every prep output has an explicit `length` statement declared before any `merge`/`set`; conversion counts are written to `logs/`
**Plans**: TBD

### Phase 4: Merge
**Goal**: A single 1:1 merge onto the md3 spine produces `g.master_data_merged` with the correct row count, no overwrite ambiguity, and full provenance tracing
**Depends on**: Phase 3
**Requirements**: MRG-01, MRG-02, MRG-03, MRG-04
**Success Criteria** (what must be TRUE):
  1. `04_merge.sas` produces `g.master_data_merged` with exactly 41,150 rows and 41,150 distinct `PRECEDE_STUDY_ID` values
  2. Zero rows in the merged output have a blank `PRECEDE_STUDY_ID`
  3. Provenance flags `in_md1`–`in_md8` and `n_sources` are present in the output and their row counts match per-source ID counts from Phase 1
  4. md3 is declared first in the merge statement; the program contains no code path allowing last-wins overwrite for any single-owner variable
**Plans**: TBD

### Phase 5: Merge QC
**Goal**: An independent QC program asserts all structural guarantees of the merged file — row count, no truncation, no NULL sentinels, correct md8-only block population, and clinical-range validity
**Depends on**: Phase 4
**Requirements**: QC-01, QC-02, QC-03, QC-04, QC-05
**Success Criteria** (what must be TRUE):
  1. `05_qc_merge.sas` issues `abort` if row count is not exactly 41,150
  2. QC program asserts no character variable is narrower than its declared prep-stage width (no truncation)
  3. QC program asserts zero surviving literal `NULL` strings anywhere in `g.master_data_merged`
  4. QC program asserts the md8-only hemodynamic block is populated for exactly 22,473 rows and missing for the remaining 18,677
  5. QC program asserts type-converted variables (e.g., hemodynamic numerics) fall within expected clinical ranges; out-of-range rows abort or are written to an exception report
**Plans**: TBD

### Phase 6: Variable Reconciliation
**Goal**: Every contested variable naming and encoding decision is resolved, attributed to a named decision-maker, and recorded in DECISIONS.md — so no silent choices remain in the codebase
**Depends on**: Phase 5
**Requirements**: REC-01, REC-02, REC-03, REC-04, REC-05, REC-06
**Success Criteria** (what must be TRUE):
  1. `Death_Date_Y_N`, `IsDead_Y_N`, and `Death` are resolved to one canonical flag in the merged file; resolution carries Erin's sign-off recorded in DECISIONS.md (PCM-D-01)
  2. All five frailty component variables are resolved to one canonical encoding (char Y/N or numeric) consistently applied across all source contributions; Erin's sign-off recorded (PCM-D-02)
  3. `ISO_SEV` naming discrepancies across md4 and md8 are either resolved to a canonical name or explicitly deferred with written rationale in DECISIONS.md (PCM-D-03)
  4. `Emergent` usability decision (near-zero positives) and `Age_at_Encounter` floor investigation are each recorded in DECISIONS.md with attributed rationale (PCM-D-04, PCM-D-07)
  5. Every decision in PCM-D-01 through D-07 has an attributed author and date in DECISIONS.md; no resolution exists only as a comment in code
**Plans**: TBD

### Phase 7: Cohort & Missingness
**Goal**: An analytic cohort is defined and documented with stated inclusion/exclusion criteria, and all key-variable missingness counts are re-asserted as code assertions
**Depends on**: Phase 6
**Requirements**: COH-01, COH-02, COH-03, COH-04
**Success Criteria** (what must be TRUE):
  1. `07_cohort.sas` runs and produces a documented analytic cohort dataset with inclusion/exclusion criteria written as code comments and/or `%put` statements
  2. A missingness profile report for BMI, Cognitive_Score, Frailty_Score, and core covariates is written to `qc/` or `docs/`
  3. Complete-case Ns (BMI 12,726; Cognitive 20,540; Frailty 23,311; all-three 6,523) are re-asserted as `abort`-on-deviation assertions in `07_cohort.sas`
  4. The INPATIENT vs OBSERVATION restriction decision (PCM-D-05) is documented with rationale in DECISIONS.md
**Plans**: TBD

### Phase 8: Documentation & Handoff
**Goal**: A data dictionary covers every variable, DECISIONS.md is complete, and `99_run_all.sas` runs start-to-finish in a clean SAS session against read-only sources with no manual steps
**Depends on**: Phase 7
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04
**Success Criteria** (what must be TRUE):
  1. `08_dictionary.sas` produces `docs/DATA_DICTIONARY.xlsx` containing every variable with source, type, length, coverage percentage, and derivation rule; KEY sheet is the leftmost tab
  2. `docs/DECISIONS.md` shows PCM-D-01 through D-07 as resolved with attribution (no "Pending" entries remain)
  3. `99_run_all.sas` completes without error in a freshly opened SAS 9.4M8 session against read-only source files, producing all `qc/` and `docs/` artifacts with no manual intervention
  4. Git history contains at least one reviewable commit per phase (Phases 1–8), each with a log entry traceable to its numbered program
**Plans**: TBD

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Source Verification & Freeze | 0/2 | Not started | - |
| 2. Ownership Map | 0/? | Not started | - |
| 3. Per-Source Normalization | 0/? | Not started | - |
| 4. Merge | 0/? | Not started | - |
| 5. Merge QC | 0/? | Not started | - |
| 6. Variable Reconciliation | 0/? | Not started | - |
| 7. Cohort & Missingness | 0/? | Not started | - |
| 8. Documentation & Handoff | 0/? | Not started | - |

---

## Coverage

| Requirement | Phase | Status |
|-------------|-------|--------|
| SRC-01 | Phase 1 | Pending |
| SRC-02 | Phase 1 | Pending |
| SRC-03 | Phase 1 | Pending |
| SRC-04 | Phase 1 | Pending |
| OWN-01 | Phase 2 | Pending |
| OWN-02 | Phase 2 | Pending |
| OWN-03 | Phase 2 | Pending |
| OWN-04 | Phase 2 | Pending |
| PREP-01 | Phase 3 | Pending |
| PREP-02 | Phase 3 | Pending |
| PREP-03 | Phase 3 | Pending |
| PREP-04 | Phase 3 | Pending |
| PREP-05 | Phase 3 | Pending |
| PREP-06 | Phase 3 | Pending |
| MRG-01 | Phase 4 | Pending |
| MRG-02 | Phase 4 | Pending |
| MRG-03 | Phase 4 | Pending |
| MRG-04 | Phase 4 | Pending |
| QC-01 | Phase 5 | Pending |
| QC-02 | Phase 5 | Pending |
| QC-03 | Phase 5 | Pending |
| QC-04 | Phase 5 | Pending |
| QC-05 | Phase 5 | Pending |
| REC-01 | Phase 6 | Pending |
| REC-02 | Phase 6 | Pending |
| REC-03 | Phase 6 | Pending |
| REC-04 | Phase 6 | Pending |
| REC-05 | Phase 6 | Pending |
| REC-06 | Phase 6 | Pending |
| COH-01 | Phase 7 | Pending |
| COH-02 | Phase 7 | Pending |
| COH-03 | Phase 7 | Pending |
| COH-04 | Phase 7 | Pending |
| DOC-01 | Phase 8 | Pending |
| DOC-02 | Phase 8 | Pending |
| DOC-03 | Phase 8 | Pending |
| DOC-04 | Phase 8 | Pending |

**Total: 37/37 v1 requirements mapped. No orphans.**

---
*Last updated: 2026-08-25*
