# Phase NN — Summary Statistics by Variable Domain

**Project:** Master_Renamed_same_format_accross
**Repo:** `C:\Master_Renamed_same_format_accross` (`sas\`, `docs\`)
**Data / QC / logs:** `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge` (`g` library, `qc\`, `logs\`)
**Paths:** defined once in `sas\00_config.sas`; every program `%include`s it
**Status:** draft — renumber file to `<NN>-CONTEXT.md` under `.planning\phases\` before execution

---

## 1. Purpose

Produce descriptive summary statistics for every variable documented in the PRECEDE data
dictionary, organized into five clinical domains rather than presented as one flat variable
list. The output is a single rollup workbook covering all years in `g.analysis_base`, so the
team can review completeness and distributions domain by domain.

This phase is descriptive only. No inferential testing, no modeling, no cohort restriction
beyond what `g.analysis_base` already applies.

---

## 2. Domains

Every in-scope variable is assigned to exactly one domain. Assignment is driven by the
PRECEDE data dictionary, not by column order or source file.

| # | Domain | Contents |
|---|--------|----------|
| D1 | Sociodemographics | Age at surgery, sex, race, ethnicity, insurance/payer, marital status, geography |
| D2 | Preoperative assessment | BMI, frailty (score and components), comorbidities, medical/surgical history, ASA class, smoking status |
| D3 | Cognitive assessments | Cognitive score, clock-drawing / dCDT-derived measures, any other documented cognitive instrument |
| D4 | Intraoperative variables | Procedure and CPT codes, service line, anesthesia type, case duration, emergent Y/N, intraoperative physiologic measures |
| D5 | Outcomes | 30-day mortality, length of stay, readmission, postoperative complications, discharge disposition |

A variable that plausibly fits two domains is assigned once, and the reasoning is recorded in
the crosswalk (§5). No variable appears in two domains.

---

## 3. Blocking decisions

**D-01 — Source dataset for D2 frailty and D3 cognitive.**
The current working file, `g.analysis_base` (master_data_3 plus `_30_DAY_MORTALITY` joined from
master_data_1; 41,150 rows x 125 columns), was deliberately scoped to exclude
`Cognitive_Score`, `Frailty_Score`, the frailty components, and the hemodynamic block. Those
variables exist only in `g.master_data_merged`. As written, D3 would be empty and D2 would be
missing its frailty content.

Options:
- **(a)** Keep `g.analysis_base` as the sole source; report D3 as not covered this phase and D2 without frailty.
- **(b)** Build `g.analysis_base_ext` = `g.analysis_base` left-joined to the frailty, cognitive and intraoperative-physiologic columns from `g.master_data_merged`, keyed on `PRECEDE_STUDY_ID`, and run all five domains against it.
- **(c)** Run D1/D2(partial)/D4/D5 on `g.analysis_base` now, and defer D3 plus frailty to a follow-on phase.

Needs sign-off before any code is written. Per the standing convention on this project,
variable-naming and cohort-definition decisions go to Price.

**D-02 — Denominator for percentages.** Whether categorical percentages use the full 41,150
rows or the non-missing count for that variable. Recommend reporting both: `n (%)` on
non-missing, with a separate missing count column.

**D-03 — Year stratification.** Whether the rollup reports all years pooled, one column block
per source year, or both. The workbook is described as covering every year, so the default
assumption is pooled plus a per-year block, but this affects sheet width materially.

---

## 4. Requirements

| ID | Requirement |
|----|-------------|
| PCM-xx | Every variable in the PRECEDE data dictionary is assigned to exactly one of D1–D5, or explicitly marked out of scope with a reason |
| PCM-xx | Continuous variables report: n, n missing, mean, SD, median, Q1, Q3, min, max |
| PCM-xx | Categorical variables report: level, n, % of non-missing, and a separate n missing |
| PCM-xx | Sentinel values are resolved to missing before statistics are computed: numeric `-999`, the literal string `NULL`, and empty strings |
| PCM-xx | The workbook contains one sheet per domain plus a KEY sheet, with KEY as the leftmost tab |
| PCM-xx | A crosswalk sheet lists every variable, its domain, its type, its source dataset and its data-dictionary label |
| PCM-xx | Output is written to `qc\`; the log is written to `logs\`; no PHI is committed to the repo |
| PCM-xx | Row-level data does not appear in the workbook — aggregates only |
| PCM-xx | Any cell representing fewer than 11 patients is suppressed per small-cell convention |

---

## 5. Work plan

**Wave 1 — Inventory**
1. Read the PRECEDE data dictionary into a SAS dataset (`g.dd_precede`): variable name, label, type, permissible values.
2. Join the dictionary against `PROC CONTENTS` of the source dataset chosen in D-01. Produce a reconciliation: in dictionary and in data, in dictionary only, in data only.
3. Assign each matched variable to D1–D5. Store as `g.var_domain_map` and export to the crosswalk sheet for review.
4. **Checkpoint:** Gerard reviews the domain assignment before any statistics are produced.

**Wave 2 — Statistics**
5. Apply sentinel recoding (`-999`, `NULL`, empty) to a working copy. Log how many values were recoded per variable.
6. Continuous variables: `PROC MEANS` with the statistic set in PCM-xx, `BY` domain.
7. Categorical variables: `PROC FREQ` with `/ MISSING` to keep missing visible, then split missing into its own column.
8. If D-03 resolves to per-year, repeat 6–7 with the year classifier and stack.

**Wave 3 — Assembly**
9. Build the workbook with `ODS EXCEL`, one sheet per domain, KEY leftmost, crosswalk and QC sheets last.
10. QC sheet: source dataset name, row count, run datetime, sentinel recode counts, count of suppressed cells, count of variables per domain.
11. **Checkpoint:** review of the issued workbook against the data dictionary.

---

## 6. Pitfalls

- **Type conflicts across sources.** `PRECEDE_STUDY_ID` is CHAR $12 in files 1–6 and 8 but NUM8 in file 7; `Base Procedure Code 1` is CHAR $10 in files 1, 2, 3, 8 and NUM8 in 4–7. If D-01 resolves to option (b), the join key must be normalized to a single type before merging.
- **master_data_8 truncation.** That extract sits at exactly 1,048,575 rows, the Excel ceiling, so it was already truncated at creation in 2021. It must not be used as a denominator source for anything.
- **Encoding damage.** `Base_Procedure_1` has transcoding loss in the esophagectomy descriptions (at most 9 rows per file, visible as `ESOPH?` vs `ESOPH-`). If procedure text is tabulated in D4, these will appear as spurious distinct levels.
- **Duplicate columns.** In master_data_6, `PRECEDE_Study_ID_1` and `PRECEDE_STUDY_ID` are identical in every row. Do not summarize both.
- **`_30_DAY_MORTALITY` provenance.** It comes from master_data_1, not master_data_3, so its missingness pattern reflects the join, not the outcome. Report the join-attributable missing separately in D5.
- **Positional variable names.** The SAS XLSX engine assigns names like `VAR37` when headers do not parse. Any `VARnn` surviving into the crosswalk is a defect, not a variable.

---

## 7. Exit criteria

- `g.var_domain_map` exists and every dictionary-documented variable is either assigned to a domain or listed with an out-of-scope reason.
- A single workbook in `qc\` contains KEY (leftmost), five domain sheets, a crosswalk sheet and a QC sheet.
- The reconciliation in Wave 1 step 2 shows no unexplained "in data only" variables.
- The run log in `logs\` is free of warnings other than the known `Base_Procedure_1` transcoding notes.
