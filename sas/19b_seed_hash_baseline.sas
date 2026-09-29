/*==========================================================================
  Program : 19b_seed_hash_baseline.sas
  Purpose : ONE-TIME seed of docs/raw_hash_baseline.csv from the verified
            sha256 values in qc/19_raw_files.csv (produced by program 19).

  IMPORTANT: This program is NOT part of run_pipeline.cmd and must NEVER
             be added to it.  Run it exactly once -- manually -- after
             program 19 has run successfully and you have confirmed that
             the eight md1-md8 source extracts are the correct, verified
             files.

  Preconditions:
    1. Program 19 (19_raw_dir_inventory.sas) must have completed
       successfully so that qc/19_raw_files.csv is current.
    2. docs/raw_hash_baseline.csv must NOT exist.  If it does, this
       program aborts with an explanatory message (D-09).

  Writes  : docs/raw_hash_baseline.csv  (C: drive, version-controlled)
            Columns: file_name, sha256, byte_size, seeded_date

  Does NOT write: nothing on the P: drive; does not touch 19_raw_files.csv.

  To re-seed (e.g. after a deliberate source update):
    1. Manually delete docs/raw_hash_baseline.csv
    2. Re-run program 19 on the new sources
    3. Re-run this program

  PCM compliance:
    - No bare open-code %IF/%THEN without named macro (Pitfall 7)
    - All conditional logic inside named macros
    - DATA step infile for CSV reads (PCM-T-16) -- no PROC IMPORT
    - %abort cancel only inside %fail_out
    - No PROC SQL UPDATE
    - ASCII only
==========================================================================*/

/* ============================================================
   SECTION 0 -- Header, %include, options
   ============================================================ */
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
options validvarname=v7 nofmterr msglevel=i;

title;


/* ============================================================
   SECTION 1 -- Utility macros
   ============================================================ */
%macro fail_out(msg=);
  %put ERROR: &msg;
  %abort cancel;
%mend fail_out;


/* ============================================================
   SECTION 2 -- Exists-guard: abort if baseline already present (D-09)
   ============================================================ */
%macro seed_guard;
  %if %sysfunc(fileexist("&docs_path.\raw_hash_baseline.csv")) %then %do;
    %put ERROR: SEED ABORTED -- docs/raw_hash_baseline.csv already exists.;
    %put ERROR: To re-seed, manually delete the file and re-run 19b.;
    %abort cancel;
  %end;
  %put NOTE: Exists-guard passed -- docs/raw_hash_baseline.csv not present; proceeding with seed.;
%mend seed_guard;
%seed_guard;


/* ============================================================
   SECTION 3 -- Validate source: qc/19_raw_files.csv must exist
   ============================================================ */
%macro check_source;
  %if not %sysfunc(fileexist("&qc_path.\19_raw_files.csv")) %then %do;
    %fail_out(msg=SEED ABORTED -- qc/19_raw_files.csv not found. Run program 19 first.);
  %end;
  %put NOTE: Source file qc/19_raw_files.csv found; proceeding with read.;
%mend check_source;
%check_source;


/* ============================================================
   SECTION 4 -- Validate header of qc/19_raw_files.csv (PCM-T-16)
   A DATA step cannot map columns by name, so we verify the header
   line first and fail loudly if the layout has changed.
   Expected header (from SECTION 12 of program 19 PROC EXPORT):
     full_path,filename,ext,fsize,fdate,sha256,status
   ============================================================ */
%macro check_raw_files_header;
  %local _hdr;
  data _null_;
    infile "&qc_path.\19_raw_files.csv" obs=1 truncover lrecl=500;
    input _infile_ $500.;
    call symputx('_hdr', strip(_infile_), 'L');
  run;
  %if %upcase(%trim(&_hdr)) ne %upcase(full_path,filename,ext,fsize,fdate,sha256,status) %then %do;
    %fail_out(msg=SEED ABORTED -- qc/19_raw_files.csv header does not match expected layout. Found: &_hdr);
  %end;
  %put NOTE: qc/19_raw_files.csv header verified: &_hdr;
%mend check_raw_files_header;
%check_raw_files_header;


/* ============================================================
   SECTION 5 -- Read qc/19_raw_files.csv (PCM-T-16: DATA step infile)
   Column positions match the verified header in SECTION 4.
   Filter to the md-master directory only.
   ============================================================ */
data work._raw_files_all;
  length full_path $500 filename $200 ext $20 fsize 8
         fdate $30 sha256 $64 status $30;
  infile "&qc_path.\19_raw_files.csv" dsd dlm=',' firstobs=2 truncover lrecl=1000;
  input full_path $ filename $ ext $ fsize fdate $ sha256 $ status $;
run;

/* Filter to the eight md-master source files only */
data work._md_master_files;
  set work._raw_files_all;
  where upcase(substr(full_path, 1, length(full_path) - length(filename) - 1))
        = upcase("&raw_path.\master");
run;


/* ============================================================
   SECTION 6 -- Assert exactly 8 md-master rows found
   ============================================================ */
%macro assert_eight_md_rows;
  %local n_md;
  %let n_md = 0;
  proc sql noprint;
    select count(*) into :n_md trimmed
    from work._md_master_files;
  quit;
  %if &n_md ne 8 %then %do;
    %fail_out(msg=SEED ABORTED -- expected 8 md1-md8 rows in md-master directory but found &n_md. Confirm program 19 ran successfully.);
  %end;
  %put NOTE: assert_eight_md_rows passed -- found &n_md md1-md8 rows in md-master directory.;
%mend assert_eight_md_rows;
%assert_eight_md_rows;


/* ============================================================
   SECTION 7 -- Build baseline dataset
   Columns: file_name (basename), sha256 (lowercase 64-hex),
            byte_size, seeded_date (YYYY-MM-DD)
   ============================================================ */
data work._baseline_out;
  set work._md_master_files;
  length file_name $200 sha256_lc $64 seeded_date $12;
  file_name   = strip(filename);
  sha256_lc   = lowcase(strip(sha256));
  byte_size   = fsize;
  seeded_date = put(today(), yymmdd10.);
  keep file_name sha256_lc byte_size seeded_date;
  rename sha256_lc = sha256;
run;


/* ============================================================
   SECTION 8 -- Write docs/raw_hash_baseline.csv (C: drive, git-tracked)
   Header must be: file_name,sha256,byte_size,seeded_date
   ============================================================ */
proc export data=work._baseline_out
  outfile="&docs_path.\raw_hash_baseline.csv"
  dbms=csv replace;
run;
%put NOTE: docs/raw_hash_baseline.csv written.;


/* ============================================================
   SECTION 9 -- Verify the output file was created
   ============================================================ */
%macro verify_baseline_written;
  %if not %sysfunc(fileexist("&docs_path.\raw_hash_baseline.csv")) %then %do;
    %fail_out(msg=SEED FAILED -- docs/raw_hash_baseline.csv was not created by PROC EXPORT.);
  %end;
  %put NOTE: docs/raw_hash_baseline.csv verified on disk.;
  %put NOTE: ==== 19b seed complete -- baseline is locked. Do not re-run 19b without deleting the file first. ====;
%mend verify_baseline_written;
%verify_baseline_written;
