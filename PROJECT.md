# PROJECT.md — PeCAN Master Dataset Integration

**Project ID:** PCM
**Owner:** Gerard Garvan (ggarvan)
**Working folder:** `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross`
**Repo:** local disk (see PCM-C-04 — do **not** put the git repo on the P: drive)
**Status:** Phase 1 not started
**Supersedes:** all ad-hoc `master_data_*` merge/stack/dedup code written before this document

---

## 1. Purpose

Produce one analysis-ready, reproducible, provenance-tracked patient-level dataset
from eight heterogeneous master extracts, with every type conversion, name
reconciliation, and row-count change traceable to a numbered program in version
control.

The prior work established the target structure but was done interactively, with
no reproducible artifact and at least two destructive incidents (see §7). This
project restarts from source with the findings preserved as requirements.

## 2. Scope

**In scope**
- The eight `master_data_1..8.sas7bdat` files in the working folder
- Harmonization, key validation, merge, post-merge QC
- Analytic cohort definition and a documented missingness profile
- A written data dictionary for the merged file

**Out of scope**
- Re-importing from the source CSV/XLSX (already validated — PCM-F-08)
- The INS abstract / dCDT pipeline (separate project)
- Any statistical modelling; this project ends at the analysis-ready file

---

## 3. Established facts (verified, do not re-litigate)

These were confirmed empirically. Phase 1 re-verifies them as assertions; it does
not rediscover them.

| ID | Finding |
|---|---|
| PCM-F-01 | `PRECEDE_STUDY_ID` is **strictly one row per patient in all eight files** (`n_rows = n_ids`, zero excess, every source). |
| PCM-F-02 | `master_data_3` (41,150 rows, 124 vars) is a **complete superset**: every ID in md1, md2, md4, md5, md6, md7, md8 appears in md3. |
| PCM-F-03 | These are **eight overlapping variable sets over one patient population**, not eight cohorts. The correct operation is a 1:1 **merge**, not a stack. Merged row count = 41,150. |
| PCM-F-04 | md1 and md3 agree **exactly** on `Race`, `Sex`, `Age_at_Encounter`, `Admit_BMI` across all 14,778 shared records (zero disagreements). |
| PCM-F-05 | md8 stores the literal four-character string `NULL` where the other seven store a blank. This is what forced its numerics to `CHAR $4/$11`. |
| PCM-F-06 | `Emergent` is Y/N/blank in both md1 and md8 at matching rates (0.05% / 0.09% `Y`). `Intraop_Ketamine` and `Preop_block` are **Y-or-blank in every source** — no `N` category anywhere — with matching rates (block: 18.57% / 18.22%). |
| PCM-F-07 | `Admit_BMI` is 12,726 / 41,150 in md3, and **coalescing all seven other sources recovers nothing** — every other source's BMI belongs to a patient md3 already covers, with zero value conflicts. The 28,424 missing are missing at source. |
| PCM-F-08 | Leading-zero audit of the source CSVs came back empty; the numeric typing in files 4–7 was lossless. No re-import needed. |
| PCM-F-09 | In md6, `PRECEDE_Study_ID_1` and `PRECEDE_STUDY_ID` are identical in every row — a duplicate column from the source query. |
| PCM-F-10 | Encoding damage is confined to `Base_Procedure_1` (esophagectomy descriptions), ≤9 rows per file, visible as `ESOPH?` vs `ESOPH-`. |
| PCM-F-11 | Complete-case counts in the merged file: BMI 12,726; `Cognitive_Score` 20,540; `Frailty_Score` 23,311; **all three together 6,523**. Core covariates (age + ASA + Charlson) 36,174. |
| PCM-F-12 | The all-three-complete subgroup is **100% INPATIENT or OBSERVATION** — zero ambulatory surgery, zero outpatient. It differs from the rest on LOS (4.47 vs 0.93 days) and Charlson (2.09 vs 0.72) but **not** on age (73.1 vs 73.4) or sex (49.6% vs 49.7% F). Within the admitted population (13,890), completeness is 6,523 = 47%. |

## 4. Requirements

### Data integrity

- **PCM-R-01** Every program writes to a **new** dataset name. No program may use
  `data X; set X;` or `proc sql update` against a library dataset.
- **PCM-R-02** No character variable may be truncated. Every merge/set step
  declares a `length` statement **before** the `merge`/`set`, using the maximum
  width across all sources.
- **PCM-R-03** Every type conversion is preceded by an exception report that lists
  values which would fail to convert. Zero rows is the pass condition; the report
  is retained as an artifact.
- **PCM-R-04** Row counts are asserted, not observed. Each phase ends with a
  program that fails loudly (`abort`) if the count deviates from expected.
- **PCM-R-05** The merged file carries `in_md1`–`in_md8` provenance flags and
  `n_sources`.

### Merge semantics

- **PCM-R-06** `PRECEDE_STUDY_ID` is the merge key. md3 is the spine, listed first.
- **PCM-R-07** Where two sources share a variable name, ownership is assigned
  **explicitly** — one source per variable — so no silent last-wins overwrite is
  possible. The ownership map is written to disk and reviewed before the merge runs.
- **PCM-R-08** Any variable where a coalesce across sources is wanted instead of
  single ownership must be named explicitly in `02_ownership.sas`, with a
  disagreement check.

### Reproducibility

- **PCM-R-09** Numbered, single-purpose programs (see §5), runnable end-to-end from
  `99_run_all.sas` with no manual steps.
- **PCM-R-10** No hardcoded absolute paths outside `00_setup.sas`.
- **PCM-R-11** Every program writes a `.log` to `logs/` and its checks to
  `qc/`. Logs and QC output are committed; data is not (PCM-C-03).
- **PCM-R-12** Every derived variable has a `label` stating its derivation rule.

## 5. Program layout

Mirrors the INS abstract pipeline convention.

```
.planning/
  PROJECT.md          <- this file
  ROADMAP.md
  STATE.md
  phases/
sas/
  00_setup.sas          libname, macro vars, paths, options
  01_verify_sources.sas assert PCM-F-01, F-02, row/ID counts per source
  02_ownership.sas      build + write the variable ownership map
  03_prep_md1.sas       per-source normalization, one program each
  03_prep_md2.sas
  03_prep_md3.sas
  03_prep_md4.sas
  03_prep_md5.sas
  03_prep_md6.sas
  03_prep_md7.sas
  03_prep_md8.sas
  04_merge.sas          the 1:1 merge onto the md3 spine
  05_qc_merge.sas       row/ID assertions, provenance marginals, NULL sweep
  06_reconcile.sas      death + frailty variable reconciliation (Phase 6)
  07_cohort.sas         analytic cohort definition + missingness profile
  08_dictionary.sas     data dictionary export
  99_run_all.sas
qc/
logs/
docs/
  DECISIONS.md
  DATA_DICTIONARY.xlsx
```

One prep program per source is deliberate: when one of the eight extracts changes
again, exactly one file changes in the diff.

## 6. Phases

| Phase | Name | Exit criteria |
|---|---|---|
| 1 | Source verification & freeze | PCM-F-01 and F-02 re-asserted in code; per-source row/ID counts written to `qc/`; source files checksummed |
| 2 | Ownership map | `02_ownership.sas` produces the variable→source map; map reviewed and committed; conflicts named in DECISIONS.md |
| 3 | Per-source normalization | Eight prep programs; all type conversions have clean exception reports; `NULL` sentinel cleared; conversion counts logged |
| 4 | Merge | `g.master_data_merged` = 41,150 rows, 41,150 distinct IDs, zero blank IDs; provenance flags match source row counts |
| 5 | Merge QC | No truncation; no surviving `NULL`; md8-only block populated for exactly 22,473; type-converted vars within expected ranges |
| 6 | Variable reconciliation | Death and frailty naming resolved (§8); decisions recorded with Erin's sign-off |
| 7 | Cohort & missingness | Analytic cohort defined; missingness profile documented; complete-case Ns stated |
| 8 | Documentation & handoff | Data dictionary; DECISIONS.md complete; `99_run_all.sas` verified from a clean session |

Phases 1–5 are mechanical and should not require new decisions. Phase 6 requires
input from Erin. Phase 7 is a study-design conversation, not a data-cleaning task.

## 7. Known traps

Recorded because each of these has already cost time or data.

- **PCM-T-01 — `CATS` in a `PROC SQL UPDATE`.** The result buffer is the target
  column's existing length. `update ... set X = cats('Precede', X)` against a
  short `X` silently blanked all 9,215 rows of md7. PROC SQL cannot widen a column.
  Prefix operations go in a DATA step with an explicit `length`. See PCM-R-01.
- **PCM-T-02 — `data X; set X;`.** Replaces the dataset on completion, with no
  undo. Combined with T-01 this destroyed md7 and required a re-run from the
  Excel import. See PCM-R-01.
- **PCM-T-03 — Stack-then-dedup.** Stacking the eight and deduping on
  `PRECEDE_STUDY_ID` yields exactly 41,150 rows and looks correct. It is not: it
  keeps md1's record for 14,778 patients and md3's for the rest, and discards
  md8's hemodynamic block (which exists in no other source) entirely. Row count
  alone does not validate a merge.
- **PCM-T-04 — `=:` in PROC SQL.** DATA-step-only operator. Use `like 'Precede%'`
  or `substr()`.
- **PCM-T-05 — Merge overwrite by missing.** In a SAS `merge`, a later dataset
  overwrites an earlier one *even when the later value is missing*, silently.
  This is why PCM-R-07 exists. (Note: this was suspected as the cause of the low
  BMI count and **was not** — see PCM-F-07. The hazard is real; that instance
  wasn't it.)
- **PCM-T-06 — md8 row ceiling.** The source
  `ALL_AIM2_MASTER_DATASET_20210917.xlsx` was truncated at Excel's 1,048,575-row
  limit when created in 2021. The current 22,473 rows are what survived. If md8
  is ever re-derived, the true count must come from whatever generated the xlsx.

## 8. Open decisions

Carry into DECISIONS.md; do not resolve silently in code.

- **PCM-D-01 — Death variables.** `Death_Date_Y_N` (md1–5), `IsDead_Y_N` (md6),
  and `Death` (md7) appear to be one flag under three names. `_30_DAY_MORTALITY`
  (md1, md2) and `Death_Days_After_Surgery` are clearly distinct measures.
  Needs Erin's confirmation before any mortality analysis.
- **PCM-D-02 — Frailty components.** `Feels_Exausted` etc. (character Y/N) and
  `Feels_Exausted_Value` etc. (numeric) are two encodings of the same five items.
  Pick one canonical form.
- **PCM-D-03 — `ISO_SEV` naming.** md4's `ISO_SEV_IntraOp_MAC_Average` maps to the
  others' `ISO_SEV_Exp_IntraOp_MAC_Average`. md8's `ISO_SEV_MAC_TOTAL_Exp` says
  *total* where the others say *average* and was deliberately left unmapped —
  confirm before folding it in.
- **PCM-D-04 — `Emergent` usability.** 7 positives in md1, 21 in md8. Almost
  certainly a field clinicians rarely complete rather than a true rate. Recommend
  flagging as unusable and checking whether `Patient_Type` or `Admit_Source`
  carries urgency instead.
- **PCM-D-05 — Analytic cohort.** Given PCM-F-12, restricting to
  INPATIENT/OBSERVATION is a defensible pre-specifiable inclusion criterion
  (ambulatory patients were never eligible for the geriatric assessments). That
  still leaves 53% missing *within* the admitted population, which needs its own
  explanation — check whether the gap tracks a source extract or an admission year
  before choosing between restriction, imputation, and dropping BMI.
- **PCM-D-06 — `PRECEDE_Study_ID_1`.** Duplicate column in md6 (PCM-F-09). Drop,
  unless it is needed for traceability to the source query.
- **PCM-D-07 — Age floor.** `Age_at_Encounter` minimum is 64. If an age inclusion
  criterion was applied upstream, document it; if not, find out what filtered it.

## 9. Constraints

- **PCM-C-01** SAS 9.4M8 on Windows, against the P: drive. Session encoding is not
  UTF-8 (source of PCM-F-10).
- **PCM-C-02** Read-only on `master_data_1..8.sas7bdat` and on everything under
  `raw\master`. All output goes to new names.
- **PCM-C-03** **No PHI in git.** `.gitignore` must exclude `*.sas7bdat`, `*.xlsx`,
  `*.csv`, and the `data/` tree. Commit code, logs, QC output, and documentation
  only. Review the first commit's file list by hand before pushing.
- **PCM-C-04** Put the repo on local disk, not the P: drive — git against a network
  share is slow and prone to index corruption. Point `00_setup.sas` at the P: data
  location; keep the code local.
- **PCM-C-05** Delivery conventions: complete programs in one block; UF colors
  (#0021A5, #FA4616) on visual deliverables; measured/neutral language; KEY sheet
  leftmost in workbooks.

## 10. Definition of done

`99_run_all.sas` runs start to finish in a clean SAS session against read-only
sources and produces:

1. `g.master_data_merged` — 41,150 rows, 41,150 distinct `PRECEDE_STUDY_ID`,
   provenance flags present, no truncation, no `NULL` strings
2. `qc/` — every assertion report, all passing
3. `docs/DATA_DICTIONARY.xlsx` — every variable with source, type, length,
   coverage, and derivation
4. `docs/DECISIONS.md` — PCM-D-01 through D-07 resolved and attributed
5. A git history where each phase is a reviewable commit
