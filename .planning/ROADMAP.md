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
| 19. Raw Directory Inventory | 2/2 | Complete | 2026-09-23 |
| 20. pecan_ID Derivation | 0/2 | Planned | - |
| 21. Runner Wiring & D3 Fix | 2/2 | Complete    | 2026-09-24 |

---

## Phases

- [x] **Phase 19: Raw Directory Inventory** - Produce a complete, checksummed, variable-level inventory of every file under `raw`, output to `qc/19_raw_inventory.xlsx`
- [ ] **Phase 20: pecan_ID Derivation** - Build the patient-level linkage key from ENCRYPTED_MRN, assert cardinality, attach to pipeline outputs, test r7/r8/r9 linkage reach, and document decisions
- [x] **Phase 21: Runner Wiring & D3 Fix** - Wire all programs into `run_pipeline.cmd` and fix the D3 cognitive domain in the Phase 17 workbook

---

## Phase Details

### Phase 19: Raw Directory Inventory
**Goal**: Users can inspect a complete, checksummed, variable-level profile of every file in the raw directory tree via a single deliverable workbook
**Depends on**: Nothing (standalone scan of read-only source tree)
**Requirements**: INV-01, INV-02, INV-03, INV-04, INV-05, INV-06, INV-07
**Success Criteria** (what must be TRUE):
  1. User can open `qc/19_raw_inventory.xlsx` and see every file under `raw` with its path, size, last-modified date, and SHA-256 checksum — no file is silently skipped
  2. User can see row count, column count, and per-sheet counts for every readable data file (sas7bdat, csv, xlsx/xls); unreadable files (pdf, docx, zip) are listed-not-profiled with their status explicit; files whose import fails are read-failed with a fail_reason recorded
  3. User can see variable name, type, length, label or original header, pct_missing, and pct_sentinel (separate columns) for every variable in every readable data file
  4. User can see which files carry `PRECEDE_STUDY_ID`, `ENCRYPTED_MRN`, or `ENCRYPTED_ENCOUNTER` in the KEY_COLUMNS sheet, with all naming variants accounted for per PCM-T-12
  5. User can see which files are known (md1-md8 or Phase 18 supplemental set) and which are flagged NEW, and can confirm total files = profiled + listed-not-profiled + read-failed with zero unknowns
**Plans**: 2 plans
Plans:
- [x] 19-01-PLAN.md — Update REQUIREMENTS.md INV-07 + write complete sas/19_raw_dir_inventory.sas (all 14 sections)
- [x] 19-02-PLAN.md — Run program, fix errors, human-verify workbook (KEY leftmost, 7 sheets, UF blue) and CSV handoff

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
**Plans**: 2 plans
Plans:
- [ ] 20-01-PLAN.md — Amend program 19 (3 CSV handoffs) + 00_config backup path + write sas/20_pecan_id.sas (checksum, cross-check, cardinality, append-only crosswalk, linkage reach) + DECISIONS.md PCM-D-17/D-18 [Wave 1]
- [ ] 20-02-PLAN.md — Attach pecan_ID in 10b (join + PID-05 + 175 cols) and 16b (pass-through + PID-05 + PID-06 counts + 175 cols); add explicit pecan_ID row to 08_dictionary.sas + regenerate DATA_DICTIONARY.xlsx [Wave 2]

### Phase 21: Runner Wiring & D3 Fix
**Goal**: Users can run the entire pipeline end-to-end from a single batch driver and regenerate the domain statistics workbook with the D3 cognitive domain correctly populated
**Depends on**: RUN-01 depends on Phases 19 and 20 (programs 19 and 20 must exist before the runner can include them); FIX-01 depends only on Phase 17 (independent of Phases 19 and 20; can run earlier if needed)
**Requirements**: RUN-01, FIX-01
**Success Criteria** (what must be TRUE):
  1. User can execute `run_pipeline.cmd` and have programs 1-8, 19, 20, 10b, 16b, 17, and 18 run as separate sas.exe invocations per PCM-C-05, in that order, stopping on exit code >= 2
  2. User can regenerate `qc/17_summary_stats_by_domain.xlsx` and see a D3 sheet containing both COGNITIVE_SCORE and COGNITIVE_CATEGORY under the instrument stat_route, applied under the DOMAIN_MAP_APPROVED gate
**Plans**: 2 plans
Plans:
- [ ] 21-01-PLAN.md — Flip DOMAIN_MAP_APPROVED gate, redirect input to g.analytic_cohort with PROC COMPARE audit, add PECAN_ID DATALINES row, record PCM-D-19 and PCM-D-20 in DECISIONS.md [Wave 1, FIX-01]
- [x] 21-02-PLAN.md — Extend 00_config.sas with envlen(RUN_ALL) check; create run_pipeline.cmd with all 14 programs; update 99_run_all.sas header; human-verify program order and paths [Wave 2, RUN-01]
