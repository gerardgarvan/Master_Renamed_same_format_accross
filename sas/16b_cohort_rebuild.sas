/* Program : 16b_cohort_rebuild.sas
   Phase   : 16 -- Rebuild the Analytic Cohort
   Purpose : Reads g.master_data_harmonized (never writes it). Rebuilds
             g.analytic_cohort from g.master_data_harmonized restricted to
             INPATIENT+OBSERVATION rows. Validates in WORK, promotes the
             validated candidate to g.analytic_cohort (replacing the stale
             Phase 7 version), measures within-cohort and h_* Ns, and
             asserts the source file is unmodified after the run.
   Requirements: HARM-10, PCM-D-05

   PCM violations avoided:
     PCM-T-01: no PROC SQL UPDATE
     PCM-T-02: no in-place dataset rewrite (no data g.master_data_harmonized; set g.master_data_harmonized)
     PCM-T-11: every numeric comparison carries an IS NOT MISSING guard
     PCM-R-05: every %abort cancel is inside a named macro definition
     All counts use SELECT COUNT(*) INTO :macvar TRIMMED (automatic row count macro forbidden)
     Pure ASCII throughout -- no non-ASCII characters (PCM-F-10)

   NOTE ON PATH SYNTAX: "&logs_path.\16b_cohort_rebuild.log" is correct and deliberate.
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
   to a file and every later submit in this session appears to vanish.        */
%macro fail_out(msg=);
  %put ERROR: &msg;
  ods listing;                 /* reopen the default destination */
  proc printto; run;           /* restore the log BEFORE aborting */
  %put ERROR: 16b_cohort_rebuild.sas aborted -- &msg;
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
proc printto log="&logs_path.\16b_cohort_rebuild.log" new;
run;

%put NOTE: ==== Phase 16 Cohort Rebuild starting ====;

/* 0b: g.master_data_harmonized must exist */
%macro check_source_exists;
  %local n_tab;
  proc sql noprint;
    select count(*) into :n_tab trimmed
    from dictionary.tables
    where libname='G' and upcase(memname)='MASTER_DATA_HARMONIZED';
  quit;
  %if &n_tab ne 1 %then
    %fail_out(msg=g.master_data_harmonized not found. Run Phases 3-15 first.);
  %put NOTE: PRECONDITION OK -- g.master_data_harmonized present.;
%mend check_source_exists;
%check_source_exists;

/* 0c: required variables must ALL be present before anything is written */
%macro check_vars_present;
  %local i v n_hit missing_list;
  %let missing_list = ;
  %do i = 1 %to 5;
    %let v = %scan(Patient_Type Admit_BMI Cognitive_Score Frailty_Score Age_at_Encounter, &i);
    proc sql noprint;
      select count(*) into :n_hit trimmed
      from dictionary.columns
      where libname='G' and upcase(memname)='MASTER_DATA_HARMONIZED'
        and upcase(name) = %upcase("&v");
    quit;
    %if &n_hit = 0 %then %let missing_list = &missing_list &v;
  %end;
  %if %superq(missing_list) ne %then
    %fail_out(msg=Required variables absent from g.master_data_harmonized:&missing_list);
  %put NOTE: PRECONDITION OK -- all five required variables present.;
%mend check_vars_present;
%check_vars_present;

/* 0d: row count must be 41,150 */
proc sql noprint;
  select count(*) into :n_harmonized trimmed
  from g.master_data_harmonized;
quit;

%macro assert_row_count;
  %if %superq(n_harmonized) = %then
    %fail_out(msg=Row count query returned no value -- g.master_data_harmonized unreadable.);
  %if &n_harmonized ne 41150 %then
    %fail_out(msg=g.master_data_harmonized has &n_harmonized rows%str(,) expected 41150. Re-run Phases 4-15.);
  %put NOTE: PRECONDITION OK -- g.master_data_harmonized has &n_harmonized rows.;
%mend assert_row_count;
%assert_row_count;

/* 0e: open the summary artifact fresh. This file is written ONLY by
   data _null_ steps -- ODS never touches it, so nothing truncates it. */
data _null_;
  file "&qc_path.\16b_cohort_missingness.txt";
  put "16b_cohort_missingness -- Run: %sysfunc(datetime(), datetime20.)";
  put "Phase 16 Cohort Rebuild -- g.master_data_harmonized (&n_harmonized rows)";
  put "Tables and distributions: see 16b_cohort_tables.txt (written by ODS LISTING)";
  put "=======================================================================";
  put " ";
run;


/* =========================================================================
   SECTION 1: Patient_Type distribution (PCM-D-05 evidence)
   -------------------------------------------------------------------------
   ODS LISTING writes to a SEPARATE file. Pointing it at
   16b_cohort_missingness.txt would TRUNCATE the header just written above --
   opening an ODS destination with FILE= creates or replaces, it does not append.
   ========================================================================= */

ods listing file="&qc_path.\16b_cohort_tables.txt";

%put NOTE: ==== SECTION 1 -- Patient_Type distribution (pre-filter) ====;

proc freq data=g.master_data_harmonized;
  tables Patient_Type / missing;
  title "Patient_Type distribution in g.master_data_harmonized (pre-filter) -- PCM-D-05 evidence";
run;
title;


/* =========================================================================
   SECTION 2: Build the cohort candidate in WORK
   -------------------------------------------------------------------------
   NOT written to g yet. Promotion happens in SECTION 5, after every check
   has passed. The gate runs BEFORE promotion (fixed latent flaw from 07).
   ========================================================================= */

%put NOTE: ==== SECTION 2 -- Building work.cohort_candidate ====;

data work.cohort_candidate;
  set g.master_data_harmonized;
  where upcase(strip(Patient_Type)) in ('INPATIENT','OBSERVATION');
run;

proc sql noprint;
  select count(*) into :n_admitted trimmed
  from work.cohort_candidate;
quit;

%put NOTE: Admitted-patient N (INPATIENT+OBSERVATION) = &n_admitted;

/* Classify the filter result. The status is recorded in the QC file (SECTION 7). */
%macro classify_cohort;
  %global cohort_status;
  %if %superq(n_admitted) = %then %let cohort_status = QUERY_FAILED;
  %else %if &n_admitted = 0 %then %do;
    %let cohort_status = ZERO_ROWS;
    %put WARNING: Admitted N is zero -- the Patient_Type filter matched no rows.;
    %put WARNING- Check the SECTION 1 PROC FREQ in 16b_cohort_tables.txt.;
  %end;
  %else %if &n_admitted = &n_harmonized %then %do;
    %let cohort_status = ALL_ROWS;
    %put WARNING: Admitted N equals harmonized N (&n_admitted) -- the filter matched everything.;
    %put WARNING- Check the SECTION 1 PROC FREQ in 16b_cohort_tables.txt.;
  %end;
  %else %do;
    %let cohort_status = OK;
    %put NOTE: Admitted N (&n_admitted) is a proper subset of harmonized N (&n_harmonized).;
  %end;
%mend classify_cohort;
%classify_cohort;


/* =========================================================================
   SECTION 3: Missingness profile (PCM-F-11)
   -------------------------------------------------------------------------
   Within-cohort Ns are MEASURED, never asserted -- except the BMI rationale
   assertion (assert_bmi_rationale) which is called after SECTION 4 sets
   &n_bmi_harm.
   ========================================================================= */

%put NOTE: ==== SECTION 3 -- Missingness profile ====;

proc means data=g.master_data_harmonized n nmiss;
  var Admit_BMI Cognitive_Score Frailty_Score Age_at_Encounter;
  title "Missingness profile: g.master_data_harmonized (all &n_harmonized rows)";
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

/* Programmatic confirmation of the post-filter invariant */
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

/* Within-cohort complete-case Ns -- measured (not asserted, except BMI) */
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
%put NOTE-   Cognitive_Score = &n_cog_cohort of &n_admitted (prior merged: 7252);
%put NOTE-   Frailty_Score   = &n_frl_cohort of &n_admitted (prior merged: 8150);
%put NOTE-   All three       = &n_all3_cohort of &n_admitted (D-06: measure only);

/* BMI availability. LACK is derived FROM the HAVE value, not computed
   independently -- two independent 5.1-rounded quotients can sum to 100.1. */
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

/* Compare admitted N to the reference -- WARNING only, no abort */
%macro compare_admitted_n;
  %if &n_admitted ne 13890 %then
    %put WARNING: admitted N is &n_admitted%str(,) reference 13890 -- investigate before trusting the cohort;
  %else
    %put NOTE: Admitted N (&n_admitted) matches reference 13890.;
%mend compare_admitted_n;
%compare_admitted_n;

/* Reopen the DEFAULT listing destination (not close -- close shuts it for the session) */
ods listing;


/* =========================================================================
   SECTION 4: Assert complete-case Ns against g.master_data_harmonized (PCM-F-11)
   -------------------------------------------------------------------------
   The three known Ns were established on the full 41,150-row harmonized file.
   Measured values kept in GLOBAL macro variables so SECTION 7 reports what
   was actually measured.
   ========================================================================= */

%put NOTE: ==== SECTION 4 -- Asserting complete-case Ns ====;

%macro assert_complete_case_n(var=, expected=, outvar=);
  %global &outvar;
  %local actual;
  proc sql noprint;
    select count(*) into :actual trimmed
    from g.master_data_harmonized
    where &var is not missing;
  quit;
  %if %superq(actual) = %then
    %fail_out(msg=&var complete-case query returned no value.);
  %let &outvar = &actual;
  %if &actual ne &expected %then
    %fail_out(msg=&var complete-case N = &actual%str(,) expected &expected);
  %put NOTE: &var complete-case N = &actual (assertion passed);
%mend assert_complete_case_n;

%assert_complete_case_n(var=Admit_BMI,       expected=12726, outvar=n_bmi_harm);
%assert_complete_case_n(var=Cognitive_Score, expected=20540, outvar=n_cog_harm);
%assert_complete_case_n(var=Frailty_Score,   expected=23311, outvar=n_frl_harm);

/* D-06: measure all-three on full harmonized file -- do NOT assert (6,523 was stale) */
%global n_all3_harm;
proc sql noprint;
  select count(*) into :n_all3_harm trimmed
  from g.master_data_harmonized
  where Admit_BMI is not missing
    and Cognitive_Score is not missing
    and Frailty_Score is not missing;
quit;
%put NOTE: All-three complete-case N on harmonized file = &n_all3_harm (D-06: measured, not asserted);

/* PCM-D-05 rationale assertion: all 12,726 BMI values must be INSIDE the admitted cohort.
   Assert equality between the two measured values (n_bmi_cohort and n_bmi_harm).
   This fires only if an ambulatory row somehow has Admit_BMI -- the biological impossibility
   that is the core of the D-05 decision. */
%macro assert_bmi_rationale;
  %if &n_bmi_cohort ne &n_bmi_harm %then
    %fail_out(msg=PCM-D-05 rationale violated: &n_bmi_harm Admit_BMI values on full file but only &n_bmi_cohort inside the admitted cohort);
  %else
    %put NOTE: PCM-D-05 rationale holds -- n_bmi_cohort (&n_bmi_cohort) = n_bmi_harm (&n_bmi_harm). All BMI values are inside the admitted cohort.;
%mend assert_bmi_rationale;
%assert_bmi_rationale;


/* =========================================================================
   SECTION 5: Gate, then promote the validated candidate to g.analytic_cohort
   -------------------------------------------------------------------------
   GATE RUNS FIRST (fixes latent ordering flaw in 07_cohort.sas where a
   ZERO_ROWS candidate could pass %verify_promotion and overwrite g.analytic_cohort
   before the gate fired). Gate first, promote second.
   Everything above has passed. Only now does a permanent dataset appear.
   ========================================================================= */

%put NOTE: ==== SECTION 5 -- Gate and promote cohort candidate to g.analytic_cohort ====;

%macro gate_on_status;
  %if &cohort_status = ZERO_ROWS or &cohort_status = ALL_ROWS
      or &cohort_status = QUERY_FAILED %then %do;
    data _null_;
      file "&qc_path.\16b_cohort_missingness.txt" mod;
      put " ";
      put "*** RUN FAILED: cohort_filter_status=&cohort_status ***";
      put "The cohort is degenerate. Downstream phases must NOT treat this run as";
      put "approval. Review the Patient_Type distribution in 16b_cohort_tables.txt.";
    run;
    %fail_out(msg=Degenerate cohort -- cohort_filter_status=&cohort_status);
  %end;
  %put NOTE: COH -- cohort_filter_status=&cohort_status;
%mend gate_on_status;
%gate_on_status;

/* Full 175-column pass-through (174 original + pecan_ID from 10b) -- no KEEP, no DROP (D-09) */
data g.analytic_cohort;
  set work.cohort_candidate;
run;

/* Verify row count matches what was built in WORK */
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

/* Verify column count is exactly 175 (174 original + pecan_ID from 10b amendment) */
%macro verify_cohort_cols;
  %global n_cohort_cols;
  proc sql noprint;
    select count(*) into :n_cohort_cols trimmed
    from dictionary.columns
    where libname='G' and upcase(memname)='ANALYTIC_COHORT';
  quit;
  %if &n_cohort_cols ne 175 %then
    %fail_out(msg=g.analytic_cohort has &n_cohort_cols columns%str(,) expected 175 (174 original + pecan_ID).);
  %put NOTE: COH -- g.analytic_cohort has &n_cohort_cols columns (175 confirmed).;
%mend verify_cohort_cols;
%verify_cohort_cols;


/* =========================================================================
   SECTION 5c: PID-05 attachment assertions on g.analytic_cohort
   pecan_ID flows through via full SET in SECTION 2 (from g.master_data_harmonized
   which was amended by 10b to carry pecan_ID -- no second join needed in 16b).
   ========================================================================= */

%macro assert_pecan_attach_cohort;
  %local n_blank_pid n_dup_pid;
  proc sql noprint;
    select count(*) into :n_blank_pid trimmed
    from g.analytic_cohort
    where pecan_ID is missing
      and not missing(ENCRYPTED_MRN)
      and strip(upcase(ENCRYPTED_MRN)) ne 'NULL';
    select count(*) into :n_dup_pid trimmed
    from (
      select PRECEDE_STUDY_ID, count(distinct pecan_ID) as n_pid
      from g.analytic_cohort
      group by PRECEDE_STUDY_ID
      having calculated n_pid > 1
    );
  quit;
  %put NOTE: [16b] PID-05 blank pecan_ID where MRN non-blank/non-NULL: &n_blank_pid;
  %put NOTE: [16b] PID-05 PRECEDEs with more than one pecan_ID: &n_dup_pid;
  %if &n_blank_pid > 0 %then %do;
    %fail_out(msg=PID-05 ABORT -- &n_blank_pid cohort rows have blank pecan_ID with non-blank non-NULL ENCRYPTED_MRN);
  %end;
  %if &n_dup_pid > 0 %then %do;
    %fail_out(msg=PID-05 ABORT -- &n_dup_pid PRECEDE_STUDY_IDs in cohort have more than one distinct pecan_ID);
  %end;
  %put NOTE: [16b] PID-05 all cohort attachment assertions passed;
%mend assert_pecan_attach_cohort;
%assert_pecan_attach_cohort;


/* =========================================================================
   SECTION 6: Assert source unmodified; measure h_* within-cohort Ns
   =========================================================================
   assert_harmonized_unchanged: adapted from 10b_concept_harmonize.sas pattern.
   Confirms the promotion DATA step did not accidentally modify the source.
   ========================================================================= */

%put NOTE: ==== SECTION 6 -- Verify source unchanged; measure h_* Ns ====;

%macro assert_harmonized_unchanged;
  %local n_cols n_rows;
  proc sql noprint;
    select count(*) into :n_cols trimmed
    from dictionary.columns
    where libname='G' and upcase(memname)='MASTER_DATA_HARMONIZED';
    select count(*) into :n_rows trimmed
    from g.master_data_harmonized;
  quit;
  %if &n_cols ne 175 or &n_rows ne 41150 %then
    %fail_out(msg=g.master_data_harmonized changed: &n_cols cols and &n_rows rows -- expected 175 and 41150);
  %put NOTE: g.master_data_harmonized confirmed post-run -- 175 columns and 41150 rows -- unmodified;
%mend assert_harmonized_unchanged;
%assert_harmonized_unchanged;

/* D-07: Measure 12 h_* column Ns within the admitted cohort (report only, no assertion).
   Each column is queried and written to the missingness QC file. */
%macro measure_h_cols;
  %local hvars i hvar hn;
  %let hvars = H_DEATH_YN H_DIABETES H_FRAILTY_ACTIVITY H_FRAILTY_EXHAUST H_FRAILTY_GRIP
               H_FRAILTY_WALKING H_FRAILTY_WEIGHT H_HYPERLIPIDEMIA H_HYPERTENSION
               H_MOVEMENT_DISORDER H_SLEEP_APNEA;
  %do i = 1 %to 11;
    %let hvar = %scan(&hvars, &i);
    proc sql noprint;
      select count(*) into :hn trimmed
      from work.cohort_candidate
      where &hvar is not missing;
    quit;
    data _null_;
      file "&qc_path.\16b_cohort_missingness.txt" mod;
      put "h_within_cohort_&hvar=&hn";
    run;
    %put NOTE: h_within_cohort_&hvar=&hn;
  %end;
%mend measure_h_cols;
%measure_h_cols;


/* =========================================================================
   SECTION 6b: PID-06 pecan_ID counts for both datasets (D-17, D-18, D-19)
   Output to qc/16b_pecan_id_counts.txt (fresh write, not appended to missingness).
   Reports side by side for g.master_data_harmonized (41,150) and g.analytic_cohort (13,890).
   ========================================================================= */

%put NOTE: ==== SECTION 6b -- PID-06 pecan_ID counts ====;

%macro pecan_counts(ds=, sfx=);
  /* Rows and patients by encounter bucket for one dataset. Writes GLOBAL
     macro variables suffixed with &sfx (h = harmonized, c = cohort). */
  %global rows_&sfx no_pecan_&sfx n_dist_&sfx n1enc_&sfx n2enc_&sfx
          n3plus_&sfx rows3plus_&sfx;
  proc sql noprint;
    create table work._pid_enc_&sfx as
    select pecan_ID, count(*) as n_enc
    from &ds
    where pecan_ID is not missing
    group by pecan_ID;

    select count(*) into :rows_&sfx trimmed from &ds;
    select count(*) into :no_pecan_&sfx trimmed from &ds where pecan_ID is missing;
    select count(*) into :n_dist_&sfx trimmed from work._pid_enc_&sfx;
    select count(*) into :n1enc_&sfx trimmed from work._pid_enc_&sfx where n_enc = 1;
    select count(*) into :n2enc_&sfx trimmed from work._pid_enc_&sfx where n_enc = 2;
    select count(*) into :n3plus_&sfx trimmed from work._pid_enc_&sfx where n_enc >= 3;
    select coalesce(sum(n_enc), 0) into :rows3plus_&sfx trimmed
    from work._pid_enc_&sfx where n_enc >= 3;
  quit;

  /* Both identities must hold, otherwise the buckets are miscounted */
  %if %eval(&&n1enc_&sfx + &&n2enc_&sfx + &&n3plus_&sfx) ne &&n_dist_&sfx %then %do;
    %fail_out(msg=PID-06 ABORT -- &ds patient buckets do not sum to distinct pecan_ID count);
  %end;
  %if %eval(&&no_pecan_&sfx + &&n1enc_&sfx + 2 * &&n2enc_&sfx + &&rows3plus_&sfx) ne &&rows_&sfx %then %do;
    %fail_out(msg=PID-06 ABORT -- &ds row buckets do not sum to total row count);
  %end;
%mend pecan_counts;

%macro write_pecan_id_counts;
  %pecan_counts(ds=g.master_data_harmonized, sfx=h);
  %pecan_counts(ds=g.analytic_cohort,        sfx=c);

  /* Fresh write -- this is the first and only write to this file */
  data _null_;
    file "&qc_path.\16b_pecan_id_counts.txt" lrecl=200;
    put "==========================================================================";
    put "Phase 20 -- PID-06 pecan_ID Counts";
    put "Generated: %sysfunc(datetime(), datetime20.)";
    put "==========================================================================";
    put " ";
    put "g.master_data_harmonized";
    put "--------------------------------------";
    put "rows_harmonized=&rows_h";
    put "no_pecan_id_rows_harmonized=&no_pecan_h";
    put "distinct_pecan_id_harmonized=&n_dist_h";
    put "pecan_id_1enc_harmonized=&n1enc_h";
    put "pecan_id_2enc_harmonized=&n2enc_h";
    put "pecan_id_3plus_enc_harmonized=&n3plus_h";
    put "rows_in_3plus_harmonized=&rows3plus_h";
    put " ";
    put "g.analytic_cohort";
    put "--------------------------------------";
    put "rows_cohort=&rows_c";
    put "no_pecan_id_rows_cohort=&no_pecan_c";
    put "distinct_pecan_id_cohort=&n_dist_c";
    put "pecan_id_1enc_cohort=&n1enc_c";
    put "pecan_id_2enc_cohort=&n2enc_c";
    put "pecan_id_3plus_enc_cohort=&n3plus_c";
    put "rows_in_3plus_cohort=&rows3plus_c";
    put " ";
    put "Identities (asserted in-run for each dataset):";
    put "  patients: 1enc + 2enc + 3plus_enc = distinct_pecan_id";
    put "  rows:     no_pecan_id_rows + 1enc + 2 x 2enc + rows_in_3plus = rows";
    put "==========================================================================";
  run;

  %put NOTE: [16b] PID-06 harmonized: rows=&rows_h no_pecan=&no_pecan_h dist=&n_dist_h 1enc=&n1enc_h 2enc=&n2enc_h 3plus=&n3plus_h;
  %put NOTE: [16b] PID-06 cohort: rows=&rows_c no_pecan=&no_pecan_c dist=&n_dist_c 1enc=&n1enc_c 2enc=&n2enc_c 3plus=&n3plus_c;
  %put NOTE: [16b] PID-06 counts written to qc/16b_pecan_id_counts.txt;
%mend write_pecan_id_counts;
%write_pecan_id_counts;


/* =========================================================================
   SECTION 7: QC summary
   -------------------------------------------------------------------------
   Appended with data _null_ ... mod. ODS never writes to this file.
   %gate_on_status has ALREADY run in SECTION 5. Do not call it a second time.
   Write cohort_filter_status to the QC file so the artifact records it.
   ========================================================================= */

%put NOTE: ==== SECTION 7 -- Writing QC summary ====;

%local admitted_n_match bmi_rationale_line;
%if &n_admitted = 13890 %then %let admitted_n_match = YES;
%else %let admitted_n_match = NO;

data _null_;
  file "&qc_path.\16b_cohort_missingness.txt" mod;
  put "=== Summary (grep-able key=value lines) ===";
  put "cohort_filter_status=&cohort_status";
  put "harmonized_n=&n_harmonized";
  put "admitted_n=&n_admitted";
  put "cohort_cols=&n_cohort_cols";
  put "BMI_complete_case_n_harmonized=&n_bmi_harm";
  put "Cognitive_complete_case_n_harmonized=&n_cog_harm";
  put "Frailty_complete_case_n_harmonized=&n_frl_harm";
  put "all_three_complete_case_n_harmonized=&n_all3_harm";
  put "BMI_complete_case_n_cohort=&n_bmi_cohort";
  put "Cognitive_complete_case_n_cohort=&n_cog_cohort";
  put "Frailty_complete_case_n_cohort=&n_frl_cohort";
  put "all_three_complete_case_n_cohort=&n_all3_cohort";
  put "expected_admitted_n=13890";
  put "admitted_n_matches_reference=&admitted_n_match";
  put "bmi_rationale_asserted=PASS (n_bmi_cohort = n_bmi_harm)";
  put "Cognitive_complete_case_n_cohort_prior_merged=7252";
  put "Frailty_complete_case_n_cohort_prior_merged=8150";
  put "pct_admitted_HAVE_bmi=&pct_bmi_have";
  put "pct_admitted_LACK_bmi=&pct_bmi_lack";
  put " ";
  put "NOTE: the three _harmonized Ns above (BMI 12726, Cognitive 20540, Frailty 23311)";
  put "  were ASSERTED and passed. The all_three_harmonized N and all _cohort values";
  put "  are MEASURED baselines -- no expectation has been established for them (D-06).";
  put "  Within-cohort Cognitive and Frailty are expected to be well below the full-file";
  put "  Ns because most values (after MRG-06) sit on ambulatory rows (PCM-F-19).";
run;

%put NOTE: ==== 16b_cohort_rebuild.sas complete ====;
%put NOTE- Summary : qc/16b_cohort_missingness.txt;
%put NOTE- Tables  : qc/16b_cohort_tables.txt;
%put NOTE- Log     : logs/16b_cohort_rebuild.log;

/* Restore the log. Every abort path restores it too, via %fail_out. */
proc printto;
run;
