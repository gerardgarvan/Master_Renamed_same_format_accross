/* Program: 07_cohort.sas
   Phase   : 7 -- Cohort & Missingness
   Purpose : Reads g.master_data_merged (read-only intent, never named on left of DATA).
             Measures Patient_Type distribution, derives g.analytic_cohort
             (INPATIENT + OBSERVATION), asserts four known complete-case Ns against
             the full merged file, measures within-cohort Ns, and writes the committed
             missingness summary to qc/07_cohort_missingness.txt.
   Requirements : PCM-D-05, PCM-F-11, PCM-F-12, COH-01 through COH-04
   Author  : Executor (Phase 7 Plan 01)
   Created : 2026-08-27
   PCM violations avoided:
     PCM-T-01: no PROC SQL UPDATE
     PCM-T-02: no in-place dataset rewrite -- g.master_data_merged never on left of DATA
     PCM-R-05: every abort cancel is inside a named macro definition
     All counts use SELECT COUNT(*) INTO :macvar TRIMMED (established pattern)
     No trim-autocall dependency -- INTO ... TRIMMED already strips
     g library is WRITABLE -- SECTION 2 writes g.analytic_cohort (writable libname required)
     Exactly one ODS LISTING destination opened on the QC path (Pitfall 7 guard)
   NOTE: g.master_data_merged is intentionally never written. Read-only intent enforced
         by naming convention; the source dataset is never on the left of a DATA statement.
*/

/* =========================================================================
   SECTION 0: Options, paths, libname, preconditions
   =========================================================================
   Paths copied from sas/06_reconcile.sas SECTION 0 (same merge tree).
   g library is WRITABLE -- SECTION 2 writes g.analytic_cohort into it.
   Opening the library read-only would prevent writing g.analytic_cohort (RESEARCH Pitfall 8).
   ========================================================================= */
options nodate nonumber ps=max ls=200;
%let g_path    = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge;
%let logs_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs;
%let qc_path   = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc;

libname g "&g_path";

/* Route log to the documented grep target */
proc printto log="&logs_path.\07_cohort.log" new;
run;

%put NOTE: ==== Phase 7 Cohort and Missingness starting ====;

/* 0a: g.master_data_merged exists (PCM-R-05: %abort cancel inside named macro) */
%macro check_source_exists;
  %local n_tab;
  proc sql noprint;
    select count(*) into :n_tab trimmed
    from dictionary.tables
    where libname='G' and upcase(memname)='MASTER_DATA_MERGED';
  quit;
  %if &n_tab ne 1 %then %do;
    %put ERROR: g.master_data_merged not found. Run Phases 3-5 first.;
    %abort cancel;
  %end;
  %put NOTE: PRECONDITION OK -- g.master_data_merged present.;
%mend check_source_exists;
%check_source_exists;

/* 0b: Row count = 41,150 (PCM-R-05: inside named macro) */
proc sql noprint;
  select count(*) into :n_merged trimmed
  from g.master_data_merged;
quit;

%macro assert_row_count;
  %if &n_merged ne 41150 %then %do;
    %put ERROR: g.master_data_merged has &n_merged rows, expected 41150.;
    %put ERROR: Re-run Phases 4-5 before proceeding.;
    %abort cancel;
  %end;
  %put NOTE: PRECONDITION OK -- g.master_data_merged has &n_merged rows (assertion passed).;
%mend assert_row_count;
%assert_row_count;

/* 0c: Open the QC file fresh (no MOD -- re-runs do not accumulate) */
data _null_;
  file "&qc_path.\07_cohort_missingness.txt";
  put "07_cohort_missingness -- Run: %sysfunc(datetime(), datetime20.)";
  put "Phase 7 Cohort and Missingness -- g.master_data_merged (41150 rows)";
  put "=======================================================================";
  put " ";
run;


/* =========================================================================
   SECTION 1: Measure Patient_Type distribution (PCM-D-05 evidence)
   =========================================================================
   PROC FREQ before filtering -- catches trailing spaces, mixed case, or
   unexpected categories that could cause the WHERE in SECTION 2 to silently
   miss rows. ODS LISTING opened ONCE here and kept open through
   SECTION 3; closed before SECTION 6 DATA step appends (Pitfall 7).
   ========================================================================= */

/* ODS LISTING is opened here and closed in SECTION 3.
   Reopening on the same path would truncate the file (Pitfall 7).
   Prose appended after close uses: data _null_; file "..." mod; */
ods listing file="&qc_path.\07_cohort_missingness.txt";

%put NOTE: ==== SECTION 1 -- Patient_Type distribution (pre-filter) ====;

proc freq data=g.master_data_merged;
  tables Patient_Type / missing;
  title "Patient_Type distribution in g.master_data_merged (pre-filter) -- PCM-D-05 evidence";
run;
title;

%put NOTE: Patient_Type distribution above -- review before asserting admitted N.;


/* =========================================================================
   SECTION 2: Derive g.analytic_cohort
   =========================================================================
   DATA step with WHERE -- never PROC SQL CREATE TABLE (would break pattern),
   never an in-place dataset rewrite (PCM-T-02).
   Admitted N is MEASURED, not asserted (it has never been fixed as a code
   assertion). Degenerate-result guard emits WARNINGs but does not abort --
   it is a finding to report, and the QC file must still be written.
   ========================================================================= */

%put NOTE: ==== SECTION 2 -- Deriving g.analytic_cohort (INPATIENT+OBSERVATION) ====;

data g.analytic_cohort;
  set g.master_data_merged;
  where upcase(strip(Patient_Type)) in ('INPATIENT','OBSERVATION');
run;

proc sql noprint;
  select count(*) into :n_admitted trimmed
  from g.analytic_cohort;
quit;

%put NOTE: Admitted-patient N (INPATIENT+OBSERVATION) = &n_admitted;

%macro guard_admitted_n;
  %if &n_admitted = 0 %then %do;
    %put WARNING: Admitted N is zero -- the Patient_Type filter matched no rows.;
    %put WARNING: Possible cause: unexpected Patient_Type values (check SECTION 1 PROC FREQ).;
    %put WARNING: QC file will still be written. Investigate before proceeding.;
  %end;
  %else %if &n_admitted = &n_merged %then %do;
    %put WARNING: Admitted N equals merged N (&n_admitted = &n_merged).;
    %put WARNING: The INPATIENT/OBSERVATION filter may have matched all rows.;
    %put WARNING: Check SECTION 1 PROC FREQ for Patient_Type values present in the data.;
    %put WARNING: QC file will still be written. Investigate before proceeding.;
  %end;
  %else %do;
    %put NOTE: Admitted N (&n_admitted) is a proper subset of merged N (&n_merged). Filter appears correct.;
  %end;
%mend guard_admitted_n;
%guard_admitted_n;


/* =========================================================================
   SECTION 3: Missingness profile on both datasets (PCM-F-11)
   =========================================================================
   PROC MEANS on g.master_data_merged then g.analytic_cohort.
   PROC FREQ on g.analytic_cohort confirms only the two intended values survive.
   Within-cohort complete-case Ns are MEASURED (not asserted -- they have
   never been observed; Pitfall 2 and Open Question 3).
   ODS LISTING is still open; closed at the end of this section.
   ========================================================================= */

%put NOTE: ==== SECTION 3 -- Missingness profile ====;

proc means data=g.master_data_merged n nmiss;
  var Admit_BMI Cognitive_Score Frailty_Score Age_at_Encounter;
  ods output Summary=work.miss_profile;
  title "Missingness profile: g.master_data_merged (all 41150 rows)";
run;
title;

proc means data=g.analytic_cohort n nmiss;
  var Admit_BMI Cognitive_Score Frailty_Score Age_at_Encounter;
  ods output Summary=work.miss_profile_cohort;
  title "Missingness profile: g.analytic_cohort (admitted rows only, N=&n_admitted)";
run;
title;

proc freq data=g.analytic_cohort;
  tables Patient_Type / missing;
  title "Patient_Type distribution in g.analytic_cohort (post-filter) -- confirms only INPATIENT and OBSERVATION survive";
run;
title;

/* Measure within-cohort complete-case Ns (SECTION 3 measurement, not assertion) */
proc sql noprint;
  select count(*) into :n_bmi_cohort  trimmed
  from g.analytic_cohort
  where Admit_BMI is not missing;

  select count(*) into :n_cog_cohort  trimmed
  from g.analytic_cohort
  where Cognitive_Score is not missing;

  select count(*) into :n_frl_cohort  trimmed
  from g.analytic_cohort
  where Frailty_Score is not missing;

  select count(*) into :n_all3_cohort trimmed
  from g.analytic_cohort
  where Admit_BMI is not missing
    and Cognitive_Score is not missing
    and Frailty_Score is not missing;
quit;

%put NOTE: Within-cohort complete-case Ns (measured, not asserted):;
%put NOTE:   Admit_BMI     = &n_bmi_cohort of &n_admitted admitted rows;
%put NOTE:   Cognitive_Score = &n_cog_cohort of &n_admitted admitted rows;
%put NOTE:   Frailty_Score   = &n_frl_cohort of &n_admitted admitted rows;
%put NOTE:   All three       = &n_all3_cohort of &n_admitted admitted rows;

/* BMI availability percentages -- explicit direction (HAVE vs LACK); Pitfall 6 */
%macro bmi_pct;
  %global pct_bmi_have pct_bmi_lack;
  %if &n_admitted = 0 %then %do;
    %let pct_bmi_have = NA;
    %let pct_bmi_lack = NA;
    %put WARNING: Admitted N is zero -- BMI percentages not computable.;
  %end;
  %else %do;
    %let pct_bmi_have = %sysfunc(putn(%sysevalf(100 * &n_bmi_cohort / &n_admitted), 5.1));
    %let pct_bmi_lack = %sysfunc(putn(%sysevalf(100 - (100 * &n_bmi_cohort / &n_admitted)), 5.1));
  %end;
%mend bmi_pct;
%bmi_pct;

%put NOTE: Of &n_admitted admitted rows: &pct_bmi_have pct HAVE non-missing Admit_BMI (pct_admitted_HAVE_bmi=&pct_bmi_have);
%put NOTE: Of &n_admitted admitted rows: &pct_bmi_lack pct LACK Admit_BMI (pct_admitted_LACK_bmi=&pct_bmi_lack);

/* Close ODS LISTING before any further data _null_ appends (Pitfall 7) */
ods listing close;


/* =========================================================================
   SECTION 4: Assert complete-case Ns against g.master_data_merged (PCM-F-11)
   =========================================================================
   The four known Ns were derived from the full 41,150-row merged file.
   %local actual prevents stale-macro-variable pass on PROC SQL failure (Pitfall 9).
   Do NOT assert the within-cohort counts -- they have never been observed.
   ========================================================================= */

%put NOTE: ==== SECTION 4 -- Asserting complete-case Ns against g.master_data_merged ====;

%macro assert_complete_case_n(dsn=, var=, expected=, label=);
  %local actual;
  proc sql noprint;
    select count(*) into :actual trimmed
    from &dsn
    where &var is not missing;
  quit;
  %if &actual ne &expected %then %do;
    %put ERROR: &label complete-case N = &actual, expected &expected;
    %abort cancel;
  %end;
  %put NOTE: &label complete-case N = &actual (assertion passed);
%mend assert_complete_case_n;

%assert_complete_case_n(dsn=g.master_data_merged, var=Admit_BMI,       expected=12726, label=Admit_BMI);
%assert_complete_case_n(dsn=g.master_data_merged, var=Cognitive_Score, expected=20540, label=Cognitive_Score);
%assert_complete_case_n(dsn=g.master_data_merged, var=Frailty_Score,   expected=23311, label=Frailty_Score);

%macro assert_all_three;
  %local actual_all;
  proc sql noprint;
    select count(*) into :actual_all trimmed
    from g.master_data_merged
    where Admit_BMI is not missing
      and Cognitive_Score is not missing
      and Frailty_Score is not missing;
  quit;
  %if &actual_all ne 6523 %then %do;
    %put ERROR: All-three complete-case N = &actual_all, expected 6523;
    %abort cancel;
  %end;
  %put NOTE: All-three complete-case N = &actual_all (assertion passed);
%mend assert_all_three;
%assert_all_three;


/* =========================================================================
   SECTION 5: md3-owns missingness trade-off note (PCM-D-11)
   =========================================================================
   Verified for the three primary analysis variables only. Not a global claim.
   Written to both the log and the QC file.
   ========================================================================= */

%put NOTE: ==== SECTION 5 -- md3-owns missingness trade-off documentation ====;

%put NOTE: Admit_BMI: 28424 of 41150 missing. Verified unrecoverable from all 7 other sources (PCM-F-07, PCM-D-11).;
%put NOTE: Cognitive_Score: missing values verified unrecoverable from md5, md6 (PCM-D-11).;
%put NOTE: Frailty_Score: missing values verified unrecoverable from md5, md6 (PCM-D-11).;
%put NOTE: Other md3-owned variables: md3-owns missingness has NOT been verified beyond these three.;
%put NOTE: Do not state md3-owns missingness as a global property.;

data _null_;
  file "&qc_path.\07_cohort_missingness.txt" mod;
  put " ";
  put "=== SECTION 5: md3-owns missingness trade-off (PCM-D-11) ===";
  put "Admit_BMI: 28424 of 41150 missing.";
  put "  Verified unrecoverable from all 7 other sources (PCM-F-07, PCM-D-11).";
  put "Cognitive_Score: missing values verified unrecoverable from md5, md6 (PCM-D-11).";
  put "Frailty_Score: missing values verified unrecoverable from md5, md6 (PCM-D-11).";
  put "Other md3-owned variables: md3-owns missingness has NOT been verified beyond these three.";
  put "Do not state md3-owns missingness as a global property.";
run;


/* =========================================================================
   SECTION 6: Write summary to QC file and close
   =========================================================================
   Appends via: data _null_; file "..." mod;
   NOT a reopened ODS LISTING destination (which would truncate everything above).
   Every N is labelled with its denominator so the file is grep-able.
   ========================================================================= */

%put NOTE: ==== SECTION 6 -- Writing QC summary ====;

data _null_;
  file "&qc_path.\07_cohort_missingness.txt" mod;
  put " ";
  put "=== SECTION 6: Summary (grep-able key=value lines) ===";
  put "merged_n=&n_merged";
  put "admitted_n=&n_admitted";
  put "BMI_complete_case_n_merged=12726 (assertion passed)";
  put "Cognitive_complete_case_n_merged=20540 (assertion passed)";
  put "Frailty_complete_case_n_merged=23311 (assertion passed)";
  put "all_three_complete_case_n_merged=6523 (assertion passed)";
  put "BMI_complete_case_n_cohort=&n_bmi_cohort (measured, not asserted)";
  put "Cognitive_complete_case_n_cohort=&n_cog_cohort (measured, not asserted)";
  put "Frailty_complete_case_n_cohort=&n_frl_cohort (measured, not asserted)";
  put "all_three_complete_case_n_cohort=&n_all3_cohort (measured, not asserted)";
  put "pct_admitted_HAVE_bmi=&pct_bmi_have";
  put "pct_admitted_LACK_bmi=&pct_bmi_lack";
  put " ";
  put "g.analytic_cohort created with admitted_n=&n_admitted rows.";
  put "All four complete-case Ns asserted against g.master_data_merged. Assertions passed.";
run;

%put NOTE: 07_cohort.sas complete -- see qc/07_cohort_missingness.txt;

proc printto;
run;
