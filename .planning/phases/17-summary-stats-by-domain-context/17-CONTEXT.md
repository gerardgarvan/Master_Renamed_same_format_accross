# Phase 17: Summary Statistics by Variable Domain — Context

**Gathered:** 2026-09-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce descriptive summary statistics for every variable documented in the PRECEDE data
dictionary, organized into five clinical domains (D1–D5), output as a single Excel workbook
covering all years in the extended analysis base. This phase is descriptive only — no
inferential testing, no modelling, no cohort restriction beyond what `g.analysis_base`
already applies.

</domain>

<decisions>
## Implementation Decisions

### D-01: Source dataset
- **D-01:** Use option **(b)** — build `g.analysis_base_ext` by left-joining the frailty,
  cognitive, and intraoperative-physiologic columns from `g.master_data_merged` onto
  `g.analysis_base`, keyed on `PRECEDE_STUDY_ID`. Run all five domains (D1–D5) against this
  extended dataset. `g.analysis_base_ext` is a temporary/working dataset for this phase only;
  it is not committed to the permanent library.
  - PRECEDE_STUDY_ID type conflict must be resolved before the join: CHAR $12 in md1–md6, md8
    but NUM8 in md7 — normalize to CHAR $12 (the canonical form used by `g.analysis_base`).

### D-02: Denominator for categorical percentages
- **D-02:** Report both: `n (%)` calculated on the non-missing count for that variable, with
  a separate `n missing` column. Full 41,150 denominator is NOT used for the percentage
  calculation.

### D-03: Year stratification
- **D-03:** Pooled + per-year column blocks. The workbook includes one set of statistics
  across all years pooled AND a block of columns per calendar year. Full statistic set
  (n, n-missing, mean, SD, median, Q1, Q3, min, max for continuous; level, n, %, n-missing
  for categorical) is repeated in each year block. Small-cell suppression (≤11 patients per
  cell) applies to per-year cells as well as pooled cells.

### Domain taxonomy (five clinical domains, locked)
| # | Domain | Contents |
|---|--------|----------|
| D1 | Sociodemographics | Age at surgery, sex, race, ethnicity, insurance/payer, marital status, geography |
| D2 | Preoperative assessment | BMI, frailty (score and components), comorbidities, medical/surgical history, ASA class, smoking status |
| D3 | Cognitive assessments | Cognitive score, clock-drawing / dCDT-derived measures, and other documented cognitive instruments |
| D4 | Intraoperative variables | Procedure and CPT codes, service line, anesthesia type, case duration, emergent Y/N, intraoperative physiologic measures |
| D5 | Outcomes | 30-day mortality, LOS, readmission, postoperative complications, discharge disposition |

Assignment rule (three-step, ordered):
1. **Timing first** — where in the episode was the value captured?
2. **Analytic role second** — where timing is ambiguous, preoperative knowledge → D2, postoperative realization → D5
3. **Instrument membership overrides both** — any variable in a named cognitive instrument → D3

Every variable assignment gets a one-line `domain_rationale` citing which rule applied and in
the reviewer's own words. A blank `domain_rationale` fails the phase.

### Authoritative spec document
- Use **`summary-stats-by-domain-CONTEXT (1).md`** (the more detailed version) as the
  authoritative requirements document for this phase. It includes:
  - The three-rule assignment framework with `domain_rationale` requirement
  - Full crosswalk columns: variable name, label, type, domain, domain_rationale, source dataset
  - Richer QC sheet: counts by assignment rule, suppressed cell count, sentinel recode counts

### Output format
- Single Excel workbook via ODS EXCEL (`qc\` folder)
- Sheets: KEY (leftmost), D1, D2, D3, D4, D5, Crosswalk, QC
- KEY sheet: legend, dataset name, run date, row count, scope statement
- Crosswalk sheet: variable name, label, type, source dataset, domain, domain_rationale
- QC sheet: run metadata, sentinel recode counts, suppressed cell counts, variable counts per
  domain, variable counts by each of the three assignment rules

### Statistics
- Continuous: n, n-missing, mean, SD, median, Q1, Q3, min, max
- Categorical: level, n, % of non-missing, n-missing
- Per-year blocks use the same full statistic set
- Small-cell suppression: any cell ≤11 patients is suppressed (shown as `<11` or `--`)

### Sentinel recoding
- Numeric `-999` → missing
- Literal string `NULL` → missing
- Empty strings → missing
- Recode counts logged per variable before any statistics are computed

### Checkpoints (human review required before proceeding)
- **Checkpoint 1 (Wave 1):** Gerard reviews domain assignment table (`g.var_domain_map`)
  variable-by-variable against the `domain_rationale` column before any statistics are run
- **Checkpoint 2 (Wave 3):** Review of the issued workbook against the data dictionary

### Claude's Discretion
- Handling of variables that are "in data only" (not in dictionary): mark out of scope with
  reason "not in PRECEDE dictionary" rather than assigning to a domain
- Whether `g.analysis_base_ext` is materialized as a permanent or temporary (`work.`) dataset

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary spec documents
- `summary-stats-by-domain-CONTEXT (1).md` — authoritative requirements, three-rule
  assignment framework, domain_rationale requirement, full QC sheet spec, pitfalls, exit
  criteria (at repo root — copy or move to phase directory before use)
- `summary-stats-by-domain-CONTEXT.md` — earlier draft, superseded by (1) version on
  crosswalk and QC sheet detail, but consistent on blocking decisions D-01/D-02/D-03

### Pipeline configuration
- `sas/00_config.sas` — all library and path definitions; every program must `%include` this
- `sas/07_cohort.sas` — builds `g.analysis_base`; defines what columns are excluded from it
- `sas/16_summary_docx.sas` — nearest prior example of PROC MEANS + PROC FREQ by-variable
  with ODS output; pattern to follow for Wave 2 statistics

### Prior phases for patterns
- `.planning/phases/` — prior CONTEXT.md files for established conventions

### No external ADRs — requirements fully captured in the spec documents and decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/16_summary_docx.sas` — ODS WORD output with PROC MEANS / PROC FREQ per variable;
  the by-variable routing logic (continuous vs categorical) is directly reusable with ODS EXCEL
- `sas/09_summary_stats.sas` — existing per-variable stats with coverage%, N distinct; the
  PROC CONTENTS scaffold and variable-type routing macros can be adapted
- `sas/00_config.sas` — library and path macros; must be the sole source of all paths

### Established Patterns
- All programs `%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas"` as first step
- No bare open-code `%IF` — all conditional logic in named macros
- No `%PUT` with apostrophes or embedded semicolons
- Every `%abort cancel` inside a named macro (PCM-R-05)
- No `&SQLOBS` — use explicit `SELECT COUNT(*) INTO :macvar TRIMMED`
- `g.&src_ds` never on the left of a DATA statement (read-only source protection)
- PROC MEANS cannot process character variables — route by type before calling
- `IS NOT MISSING` is PROC SQL / WHERE syntax; DATA step uses `NOT MISSING(x)`

### Integration Points
- Reads `g.analysis_base` (built by `sas/07_cohort.sas`) and extends it with columns from
  `g.master_data_merged` (built by `sas/04_merge.sas`)
- Reads `docs/precede_dictionary.csv` (used by `sas/16_summary_docx.sas`)
- Writes workbook to `qc\` folder (path via `00_config.sas`)
- Writes QC log to `qc\` and run log to `logs\` (paths via `00_config.sas`)
- Program numbered `17_summary_stats_by_domain.sas` — next sequential number after `16_summary_docx.sas`

### Known Pitfalls (from spec §6)
- `PRECEDE_STUDY_ID` is CHAR $12 in md1–md6/md8 but NUM8 in md7 — normalize before joining
- `master_data_8` was truncated at Excel ceiling (1,048,575 rows) in 2021 — do not use as denominator
- `Base_Procedure_1` encoding damage (≤9 rows/file) will appear as spurious D4 distinct levels
- `PRECEDE_Study_ID_1` in md6 is a duplicate of `PRECEDE_STUDY_ID` — exclude from crosswalk
- `_30_DAY_MORTALITY` missingness reflects the md1 join, not the outcome — note separately in D5
- `VARnn` positional names from XLSX engine → defect, not a variable; fail the crosswalk check

</code_context>

<specifics>
## Specific Ideas

- The user provided a fully worked draft spec (`summary-stats-by-domain-CONTEXT (1).md`) with
  domain definitions, assignment rules, pitfall list, work plan (three waves), and exit
  criteria. This is unusually complete — the planner should treat it as a near-final PRD.
- The `domain_rationale` column in the crosswalk is a hard requirement per the (1) spec.
- Checkpoint 1 (domain map review) must be a genuine human review step, not automated.
- UF colors (#0021A5, #FA4616) apply to visual deliverables (workbook header row, per CLAUDE.md).
- KEY sheet must be leftmost tab (per CLAUDE.md project convention).

</specifics>

<deferred>
## Deferred Ideas

- Inferential testing / modeling — out of scope per spec §1
- Cohort restriction beyond `g.analysis_base` — future phase
- D3 cognitive + D2 frailty on `g.analysis_base` alone (option a/c) — superseded by D-01 decision (b)

</deferred>

---

*Phase: 17-summary-stats-by-domain-context*
*Context gathered: 2026-09-03*
