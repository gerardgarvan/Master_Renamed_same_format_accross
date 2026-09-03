# Phase 17: Summary Statistics by Variable Domain — Research

**Researched:** 2026-09-03
**Domain:** SAS 9.4 descriptive statistics pipeline — PROC MEANS, PROC FREQ, ODS EXCEL, domain taxonomy
**Confidence:** HIGH (all findings sourced from existing project code and authoritative spec documents in the repo)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01 — Source dataset**
Use `g.analysis_base_ext` = `g.analysis_base` left-joined to the frailty, cognitive, and
intraoperative-physiologic columns from `g.master_data_merged`, keyed on `PRECEDE_STUDY_ID`.
Run all five domains (D1–D5) against this extended dataset. `g.analysis_base_ext` is a
temporary/working dataset for this phase only; it is not committed to the permanent library.
PRECEDE_STUDY_ID type conflict must be resolved before the join: CHAR $12 in md1–md6, md8
but NUM8 in md7 — normalize to CHAR $12.

**D-02 — Denominator for categorical percentages**
Report both: `n (%)` calculated on the non-missing count for that variable, with a separate
`n missing` column. Full 41,150 denominator is NOT used for the percentage calculation.

**D-03 — Year stratification**
Pooled + per-year column blocks. The workbook includes one set of statistics across all years
pooled AND a block of columns per calendar year. Full statistic set is repeated in each year
block. Small-cell suppression (≤11) applies to per-year cells as well as pooled cells.

**Domain taxonomy (five clinical domains, locked)**
| # | Domain | Contents |
|---|--------|----------|
| D1 | Sociodemographics | Age at surgery, sex, race, ethnicity, insurance/payer, marital status, geography |
| D2 | Preoperative assessment | BMI, frailty (score and components), comorbidities, medical/surgical history, ASA class, smoking status |
| D3 | Cognitive assessments | Cognitive score, clock-drawing / dCDT-derived measures, and other documented cognitive instruments |
| D4 | Intraoperative variables | Procedure and CPT codes, service line, anesthesia type, case duration, emergent Y/N, intraoperative physiologic measures |
| D5 | Outcomes | 30-day mortality, LOS, readmission, postoperative complications, discharge disposition |

Assignment rule (three-step, ordered):
1. Timing first — where in the episode was the value captured?
2. Analytic role second — preoperative knowledge → D2, postoperative realization → D5
3. Instrument membership overrides both — any variable in a named cognitive instrument → D3

Every variable assignment gets a one-line `domain_rationale`. A blank `domain_rationale` fails the phase.

**Output format**
- Single Excel workbook via ODS EXCEL, `qc\` folder
- Sheets: KEY (leftmost), D1, D2, D3, D4, D5, Crosswalk, QC
- Small-cell suppression: any cell ≤11 patients shown as `<11` or `--`
- Sentinel recoding: numeric `-999` → missing, literal `NULL` → missing, empty strings → missing, counts logged per variable before stats

**Checkpoints (human review required)**
- Checkpoint 1 (Wave 1): Gerard reviews `g.var_domain_map` variable-by-variable against the `domain_rationale` column before any statistics are run
- Checkpoint 2 (Wave 3): Review of the issued workbook against the data dictionary

**Authoritative spec document**
`summary-stats-by-domain-CONTEXT (1).md` (repo root) — use this, not the earlier draft

### Claude's Discretion
- Handling of variables "in data only" (not in dictionary): mark out of scope with reason "not in PRECEDE dictionary" rather than assigning to a domain
- Whether `g.analysis_base_ext` is materialized as a permanent or temporary (`work.`) dataset

### Deferred Ideas (OUT OF SCOPE)
- Inferential testing / modeling
- Cohort restriction beyond `g.analysis_base`
- D3 cognitive + D2 frailty on `g.analysis_base` alone (options a/c)
</user_constraints>

---

## Summary

Phase 17 produces descriptive summary statistics for every PRECEDE-dictionary-documented
variable, organized across five clinical domains, output as a single Excel workbook with
pooled and per-year column blocks. The authoritative spec (`summary-stats-by-domain-CONTEXT (1).md`)
is unusually complete and functions as a near-final PRD. Research confirms that all required
SAS techniques are already demonstrated in the existing pipeline (Programs 09 and 16), and no
external tools or novel SAS features are needed.

The implementation proceeds in three waves with a human checkpoint at the end of Wave 1: (1)
inventory and domain assignment producing `g.var_domain_map`, (2) sentinel recoding and
statistics, and (3) workbook assembly. The most complex technical element is per-year stratification
with pooled-plus-per-year column blocks requiring careful ODS EXCEL sheet and column structure.
Small-cell suppression must be applied after statistics are computed, before any value is written.

**Primary recommendation:** Follow the three-wave work plan from the spec. Reuse the
dictionary-matching scaffold from Program 16 and the PROC MEANS / PROC FREQ / ODS EXCEL
patterns from Programs 09 and 16. Write `work.analysis_base_ext` (not permanent) and keep
`g.var_domain_map` permanent for the Checkpoint 1 review.

---

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| SAS 9.4M8 | as installed | All computation and output | Project constraint |
| ODS EXCEL | SAS 9.4M5+ | Native .xlsx output with multiple sheets | Established pattern in Programs 09 and 16 |
| PROC MEANS | base SAS | Continuous variable statistics | Cannot process character variables — must route by type |
| PROC FREQ | base SAS | Categorical variable statistics + NLEVELS | One-pass distinct counts; use `/ MISSING` to keep missing visible, then split |
| PROC CONTENTS | base SAS | Variable inventory from g.analysis_base_ext | Already used in Program 09 via `dictionary.columns` |
| dictionary.columns | base SAS | Variable type, length, label metadata | TYPE is char/num (not 1/2 as in PROC CONTENTS OUT=) — see pitfall below |
| PROC IMPORT | base SAS | Read `docs/precede_dictionary.csv` | Pattern from Program 16 |
| PROC SQL | base SAS | All joins, count macros, crosswalk assembly | Pattern throughout pipeline |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| DATA step label assignment via generated code | Apply documented names as column labels | Pattern from Program 16, Section 1 |
| `%include` of generated .sas file | Apply PROC DATASETS MODIFY LABEL in one pass | Safer than building label in open code with macro variables |
| `PROC PRINTTO` | Route log per standalone/pipeline flag | Required by `00_config.sas` `in_pipeline` convention |

### Installation
No new packages. All tools are base SAS 9.4.

---

## Architecture Patterns

### Recommended Program Structure
```
17_summary_stats_by_domain.sas
  Section 0:  Options, %include config, preconditions
  Section 1:  Build g.analysis_base_ext (left join)
  Section 2:  Read precede_dictionary.csv → work.dd_precede
  Section 3:  Match dictionary against PROC CONTENTS of g.analysis_base_ext
              → work.var_domain_raw (reconciliation: in both, dict only, data only)
  Section 4:  Assign domains and domain_rationale → g.var_domain_map
              [STOP — Checkpoint 1 human review]
  Section 5:  Sentinel recoding → work.analysis_base_clean, log recode counts
  Section 6:  Continuous stats — PROC MEANS, pooled + per year
  Section 7:  Categorical stats — PROC FREQ, pooled + per year
  Section 8:  Small-cell suppression pass
  Section 9:  ODS EXCEL assembly — KEY, D1–D5, Crosswalk, QC sheets
  Section 10: QC artifact written to qc\
  Section 11: Restore log
```

### Pattern 1: Extended Dataset Build (D-01)
**What:** Left-join frailty/cognitive/intraop-physiologic columns from `g.master_data_merged`
onto `g.analysis_base`, keyed on PRECEDE_STUDY_ID. Result stays in WORK.

**Critical:** PRECEDE_STUDY_ID is CHAR $12 in `g.analysis_base` (and in md1–md6/md8) but NUM8
in md7 (which contributed some rows to `g.master_data_merged`). The join key in
`g.master_data_merged` must be cast to CHAR $12 before the left join.

**Example — safe join pattern:**
```sas
/* Cast the key in master_data_merged to CHAR $12 in a work copy */
data work.merged_ext_cols;
  set g.master_data_merged (keep=PRECEDE_STUDY_ID
        Cognitive_Score Frailty_Score
        /* frailty components */
        Feels_Exausted Weight_Loss Weak_Grip_Strength
        Slow_Walking_Speed Low_Physical_Activity
        /* intraop physiologic block — all variables from md8 hemodynamic block */
        /* ... enumerate from PROC CONTENTS of g.master_data_merged ... */
        );
  length key_char $12;
  if vtype(PRECEDE_STUDY_ID) = 'N' then key_char = put(PRECEDE_STUDY_ID, z12.);
  else key_char = strip(PRECEDE_STUDY_ID);
  drop PRECEDE_STUDY_ID;
  rename key_char = PRECEDE_STUDY_ID;
run;

proc sort data=work.merged_ext_cols; by PRECEDE_STUDY_ID; run;
proc sort data=g.analysis_base out=work.analysis_base_sorted; by PRECEDE_STUDY_ID; run;

data work.analysis_base_ext;
  merge work.analysis_base_sorted (in=inbase)
        work.merged_ext_cols;
  by PRECEDE_STUDY_ID;
  if inbase;
run;
```

**Note:** Enumerate the exact columns to bring in from `g.master_data_merged` based on
PROC CONTENTS — do not use `_ALL_` since that would import all 176+ columns.

### Pattern 2: Dictionary Matching (from Program 16)
**What:** Three-tier match: exact name, case-insensitive, squash (compress underscores).
Deduplicate to one row per variable before joining. Flag match ties as warnings, not errors.

**Reuse:** The dictionary-import and matching scaffold from Program 16, Sections 0–1, is
directly portable. Key difference for Phase 17: match against `work.analysis_base_ext`
(dictionary.columns) rather than `g.analysis_base`.

### Pattern 3: Variable Type Routing (from Programs 09 and 16)
**What:** Separate lists for MEANS-eligible (numeric, low cardinality rule does NOT apply
here — all numerics get PROC MEANS) vs FREQ-eligible (character, or numeric with few levels).
**Critical:** `dictionary.columns.type` is `'num'` / `'char'` (character values), NOT 1/2.
Comparing against 1 or 2 silently never matches.

```sas
proc sql noprint;
  select varname into :num_varlist separated by ' '
  from work.var_domain_map where vtype = 'num';

  select varname into :chr_varlist separated by ' '
  from work.var_domain_map where vtype = 'char';
quit;
```

### Pattern 4: Sentinel Recoding Before Statistics
**What:** Three sentinel forms must be recoded to missing BEFORE any PROC MEANS or PROC FREQ:
- Numeric `-999` → `.`
- Literal string `'NULL'` → `''`
- Empty strings → already missing to SAS (length(strip(x))=0 is missing)

Log the count of recodes per variable. Store in `work.sentinel_log` for the QC sheet.

```sas
/* Numeric sentinel — one macro call per numeric variable */
%macro recode_num(v=);
  %local cnt;
  proc sql noprint;
    select count(*) into :cnt trimmed
    from work.analysis_base_clean where &v = -999;
  quit;
  data work.analysis_base_clean;
    set work.analysis_base_clean;
    if &v = -999 then call missing(&v);
  run;
  /* insert cnt into work.sentinel_log */
%mend recode_num;

/* Character sentinel */
%macro recode_char(v=);
  %local cnt;
  proc sql noprint;
    select count(*) into :cnt trimmed
    from work.analysis_base_clean
    where upcase(strip(&v)) = 'NULL' or missing(&v);
  quit;
  data work.analysis_base_clean;
    set work.analysis_base_clean;
    if upcase(strip(&v)) = 'NULL' then call missing(&v);
  run;
%mend recode_char;
```

### Pattern 5: Pooled + Per-Year Statistics
**What:** Two passes through PROC MEANS and PROC FREQ — once without BY year (pooled) and
once with `BY year` (per-year blocks). Stack outputs. Year variable must be identified from
the dataset (likely a fiscal year or calendar year column already present in `g.analysis_base`).

**Approach for per-year:**
```sas
proc means data=work.analysis_base_clean n nmiss mean std median p25 p75 min max
           stackodsoutput;
  var &num_d1_varlist;  /* separate call per domain is cleanest */
  by year;
  ods output summary=work.means_by_year;
run;
```

**Column block layout in Excel:** The planner must decide whether to produce separate summary
datasets for pooled vs. each year and TRANSPOSE them into wide format for the domain sheets,
or to write one narrow ODS table per year block and rely on ODS EXCEL column grouping. The
simpler approach is: assemble a wide dataset with columns like `n_pooled`, `mean_pooled`,
`n_2018`, `mean_2018`, `n_2019`, `mean_2019`, etc., then write with PROC REPORT. This
requires a PROC TRANSPOSE step after PROC MEANS.

### Pattern 6: Small-Cell Suppression
**What:** Any frequency count ≤11 is replaced with the display value `<11`. Applies to
both pooled and per-year cells, for both n and % columns.

**Suppression must happen AFTER computing statistics, BEFORE writing the workbook.**
Store the count of suppressed cells in a macro variable for the QC sheet.

```sas
data work.cat_domain1_display;
  set work.cat_domain1_stats;
  /* Suppress counts ≤ 11 */
  length n_display $12 pct_display $12;
  if n_count <= 11 then do;
    n_display   = '<11';
    pct_display = '<11';
    suppressed  = 1;
  end;
  else do;
    n_display   = strip(put(n_count, comma12.));
    pct_display = strip(put(pct, 6.1));
    suppressed  = 0;
  end;
run;
```

### Pattern 7: ODS EXCEL Multi-Sheet with KEY Leftmost
**What:** Open ODS EXCEL once. Write KEY sheet first (leftmost). Switch sheets using
`ods excel options(sheet_name="D1")`. Close once at the end.

**Established pattern from Program 09:**
```sas
ods excel file="&qc_path.\17_summary_stats_by_domain.xlsx"
    options(sheet_name="KEY"
            embedded_titles="yes"
            autofilter="all"
            frozen_headers="1");

/* ... write KEY sheet content ... */

ods excel options(sheet_name="D1");
/* ... write D1 content ... */

/* repeat for D2, D3, D4, D5, Crosswalk, QC */
ods excel close;
```

**UF Colors:** Header rows must use `style(header)=[background=CX0021A5 color=white fontweight=bold]`
(per CLAUDE.md: #0021A5 blue, #FA4616 orange). Use blue for headers, orange sparingly for
accent if needed.

### Anti-Patterns to Avoid
- **`IS NOT MISSING` in DATA step:** PROC SQL / WHERE syntax only. In DATA step: `NOT MISSING(x)`. This has bitten the pipeline three times.
- **`PROC MEANS` on character variables:** Fatal error. Always route by type first.
- **`&SQLOBS`:** Never use. Use explicit `SELECT COUNT(*) INTO :macvar TRIMMED`.
- **Bare open-code `%IF`:** All conditional logic in named macros. `%IF/%THEN` in open code requires `%DO` block.
- **`%PUT` with apostrophes or embedded semicolons:** A `%PUT` ends at its first semicolon; an apostrophe opens an unclosed string.
- **`%abort cancel` in open code:** Must be inside a named macro (PCM-R-05).
- **Writing to `g.` on left of DATA statement for source datasets:** `g.analysis_base` and `g.master_data_merged` are read-only sources.
- **Using `g.analysis_base_ext` as permanent:** Decision D-01 explicitly says it is temporary/working only.
- **Double-quoting label strings in generated code:** Use single quotes to prevent `&` or `%` in dictionary descriptions from resolving as macro triggers (learned from Program 16, Section 1).
- **`dictionary.columns.TYPE` compared against 1 or 2:** The dictionary form uses `'num'` and `'char'` (character strings), not numeric 1/2.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Excel multi-sheet output | Custom CSV writer or PROC EXPORT per sheet | ODS EXCEL | Native .xlsx, sheet control, style support |
| Distinct counts | One COUNT(DISTINCT) query per variable | PROC FREQ NLEVELS on `_ALL_` | Single pass over the dataset; dramatically faster on P: drive |
| Dictionary CSV parsing | Custom DATA step reader | PROC IMPORT with `guessingrows=max` | Already established in Program 16 |
| Variable type detection | Parsing variable names | `dictionary.columns` TYPE column | Reliable; handles edge cases |
| Label application to working dataset | Inline label statement in PROC REPORT | Generated .sas file with PROC DATASETS MODIFY LABEL | Prevents macro trigger resolution in dictionary text |

---

## Common Pitfalls

### Pitfall 1: PRECEDE_STUDY_ID Type Conflict
**What goes wrong:** Left join of `g.analysis_base` (CHAR $12 key) to `g.master_data_merged`
(contains NUM8 key from md7 contribution) silently produces all-missing extended columns if
types differ.
**Why it happens:** SAS merges only match on identical type. A numeric key value like 123456789012
does not match the character string `"123456789012"`.
**How to avoid:** Cast the key to CHAR $12 in a WORK copy of the extension columns before the merge.
**Warning signs:** Row count of `work.analysis_base_ext` equals `g.analysis_base` (join succeeded)
but D3 and frailty variables are all missing.

### Pitfall 2: Sentinel Recoding After Statistics
**What goes wrong:** If `-999` or literal `'NULL'` are not cleared before PROC MEANS, the
minimum value for a continuous variable will be `-999`, mean will be wrong, and standard
deviation will be inflated.
**How to avoid:** Recode first, then stat. Log recode counts before recoding.

### Pitfall 3: Small-Cell Suppression Missed for Per-Year Cells
**What goes wrong:** Suppression applied to pooled column but not to year-specific columns.
A year with 5 patients for a level shows the real count.
**How to avoid:** Apply suppression logic to every count column (pooled AND each year block)
in a single post-statistics data step.

### Pitfall 4: `VARnn` Positional Names in Crosswalk
**What goes wrong:** The SAS XLSX engine assigns names like `VAR37` when headers do not
parse. If any of these survive into `g.var_domain_map`, the crosswalk is defective.
**How to avoid:** After the dictionary match, assert that no matched variable name matches
the pattern `/^VAR\d+$/` and fail if any do.

### Pitfall 5: `PRECEDE_Study_ID_1` Duplicate in md6
**What goes wrong:** If `g.master_data_merged` still carries this column and it is pulled into
the extension, it appears as a second PRECEDE_STUDY_ID-like column in the crosswalk.
**How to avoid:** Explicitly exclude it from the `KEEP=` list when reading extension columns.

### Pitfall 6: `_30_DAY_MORTALITY` Missingness Interpretation
**What goes wrong:** Treating all missing values of `_30_DAY_MORTALITY` in D5 as outcome
missingness when they actually reflect join missingness from the md1 left join.
**How to avoid:** Add a note in the D5 sheet and QC sheet: "missingness reflects join to
master_data_1, not the outcome. Rows not in md1 have missing `_30_DAY_MORTALITY` by
construction."

### Pitfall 7: Blank `domain_rationale` Passing QC
**What goes wrong:** The domain map is accepted with one or more empty rationale fields.
**How to avoid:** Assert in code: `SELECT COUNT(*) INTO :n_blank_rationale FROM g.var_domain_map WHERE missing(domain_rationale);` and abort if `n_blank_rationale > 0`.

### Pitfall 8: `master_data_8` Row Count as Denominator
**What goes wrong:** Using md8 row count (1,048,575 — Excel ceiling truncation) as any
denominator for coverage or percentage.
**How to avoid:** Always denominate against `g.analysis_base_ext` row count. Never reference
md8 row counts directly.

### Pitfall 9: Per-Year Block Width in ODS EXCEL
**What goes wrong:** If there are many calendar years, the per-year column blocks make each
domain sheet very wide (potentially hundreds of columns). ODS EXCEL handles this, but PROC
REPORT column lists can become unwieldy.
**How to avoid:** Determine the distinct year values before opening ODS EXCEL. Generate the
PROC REPORT column list dynamically using a macro loop over years. Verify year count is
reasonable (expected: 5–10 fiscal or calendar years).

### Pitfall 10: ODS EXCEL File Locked from Prior Run
**What goes wrong:** If the previous workbook is open in Excel and the program tries to write,
the ODS EXCEL open fails or the old file is not replaced.
**How to avoid:** Use the `filename` / `fdelete` pattern from Program 09 to delete the prior
workbook before opening ODS EXCEL, and fail clearly if `fdelete` returns non-zero.

---

## Code Examples

### Dictionary Import and Match Scaffold
```sas
/* Source: Program 16_summary_docx.sas, Sections 0-1 — directly reusable */
proc import datafile="&docs_path.\precede_dictionary.csv"
    out=work.dict_raw dbms=csv replace;
  guessingrows=max;
run;

data work.dict;
  length sheet $40 dict_name $60 dict_type $20 sas_name $32;
  set work.dict_raw (rename=(sheet=_s dict_name=_n dict_type=_t sas_name=_a));
  sheet     = strip(cats(_s));
  dict_name = strip(cats(_n));
  dict_type = strip(cats(_t));
  sas_name  = upcase(strip(cats(_a)));
  if missing(sas_name) then delete;
  if sheet = 'MASTER_DATASET' then sheet_rank = 1;
  else if sheet = 'DERIVED_VARIABLES_MASTER' then sheet_rank = 2;
  else sheet_rank = 3;
  keep sheet dict_name dict_type sas_name sheet_rank;
run;

proc sort data=work.dict; by sas_name sheet_rank; run;

data work.dict_u;
  set work.dict;
  by sas_name;
  if first.sas_name;
run;
```

### Existence Check Pattern (from established pipeline)
```sas
/* Source: Programs 09, 16 — standard pattern */
proc sql noprint;
  select count(*) into :n_tab trimmed
  from dictionary.tables
  where libname='G' and memname='ANALYSIS_BASE_EXT';
quit;

%macro check_ext;
  %if &n_tab ne 1 %then %do;
    %fail_out(msg=work.analysis_base_ext not found -- run build step first);
  %end;
%mend check_ext;
%check_ext;
```

### Blank Rationale Guard
```sas
/* Assert after g.var_domain_map is built, before any statistics */
proc sql noprint;
  select count(*) into :n_blank trimmed
  from g.var_domain_map
  where missing(domain_rationale)
    and domain not in ('OUT_OF_SCOPE');
quit;

%macro check_rationale;
  %if &n_blank > 0 %then %do;
    %fail_out(msg=&n_blank variables have blank domain_rationale -- Checkpoint 1 cannot proceed);
  %end;
%mend check_rationale;
%check_rationale;
```

### PROC MEANS with STACKODSOUTPUT (per domain)
```sas
/* Source: Program 09_summary_stats.sas, Section 3 */
ods listing close;
ods output summary=work.means_d1_pooled;
proc means data=work.analysis_base_clean
           n nmiss mean std median p25 p75 min max
           stackodsoutput;
  var &num_d1_varlist;  /* space-separated list of numeric D1 variables */
run;
ods output close;
ods listing;
```

### PROC FREQ with MISSING for Categorical Variables
```sas
/* Capture output to a dataset; split missing into its own column after */
ods listing close;
ods output onewayfreqs=work.freq_d1_pooled;
proc freq data=work.analysis_base_clean;
  tables &chr_d1_varlist / missing nocum;
run;
ods output close;
ods listing;

/* Split missing level into n_missing column */
data work.freq_d1_display;
  set work.freq_d1_pooled;
  /* ODS ONEWAYFREQS produces Table, F_<varname>, Frequency, Percent */
  /* missing level identified by missing(F_<varname>) or value = '' */
run;
```

---

## Wave Structure (from spec §5)

| Wave | Steps | Output | Checkpoint |
|------|-------|--------|------------|
| Wave 1 | Sections 1–4: build ext dataset, import dictionary, match, assign domains | `g.var_domain_map` exported to Crosswalk sheet draft | Checkpoint 1: Gerard reviews domain assignment variable-by-variable |
| Wave 2 | Sections 5–8: sentinel recode, PROC MEANS, PROC FREQ, suppression | `work.stats_*` datasets per domain | — |
| Wave 3 | Sections 9–10: ODS EXCEL assembly, QC artifact | `qc\17_summary_stats_by_domain.xlsx`, `qc\17_summary_stats_by_domain.txt` | Checkpoint 2: Review workbook against data dictionary |

---

## Environment Availability

Step 2.6: Confirmed no external dependencies beyond SAS 9.4M8 (already installed) and the
P: drive data path. No new tools required.

| Dependency | Required By | Available | Notes |
|------------|-------------|-----------|-------|
| SAS 9.4M8 | All computation | Yes | Project constraint, already in use |
| ODS EXCEL | Workbook output | Yes | Used in Program 09 successfully |
| P: drive (g_path) | `g.analysis_base`, `g.master_data_merged` | Yes | All prior phases read from here |
| `docs/precede_dictionary.csv` | Wave 1 dictionary import | Yes | Used by Program 16 |
| `qc\` folder | Output workbook | Yes | Path via `&qc_path` from 00_config.sas |
| `logs\` folder | Log routing | Yes | Path via `&logs_path` from 00_config.sas |

---

## Open Questions

1. **Year variable name in `g.analysis_base`**
   - What we know: A calendar or fiscal year column is assumed to exist for D-03 per-year stratification
   - What is unclear: The exact column name (could be `Year`, `FiscalYear`, `SurgeryYear`, etc.)
   - Recommendation: Wave 0 task — run PROC CONTENTS on `g.analysis_base` and identify the year
     column before the plan finalizes. If no year column exists, it may need to be derived from
     a surgery date column.

2. **Exact set of extension columns from `g.master_data_merged`**
   - What we know: Frailty score, frailty components, cognitive score, intraoperative physiologic
     block (md8 hemodynamic variables) are the targets
   - What is unclear: Exact column names for the full hemodynamic block and any additional
     cognitive instrument columns from md7 or other sources
   - Recommendation: Wave 0 task — run PROC CONTENTS on `g.master_data_merged` filtered to
     columns NOT in `g.analysis_base`; review against the domain taxonomy to enumerate the
     exact KEEP= list.

3. **Calendar years present in the data**
   - What we know: `master_data_8` was truncated in 2021; multiple source files cover different
     year ranges
   - What is unclear: How many distinct calendar years exist in `g.analysis_base_ext` and
     whether any year has very few patients (raising suppression frequency concerns for per-year
     blocks)
   - Recommendation: Wave 0 task — `PROC FREQ` on the year variable; document the year range
     and per-year N before designing per-year column layout.

4. **`domain_rationale` authorship for Wave 1**
   - What we know: Every variable needs a one-line rationale citing which of the three rules
     applied; Checkpoint 1 is a human review before stats run
   - What is unclear: Whether the rationale strings will be authored in code (as SAS character
     literals in a DATA step) or imported from a separate mapping CSV
   - Recommendation: Author rationales in code as a DATA step lookup table keyed on variable
     name. This keeps them version-controlled and makes the Checkpoint 1 review reproducible.

---

## Sources

### Primary (HIGH confidence)
- `sas/16_summary_docx.sas` — ODS EXCEL patterns, dictionary matching scaffold, label application, PCM compliance rules
- `sas/09_summary_stats.sas` — PROC MEANS STACKODSOUTPUT, PROC FREQ NLEVELS, type routing, ODS EXCEL KEY-leftmost pattern, identifier suppression
- `sas/00_config.sas` — Path macros, `in_pipeline` flag convention
- `sas/07_cohort.sas` — `g.analysis_base` structure and scope
- `.planning/phases/17-summary-stats-by-domain-context/17-CONTEXT.md` — Locked decisions D-01/D-02/D-03
- `summary-stats-by-domain-CONTEXT (1).md` — Authoritative spec: domain taxonomy, assignment rules, pitfall list, wave plan, exit criteria

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` — Phase 17 is new; no requirement IDs yet assigned; SUMM-01/SUMM-02 are already marked complete for Phase 11 scope
- `.planning/STATE.md` — Project at 84% completion, current focus Phase 14

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools established in existing SAS programs
- Architecture: HIGH — three-wave structure from authoritative spec; code patterns verified from Programs 09 and 16
- Pitfalls: HIGH — all sourced from spec §6 and PCM compliance notes in existing programs

**Research date:** 2026-09-03
**Valid until:** 2026-10-03 (stable SAS 9.4 environment; no external dependencies)
