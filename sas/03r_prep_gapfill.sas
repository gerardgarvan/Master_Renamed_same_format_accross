/* 03r_prep_gapfill.sas -- Phase 29: Gap-Fill Prep, r1-r6
   r1 EXCLUDED from g.gapfill output: both r1 columns already present in
   g.master_data_merged (confirmed 2026-10-07 via 29_r1_key_diag.sas, PCM-D-32).
   r7/r8/r9 EXCLUDED: MRN linkage infeasible (PCM-D-28); no ENCRYPTED_MRN column.
   Approved de-dup counts per PCM-D-32: r2=0, r4=0 (no de-dup steps needed).
   DO NOT ADD TO run_pipeline.cmd until Plan 3 approved.

   Approved removal counts copied from docs/DECISIONS.md PCM-D-32
   (after Gerard reviewed qc/29_dup_ids.txt at Plan 01 checkpoint).
   Update these values if source files change.                              */

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
%include "&sas_path.\macros_raw_import.sas";

%macro fail_out(msg=);
  %put ERROR: [03r_prep_gapfill] &msg;
  %abort cancel;
%mend fail_out;

/* Approved de-dup removal counts -- copied from docs/DECISIONS.md PCM-D-32
   after Gerard reviewed qc/29_dup_ids.txt at Plan 01 checkpoint.
   r2 = 0 and r4 = 0: no duplicate PRECEDE_STUDY_IDs found after key normalization. */
%let _r2_approved_removed = 0;
%let _r4_approved_removed = 0;

/* r7/r8/r9 excluded: no ENCRYPTED_MRN column; MRN linking infeasible per PCM-D-28.
   Phase 29 wires only r1-r6. v2.3 reopening condition: re-extract with ENCRYPTED_MRN
   or PRECEDE_STUDY_ID crosswalk table.                                    */

/* ========================================================================
   SECTION 0a: Read approved column allowlist -- DATA step infile (PCM-T-16)
   column_name $32 prevents truncation of long r2 column names.
   PROC IMPORT is forbidden for reference/gate CSVs per PCM-T-16.          */
data work._allowlist;
  infile "&docs_path.\gapfill_allowlist.csv" dsd missover firstobs=2;
  length file $8 column_name $32 approved $1;
  input file $ column_name $ approved $;
run;

/* Build per-file keep= macro variables (approved=Y rows only) */
proc sql noprint;
  select column_name into :_r1_keep separated by ' '
  from work._allowlist
  where upcase(strip(file)) = 'R1' and upcase(strip(approved)) = 'Y';

  select column_name into :_r2_keep separated by ' '
  from work._allowlist
  where upcase(strip(file)) = 'R2' and upcase(strip(approved)) = 'Y';

  select column_name into :_r3_keep separated by ' '
  from work._allowlist
  where upcase(strip(file)) = 'R3' and upcase(strip(approved)) = 'Y';

  select column_name into :_r4_keep separated by ' '
  from work._allowlist
  where upcase(strip(file)) = 'R4' and upcase(strip(approved)) = 'Y';

  select column_name into :_r5_keep separated by ' '
  from work._allowlist
  where upcase(strip(file)) = 'R5' and upcase(strip(approved)) = 'Y';

  select column_name into :_r6_keep separated by ' '
  from work._allowlist
  where upcase(strip(file)) = 'R6' and upcase(strip(approved)) = 'Y';
quit;

/* Initialize macro variables to empty string if PROC SQL found 0 rows
   (SAS does not set the macro var when SELECT INTO returns no rows).
   %do/%end required -- bare %then %let with empty value confuses parser. */
%if %symexist(_r1_keep) = 0 %then %do; %let _r1_keep = ; %end;
%if %symexist(_r2_keep) = 0 %then %do; %let _r2_keep = ; %end;
%if %symexist(_r3_keep) = 0 %then %do; %let _r3_keep = ; %end;
%if %symexist(_r4_keep) = 0 %then %do; %let _r4_keep = ; %end;
%if %symexist(_r5_keep) = 0 %then %do; %let _r5_keep = ; %end;
%if %symexist(_r6_keep) = 0 %then %do; %let _r6_keep = ; %end;

/* Empty keep-list gates -- SKIP (not abort) for all six files.
   A file with no approved=Y columns correctly contributes nothing.
   Only write g.gapfill_rN when the keep list is non-empty.               */
%macro r1_keep_gate;
  %if %length(%superq(_r1_keep)) = 0 %then
    %put NOTE: [03r r1] No approved=Y columns in allowlist -- skipping g.gapfill_r1 (contributes no new columns);
%mend r1_keep_gate;

%macro r2_keep_gate;
  %if %length(%superq(_r2_keep)) = 0 %then
    %put NOTE: [03r r2] No approved=Y columns in allowlist -- skipping g.gapfill_r2 (contributes no new columns);
%mend r2_keep_gate;

%macro r3_keep_gate;
  %if %length(%superq(_r3_keep)) = 0 %then
    %put NOTE: [03r r3] No approved=Y columns in allowlist -- skipping g.gapfill_r3 (contributes no new columns);
%mend r3_keep_gate;

%macro r4_keep_gate;
  %if %length(%superq(_r4_keep)) = 0 %then
    %put NOTE: [03r r4] No approved=Y columns in allowlist -- skipping g.gapfill_r4 (contributes no new columns);
%mend r4_keep_gate;

%macro r5_keep_gate;
  %if %length(%superq(_r5_keep)) = 0 %then
    %put NOTE: [03r r5] No approved=Y columns in allowlist -- skipping g.gapfill_r5 (contributes no new columns);
%mend r5_keep_gate;

%macro r6_keep_gate;
  %if %length(%superq(_r6_keep)) = 0 %then
    %put NOTE: [03r r6] No approved=Y columns in allowlist -- skipping g.gapfill_r6 (contributes no new columns);
%mend r6_keep_gate;

/* Run keep-list gates to log early warnings                              */
%r1_keep_gate;
%r2_keep_gate;
%r3_keep_gate;
%r4_keep_gate;
%r5_keep_gate;
%r6_keep_gate;

/* ========================================================================
   SECTION 1: r1 -- excluded (PCM-D-32)
   rt_RM_START_to_INDUCTION_mins and rt_RM_START_to_EMERGENCE_mins are
   already present in g.master_data_merged. No g.gapfill_r1 produced.    */
%put NOTE: [03r r1] r1 excluded from gap-fill -- both columns already in g.master_data_merged (PCM-D-32);

/* ========================================================================
   SECTION 2: r2 -- 2018_2019_Precede_Database.xlsx (key=studyid char, sheet 1)
   PCM-D-32: 0 duplicate PRECEDE_STUDY_IDs found after key normalization.
   Prefix is CONDITIONAL -- same logic as r1/r3/r5/r6.                   */
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

/* Blank-key gate: 'Precede' || strip('') = 'Precede' -- false duplicates */
%macro r2_blank_key_gate;
  %let _r2_blank_n = 0;
  proc sql noprint;
    select count(*) into :_r2_blank_n trimmed from work.r2_normed
    where strip(PRECEDE_STUDY_ID) = '' or strip(PRECEDE_STUDY_ID) = 'Precede';
  quit;
  %if &_r2_blank_n > 0 %then %do;
    %fail_out(msg=r2 has &_r2_blank_n blank or bare-Precede PRECEDE_STUDY_IDs -- review source file before de-dup);
  %end;
  %else %do;
    %put NOTE: [03r r2] blank-key gate passed -- 0 blank PRECEDE_STUDY_IDs;
  %end;
%mend r2_blank_key_gate;
%r2_blank_key_gate;

/* De-dup: PCM-D-32 confirmed 0 duplicates. nodupkey still run as a gate. */
proc sort data=work.r2_normed nodupkey dupout=work._r2_dup_removed;
  by PRECEDE_STUDY_ID;
run;

/* Removed-row count assertion: must match &_r2_approved_removed from PCM-D-32 */
%macro r2_removed_gate;
  %let _r2_removed_n = 0;
  proc sql noprint;
    select count(*) into :_r2_removed_n trimmed from work._r2_dup_removed;
  quit;
  %if &_r2_removed_n ne &_r2_approved_removed %then %do;
    %fail_out(msg=r2 de-dup removed &_r2_removed_n rows - expected &_r2_approved_removed per PCM-D-32 -- source file may have changed);
  %end;
  %else %do;
    %put NOTE: [03r r2] removed-row count gate passed -- &_r2_removed_n removed (expected &_r2_approved_removed per PCM-D-32);
  %end;
%mend r2_removed_gate;
%r2_removed_gate;

/* Post-dedup gate: second pass confirms no residual duplicates */
proc sort data=work.r2_normed nodupkey dupout=work._r2_post_check;
  by PRECEDE_STUDY_ID;
run;
%macro r2_post_gate;
  %let _r2_post_n = 0;
  proc sql noprint;
    select count(*) into :_r2_post_n trimmed from work._r2_post_check;
  quit;
  %if &_r2_post_n > 0 %then %do;
    %fail_out(msg=r2 still has &_r2_post_n duplicate PRECEDE_STUDY_ID rows after de-dup -- resolve PCM-D-32 before merge);
  %end;
  %else %do;
    %put NOTE: [03r r2] post-dedup gate passed -- 0 residual duplicates;
  %end;
%mend r2_post_gate;
%r2_post_gate;

/* Write to g library if approved columns exist; else skip (PCM-D-32 allows 0 cols) */
%if %length(%superq(_r2_keep)) > 0 %then %do;
  data g.gapfill_r2;
    set work.r2_normed (keep=PRECEDE_STUDY_ID &_r2_keep);
  run;
  proc sort data=g.gapfill_r2; by PRECEDE_STUDY_ID; run;
  %put NOTE: [03r r2] g.gapfill_r2 created with columns: PRECEDE_STUDY_ID &_r2_keep;
%end;
%else %do;
  %put NOTE: [03r r2] No approved=Y columns -- g.gapfill_r2 not created (contributes no new columns);
%end;

/* ========================================================================
   SECTION 3: r3 -- 2018_2022_COLONOSCOPY_20240118.xlsx (no known duplicates)
   Key is PRECEDE_Study_ID (already prefixed in source).                  */
%import_xlsx(r3, 2018_2022_COLONOSCOPY_20240118.xlsx)

proc sql noprint;
  select max(length(strip(PRECEDE_Study_ID))) into :_r3_k_maxlen trimmed
  from work.r3_s1;
quit;
%macro r3_len_gate;
  %if &_r3_k_maxlen > 12 %then %do;
    %fail_out(msg=r3 key max length is &_r3_k_maxlen -- exceeds $12 target);
  %end;
  %else %do;
    %put NOTE: [03r r3] key max length &_r3_k_maxlen -- fits $12;
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

/* Blank-key gate */
%macro r3_blank_key_gate;
  %let _r3_blank_n = 0;
  proc sql noprint;
    select count(*) into :_r3_blank_n trimmed from work.r3_normed
    where strip(PRECEDE_STUDY_ID) = '' or strip(PRECEDE_STUDY_ID) = 'Precede';
  quit;
  %if &_r3_blank_n > 0 %then %do;
    %fail_out(msg=r3 has &_r3_blank_n blank or bare-Precede PRECEDE_STUDY_IDs -- review source file before de-dup);
  %end;
  %else %do;
    %put NOTE: [03r r3] blank-key gate passed -- 0 blank PRECEDE_STUDY_IDs;
  %end;
%mend r3_blank_key_gate;
%r3_blank_key_gate;

/* De-dup gate: no known duplicates in r3; nodupkey still run as defense  */
proc sort data=work.r3_normed nodupkey dupout=work._r3_dup_removed;
  by PRECEDE_STUDY_ID;
run;

/* Post-dedup gate: use attrn(nobs) -- PROC SQL count(*) fails on 0-column dupout */
proc sort data=work.r3_normed nodupkey dupout=work._r3_post_check;
  by PRECEDE_STUDY_ID;
run;
%macro r3_post_gate;
  %let _r3_post_n = %sysfunc(attrn(%sysfunc(open(work._r3_post_check)),nobs));
  %let _r3_dsid  = %sysfunc(close(%sysfunc(open(work._r3_post_check))));
  %if &_r3_post_n > 0 %then %do;
    %fail_out(msg=r3 still has &_r3_post_n duplicate PRECEDE_STUDY_ID rows after de-dup -- resolve before merge);
  %end;
  %else %do;
    %put NOTE: [03r r3] post-dedup gate passed -- 0 residual duplicates;
  %end;
%mend r3_post_gate;
%r3_post_gate;

/* Write to g library if approved columns exist */
%if %length(%superq(_r3_keep)) > 0 %then %do;
  data g.gapfill_r3;
    set work.r3_normed (keep=PRECEDE_STUDY_ID &_r3_keep);
  run;
  proc sort data=g.gapfill_r3; by PRECEDE_STUDY_ID; run;
  %put NOTE: [03r r3] g.gapfill_r3 created with columns: PRECEDE_STUDY_ID &_r3_keep;
%end;
%else %do;
  %put NOTE: [03r r3] No approved=Y columns -- g.gapfill_r3 not created (contributes no new columns);
%end;

/* ========================================================================
   SECTION 4: r4 -- 2020_Precede_Database_Edu.xlsx (key=studyid CHARACTER)
   studyid confirmed character from import log.
   PCM-D-32: 0 duplicate PRECEDE_STUDY_IDs found after key normalization. */
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

/* Blank-key gate */
%macro r4_blank_key_gate;
  %let _r4_blank_n = 0;
  proc sql noprint;
    select count(*) into :_r4_blank_n trimmed from work.r4_normed
    where strip(PRECEDE_STUDY_ID) = '' or strip(PRECEDE_STUDY_ID) = 'Precede';
  quit;
  %if &_r4_blank_n > 0 %then %do;
    %fail_out(msg=r4 has &_r4_blank_n blank or bare-Precede PRECEDE_STUDY_IDs -- review source file before de-dup);
  %end;
  %else %do;
    %put NOTE: [03r r4] blank-key gate passed -- 0 blank PRECEDE_STUDY_IDs;
  %end;
%mend r4_blank_key_gate;
%r4_blank_key_gate;

/* De-dup: PCM-D-32 confirmed 0 duplicates. nodupkey still run as a gate. */
proc sort data=work.r4_normed nodupkey dupout=work._r4_dup_removed;
  by PRECEDE_STUDY_ID;
run;

/* Removed-row count assertion: must match &_r4_approved_removed from PCM-D-32 */
%macro r4_removed_gate;
  %let _r4_removed_n = 0;
  proc sql noprint;
    select count(*) into :_r4_removed_n trimmed from work._r4_dup_removed;
  quit;
  %if &_r4_removed_n ne &_r4_approved_removed %then %do;
    %fail_out(msg=r4 de-dup removed &_r4_removed_n rows - expected &_r4_approved_removed per PCM-D-32 -- source file may have changed);
  %end;
  %else %do;
    %put NOTE: [03r r4] removed-row count gate passed -- &_r4_removed_n removed (expected &_r4_approved_removed per PCM-D-32);
  %end;
%mend r4_removed_gate;
%r4_removed_gate;

/* Post-dedup gate: use attrn(nobs) -- PROC SQL count(*) fails on 0-column dupout */
proc sort data=work.r4_normed nodupkey dupout=work._r4_post_check;
  by PRECEDE_STUDY_ID;
run;
%macro r4_post_gate;
  %let _r4_post_n = %sysfunc(attrn(%sysfunc(open(work._r4_post_check)),nobs));
  %let _r4_dsid  = %sysfunc(close(%sysfunc(open(work._r4_post_check))));
  %if &_r4_post_n > 0 %then %do;
    %fail_out(msg=r4 still has &_r4_post_n duplicate PRECEDE_STUDY_ID rows after de-dup -- resolve PCM-D-32 before merge);
  %end;
  %else %do;
    %put NOTE: [03r r4] post-dedup gate passed -- 0 residual duplicates;
  %end;
%mend r4_post_gate;
%r4_post_gate;

/* Write to g library if approved columns exist */
%if %length(%superq(_r4_keep)) > 0 %then %do;
  data g.gapfill_r4;
    set work.r4_normed (keep=PRECEDE_STUDY_ID &_r4_keep);
  run;
  proc sort data=g.gapfill_r4; by PRECEDE_STUDY_ID; run;
  %put NOTE: [03r r4] g.gapfill_r4 created with columns: PRECEDE_STUDY_ID &_r4_keep;
%end;
%else %do;
  %put NOTE: [03r r4] No approved=Y columns -- g.gapfill_r4 not created (contributes no new columns);
%end;

/* ========================================================================
   SECTION 5: r5 -- 2021_Education_20240124.csv (no known duplicates)    */
%import_csv(r5, 2021_Education_20240124.csv)

proc sql noprint;
  select max(length(strip(PRECEDE_Study_ID))) into :_r5_k_maxlen trimmed
  from work.r5;
quit;
%macro r5_len_gate;
  %if &_r5_k_maxlen > 12 %then %do;
    %fail_out(msg=r5 key max length is &_r5_k_maxlen -- exceeds $12 target);
  %end;
  %else %do;
    %put NOTE: [03r r5] key max length &_r5_k_maxlen -- fits $12;
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

/* Blank-key gate */
%macro r5_blank_key_gate;
  %let _r5_blank_n = 0;
  proc sql noprint;
    select count(*) into :_r5_blank_n trimmed from work.r5_normed
    where strip(PRECEDE_STUDY_ID) = '' or strip(PRECEDE_STUDY_ID) = 'Precede';
  quit;
  %if &_r5_blank_n > 0 %then %do;
    %fail_out(msg=r5 has &_r5_blank_n blank or bare-Precede PRECEDE_STUDY_IDs -- review source file before de-dup);
  %end;
  %else %do;
    %put NOTE: [03r r5] blank-key gate passed -- 0 blank PRECEDE_STUDY_IDs;
  %end;
%mend r5_blank_key_gate;
%r5_blank_key_gate;

/* De-dup gate: no known duplicates in r5; nodupkey run as defense        */
proc sort data=work.r5_normed nodupkey dupout=work._r5_dup_removed;
  by PRECEDE_STUDY_ID;
run;

/* Post-dedup gate: use attrn(nobs) -- PROC SQL count(*) fails on 0-column dupout */
proc sort data=work.r5_normed nodupkey dupout=work._r5_post_check;
  by PRECEDE_STUDY_ID;
run;
%macro r5_post_gate;
  %let _r5_post_n = %sysfunc(attrn(%sysfunc(open(work._r5_post_check)),nobs));
  %let _r5_dsid  = %sysfunc(close(%sysfunc(open(work._r5_post_check))));
  %if &_r5_post_n > 0 %then %do;
    %fail_out(msg=r5 still has &_r5_post_n duplicate PRECEDE_STUDY_ID rows after de-dup -- resolve before merge);
  %end;
  %else %do;
    %put NOTE: [03r r5] post-dedup gate passed -- 0 residual duplicates;
  %end;
%mend r5_post_gate;
%r5_post_gate;

/* Write to g library if approved columns exist */
%if %length(%superq(_r5_keep)) > 0 %then %do;
  data g.gapfill_r5;
    set work.r5_normed (keep=PRECEDE_STUDY_ID &_r5_keep);
  run;
  proc sort data=g.gapfill_r5; by PRECEDE_STUDY_ID; run;
  %put NOTE: [03r r5] g.gapfill_r5 created with columns: PRECEDE_STUDY_ID &_r5_keep;
%end;
%else %do;
  %put NOTE: [03r r5] No approved=Y columns -- g.gapfill_r5 not created (contributes no new columns);
%end;

/* ========================================================================
   SECTION 6: r6 -- 2021_Frailty_20240123.csv (no known duplicates)     */
%import_csv(r6, 2021_Frailty_20240123.csv)

proc sql noprint;
  select max(length(strip(PRECEDE_Study_ID))) into :_r6_k_maxlen trimmed
  from work.r6;
quit;
%macro r6_len_gate;
  %if &_r6_k_maxlen > 12 %then %do;
    %fail_out(msg=r6 key max length is &_r6_k_maxlen -- exceeds $12 target);
  %end;
  %else %do;
    %put NOTE: [03r r6] key max length &_r6_k_maxlen -- fits $12;
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

/* Blank-key gate */
%macro r6_blank_key_gate;
  %let _r6_blank_n = 0;
  proc sql noprint;
    select count(*) into :_r6_blank_n trimmed from work.r6_normed
    where strip(PRECEDE_STUDY_ID) = '' or strip(PRECEDE_STUDY_ID) = 'Precede';
  quit;
  %if &_r6_blank_n > 0 %then %do;
    %fail_out(msg=r6 has &_r6_blank_n blank or bare-Precede PRECEDE_STUDY_IDs -- review source file before de-dup);
  %end;
  %else %do;
    %put NOTE: [03r r6] blank-key gate passed -- 0 blank PRECEDE_STUDY_IDs;
  %end;
%mend r6_blank_key_gate;
%r6_blank_key_gate;

/* De-dup gate: no known duplicates in r6; nodupkey run as defense        */
proc sort data=work.r6_normed nodupkey dupout=work._r6_dup_removed;
  by PRECEDE_STUDY_ID;
run;

/* Post-dedup gate: use attrn(nobs) -- PROC SQL count(*) fails on 0-column dupout */
proc sort data=work.r6_normed nodupkey dupout=work._r6_post_check;
  by PRECEDE_STUDY_ID;
run;
%macro r6_post_gate;
  %let _r6_post_n = %sysfunc(attrn(%sysfunc(open(work._r6_post_check)),nobs));
  %let _r6_dsid  = %sysfunc(close(%sysfunc(open(work._r6_post_check))));
  %if &_r6_post_n > 0 %then %do;
    %fail_out(msg=r6 still has &_r6_post_n duplicate PRECEDE_STUDY_ID rows after de-dup -- resolve before merge);
  %end;
  %else %do;
    %put NOTE: [03r r6] post-dedup gate passed -- 0 residual duplicates;
  %end;
%mend r6_post_gate;
%r6_post_gate;

/* Write to g library if approved columns exist */
%if %length(%superq(_r6_keep)) > 0 %then %do;
  data g.gapfill_r6;
    set work.r6_normed (keep=PRECEDE_STUDY_ID &_r6_keep);
  run;
  proc sort data=g.gapfill_r6; by PRECEDE_STUDY_ID; run;
  %put NOTE: [03r r6] g.gapfill_r6 created with columns: PRECEDE_STUDY_ID &_r6_keep;
%end;
%else %do;
  %put NOTE: [03r r6] No approved=Y columns -- g.gapfill_r6 not created (contributes no new columns);
%end;

/* ========================================================================
   SUMMARY NOTE                                                            */
%put NOTE: [03r_prep_gapfill] Program complete. Review log for g.gapfill_rN creation status.;
%put NOTE: [03r_prep_gapfill] Files with no approved=Y columns in gapfill_allowlist.csv were skipped (no ERROR).;
%put NOTE: [03r_prep_gapfill] PCM-D-32 approved removal counts: r2=0, r4=0. See gate NOTEs above for actual counts.;
