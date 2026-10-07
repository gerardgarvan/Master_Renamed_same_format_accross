/* 29_gapfill_compare.sas -- Phase 29 GAP-03 verification tool
   Two-pass program:
     Pass 1 (run BEFORE 04_merge.sas wiring): takes PROC COPY snapshot
     Pass 2 (run AFTER full pipeline including 10b): runs PROC COMPARE on original columns

   This program is NOT in run_pipeline.cmd. Run manually as:
     sas.exe "C:\Master_Renamed_same_format_accross\sas\29_gapfill_compare.sas"

   PCM compliance:
     - All conditional logic inside named macros (no open-code %IF)
     - %abort cancel only inside named macro definitions (PCM-R-05)
     - Never use &SQLOBS -- always SELECT COUNT(*) INTO :n TRIMMED
     - %sysfunc(fileexist()) with no quotes inside %sysfunc
     - %sysfunc(dcreate()) with no quotes inside %sysfunc; success confirmed via fileexist AFTER call
     - ASCII only
*/

options nofmterr msglevel=i nodate nonumber ps=max ls=200;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

%macro fail_out(msg=);
  %put ERROR: [29_gapfill_compare] &msg;
  %abort cancel;
%mend fail_out;

/* -----------------------------------------------------------------------
   Assign snap libname unconditionally at top so PASS 2 can reference
   snap.* datasets without re-assignment inside the macro.
   ----------------------------------------------------------------------- */
libname snap "&snap_path";
libname g    "&g_path";

/* -----------------------------------------------------------------------
   Determine pass: physical file existence decides pass 1 vs pass 2.
   Bug-correct approach: use %sysfunc(fileexist()) on the physical .sas7bdat
   file -- NOT dictionary.members (which requires the libname to already be
   assigned and populated). No quotes inside %sysfunc().
   ----------------------------------------------------------------------- */

%macro run_compare_passes;
  %let _snap_file = &snap_path.\master_data_merged.sas7bdat;
  %let _snap_exists = %sysfunc(fileexist(&_snap_file));

  %if &_snap_exists = 0 %then %do;
    /* ---- PASS 1: Snapshot does not exist -- take baseline snapshot ---- */
    %put NOTE: [29_gapfill_compare PASS 1] snap\master_data_merged.sas7bdat not found -- taking baseline snapshot;
    %put NOTE: Run this program BEFORE 04_merge.sas wiring. After snapshot is taken%str(,);
    %put NOTE: run the full pipeline (03r -> 04_merge -> 10b -> ...)%str(,) then re-run this program for PASS 2.;

    /* Verify g.master_data_merged exists before snapping */
    %let _n_tab = 0;
    proc sql noprint;
      select count(*) into :_n_tab trimmed
      from dictionary.tables
      where libname='G' and memname='MASTER_DATA_MERGED';
    quit;
    %if &_n_tab = 0 %then %do;
      %fail_out(msg=g.master_data_merged not found in g library -- run Phase 4 (04_merge.sas) first before taking the snapshot);
    %end;

    %let _n_harm_tab = 0;
    proc sql noprint;
      select count(*) into :_n_harm_tab trimmed
      from dictionary.tables
      where libname='G' and memname='MASTER_DATA_HARMONIZED';
    quit;
    %if &_n_harm_tab = 0 %then %do;
      %fail_out(msg=g.master_data_harmonized not found -- run 10b_concept_harmonize.sas first before taking the snapshot);
    %end;

    /* Create snap directory if it does not exist */
    %if %sysfunc(fileexist(&snap_path)) = 0 %then %do;
      %let _dcreate_result = %sysfunc(dcreate(snap, &source_path));
      /* dcreate returns new path on success%str(,) blank on failure -- check via fileexist */
      %if %sysfunc(fileexist(&snap_path)) = 0 %then %do;
        %fail_out(msg=Could not create snap directory at &snap_path -- create it manually on P: drive before re-running);
      %end;
    %end;

    proc copy in=g out=snap;
      select master_data_merged master_data_harmonized;
    run;

    %put NOTE: [29_gapfill_compare PASS 1] Baseline snapshot written to &snap_path;
    %put NOTE: snap\master_data_merged.sas7bdat and snap\master_data_harmonized.sas7bdat created;
    %put NOTE: Next step: run the full pipeline including 04_merge.sas (with r1-r6 gap-fill wiring) and 10b%str(,) then re-run this program for PASS 2.;
  %end;

  %else %do;
    /* ---- PASS 2: Snapshot exists -- run PROC COMPARE ---- */
    %put NOTE: [29_gapfill_compare PASS 2] Baseline snapshot found -- running PROC COMPARE;

    /* Verify snap and g datasets exist before comparing */
    %let _n_snap = 0;
    proc sql noprint;
      select count(*) into :_n_snap trimmed
      from dictionary.tables
      where libname='SNAP' and memname='MASTER_DATA_MERGED';
    quit;
    %if &_n_snap = 0 %then %do;
      %fail_out(msg=snap.master_data_merged not found in snap library -- check that snap_path is correct and PASS 1 completed successfully);
    %end;

    /* Derive original column list from snap (excludes new extension columns added by gap-fill wiring) */
    proc sql noprint;
      select name into :_orig_merged_cols separated by ' '
      from dictionary.columns
      where libname='SNAP' and memname='MASTER_DATA_MERGED'
        and upcase(name) ne 'PRECEDE_STUDY_ID';
    quit;

    %if %length(&_orig_merged_cols) = 0 %then %do;
      %fail_out(msg=No columns found in snap.master_data_merged -- the snapshot may be corrupt or empty);
    %end;

    proc compare base=snap.master_data_merged
                 compare=g.master_data_merged
                 noprint;
      id PRECEDE_STUDY_ID;
      var &_orig_merged_cols;
    run;

    %macro assert_no_value_diffs_merged;
      /* sysinfo bit meanings (SAS PROC COMPARE documentation):
           1     = dataset labels differ
           2     = dataset types differ
           4     = variable has different attributes
           8     = variable has different types (char vs num)
           16    = variable has different length
           32    = variable has different label
           64    = base has ID values not in compare
           128   = compare has ID values not in base
           256   = base has observations not in compare (by value)
           512   = compare has observations not in base (by value)
           1024  = base has variable not in compare
           2048  = compare has variable not in base (EXPECTED after wiring -- new gap-fill columns)
           4096  = value differences found in common variables
           8192  = variable type changed between datasets
           16384 = variable length changed
           32768 = PROC COMPARE itself errored
         Assert that NO unexpected bits are set.
         Allow bit 2048 (compare has new gap-fill columns not in base -- expected).
         Unexpected bits mask: 64+128+4096+8192+32768 = 45248. Expect 0. */
      %if %eval(&sysinfo & 45248) ne 0 %then %do;
        %fail_out(msg=GAP-03 FAILED -- PROC COMPARE sysinfo &sysinfo has unexpected bits set (mask 45248) -- existing rows were altered or IDs changed in g.master_data_merged);
      %end;
      %else %do;
        %put NOTE: [GAP-03] PROC COMPARE PASSED (sysinfo=&sysinfo) -- g.master_data_merged original columns are byte-identical to baseline snapshot;
      %end;
    %mend assert_no_value_diffs_merged;
    %assert_no_value_diffs_merged;

    /* Repeat for master_data_harmonized */
    %let _n_snap_harm = 0;
    proc sql noprint;
      select count(*) into :_n_snap_harm trimmed
      from dictionary.tables
      where libname='SNAP' and memname='MASTER_DATA_HARMONIZED';
    quit;
    %if &_n_snap_harm = 0 %then %do;
      %fail_out(msg=snap.master_data_harmonized not found in snap library -- re-run PASS 1 after confirming 10b ran successfully);
    %end;

    proc sql noprint;
      select name into :_orig_harmon_cols separated by ' '
      from dictionary.columns
      where libname='SNAP' and memname='MASTER_DATA_HARMONIZED'
        and upcase(name) ne 'PRECEDE_STUDY_ID';
    quit;

    %if %length(&_orig_harmon_cols) = 0 %then %do;
      %fail_out(msg=No columns found in snap.master_data_harmonized -- the snapshot may be corrupt or empty);
    %end;

    proc compare base=snap.master_data_harmonized
                 compare=g.master_data_harmonized
                 noprint;
      id PRECEDE_STUDY_ID;
      var &_orig_harmon_cols;
    run;

    %macro assert_no_value_diffs_harmon;
      %if %eval(&sysinfo & 45248) ne 0 %then %do;
        %fail_out(msg=GAP-03 FAILED -- PROC COMPARE sysinfo &sysinfo has unexpected bits set (mask 45248) for g.master_data_harmonized);
      %end;
      %else %do;
        %put NOTE: [GAP-03] PROC COMPARE PASSED (sysinfo=&sysinfo) -- g.master_data_harmonized original columns are byte-identical to baseline snapshot;
      %end;
    %mend assert_no_value_diffs_harmon;
    %assert_no_value_diffs_harmon;

    %put NOTE: [29_gapfill_compare PASS 2] GAP-03 verification complete;
  %end;
%mend run_compare_passes;
%run_compare_passes;
