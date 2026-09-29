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
   SECTION 4: Compute complete-case Ns -- see Plan 25-01 Task 2
   ========================================================================= */

/* =========================================================================
   SECTION 5: Assertions + write qc/25_complete_case_n.csv -- see Plan 25-01 Task 2
   ========================================================================= */

/* =========================================================================
   SECTION 6: PCNR_DICTIONARY.xlsx -- see Plan 25-02
   ========================================================================= */

/* =========================================================================
   SECTION 7: qc/25_pcnr_variables.csv -- see Plan 25-02
   ========================================================================= */
