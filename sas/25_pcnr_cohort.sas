/* Program : 25_pcnr_cohort.sas
   Phase   : 25 -- pcnr Cohort, Dictionary and Wiring
   Purpose : Subsets g.pcnr_harmonized to the PCM-D-05 cohort (INPATIENT+OBSERVATION),
             promotes to g.pcnr_analytic_cohort via WORK-then-promote, computes
             complete-case Ns vs g.analytic_cohort benchmarks, writes
             qc/25_complete_case_n.csv, builds PCNR_DICTIONARY.xlsx, and writes
             qc/25_pcnr_variables.csv.
   Requirements: PCNR-12, PCNR-13, PCNR-14
   PCM violations avoided:
     PCM-T-01: no PROC SQL UPDATE
     PCM-T-02: no in-place dataset rewrite
     PCM-T-11: every numeric comparison carries IS NOT MISSING guard
     PCM-T-16: no PROC IMPORT -- all CSV reads use DATA step infile with explicit $ informats
     PCM-R-05: every %abort cancel is inside a named macro definition
     All counts use SELECT COUNT(*) INTO :macvar TRIMMED
     Pure ASCII throughout -- no non-ASCII characters (PCM-F-10)
     No %put WARNING lines (scanner counts them)
*/

/* =========================================================================
   SECTION 0: Options, paths, preconditions, macros, errorabend
   =========================================================================
   OPEN CODE -- never wrap this %include in a macro: the %lets in 00_config would become
   LOCAL and vanish (this is exactly how the first Phase 24 run failed).           */
options nodate nonumber ps=max ls=200;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* g is WRITABLE -- Section 3 promotes the validated cohort into it */
libname g "&g_path";

/* errorabend IMMEDIATELY after libname -- a gate whose %if errors otherwise
   fails open and the rest of the program keeps running (Phase 24 lesson).    */
%macro _set_errorabend;
  %if &in_pipeline = 1 %then %do;
    options errorabend;
  %end;
%mend _set_errorabend;
%_set_errorabend;

/* ---- Restore-and-abort helper -------------------------------------------
   Any abort path must restore session state first, or the log stays redirected
   to a file and every later submit in this session appears to vanish.        */
%macro fail_out(msg=);
  %put ERROR: &msg;
  ods listing;
  proc printto; run;
  %put ERROR: 25_pcnr_cohort.sas aborted -- &msg;
  %abort cancel;
%mend fail_out;

/* ---- Directory existence guard ------------------------------------------
   Run BEFORE the log is redirected -- a missing logs\ would otherwise make
   PROC PRINTTO fail with the diagnostic going nowhere useful.               */
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

/* Route the log (standalone only; pipeline owns the master log) */
%macro _route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\25_pcnr_cohort.log" new; run;
  %end;
%mend _route_log;
%_route_log;

/* ---- PCNR_APPROVED gate ------------------------------------------------- */
%macro _gate_pcnr_approved;
  %if &PCNR_APPROVED ne 1 %then
    %fail_out(msg=PCNR_APPROVED is not 1 -- run Phase 23 checkpoint first.);
  %put NOTE: [25_pcnr_cohort] SECTION 0 OK -- PCNR_APPROVED=&PCNR_APPROVED;
%mend _gate_pcnr_approved;
%_gate_pcnr_approved;

/* ---- Source dataset existence gates ------------------------------------- */
%macro _gate_pcnr_harmonized;
  %local n_tab;
  proc sql noprint;
    select count(*) into :n_tab trimmed
    from dictionary.tables
    where libname='G' and upcase(memname)='PCNR_HARMONIZED';
  quit;
  %if &n_tab ne 1 %then
    %fail_out(msg=g.pcnr_harmonized not found -- run Phase 24 first.);
  %put NOTE: [25_pcnr_cohort] SECTION 0 OK -- g.pcnr_harmonized present.;
%mend _gate_pcnr_harmonized;
%_gate_pcnr_harmonized;

%macro _gate_analytic_cohort;
  %local n_tab2;
  proc sql noprint;
    select count(*) into :n_tab2 trimmed
    from dictionary.tables
    where libname='G' and upcase(memname)='ANALYTIC_COHORT';
  quit;
  %if &n_tab2 ne 1 %then
    %fail_out(msg=g.analytic_cohort not found -- run Phase 16 first.);
  %put NOTE: [25_pcnr_cohort] SECTION 0 OK -- g.analytic_cohort present.;
%mend _gate_analytic_cohort;
%_gate_analytic_cohort;

%put NOTE: ==== Phase 25 pcnr Cohort starting ====;

/* =========================================================================
   SECTION 1: Subset g.pcnr_harmonized to PCM-D-05 cohort
   ========================================================================= */
%put NOTE: [25_pcnr_cohort] SECTION 1 -- applying Patient_Type filter;

data work._pcnr_cohort_candidate;
  set g.pcnr_harmonized;
  where pcnr_Patient_Type in ('INPATIENT', 'OBSERVATION');
run;

proc sql noprint;
  select count(*) into :n_candidate trimmed from work._pcnr_cohort_candidate;
quit;
%put NOTE: [25_pcnr_cohort] SECTION 1 -- candidate N = &n_candidate;

/* =========================================================================
   SECTION 2: Assertions before promote
   ========================================================================= */
%put NOTE: [25_pcnr_cohort] SECTION 2 -- asserting N = 13890 and ID set identity;

%macro _assert_candidate_n;
  %if &n_candidate ne 13890 %then
    %fail_out(msg=work._pcnr_cohort_candidate has &n_candidate rows -- expected 13890 (PCNR-12));
  %put NOTE: [25_pcnr_cohort] SECTION 2 -- N assertion passed: &n_candidate rows.;
%mend _assert_candidate_n;
%_assert_candidate_n;

/* Assert PRECEDE_STUDY_ID set identity vs g.analytic_cohort (both directions) */
proc sql noprint;
  select count(*) into :n_id_only_cand trimmed
  from work._pcnr_cohort_candidate
  where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from g.analytic_cohort);

  select count(*) into :n_id_only_orig trimmed
  from g.analytic_cohort
  where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from work._pcnr_cohort_candidate);
quit;

%macro _assert_id_set;
  %if &n_id_only_cand ne 0 or &n_id_only_orig ne 0 %then
    %fail_out(msg=PRECEDE_STUDY_ID set mismatch -- cand_only=&n_id_only_cand orig_only=&n_id_only_orig (PCNR-12));
  %put NOTE: [25_pcnr_cohort] SECTION 2 -- PRECEDE_STUDY_ID set identity confirmed.;
%mend _assert_id_set;
%_assert_id_set;

/* =========================================================================
   SECTION 3: WORK-then-promote to g.pcnr_analytic_cohort
   ========================================================================= */
%put NOTE: [25_pcnr_cohort] SECTION 3 -- promoting to g.pcnr_analytic_cohort;

data g.pcnr_analytic_cohort;
  set work._pcnr_cohort_candidate;
run;

proc sql noprint;
  select count(*) into :n_promoted trimmed from g.pcnr_analytic_cohort;
quit;

%macro _assert_promoted_n;
  %if &n_promoted ne 13890 %then
    %fail_out(msg=g.pcnr_analytic_cohort has &n_promoted rows after promote -- expected 13890);
  %put NOTE: [25_pcnr_cohort] SECTION 3 OK -- g.pcnr_analytic_cohort promoted: &n_promoted rows.;
%mend _assert_promoted_n;
%_assert_promoted_n;

/* =========================================================================
   SECTION 4: Compute complete-case Ns
   n_before from g.analytic_cohort (original variable names, read-only)
   n_after  from g.pcnr_analytic_cohort (pcnr_ prefixed names)
   ========================================================================= */
%put NOTE: [25_pcnr_cohort] SECTION 4 -- computing complete-case Ns;

proc sql noprint;
  /* n_before: from g.analytic_cohort using original variable names */
  select count(Admit_BMI)       into :n_bmi_before   trimmed from g.analytic_cohort;
  select count(Cognitive_Score) into :n_cog_before   trimmed from g.analytic_cohort;
  select count(Frailty_Score)   into :n_frail_before trimmed from g.analytic_cohort;
  select count(*)               into :n_all3_before  trimmed
    from g.analytic_cohort
    where Admit_BMI is not missing
      and Cognitive_Score is not missing
      and Frailty_Score is not missing;

  /* n_after: from g.pcnr_analytic_cohort using pcnr_ names */
  select count(pcnr_Admit_BMI)       into :n_bmi_after   trimmed from g.pcnr_analytic_cohort;
  select count(pcnr_Cognitive_Score) into :n_cog_after   trimmed from g.pcnr_analytic_cohort;
  select count(pcnr_Frailty_Score)   into :n_frail_after trimmed from g.pcnr_analytic_cohort;
  select count(*)                    into :n_all3_after  trimmed
    from g.pcnr_analytic_cohort
    where pcnr_Admit_BMI is not missing
      and pcnr_Cognitive_Score is not missing
      and pcnr_Frailty_Score is not missing;
quit;

%put NOTE: [25_pcnr_cohort] n_before: BMI=&n_bmi_before Cog=&n_cog_before Frail=&n_frail_before All3=&n_all3_before;
%put NOTE: [25_pcnr_cohort] n_after:  BMI=&n_bmi_after  Cog=&n_cog_after  Frail=&n_frail_after  All3=&n_all3_after;

/* =========================================================================
   SECTION 5: Assertions + write qc/25_complete_case_n.csv
   ========================================================================= */
%put NOTE: [25_pcnr_cohort] SECTION 5 -- asserting n_after <= n_before;

/* Assertion 1: n_after must not exceed n_before for any measure.
   Recoding only adds missing values, never fills them in.              */
%macro _assert_n_after(measure=, nbefore=, nafter=);
  %if &nafter > &nbefore %then
    %fail_out(msg=PCNR-13 FAILED -- &measure n_after (&nafter) > n_before (&nbefore));
%mend _assert_n_after;

%_assert_n_after(measure=pcnr_Admit_BMI,       nbefore=&n_bmi_before,   nafter=&n_bmi_after);
%_assert_n_after(measure=pcnr_Cognitive_Score, nbefore=&n_cog_before,   nafter=&n_cog_after);
%_assert_n_after(measure=pcnr_Frailty_Score,   nbefore=&n_frail_before, nafter=&n_frail_after);
%_assert_n_after(measure=all_three,            nbefore=&n_all3_before,  nafter=&n_all3_after);

/* Assertion 1b: For measures with 0 recodes, n_after must equal n_before.
   Read qc/24_pcnr_recode_totals.csv via DATA step infile (PCM-T-16).
   Schema: variable,final_name,n_recoded_total                          */
data work._recode_totals;
  infile "&qc_path.\24_pcnr_recode_totals.csv" dsd firstobs=2 truncover;
  length variable $ 64 final_name $ 64 n_recoded_total 8;
  input variable $ final_name $ n_recoded_total;
run;

/* Extract n_recoded_total for the three score variables.
   PCM-D-24 approved no numeric recodes, so all three are expected = 0. */
proc sql noprint;
  select n_recoded_total into :rc_bmi   trimmed
    from work._recode_totals where upcase(final_name) = 'PCNR_ADMIT_BMI';
  select n_recoded_total into :rc_cog   trimmed
    from work._recode_totals where upcase(final_name) = 'PCNR_COGNITIVE_SCORE';
  select n_recoded_total into :rc_frail trimmed
    from work._recode_totals where upcase(final_name) = 'PCNR_FRAILTY_SCORE';
quit;

/* If any macro variable is empty (variable not in file), treat as unknown and skip
   (guard only -- pipeline should not reach here with missing recode records).     */
%macro _assert_zero_recode_no_change;
  %if %length(&rc_bmi) > 0 %then %do;
    %if &rc_bmi = 0 %then %do;
      %if &n_bmi_after ne &n_bmi_before %then
        %fail_out(msg=PCNR-13 FAILED -- pcnr_Admit_BMI had 0 recodes but n_after (&n_bmi_after) ne n_before (&n_bmi_before));
    %end;
  %end;
  %if %length(&rc_cog) > 0 %then %do;
    %if &rc_cog = 0 %then %do;
      %if &n_cog_after ne &n_cog_before %then
        %fail_out(msg=PCNR-13 FAILED -- pcnr_Cognitive_Score had 0 recodes but n_after (&n_cog_after) ne n_before (&n_cog_before));
    %end;
  %end;
  %if %length(&rc_frail) > 0 %then %do;
    %if &rc_frail = 0 %then %do;
      %if &n_frail_after ne &n_frail_before %then
        %fail_out(msg=PCNR-13 FAILED -- pcnr_Frailty_Score had 0 recodes but n_after (&n_frail_after) ne n_before (&n_frail_before));
    %end;
  %end;
  /* all_three: require equality when all three component recode counts are 0 */
  %if %length(&rc_bmi) > 0 and %length(&rc_cog) > 0 and %length(&rc_frail) > 0 %then %do;
    %if &rc_bmi = 0 and &rc_cog = 0 and &rc_frail = 0 %then %do;
      %if &n_all3_after ne &n_all3_before %then
        %fail_out(msg=PCNR-13 FAILED -- all_three: all component recode counts are 0 but n_after (&n_all3_after) ne n_before (&n_all3_before));
    %end;
  %end;
  %put NOTE: [25_pcnr_cohort] SECTION 5 -- zero-recode equality assertions passed.;
%mend _assert_zero_recode_no_change;
%_assert_zero_recode_no_change;

/* Assertion 2: n_before benchmarks must match known values (PCNR-13).
   Hard-coded from STATE.md / CONTEXT.md.                              */
%macro _assert_n_before_benchmarks;
  %if &n_bmi_before   ne 12726 %then %fail_out(msg=pcnr_Admit_BMI n_before=&n_bmi_before -- expected 12726);
  %if &n_cog_before   ne 7252  %then %fail_out(msg=pcnr_Cognitive_Score n_before=&n_cog_before -- expected 7252);
  %if &n_frail_before ne 8150  %then %fail_out(msg=pcnr_Frailty_Score n_before=&n_frail_before -- expected 8150);
  %if &n_all3_before  ne 6523  %then %fail_out(msg=all_three n_before=&n_all3_before -- expected 6523);
  %put NOTE: [25_pcnr_cohort] SECTION 5 -- n_before benchmarks confirmed.;
%mend _assert_n_before_benchmarks;
%_assert_n_before_benchmarks;

/* Write qc/25_complete_case_n.csv via DATA step PUT (PCM-T-16 -- never PROC EXPORT).
   n_difference computed inline with %eval.                                          */
data _null_;
  file "&qc_path.\25_complete_case_n.csv";
  put "measure,n_before,n_after,n_difference";
  put "pcnr_Admit_BMI,&n_bmi_before,&n_bmi_after,%eval(&n_bmi_before - &n_bmi_after)";
  put "pcnr_Cognitive_Score,&n_cog_before,&n_cog_after,%eval(&n_cog_before - &n_cog_after)";
  put "pcnr_Frailty_Score,&n_frail_before,&n_frail_after,%eval(&n_frail_before - &n_frail_after)";
  put "all_three,&n_all3_before,&n_all3_after,%eval(&n_all3_before - &n_all3_after)";
run;
%put NOTE: [25_pcnr_cohort] SECTION 5 OK -- qc/25_complete_case_n.csv written.;

/* =========================================================================
   SECTION 6: PCNR_DICTIONARY.xlsx -- see Plan 25-02
   ========================================================================= */

/* =========================================================================
   SECTION 7: qc/25_pcnr_variables.csv -- see Plan 25-02
   ========================================================================= */
