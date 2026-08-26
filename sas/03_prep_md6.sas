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

%let source_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross;
%let qc_path     = C:\Master_Renamed_same_format_accross\qc;
%let logs_path   = C:\Master_Renamed_same_format_accross\logs;
%let g_path      = C:\PeCAN_work\data;   /* OUTSIDE the repo tree */
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


/*==========================================================================
  SECTION 2: Exception report (PREP-02)
  Two counts, both measured -- never hardcode zero (RESEARCH Pitfall 10).
    n_sent : literal 'NULL' sentinel strings in character variables.
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
     or strip(upcase(Base_Procedure_1)) = 'NULL'
     /* Add further character variables from qc/03_charvars_all.txt
        MASTER_DATA_6 rows here -- one OR clause per variable.
        Do NOT include Base_Procedure_Code_1 (it is NUM in md6). */
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
  %else %put NOTE: PREP-04 OK -- PRECEDE_Study_ID_1 identical to PRECEDE_STUDY_ID in all rows; safe to drop.;
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
    PRECEDE_STUDY_ID       $12
    Base_Procedure_Code_1  $10    /* PREP-07: NUM in source, CHAR $10 target */
    Base_Procedure_1       $200   /* confirm width from qc/03_charvars_all.txt */
    /* ----------------------------------------------------------------
       ADD every remaining CHAR variable for MASTER_DATA_6 here,
       EXCEPT PRECEDE_Study_ID_1 (it is being dropped).
       With widths from qc/03_charvars_all.txt MASTER_DATA_6 rows.
       Example format:
         VariableName  $<width>
       Widths from PROC CONTENTS via 03_prep_setup.sas.
    ---------------------------------------------------------------- */
    ;
  set src.master_data_6 (rename=(Base_Procedure_Code_1=_bpc_n));
  if not missing(_bpc_n) then Base_Procedure_Code_1 = strip(put(_bpc_n, best12.));
  drop _bpc_n;
  drop PRECEDE_Study_ID_1;   /* PREP-04 / PCM-D-06: duplicate, proven identical above */
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
    dictionary.columns type is CHARACTER ('char'/'num').                      */

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

%assert_bpc_char(n=&n_bpc_num, dsn=g.prep_md6);


/*==========================================================================
  Close-out
==========================================================================*/

%put NOTE: ==== Phase 3 prep md6 complete -- PRECEDE_Study_ID_1 dropped ====;
