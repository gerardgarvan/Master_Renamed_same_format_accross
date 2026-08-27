# Phase 5: Merge QC - Research

**Researched:** 2026-08-26
**Domain:** SAS 9.4M8 — post-merge assertion program against g.master_data_merged
**Confidence:** HIGH for QC-01/02/03; QC-04 and QC-05 required correction (see revision log)
**Revised:** 2026-08-26 (post-review)

## Revision log — 2026-08-26 post-review

| Change | Reason |
|---|---|
| QC-04 variable set corrected from the eight PREP-03 conversion targets to the ~20 SINGLE-SOURCE md8-owned variables | The conversion targets are not md8-only; md3 owns all eight after the Phase 4 merge, so "non-missing outside md8 rows = 0" fails on every one (`Age_at_Encounter`: 38,755 non-missing in 41,150 rows vs 22,473 md8 rows) |
| QC-04 variable list now DERIVED from the ownership map, not hardcoded | Keeps it correct if Phase 2 or Phase 4 ownership changes |
| QC-04 Part A expected magnitudes stated (16-18% for ABP/BIS/NIBP, 100% for `Total_*`) | The earlier "shortfall from 22,473 needs explanation" framing would send a reviewer chasing clinically normal sparsity |
| QC-05 `Admit_BMI` ceiling fixed at 100; the 10-80 wording in the requirements row deleted | Observed max is 88.32 — a ceiling of 80 aborts on correct data |
| QC-05 `Cognitive_Score` corrected from 0-30 (assumed MMSE) to 0-3 | Observed range is 0-3. A 0-30 bound passes vacuously and would miss a genuine out-of-range value |
| QC-05 `Age_at_Encounter` floor documented as non-firing | Observed minimum is 64; an 18 floor detects nothing. Retained as a type-sanity guard, explicitly not tightened while PCM-D-07 is open |
| Pattern 3 `SELECT * FROM (VALUES ...)` replaced with `CREATE TABLE` + `INSERT ... VALUES` | SAS PROC SQL has no VALUES table constructor in FROM; the shown syntax is an error |
| Removed `PRECEDE_Study_ID_1` and `ISO_SEV_Exp_IntraOp_MAC_Average` from the QC-02 width reference | The first was dropped in PREP-04 and deleted from the Phase 4 keep list; the second is numeric in the merged file, not character |

---

## Project Constraints (from CLAUDE.md)

- SAS 9.4M8 on Windows; session encoding is NOT UTF-8 — encoding damage is flag-only (PCM-C-01)
- Source files are **read-only** — `05_qc_merge.sas` reads only `g.master_data_merged` (never src)
- No PHI in git: only `.sas` programs and plain-text QC/log artifacts may be committed
- No `data X; set X;` patterns (PCM-T-02)
- No PROC SQL UPDATE (PCM-T-01)
- `%abort cancel` must be inside a macro definition — never in open code (PCM-R-05)
- `SELECT COUNT(*) INTO :n TRIMMED` for all assertions — never `&SQLOBS`
- Repo on local disk; source data and g library on P: drive

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| QC-01 | `05_qc_merge.sas` runs and `abort`s if row count deviates from 41,150 | PROC SQL COUNT(*) into macvar; `%assert_eq(actual=&n, expected=41150)` inside macro — identical to the pattern already in `04_merge.sas` SECTION 5 |
| QC-02 | No character variable is truncated — max widths from prep are preserved | PROC CONTENTS on `g.master_data_merged`; compare each character variable's length against the owner-source width from `qc/03_charvars_all.txt`; abort on any shortfall |
| QC-03 | Zero surviving literal `NULL` strings anywhere in `g.master_data_merged` | Broaden the md8-only scan from Phase 4 to scan ALL character variables in the merged file; `%assert_eq(actual=&n_null, expected=0)` |
| QC-04 | The md8-ONLY variables are non-missing only within md8 rows | The md8-only set is the ~20 SINGLE-SOURCE variables (`ABP_*`, `BIS_INDEX_*`, `NIBP_*`, `SD_*`, `AVG_*`, the pressor/`Total_*` block, `ISO_SEV_MAC_TOTAL_Exp`) — NOT the eight PREP-03 conversion targets. Assert non-missing count outside md8 rows = 0 for each; log within-md8 counts for review |
| QC-05 | Type-converted variables verified within expected clinical ranges | Range checks on the eight PREP-03 conversion targets, with bounds calibrated to the OBSERVED data (see Pattern 6): BMI 10–100, age 18–120, ASA 1–6, frailty 0–5, cognitive 0–3, time-in-minutes 0–2000; `%assert_eq` on count of out-of-range rows = 0 |
</phase_requirements>

---

## Summary

Phase 5 produces `sas/05_qc_merge.sas`, a standalone QC sentinel that reads only
`g.master_data_merged` (already produced by Phase 4) and aborts loudly on any of five
categories of failure. The program writes a QC summary artifact to `qc/05_qc_merge_report.txt`
and a log to `logs/05_qc_merge.log` (the latter via SAS batch `-log` option, not FILE/PUT).

The assertions in Phase 5 are deliberately additive to, not replacements for, Phase 4's
assertions. Phase 4 was the merge program: it had to build the dataset and then check it.
Phase 5 reads an already-committed dataset and applies a second, independent pass of checks
that are broader (QC-02: all char widths; QC-03: all character variables, not just md8) and
deeper (QC-05: clinical ranges that Phase 4 did not assert).

The dominant design decision is **scan breadth for QC-03**: Phase 4 scoped the NULL scan only
to md8-owned character variables, and found zero because md8 owns zero character variables in
the merged file (the hemodynamic block is entirely numeric after PREP-03). Phase 5 must scan
ALL character variables in `g.master_data_merged` — it is checking the merged output's
integrity globally, not just the md8-specific conversion that Phase 3 addressed.

QC-04 rests on getting the variable list right, and an earlier draft got it wrong. It named the
eight PREP-03 conversion targets (`Admit_BMI`, `ASA__Anesth_Record_`, `Age_at_Encounter`,
`Cognitive_Score`, `Frailty_Score`, three `rt_*`) as "the md8-only hemodynamic block." Those are
not md8-only: they exist in md1-md7 as well, and Phase 4's ownership rule assigns all eight to
**md3**, so their values in the merged file come from md3 and are populated across all 41,150
rows. Asserting "non-missing outside md8 rows = 0" for them fails on every one -- for example
`Age_at_Encounter` has 38,755 non-missing values in only 41,150 rows, of which just 22,473 are
md8 rows. See Pattern 5 for the correct list.

**Primary recommendation:** One program, six sections (0: options/paths/libname; 1:
preconditions; 2: QC-01/02 row count and widths; 3: QC-03 NULL scan; 4: QC-04 hemodynamic
block; 5: QC-05 clinical ranges), with a QC summary artifact written at the end of each
section and a single `%abort cancel` macro (`%assert_eq`) reused throughout. Write the
summary artifact progressively so partial output survives if the program aborts mid-run.

---

## Context: What Phase 4 Already Asserted

These assertions are COMPLETE in `sas/04_merge.sas` and need NOT be re-done in Phase 5
(they would always pass because the same program produced the dataset):

| Assertion | Phase 4 evidence | Phase 5 action |
|-----------|-----------------|----------------|
| Row count = 41,150 | `%assert_eq(actual=&n_merged, expected=41150)` at line 482 | QC-01: re-assert independently from a second program |
| Distinct IDs = 41,150 | `%assert_eq(actual=&n_dist, expected=41150)` at line 483 | Not re-required (already proven bijective) |
| Blank key = 0 | `%assert_eq(actual=&n_blank_key, expected=0)` at line 485 | Not re-required |
| in_md1..in_md8 totals | 8 `%assert_eq` calls lines 487-494 | QC-04 builds on in_md8 |
| NULL scan (md8 chars only) | `%null_scan` macro; result was 0 because md8 owns 0 char vars | QC-03: broaden to ALL char vars |
| Ownership reconciliation | `n_unmapped=0`, `n_absent=0` | Not re-required |

**Important:** Phase 4 confirmed that `md8 owns no character variables in the merged file`
(the note appears in the log and the `%null_scan` macro handled it as a valid pass). Phase 5's
QC-03 scan must therefore cover all md3- and non-md8-owned character variables to be
meaningful.

---

## Standard Stack

### Core

| Tool/Pattern | Version | Purpose | Why Standard |
|---|---|---|---|
| `%macro assert_eq(actual=, expected=, label=)` with `%abort cancel` | SAS 9.4 | Loud failure on any mismatch | Established pattern from Phases 1-4; identical structure every time |
| `PROC SQL; SELECT COUNT(*) INTO :n TRIMMED` | SAS 9.4 | All counts and range checks | Never `&SQLOBS`; established rule |
| `PROC CONTENTS DATA=g.master_data_merged OUT=work.qc5_cols NOPRINT` | SAS 9.4 | Enumerate character variables and their declared lengths for QC-02 | Same PROC CONTENTS pattern from Wave 0 of Phase 3 |
| `DATA _NULL_; SET g.master_data_merged; ARRAY _c {*} _CHARACTER_; ...` | SAS 9.4 | NULL scan across all character variables (QC-03) | ARRAY _CHARACTER_ approach; same as md8 sentinel clearing in Phase 3 |
| `FILE/PUT` to `qc/05_qc_merge_report.txt` | SAS 9.4 | Committed plain-text QC artifact | Established in Phases 1-4 for all committed artifacts |

### No External Dependencies

No external packages. All tools are SAS 9.4 base product.

---

## Architecture Patterns

### Recommended Program Structure

```
05_qc_merge.sas
  SECTION 0: Options, %let paths, libname g, %macro assert_eq definition
  SECTION 1: Preconditions
    -- g library resolves
    -- logs/ and qc/ directories exist
    -- g.master_data_merged exists in dictionary.tables
    -- Open qc/05_qc_merge_report.txt for progressive writing
  SECTION 2: QC-01 (row count) + QC-02 (character widths)
    -- PROC SQL COUNT(*) into :n_merged; assert = 41150
    -- PROC CONTENTS on g.master_data_merged into work.qc5_cols
    -- PROC SQL join work.qc5_cols to a reference width table (from 03_charvars_all.txt)
       to find any character variable narrower than its owner's declared width
    -- Write QC-02 result to report; abort if any truncated
  SECTION 3: QC-03 (NULL strings — all character variables)
    -- DATA _NULL_ with ARRAY _c {*} _CHARACTER_ scan
    -- %assert_eq on n_null = 0
    -- Write to report
  SECTION 4: QC-04 (hemodynamic block, 22,473 rows)
    -- Eight PROC SQL counts: non-missing for in_md8=1 rows; missing for in_md8=0 rows
    -- Two assertions per variable (or combined): n_nonnull_for_md8 = [observed]; n_nonnull_for_non_md8 = 0
    -- Write to report
  SECTION 5: QC-05 (clinical range checks)
    -- PROC SQL range checks for each of 8 variables
    -- %assert_eq on count-of-out-of-range = 0 for each
    -- Write to report
  SECTION 6: Close-out
    -- %put NOTE: ==== Phase 5 QC complete ====
    -- All checks passed note in report
```

### Pattern 1: %assert_eq macro (reuse from Phase 4)

```sas
/* PCM-R-05: %abort cancel must be inside a named macro definition */
%macro assert_eq(actual=, expected=, label=);
  %if &actual ne &expected %then %do;
    %put ERROR: QC ASSERTION FAILED -- &label: expected &expected got &actual;
    %abort cancel;
  %end;
  %else %put NOTE: QC ASSERTION OK -- &label = &actual;
%mend assert_eq;
```

This is identical to the Phase 4 pattern. Copy verbatim to SECTION 0 of 05_qc_merge.sas.
Do NOT use `%include sas/04_merge.sas` — macro definitions do not persist across SAS sessions
and `05_qc_merge.sas` must be independently runnable.

### Pattern 2: QC-01 — Row count assertion

```sas
proc sql noprint;
  select count(*) into :n_merged trimmed from g.master_data_merged;
quit;
%assert_eq(actual=&n_merged, expected=41150, label=QC-01 merged row count);
```

**Confidence:** HIGH — direct copy of Phase 4 SECTION 5 pattern.

### Pattern 3: QC-02 — Character width verification

The goal is to detect any character variable in `g.master_data_merged` whose declared length
is shorter than the owner-source's width recorded in `qc/03_charvars_all.txt`.

**Approach:** Read expected widths by querying `work.qc5_cols` (PROC CONTENTS output) and
comparing against a reference table built from the owner's row in `03_charvars_all.txt`. Because
`03_charvars_all.txt` is a plain-text report (not a SAS dataset), the reference values must
be either: (a) hardcoded from the known owner widths listed below, or (b) ingested via
`PROC IMPORT` / `DATA _NULL_ INFILE` at runtime.

**Recommendation:** Hardcode the expected owner widths for each character variable as a
`PROC SQL`-insertable reference table. This is justified because the widths come from a
committed QC artifact (`qc/03_charvars_all.txt`) that does not change (source files are
read-only). This avoids a runtime INFILE parse that could break on path differences.

```sas
/* Build reference table of expected character variable widths (owner widths).
   Source: qc/03_charvars_all.txt, filtered to each variable's owner source.
   Variables not in this list are either numeric or do not require width check.
   Add a row for every character variable in g.master_data_merged.             */
/* SAS PROC SQL has NO `VALUES` table constructor in a FROM clause -- that is
   ANSI/Postgres syntax and is a syntax error here. Use CREATE TABLE with a column
   list, then INSERT with repeated VALUES clauses (SAS supports multiple VALUES
   per INSERT).                                                                    */
proc sql noprint;
  create table work.expected_widths (varname char(32), expected_len num, owner char(4));
  insert into work.expected_widths
    values ('PRECEDE_STUDY_ID',    12, 'key')
    values ('ENCRYPTED_MRN',       40, 'md3')
    values ('ENCRYPTED_ENCOUNTER', 49, 'md3')
    /* ... one VALUES clause per character variable, at its OWNER width ... */
    ;
quit;

proc contents data=g.master_data_merged out=work.qc5_cols(keep=name length type) noprint; run;

proc sql noprint;
  create table work.width_check as
    select e.varname, e.expected_len, e.owner,
           c.length as actual_len,
           (c.length < e.expected_len) as is_truncated
    from work.expected_widths e
    inner join work.qc5_cols c
      on upcase(e.varname) = upcase(c.name)
      and c.type = 2   /* character variables only */
    where c.length < e.expected_len;

  select count(*) into :n_truncated trimmed from work.width_check;
quit;
%assert_eq(actual=&n_truncated, expected=0, label=QC-02 truncated character variables);
```

**CRITICAL PITFALL:** The reference table must cover ALL character variables in the merged
output, using the OWNER's width (not the cross-source max). This is the same rule applied in
the Phase 4 LENGTH block: `Emergent $1` (md3 owns; md8's $4 never reaches the merge). If a
planner uses the wrong (non-owner) width as the reference, QC-02 will falsely flag correctly-
sized variables. See "Owner Width Reference" section below.

**Confidence:** HIGH for the PROC CONTENTS + PROC SQL pattern. MEDIUM for the reference
table completeness — the planner must enumerate all character variables from
`qc/03_charvars_all.txt` filtered to each variable's resolved owner.

### Pattern 4: QC-03 — NULL string scan (all character variables)

```sas
/* Scan ALL character variables in g.master_data_merged for the literal string 'NULL'.
   Phase 4 scoped this scan to md8-owned char vars only (found none; md8 owns 0 char vars).
   Phase 5 scans all char vars to catch any NULL that survived from any source.        */
data _null_;
  set g.master_data_merged end=eof;
  retain _n_null 0;
  array _c {*} _CHARACTER_;
  do _i = 1 to dim(_c);
    if strip(upcase(_c{_i})) = 'NULL' then _n_null + 1;
  end;
  drop _i;
  if eof then call symputx('n_null_all', _n_null, 'G');
run;
%assert_eq(actual=&n_null_all, expected=0, label=QC-03 NULL strings in any character variable);
```

**Note on `_CHARACTER_` array scope:** In a DATA step that sets `g.master_data_merged`, the
`_CHARACTER_` array includes ALL character variables in the PDV — which is all character
variables in the dataset (since there is no KEEP= or DROP= in this read). This is the correct
behavior for a global scan.

**Confidence:** HIGH — same array pattern as the md8 sentinel clearing in Phase 3.

### Pattern 5: QC-04 — md8-only block scoping check

**Use the SINGLE-SOURCE md8 variables, not the PREP-03 conversion targets.**

An earlier draft of this document listed `Admit_BMI`, `ASA__Anesth_Record_`,
`Age_at_Encounter`, `Cognitive_Score`, `Frailty_Score` and the three `rt_*` variables as "the
eight md8-only numeric variables." That is wrong on both counts:

- They are not md8-only. All eight exist in md1-md7 as well. md8 merely stored them as
  *character* (the `NULL` sentinel forced the type), which is what PREP-03 converted.
- Phase 4's ownership rule gives all eight to **md3**. Their merged values come from md3 and
  span all 41,150 rows. `Age_at_Encounter` alone has 38,755 non-missing values against 22,473
  md8 rows, so a "non-missing outside md8 = 0" assertion fails by roughly 16,000.

The genuinely md8-exclusive variables are the SINGLE-SOURCE set from the ownership map
(`N_Src=1`, owner md8) — all numeric:

```
ABP_LESS_THAN_60_COUNT   ABP_LESS_THAN_70_COUNT   ABP_LESS_THAN_80_COUNT
BIS_INDEX_LESS_30_COUNT  BIS_INDEX_LESS_40_COUNT
NIBP_LESS_60_COUNT       NIBP_LESS_70_COUNT       NIBP_LESS_80_COUNT
SD_ABP_Mean              SD_NIBP_mean             SD_BIS_index
AVG_ABP_Mean             AVG_NIBP_mean            AVG_BIS_index
Total_Phenylephrine_HCl_Pressors   Total_EPHEDRINE_SULFATE_PRESSORS
Total_Midazolam_mg       Total_Phenylephrine_HCI_mg
Total_Norepinephrine_Bitartrate_   ISO_SEV_MAC_TOTAL_Exp
```

**Do not hardcode this list.** Derive it from the ownership map so it stays correct if Phase 2
or Phase 4 changes:

```sas
/* md8-owned variables = the md8-only block. Drive the checks from the map, not a literal list. */
proc sql noprint;
  select name into :md8_only separated by ' '
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED'
    and upcase(name) in (select upcase(varname) from work.ownership_resolved
                         where owner_resolved='md8');

  select count(*) into :n_md8_only trimmed
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED'
    and upcase(name) in (select upcase(varname) from work.ownership_resolved
                         where owner_resolved='md8');
quit;
```

(If `work.ownership_resolved` is not available in this session, rebuild it from
`qclib.ownership_map` with the Phase 4 SECTION 2b resolution rule, or read
`qc/02_ownership_map.txt`.)

**Part B — the assertion.** For each md8-owned variable, non-missing count where `in_md8 = 0`
must be 0. A macro keeps this list-length-independent:

```sas
%macro qc04_partB(var=);
  %local n_out;
  proc sql noprint;
    select count(*) into :n_out trimmed
    from g.master_data_merged where in_md8 = 0 and &var is not missing;
  quit;
  %assert_eq(actual=&n_out, expected=0, label=QC-04 &var non-missing outside md8 rows);
%mend qc04_partB;

%macro qc04_all;
  %local i v;
  %do i = 1 %to %sysfunc(countw(&md8_only));
    %let v = %scan(&md8_only, &i);
    %qc04_partB(var=&v);
  %end;
%mend qc04_all;
%qc04_all;
```

**Part A — log, do not assert, and state the real magnitudes.** Within-md8 population varies
enormously across this block, and low counts are clinically expected rather than defects:

| Variable | Non-missing within md8 | Share of 22,473 |
|---|---|---|
| `Total_Midazolam_mg` | 22,473 | 100% |
| `AVG_ABP_Mean` | 4,005 | 18% |
| `BIS_INDEX_LESS_30_COUNT` | 3,604 | 16% |
| `ABP_LESS_THAN_60_COUNT` | 3,519 | 16% |

Arterial-line and BIS monitoring are not used on most cases, so the `ABP_*`, `NIBP_*`, `BIS_*`,
`SD_*` and `AVG_*` columns are populated only where the monitor was in place. **A count near
16-18% is normal for those; only the pressor/medication `Total_*` columns approach 22,473.** An
earlier draft told the human reviewer to treat any shortfall from 22,473 as needing explanation
and "a count near 0" as a conversion problem — that framing sends the reviewer chasing a
non-problem. Print these expected magnitudes alongside the observed counts in the report.

**Confidence:** HIGH for the Part B pattern once the variable list is correct.

### Pattern 6: QC-05 — Clinical range checks

These are the eight PREP-03 conversion targets (`Admit_BMI`, `ASA__Anesth_Record_`,
`Age_at_Encounter`, `Cognitive_Score`, `Frailty_Score`, and the three `rt_*` timings). Note these
are NOT the QC-04 variable set -- QC-04 covers the md8-ONLY single-source block; QC-05 covers the
variables whose TYPE md8 forced to character. The two requirements have different scopes and
different variable lists.

Bounds below are calibrated against the OBSERVED distribution in the merged data, not taken from
clinical reference ranges alone. A bound that cannot fire detects nothing; a bound tighter than
the real data aborts a correct pipeline. Both errors were present in an earlier draft.

| Variable | Low | High | Rationale |
|---|---|---|---|
| `Admit_BMI` | 10 | 100 | OBSERVED range in the merged data is 12.84 to 88.32. A ceiling of 80 -- which the QC-05 requirement row previously specified -- would ABORT on correct data. 100 clears the observed max with headroom |
| `ASA__Anesth_Record_` | 1 | 6 | ASA physical status is an ordinal 1-6 (6 = brain-dead donor). OBSERVED range is 1 to 5, comfortably inside |
| `Age_at_Encounter` | 18 | 120 | OBSERVED range is 64 to 100. A floor of 18 can never fire and detects nothing -- it is retained only as a type-sanity guard. PCM-D-07 is specifically about the observed 64 floor; this check cannot inform it either way |
| `Cognitive_Score` | 0 | 3 | OBSERVED range is 0 to 3. This is NOT MMSE. An earlier draft assumed MMSE 0-30 from clinical training knowledge; the data says otherwise, and `Cognitive_Category` ($22 label) sits beside it, consistent with a small ordinal score. A 0-30 bound passes vacuously AND misses real errors -- a stray 25 would sail through a check that should reject it |
| `Frailty_Score` | 0 | 5 | OBSERVED range is 0 to 5 -- matches the Fried frailty phenotype. Correct as written |
| `rt_INCISE_to_DRESS_mins` | 0 | 2000 | Time in minutes; negative is impossible; > 2000 minutes (33 hours) indicates data error |
| `rt_RM_START_to_INCISION_mins` | 0 | 500 | Room-start to first incision; > 500 minutes is implausible |
| `rt_RM_START_to_RM_END_mins` | 0 | 2000 | Total room time; > 2000 minutes indicates data error |

**Note on PCM-D-07 (Age floor):** STATE.md marks the Age_at_Encounter floor investigation as
pending. The range assertion uses `>= 18` as the low bound, which is consistent with a surgical
cohort but has not been formally signed off. The planner should add a comment in the code noting
PCM-D-07 is pending and that this range assertion may need updating in Phase 6.

```sas
/* QC-05: clinical range checks on md8 type-converted numerics.
   Counts rows where the non-missing value is outside the expected clinical range.
   Missing (SAS .) passes — missingness is addressed in QC-04, not here.        */
proc sql noprint;
  select count(*) into :n_bmi_range trimmed
    from g.master_data_merged where Admit_BMI is not missing and
      (Admit_BMI < 10 or Admit_BMI > 100);

  select count(*) into :n_asa_range trimmed
    from g.master_data_merged where ASA__Anesth_Record_ is not missing and
      (ASA__Anesth_Record_ < 1 or ASA__Anesth_Record_ > 6);

  select count(*) into :n_age_range trimmed
    from g.master_data_merged where Age_at_Encounter is not missing and
      (Age_at_Encounter < 18 or Age_at_Encounter > 120);
  /* PCM-D-07 PENDING: observed minimum age is 64, so an 18 floor never fires.
     Retained as a type-sanity guard only. Do NOT tighten it to 64 -- that would
     convert a legitimate cohort question into a pipeline abort. Resolve D-07 first. */

  select count(*) into :n_cog_range trimmed
    from g.master_data_merged where Cognitive_Score is not missing and
      (Cognitive_Score < 0 or Cognitive_Score > 3);
  /* NOT MMSE 0-30: observed range is 0-3. See the Pattern 6 table. */

  select count(*) into :n_frail_range trimmed
    from g.master_data_merged where Frailty_Score is not missing and
      (Frailty_Score < 0 or Frailty_Score > 5);

  select count(*) into :n_rt1_range trimmed
    from g.master_data_merged where rt_INCISE_to_DRESS_mins is not missing and
      (rt_INCISE_to_DRESS_mins < 0 or rt_INCISE_to_DRESS_mins > 2000);

  select count(*) into :n_rt2_range trimmed
    from g.master_data_merged where rt_RM_START_to_INCISION_mins is not missing and
      (rt_RM_START_to_INCISION_mins < 0 or rt_RM_START_to_INCISION_mins > 500);

  select count(*) into :n_rt3_range trimmed
    from g.master_data_merged where rt_RM_START_to_RM_END_mins is not missing and
      (rt_RM_START_to_RM_END_mins < 0 or rt_RM_START_to_RM_END_mins > 2000);
quit;

%assert_eq(actual=&n_bmi_range,   expected=0, label=QC-05 Admit_BMI out of range 10-100);
%assert_eq(actual=&n_asa_range,   expected=0, label=QC-05 ASA__Anesth_Record_ out of range 1-6);
%assert_eq(actual=&n_age_range,   expected=0, label=QC-05 Age_at_Encounter out of range 18-120);
%assert_eq(actual=&n_cog_range,   expected=0, label=QC-05 Cognitive_Score out of range 0-3);
%assert_eq(actual=&n_frail_range, expected=0, label=QC-05 Frailty_Score out of range 0-5);
%assert_eq(actual=&n_rt1_range,   expected=0, label=QC-05 rt_INCISE_to_DRESS_mins out of range 0-2000);
%assert_eq(actual=&n_rt2_range,   expected=0, label=QC-05 rt_RM_START_to_INCISION_mins out of range 0-500);
%assert_eq(actual=&n_rt3_range,   expected=0, label=QC-05 rt_RM_START_to_RM_END_mins out of range 0-2000);
```

**Confidence:** MEDIUM — ranges are clinically reasonable but have not been validated against
the actual data distribution. The planner should note that if any range assertion fires, the
correct response is: (a) inspect the out-of-range rows, (b) determine if the range ceiling is
too tight or if the data has a genuine problem, (c) adjust the ceiling and document in
`docs/DECISIONS.md` before re-running. An abort is a flag for human investigation, not
necessarily a hard data error.

---

## Owner Width Reference for QC-02

The QC-02 reference table must use each character variable's **owner's** width, not the maximum
across all sources. The owner assignment follows the Phase 4 rule:

- md3 owns a variable if md3 carries it (md3 is the spine; 41,150 rows).
- Otherwise the highest-row-count contributing source owns it.
- Five frailty components (`Feels_Exausted`, `Low_Physical_Activity`, `Slow_Walking_Speed`,
  `Unintended_Weight_Loss`, `Week_Grip_Strength`) are overridden to md7 ($3) despite md6
  having more rows, because md6's $1 width cannot hold md7's 3-character values (PCM-D-02 override).

The complete character variable list and owner widths are derivable from `qc/03_charvars_all.txt`
by filtering to each variable's resolved owner source. The planner must read
`qc/03_charvars_all.txt` and `qc/02_ownership_map.txt` together to build the reference table.

Key known widths (verified from `qc/03_charvars_all.txt`):

| Variable | Owner | Width |
|---|---|---|
| `PRECEDE_STUDY_ID` | (key — all) | $12 |
| `ENCRYPTED_MRN` | md3 | $40 |
| `ENCRYPTED_ENCOUNTER` | md3 | $49 |
| `Race` | md3 | $16 |
| `Ethnicity` | md3 | $15 |
| `Sex` | md3 | $6 |
| `Marital_Status` | md3 | $22 |
| `Emergent` | md3 | $1 (NOT md8's $4) |
| `Base_Procedure_1` | md3 | $198 (md3); also $198 in md1/md2 |
| `Base_Procedure_Code_1` | md3 | $10 |
| `Intraop_Ketamine` | md3 | $1 |
| `Preop_block` | md3 | $1 |
| `Dischg_Disposition` | md3 | $42 |
| `Anesthesia_Type` | md3 | $33 |
| `Feels_Exausted` | md7 (override) | $3 |
| `Low_Physical_Activity` | md7 (override) | $3 |
| `Slow_Walking_Speed` | md7 (override) | $3 |
| `Unintended_Weight_Loss` | md7 (override) | $3 |
| `Week_Grip_Strength` | md7 (override) | $3 |

The planner must complete this table for ALL character variables in the merged file before
coding the reference table in SECTION 2.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Character width comparison | Custom PROC PRINT + visual inspection | PROC CONTENTS + PROC SQL join to reference table; `%assert_eq` on truncated count | Automated and reproducible; visual inspection misses subtle width differences |
| NULL scan | Single-variable `if var = 'NULL'` conditions | `ARRAY _c {*} _CHARACTER_` loop | Covers all character variables including those added in future phases |
| Clinical range outlier report | PROC UNIVARIATE or PROC MEANS | PROC SQL COUNT(*) WHERE out-of-range; `%assert_eq` on count = 0 | Deterministic pass/fail; no manual review of statistics required |

---

## Common Pitfalls

### Pitfall 1: Reusing Phase 4's scoped NULL scan as Phase 5's QC-03
**What goes wrong:** Phase 4's `%null_scan` macro only checked md8-owned character variables
in the merged file. Phase 4 found that md8 owns zero character variables (all hemodynamic
block variables are numeric after PREP-03), so the scan was vacuously true. If Phase 5 copies
this pattern, QC-03 remains a vacuous check and the requirement is not satisfied.
**How to avoid:** Phase 5 SECTION 3 scans ALL character variables using `ARRAY _c {*} _CHARACTER_`
(no filtering by ownership).

### Pitfall 2: Asserting Part A of QC-04 = 22,473 when values may be legitimately missing
**What goes wrong:** Some md8 patients may have had missing values for (e.g.) `Admit_BMI` in
the original source. Asserting `n_bmi_md8 = 22473` would abort on legitimately missing data,
producing false failures.
**How to avoid:** Assert Part B (non-missing outside md8 rows = 0). Log Part A counts to the
QC report for human review but do not abort on Part A.
**Exception:** If the project has a separate confirmed expectation that all 22,473 md8 rows
have a specific variable populated, that expectation must come from a QC artifact (e.g., the
Phase 3 conversion count log shows `converted non-missing: 22473` for that variable), and only
then is a Part A abort appropriate.

### Pitfall 3: QC-02 reference table uses cross-source max widths instead of owner widths
**What goes wrong:** `Emergent` is $1 in md3 (owner) but $4 in md8. If the reference table
uses $4, QC-02 passes on a correctly-sized $1 column but would flag a legitimate width as a
false truncation if the table erroneously had $4 as the expected value, OR (more commonly)
would not detect actual truncation if the merged column is $1 and the reference says $1 anyway
but was meant to check $4.
**How to avoid:** Reference table entries must use the OWNER's width, derived from
`qc/03_charvars_all.txt` filtered to the resolved owner source. See the Owner Width Reference
section above.

### Pitfall 4: Missing `IS NOT MISSING` guard in QC-05 range checks
**What goes wrong:** `WHERE Admit_BMI < 10` in SAS is TRUE when `Admit_BMI` is SAS missing
(`.`), because missing numeric is treated as the smallest possible value (less than any number).
This would cause every patient not in md8 (18,677 rows) to fail the BMI range check.
**How to avoid:** All range check WHERE clauses include `variable IS NOT MISSING AND (variable < low OR variable > high)`.

### Pitfall 5: %abort cancel in open code (PCM-R-05)
**What goes wrong:** Any `%abort cancel;` outside a `%macro`/`%mend` block is a PCM violation
and is syntactically problematic in some SAS configurations.
**How to avoid:** All `%abort cancel` calls are inside `%assert_eq` macro (already wrapped) or
another named macro. This is established practice from Phases 1-4.

### Pitfall 6: Not writing the QC artifact progressively
**What goes wrong:** If Phase 5 aborts in SECTION 3 (QC-03 fails), SECTION 4 and 5 never
run, and the QC artifact may be empty or incomplete — making it hard to understand which check
failed from the artifact alone.
**How to avoid:** Use `FILE "..." mod;` with `PUT` after EACH section's assertions complete.
SECTION 2 writes its result immediately; SECTION 3 writes its result immediately; etc. An abort
leaves the artifact with partial results up to the failure point, which is diagnostic.

### Pitfall 7: Path mismatch with Phase 4 paths
**What goes wrong:** Phase 4 used `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge`
for `g_path`, `logs_path`, and `qc_path`. If Phase 5 uses different paths, it assigns a
different `g` libname and cannot find `g.master_data_merged`.
**How to avoid:** Copy SECTION 0 `%let` statements verbatim from `sas/04_merge.sas`:
```sas
%let g_path    = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge;
%let logs_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs;
%let qc_path   = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc;
libname g "&g_path";
```

---

## Key Facts (verified from committed QC artifacts)

These facts are established from committed artifacts and must appear in code as hardcoded
expected values, not as discoveries.

| Fact | Source | Value |
|---|---|---|
| Total merged row count | `qc/04_merge_provenance.txt` | 41,150 |
| md8 row count (in_md8 = 1) | `qc/04_merge_provenance.txt` | 22,473 |
| Non-md8 row count | Derived: 41,150 − 22,473 | 18,677 |
| md8 owns zero character variables | Phase 4 SAS log (human run 2026-08-26) | Confirmed — hemodynamic block is entirely numeric after PREP-03 |
| Eight type-converted variables are NUMERIC in merged file | Phase 4 assertion at lines 553-554 | Confirmed — n_unmapped=0, n_absent=0 passed |
| Phase 4 ran ERROR-free | Phase 4 human run 2026-08-26 | All 14 MRG ASSERTION OK lines confirmed |

---

## What 05_qc_merge.sas Must Produce

| Artifact | Location | Content | Commit? |
|---|---|---|---|
| QC summary report | `qc/05_qc_merge_report.txt` | Pass/fail status for each of 5 QC sections; counts for range violations and NULL checks | Yes |
| SAS log | `logs/05_qc_merge.log` | Written via `-log` batch option or SAS log; shows all NOTE: QC ASSERTION OK lines | No (logs are not committed) |

The QC report is the human-readable evidence that all five requirements (QC-01 through QC-05)
passed. It must contain enough information to reproduce each check: the actual count observed,
the expected value, and a PASS/FAIL label for each assertion.

---

## Environment Availability

Step 2.6 applies: Phase 5 depends on the g library on the P: drive.

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| SAS 9.4M8 | `05_qc_merge.sas` | Assumed (project constraint) | M8 | None |
| P: drive (g libname) | All sections | Verified (Phase 4 ran 2026-08-26 with P: mapped) | -- | Abort precondition in SECTION 1 |
| `g.master_data_merged` | All sections | Yes — produced by Phase 4 (41,150 rows confirmed) | -- | Abort precondition if not in dictionary.tables |
| `qc/` directory | QC artifact write | Yes (contains Phase 1-4 artifacts) | -- | -- |
| `logs/` directory | SAS batch log | Yes (Phase 3 confirmed) | -- | -- |

**Missing dependencies with no fallback:**
- P: drive must be mapped; SECTION 1 aborts if libref fails.
- `g.master_data_merged` must exist; SECTION 1 aborts if absent from `dictionary.tables`.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | SAS log assertions — `%abort cancel` on violation; `NOTE: QC ASSERTION OK` for pass |
| Config file | None |
| Quick run command | `sas -sysin "C:\Master_Renamed_same_format_accross\sas\05_qc_merge.sas" -log "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs\05_qc_merge.log"` |
| Full suite command | Same; Phase 5 is a single program |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Signal | File Exists? |
|--------|----------|-----------|------------------|--------------|
| QC-01 | Row count = 41,150 | embedded assertion | `NOTE: QC ASSERTION OK -- QC-01 merged row count = 41150` in log | No — Wave 0 |
| QC-02 | No truncated character variables | embedded assertion | `NOTE: QC ASSERTION OK -- QC-02 truncated character variables = 0` in log | No — Wave 0 |
| QC-03 | Zero NULL strings in all char vars | embedded assertion | `NOTE: QC ASSERTION OK -- QC-03 NULL strings in any character variable = 0` in log | No — Wave 0 |
| QC-04 Part B | md8-only variables missing outside md8 rows | embedded assertion (one call per md8-owned variable, ~20) | `NOTE: QC ASSERTION OK -- QC-04 <var> non-missing outside md8 rows = 0` for every md8-owned variable; count must equal `&n_md8_only` | No — Wave 0 |
| QC-05 | Type-converted vars in clinical ranges | embedded assertion (8 calls) | 8 `NOTE: QC ASSERTION OK -- QC-05 ... out of range ... = 0` | No — Wave 0 |

### Sampling Rate

- **Per task commit:** Static grep checks (see below)
- **Per wave merge:** Not applicable — Phase 5 is a single plan
- **Phase gate:** Human runs `05_qc_merge.sas`; verifies all assertion OK lines in log; verifies `qc/05_qc_merge_report.txt` is committed

### Wave 0 Gaps

- [ ] `sas/05_qc_merge.sas` — does not exist yet; this phase creates it
- [ ] `qc/05_qc_merge_report.txt` — created by the program on first run; must not be gitignored
- [ ] Reference width table (owner widths for QC-02) — planner must build by reading `qc/03_charvars_all.txt` and `qc/02_ownership_map.txt`

### Static Verification Commands (after code is written, before human SAS run)

```bash
grep -c "SECTION" sas/05_qc_merge.sas          # expect >= 6
grep -c "assert_eq" sas/05_qc_merge.sas         # expect >= 14 (1 def + 1 QC-01 + 2 QC-02 + 1 QC-03 + N QC-04 + 8 QC-05)
                                                #   N = the md8-owned variable count, ~20, derived at run time --
                                                #   do NOT hardcode a QC-04 count in a grep
grep -in "&SQLOBS" sas/05_qc_merge.sas          # expect 0
grep -in "abort cancel" sas/05_qc_merge.sas     # all must be inside macro def — check manually
grep -in "_CHARACTER_" sas/05_qc_merge.sas      # expect >= 1 (QC-03 array scan)
grep -in "05_qc_merge_report" sas/05_qc_merge.sas   # expect >= 1 (artifact write)
grep -in "IS NOT MISSING" sas/05_qc_merge.sas   # expect >= 8 (QC-05 range guards)
grep -in "values (" sas/05_qc_merge.sas         # QC-02 reference table; must follow CREATE TABLE + INSERT,
                                                #   never SELECT * FROM (VALUES ...) -- not SAS syntax
grep -in "Cognitive_Score > 30" sas/05_qc_merge.sas  # expect 0 -- the bound is 0-3, not MMSE 0-30
grep -in "Admit_BMI > 80" sas/05_qc_merge.sas        # expect 0 -- observed max is 88.32; ceiling is 100
```

---

## Open Questions

1. **QC-04 Part A assertion strength** — RESOLVED by measurement
   - The stronger reading ("every md8 row has a non-missing value") is factually false for most of
     the block: `ABP_LESS_THAN_60_COUNT` is 3,519 of 22,473, `AVG_ABP_Mean` 4,005, and only the
     pressor/medication `Total_*` columns reach 22,473. Arterial-line and BIS monitoring are not
     used on most cases.
   - Resolution: assert Part B = 0 (scoping). Log Part A counts WITH the expected magnitudes
     above so a reviewer can tell normal sparsity from a conversion failure.

2. **QC-02 reference table completeness**
   - What we know: `qc/03_charvars_all.txt` lists all character variables per source. The merged
     file has fewer columns than the union of all sources (due to KEEP=ownership).
   - What's unclear: The exact set of character variables in `g.master_data_merged` is known only
     after PROC CONTENTS runs. The planner must read the QC artifact before building the reference
     table.
   - Recommendation: The plan's Task 1 should include a read of `qc/03_charvars_all.txt` and
     `qc/02_ownership_map.txt` as required context before writing the reference table.

3. **Cognitive_Score and Frailty_Score range: md3 vs md8 owner** — PARTIALLY RESOLVED
   - Measured in the merged file: `Cognitive_Score` ranges 0-3 (NOT MMSE 0-30) and
     `Frailty_Score` ranges 0-5. QC-05 bounds are set from these observations.
   - Still open: whether md8's converted numerics landed as separate columns. The planner must
     confirm the exact column names present before coding the range checks. Original note follows.

   ORIGINAL:
   - What we know: md3 owns `Cognitive_Score` and `Frailty_Score` in the merged file (rule: md3
     carries them, md3 wins). md8's converted numeric versions of these are also present — Phase 4
     INTERFACES noted that md3 and md8 both carry `Cognitive_Score` and `Frailty_Score`, and md3
     wins by the rule. This means the values in the merged file come from md3, not from md8's
     converted numerics.
   - What's unclear: If md3 owns `Cognitive_Score` and `Frailty_Score` but md8 also has them as
     converted numerics, did those numeric conversions produce separate columns in the merged file
     (with `_Value` suffix variants) or were they subsumed? STATE.md notes "the five *_Value numeric
     variants (md3, md5) and the five character variants (md6, md7) land as ten separate columns"
     for frailty — suggesting `Frailty_Score` from md8 may be a distinct column.
   - Recommendation: The planner must read `sas/04_merge.sas` SECTION 3 LENGTH block to determine
     exactly which variable names are present in `g.master_data_merged` before coding QC-05 range
     checks. Apply range checks only to variables confirmed to be in the merged file.

---

## Sources

### Primary (HIGH confidence)

- `sas/04_merge.sas` (560 lines) — established `%assert_eq` pattern; paths; confirmed md8 owns zero char vars; confirmed all 14 assertions passed
- `qc/04_merge_provenance.txt` — committed artifact confirming row counts: total=41,150, in_md8=22,473
- `.planning/phases/04-merge/04-VERIFICATION.md` — confirms all 14 MRG ASSERTION OK lines; human SAS run 2026-08-26
- `qc/03_charvars_all.txt` — authoritative character variable widths per source (Wave 0 artifact)
- `sas/03_prep_md8.sas` — confirms conversion approach; shows which 8 variables were converted and how; post-conversion assertions pattern
- `.planning/STATE.md` — locked decisions (PCM-T-01, PCM-T-02, PCM-R-05, PCM-C-01); row count targets; pending decisions (PCM-D-07 age floor)
- `REQUIREMENTS.md` — QC-01 through QC-05 requirement text

### Secondary (MEDIUM confidence)

- SAS 9.4 DATA step documentation (training knowledge): `ARRAY _CHARACTER_` scope, `IS NOT MISSING` guard behavior for numeric missing, FILE/PUT MOD append behavior
- Clinical range references (training knowledge): ASA 1-6 scale, MMSE 0-30, Fried frailty 0-5 — standard clinical instruments

### Tertiary (LOW confidence)

- QC-04 Part A interpretation — derives from requirement wording, not an authoritative document

---

## Metadata

**Confidence breakdown:**
- QC-01 pattern: HIGH — direct copy of Phase 4 SECTION 5
- QC-02 pattern: HIGH for PROC CONTENTS approach; MEDIUM for reference table completeness (requires reading two QC artifacts)
- QC-03 pattern: HIGH — established ARRAY _CHARACTER_ approach from Phase 3
- QC-04 Part B pattern: HIGH — PROC SQL COUNT with in_md8 filter; clean assertion
- QC-04 Part A interpretation: MEDIUM — requirement wording is ambiguous
- QC-05 ranges: MEDIUM — clinically reasonable but not validated against actual data distribution

**Research date:** 2026-08-26
**Valid until:** Stable — SAS 9.4 patterns do not change; re-research only if source data or merge output changes
