/* Program: 05_qc_merge.sas
   Phase   : 5 -- Merge QC
   Purpose : Post-merge QC sentinel over g.master_data_merged (produced by Phase 4).
             Independent second-program assertions: QC-01 row count, QC-02 character
             variable widths, QC-03 NULL string scan, QC-04 md8-only block scoping,
             QC-05 clinical ranges for type-converted numerics.
             Aborts loudly on any failure; writes qc/05_qc_merge_report.txt progressively
             so partial output survives an abort.
   Requirements: QC-01, QC-02, QC-03, QC-04, QC-05
   Author  : Executor (Phase 5 Plan 01)
   Created : 2026-08-26
   PCM violations avoided:
     PCM-T-01: no PROC SQL UPDATE
     PCM-T-02: no data X; set X;
     PCM-R-05: every %abort cancel is inside a named %macro definition
     All counts use SELECT COUNT(*) INTO :macvar TRIMMED (never the automatic SQL counter)
   NOTE: This program is STANDALONE. It defines its own %assert_eq macro and does
         NOT sourced from sas/04_merge.sas -- macros do not persist across SAS sessions.
*/

/* =========================================================================
   SECTION 0: Options, paths, libname, %assert_eq macro
   =========================================================================
   g_path and logs_path are copied VERBATIM from sas/04_merge.sas SECTION 0
   so libname g resolves to the same g.master_data_merged location (RESEARCH Pitfall 7).
   qc_path points to the repo qc/ folder on C: -- the QC report is a committed
   repo artifact (mirrors how qc/04_merge_provenance.txt was committed).
   ========================================================================= */
options nodate nonumber ps=max ls=200;
%let g_path    = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge;
%let logs_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs;
%let qc_path   = C:\Master_Renamed_same_format_accross\qc;
libname g "&g_path";

/* PCM-R-05: %abort cancel must live inside a named macro definition. Copied verbatim from
   sas/04_merge.sas so 05_qc_merge.sas is independently runnable without sourcing 04_merge.sas). */
%macro assert_eq(actual=, expected=, label=);
  %if &actual ne &expected %then %do;
    %put ERROR: QC ASSERTION FAILED -- &label: expected &expected got &actual;
    %abort cancel;
  %end;
  %else %put NOTE: QC ASSERTION OK -- &label = &actual;
%mend assert_eq;

%put NOTE: ==== Phase 5 QC starting -- post-merge sentinel over g.master_data_merged ====;

/* =========================================================================
   SECTION 1: Preconditions
   All %abort cancel calls are inside named %macro definitions (PCM-R-05).
   ========================================================================= */

/* 1a: g library resolves */
%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: QC PRECONDITION -- LIBNAME &lib could not be assigned. Check g_path.;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- LIBNAME &lib resolved.;
%mend check_libname;
%check_libname(lib=g);

/* 1b: qc_path directory exists */
%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: QC PRECONDITION -- &label directory missing: &path;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- &label directory found: &path;
%mend check_dir;
%check_dir(path=&qc_path, label=qc);

/* 1c: g.master_data_merged exists */
proc sql noprint;
  select count(*) into :n_tab trimmed
  from dictionary.tables
  where libname='G' and upcase(memname)='MASTER_DATA_MERGED';
quit;

%macro check_merged;
  %if &n_tab ne 1 %then %do;
    %put ERROR: QC PRECONDITION -- g.master_data_merged not found. Run Phase 4 first.;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- g.master_data_merged present.;
%mend check_merged;
%check_merged;

/* 1d: qclib.ownership_map exists (gitignored .sas7bdat; must be present from Phase 2 run).
   Fails here with a clear message rather than silently at the PROC SQL in Section 4,
   which would produce a confusing "table not found" error mid-QC. */
libname qclib "&qc_path";

proc sql noprint;
  select count(*) into :n_owmap trimmed
  from dictionary.tables
  where libname='QCLIB' and upcase(memname)='OWNERSHIP_MAP';
quit;

%macro check_owmap;
  %if &n_owmap ne 1 %then %do;
    %put ERROR: QC PRECONDITION -- qclib.ownership_map not found at &qc_path..;
    %put ERROR- This dataset is a Phase 2 artifact (.sas7bdat) excluded from git (PCM-C-03).;
    %put ERROR- It must be present on the machine that ran Phase 2. Section 4 cannot run.;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- qclib.ownership_map present.;
%mend check_owmap;
%check_owmap;

/* 1f: Open the report and write a header.
   This is the FIRST write -- use FILE (not MOD) to start fresh (RESEARCH Pitfall 6).
   After this, every subsequent write uses FILE ... MOD. */
filename qcrep "&qc_path.\05_qc_merge_report.txt";
data _null_;
  file qcrep;
  put "05_qc_merge_report -- Run: %sysfunc(datetime(), datetime20.)";
  put "Post-merge QC over g.master_data_merged";
  put "=============================================================";
run;
filename qcrep clear;

/* =========================================================================
   SECTION 2: QC-01 (row count) and QC-02 (character variable widths)
   ========================================================================= */

/* --- QC-01: Independent row-count assertion (RESEARCH: independent second program) --- */
proc sql noprint;
  select count(*) into :n_merged trimmed from g.master_data_merged;
quit;
%assert_eq(actual=&n_merged, expected=41150, label=QC-01 merged row count);

data _null_;
  file "&qc_path.\05_qc_merge_report.txt" mod;
  put "QC-01 merged row count: &n_merged (expected 41150)";
run;

/* --- QC-02: Character variable owner-width check ---
   Build the OWNER-width reference table fully enumerated from qc/03_charvars_all.txt
   filtered to each variable's resolved owner (OWNER width, NOT cross-source max).
   Owner rule: md3 wins if it carries the var, else highest-row-count source;
   five frailty-component flags (Feels_Exausted, Low_Physical_Activity, Slow_Walking_Speed,
   Unintended_Weight_Loss, Week_Grip_Strength) override to md7 on the width signal ($3).
   RESEARCH Pitfall 3: Emergent is md3 $1 (NOT md8 $4).
   NOTE: PRECEDE_Study_ID_1 and ISO_SEV_Exp_IntraOp_MAC_Average are NOT in this list;
         PRECEDE_Study_ID_1 was dropped in PREP-04 and ISO_SEV_Exp_IntraOp_MAC_Average
         is NUMERIC in the merged file (type-converted in Phase 3).
*/
proc sql noprint;
  create table work.expected_widths (varname char(32), expected_len num, owner char(4));
  insert into work.expected_widths
    values ('PRECEDE_STUDY_ID',                 12, 'key')
    values ('ENCRYPTED_MRN',                    40, 'md3')
    values ('ENCRYPTED_ENCOUNTER',              49, 'md3')
    values ('Day_of_Week__CHAR_',                3, 'md3')
    values ('Holidays',                          1, 'md3')
    values ('Weekend_Indicator',                 1, 'md3')
    values ('EmployeeStatus',                   23, 'md3')
    values ('Education',                        19, 'md3')
    values ('Race',                             16, 'md3')
    values ('Ethnicity',                        15, 'md3')
    values ('Sex',                               6, 'md3')
    values ('Marital_Status',                   22, 'md3')
    values ('Service',                          32, 'md3')
    values ('Room_Type',                        22, 'md3')
    values ('Emergent',                          1, 'md3')
    values ('Base_Procedure_1',                199, 'md3')
    values ('Base_Procedure_Code_1',            10, 'md3')
    values ('CPT_1',                             8, 'md3')
    values ('CPT_1_Description',                75, 'md3')
    values ('CPT1_Label',                       96, 'md3')
    values ('Patient_Type',                     18, 'md3')
    values ('Payer',                            12, 'md3')
    values ('ICD10_Principal_Diagnosis_Desc',   60, 'md3')
    values ('ICD10_Principal_Diagnosis',         7, 'md3')
    values ('ICD10_Principal_Diagnosis_POA',     6, 'md6')
    values ('Intraop_Ketamine',                  1, 'md3')
    values ('Preop_block',                       1, 'md3')
    values ('Admit_Source',                     40, 'md3')
    values ('Dischg_Disposition',               43, 'md3')
    values ('_30_DAY_MORTALITY',                 1, 'md1')
    values ('Death_Date_Y_N',                    1, 'md3')
    values ('SSDI_Death_Date_Y_N',               1, 'md3')
    values ('Anesthesia_Type',                  33, 'md3')
    values ('Sleep_Apnea_YN',                    1, 'md3')
    values ('Diabetes_YN',                       1, 'md3')
    values ('Hyperlipidemia_YN',                 1, 'md3')
    values ('Hypertension_YN',                   1, 'md3')
    values ('MovementDisorder_YN',               1, 'md3')
    values ('CognitiveDisorder_YN',              1, 'md3')
    values ('Cognitive_Category',               22, 'md3')
    values ('Frailty_Category',                 24, 'md3')
    values ('Feels_Exausted',                    3, 'md7')
    values ('Low_Physical_Activity',             3, 'md7')
    values ('Slow_Walking_Speed',                3, 'md7')
    values ('Unintended_Weight_Loss',            3, 'md7')
    values ('Week_Grip_Strength',                3, 'md7')
    /* PCM-D-01 death-naming variants -- carried through UNRECONCILED pending Erin's
       sign-off (Phase 6). All three are $1 character columns in the merged file and
       MUST have reference rows or the QC-02 completeness guard aborts.            */
    values ('IsDead_Y_N',                        1, 'md6')
    values ('Death',                             1, 'md7')
    values ('SSDI_Death',                        1, 'md7')
    values ('SSDI_Death_Y_N',                    1, 'md4')
    /* md4/md5 comorbidity naming variants -- the non-_YN spellings. Also unreconciled
       (the _YN forms above are md3-owned; these are the md4/md5 names).            */
    values ('Sleep_Apnea',                       1, 'md4')
    values ('Diabetes',                          1, 'md4')
    values ('Hyperlipidemia',                    1, 'md4')
    values ('Hypertension',                      1, 'md4')
    values ('MovementDisorder',                  1, 'md4')
    values ('Cognitive_Disorder',                1, 'md4')
  ;
quit;

/* QC-02 Step A: PROC CONTENTS on merged dataset to get actual character lengths */
proc contents data=g.master_data_merged out=work.qc5_cols(keep=name length type) noprint; run;

/* QC-02 Step B: Completeness guard -- flag any character variable in the merged file
   that is MISSING from the reference table. An owner-resolution edge case or a newly
   added variable that was not added to this reference table will abort here. */
proc sql noprint;
  select count(*) into :n_uncovered trimmed
  from work.qc5_cols c
  where c.type = 2
    and upcase(c.name) not in (select upcase(varname) from work.expected_widths);
quit;
%assert_eq(actual=&n_uncovered, expected=0, label=QC-02 character variables missing from width reference);

/* QC-02 Step C: Truncation check -- find character variables where actual length < owner width */
proc sql noprint;
  create table work.width_check as
    select e.varname, e.expected_len, e.owner, c.length as actual_len
    from work.expected_widths e
    inner join work.qc5_cols c
      on upcase(e.varname) = upcase(c.name) and c.type = 2
    where c.length < e.expected_len;
  select count(*) into :n_truncated trimmed from work.width_check;
quit;
%assert_eq(actual=&n_truncated, expected=0, label=QC-02 truncated character variables);

data _null_;
  file "&qc_path.\05_qc_merge_report.txt" mod;
  put "QC-02 char vars missing from width reference: &n_uncovered (expected 0)";
  put "QC-02 truncated character variables: &n_truncated (expected 0)";
run;

/* =========================================================================
   SECTION 3: QC-03 -- NULL string scan across ALL character variables
   (Not the md8-scoped scan Phase 4 used -- this is broader: RESEARCH Pitfall 1)
   ========================================================================= */
data _null_;
  set g.master_data_merged end=eof;
  retain _n_null 0;
  array _c {*} _CHARACTER_;
  do _i = 1 to dim(_c);
    if strip(upcase(_c{_i})) = 'NULL' then _n_null + 1;
  end;
  drop _i;
  if eof then call symputx('n_null_all', _n_null, 'G');
run;
%assert_eq(actual=&n_null_all, expected=0, label=QC-03 NULL strings in any character variable);

data _null_;
  file "&qc_path.\05_qc_merge_report.txt" mod;
  put "QC-03 NULL strings in any character variable: &n_null_all (expected 0)";
run;

/* =========================================================================
   SECTION 4: QC-04 -- md8-only block scoping
   Verifies that every md8-OWNED variable (SET B: ABP_*, BIS_INDEX_*, NIBP_*, SD_*,
   AVG_*, pressor/Total_* block, ISO_SEV_MAC_TOTAL_Exp) is non-missing ONLY within
   md8 rows (in_md8=1). Non-missing count outside md8 (in_md8=0) must be zero.

   CRITICAL: QC-04 covers SET B (md8-only single-source variables), NOT SET A
   (the eight PREP-03 conversion targets that md3 owns across all 41,150 rows).
   Running QC-04 against Admit_BMI, Age_at_Encounter, etc. would fail by ~16,000 rows
   because md3 owns those variables and populates them for all sources.

   The md8-owned variable list is DERIVED at run time from qclib.ownership_map so it
   stays correct if Phase 2 or Phase 4 ownership assignments change. The expected set
   is ~20 variables: ABP_*, BIS_INDEX_*, NIBP_*, SD_*, AVG_*, Total_* pressors/meds,
   ISO_SEV_MAC_TOTAL_Exp. A large discrepancy vs this expectation signals an ownership
   map owner-column mismatch.

   in_md8 = 1 rows = 22,473 (from qc/04_merge_provenance.txt committed).
   qclib assigned in Section 1 preconditions (ownership_map presence already verified).
   ========================================================================= */
proc sql noprint;
  select name into :md8_only separated by ' '
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED'
    and upcase(name) in (select upcase(varname) from qclib.ownership_map
                         where upcase(owner) = 'MD8');

  select count(*) into :n_md8_only trimmed
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED'
    and upcase(name) in (select upcase(varname) from qclib.ownership_map
                         where upcase(owner) = 'MD8');
quit;

%macro check_md8_list;
  %if &n_md8_only = 0 %then %do;
    %put ERROR: QC-04 -- no md8-owned variables found. Check the ownership map owner column.;
    %abort cancel;
  %end;
  %else %if &n_md8_only > 30 %then %do;
    %put ERROR: QC-04 -- &n_md8_only md8-owned variables found; expected roughly 20.;
    %put ERROR- This filter reads the Phase 2 `owner` column, where multi-source variables;
    %put ERROR- carry the literal CONFLICT. If resolved owners (owner_resolved) were written;
    %put ERROR- back to the map, md8 would silently pick up additional variables and QC-04;
    %put ERROR- would widen beyond the md8-only block. Confirm which column to read.;
    %abort cancel;
  %end;
  %else %put NOTE: QC-04 -- &n_md8_only md8-owned variables to check: &md8_only;
%mend check_md8_list;
%check_md8_list;

/* Membership check on the derived list. This REPLACES the duplicate spot-check
   assertions an earlier version placed after the loop: those re-asserted eight
   variables the loop had already covered, which broke the validation gate
   (QC-04 OK count must equal &n_md8_only) and cost eight extra full-table passes.
   Static auditability of the eight representative names is preserved here, and this
   macro adds NO assertions to the QC-04 count. */
%macro check_md8_expected;
  %local i v missing;
  %let missing = 0;
  %do i = 1 %to 8;
    %let v = %scan(ABP_LESS_THAN_60_COUNT BIS_INDEX_LESS_30_COUNT NIBP_LESS_60_COUNT
                   SD_ABP_Mean AVG_ABP_Mean Total_Midazolam_mg
                   Total_Phenylephrine_HCl_Pressors ISO_SEV_MAC_TOTAL_Exp, &i);
    %if %sysfunc(indexw(%upcase(&md8_only), %upcase(&v))) = 0 %then %do;
      %put ERROR: QC-04 -- expected md8-owned variable &v absent from the derived list.;
      %let missing = %eval(&missing + 1);
    %end;
  %end;
  %if &missing > 0 %then %do;
    %put ERROR: QC-04 -- &missing of 8 representative md8-owned variables missing.;
    %put ERROR- The ownership map and the merged file have drifted apart.;
    %abort cancel;
  %end;
  %else %put NOTE: QC-04 -- all eight representative md8-owned variables present in the derived list.;
%mend check_md8_expected;
%check_md8_expected;

/* QC-04 Part B: Abort assertion -- md8-owned var non-missing outside md8 rows must be zero */
%macro qc04_partB(var=);
  %local n_out;
  proc sql noprint;
    select count(*) into :n_out trimmed
    from g.master_data_merged where in_md8 = 0 and &var is not missing;
  quit;
  %assert_eq(actual=&n_out, expected=0, label=QC-04 &var non-missing outside md8 rows);
%mend qc04_partB;

%macro qc04_all;
  %local i v;
  %do i = 1 %to %sysfunc(countw(&md8_only));
    %let v = %scan(&md8_only, &i);
    %qc04_partB(var=&v);
  %end;
%mend qc04_all;
%qc04_all;

/* QC-04 Part A: INFORMATIONAL ONLY -- within-md8 non-missing counts with expected magnitudes.
   Design choice (BLOCKER 1 resolution): Part A is LOGGED, not asserted.
   The "exactly 22,473" reading is factually false for most of this block.
   Monitoring-derived columns (ABP_*, NIBP_*, BIS_*, SD_*, AVG_*) are populated only
   where the arterial-line or BIS monitor was in use -- typically 16-18% of md8 rows.
   Only the pressor/medication Total_* columns approach 22,473 (e.g., Total_Midazolam_mg).
   A LOW count here is NOT evidence of a conversion failure; it is clinically normal.

   Selected spot-check counts (from Phase 4 SAS log, human run 2026-08-26):
     Total_Midazolam_mg:         22,473  (100% of md8 rows)
     AVG_ABP_Mean:                4,005  (~18% -- arterial line cases only)
     BIS_INDEX_LESS_30_COUNT:     3,604  (~16% -- BIS monitor cases only)
     ABP_LESS_THAN_60_COUNT:      3,519  (~16% -- arterial line cases only)
*/
/* QC-04 Part A: eight spot-check counts -- INFORMATIONAL, NOT ASSERTED.
   Covers the key variables from each sub-group of SET B.
   Expected magnitudes: Total_* pressor/med columns ~100% of md8 rows (22,473);
   monitoring columns (ABP_*, NIBP_*, BIS_*, SD_*, AVG_*) ~16-18% (arterial-line/BIS cases only). */
proc sql noprint;
  select count(*) into :_qa_Total_Midazolam_mg    trimmed from g.master_data_merged where in_md8 = 1 and Total_Midazolam_mg is not missing;
  select count(*) into :_qa_AVG_ABP_Mean          trimmed from g.master_data_merged where in_md8 = 1 and AVG_ABP_Mean is not missing;
  select count(*) into :_qa_BIS_INDEX_LESS_30     trimmed from g.master_data_merged where in_md8 = 1 and BIS_INDEX_LESS_30_COUNT is not missing;
  select count(*) into :_qa_ABP_LESS_60           trimmed from g.master_data_merged where in_md8 = 1 and ABP_LESS_THAN_60_COUNT is not missing;
  select count(*) into :_qa_SD_ABP_Mean           trimmed from g.master_data_merged where in_md8 = 1 and SD_ABP_Mean is not missing;
  select count(*) into :_qa_NIBP_LESS_60          trimmed from g.master_data_merged where in_md8 = 1 and NIBP_LESS_60_COUNT is not missing;
  select count(*) into :_qa_Total_Phenyleph       trimmed from g.master_data_merged where in_md8 = 1 and Total_Phenylephrine_HCl_Pressors is not missing;
  select count(*) into :_qa_ISO_SEV               trimmed from g.master_data_merged where in_md8 = 1 and ISO_SEV_MAC_TOTAL_Exp is not missing;
quit;

data _null_;
  file "&qc_path.\05_qc_merge_report.txt" mod;
  put "QC-04 Part B: md8-owned vars non-missing outside md8 rows -- all asserted zero (see log).";
  put "QC-04 Part A: within-md8 non-missing counts (informational; md8 rows = 22,473):";
  put "  Total_Midazolam_mg:             &_qa_Total_Midazolam_mg (expected ~22473, ~100%)";
  put "  Total_Phenylephrine_HCl_Pressors: &_qa_Total_Phenyleph (expected ~22473, ~100%)";
  put "  ISO_SEV_MAC_TOTAL_Exp:          &_qa_ISO_SEV (expected ~22473, ~100%)";
  put "  AVG_ABP_Mean:                   &_qa_AVG_ABP_Mean (expected ~4005, ~18%)";
  put "  SD_ABP_Mean:                    &_qa_SD_ABP_Mean (expected ~4005, ~18%)";
  put "  BIS_INDEX_LESS_30_COUNT:        &_qa_BIS_INDEX_LESS_30 (expected ~3604, ~16%)";
  put "  ABP_LESS_THAN_60_COUNT:         &_qa_ABP_LESS_60 (expected ~3519, ~16%)";
  put "  NIBP_LESS_60_COUNT:             &_qa_NIBP_LESS_60 (expected ~16-18%)";
  put "Part A is informational, not asserted. Monitoring-derived columns (ABP_*, NIBP_*, BIS_*, SD_*,";
  put "AVG_*) are expected at roughly 16-18% of md8 rows because those monitors are not used on most";
  put "cases. Only the pressor/medication Total_* columns approach 22,473. A LOW count here is not";
  put "evidence of a conversion failure.";
run;

/* =========================================================================
   SECTION 5: QC-05 -- Clinical range checks for PREP-03 type-conversion targets
   Checks SET A (NOT SET B): the eight variables whose CHAR->NUM conversion was
   performed in Phase 3 PREP-03. md3 owns all eight; they span all 41,150 rows.
   EVERY WHERE clause has an IS NOT MISSING guard BEFORE the range test
   (RESEARCH Pitfall 4: SAS numeric missing is less than any number, so an unguarded
   `var < low` flags all non-md8 missing rows -- roughly 18,677 false positives).

   Clinical range bounds are calibrated to the OBSERVED distribution (not reference ranges
   alone). A bound tighter than the real data aborts a correct pipeline.
   ========================================================================= */
proc sql noprint;
  /* Admit_BMI: observed 12.84..88.32 -- ceiling 100 (a ceiling of 80 would abort on correct data) */
  select count(*) into :n_bmi_range   trimmed from g.master_data_merged
    where Admit_BMI is not missing and (Admit_BMI < 10 or Admit_BMI > 100);

  /* ASA__Anesth_Record_: observed 1..5, scale is 1-6 */
  select count(*) into :n_asa_range   trimmed from g.master_data_merged
    where ASA__Anesth_Record_ is not missing and (ASA__Anesth_Record_ < 1 or ASA__Anesth_Record_ > 6);

  /* Age_at_Encounter: observed 64..100 -- floor 18 is provisional (PCM-D-07 PENDING).
     The 18 floor cannot fire on the current data (minimum observed is 64); retained as
     a type-sanity guard only. Do NOT tighten to 64 before PCM-D-07 is resolved -- that
     would convert an open cohort question into a pipeline abort.
     PCM-D-07 PENDING: investigate observed age floor of 64; resolve in Phase 6. */
  select count(*) into :n_age_range   trimmed from g.master_data_merged
    where Age_at_Encounter is not missing and (Age_at_Encounter < 18 or Age_at_Encounter > 120);

  /* Cognitive_Score: observed 0..3. This is NOT MMSE (0-30). An earlier draft used 0..30
     which passes vacuously and would miss a genuine stray value of 25. */
  select count(*) into :n_cog_range   trimmed from g.master_data_merged
    where Cognitive_Score is not missing and (Cognitive_Score < 0 or Cognitive_Score > 3);

  /* Frailty_Score: Fried phenotype 0-5, observed 0..5 */
  select count(*) into :n_frail_range trimmed from g.master_data_merged
    where Frailty_Score is not missing and (Frailty_Score < 0 or Frailty_Score > 5);

  /* Operative time variables */
  select count(*) into :n_rt1_range   trimmed from g.master_data_merged
    where rt_INCISE_to_DRESS_mins is not missing and (rt_INCISE_to_DRESS_mins < 0 or rt_INCISE_to_DRESS_mins > 2000);

  select count(*) into :n_rt2_range   trimmed from g.master_data_merged
    where rt_RM_START_to_INCISION_mins is not missing and (rt_RM_START_to_INCISION_mins < 0 or rt_RM_START_to_INCISION_mins > 500);

  select count(*) into :n_rt3_range   trimmed from g.master_data_merged
    where rt_RM_START_to_RM_END_mins is not missing and (rt_RM_START_to_RM_END_mins < 0 or rt_RM_START_to_RM_END_mins > 2000);
quit;

%assert_eq(actual=&n_bmi_range,   expected=0, label=QC-05 Admit_BMI out of range 10-100);
%assert_eq(actual=&n_asa_range,   expected=0, label=QC-05 ASA__Anesth_Record_ out of range 1-6);
%assert_eq(actual=&n_age_range,   expected=0, label=QC-05 Age_at_Encounter out of range 18-120);
%assert_eq(actual=&n_cog_range,   expected=0, label=QC-05 Cognitive_Score out of range 0-3);
%assert_eq(actual=&n_frail_range, expected=0, label=QC-05 Frailty_Score out of range 0-5);
%assert_eq(actual=&n_rt1_range,   expected=0, label=QC-05 rt_INCISE_to_DRESS_mins out of range 0-2000);
%assert_eq(actual=&n_rt2_range,   expected=0, label=QC-05 rt_RM_START_to_INCISION_mins out of range 0-500);
%assert_eq(actual=&n_rt3_range,   expected=0, label=QC-05 rt_RM_START_to_RM_END_mins out of range 0-2000);

data _null_;
  file "&qc_path.\05_qc_merge_report.txt" mod;
  put "QC-05 clinical range checks (IS NOT MISSING guard applied to each):";
  put "  Admit_BMI (10-100):                    &n_bmi_range out-of-range rows (expected 0)";
  put "  ASA__Anesth_Record_ (1-6):             &n_asa_range out-of-range rows (expected 0)";
  put "  Age_at_Encounter (18-120):             &n_age_range out-of-range rows (expected 0)";
  put "    [PCM-D-07 PENDING: floor 18 provisional; observed min is 64]";
  put "  Cognitive_Score (0-3, NOT MMSE):       &n_cog_range out-of-range rows (expected 0)";
  put "  Frailty_Score (0-5, Fried phenotype):  &n_frail_range out-of-range rows (expected 0)";
  put "  rt_INCISE_to_DRESS_mins (0-2000):      &n_rt1_range out-of-range rows (expected 0)";
  put "  rt_RM_START_to_INCISION_mins (0-500):  &n_rt2_range out-of-range rows (expected 0)";
  put "  rt_RM_START_to_RM_END_mins (0-2000):   &n_rt3_range out-of-range rows (expected 0)";
run;

/* =========================================================================
   SECTION 6: Close-out
   ========================================================================= */
%put NOTE: ==== Phase 5 QC complete -- all checks passed ====;
data _null_;
  file "&qc_path.\05_qc_merge_report.txt" mod;
  put "=============================================================";
  put "ALL QC CHECKS PASSED (QC-01 through QC-05)";
run;
/* Leave g libname open; 99_run_all.sas manages libname lifecycle */
