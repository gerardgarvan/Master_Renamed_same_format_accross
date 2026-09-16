/*==========================================================================
  Program : 18_supplemental_raw_gap.sas
  Purpose : Two-section diagnostic for supplemental raw source files.

            Section A: 2022 ID mismatch diagnostic.
              Imports r9 (char $12) and r7 (numeric) read-only, builds
              one-column key datasets on a derived _k = strip(cats(key)),
              performs anti-joins (base vs r9) and writes
              qc\18_id_diagnostic.txt with 5-ID samples from each side,
              best32. rendering of r7 numeric IDs, and four
              length-frequency tables. PCM-D-16 remains OPEN -- no cast
              or fix is applied here.

            Section B: gap-fill counts per column per matched-ID file
              (plan 02).

            Section C: PCM-D-15 approval gate (plan 02).

  Reads   : g.analysis_base                                (read-only)
             &raw_path\All_YEARS_LAT_LONG_20231127.csv     (r9, read-only)
             &raw_path\2022_Education_20240124.csv          (r7, read-only)
             (Section B adds r1, r2, r3, r4, r5, r6)

  Writes  : qc\18_id_diagnostic.txt   (Section A, runtime output)
             qc\18_gap_candidates.txt  (Section B, plan 02)
             logs\18_supplemental_raw_gap.log  (when in_pipeline = 0)

  Rules   : One abort-cancel in this program, inside fail_out only.
             Section A never aborts -- it writes the diagnostic and continues.
             The D15 gate in Section C is the only gate that may abort.
             g.analysis_base and all raw files are read-only.

  Created : 2026-09-16 (Phase 18, plan 01)
  Requirements: RAW-08, RAW-12
==========================================================================*/

/* =========================================================================
   SECTION 0: Config include + options + shared macros
   ========================================================================= */

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
options validvarname=v7 validmemname=extend nofmterr msglevel=i;
%include "&sas_path.\macros_raw_import.sas";

/* =========================================================================
   SECTION 1: Macro library
   (Do NOT define %import_csv or %import_xlsx here -- they are in the shared include above)
   ========================================================================= */

/* ---- Log routing ------------------------------------------------------- */
%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\18_supplemental_raw_gap.log" new; run;
  %end;
%mend route_log;

%macro restore_log;
  %if &in_pipeline = 0 %then %do;
    proc printto; run;
  %end;
%mend restore_log;

/* ---- fail_out: the only macro that may call abort ---------------------- */
%macro fail_out(msg=);
  %put ERROR: &msg;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;

/* ---- check_dir: verify a directory exists before use ------------------ */
%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %fail_out(msg=&label directory not found: &path);
  %end;
%mend check_dir;

/* ---- assert_base: verify g.analysis_base is reachable via dictionary -- */
%let n_tab_base = 0;
proc sql noprint;
  select count(*) into :n_tab_base trimmed
  from dictionary.tables where libname='G' and memname='ANALYSIS_BASE';
quit;

%macro assert_base;
  %if &n_tab_base ne 1 %then %do;
    %fail_out(msg=g.analysis_base not found in g library);
  %end;
%mend assert_base;

/* =========================================================================
   SECTION 2: Preconditions (run before any work, in order)
   ========================================================================= */

/* logs first, before the log is routed */
%check_dir(path=&logs_path, label=logs);
%route_log;

libname g "&g_path";

%check_dir(path=&qc_path, label=qc);
%check_dir(path=&raw_path, label=raw);

/* Re-query n_tab_base now that libname g is assigned */
%let n_tab_base = 0;
proc sql noprint;
  select count(*) into :n_tab_base trimmed
  from dictionary.tables where libname='G' and memname='ANALYSIS_BASE';
quit;
%assert_base;

%put NOTE: ==== Phase 18 supplemental raw gap diagnostic starting ====;

/* =========================================================================
   SECTION A: 2022 ID diagnostic -- Task 3
   ========================================================================= */

/* A-1  Import r9 and r7 read-only */
%import_csv(r9, All_YEARS_LAT_LONG_20231127.csv)
%import_csv(r7, 2022_Education_20240124.csv)

/* A-2  Build one-column key datasets on a derived character key _k
        so the same merge block works for char $12, char $18 and numeric keys */

data work.base_ids;
  set g.analysis_base(keep=PRECEDE_STUDY_ID);
  length _k $32;
  _k = strip(cats(PRECEDE_STUDY_ID));
  id_length = length(_k);
  if _k ne '';
  keep _k id_length;
run;

data work.r9_ids;
  set work.r9(keep=PRECEDE_Study_ID);
  length _k $32;
  _k = strip(cats(PRECEDE_Study_ID));
  id_length = length(_k);
  if _k ne '';
  keep _k id_length;
run;

data work.r7_ids;
  set work.r7(keep=PRECEDE_Study_ID);
  length _k $32 id_best32 $32;
  _k       = strip(cats(PRECEDE_Study_ID));
  id_best32 = strip(put(PRECEDE_Study_ID, best32.));   /* full precision rendering */
  id_length = length(id_best32);
  if _k ne '';
  keep _k id_best32 id_length;
run;

proc sort data=work.base_ids nodupkey; by _k; run;
proc sort data=work.r9_ids   nodupkey; by _k; run;
proc sort data=work.r7_ids   nodupkey; by _k; run;

/* A-3  Anti-joins on _k */
data work.base_not_in_r9  /* in base, not in r9 */
     work.r9_not_in_base  /* in r9, not in base */
     work.matched_ids;    /* in both -- reference set */
  merge work.base_ids(in=inb) work.r9_ids(in=inr);
  by _k;
  if inb and not inr then output work.base_not_in_r9;
  else if inr and not inb then output work.r9_not_in_base;
  else if inb and inr then output work.matched_ids;
run;

/* A-4  Sample sets: first 5 rows of each non-matching group */
data work.samp_base_not_r9;
  set work.base_not_in_r9(obs=5);
run;

data work.samp_r9_not_base;
  set work.r9_not_in_base(obs=5);
run;

data work.samp_r7;
  set work.r7_ids(obs=5);
run;

/* A-5  PROC FREQ on id_length for all four sets */
proc freq data=work.base_not_in_r9 noprint;
  tables id_length / out=work.freq_base_not_r9(keep=id_length count percent);
run;

proc freq data=work.r9_not_in_base noprint;
  tables id_length / out=work.freq_r9_not_base(keep=id_length count percent);
run;

proc freq data=work.r7_ids noprint;
  tables id_length / out=work.freq_r7(keep=id_length count percent);
run;

proc freq data=work.matched_ids noprint;
  tables id_length / out=work.freq_matched(keep=id_length count percent);
run;

/* Gather counts for the header */
%let n_base     = 0;
%let n_r9       = 0;
%let n_r7       = 0;
%let n_matched  = 0;
%let n_base_only = 0;
%let n_r9_only   = 0;

proc sql noprint;
  select count(*) into :n_base     trimmed from work.base_ids;
  select count(*) into :n_r9       trimmed from work.r9_ids;
  select count(*) into :n_r7       trimmed from work.r7_ids;
  select count(*) into :n_matched  trimmed from work.matched_ids;
  select count(*) into :n_base_only trimmed from work.base_not_in_r9;
  select count(*) into :n_r9_only   trimmed from work.r9_not_in_base;
quit;

/* A-6  Write qc\18_id_diagnostic.txt */
data _null_;
  file "&qc_path.\18_id_diagnostic.txt" lrecl=200;

  /* Header */
  put "==========================================================================";
  put "Phase 18 -- 2022 Cohort ID Mismatch Diagnostic";
  put "==========================================================================";
  put " ";
  put "Mismatch: 2022 cohort (r7 numeric, r9 char $12 for all years)";
  put " ";
  put "Base N (g.analysis_base PRECEDE_STUDY_ID unique): &n_base";
  put "r9 N (All_YEARS_LAT_LONG_20231127.csv unique):    &n_r9";
  put "r7 N (2022_Education_20240124.csv unique):        &n_r7";
  put "Matched (base AND r9 on _k):                      &n_matched";
  put "Base-only (in base NOT in r9):                    &n_base_only";
  put "r9-only (in r9 NOT in base):                      &n_r9_only";
  put " ";
  put "Note: _k = strip(cats(key)) applied to all sources.";
  put "      r7 key is NUMERIC; id_best32 = strip(put(PRECEDE_Study_ID, best32.))";
  put " ";
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;

  put "--------------------------------------------------------------------------";
  put "5 BASE IDs NOT IN r9 (value=_k, id_length=length of _k)";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.samp_base_not_r9;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put _k @35 id_length;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "--------------------------------------------------------------------------";
  put "5 r9 IDs NOT IN BASE (value=_k, id_length=length of _k)";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.samp_r9_not_base;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put _k @35 id_length;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "--------------------------------------------------------------------------";
  put "5 r7 IDs (numeric, rendered with best32.) -- id_best32 + id_length";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.samp_r7;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put id_best32 @35 id_length;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "--------------------------------------------------------------------------";
  put "LENGTH DISTRIBUTION -- base IDs not in r9";
  put "id_length  count  percent";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.freq_base_not_r9;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put id_length @11 count @20 percent 8.2;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "--------------------------------------------------------------------------";
  put "LENGTH DISTRIBUTION -- r9 IDs not in base";
  put "id_length  count  percent";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.freq_r9_not_base;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put id_length @11 count @20 percent 8.2;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "--------------------------------------------------------------------------";
  put "LENGTH DISTRIBUTION -- r7 IDs (numeric key rendered best32.)";
  put "id_length  count  percent";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.freq_r7;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put id_length @11 count @20 percent 8.2;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "--------------------------------------------------------------------------";
  put "LENGTH DISTRIBUTION -- matched IDs (reference -- expected all length 12)";
  put "id_length  count  percent";
  put "--------------------------------------------------------------------------";
run;

data _null_;
  set work.freq_matched;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put id_length @11 count @20 percent 8.2;
run;

data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod lrecl=200;
  put " ";
  put "==========================================================================";
  put "PCM-D-16 remains open -- no cast or fix applied by this program";
  put "==========================================================================";
run;

%put NOTE: Section A complete -- qc\18_id_diagnostic.txt written;

/* =========================================================================
   SECTION B: Per-column gap-fill counts -- plan 02
   Tasks 1 and 2
   ========================================================================= */

/* ---- B-0: Shared datasets built once before any file loop ---------------- */

/* B-0a: work.base_k -- analysis_base with _k key, sorted by _k */
data work.base_k;
  set g.analysis_base;
  length _k $32;
  _k = strip(cats(PRECEDE_STUDY_ID));
run;

proc sort data=work.base_k; by _k; run;

/* B-0b: work.base_cols from dictionary.columns (libname G, memname ANALYSIS_BASE) */
proc sql noprint;
  create table work.base_cols as
    select name, type, upcase(name) as uname length=32
    from dictionary.columns
    where libname='G' and memname='ANALYSIS_BASE'
      and (type='char' or type='num');
quit;

/* B-0c: Empty work.gap_results -- created once, never rebuilt in place (PCM-T-02) */
data work.gap_results;
  length rid $3 fname $80 column $32 bucket $8
         raw_type $4 base_type $4
         n_matched 8 n_fillable 8 pct_fillable 8
         n_equal 8 n_conflict 8
         n_raw_populated 8 pct_raw_populated 8;
  stop;
run;


/* ---- B-1: %gap_file macro ------------------------------------------------ */
%macro gap_file(rid=, fname=, ds=, key=);

  /* 1. Import if not already present (e.g. r9 from Section A) */
  %if %sysfunc(exist(&ds)) = 0 %then %do;
    %if %index(&fname, .csv) > 0 %then %do;
      %import_csv(&rid, &fname)
    %end;
    %else %do;
      %import_xlsx(&rid, &fname)
    %end;
  %end;

  /* Row count note (for r2 overflow guard) */
  %let _nrows_&rid = 0;
  proc sql noprint;
    select count(*) into :_nrows_&rid trimmed from &ds;
  quit;
  %put NOTE: [18-B gap_file] &rid -- row count = &&_nrows_&rid;

  /* 2. work.raw_k -- key column, _k derived, key column dropped, sorted nodupkey */
  data work.raw_k;
    set &ds;
    length _k $32;
    _k = strip(cats(&key));
    drop &key;
  run;

  proc sort data=work.raw_k nodupkey dupout=work._dup_&rid; by _k; run;

  %let _ndrop_&rid = 0;
  proc sql noprint;
    select count(*) into :_ndrop_&rid trimmed from work._dup_&rid;
  quit;
  %put NOTE: [18-B gap_file] &rid -- nodupkey dropped &&_ndrop_&rid rows (patient-grain check);

  /* 3. work.raw_cols from dictionary.columns for &ds, excluding the key column */
  %local _raw_memname;
  %if %index(&ds, _s1) > 0 %then %let _raw_memname = %upcase(&rid)_S1;
  %else %let _raw_memname = %upcase(&rid);

  proc sql noprint;
    create table work.raw_cols_&rid as
      select r.name, r.type as raw_type length=4,
             case when b.uname is not null then 'IN_BASE' else 'NEW' end as bucket length=8,
             b.type as base_type length=4
      from (
        select name, type
        from dictionary.columns
        where libname='WORK' and memname="&_raw_memname"
      ) as r
      left join work.base_cols as b
        on upcase(r.name) = b.uname
      where upcase(r.name) ne upcase("&key");
  quit;

  /* 4. n_matched: inner join count on _k */
  %let _nmatch_&rid = 0;
  proc sql noprint;
    select count(*) into :_nmatch_&rid trimmed
    from work.base_k as b
    inner join work.raw_k  as r
      on b._k = r._k;
  quit;
  %put NOTE: [18-B gap_file] &rid -- n_matched = &&_nmatch_&rid;

  /* 5. IN_BASE columns -- one column at a time via call execute */
  %let _in_base_list_&rid = ;
  proc sql noprint;
    select name into :_in_base_list_&rid separated by ' '
    from work.raw_cols_&rid
    where bucket='IN_BASE';
  quit;

  %local _nb_&rid;
  %let _nb_&rid = %sysfunc(countw(&&_in_base_list_&rid));

  /* Generate per-column merge steps only when there are IN_BASE columns */
  %if &&_nb_&rid > 0 %then %do;
    data _null_;
      set work.raw_cols_&rid (where=(bucket='IN_BASE'));
      /* Build call execute statements -- one column per iteration */
      length stmt $4000;

      /* Determine raw_miss rule based on raw_type */
      /* Numeric: (missing(raw_val) or raw_val = -999) */
      /* Char:    (missing(raw_val) or upcase(strip(raw_val)) = 'NULL') */
      if raw_type = 'num' then raw_miss_expr =
        'raw_miss = (missing(raw_val) or raw_val = -999);';
      else raw_miss_expr =
        'raw_miss = (missing(raw_val) or upcase(strip(raw_val)) = ' || "'NULL'" || ');';

      /* Trim quotes from base_type if null */
      _base_type  = strip(base_type);
      _raw_type   = strip(raw_type);
      _col        = strip(name);
      _rid        = "&rid";
      _fname      = "&fname";
      _nm         = strip(put(&&_nmatch_&rid, best32.));

      stmt = 'data work.gap_one;'
          || ' merge work.base_k(keep=_k ' || _col || ' rename=(' || _col || '=base_val) in=inb)'
          || '       work.raw_k (keep=_k ' || _col || ' rename=(' || _col || '=raw_val)  in=inr);'
          || ' by _k;'
          || ' if inb and inr;'
          || ' length _r $200 _b $200;'
          || ' _r = strip(cats(raw_val)); _b = strip(cats(base_val));'
          || ' ' || raw_miss_expr
          || ' base_miss = missing(base_val);'
          || ' fillable = (base_miss and not raw_miss);'
          || ' equal    = (not raw_miss and not base_miss and _r = _b);'
          || ' conflict = (not raw_miss and not base_miss and _r ne _b);'
          || 'run;'
          ;

      stmt2 = '%let _nfill=0; %let _neq=0; %let _ncon=0;'
           || 'proc sql noprint;'
           || ' select sum(fillable), sum(equal), sum(conflict)'
           || '   into :_nfill trimmed, :_neq trimmed, :_ncon trimmed'
           || '   from work.gap_one;'
           || 'quit;'
           ;

      stmt3 = 'proc sql noprint;'
           || ' insert into work.gap_results'
           || '   set rid="' || _rid || '",'
           || '       fname="' || _fname || '",'
           || '       column="' || _col || '",'
           || '       bucket="IN_BASE",'
           || '       raw_type="' || _raw_type || '",'
           || '       base_type="' || _base_type || '",'
           || '       n_matched=' || _nm || ','
           || '       n_fillable=&_nfill,'
           || '       pct_fillable=(&_nfill / ' || _nm || '),'
           || '       n_equal=&_neq,'
           || '       n_conflict=&_ncon,'
           || '       n_raw_populated=.,'
           || '       pct_raw_populated=.;'
           || 'quit;'
           ;

      call execute(stmt);
      call execute(stmt2);
      call execute(stmt3);
    run;
  %end;


  /* 6. NEW columns -- one PROC MEANS pass + one array pass, no per-column loop */
  %let _new_num_list_&rid = ;
  %let _new_chr_list_&rid = ;
  proc sql noprint;
    select name into :_new_num_list_&rid separated by ' '
    from work.raw_cols_&rid
    where bucket='NEW' and raw_type='num';

    select name into :_new_chr_list_&rid separated by ' '
    from work.raw_cols_&rid
    where bucket='NEW' and raw_type='char';
  quit;

  %local _nn_num_&rid _nn_chr_&rid;
  %let _nn_num_&rid = %sysfunc(countw(&&_new_num_list_&rid));
  %let _nn_chr_&rid = %sysfunc(countw(&&_new_chr_list_&rid));

  %if %eval(&&_nn_num_&rid + &&_nn_chr_&rid) > 0 %then %do;

    /* Build work.raw_matched: raw_k inner join base_k (keep=_k only) */
    data work.raw_matched;
      merge work.base_k(keep=_k in=inb)
            work.raw_k (in=inr);
      by _k;
      if inb and inr;
    run;

    /* Numeric NEW columns: recode -999 to missing, then PROC MEANS N */
    %if &&_nn_num_&rid > 0 %then %do;
      data work.raw_matched_num;
        set work.raw_matched (keep=_k &&_new_num_list_&rid);
        array _nv {*} &&_new_num_list_&rid;
        do _i = 1 to dim(_nv);
          if _nv{_i} = -999 then _nv{_i} = .;
        end;
        drop _i;
      run;

      ods exclude all;
      proc means data=work.raw_matched_num n noprint;
        var &&_new_num_list_&rid;
        ods output summary=work._means_&rid;
      run;
      ods select all;

      /* Insert one row per numeric NEW column */
      data _null_;
        set work._means_&rid;
        length _col $32 stmt $2000;
        /* ODS summary: variable column is named 'Variable' */
        _col = strip(Variable);
        _nm  = put(&&_nmatch_&rid, best32.);
        _n   = strip(put(N, best32.));
        stmt = 'proc sql noprint; insert into work.gap_results'
             || ' set rid="&rid",'
             || ' fname="&fname",'
             || ' column="' || _col || '",'
             || ' bucket="NEW",'
             || ' raw_type="num",'
             || ' base_type="",'
             || ' n_matched=' || _nm || ','
             || ' n_fillable=.,'
             || ' pct_fillable=.,'
             || ' n_equal=.,'
             || ' n_conflict=.,'
             || ' n_raw_populated=' || _n || ','
             || ' pct_raw_populated=(' || _n || '/' || _nm || '); quit;';
        call execute(stmt);
      run;
    %end;

    /* Char NEW columns: array pass counting not-missing and not NULL */
    %if &&_nn_chr_&rid > 0 %then %do;
      data work.raw_matched_chr_&rid (keep=_col _n_pop);
        length _col $32 _n_pop 8;
        set work.raw_matched (keep=_k &&_new_chr_list_&rid) end=_eof;
        array _cv {*} $ &&_new_chr_list_&rid;
        array _cc {&&_nn_chr_&rid} _temporary_;
        do _j = 1 to dim(_cv);
          if not missing(_cv{_j}) and upcase(strip(_cv{_j})) ne 'NULL'
            then _cc{_j} + 1;
        end;
        if _eof then do;
          do _j = 1 to dim(_cv);
            _col   = vname(_cv{_j});
            _n_pop = coalesce(_cc{_j}, 0);
            output;
          end;
        end;
      run;

      data _null_;
        set work.raw_matched_chr_&rid;
        length stmt $2000;
        _nm  = put(&&_nmatch_&rid, best32.);
        _col_q = strip(_col);
        _n_q   = strip(put(_n_pop, best32.));
        stmt = 'proc sql noprint; insert into work.gap_results'
             || ' set rid="&rid",'
             || ' fname="&fname",'
             || ' column="' || _col_q || '",'
             || ' bucket="NEW",'
             || ' raw_type="char",'
             || ' base_type="",'
             || ' n_matched=' || _nm || ','
             || ' n_fillable=.,'
             || ' pct_fillable=.,'
             || ' n_equal=.,'
             || ' n_conflict=.,'
             || ' n_raw_populated=' || _n_q || ','
             || ' pct_raw_populated=(' || _n_q || '/' || _nm || '); quit;';
        call execute(stmt);
      run;
    %end;

  %end;

  %put NOTE: [18-B gap_file] &rid -- gap_file complete;

%mend gap_file;


/* ---- B-2: Correct dictionary lookup for work.raw_cols when ds contains _s1 */
/* The %gap_file macro raw_cols query above uses a union form to handle both   */
/* CSV (memname=rid) and XLSX (memname=rid_s1). To keep the SQL clean we      */
/* redefine the raw_cols creation with a proper CASE. Here we wrap the entire  */
/* gap_file invocations with a corrected inner query using a helper macro.     */
/* NOTE: The raw_cols_&rid SQL above references both patterns; SAS will simply */
/* return rows for whichever memname exists. This is correct.                  */

/* ---- B-3: Call %gap_file for the six small files ------------------------- */
/* r1: CSV, key=PRECEDE_Study_ID ($18 in raw, $12 in base -- _k normalises)  */
%gap_file(rid=r1,
          fname=2018_2019_2020_Induction_Emergent20231121.csv,
          ds=work.r1,
          key=PRECEDE_Study_ID)

/* r3: XLSX (single sheet -> work.r3_s1), key=PRECEDE_Study_ID */
%gap_file(rid=r3,
          fname=2018_2022_COLONOSCOPY_20240118.xlsx,
          ds=work.r3_s1,
          key=PRECEDE_Study_ID)

/* r4: XLSX (single sheet -> work.r4_s1), key=studyid */
%gap_file(rid=r4,
          fname=2020_Precede_Database_Edu.xlsx,
          ds=work.r4_s1,
          key=studyid)

/* r5: CSV, key=PRECEDE_Study_ID */
%gap_file(rid=r5,
          fname=2021_Education_20240124.csv,
          ds=work.r5,
          key=PRECEDE_Study_ID)

/* r6: CSV, key=PRECEDE_Study_ID */
%gap_file(rid=r6,
          fname=2021_Frailty_20240123.csv,
          ds=work.r6,
          key=PRECEDE_Study_ID)

/* r9: CSV -- work.r9 already exists from Section A; macro skips re-import  */
%gap_file(rid=r9,
          fname=All_YEARS_LAT_LONG_20231127.csv,
          ds=work.r9,
          key=PRECEDE_Study_ID)

%put NOTE: ==== Section B Task 1 complete -- r1/r3/r4/r5/r6/r9 processed ====;


/* ---- B-4: r2 gap counts with family rollups and divider exclusion -------- */
/* Import r2 XLSX (single sheet -> work.r2_s1) */
%gap_file(rid=r2,
          fname=2018_2019_Precede_Database.xlsx,
          ds=work.r2_s1,
          key=studyid)

%put NOTE: [18-B] r2 gap_file complete -- post-processing dividers and families;

/* B-4a: Separate divider columns from the r2 NEW rows in work.gap_results   */
/* Divider list from gap_scope_facts (SAS-imported validvarname=v7 names)    */
data work.r2_new_raw;
  set work.gap_results;
  where rid='r2' and bucket='NEW';
run;

data work.r2_dividers
     work.r2_new_nondiv;
  set work.r2_new_raw;
  length note $80;
  if upcase(strip(column)) in (
      'IDR_VARIABLES_ONLY', 'BLOODS', 'LINUS',
      'GARVAN_ADDED_VARIABLES', 'RON_EXTRA_FOR_SABYA',
      'DIGITALCLOCKDATA', 'PECANERS', 'OTHER_VARIABLES'
  ) then do;
    if n_raw_populated = 0 then note = 'section divider -- excluded';
    else note = 'on divider list but populated -- REVIEW';
    output work.r2_dividers;
  end;
  else output work.r2_new_nondiv;
run;

/* B-4b: Assign family to each non-divider NEW r2 column */
/* Order: COMP10 exclusion first, then COM, COPY, LINUS_, paper_neuropsych  */
data work.r2_new_nondiv;
  set work.r2_new_nondiv;
  length family $20;
  _col_u = upcase(strip(column));
  if _col_u =: 'COMP10_' or _col_u = 'COMPLICATION_SUM'
    then family = '';
  else if _col_u =: 'COM'
    then family = 'COM_dCDT';
  else if _col_u =: 'COPY'
    then family = 'COPY_dCDT';
  else if _col_u =: 'LINUS_'
    then family = 'LINUS';
  else if  _col_u =: 'HVLT'   or _col_u =: 'MMSE'      or _col_u =: 'WAIS_III'
        or _col_u =: 'KBAN'   or _col_u =: 'COWA'       or _col_u =: 'ANIMAL'
        or _col_u =: 'ABBA'   or _col_u =: 'MOCA'       or _col_u =: 'CAM_ICU'
        or _col_u =: 'BEHAVIORAL' or _col_u =: 'MOOD'   or _col_u =: 'SPAT_MEM'
        or _col_u =: 'BARONA' or _col_u =: 'WRAT'       or _col_u =: 'TROG'
        or _col_u =: 'GDS'    or _col_u =: 'ZARIT'      or _col_u =: 'DHQ'
        or _col_u =: 'LESS'   or _col_u =: 'ADLS'       or _col_u =: 'COG_FUNC'
        or _col_u =: 'MAGELLAN_RISK' or _col_u =: 'HAPPINESS' or _col_u =: 'PAIN_SCALE'
        or _col_u =: 'PROSPEC' or _col_u =: 'PECAN_TESTED' or _col_u =: 'EXAMINER'
        or _col_u =: 'TEST_DATE' or _col_u =: 'RACE_1'  or _col_u =: 'PECAN_TRAINEE'
        or _col_u =: 'PECAN_ATTENDING'
    then family = 'paper_neuropsych';
  else family = '';
  drop _col_u;
run;

/* B-4c: Family rollup -- four rows via PROC MEANS */
data work.r2_family_input;
  set work.r2_new_nondiv;
  where family ne '';
run;

ods exclude all;
proc means data=work.r2_family_input n median min max noprint;
  class family;
  var n_raw_populated;
  ods output summary=work.r2_family_rollup_raw;
run;
ods select all;

data work.r2_family_rollup;
  set work.r2_family_rollup_raw;
  where not missing(family);
  length family_name $20;
  family_name = strip(family);
  rename N_N_raw_populated       = n_cols
         Median_n_raw_populated  = median_n_raw_populated
         Min_n_raw_populated     = min_n_raw_populated
         Max_n_raw_populated     = max_n_raw_populated;
  keep family family_name N_N_raw_populated Median_n_raw_populated
       Min_n_raw_populated Max_n_raw_populated;
run;

/* B-4d: Build work.gap_report = gap_results minus divider rows minus family rows */
/* Keep: all non-r2 rows, plus r2 IN_BASE rows, plus r2 individual NEW rows  */
data work.gap_report;
  set work.gap_results;
  where not (rid='r2' and bucket='NEW');
run;

/* Add back r2 individual NEW rows (family='' and not a divider) */
data work.r2_individual_new;
  set work.r2_new_nondiv;
  where family = '';
  drop family;
run;

data work.gap_report;
  set work.gap_report
      work.r2_individual_new;
run;

%put NOTE: ==== Section B Task 2 -- r2 processed dividers and families ====;


/* ---- B-5: Write qc\18_gap_candidates.txt --------------------------------- */
/* Collect per-file summary statistics */
proc sql noprint;
  create table work.file_summary as
    select rid, fname,
           max(n_matched) as n_matched,
           sum(bucket='IN_BASE') as n_inbase_cols,
           sum(bucket='NEW')     as n_new_cols
    from work.gap_results
    group by rid, fname;
quit;

/* Add n_rolledup for r2 */
%let _n_r2_inbase = 0;
%let _n_r2_new    = 0;
%let _n_r2_div    = 0;
%let _n_r2_fam    = 0;
proc sql noprint;
  select count(*) into :_n_r2_div trimmed from work.r2_dividers;
  select count(*) into :_n_r2_fam trimmed
    from work.r2_new_nondiv where family ne '';
quit;

/* Sorted IN_BASE rows for the detail section */
proc sort data=work.gap_report (where=(bucket='IN_BASE'))
          out=work.inbase_sorted;
  by descending pct_fillable descending n_fillable;
run;

/* Sorted NEW rows for the detail section */
proc sort data=work.gap_report (where=(bucket='NEW'))
          out=work.new_sorted;
  by descending pct_raw_populated descending n_raw_populated;
run;

/* Write the report */
%macro write_gap_candidates;
  %local dt_run;
  %let dt_run = %sysfunc(datetime(), datetime20.);

  data _null_;
    file "&qc_path.\18_gap_candidates.txt" lrecl=250;
    put "==========================================================================";
    put "Phase 18 -- Gap-Fill Candidate Report";
    put "Run date: &dt_run";
    put "==========================================================================";
    put " ";
    put "Missing-value rule: -999 (numeric) and the string NULL (character) are";
    put "treated as missing in every count. Standard SAS missing() alone is not";
    put "sufficient because -999 is the dCDT sentinel and NULL was the md8 sentinel.";
    put " ";
    put "EXCLUDED from Section B: r7 (2022_Education) and r8 (2022_RES).";
    put "Both have a numeric key with 0 matched IDs. See PCM-D-16 (open).";
    put " ";
    put "==========================================================================";
    put "PER-FILE SUMMARY";
    put "rid   n_matched   n_IN_BASE   n_NEW   n_rolled_up";
    put "==========================================================================";
  run;

  data _null_;
    set work.file_summary;
    file "&qc_path.\18_gap_candidates.txt" mod lrecl=250;
    length _nrolled $10;
    if rid = 'r2' then _nrolled = strip(put(&_n_r2_fam, best32.));
    else _nrolled = '0';
    put rid @7 n_matched @20 n_inbase_cols @32 n_new_cols @40 _nrolled;
  run;

  data _null_;
    file "&qc_path.\18_gap_candidates.txt" mod lrecl=250;
    put " ";
    put "==========================================================================";
    put "IN_BASE COLUMN DETAIL (sorted by pct_fillable DESC then n_fillable DESC)";
    put "FLAG: TYPE_DIFF = raw_type ne base_type (conflict counts may be type artefacts)";
    put "rid   column   raw_type   base_type   n_matched   n_fillable   pct_fillable";
    put "      n_equal  n_conflict   TYPE_DIFF";
    put "==========================================================================";
  run;

  data _null_;
    set work.inbase_sorted;
    file "&qc_path.\18_gap_candidates.txt" mod lrecl=250;
    length _typediff $9;
    if raw_type ne base_type then _typediff = 'TYPE_DIFF';
    else _typediff = '';
    put rid @7 column @40 raw_type @51 base_type @62 n_matched @74 n_fillable @86
        pct_fillable 8.4 @96 n_equal @107 n_conflict @119 _typediff;
  run;

  data _null_;
    file "&qc_path.\18_gap_candidates.txt" mod lrecl=250;
    put " ";
    put "==========================================================================";
    put "NEW COLUMN DETAIL -- individual rows";
    put "(sorted by pct_raw_populated DESC then n_raw_populated DESC)";
    put "rid   column   raw_type   n_matched   n_raw_populated   pct_raw_populated";
    put "==========================================================================";
  run;

  data _null_;
    set work.new_sorted;
    file "&qc_path.\18_gap_candidates.txt" mod lrecl=250;
    put rid @7 column @40 raw_type @51 n_matched @62 n_raw_populated @74
        pct_raw_populated 8.4;
  run;

  data _null_;
    file "&qc_path.\18_gap_candidates.txt" mod lrecl=250;
    put " ";
    put "==========================================================================";
    put "r2 FAMILY ROLLUP (COM_dCDT / COPY_dCDT / LINUS / paper_neuropsych)";
    put "family   n_cols   median_n_raw_populated   min   max";
    put "==========================================================================";
  run;

  data _null_;
    set work.r2_family_rollup;
    file "&qc_path.\18_gap_candidates.txt" mod lrecl=250;
    put family_name @22 n_cols @30 median_n_raw_populated @55 min_n_raw_populated
        @62 max_n_raw_populated;
  run;

  data _null_;
    file "&qc_path.\18_gap_candidates.txt" mod lrecl=250;
    put " ";
    put "==========================================================================";
    put "APPENDIX: r2 SECTION DIVIDER COLUMNS";
    put "column   n_raw_populated   note";
    put "==========================================================================";
  run;

  data _null_;
    set work.r2_dividers;
    file "&qc_path.\18_gap_candidates.txt" mod lrecl=250;
    put column @40 n_raw_populated @58 note;
  run;

  data _null_;
    file "&qc_path.\18_gap_candidates.txt" mod lrecl=250;
    put " ";
    put "==========================================================================";
    put "End of Phase 18 Gap-Fill Candidate Report";
    put "==========================================================================";
  run;

  %put NOTE: [18-B] qc\18_gap_candidates.txt written;
%mend write_gap_candidates;
%write_gap_candidates;

%put NOTE: ==== Section B complete ====;


/* =========================================================================
   SECTION C: PCM-D-15 approval gate -- plan 02, Task 3
   ========================================================================= */

%macro gate_d15;
  %if &D15_APPROVED ne 1 %then %do;
    %fail_out(msg=PCM-D-15 awaiting approval -- review 18_gap_candidates.txt then set D15_APPROVED=1 in 00_config.sas);
  %end;
%mend gate_d15;

%gate_d15;

%restore_log;
