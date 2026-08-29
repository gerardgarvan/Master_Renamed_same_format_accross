# PROJECT.md — PeCAN Master Dataset Integration

**Project ID:** PCM
**Owner:** Gerard Garvan (ggarvan)
**Working folder:** `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross`
**Repo:** local disk (see PCM-C-04 — do **not** put the git repo on the P: drive)
**Status:** Phase 1 not started
**Supersedes:** all ad-hoc `master_data_*` merge/stack/dedup code written before this document

---

## What This Is

A reproducible, provenance-tracked SAS pipeline that merges eight heterogeneous master
extracts (`master_data_1..8.sas7bdat`) into one analysis-ready patient-level dataset.
Every type conversion, name reconciliation, and row-count change is traceable to a
numbered SAS program in version control.

## Core Value

A single `99_run_all.sas` that runs start-to-finish in a clean SAS session against
read-only sources, producing `g.master_data_merged` (41,150 rows), passing QC reports,
a data dictionary, and a resolved DECISIONS.md — with no manual steps.

## Context

The prior work established the target structure but was done interactively, with no
reproducible artifact and at least two destructive incidents (stack-dedup trap; PROC SQL
UPDATE truncation). This project restarts from source with empirical findings preserved
as requirements. The eight files share one patient population — the correct operation is
a 1:1 merge onto the md3 spine, not a stack.

---

## Requirements

### Validated

- ✓ `PRECEDE_STUDY_ID` is strictly one row per patient in all eight files — existing
- ✓ `master_data_3` (41,150 rows, 124 vars) is a complete superset of all other IDs — existing
- ✓ md1 and md3 agree exactly on Race, Sex, Age_at_Encounter, Admit_BMI (14,778 shared rows) — existing
- ✓ md8 stores literal `NULL` where others store blank; forced its numerics to CHAR $4/$11 — existing
- ✓ Coalescing BMI from other sources recovers nothing; 28,424 missing are missing at source — existing
- ✓ `PRECEDE_Study_ID_1` in md6 is a duplicate column identical to `PRECEDE_STUDY_ID` — existing
- ✓ Encoding damage confined to `Base_Procedure_1`, ≤9 rows per file — existing

### Active

- [ ] Source files checksummed and frozen; PCM-F-01 and F-02 re-asserted in code
- [ ] Variable ownership map produced, reviewed, and committed; conflicts named in DECISIONS.md
- [ ] Eight prep programs with clean exception reports; NULL sentinel cleared; conversion counts logged
- [ ] `g.master_data_merged` — 41,150 rows, 41,150 distinct IDs, provenance flags present, no truncation
- [ ] Merge QC: no surviving NULL strings; md8-OWNED variables non-missing only within md8 rows (QC-04 — the old "exactly 22,473" target was wrong, within-md8 population varies from ~16% to 100% by design); type-converted vars in range
- [ ] Death and frailty naming resolved with Price's sign-off (PCM-D-01, PCM-D-02)
- [ ] Analytic cohort defined; missingness profile documented; complete-case Ns stated (PCM-F-11, PCM-D-05). NOTE: the original rationale for restricting to INPATIENT/OBSERVATION no longer holds — see PCM-F-19
- [ ] Data dictionary, DECISIONS.md complete, `99_run_all.sas` verified from clean session

### Out of Scope

- Re-importing from source CSV/XLSX — already validated (PCM-F-08)
- The INS abstract / dCDT pipeline — separate project
- Any statistical modelling — this project ends at the analysis-ready file

---

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| md3 as merge spine | Complete superset (PCM-F-02); 1:1 merge onto md3, not stack-dedup | ✓ Established |
| No PROC SQL UPDATE | Silent truncation trap (PCM-T-01); all mutations in DATA steps with explicit length | ✓ Established |
| No `data X; set X;` | Destroys dataset on completion with no undo (PCM-T-02) | ✓ Established |
| Single ownership per variable | Prevents silent last-wins overwrite (PCM-T-05) | ✓ Established, map needed |
| PCM-D-01 Death variables | Three names for one flag across sources | Pending — Price |
| PCM-D-02 Frailty components | Char Y/N vs numeric encodings of same five items | Pending |
| PCM-D-03 ISO_SEV naming | md4/md8 naming differs from others | Pending |
| PCM-D-04 Emergent usability | Near-zero positives; likely clinician non-completion | Pending |
| PCM-D-05 Analytic cohort | 53% missingness within admitted population; restriction vs imputation | Pending |
| PCM-D-06 PRECEDE_Study_ID_1 | Duplicate column in md6; drop or retain for traceability | Pending |
| PCM-D-07 Age floor | Minimum 64; upstream inclusion criterion or filter unknown | Pending |

---

## Constraints

- SAS 9.4M8 on Windows; session encoding is not UTF-8 (source of PCM-F-10 encoding damage)
- Read-only on `master_data_1..8.sas7bdat` and everything under `raw\master`
- No PHI in git: `.gitignore` excludes `*.sas7bdat`, `*.xlsx`, `*.csv`, `data/` tree
- Repo on local disk, not P: drive — git against network share is slow and prone to index corruption
- Delivery: UF colors (#0021A5, #FA4616) on visual deliverables; KEY sheet leftmost in workbooks

---

## Findings added 2026-08-27

- **PCM-F-17 — WITHDRAWN, it was false.** It claimed md3-owns ownership costs nothing. The
  supporting check tested md3<-md5 and md3<-md6 and omitted md8, the largest non-spine
  source. md5 and md6 hold only duplicate values, so the zeros were real but meaningless.
- **PCM-F-18** — md3-owns ownership WAS discarding data, from md8 only. A sweep of all 578
  owner/donor/variable combinations found exactly five variables affected, all donated by
  md8, all with ZERO disagreements where both sources hold a value:
  `Cognitive_Score` 8,412 · `Cognitive_Category` 8,445 · `Frailty_Score` 9,268 ·
  `Frailty_Category` 1,789 · `ORAL_MORPHINE_EQUIV_mg_POD_DAY6` 7,695.
  Resolved by MRG-06. Confirms the Phase 7 expectations that had been failing:
  12,128 + 8,412 = 20,540 and 14,043 + 9,268 = 23,311.
- **PCM-F-19 — PCM-F-12 is now false for the geriatric scores.** PCM-F-12 said the
  complete-case subgroup was 100% INPATIENT/OBSERVATION, which was the entire justification
  for the cohort restriction. After MRG-06, 13,288 of 20,540 cognitive scores and 15,161 of
  23,311 frailty scores belong to patients OUTSIDE the admitted cohort — md8 covers the
  ambulatory population. Within the admitted cohort those two are now the weaker variables
  (52.2% and 58.7%). **`Admit_BMI` is what actually forces the restriction**: all 12,726
  values sit inside the admitted cohort (91.6% there, zero outside). PCM-D-05 must be
  re-decided on that basis.

## Traps added 2026-08-27

- **PCM-T-12 — spot checks answered this wrong twice.** The variables losing data were not
  the ones anyone would have guessed: `Cognitive_Category` and `Frailty_Category` surfaced
  only from sweeping every shared variable, and `Cognitive_Score`/`Frailty_Score` only
  because Phase 7 happened to assert on them. For any question of the form "does X hold
  data that Y is discarding", enumerate every candidate. Do not sample.
- **PCM-T-13 — `dictionary.columns.type` is CHARACTER (`'char'`/`'num'`), not numeric.**
  `PROC CONTENTS OUT=` uses numeric 1=NUM / 2=CHAR. Both appear in this pipeline. Comparing
  the dictionary form against `2` silently never matches and sends every variable down the
  wrong branch.

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---

## Current Milestone: v1.1 Variable Harmonization

**Goal:** Close the one gap name-based matching structurally cannot reach -- same-concept
variables whose NAMES share nothing -- and bring the analytic cohort onto the harmonized
file.

**Phases:** 14-16 (renumbered from 9-11, which are taken)

**Rescoped 2026-08-29.** As first written this milestone re-specified work already
delivered. `g.master_data_harmonized` exists: 187 columns, 41,150 rows, eleven harmonized
columns with `_src` provenance, eleven aliases dropped after being proven redundant in the
run itself. Summary statistics cover every variable. HARM-01, 05, 06, 08 and SUMM-01, 02
are met and are marked Complete in REQUIREMENTS.md against the program that met them.

**Target features:**
- A LABEL-similarity sweep across all variable labels. Every sweep so far has matched on
  NAMES, so a pair with unrelated names and near-identical labels is structurally
  invisible. This is the genuinely new capability
- Canonical names read from `docs/precede_dictionary.csv`, the 310-variable PRECEDE data
  dictionary. NOT from `VARIABLE_RECTIFICATION.xlsx` -- an earlier draft named it as the
  crosswalk, but that workbook is a register of open questions (Variable, Status, Priority,
  Issue, Evidence, Action) and holds no name mapping
- Three concept groups the profiler has never seen: the SSDI death family, and the
  `CPT1_CLASS` / `CPT1_LABEL` code-label pair
- A stated rule for the twelve pipeline-derived columns that carry no information --
  `in_md3` is constant, and each of the eleven `h_*_src` companions holds one repeated value
- `g.analytic_cohort` rebuilt from the harmonized file. It is currently 176 columns, built
  before harmonisation existed, so it carries the dropped aliases and none of the `h_`
  columns
- PCM-D-05 resolved with the evidence now in hand: the admitted restriction produces a
  different clinical population rather than a subset, and shifts racial composition by 7.3
  percentage points

---
*Last updated: 2026-08-29 — v1.1 milestone rescoped after review*
