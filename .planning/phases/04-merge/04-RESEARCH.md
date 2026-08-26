# Phase 4: Merge - Research

**Researched:** 2026-08-26
**Domain:** SAS 9.4M8 on Windows -- BY-key DATA step merge, ownership-map-governed variable
assignment, provenance flag construction, spine-first row-count guarantee
**Confidence:** HIGH -- all patterns are native SAS 9.4 already established in Phases 1-3;
merge inputs are fully specified by the Phase 3 contract

---

## Project Constraints (from CLAUDE.md)

- SAS 9.4M8 on Windows; session encoding is NOT UTF-8 -- encoding damage confined to
  `Base_Procedure_1`, <=9 rows; flag only, do not re-encode (PCM-C-01)
- Source files `master_data_1..8.sas7bdat` are **read-only** -- Phase 4 reads from `g.prep_mdN`,
  never from `src.master_data_N` directly
- No PHI in git: `.sas7bdat`, `.xlsx`, `.csv`, `data/` tree are gitignored; only `.sas` programs
  and plain-text QC/log artifacts may be committed
- No `data X; set X;` patterns (destroys dataset, PCM-T-02)
- No PROC SQL UPDATE (silent truncation, PCM-T-01)
- `%abort cancel` must be inside a macro definition -- never in open code (PCM-R-05)
- `SELECT COUNT(*) INTO :n TRIMMED` for all counted assertions -- never `&SQLOBS`
- Single ownership per variable (prevents last-wins overwrite, PCM-T-05)
- md3 is the merge spine (PCM-F-02); 41,150 rows drives the pipeline target (MRG-01)
- g library path: `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge`
  (all Phase 3 programs use this value; Phase 4 must use the same path)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MRG-01 | User can run `04_merge.sas` to produce `g.master_data_merged` with exactly 41,150 rows and 41,150 distinct IDs | DATA step MERGE on sorted `PRECEDE_STUDY_ID` with md3 first (spine); post-merge SELECT COUNT(*) assertion; distinct-ID assertion via PROC SQL |
| MRG-02 | User can verify zero blank `PRECEDE_STUDY_ID` values in the merged output | PROC SQL assertion `WHERE missing(PRECEDE_STUDY_ID)` = 0 against `g.master_data_merged` after merge |
| MRG-03 | User can verify provenance flags `in_md1`--`in_md8` and `n_sources` are present and match source row counts | Flags assigned in the DATA step from `IN=` dataset options; `n_sources` is the sum; post-merge counts verified against `qc/src_counts.txt` values |
| MRG-04 | User can verify md3 is listed first (spine); no last-wins overwrite is possible for any variable | md3 listed first in MERGE statement; every CONFLICT variable is assigned from one named source using explicit IF-THEN assignment, never relying on last-observation-wins order |
</phase_requirements>

---

## Summary

Phase 4 produces `04_merge.sas`, a single SAS program that reads the eight `g.prep_mdN`
persistent datasets produced by Phase 3 and merges them on `PRECEDE_STUDY_ID` to produce
`g.master_data_merged` with exactly 41,150 rows and 41,150 distinct IDs.

The operation is a 1:1 merge, not a PROC APPEND stack-and-dedup. md3 is listed first in the
DATA step MERGE statement because it is the complete superset (PCM-F-02): every PRECEDE_STUDY_ID
in the merged file comes from md3. The non-md3 sources contribute additional variables only;
they do not add rows. This is enforced structurally by the merge key alignment, not by any
post-hoc dedup step.

Variable assignment is the central intellectual challenge of this phase. The ownership map at
`qc/02_ownership_map.txt` (and the machine-readable `qclib.ownership_map` SAS dataset) lists
163 variables; 135 of them are marked CONFLICT (appear in more than one source). For every
CONFLICT variable, the merge program must use an explicit assignment statement that names
exactly one source -- never relying on the last-observation-wins default. Variables that appear
in only one source are assigned automatically by the DATA step because they are unique to that
source's contribution.

Provenance flags `in_md1`--`in_md8` (8 binary indicators) and `n_sources` (count of sources
contributing to each row) are derived from the DATA step `IN=` dataset options. These flags
serve as the primary audit trail for which sources contributed to each merged record.

**Primary recommendation:** Single DATA step merge with explicit LENGTH block, IN= flags, and
explicit owner-assignment for every CONFLICT variable. Sort all eight prep datasets by
PRECEDE_STUDY_ID before the merge. Write to `g.master_data_merged`. Follow with a five-part
assertion block (row count, distinct IDs, blank key, provenance totals, no surviving NULL
strings).

---

## What Phase 3 Delivers to Phase 4

This is the verified contract from `03-VERIFICATION.md` and the actual Phase 3 SAS programs.
Phase 4 must not assume anything beyond this.

### Input Datasets

All inputs are persistent SAS datasets in the g library
(`P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge`):

| Dataset | Rows | PRECEDE_STUDY_ID | Key anomalies resolved |
|---------|------|------------------|------------------------|
| `g.prep_md1` | 14,778 | unique, non-blank | LENGTH-before-SET; no forced-char numerics; NULL sentinel scan passed |
| `g.prep_md2` | 14,778 | unique, non-blank | Same as md1 |
| `g.prep_md3` | 41,150 | unique, non-blank | **Spine**; 41,150 hard-asserted in prep |
| `g.prep_md4` | 7,695 | unique, non-blank | `Base_Procedure_Code_1` harmonized to CHAR $10 (PREP-07) |
| `g.prep_md5` | 7,695 | unique, non-blank | Same as md4 |
| `g.prep_md6` | 9,462 | unique, non-blank | `PRECEDE_Study_ID_1` dropped; `Base_Procedure_Code_1` to CHAR $10 |
| `g.prep_md7` | 9,215 | unique, non-blank | `Base_Procedure_Code_1` to CHAR $10 |
| `g.prep_md8` | 22,473 | unique, non-blank | Eight forced-char numerics converted; NULL sentinel cleared throughout |

### Type Guarantees from Phase 3

After PREP-07 and PREP-03, all eight prep datasets deliver:
- `Base_Procedure_Code_1`: CHARACTER $10 in all eight sources (no type conflict at merge)
- The eight md8 forced-char numerics (`Admit_BMI`, `ASA__Anesth_Record_`, `Age_at_Encounter`,
  `Cognitive_Score`, `Frailty_Score`, `rt_INCISE_to_DRESS_mins`, `rt_RM_START_to_INCISION_mins`,
  `rt_RM_START_to_RM_END_mins`): NUMERIC in `g.prep_md8`, matching the type in other sources

### Remaining Type Splits Requiring Merge-Time Attention

Phase 3 did NOT harmonize death and frailty naming conflicts (PCM-D-01, PCM-D-02) -- those are
Phase 6 blockers requiring Erin's sign-off. Phase 4 must bring these variables in from their
respective owners without attempting reconciliation:

| Variable | Owner(s) | Action in Phase 4 |
|----------|----------|-------------------|
| `Death_Date_Y_N` | md1, md2, md3, md4, md5 (all CONFLICT) | Declare one owner per ownership map; bring in as-is |
| `IsDead_Y_N` | md6 only | Single-source; automatic (no conflict) |
| `Death` | md7 only | Single-source; automatic (no conflict) |
| `Frailty_Score` | md3, md4, md5, md6, md7, md8 (CONFLICT) | Declare one owner per ownership map |
| `Cognitive_Score` | md3, md4, md5, md6, md7, md8 (CONFLICT) | Declare one owner per ownership map |

The DECISIONS.md conflict block from Phase 2 names these as pending (PCM-D-01, PCM-D-02).
Phase 4 must bring them in and note in-code comments that resolution is deferred to Phase 6.

### Known Variable-Width Variations Across Sources

The `qc/03_charvars_all.txt` artifact is the single source of truth for character widths.
Key variations the LENGTH block in `04_merge.sas` must accommodate (take the MAX across sources):

| Variable | Max width across all sources | Source of max |
|----------|------------------------------|---------------|
| `Base_Procedure_1` | 199 | md3, md6, md7 |
| `CPT_1_Description` | 75 | md3, md4, md5, md6, md8 |
| `Dischg_Disposition` | 43 | md3, md4, md5 |
| `Room_Type` | 22 | md3, md6, md7 |
| `Race` | 16 | md1-md5, md8 (md6, md7 are $15) |
| `EmployeeStatus` | 23 | md1-md3, md7, md8 (md4, md5 are $18; md6 is $19) |
| `ENCRYPTED_ENCOUNTER` | 49 | md1-md3, md8 (md4-md7 are $46 or $44) |
| `Feels_Exausted` | 3 | md7 ($1 in md6) |
| `Low_Physical_Activity` | 3 | md7 ($1 in md6) |
| `Slow_Walking_Speed` | 3 | md7 ($1 in md6) |
| `Unintended_Weight_Loss` | 3 | md7 ($1 in md6) |
| `Week_Grip_Strength` | 3 | md7 ($1 in md6) |
| `CPT_1` | 8 | md1-md3, md8 (md4-md7 are $6) |

The merged LENGTH block must declare the MAX width for each variable. Under-declaring causes
truncation. Over-declaring wastes bytes but is safe.

---

## Standard Stack

### Core

| Tool/Pattern | Version | Purpose | Why Standard |
|---|---|---|---|
| `DATA g.master_data_merged; LENGTH ...; MERGE g.prep_md3(IN=in3) g.prep_md4(IN=in4) ...; BY PRECEDE_STUDY_ID; ...` | SAS 9.4 | The merge operation itself | DATA step BY-merge is the SAS-standard tool for 1:1 key merge; explicit BY-key enforcement; IN= flags built in |
| `PROC SORT DATA=g.prep_mdN; BY PRECEDE_STUDY_ID;` (x8) | SAS 9.4 | Pre-sort all inputs before merge | DATA step MERGE requires BY-sorted inputs; violating this produces wrong results without error |
| `IN=in_mdN` dataset option on each source in the MERGE statement | SAS 9.4 | Provenance flag source (MRG-03) | IN= is a compile-time option; the resulting automatic variable is 1 if that dataset contributed to the current observation, 0 otherwise |
| `in_md1=in1; in_md2=in2; ...` explicit flag assignment | SAS 9.4 | Make provenance flags permanent variables in output | IN= automatic variables are dropped by default; must be assigned to retained variables to persist in the output dataset |
| `n_sources = in_md1 + in_md2 + ... + in_md8;` | SAS 9.4 | Row-level source count (MRG-03) | Sum of binary flags; range 1-8; all-zero is impossible if BY merge is correct |
| `PROC SQL; SELECT COUNT(*) INTO :n TRIMMED FROM g.master_data_merged;` | SAS 9.4 | Post-merge row-count assertion (MRG-01) | Established Phase 1-3 pattern; never &SQLOBS |
| `%abort cancel;` inside a named macro | SAS 9.4 | Loud failure on assertion violation | PCM-R-05; established Phases 1-3 |

### Supporting

| Tool/Pattern | Version | Purpose | When to Use |
|---|---|---|---|
| `PROC SORT NODUPKEY DATA=g.prep_mdN OUT=work.sort_mdN;` | SAS 9.4 | Detect duplicate keys before merge (precondition) | Run against all 8 inputs; if any record is dropped, the source violated SRC-01 -- abort |
| `%sysfunc(libref(g))` | SAS 9.4 | Verify g library assigned before attempting to read prep datasets | Section 1 precondition |
| `dictionary.columns WHERE libname='G' AND memname='PREP_MD3'` | SAS 9.4 | Assert all expected inputs exist before merge runs | Precondition check: if any `g.prep_mdN` is missing, abort with message to re-run Phase 3 |
| `PROC SQL; SELECT COUNT(DISTINCT PRECEDE_STUDY_ID) INTO :n_dist TRIMMED` | SAS 9.4 | Assert 41,150 distinct IDs post-merge (MRG-01) | Separate from row-count assertion; both must agree |
| `FILE/PUT` to `logs/04_merge_log.txt` | SAS 9.4 | Write merge summary (analogous to Phase 3 conversion logs) | Consistent with pipeline logging convention |

### No External Packages

All tools are SAS 9.4 base product. No macro libraries beyond what is defined inline.

---

## Architecture Patterns

### Recommended Program Structure

```
04_merge.sas
  SECTION 0: Options, %let paths, libname g
  SECTION 1: Preconditions
    1a. g library resolves
    1b. logs/ directory exists
    1c. All 8 g.prep_mdN datasets exist (dictionary.tables check)
    1d. Each g.prep_mdN has expected row count (from qc/src_counts.txt)
    1e. PROC SORT NODUPKEY precondition -- zero rows dropped from each input
  SECTION 2: Pre-sort all 8 inputs by PRECEDE_STUDY_ID
  SECTION 3: Ownership-map-governed DATA step merge
    3a. LENGTH block for ALL variables in the merged file (MAX width across sources)
    3b. MERGE g.prep_md3(IN=in3) g.prep_md4(IN=in4) ... g.prep_md8(IN=in8);
        [md3 FIRST -- spine]
    3c. BY PRECEDE_STUDY_ID;
    3d. Provenance flag assignment: in_md1=in1; ...; n_sources = sum;
    3e. Explicit owner assignment for every CONFLICT variable
    3f. Output: g.master_data_merged
  SECTION 4: Merge summary log
    4a. Row count, distinct IDs, in_mdN totals per provenance flag
    4b. Write to logs/04_merge_log.txt
  SECTION 5: Assertions
    5a. Row count = 41,150 (MRG-01)
    5b. Distinct PRECEDE_STUDY_ID = 41,150 (MRG-01)
    5c. Zero blank PRECEDE_STUDY_ID (MRG-02)
    5d. Provenance flag totals match source row counts (MRG-03)
    5e. No surviving NULL strings in any character variable (carryover from PREP-03)
  SECTION 6: Close-out
    %put NOTE: ==== Phase 4 merge complete ====
    libname g clear (or leave open for 99_run_all.sas)
```

### Pattern 1: Pre-sort and duplicate-key precondition

```sas
/* Pre-sort all 8 inputs and assert no duplicate keys exist.
   PROC SORT NODUPKEY with OUT= does NOT modify the source dataset.
   If any rows are dropped, SRC-01 was violated in that source -- abort.
   Do NOT sort g.prep_mdN in-place (data X; set X; pattern, PCM-T-02).   */
%macro sort_and_check(dsn=, expected_nobs=);
  proc sort data=g.&dsn out=work.sort_&dsn nodupkey;
    by PRECEDE_STUDY_ID;
  run;
  proc sql noprint;
    select count(*) into :n_sorted trimmed from work.sort_&dsn;
  quit;
  %if &n_sorted ne &expected_nobs %then %do;
    %put ERROR: MRG PRECONDITION -- &dsn has duplicate PRECEDE_STUDY_ID keys.;
    %put ERROR-   Expected &expected_nobs unique rows; NODUPKEY kept &n_sorted.;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- &dsn has &n_sorted unique keys.;
%mend sort_and_check;

%sort_and_check(dsn=prep_md1, expected_nobs=14778);
%sort_and_check(dsn=prep_md2, expected_nobs=14778);
%sort_and_check(dsn=prep_md3, expected_nobs=41150);
%sort_and_check(dsn=prep_md4, expected_nobs=7695);
%sort_and_check(dsn=prep_md5, expected_nobs=7695);
%sort_and_check(dsn=prep_md6, expected_nobs=9462);
%sort_and_check(dsn=prep_md7, expected_nobs=9215);
%sort_and_check(dsn=prep_md8, expected_nobs=22473);
```

**Why NODUPKEY before merge:** A duplicate key in any source would cause the DATA step merge
to produce more than 41,150 rows (or misaligned values). SRC-01 was asserted in Phase 1, but
checking again here is cheap and catches any corruption that occurred during Phase 3 prep.

**Why OUT=work.sort_* not in-place:** Sorting g.prep_mdN in-place would violate PCM-T-02 if
done via `data g.prep_mdN; set g.prep_mdN;` and would overwrite a dataset produced by Phase 3.
PROC SORT with OUT= writes to WORK, preserving the g datasets unchanged.

**Alternative:** If the prep datasets were already sorted by PRECEDE_STUDY_ID during Phase 3
(not asserted in the Phase 3 code), a `PROC SORT` with `OUT=` is still required because SAS
does not assume sort order. Do not skip this step.

**Confidence:** HIGH -- PROC SORT NODUPKEY with OUT= is SAS 9.4 base; established pattern.

### Pattern 2: The merge DATA step (ownership-governed, spine-first)

```sas
/* The merge operation.
   CRITICAL structural rules (all locked decisions):
     1. md3 MUST be listed first -- it is the spine (PCM-F-02, MRG-04).
     2. Every CONFLICT variable MUST have an explicit owner assignment below
        the BY statement -- relying on last-observation-wins order is
        prohibited (PCM-T-05, MRG-04).
     3. IN= variables (in1-in8) are automatic and dropped by default.
        Assign them immediately to persistent variables (in_md1--in_md8).
     4. LENGTH block declares MAX width across all sources for every character
        variable. Source of truth: qc/03_charvars_all.txt.                  */

data g.master_data_merged;
  length
    /* Key */
    PRECEDE_STUDY_ID          $12

    /* Provenance flags (new variables) */
    in_md1  3    /* 0/1 flag: md1 contributed to this row */
    in_md2  3
    in_md3  3
    in_md4  3
    in_md5  3
    in_md6  3
    in_md7  3
    in_md8  3
    n_sources 3  /* count of contributing sources, range 1-8 */

    /* Character variables -- MAX width across all sources.
       Widths from qc/03_charvars_all.txt (Wave 0 artifact).
       Never declare a width narrower than the maximum found in any source. */
    ENCRYPTED_MRN              $40
    ENCRYPTED_ENCOUNTER        $49
    Day_of_Week__CHAR_         $3
    Holidays                   $1
    Weekend_Indicator          $1
    EmployeeStatus             $23
    Education                  $19
    Race                       $16
    Ethnicity                  $15
    Sex                        $6
    Marital_Status             $22
    Service                    $32
    Room_Type                  $22
    Emergent                   $4    /* md8 has $4; others have $1 */
    Base_Procedure_1           $199
    Base_Procedure_Code_1      $10
    CPT_1                      $8
    CPT_1_Description          $75
    CPT1_Label                 $96
    Patient_Type               $18
    Payer                      $12
    ICD10_Principal_Diagnosis_Desc $60
    ICD10_Principal_Diagnosis  $7
    ICD10_Principal_Diagnosis_POA $6
    Intraop_Ketamine           $4    /* md8 has $4; others $1 */
    Preop_block                $4    /* md8 has $4; others $1 */
    Admit_Source               $40
    Dischg_Disposition         $43
    Death_Date_Y_N             $1
    SSDI_Death_Date_Y_N        $1
    SSDI_Death_Y_N             $1
    IsDead_Y_N                 $1    /* md6 only */
    Death                      $1    /* md7 only */
    SSDI_Death                 $1    /* md7 only */
    _30_DAY_MORTALITY          $1    /* md1, md2 only */
    Anesthesia_Type            $33
    Sleep_Apnea_YN             $1
    Sleep_Apnea                $1    /* md4, md5 naming variant */
    Diabetes_YN                $1
    Diabetes                   $1    /* md4, md5 */
    Hyperlipidemia_YN          $1
    Hyperlipidemia             $1    /* md4, md5 */
    Hypertension_YN            $1
    Hypertension               $1    /* md4, md5 */
    MovementDisorder_YN        $1
    MovementDisorder           $1    /* md4, md5 */
    CognitiveDisorder_YN       $1
    Cognitive_Disorder         $1    /* md4, md5 */
    Cognitive_Category         $22
    Frailty_Category           $24
    Feels_Exausted             $3    /* md7=$3; md6=$1 -- take max */
    Feels_Exausted_Value       $... /* md3, md5 -- get width from 03_contents_all.txt */
    Low_Physical_Activity      $3
    Low_Physical_Activity_Value $...
    Slow_Walking_Speed         $3
    Slow_Walking_Speed_Value   $...
    Unintended_Weight_Loss     $3
    Unintended_Weight_Loss_Value $...
    Week_Grip_Strength         $3
    Week_Grip_Strength_Value   $...
    /* ... remaining character variables from qc/03_contents_all.txt ... */
    ;

  merge
    work.sort_prep_md3 (IN=in3)   /* SPINE -- listed FIRST (MRG-04, PCM-F-02) */
    work.sort_prep_md1 (IN=in1)
    work.sort_prep_md2 (IN=in2)
    work.sort_prep_md4 (IN=in4)
    work.sort_prep_md5 (IN=in5)
    work.sort_prep_md6 (IN=in6)
    work.sort_prep_md7 (IN=in7)
    work.sort_prep_md8 (IN=in8)
    ;
  by PRECEDE_STUDY_ID;

  /* --- Provenance flags (MRG-03) --- */
  in_md1 = in1;
  in_md2 = in2;
  in_md3 = in3;
  in_md4 = in4;
  in_md5 = in5;
  in_md6 = in6;
  in_md7 = in7;
  in_md8 = in8;
  n_sources = in_md1 + in_md2 + in_md3 + in_md4 + in_md5 + in_md6 + in_md7 + in_md8;

  /* --- Owner assignments for CONFLICT variables (MRG-04, PCM-T-05) ---
     Each CONFLICT variable is assigned from exactly one owner.
     The ownership map (qc/02_ownership_map.txt) governs which source is
     the declared owner. For PENDING decisions (PCM-D-01, PCM-D-02), the
     planner must choose a provisional owner that can be re-examined in Phase 6
     WITHOUT rerunning the merge. The safest choice is md3 for any variable
     md3 carries, since md3 is the spine and has 41,150 rows.

     Pattern:
       varname = sourcename.varname;
     becomes:
       if in_mdN then actual_var = var_from_mdN;
     BUT the correct SAS DATA step approach for merge is simpler:
     list the variable from the owning source's IN= block.
     The cleanest approach is RENAME= on non-owning sources to suppress
     their copies, or use explicit IF-assignment after the BY statement.

     IMPLEMENTATION CHOICE: use RENAME= to suppress non-owner copies.
     For each CONFLICT variable, rename the non-owner copies to _drop_*
     names and DROP them at the end. The owner's copy keeps the canonical name.
     This is explicit, auditable, and does not rely on merge order.           */

  /* Example for Admit_BMI -- owner: md3 (has 41,150 rows; most complete).
     Non-owners: md1, md2, md4, md5, md6, md7 -- rename suppresses their copies.
     md8 type is now NUMERIC (Phase 3 PREP-03) so no type conflict remains.   */
  /* [Planner generates one rename-based suppression block per CONFLICT var]  */

run;
```

**CRITICAL NOTE on the ownership assignment implementation:**

There are two valid implementation strategies for CONFLICT variable ownership. The planner
must choose one and apply it consistently:

**Strategy A: RENAME= on non-owner datasets (preferred)**
In the MERGE statement, use `RENAME=(conflict_var=_drop_conflict_var)` on every non-owner
dataset. At the end of the DATA step, DROP all `_drop_*` variables. The owner dataset's
copy of the variable keeps its canonical name and is the only copy in the output. This is
explicit, requires no IF-THEN logic in the DATA step body, and is auditable by reading the
MERGE statement.

```sas
merge
  work.sort_prep_md3 (IN=in3)   /* owns: Admit_BMI, Age_at_Encounter, ... */
  work.sort_prep_md1 (IN=in1
    rename=(Admit_BMI=_d_Admit_BMI_md1
            Age_at_Encounter=_d_Age_md1))
  ...
  ;
drop _d_: ;   /* drop all suppressed non-owner copies */
```

**Strategy B: Explicit IF-THEN after BY**
Retain all copies with distinct names using RENAME=, then assign the canonical name
from the declared owner in the DATA step body. More verbose but equally explicit.

Strategy A is preferred for this pipeline because it keeps the ownership declaration in
the MERGE statement (a single auditable location) and requires fewer lines in the DATA step
body. The planner should generate the RENAME= block for all 135 CONFLICT variables.

**Confidence:** HIGH -- RENAME= dataset option and DROP statement are SAS 9.4 base; behavior
is well-established.

### Pattern 3: Post-merge assertions

```sas
/* Five-part assertion block (MRG-01 through MRG-03). */

proc sql noprint;
  /* MRG-01a: row count */
  select count(*) into :n_merged trimmed from g.master_data_merged;
  /* MRG-01b: distinct ID count */
  select count(distinct PRECEDE_STUDY_ID) into :n_dist trimmed
    from g.master_data_merged;
  /* MRG-02: blank key */
  select count(*) into :n_blank_key trimmed
    from g.master_data_merged
    where missing(PRECEDE_STUDY_ID);
  /* MRG-03: provenance flag totals */
  select sum(in_md1) into :n_in_md1 trimmed from g.master_data_merged;
  select sum(in_md2) into :n_in_md2 trimmed from g.master_data_merged;
  select sum(in_md3) into :n_in_md3 trimmed from g.master_data_merged;
  select sum(in_md4) into :n_in_md4 trimmed from g.master_data_merged;
  select sum(in_md5) into :n_in_md5 trimmed from g.master_data_merged;
  select sum(in_md6) into :n_in_md6 trimmed from g.master_data_merged;
  select sum(in_md7) into :n_in_md7 trimmed from g.master_data_merged;
  select sum(in_md8) into :n_in_md8 trimmed from g.master_data_merged;
quit;

%macro assert_eq(actual=, expected=, label=);
  %if &actual ne &expected %then %do;
    %put ERROR: MRG ASSERTION FAILED -- &label: expected &expected got &actual;
    %abort cancel;
  %end;
  %else %put NOTE: MRG ASSERTION OK -- &label = &actual;
%mend assert_eq;

%assert_eq(actual=&n_merged,     expected=41150, label=merged row count);
%assert_eq(actual=&n_dist,       expected=41150, label=distinct PRECEDE_STUDY_ID);
%assert_eq(actual=&n_blank_key,  expected=0,     label=blank PRECEDE_STUDY_ID count);
%assert_eq(actual=&n_in_md1,     expected=14778, label=in_md1 total);
%assert_eq(actual=&n_in_md2,     expected=14778, label=in_md2 total);
%assert_eq(actual=&n_in_md3,     expected=41150, label=in_md3 total);
%assert_eq(actual=&n_in_md4,     expected=7695,  label=in_md4 total);
%assert_eq(actual=&n_in_md5,     expected=7695,  label=in_md5 total);
%assert_eq(actual=&n_in_md6,     expected=9462,  label=in_md6 total);
%assert_eq(actual=&n_in_md7,     expected=9215,  label=in_md7 total);
%assert_eq(actual=&n_in_md8,     expected=22473, label=in_md8 total);
```

**Confidence:** HIGH -- same assertion pattern established in Phases 1-3.

### Pattern 4: No-surviving-NULL assertion (carried forward from PREP-03)

```sas
/* Phase 3 cleared all NULL sentinels from g.prep_md8.
   Phase 4 must assert they did not propagate into g.master_data_merged.
   Enumerate character variables explicitly -- do not use ARRAY _CHARACTER_
   in PROC SQL (not supported there). Run in a DATA step with a flag.      */
data _null_;
  set g.master_data_merged end=eof;
  retain _n_null 0;
  /* Enumerate every character variable that had NULL sentinel risk.
     md8 character variables are the risk scope.                          */
  if strip(upcase(PRECEDE_STUDY_ID))  = 'NULL' then _n_null + 1;
  if strip(upcase(Race))              = 'NULL' then _n_null + 1;
  if strip(upcase(Ethnicity))         = 'NULL' then _n_null + 1;
  /* ... all character variables from the merged file ... */
  if eof then call symputx('n_null_merged', _n_null, 'G');
run;
%assert_eq(actual=&n_null_merged, expected=0, label=surviving NULL sentinel strings);
```

**Confidence:** HIGH.

### Anti-Patterns to Avoid

- **Last-observation-wins in a multi-source DATA step merge:** When `MERGE` lists multiple
  datasets and the same variable appears in more than one, SAS assigns the value from the
  LAST dataset that has a non-missing (or any) value for that variable. The order of datasets
  in the MERGE statement determines whose value "wins" -- and that order is an accidental
  dependency, not a declared ownership rule. PCM-T-05 prohibits this. Use RENAME= explicitly.

- **Listing md3 anywhere other than first in the MERGE statement:** md3 is the spine.
  Placing it anywhere else does not cause a SAS error (the merge still completes), but it
  violates the documented architecture and makes MRG-04 unverifiable. MRG-04 explicitly
  requires "md3 is listed first." Always list it first.

- **Sorting g.prep_mdN in-place:** `PROC SORT DATA=g.prep_md3;` without `OUT=` rewrites the
  g dataset in-place. While PROC SORT is safer than `data X; set X;`, it still modifies the
  Phase 3 output and conflicts with the principle that Phase 4 does not modify Phase 3 outputs.
  Always use `OUT=work.sort_prep_mdN`.

- **Omitting IN= flags from the MERGE statement:** If any dataset in the MERGE statement
  lacks an `IN=` option, its provenance flag is unavailable. `n_sources` will be wrong for
  rows contributed by that source. All eight sources must have `IN=` options.

- **Declaring LENGTH for a character variable narrower than its maximum source width:**
  The merged LENGTH block must use the MAX across all sources. Under-declaring causes
  truncation of values that fit in the source but not in the merged dataset.

- **Using PROC SQL UPDATE to assign CONFLICT variable values:** PCM-T-01 prohibits PROC SQL
  UPDATE. The correct tool is the DATA step MERGE with RENAME=.

- **Assuming the sort order of g.prep_mdN datasets from Phase 3:** The Phase 3 prep programs
  write to g.prep_mdN but do not sort by PRECEDE_STUDY_ID as a final step. Do not assume the
  datasets are sorted -- always PROC SORT before the MERGE.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| 1:1 key merge across 8 sorted datasets | Custom PROC SQL multi-table join or iterative DATA step stacking | `DATA step MERGE ... BY PRECEDE_STUDY_ID;` | DATA step MERGE is the SAS-standard tool for 1:1 horizontal merge on a key; produces exactly one output row per key value; predictable, auditable |
| Provenance tracking | Separate lookup table built by post-merge PROC SQL | `IN=` dataset options on each MERGE source | `IN=` flags are produced at merge time with zero overhead; they are the correct tool for this purpose |
| Ownership enforcement | Hand-coded IF-THEN checking which source contributed each variable | `RENAME=` on non-owner datasets in MERGE statement | RENAME= is a declarative, compile-time specification; it cannot accidentally be bypassed by data values |
| Row count validation | Manual PROC PRINT scan | `PROC SQL SELECT COUNT(*) INTO :n TRIMMED` + `%abort cancel` | Established Phase 1-3 pattern; machine-verifiable; hard stop on violation |

---

## Ownership Map -- What the Merge Program Must Implement

The `qc/02_ownership_map.txt` artifact (run 26AUG2026) lists 163 unique variable names.

**Variables with a single source (automatic assignment, no RENAME= needed):**

From the ownership map, these have N_Src=1 and will be contributed only by their one source:
`ABP_LESS_THAN_60_COUNT`, `ABP_LESS_THAN_70_COUNT`, `ABP_LESS_THAN_80_COUNT`,
`AVG_ABP_MEAN`, `AVG_BIS_INDEX`, `AVG_NIBP_MEAN`, `BIS_INDEX_LESS_30_COUNT`,
`BIS_INDEX_LESS_40_COUNT`, `DEATH` (md7), `ISO_SEV_INTRAOP_MAC_AVERAGE` (md4),
`ISO_SEV_MAC_TOTAL_EXP` (md8), `ISDEAD_Y_N` (md6), `NIBP_LESS_60_COUNT`,
`NIBP_LESS_70_COUNT`, `NIBP_LESS_80_COUNT`, `PRECEDE_STUDY_ID_1` (but this was DROPPED in
Phase 3 prep -- Phase 4 must not try to bring it in), `SSDI_DEATH` (md7),
`TOTAL_EPHEDRINE_SULFATE_PRESSORS`, `TOTAL_MIDAZOLAM_MG`, `TOTAL_NOREPINEPHRINE_BITARTRATE_`,
`TOTAL_PHENYLEPHRINE_HCI_MG`, `TOTAL_PHENYLEPHRINE_HCL_PRESSORS`, `YEAR` (md3).

**CONFLICT variables requiring explicit RENAME= suppression of non-owners:**

All 135+ variables marked CONFLICT in the ownership map. The planner must declare one owner
per variable. The recommended default for variables that appear in md3 is to make md3 the
owner (since md3 is the spine with the most complete population). Exceptions:

| Variable | Recommended owner | Rationale |
|----------|-------------------|-----------|
| `Frailty_Score` | md3 | Spine; 41,150 rows; Phase 6 pending |
| `Cognitive_Score` | md3 | Spine; 41,150 rows; Phase 6 pending |
| `Admit_BMI` | md3 | Spine; prior analysis (OWN-04) confirmed coalescing adds nothing |
| `Age_at_Encounter` | md3 | Spine; PCM-F-04 confirmed md1/md3 agreement |
| `Death_Date_Y_N` | md3 | Spine; PCM-D-01 pending Erin sign-off -- provisional owner |
| `SSDI_Death_Date_Y_N` | md3 | Spine |
| `SSDI_Death_Y_N` | md4 | md4 is the earliest source carrying this name (md4, md5, md6) |
| Variables in md3 and others | md3 | Default: spine owns |
| Variables NOT in md3 | Highest-N source | Take from whichever non-spine source has the most rows |

**IMPORTANT:** The planner must enumerate every CONFLICT variable from the ownership map and
assign it an owner. Skipping any variable leaves a last-wins vulnerability.

---

## Common Pitfalls

### Pitfall 1: Last-observation-wins via merge statement order
**What goes wrong:** A CONFLICT variable appears in both md3 and md4. md4 is listed after
md3 in MERGE. For rows where md4 contributes (7,695 rows), the md4 value overwrites the
md3 value -- silently. No error. No warning. Wrong data.
**Why it happens:** SAS DATA step merge assigns each variable from the LAST dataset in the
merge list that has a non-missing value for that observation.
**How to avoid:** RENAME= every non-owner copy to `_d_varname_mdN` and DROP `_d_:` at the
end. The owner dataset's copy keeps the canonical name and cannot be overwritten.
**Warning signs:** `PROC MEANS` on a conflict variable shows unexpected distribution; values
for rows that should come from md3 look like md4 values.

### Pitfall 2: Forgetting to sort inputs before the DATA step MERGE
**What goes wrong:** `ERROR: BY variable PRECEDE_STUDY_ID is not properly sorted.` in the
SAS log. The merge produces zero observations after the error.
**Why it happens:** DATA step MERGE requires BY-sorted inputs. Phase 3 prep programs write
g.prep_mdN but do not guarantee sort order as a final step.
**How to avoid:** Pattern 1 (PROC SORT ... OUT=work.sort_prep_mdN) is required before the
merge DATA step. Never assume the prep outputs are sorted.
**Warning signs:** Log error about BY-variable sort order; output dataset has zero rows.

### Pitfall 3: IN= automatic variables dropped without assignment
**What goes wrong:** After the merge, `in_md1`--`in_md8` do not exist in `g.master_data_merged`.
MRG-03 fails. `n_sources` is computed incorrectly (or not at all).
**Why it happens:** IN= automatic variables are temporary -- they exist during DATA step
execution but are dropped from the output dataset by default.
**How to avoid:** Immediately after the BY statement, assign each IN= variable to a
permanently-declared variable: `in_md1 = in1; in_md2 = in2; ...`. The LENGTH block must
declare `in_md1`--`in_md8` as numeric type 3 (single byte sufficient for 0/1).
**Warning signs:** PROC CONTENTS on `g.master_data_merged` shows no variables named `in_md1`
through `in_md8`.

### Pitfall 4: LENGTH block missing variables from non-md3 sources
**What goes wrong:** Variables that exist only in md1, md2, md4-md8 (and not in md3) are
not included in the LENGTH block. SAS infers their width from the first observation where
they are non-missing -- which may be a short value. Later observations with wider values
are truncated.
**Why it happens:** Writing the LENGTH block from md3's variable list (the most complete
source) omits variables that md3 does not carry.
**How to avoid:** The LENGTH block must include EVERY variable that will appear in the merged
output -- not just md3's variables. Use `qc/03_contents_all.txt` (the full variable inventory)
to verify completeness. The md8-only hemodynamic block (`ABP_*`, `NIBP_*`, `AVG_*`, `SD_*`,
timing variables, pressors, midazolam) must be included.
**Warning signs:** PROC CONTENTS on `g.master_data_merged` shows a character variable with
a width smaller than the corresponding source width in `qc/03_charvars_all.txt`.

### Pitfall 5: Provenance flag totals do not match source row counts
**What goes wrong:** `sum(in_md1)` from `g.master_data_merged` is not 14,778. MRG-03
assertion fails.
**Why it happens:** Several scenarios: (a) md1 was not included in the merge; (b) the IN=
variable for md1 was not assigned to `in_md1` before the DATA step ended; (c) the merge
produced more or fewer rows than expected (indicating a key alignment problem).
**How to avoid:** Pattern 3 assertion explicitly checks all 8 provenance totals against the
known source row counts from `qc/src_counts.txt`.
**Warning signs:** Assertion `n_in_md1 = 14778` fails with an actual value different from
14,778.

### Pitfall 6: PRECEDE_Study_ID_1 appearing in the merge from md6
**What goes wrong:** md6 originally contained a duplicate column `PRECEDE_Study_ID_1` that
was DROPPED in Phase 3 (PREP-04). If Phase 3 was run against a stale version of md6 that
still has the column, it will appear in `g.prep_md6` and be brought into the merge.
**Why it happens:** Phase 3 execution gap or using a wrong version of the prep output.
**How to avoid:** Section 1 precondition of Phase 4 should assert via `dictionary.columns`
that `g.prep_md6` does NOT contain `PRECEDE_Study_ID_1`. This replicates the PREP-04
assertion at Phase 4 entry.
**Warning signs:** `g.master_data_merged` contains a column `PRECEDE_Study_ID_1`.

### Pitfall 7: g library path inconsistency with Phase 3
**What goes wrong:** Phase 4 defines `g_path = C:\PeCAN_work\data` (the planned path) but
Phase 3 wrote its datasets to `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge`.
Phase 4 cannot find `g.prep_md3` and aborts with a dataset-not-found error.
**Why it happens:** Phase 3 VERIFICATION noted that the actual g_path deviates from the
planned value. Phase 4 must use the SAME path Phase 3 used.
**How to avoid:** Use `%let g_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge;`
This is the value confirmed in all ten Phase 3 SAS programs. Do not use the plan-specified
`C:\PeCAN_work\data` until that discrepancy is formally resolved.
**Warning signs:** `ERROR: File G.PREP_MD3 does not exist.` at PROC SORT time.

### Pitfall 8: Emergent width -- $1 in md1-md7 but $4 in md8
**What goes wrong:** `Emergent` is $1 in md1-md7 but the `qc/03_charvars_all.txt` shows it
as $4 in MASTER_DATA_8. After Phase 3 NULL sentinel clearing, `Emergent` in md8 may still
be $4. If the merged LENGTH block declares `Emergent $1`, any md8 value wider than 1 byte
is silently truncated.
**Why it happens:** md8 sentinel clearing did not change the character column width.
**How to avoid:** Declare `Emergent $4` in the merged LENGTH block (use the max). Phase 5
QC (QC-02) will also check for truncation.
**Warning signs:** PROC CONTENTS shows `Emergent` as $1 in `g.master_data_merged` but $4
in `g.prep_md8`.

### Pitfall 9: Numeric-type variables with CONFLICT across sources having a width issue
**What goes wrong:** Not applicable for numeric variables -- SAS numeric variables are always
8 bytes unless the LENGTH statement specifies fewer. All numeric CONFLICT variables (e.g.,
`Admit_BMI`, `Age_at_Encounter`) are now NUMERIC in all eight sources (after PREP-03/PREP-07).
No truncation risk for numeric variables at merge time.
**Why it happens:** Not applicable -- documenting this explicitly to avoid confusion.
**Confidence:** HIGH.

---

## Open Questions

1. **Exact ownership assignment for all 135 CONFLICT variables**
   - What we know: The ownership map lists them all; the recommended defaults above cover
     the named/known conflicts. md3 is recommended as the default owner for any variable
     it carries.
   - What's unclear: Some CONFLICT variables do not appear in md3 (e.g., `SSDI_Death_Y_N`
     appears in md4, md5, md6 but NOT md3). For these, the planner must pick one of the
     contributing sources as owner.
   - Recommendation: Run `qc/02_ownership_map.txt` through a filter to identify all CONFLICT
     variables where md3 is NOT a contributing source. Assign to the highest-row-count
     contributing source (md8 for 22,473-row scope; md1/md2 for 14,778-row scope).

2. **Phase 3 g_path deviation: C:\PeCAN_work\data vs P: drive**
   - What we know: All Phase 3 programs use the P: drive path. Phase 4 must match.
   - What's unclear: Whether the discrepancy will be resolved before Phase 4 runs.
   - Recommendation: Phase 4 uses the P: drive path as written in the Phase 3 programs.
     If the user later standardizes on `C:\PeCAN_work\data`, a single `%let g_path = ...`
     change in Section 0 propagates to all reads and writes.

3. **Sorting in WORK vs g -- memory and disk implications**
   - What we know: PROC SORT with OUT= writes to WORK. The combined input data across 8
     datasets is substantial (total rows: 14778+14778+41150+7695+7695+9462+9215+22473 =
     127,246 rows). SAS WORK temp space must accommodate all 8 sorted copies.
   - What's unclear: Available temp space on this machine.
   - Recommendation: WORK is the correct target for sort intermediates. If WORK space is
     insufficient, sort one dataset at a time and merge them in stages (unlikely to be
     necessary for this data volume). The planner should add a note in SECTION 0 about
     the total expected WORK usage.

4. **`Feels_Exausted_Value` and related `_Value` suffix variables -- widths**
   - What we know: The ownership map shows `FEELS_EXAUSTED_VALUE` in md3 and md5.
     `qc/03_charvars_all.txt` was checked but does not show a width for these variables --
     they may be numeric in md3 and md5 (not captured in the character-only file).
   - What's unclear: Type and width of `Feels_Exausted_Value`, `Low_Physical_Activity_Value`,
     `Slow_Walking_Speed_Value`, `Unintended_Weight_Loss_Value`, `Week_Grip_Strength_Value`.
   - Recommendation: Planner must check `qc/03_contents_all.txt` (the full variable inventory
     from PROC CONTENTS, not just character variables) for these five variables before
     writing the LENGTH block.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| SAS 9.4M8 | All sections | Assumed (project constraint) | M8 | None |
| P: drive (g library) | All 8 g.prep_mdN reads | Verified (Phase 3 ran successfully) | -- | Abort precondition |
| `logs/` directory | Section 4 merge log | Confirmed (Phase 3 used it) | -- | -- |
| `qc/02_ownership_map.txt` | Planner reference for RENAME= block | Confirmed (26AUG2026 run) | -- | -- |
| `g.prep_md1` through `g.prep_md8` | Section 2 sort + Section 3 merge | Assumed (Phase 3 passed) | -- | Re-run Phase 3 |

**Missing dependencies with no fallback:**
- P: drive must be mapped at execution time. Each program aborts if the g libref fails.

**Missing dependencies with fallback:**
- None. If any `g.prep_mdN` dataset is missing, the resolution is to re-run the corresponding
  Phase 3 prep program, not to work around the missing input.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | SAS log assertions -- `%abort cancel` on violation; `NOTE:` messages for pass |
| Config file | none |
| Quick run command | `sas -sysin "...\sas\04_merge.sas" -log "...\logs\04_merge.log"` |
| Full suite command | `sas -sysin sas\99_run_all.sas` (Phase 8) |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Signal | File Exists? |
|--------|----------|-----------|------------------|-------------|
| MRG-01 | `04_merge.sas` runs without ERROR; produces `g.master_data_merged` with 41,150 rows | smoke | Log: `NOTE: ==== Phase 4 merge complete`; no `ERROR:` | No -- Wave 0 |
| MRG-01 | `g.master_data_merged` has exactly 41,150 rows and 41,150 distinct IDs | embedded assertion | `%abort cancel` if `n_merged ne 41150` or `n_dist ne 41150` | No -- Wave 0 |
| MRG-02 | Zero blank `PRECEDE_STUDY_ID` in merged output | embedded assertion | `%abort cancel` if `n_blank_key ne 0` | No -- Wave 0 |
| MRG-03 | Provenance flags `in_md1`--`in_md8` and `n_sources` present and correct | embedded assertion | `%abort cancel` if any `n_in_mdN` deviates from source row count | No -- Wave 0 |
| MRG-04 | md3 listed first in MERGE statement | code review | `grep -n "merge" sas/04_merge.sas` shows `prep_md3` as first dataset after `merge` keyword | No -- Wave 0 |
| MRG-04 | No last-wins overwrites | code review | `grep -n "rename=" sas/04_merge.sas` returns hits for all 135 CONFLICT variables' non-owner copies | No -- Wave 0 |

### Sampling Rate

- **Per task commit:** Run `04_merge.sas`; check log for ERROR-free completion and 5-part
  assertion passage; inspect `logs/04_merge_log.txt`
- **Per wave merge:** Same (single program phase)
- **Phase gate:** `g.master_data_merged` exists; all five assertions pass; `logs/04_merge_log.txt`
  shows correct row counts and provenance totals; log is ERROR-free

### Wave 0 Gaps

- [ ] `sas/04_merge.sas` -- does not exist yet
- [ ] `logs/04_merge_log.txt` -- created by the program on first run; must not be gitignored
- [ ] Verify `g.prep_md1` through `g.prep_md8` exist in the g library (Phase 3 must have run)
- [ ] Confirm g_path resolution before writing a single line of Section 0

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| PROC SQL multi-table join for horizontal merge | DATA step MERGE with BY statement | PCM-T-01 established | PROC SQL UPDATE is prohibited; DATA step MERGE is the correct tool for 1:1 horizontal merges |
| In-place sort of source datasets | PROC SORT with OUT=work.sort_* | PCM-T-02 established | Never sort g.prep_mdN in place; always sort to WORK |
| Undeclared variable ownership (last-wins by merge order) | Explicit RENAME= suppression of non-owner copies | PCM-T-05 established | Every CONFLICT variable in the ownership map gets a RENAME= block |
| Numeric type conflicts at merge time | Phase 3 PREP-03/PREP-07 resolved all type conflicts | Phase 3 complete | md8 numerics are now NUMERIC; Base_Procedure_Code_1 is CHAR $10 in all 8 sources |

**Deprecated/outdated:**
- `PRECEDE_Study_ID_1` column: dropped in Phase 3 PREP-04; Phase 4 must never reference it

---

## Sources

### Primary (HIGH confidence)
- `qc/02_ownership_map.txt` (26AUG2026 run) -- authoritative list of 163 variables, 135 CONFLICT, 28 single-source; source-list for each
- `qc/03_charvars_all.txt` (26AUG2026 run) -- all character variable widths per source; basis for merged LENGTH block
- `qc/src_counts.txt` (25AUG2026 run) -- row counts per source: md1/md2=14,778; md3=41,150; md4/md5=7,695; md6=9,462; md7=9,215; md8=22,473
- `sas/03_prep_md3.sas` through `sas/03_prep_md8.sas` -- actual g_path (`P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge`), LENGTH block patterns
- Phase 3 VERIFICATION.md -- confirmed Phase 3 gaps (g_path deviation; PREP-07 orphaned in registry)
- STATE.md -- locked decisions: md3 spine, no PROC SQL UPDATE, no data X; set X;, single ownership

### Secondary (MEDIUM confidence)
- SAS 9.4 DATA step documentation (training knowledge): MERGE statement behavior, IN= option semantics, RENAME= dataset option, last-observation-wins default, PROC SORT NODUPKEY

### Tertiary (LOW confidence)
- None -- all critical patterns are grounded in existing project artifacts or established Phase 1-3 patterns

---

## Metadata

**Confidence breakdown:**
- Standard stack (MERGE, IN=, RENAME=, PROC SORT, assertions): HIGH -- SAS 9.4 base features, same patterns established in Phases 1-3
- Phase 3 contract (input datasets, types, row counts): HIGH -- from verified Phase 3 code and VERIFICATION.md
- Ownership map (which source owns each CONFLICT variable): MEDIUM -- the map lists who has each variable; the declaration of ownership is a human decision that the planner must make for all 135 CONFLICT variables
- g library path: HIGH -- confirmed from all ten Phase 3 SAS programs (deviates from plan but consistent in code)
- Character variable widths for merged LENGTH block: HIGH -- from `qc/03_charvars_all.txt`; the `_Value` suffix variables for frailty components require verification from `qc/03_contents_all.txt`

**Research date:** 2026-08-26
**Valid until:** Stable -- SAS 9.4 patterns do not change; re-research only if source data or Phase 3 outputs change
