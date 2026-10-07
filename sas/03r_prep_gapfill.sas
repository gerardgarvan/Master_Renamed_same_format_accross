/* 03r_prep_gapfill.sas -- Phase 29: Gap-Fill Prep, r2-r6
   r1 EXCLUDED: both r1 columns already present in g.master_data_merged (confirmed
   2026-10-07 via 29_r1_key_diag.sas, PCM-D-32 updated).
   DIAGNOSTIC STUB -- DO NOT ADD TO run_pipeline.cmd until Plan 2 approved
   Requires: PCM-D-32 de-dup rules (r2/r4) approved by Gerard in DECISIONS.md
   Requires: docs/gapfill_allowlist.csv approved by Gerard                  */

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
%include "&sas_path.\macros_raw_import.sas";

%macro fail_out(msg=);
  %put ERROR: [03r_prep_gapfill] &msg;
  %abort cancel;
%mend fail_out;

/* r1 EXCLUDED -- both columns (rt_RM_START_to_INDUCTION_mins,
   rt_RM_START_to_EMERGENCE_mins) already present in g.master_data_merged.
   Confirmed 2026-10-07 via 29_r1_key_diag.sas. See PCM-D-32 in DECISIONS.md. */

/* ========================================================================
   SECTION 2: r2 -- 2018_2019_Precede_Database.xlsx (key=studyid char, sheet 1)
   Prefix is CONDITIONAL -- same logic as r1/r3/r5/r6.
   If studyid already contains 'PRECEDE', strip it and re-add correct case.    */
%import_xlsx(r2, 2018_2019_Precede_Database.xlsx)

/* Max-length gate -- check worst case from both branches */
proc sql noprint;
  select max(
    case when index(upcase(strip(studyid)),'PRECEDE')=0
      then length('Precede'||strip(studyid))
      else length('Precede'||substr(strip(studyid),8))
    end
  ) into :_r2_k_maxlen trimmed
  from work.r2_s1;
quit;
%macro r2_len_gate;
  %if &_r2_k_maxlen > 12 %then %do;
    %fail_out(msg=r2 normalized key max length is &_r2_k_maxlen -- exceeds $12 target);
  %end;
  %else %do;
    %put NOTE: [03r r2] normalized key max length &_r2_k_maxlen -- fits $12;
  %end;
%mend r2_len_gate;
%r2_len_gate;

data work.r2_normed;
  length PRECEDE_STUDY_ID $12;
  set work.r2_s1 (keep=studyid rename=(studyid=_k_raw));
  if index(upcase(strip(_k_raw)), 'PRECEDE') = 0
    then PRECEDE_STUDY_ID = 'Precede' || strip(_k_raw);
    else PRECEDE_STUDY_ID = 'Precede' || substr(strip(_k_raw), 8);
  drop _k_raw;
run;

%macro r2_blank_key_gate;
  %let _r2_blank_n = 0;
  proc sql noprint;
    select count(*) into :_r2_blank_n trimmed from work.r2_normed
    where strip(PRECEDE_STUDY_ID) in ('', 'Precede');
  quit;
  %if &_r2_blank_n > 0 %then %do;
    %fail_out(msg=r2 has &_r2_blank_n blank/bare-Precede PRECEDE_STUDY_IDs -- review before de-dup);
  %end;
%mend r2_blank_key_gate;
%r2_blank_key_gate;

proc sort data=work.r2_normed nodupkey dupout=work._r2_dups;
  by PRECEDE_STUDY_ID;
run;

/* ========================================================================
   SECTION 3: r3 -- 2018_2022_COLONOSCOPY_20240118.xlsx (no known duplicates) */
%import_xlsx(r3, 2018_2022_COLONOSCOPY_20240118.xlsx)

proc sql noprint;
  select max(length(strip(PRECEDE_Study_ID))) into :_r3_k_maxlen trimmed
  from work.r3_s1;
quit;
%macro r3_len_gate;
  %if &_r3_k_maxlen > 12 %then %do;
    %fail_out(msg=r3 key max length is &_r3_k_maxlen -- exceeds $12 target);
  %end;
%mend r3_len_gate;
%r3_len_gate;

data work.r3_normed;
  length PRECEDE_STUDY_ID $12;
  set work.r3_s1 (keep=PRECEDE_Study_ID rename=(PRECEDE_Study_ID=_k_raw));
  if index(upcase(strip(_k_raw)), 'PRECEDE') = 0
    then PRECEDE_STUDY_ID = 'Precede' || strip(_k_raw);
    else PRECEDE_STUDY_ID = 'Precede' || substr(strip(_k_raw), 8);
  drop _k_raw;
run;

/* ========================================================================
   SECTION 4: r4 -- 2020_Precede_Database_Edu.xlsx (key=studyid CHARACTER)
   studyid confirmed character from import log -- same prefix logic as r2/r3/r5/r6. */
%import_xlsx(r4, 2020_Precede_Database_Edu.xlsx)

proc sql noprint;
  select max(
    case when index(upcase(strip(studyid)),'PRECEDE')=0
      then length('Precede'||strip(studyid))
      else length('Precede'||substr(strip(studyid),8))
    end
  ) into :_r4_k_maxlen trimmed
  from work.r4_s1;
quit;
%macro r4_len_gate;
  %if &_r4_k_maxlen > 12 %then %do;
    %fail_out(msg=r4 normalized key max length is &_r4_k_maxlen -- exceeds $12 target);
  %end;
  %else %do;
    %put NOTE: [03r r4] normalized key max length &_r4_k_maxlen -- fits $12;
  %end;
%mend r4_len_gate;
%r4_len_gate;

data work.r4_normed;
  length PRECEDE_STUDY_ID $12;
  set work.r4_s1 (keep=studyid rename=(studyid=_k_raw));
  if index(upcase(strip(_k_raw)), 'PRECEDE') = 0
    then PRECEDE_STUDY_ID = 'Precede' || strip(_k_raw);
    else PRECEDE_STUDY_ID = 'Precede' || substr(strip(_k_raw), 8);
  drop _k_raw;
run;

proc sort data=work.r4_normed nodupkey dupout=work._r4_dups;
  by PRECEDE_STUDY_ID;
run;

/* ========================================================================
   SECTION 5: r5 -- 2021_Education_20240124.csv */
%import_csv(r5, 2021_Education_20240124.csv)

proc sql noprint;
  select max(length(strip(PRECEDE_Study_ID))) into :_r5_k_maxlen trimmed
  from work.r5;
quit;
%macro r5_len_gate;
  %if &_r5_k_maxlen > 12 %then %do;
    %fail_out(msg=r5 key max length is &_r5_k_maxlen -- exceeds $12 target);
  %end;
%mend r5_len_gate;
%r5_len_gate;

data work.r5_normed;
  length PRECEDE_STUDY_ID $12;
  set work.r5 (keep=PRECEDE_Study_ID rename=(PRECEDE_Study_ID=_k_raw));
  if index(upcase(strip(_k_raw)), 'PRECEDE') = 0
    then PRECEDE_STUDY_ID = 'Precede' || strip(_k_raw);
    else PRECEDE_STUDY_ID = 'Precede' || substr(strip(_k_raw), 8);
  drop _k_raw;
run;

/* ========================================================================
   SECTION 6: r6 -- 2021_Frailty_20240123.csv */
%import_csv(r6, 2021_Frailty_20240123.csv)

proc sql noprint;
  select max(length(strip(PRECEDE_Study_ID))) into :_r6_k_maxlen trimmed
  from work.r6;
quit;
%macro r6_len_gate;
  %if &_r6_k_maxlen > 12 %then %do;
    %fail_out(msg=r6 key max length is &_r6_k_maxlen -- exceeds $12 target);
  %end;
%mend r6_len_gate;
%r6_len_gate;

data work.r6_normed;
  length PRECEDE_STUDY_ID $12;
  set work.r6 (keep=PRECEDE_Study_ID rename=(PRECEDE_Study_ID=_k_raw));
  if index(upcase(strip(_k_raw)), 'PRECEDE') = 0
    then PRECEDE_STUDY_ID = 'Precede' || strip(_k_raw);
    else PRECEDE_STUDY_ID = 'Precede' || substr(strip(_k_raw), 8);
  drop _k_raw;
run;

/* ========================================================================
   SECTION 7: Duplicate ID report -- written to qc/ before abort */
%macro report_dups_and_abort;
  %let _r2_dups = 0;
  %let _r4_dups = 0;
  proc sql noprint;
    select count(*) into :_r2_dups trimmed from work._r2_dups;
    select count(*) into :_r4_dups trimmed from work._r4_dups;
  quit;

  data _null_;
    file "&qc_path.\29_dup_ids.txt" lrecl=200;
    put "Phase 29 -- Duplicate PRECEDE_STUDY_ID Report";
    put "Generated: %sysfunc(date(), worddate.) %sysfunc(time(), time8.)";
    put "r1: excluded (columns already in g.master_data_merged -- PCM-D-32)";
    put "r2 dup rows removed: &_r2_dups";
    put "r4 dup rows removed: &_r4_dups";
    put "---";
    put "ACTION REQUIRED: Review duplicate IDs below and record de-dup rule";
    put "in docs/DECISIONS.md as PCM-D-32 before Plan 2 proceeds.";
    put "---";
  run;

  %if &_r2_dups > 0 %then %do;
    data _null_;
      set work._r2_dups;
      file "&qc_path.\29_dup_ids.txt" mod lrecl=200;
      put "r2 duplicate removed: " PRECEDE_STUDY_ID;
    run;
  %end;

  %if &_r4_dups > 0 %then %do;
    data _null_;
      set work._r4_dups;
      file "&qc_path.\29_dup_ids.txt" mod lrecl=200;
      put "r4 duplicate removed: " PRECEDE_STUDY_ID;
    run;
  %end;

  /* Hard abort if ANY duplicates exist -- de-dup rules must be approved first */
  %if %eval(&_r2_dups + &_r4_dups) > 0 %then %do;
    %fail_out(msg=03r_prep_gapfill DIAGNOSTIC COMPLETE. Found &_r2_dups r2 + &_r4_dups r4 duplicate IDs. Review qc/29_dup_ids.txt and record PCM-D-32 de-dup rules in DECISIONS.md before Plan 2.);
  %end;
  %else %do;
    %put NOTE: [03r_prep_gapfill] No duplicate PRECEDE_STUDY_IDs found in r2/r4. Proceed to Plan 2.;
  %end;
%mend report_dups_and_abort;
%report_dups_and_abort;
