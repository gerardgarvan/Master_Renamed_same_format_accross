# ROADMAP.md — PeCAN Master Dataset Integration

## Milestones

- v1 **PeCAN Master Dataset Integration Pipeline** -- Phases 1-8, 14-18 (shipped 2026-09-22)
  Archive: .planning/milestones/v1-ROADMAP.md
- v2.0 **pecan_ID + Raw Directory Inventory** -- Phases 19-21 (IN PROGRESS)

---

## Phase Progress

<details>
<summary>v1 PeCAN Master Dataset Integration Pipeline (Phases 1-18) -- SHIPPED 2026-09-22</summary>

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

### v2.0 pecan_ID + Raw Directory Inventory

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 19. Raw Directory Inventory | 0/? | Not started | - |
| 20. pecan_ID Derivation | 0/? | Not started | - |
| 21. Runner Wiring & D3 Fix | 0/? | Not started | - |

---

## Phases

- [ ] **Phase 19: Raw Directory Inventory** - Produce a complete, checksummed, variable-level inventory of every file under `raw`, output to `qc/19_raw_inventory.xlsx`
- [ ] **Phase 20: pecan_ID Derivation** - Build the patient-level linkage key from ENCRYPTED_MRN, assert cardinality, attach to pipeline outputs, test r7/r8/r9 linkage reach, and document decisions
- [ ] **Phase 21: Runner Wiring & D3 Fix** - Wire all programs into `99_run_all.sas` and fix the D3 cognitive domain in the Phase 17 workbook

---

## Phase Details

### Phase 19: Raw Directory Inventory
**Goal**: Users can inspect a complete, checksummed, variable-level profile of every file in the raw directory tree via a single deliverable workbook
**Depends on**: Nothing (standalone scan of read-only source tree)
**Requirements**: INV-01, INV-02, INV-03, INV-04, INV-05, INV-06, INV-07
**Success Criteria** (what must be TRUE):
  1. User can open `qc/19_raw_inventory.xlsx` and see every file under `raw` with its path, size, last-modified date, and SHA-256 checksum — no file is silently skipped
  2. User can see row count, column count, and per-sheet counts for every readable data file (sas7bdat, csv, xlsx/xls); unreadable files (pdf, docx, zip) are listed-not-profiled with their status explicit
  3. User can see variable name, type, length, label or original header, and percent missing for every variable in every readable data file
  4. User can see which files carry `PRECEDE_STUDY_ID`, `ENCRYPTED_MRN`, or `ENCRYPTED_ENCOUNTER` in the KEY_COLUMNS sheet, with all naming variants accounted for per PCM-T-12
  5. User can see which files are known (md1-md8 or Phase 18 supplemental set) and which are flagged NEW, and can confirm total files = profiled + listed-not-profiled with zero unknowns
**Plans**: TBD

### Phase 20: pecan_ID Derivation
**Goal**: Users can confirm that every patient with a valid ENCRYPTED_MRN has a stable, derivation-documented linkage key (pecan_ID) attached to pipeline outputs, with cardinality assertions passing and r7/r8/r9 linkage reach explicitly tested
**Depends on**: Phase 19 (PID-01 verifies checksum against INV-01 record; PID-07 uses INV-04 key-column flags)
**Requirements**: PID-01, PID-02, PID-03, PID-04, PID-05, PID-06, PID-07, PID-08
**Success Criteria** (what must be TRUE):
  1. User can confirm the pecan_ID source file is checksummed and its checksum matches the Phase 19 inventory record before any data is read from it
  2. User can view the source audit: blank MRN count, distinct MRN count, distinct PRECEDE_STUDY_ID count, and both-direction cardinalities; the program aborts if any PRECEDE_STUDY_ID maps to more than one ENCRYPTED_MRN
  3. User can confirm crosswalk `g.pecan_id_xwalk` is built per PCM-D-17 and is append-only (existing assignments are never renumbered on re-run)
  4. User can confirm pecan_ID is attached per PCM-D-18 without rewriting any existing dataset in place; row count unchanged in every file that receives pecan_ID; zero blank pecan_ID where ENCRYPTED_MRN is non-blank; zero patients gaining a second pecan_ID after attachment; column-count assertions and DATA_DICTIONARY.xlsx variable totals in every program PCM-D-18 touches are updated to reflect the added column
  5. User can see distinct pecan_ID counts and the encounter-per-patient distribution, and can see whether r7/r8/r9 raw files link on MRN where they previously failed on PRECEDE_STUDY_ID (PCM-D-16); pecan_ID appears in DATA_DICTIONARY.xlsx and PCM-D-17/D-18 are recorded in DECISIONS.md
**Plans**: TBD

### Phase 21: Runner Wiring & D3 Fix
**Goal**: Users can run the entire pipeline end-to-end from a single file and regenerate the domain statistics workbook with the D3 cognitive domain correctly populated
**Depends on**: RUN-01 depends on Phases 19 and 20 (programs 19 and 20 must exist before the runner can include them); FIX-01 depends only on Phase 17 (independent of Phases 19 and 20; can run earlier if needed)
**Requirements**: RUN-01, FIX-01
**Success Criteria** (what must be TRUE):
  1. User can execute `99_run_all.sas` in a clean SAS session and have programs 1–8, 10b, 16b, 17, 18, 19, and 20 run as separate batch invocations per PCM-C-05, in the order determined by PCM-D-18, with exit code 3 on any abort
  2. User can regenerate `qc/17_summary_stats_by_domain.xlsx` and see a D3 sheet containing both COGNITIVE_SCORE and COGNITIVE_CATEGORY under the instrument stat_route, applied only when DOMAIN_MAP_APPROVED gate is set
**Plans**: TBD
