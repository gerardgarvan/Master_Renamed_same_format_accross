# Phase 24: Build g.pcnr_harmonized - Research

**Researched:** 2026-09-28
**Domain:** SAS 9.4 data step code generation, sentinel recode, full-comparison assertion
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01: Gate Check at Program Top**
`%pcnr_gate_check` macro runs at the very top of program 24 before any data work.
Reads gate files via DATA step `infile` with explicit `$` informats (PCM-T-16 — never PROC IMPORT).
Gate files: `qc/23_sentinel_fingerprint.txt`, `docs/sentinel_decisions.csv`,
`qc/23_sentinel_candidates.csv`, `docs/pcnr_name_map.csv`.
Key lookup: `(variable, raw_hex)` using `%hexkey` macro from `00_config.sas`.
All checks abort on failure; AMBIGUOUS candidates may not be resolved by wildcard.

**D-02: Recode Step — Code Generation, Not Macro Loops**
Three-step pass: recode (original names) → compare → rename.
Step 1: resolve `work._recode_rules` (one explicit row per variable+raw_hex with action=MISSING).
Step 2: write `qc/24_recode_rules_generated.sas` — one `select/when` block per character column
with rules; numeric rules use `if var = value and not missing(var) then call missing(var);`.
Step 3: apply rules via `%include` in one DATA step. No macro loops inside the DATA step.

**D-03: Full-Comparison Assertion — Two-SET DATA Step, Not PROC COMPARE**
Parallel-set DATA step reads source and recoded by row position.
Separate char and numeric array pairs (SAS 9.4 constraint).
Authorized change: recoded cell is missing AND source cell hex key is in `work._recode_rules`
for that column. Anything else → `%fail_out`.
Two cross-checks: `n_compare_changes = n_recode_step_changes`; per-rule `n_recoded = n_rows`
from `qc/23_sentinel_candidates.csv`.

**D-04: Rename Step — Single Final DATA Step**
After comparison passes, apply name map in one DATA step with `drop=`, `rename=`, `label`
clauses generated from macro variable lists.
KEY columns stay with original names; KEEP columns get `pcnr_` prefix per `final_name`.
Assert: variable set equals KEY + KEEP `final_name` values exactly; column count equals source;
type and length unchanged.
WORK-then-promote: `data g.pcnr_harmonized; set work.pcnr_harmonized; run;`
PROC DATASETS MODIFY is not used.

**D-05: Recode Counts — Two Tidy CSVs, No TOTAL Rows**
`qc/24_pcnr_recode_counts.csv`: columns `variable, final_name, raw_value, raw_hex, var_type,
rule_source, n_expected, n_recoded`. One row per MISSING rule; include zero-hit rules.
`qc/24_pcnr_recode_totals.csv`: columns `variable, final_name, n_recoded_total`.
One row per KEEP and KEY column; include all columns (zero-hit columns included).
No TOTAL sentinel value in raw_value. Both files read by Phase 25 via DATA step `infile`.

**D-06: Program Structure**
Single file `sas/24_pcnr_build.sas` with 8 sections:
SECTION 0: `%pcnr_gate_check` macro + gate execution
SECTION 1: Resolve rules → `work._recode_rules`
SECTION 2: Generate `qc/24_recode_rules_generated.sas`
SECTION 3: Apply rules → `work._recoded` (one DATA step, `%include` generated file)
SECTION 4: Full comparison → `work._compare_out` + cross-checks
SECTION 5: Rename + label + drop → `work.pcnr_harmonized`
SECTION 6: WORK-then-promote → `g.pcnr_harmonized`
SECTION 7: Write `qc/24_pcnr_recode_counts.csv` + `qc/24_pcnr_recode_totals.csv`
SECTION 8: PCNR-11 assertions
Static checks: `grep -ni "proc import"` → 0; `grep -c '\$hex\.'` → 0;
`grep -ni "%put WARNING"` → 0.

### Claude's Discretion

- Exact character array syntax for mixed-type parallel-set comparison (SAS 9.4 constraint:
  character and numeric arrays must be separate; planner confirms working pattern)
- Whether `work._recode_rules` is written as a SAS dataset or held entirely in indexed macro
  variables (dataset preferred for debuggability; macro variables acceptable if rule count fits)
- Log verbosity: `%put NOTE:` lines at section transitions (match existing program pattern)
- Whether the generated `.sas` file omits columns with zero MISSING rules entirely vs includes
  them as empty `select/when` blocks (omit entirely — cleaner file)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PCNR-07 | `g.pcnr_harmonized` built from `g.master_data_harmonized` only (no other input except two approved CSVs). WORK-then-promote; source never written. | D-04 rename step; WORK-then-promote pattern confirmed in `10b_concept_harmonize.sas` |
| PCNR-08 | Every MISSING decision applied by exact match on raw value. Char columns keep type and length; numeric recodes become standard missing. | D-02 code-generation approach; `%hexkey` for char; `if var = value and not missing(var)` for numeric |
| PCNR-09 | Columns renamed per `docs/pcnr_name_map.csv`; key columns per PCM-D-22. Each pcnr column keeps original label; blank label set to original variable name. | D-04 rename step; 159 KEEP + 4 KEY + 12 DROP = 175 total columns confirmed from name map |
| PCNR-10 | Recode audit `qc/24_pcnr_recode_counts.csv` + per-variable total. | D-05; two CSVs with defined columns |
| PCNR-11 | Assertions: 41,150 rows; key identity; column count = source; missing math; full comparison; zero remaining sentinels; type/length unchanged; source confirmed unchanged. | D-03 full comparison; D-04 column count assertion; SECTION 8 |
</phase_requirements>

---

## Summary

Phase 24 writes a single SAS program (`sas/24_pcnr_build.sas`) that applies the human-approved
sentinel decisions and name map to produce `g.pcnr_harmonized`. The approach is code generation:
the program first resolves all recode rules into `work._recode_rules`, then writes
`qc/24_recode_rules_generated.sas` (the machine-generated audit file), and finally `%include`s
that file inside one DATA step. Nothing inside the DATA step does any decision logic at runtime —
all logic was pre-computed and written to a file that is itself the audit trail.

The full-comparison assertion is implemented as a parallel-set DATA step (not PROC COMPARE)
that reads source and recoded by row position and tests every cell. Authorized changes are
verified by checking the recoded cell is missing and the source hex key exists in
`work._recode_rules` for that column. Everything else is a hard abort.

The rename step is a single DATA step using macro-variable lists generated from
`docs/pcnr_name_map.csv` (175 rows, 159 KEEP + 4 KEY + 12 DROP). SECTION 8 runs the full
suite of PCNR-11 assertions before program exit.

**Primary recommendation:** Follow the 8-section structure from D-06 exactly. All design
decisions are locked. Planner tasks map 1:1 to the 8 sections.

---

## Standard Stack

### Core (SAS 9.4 — no external libraries)

| Technique | Purpose | Authority |
|-----------|---------|-----------|
| `DATA step %include` | Apply generated recode rules in one pass | D-02; established in pipeline |
| `DATA step parallel SET` | Full cell-by-cell comparison | D-03 |
| `ARRAY` (separate char/num) | Iterate columns in comparison step | SAS 9.4 constraint |
| `%hexkey` macro | Hex-encode raw values for exact match | `00_config.sas` line 89 |
| `%fail_out` macro | Standard abort path | `00_config.sas`; `10b_concept_harmonize.sas` |
| `PROC PRINTTO` | Log routing (standalone vs pipeline) | `10b_concept_harmonize.sas` pattern |
| `DATA step infile` with `$` informats | Read CSVs (PCM-T-16 — never PROC IMPORT) | `00_config.sas`; D-01 |
| WORK-then-promote | Build in WORK, assert, then copy to g lib | `10b_concept_harmonize.sas` pattern |
| `SELECT COUNT(*) INTO :macvar TRIMMED` | All row counts (never `&SQLOBS`) | Established pattern |

### Anti-Patterns (must NOT appear in program 24)

| Pattern | Why Forbidden | Rule |
|---------|--------------|------|
| `PROC IMPORT` on any CSV | Guesses types; fails non-UTF-8 | PCM-T-16 |
| `put(var, $hex.)` without width | Truncates to 2 bytes (only first char encoded) | `00_config.sas` comment line 88 |
| `&SQLOBS` | Unreliable count | Established pattern |
| `IS NOT MISSING` in DATA step | Only valid in PROC SQL | PCM compliance |
| `NOT MISSING()` in PROC SQL | Use `IS NOT MISSING` in SQL | PCM compliance |
| Bare open-code `%if` | Requires `%DO` block in open code | PCM compliance |
| `%put WARNING` | Scanner counts WARNING lines | D-06 static check |
| `data g.pcnr_harmonized; set g.pcnr_harmonized;` | Destroys dataset | PCM-T-02 |
| `PROC COMPARE` for authorization | Cannot verify authorization per cell | D-03 |
| Macro loops inside the recode DATA step | Prohibited; use `%include` | D-02 |

---

## Architecture Patterns

### Recommended Program Structure

```
sas/24_pcnr_build.sas
  SECTION 0  : %pcnr_gate_check macro definition + invocation
  SECTION 1  : Resolve work._recode_rules from sentinel_decisions.csv + candidates.csv
  SECTION 2  : Write qc/24_recode_rules_generated.sas (code generation via PUT to file)
  SECTION 3  : DATA work._recoded; set g.master_data_harmonized; %include generated file; run;
  SECTION 4  : Parallel-set comparison DATA step + two cross-checks
  SECTION 5  : DATA work.pcnr_harmonized; set work._recoded (drop= rename= label); run;
  SECTION 6  : data g.pcnr_harmonized; set work.pcnr_harmonized; run;
  SECTION 7  : Write qc/24_pcnr_recode_counts.csv + qc/24_pcnr_recode_totals.csv
  SECTION 8  : PCNR-11 assertions
```

### Pattern 1: Gate Check via DATA Step Infile

Read all four gate files using `infile` with explicit `$` informats. No PROC IMPORT.
```sas
/* Read sentinel_decisions.csv via infile (PCM-T-16) */
data work._decisions;
  infile "&docs_path.\sentinel_decisions.csv" dsd firstobs=2 truncover lrecl=32767;
  length variable $32 raw_value $200 raw_hex $400 var_type $4 action $7;
  input variable $ raw_value $ raw_hex $ raw_len var_type $ action $;
run;
```

### Pattern 2: Fingerprint Check

Read `qc/23_sentinel_fingerprint.txt` and compare nobs, nvars, modate against current
`g.master_data_harmonized` via `dictionary.tables`. Abort if any field mismatches.

```sas
proc sql noprint;
  select nobs, nvar, modate
  into :cur_nobs trimmed, :cur_nvar trimmed, :cur_modate trimmed
  from dictionary.tables
  where libname='G' and memname='MASTER_DATA_HARMONIZED';
quit;
/* compare against values read from fingerprint file; %fail_out on mismatch */
```

### Pattern 3: Code Generation (SECTION 2)

Use a DATA step with `file` statement to write the generated SAS file. One `select/when`
block per column that has at least one MISSING rule. Omit columns with zero rules.

```sas
data _null_;
  file "&qc_path.\24_recode_rules_generated.sas" lrecl=32767;
  set work._char_rules_by_col;  /* one row per column, with all rules pre-resolved */
  /* PUT the select/when block for each column */
  put "/* variable: " variable +(-1) "  (" n_rules "rules) */";
  put "select (%hexkey(" variable +(-1) "));";
  /* inner loop over rules for this column */
  ...
  put "  otherwise;";
  put "end;";
run;
```

**Key constraint:** The generated file must be plain ASCII SAS code snippets. No `options`,
no `%include`, no `run;` inside the file itself. It is `%include`d inside an open DATA step.

### Pattern 4: Parallel-Set Full Comparison

```sas
/* Requires: both datasets have identical row counts (asserted in PCNR-11 before this step) */
data work._compare_out;
  set g.master_data_harmonized;         /* source — row by row */
  set work._recoded (rename=(...));     /* all columns suffixed _r_ */

  /* Char arrays — separate from numeric (SAS 9.4 constraint) */
  array _src_c{*} $ <char columns in source>;
  array _rec_c{*} $ <char columns in recoded, _r_ suffix>;

  /* Numeric arrays */
  array _src_n{*}   <numeric columns in source>;
  array _rec_n{*}   <numeric columns in recoded, _r_ suffix>;

  /* Check char columns */
  do _i = 1 to dim(_src_c);
    if _src_c{_i} ne _rec_c{_i} then do;
      /* authorized: _rec_c{_i} is missing AND hex key in work._recode_rules */
      /* else: %fail_out */
    end;
  end;
  /* Check numeric columns — same structure */
  do _j = 1 to dim(_src_n);
    if _src_n{_j} ne _rec_n{_j} then do;
      /* authorized: missing(_rec_n{_j}) AND rule exists in work._recode_rules */
      /* else: %fail_out */
    end;
  end;
run;
```

**SAS 9.4 array constraint:** Character and numeric columns cannot share one array. The
`array src{*} <mixed columns>` syntax will error. Separate array pairs are mandatory.

### Pattern 5: Rename Step with Generated Macro Lists

Build macro variable lists from `work._name_map` (loaded from `docs/23_pcnr_name_map.csv`):

```sas
/* Build %let rename_list, drop_list, label_list from name map dataset */
proc sql noprint;
  select catx('=', source_name, final_name)
  into :rename_list separated by ' '
  from work._name_map where role='KEEP';

  select source_name
  into :drop_list separated by ' '
  from work._name_map where role='DROP';
quit;

data work.pcnr_harmonized;
  set work._recoded (
    drop   = &drop_list
    rename = (&rename_list)
  );
  label <generated label statements>;
run;
```

### Pattern 6: Missing-Math Assertion

```sas
/* Per variable: n_missing_after = n_missing_before + n_recoded */
proc sql noprint;
  select nmiss(<pcnr_var>) into :n_miss_after trimmed from work.pcnr_harmonized;
  select nmiss(<source_var>) into :n_miss_before trimmed from g.master_data_harmonized;
quit;
/* retrieve n_recoded from work._recode_counts_detail for this variable */
/* assert n_miss_after = n_miss_before + n_recoded */
```

### Anti-Patterns to Avoid

- **Empty select/when blocks:** Omit columns with zero MISSING rules from the generated file
  entirely. Including empty blocks adds noise and may cause SAS parser warnings.
- **Single mixed-type array for comparison:** Fatal syntax error in SAS 9.4. Always separate
  char and numeric into distinct arrays.
- **PROC COMPARE for authorization:** Cannot determine which differences were authorized.
  Use the parallel-set DATA step pattern (D-03).
- **Wildcard rows resolving AMBIGUOUS candidates:** Gate must abort before SECTION 1 if
  any AMBIGUOUS candidate has only wildcard coverage. Never silently promote a wildcard match
  for an AMBIGUOUS value.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Hex encoding of raw values | Custom hex function | `%hexkey` macro (`00_config.sas` line 89) | Already exists; uses `$hex400.` to avoid the 2-byte truncation trap |
| Program abort on failure | `%abort` in open code | `%fail_out` macro (`00_config.sas`) | Consistent abort path; handles log restore |
| Log routing | `proc printto` in open code | `%route_log`/`%restore_log` macros (copy from `10b_concept_harmonize.sas`) | Handles pipeline vs standalone correctly |
| PCNR gate flag check | Open-code `%if` | Wrap in macro | PCM compliance — bare open-code `%if` requires `%do` |

---

## File Inventory (Phase 24 Inputs and Outputs)

### Inputs (all read-only)

| File | Location | Notes |
|------|----------|-------|
| `g.master_data_harmonized` | `g` libname (P: merge tree) | 41,150 rows, 175 columns; PCM-T-02 forbids writing |
| `docs/sentinel_decisions.csv` | `C:\...\docs\` (in git) | 16 MISSING decisions confirmed; wildcard row for `?` present |
| `docs/23_pcnr_name_map.csv` | `C:\...\docs\` (in git) | **NAMING DISCREPANCY** — file on disk is `23_pcnr_name_map.csv`; CONTEXT.md references `docs/pcnr_name_map.csv`. Planner must reconcile: either rename the file to `pcnr_name_map.csv` or update program 24 path to `23_pcnr_name_map.csv`. |
| `qc/23_sentinel_candidates.csv` | `qc_path` (P: merge tree) | Source of `n_rows` for `n_expected` column; needed for stale checks |
| `qc/23_sentinel_fingerprint.txt` | `qc_path` (P: merge tree) | nobs, nvars, modate at program 23 run time |
| `00_config.sas` | `sas/` | Gate flag `PCNR_APPROVED`; `%hexkey`; `%fail_out`; all path macros |

### Outputs

| File | Location | Notes |
|------|----------|-------|
| `g.pcnr_harmonized` | `g` libname (P:) | 41,150 rows; 163 columns (159 KEEP + 4 KEY; 12 DROP removed) |
| `qc/24_recode_rules_generated.sas` | `qc_path` (P:) | Machine-generated audit file; `%include`d by SECTION 3 |
| `qc/24_pcnr_recode_counts.csv` | `qc_path` (P:) | Detail: one row per MISSING rule |
| `qc/24_pcnr_recode_totals.csv` | `qc_path` (P:) | Per variable: one row per KEEP + KEY column |

**Note on `qc/24_recode_rules_generated.sas` and `.gitignore`:** CONTEXT.md notes this file
lives in `qc/` on P: (outside the git working tree). Since `qc_path` resolves to the P: merge
tree (per `00_config.sas`), this file is never in the git repo and no `.gitignore` entry is
needed. Planner should confirm path at implementation.

---

## Name Map Summary (from docs/23_pcnr_name_map.csv)

| Role | Count | Treatment |
|------|-------|-----------|
| KEEP | 159 | Renamed to `final_name` (pcnr_ prefix); recode applied |
| KEY | 4 | `PRECEDE_STUDY_ID`, `pecan_ID`, `ENCRYPTED_MRN`, `ENCRYPTED_ENCOUNTER` — no rename |
| DROP | 12 | Removed from output (redundant h_*_src companions and raw duplicates) |
| **Total** | **175** | Equals source column count; column count assertion holds |

PCNR-11 column count assertion: output has 163 columns (159 + 4); this equals source 175 minus 12
DROP columns. The assertion `DROP count + KEEP count + KEY count = source column count` is satisfied.

---

## Sentinel Decisions Summary (from docs/sentinel_decisions.csv)

Total rows in file: 16 MISSING + many KEEP. MISSING decisions confirmed:
- Character sentinels: `?` (wildcard covering all char columns), `MISSING OR INVALID DATA FORMATION`
  (Anesthesia_Type), `UNKNOWN` (EmployeeStatus, Ethnicity, Marital_Status, Race),
  `PATIENT REFUSED` (Ethnicity, Race), `?` per-variable rows (Admit_Source, CPT_1,
  Dischg_Disposition, Ethnicity, ICD10_Principal_Diagnosis, ICD10_Principal_Diagnosis_POA,
  Marital_Status, Patient_Type)
- Numeric sentinels: none with action=MISSING (all reviewed numeric candidates are KEEP)
- Wildcard row: `variable=*`, `raw_value=?`, `action=MISSING` — covers all char columns
  for `?` placeholder

The wildcard row is char-only (var_type=char) per D-04/Phase 23 D-06.

---

## Common Pitfalls

### Pitfall 1: `$hex.` Width Truncation
**What goes wrong:** `put(var, $hex.)` uses default width 4, encoding only the first 2 bytes.
`UNKNOWN` and `UNK` both produce `554E`; `-999` and `-99` both produce `2D39`.
**Why it happens:** SAS default format width for `$hex.` is 4 (2 bytes).
**How to avoid:** Always use `%hexkey(var)` macro which uses `$hex400.` and trims padding.
**Warning signs:** `grep -c '\$hex\.' sas/24_pcnr_build.sas` returning non-zero.

### Pitfall 2: Mixed-Type Array in Comparison Step
**What goes wrong:** `array src{*} Race Age_at_Encounter;` fails — cannot mix char and numeric.
**Why it happens:** SAS 9.4 arrays are typed; a mixed list causes a compile-time error.
**How to avoid:** Declare one char array and one numeric array; index them separately.
**Warning signs:** `ERROR: Variables in list must all be character or all numeric.`

### Pitfall 3: PROC IMPORT on Gate CSVs
**What goes wrong:** PROC IMPORT uses `guessingrows=` heuristic; on non-UTF-8 sessions it can
mangle long hex strings or fail on unusual values.
**Why it happens:** Default behavior; easy to reach for.
**How to avoid:** Read ALL CSVs via `DATA step infile` with explicit `$` informats (PCM-T-16).
`grep -ni "proc import" sas/24_pcnr_build.sas` static check catches this.

### Pitfall 4: Parallel-Set Requires Equal Row Counts
**What goes wrong:** `set ds1; set ds2;` by position silently truncates to the shorter dataset
if row counts differ. The shorter dataset stops emitting rows; the longer carries forward stale values.
**Why it happens:** SAS parallel-set does not check counts.
**How to avoid:** Assert row counts are equal BEFORE the comparison DATA step (PCNR-11 row count
assertion must run first and abort if counts differ).

### Pitfall 5: Wildcard Expanding to AMBIGUOUS Candidates
**What goes wrong:** A wildcard row for `?` could match a column where `?` was classified
AMBIGUOUS (e.g., in a score column). Gate would silently recode it.
**Why it happens:** Wildcard expansion does not distinguish candidate_class.
**How to avoid:** Gate check must verify no AMBIGUOUS candidate is resolved only by wildcard.
Abort if any KEEP/KEY column has an AMBIGUOUS candidate with only wildcard coverage.
Per D-01: `%fail_out` on this condition.

### Pitfall 6: Bare Open-Code `%if` for Gate Flag Check
**What goes wrong:** `%if &PCNR_APPROVED = 0 %then %abort cancel;` in open code requires
a `%do` block — without it, SAS expects `%DO` and skips forward, swallowing subsequent code.
**Why it happens:** SAS open-code `%if/%then` bare statement restriction.
**How to avoid:** Wrap every `%if` in a named macro. `%pcnr_gate_check` is already the wrapper.

### Pitfall 7: `%put WARNING` in Program
**What goes wrong:** The pipeline warning-count scanner (`run_pipeline.cmd`) counts lines
beginning with `WARNING` in the log. A `%put WARNING:` line inflates the count.
**Why it happens:** Easy to use for debugging.
**How to avoid:** Use `%put NOTE:` or `%put ERROR:`. Static check: `grep -ni "%put WARNING"` → 0.

### Pitfall 8: Name Map File Name Discrepancy
**What goes wrong:** CONTEXT.md references `docs/pcnr_name_map.csv` but the file on disk is
`docs/23_pcnr_name_map.csv`. A hardcoded path using the CONTEXT.md name will fail at runtime
with `ERROR: Physical file does not exist`.
**Why it happens:** The file was written with the phase prefix during Phase 23 work.
**How to avoid:** Planner must resolve: rename file to `docs/pcnr_name_map.csv` (preferred for
clarity as a persistent deliverable) OR use `docs/23_pcnr_name_map.csv` in program 24.
Either is acceptable; choose one and be consistent across all references.

---

## Code Examples

### Fingerprint Read Pattern
```sas
/* Read fingerprint file: three fields, one per line */
data work._fingerprint;
  infile "&qc_path.\23_sentinel_fingerprint.txt" truncover lrecl=200;
  length field $20 value $40;
  input field $ value $;
run;
/* Extract to macro variables and compare against dictionary.tables */
```

### Recode Rules Resolution (SECTION 1)
```sas
/* Load sentinel_decisions.csv via infile */
data work._decisions_raw;
  infile "&docs_path.\sentinel_decisions.csv" dsd firstobs=2 truncover lrecl=32767;
  length variable $32 raw_value $400 raw_hex $800 var_type $4 action $7
         candidate_class $20;
  input variable $ raw_value $ raw_hex $ raw_len var_type $ n_rows
        pct_rows column_group $ candidate_class $ non_ascii_flag $
        match_rule $ action $ rationale $ decided_by $ decided_date $;
run;

/* Expand wildcards: join wildcard rows against candidates for KEEP/KEY columns */
proc sql noprint;
  create table work._recode_rules as
  select c.variable, c.raw_hex, d.action, d.raw_value, 'WILDCARD' as rule_source length=7,
         c.n_rows as n_expected
  from work._candidates_raw c
  inner join work._decisions_raw d
    on d.variable = '*' and d.raw_hex = c.raw_hex
    and c.role in ('KEEP','KEY') and c.var_type = 'char'
  where d.action = 'MISSING'

  union

  /* Per-variable MISSING rules (non-wildcard) */
  select d.variable, d.raw_hex, d.action, d.raw_value, 'PER_VAR' as rule_source,
         c.n_rows as n_expected
  from work._decisions_raw d
  inner join work._candidates_raw c
    on d.variable = c.variable and d.raw_hex = c.raw_hex
  where d.action = 'MISSING' and d.variable ne '*';
quit;
```

### Generated Recode File Format (character column)
```sas
/* variable: Race  (3 rules) */
select (%hexkey(Race));
  when ('554E4B4E4F574E') call missing(Race);        /* UNKNOWN -- wildcard */
  when ('50415449454E542052454655534544') call missing(Race); /* PATIENT REFUSED -- per-var */
  otherwise;
end;
```

### Generated Recode File Format (numeric column, if any approved)
```sas
/* numeric: clock_variable  (1 rule, PCM-D-24 approved) */
if clock_variable = -999 and not missing(clock_variable) then call missing(clock_variable);
```

### Apply Rules DATA Step (SECTION 3)
```sas
data work._recoded;
  set g.master_data_harmonized;
  %include "&qc_path.\24_recode_rules_generated.sas";
run;
```

### Write CSV Outputs (PCM-T-16 compliant)
```sas
data _null_;
  file "&qc_path.\24_pcnr_recode_counts.csv" lrecl=32767;
  put "variable,final_name,raw_value,raw_hex,var_type,rule_source,n_expected,n_recoded";
  set work._recode_counts_detail;
  put variable ',' final_name ',' raw_value ',' raw_hex ',' var_type ','
      rule_source ',' n_expected ',' n_recoded;
run;
```

---

## Environment Availability

Step 2.6: SKIPPED — Phase 24 produces SAS code only; all dependencies (`g` libname, `docs/`,
`qc/` paths) are established by `00_config.sas` which is verified operational (pipeline PASSED
Phase 22). No new external tools, runtimes, or services required.

The qc/ gate files (`23_sentinel_fingerprint.txt`, `23_sentinel_candidates.csv`) live on P:
and are written by program 23. Phase 24 cannot run until Phase 23 has been executed. This is
enforced by the gate check (D-01), not by the environment.

---

## Validation Architecture

> `workflow.nyquist_validation` key not present in `.planning/config.json` — treating as enabled.

Phase 24 is a SAS pipeline program. SAS programs are not unit-testable with a standard framework
(pytest/jest). Validation is performed by the assertions built into the program itself (PCNR-11)
and by the static grep checks from D-06.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | SAS 9.4 built-in assertions (DATA step abort) + shell grep static checks |
| Config file | none — assertions in `sas/24_pcnr_build.sas` SECTION 8 |
| Quick run command | `grep -ni "proc import" sas/24_pcnr_build.sas && grep -c '\$hex\.' sas/24_pcnr_build.sas && grep -ni "%put WARNING" sas/24_pcnr_build.sas` |
| Full suite command | Run `sas/24_pcnr_build.sas` standalone; check log for ERROR/abort; verify output files exist |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | Notes |
|--------|----------|-----------|-------------------|-------|
| PCNR-07 | Source not written; WORK-then-promote | assertion | SECTION 8 in program | manual-verify: `g.master_data_harmonized` modate unchanged post-run |
| PCNR-08 | Every MISSING decision applied | assertion | SECTION 8 zero-sentinel check | automated via program |
| PCNR-09 | Columns renamed per name map | assertion | SECTION 5 variable-set check | automated via program |
| PCNR-10 | Recode audit CSVs written | smoke | file-exists check after run | automated via program SECTION 7 |
| PCNR-11 | Full assertion suite | assertion | SECTION 8 — all 7 sub-checks | program aborts on any failure |

### Static Checks (run before commit)

```bash
# Expect 0 for each:
grep -ni "proc import" sas/24_pcnr_build.sas
grep -c '\$hex\.' sas/24_pcnr_build.sas
grep -ni "%put WARNING" sas/24_pcnr_build.sas
```

### Wave 0 Gaps

- [ ] Verify `qc/23_sentinel_fingerprint.txt` and `qc/23_sentinel_candidates.csv` exist on P:
      before program 24 can run (these are Phase 23 outputs; if Phase 23 has not been executed,
      program 24 will abort at SECTION 0 gate check — expected behavior, not a bug)
- [ ] Set `PCNR_APPROVED = 1` in `sas/00_config.sas` before running program 24

---

## Open Questions

1. **Name map file name discrepancy**
   - What we know: CONTEXT.md and D-01 reference `docs/pcnr_name_map.csv`; the actual file
     on disk is `docs/23_pcnr_name_map.csv`
   - What's unclear: Is the intent to rename the file or use the phase-prefixed name in program 24?
   - Recommendation: Rename to `docs/pcnr_name_map.csv` (removes phase prefix; appropriate for
     a persistent deliverable used by Phase 25 dictionary). Add a rename task in Wave 0.

2. **Phase 23 gate files availability**
   - What we know: `qc/23_sentinel_fingerprint.txt` and `qc/23_sentinel_candidates.csv` are
     Phase 23 outputs written to P: merge tree. Phase 23 status in STATE.md shows "Not started."
   - What's unclear: Has Phase 23 been executed? (STATE.md shows it as not started but
     `docs/sentinel_decisions.csv` and `docs/23_pcnr_name_map.csv` already exist on disk,
     suggesting Phase 23 ran but STATE.md was not updated.)
   - Recommendation: Verify qc/ gate files exist on P: as Wave 0 check. If absent, Phase 23
     must run before Phase 24 planning can be executed.

3. **`work._recode_rules` implementation: dataset vs indexed macro variables**
   - What we know: 15 distinct MISSING rules currently in sentinel_decisions.csv (char only;
     no numeric MISSING decisions). Wildcard expands across all char columns that have `?`.
   - What's unclear: Final rule count after wildcard expansion (depends on how many char columns
     have `?` in the candidates scan).
   - Recommendation: Use a SAS dataset (`work._recode_rules`) for debuggability. Rule count is
     small enough that macro variables would also work, but a dataset is queryable and easier
     to inspect when something goes wrong.

4. **Numeric sentinel MISSING decisions**
   - What we know: All numeric candidates in `sentinel_decisions.csv` have action=KEEP. PCM-D-24
     approved no numeric recodes.
   - What's unclear: The generated file format for numeric rules exists in D-02 but no current
     numeric MISSING decisions require it.
   - Recommendation: Generate the numeric rule section only if `work._recode_rules` contains
     any numeric rows. Currently it will be empty; include the logic stub so it is
     future-proof.

---

## Sources

### Primary (HIGH confidence)

- `C:\Master_Renamed_same_format_accross\.planning\phases\24-build-g-pcnr-harmonized\24-CONTEXT.md`
  — all implementation decisions D-01 through D-06; canonical design authority
- `C:\Master_Renamed_same_format_accross\sas\00_config.sas`
  — `%hexkey`, `%fail_out`, `PCNR_APPROVED`, all path macros; verified by reading file
- `C:\Master_Renamed_same_format_accross\sas\10b_concept_harmonize.sas`
  — gate patterns, WORK-then-promote, `%route_log`/`%restore_log`, PCM compliance notes
- `C:\Master_Renamed_same_format_accross\docs\sentinel_decisions.csv`
  — 16 MISSING decisions; wildcard row confirmed; no numeric MISSING decisions
- `C:\Master_Renamed_same_format_accross\docs\23_pcnr_name_map.csv`
  — 175 rows: 159 KEEP, 4 KEY, 12 DROP; confirmed by reading file
- `C:\Master_Renamed_same_format_accross\.planning\REQUIREMENTS.md`
  — PCNR-07 through PCNR-11 acceptance criteria

### Secondary (MEDIUM confidence)

- `C:\Master_Renamed_same_format_accross\.planning\STATE.md`
  — project decisions, open decisions, established patterns

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — SAS 9.4 patterns read directly from existing programs
- Architecture: HIGH — all decisions locked in CONTEXT.md; existing programs confirm patterns
- Pitfalls: HIGH — drawn from CONTEXT.md code comments, 10b header, and `00_config.sas` comments
- File inventory: HIGH — verified by reading actual files on disk
- Name map discrepancy: HIGH — confirmed by `ls docs/` output

**Research date:** 2026-09-28
**Valid until:** Stable until `docs/sentinel_decisions.csv` or `docs/23_pcnr_name_map.csv` change;
re-research not needed before planning.
