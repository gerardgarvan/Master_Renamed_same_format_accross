/* Program: 03_prep_md1.sas | Phase 3 | Requirements: PREP-01,PREP-02,PREP-05,PREP-06
   Purpose: Structural prep for master_data_1 (14,778 rows).
            Pre-step exception scan, LENGTH-before-SET copy to g.prep_md1,
            zero-conversion log, and row-count assertion.
   Author : Executor (Phase 3 Plan 03)
   Created: 2026-08-26
   Notes  : md1 has no forced-char numerics and no NULL sentinel (RESEARCH md1-md7 section).
            The exception scan measures both sentinel count and encoding-damage count --
            NEVER writes a hardcoded zero (RESEARCH Pitfall 10).
            LENGTH block widths sourced from qc/03_charvars_all.txt (Wave 0 artifact).
*/
options mprint nofmterr;
%let expected_nobs = 14778;

/* =========================================================================
   SECTION 0: Paths and libnames
   ========================================================================= */
%let source_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross;
%let qc_path     = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc;
%let logs_path   = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs;
%let g_path      = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge;   /* OUTSIDE the repo tree -- RESEARCH Pitfall 9 */
libname src "&source_path" access=readonly;
libname g   "&g_path";

/* =========================================================================
   SECTION 1: Preconditions
   All %abort cancel calls are inside macro definitions (PCM-R-05).
   ========================================================================= */
%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: LIBNAME &lib not assigned.;
    %abort cancel;
  %end;
  %else %put NOTE: LIBNAME &lib resolved.;
%mend check_libname;
%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: &label dir missing: &path;
    %abort cancel;
  %end;
  %else %put NOTE: &label dir found: &path;
%mend check_dir;
%check_libname(lib=src);
%check_libname(lib=g);
%check_dir(path=&qc_path,   label=qc);
%check_dir(path=&logs_path, label=logs);

/* =========================================================================
   SECTION 2: Exception report (PREP-02)
   Two counts, BOTH measured -- never hardcoded (RESEARCH Pitfall 10).
     n_sent : literal 'NULL' sentinel strings in character variables.
              Expected 0 for md1-md7. Nonzero means source was re-exported
              from Excel like md8 -> ABORT.
     n_enc  : encoding-damaged Base_Procedure_1 rows -> FLAG ONLY (PCM-C-01).
   ========================================================================= */
proc sql noprint;
  select count(*) into :n_sent trimmed
  from src.master_data_1
  where strip(upcase(PRECEDE_STUDY_ID))  = 'NULL'
     or strip(upcase(Base_Procedure_1))  = 'NULL'
     /* NOTE: Add every character variable from qc/03_charvars_all.txt
        for MASTER_DATA_1 here. The above covers the two universally-known
        character variables; the full list is produced by 03_prep_setup.sas
        (Wave 0). Expand this WHERE clause before production use.          */
     ;

  select count(*) into :n_enc trimmed
  from src.master_data_1
  where not missing(Base_Procedure_1)
    and verify(Base_Procedure_1,
               ' !"#$%&' || "'" ||
               '()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~') > 0;
quit;

filename excf "&qc_path.\03_exceptions_md1.txt";
data _null_;
  file excf;
  put "md1 Exception Report -- Run: %sysfunc(datetime(), datetime20.)";
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
%assert_zero(n=&n_sent, msg=NULL sentinel strings in md1 (source may have been re-exported));
%put NOTE: PREP-02 md1 -- &n_enc encoding-damaged rows flagged (no abort, PCM-C-01).;

/* =========================================================================
   SECTION 3: LENGTH-before-SET copy to g.prep_md1 (PREP-05, PCM-R-02)
   LENGTH block declared BEFORE set statement -- widths from qc/03_charvars_all.txt.
   PRECEDE_STUDY_ID $12 confirmed from Phase 1 SRC-06 assertion.
   All other widths sourced from the MASTER_DATA_1 rows of qc/03_charvars_all.txt
   produced by 03_prep_setup.sas (Wave 0). Expand this LENGTH block with the
   full character variable list before production use.
   ========================================================================= */
data g.prep_md1;
  length
    PRECEDE_STUDY_ID    $12
    Base_Procedure_1    $200
    /* INSERT all remaining character variables for MASTER_DATA_1 here,
       with widths from qc/03_charvars_all.txt (MASTER_DATA_1 rows).
       Example format:
         Variable_Name   $<width>
       Do NOT omit any character variable -- a missing declaration allows
       SAS to infer width from the first observation (truncation risk,
       RESEARCH Pitfall 1).                                               */
    ;
  set src.master_data_1;
run;

/* =========================================================================
   SECTION 4: Conversion log (PREP-06)
   Zero conversions expected -- md1 has no forced-char numerics.
   ========================================================================= */
proc sql noprint;
  select count(*) into :n_total trimmed from g.prep_md1;
quit;
filename cl "&logs_path.\03_conversions_md1.txt";
data _null_;
  file cl;
  put "md1 Conversion Count Log -- Run: %sysfunc(datetime(), datetime20.)";
  put "Total rows: &n_total";
  put "Type conversions performed: 0 (md1 has no forced-char numerics)";
  put "NULL sentinels found (asserted zero pre-copy): &n_sent";
  put "Encoding-damaged rows flagged: &n_enc";
run;
filename cl clear;

/* =========================================================================
   SECTION 5: Row-count assertion
   ========================================================================= */
proc sql noprint;
  select count(*) into :n_prep trimmed from g.prep_md1;
quit;
%macro assert_row_count(actual=, expected=, src=);
  %if &actual ne &expected %then %do;
    %put ERROR: PREP row count mismatch for &src -- expected &expected got &actual;
    %abort cancel;
  %end;
  %else %put NOTE: OK -- &src row count &actual matches expected &expected;
%mend assert_row_count;
%assert_row_count(actual=&n_prep, expected=&expected_nobs, src=md1);
%put NOTE: ==== Phase 3 prep md1 complete ====;
