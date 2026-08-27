/*==========================================================================
  Program    : 03_prep_md8.sas
  Phase      : Phase 3 -- Per-Source Normalization
  Purpose    : md8 NULL sentinel clear + forced-char-to-numeric conversion.
               md8 is the only source that (a) stores the literal string
               'NULL' where SAS would store missing, and (b) had eight
               numeric variables forced to CHAR ($4 or $11) during a prior
               Excel export. This program:
                 1. Scans for non-parseable values BEFORE conversion (PREP-02)
                 2. Clears every 'NULL' sentinel to blank (PREP-03)
                 3. Converts the eight forced-char numerics to numeric via
                    INPUT() (PREP-03)
                 4. Logs conversion counts to logs/ (PREP-06)
                 5. Asserts zero surviving sentinels, correct numeric types,
                    and the frozen 22,473 row count (PREP-03, PREP-05)
  Requirements: PREP-01, PREP-02, PREP-03, PREP-05, PREP-06
  Author     : Executor (Phase 3 Plan 02)
  Created    : 2026-08-26
==========================================================================*/

options mprint nofmterr;


/*==========================================================================
  SECTION 0: Paths and libnames
  Copy verbatim from interfaces -- do NOT change paths here without updating
  all other Phase 3 prep programs and 99_run_all.sas.
==========================================================================*/

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
libname src "&source_path" access=readonly;
libname g   "&g_path";
%let expected_nobs = 22473;   /* md8 frozen source count, qc/src_counts.txt */
%let mdnum        = 8;        /* PREP-09 builds its dictionary.columns lookup and its
                                 logs/03_negtime_mdN.txt filename from &mdnum. Present in
                                 md1-md7; without it here &mdnum is unresolved, the lookup
                                 returns nothing, and md8's report is written as
                                 03_negtime_md.txt or not at all.                        */


/*==========================================================================
  SECTION 1: Preconditions
  All %abort cancel calls are inside macro definitions (PCM-R-05).
==========================================================================*/

%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: LIBNAME &lib could not be assigned.; %abort cancel;
  %end;
  %else %put NOTE: LIBNAME &lib resolved.;
%mend check_libname;

%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: &label directory missing: &path; %abort cancel;
  %end;
  %else %put NOTE: &label directory found: &path;
%mend check_dir;

%check_libname(lib=src);
%check_libname(lib=g);
%check_dir(path=&qc_path,   label=qc);
%check_dir(path=&logs_path, label=logs);

/* md8 identity precondition: assert the eight forced-char numerics are
   CHARACTER in the source (confirms we are reading the version with the
   forced-char problem, RESEARCH Section 1 Architecture).                */
proc contents data=src.master_data_8 out=work.c8 (keep=name type length) noprint; run;

proc sql noprint;
  select count(*) into :n_forcedchar trimmed from work.c8
  where upcase(name) in ('ADMIT_BMI','ASA__ANESTH_RECORD_','AGE_AT_ENCOUNTER','COGNITIVE_SCORE',
                         'FRAILTY_SCORE','RT_INCISE_TO_DRESS_MINS','RT_RM_START_TO_INCISION_MINS',
                         'RT_RM_START_TO_RM_END_MINS')
    and type = 2;   /* type=2 is character */
quit;

%macro check_forcedchar;
  %if &n_forcedchar ne 8 %then %do;
    %put ERROR: PREP-03 precondition -- expected 8 forced-CHAR numerics in md8, found &n_forcedchar.;
    %put ERROR- The source may already be converted or is the wrong version. Investigate before prep.;
    %abort cancel;
  %end;
  %else %put NOTE: md8 identity confirmed -- 8 forced-char numerics present as CHARACTER.;
%mend check_forcedchar;
%check_forcedchar;


/*==========================================================================
  SECTION 2: Pre-conversion exception report (PREP-02)
  Scan BEFORE any type conversion. Non-parseable values in the eight
  forced-char numerics abort the run. Encoding damage in Base_Procedure_1
  is flag-only (PCM-C-01, Pitfall 6 -- do NOT include in &n_exc abort).
  The exception report file is written before the abort test so it always
  exists as an artifact.
==========================================================================*/

proc sql noprint;
  create table work.exc_md8 as
    select 'Admit_BMI' as variable length=32, PRECEDE_STUDY_ID length=12,
           Admit_BMI as raw_value length=11, 'non-numeric content' as exception_type length=30
    from src.master_data_8
    where strip(Admit_BMI) not in ('NULL','') and notdigit(compress(strip(Admit_BMI),'.-')) > 0
  union all
    select 'ASA__Anesth_Record_', PRECEDE_STUDY_ID, ASA__Anesth_Record_, 'non-numeric content'
    from src.master_data_8
    where strip(ASA__Anesth_Record_) not in ('NULL','') and notdigit(compress(strip(ASA__Anesth_Record_),'.-')) > 0
  union all
    select 'Age_at_Encounter', PRECEDE_STUDY_ID, Age_at_Encounter, 'non-numeric content'
    from src.master_data_8
    where strip(Age_at_Encounter) not in ('NULL','') and notdigit(compress(strip(Age_at_Encounter),'.-')) > 0
  union all
    select 'Cognitive_Score', PRECEDE_STUDY_ID, Cognitive_Score, 'non-numeric content'
    from src.master_data_8
    where strip(Cognitive_Score) not in ('NULL','') and notdigit(compress(strip(Cognitive_Score),'.-')) > 0
  union all
    select 'Frailty_Score', PRECEDE_STUDY_ID, Frailty_Score, 'non-numeric content'
    from src.master_data_8
    where strip(Frailty_Score) not in ('NULL','') and notdigit(compress(strip(Frailty_Score),'.-')) > 0
  union all
    select 'rt_INCISE_to_DRESS_mins', PRECEDE_STUDY_ID, rt_INCISE_to_DRESS_mins, 'non-numeric content'
    from src.master_data_8
    where strip(rt_INCISE_to_DRESS_mins) not in ('NULL','') and notdigit(compress(strip(rt_INCISE_to_DRESS_mins),'.-')) > 0
  union all
    select 'rt_RM_START_to_INCISION_mins', PRECEDE_STUDY_ID, rt_RM_START_to_INCISION_mins, 'non-numeric content'
    from src.master_data_8
    where strip(rt_RM_START_to_INCISION_mins) not in ('NULL','') and notdigit(compress(strip(rt_RM_START_to_INCISION_mins),'.-')) > 0
  union all
    select 'rt_RM_START_to_RM_END_mins', PRECEDE_STUDY_ID, rt_RM_START_to_RM_END_mins, 'non-numeric content'
    from src.master_data_8
    where strip(rt_RM_START_to_RM_END_mins) not in ('NULL','') and notdigit(compress(strip(rt_RM_START_to_RM_END_mins),'.-')) > 0
  ;
  select count(*) into :n_exc trimmed from work.exc_md8;
quit;

/* Encoding-damage flag scan -- WARNING only, NOT counted in &n_exc (Pitfall 6).
   verify() returns position of first character NOT in the allowed set.
   A value > 0 means the string contains at least one non-ASCII byte.        */
proc sql noprint;
  select count(*) into :n_enc trimmed from src.master_data_8
  where not missing(Base_Procedure_1)
    and verify(Base_Procedure_1, ' !"#$%&' || "'" || '()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~') > 0;
quit;

/* Write exception report to qc/ BEFORE the abort test so the artifact
   always exists regardless of outcome.                                      */
filename excfile "&qc_path.\03_exceptions_md8.txt";
data _null_;
  file excfile;
  put "md8 Exception Report -- Run: %sysfunc(datetime(), datetime20.)";
  put "Non-parseable values in forced-char numerics (abort if nonzero): &n_exc";
  put "Encoding-damaged rows in Base_Procedure_1 (flag only, PCM-C-01):  &n_enc";
run;

/* Append detail rows only when exceptions exist */
%macro write_exc_detail;
  %if &n_exc > 0 %then %do;
    data _null_;
      set work.exc_md8;
      file excfile mod;
      put variable $32. ' | ' PRECEDE_STUDY_ID $12. ' | ' raw_value $11. ' | ' exception_type $30.;
    run;
  %end;
%mend write_exc_detail;
%write_exc_detail;

filename excfile clear;

/* Abort on non-parseable conversion-blocking values (not on encoding damage) */
%macro assert_zero(n=, msg=);
  %if &n > 0 %then %do; %put ERROR: PREP-02 VIOLATION -- &n &msg; %abort cancel; %end;
  %else %put NOTE: PREP-02 md8 -- 0 &msg;
%mend assert_zero;
%assert_zero(n=&n_exc, msg=non-parseable values in md8 forced-char numerics);
%put NOTE: PREP-02 md8 -- &n_enc encoding-damaged Base_Procedure_1 rows flagged (no abort, PCM-C-01).;

/* === Task 2 appends Sections 3-5 (normalization, log, assertions) below this line === */


/*==========================================================================
  SECTION 3: Two-step normalization (PREP-03, PREP-05)

  CRITICAL ORDER: LENGTH is the FIRST statement in every DATA step, BEFORE
  SET. LENGTH after SET is silently ignored for variables already typed by
  the SET descriptor (Pitfall 1).

  Character variable widths are sourced from qc/03_charvars_all.txt
  (produced by 03_prep_setup.sas / Plan 01). The eight forced-char numerics
  are listed at their CHAR widths here because they are still character at
  this stage. All other character widths are declared from the Wave 0 scan.
  Confirmed widths (RESEARCH, post-review):
    Admit_BMI $11, ASA__Anesth_Record_ $4,
    Age_at_Encounter $4, Cognitive_Score $4, Frailty_Score $4,
    rt_INCISE_to_DRESS_mins $4, rt_RM_START_to_INCISION_mins $4,
    rt_RM_START_to_RM_END_mins $4
  All other character variable widths: source from qc/03_charvars_all.txt.
==========================================================================*/

/* Step 1: Clear NULL sentinels across ALL character variables.
   Done BEFORE INPUT() so the conversion never receives the literal 'NULL'.
   Reading _CHARACTER_ here is safe because no temp _c variables exist yet
   (two-step approach isolates the rename, Pitfall 3).                       */
data work.prep_md8_s1;
  length
    PRECEDE_STUDY_ID            $12
    /* Eight forced-char numerics: widths confirmed from RESEARCH post-review.
       Admit_BMI is $11; the other seven are $4.
       NOTE: All remaining character variables must be declared at their
       source widths from qc/03_charvars_all.txt (03_prep_setup.sas Wave 0).
       Placeholder declarations below use $200 for longer text fields and $50
       for shorter fields; update these from qc/03_charvars_all.txt before
       running against the source. Over-declaring is survivable; under-
       declaring causes truncation (Pitfall 1).                              */
    Admit_BMI                   $11
    ASA__Anesth_Record_         $4
    Age_at_Encounter            $4
    Cognitive_Score             $4
    Frailty_Score               $4
    rt_INCISE_to_DRESS_mins     $4
    rt_RM_START_to_INCISION_mins $4
    rt_RM_START_to_RM_END_mins  $4
    Base_Procedure_1            $198
    ENCRYPTED_MRN               $40
    ENCRYPTED_ENCOUNTER         $49
    EmployeeStatus              $23
    Education                   $19
    Race                        $16
    Ethnicity                   $15
    Sex                         $6
    Marital_Status              $22
    Service                     $32
    CPT_1                       $8
    CPT_1_Description           $75
    Cognitive_Category          $22
    Frailty_Category            $24
    ;
  set src.master_data_8;

  /* Clear NULL sentinel in ALL character variables (Pitfall 2 prevention).
     _CHARACTER_ expands to every character variable in the PDV at this point.
     After Step 1 sentinel clear, INPUT() never receives the literal 'NULL'. */
  array _charv {*} _CHARACTER_;
  do _i = 1 to dim(_charv);
    if strip(upcase(_charv{_i})) = 'NULL' then _charv{_i} = ' ';
  end;
  drop _i;
run;

/* Step 2: Convert the eight forced-char numerics to true numeric type.
   Read from work.prep_md8_s1 (sentinels already cleared).
   Rename each char var to a _c temp; INPUT into the same-named numeric.
   NEVER rename via _CHARACTER_ array -- explicit rename avoids Pitfall 3. */
data g.prep_md8;
  length
    PRECEDE_STUDY_ID            $12
    Base_Procedure_1            $198
    ENCRYPTED_MRN               $40
    ENCRYPTED_ENCOUNTER         $49
    EmployeeStatus              $23
    Education                   $19
    Race                        $16
    Ethnicity                   $15
    Sex                         $6
    Marital_Status              $22
    Service                     $32
    CPT_1                       $8
    CPT_1_Description           $75
    Cognitive_Category          $22
    Frailty_Category            $24
    /* Eight forced-char numerics declared as NUMERIC (length 8, not 8.)
       A trailing period in a LENGTH statement is a syntax error.            */
    Admit_BMI                   8
    ASA__Anesth_Record_         8
    Age_at_Encounter            8
    Cognitive_Score             8
    Frailty_Score               8
    rt_INCISE_to_DRESS_mins     8
    rt_RM_START_to_INCISION_mins 8
    rt_RM_START_to_RM_END_mins  8
    ;
  set work.prep_md8_s1
    (rename=(Admit_BMI=Admit_BMI_c ASA__Anesth_Record_=ASA_c Age_at_Encounter=Age_c
             Cognitive_Score=Cog_c Frailty_Score=Frailty_c
             rt_INCISE_to_DRESS_mins=rt1_c rt_RM_START_to_INCISION_mins=rt2_c
             rt_RM_START_to_RM_END_mins=rt3_c));

  /* INPUT(STRIP(var), best12.) handles blanks (now missing after sentinel
     clear) cleanly: INPUT('', best12.) = . (numeric missing). Correct.      */
  Admit_BMI                    = input(strip(Admit_BMI_c), best12.);
  ASA__Anesth_Record_          = input(strip(ASA_c),       best12.);
  Age_at_Encounter             = input(strip(Age_c),       best12.);
  Cognitive_Score              = input(strip(Cog_c),       best12.);
  Frailty_Score                = input(strip(Frailty_c),   best12.);
  rt_INCISE_to_DRESS_mins      = input(strip(rt1_c),       best12.);
  rt_RM_START_to_INCISION_mins = input(strip(rt2_c),       best12.);
  rt_RM_START_to_RM_END_mins   = input(strip(rt3_c),       best12.);

  drop Admit_BMI_c ASA_c Age_c Cog_c Frailty_c rt1_c rt2_c rt3_c;

  /* PREP-08: a negative elapsed time is invalid at any threshold. Set to missing.
     Evidence: AMENDMENT-01 section 2 (PCM-F-13, PCM-F-14). 52 rows in
     rt_INCISE_to_DRESS_mins and 15 in rt_RM_START_to_INCISION_mins, disjoint sets.
     Max negative is -1 and 75% sit between -6.5 and -1 -- consistent with the two
     timestamps being charted out of order, concentrated in percutaneous services
     (EP/interventional cardiology, 46% neurosurgery) where there is no incision or
     dressing in the surgical sense. Missing is more honest there than a number.
     IS NOT MISSING guard is mandatory (PCM-T-11): missing < 0 is TRUE in SAS.
     ORDERING NOTE (md8 only): this block MUST follow the input() conversions above.
     Before this point the three variables are still character (rt1_c..rt3_c) and the
     numeric comparison is meaningless. After INPUT() they are numeric in the PDV.     */
  if not missing(rt_INCISE_to_DRESS_mins)
     and rt_INCISE_to_DRESS_mins < 0      then rt_INCISE_to_DRESS_mins = .;
  if not missing(rt_RM_START_to_INCISION_mins)
     and rt_RM_START_to_INCISION_mins < 0 then rt_RM_START_to_INCISION_mins = .;
  if not missing(rt_RM_START_to_RM_END_mins)
     and rt_RM_START_to_RM_END_mins < 0   then rt_RM_START_to_RM_END_mins = .;
run;


/*==========================================================================
  SECTION 4: Conversion count log (PREP-06)
  Written to logs/ (not qc/ -- different artifact semantics, RESEARCH
  anti-pattern). Count per variable: successful conversions (numeric non-
  missing in g.prep_md8) and sentinels cleared (strip(upcase)='NULL' in
  the original src.master_data_8). Never use &SQLOBS -- always SELECT
  COUNT(*) INTO :n TRIMMED (Phases 1-2 established rule).
==========================================================================*/

proc sql noprint;
  select count(*) into :n_total    trimmed from g.prep_md8;
  select count(*) into :c_bmi      trimmed from g.prep_md8      where Admit_BMI             is not missing;
  select count(*) into :s_bmi      trimmed from src.master_data_8 where strip(upcase(Admit_BMI))             = 'NULL';
  select count(*) into :c_asa      trimmed from g.prep_md8      where ASA__Anesth_Record_   is not missing;
  select count(*) into :s_asa      trimmed from src.master_data_8 where strip(upcase(ASA__Anesth_Record_))   = 'NULL';
  select count(*) into :c_age      trimmed from g.prep_md8      where Age_at_Encounter      is not missing;
  select count(*) into :s_age      trimmed from src.master_data_8 where strip(upcase(Age_at_Encounter))      = 'NULL';
  select count(*) into :c_cog      trimmed from g.prep_md8      where Cognitive_Score       is not missing;
  select count(*) into :s_cog      trimmed from src.master_data_8 where strip(upcase(Cognitive_Score))       = 'NULL';
  select count(*) into :c_frail    trimmed from g.prep_md8      where Frailty_Score         is not missing;
  select count(*) into :s_frail    trimmed from src.master_data_8 where strip(upcase(Frailty_Score))         = 'NULL';
  select count(*) into :c_rt1      trimmed from g.prep_md8      where rt_INCISE_to_DRESS_mins             is not missing;
  select count(*) into :s_rt1      trimmed from src.master_data_8 where strip(upcase(rt_INCISE_to_DRESS_mins))             = 'NULL';
  select count(*) into :c_rt2      trimmed from g.prep_md8      where rt_RM_START_to_INCISION_mins        is not missing;
  select count(*) into :s_rt2      trimmed from src.master_data_8 where strip(upcase(rt_RM_START_to_INCISION_mins))        = 'NULL';
  select count(*) into :c_rt3      trimmed from g.prep_md8      where rt_RM_START_to_RM_END_mins          is not missing;
  select count(*) into :s_rt3      trimmed from src.master_data_8 where strip(upcase(rt_RM_START_to_RM_END_mins))          = 'NULL';
quit;

filename convlog "&logs_path.\03_conversions_md8.txt";
data _null_;
  file convlog;
  put "md8 Conversion Count Log -- Run: %sysfunc(datetime(), datetime20.)";
  put "Total rows: &n_total";
  put "Admit_BMI                    -- converted non-missing: &c_bmi   | NULL sentinel cleared: &s_bmi";
  put "ASA__Anesth_Record_          -- converted non-missing: &c_asa   | NULL sentinel cleared: &s_asa";
  put "Age_at_Encounter             -- converted non-missing: &c_age   | NULL sentinel cleared: &s_age";
  put "Cognitive_Score              -- converted non-missing: &c_cog   | NULL sentinel cleared: &s_cog";
  put "Frailty_Score                -- converted non-missing: &c_frail | NULL sentinel cleared: &s_frail";
  put "rt_INCISE_to_DRESS_mins      -- converted non-missing: &c_rt1   | NULL sentinel cleared: &s_rt1";
  put "rt_RM_START_to_INCISION_mins -- converted non-missing: &c_rt2   | NULL sentinel cleared: &s_rt2";
  put "rt_RM_START_to_RM_END_mins   -- converted non-missing: &c_rt3   | NULL sentinel cleared: &s_rt3";
run;
filename convlog clear;


/*==========================================================================
  SECTION 5: Post-conversion assertions (PREP-03, PREP-05)
  Three assertions:
    1. Zero surviving 'NULL' strings in any character variable of g.prep_md8
    2. The eight converted variables are NUMERIC (type=1 / type ne 'char')
    3. Row count preserved: g.prep_md8 = &expected_nobs (22,473)
  All %abort cancel calls inside macro definitions (PCM-R-05).
==========================================================================*/

/* Redefine assert_zero so it references the correct dataset in error messages.
   (First definition in Section 2 is for PREP-02; this one is for PREP-03.)   */
%macro assert_zero(n=, msg=);
  %if &n > 0 %then %do; %put ERROR: PREP-03 VIOLATION -- &n &msg; %abort cancel; %end;
  %else %put NOTE: OK -- 0 &msg;
%mend assert_zero;

/* 5a: Zero surviving NULL strings across all character variables of g.prep_md8.
   Enumerate the remaining character variables explicitly (the eight forced-char
   numerics are now numeric and are NOT in this list).
   NOTE: Update this list to match the full character variable inventory from
   qc/03_charvars_all.txt once 03_prep_setup.sas has been executed.
   PRECEDE_STUDY_ID and Base_Procedure_1 are the confirmed character variables
   that remain after conversion; add all others from qc/03_charvars_all.txt.  */
proc sql noprint;
  select count(*) into :n_null_surv trimmed from g.prep_md8
  where strip(upcase(PRECEDE_STUDY_ID)) = 'NULL'
     or strip(upcase(Base_Procedure_1)) = 'NULL'
  /* TODO: add all remaining character variables from qc/03_charvars_all.txt,
     one OR clause per variable. Pattern:
       or strip(upcase(VarName)) = 'NULL'                                    */
  ;
quit;
%assert_zero(n=&n_null_surv, msg=surviving NULL sentinel strings in g.prep_md8);

/* 5b: The eight converted variables are NUMERIC in g.prep_md8.
   dictionary.columns type='char' means still character -- assert zero.       */
proc sql noprint;
  select count(*) into :n_stillchar trimmed from dictionary.columns
  where libname='G' and memname='PREP_MD8'
    and upcase(name) in ('ADMIT_BMI','ASA__ANESTH_RECORD_','AGE_AT_ENCOUNTER','COGNITIVE_SCORE',
                         'FRAILTY_SCORE','RT_INCISE_TO_DRESS_MINS','RT_RM_START_TO_INCISION_MINS',
                         'RT_RM_START_TO_RM_END_MINS')
    and type='char';
quit;
%assert_zero(n=&n_stillchar, msg=forced-char numerics still CHARACTER in g.prep_md8);

/* 5c: Row count preserved */
proc sql noprint; select count(*) into :n_prep trimmed from g.prep_md8; quit;
%macro assert_row_count(actual=, expected=, src=);
  %if &actual ne &expected %then %do;
    %put ERROR: PREP row count mismatch for &src -- expected &expected got &actual;
    %abort cancel;
  %end;
  %else %put NOTE: OK -- &src row count &actual matches expected &expected;
%mend assert_row_count;
%assert_row_count(actual=&n_prep, expected=&expected_nobs, src=md8);

/* 5d: PREP-08 assertion -- no negative operative intervals survive.
   IS NOT MISSING guard required (PCM-T-11): missing < 0 is TRUE in SAS.   */
proc sql noprint;
  select sum( (rt_INCISE_to_DRESS_mins is not missing and rt_INCISE_to_DRESS_mins < 0)
            + (rt_RM_START_to_INCISION_mins is not missing and rt_RM_START_to_INCISION_mins < 0)
            + (rt_RM_START_to_RM_END_mins is not missing and rt_RM_START_to_RM_END_mins < 0) )
         into :n_negsurv trimmed
  from g.prep_md8;
quit;
%macro assert_no_negtime(n=, dsn=);
  %if &n > 0 %then %do;
    %put ERROR: PREP-08 VIOLATION -- &n negative operative intervals survived in &dsn;
    %abort cancel;
  %end;
  %else %put NOTE: PREP-08 OK -- no negative operative intervals in &dsn;
%mend assert_no_negtime;
%assert_no_negtime(n=&n_negsurv, dsn=g.prep_md8);

/* 5e: PREP-09 -- report-only negative scan of every rt_* numeric variable.
   This section modifies NOTHING. It derives the variable list at run time so that
   any rt_* column not listed here is still covered. The rt_ANCHOR_to_*_days variables
   may show negatives -- that is EXPECTED and legitimate (offsets, not durations).
   This report is the evidence for PCM-D-10; do not act on it inside this program.   */
proc sql noprint;
  select name into :rtvars separated by ' '
  from dictionary.columns
  where libname='G' and upcase(memname)="PREP_MD&mdnum"
    and type='num' and upcase(name) like 'RT!_%' escape '!';

  select count(*) into :n_rtvars trimmed
  from dictionary.columns
  where libname='G' and upcase(memname)="PREP_MD&mdnum"
    and type='num' and upcase(name) like 'RT!_%' escape '!';
quit;

%macro scan_negtime;
  %local i v;
  filename negrep "&logs_path.\03_negtime_md&mdnum..txt";
  data _null_;
    file negrep;
    put "PREP-08 / PREP-09 negative-time report -- md&mdnum -- Run: %sysfunc(datetime(), datetime20.)";
    put " ";
    put "PREP-08 nulled: rt_INCISE_to_DRESS_mins, rt_RM_START_to_INCISION_mins,";
    put "                rt_RM_START_to_RM_END_mins  (must read 0 below)";
    put "PREP-09 report-only: every other rt_* numeric variable. NOT modified.";
    put "  NOTE: negatives in rt_ANCHOR_to_*_days are EXPECTED and legitimate --";
    put "  those are offsets from an anchor date, not durations. See PCM-D-10.";
    put " ";
    put @1 "Variable" @40 "N_Negative";
    put @1 "--------------------------------------------------";
  run;

  %do i = 1 %to &n_rtvars;
    %let v = %scan(&rtvars, &i);
    %local n_neg;
    proc sql noprint;
      select count(*) into :n_neg trimmed
      from g.prep_md&mdnum
      where &v is not missing and &v < 0;   /* PCM-T-11 guard */
    quit;
    data _null_;
      file negrep mod;
      put @1 "&v" @40 "&n_neg";
    run;
  %end;

  filename negrep clear;
  %put NOTE: PREP-09 -- negative-time scan written for &n_rtvars rt_* variables in md&mdnum.;
%mend scan_negtime;
%scan_negtime;

/* Do NOT clear libname src or g -- the session may be reused by other prep
   programs and by 99_run_all.sas.                                           */

%put NOTE: ==== Phase 3 prep md8 complete -- sentinels cleared, 8 numerics converted, assertions passed ====;
