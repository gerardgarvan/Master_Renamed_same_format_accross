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
- **D-01:** Use option **(b)** — build `work.analysis_base_ext` by left-joining the frailty,
  cognitive, and intraoperative-physiologic columns from `g.master_data_merged` onto
  `g.analysis_base`, keyed on `PRECEDE_STUDY_ID`. Run all five domains (D1–D5) against this
  extended dataset. It is a temporary WORK dataset for this phase only — always
  `work.analysis_base_ext`, never `g.analysis_base_ext` — and is not committed to the permanent
  library.
  - PRECEDE_STUDY_ID type must be normalized to CHAR $12 before the join. Resolve the stored type
    at MACRO time from `dictionary.columns` and generate the cast from it. Do NOT write a runtime
    `if vtype(x)='N' then ... else ...` branch: SAS compiles both branches, so the one that does
    not apply is a compile error and the step never runs. A SAS variable has exactly one type per
    dataset — the CHAR/NUM8 history describes the md1–md8 SOURCE files, not `g.master_data_merged`,
    which now holds a single resolved type.
  - Cast with `best12.`, not `z12.`, unless Wave 0 proved the character key is zero-padded. `z12.`
    yields `'000123456789'` against an unpadded `'123456789'` and matches nothing, producing
    all-missing extension columns while the row count still passes.
  - Assert `PRECEDE_STUDY_ID` uniqueness in `g.master_data_merged` BEFORE the merge, so a duplicate
    key fails with its own name rather than as a row-count mismatch.

### D-04: Extension coverage and the D3 / frailty denominator
- **D-04:** Wave 0 counts non-missing coverage for every extension column. If cognitive assessment
  or frailty covers materially less than the full base (the plausible case, if assessment is a
  PRECEDE subcohort activity), D3 and the D2 frailty block are reported against a **stated
  subcohort denominator**, carried on `g.var_domain_map.denominator_note` and printed on the KEY
  sheet and the affected domain sheets. Without this the reader sees ~95 percent missing and
  concludes the data are broken rather than that the population differs.

### D-05: Identifier exclusion
- **D-05:** Identifiers and technical keys are marked `OUT_OF_SCOPE` with reason "identifier or
  technical key; not an analytic variable" and never routed to statistics: `PRECEDE_STUDY_ID`,
  `PRECEDE_STUDY_ID_1`, `ENCRYPTED_MRN`, `ENCRYPTED_ENCOUNTER`, anything matching
  `/(^|_)(ID|MRN)(_|$)/`, and any character variable with more than 200 distinct levels. They
  remain on the Crosswalk — excluded from statistics, not from documentation. An ID routed to
  PROC FREQ produces a ~41,000-level table and an unusable sheet.

### D-06: Statistic routing by type AND cardinality
- **D-06:** Each in-scope variable carries a `stat_route` of MEANS or FREQ on `g.var_domain_map`,
  set from type and observed level count, not from type alone: character → FREQ; numeric with
  ≤10 levels → FREQ; numeric with >10 levels → MEANS. Routing on type alone would send
  `_30_DAY_MORTALITY`, sex, race, ASA class and emergent Y/N into PROC MEANS and report a
  meaningless mean for the phase's headline outcome. The threshold is a default; Checkpoint 1 is
  where Gerard overrides any variable whose route is wrong.

### D-02: Denominator for categorical percentages
- **D-02:** Report both: `n (%)` calculated on the non-missing count for that variable, with
  a separate `n missing` column. Full 41,150 denominator is NOT used for the percentage
  calculation.

### D-03: Year stratification
- **D-03:** Pooled + per-year column blocks. The workbook includes one set of statistics
  across all years pooled AND a block of columns per calendar year. Full statistic set
  (n, n-missing, mean, SD, median, Q1, Q3, min, max for continuous; level, n, %, n-missing
  for categorical) is repeated in each year block. Small-cell suppression applies to per-year
  cells as well as pooled cells.
  - Implement per-year with `CLASS` / `TYPES () year` in PROC MEANS and `TABLES (...)*year` in
    PROC FREQ — **not** `BY year`. A BY statement requires the input sorted by that variable, and
    the working dataset is sorted by `PRECEDE_STUDY_ID`; CLASS needs no sort and returns pooled
    plus per-year in one pass.
  - Group the per-year columns under spanning headers in PROC REPORT (Pooled, 2018, 2019, …).
    Nine statistics across pooled plus ~10 years is ~99 columns per continuous row.

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
- **Rename before execution.** The spec currently sits at repo root as
  `docs/17-spec-summary-stats-by-domain.md`. The space and parentheses break the `@` context
  references in every plan. Move and rename it to **`docs/17-spec-summary-stats-by-domain.md`**;
  all plans reference that path. The earlier draft `summary-stats-by-domain-CONTEXT.md` is
  superseded and should be deleted or archived so no executor resolves the wrong file.
- Use it as the authoritative requirements document for this phase. It includes:
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
- Routing is by `stat_route` (D-06), never by `vtype` alone

### Small-cell suppression
- Constants declared once in Section 0: `%let SUPPRESS_MAX = 11;` and `%let SUPPRESS_LABEL = --;`
- Rule: any subject-level count **≤ 11** is suppressed and shown as `--`
- The label is `--`, NOT `<11`. Under an `n <= 11` rule a cell of exactly 11 rendered as "<11" is
  a false statement. If the rule were `n < 11`, `<11` would be correct — the project takes `≤ 11`
  with `--`.
- Suppression covers, in pooled AND every per-year block:
  1. categorical level counts and their percentages
  2. `n_missing` (an unsuppressed "Missing 7" discloses just as plainly as a level would)
  3. the ENTIRE statistic row of any continuous block whose non-missing n ≤ 11 — mean, SD, median,
     Q1, Q3, min, max and n. Min/max on seven patients are more disclosive than the count.
  4. the next-smallest level when only one level in a block is suppressed and the total is printed,
     so the suppressed count cannot be back-calculated

### Sentinel recoding
- Numeric `-999` → missing; literal string `NULL` → missing; empty strings are already missing
- **Scoped, not blanket.** Wave 0 produces a sentinel applicability list — the variables where a
  `-999` or literal `NULL` value is actually observed — and Wave 2 recodes only those. `-999` is a
  documented sentinel for the clock-drawing/dCDT variables, not a proven global reserved code;
  applying it to every numeric would destroy legitimate values.
- Implement as ONE array-based DATA step, not one dataset rewrite per variable
- Recode counts logged per variable before any statistics are computed, and listed per variable on
  the QC sheet so an unexpected entry surfaces at Checkpoint 2. Count only what is actually
  recoded — a character count of `'NULL' or missing(x)` inflates the log with rows never touched.

### Checkpoints (human review required before proceeding)
- **Checkpoint 1 (Wave 1):** Gerard reviews domain assignment table (`g.var_domain_map`)
  variable-by-variable against the `domain_rationale` and `stat_route` columns before any
  statistics are run
- **Checkpoint 2 (Wave 3):** Review of the issued workbook against the data dictionary
- **The Checkpoint 1 gate is enforced in code, not by convention.** Section 0 declares
  `%let DOMAIN_MAP_APPROVED = 0;` and a `%gate_stats` macro that aborts unless the flag is 1.
  Sections 5–11 open with `%gate_stats;`. Because all eleven sections live in one `.sas` file,
  without this the completed program would run straight past the blocking checkpoint into
  statistics. The flag is set to 1 only after Gerard approves the review CSV.

### Library invariant (scoped)
- Existing `g.*` **source** datasets — `g.analysis_base`, `g.master_data_merged` — are read-only and
  never appear on the left of a DATA statement.
- `g.var_domain_map` is the explicitly authorized exception: it is the one permanent artifact this
  phase creates. Automated compliance checks should not flag it.

### Output verification order
- `%check_xlsx` and `%check_qc_txt` run BEFORE `%restore_log`. `%fail_out` calls `%restore_log`
  itself, so validating after the log is already restored is backwards. Both deliverables are
  checked, not just the workbook.

### Claude's Discretion
- Handling of variables that are "in data only" (not in dictionary): mark out of scope with
  reason "not in PRECEDE dictionary" rather than assigning to a domain
- Materialization of `analysis_base_ext` — resolved: WORK, temporary (`work.analysis_base_ext`)
- The exact numeric-cardinality threshold for FREQ routing (default 10) and the character-level
  threshold for identifier exclusion (default 200)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary spec documents
- `docs/17-spec-summary-stats-by-domain.md` — authoritative requirements, three-rule
  assignment framework, domain_rationale requirement, full QC sheet spec, pitfalls, exit
  criteria. (Formerly `docs/17-spec-summary-stats-by-domain.md` at repo root; rename it before
  execution so the `@` references resolve.)
- The earlier draft `summary-stats-by-domain-CONTEXT.md` is superseded on crosswalk and QC sheet
  detail. Delete or archive it — two similarly named specs at repo root is how an executor ends up
  planning against the wrong one.

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
- `PRECEDE_STUDY_ID` was CHAR $12 in md1–md6/md8 but NUM8 in md7 — normalize before joining, using
  macro-time type resolution and `best12.` (see D-01). Runtime `vtype()` branching does not compile.
- `master_data_8` was truncated at Excel ceiling (1,048,575 rows) in 2021 — do not use as denominator
- `Base_Procedure_1` encoding damage (≤9 rows/file) will appear as spurious D4 distinct levels
- `PRECEDE_Study_ID_1` in md6 is a duplicate of `PRECEDE_STUDY_ID` — exclude from the extension
  KEEP= list and mark OUT_OF_SCOPE
- `_30_DAY_MORTALITY` missingness reflects the md1 join, not the outcome — note separately in D5.
  It is also a numeric-coded categorical: it must route to FREQ, not MEANS (D-06).
- `VARnn` positional names from XLSX engine → defect, not a variable; fail the crosswalk check
- `BY year` on the working dataset aborts (sorted by `PRECEDE_STUDY_ID`) — use CLASS / TABLES year*var
- ODS EXCEL default `sheet_interval="table"` splits a domain across `D1` and `D1 1` — set it to `none`
- Blanket `-999` recoding destroys legitimate values — scope it to the Wave 0 applicability list
- An identifier routed to PROC FREQ produces a ~41,000-level table — exclude identifiers (D-05)

</code_context>

<specifics>
## Specific Ideas

- The user provided a fully worked draft spec (`docs/17-spec-summary-stats-by-domain.md`) with
  domain definitions, assignment rules, pitfall list, work plan (three waves), and exit
  criteria. This is unusually complete — the planner should treat it as a near-final PRD.
- The `domain_rationale` column in the crosswalk is a hard requirement per the (1) spec.
- Checkpoint 1 (domain map review) must be a genuine human review step, not automated.
- UF colors (#0021A5, #FA4616) apply to visual deliverables (workbook header row, per CLAUDE.md).
- KEY sheet must be leftmost tab (per CLAUDE.md project convention).
- The requirement IDs used by the plans (SUMM-DOMAIN-DISC / -MAP / -STATS / -BOOK) are not yet in
  `.planning/REQUIREMENTS.md` — RESEARCH notes none are assigned for Phase 17. Register them there
  before execution or they dangle.

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
