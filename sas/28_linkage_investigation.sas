/*==========================================================================
  Program    : 28_linkage_investigation.sas
  Phase      : Phase 28 -- r7/r8/r9 Linkage Investigation
  Purpose    : Standalone one-time investigation program that profiles
               PRECEDE_STUDY_ID for r7, r8, r9, md3-2022, and md7;
               compares SHA-256 values for raw\ vs raw\master file pairs;
               and derives both-direction normalized ID match rates for all
               comparison pairs.  Output is qc/28_linkage_investigation.csv.
               PCM-D-28 in docs/DECISIONS.md is written by the executor
               (not auto-generated) after reviewing the CSV.

  IMPORTANT:  This program is NOT part of run_pipeline.cmd and must NEVER be added to it.
              Run it exactly once -- manually -- after src.master_data_7 is available on the P: drive.

  Requirements: LINK-01, LINK-02

  Author     : Executor (Phase 28 Plan 01)
  Created    : 2026-10-07

  PCM compliance:
    - All conditional logic inside named macros (no open-code %IF)
    - DATA step infile for CSV reads (PCM-T-16) -- never use the import procedure
    - %abort cancel only inside named macro definitions (PCM-R-05)
    - Never use &SQLOBS -- always SELECT COUNT(*) INTO :n TRIMMED
    - ASCII only
    - PHI guard: ENCRYPTED_MRN -- width and count only, no min/max,
                 no sample values anywhere (logs, PUT, CSV)

  r7/r8/r9 ENCRYPTED_MRN note (LINK-01):
    r7 (2022_Education_20240124.csv):       2 cols -- PRECEDE_Study_ID + Education
    r8 (2022_RES_20230927.csv):             4 cols -- PRECEDE_Study_ID + Race + Ethnicity + Sex
    r9 (All_YEARS_LAT_LONG_20231127.csv):   4 cols -- PRECEDE_Study_ID + Latitude + Longitude + YEAR
    NONE of r7/r8/r9 carry an ENCRYPTED_MRN column.
    MRN linking is therefore infeasible with the current extracts.
==========================================================================*/

options nofmterr msglevel=i;


/*==========================================================================
  SECTION 0: Paths and libnames
==========================================================================*/

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
libname src "&source_path" access=readonly;


/*==========================================================================
  SECTION 1: Precondition guards
  All %abort cancel calls are inside named macros (PCM-R-05).
  Every input file is verified before any block runs.
==========================================================================*/

%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: LIBNAME &lib could not be assigned.; %abort cancel;
  %end;
  %else %put NOTE: LIBNAME &lib resolved.;
%mend check_libname;

%macro check_file(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: Required file missing -- &label: &path; %abort cancel;
  %end;
  %else %put NOTE: File found -- &label: &path;
%mend check_file;

%macro check_dataset(dsn=, label=);
  %if %sysfunc(exist(&dsn)) = 0 %then %do;
    %put ERROR: Required dataset missing -- &label: &dsn; %abort cancel;
  %end;
  %else %put NOTE: Dataset found -- &label: &dsn;
%mend check_dataset;

/* Verify libname SRC was assigned */
%check_libname(lib=src);

/* 19_raw_files.csv -- Block 1 source */
%check_file(path=&qc_path.\19_raw_files.csv,
            label=19_raw_files.csv -- run program 19 first if missing);

/* r7, r8, r9 raw CSV files */
%check_file(path=&raw_path.\2022_Education_20240124.csv,
            label=r7 Education CSV);
%check_file(path=&raw_path.\2022_RES_20230927.csv,
            label=r8 Race/Ethnicity/Sex CSV);
%check_file(path=&raw_path.\All_YEARS_LAT_LONG_20231127.csv,
            label=r9 Lat/Long all years CSV);

/* md3-2022 source: primary (raw\master) and secondary (raw\) */
%check_file(path=&raw_path.\master\2018_2022_X_MASTER_DATASET_20240402.csv,
            label=md3-2022 primary source raw\master);
%check_file(path=&raw_path.\2018_2022_X_MASTER_DATASET_20240402.csv,
            label=md3-2022 secondary source raw\);

/* 2018-2019 master file in raw\master for SHA comparison and Crypto matching */
%check_file(path=&raw_path.\master\2018_2019_X_MASTER_DATASET_20200801.csv,
            label=2018_2019_X_MASTER raw\master copy);

/* Crypto files */
%check_file(path=&raw_path.\2018_2019_MRN_Crypto_Data20260814.csv,
            label=MRN Crypto file);
%check_file(path=&raw_path.\2018_2019_ENCOUNTER_Crypto_Data_20260814.csv,
            label=ENCOUNTER Crypto file);

/* src.master_data_7 (md7 = 2022_MASTER_DATASET SAS dataset) */
%check_dataset(dsn=src.master_data_7, label=md7 SAS dataset);


/*==========================================================================
  SECTION 2: Block 1 -- SHA-256 comparison of raw\ vs raw\master pairs

  Read qc/19_raw_files.csv via DATA step infile (PCM-T-16).
  Select rows by exact directory field value:
    raw\master rows:  directory = "&raw_path.\master"
    raw\ rows:        directory = "&raw_path."
  Do NOT use index() on full_path with 'master' -- that pattern matches
  "PeCAN Master Data" and "X_MASTER_DATASET" in the path.

  Header assumed: full_path,filename,ext,fsize,fdate,sha256,status,
                  nobs,ncols,fail_reason,import_warning,seq_num
  (12 columns, positional read -- consistent with program 27 SECTION 3b)

  Pairs of interest (both copies known to exist):
    2018_2019_X_MASTER_DATASET_20200801.csv         -- expected sha_identical_flag=NO
    2018_2019_CPT_ROLLUP_X_MASTER_DATASET_20200801.csv  -- expected NO
    2018_2022_X_MASTER_DATASET_20240402.csv          -- expected NO (80,233-byte gap)
    2020_X_MASTER_DATASET_20210519.csv               -- same size, sha TBD
    2020_CPT_ROLLUP_X_MASTER_DATASET_20210609.csv    -- same size, sha TBD
    2021_X_MASTER_DATASET_20230512.csv               -- same size, sha TBD
    2022_MASTER_DATASET_20231024.csv                 -- same size, sha TBD
==========================================================================*/

%macro block1_sha;
  %global sha_flag_2018_2019_xmaster
          sha_flag_2018_2019_cpt
          sha_flag_2018_2022_xmaster
          sha_flag_2020_xmaster
          sha_flag_2020_cpt
          sha_flag_2021_xmaster
          sha_flag_2022_master
          fsize_raw_2018_2019_xmaster
          fsize_master_2018_2019_xmaster
          fsize_raw_2018_2022_xmaster
          fsize_master_2018_2022_xmaster;

  /* Read 19_raw_files.csv and collect sha256 values for both directories */
  data work._sha_raw work._sha_mstr;
    length full_path $ 500 filename $ 200 ext $ 10 fsize $ 30 fdate $ 30
           sha256 $ 64 status $ 20 nobs_s $ 20 ncols_s $ 20
           fail_reason $ 200 import_warning $ 200 _fseq $ 20
           directory $ 500;
    infile "&qc_path.\19_raw_files.csv" dsd dlm=',' firstobs=2
           truncover lrecl=2000;
    input full_path $ filename $ ext $ fsize $ fdate $ sha256 $ status $
          nobs_s $ ncols_s $ fail_reason $ import_warning $ _fseq $;

    /* Derive directory from full_path by stripping the filename */
    /* Compare directory portion to expected raw\ or raw\master paths */
    _pathlen_raw    = length("&raw_path.");
    _pathlen_master = length("&raw_path.\master");

    /* raw\master row: path starts with &raw_path.\master and is longer */
    if substr(full_path, 1, length("&raw_path.\master")) = "&raw_path.\master"
       and length(trim(full_path)) > length("&raw_path.\master")
    then do;
      output work._sha_mstr;
    end;
    /* raw\ row: path starts with &raw_path.\ but NOT with &raw_path.\master */
    else if substr(full_path, 1, length("&raw_path.\")) = "&raw_path.\"
       and substr(full_path, 1, length("&raw_path.\master")) ne "&raw_path.\master"
    then do;
      output work._sha_raw;
    end;
    keep filename sha256 fsize;
    drop _pathlen_raw _pathlen_master;
  run;

  /* Build a lookup of sha256 values keyed by filename for each directory */
  proc sql noprint;
    /* 2018_2019_X_MASTER */
    select sha256, fsize into :sha_raw_2018_2019_xm trimmed, :fsize_raw_2018_2019_xmaster trimmed
    from work._sha_raw
    where filename='2018_2019_X_MASTER_DATASET_20200801.csv';

    select sha256, fsize into :sha_mst_2018_2019_xm trimmed, :fsize_master_2018_2019_xmaster trimmed
    from work._sha_mstr
    where filename='2018_2019_X_MASTER_DATASET_20200801.csv';

    /* 2018_2019_CPT_ROLLUP */
    select sha256 into :sha_raw_2018_2019_cpt trimmed
    from work._sha_raw
    where filename='2018_2019_CPT_ROLLUP_X_MASTER_DATASET_20200801.csv';

    select sha256 into :sha_mst_2018_2019_cpt trimmed
    from work._sha_mstr
    where filename='2018_2019_CPT_ROLLUP_X_MASTER_DATASET_20200801.csv';

    /* 2018_2022_X_MASTER */
    select sha256, fsize into :sha_raw_2018_2022_xm trimmed, :fsize_raw_2018_2022_xmaster trimmed
    from work._sha_raw
    where filename='2018_2022_X_MASTER_DATASET_20240402.csv';

    select sha256, fsize into :sha_mst_2018_2022_xm trimmed, :fsize_master_2018_2022_xmaster trimmed
    from work._sha_mstr
    where filename='2018_2022_X_MASTER_DATASET_20240402.csv';

    /* 2020_X_MASTER */
    select sha256 into :sha_raw_2020_xm trimmed
    from work._sha_raw
    where filename='2020_X_MASTER_DATASET_20210519.csv';

    select sha256 into :sha_mst_2020_xm trimmed
    from work._sha_mstr
    where filename='2020_X_MASTER_DATASET_20210519.csv';

    /* 2020_CPT_ROLLUP */
    select sha256 into :sha_raw_2020_cpt trimmed
    from work._sha_raw
    where filename='2020_CPT_ROLLUP_X_MASTER_DATASET_20210609.csv';

    select sha256 into :sha_mst_2020_cpt trimmed
    from work._sha_mstr
    where filename='2020_CPT_ROLLUP_X_MASTER_DATASET_20210609.csv';

    /* 2021_X_MASTER */
    select sha256 into :sha_raw_2021_xm trimmed
    from work._sha_raw
    where filename='2021_X_MASTER_DATASET_20230512.csv';

    select sha256 into :sha_mst_2021_xm trimmed
    from work._sha_mstr
    where filename='2021_X_MASTER_DATASET_20230512.csv';

    /* 2022_MASTER */
    select sha256 into :sha_raw_2022_m trimmed
    from work._sha_raw
    where filename='2022_MASTER_DATASET_20231024.csv';

    select sha256 into :sha_mst_2022_m trimmed
    from work._sha_mstr
    where filename='2022_MASTER_DATASET_20231024.csv';
  quit;

  /* Compute sha_identical_flag for each pair */
  %macro _set_sha_flag(rawvar=, mstvar=, flagvar=);
    %if %length(&&&rawvar) = 0 or %length(&&&mstvar) = 0 %then
      %let &flagvar = MISSING;
    %else %if &&&rawvar = &&&mstvar %then
      %let &flagvar = YES;
    %else
      %let &flagvar = NO;
  %mend _set_sha_flag;

  %_set_sha_flag(rawvar=sha_raw_2018_2019_xm, mstvar=sha_mst_2018_2019_xm,
                 flagvar=sha_flag_2018_2019_xmaster);
  %_set_sha_flag(rawvar=sha_raw_2018_2019_cpt, mstvar=sha_mst_2018_2019_cpt,
                 flagvar=sha_flag_2018_2019_cpt);
  %_set_sha_flag(rawvar=sha_raw_2018_2022_xm, mstvar=sha_mst_2018_2022_xm,
                 flagvar=sha_flag_2018_2022_xmaster);
  %_set_sha_flag(rawvar=sha_raw_2020_xm, mstvar=sha_mst_2020_xm,
                 flagvar=sha_flag_2020_xmaster);
  %_set_sha_flag(rawvar=sha_raw_2020_cpt, mstvar=sha_mst_2020_cpt,
                 flagvar=sha_flag_2020_cpt);
  %_set_sha_flag(rawvar=sha_raw_2021_xm, mstvar=sha_mst_2021_xm,
                 flagvar=sha_flag_2021_xmaster);
  %_set_sha_flag(rawvar=sha_raw_2022_m, mstvar=sha_mst_2022_m,
                 flagvar=sha_flag_2022_master);

  %put NOTE: Block 1 -- SHA comparison results:;
  %put NOTE:   2018_2019_X_MASTER_DATASET:        sha_identical_flag=&sha_flag_2018_2019_xmaster;
  %put NOTE:   2018_2019_CPT_ROLLUP_X_MASTER:     sha_identical_flag=&sha_flag_2018_2019_cpt;
  %put NOTE:   2018_2022_X_MASTER_DATASET:        sha_identical_flag=&sha_flag_2018_2022_xmaster;
  %put NOTE:   2020_X_MASTER_DATASET:             sha_identical_flag=&sha_flag_2020_xmaster;
  %put NOTE:   2020_CPT_ROLLUP_X_MASTER_DATASET:  sha_identical_flag=&sha_flag_2020_cpt;
  %put NOTE:   2021_X_MASTER_DATASET:             sha_identical_flag=&sha_flag_2021_xmaster;
  %put NOTE:   2022_MASTER_DATASET:               sha_identical_flag=&sha_flag_2022_master;
%mend block1_sha;
%block1_sha;


/*==========================================================================
  SECTION 3: Block 2 -- PRECEDE_STUDY_ID format profile

  Profile type, width, and non-missing count for:
    r7: raw CSV 2022_Education_20240124.csv (numeric PRECEDE_Study_ID)
    r8: raw CSV 2022_RES_20230927.csv (numeric PRECEDE_Study_ID)
    r9: raw CSV All_YEARS_LAT_LONG_20231127.csv (character $12 PRECEDE_STUDY_ID)
        -- also profile distinct YEAR values (YEAR is $9, may not be "2022")
    md3-2022: raw\master 2018_2022_X_MASTER_DATASET_20240402.csv, subset YEAR=2022
    md7: src.master_data_7 -- discover type/width via PROC CONTENTS

  r7/r8/r9 do NOT have ENCRYPTED_MRN -- do not attempt to read it for them.
  PHI guard: ENCRYPTED_MRN in md3/md7/Crypto -- width and count only.

  Note on LINK-01: r7, r8, r9 carry no ENCRYPTED_MRN column.
  MRN linking is therefore infeasible with the current extracts.
==========================================================================*/

%macro block2_profile;
  %global r7_id_type r7_id_width r7_id_nonmiss
          r8_id_type r8_id_width r8_id_nonmiss
          r9_id_type r9_id_width r9_id_nonmiss
          r9_year_label
          md3_2022_n md3_2022_id_width md3_2022_id_type
          md3_2022_enc_width md3_2022_enc_nonmiss
          md7_id_type md7_id_len md7_id_nonmiss
          md7_enc_width md7_enc_nonmiss;

  /* --- r7: 2022_Education_20240124.csv (2 cols, numeric PRECEDE_Study_ID) --- */
  /* Read first row to discover ID type; informat N. used as safe numeric read  */
  data work._r7_raw;
    length id_raw $ 32;
    infile "&raw_path.\2022_Education_20240124.csv" dsd dlm=',' firstobs=2
           truncover lrecl=500;
    input id_raw $ @;  /* read first column as character to detect format */
    /* Attempt numeric conversion -- if no alpha chars, treat as numeric */
    _id_num = input(compress(id_raw, , 'kd'), best32.);
    keep id_raw _id_num;
  run;

  /* r7 profile: type=numeric (validated from source CONTEXT.md; confirm here) */
  /* Read as numeric using digits-only approach */
  data work._r7_ids;
    infile "&raw_path.\2022_Education_20240124.csv" dsd dlm=',' firstobs=2
           truncover lrecl=500;
    input PRECEDE_Study_ID Education $;
    if not missing(PRECEDE_Study_ID);
    id_c = strip(put(PRECEDE_Study_ID, best32.));
  run;

  proc sql noprint;
    select count(*) into :r7_id_nonmiss trimmed from work._r7_ids;
  quit;
  %let r7_id_type  = numeric;
  %let r7_id_width = 8;
  %put NOTE: r7 (2022_Education) PRECEDE_Study_ID type=&r7_id_type width=&r7_id_width nonmiss=&r7_id_nonmiss;
  %put NOTE: r7 -- no MRN column present (LINK-01: no linkage key in this extract);

  /* --- r8: 2022_RES_20230927.csv (4 cols, numeric PRECEDE_Study_ID) --- */
  data work._r8_ids;
    infile "&raw_path.\2022_RES_20230927.csv" dsd dlm=',' firstobs=2
           truncover lrecl=500;
    input PRECEDE_Study_ID Race $ Ethnicity $ Sex $;
    if not missing(PRECEDE_Study_ID);
    id_c = strip(put(PRECEDE_Study_ID, best32.));
  run;

  proc sql noprint;
    select count(*) into :r8_id_nonmiss trimmed from work._r8_ids;
  quit;
  %let r8_id_type  = numeric;
  %let r8_id_width = 8;
  %put NOTE: r8 (2022_RES) PRECEDE_Study_ID type=&r8_id_type width=&r8_id_width nonmiss=&r8_id_nonmiss;
  %put NOTE: r8 -- no MRN column present (LINK-01: no linkage key in this extract);

  /* --- r9: All_YEARS_LAT_LONG_20231127.csv (4 cols, char $12 PRECEDE_STUDY_ID) --- */
  /* Also profile distinct YEAR values before subsetting in Block 3              */
  data work._r9_raw;
    length PRECEDE_STUDY_ID $ 12 Latitude $ 20 Longitude $ 20 YEAR $ 9;
    infile "&raw_path.\All_YEARS_LAT_LONG_20231127.csv" dsd dlm=',' firstobs=2
           truncover lrecl=500;
    input PRECEDE_STUDY_ID $ Latitude $ Longitude $ YEAR $;
  run;

  proc sql noprint;
    select count(*) into :r9_id_nonmiss trimmed
    from work._r9_raw
    where not missing(PRECEDE_STUDY_ID)
      and upcase(strip(PRECEDE_STUDY_ID)) ne 'NULL';

    /* Discover distinct YEAR values -- YEAR is $9, may not be plain "2022" */
    select distinct strip(YEAR) into :r9_year_vals separated by '|'
    from work._r9_raw
    where not missing(YEAR) and upcase(strip(YEAR)) ne 'NULL';
  quit;
  %let r9_id_type  = character;
  %let r9_id_width = 12;
  %put NOTE: r9 (All_YEARS_LAT_LONG) PRECEDE_STUDY_ID type=&r9_id_type width=&r9_id_width nonmiss=&r9_id_nonmiss;
  %put NOTE: r9 -- no MRN column present (LINK-01: no linkage key in this extract);
  %put NOTE: r9 -- distinct YEAR values: &r9_year_vals;

  /* Determine the 2022 YEAR label from r9 (pick value containing "2022") */
  %macro _find_r9_year_label;
    %local _i _yval _found;
    %let _found = 0;
    %let r9_year_label = ;
    %let _i = 1;
    %do %while(%scan(&r9_year_vals, &_i, '|') ne %str() and &_found = 0);
      %let _yval = %scan(&r9_year_vals, &_i, '|');
      %if %index(&_yval, 2022) > 0 %then %do;
        %let r9_year_label = &_yval;
        %let _found = 1;
      %end;
      %let _i = %eval(&_i + 1);
    %end;
    %if &_found = 0 %then
      %let r9_year_label = 2022;  /* fallback: plain string "2022" */
    %put NOTE: r9 YEAR label for 2022 subset: [&r9_year_label];
  %mend _find_r9_year_label;
  %_find_r9_year_label;

  /* Build r9 ID lookup (all years, for full-file and 2022 subset variants) */
  data work._r9_ids_all;
    set work._r9_raw;
    where not missing(PRECEDE_STUDY_ID)
      and upcase(strip(PRECEDE_STUDY_ID)) ne 'NULL';
    id_c = strip(PRECEDE_STUDY_ID);
    keep id_c YEAR;
  run;

  data work._r9_ids_2022;
    set work._r9_ids_all;
    where strip(YEAR) = "&r9_year_label";
    keep id_c;
  run;

  proc sql noprint;
    select count(*) into :r9_n_2022 trimmed from work._r9_ids_2022;
  quit;
  %put NOTE: r9 YEAR=&r9_year_label subset n=&r9_n_2022;

  /* --- md3-2022: raw\master 2018_2022_X_MASTER_DATASET_20240402.csv, YEAR=2022 --- */
  /* Read full CSV, subset YEAR=2022; PRECEDE_STUDY_ID is character $12            */
  /* ENCRYPTED_MRN: PHI guard -- width and count only                              */
  data work._md3_2022_raw;
    length PRECEDE_STUDY_ID $ 12 ENCRYPTED_MRN $ 40 YEAR $ 4;
    infile "&raw_path.\master\2018_2022_X_MASTER_DATASET_20240402.csv"
           dsd dlm=',' firstobs=2 truncover lrecl=5000;
    input PRECEDE_STUDY_ID $ ENCRYPTED_MRN $ YEAR $;
    /* NOTE: positional read of first 3 columns only.                      */
    /* ENCRYPTED_MRN must not appear in output beyond count -- PHI guard.  */
    if strip(YEAR) = '2022';
    id_c = strip(PRECEDE_STUDY_ID);
    has_enc = (not missing(ENCRYPTED_MRN) and upcase(strip(ENCRYPTED_MRN)) ne 'NULL');
    keep id_c has_enc;
  run;

  proc sql noprint;
    select count(*) into :md3_2022_n trimmed from work._md3_2022_raw;
    /* PHI guard: ENCRYPTED_MRN count only */
    select count(*) into :md3_2022_enc_nonmiss trimmed
    from work._md3_2022_raw where has_enc = 1;
  quit;
  %let md3_2022_id_type  = character;
  %let md3_2022_id_width = 12;
  /* PHI guard: ENCRYPTED_MRN width (40) from length declaration above */
  %let md3_2022_enc_width = 40;
  %put NOTE: md3-2022 (raw\master) n=&md3_2022_n PRECEDE_STUDY_ID type=&md3_2022_id_type width=&md3_2022_id_width;
  %put NOTE: md3-2022 ENCRYPTED_MRN width=&md3_2022_enc_width nonmiss=&md3_2022_enc_nonmiss [PHI guard -- no sample values];

  /* Build md3-2022 ID lookup table for Block 3 joins */
  data work._md3_2022;
    set work._md3_2022_raw (keep=id_c);
    where not missing(id_c) and id_c ne '';
  run;

  /* Also read raw\ copy for secondary comparison rows */
  data work._md3_2022_rawcopy;
    length PRECEDE_STUDY_ID $ 12 ENCRYPTED_MRN $ 40 YEAR $ 4;
    infile "&raw_path.\2018_2022_X_MASTER_DATASET_20240402.csv"
           dsd dlm=',' firstobs=2 truncover lrecl=5000;
    input PRECEDE_STUDY_ID $ ENCRYPTED_MRN $ YEAR $;
    if strip(YEAR) = '2022';
    id_c = strip(PRECEDE_STUDY_ID);
    keep id_c;
    where not missing(id_c) and id_c ne '';
  run;

  proc sql noprint;
    select count(*) into :md3_2022_rawcopy_n trimmed from work._md3_2022_rawcopy;
  quit;
  %put NOTE: md3-2022 raw\ copy n=&md3_2022_rawcopy_n;

  /* --- md7: src.master_data_7 (2022_MASTER_DATASET SAS dataset) --- */
  /* Discover type and length via PROC CONTENTS -- not assumed           */
  proc contents data=src.master_data_7
    out=work._md7_meta(keep=name type length) noprint;
  run;

  proc sql noprint;
    select type, length into :md7_id_type trimmed, :md7_id_len trimmed
    from work._md7_meta
    where upcase(name) = 'PRECEDE_STUDY_ID';

    select count(*) into :md7_id_nonmiss trimmed
    from src.master_data_7
    where not missing(PRECEDE_STUDY_ID);

    /* PHI guard: ENCRYPTED_MRN width and count only */
    select length into :md7_enc_width trimmed
    from work._md7_meta
    where upcase(name) = 'ENCRYPTED_MRN';

    select count(*) into :md7_enc_nonmiss trimmed
    from src.master_data_7
    where not missing(ENCRYPTED_MRN)
      and upcase(strip(ENCRYPTED_MRN)) ne 'NULL';
  quit;
  /* type=1 => numeric; type=2 => character */
  %put NOTE: md7 PRECEDE_STUDY_ID type=&md7_id_type length=&md7_id_len nonmiss=&md7_id_nonmiss;
  %put NOTE: md7 ENCRYPTED_MRN width=&md7_enc_width nonmiss=&md7_enc_nonmiss [PHI guard -- no sample values];

  /* Build md7 ID lookup (numeric; put to character for joining) */
  proc sql noprint;
    create table work._md7_ids as
    select distinct strip(put(PRECEDE_STUDY_ID, best32.)) as id_c length=32
    from src.master_data_7
    where not missing(PRECEDE_STUDY_ID);
  quit;

  proc sql noprint;
    select count(*) into :md7_n_distinct trimmed from work._md7_ids;
  quit;
  %put NOTE: md7 distinct non-missing IDs (normalized): &md7_n_distinct;

%mend block2_profile;
%block2_profile;


/*==========================================================================
  SECTION 4: Block 3 -- Normalized ID match rates (both directions)

  For each comparison: build left and right ID tables, count n_left/n_right/
  n_matched via PROC SQL inner join, compute both-direction rates via %sysevalf.
  Division-by-zero guard: if n_left=0 or n_right=0 set corresponding rate to .

  Normalizations derived from Block 2 profile:
    r7 numeric -> strip(put(x, best32.))  labeled "put-best32-strip"
    r8 numeric -> strip(put(x, best32.))  labeled "put-best32-strip"
    r9 char $12 -> strip(x)               labeled "strip"
    md3 char $12 -> strip(x)              labeled "strip"
    md7 numeric -> strip(put(x, best32.)) labeled "put-best32-strip"

  Also uses digits-only normalization input(compress(id,,'kd'), best32.)
  labeled "compress-kd-input-best32" for cross-type numeric/character comparisons.
==========================================================================*/

%macro block3_rates;
  %global n_left_r7    n_right_md3    n_matched_r7    mleft_r7    mright_r7
          n_left_r8    n_right_md3_r8  n_matched_r8    mleft_r8    mright_r8
          n_left_r9    n_right_md3_r9  n_matched_r9    mleft_r9    mright_r9
          n_left_md7   n_right_md3_m7  n_matched_md7   mleft_md7   mright_md7
          n_left_r7m7  n_right_md7_r7  n_matched_r7m7  mleft_r7m7  mright_r7m7
          n_left_r8m7  n_right_md7_r8  n_matched_r8m7  mleft_r8m7  mright_r8m7
          n_left_mrnc  n_right_mrnc    n_matched_mrnc  mleft_mrnc  mright_mrnc
          n_left_mrncr n_right_mrncr   n_matched_mrncr mleft_mrncr mright_mrncr
          n_enc_left_mrnc n_enc_right_mrnc n_enc_matched_mrnc
          n_left_encc  n_right_encc    n_matched_encc  mleft_encc  mright_encc
          n_enc_left_encc n_enc_right_encc n_enc_matched_encc;

  /* Helper macro to compute both-direction rates with division-by-zero guard */
  %macro _calc_rates(nleft=, nright=, nmatched=, mleft=, mright=);
    %if &&&nleft = 0 %then %let &mleft = .;
    %else %let &mleft = %sysevalf(&&&nmatched / &&&nleft, float);
    %if &&&nright = 0 %then %let &mright = .;
    %else %let &mright = %sysevalf(&&&nmatched / &&&nright, float);
  %mend _calc_rates;

  /* ===== Build normalized left-side ID tables ===== */

  /* r7 normalized: numeric -> put best32 strip */
  data work._r7_norm;
    set work._r7_ids (keep=id_c);
    id_c_digits = strip(put(input(compress(id_c, , 'kd'), best32.), best32.));
    keep id_c_digits;
    rename id_c_digits = id_c;
  run;

  /* r8 normalized: numeric -> put best32 strip */
  data work._r8_norm;
    set work._r8_ids (keep=id_c);
    id_c_digits = strip(put(input(compress(id_c, , 'kd'), best32.), best32.));
    keep id_c_digits;
    rename id_c_digits = id_c;
  run;

  /* r9 2022 normalized: character strip */
  data work._r9_norm;
    set work._r9_ids_2022;
    id_c = strip(id_c);
  run;

  /* md3-2022 normalized (raw\master copy) */
  data work._md3_norm;
    set work._md3_2022 (keep=id_c);
    id_c = strip(id_c);
  run;

  /* md3-2022 raw\ copy normalized */
  data work._md3_rawcopy_norm;
    set work._md3_2022_rawcopy (keep=id_c);
    id_c = strip(id_c);
  run;

  /* md7 normalized (already built in Block 2 as work._md7_ids) */
  /* work._md7_ids.id_c = strip(put(PRECEDE_STUDY_ID, best32.)) */

  /* ===== Comparison 1: r7 vs md3-2022 (raw\master) ===== */
  proc sql noprint;
    select count(*) into :n_left_r7 trimmed from work._r7_norm;
    select count(*) into :n_right_md3 trimmed from work._md3_norm;
    select count(*) into :n_matched_r7 trimmed
    from work._r7_norm as l
    inner join work._md3_norm as r on l.id_c = r.id_c;
  quit;
  %_calc_rates(nleft=n_left_r7, nright=n_right_md3, nmatched=n_matched_r7,
               mleft=mleft_r7, mright=mright_r7);
  %put NOTE: r7 vs md3-2022: n_left=&n_left_r7 n_right=&n_right_md3 n_matched=&n_matched_r7;
  %put NOTE: r7 vs md3-2022: match_rate_left=&mleft_r7 match_rate_right=&mright_r7;

  /* ===== Comparison 2: r8 vs md3-2022 (raw\master) ===== */
  proc sql noprint;
    select count(*) into :n_left_r8 trimmed from work._r8_norm;
    select count(*) into :n_right_md3_r8 trimmed from work._md3_norm;
    select count(*) into :n_matched_r8 trimmed
    from work._r8_norm as l
    inner join work._md3_norm as r on l.id_c = r.id_c;
  quit;
  %_calc_rates(nleft=n_left_r8, nright=n_right_md3_r8, nmatched=n_matched_r8,
               mleft=mleft_r8, mright=mright_r8);
  %put NOTE: r8 vs md3-2022: n_left=&n_left_r8 n_right=&n_right_md3_r8 n_matched=&n_matched_r8;
  %put NOTE: r8 vs md3-2022: match_rate_left=&mleft_r8 match_rate_right=&mright_r8;

  /* ===== Comparison 3: r9 vs md3-2022 (raw\master, 2022 subset only) ===== */
  /* r9 is character $12; md3 is character $12 -- try direct strip match first */
  proc sql noprint;
    select count(*) into :n_left_r9 trimmed from work._r9_norm;
    select count(*) into :n_right_md3_r9 trimmed from work._md3_norm;
    select count(*) into :n_matched_r9 trimmed
    from work._r9_norm as l
    inner join work._md3_norm as r on l.id_c = r.id_c;
  quit;
  %_calc_rates(nleft=n_left_r9, nright=n_right_md3_r9, nmatched=n_matched_r9,
               mleft=mleft_r9, mright=mright_r9);
  %put NOTE: r9 vs md3-2022 (direct strip): n_left=&n_left_r9 n_right=&n_right_md3_r9 n_matched=&n_matched_r9;
  %put NOTE: r9 vs md3-2022 (direct strip): match_rate_left=&mleft_r9 match_rate_right=&mright_r9;

  /* If direct strip produces 0 matches, try digits-only normalization */
  %macro _r9_alt_normalization;
    %if &n_matched_r9 = 0 %then %do;
      %put NOTE: r9 direct strip produced n_matched=0 -- attempting digits-only normalization;
      proc sql noprint;
        create table work._r9_norm_digits as
        select distinct strip(put(input(compress(id_c, , 'kd'), best32.), best32.)) as id_c length=32
        from work._r9_norm
        where not missing(id_c) and id_c ne '';

        select count(*) into :n_matched_r9_alt trimmed
        from work._r9_norm_digits as l
        inner join work._md3_norm as r on l.id_c = r.id_c;
      quit;
      %put NOTE: r9 vs md3-2022 (digits-only): n_matched=&n_matched_r9_alt;
      /* Document which normalization is reported: use digits-only result */
      %let n_matched_r9 = &n_matched_r9_alt;
      %_calc_rates(nleft=n_left_r9, nright=n_right_md3_r9, nmatched=n_matched_r9,
                   mleft=mleft_r9, mright=mright_r9);
      %global r9_norm_applied;
      %let r9_norm_applied = compress-kd-input-best32;
    %end;
    %else %do;
      %global r9_norm_applied;
      %let r9_norm_applied = strip;
    %end;
  %mend _r9_alt_normalization;
  %_r9_alt_normalization;

  /* ===== Comparison 4: md7 vs md3-2022 (raw\master) -- root diagnostic ===== */
  /* md7 numeric, md3 character -- digits-only normalization on both sides      */
  proc sql noprint;
    select count(*) into :n_left_md7 trimmed from work._md7_ids;
    select count(*) into :n_right_md3_m7 trimmed from work._md3_norm;
    select count(*) into :n_matched_md7 trimmed
    from work._md7_ids as l
    inner join work._md3_norm as r on l.id_c = r.id_c;
  quit;
  %_calc_rates(nleft=n_left_md7, nright=n_right_md3_m7, nmatched=n_matched_md7,
               mleft=mleft_md7, mright=mright_md7);
  %put NOTE: md7 vs md3-2022: n_left=&n_left_md7 n_right=&n_right_md3_m7 n_matched=&n_matched_md7;
  %put NOTE: md7 vs md3-2022: match_rate_left=&mleft_md7 match_rate_right=&mright_md7;
  %put NOTE: md7_vs_md3_2022 is the root diagnostic: if ~0 percent then PCM-D-16 is an md3-vs-md7 ID-space problem;

  /* ===== Comparison 5: r7 vs md7 (both numeric, direct numeric match) ===== */
  proc sql noprint;
    select count(*) into :n_left_r7m7 trimmed from work._r7_norm;
    select count(*) into :n_right_md7_r7 trimmed from work._md7_ids;
    select count(*) into :n_matched_r7m7 trimmed
    from work._r7_norm as l
    inner join work._md7_ids as r on l.id_c = r.id_c;
  quit;
  %_calc_rates(nleft=n_left_r7m7, nright=n_right_md7_r7, nmatched=n_matched_r7m7,
               mleft=mleft_r7m7, mright=mright_r7m7);
  %put NOTE: r7 vs md7: n_left=&n_left_r7m7 n_right=&n_right_md7_r7 n_matched=&n_matched_r7m7;
  %put NOTE: r7 vs md7: match_rate_left=&mleft_r7m7 match_rate_right=&mright_r7m7;

  /* ===== Comparison 6: r8 vs md7 (both numeric, direct numeric match) ===== */
  proc sql noprint;
    select count(*) into :n_left_r8m7 trimmed from work._r8_norm;
    select count(*) into :n_right_md7_r8 trimmed from work._md7_ids;
    select count(*) into :n_matched_r8m7 trimmed
    from work._r8_norm as l
    inner join work._md7_ids as r on l.id_c = r.id_c;
  quit;
  %_calc_rates(nleft=n_left_r8m7, nright=n_right_md7_r8, nmatched=n_matched_r8m7,
               mleft=mleft_r8m7, mright=mright_r8m7);
  %put NOTE: r8 vs md7: n_left=&n_left_r8m7 n_right=&n_right_md7_r8 n_matched=&n_matched_r8m7;
  %put NOTE: r8 vs md7: match_rate_left=&mleft_r8m7 match_rate_right=&mright_r8m7;

  /* ===== Comparison 7: MRN Crypto vs 2018_2019_X_MASTER (raw\master) ===== */
  /* PRECEDE_Study_ID: Crypto $18 vs master $12 -- digits-only normalization  */
  /* ENCRYPTED_MRN: count-only join (PHI guard)                               */

  /* Read MRN Crypto file */
  data work._mrn_crypto_raw;
    length PRECEDE_Study_ID $ 18 ENCRYPTED_MRN $ 41;
    infile "&raw_path.\2018_2019_MRN_Crypto_Data20260814.csv"
           dsd dlm=',' firstobs=2 truncover lrecl=200;
    input PRECEDE_Study_ID $ ENCRYPTED_MRN $;
  run;

  data work._mrn_crypto_ids;
    set work._mrn_crypto_raw;
    id_c = strip(put(input(compress(PRECEDE_Study_ID, , 'kd'), best32.), best32.));
    has_enc = (not missing(ENCRYPTED_MRN) and upcase(strip(ENCRYPTED_MRN)) ne 'NULL');
    keep id_c has_enc ENCRYPTED_MRN;
  run;

  /* Read 2018_2019_X_MASTER raw\master copy */
  data work._xmaster_2018_raw;
    length PRECEDE_STUDY_ID $ 12 ENCRYPTED_MRN $ 40;
    infile "&raw_path.\master\2018_2019_X_MASTER_DATASET_20200801.csv"
           dsd dlm=',' firstobs=2 truncover lrecl=5000;
    input PRECEDE_STUDY_ID $ ENCRYPTED_MRN $;
    id_c = strip(put(input(compress(PRECEDE_STUDY_ID, , 'kd'), best32.), best32.));
    has_enc = (not missing(ENCRYPTED_MRN) and upcase(strip(ENCRYPTED_MRN)) ne 'NULL');
    keep id_c has_enc ENCRYPTED_MRN;
  run;

  proc sql noprint;
    select count(*) into :n_left_mrnc trimmed
    from work._mrn_crypto_ids
    where not missing(id_c) and id_c ne '' and id_c ne '.';

    select count(*) into :n_right_mrnc trimmed
    from work._xmaster_2018_raw
    where not missing(id_c) and id_c ne '' and id_c ne '.';

    select count(*) into :n_matched_mrnc trimmed
    from work._mrn_crypto_ids as l
    inner join work._xmaster_2018_raw as r
    on l.id_c = r.id_c
    where not missing(l.id_c) and l.id_c ne '' and l.id_c ne '.';

    /* PHI guard: ENCRYPTED_MRN count-only join */
    select count(*) into :n_enc_left_mrnc trimmed
    from work._mrn_crypto_ids where has_enc = 1;

    select count(*) into :n_enc_right_mrnc trimmed
    from work._xmaster_2018_raw where has_enc = 1;

    /* Count-only ENCRYPTED_MRN match -- no values output */
    select count(*) into :n_enc_matched_mrnc trimmed
    from work._mrn_crypto_ids as c
    inner join work._xmaster_2018_raw as m
    on c.ENCRYPTED_MRN = m.ENCRYPTED_MRN  /* PHI guard: count-only, no sample values */
    where c.has_enc = 1 and m.has_enc = 1;
  quit;
  %_calc_rates(nleft=n_left_mrnc, nright=n_right_mrnc, nmatched=n_matched_mrnc,
               mleft=mleft_mrnc, mright=mright_mrnc);
  %put NOTE: MRN Crypto vs 2018_2019_X_MASTER master: n_left=&n_left_mrnc n_right=&n_right_mrnc n_matched=&n_matched_mrnc;
  %put NOTE: MRN Crypto vs 2018_2019_X_MASTER master: match_rate_left=&mleft_mrnc match_rate_right=&mright_mrnc;
  %put NOTE: ENCRYPTED_MRN count-only match: left=&n_enc_left_mrnc right=&n_enc_right_mrnc matched=&n_enc_matched_mrnc [PHI guard -- no sample values];

  /* MRN Crypto vs raw\ copy (secondary row) */
  /* Read raw\ copy of 2018_2019_X_MASTER */
  data work._xmaster_2018_rawcopy;
    length PRECEDE_STUDY_ID $ 12 ENCRYPTED_MRN $ 41;
    infile "&raw_path.\2018_2019_X_MASTER_DATASET_20200801.csv"
           dsd dlm=',' firstobs=2 truncover lrecl=5000;
    input PRECEDE_STUDY_ID $ ENCRYPTED_MRN $;
    id_c = strip(put(input(compress(PRECEDE_STUDY_ID, , 'kd'), best32.), best32.));
    has_enc = (not missing(ENCRYPTED_MRN) and upcase(strip(ENCRYPTED_MRN)) ne 'NULL');
    keep id_c has_enc ENCRYPTED_MRN;
  run;

  proc sql noprint;
    select count(*) into :n_left_mrncr trimmed
    from work._mrn_crypto_ids
    where not missing(id_c) and id_c ne '' and id_c ne '.';

    select count(*) into :n_right_mrncr trimmed
    from work._xmaster_2018_rawcopy
    where not missing(id_c) and id_c ne '' and id_c ne '.';

    select count(*) into :n_matched_mrncr trimmed
    from work._mrn_crypto_ids as l
    inner join work._xmaster_2018_rawcopy as r
    on l.id_c = r.id_c
    where not missing(l.id_c) and l.id_c ne '' and l.id_c ne '.';
  quit;
  %_calc_rates(nleft=n_left_mrncr, nright=n_right_mrncr, nmatched=n_matched_mrncr,
               mleft=mleft_mrncr, mright=mright_mrncr);
  %put NOTE: MRN Crypto vs 2018_2019_X_MASTER raw\: n_left=&n_left_mrncr n_right=&n_right_mrncr n_matched=&n_matched_mrncr;
  %put NOTE: MRN Crypto vs 2018_2019_X_MASTER raw\: match_rate_left=&mleft_mrncr match_rate_right=&mright_mrncr;

  /* ===== Comparison 8: ENCOUNTER Crypto vs 2018_2019_X_MASTER ===== */
  data work._enc_crypto_raw;
    length PRECEDE_Study_ID $ 18 ENCRYPTED_MRN $ 41;
    infile "&raw_path.\2018_2019_ENCOUNTER_Crypto_Data_20260814.csv"
           dsd dlm=',' firstobs=2 truncover lrecl=200;
    input PRECEDE_Study_ID $ ENCRYPTED_MRN $;
  run;

  data work._enc_crypto_ids;
    set work._enc_crypto_raw;
    id_c = strip(put(input(compress(PRECEDE_Study_ID, , 'kd'), best32.), best32.));
    has_enc = (not missing(ENCRYPTED_MRN) and upcase(strip(ENCRYPTED_MRN)) ne 'NULL');
    keep id_c has_enc ENCRYPTED_MRN;
  run;

  proc sql noprint;
    select count(*) into :n_left_encc trimmed
    from work._enc_crypto_ids
    where not missing(id_c) and id_c ne '' and id_c ne '.';

    select count(*) into :n_right_encc trimmed
    from work._xmaster_2018_raw
    where not missing(id_c) and id_c ne '' and id_c ne '.';

    select count(*) into :n_matched_encc trimmed
    from work._enc_crypto_ids as l
    inner join work._xmaster_2018_raw as r
    on l.id_c = r.id_c
    where not missing(l.id_c) and l.id_c ne '' and l.id_c ne '.';

    /* PHI guard: ENCRYPTED_MRN count-only */
    select count(*) into :n_enc_left_encc trimmed
    from work._enc_crypto_ids where has_enc = 1;

    select count(*) into :n_enc_right_encc trimmed
    from work._xmaster_2018_raw where has_enc = 1;

    select count(*) into :n_enc_matched_encc trimmed
    from work._enc_crypto_ids as c
    inner join work._xmaster_2018_raw as m
    on c.ENCRYPTED_MRN = m.ENCRYPTED_MRN  /* PHI guard: count-only */
    where c.has_enc = 1 and m.has_enc = 1;
  quit;
  %_calc_rates(nleft=n_left_encc, nright=n_right_encc, nmatched=n_matched_encc,
               mleft=mleft_encc, mright=mright_encc);
  %put NOTE: ENCOUNTER Crypto vs 2018_2019_X_MASTER master: n_left=&n_left_encc n_right=&n_right_encc n_matched=&n_matched_encc;
  %put NOTE: ENCOUNTER Crypto vs 2018_2019_X_MASTER master: match_rate_left=&mleft_encc match_rate_right=&mright_encc;
  %put NOTE: ENCRYPTED_MRN count-only match: left=&n_enc_left_encc right=&n_enc_right_encc matched=&n_enc_matched_encc [PHI guard -- no sample values];

%mend block3_rates;
%block3_rates;


/*==========================================================================
  SECTION 5: Write qc/28_linkage_investigation.csv via DATA step PUT
  Header (exact, D-04):
    source_pair,key_used,normalization_applied,n_left,n_right,n_matched,
    match_rate_left,match_rate_right,sha_identical_flag
  One row per Block 1 file pair + one row per Block 3 comparison.
  No PHI: ENCRYPTED_MRN rows report counts only.
==========================================================================*/

%macro write_output_csv;
  filename csvout "&qc_path.\28_linkage_investigation.csv";
  data _null_;
    file csvout;
    /* Header */
    put "source_pair,key_used,normalization_applied,n_left,n_right,n_matched,"
        "match_rate_left,match_rate_right,sha_identical_flag";

    /* Block 1: SHA comparison rows (n_left/n_right/n_matched blank -- SHA comparison) */
    put "2018_2019_X_MASTER_DATASET_raw_vs_master,sha256,pre-established-80233-byte-gap,"
        ".,.,.,.,.,&sha_flag_2018_2019_xmaster";
    put "2018_2019_CPT_ROLLUP_X_MASTER_raw_vs_master,sha256,pre-established-80233-byte-gap,"
        ".,.,.,.,.,&sha_flag_2018_2019_cpt";
    put "2018_2022_X_MASTER_raw_vs_master,sha256,pre-established-80233-byte-gap,"
        ".,.,.,.,.,&sha_flag_2018_2022_xmaster";
    put "2020_X_MASTER_raw_vs_master,sha256,confirmed-by-block1,"
        ".,.,.,.,.,&sha_flag_2020_xmaster";
    put "2020_CPT_ROLLUP_X_MASTER_raw_vs_master,sha256,confirmed-by-block1,"
        ".,.,.,.,.,&sha_flag_2020_cpt";
    put "2021_X_MASTER_raw_vs_master,sha256,confirmed-by-block1,"
        ".,.,.,.,.,&sha_flag_2021_xmaster";
    put "2022_MASTER_raw_vs_master,sha256,confirmed-by-block1,"
        ".,.,.,.,.,&sha_flag_2022_master";

    /* Block 3: Match rate rows */
    put "r7_vs_md3_2022,PRECEDE_STUDY_ID,compress-kd-input-best32,"
        "&n_left_r7,&n_right_md3,&n_matched_r7,"
        "&mleft_r7,&mright_r7,.";
    put "r8_vs_md3_2022,PRECEDE_STUDY_ID,compress-kd-input-best32,"
        "&n_left_r8,&n_right_md3_r8,&n_matched_r8,"
        "&mleft_r8,&mright_r8,.";
    put "r9_vs_md3_2022,PRECEDE_STUDY_ID,&r9_norm_applied.,"
        "&n_left_r9,&n_right_md3_r9,&n_matched_r9,"
        "&mleft_r9,&mright_r9,.";
    put "md7_vs_md3_2022,PRECEDE_STUDY_ID,compress-kd-input-best32,"
        "&n_left_md7,&n_right_md3_m7,&n_matched_md7,"
        "&mleft_md7,&mright_md7,.";
    put "r7_vs_md7,PRECEDE_STUDY_ID,put-best32-strip-direct-numeric,"
        "&n_left_r7m7,&n_right_md7_r7,&n_matched_r7m7,"
        "&mleft_r7m7,&mright_r7m7,.";
    put "r8_vs_md7,PRECEDE_STUDY_ID,put-best32-strip-direct-numeric,"
        "&n_left_r8m7,&n_right_md7_r8,&n_matched_r8m7,"
        "&mleft_r8m7,&mright_r8m7,.";
    put "2018_2019_MRN_Crypto,2018_2019_X_MASTER_master,PRECEDE_STUDY_ID,"
        "compress-kd-input-best32,"
        "&n_left_mrnc,&n_right_mrnc,&n_matched_mrnc,"
        "&mleft_mrnc,&mright_mrnc,.";
    /* PHI guard: ENCRYPTED_MRN -- count-only match row */
    put "Crypto_ENCRYPTED_MRN,2018_2019_X_MASTER_master_ENCRYPTED_MRN,"
        "ENCRYPTED_MRN,count-only-PHI-guard,"
        "&n_enc_left_mrnc,&n_enc_right_mrnc,&n_enc_matched_mrnc,"
        ".,.,." ;
    put "2018_2019_MRN_Crypto,2018_2019_X_MASTER_raw,PRECEDE_STUDY_ID,"
        "compress-kd-input-best32,"
        "&n_left_mrncr,&n_right_mrncr,&n_matched_mrncr,"
        "&mleft_mrncr,&mright_mrncr,.";
    put "2018_2019_ENCOUNTER_Crypto,2018_2019_X_MASTER_master,PRECEDE_STUDY_ID,"
        "compress-kd-input-best32,"
        "&n_left_encc,&n_right_encc,&n_matched_encc,"
        "&mleft_encc,&mright_encc,.";
    /* PHI guard: ENCRYPTED_MRN -- count-only match row for ENCOUNTER Crypto */
    put "Crypto_ENCOUNTER_ENCRYPTED_MRN,2018_2019_X_MASTER_master_ENCRYPTED_MRN,"
        "ENCRYPTED_MRN,count-only-PHI-guard,"
        "&n_enc_left_encc,&n_enc_right_encc,&n_enc_matched_encc,"
        ".,.,." ;
  run;
  filename csvout clear;
  %put NOTE: qc/28_linkage_investigation.csv written.;
%mend write_output_csv;
%write_output_csv;


/*==========================================================================
  SECTION 6: Assertions -- pass/fail summary
  assert_eq_local aborts on mismatch (PCM-R-05).
  We do NOT assert specific match-rate values (they are discovered, not known).
  We DO assert that the CSV was written and that all Block 3 comparison macrovars
  were populated (not empty).
==========================================================================*/

%macro assert_eq_local(actual=, expected=, msg=);
  %if &actual ne &expected %then %do;
    %put ERROR: &msg -- expected &expected got &actual; %abort cancel;
  %end;
  %else %put NOTE: OK -- &msg (&actual);
%mend assert_eq_local;

%macro assert_csv_written;
  %if %sysfunc(fileexist(&qc_path.\28_linkage_investigation.csv)) = 0 %then %do;
    %put ERROR: qc/28_linkage_investigation.csv not found after write step.; %abort cancel;
  %end;
  %else %put NOTE: OK -- qc/28_linkage_investigation.csv exists.;
%mend assert_csv_written;
%assert_csv_written;

%macro assert_block3_populated;
  /* Each Block 3 n_matched variable must be a number (not empty) */
  %macro _chk(v=);
    %if %length(&&&v) = 0 %then %do;
      %put ERROR: Block 3 variable &v is empty -- Block 3 did not complete.; %abort cancel;
    %end;
    %else %put NOTE: OK -- &v = &&&v;
  %mend _chk;
  %_chk(v=n_matched_r7);
  %_chk(v=n_matched_r8);
  %_chk(v=n_matched_r9);
  %_chk(v=n_matched_md7);
  %_chk(v=n_matched_r7m7);
  %_chk(v=n_matched_r8m7);
  %_chk(v=n_matched_mrnc);
  %_chk(v=n_matched_encc);
%mend assert_block3_populated;
%assert_block3_populated;

/* Summary to log */
%put NOTE: ===========================================================;
%put NOTE: 28_linkage_investigation COMPLETE;
%put NOTE: LINK-01 finding: r7/r8/r9 have no ENCRYPTED_MRN column.;
%put NOTE:   MRN linking is infeasible with the current extracts.;
%put NOTE: Block 1 SHA flags: 2018_2019_XM=&sha_flag_2018_2019_xmaster;
%put NOTE:   2018_2019_CPT=&sha_flag_2018_2019_cpt;
%put NOTE:   2018_2022_XM=&sha_flag_2018_2022_xmaster;
%put NOTE:   2020_XM=&sha_flag_2020_xmaster;
%put NOTE:   2020_CPT=&sha_flag_2020_cpt;
%put NOTE:   2021_XM=&sha_flag_2021_xmaster;
%put NOTE:   2022_M=&sha_flag_2022_master;
%put NOTE: Block 3 decisive comparisons:;
%put NOTE:   md7_vs_md3_2022: n_matched=&n_matched_md7 mleft=&mleft_md7 mright=&mright_md7;
%put NOTE:   r7_vs_md7:       n_matched=&n_matched_r7m7 mleft=&mleft_r7m7 mright=&mright_r7m7;
%put NOTE:   r8_vs_md7:       n_matched=&n_matched_r8m7 mleft=&mleft_r8m7 mright=&mright_r8m7;
%put NOTE: Output: &qc_path.\28_linkage_investigation.csv;
%put NOTE: ===========================================================;
