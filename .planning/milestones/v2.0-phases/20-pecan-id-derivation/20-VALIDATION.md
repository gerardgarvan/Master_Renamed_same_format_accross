---
phase: 20
slug: pecan-id-derivation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-23
---

# Phase 20 — Validation Strategy

> Per-phase validation contract. This is a SAS pipeline phase — verification is through
> in-program assertion macros (%assert_eq, %assert_zero, %abort cancel) and QC file
> inspection. No automated test framework applies.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | SAS 9.4M8 assertion macros (`%assert_eq`, `%assert_zero`, `%abort cancel`) |
| **Config file** | `sas/00_config.sas` |
| **Quick run command** | Run the specific program in SAS batch; check log for ERROR/ABORT |
| **Full suite command** | Run programs in order: 20 → 10b → 16b → 08 → 17 → 18; inspect qc/ output files |
| **Estimated runtime** | ~5-15 minutes for full suite |

---

## Sampling Rate

- **After every task commit:** Review SAS log for ERROR/ABORT lines from the modified program
- **After every plan wave:** Run the full program affected by the wave and inspect assertion output
- **Before `/gsd:verify-work`:** All QC output files must exist and assertion counts must be zero

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Verification Type | Check Command | Status |
|---------|------|------|-------------|-------------------|---------------|--------|
| 20-01-01 | 01 | 1 | PID-01 | SAS assertion + file inspect | `qc/19_raw_files.csv` exists; certutil hash matches; program log has no ABORT | ⬜ pending |
| 20-01-02 | 01 | 1 | PID-02 | SAS log inspect | Log reports blank count, distinct MRN count, PRECEDE count, both cardinalities | ⬜ pending |
| 20-01-03 | 01 | 1 | PID-03 | SAS assertion | `%assert_eq` for PRECEDE→1 MRN fires and does not abort (all pass); manual verify cardinality output | ⬜ pending |
| 20-01-04 | 01 | 1 | PID-04 | SAS + file inspect | `g.pecan_id_xwalk` dataset exists; row count = distinct non-blank MRN count; no duplicate pecan_IDs | ⬜ pending |
| 20-01-05 | 01 | 1 | PID-04 | SAS assertion | Re-run program 20: backup comparison assertion passes; PROC APPEND adds 0 rows (no new MRNs on second run) | ⬜ pending |
| 20-01-06 | 01 | 1 | PID-07 | File inspect | `qc/20_linkage_reach.txt` exists; contains sections for all ENCRYPTED_MRN-tagged files; r7/r8/r9 explicit YES/NO line; exclusions list; type-mismatch block if applicable | ⬜ pending |
| 20-01-07 | 01 | 1 | PID-08 | File inspect | `docs/DECISIONS.md` contains PCM-D-17 and PCM-D-18 with Gerard Garvan attribution dated 2026-09-23 | ⬜ pending |
| 20-02-01 | 02 | 2 | PID-05 | SAS assertion | 10b log: row count assertion = 41150; zero blank pecan_ID where MRN non-blank; column count = 175 | ⬜ pending |
| 20-02-02 | 02 | 2 | PID-05 | SAS assertion | 16b log: row count assertion = 13890; zero blank pecan_ID; column count = 175; zero duplicate pecan_ID per PRECEDE | ⬜ pending |
| 20-02-03 | 02 | 2 | PID-06 | File inspect | `qc/16b_pecan_id_counts.txt` exists; no-pecan-ID row + 1/2/3+ distribution present; counts for both harmonized and cohort | ⬜ pending |
| 20-02-04 | 02 | 2 | PID-08 | File inspect | `08_dictionary.sas` contains pecan_ID explicit row in dict_final append block; re-running 08 produces DATA_DICTIONARY.xlsx with pecan_ID row | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ needs review*

---

## Wave 0 Requirements

No test framework to install. All verification is through SAS assertion macros already
present in the codebase (`sas/macros.sas` or inline in programs).

**Pre-conditions before any Wave 1 task:**
- [ ] Phase 19 plan amendment written and confirmed: `qc/19_raw_key_columns.csv`, `qc/19_raw_sheets.csv`, `qc/19_raw_variables_md3.csv` will be produced by program 19
- [ ] `qc/19_raw_files.csv` exists (confirms program 19 has run at least once)
- [ ] `g.master_data_merged` accessible in the `g` library (program 4 output)
- [ ] Crosswalk backup path macro defined in `sas/00_config.sas`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Crosswalk backup written to protected location | PID-04 (D-04) | File location is outside repo; cannot be inspected by automated means | Confirm dated backup file exists at `&xwalk_backup_path` after first run |
| r7/r8/r9 PCM-D-16 YES/NO result interpretation | PID-07 (D-24) | Gerard decides whether match rate is actionable for PCM-D-15 | Read `qc/20_linkage_reach.txt` r7/r8/r9 sections; record result in DECISIONS.md note |
| DATA_DICTIONARY.xlsx pecan_ID row correct | PID-08 (D-27) | xlsx content requires manual inspection | Open `docs/DATA_DICTIONARY.xlsx`; confirm pecan_ID row present with correct derivation note and dataset list |
| DECISIONS.md PCM-D-17/D-18 entries attributed | PID-08 (D-28) | Attribution requires human review | Open `docs/DECISIONS.md`; confirm Gerard Garvan, 2026-09-23 attribution |

---

## Validation Sign-Off

- [ ] All program tasks produce SAS log with no ERROR/ABORT lines
- [ ] All qc/ output files exist and contain expected content
- [ ] Crosswalk backup exists at protected path
- [ ] DATA_DICTIONARY.xlsx contains pecan_ID row
- [ ] DECISIONS.md contains PCM-D-17 and PCM-D-18
- [ ] r7/r8/r9 linkage result recorded for PCM-D-15 decision
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
