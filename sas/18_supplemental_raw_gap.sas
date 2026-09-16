/*==========================================================================
  Program : 18_supplemental_raw_gap.sas
  Purpose : Two-section diagnostic for supplemental raw source files.

            Section A: 2022 ID mismatch diagnostic.
              Imports r9 (char $12) and r7 (numeric) read-only, builds
              one-column key datasets on a derived _k = strip(cats(key)),
              performs anti-joins (base vs r9) and writes
              qc\18_id_diagnostic.txt with 5-ID samples from each side,
              best32. rendering of r7 numeric IDs, and four
              length-frequency tables. PCM-D-16 remains OPEN -- no cast
              or fix is applied here.

            Section B: gap-fill counts per column per matched-ID file
              (plan 02).

            Section C: PCM-D-15 approval gate (plan 02).

  Reads   : g.analysis_base                                (read-only)
             &raw_path\All_YEARS_LAT_LONG_20231127.csv     (r9, read-only)
             &raw_path\2022_Education_20240124.csv          (r7, read-only)
             (Section B adds r1, r2, r3, r4, r5, r6)

  Writes  : qc\18_id_diagnostic.txt   (Section A, runtime output)
             qc\18_gap_candidates.txt  (Section B, plan 02)
             logs\18_supplemental_raw_gap.log  (when in_pipeline = 0)

  Rules   : One abort-cancel in this program, inside fail_out only.
             Section A never aborts -- it writes the diagnostic and continues.
             The D15 gate in Section C is the only gate that may abort.
             g.analysis_base and all raw files are read-only.

  Created : 2026-09-16 (Phase 18, plan 01)
  Requirements: RAW-08, RAW-12
==========================================================================*/

/* =========================================================================
   SECTION 0: Config include + options + shared macros
   ========================================================================= */

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
options validvarname=v7 validmemname=extend nofmterr msglevel=i;
%include "&sas_path.\macros_raw_import.sas";

/* =========================================================================
   SECTION 1: Macro library
   (Do NOT define %import_csv or %import_xlsx here -- they are in the shared include above)
   ========================================================================= */

/* ---- Log routing ------------------------------------------------------- */
%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\18_supplemental_raw_gap.log" new; run;
  %end;
%mend route_log;

%macro restore_log;
  %if &in_pipeline = 0 %then %do;
    proc printto; run;
  %end;
%mend restore_log;

/* ---- fail_out: the only macro that may call abort ---------------------- */
%macro fail_out(msg=);
  %put ERROR: &msg;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;

/* ---- check_dir: verify a directory exists before use ------------------ */
%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %fail_out(msg=&label directory not found: &path);
  %end;
%mend check_dir;

/* ---- assert_base: verify g.analysis_base is reachable via dictionary -- */
%let n_tab_base = 0;
proc sql noprint;
  select count(*) into :n_tab_base trimmed
  from dictionary.tables where libname='G' and memname='ANALYSIS_BASE';
quit;

%macro assert_base;
  %if &n_tab_base ne 1 %then %do;
    %fail_out(msg=g.analysis_base not found in g library);
  %end;
%mend assert_base;

/* =========================================================================
   SECTION 2: Preconditions (run before any work, in order)
   ========================================================================= */

/* logs first, before the log is routed */
%check_dir(path=&logs_path, label=logs);
%route_log;

libname g "&g_path";

%check_dir(path=&qc_path, label=qc);
%check_dir(path=&raw_path, label=raw);

/* Re-query n_tab_base now that libname g is assigned */
%let n_tab_base = 0;
proc sql noprint;
  select count(*) into :n_tab_base trimmed
  from dictionary.tables where libname='G' and memname='ANALYSIS_BASE';
quit;
%assert_base;

%put NOTE: ==== Phase 18 supplemental raw gap diagnostic starting ====;

/* =========================================================================
   SECTION A: 2022 ID diagnostic -- Task 3
   ========================================================================= */

/* A-1  Import r9 and r7 read-only */
%import_csv(r9, All_YEARS_LAT_LONG_20231127.csv)
%import_csv(r7, 2022_Education_20240124.csv)

/* A-2  Build one-column key datasets on a derived character key _k
        so the same merge block works for char $12, char $18 and numeric keys */

data work.base_ids;
  set g.analysis_base(keep=PRECEDE_STUDY_ID);
  length _k $32;
  _k = strip(cats(PRECEDE_STUDY_ID));
  id_length = length(_k);
  if _k ne '';
  keep _k id_length;
run;

data work.r9_ids;
  set work.r9(keep=PRECEDE_Study_ID);
  length _k $32;
  _k = strip(cats(PRECEDE_Study_ID));
  id_length = length(_k);
  if _k ne '';
  keep _k id_length;
run;

data work.r7_ids;
  set work.r7(keep=PRECEDE_Study_ID);
  length _k $32 id_best32 $32;
  _k       = strip(cats(PRECEDE_Study_ID));
  id_best32 = strip(put(PRECEDE_Study_ID, best32.));   /* full precision rendering */
  id_length = length(id_best32);
  if _k ne '';
  keep _k id_best32 id_length;
run;

proc sort data=work.base_ids nodupkey; by _k; run;
proc sort data=work.r9_ids   nodupkey; by _k; run;
proc sort data=work.r7_ids   nodupkey; by _k; run;

/* A-3  Anti-joins on _k */
data work.base_not_in_r9  /* in base, not in r9 */
     work.r9_not_in_base  /* in r9, not in base */
     work.matched_ids;    /* in both -- reference set */
  merge work.base_ids(in=inb) work.r9_ids(in=inr);
  by _k;
  if inb and not inr then output work.base_not_in_r9;
  else if inr and not inb then output work.r9_not_in_base;
  else if inb and inr then output work.matched_ids;
run;

/* A-4  Sample sets: first 5 rows of each non-matching group */
data work.samp_base_not_r9;
  set work.base_not_in_r9(obs=5);
run;

data work.samp_r9_not_base;
  set work.r9_not_in_base(obs=5);
run;

data work.samp_r7;
  set work.r7_ids(obs=5);
run;

/* A-5  PROC FREQ on id_length for all four sets */
proc freq data=work.base_not_in_r9 noprint;
  tables id_length / out=work.freq_base_not_r9(keep=id_length count percent);
run;

proc freq data=work.r9_not_in_base noprint;
  tables id_length / out=work.freq_r9_not_base(keep=id_length count percent);
run;

proc freq data=work.r7_ids noprint;
  tables id_length / out=work.freq_r7(keep=id_length count percent);
run;

proc freq data=work.matched_ids noprint;
  tables id_length / out=work.freq_matched(keep=id_length count percent);
run;

/* Gather counts for the header */
%let n_base     = 0;
%let n_r9       = 0;
%let n_r7       = 0;
%let n_matched  = 0;
%let n_base_only = 0;
%let n_r9_only   = 0;

proc sql noprint;
  select count(*) into :n_base     trimmed from work.base_ids;
  select count(*) into :n_r9       trimmed from work.r9_ids;
  select count(*) into :n_r7       trimmed from work.r7_ids;
  select count(*) into :n_matched  trimmed from work.matched_ids;
  select count(*) into :n_base_only trimmed from work.base_not_in_r9;
  select count(*) into :n_r9_only   trimmed from work.r9_not_in_base;
quit;

/* A-6  Write qc\18_id_diagnostic.txt */
data _null_;
  file "&qc_path.\18_id_diagnostic.txt" lrecl=200;

  /* Header */
  put "==========================================================================";
  put "Phase 18 -- 2022 Cohort ID Mismatch Diagnostic";
  put "==========================================================================";
  put " ";
  put "Mismatch: 2022 cohort (r7 numeric, r9 char $12 for all years)";
  put " ";
  put "Base N (g.analysis_base PRECEDE_STUDY_ID unique): &n_base";
  put "r9 N (All_YEARS_LAT_LONG_20231127.csv unique):    &n_r9";
  put "r7 N (2022_Education_20240124.csv unique):        &n_r7";
  put "Matched (base AND r9 on _k):                      &n_matched";
  put "Base-only (in base NOT in r9):                    &n_base_only";
  put "r9-only (in r9 NOT in base):                      &n_r9_only";
  put " ";
  put "Note: _k = strip(cats(key)) applied to all sources.";
  put "      r7 key is NUMERIC; id_best32 = strip(put(PRECEDE_Study_ID, best32.))";
  put " ";
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;

  put "--------------------------------------------------------------------------";
  put "5 BASE IDs NOT IN r9 (value=_k, id_length=length of _k)";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.samp_base_not_r9;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put _k @35 id_length;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "--------------------------------------------------------------------------";
  put "5 r9 IDs NOT IN BASE (value=_k, id_length=length of _k)";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.samp_r9_not_base;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put _k @35 id_length;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "--------------------------------------------------------------------------";
  put "5 r7 IDs (numeric, rendered with best32.) -- id_best32 + id_length";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.samp_r7;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put id_best32 @35 id_length;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "--------------------------------------------------------------------------";
  put "LENGTH DISTRIBUTION -- base IDs not in r9";
  put "id_length  count  percent";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.freq_base_not_r9;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put id_length @11 count @20 percent 8.2;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "--------------------------------------------------------------------------";
  put "LENGTH DISTRIBUTION -- r9 IDs not in base";
  put "id_length  count  percent";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.freq_r9_not_base;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put id_length @11 count @20 percent 8.2;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "--------------------------------------------------------------------------";
  put "LENGTH DISTRIBUTION -- r7 IDs (numeric key rendered best32.)";
  put "id_length  count  percent";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.freq_r7;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put id_length @11 count @20 percent 8.2;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "--------------------------------------------------------------------------";
  put "LENGTH DISTRIBUTION -- matched IDs (reference -- expected all length 12)";
  put "id_length  count  percent";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.freq_matched;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put id_length @11 count @20 percent 8.2;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "==========================================================================";
  put "PCM-D-16 remains open -- no cast or fix applied by this program";
  put "==========================================================================";
run;

%put NOTE: Section A complete -- qc\18_id_diagnostic.txt written;

/* SECTION B: gap counts -- plan 02 */

/* SECTION C: D15 gate -- plan 02 */

%restore_log;
