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

  /* cur_nobs/cur_nvar/cur_modate are re-used by SECTION 8 Check 7. PROC SQL INTO inside a
     macro creates LOCAL variables, which would vanish when this macro ends -- declare global. */
  %global cur_nobs cur_nvar cur_modate;
  %local fp_nobs fp_nvars fp_modate;

  /* ---- Check 1: Gate flag ---- */
  %if &PCNR_APPROVED ne 1 %then %do;
    %fail_out(msg=PCNR_APPROVED is not 1 -- gate closed. Set PCNR_APPROVED=1 in 00_config.sas after reviewing gate files.);
  %end;
  %put NOTE: [24] Check 1 passed -- PCNR_APPROVED=&PCNR_APPROVED;

  /* ---- Check 2: Fingerprint -- read file and compare against dictionary.tables ----
     Program 23 writes ONE line of blank-separated key=value tokens:
       nobs=41150 nvars=175 modate=28SEP2026:11:28:22
     Split on blanks, then on '=' (modate contains colons but no '='). Key is NVARS, not NVAR. */
  data work._fingerprint_raw;
    infile "&qc_path.\23_sentinel_fingerprint.txt" truncover lrecl=200;
    length _tok $80 field $20 value $40;
    input;
    do _k = 1 to countw(_infile_, ' ');
      _tok  = scan(_infile_, _k, ' ');
      field = upcase(scan(_tok, 1, '='));
      value = strip(scan(_tok, 2, '='));
      output;
    end;
    keep field value;
  run;

  proc sql noprint;
    select value into :fp_nobs   trimmed from work._fingerprint_raw where field = 'NOBS';
    select value into :fp_nvars  trimmed from work._fingerprint_raw where field = 'NVARS';
    select value into :fp_modate trimmed from work._fingerprint_raw where field = 'MODATE';

    /* Check that g.master_data_harmonized exists before querying its attributes */
    select count(*) into :n_harm_tab trimmed
    from dictionary.tables
    where libname='G' and memname='MASTER_DATA_HARMONIZED';
  quit;

  %if %length(&fp_nobs) = 0 or %length(&fp_nvars) = 0 or %length(&fp_modate) = 0 %then %do;
    %fail_out(msg=Fingerprint file unreadable -- expected nobs/nvars/modate tokens in 23_sentinel_fingerprint.txt);
  %end;

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
  %if &cur_nvar ne &fp_nvars %then %do;
    %fail_out(msg=Fingerprint mismatch: nvars -- expected &fp_nvars got &cur_nvar);
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
  quit;
  %let n_dup_dec = %eval(&n_dup_pv + &n_dup_wc);

  %if &n_dup_dec > 0 %then %do;
    %fail_out(msg=Duplicate decision check failed -- &n_dup_pv duplicate per-variable keys and &n_dup_wc duplicate wildcard keys);
  %end;
  %put NOTE: [24] Check 11 passed -- no duplicate decision keys;

  /* ---- Check 12: Name-map integrity -- fail at the cause, not later at the
     SECTION 5 column count ---- */
  proc sql noprint;
    create table work._src_cols as
    select upcase(name) as uname
    from dictionary.columns
    where libname='G' and memname='MASTER_DATA_HARMONIZED';

    select count(*) into :n_nm_badrole trimmed
    from work._name_map where role not in ('KEEP','KEY','DROP');

    select count(*) into :n_nm_dupsrc trimmed
    from (select upcase(source_name) as u from work._name_map
          group by calculated u having count(*) > 1);

    select count(*) into :n_nm_nosrc trimmed           /* map row with no source column */
    from work._name_map m
    where upcase(m.source_name) not in (select uname from work._src_cols);

    select count(*) into :n_nm_unmapped trimmed        /* source column with no map row */
    from work._src_cols s
    where s.uname not in (select upcase(source_name) from work._name_map);

    select count(*) into :n_nm_badkeep trimmed         /* KEEP name blank, too long, or invalid */
    from work._name_map
    where role = 'KEEP'
      and (missing(final_name) or length(final_name) > 32 or nvalid(final_name, 'v7') = 0);

    select count(*) into :n_nm_dupout trimmed          /* two output columns with one name */
    from (select upcase(coalescec(final_name, source_name)) as o from work._name_map
          where role in ('KEEP','KEY')
          group by calculated o having count(*) > 1);
  quit;
  %let n_nm_bad = %eval(&n_nm_badrole + &n_nm_dupsrc + &n_nm_nosrc + &n_nm_unmapped
                        + &n_nm_badkeep + &n_nm_dupout);

  %if &n_nm_bad > 0 %then %do;
    %fail_out(msg=Name-map check failed -- badrole=&n_nm_badrole dupsrc=&n_nm_dupsrc nosrc=&n_nm_nosrc unmapped=&n_nm_unmapped badkeep=&n_nm_badkeep dupout=&n_nm_dupout);
  %end;
  %put NOTE: [24] Check 12 passed -- name map complete and consistent;

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
   - raw_value in comment is display-only: the comment terminator is broken up with a
     space and non-ASCII bytes are replaced
   - Numeric rules (if any) use: if var = value and not missing(var) then call missing(var);
*/

/* Write header block as a single-row data step.
   SINGLE quotes on every PUT literal in this section: the macro processor scans
   double-quoted strings, so "%include..." / "%hexkey(" inside double quotes would be
   treated as macro calls when THIS step compiles, not written as text. */
data _null_;
  file "&qc_path.\24_recode_rules_generated.sas" lrecl=32767;
  put '/* qc/24_recode_rules_generated.sas';
  put '   Machine-generated by sas/24_pcnr_build.sas SECTION 2.';
  put '   Do not edit -- re-run program 24 to regenerate.';
  put '   This file is included inside a DATA step (no options/run/include here). */';
  put ' ';
run;

/* Write char select/when blocks: sequential read, detect variable break by retained _prev_var.
   work._char_rules is sorted by variable, raw_hex so all rules for a column are contiguous. */
%macro _s2_write_char_rules;
%if &n_char_vars > 0 %then %do;
data _null_;
  file "&qc_path.\24_recode_rules_generated.sas" lrecl=32767 mod;
  set work._char_rules end=_eof;
  length _prev_var $32 _safe_val $802;
  retain _prev_var '';

  /* Sanitize raw_value for display in comment:
     - bytes outside 0x20-0x7E become ~ (cats() was dropping embedded blanks:
       PATIENT REFUSED became PATIENTREFUSED)
     - the comment terminator is broken up with a space to prevent breakout */
  _safe_val = prxchange('s/[^\x20-\x7E]/~/', -1, strip(raw_value));
  _safe_val = tranwrd(_safe_val, '*/', '* /');

  /* Open a new select block when the variable changes */
  if variable ne _prev_var then do;
    if _prev_var ne '' then do;
      put '  otherwise;';
      put 'end;';
      put ' ';
    end;
    put '/* variable: ' variable +(-1) ' */';
    put 'select (%hexkey(' variable +(-1) '));';
    _prev_var = variable;
  end;

  /* Write the when clause for this rule */
  put "  when ('" raw_hex +(-1) "') call missing(" variable +(-1) ');  /* '
      _safe_val +(-1) ' -- ' rule_source +(-1) ' */';

  /* Close the last block at end of file */
  if _eof then do;
    put '  otherwise;';
    put 'end;';
    put ' ';
  end;
run;
%end;
%mend _s2_write_char_rules;
%_s2_write_char_rules;

/* Write numeric rules (currently none per PCM-D-24; future-proof branch).
   Format: if var = value and not missing(var) then call missing(var); */
%macro _s2_write_num_rules;
%if &n_num_vars > 0 %then %do;
data _null_;
  file "&qc_path.\24_recode_rules_generated.sas" lrecl=32767 mod;
  set work._num_rules end=_eof;
  length _nval $50;
  _nval = strip(raw_value);
  put '/* numeric: ' variable +(-1) ' -- ' rule_source +(-1) ' */';
  put 'if ' variable +(-1) ' = ' _nval +(-1)
      ' and not missing(' variable +(-1) ') then call missing(' variable +(-1) ');';
run;
%end;
%mend _s2_write_num_rules;
%_s2_write_num_rules;

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
  %global n_recode_step_changes;
  %if &_n_recode_vars = 0 %then %do;     /* no MISSING rules: nothing to count */
    %let n_recode_step_changes = 0;
    %return;
  %end;
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


/* ===== SECTION 5: rename + label + drop -- work.pcnr_harmonized (Plan 24-03 Task 1) ===== */

/* Build rename_list and drop_list from work._name_map (already loaded in SECTION 0).
   Do NOT read pcnr_name_map.csv a second time.
   rename_list: source_name=final_name for role=KEEP (space-separated)
   drop_list:   source_name for role=DROP (space-separated)
*/
%let drop_list = ;     /* stays blank if the name map has no DROP rows */
proc sql noprint;
  select catx('=', source_name, final_name)
  into  :rename_list separated by ' '
  from  work._name_map
  where role = 'KEEP';

  select source_name
  into  :drop_list separated by ' '
  from  work._name_map
  where role = 'DROP';
quit;

%put NOTE: [24] SECTION 5 -- rename_list and drop_list built from work._name_map;

/* Write label statements to a generated file.
   Single-quoted values: &/% inside a label would resolve if double-quoted.
   Embedded apostrophes are doubled via tranwrd.
   KEY rows: final_name is blank -- use coalescec(final_name, source_name) for output name.
   Blank source_label rows: set label = original source_name (PCNR-09). */
data _null_;
  file "&qc_path.\24_label_stmts_generated.sas" lrecl=32767;
  set work._name_map (where=(role in ('KEEP','KEY')));
  length _out $32 _lab $256 _q $600;
  _out = coalescec(final_name, source_name);      /* KEY final_name is blank */
  _lab = coalescec(source_label, source_name);    /* blank label -> original name */
  /* Single-quote the label text; double any embedded apostrophes */
  _q = cats("'", tranwrd(strip(_lab), "'", "''"), "'");
  put 'label ' _out +(-1) ' = ' _q +(-1) ';';
run;

%put NOTE: [24] SECTION 5 -- label statements written to qc/24_label_stmts_generated.sas;

/* One DATA step: drop DROP columns, rename KEEP columns, apply labels.
   Key columns keep original names (final_name blank -> not in rename_list).
   Formats travel with the variable automatically via SET -- do not strip. */
data work.pcnr_harmonized;
  set work._recoded (%sysfunc(ifc(%length(&drop_list), drop = &drop_list, ))
                     rename = (&rename_list));
  %include "&qc_path.\24_label_stmts_generated.sas";
run;

/* ---- Assert 5a: column count = 163 (159 KEEP + 4 KEY) ---- */
proc sql noprint;
  select count(*) into :n_pcnr_cols trimmed
  from dictionary.columns
  where libname = 'WORK' and memname = 'PCNR_HARMONIZED';
quit;

%macro _s5_colcount_gate;
  %if &n_pcnr_cols ne 163 %then %do;
    %fail_out(msg=SECTION 5 column count assertion failed -- work.pcnr_harmonized has &n_pcnr_cols cols, expected 163);
  %end;
%mend _s5_colcount_gate;
%_s5_colcount_gate;

%put NOTE: [24] SECTION 5 -- column count OK (&n_pcnr_cols cols);

/* ---- Assert 5b: variable set equals KEY source_names + KEEP final_names exactly ---- */
/* Expected names: KEY rows -> source_name; KEEP rows -> final_name */
proc sql noprint;
  /* Count names in expected set that are absent from work.pcnr_harmonized (missing) */
  create table work._s5_expected as
  select upcase(coalescec(final_name, source_name)) as expected_name
  from work._name_map
  where role in ('KEEP','KEY');

  create table work._s5_actual as
  select upcase(name) as actual_name
  from dictionary.columns
  where libname = 'WORK' and memname = 'PCNR_HARMONIZED';

  select count(*) into :n_expected_missing trimmed
  from work._s5_expected e
  where not exists (
      select 1 from work._s5_actual a
      where a.actual_name = e.expected_name
  );

  select count(*) into :n_extra trimmed
  from work._s5_actual a
  where not exists (
      select 1 from work._s5_expected e
      where e.expected_name = a.actual_name
  );

quit;
%let n_name_mismatch = %eval(&n_expected_missing + &n_extra);

%macro _s5_nameset_gate;
  %if &n_name_mismatch > 0 %then %do;
    %fail_out(msg=SECTION 5 variable-set assertion failed -- &n_expected_missing expected names missing and &n_extra extra names in work.pcnr_harmonized);
  %end;
%mend _s5_nameset_gate;
%_s5_nameset_gate;

%put NOTE: [24] SECTION 5 -- variable set OK (no extra or missing names);

/* ---- Assert 5c: type and length of every output column = source column ---- */
/* Map output column back to source via name map; compare type/length. */
proc sql noprint;
  create table work._s5_typelen_check as
  select m.source_name, coalescec(m.final_name, m.source_name) as out_name,
         src.type as src_type, src.length as src_len,
         out.type as out_type, out.length as out_len
  from work._name_map m
       inner join (
           select name, type, length
           from dictionary.columns
           where libname='G' and memname='MASTER_DATA_HARMONIZED'
       ) src on upcase(src.name) = upcase(m.source_name)
       inner join (
           select name, type, length
           from dictionary.columns
           where libname='WORK' and memname='PCNR_HARMONIZED'
       ) out on upcase(out.name) = upcase(coalescec(m.final_name, m.source_name))
  where m.role in ('KEEP','KEY')
    and (src.type ne out.type or src.length ne out.length);

  select count(*) into :n_typelen_mismatch trimmed
  from work._s5_typelen_check;

  /* The inner joins above drop any column whose name fails to match, which would let the
     check pass vacuously. Require every KEEP/KEY row to match on both sides. */
  select count(*) into :n_typelen_matched trimmed
  from work._name_map m
       inner join dictionary.columns src
         on src.libname='G' and src.memname='MASTER_DATA_HARMONIZED'
        and upcase(src.name) = upcase(m.source_name)
       inner join dictionary.columns out
         on out.libname='WORK' and out.memname='PCNR_HARMONIZED'
        and upcase(out.name) = upcase(coalescec(m.final_name, m.source_name))
  where m.role in ('KEEP','KEY');
quit;
%let n_typelen_mismatch = %eval(&n_typelen_mismatch + (&n_typelen_matched ne 163));

%macro _s5_typelen_gate;
  %if &n_typelen_mismatch > 0 %then %do;
    %fail_out(msg=SECTION 5 type/length assertion failed -- &n_typelen_mismatch columns have type or length change in work.pcnr_harmonized);
  %end;
%mend _s5_typelen_gate;
%_s5_typelen_gate;

%put NOTE: [24] SECTION 5 -- type/length unchanged for all output columns;


/* ===== SECTION 6: WORK-then-promote -- g.pcnr_harmonized (Plan 24-03 Task 1) ===== */

data g.pcnr_harmonized;
  set work.pcnr_harmonized;
run;

%put NOTE: [24] promoted g.pcnr_harmonized (163 cols, 41150 rows);


/* ===== SECTION 7: write recode counts CSVs (Plan 24-03 Task 2) ===== */

/* ---- Build detail dataset: left-join _recode_rules to per-rule actual counts + final_name ---- */
/* n_recoded = actual rows changed for that (variable, raw_hex); 0 for zero-hit rules */
proc sql;
  create table work._recode_counts_detail as
  select r.variable,
         coalescec(m.final_name, r.variable) as final_name length=32,
         r.raw_value,
         r.raw_hex,
         r.var_type,
         r.rule_source,
         r.n_expected,
         coalesce(a.n_recoded, 0) as n_recoded
  from work._recode_rules r
       left join (
           select _chg_var as variable, _raw_hex as raw_hex, count(*) as n_recoded
           from work._compare_out
           group by _chg_var, _raw_hex
       ) a on a.variable = r.variable
           and a.raw_hex  = r.raw_hex
       left join work._name_map m on m.source_name = r.variable
  order by r.variable, r.raw_hex;
quit;

/* Write detail CSV: header first (no dsd), then data rows (dsd for quoting/trimming) */
data _null_;
  file "&qc_path.\24_pcnr_recode_counts.csv" lrecl=32767;
  put "variable,final_name,raw_value,raw_hex,var_type,rule_source,n_expected,n_recoded";
run;

data _null_;
  file "&qc_path.\24_pcnr_recode_counts.csv" dsd mod lrecl=32767;
  set work._recode_counts_detail;
  put variable final_name raw_value raw_hex var_type rule_source n_expected n_recoded;
run;

%put NOTE: [24] wrote qc/24_pcnr_recode_counts.csv;

/* ---- Build totals dataset: one row per KEEP and KEY column ---- */
/* Sum n_recoded from detail (0 for columns with no MISSING rules) */
proc sql;
  create table work._recode_totals as
  select m.source_name as variable,
         coalescec(m.final_name, m.source_name) as final_name length=32,
         coalesce(t.n_recoded_total, 0) as n_recoded_total
  from work._name_map m
       left join (
           select variable, sum(n_recoded) as n_recoded_total
           from work._recode_counts_detail
           group by variable
       ) t on t.variable = m.source_name
  where m.role in ('KEEP','KEY')
  order by m.source_name;
quit;

/* Write totals CSV: header first, then data rows */
data _null_;
  file "&qc_path.\24_pcnr_recode_totals.csv" lrecl=32767;
  put "variable,final_name,n_recoded_total";
run;

data _null_;
  file "&qc_path.\24_pcnr_recode_totals.csv" dsd mod lrecl=32767;
  set work._recode_totals;
  put variable final_name n_recoded_total;
run;

%put NOTE: [24] wrote qc/24_pcnr_recode_totals.csv;


/* ===== SECTION 8: PCNR-11 assertion suite (Plan 24-03 Task 2) ===== */

/* ---- Check 1: Row count = 41,150 ---- */
proc sql noprint;
  select count(*) into :n_pcnr_rows trimmed
  from g.pcnr_harmonized;
quit;

%macro _s8_rowcount;
  %if &n_pcnr_rows ne 41150 %then %do;
    %fail_out(msg=PCNR-11 Check 1 FAILED -- g.pcnr_harmonized has &n_pcnr_rows rows, expected 41150);
  %end;
%mend _s8_rowcount;
%_s8_rowcount;

%put NOTE: [24] PCNR-11 Check 1 -- row count OK (&n_pcnr_rows rows);

/* ---- Check 2: Key identity -- PRECEDE_STUDY_ID unique and set-identical; pecan_ID row-identical ---- */
proc sql noprint;
  /* PRECEDE_STUDY_ID: distinct count in output = distinct count in source */
  select count(distinct PRECEDE_STUDY_ID) into :n_sid_out trimmed
  from g.pcnr_harmonized;

  select count(distinct PRECEDE_STUDY_ID) into :n_sid_src trimmed
  from g.master_data_harmonized;

  /* Set differences both ways. EXCEPT de-duplicates and sorts once; the correlated
     NOT EXISTS it replaces compared 41,150 x 41,150 rows per direction. */
  select count(*) into :n_sid_anti1 trimmed
  from (select PRECEDE_STUDY_ID from g.pcnr_harmonized
        except
        select PRECEDE_STUDY_ID from g.master_data_harmonized);

  select count(*) into :n_sid_anti2 trimmed
  from (select PRECEDE_STUDY_ID from g.master_data_harmonized
        except
        select PRECEDE_STUDY_ID from g.pcnr_harmonized);

  /* PCNR-11: PRECEDE_STUDY_ID unique -- one non-missing ID per row */
  select count(*) into :n_sid_missing trimmed
  from g.pcnr_harmonized where PRECEDE_STUDY_ID is missing;
quit;

%macro _s8_key_identity;
  %if &n_sid_out ne &n_sid_src %then %do;
    %fail_out(msg=PCNR-11 Check 2 FAILED -- PRECEDE_STUDY_ID distinct count mismatch: output=&n_sid_out source=&n_sid_src);
  %end;
  %if &n_sid_anti1 ne 0 or &n_sid_anti2 ne 0 %then %do;
    %fail_out(msg=PCNR-11 Check 2 FAILED -- PRECEDE_STUDY_ID set mismatch: anti1=&n_sid_anti1 anti2=&n_sid_anti2);
  %end;
  %if &n_sid_out ne &n_pcnr_rows or &n_sid_missing ne 0 %then %do;
    %fail_out(msg=PCNR-11 Check 2 FAILED -- PRECEDE_STUDY_ID not unique: distinct=&n_sid_out rows=&n_pcnr_rows missing=&n_sid_missing);
  %end;
%mend _s8_key_identity;
%_s8_key_identity;

%put NOTE: [24] PCNR-11 Check 2a -- PRECEDE_STUDY_ID set-identical (distinct=&n_sid_out);

/* pecan_ID: row-by-row identical (parallel SET comparison; row counts already asserted equal) */
data work._s8_pid_diffs;
  set g.master_data_harmonized (keep=pecan_ID);
  set g.pcnr_harmonized        (keep=pecan_ID rename=(pecan_ID=pecan_ID_out));
  if pecan_ID ne pecan_ID_out;
run;

proc sql noprint;
  select count(*) into :n_pid_diffs trimmed from work._s8_pid_diffs;
quit;

%macro _s8_pecanid_check;
  %if &n_pid_diffs ne 0 %then %do;
    %fail_out(msg=PCNR-11 Check 2b FAILED -- &n_pid_diffs pecan_ID row mismatches between source and output);
  %end;
%mend _s8_pecanid_check;
%_s8_pecanid_check;

%put NOTE: [24] PCNR-11 Check 2b -- pecan_ID row-identical (diffs=&n_pid_diffs);

/* ---- Check 3: Column count = 163 (= 175 source - 12 DROP) ---- */
proc sql noprint;
  select count(*) into :n_pcnr_colcount trimmed
  from dictionary.columns
  where libname='G' and memname='PCNR_HARMONIZED';
quit;

%macro _s8_colcount;
  %if &n_pcnr_colcount ne 163 %then %do;
    %fail_out(msg=PCNR-11 Check 3 FAILED -- g.pcnr_harmonized has &n_pcnr_colcount cols, expected 163);
  %end;
%mend _s8_colcount;
%_s8_colcount;

%put NOTE: [24] PCNR-11 Check 3 -- column count OK (&n_pcnr_colcount cols);

/* ---- Check 4: Missing math per variable ---- */
/* For every KEEP column: nmiss(final) = nmiss(source) + n_recoded_total */
/* Build comparison dataset: nmiss before (from source), nmiss after (from output), n_recoded_total */

/* nmiss before: query source for each KEEP column source_name */
/* nmiss after:  query output for each KEEP column final_name */
/* We loop by writing a dataset of variable pairs and joining. Use PROC SQL with a
   generated expression list approach: build arrays via a generated DATA step approach. */

/* Step 1: build nmiss expressions for source (source_name) and output (final_name) for KEEP columns */
proc sql noprint;
  select source_name
  into  :_keep_src_names separated by ' '
  from  work._name_map where role='KEEP';

  select coalescec(final_name, source_name)
  into  :_keep_out_names separated by ' '
  from  work._name_map where role='KEEP';

  select count(*) into :_n_keep trimmed
  from  work._name_map where role='KEEP';
quit;

/* Steps 2-4: one pass over each dataset. %local and %do are illegal in open code
   (PCM-T-15), so all of this lives in a named macro. Each dataset is read once with
   arrays: cmiss() counts missing for both char and numeric. */
%macro _s8_build_mmcheck;
  %local _i _src _out;

  /* nmiss per KEEP column in the source -> one row per column */
  data work._s8_nm_src (keep=_pos nmiss_src);
    set g.master_data_harmonized (keep=&_keep_src_names) end=_eof;
    array _m{&_n_keep} _temporary_ (&_n_keep*0);
    %do _i = 1 %to &_n_keep;
      %let _src = %scan(&_keep_src_names, &_i, %str( ));
      _m{&_i} = _m{&_i} + cmiss(&_src);
    %end;
    if _eof then do _pos = 1 to &_n_keep;
      nmiss_src = _m{_pos};
      output;
    end;
  run;

  /* nmiss per KEEP column in the output */
  data work._s8_nm_out (keep=_pos nmiss_out);
    set g.pcnr_harmonized (keep=&_keep_out_names) end=_eof;
    array _m{&_n_keep} _temporary_ (&_n_keep*0);
    %do _i = 1 %to &_n_keep;
      %let _out = %scan(&_keep_out_names, &_i, %str( ));
      _m{&_i} = _m{&_i} + cmiss(&_out);
    %end;
    if _eof then do _pos = 1 to &_n_keep;
      nmiss_out = _m{_pos};
      output;
    end;
  run;

  /* names by position */
  data work._s8_names;
    length variable $32 final_name $32;
    %do _i = 1 %to &_n_keep;
      _pos = &_i;
      variable   = "%scan(&_keep_src_names, &_i, %str( ))";
      final_name = "%scan(&_keep_out_names, &_i, %str( ))";
      output;
    %end;
  run;

  data work._s8_mmcheck;
    merge work._s8_names work._s8_nm_src work._s8_nm_out;
    by _pos;
  run;
%mend _s8_build_mmcheck;
%_s8_build_mmcheck;

proc sql noprint;
  create table work._s8_mmviolations as
  select m.variable, m.final_name,
         m.nmiss_src, m.nmiss_out,
         coalesce(t.n_recoded_total, 0) as n_recoded_total,
         m.nmiss_out - m.nmiss_src as delta,
         (m.nmiss_out - m.nmiss_src) as delta_actual,
         coalesce(t.n_recoded_total, 0) as delta_expected
  from work._s8_mmcheck m
       left join work._recode_totals t on t.variable = m.variable
  where (m.nmiss_out - m.nmiss_src) ne coalesce(t.n_recoded_total, 0);

  select count(*) into :n_mm_violations trimmed
  from work._s8_mmviolations;
quit;

%macro _s8_missing_math;
  %if &n_mm_violations > 0 %then %do;
    %fail_out(msg=PCNR-11 Check 4 FAILED -- &n_mm_violations KEEP columns fail missing-math: nmiss_after ne nmiss_before plus n_recoded);
  %end;
%mend _s8_missing_math;
%_s8_missing_math;

%put NOTE: [24] PCNR-11 Check 4 -- missing math OK for all &_n_keep KEEP columns;

/* ---- Check 5: Zero remaining sentinels in output ---- */
/* For every MISSING rule, count cells in g.pcnr_harmonized (mapped to final_name)
   whose %hexkey(value) equals the rule raw_hex. Total across all rules must = 0. */

/* Build list of distinct (final_name, raw_hex) pairs from recode rules */
proc sql noprint;
  select count(*) into :_n_sentinel_rules trimmed
  from work._recode_counts_detail;
quit;

/* Load each rule row's final_name, raw_hex, var_type into indexed macro variables */
data _null_;
  set work._recode_counts_detail;
  call symputx(cats('_sent_fn_', _n_), final_name, 'G');
  call symputx(cats('_sent_rh_', _n_), raw_hex,    'G');
  call symputx(cats('_sent_vt_', _n_), var_type,   'G');
run;

%macro _s8_zero_sentinels;
  %local _i _fn _rh _vt _cnt _total;
  %let _total = 0;
  %do _i = 1 %to &_n_sentinel_rules;     /* from PROC SQL count: 0 when no rules */
    %let _fn = &&_sent_fn_&_i;
    %let _rh = &&_sent_rh_&_i;
    %let _vt = &&_sent_vt_&_i;
    proc sql noprint;
      %if &_vt = char %then %do;
        select count(*) into :_cnt trimmed
        from g.pcnr_harmonized
        where %hexkey(&_fn) = "&_rh";
      %end;
      %else %do;
        /* numeric: sentinel was set to missing; any non-missing value that hex-encodes to raw_hex */
        select count(*) into :_cnt trimmed
        from g.pcnr_harmonized
        where not missing(&_fn) and %hexkey(strip(put(&_fn, best32.))) = "&_rh";
      %end;
    quit;
    %let _total = %eval(&_total + &_cnt);
  %end;
  %if &_total > 0 %then %do;
    %fail_out(msg=PCNR-11 Check 5 FAILED -- &_total remaining sentinel values found in g.pcnr_harmonized after recode);
  %end;
%mend _s8_zero_sentinels;
%_s8_zero_sentinels;

%put NOTE: [24] PCNR-11 Check 5 -- zero remaining sentinels confirmed;

/* ---- Check 6: Type and length unchanged ---- */
/* Re-assert from dictionary.columns (same check as SECTION 5c, but on g.pcnr_harmonized) */
proc sql noprint;
  create table work._s8_typelen_check2 as
  select m.source_name, coalescec(m.final_name, m.source_name) as out_name,
         src.type as src_type, src.length as src_len,
         out.type as out_type, out.length as out_len
  from work._name_map m
       inner join (
           select name, type, length
           from dictionary.columns
           where libname='G' and memname='MASTER_DATA_HARMONIZED'
       ) src on upcase(src.name) = upcase(m.source_name)
       inner join (
           select name, type, length
           from dictionary.columns
           where libname='G' and memname='PCNR_HARMONIZED'
       ) out on upcase(out.name) = upcase(coalescec(m.final_name, m.source_name))
  where m.role in ('KEEP','KEY')
    and (src.type ne out.type or src.length ne out.length);

  select count(*) into :n_typelen2 trimmed
  from work._s8_typelen_check2;
quit;

%macro _s8_typelen;
  %if &n_typelen2 > 0 %then %do;
    %fail_out(msg=PCNR-11 Check 6 FAILED -- &n_typelen2 columns have type or length change in g.pcnr_harmonized);
  %end;
%mend _s8_typelen;
%_s8_typelen;

%put NOTE: [24] PCNR-11 Check 6 -- type/length unchanged for all output columns;

/* ---- Check 7: Source unchanged -- compare to SECTION 0 fingerprint values ---- */
/* Re-query dictionary.tables for g.master_data_harmonized nobs, nvar, modate */
proc sql noprint;
  select strip(put(nobs,  best32.))        into :post_nobs   trimmed
  from dictionary.tables where libname='G' and memname='MASTER_DATA_HARMONIZED';
  select strip(put(nvar,  best32.))        into :post_nvar   trimmed
  from dictionary.tables where libname='G' and memname='MASTER_DATA_HARMONIZED';
  select strip(put(modate, datetime20.))   into :post_modate trimmed
  from dictionary.tables where libname='G' and memname='MASTER_DATA_HARMONIZED';
quit;

%macro _s8_source_unchanged;
  %if &post_nobs ne &cur_nobs %then %do;
    %fail_out(msg=PCNR-11 Check 7 FAILED -- g.master_data_harmonized nobs changed: was &cur_nobs now &post_nobs);
  %end;
  %if &post_nvar ne &cur_nvar %then %do;
    %fail_out(msg=PCNR-11 Check 7 FAILED -- g.master_data_harmonized nvar changed: was &cur_nvar now &post_nvar);
  %end;
  %if &post_modate ne &cur_modate %then %do;
    %fail_out(msg=PCNR-11 Check 7 FAILED -- g.master_data_harmonized modate changed: was &cur_modate now &post_modate);
  %end;
%mend _s8_source_unchanged;
%_s8_source_unchanged;

%put NOTE: [24] PCNR-11 Check 7 -- g.master_data_harmonized unchanged (nobs=&post_nobs nvar=&post_nvar);

%put NOTE: [24] PCNR-11 PASS -- all assertions cleared;

%put NOTE: ==== Program 24 pcnr_build complete ====;
%restore_log;
