/*==========================================================================
  Program : 19_raw_dir_inventory.sas
  Purpose : Recursive inventory of &raw_path; seven-sheet workbook +
            machine-readable CSV handoff for Phase 20.

  Reads   : Everything under &raw_path (read-only).
            No g.* datasets are read or written.

  Writes  : qc/19_raw_inventory.xlsx  -- seven-sheet human-facing workbook
            qc/19_raw_files.csv       -- machine-readable Phase 20 handoff
            logs/19_raw_dir_inventory.log

  XCMD required: certutil and dir are called through PIPE; the batch session
    must have XCMD enabled (shared constraint with RUN-01 in Phase 21).

  PCM compliance:
    - No bare open-code %IF/%THEN; all conditional logic inside named macros
    - No apostrophes or embedded semicolons in %PUT text
    - Every %abort cancel inside %fail_out only
    - No automatic-macro row counts; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - dictionary.columns.type is char/num not 1/2 (PCM-T-13)
    - ASCII only (session encoding is not UTF-8)
    - No in-place dataset rewrite (data X; set X;) -- PCM-T-02
    - No PROC SQL UPDATE
    - options nosyntaxcheck noerrorabend set before any PROC IMPORT

  Path handling: file paths are never passed through macro variables.
    Paths go from data to filerefs/librefs via the FILENAME() and LIBNAME()
    functions, and certutil is driven with INFILE PIPE FILEVAR=, so names
    containing ampersands, percent signs or commas cannot break macro code.

  Author  : GSD Phase 19 Plan 01
  Revised : 2026-09-23 (review round 4 -- per-sheet status, exact raw\master match,
            single-type tables)
==========================================================================*/

/* ============================================================
   SECTION 0 -- Header, %include, options
   ============================================================ */
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
options validvarname=v7 validmemname=extend nofmterr msglevel=i;
options nosyntaxcheck noerrorabend;   /* MUST precede any PROC IMPORT */
%include "&sas_path.\macros_raw_import.sas";   /* included per CONTEXT; not called */
title;


/* ============================================================
   SECTION 1 -- Utility macros
   ============================================================ */
%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\19_raw_dir_inventory.log" new; run;
  %end;
%mend route_log;

%macro restore_log;
  %if &in_pipeline = 0 %then %do;
    proc printto; run;
  %end;
%mend restore_log;

%macro fail_out(msg=);
  %put ERROR: &msg;
  ods excel close;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;

%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %fail_out(msg=&label directory not found: &path);
  %end;
%mend check_dir;


/* ============================================================
   SECTION 2 -- Preconditions
   ============================================================ */
%check_dir(path=&logs_path, label=logs);
%route_log;
%check_dir(path=&qc_path, label=qc);
%check_dir(path=&raw_path, label=raw);
%put NOTE: ==== Phase 19 raw directory inventory starting ====;


/* ============================================================
   SECTION 3 -- Directory traversal and file metadata
   /a-d excludes directory lines so folders never become FILES rows.
   ============================================================ */
filename dirpipe pipe "dir /s /b /a-d ""&raw_path""";
data work.files_raw;
  infile dirpipe truncover lrecl=1000;
  length full_path $500 filename $200 ext $20;
  input full_path $500.;
  full_path = strip(full_path);
  if lengthn(full_path) = 0 then delete;
  filename  = scan(full_path, -1, '\');
  ext       = lowcase(scan(filename, -1, '.'));
  file_id   + 1;
run;
filename dirpipe clear;

/* Size, date and file type. Writes a NEW dataset (PCM-T-02).
   FOPEN takes a fileref, so assign one with FILENAME() first (B-05). */
data work.files_meta;
  set work.files_raw;
  length fsize 8 fdate $30 ftype $10;
  _rc = filename('_fr_', full_path);
  _fid = fopen('_fr_');
  if _fid > 0 then do;
    fsize = input(finfo(_fid, 'File Size (bytes)'), best32.);
    fdate = finfo(_fid, 'Last Modified');
    _rc   = fclose(_fid);
  end;
  else do;
    fsize = .;
    fdate = 'UNKNOWN';
  end;
  _rc = filename('_fr_');
  if ext in ('csv', 'xlsx', 'xls', 'sas7bdat') then ftype = ext;
  else ftype = 'other';
  drop _rc _fid;
run;


/* ============================================================
   SECTION 4 -- D-02b presence assertion (md1-md8)
   Each required extract must appear exactly once under raw\master.
   Only the CSV form of md3 is required (B-01).
   ============================================================ */
data work.required_files;
  length req_filename $200;
  infile datalines truncover;
  input req_filename $200.;
  datalines;
2018_2019_CPT_ROLLUP_X_MASTER_DATASET_20200801.csv
2018_2019_X_MASTER_DATASET_20200801.csv
2018_2022_X_MASTER_DATASET_20240402.csv
2020_CPT_ROLLUP_X_MASTER_DATASET_20210609.csv
2020_X_MASTER_DATASET_20210519.csv
2021_X_MASTER_DATASET_20230512.csv
2022_MASTER_DATASET_20231024.csv
ALL_AIM2_MASTER_DATASET_20210917.xlsx
;

%macro assert_required_files;
  %local n_bad;
  %let n_bad = 0;
  proc sql noprint;
    create table work._req_chk as
    select r.req_filename, count(f.file_id) as n_found
    from work.required_files r
    left join work.files_meta f
      on upcase(f.filename) = upcase(r.req_filename)
     and upcase(substr(f.full_path, 1, length(f.full_path) - length(f.filename) - 1))
         = upcase("&raw_path.\master")
    group by r.req_filename;
    select count(*) into :n_bad trimmed
    from work._req_chk
    where n_found ne 1;
  quit;
  %if &n_bad > 0 %then %do;
    data _null_;
      set work._req_chk(where=(n_found ne 1));
      put 'ERROR: D-02b required extract ' req_filename= n_found= '(expected 1 in raw\master)';
    run;
    %fail_out(msg=D-02b ABORT -- &n_bad required master extracts missing or duplicated in raw\master);
  %end;
  %put NOTE: D-02b assertion passed -- all 8 required master extracts found once in raw\master;
%mend assert_required_files;
%assert_required_files;


/* ============================================================
   SECTION 5 -- SHA-256 checksums (D-01)
   certutil through INFILE PIPE FILEVAR= (one pipe per file, no macro
   quoting of paths). Spaces are stripped before the 64-hex test.
   ============================================================ */
data work.sha_results;
  set work.files_meta(keep=file_id full_path);
  length _cmd $1000 line $400 compressed $400 sha256 $64;
  _cmd   = 'certutil -hashfile "' || strip(full_path) || '" SHA256';
  sha256 = 'FAILED';
  infile ckpipe pipe filevar=_cmd end=_done truncover lrecl=400;
  do while (not _done);
    input line $400.;
    compressed = compress(line, ' ');
    if lengthn(compressed) = 64 and notxdigit(strip(compressed)) = 0 then
      sha256 = lowcase(compressed);
  end;
  if sha256 = 'FAILED' then put 'WARNING: SHA-256 FAILED for ' full_path=;
  keep file_id sha256;
run;


/* ============================================================
   SECTION 6 -- Import loop with error trapping (D-06)
   csv      -> PROC IMPORT from a fileref
   xlsx     -> XLSX libref; every sheet copied to &dsname._s<n>
   xls      -> read-failed (XLSX engine cannot read the old format)
   sas7bdat -> libref on the folder; table copied to WORK
   other    -> listed-not-profiled
   ============================================================ */
data work.file_stats;
  length file_id 8 dsname $32 status $30 fail_reason $200
         import_warning $500 nobs 8 ncols 8;
  stop;
run;

data work.sheets_out;
  length file_id 8 sheet_seq 8 sheet_name $200 sheet_ds $32 sheet_status $30
         nobs 8 ncols 8;
  stop;
run;

/* Evaluate the step that just ran. Reads &syserr directly, so it must be
   called immediately after the import step (B-02: le 4 = success). */
%macro eval_import(target=);
  %if &syserr le 4 and %sysfunc(exist(&target)) %then %do;
    %let fstatus = profiled;
    %if &syserr > 0 %then %let fwarn = %superq(syswarningtext);
  %end;
  %else %do;
    %let fstatus = read-failed;
    %let freason = import error syserr=&syserr;
  %end;
  %let syscc = 0;   /* R2-S-02: warning-only or trapped failure must not set exit code */
%mend eval_import;

%macro import_loop;
  %local n_files i j ftype dsname fstatus freason fwarn fr_nobs fr_ncols
         nsheets n_fail;
  %let n_files = 0;
  proc sql noprint;
    select count(*) into :n_files trimmed from work.files_meta;
  quit;

  %do i = 1 %to &n_files;
    %let ftype = ;
    proc sql noprint;
      select ftype into :ftype trimmed
      from work.files_meta where file_id = &i;
    quit;

    %let dsname   = inv_%sysfunc(putn(&i, z5.));
    %let fstatus  = ;
    %let freason  = ;
    %let fwarn    = ;
    %let fr_nobs  = .;
    %let fr_ncols = .;

    /* ---------------- not a data file ---------------- */
    %if &ftype = other %then %do;
      %let fstatus = listed-not-profiled;
    %end;

    /* ---------------- CSV ---------------- */
    %else %if &ftype = csv %then %do;
      proc datasets lib=work nolist nowarn; delete &dsname; quit;
      data _null_;
        set work.files_meta(where=(file_id = &i));
        _rc = filename('_impf', full_path);
      run;
      proc import datafile=_impf out=work.&dsname dbms=csv replace;
        guessingrows=max;
      run;
      %eval_import(target=work.&dsname);
      filename _impf clear;
    %end;

    /* ---------------- XLS (old format) ---------------- */
    %else %if &ftype = xls %then %do;
      %let fstatus = read-failed;
      %let freason = xls format not readable by the XLSX engine -- convert to xlsx;
    %end;

    /* ---------------- XLSX ---------------- */
    %else %if &ftype = xlsx %then %do;
      data _null_;
        set work.files_meta(where=(file_id = &i));
        _rc = libname('_xlw', full_path, 'xlsx');
      run;
      %if %sysfunc(libref(_xlw)) ne 0 %then %do;
        /* Locked, corrupt, or Excel ~$ temp file */
        %let fstatus = read-failed;
        %let freason = xlsx libname could not be assigned;
        %let syscc = 0;
      %end;
      %else %do;
        %let nsheets = 0;
        proc sql noprint;
          /* dictionary.members gives the SAS memname as registered; use it
             for both the SHEETS row label and the dataset copy reference */
          create table work._sheetlist0 as
          select memname as sheet_name length=200
          from dictionary.members
          where libname = '_XLW' and memtype = 'DATA';
          select count(*) into :nsheets trimmed from work._sheetlist0;
        quit;

        %if &nsheets = 0 %then %do;
          %let fstatus = read-failed;
          %let freason = xlsx opened but no sheets found;
        %end;
        %else %do;
          /* One row per sheet; datasets named by position (&dsname._s<n>)
             so sheet names with spaces or over 32 chars cannot break them */
          data work._sheetlist;
            set work._sheetlist0;
            length sheet_ds $32;
            sheet_seq = _n_;
            sheet_ds  = cats("&dsname._s", _n_);
            call symputx(cats('_sh', _n_), sheet_name, 'G');
          run;

          %let n_fail = 0;
          %do j = 1 %to &nsheets;
            proc datasets lib=work nolist nowarn; delete &dsname._s&j; quit;
            /* R3-B-01: dictionary.members returns uppercase memnames; name literals
               ("SHEET1"n) pass the uppercase string case-sensitively to the XLSX
               engine, which fails when the actual tab is "Sheet1".  Unquoted SAS
               names go through SAS case-insensitive resolution and find the tab
               correctly.  Use unquoted form when the name is a valid SAS identifier
               (starts with letter or underscore); digit-prefix names still need the
               literal form but are non-master XLSX files not required by D-06. */
            %if %sysfunc(prxmatch(%str(/^[A-Za-z_]\w*$/), %superq(_sh&j))) %then %do;
              data work.&dsname._s&j;
                set _xlw.&&_sh&j;
              run;
            %end;
            %else %do;
              data work.&dsname._s&j;
                set _xlw."%superq(_sh&j)"n;
              run;
            %end;
            %if &syserr > 4 %then %do;
              /* Remove any partial copy so existence = success below */
              proc datasets lib=work nolist nowarn; delete &dsname._s&j; quit;
            %end;
            %else %if &syserr > 0 and %length(&fwarn) = 0 %then
              %let fwarn = %superq(syswarningtext);
            %if %sysfunc(exist(work.&dsname._s&j)) = 0 %then
              %let n_fail = %eval(&n_fail + 1);
          %end;
          %let syscc = 0;

          /* Every sheet gets a SHEETS row with its own status; readable
             sheets are profiled even when another sheet failed */
          proc sql noprint;
            create table work._sh_ as
            select &i as file_id, s.sheet_seq, s.sheet_name, s.sheet_ds,
                   case when t.memname is not missing then 'profiled'
                        else 'read-failed' end as sheet_status length=30,
                   t.nobs, t.nvar as ncols
            from work._sheetlist s
            left join dictionary.tables t
              on t.libname = 'WORK' and t.memname = upcase(s.sheet_ds)
            order by s.sheet_seq;
          quit;
          proc append base=work.sheets_out data=work._sh_ force; run;

          %if &n_fail > 0 %then %do;
            %let fstatus = read-failed;
            %let freason = sheet copy failed for &n_fail of &nsheets sheets -- readable sheets still profiled;
          %end;
          %else %let fstatus = profiled;
          proc datasets lib=work nolist nowarn;
            delete _sheetlist0 _sheetlist _sh_;
          quit;
        %end;
        libname _xlw clear;
      %end;
      %let dsname = ;   /* workbook rows live in SHEETS, not FILES */
    %end;

    /* ---------------- SAS7BDAT ---------------- */
    %else %if &ftype = sas7bdat %then %do;
      data _null_;
        set work.files_meta(where=(file_id = &i));
        length _dir $500 _mem $200;
        _dir = substr(full_path, 1, length(full_path) - length(filename) - 1);
        _mem = scan(filename, 1, '.');
        _rc  = libname('_sbw', _dir);
        call symputx('_sbmem', _mem, 'G');
      run;
      %if %sysfunc(libref(_sbw)) ne 0 %then %do;
        %let fstatus = listed-not-profiled;
        %let freason = sas7bdat folder libname could not be assigned;
        %let syscc = 0;
      %end;
      %else %do;
        proc datasets lib=work nolist nowarn; delete &dsname; quit;
        data work.&dsname;
          set _sbw."%superq(_sbmem)"n;
        run;
        %eval_import(target=work.&dsname);
        libname _sbw clear;
      %end;
    %end;

    /* nobs / ncols for single-table files (workbooks are in SHEETS) */
    %if %bquote(&fstatus) = profiled and %length(&dsname) > 0 %then %do;
      proc sql noprint;
        select nobs, nvar into :fr_nobs trimmed, :fr_ncols trimmed
        from dictionary.tables
        where libname = 'WORK' and memname = upcase("&dsname");
      quit;
    %end;

    /* Record the file_stats row (text via SYMGET, not macro resolution) */
    data work._fs_row_;
      length file_id 8 dsname $32 status $30 fail_reason $200
             import_warning $500 nobs 8 ncols 8;
      file_id        = &i;
      dsname         = symget('dsname');
      status         = symget('fstatus');
      fail_reason    = symget('freason');
      import_warning = symget('fwarn');
      nobs           = &fr_nobs;
      ncols          = &fr_ncols;
    run;
    proc append base=work.file_stats data=work._fs_row_; run;
    proc datasets lib=work nolist nowarn; delete _fs_row_; quit;
  %end;
%mend import_loop;
%import_loop;

/* FILES dataset */
proc sql noprint;
  create table work.files_out as
  select m.full_path, m.filename, m.ext, m.fsize, m.fdate, s.sha256,
         t.status, t.nobs, t.ncols, t.fail_reason, t.import_warning,
         m.file_id
  from work.files_meta m
  left join work.sha_results s on m.file_id = s.file_id
  left join work.file_stats  t on m.file_id = t.file_id
  order by m.full_path;
quit;


/* ============================================================
   SECTION 7 -- Variable profiling (INV-03, D-03)
   One work list of every profiled table (CSV, SAS7BDAT, each XLSX sheet).
   VARIABLES is built from dictionary.columns, counts left-joined (W-03).
   nobs comes from dictionary.tables, so zero-row tables still get rows.
   ============================================================ */
proc sql noprint;
  create table work.profile_list as
  select file_id, dsname as ds length=32, '' as sheet_name length=200
  from work.file_stats
  where status = 'profiled' and dsname ne ''
  union all
  select file_id, sheet_ds as ds length=32, sheet_name length=200
  from work.sheets_out
  where sheet_status = 'profiled'
  order by file_id, ds;
quit;

data work._var_acc;
  length file_id 8 ds $32 var_name $32 var_type $4 var_length 8
         var_label $256 var_pos 8 nobs 8 n_missing 8 pct_missing 8
         n_sentinel 8 pct_sentinel 8;
  stop;
run;

%macro profile_tables;
  %local n_tab t ds fid n_num n_char ds_nobs;
  %let n_tab = 0;
  proc sql noprint;
    select count(*) into :n_tab trimmed from work.profile_list;
  quit;
  data _null_;
    set work.profile_list;
    call symputx(cats('_pds', _n_), ds, 'G');
    call symputx(cats('_pfi', _n_), file_id, 'G');
  run;

  %do t = 1 %to &n_tab;
    %let ds  = &&_pds&t;
    %let fid = &&_pfi&t;

    %let n_num   = 0;
    %let n_char  = 0;
    %let ds_nobs = 0;
    proc sql noprint;
      select count(*) into :n_num trimmed from dictionary.columns
      where libname = 'WORK' and memname = upcase("&ds") and type = 'num';
      select count(*) into :n_char trimmed from dictionary.columns
      where libname = 'WORK' and memname = upcase("&ds") and type = 'char';
      select nobs into :ds_nobs trimmed from dictionary.tables
      where libname = 'WORK' and memname = upcase("&ds");
    quit;

    /* One pass: true missing and sentinel counts for every column.
       Temporary arrays sized explicitly (B-03). No STOP (B-04). */
    data work._miss_ (keep=_v_name _n_miss _n_sent);
      set work.&ds end=_eof;
      length _v_name $32;
      /* Arrays declared only for types the table has, so a char-only or
         num-only table compiles cleanly (no zero-element array warning).
         A zero-row table produces no rows here; VARIABLES still gets one
         row per column from dictionary.columns with nobs = 0. */
      %if &n_num > 0 %then %do;
        array _num {*} _numeric_;
        array _mn {&n_num} _temporary_;
        array _sn {&n_num} _temporary_;
      %end;
      %if &n_char > 0 %then %do;
        array _char {*} _character_;
        array _mc {&n_char} _temporary_;
        array _sc {&n_char} _temporary_;
      %end;
      if _n_ = 1 then do;
        %if &n_num > 0 %then %do;
          do _i = 1 to &n_num; _mn{_i} = 0; _sn{_i} = 0; end;
        %end;
        %if &n_char > 0 %then %do;
          do _i = 1 to &n_char; _mc{_i} = 0; _sc{_i} = 0; end;
        %end;
      end;
      %if &n_num > 0 %then %do;
        do _i = 1 to &n_num;
          if missing(_num{_i})    then _mn{_i} + 1;
          else if _num{_i} = -999 then _sn{_i} + 1;
        end;
      %end;
      %if &n_char > 0 %then %do;
        do _i = 1 to &n_char;
          if missing(_char{_i})                     then _mc{_i} + 1;
          else if upcase(strip(_char{_i})) = 'NULL' then _sc{_i} + 1;
        end;
      %end;
      if _eof then do;
        %if &n_num > 0 %then %do;
          do _i = 1 to &n_num;
            _v_name = vname(_num{_i}); _n_miss = _mn{_i}; _n_sent = _sn{_i};
            output;
          end;
        %end;
        %if &n_char > 0 %then %do;
          do _i = 1 to &n_char;
            _v_name = vname(_char{_i}); _n_miss = _mc{_i}; _n_sent = _sc{_i};
            output;
          end;
        %end;
        /* B04-NOSTOP-VERIFIED */
      end;
    run;

    proc sql noprint;
      create table work._vj_ as
      select &fid as file_id, "&ds" as ds length=32,
             m.name as var_name length=32, m.type as var_type length=4,
             m.length as var_length, m.label as var_label length=256,
             m.varnum as var_pos, &ds_nobs as nobs,
             coalesce(c._n_miss, 0) as n_missing,
             case when &ds_nobs > 0
                  then coalesce(c._n_miss, 0) / &ds_nobs * 100
                  else . end as pct_missing,
             coalesce(c._n_sent, 0) as n_sentinel,
             case when &ds_nobs > 0
                  then coalesce(c._n_sent, 0) / &ds_nobs * 100
                  else . end as pct_sentinel
      from dictionary.columns m
      left join work._miss_ c on upcase(m.name) = upcase(c._v_name)
      where m.libname = 'WORK' and m.memname = upcase("&ds");
    quit;

    proc append base=work._var_acc data=work._vj_ force; run;
    /* Drop the imported copy once profiled to keep WORK small */
    proc datasets lib=work nolist nowarn;
      delete _miss_ _vj_ &ds;
    quit;
  %end;
%mend profile_tables;
%profile_tables;

proc sql noprint;
  create table work.variables as
  select f.full_path as source_file length=500, p.sheet_name,
         a.var_name, a.var_type, a.var_length, a.var_label, a.var_pos,
         a.nobs, a.n_missing, a.pct_missing, a.n_sentinel, a.pct_sentinel
  from work._var_acc a
  inner join work.profile_list p on a.ds = p.ds
  inner join work.files_meta   f on a.file_id = f.file_id
  order by source_file, p.sheet_name, a.var_pos;
quit;


/* ============================================================
   SECTION 8 -- Key-column detection (INV-04, PCM-T-12, W-01, W-02)
   Normalised with compress(upcase(...),' _-'); PROC SQL uses substr
   prefix tests (the DATA-step starts-with operator is not valid here).
   ============================================================ */
proc sql noprint;
  create table work.key_columns as
  select source_file, sheet_name, var_name, var_label, var_type,
    case
      when compress(upcase(var_name),' _-') in
           ('PRECEDESTUDYID','STUDYID')                         then 'PRECEDE_STUDY_ID'
      when compress(upcase(var_name),' _-') = 'ENCRYPTEDMRN'
           or (substr(upcase(compress(var_name,' _-')),1,9) = 'ENCRYPTED'
               and index(upcase(var_name),'MRN') > 0)           then 'ENCRYPTED_MRN'
      when compress(upcase(var_name),' _-') = 'MRN'            then 'UNENC_MRN'
      when substr(upcase(compress(var_name,' _-')),1,9) = 'ENCRYPTED'
           and index(upcase(var_name),'ENCOUNTER') > 0          then 'ENCRYPTED_ENCOUNTER'
      when compress(upcase(var_name),' _-') in
           ('ENCOUNTERID','ENCOUNTER')                          then 'UNENC_ENCOUNTER'
      /* Label-based matches (VARnn names from the XLSX engine) */
      when compress(upcase(var_label),' _-') in
           ('PRECEDESTUDYID','STUDYID')                         then 'PRECEDE_STUDY_ID'
      when compress(upcase(var_label),' _-') = 'ENCRYPTEDMRN'  then 'ENCRYPTED_MRN'
      when compress(upcase(var_label),' _-') = 'MRN'           then 'UNENC_MRN'
      when compress(upcase(var_label),' _-') = 'ENCRYPTEDENCOUNTER' then 'ENCRYPTED_ENCOUNTER'
      when compress(upcase(var_label),' _-') in
           ('ENCOUNTERID','ENCOUNTER')                          then 'UNENC_ENCOUNTER'
    end as key_column_type length=30,
    case
      when compress(upcase(var_name),' _-') in
           ('ENCRYPTEDMRN','MRN','ENCOUNTERID','ENCOUNTER')
           or substr(upcase(compress(var_name,' _-')),1,9) = 'ENCRYPTED' then 'name'
      when compress(upcase(var_name),' _-') = 'PRECEDESTUDYID'          then 'name'
      when compress(upcase(var_name),' _-') = 'STUDYID'                 then 'loose'
      when compress(upcase(var_label),' _-') = 'STUDYID'                then 'loose'
      else 'label'
    end as match_basis length=20
  from work.variables
  where calculated key_column_type is not missing
  order by source_file, sheet_name, var_name;
quit;


/* ============================================================
   SECTION 9 -- FAMILIES (D-04, longest match)
   ============================================================ */

/* COM scouting -- written to the log for the Plan 02 checkpoint */
proc sql noprint;
  create table work.com_scout as
  select distinct var_name, source_file
  from work.variables
  where substr(upcase(var_name),1,3) = 'COM'
    and compress(upcase(var_name),' _-') ne 'COMPLICATIONSUM'
    and substr(upcase(var_name),1,6) ne 'COMP10'
  order by var_name, source_file;
quit;
data _null_;
  set work.com_scout;
  put 'COM_SCOUT: ' var_name= source_file=;
run;

/* Prefix lookup -- extend after COM scouting review */
data work.prefix_lookup;
  length prefix $50 family_name $50;
  infile datalines dsd truncover;
  input prefix $ family_name $;
  prefix     = upcase(strip(prefix));
  prefix_len = length(prefix);
  datalines;
COMPLICATION_SUM,complications
COMP10_,complications
LINUS,LINUS
COM,dCDT
;

proc sort data=work.prefix_lookup out=work.prefix_sorted;
  by descending prefix_len;
run;

%macro assign_families;
  %local n_pref pi;
  %let n_pref = 0;
  proc sql noprint;
    select count(*) into :n_pref trimmed from work.prefix_sorted;
  quit;
  /* Load prefixes BEFORE the DATA step (no PROC inside a DATA step) */
  data _null_;
    set work.prefix_sorted;
    call symputx(cats('_pfx', _n_), prefix, 'G');
    call symputx(cats('_pfm', _n_), family_name, 'G');
  run;

  data work.var_family;
    set work.variables;
    length family_name $50;
    family_name = 'unassigned';
    %do pi = 1 %to &n_pref;
      if family_name = 'unassigned'
         and find(upcase(var_name), "&&_pfx&pi") = 1 then
        family_name = "&&_pfm&pi";
    %end;
  run;
%mend assign_families;
%assign_families;

proc summary data=work.var_family nway missing;
  class source_file family_name;
  var pct_missing;
  output out=work._fam_stats(drop=_type_)
         min=pct_missing_min median=pct_missing_median max=pct_missing_max;
run;

data work.families;
  retain family_name source_file n_cols
         pct_missing_min pct_missing_median pct_missing_max;
  set work._fam_stats(rename=(_freq_=n_cols));
run;

%macro assert_families;
  %local n_bad;
  %let n_bad = 0;
  proc sql noprint;
    select count(*) into :n_bad trimmed
    from (
      select coalesce(f.source_file, v.source_file) as src
      from (select source_file, sum(n_cols) as fam_total from work.families
            group by source_file) f
      full join
           (select source_file, count(*) as var_total from work.variables
            group by source_file) v
        on f.source_file = v.source_file
      where coalesce(f.fam_total, 0) ne coalesce(v.var_total, 0)
    );
  quit;
  %if &n_bad > 0 %then %do;
    %fail_out(msg=FAMILIES column totals do not match VARIABLES for &n_bad source files);
  %end;
  %put NOTE: assert_families passed;
%mend assert_families;
%assert_families;


/* ============================================================
   SECTION 10 -- RECONCILIATION (D-07)
   ============================================================ */
data work.known_files;
  length known_filename $200;
  infile datalines truncover;
  input known_filename $200.;
  datalines;
2018_2019_CPT_ROLLUP_X_MASTER_DATASET_20200801.csv
2018_2019_X_MASTER_DATASET_20200801.csv
2018_2022_X_MASTER_DATASET_20240402.csv
2020_CPT_ROLLUP_X_MASTER_DATASET_20210609.csv
2020_X_MASTER_DATASET_20210519.csv
2021_X_MASTER_DATASET_20230512.csv
2022_MASTER_DATASET_20231024.csv
ALL_AIM2_MASTER_DATASET_20210917.xlsx
2018_2019_2020_Induction_Emergent20231121.csv
2018_2019_Precede_Database.xlsx
2018_2022_COLONOSCOPY_20240118.xlsx
2020_Precede_Database_Edu.xlsx
2021_Education_20240124.csv
2021_Frailty_20240123.csv
2022_Education_20240124.csv
2022_RES_20230927.csv
All_YEARS_LAT_LONG_20231127.csv
;

proc sql noprint;
  create table work.reconciliation as
  select f.full_path, f.filename, f.ext, f.status, f.sha256,
    case when k.known_filename is not missing then 'known'
         else 'NEW'
    end as status_known length=10
  from work.files_out f
  left join work.known_files k
    on upcase(f.filename) = upcase(k.known_filename)
  order by f.full_path;
quit;


/* ============================================================
   SECTION 11 -- INV-06 three-term assertion (D-06)
   ============================================================ */
%macro assert_inv06;
  %local n_bad n_total n_prof n_listed n_failed;
  %let n_bad = 0;
  proc sql noprint;
    select count(*) into :n_bad trimmed
    from work.files_out
    where status not in ('profiled', 'listed-not-profiled', 'read-failed')
       or status is missing;
  quit;
  %if &n_bad > 0 %then %do;
    %fail_out(msg=INV-06 violated -- &n_bad files have unrecognized status);
  %end;
  proc sql noprint;
    select count(*) into :n_total  trimmed from work.files_out;
    select count(*) into :n_prof   trimmed from work.files_out where status='profiled';
    select count(*) into :n_listed trimmed from work.files_out where status='listed-not-profiled';
    select count(*) into :n_failed trimmed from work.files_out where status='read-failed';
  quit;
  %if %eval(&n_prof + &n_listed + &n_failed) ne &n_total %then %do;
    %fail_out(msg=INV-06 violated -- status counts do not sum to &n_total files);
  %end;
  %put NOTE: INV-06 assertion -- total=&n_total profiled=&n_prof listed=&n_listed failed=&n_failed;
  %put NOTE: assert_inv06 passed;
%mend assert_inv06;
%assert_inv06;


/* ============================================================
   SECTION 11b -- D-06: every md1-md8 extract under raw\master profiled
   ============================================================ */
%macro assert_masters_profiled;
  %local n_bad;
  %let n_bad = 0;
  proc sql noprint;
    select count(*) into :n_bad trimmed
    from work.required_files r
    left join work.files_out f
      on upcase(f.filename) = upcase(r.req_filename)
     and upcase(substr(f.full_path, 1, length(f.full_path) - length(f.filename) - 1))
         = upcase("&raw_path.\master")
    where coalesce(f.status, '') ne 'profiled';
  quit;
  %if &n_bad > 0 %then %do;
    %fail_out(msg=D-06 ABORT -- &n_bad required master extracts did not reach profiled status);
  %end;
  %put NOTE: assert_masters_profiled passed -- all 8 md1-md8 masters have status=profiled;
%mend assert_masters_profiled;
%assert_masters_profiled;


/* ============================================================
   SECTION 12 -- PROC EXPORT -> qc/19_raw_files.csv
   Written BEFORE ODS Excel opens so an ODS failure cannot block Phase 20.
   ============================================================ */
proc export data=work.files_out
  outfile="&qc_path.\19_raw_files.csv"
  dbms=csv replace;
run;
%put NOTE: qc/19_raw_files.csv written -- Phase 20 handoff file ready;


/* ============================================================
   SECTION 13 -- ODS Excel (D-05): KEY leftmost, UF blue headers
   ============================================================ */
proc sql noprint;
  create table work.sheets_rpt as
  select f.full_path, f.filename, s.sheet_seq, s.sheet_name, s.sheet_status,
         s.nobs, s.ncols
  from work.sheets_out s
  inner join work.files_meta f on s.file_id = f.file_id
  order by f.full_path, s.sheet_seq;
quit;

data work.key_legend;
  length sheet_name $20 column_name $50 description $200 notes $250;
  infile datalines4 dsd dlm='|' truncover;
  input sheet_name $ column_name $ description $ notes $;
  datalines4;
FILES|full_path|Full path of the file on disk|Read-only source
FILES|filename|File name with extension|
FILES|ext|File extension (lowercased)|
FILES|fsize|File size in bytes|
FILES|fdate|Last modified date from the OS|
FILES|sha256|SHA-256 checksum from certutil|FAILED if certutil could not hash the file
FILES|status|profiled / listed-not-profiled / read-failed|Workbooks: read-failed if any sheet failed -- see SHEETS
FILES|nobs|Row count for CSV and SAS7BDAT files|Missing for workbooks -- see SHEETS for per-sheet counts
FILES|ncols|Column count for CSV and SAS7BDAT files|Missing for workbooks -- see SHEETS
FILES|fail_reason|Reason text if status=read-failed|
FILES|import_warning|Warning text when the import finished with a warning|Transcoding warnings appear here
FILES|file_id|Internal sequence number|
SHEETS|full_path|Full path of the parent workbook|
SHEETS|filename|File name of the parent workbook|
SHEETS|sheet_seq|Sheet position as reported by the XLSX engine|
SHEETS|sheet_name|Sheet name|
SHEETS|sheet_status|profiled or read-failed for this sheet|A workbook is read-failed if any sheet failed; its readable sheets are still profiled
SHEETS|nobs|Row count for this sheet|
SHEETS|ncols|Column count for this sheet|
VARIABLES|source_file|Full path of the source file|
VARIABLES|sheet_name|Sheet name for workbooks (blank for CSV/SAS7BDAT)|Distinguishes sheets within one workbook
VARIABLES|var_name|SAS variable name|May be VARnn for workbook headers the engine renamed
VARIABLES|var_type|SAS type: char or num|Type as imported by SAS -- not the source system type; ENCRYPTED_MRN can import as num in one file and char in another
VARIABLES|var_length|SAS variable length in bytes|
VARIABLES|var_label|SAS variable label|Holds the original header where the name was changed
VARIABLES|var_pos|Variable position in the table (1-based)|
VARIABLES|nobs|Row count of the table|
VARIABLES|n_missing|Count of true SAS-missing values|. for num; blank for char
VARIABLES|pct_missing|n_missing / nobs * 100|Missing when nobs = 0
VARIABLES|n_sentinel|Count of sentinel values|-999 for num; the string NULL for char
VARIABLES|pct_sentinel|n_sentinel / nobs * 100|Reported separately from pct_missing; sentinels are not recoded
KEY_COLUMNS|source_file|Full path of the source file|
KEY_COLUMNS|sheet_name|Sheet name (blank for CSV/SAS7BDAT)|
KEY_COLUMNS|var_name|SAS variable name|
KEY_COLUMNS|var_label|SAS variable label|
KEY_COLUMNS|var_type|SAS type|
KEY_COLUMNS|key_column_type|PRECEDE_STUDY_ID / ENCRYPTED_MRN / UNENC_MRN / ENCRYPTED_ENCOUNTER / UNENC_ENCOUNTER|UNENC_* columns may hold plain identifiers -- do not link them to encrypted keys
KEY_COLUMNS|match_basis|name / loose / label|loose = bare STUDYID (could belong to another study)
RECONCILIATION|full_path|Full path of the file|
RECONCILIATION|filename|File name|
RECONCILIATION|ext|Extension|
RECONCILIATION|status|Import status|
RECONCILIATION|sha256|SHA-256 checksum|
RECONCILIATION|status_known|known (md1-md8 or r1-r9) or NEW|
FAMILIES|family_name|complications / dCDT / LINUS / unassigned|dCDT assignment depends on the COM scouting review
FAMILIES|source_file|Full path of the source file|
FAMILIES|n_cols|Number of columns in this family for this file|Sums to the VARIABLES row count per file (asserted)
FAMILIES|pct_missing_min|Minimum pct_missing in the family|
FAMILIES|pct_missing_median|Median pct_missing in the family|
FAMILIES|pct_missing_max|Maximum pct_missing in the family|
;;;;


/* UF blue header style (swap in the program 17 template block if it differs) */
ods path(prepend) work.templat(update);
proc template;
  define style styles.uf_inventory;
    parent = styles.pearl;
    class header /
      backgroundcolor = cx0021A5
      color           = white
      fontweight      = bold;
  end;
run;

ods listing close;
ods excel file="&qc_path.\19_raw_inventory.xlsx"
    style=styles.uf_inventory
    options(sheet_interval='proc' frozen_headers='on' autofilter='all');

ods excel options(sheet_name='KEY');
proc print data=work.key_legend noobs; run;

ods excel options(sheet_name='FILES');
proc print data=work.files_out noobs; run;

ods excel options(sheet_name='SHEETS');
proc print data=work.sheets_rpt noobs; run;

ods excel options(sheet_name='VARIABLES');
proc print data=work.variables noobs; run;

ods excel options(sheet_name='KEY_COLUMNS');
proc print data=work.key_columns noobs; run;

ods excel options(sheet_name='RECONCILIATION');
proc print data=work.reconciliation noobs; run;

ods excel options(sheet_name='FAMILIES');
proc print data=work.families noobs; run;

ods excel close;
ods listing;


/* ============================================================
   SECTION 14 -- Output verification and log restore
   No literal quotes inside %sysfunc(fileexist()) (B-06).
   ============================================================ */
%macro verify_output;
  %if %sysfunc(fileexist(&qc_path.\19_raw_inventory.xlsx)) = 0 %then %do;
    %fail_out(msg=OUTPUT MISSING -- qc/19_raw_inventory.xlsx was not created);
  %end;
  %if %sysfunc(fileexist(&qc_path.\19_raw_files.csv)) = 0 %then %do;
    %fail_out(msg=OUTPUT MISSING -- qc/19_raw_files.csv was not created);
  %end;
  %put NOTE: Phase 19 outputs verified;
%mend verify_output;
%verify_output;

%put NOTE: ==== Phase 19 raw directory inventory complete ====;
%restore_log;
