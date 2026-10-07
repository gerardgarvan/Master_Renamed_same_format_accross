# Requirements: PeCAN Master Dataset Integration — v2.2

**Defined:** 2026-09-29
**Core Value:** A single `run_pipeline.cmd` that runs all SAS programs start-to-finish in a clean SAS session against read-only sources, producing `g.master_data_merged` (41,150 rows), `g.pcnr_harmonized`, and `g.pcnr_analytic_cohort` (13,890 rows), passing QC reports, a data dictionary, and a resolved DECISIONS.md — with no manual steps.

---

## v2.2 Requirements

Phase order: FIX/HARD → MD8 → LINK → GAP → NORM

### FIX — v2.1 Carry-Forward

- [ ] **FIX-03**: Program 23's contains-rule sentinel matching is cleaned up and the corresponding KEEP rows are removed from `docs/sentinel_decisions.csv` in the same change, so the decisions file stays consistent with the program logic
- [x] **FIX-04**: QC checks for `Cognitive_Score = 0` and `rt_RM_START_to_AN_START_mins = -9` are added to the appropriate program and pass on a clean pipeline run

### HARD — Source Directory Hardening

- [ ] **HARD-01**: Program 19 reads a stored baseline hash file from `docs/` and compares each md1-md8 sha256 against it (reusing the sha256 already recorded in `19_raw_files.csv`); any mismatch fails the run with an explicit error before any merge program executes; the baseline file is read with a DATA step `infile` (per PCM-T-16)
- [ ] **HARD-02**: The baseline hashes file is seeded from today's verified hashes in `19_raw_files.csv` and is updated only intentionally (for example, when an extract is added or replaced); program 19 never overwrites it automatically
- [x] **HARD-03**: DECISIONS.md records a documentation-only recommendation that the read-only file attribute is insufficient on a network share and that folder-level write and delete permission removal requires IT engagement

### MD8 — md8 Row-Count Correction

- [x] **MD8-01**: A SAS program counts md8 rows where any of the 68 columns is non-missing (treating literal `NULL` as missing) and compares the result against a count taken independently (from the `raw\` copy or the generating query), so the check can genuinely disagree; both counts are reported
- [x] **MD8-02**: DECISIONS.md and pipeline documentation are updated to reflect that the remaining rows beyond 22,473 are blank trailing rows (not lost data), and that the `raw\` copy is a row-count reference only — its MRNs use a different encryption and the two files are not interchangeable

### LINK — r7/r8/r9 Linkage Investigation (PCM-D-16)

- [x] **LINK-01**: `qc\20_linkage_reach.txt` is read and findings documented — confirm whether r7-r9 carry a character `ENCRYPTED_MRN` column
- [x] **LINK-02**: The 2018_2019 MRN/ENCOUNTER Crypto files and the same-named `raw\` files (2018_2019 X_MASTER/CPT_ROLLUP, 2018_2022 X_MASTER, ALL_AIM2) are examined; their crosswalk match rates (14.5%, 64%, and 41%) and their relationship to a second encryption scheme are documented as a finding regardless of outcome, so no later phase uses a `raw\` copy under the wrong encryption assumption
- [x] **LINK-03**: A determination is recorded as PCM-D-28: which encryption scheme r7-r9 use, and whether the 2022 mismatch (PCM-D-16, 9,215 IDs) is recoverable; any wiring is scoped to v2.3, not this milestone

### GAP — Gap-Fill Wiring (PCM-D-15)

- [x] **GAP-01**: Extension-column gap candidates from the D15_APPROVED list for r1-r6 are wired into the base merge; r7-r9 remain excluded pending PCM-D-28
- [ ] **GAP-02**: `docs/pcnr_name_map.csv` and `docs/sentinel_decisions.csv` are extended to cover all new columns through the same review gate as existing columns; column-count assertions in programs 23 and 24 (currently 175 and 163) are updated to match the new totals; program 25's row-count assertion (41,150) stays unchanged, consistent with GAP-03
- [x] **GAP-03**: After wiring, a pre-change copy of `g.master_data_merged` and `g.master_data_harmonized` is saved and compared with PROC COMPARE; both datasets remain at 41,150 rows and `g.pcnr_analytic_cohort` remains at 13,890; existing columns are byte-identical before and after; only the newly added columns differ

### NORM — Normalization and Type Conversion (pcnr datasets)

- [ ] **NORM-01**: A normalization map (an approved file analogous to `sentinel_decisions.csv`) is produced from the `23_case_variants.csv` report; if the report shows no columns needing normalization, the map is empty and no changes are made to the pcnr datasets for this item
- [ ] **NORM-02**: A new SAS step runs after program 24 and applies only the normalizations listed in the approved map, with its own change-accounting output (counts of changed cells per column) and an abort if any cell change falls outside the map
- [ ] **NORM-03**: Character columns approved for type conversion pass a round-trip test: converting to numeric and back reproduces the original string exactly; blank values and literal `NULL` count as missing and are not counted as failures; values with leading or trailing spaces fail the round trip; values longer than 15 significant digits fail (SAS loses precision beyond that); values like `007`, `1.50`, or `1E5` fail; only columns where every non-missing value passes are converted
- [ ] **NORM-04**: An approved whitelist (not an exclusion list) names the specific columns eligible for type conversion; KEY-role columns (`PRECEDE_STUDY_ID`, `ENCRYPTED_MRN`, `ENCRYPTED_ENCOUNTER`) are never on the whitelist regardless of content
- [ ] **NORM-05**: Program 24's column-type check, `docs/DATA_DICTIONARY.xlsx`, and `qc/PCNR_DICTIONARY.xlsx` are updated in the same phase to reflect any converted types; QC assertions confirm no values were lost or coerced

---

## Future Requirements (v2.3 candidates)

- r7-r9 MRN-based linkage wiring — contingent on PCM-D-28 confirming feasibility
- Program 17 repoint from `g.analytic_cohort` to `g.pcnr_analytic_cohort` (PCM-D-26) — pending Price review and domain map re-approval; run after NORM so Price reviews final pcnr values once

## Out of Scope

| Feature | Reason |
|---------|--------|
| Re-importing from source CSVs/XLSX | Validated lossless (PCM-F-08); no re-import needed |
| UTF-8 encoding repair | Damage confined to Base_Procedure_1, <=9 rows; flag only (PCM-C-01) |
| Statistical modelling | This project ends at the analysis-ready file |
| r7-r9 gap-fill wiring (this milestone) | Depends on PCM-D-28; deferred to v2.3 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FIX-03 | Phase 26 | Pending |
| FIX-04 | Phase 26 | Complete |
| HARD-01 | Phase 26 | Pending |
| HARD-02 | Phase 26 | Pending |
| HARD-03 | Phase 26 | Complete |
| MD8-01 | Phase 27 | Complete |
| MD8-02 | Phase 27 | Complete |
| LINK-01 | Phase 28 | Complete |
| LINK-02 | Phase 28 | Complete |
| LINK-03 | Phase 28 | Complete |
| GAP-01 | Phase 29 | Complete |
| GAP-02 | Phase 29 | Pending |
| GAP-03 | Phase 29 | Complete |
| NORM-01 | Phase 30 | Pending |
| NORM-02 | Phase 30 | Pending |
| NORM-03 | Phase 30 | Pending |
| NORM-04 | Phase 30 | Pending |
| NORM-05 | Phase 30 | Pending |

**Coverage:**
- v2.2 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0 ✓

---
*Requirements defined: 2026-09-29*
*Last updated: 2026-09-29 after v2.2 milestone kickoff*
