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
- [ ] Merge QC: no surviving NULL strings; md8-only block populated for exactly 22,473; type-converted vars in range
- [ ] Death and frailty naming resolved with Erin's sign-off (PCM-D-01, PCM-D-02)
- [ ] Analytic cohort defined; missingness profile documented; complete-case Ns stated (PCM-F-11, PCM-D-05)
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
| PCM-D-01 Death variables | Three names for one flag across sources | Pending — Erin |
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
*Last updated: 2026-08-25 after initialization*
