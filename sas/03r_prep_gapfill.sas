/* 03r_prep_gapfill.sas -- Phase 29: Gap-Fill Prep, r1-r6
   r1 EXCLUDED from g.gapfill output: both r1 columns already present in
   g.master_data_merged (confirmed 2026-10-07 via 29_r1_key_diag.sas, PCM-D-32).
   r7/r8/r9 EXCLUDED: MRN linkage infeasible (PCM-D-28); no ENCRYPTED_MRN column.
   Approved de-dup counts per PCM-D-32: r2=0, r4=0 (no de-dup steps needed).
   DO NOT ADD TO run_pipeline.cmd until Plan 3 approved.

   Approved removal counts copied from docs/DECISIONS.md PCM-D-32
   (after Gerard reviewed qc/29_dup_ids.txt at Plan 01 checkpoint).
   Update these values if source files change.

   2026-10-07 REVISION (SAS kernel crash fix):
   - Removed ALL open-code %if/%do. Open-code %if followed by a %macro
     definition crashed the SAS 9.4 kernel (Read Access Violation / bogus
     "Out of memory"). All conditional logic now lives inside macros.
   - Keep-list macro vars are pre-initialized with %let before SELECT INTO
     (SELECT INTO with 0 rows leaves an existing value untouched), replacing
     the %symexist checks.
   - Dataset row counts use one helper (%_nobs) that opens, reads, and closes
     the SAME handle. The old post-gates opened the dataset twice and closed
     only the second handle, leaking an open handle on each call.
   - Per-file gate macros consolidated into parameterized macros; gate
     logic, messages, and abort behavior are unchanged.
   - Key max-length gate now measures the NORMALIZED key for every file
     (r3/r5/r6 previously measured the raw key, which could miss a key that
     exceeds $12 only after the 'Precede' prefix is added).               */

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
   HELPER MACROS
   ======================================================================== */

/* %_nobs(ds) -- function-style: returns logical row count of a dataset.
   Works on 0-column datasets (where PROC SQL count(*) fails).            */
%macro _nobs(ds);
  %local _dsid _n _rc;
  %let _dsid = %sysfunc(open(&ds));
  %if &_dsid = 0 %then %do;
    %fail_out(msg=Cannot open &ds for row count -- %sysfunc(sysmsg()));
  %end;
  %let _n  = %sysfunc(attrn(&_dsid, nlobs));
  %let _rc = %sysfunc(close(&_dsid));
&_n
%mend _nobs;

/* %keep_gate(n=) -- early NOTE when file rN has no approved=Y columns     */
%macro keep_gate(n=);
  %local _kl;
  %let _kl = &&_r&n._keep;
  %if %length(%superq(_kl)) = 0 %then %do;
    %put NOTE: [03r r&n] No approved=Y columns in allowlist -- skipping g.gapfill_r&n (contributes no new columns);
  %end;
%mend keep_gate;

/* %len_gate(n=, src=, key=) -- normalized key must fit $12               */
%macro len_gate(n=, src=, key=);
  %local _maxlen;
  %let _maxlen = 0;
  proc sql noprint;
    select max(
      case when index(upcase(strip(&key)),'PRECEDE')=0
        then length('Precede'||strip(&key))
        else length('Precede'||substr(strip(&key),8))
      end
    ) into :_maxlen trimmed
    from &src;
  quit;
  %if %length(&_maxlen) = 0 or &_maxlen = . %then %do;
    %fail_out(msg=r&n key max length could not be computed from &src (0 rows or all-missing &key));
  %end;
  %else %if &_maxlen > 12 %then %do;
    %fail_out(msg=r&n normalized key max length is &_maxlen -- exceeds $12 target);
  %end;
  %else %do;
    %put NOTE: [03r r&n] normalized key max length &_maxlen -- fits $12;
  %end;
%mend len_gate;

/* %norm_key(n=, src=, key=) -- build work.rN_normed with PRECEDE_STUDY_ID */
%macro norm_key(n=, src=, key=);
  data work.r&n._normed;
    length PRECEDE_STUDY_ID $12;
    set &src (keep=&key rename=(&key=_k_raw));
    if index(upcase(strip(_k_raw)), 'PRECEDE') = 0
      then PRECEDE_STUDY_ID = 'Precede' || strip(_k_raw);
      else PRECEDE_STUDY_ID = 'Precede' || substr(strip(_k_raw), 8);
    drop _k_raw;
  run;
%mend norm_key;

/* %blank_key_gate(n=) -- 'Precede' || strip('') = 'Precede' -> false dups */
%macro blank_key_gate(n=);
  %local _blank_n;
  %let _blank_n = 0;
  proc sql noprint;
    select count(*) into :_blank_n trimmed from work.r&n._normed
    where strip(PRECEDE_STUDY_ID) = '' or strip(PRECEDE_STUDY_ID) = 'Precede';
  quit;
  %if &_blank_n > 0 %then %do;
    %fail_out(msg=r&n has &_blank_n blank or bare-Precede PRECEDE_STUDY_IDs -- review source file before de-dup);
  %end;
  %else %do;
    %put NOTE: [03r r&n] blank-key gate passed -- 0 blank PRECEDE_STUDY_IDs;
  %end;
%mend blank_key_gate;

/* %dedup(n=, expected=) -- nodupkey de-dup, optional removed-count
   assertion (when expected= is given), then post-dedup residual check.   */
%macro dedup(n=, expected=);
  %local _removed_n _post_n;

  proc sort data=work.r&n._normed nodupkey dupout=work._r&n._dup_removed;
    by PRECEDE_STUDY_ID;
  run;

  %if %length(&expected) > 0 %then %do;
    %let _removed_n = %_nobs(work._r&n._dup_removed);
    %if &_removed_n ne &expected %then %do;
      %fail_out(msg=r&n de-dup removed &_removed_n rows - expected &expected per PCM-D-32 -- source file may have changed);
    %end;
    %else %do;
      %put NOTE: [03r r&n] removed-row count gate passed -- &_removed_n removed (expected &expected per PCM-D-32);
    %end;
  %end;

  /* Post-dedup gate: second pass confirms no residual duplicates */
  proc sort data=work.r&n._normed nodupkey dupout=work._r&n._post_check;
    by PRECEDE_STUDY_ID;
  run;
  %let _post_n = %_nobs(work._r&n._post_check);
  %if &_post_n > 0 %then %do;
    %fail_out(msg=r&n still has &_post_n duplicate PRECEDE_STUDY_ID rows after de-dup -- resolve before merge);
  %end;
  %else %do;
    %put NOTE: [03r r&n] post-dedup gate passed -- 0 residual duplicates;
  %end;
%mend dedup;

/* %write_gapfill(n=) -- write g.gapfill_rN only if approved columns exist */
%macro write_gapfill(n=);
  %local _kl;
  %let _kl = &&_r&n._keep;
  %if %length(%superq(_kl)) > 0 %then %do;
    data g.gapfill_r&n;
      set work.r&n._normed (keep=PRECEDE_STUDY_ID &_kl);
    run;
    proc sort data=g.gapfill_r&n; by PRECEDE_STUDY_ID; run;
    %put NOTE: [03r r&n] g.gapfill_r&n created with columns: PRECEDE_STUDY_ID &_kl;
  %end;
  %else %do;
    %put NOTE: [03r r&n] No approved=Y columns -- g.gapfill_r&n not created (contributes no new columns);
  %end;
%mend write_gapfill;

/* ========================================================================
   SECTION 0a: Read approved column allowlist -- DATA step infile (PCM-T-16)
   column_name $32 prevents truncation of long r2 column names.
   PROC IMPORT is forbidden for reference/gate CSVs per PCM-T-16.          */
data work._allowlist;
  infile "&docs_path.\gapfill_allowlist.csv" dsd missover firstobs=2;
  length file $8 column_name $32 approved $1;
  input file $ column_name $ approved $;
run;

/* Pre-initialize keep lists (global). SELECT INTO returning 0 rows leaves
   these empty, so files with no approved=Y columns contribute nothing.   */
%let _r1_keep = ;
%let _r2_keep = ;
%let _r3_keep = ;
%let _r4_keep = ;
%let _r5_keep = ;
%let _r6_keep = ;

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

/* Empty keep-list gates -- SKIP (not abort) for all six files.
   A file with no approved=Y columns correctly contributes nothing.       */
%keep_gate(n=1)
%keep_gate(n=2)
%keep_gate(n=3)
%keep_gate(n=4)
%keep_gate(n=5)
%keep_gate(n=6)

/* ========================================================================
   SECTION 1: r1 -- excluded (PCM-D-32)
   rt_RM_START_to_INDUCTION_mins and rt_RM_START_to_EMERGENCE_mins are
   already present in g.master_data_merged. No g.gapfill_r1 produced.    */
%put NOTE: [03r r1] r1 excluded from gap-fill -- both columns already in g.master_data_merged (PCM-D-32);

/* ========================================================================
   SECTION 2: r2 -- 2018_2019_Precede_Database.xlsx (key=studyid char, sheet 1)
   PCM-D-32: 0 duplicate PRECEDE_STUDY_IDs found after key normalization.
   Prefix is CONDITIONAL -- same logic as r3/r5/r6.                      */
%import_xlsx(r2, 2018_2019_Precede_Database.xlsx)
%len_gate(n=2, src=work.r2_s1, key=studyid)
%norm_key(n=2, src=work.r2_s1, key=studyid)
%blank_key_gate(n=2)
%dedup(n=2, expected=&_r2_approved_removed)
%write_gapfill(n=2)

/* ========================================================================
   SECTION 3: r3 -- 2018_2022_COLONOSCOPY_20240118.xlsx (no known duplicates)
   Key is PRECEDE_Study_ID (already prefixed in source).                  */
%import_xlsx(r3, 2018_2022_COLONOSCOPY_20240118.xlsx)
%len_gate(n=3, src=work.r3_s1, key=PRECEDE_Study_ID)
%norm_key(n=3, src=work.r3_s1, key=PRECEDE_Study_ID)
%blank_key_gate(n=3)
%dedup(n=3)
%write_gapfill(n=3)

/* ========================================================================
   SECTION 4: r4 -- 2020_Precede_Database_Edu.xlsx (key=studyid CHARACTER)
   studyid confirmed character from import log.
   PCM-D-32: 0 duplicate PRECEDE_STUDY_IDs found after key normalization. */
%import_xlsx(r4, 2020_Precede_Database_Edu.xlsx)
%len_gate(n=4, src=work.r4_s1, key=studyid)
%norm_key(n=4, src=work.r4_s1, key=studyid)
%blank_key_gate(n=4)
%dedup(n=4, expected=&_r4_approved_removed)
%write_gapfill(n=4)

/* ========================================================================
   SECTION 5: r5 -- 2021_Education_20240124.csv (no known duplicates)    */
%import_csv(r5, 2021_Education_20240124.csv)
%len_gate(n=5, src=work.r5, key=PRECEDE_Study_ID)
%norm_key(n=5, src=work.r5, key=PRECEDE_Study_ID)
%blank_key_gate(n=5)
%dedup(n=5)
%write_gapfill(n=5)

/* ========================================================================
   SECTION 6: r6 -- 2021_Frailty_20240123.csv (no known duplicates)     */
%import_csv(r6, 2021_Frailty_20240123.csv)
%len_gate(n=6, src=work.r6, key=PRECEDE_Study_ID)
%norm_key(n=6, src=work.r6, key=PRECEDE_Study_ID)
%blank_key_gate(n=6)
%dedup(n=6)
%write_gapfill(n=6)

/* ========================================================================
   SUMMARY NOTE                                                            */
%put NOTE: [03r_prep_gapfill] Program complete. Review log for g.gapfill_rN creation status.;
%put NOTE: [03r_prep_gapfill] Files with no approved=Y columns in gapfill_allowlist.csv were skipped (no ERROR).;
%put NOTE: [03r_prep_gapfill] PCM-D-32 approved removal counts: r2=0, r4=0. See gate NOTEs above for actual counts.;
