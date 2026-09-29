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
            Columns, in this order: file_name, sha256, byte_size, seeded_date
            (program 19's hash guard reads them positionally in this order)

  Does NOT write: nothing on the P: drive; does not touch 19_raw_files.csv.

  To re-seed (e.g. after a deliberate source update):
    1. Manually delete docs/raw_hash_baseline.csv (the old version stays
       in git history -- the file is committed)
    2. Re-run program 19 on the new sources
    3. Re-run this program
    4. REVIEW `git diff docs/raw_hash_baseline.csv` before committing:
       exactly the files you meant to replace should show new hashes.
       This file is the trust anchor; an unexpected changed hash here is
       the tampering the guard exists to catch -- do not commit it.

  PCM compliance:
    - All conditional logic inside named macros (no open-code %IF)
    - DATA step infile for CSV reads (PCM-T-16) -- no PROC IMPORT
    - No quotes inside %sysfunc(fileexist(...)) (B-06): %sysfunc passes
      them through literally, so the file is never found
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
   REQUIRED BEFORE FIRST RUN: the eight expected md-master file names,
   space-separated, copied from program 19 SECTION 11b (work.required_files).
   The seed refuses to run while this is blank, so "any eight files in
   the directory" can never become the baseline.
   ============================================================ */
%let md_expected_files = ;


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
  %if %sysfunc(fileexist(&docs_path.\raw_hash_baseline.csv)) %then %do;
    %fail_out(msg=SEED ABORTED -- docs/raw_hash_baseline.csv already exists. To re-seed delete the file and re-run 19b.);
  %end;
  %if %length(&md_expected_files) = 0 or %sysfunc(countw(&md_expected_files, %str( ))) ne 8 %then %do;
    %fail_out(msg=SEED ABORTED -- set md_expected_files to the eight md-master file names from program 19 SECTION 11b.);
  %end;
  %put NOTE: Exists-guard passed -- docs/raw_hash_baseline.csv not present, proceeding with seed.;
%mend seed_guard;
%seed_guard;


/* ============================================================
   SECTION 3 -- Validate source: qc/19_raw_files.csv must exist
   ============================================================ */
%macro check_source;
  %if not %sysfunc(fileexist(&qc_path.\19_raw_files.csv)) %then %do;
    %fail_out(msg=SEED ABORTED -- qc/19_raw_files.csv not found. Run program 19 first.);
  %end;
  %put NOTE: Source file qc/19_raw_files.csv found, proceeding with read.;
%mend check_source;
%check_source;


/* ============================================================
   SECTION 4 -- Validate header of qc/19_raw_files.csv (PCM-T-16)
   A DATA step cannot map columns by name, so verify the header line
   first and fail loudly if the layout has changed.
   The comparison is done in the DATA step: the header contains commas,
   which would split the arguments of %upcase/%trim/%fail_out.
   ============================================================ */
%macro check_raw_files_header;
  %local _hdr_ok _hdr_disp;
  %let _hdr_ok = 0;
  data _null_;
    infile "&qc_path.\19_raw_files.csv" obs=1 truncover lrecl=2000;
    input;
    length _h $2000;
    _h = upcase(compress(_infile_, '"'));      /* PROC EXPORT may quote names */
    call symputx('_hdr_ok',
                 (strip(_h) = 'FULL_PATH,FILENAME,EXT,FSIZE,FDATE,SHA256,STATUS'), 'L');
    call symputx('_hdr_disp', translate(strip(_infile_), '|', ','), 'L');
  run;
  %if &_hdr_ok ne 1 %then %do;
    %fail_out(msg=SEED ABORTED -- qc/19_raw_files.csv header is not full_path|filename|ext|fsize|fdate|sha256|status. Found: %superq(_hdr_disp));
  %end;
  %put NOTE: qc/19_raw_files.csv header verified.;
%mend check_raw_files_header;
%check_raw_files_header;


/* ============================================================
   SECTION 5 -- Read qc/19_raw_files.csv (PCM-T-16: DATA step infile)
   Column order matches the header verified in SECTION 4.
   fsize is read as text and converted with COMMAw. because PROC EXPORT
   writes formatted values (a COMMA format would quote "1,234,567").
   Keep only files directly in the md-master directory.
   ============================================================ */
data work._md_master_files;
  length full_path $500 filename $200 ext $20 fsize_c $40 fsize 8
         fdate $30 sha256 $200 status $30;
  infile "&qc_path.\19_raw_files.csv" dsd dlm=',' firstobs=2 truncover lrecl=2000;
  input full_path $ filename $ ext $ fsize_c $ fdate $ sha256 $ status $;
  fsize = input(strip(fsize_c), comma32.);
  if upcase(strip(full_path)) = upcase(cats("&raw_path.\master\", filename));
  drop fsize_c;
run;


/* ============================================================
   SECTION 6 -- Assert exactly 8 distinct md-master files, each with a
   well-formed 64-hex sha256 (a failed certutil call leaves text or blank)
   ============================================================ */
%macro assert_md_rows;
  %local n_md n_distinct n_badhash n_badsize n_unexpected;
  %let n_md = 0;
  proc sql noprint;
    select count(*),
           count(distinct upcase(filename)),
           coalesce(sum(lengthn(strip(sha256)) ne 64 or notxdigit(strip(sha256)) > 0), 0),
           coalesce(sum(missing(fsize) or fsize <= 0), 0),
           coalesce(sum(indexw(upcase("&md_expected_files"), upcase(strip(filename)), ' ') = 0), 0)
      into :n_md trimmed, :n_distinct trimmed, :n_badhash trimmed,
           :n_badsize trimmed, :n_unexpected trimmed
    from work._md_master_files;
  quit;
  %if &n_md ne 8 %then %do;
    %fail_out(msg=SEED ABORTED -- expected 8 files in &raw_path.\master but found &n_md. Confirm program 19 ran successfully.);
  %end;
  %if &n_distinct ne 8 %then %do;
    %fail_out(msg=SEED ABORTED -- md-master file names are not distinct (&n_distinct distinct of 8).);
  %end;
  %if &n_unexpected ne 0 %then %do;
    %fail_out(msg=SEED ABORTED -- &n_unexpected md-master files are not in md_expected_files.);
  %end;
  %if &n_badhash ne 0 %then %do;
    %fail_out(msg=SEED ABORTED -- &n_badhash md-master rows have a sha256 that is not 64 hex characters. Re-run program 19.);
  %end;
  %if &n_badsize ne 0 %then %do;
    %fail_out(msg=SEED ABORTED -- &n_badsize md-master rows have a missing or non-positive file size.);
  %end;
  %put NOTE: assert_md_rows passed -- the 8 expected md-master files, valid sha256 and size.;
%mend assert_md_rows;
%assert_md_rows;


/* ============================================================
   SECTION 7 -- Build baseline rows (sorted for a stable git diff)
   ============================================================ */
data work._baseline_out;
  set work._md_master_files;
  length file_name $200 sha256_lc $64 seeded_date $10;
  file_name   = strip(filename);
  sha256_lc   = lowcase(strip(sha256));
  byte_size   = fsize;
  seeded_date = put(today(), yymmdd10.);
  keep file_name sha256_lc byte_size seeded_date;
run;

proc sort data=work._baseline_out;
  by file_name;
run;


/* ============================================================
   SECTION 8 -- Write docs/raw_hash_baseline.csv (C: drive, git-tracked)
   DATA step PUT, not PROC EXPORT: the column ORDER must be exactly
   file_name,sha256,byte_size,seeded_date because program 19 reads the
   file positionally. (PROC EXPORT follows PDV order, which here would
   put seeded_date before byte_size.)
   ============================================================ */
data _null_;                                      /* header */
  file "&docs_path.\raw_hash_baseline.csv" lrecl=1000;
  put 'file_name,sha256,byte_size,seeded_date';
run;

data _null_;                                      /* rows */
  file "&docs_path.\raw_hash_baseline.csv" dsd mod lrecl=1000;
  set work._baseline_out;
  put file_name sha256_lc byte_size :32. seeded_date;
run;
%put NOTE: docs/raw_hash_baseline.csv written.;


/* ============================================================
   SECTION 9 -- Verify the output: exists, header, 8 data rows
   ============================================================ */
%macro verify_baseline_written;
  %local n_lines hdr_ok;
  %if not %sysfunc(fileexist(&docs_path.\raw_hash_baseline.csv)) %then %do;
    %fail_out(msg=SEED FAILED -- docs/raw_hash_baseline.csv was not created.);
  %end;
  %let n_lines = 0;
  %let hdr_ok  = 0;
  data _null_;
    infile "&docs_path.\raw_hash_baseline.csv" truncover lrecl=1000 end=_eof;
    input;
    if _n_ = 1 then
      call symputx('hdr_ok', (strip(_infile_) = 'file_name,sha256,byte_size,seeded_date'), 'L');
    if _eof then call symputx('n_lines', _n_, 'L');
  run;
  %if &hdr_ok ne 1 or &n_lines ne 9 %then %do;
    %fail_out(msg=SEED FAILED -- docs/raw_hash_baseline.csv has an unexpected header or &n_lines lines (expected 9).);
  %end;
  %put NOTE: docs/raw_hash_baseline.csv verified -- header plus 8 rows.;
  %put NOTE: ==== 19b seed complete -- baseline is locked. Do not re-run 19b without deleting the file first. ====;
%mend verify_baseline_written;
%verify_baseline_written;
