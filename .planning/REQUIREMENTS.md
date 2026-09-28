# REQUIREMENTS.md — PeCAN Master Dataset Integration

**Milestone:** v2.1 — pcnr_ Clean Analysis Dataset
**Defined:** 2026-09-24
**Prior milestones:** v1 (.planning/milestones/v1-REQUIREMENTS.md), v2.0 (.planning/milestones/v2.0-REQUIREMENTS.md)

## Milestone Goal

A new dataset, `g.pcnr_harmonized`, derived entirely from `g.master_data_harmonized`, in
which placeholder values such as `?` and `Unknown` are set to missing and every analysis
variable is renamed `pcnr_<original name>`. A matching `g.pcnr_analytic_cohort` follows
from it. The source dataset is never modified, and every recoded cell is counted and
traceable to a human-approved decision.

The pipeline must be green before new work is layered on it: the 2026-09-24 run stopped
at 16b, and the new programs run downstream of 16b.

---

## v2.1 Requirements

### Pipeline Green & Hardening (Phase 22)

- [x] **FIX-02**: 16b and 20 fixes from 2026-09-24 committed: `%put` semicolon (16b line 443), open-code `%local`/`%if` in 16b SECTION 7 replaced with `%sysfunc(ifc())`, `H_SSDI_DEATH` added to `%measure_h_cols` (loop bound from `countw`), `output; stop;` in the program 20 certutil step. Full `run_pipeline.cmd` run exits clean with `qc/16b_pecan_id_counts.txt` written.
- [x] **RUN-02**: `run_pipeline.cmd` warning count matches only log lines that BEGIN with `WARNING` (echoed source lines no longer counted). Verified: 10b reports 0.
- [x] **RUN-03**: `SAS_EXE` overridable without editing the committed file (environment variable or `%~dp0config.cmd` include), per the v2.0 retrospective lesson 2.
- [x] **INV-07**: `qc/19_raw_inventory.xlsx` formatting: UF blue (#0021A5) headers, KEY sheet leftmost with legend, FAMILIES sheet, sheet order enforced. (Carried from v2.0.)
- [x] **DOC-05**: Documentation drift closed: MILESTONES.md v2.0 "One-liner:" placeholders filled; STATE.md pecan_ID metrics populated from the PID-06 run; PROJECT.md trap list gains PCM-T-14 and PCM-T-15.

### Sentinel & Name Inventory (Phase 23)

- [x] **PCNR-01**: Every character column of `g.master_data_harmonized` is swept, not sampled (PCM-T-12). For each column, distinct values are normalized (upcase, strip, compress repeated blanks) and matched against a candidate sentinel pattern list (`?`, `??`, `UNKNOWN`, `UNK`, `N/A`, `NA`, `NOT DOCUMENTED`, `NOT RECORDED`, `NOT AVAILABLE`, `-`, `--`, `.`, `NULL`, and compound forms such as `UNKNOWN/NOT DOCUMENTED`). Output: `qc/23_sentinel_candidates.csv` (variable, raw value, normalized value, row count).
- [x] **PCNR-02**: Every numeric column is scanned for common numeric sentinels (-999, -99, -9, 99, 999, 9999, 99999, 777, 888) with counts reported, including the IS NOT MISSING guard (PCM-T-11). **Report only**; no numeric value is recoded unless PCM-D-24 approves it for that variable.
- [x] **PCNR-03**: Ambiguous values are reported separately for human review and never auto-classified: `None`, `Not applicable`, `Declined`, `Refused`, `Other`, `0`. (`None` can be a real answer; `Not applicable` can be structurally meaningful.)
- [x] **PCNR-04**: Case and whitespace variants of real categories (for example `Yes`/`YES`/`yes `) are reported in `qc/23_case_variants.csv`. **Report only**; they are not normalized in v2.1.
- [x] **PCNR-05**: Name map `docs/pcnr_name_map.csv` generated for every column: original name, pcnr name, original length, shortened flag. Names longer than 27 characters (32 minus the 5-character `pcnr_` prefix) are shortened by the PCM-D-23 rule. Asserted: every pcnr name is 32 characters or fewer, and names are unique case-insensitively.
- [x] **PCNR-06**: `docs/sentinel_decisions.csv` records a human decision for every candidate from PCNR-01..03: variable, raw value, action (`MISSING` / `KEEP`), rationale, decided_by, date. Gate `PCNR_APPROVED` in `00_config.sas`, default 0. Same pattern as `concept_decisions.csv`: the human confirms, the program applies exactly that, and it FAILS on any candidate with no decision.

### Build g.pcnr_harmonized (Phase 24)

- [x] **PCNR-07**: `g.pcnr_harmonized` built from `g.master_data_harmonized` only (no other input except the two approved CSVs). WORK-then-promote; `g.master_data_harmonized` is never written (PCM-T-02).
- [x] **PCNR-08**: Every `MISSING` decision in `sentinel_decisions.csv` applied by exact match on the raw value after the same normalization used in PCNR-01. Character columns keep their type and length; numeric recodes (if any are approved) become standard missing.
- [ ] **PCNR-09**: Columns renamed per `docs/pcnr_name_map.csv`; key columns handled per PCM-D-22. Each pcnr column keeps its original label and format; a blank original label is set to the original variable name so the lineage is visible in PROC CONTENTS.
- [ ] **PCNR-10**: Recode audit `qc/24_pcnr_recode_counts.csv`: variable × raw value × rows recoded, plus a per-variable total.
- [x] **PCNR-11**: Assertions (all abort on failure):
  - 41,150 rows; `PRECEDE_STUDY_ID` unique and identical in set to the source; `pecan_ID` identical row by row
  - column count equals the source column count (1:1 mapping, nothing dropped or added)
  - per variable: `n_missing_after = n_missing_before + n_recoded`, exactly
  - every cell NOT recoded is identical to its source cell (full comparison, not a sample)
  - zero remaining values that normalize to any `MISSING`-decided sentinel
  - type and length of every column unchanged
  - `g.master_data_harmonized` confirmed unchanged post-run (175 columns, 41,150 rows)

### Cohort, Dictionary & Wiring (Phase 25)

- [ ] **PCNR-12**: `g.pcnr_analytic_cohort` derived from `g.pcnr_harmonized` with the PCM-D-05 restriction (`pcnr_Patient_Type` in INPATIENT, OBSERVATION). Asserted: N = 13,890 and the `PRECEDE_STUDY_ID` set is identical to `g.analytic_cohort`.
- [ ] **PCNR-13**: Complete-case Ns for `pcnr_Admit_BMI`, `pcnr_Cognitive_Score`, `pcnr_Frailty_Score` reported side by side with the `g.analytic_cohort` values (12,726 / 7,252 / 8,150 within cohort). Any difference must equal that variable's recode count.
- [ ] **PCNR-14**: Data dictionary for the pcnr datasets: KEY sheet leftmost, UF blue headers, one row per variable with pcnr name, original name, label, type, length, values recoded, n recoded, coverage before and after. Either a PCNR sheet in `docs/DATA_DICTIONARY.xlsx` or a separate `docs/PCNR_DICTIONARY.xlsx` (decided in the Phase 25 plan).
- [ ] **PCNR-15**: New programs wired into `run_pipeline.cmd` after 16b and before 17, as separate sas.exe sessions (PCM-C-05). Full end-to-end run PASS.
- [ ] **PCNR-16**: Program 17 input resolved per PCM-D-26. If repointed to `g.pcnr_analytic_cohort`, its own sentinel recoding is reconciled against `sentinel_decisions.csv` so the rules live in one place.
- [ ] **PCNR-17**: `docs/DECISIONS.md` records PCM-D-21 through PCM-D-26 with attribution and date.

---

## Open Decisions (must be resolved before the plan that needs them executes)

| ID | Question | Proposed default | Needed by |
|----|----------|------------------|-----------|
| **PCM-D-21** | Which candidate values become missing, per variable | Decided row by row in `sentinel_decisions.csv`; no global rule | Phase 24 |
| **PCM-D-22** | Prefix scope: all non-key columns, or only columns that had a value recoded? | All non-key columns get `pcnr_` (a mix of prefixed and unprefixed columns would make untouched variables look like raw ones). Keys `PRECEDE_STUDY_ID`, `pecan_ID`, `ENCRYPTED_MRN`, `ENCRYPTED_ENCOUNTER` stay unprefixed so joins to other datasets work unchanged | Phase 23 |
| **PCM-D-23** | Shortening rule for names over 27 characters | Deterministic abbreviation list (same approach as the `cwg_` names in the INS abstract pipeline), human-approved in the name map; no silent truncation | Phase 23 |
| **PCM-D-24** | Are numeric sentinels in scope? | Only per-variable, with evidence from PCNR-02; none by default | Phase 24 |
| **PCM-D-25** | Preserve the reason when `Declined` / `Refused` / `Not applicable` are set to missing? | No companion columns in v2.1; `qc/24_pcnr_recode_counts.csv` keeps the per-value record. Revisit if an analysis needs informative missingness | Phase 24 |
| **PCM-D-26** | Should program 17 read `g.pcnr_analytic_cohort` instead of `g.analytic_cohort`? | Yes, after PCNR-12 passes | Phase 25 |

Per project practice, sign-off on analytic-facing decisions (D-21, D-24, D-25) goes to Price.

---

## Future Requirements (v2.2 candidates)

- **PCM-D-15 gap-fill wiring**: r1-r9 extension-column gap candidates into the base file. Because `g.pcnr_harmonized` is fully derived, it regenerates automatically once gap-fill changes the harmonized file.
- **r7/r8/r9 linkage resolution**: MRN-based linking for the 2022 files (PCM-D-16 follow-up).
- **Type conversion**: character columns that are entirely numeric after sentinel removal (candidates reported, not converted, in v2.1).
- **Category normalization**: case and whitespace variants from PCNR-04.

## Out of Scope (v2.1)

- Any change to `g.master_data_merged`, `g.master_data_harmonized`, or `g.analytic_cohort`
- Imputation of any kind: missing means missing
- Re-encoding `Base_Procedure_1` (PCM-C-01 stands)

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FIX-02 | 22 | Complete |
| RUN-02 | 22 | Complete |
| RUN-03 | 22 | Complete |
| INV-07 | 22 | Complete |
| DOC-05 | 22 | Complete |
| PCNR-01 | 23 | Complete |
| PCNR-02 | 23 | Complete |
| PCNR-03 | 23 | Complete |
| PCNR-04 | 23 | Complete |
| PCNR-05 | 23 | Complete |
| PCNR-06 | 23 | Complete |
| PCNR-07 | 24 | Complete |
| PCNR-08 | 24 | Complete |
| PCNR-09 | 24 | Pending |
| PCNR-10 | 24 | Pending |
| PCNR-11 | 24 | Complete |
| PCNR-12 | 25 | Pending |
| PCNR-13 | 25 | Pending |
| PCNR-14 | 25 | Pending |
| PCNR-15 | 25 | Pending |
| PCNR-16 | 25 | Pending |
| PCNR-17 | 25 | Pending |

**Coverage:** 22 requirements, 22 mapped, 0 unmapped.

Tick each checkbox at plan completion, not at milestone close (v2.0 retrospective lesson 1).

---
*Defined: 2026-09-24 for milestone v2.1*
