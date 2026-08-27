/*==========================================================================
  Program : 03_prep_md7.sas
  Phase   : Phase 3 -- Per-Source Normalization
  Purpose : Structural prep for master_data_7.
            Exception scan (NULL sentinel abort; encoding damage flag-only),
            LENGTH-before-SET copy to g.prep_md7, PREP-07 Base_Procedure_Code_1
            NUM->CHAR $10 conversion, zero-conversion log, row-count assertion.
  Requirements addressed:
            PREP-01 (independently runnable)
            PREP-02 (exception report to qc/ before data step)
            PREP-05 (LENGTH before SET for every character variable)
            PREP-06 (conversion log to logs/)
            PREP-07 (Base_Procedure_Code_1 harmonized to CHAR $10; md7 is the
                     last of the four numeric-coded sources -- md4/md5/md6/md7)
  Source row count (frozen, qc/src_counts.txt): md7 = 9,215
  Character variable widths: from qc/03_charvars_all.txt MASTER_DATA_7 rows
                             (written by 03_prep_setup.sas / Plan 03-01)
  Key lineage note: md7 was originally NUM8, destroyed by PCM-T-01, and
                    rebuilt. PRECEDE_STUDY_ID is Char 12. Gated in Phase 1
                    SRC-06. Noted here for traceability (PCM-D lineage).
  Author  : Executor (Phase 3 Plan 05)
  Created : 2026-08-26
==========================================================================*/

options mprint nofmterr;
%let expected_nobs = 9215;
%let mdnum = 7;


/*==========================================================================
  SECTION 0: Paths and libnames
  Canonical paths -- copy verbatim from 03_prep_setup.sas.
  g library MUST be outside the repo tree (RESEARCH Pitfall 9 / PCM-C-04).
==========================================================================*/

%let source_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross;
%let qc_path     = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc;
%let logs_path   = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs;
%let g_path      = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge;   /* OUTSIDE the repo tree */
libname src "&source_path" access=readonly;
libname g   "&g_path";


/*==========================================================================
  SECTION 1: Preconditions
  %abort cancel is ONLY valid inside a %macro definition (PCM-R-05).
==========================================================================*/

%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: LIBNAME &lib not assigned. Check P: drive availability.;
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

/* Key-lineage note: md7 was originally NUM8, destroyed by PCM-T-01, and
   rebuilt from the source system. PRECEDE_STUDY_ID is Char 12 (already
   gated in Phase 1 SRC-06; re-noted here for phase-3 traceability).    */
/* Split into two %put statements: a %PUT ends at its FIRST semicolon, so the
   embedded ';' after "rebuilt" left the remainder as an orphan statement and
   logged ERROR 180-322 on every run.                                          */
%put NOTE: md7 lineage -- originally NUM8, destroyed by PCM-T-01, rebuilt.;
%put NOTE- PRECEDE_STUDY_ID is Char 12 (gated in Phase 1 SRC-06).;


/*==========================================================================
  SECTION 2: Exception report (PREP-02)
  Two counts, both measured -- never hardcode zero (RESEARCH Pitfall 10).
    n_sent : literal 'NULL' sentinel strings in character variables.
             Expected 0 for md7 (only md8 has them). Nonzero -> ABORT.
    n_enc  : encoding-damaged Base_Procedure_1 rows -> FLAG ONLY (PCM-C-01).
  Note: Base_Procedure_Code_1 is NUM in md7 -- not included in NULL scan.
  Exception report written to qc/ BEFORE the data step (PREP-02).
==========================================================================*/

proc sql noprint;
  select count(*) into :n_sent trimmed
  from src.master_data_7
  where strip(upcase(PRECEDE_STUDY_ID))        = 'NULL'
     or strip(upcase(ENCRYPTED_MRN))           = 'NULL'
     or strip(upcase(ENCRYPTED_ENCOUNTER))     = 'NULL'
     or strip(upcase(Day_of_Week__CHAR_))      = 'NULL'
     or strip(upcase(Holidays))                = 'NULL'
     or strip(upcase(Race))                    = 'NULL'
     or strip(upcase(Ethnicity))               = 'NULL'
     or strip(upcase(Sex))                     = 'NULL'
     or strip(upcase(Marital_Status))          = 'NULL'
     or strip(upcase(EmployeeStatus))          = 'NULL'
     or strip(upcase(Service))                 = 'NULL'
     or strip(upcase(Room_Type))               = 'NULL'
     or strip(upcase(Emergent))                = 'NULL'
     or strip(upcase(Base_Procedure_1))        = 'NULL'
     or strip(upcase(CPT_1))                   = 'NULL'
     or strip(upcase(CPT_1_Description))       = 'NULL'
     or strip(upcase(CPT1_Label))              = 'NULL'
     or strip(upcase(Patient_Type))            = 'NULL'
     or strip(upcase(Payer))                   = 'NULL'
     or strip(upcase(ICD10_Principal_Diagnosis))     = 'NULL'
     or strip(upcase(ICD10_Principal_Diagnosis_POA)) = 'NULL'
     or strip(upcase(Death))                   = 'NULL'
     or strip(upcase(SSDI_Death))              = 'NULL'
     or strip(upcase(Admit_Source))            = 'NULL'
     or strip(upcase(Anesthesia_Type))         = 'NULL'
     or strip(upcase(Dischg_Disposition))      = 'NULL'
     or strip(upcase(Intraop_Ketamine))        = 'NULL'
     or strip(upcase(Preop_block))             = 'NULL'
     or strip(upcase(Cognitive_Category))      = 'NULL'
     or strip(upcase(Frailty_Category))        = 'NULL'
     or strip(upcase(Feels_Exausted))          = 'NULL'
     or strip(upcase(Low_Physical_Activity))   = 'NULL'
     or strip(upcase(Slow_Walking_Speed))      = 'NULL'
     or strip(upcase(Unintended_Weight_Loss))  = 'NULL'
     or strip(upcase(Week_Grip_Strength))      = 'NULL'
  ;

  select count(*) into :n_enc trimmed
  from src.master_data_7
  where not missing(Base_Procedure_1)
    and verify(Base_Procedure_1,
        ' !"#$%&' || "'" ||
        '()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~') > 0;
quit;

filename excf "&qc_path.\03_exceptions_md7.txt";
data _null_;
  file excf;
  put "md7 Exception Report -- Run: %sysfunc(datetime(), datetime20.)";
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

%assert_zero(n=&n_sent, msg=NULL sentinel strings in md7 (source may have been re-exported));
%put NOTE: PREP-02 md7 -- &n_enc encoding-damaged rows flagged in Base_Procedure_1 (no abort, PCM-C-01).;


/*==========================================================================
  SECTION 3: LENGTH-before-SET copy to g.prep_md7 with PREP-07 conversion.
  Base_Procedure_Code_1 is NUM 8 in md7; harmonize to CHAR $10 (PREP-07).
  md7 is the LAST of the four numeric-coded sources (md4, md5, md6, md7).
  After this step all eight sources agree: Base_Procedure_Code_1 is CHAR $10.
  Rename incoming numeric to _bpc_n to avoid PDV collision, convert via
  strip(put(..., best12.)), drop the temp. Never use input() toward numeric
  (destroys leading zeros / alpha codes).
  LENGTH block MUST precede the SET statement (PREP-05 / PCM-R-02).
  Widths from qc/03_charvars_all.txt MASTER_DATA_7 rows (produced by
  03_prep_setup.sas). DO NOT GUESS widths.
  Do NOT list Base_Procedure_Code_1 as $10 AND keep the numeric rename --
  the $10 target is declared in LENGTH; the numeric source arrives renamed.
==========================================================================*/

data g.prep_md7;
  length
    PRECEDE_STUDY_ID               $12
    Base_Procedure_Code_1          $10   /* PREP-07: NUM in source, CHAR $10 target */
    ENCRYPTED_MRN                  $36
    ENCRYPTED_ENCOUNTER            $44
    Day_of_Week__CHAR_             $3
    Holidays                       $1
    Race                           $15
    Ethnicity                      $15
    Sex                            $6
    Marital_Status                 $22
    EmployeeStatus                 $23
    Service                        $32
    Room_Type                      $22
    Emergent                       $1
    Base_Procedure_1               $199
    CPT_1                          $6
    CPT_1_Description              $70
    CPT1_Label                     $96
    Patient_Type                   $18
    Payer                          $12
    ICD10_Principal_Diagnosis      $7
    ICD10_Principal_Diagnosis_POA  $6
    Death                          $1
    SSDI_Death                     $1
    Admit_Source                   $28
    Anesthesia_Type                $33
    Dischg_Disposition             $38
    Intraop_Ketamine               $1
    Preop_block                    $1
    Cognitive_Category             $22
    Frailty_Category               $24
    Feels_Exausted                 $3
    Low_Physical_Activity          $3
    Slow_Walking_Speed             $3
    Unintended_Weight_Loss         $3
    Week_Grip_Strength             $3
    ;
  set src.master_data_7 (rename=(Base_Procedure_Code_1=_bpc_n));
  if not missing(_bpc_n) then Base_Procedure_Code_1 = strip(put(_bpc_n, best12.));
  drop _bpc_n;

  /* PREP-08: a negative elapsed time is invalid at any threshold. Set to missing.
     Evidence: AMENDMENT-01 section 2 (PCM-F-13, PCM-F-14). 52 rows in
     rt_INCISE_to_DRESS_mins and 15 in rt_RM_START_to_INCISION_mins, disjoint sets.
     Max negative is -1 and 75% sit between -6.5 and -1 -- consistent with the two
     timestamps being charted out of order, concentrated in percutaneous services
     (EP/interventional cardiology, 46% neurosurgery) where there is no incision or
     dressing in the surgical sense. Missing is more honest there than a number.
     IS NOT MISSING guard is mandatory (PCM-T-11): missing < 0 is TRUE in SAS.        */
  if rt_INCISE_to_DRESS_mins is not missing
     and rt_INCISE_to_DRESS_mins < 0      then rt_INCISE_to_DRESS_mins = .;
  if rt_RM_START_to_INCISION_mins is not missing
     and rt_RM_START_to_INCISION_mins < 0 then rt_RM_START_to_INCISION_mins = .;
  if rt_RM_START_to_RM_END_mins is not missing
     and rt_RM_START_to_RM_END_mins < 0   then rt_RM_START_to_RM_END_mins = .;
run;


/*==========================================================================
  SECTION 4: Conversion log (PREP-06)
  Zero type conversions expected beyond Base_Procedure_Code_1 NUM->CHAR;
  log the count of non-missing conversions as evidence the step ran.
  Conversion log goes to logs/ (not qc/ -- different directories: PREP-06
  vs PREP-02).
==========================================================================*/

proc sql noprint;
  select count(*)               into :n_total   trimmed from g.prep_md7;
  select count(Base_Procedure_Code_1)
                                into :n_bpc_conv trimmed from g.prep_md7
    where not missing(Base_Procedure_Code_1);
quit;

filename cl "&logs_path.\03_conversions_md7.txt";
data _null_;
  file cl;
  put "md7 Conversion Count Log -- Run: %sysfunc(datetime(), datetime20.)";
  put "Total rows in g.prep_md7: &n_total";
  put "Base_Procedure_Code_1 NUM->CHAR $10 (PREP-07) -- non-missing converted: &n_bpc_conv";
  put "NULL sentinels found (asserted zero pre-copy): &n_sent";
  put "Encoding-damaged rows flagged (no abort, PCM-C-01): &n_enc";
  put "Key lineage: md7 was originally NUM8, destroyed by PCM-T-01, rebuilt; PRECEDE_STUDY_ID Char 12.";
run;
filename cl clear;


/*==========================================================================
  SECTION 5: Post-copy assertions

  5a: Row count (all sources -- frozen count from qc/src_counts.txt).
      expected_nobs set once at top; assertion reads &expected_nobs
      (RESEARCH Pitfall 4 -- never hardcode expected count in the call).
==========================================================================*/

proc sql noprint;
  select count(*) into :n_prep trimmed from g.prep_md7;
quit;

%macro assert_row_count(actual=, expected=, src=);
  %if &actual ne &expected %then %do;
    %put ERROR: PREP row count mismatch for &src -- expected &expected got &actual;
    %abort cancel;
  %end;
  %else %put NOTE: OK -- &src row count &actual matches expected &expected;
%mend assert_row_count;

%assert_row_count(actual=&n_prep, expected=&expected_nobs, src=md7);

/*  5c: PREP-07 type assertion -- Base_Procedure_Code_1 must be CHAR in g.prep_md7.
    dictionary.columns type is CHARACTER ('char'/'num'), distinct from PROC CONTENTS
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

%assert_bpc_char(n=&n_bpc_num, dsn=g.prep_md7);

/* SECTION 5d: PREP-08 assertion -- no negative operative intervals survive.
   IS NOT MISSING guard required (PCM-T-11): missing < 0 is TRUE in SAS.   */
proc sql noprint;
  select sum( (rt_INCISE_to_DRESS_mins is not missing and rt_INCISE_to_DRESS_mins < 0)
            + (rt_RM_START_to_INCISION_mins is not missing and rt_RM_START_to_INCISION_mins < 0)
            + (rt_RM_START_to_RM_END_mins is not missing and rt_RM_START_to_RM_END_mins < 0) )
         into :n_negsurv trimmed
  from g.prep_md7;
quit;
%macro assert_no_negtime(n=, dsn=);
  %if &n > 0 %then %do;
    %put ERROR: PREP-08 VIOLATION -- &n negative operative intervals survived in &dsn;
    %abort cancel;
  %end;
  %else %put NOTE: PREP-08 OK -- no negative operative intervals in &dsn;
%mend assert_no_negtime;
%assert_no_negtime(n=&n_negsurv, dsn=g.prep_md7);

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

%put NOTE: ==== Phase 3 prep md7 complete ====;
