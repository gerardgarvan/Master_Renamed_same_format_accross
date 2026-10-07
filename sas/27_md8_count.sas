/*==========================================================================
  Program    : 27_md8_count.sas
  Phase      : Phase 27 -- md8 Row-Count Correction
  Purpose    : Standalone dual-count + contiguity + ID-agreement verification
               for md8.  Proves the 22,473 non-missing row figure via two
               independent counts and three confirmation checks, and commits
               the result to qc/27_md8_count.csv.  This settles MD8-01:
               md8's apparent "truncation" is trailing blank-row padding in
               the source XLSX, not lost data.

  IMPORTANT:  This program is NOT part of run_pipeline.cmd and must NEVER be added to it.
              Run it exactly once -- manually -- after src.master_data_8 is available.

  Requirements: MD8-01
  Author     : Executor (Phase 27 Plan 01)
  Created    : 2026-10-07

  PCM compliance:
    - All conditional logic inside named macros (no open-code %IF)
    - DATA step infile for CSV reads (PCM-T-16) -- never use the import procedure
    - %abort cancel only inside named macro definitions (PCM-R-05)
    - Never use &SQLOBS -- always SELECT COUNT(*) INTO :n TRIMMED
    - ASCII only
==========================================================================*/

options nofmterr msglevel=i;


/*==========================================================================
  SECTION 0: Paths and libnames
==========================================================================*/

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
libname src "&source_path" access=readonly;


/*==========================================================================
  SECTION 0b: Determine src.master_data_8 nobs and select Count A source
  If 03_prep_md8.sas already stripped the padding (nobs=22473), Count A
  must read the raw XLSX workbook directly.  If nobs=1048575, the pipeline
  source still carries all rows.
==========================================================================*/

proc sql noprint;
  select nobs into :src_nobs trimmed from dictionary.tables
  where libname='SRC' and memname='MASTER_DATA_8';
quit;
%put NOTE: src.master_data_8 nobs = &src_nobs;

/* Macro that sets &count_a_dsn and (when needed) assigns the XLSX libname */
%macro set_count_a_source;
  %global count_a_dsn xlsx_path_used;

  %if &src_nobs = 22473 %then %do;
    /* src already has stripped rows -- Count A must go to the raw XLSX */
    %put NOTE: src.master_data_8 has 22473 rows -- Count A reads raw XLSX workbook.;

    /* Try the source_path copy first; fall back to raw\master */
    %let _try1 = &source_path.\master_data_8.xlsx;
    %let _try2 = &raw_path.\master\ALL_AIM2_MASTER_DATASET_20210917.xlsx;

    %if %sysfunc(fileexist(&_try1)) %then %do;
      %let xlsx_path_used = &_try1;
    %end;
    %else %if %sysfunc(fileexist(&_try2)) %then %do;
      %let xlsx_path_used = &_try2;
    %end;
    %else %do;
      %put ERROR: Cannot find raw XLSX for Count A.;
      %put ERROR- Tried: &_try1;
      %put ERROR- Tried: &_try2;
      %abort cancel;
    %end;

    libname xlmd8 xlsx "&xlsx_path_used";
    %put NOTE: Count A XLSX libname assigned: &xlsx_path_used;

    /* Discover sheet name at run time */
    proc contents data=xlmd8._all_ out=work._xlmd8_sheets (keep=memname) noprint; run;
    proc sql noprint;
      select distinct memname into :_xlmd8_sheet trimmed
      from work._xlmd8_sheets;
    quit;
    %put NOTE: Count A XLSX sheet: &_xlmd8_sheet;
    %let count_a_dsn = xlmd8.&_xlmd8_sheet;
  %end;
  %else %if &src_nobs = 1048575 %then %do;
    %put NOTE: src.master_data_8 has 1048575 rows (padding present) -- Count A reads src directly.;
    %let count_a_dsn = src.master_data_8;
    %let xlsx_path_used = (src.master_data_8);
  %end;
  %else %do;
    %put ERROR: Unexpected src_nobs=&src_nobs for src.master_data_8.;
    %put ERROR- Expected 22473 (padding stripped) or 1048575 (full with padding).;
    %abort cancel;
  %end;
%mend set_count_a_source;
%set_count_a_source;


/*==========================================================================
  SECTION 1: Preconditions
==========================================================================*/

%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: LIBNAME &lib could not be assigned.; %abort cancel;
  %end;
  %else %put NOTE: LIBNAME &lib resolved.;
%mend check_libname;

%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: &label directory missing: &path; %abort cancel;
  %end;
  %else %put NOTE: &label directory found: &path;
%mend check_dir;

%macro check_file(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: Required file missing -- &label: &path; %abort cancel;
  %end;
  %else %put NOTE: File found -- &label: &path;
%mend check_file;

%check_libname(lib=src);
%check_dir(path=&qc_path, label=qc);
%check_file(path=&qc_path.\19_raw_files.csv,
            label=19_raw_files.csv -- run program 19 first if missing);

/* When Count A reads raw XLSX, also verify that file exists */
%macro check_xlsx_precond;
  %if &src_nobs = 22473 %then %do;
    %check_file(path=&xlsx_path_used,
                label=Count A XLSX source);
  %end;
%mend check_xlsx_precond;
%check_xlsx_precond;


/*==========================================================================
  SECTION 2: COUNT A -- any-column non-missing sweep over &count_a_dsn

  SELF-REFERENCE TRAP: the two array declarations MUST be the very first
  statements after SET, before any new variable is created in the PDV.
  If helper variables appear before the arrays, SAS includes them in
  _NUMERIC_ and their non-missing values falsely inflate the count.

  vname() guard: helper numerics (_n_nonmiss, _i, _j) are excluded by name
  from the numeric loop so they never trigger a false positive.
==========================================================================*/

data work.md8_flags;
  set &count_a_dsn;
  array _charv {*} _CHARACTER_;   /* FIRST statement: before any new variable */
  array _numv  {*} _NUMERIC_;     /* SECOND statement: before any new variable */
  _n_nonmiss = 0;
  do _i = 1 to dim(_charv);
    if not missing(_charv{_i}) and upcase(strip(_charv{_i})) ne 'NULL'
      then _n_nonmiss = _n_nonmiss + 1;
  end;
  do _j = 1 to dim(_numv);
    if vname(_numv{_j}) not in ('_n_nonmiss','_i','_j')
      and not missing(_numv{_j})
      then _n_nonmiss = _n_nonmiss + 1;
  end;
  row_pos = _n_;
  nonmiss = (_n_nonmiss > 0);
  keep row_pos nonmiss;
run;

proc sql noprint;
  select count(*) into :count_a trimmed from work.md8_flags where nonmiss=1;
quit;
%put NOTE: Count A (&count_a_dsn any-column non-missing) = &count_a;


/*==========================================================================
  SECTION 2b: CONTIGUITY check
  For pure trailing padding, last non-missing row position must equal count_a.
==========================================================================*/

proc sql noprint;
  select max(row_pos) into :last_nonmiss trimmed
  from work.md8_flags where nonmiss=1;
quit;
%put NOTE: Last non-missing row position = &last_nonmiss (must equal &count_a for pure trailing padding);


/*==========================================================================
  SECTION 2c: PRECEDE_STUDY_ID agreement check
  Run against the same source as Count A.
==========================================================================*/

proc sql noprint;
  select count(*) into :id_count trimmed from &count_a_dsn
  where not missing(PRECEDE_STUDY_ID)
    and upcase(strip(PRECEDE_STUDY_ID)) ne 'NULL';
quit;
%put NOTE: Non-missing PRECEDE_STUDY_ID count = &id_count (must equal 22473);


/*==========================================================================
  SECTION 3: COUNT B -- independent any-column non-missing sweep on
  raw\ALL_AIM2_MASTER_DATASET_20210917.xlsx via XLSX libname.
  This is a genuine independent count from a different file.
  The sweep takes approximately 8 seconds; that is expected.
==========================================================================*/

libname rawaim xlsx "&raw_path.\ALL_AIM2_MASTER_DATASET_20210917.xlsx";

/* Discover the sheet name at run time */
proc contents data=rawaim._all_ out=work._rawaim_sheets (keep=memname) noprint; run;
proc sql noprint;
  select distinct memname into :_rawaim_sheet trimmed
  from work._rawaim_sheets;
quit;
%put NOTE: Count B XLSX sheet: &_rawaim_sheet;

data work.raw_flags;
  set rawaim.&_rawaim_sheet;
  array _charv {*} _CHARACTER_;   /* FIRST: before any new variable */
  array _numv  {*} _NUMERIC_;     /* SECOND: before any new variable */
  _n_nonmiss = 0;
  do _i = 1 to dim(_charv);
    if not missing(_charv{_i}) and upcase(strip(_charv{_i})) ne 'NULL'
      then _n_nonmiss = _n_nonmiss + 1;
  end;
  do _j = 1 to dim(_numv);
    if vname(_numv{_j}) not in ('_n_nonmiss','_i','_j')
      and not missing(_numv{_j})
      then _n_nonmiss = _n_nonmiss + 1;
  end;
  row_pos = _n_;
  nonmiss = (_n_nonmiss > 0);
  keep row_pos nonmiss;
run;

proc sql noprint;
  select count(*) into :count_b trimmed from work.raw_flags where nonmiss=1;
quit;
%put NOTE: Count B (raw XLSX all-column non-missing) = &count_b;


/*==========================================================================
  SECTION 3b: SHA-256 DIFFERENCE pre-condition (D-02)
  Read qc/19_raw_files.csv via DATA step infile (PCM-T-16 -- no import procedure).
  Select rows BY PATH (filename + directory pattern) -- NOT by file_id.
  Header: full_path,filename,ext,fsize,fdate,sha256,status,nobs,ncols,
          fail_reason,import_warning,file_id  (12 columns, positional read).
  raw\ copy:        filename='ALL_AIM2_MASTER_DATASET_20210917.xlsx' and index(full_path,'master')=0
  raw\master\ copy: filename='ALL_AIM2_MASTER_DATASET_20210917.xlsx' and index(full_path,'master')>0
==========================================================================*/

data work._sha_check;
  length full_path $ 500 filename $ 100 ext $ 10 fsize $ 20 fdate $ 30
         sha256 $ 64 status $ 20 nobs $ 20 ncols $ 20
         fail_reason $ 200 import_warning $ 200 file_id $ 20
         sha_raw $ 64 sha_master $ 64;
  retain sha_raw '' sha_master '';

  infile "&qc_path.\19_raw_files.csv" dsd dlm=',' firstobs=2
         truncover lrecl=2000 end=_eof;
  input full_path $ filename $ ext $ fsize $ fdate $ sha256 $ status $
        nobs $ ncols $ fail_reason $ import_warning $ file_id $;

  if filename='ALL_AIM2_MASTER_DATASET_20210917.xlsx'
    and index(full_path,'master')=0
  then sha_raw = sha256;

  if filename='ALL_AIM2_MASTER_DATASET_20210917.xlsx'
    and index(full_path,'master')>0
  then sha_master = sha256;

  if _eof then output;
  keep sha_raw sha_master;
run;

/* Extract macro variables from the single output row */
proc sql noprint;
  select sha_raw, sha_master into :sha_raw trimmed, :sha_master trimmed
  from work._sha_check;
quit;

%macro assert_sha_precond;
  /* raw\ copy must be present */
  %if %length(&sha_raw) = 0 %then %do;
    %put ERROR: SHA-256 pre-condition -- raw\ copy of ALL_AIM2_MASTER_DATASET_20210917.xlsx;
    %put ERROR- not found in qc/19_raw_files.csv -- run program 19 first.;
    %abort cancel;
  %end;
  %else %put NOTE: SHA raw\  copy found: &sha_raw;

  /* raw\master\ copy must be present */
  %if %length(&sha_master) = 0 %then %do;
    %put ERROR: SHA-256 pre-condition -- raw\master copy of ALL_AIM2_MASTER_DATASET_20210917.xlsx;
    %put ERROR- not found in qc/19_raw_files.csv -- run program 19 first.;
    %put ERROR- (sha_master ne '' check failed -- no silent skip);
    %abort cancel;
  %end;
  %else %put NOTE: SHA raw\master copy found: &sha_master;

  /* The two copies must have DIFFERENT sha256 values */
  %if &sha_raw = &sha_master %then %do;
    %put ERROR: SHA-256 difference pre-condition FAILED.;
    %put ERROR- The two AIM2 copies have the same sha256 (&sha_raw).;
    %put ERROR- This means the raw\ copy is the same file as raw\master -- not an independent source.;
    %put ERROR- The 1048575-row figure would be an artifact of the same file, not an independent observation.;
    %abort cancel;
  %end;
  %else %do;
    %put NOTE: SHA-256 difference confirmed -- the two AIM2 copies are distinct files.;
    %put NOTE: sha_raw    = &sha_raw;
    %put NOTE: sha_master = &sha_master;
  %end;
%mend assert_sha_precond;
%assert_sha_precond;


/*==========================================================================
  SECTION 4: Write qc/27_md8_count.csv via DATA step PUT (NOT PROC EXPORT)
  Header:  count_source,row_count,last_nonmissing_pos,precede_id_count,pass_fail
  Row 1:   pipeline_any_column (Count A)
  Row 2:   raw_aim2_xlsx       (Count B)
  pass_fail = PASS when row_count = 22473 (and for row 1 also
              last_nonmiss=22473 and id_count=22473), else FAIL.
==========================================================================*/

%macro write_csv;
  %local pf_a pf_b;

  /* Determine pass/fail for Count A */
  %if &count_a = 22473 and &last_nonmiss = 22473 and &id_count = 22473 %then
    %let pf_a = PASS;
  %else
    %let pf_a = FAIL;

  /* Determine pass/fail for Count B */
  %if &count_b = 22473 %then
    %let pf_b = PASS;
  %else
    %let pf_b = FAIL;

  filename csvout "&qc_path.\27_md8_count.csv";
  data _null_;
    file csvout;
    put "count_source,row_count,last_nonmissing_pos,precede_id_count,pass_fail";
    put "pipeline_any_column,&count_a,&last_nonmiss,&id_count,&pf_a";
    put "raw_aim2_xlsx,&count_b,.,.,&pf_b";
  run;
  filename csvout clear;
  %put NOTE: qc/27_md8_count.csv written (Count A &pf_a, Count B &pf_b).;
%mend write_csv;
%write_csv;


/*==========================================================================
  SECTION 5: Assertions (PCM-R-05 -- all %abort cancel inside named macros)
==========================================================================*/

%macro assert_eq_local(actual=, expected=, msg=);
  %if &actual ne &expected %then %do;
    %put ERROR: &msg -- expected &expected got &actual; %abort cancel;
  %end;
  %else %put NOTE: OK -- &msg (&actual);
%mend assert_eq_local;

/* Side-by-side summary before assertion chain */
%put NOTE: md8 COUNT A (&count_a_dsn any-column) = &count_a | COUNT B (raw XLSX) = &count_b;

%assert_eq_local(actual=&count_a,     expected=22473, msg=md8 any-column non-missing count);
%assert_eq_local(actual=&last_nonmiss,expected=22473, msg=md8 last non-missing row position (contiguity));
%assert_eq_local(actual=&id_count,    expected=22473, msg=md8 non-missing PRECEDE_STUDY_ID count);
%assert_eq_local(actual=&count_b,     expected=22473, msg=md8 independent count from raw XLSX);

/* Do NOT clear libname src */
%put NOTE: ==== 27_md8_count complete -- dual count 22473 confirmed, three checks passed ====;
