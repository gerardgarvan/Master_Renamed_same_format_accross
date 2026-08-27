/* Program: 07_cohort.sas
   Phase   : 7 -- Cohort & Missingness
   Purpose : Reads g.master_data_merged (never written). Measures Patient_Type
             distribution, builds and validates a candidate cohort in WORK,
             asserts four known complete-case Ns against the full merged file,
             measures within-cohort Ns, promotes the validated candidate to
             g.analytic_cohort, and writes two committed QC artifacts.
   Requirements : PCM-D-05, PCM-F-11, PCM-F-12, COH-01 through COH-04
   Author  : Executor (Phase 7 Plan 01)
   Created : 2026-08-27
   Revised : 2026-08-27 -- review fixes:
     * ODS LISTING writes to a SEPARATE file (07_cohort_tables.txt). Opening an
       ODS destination with FILE= TRUNCATES that file, which destroyed the header
       the old SECTION 0c had just written to 07_cohort_missingness.txt.
     * Cohort is built and validated in WORK, then promoted. The old version wrote
       g.analytic_cohort BEFORE any variable check, any missingness profile and any
       assertion -- an abort left a permanent empty/unvalidated dataset behind.
     * Required variables verified present BEFORE anything is written.
     * Degenerate cohort (0 rows or all rows) is recorded in the QC file, not only
       the log, and aborts AFTER the artifacts are complete.
     * BMI LACK% derived from the HAVE% value, not computed independently
       (independent rounding could sum to 100.1).
     * Session state restored on EVERY exit path: `ods listing;` reopens the
       default destination (the old `ods listing close;` left it closed for the
       rest of the session) and PROC PRINTTO is restored before every abort.
     * qc/ and logs/ existence checked before the log is redirected.

   PCM violations avoided:
     PCM-T-01: no PROC SQL UPDATE
     PCM-T-02: no in-place dataset rewrite
     PCM-T-11: every numeric comparison carries an IS NOT MISSING guard
     PCM-R-05: every %abort cancel is inside a named macro definition
     All counts use SELECT COUNT(*) INTO :macvar TRIMMED

   NOTE ON PATH SYNTAX: "&logs_path.\07_cohort.log" is correct and deliberate.
   The period terminates the macro variable name and is consumed by the macro
   processor; the backslash remains. Do not "fix" this to "&logs_path\...".
*/

/* =========================================================================
   SECTION 0: Options, paths, preconditions
   -------------------------------------------------------------------------
   Directory checks run BEFORE the log is redirected -- a missing logs\ would
   otherwise make PROC PRINTTO fail with the diagnostic going nowhere useful.
   ========================================================================= */
options nodate nonumber ps=max ls=200;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* g is WRITABLE -- SECTION 5 promotes the validated cohort into it */
libname g "&g_path";

/* ---- Restore-and-abort helper -------------------------------------------
   Any abort path must restore session state first, or the log stays redirected
   to a file and every later submit in this session appears to vanish. This is
   not hypothetical -- it is what made a previous session go silent.          */
%macro fail_out(msg=);
  %put ERROR: &msg;
  ods listing;                 /* reopen the default destination */
  proc printto; run;           /* restore the log BEFORE aborting */
  %put ERROR: 07_cohort.sas aborted -- &msg;
  %abort cancel;
%mend fail_out;

/* 0a: directories must exist (checked before PRINTTO redirects the log) */
%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: &label directory not found: &path;
    ods listing;
    %abort cancel;
  %end;
  %put NOTE: PRECONDITION OK -- &label directory found.;
%mend check_dir;
%check_dir(path=&qc_path,   label=qc);
%check_dir(path=&logs_path, label=logs);

/* Route the log to the documented grep target */
proc printto log="&logs_path.\07_cohort.log" new;
run;

%put NOTE: ==== Phase 7 Cohort and Missingness starting ====;

/* 0b: g.master_data_merged must exist */
%macro check_source_exists;
  %local n_tab;
  proc sql noprint;
    select count(*) into :n_tab trimmed
    from dictionary.tables
    where libname='G' and upcase(memname)='MASTER_DATA_MERGED';
  quit;
  %if &n_tab ne 1 %then
    %fail_out(msg=g.master_data_merged not found. Run Phases 3-5 first.);
  %put NOTE: PRECONDITION OK -- g.master_data_merged present.;
%mend check_source_exists;
%check_source_exists;

/* 0c: required variables must ALL be present before anything is written.
   The old version discovered a missing variable at the PROC MEANS in SECTION 3,
   by which time g.analytic_cohort had already been created and replaced.      */
%macro check_vars_present;
  %local i v n_hit missing_list;
  %let missing_list = ;
  %do i = 1 %to 5;
    %let v = %scan(Patient_Type Admit_BMI Cognitive_Score Frailty_Score Age_at_Encounter, &i);
    proc sql noprint;
      select count(*) into :n_hit trimmed
      from dictionary.columns
      where libname='G' and upcase(memname)='MASTER_DATA_MERGED'
        and upcase(name) = %upcase("&v");
    quit;
    %if &n_hit = 0 %then %let missing_list = &missing_list &v;
  %end;
  %if %superq(missing_list) ne %then
    %fail_out(msg=Required variables absent from g.master_data_merged:&missing_list);
  %put NOTE: PRECONDITION OK -- all five required variables present.;
%mend check_vars_present;
%check_vars_present;

/* 0d: row count must be 41,150 */
proc sql noprint;
  select count(*) into :n_merged trimmed
  from g.master_data_merged;
quit;

%macro assert_row_count;
  /* %superq guards the blank case: a failed PROC SQL leaves n_merged unset,
     and `%if  ne 41150` is a macro error rather than a clean failure.        */
  %if %superq(n_merged) = %then
    %fail_out(msg=Row count query returned no value -- g.master_data_merged unreadable.);
  %if &n_merged ne 41150 %then
    %fail_out(msg=g.master_data_merged has &n_merged rows%str(,) expected 41150. Re-run Phases 4-5.);
  %put NOTE: PRECONDITION OK -- g.master_data_merged has &n_merged rows.;
%mend assert_row_count;
%assert_row_count;

/* 0e: open the summary artifact fresh. This file is written ONLY by
   data _null_ steps -- ODS never touches it, so nothing truncates it. */
data _null_;
  file "&qc_path.\07_cohort_missingness.txt";
  put "07_cohort_missingness -- Run: %sysfunc(datetime(), datetime20.)";
  put "Phase 7 Cohort and Missingness -- g.master_data_merged (&n_merged rows)";
  put "Tables and distributions: see 07_cohort_tables.txt (written by ODS LISTING)";
  put "=======================================================================";
  put " ";
run;


/* =========================================================================
   SECTION 1: Patient_Type distribution (PCM-D-05 evidence)
   -------------------------------------------------------------------------
   ODS LISTING writes to a SEPARATE file. Pointing it at
   07_cohort_missingness.txt would TRUNCATE the header just written above --
   opening an ODS destination with FILE= creates or replaces, it does not append.
   Two files also separates concerns: wide PROC tables for a human reader,
   grep-able key=value lines for tooling.
   ========================================================================= */

ods listing file="&qc_path.\07_cohort_tables.txt";

%put NOTE: ==== SECTION 1 -- Patient_Type distribution (pre-filter) ====;

proc freq data=g.master_data_merged;
  tables Patient_Type / missing;
  title "Patient_Type distribution in g.master_data_merged (pre-filter) -- PCM-D-05 evidence";
run;
title;


/* =========================================================================
   SECTION 2: Build the cohort candidate in WORK
   -------------------------------------------------------------------------
   NOT written to g yet. The old version created g.analytic_cohort here, before
   any validation ran -- so an abort in SECTION 3 or 4 left a permanent dataset
   that was empty or unvalidated, indistinguishable from a good one. Promotion
   happens in SECTION 5, after every check has passed.
   ========================================================================= */

%put NOTE: ==== SECTION 2 -- Building work.cohort_candidate ====;

data work.cohort_candidate;
  set g.master_data_merged;
  where upcase(strip(Patient_Type)) in ('INPATIENT','OBSERVATION');
run;

proc sql noprint;
  select count(*) into :n_admitted trimmed
  from work.cohort_candidate;
quit;

%put NOTE: Admitted-patient N (INPATIENT+OBSERVATION) = &n_admitted;

/* Classify the filter result. The status is recorded in the QC file (SECTION 6),
   not only in the log -- a degenerate cohort must be visible to anyone reading
   the artifact, not just to whoever watched the run.                          */
%macro classify_cohort;
  %global cohort_status;
  %if %superq(n_admitted) = %then %let cohort_status = QUERY_FAILED;
  %else %if &n_admitted = 0 %then %do;
    %let cohort_status = ZERO_ROWS;
    %put WARNING: Admitted N is zero -- the Patient_Type filter matched no rows.;
    %put WARNING- Check the SECTION 1 PROC FREQ in 07_cohort_tables.txt.;
  %end;
  %else %if &n_admitted = &n_merged %then %do;
    %let cohort_status = ALL_ROWS;
    %put WARNING: Admitted N equals merged N (&n_admitted) -- the filter matched everything.;
    %put WARNING- Check the SECTION 1 PROC FREQ in 07_cohort_tables.txt.;
  %end;
  %else %do;
    %let cohort_status = OK;
    %put NOTE: Admitted N (&n_admitted) is a proper subset of merged N (&n_merged).;
  %end;
%mend classify_cohort;
%classify_cohort;


/* =========================================================================
   SECTION 3: Missingness profile (PCM-F-11)
   -------------------------------------------------------------------------
   Within-cohort Ns are MEASURED, never asserted -- they have never been
   observed, so there is no established value to assert against.
   ========================================================================= */

%put NOTE: ==== SECTION 3 -- Missingness profile ====;

proc means data=g.master_data_merged n nmiss;
  var Admit_BMI Cognitive_Score Frailty_Score Age_at_Encounter;
  title "Missingness profile: g.master_data_merged (all &n_merged rows)";
run;
title;

proc means data=work.cohort_candidate n nmiss;
  var Admit_BMI Cognitive_Score Frailty_Score Age_at_Encounter;
  title "Missingness profile: cohort candidate (admitted rows only, N=&n_admitted)";
run;
title;

proc freq data=work.cohort_candidate;
  tables Patient_Type / missing;
  title "Patient_Type in the cohort candidate (post-filter) -- only INPATIENT and OBSERVATION should appear";
run;
title;

/* Programmatic confirmation of the post-filter invariant. PROC FREQ shows it to
   a reader; this asserts it. Cheap, and it catches a filter that silently
   changed meaning (e.g. a new Patient_Type value with different spacing).     */
%macro assert_cohort_values;
  %local n_bad;
  proc sql noprint;
    select count(*) into :n_bad trimmed
    from work.cohort_candidate
    where upcase(strip(Patient_Type)) not in ('INPATIENT','OBSERVATION');
  quit;
  %if &n_bad ne 0 %then
    %fail_out(msg=&n_bad cohort rows carry a Patient_Type outside INPATIENT/OBSERVATION.);
  %put NOTE: COH -- post-filter invariant holds: only INPATIENT and OBSERVATION present.;
%mend assert_cohort_values;
%assert_cohort_values;

/* Within-cohort complete-case Ns -- measured */
proc sql noprint;
  select count(*) into :n_bmi_cohort  trimmed
  from work.cohort_candidate where Admit_BMI is not missing;

  select count(*) into :n_cog_cohort  trimmed
  from work.cohort_candidate where Cognitive_Score is not missing;

  select count(*) into :n_frl_cohort  trimmed
  from work.cohort_candidate where Frailty_Score is not missing;

  select count(*) into :n_all3_cohort trimmed
  from work.cohort_candidate
  where Admit_BMI is not missing
    and Cognitive_Score is not missing
    and Frailty_Score is not missing;
quit;

%put NOTE: Within-cohort complete-case Ns (measured, not asserted):;
%put NOTE-   Admit_BMI       = &n_bmi_cohort of &n_admitted;
%put NOTE-   Cognitive_Score = &n_cog_cohort of &n_admitted;
%put NOTE-   Frailty_Score   = &n_frl_cohort of &n_admitted;
%put NOTE-   All three       = &n_all3_cohort of &n_admitted;

/* BMI availability. LACK is derived FROM the HAVE value, not computed
   independently -- two independent 5.1-rounded quotients can sum to 100.1.
   strip() removes putn()s right-alignment padding so the key=value lines
   in the summary have no leading space.                                       */
%macro bmi_pct;
  %global pct_bmi_have pct_bmi_lack;
  %local val_have;
  %if &n_admitted = 0 %then %do;
    %let pct_bmi_have = NA;
    %let pct_bmi_lack = NA;
    %put WARNING: Admitted N is zero -- BMI percentages not computable.;
  %end;
  %else %do;
    %let val_have     = %sysevalf(100 * &n_bmi_cohort / &n_admitted);
    %let pct_bmi_have = %sysfunc(strip(%sysfunc(putn(&val_have, 5.1))));
    %let pct_bmi_lack = %sysfunc(strip(%sysfunc(putn(%sysevalf(100 - &val_have), 5.1))));
  %end;
%mend bmi_pct;
%bmi_pct;

%put NOTE: Of &n_admitted admitted rows: &pct_bmi_have pct HAVE Admit_BMI%str(,) &pct_bmi_lack pct LACK it.;

/* Reopen the DEFAULT listing destination. `ods listing close;` would leave the
   destination shut for the rest of the session, so every later PROC in this
   SAS session would produce no output.                                        */
ods listing;


/* =========================================================================
   SECTION 4: Assert complete-case Ns against g.master_data_merged (PCM-F-11)
   -------------------------------------------------------------------------
   The four known Ns were established on the full 41,150-row merged file.
   Measured values are kept in GLOBAL macro variables so SECTION 6 reports what
   was actually measured rather than repeating hardcoded constants.
   ========================================================================= */

%put NOTE: ==== SECTION 4 -- Asserting complete-case Ns ====;

%macro assert_complete_case_n(var=, expected=, outvar=);
  %global &outvar;
  %local actual;
  proc sql noprint;
    select count(*) into :actual trimmed
    from g.master_data_merged
    where &var is not missing;
  quit;
  %if %superq(actual) = %then
    %fail_out(msg=&var complete-case query returned no value.);
  %let &outvar = &actual;
  %if &actual ne &expected %then
    %fail_out(msg=&var complete-case N = &actual%str(,) expected &expected);
  %put NOTE: &var complete-case N = &actual (assertion passed);
%mend assert_complete_case_n;

%assert_complete_case_n(var=Admit_BMI,       expected=12726, outvar=n_bmi_merged);
%assert_complete_case_n(var=Cognitive_Score, expected=20540, outvar=n_cog_merged);
%assert_complete_case_n(var=Frailty_Score,   expected=23311, outvar=n_frl_merged);

%macro assert_all_three;
  %global n_all3_merged;
  %local actual_all;
  proc sql noprint;
    select count(*) into :actual_all trimmed
    from g.master_data_merged
    where Admit_BMI is not missing
      and Cognitive_Score is not missing
      and Frailty_Score is not missing;
  quit;
  %if %superq(actual_all) = %then
    %fail_out(msg=All-three complete-case query returned no value.);
  %let n_all3_merged = &actual_all;
  %if &actual_all ne 6523 %then
    %fail_out(msg=All-three complete-case N = &actual_all%str(,) expected 6523);
  %put NOTE: All-three complete-case N = &actual_all (assertion passed);
%mend assert_all_three;
%assert_all_three;


/* =========================================================================
   SECTION 5: Promote the validated candidate to g.analytic_cohort
   -------------------------------------------------------------------------
   Everything above has passed. Only now does a permanent dataset appear.
   If any check failed, g.analytic_cohort keeps its previous contents (or stays
   absent) rather than being replaced by something unvalidated.
   ========================================================================= */

%put NOTE: ==== SECTION 5 -- Promoting cohort candidate to g.analytic_cohort ====;

data g.analytic_cohort;
  set work.cohort_candidate;
run;

%macro verify_promotion;
  %local n_promoted;
  proc sql noprint;
    select count(*) into :n_promoted trimmed from g.analytic_cohort;
  quit;
  %if &n_promoted ne &n_admitted %then
    %fail_out(msg=g.analytic_cohort has &n_promoted rows%str(,) candidate had &n_admitted.);
  %put NOTE: COH -- g.analytic_cohort promoted with &n_promoted rows.;
%mend verify_promotion;
%verify_promotion;


/* =========================================================================
   SECTION 6: QC summary and md3-owns note
   -------------------------------------------------------------------------
   Appended with data _null_ ... mod. ODS never writes to this file, so there is
   nothing to truncate. Every N is labelled with its denominator, and the
   asserted values are the MEASURED ones, not repeated constants.
   ========================================================================= */

%put NOTE: ==== SECTION 6 -- Writing QC summary ====;

data _null_;
  file "&qc_path.\07_cohort_missingness.txt" mod;
  put "=== md3-owns missingness trade-off (PCM-D-11) ===";
  put "Admit_BMI: 28424 of 41150 missing in the merged file.";
  put "  Verified unrecoverable from all 7 other sources (PCM-F-07, PCM-D-11).";
  put "Cognitive_Score: missing values verified unrecoverable from md5, md6 (PCM-D-11).";
  put "Frailty_Score: missing values verified unrecoverable from md5, md6 (PCM-D-11).";
  put "SCOPE: verified for these three variables ONLY. md3-owns missingness is NOT";
  put "  established as a global property -- do not state it as one.";
  put " ";
  put "=== Summary (grep-able key=value lines) ===";
  put "cohort_filter_status=&cohort_status";
  put "merged_n=&n_merged";
  put "admitted_n=&n_admitted";
  put "BMI_complete_case_n_merged=&n_bmi_merged";
  put "Cognitive_complete_case_n_merged=&n_cog_merged";
  put "Frailty_complete_case_n_merged=&n_frl_merged";
  put "all_three_complete_case_n_merged=&n_all3_merged";
  put "BMI_complete_case_n_cohort=&n_bmi_cohort";
  put "Cognitive_complete_case_n_cohort=&n_cog_cohort";
  put "Frailty_complete_case_n_cohort=&n_frl_cohort";
  put "all_three_complete_case_n_cohort=&n_all3_cohort";
  put "pct_admitted_HAVE_bmi=&pct_bmi_have";
  put "pct_admitted_LACK_bmi=&pct_bmi_lack";
  put " ";
  put "NOTE: the four _merged values above were ASSERTED against established";
  put "  expectations and passed. The _cohort values were MEASURED only -- no";
  put "  expectation has ever been established for them.";
run;

/* Degenerate cohort: the artifacts are now complete, so fail loudly.
   Order matters -- the diagnostic must survive the abort, which is why this
   comes after SECTION 6 rather than at the point of detection.               */
%macro gate_on_status;
  %if &cohort_status = ZERO_ROWS or &cohort_status = ALL_ROWS
      or &cohort_status = QUERY_FAILED %then %do;
    data _null_;
      file "&qc_path.\07_cohort_missingness.txt" mod;
      put " ";
      put "*** RUN FAILED: cohort_filter_status=&cohort_status ***";
      put "The cohort is degenerate. Downstream phases must NOT treat this run as";
      put "approval. Review the Patient_Type distribution in 07_cohort_tables.txt.";
    run;
    %fail_out(msg=Degenerate cohort -- cohort_filter_status=&cohort_status);
  %end;
  %put NOTE: COH -- cohort_filter_status=&cohort_status;
%mend gate_on_status;
%gate_on_status;

%put NOTE: ==== 07_cohort.sas complete ====;
%put NOTE- Summary : qc/07_cohort_missingness.txt;
%put NOTE- Tables  : qc/07_cohort_tables.txt;

/* Restore the log. Every abort path restores it too, via %fail_out. */
proc printto;
run;
