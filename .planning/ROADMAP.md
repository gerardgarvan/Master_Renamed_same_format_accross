# ROADMAP.md — PeCAN Master Dataset Integration

## Milestones

- ✅ **v1** — PeCAN Master Dataset Integration Pipeline (Phases 1-8, 14-18) — shipped 2026-09-22
  Archive: .planning/milestones/v1-ROADMAP.md
- ✅ **v2.0** — pecan_ID + Raw Directory Inventory (Phases 19-21) — shipped 2026-09-24
  Archive: .planning/milestones/v2.0-ROADMAP.md
- ✅ **v2.1** — pcnr_ Clean Analysis Dataset (Phases 22-25) — shipped 2026-09-29
  Archive: .planning/milestones/v2.1-ROADMAP.md
- 🔲 **v2.2** — pcnr Normalization, Gap-Fill & Linkage (Phases 26-30) — in progress

---

## Phases

### v2.2 pcnr Normalization, Gap-Fill & Linkage

- [ ] **Phase 26: v2.1 Carry-Forward & Source Hardening** — Fix sentinel logic, add QC checks, guard md1-md8 source files with hash verification
- [ ] **Phase 27: md8 Row-Count Correction** — Independent dual count of non-missing md8 rows; both counts reported; documentation updated to the verified figure
- [ ] **Phase 28: r7/r8/r9 Linkage Investigation** — Read linkage reach report, examine crypto file match rates, record PCM-D-28 determination
- [ ] **Phase 29: Gap-Fill Wiring (r1-r6)** — Wire D15-approved extension columns into base merge, extend pcnr name map and sentinel map, verify identity of existing columns
- [ ] **Phase 30: pcnr Normalization & Type Conversion** — Produce approved normalization map, apply case/whitespace changes, convert approved numeric-content columns, update dictionaries

---

## Phase Details

### Phase 26: v2.1 Carry-Forward & Source Hardening

**Goal**: The pipeline is clean (sentinel logic consistent, two missing QC assertions added) and md1-md8 source files are protected by a stored-baseline hash guard so any accidental modification fails the run immediately.

**Depends on**: Phase 25 (all v2.1 deliverables complete)

**Requirements**: FIX-03, FIX-04, HARD-01, HARD-02, HARD-03

**Success Criteria** (what must be TRUE):
  1. Program 23's sentinel matching uses only the approved contains/exact rule and the corresponding rows have been removed from `docs/sentinel_decisions.csv`; the two artifacts are consistent when inspected side-by-side
  2. A clean end-to-end pipeline run passes two new QC assertions: `Cognitive_Score = 0` rows detected and `rt_RM_START_to_AN_START_mins = -9` rows detected (or both asserted to be zero)
  3. Program 19 reads a baseline hash file from `docs/` with a DATA step `infile` statement and emits an explicit error — stopping the pipeline before any merge program — when any md1-md8 sha256 does not match the stored value
  4. The baseline hashes file in `docs/` contains today's verified sha256 values from `19_raw_files.csv` and is never overwritten automatically by program 19
  5. `docs/DECISIONS.md` contains a documentation-only note explaining that the read-only file attribute is insufficient on a network share and that full protection requires IT engagement

**Plans**: 4 plans

Plans:
- [x] 26-01-PLAN.md — FIX-03: CONTAINS sentinel audit + narrowing (human checkpoint) + sentinel_decisions.csv reconcile
- [x] 26-02-PLAN.md — FIX-04: two QC assertions in program 24 (Cognitive_Score=0, rt sentinel -9)
- [x] 26-03-PLAN.md — HARD-01/02: 19b seed program + program 19 sha256 hash guard + baseline CSV
- [x] 26-04-PLAN.md — HARD-03: PCM-D-29 documentation note on network-share protection

---

### Phase 27: md8 Row-Count Correction

**Goal**: Independent dual count of non-missing md8 rows; both counts reported; documentation updated to the verified figure, with the raw\ copy's encryption difference noted explicitly.

**Depends on**: Phase 26

**Requirements**: MD8-01, MD8-02

**Success Criteria** (what must be TRUE):
  1. A SAS program reports two independently derived counts of md8 non-missing rows (one from the pipeline dataset treating literal `NULL` as missing, one from the `raw\` copy or the generating query) and both counts agree at 22,473
  2. The program's output log shows both counts side-by-side and aborts with an explicit message if they disagree
  3. `docs/DECISIONS.md` and any pipeline documentation that previously referenced an incorrect md8 row count have been updated to state that rows beyond 22,473 are blank trailing rows, not lost data
  4. The documentation explicitly notes that the `raw\` copy serves as a row-count reference only — its MRNs use a different encryption and the two files are not interchangeable

**Plans**: 2 plans

Plans:
- [x] 27-01-PLAN.md — MD8-01: standalone dual-count verification program (27_md8_count.sas) + three checks + qc/27_md8_count.csv
- [x] 27-02-PLAN.md — MD8-02: permanent all-missing-row drop + 22,473 assertion in 03_prep_md8.sas; PCM-D-31; 00_ownership_rule comment; STATE.md metric

---

### Phase 28: r7/r8/r9 Linkage Investigation

**Goal**: The encryption scheme used by r7-r9 is identified and documented as PCM-D-28, and the match-rate evidence from the 2018-2022 crypto files is recorded so no future phase applies the wrong encryption assumption to any raw\ copy.

**Depends on**: Phase 27

**Requirements**: LINK-01, LINK-02, LINK-03

**Success Criteria** (what must be TRUE):
  1. `qc/20_linkage_reach.txt` has been read and a written finding states whether r7, r8, and r9 carry a character `ENCRYPTED_MRN` column
  2. The crosswalk match rates for the 2018_2019 MRN/ENCOUNTER Crypto files and the same-named `raw\` files (reported as 14.5%, 64%, and 41%) are documented with a clear statement of what encryption scheme each file uses and whether they are interchangeable with the pipeline crosswalk
  3. PCM-D-28 is recorded in `docs/DECISIONS.md` stating which encryption scheme r7-r9 use, whether the 9,215-ID mismatch diagnosed in PCM-D-16 is recoverable via MRN linking, and what (if any) work is scoped to v2.3

**Plans**: 2 plans

Plans:
- [ ] 28-01-PLAN.md — LINK-01/LINK-02: read 20_linkage_reach.txt + provenance search; build standalone sas/28_linkage_investigation.sas (3 blocks)
- [ ] 28-02-PLAN.md — LINK-03: run program, review qc/28_linkage_investigation.csv, record PCM-D-28 in docs/DECISIONS.md

---

### Phase 29: Gap-Fill Wiring (r1-r6)

**Goal**: Extension columns approved under PCM-D-15 for r1-r6 are wired into the base merge, covered by the pcnr name map and sentinel gate, and verified not to alter any existing row or column.

**Depends on**: Phase 28 (PCM-D-28 must be recorded before scope of r7-r9 exclusion is confirmed)

**Requirements**: GAP-01, GAP-02, GAP-03

**Success Criteria** (what must be TRUE):
  1. All D15_APPROVED extension columns for r1-r6 appear in `g.master_data_merged`; r7-r9 extension columns are explicitly excluded with a reference to PCM-D-28
  2. Every newly added column has an entry in `docs/pcnr_name_map.csv` and `docs/sentinel_decisions.csv` with PCNR_APPROVED set; column-count assertions in programs 23 and 24 reflect the updated totals
  3. A PROC COMPARE between the pre-change and post-change copies of `g.master_data_merged` and `g.master_data_harmonized` reports zero differences on all pre-existing columns; both datasets remain at 41,150 rows
  4. `g.pcnr_analytic_cohort` remains at 13,890 rows after pipeline re-run; the row-count assertion in program 25 passes without modification

**Plans**: TBD

---

### Phase 30: pcnr Normalization & Type Conversion

**Goal**: Category levels in pcnr datasets are case/whitespace-normalized per an approved map, and character columns that are entirely numeric after sentinel removal are type-converted per an approved whitelist — with dictionaries updated to match.

**Depends on**: Phase 29 (final column set must be known before normalization map is finalized)

**Requirements**: NORM-01, NORM-02, NORM-03, NORM-04, NORM-05

**Success Criteria** (what must be TRUE):
  1. A normalization map file (analogous to `sentinel_decisions.csv`) is produced from `23_case_variants.csv`; if no columns need normalization the map is empty and no pcnr data changes are made for this item
  2. A SAS step runs after program 24 and applies only the normalizations listed in the approved map; it outputs a per-column changed-cell count and aborts if any cell change falls outside the map
  3. A type-conversion whitelist exists naming specific approved columns; `PRECEDE_STUDY_ID`, `ENCRYPTED_MRN`, and `ENCRYPTED_ENCOUNTER` are absent from it; every column on the whitelist has passed the round-trip test (convert to numeric and back reproduces the original string exactly; values with leading/trailing spaces, precision beyond 15 significant digits, or formatted strings such as `007` or `1.50` are absent or treated as failures)
  4. Program 24's column-type assertions, `docs/DATA_DICTIONARY.xlsx`, and `qc/PCNR_DICTIONARY.xlsx` reflect the types of any converted columns; QC output confirms no values were lost or coerced during conversion

**Plans**: TBD

---

## Phase Progress

<details>
<summary>✅ v1 PeCAN Master Dataset Integration Pipeline (Phases 1-8, 14-18) — SHIPPED 2026-09-22</summary>

| Phase | Name | Plans Complete | Status | Completed |
|-------|------|---------------|--------|-----------|
| 1 | Source Verification & Freeze | 2/2 | Complete | 2026-08-26 |
| 2 | Ownership Map | 2/2 | Complete | 2026-08-26 |
| 3 | Per-Source Normalization | 6/6 | Complete | 2026-09-14 |
| 4 | Merge | 2/2 | Complete | 2026-08-27 |
| 5 | Merge QC | 3/3 | Complete | 2026-09-14 |
| 6 | Variable Reconciliation | 3/3 | Complete | 2026-09-14 |
| 7 | Cohort & Missingness | 2/2 | Complete | 2026-09-22 |
| 8 | Documentation & Handoff | 3/3 | Complete | 2026-09-22 |
| 14 | Label-Similarity Sweep | 2/2 | Complete | 2026-09-21 |
| 15 | Extend the Harmonized Dataset | 2/2 | Complete | 2026-09-21 |
| 16 | Rebuild the Analytic Cohort | 2/2 | Complete | 2026-09-22 |
| 17 | Summary Stats by Domain | 4/4 | Complete | 2026-09-22 |
| 18 | Supplemental Raw Inventory | 2/2 | Complete | 2026-09-22 |

</details>

<details>
<summary>✅ v2.0 pecan_ID + Raw Directory Inventory (Phases 19-21) — SHIPPED 2026-09-24</summary>

| Phase | Name | Plans Complete | Status | Completed |
|-------|------|----------------|--------|-----------|
| 19 | Raw Directory Inventory | 2/2 | Complete | 2026-09-23 |
| 20 | pecan_ID Derivation | 2/2 | Complete | 2026-09-23 |
| 21 | Runner Wiring & D3 Fix | 2/2 | Complete | 2026-09-24 |

</details>

<details>
<summary>✅ v2.1 pcnr_ Clean Analysis Dataset (Phases 22-25) — SHIPPED 2026-09-29</summary>

| Phase | Name | Plans Complete | Status | Completed |
|-------|------|----------------|--------|-----------|
| 22 | Pipeline Green & Hardening | 3/3 | Complete | 2026-09-28 |
| 23 | Sentinel & Name Inventory | 3/3 | Complete | 2026-09-28 |
| 24 | Build g.pcnr_harmonized | 3/3 | Complete | 2026-09-29 |
| 25 | pcnr Cohort, Dictionary & Wiring | 3/3 | Complete | 2026-09-29 |

</details>

### v2.2 pcnr Normalization, Gap-Fill & Linkage

| Phase | Name | Plans Complete | Status | Completed |
|-------|------|----------------|--------|-----------|
| 26 | v2.1 Carry-Forward & Source Hardening | 4/4 | Complete   | 2026-09-30 |
| 27 | md8 Row-Count Correction | 2/2 | Complete    | 2026-10-07 |
| 28 | r7/r8/r9 Linkage Investigation | 0/2 | Planned | - |
| 29 | Gap-Fill Wiring (r1-r6) | 0/? | Not started | - |
| 30 | pcnr Normalization & Type Conversion | 0/? | Not started | - |

---

*Last updated: 2026-09-29 — v2.2 roadmap defined (Phases 26-30)*
