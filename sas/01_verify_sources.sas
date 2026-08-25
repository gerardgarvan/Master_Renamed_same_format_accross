/*==========================================================================
  Program : 01_verify_sources.sas
  Phase   : Phase 1 -- Source Verification & Freeze
  Purpose : Preconditions (libname + XCMD), SRC-06 key verification across
            all eight sources, SHA-256 checksums (SRC-04), and per-source
            row/ID counts (SRC-03).
  Requirements addressed:
            SRC-03 (per-source row/ID counts)
            SRC-04 (SHA-256 checksums committed to qc/)
            SRC-06 (PRECEDE_STUDY_ID present, Char 12, in all eight sources)
            -- plan 02 appends: SRC-05 (blank key), SRC-01 (uniqueness),
                                SRC-02 (md3 superset)
  Author  : Executor (Phase 1 Plan 01)
  Created : 2026-08-25
==========================================================================*/

/* ---- Paths ---- */
%let source_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross;
%let qc_path     = C:\Master_Renamed_same_format_accross\qc;
libname src "&source_path" access=readonly;

/* ---- Precondition 1: libname must resolve ---- */
%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: LIBNAME &lib could not be assigned. Check P: drive availability.;
    %abort cancel;
  %end;
%mend check_libname;
%check_libname(lib=src);

/* ---- Precondition 2: XCMD must be enabled (gates all FILENAME PIPE use) ---- */
%macro check_xcmd;
  %if %upcase(%sysfunc(getoption(xcmd))) ne XCMD %then %do;
    %put ERROR: SAS is running with NOXCMD -- FILENAME PIPE is unavailable, so SRC-04;
    %put ERROR- (SHA-256 checksums) cannot run. This is NOT a certutil problem.;
    %put ERROR- Re-plan SRC-04 against sashelp.vtable metadata (RESEARCH Pitfall 8).;
    %abort cancel;
  %end;
  %else %put NOTE: XCMD enabled -- FILENAME PIPE available for SRC-04.;
%mend check_xcmd;
%check_xcmd;

/* ---- Source list (reused by later blocks and plan 02) ---- */
%let src_list = master_data_1 master_data_2 master_data_3 master_data_4 master_data_5 master_data_6 master_data_7 master_data_8;


/* ===== SRC-06: PRECEDE_STUDY_ID present, Char, length 12, in all eight ===== */
proc contents data=src._all_ out=work._allvars
  (keep=memname name type length) noprint;
run;

proc sql noprint;
  /* every source must carry the key exactly once */
  select count(*) into :n_haskey trimmed
  from work._allvars
  where upcase(name) = 'PRECEDE_STUDY_ID'
    and upcase(memname) in ('MASTER_DATA_1','MASTER_DATA_2','MASTER_DATA_3','MASTER_DATA_4',
                            'MASTER_DATA_5','MASTER_DATA_6','MASTER_DATA_7','MASTER_DATA_8');

  /* and it must be character, length 12, in every one of them */
  select count(*) into :n_badkey trimmed
  from work._allvars
  where upcase(name) = 'PRECEDE_STUDY_ID'
    and upcase(memname) in ('MASTER_DATA_1','MASTER_DATA_2','MASTER_DATA_3','MASTER_DATA_4',
                            'MASTER_DATA_5','MASTER_DATA_6','MASTER_DATA_7','MASTER_DATA_8')
    and not (type = 2 and length = 12);   /* type=2 is character */
quit;

%if &n_haskey ne 8 %then %do;
  %put ERROR: SRC-06 VIOLATION: PRECEDE_STUDY_ID found in &n_haskey of 8 sources (expected 8).;
  %put ERROR- Check for a missing/renamed .sas7bdat or a casing difference in the key name.;
  %abort cancel;
%end;

%if &n_badkey > 0 %then %do;
  %put ERROR: SRC-06 VIOLATION: PRECEDE_STUDY_ID is not Char 12 in &n_badkey source(s).;
  %put ERROR- A numeric key breaks the SRC-02 anti-join (type mismatch or silent coercion).;
  %put ERROR- md7 is the likely offender: it was NUM8 originally, destroyed by PCM-T-01, and rebuilt.;
  %abort cancel;
%end;
%else %put NOTE: SRC-06 OK -- PRECEDE_STUDY_ID is Char 12 in all eight sources.;

/*
  Note: upcase(name) = 'PRECEDE_STUDY_ID' deliberately excludes md6's duplicate
  PRECEDE_Study_ID_1 column, whose name differs by the _1 suffix.
*/


/* ===== SRC-04: SHA-256 checksums via certutil FILENAME PIPE ===== */

/* get_sha256: compute SHA-256 of a single .sas7bdat file via certutil.
   The doubled "" produces a literal double-quote in the pipe string, quoting
   a path that contains spaces (Pitfall 1). The %global + blank initialisation
   ensures a failed pipe leaves the variable blank (caught by check_hash) rather
   than undefined (which would throw "apparent symbolic reference not resolved"). */
%macro get_sha256(filepath=, outvar=);
  %global &outvar;
  %let &outvar = ;
  filename _hpipe pipe "certutil -hashfile ""&filepath"" SHA256";
  data _null_;
    infile _hpipe truncover;
    input line $200.;
    line = strip(line);
    if length(line) = 64 then call symputx("&outvar", line, 'G');
  run;
  filename _hpipe clear;
%mend get_sha256;

%get_sha256(filepath=&source_path.\master_data_1.sas7bdat, outvar=hash_md1);
%get_sha256(filepath=&source_path.\master_data_2.sas7bdat, outvar=hash_md2);
%get_sha256(filepath=&source_path.\master_data_3.sas7bdat, outvar=hash_md3);
%get_sha256(filepath=&source_path.\master_data_4.sas7bdat, outvar=hash_md4);
%get_sha256(filepath=&source_path.\master_data_5.sas7bdat, outvar=hash_md5);
%get_sha256(filepath=&source_path.\master_data_6.sas7bdat, outvar=hash_md6);
%get_sha256(filepath=&source_path.\master_data_7.sas7bdat, outvar=hash_md7);
%get_sha256(filepath=&source_path.\master_data_8.sas7bdat, outvar=hash_md8);

/* Guard: any blank hash means certutil failed or the file is missing -- abort */
%macro check_hash(v=, name=);
  %if %superq(&v) = %then %do;
    %put ERROR: SHA-256 for &name is empty -- certutil failed or file missing.;
    %abort cancel;
  %end;
%mend check_hash;
%check_hash(v=hash_md1, name=master_data_1);
%check_hash(v=hash_md2, name=master_data_2);
%check_hash(v=hash_md3, name=master_data_3);
%check_hash(v=hash_md4, name=master_data_4);
%check_hash(v=hash_md5, name=master_data_5);
%check_hash(v=hash_md6, name=master_data_6);
%check_hash(v=hash_md7, name=master_data_7);
%check_hash(v=hash_md8, name=master_data_8);

/* Write hashes, timestamp, and regeneration caveat to qc/checksums.txt */
filename qcsum "&qc_path.\checksums.txt";
data _null_;
  file qcsum;
  put "SHA256 Source Checksums -- Run: %sysfunc(datetime(), datetime20.)";
  put " ";
  put "NOTE: These hash the .sas7bdat FILES, not the data they contain.";
  put "A .sas7bdat embeds its creation datetime, so re-importing byte-identical";
  put "data from the same source produces a DIFFERENT hash. A mismatch on a later";
  put "run means the dataset was regenerated -- it is not evidence of corruption.";
  put "These hashes prove Phase 4 merges the same bytes Phase 1 verified.";
  put " ";
  put "master_data_1  &hash_md1";
  put "master_data_2  &hash_md2";
  put "master_data_3  &hash_md3";
  put "master_data_4  &hash_md4";
  put "master_data_5  &hash_md5";
  put "master_data_6  &hash_md6";
  put "master_data_7  &hash_md7";
  put "master_data_8  &hash_md8";
run;
filename qcsum clear;


/* ===== SRC-03: Per-source row and distinct-ID counts ===== */

/* count_src: PROC SQL COUNT(*) for true row count (not PROC CONTENTS nobs,
   which counts deleted observations -- Pitfall 4). */
%macro count_src(ds=);
  proc sql noprint;
    select count(*)                         into :n_&ds trimmed from src.&ds;
    select count(distinct PRECEDE_STUDY_ID) into :d_&ds trimmed from src.&ds;
  quit;
%mend count_src;
%count_src(ds=master_data_1);
%count_src(ds=master_data_2);
%count_src(ds=master_data_3);
%count_src(ds=master_data_4);
%count_src(ds=master_data_5);
%count_src(ds=master_data_6);
%count_src(ds=master_data_7);
%count_src(ds=master_data_8);

/* Informational check for the md3 spine expectation (no abort -- plan 02 asserts) */
%if &n_master_data_3 ne 41150 %then
  %put WARNING: md3 NOBS=&n_master_data_3 differs from frozen expectation 41150 -- investigate before merge.;

/* Write aligned report using column pointers (macro-variable resolution inside
   a quoted string does NOT produce fixed-width output) */
filename qccnt "&qc_path.\src_counts.txt";
data _null_;
  file qccnt;
  put "Source Verification Report -- Run: %sysfunc(datetime(), datetime20.)";
  put " ";
  put @1 "Source" @20 "NOBS" @35 "Distinct_IDs";
  put @1 "------------------------------------------------";
  put @1 "master_data_1" @20 "&n_master_data_1" @35 "&d_master_data_1";
  put @1 "master_data_2" @20 "&n_master_data_2" @35 "&d_master_data_2";
  put @1 "master_data_3" @20 "&n_master_data_3" @35 "&d_master_data_3";
  put @1 "master_data_4" @20 "&n_master_data_4" @35 "&d_master_data_4";
  put @1 "master_data_5" @20 "&n_master_data_5" @35 "&d_master_data_5";
  put @1 "master_data_6" @20 "&n_master_data_6" @35 "&d_master_data_6";
  put @1 "master_data_7" @20 "&n_master_data_7" @35 "&d_master_data_7";
  put @1 "master_data_8" @20 "&n_master_data_8" @35 "&d_master_data_8";
run;
filename qccnt clear;


/* === plan 02 appends SRC-05, SRC-01 and SRC-02 assertions below this line === */
