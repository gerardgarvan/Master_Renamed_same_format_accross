/*==========================================================================
  Program : 01_verify_sources.sas
  Phase   : Phase 1 -- Source Verification & Freeze
  Purpose : Preconditions (libname + XCMD + qc path), SRC-06 key verification
            across all eight sources, SHA-256 checksums (SRC-04), per-source
            row/ID counts (SRC-03), then the SRC-05 / SRC-01 / SRC-02
            structural assertions.
  Requirements addressed:
            SRC-03 (per-source row/ID counts)
            SRC-04 (SHA-256 checksums committed to qc/)
            SRC-05 (key never blank / sentinel)
            SRC-06 (PRECEDE_STUDY_ID present, Char 12, in all eight sources)
            SRC-01 / PCM-F-01 (key unique per source)
            SRC-02 / PCM-F-02 (md3 is a complete superset)
  Author  : Executor (Phase 1 Plans 01 + 02)
  Created : 2026-08-25
  Revised : 2026-08-25 -- review fixes:
            * every %abort moved inside a macro definition (%ABORT is not
              valid in open code)
            * %GLOBAL added to count_src so the counts survive the macro
            * blank-key sum() protected against a zero-row source
            * SRC-05 extended to catch the literal 'NULL' sentinel (PCM-F-05)
            * qc output directory checked before the first FILE statement
==========================================================================*/

options mprint;   /* macro-generated code visible in the log for audit */

/* ---- Paths ---- */
%let source_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross;
%let qc_path     = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\qc;
libname src "&source_path" access=readonly;


/*==========================================================================
  PRECONDITIONS
==========================================================================*/

/* ---- Precondition 1: libname must resolve ---- */
%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: LIBNAME &lib could not be assigned. Check P: drive availability.;
    %abort cancel;
  %end;
  %else %put NOTE: LIBNAME &lib resolved.;
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

/* ---- Precondition 3: qc output directory must exist ---- */
/*      Without this, the first FILE statement fails mid-run, after the
        checksums have already been computed.                            */
%macro check_qc_path;
  %if %sysfunc(fileexist(&qc_path)) = 0 %then %do;
    %put ERROR: qc output directory does not exist: &qc_path;
    %put ERROR- Create it before running (it is a committed artifact location).;
    %abort cancel;
  %end;
  %else %put NOTE: qc output directory found: &qc_path;
%mend check_qc_path;
%check_qc_path;

/* ---- Source list (reused by later blocks) ---- */
%let src_list = master_data_1 master_data_2 master_data_3 master_data_4 master_data_5 master_data_6 master_data_7 master_data_8;


/*==========================================================================
  SRC-06: PRECEDE_STUDY_ID present, Char, length 12, in all eight
==========================================================================*/
/* Runs before anything that compares IDs: a numeric key in any source makes
   the SRC-02 anti-join either fail on type mismatch or coerce silently, in
   which case that assertion proves nothing.                                */

proc contents data=src._all_ out=work._allvars
  (keep=memname name type length) noprint;
run;

proc sql noprint;
  /* every source must carry the key */
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

/* %ABORT is valid only inside a macro definition, so the assertion is wrapped */
%macro assert_src06;
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
%mend assert_src06;
%assert_src06;

/*
  Note: upcase(name) = 'PRECEDE_STUDY_ID' deliberately excludes md6's duplicate
  PRECEDE_Study_ID_1 column, whose name differs by the _1 suffix.

  Note: src._all_ enumerates EVERY dataset in the library. If stale artifacts
  from the pre-GSD ad-hoc work (master_data_all, master_data_dedup,
  master_data_merged, master_data_7b) are still in that folder, they appear in
  work._allvars but are excluded by the memname filter. They should still be
  moved out of the source folder so nothing downstream can pick them up.
*/


/*==========================================================================
  SRC-04: SHA-256 checksums via certutil FILENAME PIPE
==========================================================================*/

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
%put NOTE: SRC-04 OK -- eight SHA-256 hashes written to &qc_path.\checksums.txt;


/*==========================================================================
  SRC-03: Per-source row and distinct-ID counts
==========================================================================*/

/* count_src: PROC SQL COUNT(*) for true row count (not PROC CONTENTS nobs,
   which counts deleted observations -- Pitfall 4).
   %GLOBAL is required: this macro has a parameter, so it has a local symbol
   table, and INTO: would otherwise create n_&ds / d_&ds locally and discard
   them at %mend -- leaving the report below with unresolved references. */
%macro count_src(ds=);
  %global n_&ds d_&ds;
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

/* Informational check for the md3 spine expectation (no abort -- a changed
   row count is something to investigate, not a structural violation) */
%macro check_md3_expectation;
  %if &n_master_data_3 ne 41150 %then
    %put WARNING: md3 NOBS=&n_master_data_3 differs from frozen expectation 41150 -- investigate before merge.;
  %else
    %put NOTE: md3 NOBS=41150 matches the frozen spine expectation.;
%mend check_md3_expectation;
%check_md3_expectation;

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
%put NOTE: SRC-03 OK -- per-source counts written to &qc_path.\src_counts.txt;


/* === plan 02 appends SRC-05, SRC-01 and SRC-02 assertions below this line === */

/*==========================================================================
  SRC-05: PRECEDE_STUDY_ID must be non-missing and not a sentinel
==========================================================================*/
/* Runs BEFORE SRC-01: a single blank is "unique" and would pass uniqueness,
   and several blanks would surface there as a confusing duplicate error.
   The 'NULL' arm exists because md8 stores that literal string where the other
   seven store a blank (PCM-F-05) -- a 'NULL' key is not missing(), so the
   blank check alone would not catch it.
   coalesce() guards the zero-row case: sum() over no rows returns missing,
   and %if . > 0 compares as text and silently passes.                       */
%macro assert_no_blank_id(ds=);
  %local n_blank n_sentinel;
  proc sql noprint;
    select coalesce(sum(missing(PRECEDE_STUDY_ID)), 0) into :n_blank trimmed
    from src.&ds;

    select coalesce(sum(upcase(strip(PRECEDE_STUDY_ID)) = 'NULL'), 0) into :n_sentinel trimmed
    from src.&ds;
  quit;

  %if &n_blank > 0 %then %do;
    %put ERROR: SRC-05 VIOLATION: &n_blank blank PRECEDE_STUDY_ID in &ds;
    %put ERROR- A blank key passes uniqueness and the superset check, then becomes;
    %put ERROR- a Phase 4 merge key joining unrelated patients. Fix at source.;
    %abort cancel;
  %end;

  %if &n_sentinel > 0 %then %do;
    %put ERROR: SRC-05 VIOLATION: &n_sentinel literal 'NULL' PRECEDE_STUDY_ID in &ds;
    %put ERROR- This is the md8 sentinel (PCM-F-05). It is not missing(), so it;
    %put ERROR- would survive the blank check and merge as a real key value.;
    %abort cancel;
  %end;

  %put NOTE: SRC-05 OK -- no blank or sentinel PRECEDE_STUDY_ID in &ds;
%mend assert_no_blank_id;

%assert_no_blank_id(ds=master_data_1);
%assert_no_blank_id(ds=master_data_2);
%assert_no_blank_id(ds=master_data_3);
%assert_no_blank_id(ds=master_data_4);
%assert_no_blank_id(ds=master_data_5);
%assert_no_blank_id(ds=master_data_6);
%assert_no_blank_id(ds=master_data_7);
%assert_no_blank_id(ds=master_data_8);


/*==========================================================================
  SRC-01 / PCM-F-01: PRECEDE_STUDY_ID unique per source
==========================================================================*/
%macro assert_unique_id(ds=);
  %local n_dups;
  proc sql noprint;
    /* keep the offenders for diagnosis, then count them explicitly */
    create table work._dups_&ds as
      select PRECEDE_STUDY_ID, count(*) as n
      from src.&ds
      group by PRECEDE_STUDY_ID
      having count(*) > 1;

    select count(*) into :n_dups trimmed from work._dups_&ds;
  quit;
  %if &n_dups > 0 %then %do;
    %put ERROR: PCM-F-01 VIOLATION: Duplicate PRECEDE_STUDY_ID in &ds (&n_dups IDs affected);
    %put ERROR- Offending IDs retained in work._dups_&ds for inspection.;
    %abort cancel;
  %end;
  %else %put NOTE: PCM-F-01 OK -- PRECEDE_STUDY_ID unique in &ds;
%mend assert_unique_id;

%assert_unique_id(ds=master_data_1);
%assert_unique_id(ds=master_data_2);
%assert_unique_id(ds=master_data_3);
%assert_unique_id(ds=master_data_4);
%assert_unique_id(ds=master_data_5);
%assert_unique_id(ds=master_data_6);
%assert_unique_id(ds=master_data_7);
%assert_unique_id(ds=master_data_8);


/*==========================================================================
  SRC-02 / PCM-F-02: md3 is a complete superset of all other IDs
==========================================================================*/
/* Meaningful only because SRC-06 already guaranteed the key is Char 12
   everywhere -- a numeric key would make NOT IN fail or coerce silently. */
proc sql noprint;
  create table work._not_in_md3 as
    select 'md1' as source_ds length=3, PRECEDE_STUDY_ID from src.master_data_1
      where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from src.master_data_3)
    union all
    select 'md2', PRECEDE_STUDY_ID from src.master_data_2
      where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from src.master_data_3)
    union all
    select 'md4', PRECEDE_STUDY_ID from src.master_data_4
      where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from src.master_data_3)
    union all
    select 'md5', PRECEDE_STUDY_ID from src.master_data_5
      where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from src.master_data_3)
    union all
    select 'md6', PRECEDE_STUDY_ID from src.master_data_6
      where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from src.master_data_3)
    union all
    select 'md7', PRECEDE_STUDY_ID from src.master_data_7
      where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from src.master_data_3)
    union all
    select 'md8', PRECEDE_STUDY_ID from src.master_data_8
      where PRECEDE_STUDY_ID not in (select PRECEDE_STUDY_ID from src.master_data_3);

  select count(*) into :n_orphan trimmed from work._not_in_md3;
quit;

/* %ABORT is valid only inside a macro definition, so the assertion is wrapped */
%macro assert_src02;
  %if &n_orphan > 0 %then %do;
    %put ERROR: PCM-F-02 VIOLATION: md3 is NOT a superset -- &n_orphan IDs missing from md3;
    %put ERROR- Orphan IDs retained in work._not_in_md3 (column SOURCE_DS names the source).;
    %put ERROR- Phase 4 assumes md3 is the spine; a merge would silently grow past 41,150 rows.;
    %abort cancel;
  %end;
  %else %put NOTE: PCM-F-02 OK -- md3 is a complete superset of md1,md2,md4-md8;
%mend assert_src02;
%assert_src02;


%put NOTE: ==== Phase 1 source verification complete -- all assertions passed ====;

libname src clear;
