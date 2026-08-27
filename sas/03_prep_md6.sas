/*==========================================================================
  Program : 03_prep_md6.sas
  Phase   : Phase 3 -- Per-Source Normalization
  Purpose : Structural prep for master_data_6 with PREP-04 duplicate drop.
            PRECEDE_Study_ID_1 is proven identical to PRECEDE_STUDY_ID
            BEFORE the data step (not merely asserted absent afterwards).
            Exception scan (NULL sentinel abort; encoding damage flag-only),
            LENGTH-before-SET copy to g.prep_md6, PREP-07 Base_Procedure_Code_1
            NUM->CHAR $10 conversion, DROP of PRECEDE_Study_ID_1, zero-
            conversion log, row-count assertion, column-absence assertion.
  Requirements addressed:
            PREP-01 (independently runnable)
            PREP-02 (exception report to qc/ before data step)
            PREP-04 (PRECEDE_Study_ID_1 proven identical, then dropped,
                     then absence asserted via dictionary.columns)
            PREP-05 (LENGTH before SET for every character variable)
            PREP-06 (conversion log to logs/)
            PREP-07 (Base_Procedure_Code_1 harmonized to CHAR $10)
  Source row count (frozen, qc/src_counts.txt): md6 = 9,462
  Character variable widths: from qc/03_charvars_all.txt MASTER_DATA_6 rows
                             (written by 03_prep_setup.sas / Plan 03-01).
                             Note: PRECEDE_Study_ID_1 appears in that file
                             but must NOT be declared in the LENGTH block
                             because it is dropped in the DATA step.
  Author  : Executor (Phase 3 Plan 04)
  Created : 2026-08-26
==========================================================================*/

options mprint nofmterr;
%let expected_nobs = 9462;
%let mdnum = 6;


/*==========================================================================
  SECTION 0: Paths and libnames
  Canonical paths -- copy verbatim from 03_prep_setup.sas.
  g library MUST be outside the repo tree (RESEARCH Pitfall 9 / PCM-C-04).
==========================================================================*/

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
libname src "&source_path" access=readonly;
libname g   "&g_path";


/*==========================================================================
  SECTION 1: Preconditions
  %abort cancel is ONLY valid inside a %macro definition (PCM-R-05).
==========================================================================*/

%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: LIBNAME &lib not assigned. Check C:\Master_Renamed_same_format_accross is accessible.;
    %abort cancel;
  %end;
  %else %put NOTE: LIBNAME &lib resolved.;
%mend check_libname;

%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: &label directory not found: &path;
    %abort cancel;
  %end;
  %else %put NOTE: &label directory found: &path;
%mend check_dir;

%check_libname(lib=src);
%check_libname(lib=g);
%check_dir(path=&qc_path,   label=qc);
%check_dir(path=&logs_path, label=logs);


/*==========================================================================
  SECTION 2: Exception report (PREP-02)
  Two counts, both measured -- never hardcode zero (RESEARCH Pitfall 10).
    n_sent : literal NULL sentinel strings in character variables.
             Expected 0 for md6 (only md8 has them). Nonzero -> ABORT.
    n_enc  : encoding-damaged Base_Procedure_1 rows -> FLAG ONLY (PCM-C-01).
  Note: Base_Procedure_Code_1 is NUM in md6 -- not in the NULL scan.
        PRECEDE_Study_ID_1 is CHAR -- included in the sentinel scan.
  Exception report written to qc/ BEFORE the data step (PREP-02).
==========================================================================*/

proc sql noprint;
  select count(*) into :n_sent trimmed
  from src.master_data_6
  where strip(upcase(PRECEDE_STUDY_ID)) = 'NULL'
     or strip(upcase(PRECEDE_Study_ID_1)) = 'NULL'
     or strip(upcase(ENCRYPTED_MRN)) = 'NULL'
     or strip(upcase(ENCRYPTED_ENCOUNTER)) = 'NULL'
     or strip(upcase(Day_of_Week__CHAR_)) = 'NULL'
     or strip(upcase(Holidays)) = 'NULL'
     or strip(upcase(Race)) = 'NULL'
     or strip(upcase(Ethnicity)) = 'NULL'
     or strip(upcase(Sex)) = 'NULL'
     or strip(upcase(Marital_Status)) = 'NULL'
     or strip(upcase(EmployeeStatus)) = 'NULL'
     or strip(upcase(Service)) = 'NULL'
     or strip(upcase(Room_Type)) = 'NULL'
     or strip(upcase(Emergent)) = 'NULL'
     or strip(upcase(Base_Procedure_1)) = 'NULL'
     or strip(upcase(CPT_1)) = 'NULL'
     or strip(upcase(CPT_1_Description)) = 'NULL'
     or strip(upcase(CPT1_Label)) = 'NULL'
     or strip(upcase(Patient_Type)) = 'NULL'
     or strip(upcase(Payer)) = 'NULL'
     or strip(upcase(ICD10_Principal_Diagnosis)) = 'NULL'
     or strip(upcase(ICD10_Principal_Diagnosis_POA)) = 'NULL'
     or strip(upcase(IsDead_Y_N)) = 'NULL'
     or strip(upcase(SSDI_Death_Y_N)) = 'NULL'
     or strip(upcase(Admit_Source)) = 'NULL'
     or strip(upcase(Dischg_Disposition)) = 'NULL'
     or strip(upcase(Anesthesia_Type)) = 'NULL'
     or strip(upcase(Preop_block)) = 'NULL'
     or strip(upcase(Intraop_Ketamine)) = 'NULL'
     or strip(upcase(Cognitive_Category)) = 'NULL'
     or strip(upcase(Frailty_Category)) = 'NULL'
     or strip(upcase(Feels_Exausted)) = 'NULL'
     or strip(upcase(Low_Physical_Activity)) = 'NULL'
     or strip(upcase(Slow_Walking_Speed)) = 'NULL'
     or strip(upcase(Unintended_Weight_Loss)) = 'NULL'
     or strip(upcase(Week_Grip_Strength)) = 'NULL'
     /* Base_Procedure_Code_1 is NUM in md6 -- excluded */
  ;

  select count(*) into :n_enc trimmed
  from src.master_data_6
  where not missing(Base_Procedure_1)
    and verify(Base_Procedure_1,
        ' !"#$%&' || "'" ||
        '()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~') > 0;
quit;

filename excf "&qc_path.\03_exceptions_md6.txt";
data _null_;
  file excf;
  put "md6 Exception Report -- Run: %sysfunc(datetime(), datetime20.)";
  put "NULL sentinel strings in character variables (abort if nonzero): &n_sent";
  put "Encoding-damaged Base_Procedure_1 rows (flag only, PCM-C-01): &n_enc";
run;
filename excf clear;

%macro assert_zero(n=, msg=);
  %if &n > 0 %then %do;
    %put ERROR: PREP-02 VIOLATION -- &n &msg;
    %abort cancel;
  %end;
  %else %put NOTE: PREP-02 OK -- 0 &msg;
%mend assert_zero;

%assert_zero(n=&n_sent, msg=NULL sentinel strings in md6 (source may have been re-exported));
%put NOTE: PREP-02 md6 -- &n_enc encoding-damaged rows flagged in Base_Procedure_1 (no abort, PCM-C-01).;


/*==========================================================================
  SECTION 2b: PREP-04 -- Prove PRECEDE_Study_ID_1 identical to PRECEDE_STUDY_ID
  BEFORE the DATA step drops it. PCM-D-06 is recorded as resolved on the
  claim that the columns are identical in every row. That claim may never
  have been executed. Prove it here: if they differ anywhere, the column is
  NOT a true duplicate and dropping it would destroy information.
  This check MUST precede the DATA step (identity proof before DROP).
==========================================================================*/

proc sql noprint;
  select count(*) into :n_keydiff trimmed
  from src.master_data_6
  where PRECEDE_STUDY_ID ne PRECEDE_Study_ID_1;
quit;

%macro assert_dup_identical;
  %if &n_keydiff > 0 %then %do;
    %put ERROR: PREP-04 VIOLATION -- PRECEDE_Study_ID_1 differs from PRECEDE_STUDY_ID in &n_keydiff rows.;
    %put ERROR- It is NOT a duplicate. Dropping it would destroy data. Re-open PCM-D-06.;
    %abort cancel;
  %end;
  %else %do;
    /* Two %put statements, not one. A %PUT ends at its FIRST semicolon, so an
       embedded ; left "safe to drop.;" as an orphan statement and logged
       ERROR 180-322 on every run. NOTE- continues the previous NOTE block.   */
    %put NOTE: PREP-04 OK -- PRECEDE_Study_ID_1 identical to PRECEDE_STUDY_ID in all rows.;
    %put NOTE- Safe to drop.;
  %end;
%mend assert_dup_identical;
%assert_dup_identical;


/*==========================================================================
  SECTION 3: LENGTH-before-SET copy to g.prep_md6 with PREP-07 conversion
             and PREP-04 drop.
  Base_Procedure_Code_1 is NUM 8 in md6; harmonize to CHAR $10 (PREP-07).
  PRECEDE_Study_ID_1 is dropped (PREP-04 / PCM-D-06): proven identical above.
  CRITICAL: Do NOT declare PRECEDE_Study_ID_1 in the LENGTH block. Declaring
  a variable in LENGTH re-creates it as a zero-width slot; the DROP removes it,
  but the declaration itself is misleading. Leave it out entirely.
  LENGTH block MUST precede the SET statement (PREP-05 / PCM-R-02).
  Widths from qc/03_charvars_all.txt MASTER_DATA_6 rows (produced by
  03_prep_setup.sas). DO NOT GUESS widths; over-declaring is harmless,
  under-declaring truncates.
==========================================================================*/

data g.prep_md6;
  length
    PRECEDE_STUDY_ID               $12
    Base_Procedure_Code_1          $10   /* PREP-07: NUM in source, CHAR $10 target */
    ENCRYPTED_MRN                  $36
    ENCRYPTED_ENCOUNTER            $46
    Day_of_Week__CHAR_             $3
    Holidays                       $1
    Race                           $15
    Ethnicity                      $15
    Sex                            $6
    Marital_Status                 $22
    EmployeeStatus                 $19
    Service                        $32
    Room_Type                      $22
    Emergent                       $1
    Base_Procedure_1               $199
    CPT_1                          $6
    CPT_1_Description              $75
    CPT1_Label                     $96
    Patient_Type                   $18
    Payer                          $12
    ICD10_Principal_Diagnosis      $7
    ICD10_Principal_Diagnosis_POA  $6
    IsDead_Y_N                     $1
    SSDI_Death_Y_N                 $1
    Admit_Source                   $40
    Dischg_Disposition             $28
    Anesthesia_Type                $33
    Preop_block                    $1
    Intraop_Ketamine               $1
    Cognitive_Category             $22
    Frailty_Category               $24
    Feels_Exausted                 $1
    Low_Physical_Activity          $1
    Slow_Walking_Speed             $1
    Unintended_Weight_Loss         $1
    Week_Grip_Strength             $1
    /* PRECEDE_Study_ID_1 intentionally omitted -- dropped (PREP-04/PCM-D-06) */
    ;
  set src.master_data_6 (rename=(Base_Procedure_Code_1=_bpc_n));
  if not missing(_bpc_n) then Base_Procedure_Code_1 = strip(put(_bpc_n, best12.));
  drop _bpc_n;
  drop PRECEDE_Study_ID_1;   /* PREP-04 / PCM-D-06: duplicate, proven identical above */

  /* PREP-08: a negative elapsed time is invalid at any threshold. Set to missing.
     Evidence: AMENDMENT-01 section 2 (PCM-F-13, PCM-F-14). 52 rows in
     rt_INCISE_to_DRESS_mins and 15 in rt_RM_START_to_INCISION_mins, disjoint sets.
     Max negative is -1 and 75% sit between -6.5 and -1 -- consistent with the two
     timestamps being charted out of order, concentrated in percutaneous services
     (EP/interventional cardiology, 46% neurosurgery) where there is no incision or
     dressing in the surgical sense. Missing is more honest there than a number.
     IS NOT MISSING guard is mandatory (PCM-T-11): missing < 0 is TRUE in SAS.        */
  if not missing(rt_INCISE_to_DRESS_mins)
     and rt_INCISE_to_DRESS_mins < 0      then rt_INCISE_to_DRESS_mins = .;
  if not missing(rt_RM_START_to_INCISION_mins)
     and rt_RM_START_to_INCISION_mins < 0 then rt_RM_START_to_INCISION_mins = .;
  if not missing(rt_RM_START_to_RM_END_mins)
     and rt_RM_START_to_RM_END_mins < 0   then rt_RM_START_to_RM_END_mins = .;
run;


/*==========================================================================
  SECTION 4: Conversion log (PREP-06)
  Base_Procedure_Code_1 NUM->CHAR conversion count logged.
  Conversion log goes to logs/ (not qc/ -- different directories: PREP-06
  vs PREP-02).
==========================================================================*/

proc sql noprint;
  select count(*)               into :n_total   trimmed from g.prep_md6;
  select count(Base_Procedure_Code_1)
                                into :n_bpc_conv trimmed from g.prep_md6
    where not missing(Base_Procedure_Code_1);
quit;

filename cl "&logs_path.\03_conversions_md6.txt";
data _null_;
  file cl;
  put "md6 Conversion Count Log -- Run: %sysfunc(datetime(), datetime20.)";
  put "Total rows in g.prep_md6: &n_total";
  put "Base_Procedure_Code_1 NUM->CHAR $10 (PREP-07) -- non-missing converted: &n_bpc_conv";
  put "PRECEDE_Study_ID_1 dropped (PREP-04 / PCM-D-06): proven identical before drop";
  put "NULL sentinels found (asserted zero pre-copy): &n_sent";
  put "Encoding-damaged rows flagged (no abort, PCM-C-01): &n_enc";
run;
filename cl clear;


/*==========================================================================
  SECTION 5: Post-copy assertions

  5a: Row count (all sources -- frozen count from qc/src_counts.txt).
      expected_nobs set once at top; assertion reads &expected_nobs
      (RESEARCH Pitfall 4 -- never hardcode expected count in the call).
==========================================================================*/

proc sql noprint;
  select count(*) into :n_prep trimmed from g.prep_md6;
quit;

%macro assert_row_count(actual=, expected=, src=);
  %if &actual ne &expected %then %do;
    %put ERROR: PREP row count mismatch for &src -- expected &expected got &actual;
    %abort cancel;
  %end;
  %else %put NOTE: OK -- &src row count &actual matches expected &expected;
%mend assert_row_count;

%assert_row_count(actual=&n_prep, expected=&expected_nobs, src=md6);

/*  5b: PREP-04 absence assertion -- PRECEDE_Study_ID_1 must NOT appear in
    g.prep_md6 after the DROP. dictionary.columns is the authoritative check.
    dictionary.columns type is CHARACTER (char/num).                      */

proc sql noprint;
  select count(*) into :n_dup_col trimmed
  from dictionary.columns
  where libname='G' and memname='PREP_MD6'
    and upcase(name)='PRECEDE_STUDY_ID_1';
quit;

%macro assert_col_absent(n=, colname=, dsn=);
  %if &n > 0 %then %do;
    %put ERROR: PREP-04 VIOLATION -- &colname still present in &dsn after DROP;
    %abort cancel;
  %end;
  %else %put NOTE: PREP-04 OK -- &colname absent from &dsn;
%mend assert_col_absent;

%assert_col_absent(n=&n_dup_col, colname=PRECEDE_Study_ID_1, dsn=g.prep_md6);

/*  5c: PREP-07 type assertion -- Base_Procedure_Code_1 must be CHAR in g.prep_md6.
    dictionary.columns type is CHARACTER (char/num), distinct from PROC CONTENTS
    OUT= where type is numeric 1=NUM / 2=CHAR. Do not interchange them.          */

proc sql noprint;
  select count(*) into :n_bpc_num trimmed
  from dictionary.columns
  where libname='G' and memname="PREP_MD&mdnum"
    and upcase(name)='BASE_PROCEDURE_CODE_1'
    and type='num';
quit;

%macro assert_bpc_char(n=, dsn=);
  %if &n > 0 %then %do;
    %put ERROR: PREP-07 VIOLATION -- Base_Procedure_Code_1 is still NUMERIC in &dsn;
    %put ERROR- Phase 4 would face a cross-source type conflict on this column.;
    %abort cancel;
  %end;
  %else %put NOTE: PREP-07 OK -- Base_Procedure_Code_1 is CHARACTER in &dsn;
%mend assert_bpc_char;

%assert_bpc_char(n=&n_bpc_num, dsn=g.prep_md6);

/* SECTION 5d: PREP-08 assertion -- no negative operative intervals survive.
   IS NOT MISSING guard required (PCM-T-11): missing < 0 is TRUE in SAS.   */
proc sql noprint;
  select sum( (rt_INCISE_to_DRESS_mins is not missing and rt_INCISE_to_DRESS_mins < 0)
            + (rt_RM_START_to_INCISION_mins is not missing and rt_RM_START_to_INCISION_mins < 0)
            + (rt_RM_START_to_RM_END_mins is not missing and rt_RM_START_to_RM_END_mins < 0) )
         into :n_negsurv trimmed
  from g.prep_md6;
quit;
%macro assert_no_negtime(n=, dsn=);
  %if &n > 0 %then %do;
    %put ERROR: PREP-08 VIOLATION -- &n negative operative intervals survived in &dsn;
    %abort cancel;
  %end;
  %else %put NOTE: PREP-08 OK -- no negative operative intervals in &dsn;
%mend assert_no_negtime;
%assert_no_negtime(n=&n_negsurv, dsn=g.prep_md6);

/* SECTION 5e: PREP-09 -- report-only negative scan of every rt_* numeric variable.
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


/*==========================================================================
  Close-out
==========================================================================*/

%put NOTE: ==== Phase 3 prep md6 complete -- PRECEDE_Study_ID_1 dropped ====;
