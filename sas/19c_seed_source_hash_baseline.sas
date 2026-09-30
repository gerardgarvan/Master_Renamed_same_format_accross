/*==========================================================================
  Program : 19c_seed_source_hash_baseline.sas
  Purpose : ONE-TIME seed of docs/source_hash_baseline.csv from live
            sha256 hashes of the 8 renamed source extracts in &source_path
            (master_data_1.sas7bdat ... master_data_8.sas7bdat).

  IMPORTANT: NOT part of run_pipeline.cmd. Run exactly once after confirming
             the 8 renamed source extracts in &source_path are the correct
             verified files.

  To re-seed (e.g. after a deliberate source update):
    1. Delete docs/source_hash_baseline.csv
    2. Re-run this program
    3. REVIEW `git diff docs/source_hash_baseline.csv` before committing.
       This file is the trust anchor; an unexpected changed hash here is
       the tampering the guard exists to catch -- do not commit it blindly.

  Preconditions:
    1. docs/source_hash_baseline.csv must NOT have data rows.
       (A header-only stub produced by a failed seed run is safe to proceed;
       only a file with 1+ data rows causes the abort.)
    2. &src_hash_files must resolve to exactly 8 file names.
    3. All 8 files must be accessible and hashable.

  Writes  : docs/source_hash_baseline.csv  (C: drive, version-controlled)
            Columns: file_name,sha256,byte_size,seeded_date
            (program 19 SECTION 14 reads them positionally in this order)

  Does NOT write: nothing on the P: drive; does not touch qc/19_source_hash_check.csv.

  PCM compliance:
    - All conditional logic inside named macros (no open-code %IF)
    - DATA step infile for CSV reads (PCM-T-16) -- no PROC IMPORT
    - No quotes inside %sysfunc(fileexist(...)) (B-06)
    - %abort cancel only inside %fail_out
    - ASCII only
==========================================================================*/

/* ============================================================
   SECTION 0 -- Header, %include, options (config in OPEN CODE)
   ============================================================ */
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
options validvarname=v7 nofmterr msglevel=i;

title;


/* ============================================================
   SECTION 1 -- Utility macro: %fail_out
   ============================================================ */
%macro fail_out(msg=);
  %put ERROR: &msg;
  %abort cancel;
%mend fail_out;


/* ============================================================
   SECTION 2 -- Exists-guard:
   Count DATA ROWS in &src_hash_baseline (not just file existence).
   A header-only stub (0 data rows) is safe to overwrite.
   If the file has data rows, abort -- do not overwrite a valid baseline.
   Also checks that &src_hash_files resolves to exactly 8 names.
   ============================================================ */
%macro seed_guard;
  %local n_data_rows n_src_files;
  %let n_data_rows = 0;
  %let n_src_files = 0;

  /* Count data rows in existing baseline (skip header via firstobs=2) */
  %if %sysfunc(fileexist(&src_hash_baseline)) %then %do;
    data _null_;
      retain _cnt 0;
      infile "&src_hash_baseline" dsd dlm=',' firstobs=2 truncover lrecl=500 end=_eof;
      input;
      _cnt + 1;
      if _eof then call symputx('n_data_rows', _cnt, 'L');
    run;
    %if &n_data_rows > 0 %then %do;
      %fail_out(msg=SEED ABORTED -- docs/source_hash_baseline.csv already has &n_data_rows data row(s). Delete the file and re-run 19c to reseed.);
    %end;
  %end;

  /* Verify &src_hash_files has exactly 8 names */
  %let n_src_files = %sysfunc(countw(&src_hash_files, %str( )));
  %if &n_src_files ne 8 %then %do;
    %fail_out(msg=SEED ABORTED -- src_hash_files in 00_config.sas resolves to &n_src_files names -- expected 8.);
  %end;

  %put NOTE: Exists-guard passed -- no data rows in baseline (if any) and 8 src_hash_files confirmed.;
%mend seed_guard;
%seed_guard;


/* ============================================================
   SECTION 3 -- Compute live hashes of the 8 source sas7bdat files
   %src_hash_compute is defined in 00_config.sas (Phase 26 / HARD-02).
   ============================================================ */
%src_hash_compute(out=work._src_hash_now);


/* ============================================================
   SECTION 4 -- Assert all 8 files hashed successfully
   ============================================================ */
%macro assert_hash_ok;
  %local n_ok n_bad;
  %let n_ok  = 0;
  %let n_bad = 0;
  proc sql noprint;
    select count(*) into :n_ok  trimmed from work._src_hash_now where status = 'OK';
    select count(*) into :n_bad trimmed from work._src_hash_now where status ne 'OK';
  quit;
  %if &n_ok ne 8 or &n_bad > 0 %then %do;
    proc print data=work._src_hash_now noobs; run;
    %fail_out(msg=SEED ABORTED -- only &n_ok of 8 files hashed OK (&n_bad failures). Confirm source files are accessible in &source_path.);
  %end;
  %put NOTE: assert_hash_ok passed -- 8 files hashed OK.;
%mend assert_hash_ok;
%assert_hash_ok;


/* ============================================================
   SECTION 5 -- Build baseline rows, sorted by file_name (stable git diff)
   ============================================================ */
data work._baseline_out;
  set work._src_hash_now;
  length seeded_date $10;
  seeded_date = put(today(), yymmdd10.);
  keep file_name sha256 bytes seeded_date;
run;

proc sort data=work._baseline_out;
  by file_name;
run;


/* ============================================================
   SECTION 6 -- Write docs/source_hash_baseline.csv
   DATA step PUT (not PROC EXPORT): column ORDER must be exactly
   file_name,sha256,byte_size,seeded_date because program 19 SECTION 14
   reads the file positionally.
   ============================================================ */
data _null_;                                      /* header */
  file "&src_hash_baseline" lrecl=1000;
  put 'file_name,sha256,byte_size,seeded_date';
run;

data _null_;                                      /* rows */
  file "&src_hash_baseline" dsd mod lrecl=1000;
  set work._baseline_out;
  put file_name sha256 bytes :32. seeded_date;
run;
%put NOTE: docs/source_hash_baseline.csv written.;


/* ============================================================
   SECTION 7 -- Verify the output: exists, correct header, 8 data rows
   ============================================================ */
%macro verify_baseline_written;
  %local n_lines hdr_ok;
  %if not %sysfunc(fileexist(&src_hash_baseline)) %then %do;
    %fail_out(msg=SEED FAILED -- docs/source_hash_baseline.csv was not created.);
  %end;
  %let n_lines = 0;
  %let hdr_ok  = 0;
  data _null_;
    infile "&src_hash_baseline" truncover lrecl=1000 end=_eof;
    input;
    if _n_ = 1 then
      call symputx('hdr_ok', (strip(_infile_) = 'file_name,sha256,byte_size,seeded_date'), 'L');
    if _eof then call symputx('n_lines', _n_, 'L');
  run;
  %if &hdr_ok ne 1 or &n_lines ne 9 %then %do;
    %fail_out(msg=SEED FAILED -- docs/source_hash_baseline.csv has an unexpected header or &n_lines lines (expected 9 = 1 header + 8 data).);
  %end;
  %put NOTE: source_hash_baseline.csv verified -- header plus 8 rows.;
  %put NOTE: ==== 19c seed complete. Do not re-run without deleting the file first. ====;
%mend verify_baseline_written;
%verify_baseline_written;
