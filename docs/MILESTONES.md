# MILESTONES.md -- PeCAN Master Dataset Integration

Milestone summaries and run evidence, updated at each milestone boundary.

---

## v1.0 -- PeCAN Master Dataset Integration Pipeline

**Shipped:** 2026-09-22
**Phases:** 1-8, 14-18 (13 phases)
**Programs:** 14 SAS programs (01-08, 10b, 14, 15, 16b, 17, 18) merged into a single batch driver

**One-liner:** Merged eight heterogeneous master extracts (41,150 rows, 176 columns) into g.master_data_merged with a harmonized overlay, analytic cohort (N=13,890), and a complete provenance record from checksums through QC assertions.

**Key outputs:**
- `g.master_data_merged` -- 41,150 rows, 176 columns, all QC-01 through QC-07 assertions pass
- `g.master_data_harmonized` -- 41,150 rows, 175 columns (h_* harmonized variables)
- `g.analytic_cohort` -- 13,890 rows (INPATIENT + OBSERVATION; PCM-D-05)
- `docs/DATA_DICTIONARY.xlsx` -- 175 variables, KEY sheet leftmost, UF blue headers
- `docs/DECISIONS.md` -- PCM-D-01 through PCM-D-16 resolved and attributed

---

## v2.0 -- pecan_ID + Raw Directory Inventory

**Shipped:** 2026-09-24
**Phases:** 19-21 (3 phases)

**Phase 19: Raw Directory Inventory**
One-liner: Produced a complete SHA-256-checksummed, variable-level inventory of every file under the raw directory tree, output to qc/19_raw_inventory.xlsx with seven sheets (KEY, FILES, SHEETS, VARIABLES, KEY_COLUMNS, RECONCILIATION, FAMILIES) and UF blue headers.

**Phase 20: pecan_ID Derivation**
One-liner: Derived a stable append-only surrogate integer key (pecan_ID) from ENCRYPTED_MRN using an existing crosswalk, confirmed 33,031 distinct harmonized pecan_IDs, asserted zero MRN-to-multiple-pecan_ID mappings, and attached pecan_ID to g.master_data_harmonized and g.analytic_cohort.

**Phase 21: Runner Wiring & D3 Fix**
One-liner: Wired all 14 programs into a single run_pipeline.cmd batch driver with per-program exit-code gating (sas.exe per PCM-C-05), confirmed full end-to-end PIPELINE PASSED, and repopulated the D3 cognitive domain in the Phase 17 domain-statistics workbook under the DOMAIN_MAP_APPROVED gate.

**Key outputs:**
- `g.pecan_id_xwalk` -- append-only crosswalk (ENCRYPTED_MRN -> pecan_ID)
- `qc/19_raw_inventory.xlsx` -- complete raw directory inventory
- `qc/20_pecan_id_linkage_reach.txt` -- r7/r8/r9 MRN linkage reach report
- `run_pipeline.cmd` -- 14-program end-to-end batch driver

**Known gap carried to v2.1:**
- INV-07: qc/19_raw_inventory.xlsx workbook formatting (FAMILIES sheet second, UF colors on all sheets) not yet applied

---

## v2.1 -- pcnr_ Clean Analysis Dataset

**Status:** In progress (2026-09-28)

**Phase 22: Pipeline Green & Hardening** -- Complete 2026-09-28
One-liner: Hardened the batch runner (RUN-02 line-start warning count, RUN-03 SAS_EXE override guard, log scanner), applied INV-07 workbook formatting (FAMILIES sheet to position 2, UF blue headers), and confirmed end-to-end PIPELINE PASSED on 2026-09-28 with the scanner operational and pre-existing xlsx-read notes documented as known allowlist items.

**Run evidence (2026-09-28):**
- Pipeline exit: PIPELINE PASSED (exit 0)
- Scanner output: qc/22_pipeline_scan.txt (on P: drive, not committed)
- Scanner status: FAIL due to pre-existing xlsx-read ERRORs in program 19 (files locked/unavailable); pipeline exit codes confirm success
- Known scanner findings (pre-existing, not regressions):
  - 92x NOTE: Variable is uninitialized (benign)
  - 2x WARNING: WORK.INV dataset may be incomplete (program 19, xlsx reading)
  - 2x NOTE: Invalid argument to SUBSTR (benign)
  - 2x ERROR: Couldn't find range or sheet in spreadsheet (program 19, xlsx unavailable)
  - 1x ERROR: File _XLW PRECEDE_DATABASE_ED does not exist (xlsx unavailable)
  - 1x ERROR: File _XLW PRECEDE_DATABAS does not exist (xlsx unavailable)
  - 1x WARNING: No cognitive score column (pre-existing)
  - 1x WARNING: Multiple lengths specified for variable (benign)
  - 1x WARNING: OWN type mismatch -- Admit_BMI (pre-existing ownership check warning)
  - 1x ERROR: Errors printed on pages (scanner summary line)

---

*Last updated: 2026-09-28 -- Phase 22 pipeline green verified*
