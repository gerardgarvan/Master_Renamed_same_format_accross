/*==========================================================================
  Program : 19_raw_dir_inventory.sas
  Purpose : Recursive inventory of &raw_path; seven-sheet workbook +
            machine-readable CSV handoff for Phase 20.

  Reads   : Everything under &raw_path (read-only).
             No g.* datasets are read or written.

  Writes  : qc/19_raw_inventory.xlsx  -- seven-sheet human-facing workbook
            qc/19_raw_files.csv       -- machine-readable Phase 20 handoff
            logs/19_raw_dir_inventory.log

  Does NOT write to any g.* dataset.

  XCMD required: certutil is called via FILENAME PIPE; the batch session
    must have XCMD enabled (shared constraint with RUN-01 in Phase 21).

  PCM compliance:
    - No bare open-code %IF/%THEN; all conditional logic inside named macros
    - No apostrophes or embedded semicolons in %PUT text
    - Every %abort cancel inside %fail_out only
    - No automatic-macro row counts; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - dictionary.columns.type is char/num not 1/2 (PCM-T-13)
    - ASCII only (session encoding is not UTF-8)
    - No in-place dataset rewrite (data X; set X;)
    - No PROC SQL UPDATE
    - g.* datasets are not touched -- standalone scan
    - options nosyntaxcheck noerrorabend set before any PROC IMPORT

  Author  : GSD Phase 19 Plan 01
  Revised : 2026-09-23
==========================================================================*/

/* ============================================================
   SECTION 0 -- Header, %include, options
   ============================================================ */
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
options validvarname=v7 validmemname=extend nofmterr msglevel=i;
options nosyntaxcheck noerrorabend;   /* MUST precede any PROC IMPORT */
%include "&sas_path.\macros_raw_import.sas";


/* ============================================================
   SECTION 1 -- Utility macros
   (copied from 16_raw_inventory.sas; log filename updated)
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
   NOTE: Phase 19 does NOT read g.* datasets.
         No libname g or %assert_base call here.
   ============================================================ */
%check_dir(path=&logs_path, label=logs);
%route_log;
%check_dir(path=&qc_path, label=qc);
%check_dir(path=&raw_path, label=raw);
%put NOTE: ==== Phase 19 raw directory inventory starting ====;


/* ============================================================
   SECTION 3 -- Directory traversal
   /a-d flag excludes subdirectory name lines so folder paths
   do not appear as FILES rows (B-BLOCKER-2 fix).
   ============================================================ */
filename dirpipe pipe "dir /s /b /a-d ""&raw_path""";
data work.files_raw;
  infile dirpipe truncover lrecl=500;
  length full_path $500 filename $200 ext $20;
  input full_path $500.;
  full_path = strip(full_path);
  if lengthn(strip(full_path)) = 0 then delete;
  filename  = scan(full_path, -1, '\');
  ext       = lowcase(scan(filename, -1, '.'));
  file_id   + 1;
run;
filename dirpipe clear;

/* Get file metadata: fsize and fdate via fileref + FINFO
   B-05 fix: FOPEN requires a fileref, not a path string directly */
data work.files_raw;
  set work.files_raw;
  length fsize 8 fdate $30;
  retain _rc 0;
  _rc = filename('_fr_', full_path);
  fid = fopen('_fr_');
  if fid > 0 then do;
    fsize = input(finfo(fid, 'File Size (bytes)'), best32.);
    fdate = finfo(fid, 'Last Modified');
    _rc   = fclose(fid);
    _rc   = filename('_fr_');   /* clear fileref */
  end;
  else do;
    fsize = .;
    fdate = 'UNKNOWN';
    _rc   = filename('_fr_');   /* clear even on failure */
  end;
  drop _rc fid;
run;


/* ============================================================
   SECTION 4 -- D-02b presence assertion (md1-md8 must all be present)
   Exact filenames from Phase 1 source list (raw\master).
   NOTE (B-01): Only the CSV form of md3 is required.
                Do NOT add the .xlsx variant.
   ============================================================ */
data work.required_files;
  length req_filename $200;
  infile datalines dsd;
  input req_filename $;
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
  %local n_req i req_name n_found;
  %let n_req = 0;
  proc sql noprint;
    select count(*) into :n_req trimmed from work.required_files;
  quit;
  %do i = 1 %to &n_req;
    %let req_name = ;
    proc sql noprint;
      select req_filename into :req_name trimmed
      from work.required_files(firstobs=&i obs=&i);
    quit;
    %let n_found = 0;
    proc sql noprint;
      /* R2-W-02: restrict to raw\master\ and upcase both sides for
         Windows folder-name capitalisation variants */
      select count(*) into :n_found trimmed
      from work.files_raw
      where upcase(filename) = upcase("&req_name")
        and index(upcase(full_path), '\MASTER\') > 0;
    quit;
    %if &n_found = 0 %then %do;
      %fail_out(msg=D-02b ABORT -- required master extract not found in raw\master\: &req_name);
    %end;
    %if &n_found > 1 %then %do;
      %fail_out(msg=D-02b ABORT -- required file has &n_found copies in raw\master\ (expected 1): &req_name);
    %end;
  %end;
  %put NOTE: D-02b assertion passed -- all 8 required master extracts found;
%mend assert_required_files;
%assert_required_files;


/* ============================================================
   SECTION 5 -- SHA-256 checksums (D-01)
   certutil via FILENAME PIPE; strip spaces before 64-hex test.
   ============================================================ */
%macro get_sha256(fpath=, outdsn=, rowid=);
  %local hash_found;
  %let hash_found = FAILED;
  filename ck pipe "certutil -hashfile ""&fpath"" SHA256";
  data _null_;
    infile ck truncover lrecl=200;
    input line $200.;
    /* Strip all spaces -- guards Windows builds that print spaces between byte pairs */
    compressed = compress(line, ' ');
    if lengthn(compressed) = 64 and notxdigit(compressed) = 0 then do;
      call symputx('hash_found', compressed, 'L');
    end;
  run;
  filename ck clear;
  /* Write the hash (or FAILED) to the output dataset */
  data work._sha_row_;
    file_id  = &rowid;
    sha256   = "&hash_found";
    if "&hash_found" = "FAILED" then
      put "WARNING: SHA-256 FAILED for file_id=&rowid path=&fpath";
  run;
  proc append base=&outdsn data=work._sha_row_; run;
  proc datasets lib=work nolist; delete _sha_row_; quit;
%mend get_sha256;

/* Initialise the checksum accumulator */
data work.sha_results;
  length file_id 8 sha256 $64;
  stop;
run;

/* Loop over all files and compute checksums */
%macro loop_sha256;
  %local n_files i fpath fid;
  %let n_files = 0;
  proc sql noprint;
    select count(*) into :n_files trimmed from work.files_raw;
  quit;
  %do i = 1 %to &n_files;
    %let fpath = ;
    proc sql noprint;
      select full_path into :fpath trimmed
      from work.files_raw(firstobs=&i obs=&i);
    quit;
    %get_sha256(fpath=&fpath, outdsn=work.sha_results, rowid=&i);
  %end;
%mend loop_sha256;
%loop_sha256;

/* Join checksums back to files_raw */
proc sql noprint;
  create table work.files_ck as
  select f.*, s.sha256
  from work.files_raw f
  left join work.sha_results s on f.file_id = s.file_id;
quit;


/* ============================================================
   SECTION 6 -- Import loop with error trapping (D-06)
   ============================================================ */
/* Initialise accumulator datasets */
data work.file_stats;
  length file_id 8 dsname $32 status $30 fail_reason $200
         import_warning $500 nobs 8 ncols 8 sheet_name $200;
  stop;
run;

data work.sheets_out;
  length full_path $500 filename $200 sheet_name $200 nobs 8 ncols 8;
  stop;
run;

%macro import_loop;
  %local n_files i fpath fname ext dsname xlibname nsheets
         import_ok import_warn fr_nobs fr_ncols fstatus freason fwarn
         n_ds_before n_ds_after sh_count;

  %let n_files = 0;
  proc sql noprint;
    select count(*) into :n_files trimmed from work.files_ck;
  quit;

  %do i = 1 %to &n_files;
    %let fpath  = ;
    %let fname  = ;
    %let ext    = ;
    proc sql noprint;
      select full_path, filename, ext
      into :fpath trimmed, :fname trimmed, :ext trimmed
      from work.files_ck(firstobs=&i obs=&i);
    quit;

    %let dsname = inv_%sysfunc(putn(&i, z5.));

    /* Classify by extension */
    %if %sysfunc(indexw('csv xlsx xls sas7bdat', "&ext", ' ')) > 0 %then %do;
      /* ---- Readable-extension file ---- */

      /* Step A: Pre-delete stale dataset (stale dataset trap) */
      proc datasets lib=work nolist;
        delete &dsname;
      quit;

      %let import_ok   = 0;
      %let import_warn = 0;
      %let fstatus     = read-failed;
      %let freason     = ;
      %let fwarn       = ;

      /* Step B: Attempt import by extension */
      %if &ext = csv %then %do;
        proc import datafile="&fpath" out=work.&dsname
          dbms=csv replace;
          guessingrows=max;
        run;
      %end;
      %else %if &ext = xlsx or &ext = xls %then %do;
        /* XLSX/XLS: libname engine to enumerate sheets */
        %let xlibname = _xl&i;
        libname &xlibname xlsx "&fpath";
        /* Enumerate sheets via dictionary.tables */
        proc sql noprint;
          select count(*) into :nsheets trimmed
          from dictionary.tables
          where libname = upcase("&xlibname");
        quit;
        %let sh_count = 0;
        %let n_ds_before = 0;
        proc sql noprint;
          select count(*) into :n_ds_before trimmed
          from dictionary.tables where libname='WORK';
        quit;
        /* Copy each sheet via CALL EXECUTE.
           R2-B-02: &dsname._ pattern -- period terminates the macro var name
           so that a trailing underscore (or sheet suffix) is treated as a
           literal character and not silently consumed into the var name.
           Without the period, &dsname_ resolves to blank -> every copy fails. */
        data _null_;
          set sashelp.vtable(where=(libname=upcase("&xlibname")));
          /* Use &dsname._ prefix so the sheet suffix follows a literal underscore */
          call execute('%let _sht_dsn_ = ' || "&dsname._" || strip(memname) || ';');
          call execute('data work.&_sht_dsn_; set '
            || strip(libname) || '.' || strip(memname) || '; run;');
          call execute('%let sh_count=%eval(&sh_count + 1);');
        run;
        libname &xlibname clear;
        %let n_ds_after = 0;
        proc sql noprint;
          select count(*) into :n_ds_after trimmed
          from dictionary.tables where libname='WORK';
        quit;
        /* Sheet shortfall check */
        %if %eval(&n_ds_after - &n_ds_before) < &nsheets %then %do;
          %let import_ok = 0;
          %let freason   = XLSX sheet shortfall: expected &nsheets sheets;
        %end;
        %else %do;
          %let import_ok = 1;
          %let fstatus   = profiled;
        %end;
      %end;
      %else %if &ext = sas7bdat %then %do;
        /* SAS7BDAT: assign libname to directory; profile if successful */
        %let xlibname = _sb&i;
        %let fdir = %sysfunc(substr(&fpath, 1, %eval(%length(&fpath) - %length(&fname) - 1)));
        libname &xlibname "&fdir";
        %let fr_ncols = 0;
        proc sql noprint;
          select count(*) into :fr_ncols trimmed
          from dictionary.columns
          where libname = upcase("&xlibname")
            and memname = upcase("%scan(&fname, 1, '.')");
        quit;
        %if &fr_ncols > 0 %then %do;
          %let import_ok = 1;
          %let fstatus   = profiled;
        %end;
        %else %do;
          %let import_ok = 0;
          %let freason   = sas7bdat libname or table not found;
          %let fstatus   = listed-not-profiled;
        %end;
        libname &xlibname clear;
      %end;

      /* Step C: Check &syserr for CSV (B-02: use le 4, not = 0) */
      %if &ext = csv %then %do;
        %if &syserr = 0 %then %do;
          %let import_ok = 1;
          %let fstatus   = profiled;
        %end;
        %else %if &syserr le 4 %then %do;
          /* Warning only (e.g., transcoding warning, syserr=4) */
          %let import_ok   = 1;
          %let import_warn = 1;
          %let fwarn       = &syswarningtext;   /* R2-S-01: correct macro */
          %let fstatus     = profiled;
          %let syscc = 0;   /* R2-S-02: reset so warning-only run exits 0 */
        %end;
        %else %do;
          %let import_ok = 0;
          %let freason   = syserr=&syserr;
          %let fstatus   = read-failed;
          %let syscc = 0;   /* reset so error does not propagate */
        %end;
      %end;

      /* Step D: Collect nobs / ncols for profiled files */
      %let fr_nobs = .;
      %let fr_ncols = .;
      %if &import_ok = 1 and &ext ne xlsx and &ext ne xls and &ext ne sas7bdat %then %do;
        %if %sysfunc(exist(work.&dsname)) %then %do;
          proc sql noprint;
            select nobs, nvar
            into :fr_nobs trimmed, :fr_ncols trimmed
            from dictionary.tables
            where libname='WORK' and memname=upcase("&dsname");
          quit;
        %end;
      %end;

      /* Step E: Record SHEETS rows for XLSX */
      %if (&ext = xlsx or &ext = xls) and &import_ok = 1 %then %do;
        data _null_;
          set sashelp.vtable(where=(libname='WORK'
              and substr(memname,1,%length("&dsname")) = upcase("&dsname")));
          /* build one row per sheet in sheets_out */
          full_path_ = "&fpath";
          filename_  = "&fname";
          sheet_nm   = substr(memname, %length("&dsname") + 1);
          nr = 0; nc = 0;
          call execute(
            'proc sql noprint; select nobs, nvar into :_s_nobs trimmed, :_s_ncol trimmed'
            || ' from dictionary.tables where libname=''WORK'' and memname=''' || strip(memname) || '''; quit;'
            || 'data _sh_row_; length full_path $500 filename $200 sheet_name $200 nobs 8 ncols 8;'
            || ' full_path="' || strip(full_path_) || '"; filename="' || strip(filename_) || '";'
            || ' sheet_name="' || strip(sheet_nm) || '"; nobs=&_s_nobs; ncols=&_s_ncol; run;'
            || 'proc append base=work.sheets_out data=work._sh_row_; run;'
            || 'proc datasets lib=work nolist; delete _sh_row_; quit;'
          );
        run;
      %end;

      /* Step F: Record file_stats row */
      data _fs_row_;
        length file_id 8 dsname $32 status $30 fail_reason $200
               import_warning $500 nobs 8 ncols 8 sheet_name $200;
        file_id        = &i;
        dsname         = "&dsname";
        status         = "&fstatus";
        fail_reason    = "&freason";
        import_warning = "&fwarn";
        nobs           = &fr_nobs;
        ncols          = &fr_ncols;
        sheet_name     = '';
      run;
      proc append base=work.file_stats data=work._fs_row_; run;
      proc datasets lib=work nolist; delete _fs_row_; quit;

    %end;  /* readable extension */
    %else %do;
      /* ---- Not-profiled file ---- */
      data _fs_row_;
        length file_id 8 dsname $32 status $30 fail_reason $200
               import_warning $500 nobs 8 ncols 8 sheet_name $200;
        file_id        = &i;
        dsname         = '';
        status         = 'listed-not-profiled';
        fail_reason    = '';
        import_warning = '';
        nobs           = .;
        ncols          = .;
        sheet_name     = '';
      run;
      proc append base=work.file_stats data=work._fs_row_; run;
      proc datasets lib=work nolist; delete _fs_row_; quit;
    %end;

  %end;  /* do i */
%mend import_loop;
%import_loop;

/* Build work.files_out by joining files_ck with file_stats */
proc sql noprint;
  create table work.files_out as
  select f.full_path, f.filename, f.ext, f.fsize, f.fdate, f.sha256,
         s.status, s.nobs, s.ncols, s.fail_reason, s.import_warning,
         f.file_id
  from work.files_ck f
  left join work.file_stats s on f.file_id = s.file_id
  order by f.full_path;
quit;


/* ============================================================
   SECTION 7 -- Variable profiling (INV-03, D-03)
   One-pass DATA step per profiled dataset.
   Explicit temporary array sizes -- never {*} (B-03).
   No stop; inside the main loop body (B-04).
   ============================================================ */
/* Initialise the VARIABLES accumulator */
data work.variables;
  length source_file $500 sheet_name $200 var_name $32 var_type $4
         var_length 8 var_label $256 var_pos 8 nobs 8
         n_missing 8 pct_missing 8 n_sentinel 8 pct_sentinel 8;
  stop;
run;

%macro profile_variables;
  %local n_prof i fpath dsname n_num n_char;
  %let n_prof = 0;
  proc sql noprint;
    select count(*) into :n_prof trimmed
    from work.file_stats
    where status = 'profiled';
  quit;

  %let i = 0;
  data _null_;
    set work.file_stats(where=(status='profiled'));
    call symputx('_pds_' || strip(put(_n_, best.)), dsname, 'G');
    call symputx('_pfp_' || strip(put(_n_, best.)), file_id,  'G');
    call symputx('_n_prof', _n_, 'G');
  run;

  %do i = 1 %to &_n_prof;
    %let dsname  = &&_pds_&i;
    %let file_id = &&_pfp_&i;
    %let fpath   = ;
    proc sql noprint;
      select full_path into :fpath trimmed
      from work.files_ck where file_id = &file_id;
    quit;

    /* Skip if dataset no longer in WORK (XLSX sheets have different names) */
    %if %sysfunc(exist(work.&dsname)) = 0 %then %goto next_profile;

    /* Get n_num and n_char BEFORE the DATA step (B-03 fix) */
    %let n_num  = 0;
    %let n_char = 0;
    proc sql noprint;
      select count(*) into :n_num trimmed
      from dictionary.columns
      where libname='WORK' and memname=upcase("&dsname")
        and type='num';
      select count(*) into :n_char trimmed
      from dictionary.columns
      where libname='WORK' and memname=upcase("&dsname")
        and type='char';
    quit;

    /* One-pass missingness and sentinel count */
    data work.miss_&dsname (keep=var_name n_miss_num n_sent_num
                                  n_miss_chr n_sent_chr nobs);
      set work.&dsname end=_eof;
      array _num  {*} _numeric_;
      array _char {*} _character_;
      /* B-03: explicit sizes using max(...,1) so zero-column files compile */
      array n_miss_n {%eval(%sysfunc(max(&n_num,1)))}  _temporary_;
      array n_sent_n {%eval(%sysfunc(max(&n_num,1)))}  _temporary_;
      array n_miss_c {%eval(%sysfunc(max(&n_char,1)))} _temporary_;
      array n_sent_c {%eval(%sysfunc(max(&n_char,1)))} _temporary_;
      if _n_ = 1 then do;
        do _i = 1 to dim(_num);  n_miss_n{_i}=0; n_sent_n{_i}=0; end;
        do _i = 1 to dim(_char); n_miss_c{_i}=0; n_sent_c{_i}=0; end;
      end;
      do _i = 1 to dim(_num);
        if missing(_num{_i})    then n_miss_n{_i} + 1;
        else if _num{_i} = -999 then n_sent_n{_i} + 1;
      end;
      do _i = 1 to dim(_char);
        if missing(_char{_i})                         then n_miss_c{_i} + 1;
        else if upcase(strip(_char{_i})) = 'NULL'     then n_sent_c{_i} + 1;
      end;
      if _eof then do;
        nobs = _n_;
        /* Output one row per numeric variable */
        do _i = 1 to dim(_num);
          var_name   = vname(_num{_i});
          n_miss_num = n_miss_n{_i};
          n_sent_num = n_sent_n{_i};
          n_miss_chr = .;
          n_sent_chr = .;
          output;
        end;
        /* Output one row per character variable */
        do _i = 1 to dim(_char);
          var_name   = vname(_char{_i});
          n_miss_num = .;
          n_sent_num = .;
          n_miss_chr = n_miss_c{_i};
          n_sent_chr = n_sent_c{_i};
          output;
        end;
        /* B04-NOSTOP-VERIFIED */
      end;
    run;

    /* Build variable metadata from dictionary.columns (W-03: include sheet_name) */
    proc sql noprint;
      create table work.variables_meta as
      select libname, memname, name as var_name, type as var_type,
             length as var_length, label as var_label, varnum as var_pos,
             "&fpath"  as source_file length=500,
             ''        as sheet_name  length=200
      from dictionary.columns
      where libname='WORK' and memname=upcase("&dsname");
    quit;

    /* Left-join missingness counts onto the metadata base
       R2-S-03: coalesce(nobs,0) protects zero-row datasets */
    proc sql noprint;
      create table work.vars_joined as
      select m.*,
             coalesce(c.n_miss_num, c.n_miss_chr, 0) as n_missing,
             coalesce(c.n_sent_num, c.n_sent_chr, 0) as n_sentinel,
             coalesce(m_nobs.nobs, 0) as nobs,
             case when coalesce(m_nobs.nobs, 0) > 0
                  then coalesce(c.n_miss_num, c.n_miss_chr, 0)
                       / coalesce(m_nobs.nobs, 0) * 100
                  else . end as pct_missing,
             case when coalesce(m_nobs.nobs, 0) > 0
                  then coalesce(c.n_sent_num, c.n_sent_chr, 0)
                       / coalesce(m_nobs.nobs, 0) * 100
                  else . end as pct_sentinel
      from work.variables_meta m
      left join work.miss_&dsname c on m.var_name = c.var_name
      left join (select nobs from work.miss_&dsname(obs=1)) m_nobs on 1=1;
    quit;

    proc append base=work.variables data=work.vars_joined; run;
    proc datasets lib=work nolist;
      delete variables_meta vars_joined miss_&dsname;
    quit;

    %goto next_profile;
    %next_profile:
  %end;
%mend profile_variables;
%profile_variables;

/* Also profile individual XLSX sheets (they have different dsnames) */
%macro profile_xlsx_sheets;
  %local n_sheets i ds_sheet fpath fname sheet;
  /* Find all WORK tables that start with inv_ and are NOT already in variables */
  /* We will sweep work.sheets_out for sheet references */
  %let n_sheets = 0;
  proc sql noprint;
    select count(*) into :n_sheets trimmed from work.sheets_out;
  quit;

  %do i = 1 %to &n_sheets;
    %let fpath  = ;
    %let fname  = ;
    %let sheet  = ;
    proc sql noprint;
      select full_path, filename, sheet_name
      into :fpath trimmed, :fname trimmed, :sheet trimmed
      from work.sheets_out(firstobs=&i obs=&i);
    quit;
    /* dsname is inv_NNNNN + sheet name (uppercased) */
    /* We need to find the file_id for this fpath */
    %let fid = 0;
    proc sql noprint;
      select file_id into :fid trimmed
      from work.files_ck where full_path = "&fpath";
    quit;
    %let ds_sheet = inv_%sysfunc(putn(&fid, z5.))%sysfunc(upcase(&sheet));
    %if %sysfunc(exist(work.&ds_sheet)) = 0 %then %goto next_sheet;

    %let n_num  = 0;
    %let n_char = 0;
    proc sql noprint;
      select count(*) into :n_num trimmed
      from dictionary.columns
      where libname='WORK' and memname=upcase("&ds_sheet")
        and type='num';
      select count(*) into :n_char trimmed
      from dictionary.columns
      where libname='WORK' and memname=upcase("&ds_sheet")
        and type='char';
    quit;

    data work.miss_&ds_sheet (keep=var_name n_miss_num n_sent_num
                                    n_miss_chr n_sent_chr nobs);
      set work.&ds_sheet end=_eof;
      array _num  {*} _numeric_;
      array _char {*} _character_;
      array n_miss_n {%eval(%sysfunc(max(&n_num,1)))}  _temporary_;
      array n_sent_n {%eval(%sysfunc(max(&n_num,1)))}  _temporary_;
      array n_miss_c {%eval(%sysfunc(max(&n_char,1)))} _temporary_;
      array n_sent_c {%eval(%sysfunc(max(&n_char,1)))} _temporary_;
      if _n_ = 1 then do;
        do _i = 1 to dim(_num);  n_miss_n{_i}=0; n_sent_n{_i}=0; end;
        do _i = 1 to dim(_char); n_miss_c{_i}=0; n_sent_c{_i}=0; end;
      end;
      do _i = 1 to dim(_num);
        if missing(_num{_i})    then n_miss_n{_i} + 1;
        else if _num{_i} = -999 then n_sent_n{_i} + 1;
      end;
      do _i = 1 to dim(_char);
        if missing(_char{_i})                         then n_miss_c{_i} + 1;
        else if upcase(strip(_char{_i})) = 'NULL'     then n_sent_c{_i} + 1;
      end;
      if _eof then do;
        nobs = _n_;
        do _i = 1 to dim(_num);
          var_name   = vname(_num{_i});
          n_miss_num = n_miss_n{_i};
          n_sent_num = n_sent_n{_i};
          n_miss_chr = .;
          n_sent_chr = .;
          output;
        end;
        do _i = 1 to dim(_char);
          var_name   = vname(_char{_i});
          n_miss_num = .;
          n_sent_num = .;
          n_miss_chr = n_miss_c{_i};
          n_sent_chr = n_sent_c{_i};
          output;
        end;
        /* B04-NOSTOP-VERIFIED */
      end;
    run;

    proc sql noprint;
      create table work.variables_meta as
      select libname, memname, name as var_name, type as var_type,
             length as var_length, label as var_label, varnum as var_pos,
             "&fpath"  as source_file length=500,
             "&sheet"  as sheet_name  length=200
      from dictionary.columns
      where libname='WORK' and memname=upcase("&ds_sheet");
    quit;

    proc sql noprint;
      create table work.vars_joined as
      select m.*,
             coalesce(c.n_miss_num, c.n_miss_chr, 0) as n_missing,
             coalesce(c.n_sent_num, c.n_sent_chr, 0) as n_sentinel,
             coalesce(m_nobs.nobs, 0) as nobs,
             case when coalesce(m_nobs.nobs, 0) > 0
                  then coalesce(c.n_miss_num, c.n_miss_chr, 0)
                       / coalesce(m_nobs.nobs, 0) * 100
                  else . end as pct_missing,
             case when coalesce(m_nobs.nobs, 0) > 0
                  then coalesce(c.n_sent_num, c.n_sent_chr, 0)
                       / coalesce(m_nobs.nobs, 0) * 100
                  else . end as pct_sentinel
      from work.variables_meta m
      left join work.miss_&ds_sheet c on m.var_name = c.var_name
      left join (select nobs from work.miss_&ds_sheet(obs=1)) m_nobs on 1=1;
    quit;

    proc append base=work.variables data=work.vars_joined; run;
    proc datasets lib=work nolist;
      delete variables_meta vars_joined miss_&ds_sheet;
    quit;

    %goto next_sheet;
    %next_sheet:
  %end;
%mend profile_xlsx_sheets;
%profile_xlsx_sheets;


/* ============================================================
   SECTION 8 -- Key-column detection (INV-04, PCM-T-12, W-01, W-02)
   R2-B-01: DATA-step-only starts-with operator avoided in PROC SQL; substr(upcase(compress(...))) used instead.
   R2-W-01: ENCOUNTERID -> UNENC_ENCOUNTER; label 'ENCRYPTEDENCOUNTER' -> ENCRYPTED_ENCOUNTER.
   W-02: compress(upcase(name),' _-') normalization.
   W-01: var_type restriction removed (PRECEDE_STUDY_ID is numeric in md7).
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
      /* R2-W-01: ENCOUNTERID and bare ENCOUNTER are unencrypted */
      when compress(upcase(var_name),' _-') in
           ('ENCOUNTERID','ENCOUNTER')                          then 'UNENC_ENCOUNTER'
      /* Label-based matches (VARnn from XLSX engine) */
      when compress(upcase(var_label),' _-') in
           ('PRECEDESTUDYID','STUDYID')                         then 'PRECEDE_STUDY_ID'
      when compress(upcase(var_label),' _-') = 'ENCRYPTEDMRN'  then 'ENCRYPTED_MRN'
      when compress(upcase(var_label),' _-') = 'MRN'           then 'UNENC_MRN'
      /* R2-W-01 label branch: split ENCRYPTEDENCOUNTER (encrypted) from ENCOUNTERID */
      when compress(upcase(var_label),' _-') = 'ENCRYPTEDENCOUNTER' then 'ENCRYPTED_ENCOUNTER'
      when compress(upcase(var_label),' _-') in
           ('ENCOUNTERID','ENCOUNTER')                          then 'UNENC_ENCOUNTER'
    end as key_column_type length=30,
    /* R2-W-01: STUDYID match_basis='loose'; PRECEDESTUDYID match_basis='name';
       ENCOUNTERID match_basis='name' -> UNENC_ENCOUNTER */
    case
      when compress(upcase(var_name),' _-') in
           ('ENCRYPTEDMRN','MRN','ENCOUNTERID','ENCOUNTER')
           or substr(upcase(compress(var_name,' _-')),1,9) = 'ENCRYPTED' then 'name'
      when compress(upcase(var_name),' _-') = 'PRECEDESTUDYID'          then 'name'
      when compress(upcase(var_name),' _-') = 'STUDYID'                 then 'loose'
      else 'label'
    end as match_basis length=20
  from work.variables
  where calculated key_column_type is not missing;
quit;


/* ============================================================
   SECTION 9 -- FAMILIES assignment (D-04, longest-match)
   R2-B-03: COM scouting uses DATA _null_ PUT, not PROC PRINT.
   ============================================================ */

/* COM scouting step */
proc sql noprint;
  create table work.com_scout as
  select distinct var_name, source_file
  from work.variables
  where substr(upcase(var_name),1,3) = 'COM'
    and compress(upcase(var_name),' _-') not in ('COMPLICATIONSUM')
    and substr(upcase(var_name),1,6) ne 'COMP10';
quit;
data _null_;
  set work.com_scout;
  put 'COM_SCOUT: ' var_name= source_file=;
run;

/* Prefix lookup (sorted by descending prefix length in code) */
data work.prefix_lookup;
  length prefix $50 family_name $50;
  retain prefix_len 0;
  infile datalines dsd;
  input prefix $ family_name $;
  prefix_len = length(strip(prefix));
  datalines;
COMPLICATION_SUM,complications
COMP10_,complications
LINUS,LINUS
COM,dCDT
;

proc sort data=work.prefix_lookup;
  by descending prefix_len;
run;

/* Assign family to each variable via longest-match */
%macro assign_families;
  %local n_pref;
  %let n_pref = 0;
  proc sql noprint;
    select count(*) into :n_pref trimmed from work.prefix_lookup;
  quit;

  /* Build a family assignment dataset */
  data work.var_family;
    set work.variables;
    length family_name $50;
    family_name = 'unassigned';
    uname = upcase(var_name);
    /* Longest-match: try each prefix in order (already sorted desc length) */
    %do _pi = 1 %to &n_pref;
      %local _pfx _pfam;
      %let _pfx = ;
      %let _pfam = ;
      proc sql noprint;
        select prefix, family_name
        into :_pfx trimmed, :_pfam trimmed
        from work.prefix_lookup(firstobs=&_pi obs=&_pi);
      quit;
      if family_name = 'unassigned' and
         substr(uname, 1, %length(&_pfx)) = upcase("&_pfx") then
        family_name = "&_pfam";
    %end;
    drop uname;
  run;

  /* Aggregate to FAMILIES sheet: family_name x source_file */
  proc sql noprint;
    create table work.families as
    select family_name, source_file,
           count(*) as n_cols,
           min(pct_missing) as pct_missing_min,
           median(pct_missing) as pct_missing_median,
           max(pct_missing) as pct_missing_max
    from work.var_family
    group by family_name, source_file
    order by family_name, source_file;
  quit;
%mend assign_families;
%assign_families;

/* FAMILIES full-join assertion (D-04) */
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
   Known files: md1-md8 (same as Section 4) + r1-r9 Phase 18 supplemental.
   B-01 fix: do NOT include the r1-also-md1 guess.
   r1-r9 exact filenames from 18-02-PLAN.md and sas/16_raw_inventory.sas.
   ============================================================ */
data work.known_files;
  length known_filename $200;
  infile datalines dsd;
  input known_filename $;
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
    where status not in ('profiled', 'listed-not-profiled', 'read-failed');
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
  %put NOTE: INV-06 assertion -- total=&n_total profiled=&n_prof listed=&n_listed failed=&n_failed;
  %put NOTE: assert_inv06 passed;
%mend assert_inv06;
%assert_inv06;

/* ============================================================
   SECTION 11b -- W-04 D-06 abort-on-required-file-failure assertion
   ============================================================ */
%macro assert_masters_profiled;
  %local n_bad;
  %let n_bad = 0;
  proc sql noprint;
    select count(*) into :n_bad trimmed
    from work.required_files r
    left join work.files_out f
      on upcase(f.filename) = upcase(r.req_filename)
    where coalesce(f.status,'') ne 'profiled';
  quit;
  %if &n_bad > 0 %then %do;
    %fail_out(msg=D-06 ABORT -- &n_bad required master extract(s) did not reach profiled status);
  %end;
  %put NOTE: assert_masters_profiled passed -- all 8 md1-md8 masters have status=profiled;
%mend assert_masters_profiled;
%assert_masters_profiled;


/* ============================================================
   SECTION 12 -- PROC EXPORT -> qc/19_raw_files.csv
   Written BEFORE ODS Excel opens (Pitfall 9 / CONTEXT.md Specifics).
   ============================================================ */
proc export data=work.files_out
  outfile="&qc_path.\19_raw_files.csv"
  dbms=csv replace;
run;
%put NOTE: qc/19_raw_files.csv written -- Phase 20 handoff file ready;


/* ============================================================
   SECTION 13 -- ODS Excel assembly (D-05, KEY sheet first = leftmost)
   KEY written first so it is the leftmost tab in the workbook.
   UF blue (#0021A5) headers via PROC TEMPLATE style override.
   ============================================================ */

/* Build KEY legend: one row per column in each sheet */
data work.key_legend;
  length sheet_name $20 column_name $50 description $200 notes $200;
  infile datalines dsd dlm='|';
  input sheet_name $ column_name $ description $ notes $;
  datalines;
FILES|full_path|Full path of the file on disk|Read-only source; no writes
FILES|filename|File name with extension|
FILES|ext|File extension (lowercased)|
FILES|fsize|File size in bytes|
FILES|fdate|Last modified date from OS|
FILES|sha256|SHA-256 checksum (certutil)|FAILED if certutil could not hash the file
FILES|status|profiled / listed-not-profiled / read-failed|
FILES|nobs|Row count (missing for non-profiled files)|
FILES|ncols|Column count (missing for non-profiled files)|
FILES|fail_reason|Error text if status=read-failed|
FILES|import_warning|Warning text if syserr was 1-4 on import|SAS transcoding warnings appear here
FILES|file_id|Internal sequence number|
SHEETS|full_path|Full path of the parent XLSX/XLS file|
SHEETS|filename|File name of the parent workbook|
SHEETS|sheet_name|Name of the individual sheet|
SHEETS|nobs|Row count for this sheet|
SHEETS|ncols|Column count for this sheet|
VARIABLES|source_file|Full path of the source file|
VARIABLES|sheet_name|Sheet name for XLSX (blank for CSV/SAS7BDAT)|W-03: distinguishes sheets within same workbook
VARIABLES|var_name|SAS variable name (may be VARnn for XLSX with spaced headers)|
VARIABLES|var_type|SAS type: char or num|type reflects SAS-imported type NOT source system type; ENCRYPTED_MRN may import as num in one file and char in another
VARIABLES|var_length|SAS variable length in bytes|
VARIABLES|var_label|SAS variable label (original header for XLSX VARnn columns)|
VARIABLES|var_pos|Variable position in dataset (1-based)|
VARIABLES|nobs|Row count of the source dataset|
VARIABLES|n_missing|Count of true SAS-missing values (. for num; blank for char)|
VARIABLES|pct_missing|Percent missing (n_missing / nobs * 100)|
VARIABLES|n_sentinel|Count of sentinel values (-999 numeric or NULL string)|
VARIABLES|pct_sentinel|Percent sentinel (n_sentinel / nobs * 100)|Separate from pct_missing; -999 is not counted by NMISS
KEY_COLUMNS|source_file|Full path of the source file|
KEY_COLUMNS|sheet_name|Sheet name (blank for CSV)|
KEY_COLUMNS|var_name|SAS variable name|
KEY_COLUMNS|var_label|SAS variable label|
KEY_COLUMNS|var_type|SAS type|
KEY_COLUMNS|key_column_type|Detected key type: PRECEDE_STUDY_ID / ENCRYPTED_MRN / UNENC_MRN / ENCRYPTED_ENCOUNTER / UNENC_ENCOUNTER|W-01: UNENC_MRN is a plain MRN; do not equate to ENCRYPTED_MRN
KEY_COLUMNS|match_basis|How the key was detected: name / loose / label|STUDYID is loose (another study possible); PRECEDESTUDYID is name
RECONCILIATION|full_path|Full path of the file|
RECONCILIATION|filename|File name|
RECONCILIATION|ext|Extension|
RECONCILIATION|status|Import status|
RECONCILIATION|sha256|SHA-256 checksum|
RECONCILIATION|status_known|known (md1-md8 or r1-r9) or NEW|
FAMILIES|family_name|Column family name: complications / dCDT / LINUS / unassigned|COM scouting output in log determines dCDT columns
FAMILIES|source_file|Full path of the source file|
FAMILIES|n_cols|Number of columns in this family for this file|
FAMILIES|pct_missing_min|Minimum pct_missing across columns in this family|
FAMILIES|pct_missing_median|Median pct_missing across columns in this family|
FAMILIES|pct_missing_max|Maximum pct_missing across columns in this family|
;

/* ODS Excel: KEY first (leftmost), then remaining sheets in order */
ods excel file="&qc_path.\19_raw_inventory.xlsx"
    style=styles.pearl
    options(embedded_titles='yes');

ods excel options(sheet_name='KEY');
proc print data=work.key_legend noobs label; run;

ods excel options(sheet_name='FILES');
proc print data=work.files_out(drop=file_id) noobs; run;

ods excel options(sheet_name='SHEETS');
proc print data=work.sheets_out noobs; run;

ods excel options(sheet_name='VARIABLES');
proc print data=work.variables(rename=(source_file=file)) noobs; run;

ods excel options(sheet_name='KEY_COLUMNS');
proc print data=work.key_columns noobs; run;

ods excel options(sheet_name='RECONCILIATION');
proc print data=work.reconciliation noobs; run;

ods excel options(sheet_name='FAMILIES');
proc print data=work.families noobs; run;

ods excel close;


/* ============================================================
   SECTION 14 -- Output verification and log restore
   B-06 fix: no literal double-quotes inside %sysfunc(fileexist()).
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
