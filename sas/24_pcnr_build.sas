/*==========================================================================
  Program : 24_pcnr_build.sas
  Phase   : 24 -- Build g.pcnr_harmonized
  Purpose : Apply approved sentinel decisions and name map to
            g.master_data_harmonized to produce g.pcnr_harmonized.
            Placeholder values (?, Unknown, ...) are set to missing and
            every analysis variable is renamed pcnr_<original_name>.
            Source datasets are never modified.

  Inputs  : g.master_data_harmonized  (read-only)
            docs/sentinel_decisions.csv
            docs/pcnr_name_map.csv
            qc/23_sentinel_fingerprint.txt  (P: drive)
            qc/23_sentinel_candidates.csv   (P: drive)

  Outputs : g.pcnr_harmonized
            qc/24_recode_rules_generated.sas  (machine-generated audit file)
            qc/24_pcnr_recode_counts.csv      (detail: one row per rule)
            qc/24_pcnr_recode_totals.csv      (per-variable total)

  PCM Compliance notes:
    - PCM-T-16: CSVs read via DATA step infile with explicit informats only (never IMPORT)
    - PCM-T-01: hex encoding uses %hexkey macro (hex400. width) -- bare hex. without width is forbidden
    - PCM-D-06: log messages use NOTE or ERROR only (WARNING inflates pipeline scanner count)
    - PCM-T-02: WORK-then-promote -- never data G.x; set G.x;
    - Open-code %if forbidden -- all %if inside named macros
    - IS NOT MISSING only in PROC SQL; not missing() in DATA step
    - No &SQLOBS -- use SELECT COUNT(*) INTO :macvar TRIMMED

  Author  : Phase 24 (2026-09-28)
==========================================================================*/

options mprint nofmterr nodate nonumber ps=max ls=200;

/* ---- Include config (standalone guard: pipeline runner pre-includes it) ---- */
%macro _24_include_config;
  %if not %symexist(sas_path) %then %do;
    %include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
  %end;
%mend _24_include_config;
%_24_include_config;

/* ---- Log routing (copied verbatim from sas/10b_concept_harmonize.sas lines 76-88) ---- */
%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\24_pcnr_build.log" new;
    run;
  %end;
%mend route_log;

%macro restore_log;
  %if &in_pipeline = 0 %then %do;
    proc printto;
    run;
  %end;
%mend restore_log;

/* ---- Abort macro (copied verbatim from sas/10b_concept_harmonize.sas lines 90-95) ---- */
%macro fail_out(msg=);
  %put ERROR: &msg;
  %restore_log;
  %abort cancel;
%mend fail_out;

%route_log;

libname g "&g_path";

%put NOTE: ==== Program 24 pcnr_build starting ====;


/* ===== SECTION 0: %pcnr_gate_check macro + gate execution (Plan 24-01 Task 2) ===== */

%macro pcnr_gate_check;

  /* ---- Check 1: Gate flag ---- */
  %if &PCNR_APPROVED ne 1 %then %do;
    %fail_out(msg=PCNR_APPROVED is not 1 -- gate closed. Set PCNR_APPROVED=1 in 00_config.sas after reviewing gate files.);
  %end;
  %put NOTE: [24] Check 1 passed -- PCNR_APPROVED=&PCNR_APPROVED;

  /* ---- Check 2: Fingerprint -- read file and compare against dictionary.tables ---- */
  data work._fingerprint_raw;
    infile "&qc_path.\23_sentinel_fingerprint.txt" truncover lrecl=200;
    length field $20 value $40;
    input field $ value $;
    field = upcase(strip(field));
    value = strip(value);
  run;

  proc sql noprint;
    select value into :fp_nobs   trimmed from work._fingerprint_raw where field = 'NOBS';
    select value into :fp_nvar   trimmed from work._fingerprint_raw where field = 'NVAR';
    select value into :fp_modate trimmed from work._fingerprint_raw where field = 'MODATE';

    /* Check that g.master_data_harmonized exists before querying its attributes */
    select count(*) into :n_harm_tab trimmed
    from dictionary.tables
    where libname='G' and memname='MASTER_DATA_HARMONIZED';
  quit;

  %if &n_harm_tab ne 1 %then %do;
    %fail_out(msg=g.master_data_harmonized not found in g library -- run Phase 23 first);
  %end;

  proc sql noprint;
    select strip(put(nobs,  best32.)) into :cur_nobs   trimmed
    from dictionary.tables where libname='G' and memname='MASTER_DATA_HARMONIZED';
    select strip(put(nvar,  best32.)) into :cur_nvar   trimmed
    from dictionary.tables where libname='G' and memname='MASTER_DATA_HARMONIZED';
    select strip(put(modate, datetime20.)) into :cur_modate trimmed
    from dictionary.tables where libname='G' and memname='MASTER_DATA_HARMONIZED';
  quit;

  %if &cur_nobs ne &fp_nobs %then %do;
    %fail_out(msg=Fingerprint mismatch: nobs -- expected &fp_nobs got &cur_nobs);
  %end;
  %if &cur_nvar ne &fp_nvar %then %do;
    %fail_out(msg=Fingerprint mismatch: nvar -- expected &fp_nvar got &cur_nvar);
  %end;
  %if &cur_modate ne &fp_modate %then %do;
    %fail_out(msg=Fingerprint mismatch: modate -- expected &fp_modate got &cur_modate);
  %end;
  %put NOTE: [24] Check 2 passed -- fingerprint matches nobs=&cur_nobs nvar=&cur_nvar;

  /* ---- Check 3: Load decisions via infile (PCM-T-16) ---- */
  data work._decisions_raw;
    infile "&docs_path.\sentinel_decisions.csv" dsd firstobs=2 truncover lrecl=32767;
    length variable      $32
           raw_value     $400
           raw_hex       $800
           raw_len       8
           normalized_value $400
           var_type      $4
           n_rows        8
           pct_rows      8
           column_group  $32
           candidate_class $20
           non_ascii_flag  8
           match_rule    $40
           action        $7
           rationale     $400
           decided_by    $40
           decided_date  $20;
    input variable $      raw_value $    raw_hex $
          raw_len          normalized_value $
          var_type $       n_rows          pct_rows
          column_group $   candidate_class $
          non_ascii_flag   match_rule $    action $
          rationale $      decided_by $    decided_date $;
  run;

  proc sql noprint;
    select count(*) into :n_decisions trimmed from work._decisions_raw;
  quit;
  %put NOTE: [24] Check 3 -- loaded &n_decisions decision rows from sentinel_decisions.csv;

  /* ---- Check 4: Load candidates + name map ---- */
  data work._candidates_raw;
    infile "&qc_path.\23_sentinel_candidates.csv" dsd firstobs=2 truncover lrecl=32767;
    length variable       $32
           raw_value      $400
           raw_hex        $800
           raw_len        8
           normalized_value $400
           var_type       $4
           n_rows         8
           pct_rows       8
           column_group   $32
           candidate_class $20
           non_ascii_flag  8
           match_rule     $40
           role           $4;   /* display only per Phase 23 D-04 -- do NOT use for rules */
    input variable $       raw_value $     raw_hex $
          raw_len           normalized_value $
          var_type $        n_rows           pct_rows
          column_group $    candidate_class $
          non_ascii_flag    match_rule $     role $;
  run;

  data work._name_map;
    infile "&docs_path.\pcnr_name_map.csv" dsd firstobs=2 truncover lrecl=32767;
    length source_name    $32
           source_label   $256
           role           $4
           h_strip        $1
           proposed_name  $32
           override_name  $32
           final_name     $32
           name_len       8
           collision_flag 8
           id_flag        8;
    input source_name $  source_label $  role $
          h_strip $       proposed_name $  override_name $
          final_name $    name_len        collision_flag
          id_flag;
  run;

  proc sql noprint;
    select count(*) into :n_candidates trimmed from work._candidates_raw;
    select count(*) into :n_map        trimmed from work._name_map;
  quit;
  %put NOTE: [24] Check 4 -- loaded &n_candidates candidates and &n_map name-map rows;

  /* ---- Check 5: Coverage -- every KEEP/KEY candidate must be covered ----
     Covered = per-variable decision row with same (variable, raw_hex) [any action]
               OR (no per-variable row AND var_type='char' AND not AMBIGUOUS)
                   a wildcard row (variable='*', var_type='char')
                   whose upcase(normalized_value) = upcase(candidate's normalized_value).
     Wildcard is matched on normalized_value ONLY -- never on raw_hex (blank on wildcard rows). */
  proc sql noprint;
    create table work._uncovered as
    select c.variable, c.raw_hex, c.raw_value, c.candidate_class, m.role
    from work._candidates_raw c
         inner join work._name_map m on m.source_name = c.variable
                                     and m.role in ('KEEP','KEY')
    where not exists (
        /* per-variable row for this (variable, raw_hex) -- any action */
        select 1 from work._decisions_raw d
        where d.variable = c.variable
          and d.raw_hex  = c.raw_hex
          and d.variable ne '*'
    )
    and not (
        /* wildcard coverage allowed only for char non-AMBIGUOUS */
        c.var_type = 'char'
        and c.candidate_class ne 'AMBIGUOUS'
        and exists (
            select 1 from work._decisions_raw w
            where w.variable = '*'
              and w.var_type  = 'char'
              and upcase(w.normalized_value) = upcase(c.normalized_value)
        )
    );
    select count(*) into :n_uncovered trimmed from work._uncovered;
  quit;

  %if &n_uncovered > 0 %then %do;
    %fail_out(msg=Coverage check failed -- &n_uncovered KEEP/KEY candidates have no decision (per-variable or wildcard). Review work._uncovered.);
  %end;
  %put NOTE: [24] Check 5 passed -- all KEEP/KEY candidates covered;

  /* ---- Check 6: AMBIGUOUS guard -- AMBIGUOUS KEEP/KEY must have per-variable row ---- */
  proc sql noprint;
    select count(*) into :n_amb_wild trimmed
    from work._candidates_raw c
         inner join work._name_map m on m.source_name = c.variable
                                     and m.role in ('KEEP','KEY')
    where c.candidate_class = 'AMBIGUOUS'
      and not exists (
          select 1 from work._decisions_raw d
          where d.variable = c.variable
            and d.raw_hex  = c.raw_hex
            and d.variable ne '*'
      );
  quit;

  %if &n_amb_wild > 0 %then %do;
    %fail_out(msg=AMBIGUOUS guard failed -- &n_amb_wild AMBIGUOUS KEEP/KEY candidates lack a per-variable decision row (wildcard may not resolve AMBIGUOUS values));
  %end;
  %put NOTE: [24] Check 6 passed -- no AMBIGUOUS candidate relies on wildcard coverage;

  /* ---- Check 7: Stale per-variable rows ---- */
  proc sql noprint;
    select count(*) into :n_stale_pv trimmed
    from work._decisions_raw d
    where d.variable ne '*'
      and not exists (
          select 1 from work._candidates_raw c
          where c.variable = d.variable
            and c.raw_hex  = d.raw_hex
      );
  quit;

  %if &n_stale_pv > 0 %then %do;
    %fail_out(msg=Stale per-variable check failed -- &n_stale_pv decision rows reference a (variable%str(,) raw_hex) not present in the candidates scan);
  %end;
  %put NOTE: [24] Check 7 passed -- no stale per-variable decision rows;

  /* ---- Check 8: Stale wildcard rows ---- */
  proc sql noprint;
    select count(*) into :n_stale_wc trimmed
    from work._decisions_raw w
    where w.variable = '*'
      and not exists (
          select 1 from work._candidates_raw c
               inner join work._name_map m on m.source_name = c.variable
                                           and m.role in ('KEEP','KEY')
          where c.var_type = 'char'
            and c.candidate_class ne 'AMBIGUOUS'
            and upcase(w.normalized_value) = upcase(c.normalized_value)
      );
  quit;

  %if &n_stale_wc > 0 %then %do;
    %fail_out(msg=Stale wildcard check failed -- &n_stale_wc wildcard rows match zero KEEP/KEY non-AMBIGUOUS char candidates);
  %end;
  %put NOTE: [24] Check 8 passed -- no stale wildcard rows;

  /* ---- Check 9: Wildcard type must be char ---- */
  proc sql noprint;
    select count(*) into :n_wc_num trimmed
    from work._decisions_raw
    where variable = '*' and var_type ne 'char';
  quit;

  %if &n_wc_num > 0 %then %do;
    %fail_out(msg=Wildcard type check failed -- &n_wc_num wildcard rows have var_type ne char (wildcards must be char only));
  %end;
  %put NOTE: [24] Check 9 passed -- all wildcard rows are var_type=char;

  /* ---- Check 10: Action validity ---- */
  proc sql noprint;
    select count(*) into :n_bad_action trimmed
    from work._decisions_raw
    where action not in ('MISSING','KEEP') or missing(action);
  quit;

  %if &n_bad_action > 0 %then %do;
    %fail_out(msg=Action validity check failed -- &n_bad_action decision rows have action not in (MISSING%str(,)KEEP) or blank action);
  %end;
  %put NOTE: [24] Check 10 passed -- all decision rows have valid action;

  /* ---- Check 11: Duplicate decisions ---- */
  proc sql noprint;
    /* Duplicate per-variable (variable, raw_hex) keys */
    select count(*) into :n_dup_pv trimmed
    from (
        select variable, raw_hex, count(*) as cnt
        from work._decisions_raw
        where variable ne '*'
        group by variable, raw_hex
        having cnt > 1
    );
    /* Duplicate wildcard normalized_value keys */
    select count(*) into :n_dup_wc trimmed
    from (
        select upcase(normalized_value) as nv, count(*) as cnt
        from work._decisions_raw
        where variable = '*'
        group by upcase(normalized_value)
        having cnt > 1
    );
    %let n_dup_dec = %eval(&n_dup_pv + &n_dup_wc);
  quit;

  %if &n_dup_dec > 0 %then %do;
    %fail_out(msg=Duplicate decision check failed -- &n_dup_pv duplicate per-variable keys and &n_dup_wc duplicate wildcard keys);
  %end;
  %put NOTE: [24] Check 11 passed -- no duplicate decision keys;

  %put NOTE: [24] gate passed -- nobs=&cur_nobs nvar=&cur_nvar;

%mend pcnr_gate_check;

%pcnr_gate_check;


/* ===== SECTION 1: resolve work._recode_rules (Plan 24-01 Task 3) ===== */

/* Build work._recode_rules: one row per (variable, raw_hex, action=MISSING).
   Per-variable MISSING rows take precedence over wildcard rows for the same
   (variable, raw_hex). Rule source is length=8 ('WILDCARD' is 8 characters). */

proc sql;
  /* Per-variable MISSING rows: any var_type */
  create table work._rules_pv as
  select d.variable, d.raw_hex, c.raw_value, c.var_type, d.action,
         'PER_VAR' as rule_source length=8, c.n_rows as n_expected
  from work._decisions_raw d
       inner join work._candidates_raw c on d.variable = c.variable
                                        and d.raw_hex  = c.raw_hex
       inner join work._name_map m       on m.source_name = c.variable
                                        and m.role in ('KEEP','KEY')
  where d.variable ne '*' and d.action = 'MISSING';

  /* Wildcard expansion: char KEEP/KEY non-AMBIGUOUS, no per-variable override */
  create table work._rules_wc as
  select c.variable, c.raw_hex, c.raw_value, c.var_type, d.action,
         'WILDCARD' as rule_source length=8, c.n_rows as n_expected
  from work._decisions_raw d
       inner join work._candidates_raw c on upcase(d.normalized_value) = upcase(c.normalized_value)
       inner join work._name_map m       on m.source_name = c.variable
                                        and m.role in ('KEEP','KEY')
  where d.variable = '*' and d.action = 'MISSING'
    and c.var_type = 'char' and c.candidate_class ne 'AMBIGUOUS'
    and not exists (
        select 1 from work._decisions_raw p
        where p.variable = c.variable
          and p.raw_hex  = c.raw_hex
    );

  /* Stack per-variable and wildcard rules */
  create table work._recode_rules as
  select * from work._rules_pv
  outer union corr
  select * from work._rules_wc
  order by variable, raw_hex;

  /* Assert uniqueness on (variable, raw_hex) */
  create table work._recode_dup_check as
  select variable, raw_hex, count(*) as cnt
  from work._recode_rules
  group by variable, raw_hex
  having cnt > 1;

  select count(*) into :n_dup_rules trimmed
  from work._recode_dup_check;
quit;

%macro _check_recode_unique;
  %if &n_dup_rules > 0 %then %do;
    %fail_out(msg=work._recode_rules has &n_dup_rules duplicate (variable%str(,) raw_hex) keys -- rule resolution error);
  %end;
%mend _check_recode_unique;
%_check_recode_unique;

proc sql noprint;
  select count(*) into :n_rules trimmed from work._recode_rules;
quit;

%put NOTE: [24] resolved &n_rules recode rules (action=MISSING) into work._recode_rules;


/* ===== SECTION 2: generate qc/24_recode_rules_generated.sas (Plan 24-01 Task 3) ===== */

/* Build a helper dataset: one row per (variable, raw_hex) for char rules,
   ordered so all rules for the same variable are contiguous.
   The DATA _NULL_ writer reads this sequentially, emitting one select/when block
   per variable. Numeric rules (currently none) are handled separately. */

/* Separate char and numeric rules */
proc sql;
  create table work._char_rules as
  select variable, raw_hex, raw_value, rule_source, n_expected
  from work._recode_rules
  where var_type = 'char'
  order by variable, raw_hex;

  create table work._num_rules as
  select variable, raw_hex, raw_value, rule_source, n_expected
  from work._recode_rules
  where var_type ne 'char'
  order by variable, raw_hex;

  select count(distinct variable) into :n_char_vars trimmed from work._char_rules;
  select count(distinct variable) into :n_num_vars  trimmed from work._num_rules;
quit;

%put NOTE: [24] char recode variables: &n_char_vars -- numeric recode variables: &n_num_vars;

/* Write the generated SAS snippet.
   Rules:
   - Plain ASCII SAS code only -- no options, no %include, no run; inside this file
   - It is %include'd inside an open DATA step (SECTION 3)
   - One select/when block per char column with at least one rule
   - Columns with zero rules are omitted entirely
   - raw_value in comment is display-only: sanitize */ to * / and replace non-ASCII bytes
   - Numeric rules (if any) use: if var = value and not missing(var) then call missing(var);
*/

/* Write header block as a single-row data step */
data _null_;
  file "&qc_path.\24_recode_rules_generated.sas" lrecl=32767;
  put "/* qc/24_recode_rules_generated.sas";
  put "   Machine-generated by sas/24_pcnr_build.sas SECTION 2.";
  put "   Do not edit -- re-run program 24 to regenerate.";
  put "   This file is %include'd inside a DATA step (no options/run/include here). */";
  put " ";
run;

/* Write char select/when blocks: sequential read, detect variable break by retained _prev_var.
   work._char_rules is sorted by variable, raw_hex so all rules for a column are contiguous. */
%if &n_char_vars > 0 %then %do;
data _null_;
  file "&qc_path.\24_recode_rules_generated.sas" lrecl=32767 mod;
  set work._char_rules end=_eof;
  length _prev_var $32 _safe_val $802;
  retain _prev_var '';

  /* Sanitize raw_value for display in comment:
     - bytes outside 0x20-0x7E become <non-ascii>
     - */ becomes * / to prevent comment breakout */
  _safe_val = '';
  do _i_byte = 1 to length(raw_value);
    _c = substr(raw_value, _i_byte, 1);
    if rank(_c) >= 32 and rank(_c) <= 126 then
      _safe_val = cats(_safe_val, _c);
    else
      _safe_val = cats(_safe_val, '<non-ascii>');
  end;
  _safe_val = tranwrd(_safe_val, '*/', '* /');

  /* Open a new select block when the variable changes */
  if variable ne _prev_var then do;
    if _prev_var ne '' then do;
      put "  otherwise;";
      put "end;";
      put " ";
    end;
    put "/* variable: " variable +(-1) " */";
    put "select (%hexkey(" variable +(-1) "));";
    _prev_var = variable;
  end;

  /* Write the when clause for this rule */
  put "  when ('" raw_hex +(-1) "') call missing(" variable +(-1) ");  /* "
      _safe_val +(-1) " -- " rule_source +(-1) " */";

  /* Close the last block at end of file */
  if _eof then do;
    put "  otherwise;";
    put "end;";
    put " ";
  end;
run;
%end;

/* Write numeric rules (currently none per PCM-D-24; future-proof branch).
   Format: if var = value and not missing(var) then call missing(var); */
%if &n_num_vars > 0 %then %do;
data _null_;
  file "&qc_path.\24_recode_rules_generated.sas" lrecl=32767 mod;
  set work._num_rules end=_eof;
  length _nval $50;
  _nval = strip(raw_value);
  put "/* numeric: " variable +(-1) " -- " rule_source +(-1) " */";
  put "if " variable +(-1) " = " _nval +(-1)
      " and not missing(" variable +(-1) ") then call missing(" variable +(-1) ");";
run;
%end;

%put NOTE: [24] wrote qc/24_recode_rules_generated.sas;


/* ===== SECTION 3: apply rules -- work._recoded (Plan 24-02) ===== */

data work._recoded;
  set g.master_data_harmonized;
  %include "&qc_path.\24_recode_rules_generated.sas";
run;

/* ---- Row count gate: must agree with source AND equal 41,150 before parallel-set compare ---- */
/* (RESEARCH.md Pitfall 4: parallel SET silently truncates to the shorter dataset)              */
proc sql noprint;
  select count(*) into :n_recoded_rows trimmed from work._recoded;
  select count(*) into :n_src_rows     trimmed from g.master_data_harmonized;
quit;

%macro _s3_rowcount_gate;
  %if &n_recoded_rows ne &n_src_rows %then %do;
    %fail_out(msg=work._recoded row count &n_recoded_rows ne source &n_src_rows);
  %end;
  %if &n_recoded_rows ne 41150 %then %do;
    %fail_out(msg=work._recoded row count &n_recoded_rows ne expected 41150);
  %end;
%mend _s3_rowcount_gate;
%_s3_rowcount_gate;

%put NOTE: [24] SECTION 3 row count OK -- n_recoded_rows=&n_recoded_rows;

/* ---- Compute n_recode_step_changes: sum(nmiss_after - nmiss_before) over recoded columns ---- */
/* Drive column list from work._recode_rules so it stays in sync with generated file.           */
/* Two PROC SQL passes (one per dataset) build comma-separated nmiss() expressions; a third     */
/* pass computes the delta and sums across columns.                                             */

/* Step 1: get distinct list of columns that have rules (any var_type) */
proc sql noprint;
  select distinct variable
  into  :_recode_vars separated by ' '
  from  work._recode_rules;
  select count(distinct variable) into :_n_recode_vars trimmed
  from  work._recode_rules;
quit;

/* Step 2: build nmiss() expression lists -- each column: nmiss(col) */
%macro _s3_build_nmiss_exprs;
  %local _i _col;
  %let _src_expr  = ;
  %let _rec_expr  = ;
  %do _i = 1 %to &_n_recode_vars;
    %let _col = %scan(&_recode_vars, &_i, %str( ));
    %if &_i = 1 %then %do;
      %let _src_expr = nmiss(&_col);
      %let _rec_expr = nmiss(&_col);
    %end;
    %else %do;
      %let _src_expr = &_src_expr + nmiss(&_col);
      %let _rec_expr = &_rec_expr + nmiss(&_col);
    %end;
  %end;

  /* Query source nmiss total */
  proc sql noprint;
    select &_src_expr into :_nmiss_src trimmed
    from g.master_data_harmonized;
  quit;

  /* Query recoded nmiss total */
  proc sql noprint;
    select &_rec_expr into :_nmiss_rec trimmed
    from work._recoded;
  quit;

  /* Delta = new missings introduced by recode step */
  %let n_recode_step_changes = %eval(&_nmiss_rec - &_nmiss_src);
%mend _s3_build_nmiss_exprs;
%_s3_build_nmiss_exprs;

%put NOTE: [24] recode-step changes = &n_recode_step_changes;


/* ===== SECTION 4: full comparison -- work._compare_out (Plan 24-02) ===== */

/* ---- Step 4a: build column metadata macros from dictionary.columns ---- */
/* (Pitfall 2: char and numeric CANNOT share one array -- build separate lists)  */
/* column names ordered by varnum to guarantee positional alignment              */

proc sql noprint;
  /* Space-separated char column names (ordered by varnum) */
  select name
  into  :char_cols separated by ' '
  from  dictionary.columns
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED' and type = 'char'
  order by varnum;
  select count(*) into :n_char trimmed
  from  dictionary.columns
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED' and type = 'char';

  /* Space-separated numeric column names (ordered by varnum) */
  select name
  into  :num_cols separated by ' '
  from  dictionary.columns
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED' and type = 'num'
  order by varnum;
  select count(*) into :n_num trimmed
  from  dictionary.columns
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED' and type = 'num';
quit;

%put NOTE: [24] SECTION 4 -- n_char=&n_char char cols, n_num=&n_num num cols;

/* ---- Step 4b: build positional rename list and recoded array name lists ---- */
/* Rename i-th char col -> _rc<i> (e.g. _rc1, _rc2, ...), j-th num -> _rn<i>  */
/* Suffixing (<name>_r) is not possible: ten source names are already 32 chars  */

%macro _s4_build_rename_lists;
  %local _i _col _rec_rename _char_cols_r _num_cols_r;
  %let _rec_rename   = ;
  %let _char_cols_r  = ;
  %let _num_cols_r   = ;

  /* Char columns */
  %do _i = 1 %to &n_char;
    %let _col = %scan(&char_cols, &_i, %str( ));
    %let _rec_rename  = &_rec_rename &_col=_rc&_i;
    %let _char_cols_r = &_char_cols_r _rc&_i;
  %end;

  /* Numeric columns */
  %do _i = 1 %to &n_num;
    %let _col = %scan(&num_cols, &_i, %str( ));
    %let _rec_rename  = &_rec_rename &_col=_rn&_i;
    %let _num_cols_r  = &_num_cols_r _rn&_i;
  %end;

  %global rec_rename_list char_cols_r num_cols_r;
  %let rec_rename_list = &_rec_rename;
  %let char_cols_r     = &_char_cols_r;
  %let num_cols_r      = &_num_cols_r;
%mend _s4_build_rename_lists;
%_s4_build_rename_lists;

/* ---- Step 4c: parallel-set comparison DATA step ---- */
/* keep= limits work._compare_out to five working columns only                  */
/* Authorization: recoded cell must be missing (otherwise unauthorized)         */
/* Hash authorization lookup (variable,raw_hex) against work._recode_rules      */
/* is done post-step via PROC SQL join (cleaner than hash object in DATA step)  */

data work._compare_out (keep=_n_row _chg_var _raw_value _raw_hex _authorized);
  set g.master_data_harmonized;                           /* source, by position */
  set work._recoded (rename=(&rec_rename_list));          /* recoded, positional _rc/_rn names */
  length _chg_var $32 _raw_value $400 _raw_hex $800;
  array _src_c{*} $ &char_cols;
  array _rec_c{*} $ &char_cols_r;
  array _src_n{*}   &num_cols;
  array _rec_n{*}   &num_cols_r;
  _n_row = _n_;

  /* ---- char columns ---- */
  do _i = 1 to dim(_src_c);
    if _src_c{_i} ne _rec_c{_i} then do;
      _authorized = (missing(_rec_c{_i}));    /* recoded cell must be missing */
      _chg_var    = vname(_src_c{_i});
      _raw_value  = _src_c{_i};
      _raw_hex    = %hexkey(_src_c{_i});
      output;
    end;
  end;

  /* ---- numeric columns ---- */
  do _j = 1 to dim(_src_n);
    if _src_n{_j} ne _rec_n{_j} then do;
      _authorized = (missing(_rec_n{_j}));
      _chg_var    = vname(_src_n{_j});
      _raw_value  = strip(put(_src_n{_j}, best32.));
      _raw_hex    = %hexkey(strip(put(_src_n{_j}, best32.)));
      output;
    end;
  end;

  drop _i _j;
run;

/* ---- Step 4d: authorization check -- join compare_out to recode_rules ---- */
/* Unauthorized = compare row where _authorized=0                              */
/*              OR (_chg_var,_raw_hex) absent from work._recode_rules          */

proc sql noprint;
  /* Count of compare rows */
  select count(*) into :n_compare_changes trimmed
  from work._compare_out;

  /* Count unauthorized rows */
  select count(*) into :n_unauth trimmed
  from work._compare_out c
  where c._authorized = 0
     or not exists (
         select 1 from work._recode_rules r
         where r.variable = c._chg_var
           and r.raw_hex  = c._raw_hex
     );
quit;

%macro _s4_unauth_gate;
  %if &n_unauth > 0 %then %do;
    %fail_out(msg=&n_unauth unauthorized cell changes found in work._compare_out);
  %end;
%mend _s4_unauth_gate;
%_s4_unauth_gate;

%put NOTE: [24] authorization check -- n_unauth=&n_unauth;

/* ---- Step 4e: Cross-check 1: compare-step count must equal recode-step count ---- */

%macro _s4_crosscheck1;
  %if &n_compare_changes ne &n_recode_step_changes %then %do;
    %fail_out(msg=Cross-check 1 failed -- n_compare_changes=&n_compare_changes ne n_recode_step_changes=&n_recode_step_changes);
  %end;
%mend _s4_crosscheck1;
%_s4_crosscheck1;

%put NOTE: [24] Cross-check 1 passed -- n_compare_changes=&n_compare_changes matches recode-step count;

/* ---- Step 4f: Cross-check 2: per-rule actual count must equal n_expected ---- */
/* n_expected comes from qc/23_sentinel_candidates.csv (loaded into work._recode_rules) */
/* This catches source drift that slipped past the fingerprint check               */

proc sql noprint;
  create table work._rule_drift_check as
  select r.variable, r.raw_hex, r.n_expected,
         coalesce(a.n_actual, 0) as n_actual
  from work._recode_rules r
       left join (
           select _chg_var as variable, _raw_hex as raw_hex, count(*) as n_actual
           from work._compare_out
           group by _chg_var, _raw_hex
       ) a on a.variable = r.variable
           and a.raw_hex  = r.raw_hex
  where a.n_actual ne r.n_expected
     or (a.variable is null and r.n_expected ne 0);

  select count(*) into :n_drift trimmed
  from work._rule_drift_check;
quit;

%macro _s4_crosscheck2;
  %if &n_drift > 0 %then %do;
    %fail_out(msg=Cross-check 2 failed -- &n_drift rules have actual count ne n_expected (source drift or rule mismatch));
  %end;
%mend _s4_crosscheck2;
%_s4_crosscheck2;

%put NOTE: [24] comparison OK -- &n_compare_changes authorized changes;


/* ===== SECTION 5: rename + label + drop -- work.pcnr_harmonized (Plan 24-02) ===== */
/* Stub: Plan 24-02 fills this section.
   data work.pcnr_harmonized;
     set work._recoded (drop=<DROP-role> rename=(<KEEP renames>));
     %include "&qc_path.\24_label_stmts_generated.sas";
   run;
*/


/* ===== SECTION 6: WORK-then-promote -- g.pcnr_harmonized (Plan 24-02) ===== */
/* Stub: Plan 24-02 fills this section.
   data g.pcnr_harmonized;
     set work.pcnr_harmonized;
   run;
*/


/* ===== SECTION 7: write recode counts CSVs (Plan 24-02) ===== */
/* Stub: Plan 24-02 fills this section.
   Outputs: qc/24_pcnr_recode_counts.csv  (detail: one row per rule)
            qc/24_pcnr_recode_totals.csv  (per-variable total)
*/


/* ===== SECTION 8: PCNR-11 assertions (Plan 24-02) ===== */
/* Stub: Plan 24-02 fills this section.
   Assertions: 41,150 rows; key identity; column count = source;
   missing math; full comparison; zero remaining sentinels;
   type/length unchanged; source confirmed unchanged.
*/

%put NOTE: ==== Program 24 pcnr_build SECTIONS 0-4 complete ====;
%restore_log;
