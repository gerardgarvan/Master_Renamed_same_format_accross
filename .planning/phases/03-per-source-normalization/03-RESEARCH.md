# Phase 3: Per-Source Normalization - Research

**Researched:** 2026-08-26
**Domain:** SAS 9.4M8 on Windows -- type conversion, NULL sentinel handling, character width enforcement, exception reporting
**Confidence:** HIGH -- all patterns are native SAS 9.4 already established in Phases 1 and 2; md8-specific anomalies are documented project facts
**Revised:** 2026-08-26 (post-review)

## Revision log -- 2026-08-26 post-review

| Change | Reason |
|---|---|
| md8 source widths removed from the anomaly table | Six of eight were wrong (`$11` given for six variables that are `Char 4`). `qc/03_charvars_all.txt` is the only source of truth |
| Pattern 2: `length ... 8.` corrected to `length ... 8` | A trailing period in a LENGTH statement is a syntax error |
| Pattern 5: `%local` removed from an open-code PROC SQL block | `%LOCAL` is valid only inside a macro definition |
| Open Question 4: g library moved outside the repo tree | `git clean -xdf` deletes ignored files (would wipe all prep datasets); a gitignore line is the only barrier to a PHI commit (new Pitfall 9) |
| PREP-07 added: `Base_Procedure_Code_1` harmonized to CHAR in md4-md7 | The split was noted but no plan implemented it, breaking the stated Phase 4 contract |
| New Pitfall 10: hollow exception report | The md1-md7 template wrote a hardcoded `0`, defeating PREP-02 for seven of eight sources |
| md6: equality assertion added before the `PRECEDE_Study_ID_1` drop | PCM-D-06 is recorded as resolved on an identity claim that may never have been executed |

---

## Project Constraints (from CLAUDE.md)

- SAS 9.4M8 on Windows; session encoding is NOT UTF-8 -- encoding damage confined to `Base_Procedure_1`, <=9 rows; flag only, do not re-encode (PCM-C-01)
- Source files `master_data_1..8.sas7bdat` are **read-only** -- prep programs read from `src`, write to `work` or `g.`
- No PHI in git: `.sas7bdat`, `.xlsx`, `.csv`, `data/` tree are gitignored; only `.sas` programs and plain-text QC/log artifacts may be committed
- No `data X; set X;` patterns (destroys dataset, PCM-T-02)
- No PROC SQL UPDATE (silent truncation, PCM-T-01)
- `%abort cancel` must be inside a macro definition -- never in open code (PCM-R-05)
- `SELECT COUNT(*) INTO :n TRIMMED` for all counted assertions -- never `&SQLOBS` (Phases 1-2 Pitfall)
- Repo on local disk; source data on P: drive
- Stale-artifact filter uses `IN`, never `IN:` (prefix match trap, Phase 2 Pitfall 1)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PREP-01 | Eight independently-runnable prep programs (`03_prep_md1.sas` ... `03_prep_md8.sas`) exist and each completes without error | Each program: `libname src` read-only, precondition checks, DATA step read source -> write `work.prep_mdN`, no in-place rewrites |
| PREP-02 | Exception report written to `qc/` before any type conversion executes; zero rows is the pass condition | Pre-conversion PROC SQL scan for anomalies (NULL strings in unexpected columns, char-typed numerics, range violations) writes to `qc/03_exceptions_mdN.txt`; abort if nonzero |
| PREP-03 | md8 literal `NULL` sentinel is cleared and all md8 forced-char numerics are correctly converted to numeric type | INPUT function for char-to-num conversion; conditional `if strip(upcase(var)) = 'NULL' then var = .;` for sentinel clearing; post-conversion range assertions |
| PREP-04 | `PRECEDE_Study_ID_1` duplicate column in md6 is dropped from prep output | DROP statement in the DATA step that writes `work.prep_md6` |
| PREP-05 | Every character variable has an explicit `length` statement before every `merge`/`set` in prep code (PCM-R-02) | LENGTH statement block placed at top of every DATA step that uses SET or MERGE; widths sourced from PROC CONTENTS output |
| PREP-07 | `Base_Procedure_Code_1` harmonized to CHARACTER `$10` in md4-md7, so Phase 4 receives one consistent type across all eight | `put(Base_Procedure_Code_1, best12.)` + `strip()` into a `$10` target in the md4-md7 prep DATA steps; assert type via `dictionary.columns` after |
| PREP-06 | Conversion counts for each prep program written to `logs/` | FILE/PUT to `logs/03_conversions_mdN.txt` at end of each program; count of rows affected per conversion operation |
</phase_requirements>

---

## Summary

Phase 3 produces eight standalone SAS prep programs (`03_prep_md1.sas` ... `03_prep_md8.sas`), one per source. Each program reads its source dataset read-only, applies all known type and structural normalization, and writes a clean intermediate to `work.prep_mdN` (or `g.prep_mdN` if persistence across programs is needed -- see Open Questions). The programs are designed to run independently and also to be called from `99_run_all.sas`.

The dominant normalization work is concentrated in md8: eight variables that were forced to character (CHAR $4 or $11) must be converted back to numeric, and every occurrence of the literal four-character string `'NULL'` must be replaced with SAS missing before any merge. For the other seven sources the prep programs are largely structural -- explicit LENGTH statements, drop of `PRECEDE_Study_ID_1` from md6, and the pre-conversion exception report before touching any data. All seven sources must still get the exception scan and the LENGTH statement discipline; the absence of anomalies is not assumed, it is asserted.

The output of each prep program is the input to Phase 4 (`04_merge.sas`). Phase 4 must be able to execute a clean merge using `work.prep_md1` ... `work.prep_md8` with no further type or width corrections. That constraint drives the design: every prep program must leave its output in an agreed state, verified by an end-of-program assertion.

**Primary recommendation:** Build a shared macro library (`03_prep_macros.sas` or inline in each program) that provides: pre-conversion exception scan, char-to-num conversion with count logging, NULL sentinel clearing, and post-conversion range assertion. The eight programs then call these shared macros with source-specific parameters, keeping each program short and auditable. All programs use identical structure: Section 0 (paths/libnames), Section 1 (preconditions), Section 2 (exception report), Section 3 (normalization), Section 4 (conversion count log), Section 5 (post-conversion assertion), Section 6 (close-out).

---

## Known Source-Specific Anomalies

This is the authoritative inventory from accumulated project context. Every item must be addressed in the corresponding prep program.

### md8 -- Primary normalization target

From STATE.md and Phase 2 research:

| Variable | Target Type | Conversion Method | NULL handling |
|---|---|---|---|
| `Admit_BMI` | NUMERIC | `input(strip(var), best12.)` | clear 'NULL' first |
| `ASA__Anesth_Record_` | NUMERIC | `input(strip(var), best12.)` | clear 'NULL' first |
| `Age_at_Encounter` | NUMERIC | `input(strip(var), best12.)` | clear 'NULL' first |
| `Cognitive_Score` | NUMERIC | `input(strip(var), best12.)` | clear 'NULL' first |
| `Frailty_Score` | NUMERIC | `input(strip(var), best12.)` | clear 'NULL' first |
| `rt_INCISE_to_DRESS_mins` | NUMERIC | `input(strip(var), best12.)` | clear 'NULL' first |
| `rt_RM_START_to_INCISION_mins` | NUMERIC | `input(strip(var), best12.)` | clear 'NULL' first |
| `rt_RM_START_to_RM_END_mins` | NUMERIC | `input(strip(var), best12.)` | clear 'NULL' first |

**Source widths are deliberately NOT listed here.** An earlier draft of this table gave `$11`
for `Age_at_Encounter`, `Cognitive_Score`, `Frailty_Score` and all three `rt_*` variables; they
are `Char 4`. Six of the eight were wrong. Only `Admit_BMI` ($11) and `ASA__Anesth_Record_` ($4)
were correct. **The single source of truth for every character width is
`qc/03_charvars_all.txt`, produced by Wave 0 (`03_prep_setup.sas`).** Do not hardcode a width in
a plan, an interfaces block, or this document — read it from the artifact. Over-declaring is
survivable (LENGTH-before-SET wins, it just wastes bytes); under-declaring truncates.

Additionally, md8 uses literal `'NULL'` throughout character variables (not just the eight forced-char numerics). Every character variable in md8 must be scanned for the sentinel, and any occurrence cleared to blank (SAS missing) before the dataset is passed to Phase 4.

### Base_Procedure_Code_1 -- cross-source type split (PREP-07)

`Base_Procedure_Code_1` is **CHAR $10 in md1/md2/md3/md8 and NUM 8 in md4-md7**. Unlike the
death-variable naming (PCM-D-01), the frailty encoding (PCM-D-02) and ISO_SEV (PCM-D-03), this
is not waiting on a decision -- it is a mechanical conflict with a known correct resolution.

**Harmonize to CHARACTER $10 in md4-md7.** Converting the other direction destroys any code with
a leading zero or an alphabetic character; `put(numvar, best12.)` then `strip()` is lossless in
the char direction. Phase 1's leading-zero audit (PCM-F-08) came back empty, so the conversion
is safe, but character remains the correct target because it preserves the md1/md2/md3/md8 form.

**This must happen in Phase 3, not Phase 4.** The Summary below states Phase 4 receives sources
needing "no further type or width corrections." Leaving this split breaks that contract: Phase 4
would still be doing type work. An earlier draft of this document mentioned the split only as a
note and no plan implemented it. It is now PREP-07 (see Phase Requirements).

### md6 -- Structural anomaly

- `PRECEDE_Study_ID_1`: duplicate column, identical to `PRECEDE_STUDY_ID`. Drop it in `03_prep_md6.sas` via a DROP statement. Document in `docs/DECISIONS.md` (PCM-D-06, already resolved).

### All sources -- Encoding flag

- `Base_Procedure_1` in each source has up to 9 rows with encoding damage (non-ASCII characters). Do NOT attempt re-encoding. The exception report for each source must flag these rows by count. Prep programs record the count but do not modify the values.

### md1-md7 -- No forced-char numerics

These sources do not have the md8 NULL sentinel or forced-char numeric problem. Their prep programs are primarily: LENGTH statement blocks, the exception scan, and the conversion count log (which will record zero conversions -- that is the expected and desirable output).

---

## Standard Stack

### Core

| Tool/Pattern | Version | Purpose | Why Standard |
|---|---|---|---|
| `DATA work.prep_mdN; LENGTH ...; SET src.master_data_N; ...` | SAS 9.4 | Read-only source scan with explicit widths | LENGTH before SET declares widths before any observation is read; prevents truncation |
| `INPUT(STRIP(charvar), best12.)` | SAS 9.4 | Convert character-typed numeric to numeric | Handles leading/trailing blanks; `best12.` informat is appropriate for integer and decimal clinical values |
| `IF STRIP(UPCASE(charvar)) = 'NULL' THEN charvar = ' ';` | SAS 9.4 | Clear md8 NULL sentinel in character variables | Conditional assignment; no INPUT needed (sentinel stays character, just becomes blank) |
| `PROC SQL; SELECT COUNT(*) INTO :n TRIMMED` | SAS 9.4 | Exception counting; post-conversion assertions | Established in Phases 1-2; never `&SQLOBS` |
| `FILE "logs/..." ; PUT "...";` | SAS 9.4 | Write conversion count log (PREP-06) | Same FILE/PUT pattern as Phase 1 QC artifacts |
| `DROP PRECEDE_Study_ID_1;` in DATA step | SAS 9.4 | Remove duplicate column from md6 (PREP-04) | DROP statement processed at compile time; simplest correct approach |
| `%abort cancel;` inside a macro | SAS 9.4 | Loud failure on nonzero exception count | Established Phase 1 pattern |

### Supporting

| Tool/Pattern | Version | Purpose | When to Use |
|---|---|---|---|
| `PROC CONTENTS DATA=src.master_data_N OUT=work.contents_mdN NOPRINT` | SAS 9.4 | Discover variable names, types, lengths before writing LENGTH statements | Run once per source in Wave 0 to generate the LENGTH statement block; also run in the exception scan |
| `%sysfunc(libref(src))` | SAS 9.4 | Verify P: drive available before proceeding | Precondition Section 1, identical to Phases 1-2 |
| `PROC SQL WHERE upcase(name) IN (...)` | SAS 9.4 | Verify specific variables exist and have expected types in the pre-conversion check | Target the eight forced-char numerics in md8 specifically |

### Installation

No external packages. All tools are SAS 9.4 base product.

---

## Architecture Patterns

### Recommended Program Structure (repeated for each of 8 programs)

```
03_prep_mdN.sas
  SECTION 0: Options, %let paths, libname src (read-only), libname g (if needed)
  SECTION 1: Preconditions
    -- libname src resolves
    -- qc/ and logs/ directories exist
    -- [md8 only] PROC CONTENTS assertion that forced-char variables are CHAR
       (confirms we are reading the right version of the source)
  SECTION 2: Exception report (PREP-02)
    -- PROC SQL scan for: NULL sentinels in char variables,
       out-of-range numeric values (pre-conversion only),
       encoding-damaged rows in Base_Procedure_1
    -- Write to qc/03_exceptions_mdN.txt
    -- Count exceptions into :n_exceptions
    -- %abort cancel if n_exceptions > 0
       EXCEPT: encoding damage in Base_Procedure_1 is a WARNING, not abort
  SECTION 3: Normalization DATA step
    -- LENGTH statements for ALL character variables (PCM-R-02)
       declared BEFORE the SET statement
    -- [md8 only] NULL sentinel clearing for all char vars
    -- [md8 only] INPUT() conversion for the eight forced-char numerics
       (on NEW numeric variables; DROP the old char version)
    -- [md6 only] DROP PRECEDE_Study_ID_1
    -- Output: work.prep_mdN
  SECTION 4: Conversion count log (PREP-06)
    -- Count rows converted (md8: INPUT applied)
    -- Count NULL sentinels cleared (md8)
    -- Count rows with encoding damage flagged (all sources)
    -- Write to logs/03_conversions_mdN.txt
  SECTION 5: Post-conversion assertions
    -- Surviving NULL strings = 0 (md8)
    -- Type of each converted variable = NUMERIC (md8)
    -- Duplicate column PRECEDE_Study_ID_1 absent (md6)
    -- Row count of work.prep_mdN = source row count (all sources)
  SECTION 6: Close-out
    -- %put NOTE: ==== Phase 3 prep mdN complete ====
    -- libname src clear (if not needed by downstream in run_all)
```

### Pattern 1: LENGTH statement block before SET (PCM-R-02)

```sas
/* PREP-05: All character variable lengths declared BEFORE the SET statement.
   Widths from PROC CONTENTS run in Wave 0 against src.master_data_N.
   Never allow SAS to infer width from the first observation (causes
   truncation when that observation is shorter than the maximum).          */
data work.prep_md1;
  length
    PRECEDE_STUDY_ID    $12
    Base_Procedure_1    $200   /* confirm max width from PROC CONTENTS */
    /* ... all other character variables in this source ... */
    ;
  set src.master_data_1;
  /* normalization code here */
run;
```

**CRITICAL:** The LENGTH statement must come before the SET statement in every DATA step that reads source data. If SET comes first, SAS assigns widths from the dataset descriptor and the LENGTH statement is ignored for variables already defined.

**Confidence:** HIGH -- SAS 9.4 DATA step compilation rule; stable across all 9.4 releases.

### Pattern 2: NULL sentinel clearing then char-to-num conversion (md8)

```sas
/* Step 1: Clear NULL sentinels in ALL character variables.
   Done first, before any INPUT() conversion, so the conversion
   never receives the literal string 'NULL' as input.
   INPUT('NULL', best12.) produces a missing value with a NOTE in the log
   about invalid input -- acceptable, but the sentinel clear is cleaner
   and explicit about intent.                                             */
data work.prep_md8_s1;
  length
    PRECEDE_STUDY_ID        $12
    Admit_BMI_c             $11   /* width from qc/03_charvars_all.txt, not guessed */
    /* ... all char vars, widths from qc/03_charvars_all.txt ... */
    ;
  set src.master_data_8;

  /* Clear NULL sentinel in all character variables */
  array charv {*} _CHARACTER_;
  do _i = 1 to dim(charv);
    if strip(upcase(charv{_i})) = 'NULL' then charv{_i} = ' ';
  end;
  drop _i;
run;

/* Step 2: Convert the eight forced-char numerics.
   Read from work.prep_md8_s1 (not from src -- read-only source is done).
   Rename the char variable to a temp name; create the new numeric with the
   original name.
   INPUT(STRIP(var), best12.) handles blanks (now missing) cleanly --
   INPUT('', best12.) = . (missing numeric), which is correct.            */
data work.prep_md8;
  length
    PRECEDE_STUDY_ID        $12
    /* ... all char vars (excluding the eight being converted) ... */
    Admit_BMI               8   /* numeric target -- NO trailing period */
    ASA__Anesth_Record_     8
    Age_at_Encounter        8
    Cognitive_Score         8
    Frailty_Score           8
    rt_INCISE_to_DRESS_mins             8
    rt_RM_START_to_INCISION_mins        8
    rt_RM_START_to_RM_END_mins          8
    ;
  set work.prep_md8_s1
    (rename=(Admit_BMI=Admit_BMI_c
             ASA__Anesth_Record_=ASA_c
             Age_at_Encounter=Age_c
             Cognitive_Score=Cog_c
             Frailty_Score=Frailty_c
             rt_INCISE_to_DRESS_mins=rt1_c
             rt_RM_START_to_INCISION_mins=rt2_c
             rt_RM_START_to_RM_END_mins=rt3_c));

  Admit_BMI           = input(strip(Admit_BMI_c),           best12.);
  ASA__Anesth_Record_ = input(strip(ASA_c),                 best12.);
  Age_at_Encounter    = input(strip(Age_c),                 best12.);
  Cognitive_Score     = input(strip(Cog_c),                 best12.);
  Frailty_Score       = input(strip(Frailty_c),             best12.);
  rt_INCISE_to_DRESS_mins          = input(strip(rt1_c),    best12.);
  rt_RM_START_to_INCISION_mins     = input(strip(rt2_c),    best12.);
  rt_RM_START_to_RM_END_mins       = input(strip(rt3_c),    best12.);

  drop Admit_BMI_c ASA_c Age_c Cog_c Frailty_c rt1_c rt2_c rt3_c;
run;
```

**Why two steps:** Separating sentinel clearing from type conversion keeps the DATA steps readable and makes the conversion count log meaningful. The intermediate `work.prep_md8_s1` is a WORK dataset and is not committed.

**Confidence:** HIGH -- `INPUT()`, `RENAME=`, `DROP` are SAS 9.4 base.

**Alternative (single-step):** Combine both DATA steps into one by using temporary `_charN_` variables. Acceptable, but harder to audit. Two steps is preferred for this pipeline.

### Pattern 3: Pre-conversion exception report (PREP-02)

```sas
/* Exception scan must run BEFORE Pattern 2 DATA step.
   Counts:
     1. Unexpected NULL sentinels in variables that should not carry them
        (sanity check; we expect them throughout md8)
     2. Non-numeric content in the forced-char numerics (values that are
        not 'NULL', not blank, and not parseable as a number)
     3. Base_Procedure_1 encoding damage (non-ASCII bytes -- WARNING only)
   Zero rows required (exception for encoding damage) before any conversion.  */

/* Non-numeric content check for one forced-char numeric.
   Adapt this pattern for each of the eight variables.                       */
proc sql noprint;
  create table work.exc_md8 as
    select 'Admit_BMI_c' as variable length=40,
           PRECEDE_STUDY_ID,
           Admit_BMI as raw_value length=11,
           'non-numeric content' as exception_type length=30
    from src.master_data_8
    where Admit_BMI not in ('NULL', '')
      and strip(Admit_BMI) ne ''
      and notdigit(compress(strip(Admit_BMI), '.-')) > 0
  union all
    select 'ASA__Anesth_Record_', PRECEDE_STUDY_ID,
           ASA__Anesth_Record_, 'non-numeric content'
    from src.master_data_8
    where ASA__Anesth_Record_ not in ('NULL', '')
      and strip(ASA__Anesth_Record_) ne ''
      and notdigit(compress(strip(ASA__Anesth_Record_), '.-')) > 0
  /* ... repeat for each of the eight forced-char numerics ... */
  ;
  select count(*) into :n_exc trimmed from work.exc_md8;
quit;

filename excfile "&qc_path.\03_exceptions_md8.txt";
data _null_;
  file excfile;
  put "md8 Exception Report -- Run: %sysfunc(datetime(), datetime20.)";
  put "Non-parseable values in forced-char numerics: &n_exc";
run;
/* If exceptions > 0, append detail rows */
data _null_;
  set work.exc_md8;
  file excfile mod;
  put variable $40. ' | ' PRECEDE_STUDY_ID $12. ' | ' raw_value $11. ' | ' exception_type $30.;
run;
filename excfile clear;

%macro assert_zero_exc(n=, msg=);
  %if &n > 0 %then %do;
    %put ERROR: PREP-02 VIOLATION -- &n &msg;
    %abort cancel;
  %end;
%mend assert_zero_exc;
%assert_zero_exc(n=&n_exc, msg=non-parseable values in md8 forced-char numerics);
```

**Confidence:** HIGH -- `NOTDIGIT()`, `COMPRESS()`, PROC SQL union, FILE/PUT patterns all established in Phases 1-2.

### Pattern 4: Conversion count log (PREP-06)

```sas
/* Count actual conversions performed.
   For md8: count rows where a forced-char numeric was non-missing and
   the resulting numeric is also non-missing (successful conversion).
   Count rows where result is missing = cases where the input was 'NULL' or blank.  */
proc sql noprint;
  select count(*) into :n_total trimmed from work.prep_md8;
  select count(*) into :n_bmi_conv trimmed
    from work.prep_md8 where Admit_BMI is not missing;
  select count(*) into :n_bmi_null trimmed
    from work.prep_md8_s1 where strip(upcase(Admit_BMI)) = 'NULL';
  /* ... repeat for each variable ... */
quit;

filename convlog "&logs_path.\03_conversions_md8.txt";
data _null_;
  file convlog;
  put "md8 Conversion Count Log -- Run: %sysfunc(datetime(), datetime20.)";
  put "Total rows: &n_total";
  put "Admit_BMI -- converted non-missing: &n_bmi_conv  |  NULL sentinel cleared: &n_bmi_null";
  /* ... one line per variable ... */
run;
filename convlog clear;
```

**Confidence:** HIGH -- same FILE/PUT pattern as Phase 1.

### Pattern 5: Post-conversion assertions

```sas
/* Verify no surviving NULL strings in work.prep_md8 (PREP-03).
   After sentinel clearing and type conversion, zero NULL strings must remain.  */
proc sql noprint;
  create table work._null_check as
    select name from dictionary.columns
    where libname = 'WORK' and memname = 'PREP_MD8' and type = 'char';
  /* Dynamic scan across all character vars -- but for predictability and
     auditability, enumerate them explicitly in this pipeline.             */
  select count(*) into :n_null_surv trimmed
  from work.prep_md8
  where /* list each character variable explicitly */
        strip(upcase(charvar1)) = 'NULL'
     or strip(upcase(charvar2)) = 'NULL'
     /* ... */
     ;
quit;
%assert_zero_exc(n=&n_null_surv, msg=surviving NULL sentinel strings in work.prep_md8);
/* NOTE: an earlier draft placed `%local n_null_surv;` inside this PROC SQL block.
   %LOCAL is valid only inside a macro definition -- in open code it is an error.
   Macro variables created by SELECT ... INTO in open code are global already.     */

/* Verify row count preserved */
proc sql noprint;
  select count(*) into :n_prep trimmed from work.prep_md8;
quit;
%macro assert_row_count(actual=, expected=, src=);
  %if &actual ne &expected %then %do;
    %put ERROR: PREP row count mismatch for &src -- expected &expected got &actual;
    %abort cancel;
  %end;
%mend assert_row_count;
%assert_row_count(actual=&n_prep, expected=22473, src=md8);
```

Row counts from Phase 1 (`qc/src_counts.txt`): md1=14,778; md2=14,778; md3=41,150; md4=7,695; md5=7,695; md6=9,462; md7=9,215; md8=22,473. These are the expected row counts for post-prep assertion.

**Confidence:** HIGH.

### Anti-Patterns to Avoid

- **`data work.prep_md8; set work.prep_md8;`**: Destroys the dataset (PCM-T-02). Always write to a new name.
- **`PROC SQL UPDATE` for conversion**: Silent truncation if the character column is narrower than the updated value (PCM-T-01). Use DATA step with RENAME instead.
- **LENGTH statement after SET**: SAS assigns widths from the file descriptor on SET; a subsequent LENGTH is ignored for variables already typed. Put LENGTH first, always.
- **`INPUT(var, best12.)` without STRIP**: Leading/trailing blanks in a character field cause NOTE-level invalid input data messages; STRIP before INPUT eliminates these.
- **Not explicitly naming the RENAME= variables**: An `array charv {*} _CHARACTER_` loop for sentinel clearing will include the temporary renamed variables if they are still character -- use explicit variable lists or the two-step approach.
- **Skipping the exception report on md1-md7**: The absence of known anomalies does not mean the exception report can be omitted. PREP-02 requires an exception report for every source. For md1-md7 the report is expected to show zero; an unexpected nonzero count is the signal that something changed in the source.
- **Writing conversion logs to `qc/` instead of `logs/`**: PREP-06 specifies `logs/`; PREP-02 specifies `qc/`. These are different output directories with different committed-artifact semantics.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Char-to-num conversion with sentinel handling | Custom IF-THEN chains for each value | `INPUT(STRIP(var), best12.)` after sentinel clearing | `INPUT` is the SAS-standard informat-based converter; handles blank, numeric, and decimal correctly |
| Detecting non-numeric content in a character column | Nested character function comparisons | `NOTDIGIT(COMPRESS(strip(var), '.-'))` to find non-digit, non-decimal, non-sign characters | Compact, handles negative numbers and decimals |
| Clearing a sentinel across all character columns | Hard-coded `if var1 = 'NULL' then var1 = '';` times N | `ARRAY _c {*} _CHARACTER_; do i = 1 to dim(_c); if strip(upcase(_c{i})) = 'NULL' then _c{i} = ' '; end;` | Handles future column additions without code change; less error-prone |
| Verifying no surviving NULL strings | Manual scan per variable | Same array pattern in a PROC SQL count across all char vars | Consistent with the clearing step |

**Key insight:** The forced-char numeric problem in md8 is a known historical artefact of an Excel export that introduced `'NULL'` strings where SAS would store missing (`.`). The correct fix is INPUT()-based conversion after sentinel clearing -- not re-importing from Excel.

---

## Common Pitfalls

### Pitfall 1: LENGTH statement after SET -- silently ignored
**What goes wrong:** Character variable widths are set by the SET statement from the source dataset descriptor. A LENGTH statement placed after SET is ignored for those variables, and truncation occurs at the source width.
**Why it happens:** SAS DATA step compilation processes LENGTH before SET only when LENGTH appears first. It is order-dependent.
**How to avoid:** LENGTH block is always the FIRST statement in every DATA step. Verify via PROC CONTENTS on the output dataset that widths match the declared lengths.
**Warning signs:** PROC CONTENTS on `work.prep_mdN` shows a character variable narrower than the declared length.

### Pitfall 2: INPUT('NULL', best12.) produces NOTE, not ERROR
**What goes wrong:** If the NULL sentinel is not cleared before INPUT(), SAS reads `'NULL'` as invalid numeric input, writes a NOTE to the log, and sets the result to missing. This looks correct in the data but the NOTE-storm in the log obscures real problems.
**Why it happens:** `INPUT()` with `best12.` silently sets to missing on non-numeric content.
**How to avoid:** Clear the sentinel first (Pattern 2 Step 1). After clearing, `INPUT(strip(var), best12.)` only sees blanks and valid numerics -- no Notes from invalid input.
**Warning signs:** Many `NOTE: Invalid argument to function INPUT` in the md8 prep log.

### Pitfall 3: ARRAY _CHARACTER_ includes temp renamed variables
**What goes wrong:** When using `RENAME=(Admit_BMI=Admit_BMI_c)` in the SET statement, the array `_CHARACTER_` picks up `Admit_BMI_c` as a character variable and the sentinel loop clears it correctly. But if sentinel clearing and INPUT() are in the same DATA step, the cleared `Admit_BMI_c` is then INPUT'd -- which is correct. The trap is when _CHARACTER_ also picks up variables you intended to exclude.
**Why it happens:** `_CHARACTER_` is all character variables in the PDV at that point.
**How to avoid:** Two-step approach (Pattern 2) avoids this entirely. If single-step is preferred, enumerate character variables explicitly rather than using `_CHARACTER_`.

### Pitfall 4: Post-conversion assertion uses wrong expected row count
**What goes wrong:** The assertion `n_prep = 22473` is hardcoded for md8 but accidentally used for another source.
**Why it happens:** Copy-paste across eight programs.
**How to avoid:** Use a macro parameter or `%let` at the top of each program: `%let expected_nobs = 22473;`. Source the value from `qc/src_counts.txt` (Phase 1 artifact). The expected row counts are: md1=14,778; md2=14,778; md3=41,150; md4=7,695; md5=7,695; md6=9,462; md7=9,215; md8=22,473.

### Pitfall 5: Conversion log directory does not exist
**What goes wrong:** `FILE "logs/03_conversions_mdN.txt"` fails or writes to an unexpected location if `logs/` does not exist.
**Why it happens:** Phase 1 confirmed `qc/` exists but `logs/` was listed as "not confirmed" in Phase 2 research. Phase 2 marked it as a Wave 0 gap.
**How to avoid:** Each prep program must check `%sysfunc(fileexist(&logs_path))` in Section 1 and abort with an actionable message if absent. Wave 0 must verify/create `logs/` before any prep program runs.
**Warning signs:** No `logs/03_conversions_mdN.txt` file after a run that completed without error.

### Pitfall 6: Exception report abort fires on the encoding damage rows
**What goes wrong:** The PREP-02 exception scan includes all anomalies and aborts on nonzero. If encoding damage rows in `Base_Procedure_1` are included in the count, the programs abort on md1-md8 immediately.
**Why it happens:** Encoding damage is a flag-only situation (PCM-C-01), not an abort condition.
**How to avoid:** The exception report query separates encoding-damage rows from conversion-blocking anomalies. Encoding damage is counted and logged as a WARNING; only non-parseable values in forced-char numerics and unexpected NULL patterns trigger abort.

### Pitfall 7: PRECEDE_Study_ID_1 drop missed in md6
**What goes wrong:** `work.prep_md6` still contains `PRECEDE_Study_ID_1`. Phase 4 merge receives two key-like columns in md6, causing confusion or silent overwrite.
**Why it happens:** DROP is easy to forget when focusing on the type conversion work.
**How to avoid:** Add a post-normalization PROC CONTENTS assertion for md6 that counts variables named `PRECEDE_Study_ID_1` and asserts zero. This is a one-line PROC SQL against `dictionary.columns`.

### Pitfall 9: Persistent PHI intermediates inside the git working tree
**What goes wrong:** Two separate failures, both bad. (a) `git clean -xdf` -- a routine
tidy-up -- deletes *ignored* files, so it wipes every `g.prep_mdN` dataset. (b) A single
`git add -f`, an edited `.gitignore`, or a mis-scoped `git add -A` commits full-PHI
`.sas7bdat` files to history, where removing them requires a history rewrite.
**Why it happens:** `C:\Master_Renamed_same_format_accross\data` sits inside the repo
folder, so the only thing separating PHI from a commit is one `.gitignore` line.
**How to avoid:** Site the g library outside the repo entirely -- `C:\PeCAN_work\data` or
`P:\PeCAN Master Data\Gerard\_prep`. No git command can reach it, and PCM-C-04
(repo local, data on P:) is satisfied rather than contradicted.
**Warning signs:** `git status --ignored` lists `.sas7bdat` files; the g library path shares a
prefix with the repo root.

### Pitfall 10: An exception report that reports a hardcoded zero
**What goes wrong:** The md1-md7 structural template writes
`put "Type-conversion anomalies (abort if nonzero): 0";` -- a literal. Nothing is measured, so
the report says `0` even if the source was completely re-exported. PREP-02's stated purpose
("an unexpected nonzero count is the signal that something changed at source") is defeated for
seven of the eight sources, while the artifact looks like evidence of a passing check.
**Why it happens:** md1-md7 have no *known* anomalies, so there seems to be nothing to count.
**How to avoid:** Count something real. The cheapest meaningful scan for md1-md7 is the literal
`'NULL'` sentinel across their character variables -- expected zero, and a genuine
"was this re-exported from Excel like md8" signal. Reuse the md8 machinery. Any nonzero result
aborts, exactly as PREP-02 specifies.
**Warning signs:** An exception report whose count line contains no macro variable.

### Pitfall 8: Path inconsistency between programs
**What goes wrong:** `03_prep_md1.sas` uses `%let qc_path = C:\...\qc;` but `03_prep_md3.sas` hardcodes a different path. One program writes the exception report to the wrong location.
**Why it happens:** Eight separate programs, each with a Section 0 path block.
**How to avoid:** All eight programs use identical Section 0 `%let` statements. The planner should define these once in the plan and replicate verbatim. From Phase 1: `%let source_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross;` and `%let qc_path = C:\Master_Renamed_same_format_accross\qc;`. Note Phase 2 used a different `qc_path` pointing to the P: drive -- the Phase 1 path (`C:\...\qc`) is correct because that is the git-tracked location where `checksums.txt` and `src_counts.txt` were successfully written.

---

## Code Examples

### Exception report pattern for md1-md7 (encoding damage only)

```sas
/* Exception report for sources with no forced-char numerics.
   Only check: Base_Procedure_1 encoding damage (flag only, not abort).
   Expected result: zero rows in exc_mdN except possibly encoding rows.    */
proc sql noprint;
  create table work.exc_md1 as
    select PRECEDE_STUDY_ID,
           'Base_Procedure_1' as variable length=40,
           Base_Procedure_1 as raw_value length=200,
           'encoding-damage-flag-only' as exception_type length=30
    from src.master_data_1
    where not missing(Base_Procedure_1)
      /* Encoding damage detection: look for characters outside printable ASCII.
         notprint() returns position of first non-printable char; check for
         characters outside ASCII 32-126. This is approximate.              */
      and verify(Base_Procedure_1, ' !"#$%&' || "'" || '()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~') > 0
    ;
  select count(*) into :n_enc_damage trimmed from work.exc_md1;
quit;

filename excfile "&qc_path.\03_exceptions_md1.txt";
data _null_;
  file excfile;
  put "md1 Exception Report -- Run: %sysfunc(datetime(), datetime20.)";
  put "Encoding-damaged rows in Base_Procedure_1 (flag only): &n_enc_damage";
  put "Type-conversion anomalies (abort if nonzero): 0";
run;
filename excfile clear;
/* No abort -- encoding damage is flag-only per PCM-C-01. */
%put NOTE: PREP-02 md1 -- &n_enc_damage encoding-damaged rows flagged in Base_Procedure_1 (no abort).;
```

### Verify PRECEDE_Study_ID_1 absent in md6 output

```sas
proc sql noprint;
  select count(*) into :n_dup_col trimmed
  from dictionary.columns
  where libname = 'WORK'
    and memname = 'PREP_MD6'
    and upcase(name) = 'PRECEDE_STUDY_ID_1';
quit;
%macro assert_col_absent(n=, colname=, dsn=);
  %if &n > 0 %then %do;
    %put ERROR: PREP-04 VIOLATION -- column &colname still present in &dsn after DROP;
    %abort cancel;
  %end;
%mend assert_col_absent;
%assert_col_absent(n=&n_dup_col, colname=PRECEDE_Study_ID_1, dsn=work.prep_md6);
```

---

## State of the Art

| Old Approach | Current Approach | Notes |
|---|---|---|
| PROC SQL UPDATE to convert char to num | DATA step with RENAME= and INPUT() | PCM-T-01 prohibits PROC SQL UPDATE; DATA step is the correct tool |
| `data X; set X;` in-place normalization | Read source to `work.prep_mdN` (new name) | PCM-T-02 prohibits in-place rewrite |
| Infer character widths from data | Explicit LENGTH statement before SET | PCM-R-02; required for every prep program |
| Assume NULL strings will not survive | Post-conversion assertion for zero NULL strings | Phase 4 QC-03 re-asserts this on the merged file; Phase 3 asserts it per source |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| SAS 9.4M8 | All 8 prep programs | Assumed (project constraint) | M8 | None |
| P: drive (src libname) | All 8 prep programs Section 2 | Verified (Phase 1 passed) | -- | Abort precondition |
| `qc/` directory | PREP-02 exception reports | Yes (confirmed, contains Phase 1 artifacts) | -- | -- |
| `logs/` directory | PREP-06 conversion logs | Not confirmed (Phase 2 Wave 0 gap, unresolved) | -- | Wave 0 must create |
| `C:\Master_Renamed_same_format_accross\` local repo | Output path for QC/log artifacts | Yes (confirmed) | -- | -- |

**Missing dependencies with no fallback:**
- P: drive must be mapped; each program aborts if libref fails.

**Missing dependencies with fallback:**
- `logs/` directory: if absent, Wave 0 creates it before any prep program runs. No fallback is acceptable at runtime; creation is a precondition.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | SAS log assertions -- `%abort cancel` on violation; `NOTE:` messages for pass; artifact existence checks |
| Config file | none |
| Quick run command | `sas -sysin "C:\Master_Renamed_same_format_accross\sas\03_prep_md8.sas" -log "C:\Master_Renamed_same_format_accross\logs\03_prep_md8.log"` |
| Full suite command | Run all eight programs sequentially; then `sas -sysin sas\99_run_all.sas` in Phase 8 |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Signal | File Exists? |
|--------|----------|-----------|------------------|-------------|
| PREP-01 | Each of 8 programs runs without ERROR | smoke | Log contains `NOTE: ==== Phase 3 prep mdN complete`; no `ERROR:` | No -- Wave 0 |
| PREP-02 | Exception report written before conversion | output artifact | `qc/03_exceptions_mdN.txt` exists after run | No -- Wave 0 |
| PREP-02 | Zero conversion-blocking exceptions | embedded assertion | `%abort cancel` if `n_exc > 0`; log shows `NOTE: PREP-02 mdN -- 0 anomalies` | No -- Wave 0 |
| PREP-03 | md8 NULL sentinel cleared, char-to-num correct | embedded assertion + output check | Zero surviving NULL strings in `work.prep_md8`; eight variables are NUMERIC in PROC CONTENTS of output | No -- Wave 0 |
| PREP-04 | `PRECEDE_Study_ID_1` absent from md6 output | embedded assertion | `%abort cancel` if `dictionary.columns` finds the column in `work.prep_md6` | No -- Wave 0 |
| PREP-05 | LENGTH before SET in all DATA steps | code review | `grep -n "length" sas/03_prep_mdN.sas` returns hits that precede `grep -n "set src\." sas/03_prep_mdN.sas` line numbers | No -- Wave 0 |
| PREP-06 | Conversion count log written to `logs/` | output artifact | `logs/03_conversions_mdN.txt` exists after run | No -- Wave 0 |

### Sampling Rate

- **Per task commit:** Run the prep program for the affected source; check log for ERROR-free completion and artifact existence
- **Per wave merge:** Run all 8 programs sequentially; verify all 16 artifacts (8 exception reports + 8 conversion logs) exist
- **Phase gate:** All 8 programs ERROR-free; all exception reports show zero conversion-blocking anomalies; `work.prep_md8` has zero NULL strings and correct numeric types

### Wave 0 Gaps

- [ ] `logs/` directory -- must be created before any prep program runs (Phase 2 unresolved gap)
- [ ] `sas/03_prep_md1.sas` through `sas/03_prep_md8.sas` -- none exist yet
- [ ] `qc/03_exceptions_md1.txt` through `qc/03_exceptions_md8.txt` -- created by programs on first run; must not be gitignored
- [ ] `logs/03_conversions_md1.txt` through `logs/03_conversions_md8.txt` -- created by programs on first run; must not be gitignored
- [ ] Verify `logs/` and `qc/03_exceptions_*.txt` are not covered by `.gitignore` rules

---

## Open Questions

1. **Shared macro library vs. inline macros in each program**
   - What we know: Eight programs with identical Section 0-1-4-5-6 structure and shared macros suggests a `03_prep_macros.sas` include file
   - What's unclear: A `%include` creates a dependency that breaks independent runnability (PREP-01) if the include path is wrong, or is a non-issue if the path is always absolute
   - Recommendation: Include macros inline in each program (copy-paste). This guarantees independent runnability and keeps each program self-contained. Document the duplication intentionally. The planner should generate the boilerplate macro blocks as part of the plan.

2. **Output library: WORK vs. g.**
   - What we know: Phase 4 (`04_merge.sas`) will read from `work.prep_md1` ... `work.prep_md8`. WORK is session-scoped; if Phase 3 and Phase 4 run in the same SAS session (via `99_run_all.sas`), WORK is shared. If run independently, the work datasets are not available to Phase 4.
   - What's unclear: Will Phase 4 always be run in the same session as Phase 3, or must it be independently runnable from already-persisted intermediates?
   - Recommendation: Write to `g.prep_mdN` (the persistent library, same as `g.master_data_merged` in the project goal) so Phase 4 can always read them regardless of session order. Add a `libname g "..."` to Section 0 of each prep program. The planner should confirm the `g` library path.

3. **Exact list of character variables per source for LENGTH statements**
   - What we know: LENGTH blocks must be complete -- missing any character variable means its width is inferred from the source, potentially causing truncation downstream
   - What's unclear: The complete variable list and widths for md1-md7 are not documented in planning artifacts; md8's eight forced-char numerics are known but the rest of md8's character variables are not listed
   - Recommendation: Wave 0 runs `PROC CONTENTS DATA=src.master_data_N OUT=work.c_mdN NOPRINT; PROC PRINT DATA=work.c_mdN (WHERE=(type=2)); RUN;` for each source and captures the output. The planner uses these lists to generate the LENGTH statement blocks in each plan. This cannot be skipped.

4. **The `g` library path**
   - What we know: `g.master_data_merged` is the final output; `g` is a named library used across the pipeline
   - What's unclear: The `g` library `libname` path has not been defined in any program yet
   - Recommendation: **Put the g library OUTSIDE the git working tree.** `%let g_path = C:\PeCAN_work\data;` (a plain local folder, not under the repo). See Pitfall 9 -- a gitignored folder inside the repo is not safe for PHI, and `git clean -xdf` deletes ignored files, which would wipe every prep dataset. Add the chosen path to Section 0 of each prep program.

---

## Sources

### Primary (HIGH confidence)
- Phase 1 RESEARCH.md and `sas/01_verify_sources.sas` -- established patterns for `%abort cancel`, `SELECT COUNT(*) INTO :n TRIMMED`, FILE/PUT artifacts, precondition macros
- Phase 2 RESEARCH.md and `sas/02_ownership.sas` -- cross-type variable list for md8, IN vs IN: filter, sentinel-aware coalesce pattern
- `qc/src_counts.txt` -- authoritative row counts per source (md1=14,778; md2=14,778; md3=41,150; md4=7,695; md5=7,695; md6=9,462; md7=9,215; md8=22,473)
- STATE.md -- locked decisions (PCM-T-01, PCM-T-02, PCM-R-02, PCM-D-06), forced-char numeric list for md8, NULL sentinel scope

### Secondary (MEDIUM confidence)
- SAS 9.4 DATA step documentation (training knowledge): LENGTH before SET order dependency, RENAME= dataset option, INPUT() informat behavior, DROP statement, ARRAY _CHARACTER_
- `docs/DECISIONS.md` -- PCM-D-06 resolved as drop; confirms PRECEDE_Study_ID_1 scope

### Tertiary (LOW confidence)
- None -- all critical patterns are grounded in Phase 1-2 established code or project-documented facts

---

## Metadata

**Confidence breakdown:**
- Standard stack (INPUT, LENGTH, DROP, FILE/PUT): HIGH -- SAS 9.4 base features, same patterns used in Phases 1-2
- md8 anomaly inventory (forced-char list, NULL sentinel scope): HIGH -- from STATE.md established decisions and Phase 2 cross-type variable table
- Architecture (8-program structure, section layout): HIGH -- follows Phase 1-2 structure exactly
- Pitfalls: HIGH -- drawn from Phases 1-2 validated pitfall inventories plus md8-specific known issues
- Character variable width list per source: LOW -- not yet captured from PROC CONTENTS; Wave 0 must generate this before LENGTH blocks can be written
- `g` library path: LOW -- not defined in any existing program; planner must confirm

**Research date:** 2026-08-26
**Valid until:** Stable -- SAS 9.4 patterns do not change; re-research only if source data files change or environment changes
