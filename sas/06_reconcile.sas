/* Program: 06_reconcile.sas
   Phase   : 6 -- Variable Reconciliation
   Purpose : Read-only QC program over g.master_data_merged. Confirms the 16 deliberately-
             separate columns are present (D-01, D-02, D-03), counts the Emergent
             distribution (D-04), documents the rt_envelope_flag distribution (MRG-05),
             spot-checks that the deliberate columns are populated (not just present),
             and writes a committed prose QC summary to qc/06_reconcile_summary.txt.
   Requirements: D-01, D-02, D-03, D-04, MRG-05, REC-01, REC-02, REC-03, REC-04
   Author  : Executor (Phase 6 Plan 02)
   Created : 2026-08-27
   PCM violations avoided:
     PCM-T-01: no PROC SQL UPDATE
     PCM-T-02: no data X; set X;
     PCM-T-11: every numeric comparison guarded with IS NOT MISSING
     PCM-R-05: every %abort cancel is inside a named %macro definition
     All counts use SELECT COUNT(*) INTO :macvar TRIMMED (never &SQLOBS)
   NOTE: This program MODIFIES NO DATASET. It reads g.master_data_merged (read-only)
         and writes only qc/06_reconcile_summary.txt. It does NOT call any prep program.
*/

/* =========================================================================
   SECTION 0: Options, paths, libname, preconditions
   =========================================================================
   g_path, logs_path and qc_path all live under the P: merge tree, consistent
   with all prior phases (copied from sas/05_qc_merge.sas SECTION 0).
   ========================================================================= */
options nodate nonumber ps=max ls=200;
%let g_path    = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge;
%let logs_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs;
%let qc_path   = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc;
libname g "&g_path";

%put NOTE: ==== Phase 6 Variable Reconciliation starting -- read-only QC over g.master_data_merged ====;

/* 0a: g library resolves */
%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: PRECONDITION -- LIBNAME &lib could not be assigned. Check g_path.;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- LIBNAME &lib resolved.;
%mend check_libname;
%check_libname(lib=g);

/* 0b: qc_path directory exists */
%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: PRECONDITION -- &label directory missing: &path;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- &label directory found: &path;
%mend check_dir;
%check_dir(path=&qc_path, label=qc);

/* 0c: g.master_data_merged exists */
proc sql noprint;
  select count(*) into :n_tab trimmed
  from dictionary.tables
  where libname='G' and upcase(memname)='MASTER_DATA_MERGED';
quit;

%macro check_merged;
  %if &n_tab ne 1 %then %do;
    %put ERROR: PRECONDITION -- g.master_data_merged not found. Run Phase 4 and Phase 5 first.;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- g.master_data_merged present.;
%mend check_merged;
%check_merged;

/* 0d: Open the QC summary and write a header (FILE, not MOD -- starts fresh) */
filename outref "&qc_path.\06_reconcile_summary.txt";
data _null_;
  file outref;
  put "06_reconcile_summary -- Run: %sysfunc(datetime(), datetime20.)";
  put "Phase 6 Variable Reconciliation -- read-only QC over g.master_data_merged";
  put "===========================================================================";
run;
filename outref clear;


/* =========================================================================
   SECTION 1: Column presence checks (D-01, D-02, D-03, D-04, MRG-05)
   Uses dictionary.columns with libname='G' and upcase(memname)='MASTER_DATA_MERGED'.
   %macro assert_col aborts loudly on absence -- that is a real finding, not a defect.
   Each %put on success contains "PASS" so `grep -c "PASS" logs/06_reconcile.log`
   returns at least 18.
   ========================================================================= */

%macro assert_col(lib=, dsn=, col=, label=);
  %local n;
  proc sql noprint;
    select count(*) into :n trimmed
    from dictionary.columns
    where libname = upcase("&lib")
      and upcase(memname) = upcase("&dsn")
      and upcase(name) = upcase("&col");
  quit;
  %if &n = 0 %then %do;
    %put ERROR: &label -- &col absent from &lib..&dsn -- PRESENCE CHECK FAILED;
    %abort cancel;
  %end;
  %else %put NOTE: &label PASS -- &col present in &lib..&dsn;
%mend assert_col;

/* D-01: Mortality columns (PCM-D-01 -- keep separate) */
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Death_Date_Y_N, label=REC-01/D-01);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=IsDead_Y_N,     label=REC-01/D-01);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Death,          label=REC-01/D-01);

/* D-02: Frailty char columns (md7-owned, PCM-D-02 -- keep separate) */
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Feels_Exausted,          label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Low_Physical_Activity,   label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Slow_Walking_Speed,      label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Unintended_Weight_Loss,  label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Week_Grip_Strength,      label=REC-02/D-02);

/* D-02: Frailty numeric columns (md3/md5-owned, PCM-D-02 -- keep separate) */
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Feels_Exausted_Value,         label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Low_Physical_Activity_Value,  label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Slow_Walking_Speed_Value,     label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Unintended_Weight_Loss_Value, label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Week_Grip_Strength_Value,     label=REC-02/D-02);

/* D-03: ISO_SEV columns (PCM-D-03 -- keep separate; md8's is a TOTAL not an average) */
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=ISO_SEV_Exp_IntraOp_MAC_Average, label=REC-03/D-03);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=ISO_SEV_IntraOp_MAC_Average,     label=REC-03/D-03);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=ISO_SEV_MAC_TOTAL_Exp,           label=REC-03/D-03);

/* D-04: Emergent (retained despite rarity, PCM-D-04) */
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Emergent,        label=REC-04/D-04);

/* MRG-05: rt_envelope_flag (derived flag for 9 envelope-violating rows, PCM-D-08) */
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=rt_envelope_flag, label=MRG-05);

%put NOTE: SECTION 1 complete -- all 18 column presence checks passed.;

/* Write SECTION 1 result to summary */
data _null_;
  file "&qc_path.\06_reconcile_summary.txt" mod;
  put " ";
  put "SECTION 1 -- Column presence (18 checks)";
  put "-----------------------------------------";
  put "Column presence: 16 deliberate columns + Emergent + rt_envelope_flag all PASS";
  put "  D-01 (mortality, 3 cols):     Death_Date_Y_N  IsDead_Y_N  Death";
  put "  D-02 (frailty char, 5 cols):  Feels_Exausted  Low_Physical_Activity";
  put "                                Slow_Walking_Speed  Unintended_Weight_Loss";
  put "                                Week_Grip_Strength";
  put "  D-02 (frailty num, 5 cols):   Feels_Exausted_Value  Low_Physical_Activity_Value";
  put "                                Slow_Walking_Speed_Value  Unintended_Weight_Loss_Value";
  put "                                Week_Grip_Strength_Value";
  put "  D-03 (ISO_SEV, 3 cols):       ISO_SEV_Exp_IntraOp_MAC_Average";
  put "                                ISO_SEV_IntraOp_MAC_Average";
  put "                                ISO_SEV_MAC_TOTAL_Exp  (md8 col is a TOTAL not an average)";
  put "  D-04 (Emergent):              Emergent";
  put "  MRG-05 (derived flag):        rt_envelope_flag";
run;


/* =========================================================================
   SECTION 2: Emergent counts (D-04 / REC-04)
   Emergent is CHARACTER $1 (md3-owned; Phase 4 LENGTH block). Values are Y/N/blank.
   NOT 1/0 -- using '1'/'0' returns 0 for both counts (PCM-F-06 established this).
   Guard applied: IS NOT MISSING before comparison (PCM-T-11).
   Report counts only; assert NOTHING (no expected value for the merged md3-owned column).
   ========================================================================= */
proc sql noprint;
  select sum(Emergent is not missing and upcase(Emergent) = 'Y') into :n_emergent_y    trimmed,
         sum(Emergent is not missing and upcase(Emergent) = 'N') into :n_emergent_n    trimmed,
         sum(missing(Emergent))                                  into :n_emergent_miss trimmed
  from g.master_data_merged;
quit;

%put NOTE: REC-04/D-04 -- Emergent: &n_emergent_y Y, &n_emergent_n N, &n_emergent_miss missing;

data _null_;
  file "&qc_path.\06_reconcile_summary.txt" mod;
  put " ";
  put "SECTION 2 -- Emergent distribution (D-04 / REC-04)";
  put "----------------------------------------------------";
  put "Emergent: &n_emergent_y Y / &n_emergent_n N / &n_emergent_miss missing";
  put "(Values are Y/N/blank -- NOT 1/0. Using '1'/'0' returns zero for both, PCM-F-06.)";
  put "No assertion on counts: the merged Emergent is md3-owned; its distribution";
  put "has not been separately measured. The 0.05% and 0.09% figures from DECISIONS.md";
  put "(PCM-D-04) are md1 and md8 SOURCE rates and do not describe this column.";
run;


/* =========================================================================
   SECTION 3: rt_envelope_flag distribution (MRG-05 / PCM-D-08)
   Guarded with IS NOT MISSING (PCM-T-11). Report both = 0 and = 1 counts.
   Do NOT assert n_flag1 = 9 -- this is a pipeline observation, not an invariant.
   (RESEARCH Pitfall 4; QC-06 already asserts zero UNFLAGGED violations.)
   ========================================================================= */
proc sql noprint;
  select sum(rt_envelope_flag = 0) into :n_flag0 trimmed,
         sum(rt_envelope_flag = 1) into :n_flag1 trimmed
  from g.master_data_merged
  where rt_envelope_flag is not missing;
quit;
/* observation, not an invariant -- see PCM-D-08 */

%put NOTE: MRG-05 -- rt_envelope_flag=0: &n_flag0, rt_envelope_flag=1: &n_flag1;

data _null_;
  file "&qc_path.\06_reconcile_summary.txt" mod;
  put " ";
  put "SECTION 3 -- rt_envelope_flag distribution (MRG-05 / PCM-D-08)";
  put "----------------------------------------------------------------";
  put "rt_envelope_flag: &n_flag0 at 0, &n_flag1 at 1 (flagged count is an observation, not asserted)";
  put "The 9 rows flagged in Phase 5 QC-06 carry operative sub-interval > room occupancy.";
  put "Each timestamp is individually plausible; only the combination is impossible.";
  put "PCM-D-08: flag, do not null. QC-06 asserts zero UNFLAGGED violations (passes).";
  put "A different flagged count is not a pipeline failure -- it is a data change worth reading.";
run;


/* =========================================================================
   SECTION 3b: Populated check for the six deliberate columns
   REPORT ONLY -- no assertion. Presence confirms a column EXISTS; it does not
   confirm that anything landed in it. A broken keep list or stale merge produces
   a column that is present and entirely missing. SECTION 1 cannot see this.
   A count of 0 on any of these is a real finding -- flag loudly in summary.
   ========================================================================= */
proc sql noprint;
  select sum(Death_Date_Y_N      is not missing) into :n_pop_dd  trimmed,
         sum(IsDead_Y_N          is not missing) into :n_pop_id  trimmed,
         sum(Death               is not missing) into :n_pop_dt  trimmed,
         sum(Feels_Exausted      is not missing) into :n_pop_fe  trimmed,
         sum(Feels_Exausted_Value is not missing) into :n_pop_fev trimmed,
         sum(ISO_SEV_MAC_TOTAL_Exp is not missing) into :n_pop_iso trimmed
  from g.master_data_merged;
quit;

%put NOTE: Populated check -- Death_Date_Y_N: &n_pop_dd  IsDead_Y_N: &n_pop_id  Death: &n_pop_dt;
%put NOTE: Populated check -- Feels_Exausted: &n_pop_fe  Feels_Exausted_Value: &n_pop_fev  ISO_SEV_MAC_TOTAL_Exp: &n_pop_iso;

data _null_;
  file "&qc_path.\06_reconcile_summary.txt" mod;
  put " ";
  put "SECTION 3b -- Populated counts for spot-checked deliberate columns (report only, no assertion)";
  put "----------------------------------------------------------------------------------------------";
  put "A count of 0 means the column landed empty -- the keep-separate resolution did not take.";
  put "Presence alone (SECTION 1) cannot detect this. A zero here is a real finding.";
  put " ";
  put "  Death_Date_Y_N       non-missing: &n_pop_dd  (rough expectation: ~41150, md3-owned)";
  put "  IsDead_Y_N           non-missing: &n_pop_id  (rough expectation: ~9462,  md6-owned)";
  put "  Death                non-missing: &n_pop_dt  (rough expectation: ~9215,  md7-owned)";
  put "  Feels_Exausted       non-missing: &n_pop_fe  (rough expectation: ~9215,  md7-owned char)";
  put "  Feels_Exausted_Value non-missing: &n_pop_fev (rough expectation: ~41150, md3-owned num)";
  put "  ISO_SEV_MAC_TOTAL_Exp non-missing: &n_pop_iso (rough expectation: ~22473, md8-owned)";
run;


/* =========================================================================
   SECTION 4: PCM-D-10 confirmation note (read-only)
   Anchor-offset variables (rt_ANCHOR_to_ADMIT_days, rt_ANCHOR_to_SURGERY_days,
   rt_ANCHOR_to_DISCHG_days) legitimately carry negative values. A negative offset
   means the event preceded the anchor date -- this is meaningful, not an error.
   These variables were NOT nulled by PREP-08. DO NOT add them to PREP-08.
   Resolved: docs/DECISIONS.md PCM-D-10. No data modification in this section.
   ========================================================================= */
%put NOTE: PCM-D-10 -- rt_ANCHOR_to_*_days negatives are legitimate offsets, not nulled.;

data _null_;
  file "&qc_path.\06_reconcile_summary.txt" mod;
  put " ";
  put "SECTION 4 -- PCM-D-10: anchor-offset variables (read-only note)";
  put "----------------------------------------------------------------";
  put "PCM-D-10: anchor-offset rt_ANCHOR_to_*_days negatives are legitimate, not nulled.";
  put "  rt_ANCHOR_to_ADMIT_days, rt_ANCHOR_to_SURGERY_days, rt_ANCHOR_to_DISCHG_days";
  put "  are date offsets from an anchor date, not durations. A negative value means the";
  put "  event preceded the anchor, which is clinically meaningful.";
  put "  PREP-08 does NOT null these variables. Do not add them to PREP-08.";
  put "  Cross-reference: docs/DECISIONS.md PCM-D-10.";
run;


/* =========================================================================
   SECTION 5: Emergent caveat and close-out
   ========================================================================= */
data _null_;
  file "&qc_path.\06_reconcile_summary.txt" mod;
  put " ";
  put "SECTION 5 -- Emergent caveat and close-out";
  put "------------------------------------------";
  put "Emergent caveat (PCM-D-04): the merged value is md3-owned. At source, md1 and md8";
  put "showed 0.05% and 0.09% Y with matching blank shares -- consistent with a field";
  put "clinicians rarely complete rather than a true emergency rate. Patient_Type and";
  put "Admit_Source are likely better urgency proxies. Do not model on Emergent without";
  put "checking the observed rate above first.";
  put " ";
  put "===========================================================================";
  put "Phase 6 Variable Reconciliation QC complete.";
  put "  16 deliberate columns + Emergent + rt_envelope_flag: all presence checks PASSED.";
  put "  Emergent distribution: see SECTION 2 above.";
  put "  rt_envelope_flag distribution: see SECTION 3 above.";
  put "  Populated counts: see SECTION 3b above.";
  put "  PCM-D-10 anchor-offset note: see SECTION 4 above.";
  put "  No dataset was modified by this program.";
  put "===========================================================================";
run;

%put NOTE: ==== Phase 6 Variable Reconciliation QC complete -- 06_reconcile_summary.txt written ====;
