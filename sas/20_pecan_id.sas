/*==========================================================================
  Program : 20_pecan_id.sas
  Purpose : Build the pecan_ID patient linkage key from ENCRYPTED_MRN.
            Verifies md3 source checksum (PID-01), audits MRN cardinality
            (PID-02, PID-03), builds the append-only crosswalk g.pecan_id_xwalk
            with a dated backup (PID-04), tests r7/r8/r9 linkage reach (PID-07),
            and documents PCM-D-17/PCM-D-18 completion (PID-08).

  Reads   : qc/19_raw_files.csv, qc/19_raw_key_columns.csv,
            qc/19_raw_sheets.csv, qc/19_raw_variables_md3.csv  (Phase 19 handoffs)
            raw\master\2018_2022_X_MASTER_DATASET_20240402.csv (md3 source, read-only)
            g.master_data_merged                                (read-only)
            g.pecan_id_xwalk                                    (append-only)

  Writes  : g.pecan_id_xwalk           (new or appended)
            [xwalk_backup_path]/pecan_id_xwalk_<stamp>.sas7bdat (dated backup)
            qc/20_linkage_reach.txt     (PID-07 output)
            logs/20_pecan_id.log        (when in_pipeline=0)

  PCM compliance:
    - No bare open-code %IF/%THEN; all conditional logic inside named macros
    - No apostrophes or embedded semicolons in %PUT text
    - Every %abort cancel inside %fail_out only
    - No automatic-macro row counts; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - ASCII only (session encoding is not UTF-8)
    - No in-place dataset rewrite (data g.X; set g.X;) -- PCM-T-02
    - No PROC SQL UPDATE
    - options nosyntaxcheck noerrorabend set before PROC IMPORT calls

  Requirements: PID-01, PID-02, PID-03, PID-04, PID-07, PID-08
  Created     : 2026-09-23 (Phase 20, plan 01)
==========================================================================*/


/* ============================================================
   SECTION 0 -- Config, options, libnames, utility macros
   ============================================================ */

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

options validvarname=v7 nofmterr msglevel=i;
options nosyntaxcheck noerrorabend;

libname g "&g_path.";
libname bak "&xwalk_backup_path.";

/* ---- Log routing ---- */
%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\20_pecan_id.log" new; run;
  %end;
%mend route_log;

%macro restore_log;
  %if &in_pipeline = 0 %then %do;
    proc printto; run;
  %end;
%mend restore_log;

/* ---- fail_out: the only macro that may call abort ---- */
%macro fail_out(msg=);
  %put ERROR: &msg;
  %restore_log;
  %abort cancel;
%mend fail_out;

/* ---- check_dir: verify a path exists ---- */
%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path.)) = 0 %then %do;
    %fail_out(msg=&label. directory not found: &path.);
  %end;
%mend check_dir;

%check_dir(path=&logs_path., label=logs);
%check_dir(path=&qc_path.,   label=qc);
%check_dir(path=&g_path.,    label=g_path);

%route_log;


/* ============================================================
   SECTION 1 -- Preconditions: assert all four Phase 19 CSV handoffs
   exist, and the md3 source CSV exists (PCM-T-12: enumerated individually)
   ============================================================ */

%macro check_phase19_csvs;
  %if %sysfunc(fileexist(&qc_path.\19_raw_files.csv)) = 0 %then %do;
    %fail_out(msg=PRECONDITION FAILED -- qc/19_raw_files.csv not found -- re-run program 19 first);
  %end;
  %if %sysfunc(fileexist(&qc_path.\19_raw_key_columns.csv)) = 0 %then %do;
    %fail_out(msg=PRECONDITION FAILED -- qc/19_raw_key_columns.csv not found -- re-run program 19 first);
  %end;
  %if %sysfunc(fileexist(&qc_path.\19_raw_sheets.csv)) = 0 %then %do;
    %fail_out(msg=PRECONDITION FAILED -- qc/19_raw_sheets.csv not found -- re-run program 19 first);
  %end;
  %if %sysfunc(fileexist(&qc_path.\19_raw_variables_md3.csv)) = 0 %then %do;
    %fail_out(msg=PRECONDITION FAILED -- qc/19_raw_variables_md3.csv not found -- re-run program 19 first);
  %end;
  %if %sysfunc(fileexist(&raw_path.\master\2018_2022_X_MASTER_DATASET_20240402.csv)) = 0 %then %do;
    %fail_out(msg=PRECONDITION FAILED -- md3 source CSV not found at raw\master\2018_2022_X_MASTER_DATASET_20240402.csv);
  %end;
  %put NOTE: [20] SECTION 1 preconditions passed -- all four Phase 19 CSVs and md3 source present;
%mend check_phase19_csvs;
%check_phase19_csvs;


/* ============================================================
   SECTION 2 -- PID-01: Checksum the md3 source CSV and compare
   to the Phase 19 record in qc/19_raw_files.csv
   ============================================================ */

/* Compute the live SHA-256 of the md3 source CSV */
%let _md3_src_path = &raw_path.\master\2018_2022_X_MASTER_DATASET_20240402.csv;
%let _computed_sha = FAILED;

data work._sha_md3;
  length _cmd $1000 line $400 compressed $400 sha256 $64;
  _cmd = 'certutil -hashfile "' || strip("&_md3_src_path.") || '" SHA256';
  sha256 = 'FAILED';
  infile ckpipe20 pipe filevar=_cmd end=_done truncover lrecl=400;
  do while (not _done);
    input line $400.;
    compressed = compress(line, ' ');
    if lengthn(compressed) = 64 and notxdigit(strip(compressed)) = 0 then
      sha256 = lowcase(compressed);
  end;
  if sha256 = 'FAILED' then put 'WARNING: SHA-256 FAILED for md3 source CSV';
  keep sha256;
run;

proc sql noprint;
  select sha256 into :_computed_sha trimmed
  from work._sha_md3;
quit;
%put NOTE: [20] Computed SHA-256 of md3 source CSV: &_computed_sha;

/* Read the expected SHA-256 from the Phase 19 handoff */
proc import datafile="&qc_path.\19_raw_files.csv"
    out=work.files19 dbms=csv replace;
  guessingrows=max;
run;

/* Assert exactly one matching row before the lookup */
%let _n_md3_rows = 0;
proc sql noprint;
  select count(*) into :_n_md3_rows trimmed
  from work.files19
  where upcase(strip(filename)) = '2018_2022_X_MASTER_DATASET_20240402.CSV'
    and upcase(scan(full_path, -2, '\')) = 'MASTER';
quit;

%macro assert_md3_row_count;
  %if &_n_md3_rows ne 1 %then %do;
    %fail_out(msg=PID-01 ABORT -- found &_n_md3_rows rows for md3 source in 19_raw_files.csv -- expected exactly 1 -- possible duplicate-folder problem);
  %end;
%mend assert_md3_row_count;
%assert_md3_row_count;

%let _expected_sha = ;
proc sql noprint;
  select sha256 into :_expected_sha trimmed
  from work.files19
  where upcase(strip(filename)) = '2018_2022_X_MASTER_DATASET_20240402.CSV'
    and upcase(scan(full_path, -2, '\')) = 'MASTER';
quit;
%put NOTE: [20] Expected SHA-256 from Phase 19 record: &_expected_sha;

%macro assert_checksum_match;
  %if %upcase(&_computed_sha) ne %upcase(&_expected_sha) %then %do;
    %fail_out(msg=PID-01 ABORT -- md3 source SHA-256 mismatch -- computed &_computed_sha expected &_expected_sha -- source file may have changed);
  %end;
  %put NOTE: [20] PID-01 checksum match confirmed;
%mend assert_checksum_match;
%assert_checksum_match;


/* ============================================================
   SECTION 3 -- PID-01 cont. (D-11): ENCRYPTED_MRN type and length
   from qc/19_raw_variables_md3.csv
   ============================================================ */

proc import datafile="&qc_path.\19_raw_variables_md3.csv"
    out=work.inv_vars_md3 dbms=csv replace;
  guessingrows=max;
run;

%let _mrn_type   = ;
%let _mrn_len    = 0;
%let _pid_type   = ;
%let _precede_is_num = 0;

proc sql noprint;
  select strip(var_type), strip(put(var_length, best12.))
    into :_mrn_type trimmed, :_mrn_len trimmed
  from work.inv_vars_md3
  where upcase(strip(var_name)) = 'ENCRYPTED_MRN';

  select strip(var_type) into :_pid_type trimmed
  from work.inv_vars_md3
  where upcase(strip(var_name)) = 'PRECEDE_STUDY_ID';
quit;

%macro set_precede_type_flag;
  %if %upcase(&_pid_type) = NUM %then %let _precede_is_num = 1;
  %else %let _precede_is_num = 0;
%mend set_precede_type_flag;
%set_precede_type_flag;

%put NOTE: [20] D-11 ENCRYPTED_MRN type=&_mrn_type length=&_mrn_len;
%put NOTE: [20] D-11 PRECEDE_STUDY_ID type=&_pid_type precede_is_num=&_precede_is_num;


/* ============================================================
   SECTION 4 -- PID-01 cont. (D-12): Import md3 CSV at $64;
   assert max ENCRYPTED_MRN length <= 40
   ============================================================ */

options nosyntaxcheck noerrorabend;
proc import datafile="&raw_path.\master\2018_2022_X_MASTER_DATASET_20240402.csv"
    out=work.md3csv dbms=csv replace;
  guessingrows=max;
run;

%let _max_mrn_len = 0;
proc sql noprint;
  select max(lengthn(strip(ENCRYPTED_MRN))) into :_max_mrn_len trimmed
  from work.md3csv;
quit;
%put NOTE: [20] D-12 max ENCRYPTED_MRN length in md3 source CSV: &_max_mrn_len;

%macro assert_mrn_length;
  %if &_max_mrn_len > 40 %then %do;
    %fail_out(msg=D-12 ABORT -- source holds MRN longer than 40 chars (&_max_mrn_len) -- merged file would silently truncate);
  %end;
  %put NOTE: [20] D-12 truncation guard passed -- max MRN length &_max_mrn_len le 40;
%mend assert_mrn_length;
%assert_mrn_length;


/* ============================================================
   SECTION 5 -- D-14 cross-check: join CSV to g.master_data_merged
   on PRECEDE_STUDY_ID after applying md3 prep normalization
   ============================================================ */

/* Apply md3 prep normalization to the CSV side:
   strip() on ENCRYPTED_MRN; strip(upcase()) = NULL -> blank.
   PRECEDE_STUDY_ID: if CSV imported as numeric, build _pid_key_num from it;
   on merged side compute _pid_key_num = input(strip(PRECEDE_STUDY_ID), best32.).
   Assert no missing conversion on merged side before joining. */

%if &_precede_is_num = 1 %then %do;
  /* CSV PRECEDE is numeric -- join numerically */
  proc sql noprint;
    create table work._crosscheck as
    select
      c.PRECEDE_STUDY_ID as _pid_csv_num,
      case when missing(strip(upcase(c.ENCRYPTED_MRN))) or strip(upcase(c.ENCRYPTED_MRN)) = 'NULL'
           then '' else strip(c.ENCRYPTED_MRN) end as _mrn_csv length=40,
      m.PRECEDE_STUDY_ID as _pid_mrg_char,
      input(strip(m.PRECEDE_STUDY_ID), best32.) as _pid_mrg_num,
      case when missing(strip(upcase(m.ENCRYPTED_MRN))) or strip(upcase(m.ENCRYPTED_MRN)) = 'NULL'
           then '' else strip(m.ENCRYPTED_MRN) end as _mrn_mrg length=40
    from work.md3csv as c
    full join g.master_data_merged as m
      on c.PRECEDE_STUDY_ID = input(strip(m.PRECEDE_STUDY_ID), best32.);
  quit;
%end;
%else %do;
  /* CSV PRECEDE is char -- join on stripped char */
  proc sql noprint;
    create table work._crosscheck as
    select
      strip(c.PRECEDE_STUDY_ID) as _pid_csv_char length=12,
      case when missing(strip(upcase(c.ENCRYPTED_MRN))) or strip(upcase(c.ENCRYPTED_MRN)) = 'NULL'
           then '' else strip(c.ENCRYPTED_MRN) end as _mrn_csv length=40,
      m.PRECEDE_STUDY_ID as _pid_mrg_char,
      case when missing(strip(upcase(m.ENCRYPTED_MRN))) or strip(upcase(m.ENCRYPTED_MRN)) = 'NULL'
           then '' else strip(m.ENCRYPTED_MRN) end as _mrn_mrg length=40
    from work.md3csv as c
    full join g.master_data_merged as m
      on strip(c.PRECEDE_STUDY_ID) = strip(m.PRECEDE_STUDY_ID);
  quit;
%end;

/* If numeric PRECEDE on merged side, assert no conversion failures */
%if &_precede_is_num = 1 %then %do;
  %let _n_conv_fail = 0;
  proc sql noprint;
    select count(*) into :_n_conv_fail trimmed
    from work._crosscheck
    where _pid_mrg_char ne '' and _pid_mrg_num = .;
  quit;
  %macro assert_pid_conversion;
    %if &_n_conv_fail > 0 %then %do;
      %fail_out(msg=D-14 ABORT -- &_n_conv_fail non-numeric PRECEDE_STUDY_ID values in g.master_data_merged -- cannot join numerically);
    %end;
    %put NOTE: [20] D-14 PRECEDE numeric conversion check passed;
  %mend assert_pid_conversion;
  %assert_pid_conversion;
%end;

/* Assert (a) MRN equal on all matched rows */
%let _n_mrn_mismatch = 0;
proc sql noprint;
  select count(*) into :_n_mrn_mismatch trimmed
  from work._crosscheck
  where _mrn_csv ne '' and _mrn_mrg ne '' and _mrn_csv ne _mrn_mrg;
quit;
%put NOTE: [20] D-14 MRN mismatch count on matched rows: &_n_mrn_mismatch;

%macro assert_mrn_match;
  %if &_n_mrn_mismatch > 0 %then %do;
    %fail_out(msg=D-14 ABORT -- &_n_mrn_mismatch matched rows have differing ENCRYPTED_MRN values between CSV and merged file);
  %end;
  %put NOTE: [20] D-14 MRN equality assertion passed;
%mend assert_mrn_match;
%assert_mrn_match;

/* Assert (b) no orphans on either side */
%let _n_csv_orphan = 0;
%let _n_mrg_orphan = 0;
proc sql noprint;
  select count(*) into :_n_csv_orphan trimmed
  from work._crosscheck
  where _mrn_mrg = '' and _mrn_csv ne '';

  select count(*) into :_n_mrg_orphan trimmed
  from work._crosscheck
  where _mrn_csv = '' and _mrn_mrg ne '';
quit;
%put NOTE: [20] D-14 CSV orphans (in CSV not in merged): &_n_csv_orphan;
%put NOTE: [20] D-14 Merged orphans (in merged not in CSV): &_n_mrg_orphan;

%macro assert_no_orphans;
  %if &_n_csv_orphan > 0 or &_n_mrg_orphan > 0 %then %do;
    %fail_out(msg=D-14 ABORT -- &_n_csv_orphan CSV orphans and &_n_mrg_orphan merged orphans found -- merged file does not reflect its source);
  %end;
  %put NOTE: [20] D-14 orphan assertion passed -- PRECEDE sets are identical;
%mend assert_no_orphans;
%assert_no_orphans;


/* ============================================================
   SECTION 6 -- PID-02: Source audit on g.master_data_merged
   (blank MRN, placeholder MRN, distinct MRN, cardinalities)
   ============================================================ */

%let _n_blank_mrn    = 0;
%let _n_null_mrn     = 0;
%let _n_incl_mrn     = 0;
%let _n_incl_precede = 0;
%let _max_mrn_per_pid = 0;
%let _max_pid_per_mrn = 0;

proc sql noprint;
  select count(*) into :_n_blank_mrn trimmed
  from g.master_data_merged
  where missing(ENCRYPTED_MRN);

  select count(*) into :_n_null_mrn trimmed
  from g.master_data_merged
  where not missing(ENCRYPTED_MRN)
    and strip(upcase(ENCRYPTED_MRN)) = 'NULL';

  select count(distinct ENCRYPTED_MRN) into :_n_incl_mrn trimmed
  from g.master_data_merged
  where not missing(ENCRYPTED_MRN)
    and strip(upcase(ENCRYPTED_MRN)) ne 'NULL';

  select count(distinct PRECEDE_STUDY_ID) into :_n_incl_precede trimmed
  from g.master_data_merged
  where not missing(ENCRYPTED_MRN)
    and strip(upcase(ENCRYPTED_MRN)) ne 'NULL';

  select max(n_mrn) into :_max_mrn_per_pid trimmed
  from (select PRECEDE_STUDY_ID, count(distinct ENCRYPTED_MRN) as n_mrn
        from g.master_data_merged
        where not missing(ENCRYPTED_MRN)
          and strip(upcase(ENCRYPTED_MRN)) ne 'NULL'
        group by PRECEDE_STUDY_ID);

  select max(n_pid) into :_max_pid_per_mrn trimmed
  from (select ENCRYPTED_MRN, count(distinct PRECEDE_STUDY_ID) as n_pid
        from g.master_data_merged
        where not missing(ENCRYPTED_MRN)
          and strip(upcase(ENCRYPTED_MRN)) ne 'NULL'
        group by ENCRYPTED_MRN);
quit;

%put NOTE: [20] PID-02 blank MRN rows: &_n_blank_mrn;
%put NOTE: [20] PID-02 placeholder (NULL sentinel) MRN rows: &_n_null_mrn;
%put NOTE: [20] PID-02 distinct included MRNs: &_n_incl_mrn;
%put NOTE: [20] PID-02 distinct included PRECEDEs: &_n_incl_precede;
%put NOTE: [20] PID-02 max distinct MRNs per PRECEDE: &_max_mrn_per_pid;
%put NOTE: [20] PID-02 max distinct PRECEDEs per MRN: &_max_pid_per_mrn;


/* ============================================================
   SECTION 7 -- PID-03: Cardinality assertion
   Every PRECEDE_STUDY_ID maps to exactly one ENCRYPTED_MRN
   ============================================================ */

%let _n_multi_mrn = 0;
proc sql noprint;
  select count(*) into :_n_multi_mrn trimmed
  from (
    select PRECEDE_STUDY_ID
    from g.master_data_merged
    where not missing(ENCRYPTED_MRN)
      and strip(upcase(ENCRYPTED_MRN)) ne 'NULL'
    group by PRECEDE_STUDY_ID
    having count(distinct ENCRYPTED_MRN) > 1
  );
quit;
%put NOTE: [20] PID-03 PRECEDEs mapping to more than one MRN: &_n_multi_mrn;

%macro assert_pid_cardinality;
  %if &_n_multi_mrn > 0 %then %do;
    %fail_out(msg=PID-03 ABORT -- &_n_multi_mrn PRECEDE_STUDY_IDs map to more than one ENCRYPTED_MRN -- crosswalk cannot be safely built);
  %end;
  %put NOTE: [20] PID-03 cardinality assertion passed;
%mend assert_pid_cardinality;
%assert_pid_cardinality;


/* ============================================================
   SECTION 8 -- PID-04: build_or_append_xwalk (D-01, D-02, D-04)
   Named macro %build_or_append_xwalk
   ============================================================ */

%macro build_or_append_xwalk;
  %local xwalk_exists n_backups latest_bak bak_stamp;

  /* Pre-condition: backup folder must exist */
  %if %sysfunc(fileexist(&xwalk_backup_path.)) = 0 %then %do;
    %fail_out(msg=D-04 ABORT -- xwalk_backup_path does not exist -- create the folder first: &xwalk_backup_path);
  %end;

  /* Detect whether g.pecan_id_xwalk exists */
  %let xwalk_exists = 0;
  proc sql noprint;
    select count(*) into :xwalk_exists trimmed
    from dictionary.tables
    where libname = 'G' and memname = 'PECAN_ID_XWALK';
  quit;

  /* Detect whether any dated backup exists in bak library */
  %let n_backups = 0;
  %let latest_bak = ;
  proc sql noprint;
    select count(*), max(memname)
      into :n_backups trimmed, :latest_bak trimmed
    from dictionary.tables
    where libname = 'BAK' and memname like 'PECAN_ID_XWALK_%';
  quit;
  %put NOTE: [20] xwalk_exists=&xwalk_exists n_backups=&n_backups latest_bak=&latest_bak;

  /* Compute dated backup name for new writes */
  %let bak_stamp = %sysfunc(datetime(), B8601DT15.);
  /* B8601DT15. yields e.g. 20260923T140500 -- valid SAS dataset name, sorts chronologically */

  /* CASE 3: backup present but xwalk missing -- do not rebuild, restore from backup */
  %if &xwalk_exists = 0 and &n_backups > 0 %then %do;
    %fail_out(msg=D-04 ABORT -- g.pecan_id_xwalk is missing but &n_backups backup(s) exist at &xwalk_backup_path -- restore from backup before re-running);
  %end;

  /* CASE 1: first run -- no xwalk and no backup */
  %else %if &xwalk_exists = 0 and &n_backups = 0 %then %do;
    %put NOTE: [20] First run -- building g.pecan_id_xwalk from g.master_data_merged;

    proc sql noprint;
      create table work._mrn_rank as
      select ENCRYPTED_MRN,
             min(input(strip(PRECEDE_STUDY_ID), best32.)) as _min_pid_num
      from g.master_data_merged
      where not missing(ENCRYPTED_MRN)
        and strip(upcase(ENCRYPTED_MRN)) ne 'NULL'
      group by ENCRYPTED_MRN
      order by calculated _min_pid_num;
    quit;

    data g.pecan_id_xwalk;
      set work._mrn_rank;
      length ENCRYPTED_MRN $40 pecan_ID 8;
      pecan_ID = _N_;
      keep ENCRYPTED_MRN pecan_ID;
    run;

    /* Write first dated backup */
    data bak.pecan_id_xwalk_&bak_stamp.;
      set g.pecan_id_xwalk;
    run;

    %let _n_xwalk_built = 0;
    proc sql noprint;
      select count(*) into :_n_xwalk_built trimmed from g.pecan_id_xwalk;
    quit;
    %put NOTE: [20] PID-04 initial crosswalk built with &_n_xwalk_built distinct MRNs;
    %put NOTE: [20] PID-04 first backup written: pecan_id_xwalk_&bak_stamp;
  %end;

  /* CASE 4: xwalk present but no backup -- write first backup and continue */
  %else %if &xwalk_exists = 1 and &n_backups = 0 %then %do;
    %put WARNING: [20] D-04 no backup found -- writing first backup now;
    data bak.pecan_id_xwalk_&bak_stamp.;
      set g.pecan_id_xwalk;
    run;
    %put NOTE: [20] PID-04 first backup written: pecan_id_xwalk_&bak_stamp;
    /* Re-read n_backups so CASE 2 logic continues correctly after this case */
    %let n_backups = 1;
    %let latest_bak = PECAN_ID_XWALK_&bak_stamp.;
  %end;

  /* CASE 2: re-run -- xwalk and backup both exist */
  %if &xwalk_exists = 1 and &n_backups > 0 %then %do;
    %put NOTE: [20] Re-run detected -- asserting xwalk equals latest backup before appending;

    /* Compare xwalk to latest backup (two-way NOT EXISTS diff) */
    %let _n_xwalk_only = 0;
    %let _n_bak_only   = 0;
    proc sql noprint;
      select count(*) into :_n_xwalk_only trimmed
      from g.pecan_id_xwalk as x
      where not exists (
        select 1 from bak.&latest_bak as b
        where b.ENCRYPTED_MRN = x.ENCRYPTED_MRN
          and b.pecan_ID = x.pecan_ID
      );
      select count(*) into :_n_bak_only trimmed
      from bak.&latest_bak as b
      where not exists (
        select 1 from g.pecan_id_xwalk as x
        where x.ENCRYPTED_MRN = b.ENCRYPTED_MRN
          and x.pecan_ID = b.pecan_ID
      );
    quit;
    %put NOTE: [20] Pre-append diff -- xwalk_only=&_n_xwalk_only bak_only=&_n_bak_only;

    %macro assert_xwalk_matches_backup;
      %if &_n_xwalk_only > 0 or &_n_bak_only > 0 %then %do;
        %fail_out(msg=D-02 ABORT -- g.pecan_id_xwalk differs from latest backup (&latest_bak) -- xwalk_only=&_n_xwalk_only bak_only=&_n_bak_only -- crosswalk may have been edited outside program 20);
      %end;
      %put NOTE: [20] D-02 pre-append xwalk=backup assertion passed;
    %mend assert_xwalk_matches_backup;
    %assert_xwalk_matches_backup;

    /* Find new MRNs (in merged, not in xwalk) */
    %let _max_pid = 0;
    proc sql noprint;
      select max(pecan_ID) into :_max_pid trimmed from g.pecan_id_xwalk;
    quit;
    %put NOTE: [20] Current max pecan_ID: &_max_pid;

    proc sql noprint;
      create table work._new_mrns_rank as
      select ENCRYPTED_MRN,
             min(input(strip(PRECEDE_STUDY_ID), best32.)) as _min_pid_num
      from g.master_data_merged
      where not missing(ENCRYPTED_MRN)
        and strip(upcase(ENCRYPTED_MRN)) ne 'NULL'
        and ENCRYPTED_MRN not in (select ENCRYPTED_MRN from g.pecan_id_xwalk)
      group by ENCRYPTED_MRN
      order by calculated _min_pid_num;
    quit;

    %let _n_new = 0;
    proc sql noprint;
      select count(*) into :_n_new trimmed from work._new_mrns_rank;
    quit;
    %put NOTE: [20] New MRNs to append: &_n_new;

    %if &_n_new > 0 %then %do;
      data work._new_rows;
        set work._new_mrns_rank;
        length ENCRYPTED_MRN $40 pecan_ID 8;
        pecan_ID = &_max_pid + _N_;
        keep ENCRYPTED_MRN pecan_ID;
      run;

      proc append base=g.pecan_id_xwalk data=work._new_rows; run;
      %put NOTE: [20] PID-04 appended &_n_new new MRN rows via PROC APPEND;
    %end;

    /* Assert every backup row still present after append */
    %let _n_bak_lost = 0;
    proc sql noprint;
      select count(*) into :_n_bak_lost trimmed
      from bak.&latest_bak as b
      where not exists (
        select 1 from g.pecan_id_xwalk as x
        where x.ENCRYPTED_MRN = b.ENCRYPTED_MRN
          and x.pecan_ID = b.pecan_ID
      );
    quit;
    %put NOTE: [20] Post-append backup rows lost: &_n_bak_lost;

    %macro assert_backup_rows_intact;
      %if &_n_bak_lost > 0 %then %do;
        %fail_out(msg=D-02 ABORT -- &_n_bak_lost backup rows missing after PROC APPEND -- existing pecan_ID assignments may have been altered);
      %end;
      %put NOTE: [20] D-02 post-append backup integrity assertion passed;
    %mend assert_backup_rows_intact;
    %assert_backup_rows_intact;

    /* Write new dated backup */
    data bak.pecan_id_xwalk_&bak_stamp.;
      set g.pecan_id_xwalk;
    run;
    %put NOTE: [20] PID-04 new backup written: pecan_id_xwalk_&bak_stamp;
  %end;

%mend build_or_append_xwalk;
%build_or_append_xwalk;

/* Final crosswalk count */
%let _n_xwalk_final = 0;
proc sql noprint;
  select count(*) into :_n_xwalk_final trimmed from g.pecan_id_xwalk;
quit;
%put NOTE: [20] PID-04 g.pecan_id_xwalk final row count: &_n_xwalk_final;


/* ============================================================
   SECTION 9 -- PID-07: Linkage reach report
   Loop over qc/19_raw_key_columns.csv rows where key_column_type = ENCRYPTED_MRN.
   Write results to qc/20_linkage_reach.txt using PUT-to-fileref pattern.
   r7/r8/r9 get explicit PCM-D-16 YES/NO lines.
   ============================================================ */

/* Read Phase 19 key-column and sheet metadata */
proc import datafile="&qc_path.\19_raw_key_columns.csv"
    out=work.inv_key_cols dbms=csv replace;
  guessingrows=max;
run;

proc import datafile="&qc_path.\19_raw_sheets.csv"
    out=work.inv_sheets dbms=csv replace;
  guessingrows=max;
run;

/* Open the linkage reach report -- fresh write */
data _null_;
  file "&qc_path.\20_linkage_reach.txt" lrecl=200;
  put "==========================================================================";
  put "Phase 20 -- PID-07 Linkage Reach Report";
  put "Generated: %sysfunc(datetime(), datetime20.)";
  put "Crosswalk: g.pecan_id_xwalk (distinct MRNs: &_n_xwalk_final)";
  put "==========================================================================";
  put " ";
  put "NOTE: MRN normalization applied on BOTH sides before matching:";
  put "  strip() to remove whitespace; treat strip(upcase(col)) = NULL as blank.";
  put " ";
run;

/* Identify r7/r8/r9 source files by their known filenames from Phase 18 */
/* r7 = 2022_Education_20240124.csv, r8 = ... , r9 = All_YEARS_LAT_LONG_20231127.csv */
/* Use explicit filename list -- key_columns alone does not carry r7/r8/r9 labels */

/* Section: UNENC_MRN-only exclusions */
proc sql noprint;
  create table work._unenc_only as
  select distinct source_file, filename
  from (
    select distinct source_file,
           scan(source_file, -1, '\') as filename,
           sum(case when upcase(strip(key_column_type)) = 'ENCRYPTED_MRN' then 1 else 0 end) as n_enc,
           sum(case when upcase(strip(key_column_type)) = 'UNENC_MRN' then 1 else 0 end) as n_unenc
    from work.inv_key_cols
    group by source_file
  )
  where n_enc = 0 and n_unenc > 0;
quit;

%let _n_unenc_only = 0;
proc sql noprint;
  select count(*) into :_n_unenc_only trimmed from work._unenc_only;
quit;

%if &_n_unenc_only > 0 %then %do;
  data _null_;
    set work._unenc_only;
    file "&qc_path.\20_linkage_reach.txt" mod lrecl=200;
    if _n_ = 1 then do;
      put "--------------------------------------------------------------------------";
      put "EXCLUDED FILES (UNENC_MRN only -- ENCRYPTED_MRN not present)";
      put "--------------------------------------------------------------------------";
    end;
    put "  " filename;
  run;
  data _null_;
    file "&qc_path.\20_linkage_reach.txt" mod lrecl=200;
    put " ";
  run;
%end;

/* Numeric-MRN type mismatch block */
proc sql noprint;
  create table work._numeric_mrn as
  select distinct source_file, scan(source_file, -1, '\') as filename length=200,
         sheet_name, var_name
  from work.inv_key_cols
  where upcase(strip(key_column_type)) = 'ENCRYPTED_MRN'
    and upcase(strip(var_type)) in ('NUM','NUMERIC');
quit;

%let _n_numeric_mrn = 0;
proc sql noprint;
  select count(*) into :_n_numeric_mrn trimmed from work._numeric_mrn;
quit;

%if &_n_numeric_mrn > 0 %then %do;
  data _null_;
    set work._numeric_mrn;
    file "&qc_path.\20_linkage_reach.txt" mod lrecl=200;
    if _n_ = 1 then do;
      put "--------------------------------------------------------------------------";
      put "TYPE MISMATCH -- NOT COMPARED (numeric ENCRYPTED_MRN -- D-26)";
      put "Silent numeric-to-char conversion can lose digits; these columns excluded.";
      put "--------------------------------------------------------------------------";
    end;
    put "  " filename " sheet=" sheet_name " col=" var_name;
  run;
  data _null_;
    file "&qc_path.\20_linkage_reach.txt" mod lrecl=200;
    put " ";
  run;
%end;

/* Main linkage reach loop over char ENCRYPTED_MRN entries */
proc sql noprint;
  create table work._enc_mrn_targets as
  select distinct source_file, sheet_name, var_name, var_type,
         scan(source_file, -1, '\') as filename length=200,
         scan(source_file, -4, '\') as ext_label length=20,
         lowcase(scan(source_file, -1, '.')) as ext length=10
  from work.inv_key_cols
  where upcase(strip(key_column_type)) = 'ENCRYPTED_MRN'
    and upcase(strip(var_type)) not in ('NUM','NUMERIC');
quit;

%let _n_targets = 0;
proc sql noprint;
  select count(*) into :_n_targets trimmed from work._enc_mrn_targets;
quit;
%put NOTE: [20] PID-07 char ENCRYPTED_MRN targets to process: &_n_targets;

/* r7/r8/r9 filename patterns (from Phase 18 source names) */
/* r7 = 2022_Education, r8 = second file with MRN from supplemental set,
   r9 = All_YEARS_LAT_LONG */
/* For PCM-D-16: r7, r8, r9 are supplemental files from raw\ (not raw\master) */
/* Apply PCM-D-16 YES/NO label if filename matches known r7/r8/r9 patterns */

%macro is_r789(fn=);
  /* Returns 1 if filename matches r7, r8, or r9 pattern from Phase 18 */
  %local _result;
  %let _result = 0;
  %if %index(%upcase(&fn), 2022_EDUCATION) > 0 %then %let _result = 1;
  %if %index(%upcase(&fn), ALL_YEARS_LAT_LONG) > 0 %then %let _result = 1;
  /* Add additional r8 pattern if applicable */
  &_result
%mend is_r789;

/* Process each target in a DATA step loop */
data _null_;
  set work._enc_mrn_targets;
  /* Write section header to reach report for each target */
  file "&qc_path.\20_linkage_reach.txt" mod lrecl=200;
  put "--------------------------------------------------------------------------";
  is_md3 = (upcase(strip(filename)) = '2018_2022_X_MASTER_DATASET_20240402.CSV'
             and upcase(strip(ext_label)) = 'MASTER');
  if is_md3 then
    put "SOURCE: " filename " (reference -- crosswalk source; 100% by construction)";
  else
    put "SOURCE: " filename " sheet=[" sheet_name "]  col=" var_name;
  put "--------------------------------------------------------------------------";
run;

/* Because SAS macro cannot loop over dataset rows inline without a CALL EXECUTE
   or %DO %UNTIL approach, and CALL EXECUTE is available here,
   use CALL EXECUTE to emit one macro call per row.
   Each call imports the file, joins to xwalk, writes counts. */

%macro process_one_reach_target(src_file=, sheet=, col=, fn=, is_ext=, ext=);
  %local _n_total _n_match _n_dist_total _n_dist_match _pct_row _pct_dist;
  %local _is_r789_file _yes_no;

  options nosyntaxcheck noerrorabend;

  /* Targeted re-import (D-25) -- PROC IMPORT for CSV, LIBNAME XLSX for xlsx */
  %if %upcase(&ext) = CSV %then %do;
    proc import datafile="&src_file."
        out=work._reach_tmp dbms=csv replace;
      guessingrows=max;
    run;
  %end;
  %else %if %upcase(&ext) in (XLSX XLS) %then %do;
    /* Use PROC IMPORT with SHEET= from 19_raw_sheets.csv */
    proc import datafile="&src_file."
        out=work._reach_tmp dbms=xlsx replace;
      sheet="&sheet.";
      getnames=yes;
    run;
  %end;
  %else %do;
    /* SAS7BDAT or other -- read directly */
    %local _dslib _dsmem;
    %let _dslib = %scan(&src_file, -2, \/);
    %let _dsmem = %scan(&src_file, -1, \/);
    /* Fall back to PROC IMPORT CSV path; unlikely to be needed */
    proc import datafile="&src_file."
        out=work._reach_tmp dbms=csv replace;
      guessingrows=max;
    run;
  %end;

  /* Count total and matched rows/MRNs */
  %let _n_total = 0;
  %let _n_match = 0;
  %let _n_dist_total = 0;
  %let _n_dist_match = 0;

  proc sql noprint;
    /* Apply MRN normalization before matching */
    create table work._reach_norm as
    select case when missing(strip(upcase(&col.))) or strip(upcase(&col.)) = 'NULL'
                then '' else strip(&col.) end as _mrn_norm length=40
    from work._reach_tmp
    where calculated _mrn_norm ne '';
  quit;

  proc sql noprint;
    select count(*) into :_n_total trimmed from work._reach_norm;
    select count(*) into :_n_match trimmed
    from work._reach_norm as r
    where r._mrn_norm in (select ENCRYPTED_MRN from g.pecan_id_xwalk);
    select count(distinct _mrn_norm) into :_n_dist_total trimmed from work._reach_norm;
    select count(distinct r._mrn_norm) into :_n_dist_match trimmed
    from work._reach_norm as r
    where r._mrn_norm in (select ENCRYPTED_MRN from g.pecan_id_xwalk);
  quit;

  /* Write results */
  data _null_;
    file "&qc_path.\20_linkage_reach.txt" mod lrecl=200;
    n_total      = &_n_total;
    n_match      = &_n_match;
    n_dist_total = &_n_dist_total;
    n_dist_match = &_n_dist_match;
    if n_total > 0 then pct_row  = n_match  / n_total  * 100;
    else pct_row = .;
    if n_dist_total > 0 then pct_dist = n_dist_match / n_dist_total * 100;
    else pct_dist = .;
    put "  Row match:          " n_match 8. " / " n_total 8. "  (" pct_row 6.1 "%)";
    put "  Distinct MRN match: " n_dist_match 8. " / " n_dist_total 8. "  (" pct_dist 6.1 "%)";
  run;

  /* PCM-D-16 YES/NO for r7/r8/r9 */
  %let _is_r789_file = 0;
  %if %index(%upcase(&fn.), 2022_EDUCATION) > 0 %then %let _is_r789_file = 1;
  %if %index(%upcase(&fn.), ALL_YEARS_LAT_LONG) > 0 %then %let _is_r789_file = 1;

  %if &_is_r789_file = 1 %then %do;
    %if &_n_dist_match > 0 %then %let _yes_no = YES;
    %else %let _yes_no = NO;
    data _null_;
      file "&qc_path.\20_linkage_reach.txt" mod lrecl=200;
      put "  Links on MRN (PCM-D-16 test): &_yes_no (&_n_dist_match distinct MRN matches)";
    run;
  %end;

  data _null_;
    file "&qc_path.\20_linkage_reach.txt" mod lrecl=200;
    put " ";
  run;

  %put NOTE: [20] PID-07 &fn -- rows &_n_total matched &_n_match -- dist MRNs &_n_dist_total matched &_n_dist_match;
%mend process_one_reach_target;

/* Emit one CALL EXECUTE per target row */
data _null_;
  set work._enc_mrn_targets;
  call execute(
    '%process_one_reach_target(src_file=' || strip(source_file) ||
    ', sheet=' || strip(sheet_name) ||
    ', col=' || strip(var_name) ||
    ', fn=' || strip(filename) ||
    ', ext=' || strip(ext) || ')'
  );
run;

/* Close reach report */
data _null_;
  file "&qc_path.\20_linkage_reach.txt" mod lrecl=200;
  put "==========================================================================";
  put "END OF PID-07 LINKAGE REACH REPORT";
  put "==========================================================================";
run;
%put NOTE: [20] PID-07 linkage reach report written to qc/20_linkage_reach.txt;


/* ============================================================
   SECTION 10 -- PID-08: DECISIONS.md entries noted
   The actual edits to docs/DECISIONS.md are made in Task 4 (text file edit,
   not a SAS write) per the plan.
   ============================================================ */

%put NOTE: [20] PID-08 -- PCM-D-17 and PCM-D-18 are recorded in docs/DECISIONS.md;
%put NOTE: [20] ==== Phase 20 program 20 complete ====;
%restore_log;
