/*==========================================================================
  Program : 23_pcnr_inventory.sas
  Phase   : 23 -- Sentinel & Name Inventory
  Purpose : Sweep every column of g.master_data_harmonized for sentinel
            (placeholder / missing-indicator) values, produce a case-variant
            report, and write three qc/ evidence files. Does NOT modify any
            source dataset.

  THIS PROGRAM DECIDES NOTHING AND CHANGES NOTHING IN SOURCE DATA.
  All output goes to qc/ only (structural prohibition -- see static check).

  Plans implemented
    Plan 01 (this file):
      SECTION 0: Preconditions in %check_preconditions
      SECTION 1: Fingerprint (qc/23_sentinel_fingerprint.txt)
      SECTION 2: Character sentinel sweep (work.candidates, char rows)
      SECTION 3: Numeric sentinel scan (appended to work.candidates)
      SECTION 4: Ambiguous reclassification + write qc/23_sentinel_candidates.csv
      SECTION 5: Case/whitespace variant report (qc/23_case_variants.csv)

  Reads   : g.master_data_harmonized   (read-only, never modified)
            docs/concept_decisions.csv (to confirm cols readable)
  Writes  : qc/23_sentinel_fingerprint.txt
            qc/23_sentinel_candidates.csv
            qc/23_case_variants.csv

  Static check (must pass before commit):
    grep -ni "docs" sas/23_pcnr_inventory.sas
    -- must show only the concept_decisions.csv readable check and comment lines;
       no filename/file=/ods file= pointing at docs/
    grep -c '$hex\.' sas/23_pcnr_inventory.sas  (expect 0 -- only %hexkey used)
    grep -ni "proc import" sas/23_pcnr_inventory.sas  (expect 0)
    grep -ni "%put WARNING" sas/23_pcnr_inventory.sas  (expect 0)

  PCM compliance:
    - No bare open-code %IF (every %if inside a %macro...%mend)
    - No %put WARNING (scanner fails on WARNING lines) -- use %put NOTE:
    - No PROC IMPORT for gate files (PCM-T-16)
    - No bare $hex. format (truncates to 2 bytes) -- only %hexkey macro
    - No semicolons or apostrophes in %put text (PCM-T-14)
    - IS NOT MISSING only in PROC SQL; NOT MISSING() in DATA step
    - No &SQLOBS; use SELECT COUNT(*) INTO :macvar TRIMMED

  Author  : Phase 23 Plan 01
==========================================================================*/

options mprint nofmterr nodate nonumber ps=max ls=200;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* ---- Column lists (PCM-D-27) -- hardcoded in program header -----------
   If a raw name is absent from g.master_data_harmonized but its h_ survivor
   is present, the POST-h_-STRIP RULE (review item 5) substitutes h_name.
   Resolution happens in SECTION 2 via dictionary.columns lookup.
   -----------------------------------------------------------------------*/

/* DEMOGRAPHIC columns -- UNKNOWN treated AMBIGUOUS (not AUTO) in these */
%let demog_cols_raw = Race Ethnicity Sex Marital_Status Education
                      EmployeeStatus Patient_Type Payer;

/* SCORE / count columns -- numeric 0 treated AMBIGUOUS in these */
%let score_cols_raw = Feels_Exausted_Value Low_Physical_Activity_Value
                      Slow_Walking_Speed_Value Unintended_Weight_Loss_Value
                      Week_Grip_Strength_Value Braden_Activity Braden_Mobility
                      Braden_Sensory_Perception Charlson_Comorbidity_Index
                      Cognitive_Score Frailty_Score
                      COMP10_T80 COMP10_T81 COMP10_T82 COMP10_T83 COMP10_T84
                      COMP10_T85 COMP10_T86 COMP10_T87 COMP10_T88
                      complication_sum ABP_LESS_THAN_60_COUNT
                      ABP_LESS_THAN_70_COUNT ABP_LESS_THAN_80_COUNT
                      BIS_INDEX_LESS_30_COUNT BIS_INDEX_LESS_40_COUNT
                      NIBP_LESS_60_COUNT NIBP_LESS_70_COUNT NIBP_LESS_80_COUNT;

/* FREE-TEXT columns -- excluded from the CONTAINS (REVIEW) sweep only.
   Still swept by exact-match AUTO rule.
   EXPLICIT exclusion list -- NOT a length heuristic (per CONTEXT.md). */
%let freetext_cols = Base_Procedure_1;

/* NOTE: Admit_Source, Dischg_Disposition, Anesthesia_Type, and all
   CPT/ICD *_Description/*_Label columns are categorical/vocabulary and
   are NOT in freetext_cols -- they need REVIEW coverage. Only
   Base_Procedure_1 (encoding-damaged free text, PCM-F-10) is excluded. */

/* ---- Log routing ---- */
%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\23_pcnr_inventory.log" new;
    run;
  %end;
%mend route_log;

%macro restore_log;
  %if &in_pipeline = 0 %then %do;
    proc printto;
    run;
  %end;
%mend restore_log;

%macro fail_out(msg=);
  %put ERROR: &msg;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;

%route_log;
libname g "&g_path";

%put NOTE: ==== Phase 23 Sentinel Inventory starting ====;


/* =========================================================================
   SECTION 0: Preconditions (all %if inside macro -- PCM-T-15)
   ========================================================================= */

%macro check_preconditions;
  /* --- 0a. g.master_data_harmonized must exist ---- */
  %local _nobs _nvar;
  proc sql noprint;
    select count(*) into :_tbl_exists trimmed
    from sashelp.vtable
    where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED';
  quit;
  %if &_tbl_exists = 0 %then
    %fail_out(msg=23 -- g.master_data_harmonized not found in library G);

  /* --- 0b. Row count must equal 41150 ---- */
  proc sql noprint;
    select nobs into :_nobs trimmed
    from sashelp.vtable
    where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED';
  quit;
  %if &_nobs ne 41150 %then
    %fail_out(msg=23 -- g.master_data_harmonized not 41150 rows -- found &_nobs);

  /* --- 0c. docs/concept_decisions.csv must be readable ---- */
  %local _cdec_path _cdec_exists;
  %let _cdec_path = &docs_path.\concept_decisions.csv;
  %let _cdec_exists = %sysfunc(fileexist(&_cdec_path));
  %if &_cdec_exists = 0 %then
    %fail_out(msg=23 -- docs/concept_decisions.csv not found at &_cdec_path);

  /* --- 0d. Max char column length must be <= 200 (%hexkey uses $hex400.) ---- */
  proc sql noprint;
    select max(length) into :_maxlen trimmed
    from dictionary.columns
    where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED'
      and type = 'char';
  quit;
  %if %eval(&_maxlen > 200) %then
    %fail_out(msg=23 -- max char column length &_maxlen exceeds 200 -- hexkey($hex400.) would truncate keys);

  %put NOTE: [23] Preconditions passed -- nobs=&_nobs maxcharlen=&_maxlen;
%mend check_preconditions;
%check_preconditions;


/* =========================================================================
   SECTION 1: Fingerprint
   Write nobs, nvars, modate to qc/23_sentinel_fingerprint.txt
   ========================================================================= */

proc sql noprint;
  select put(nobs, 20. -L),
         put(nvar, 8. -L),
         put(modate, datetime20.)
  into :fp_nobs trimmed,
       :fp_nvars trimmed,
       :fp_modate trimmed
  from sashelp.vtable
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED';
quit;

%put NOTE: [23] Fingerprint -- nobs=&fp_nobs nvars=&fp_nvars modate=&fp_modate;

data _null_;
  file "&qc_path.\23_sentinel_fingerprint.txt";
  put "nobs=&fp_nobs nvars=&fp_nvars modate=&fp_modate";
run;

%put NOTE: [23] Fingerprint written to qc/23_sentinel_fingerprint.txt;


/* =========================================================================
   SECTION 2: POST-h_-STRIP RULE -- resolve demog_cols and score_cols
   For each listed name: if absent from dataset but h_<name> present,
   substitute h_<name>. Emit NOTE for any that resolve to neither form.
   ========================================================================= */

/* --- Build a lookup of all column names in g.master_data_harmonized ---- */
proc sql noprint;
  create table work._colnames as
  select upcase(name) as uname, name, type, length
  from dictionary.columns
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED';
quit;

/* --- Resolve demog_cols ---- */
%macro resolve_collist(rawlist=, outmvar=, listlabel=);
  %local _i _raw _upper _test_h _resolved _final_list;
  %let _final_list = ;
  %let _i = 1;
  %do %while(%scan(&rawlist, &_i, %str( )) ne %str());
    %let _raw = %scan(&rawlist, &_i, %str( ));
    %let _upper = %upcase(&_raw);
    %let _test_h = H_&_upper;

    /* Check raw name in dataset */
    proc sql noprint;
      select count(*) into :_found_raw trimmed
      from work._colnames
      where uname = "&_upper";
    quit;

    %if &_found_raw > 0 %then %do;
      %let _resolved = &_raw;
    %end;
    %else %do;
      /* Check h_ survivor */
      proc sql noprint;
        select count(*) into :_found_h trimmed
        from work._colnames
        where uname = "&_test_h";
      quit;
      %if &_found_h > 0 %then %do;
        %let _resolved = h_&_raw;
        %put NOTE: [23] &listlabel member &_raw resolved to h_ survivor h_&_raw;
      %end;
      %else %do;
        %let _resolved = ;
        %put NOTE: [23] &listlabel member &_raw not found in g.master_data_harmonized (neither &_raw nor h_&_raw);
      %end;
    %end;

    %if &_resolved ne %str() %then
      %let _final_list = &_final_list &_resolved;

    %let _i = %eval(&_i + 1);
  %end;
  %global &outmvar;
  %let &outmvar = &_final_list;
  %put NOTE: [23] &listlabel resolved list -- &outmvar;
%mend resolve_collist;

%resolve_collist(rawlist=&demog_cols_raw, outmvar=demog_cols, listlabel=DEMOG);
%resolve_collist(rawlist=&score_cols_raw, outmvar=score_cols, listlabel=SCORE);


/* =========================================================================
   SECTION 2 (cont): Character sentinel sweep (PCNR-01, D-01)
   Single-pass DATA step with array _c(*) _character_
   ========================================================================= */

/* --- Get char var list and count from dictionary.columns ---- */
proc sql noprint;
  select name into :charlist separated by ' '
  from dictionary.columns
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED'
    and type = 'char'
  order by name;
  select count(*) into :ncharvars trimmed
  from dictionary.columns
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED'
    and type = 'char';
quit;

%put NOTE: [23] Character columns to sweep -- &ncharvars;

/* --- Single-pass DATA step: emit one row per (variable, raw_value) observation ---- */
data work._char_raw;
  length variable     $32
         raw_value    $200
         raw_hex      $400
         raw_len      8
         normalized_value $200
         var_type     $4
         non_ascii_flag 8
         column_group $20
         ;
  set g.master_data_harmonized (keep=&charlist);

  array _c(*) _character_;

  do _i = 1 to dim(_c);
    if not missing(_c(_i)) then do;
      variable = vname(_c(_i));
      raw_value = _c(_i);

      /* Hex key -- full-value, length-trimmed (no bare $hex.) */
      raw_len  = length(raw_value);
      raw_hex  = %hexkey(raw_value);

      /* Non-ASCII detection (bytes outside printable 20x-7Ex range) */
      non_ascii_flag = (verify(raw_value,
        '20202020202020202020202020202020202020202020202020202020202020202020202020202020'x
        /* safer: use the complement form below */
        ) > 0);
      /* Recompute correctly: any byte < 20x or > 7Ex */
      non_ascii_flag = 0;
      do _b = 1 to raw_len;
        if rank(substr(raw_value, _b, 1)) < 32 or
           rank(substr(raw_value, _b, 1)) > 126 then do;
          non_ascii_flag = 1;
          leave;
        end;
      end;

      /* Normalized value -- upcase + strip + compbl, with control-char tokens */
      normalized_value = compbl(strip(upcase(raw_value)));

      /* Control-character substitutions (before match rules) */
      if raw_value = '09'x then normalized_value = '<TAB>';
      else if raw_value in ('0D0A'x, '0D'x, '0A'x) then normalized_value = '<CRLF>';
      else if raw_value = 'A0'x then normalized_value = '<NBSP>';

      /* column_group from hardcoded lists */
      column_group = '';
      /* DEMOGRAPHIC check (upcase compare against resolved demog_cols) */
      if indexw(upcase("&demog_cols"), upcase(variable)) > 0 then
        column_group = 'DEMOGRAPHIC';
      else if indexw(upcase("&score_cols"), upcase(variable)) > 0 then
        column_group = 'SCORE';

      var_type = 'char';

      output;
    end;
  end;

  drop _i _b;
  keep variable raw_value raw_hex raw_len normalized_value var_type
       non_ascii_flag column_group;
run;

%put NOTE: [23] Raw char observations extracted;

/* --- Group by (variable, raw_hex) to get n_rows and pct_rows ---- */
proc sql noprint;
  select count(*) into :_totalrows trimmed
  from g.master_data_harmonized;
quit;

proc sql noprint;
  create table work._char_freq as
  select variable,
         min(raw_value)      as raw_value     length=200,
         raw_hex,
         min(raw_len)        as raw_len,
         min(normalized_value) as normalized_value length=200,
         min(var_type)       as var_type       length=4,
         count(*)            as n_rows,
         count(*) / &_totalrows * 100 as pct_rows format=8.4,
         min(column_group)   as column_group   length=20,
         min(non_ascii_flag) as non_ascii_flag_min,
         max(non_ascii_flag) as non_ascii_flag
  from work._char_raw
  group by variable, raw_hex;
quit;

/* --- Apply candidate_class classification ---- */
data work._char_candidates;
  set work._char_freq;
  length candidate_class $10 match_rule $20 role $4;

  /* Temporary: freetext check for CONTAINS exclusion */
  length _isft 8;
  _isft = (indexw(upcase("&freetext_cols"), upcase(variable)) > 0);

  /* AUTO: exact match on normalized_value */
  if normalized_value in ('?', '??', '-', '--', '.', 'UNKNOWN', 'UNK',
     'N/A', 'NA', 'NULL', 'MISSING', 'NOT DOCUMENTED', 'NOT RECORDED',
     '<TAB>', '<CRLF>', '<NBSP>') then do;
    candidate_class = 'AUTO';
    match_rule = 'EXACT';
  end;
  /* REVIEW: contains sentinel fragment (exclude freetext columns) */
  else if _isft = 0 and
     (index(normalized_value, 'UNKNOWN')     > 0 or
      index(normalized_value, 'NOT DOCUMENTED') > 0 or
      index(normalized_value, 'NOT RECORDED')  > 0 or
      index(normalized_value, 'MISSING')     > 0 or
      index(normalized_value, 'NOT APPLICABLE') > 0 or
      index(normalized_value, 'N/A')         > 0 or
      index(normalized_value, 'OTHER')       > 0 or
      index(normalized_value, 'NONE')        > 0 or
      index(normalized_value, 'DECLINED')    > 0 or
      index(normalized_value, 'REFUSED')     > 0 or
      index(normalized_value, 'NOT ASSESSED') > 0 or
      index(normalized_value, 'NOT PERFORMED') > 0 or
      index(normalized_value, 'UNABLE TO OBTAIN') > 0 or
      index(normalized_value, 'NOT SPECIFIED') > 0 or
      index(normalized_value, 'PENDING')     > 0) then do;
    candidate_class = 'REVIEW';
    match_rule = 'CONTAINS';
  end;

  /* role blank at Plan 01 -- Plan 02 SECTION 6 backfills from name map */
  role = '';

  /* Keep output columns in interfaces order */
  keep variable raw_value raw_hex raw_len normalized_value var_type
       n_rows pct_rows column_group candidate_class non_ascii_flag
       match_rule role;

  drop _isft non_ascii_flag_min;
run;

/* Keep only rows that have a classification (AUTO or REVIEW at this stage) */
data work._char_candidates;
  set work._char_candidates;
  if candidate_class in ('AUTO', 'REVIEW');
run;

%put NOTE: [23] Character candidate classification complete;


/* =========================================================================
   SECTION 3: Numeric sentinel scan (PCNR-02, D-03)
   Single-pass DATA step with array _n(*) _numeric_
   Sentinel values: -999 -99 -9 99 999 777 888 9999 99999
   IS NOT MISSING guard; candidate_class = REVIEW (never AUTO for numeric)
   ========================================================================= */

/* Get numeric var list */
proc sql noprint;
  select name into :numlist separated by ' '
  from dictionary.columns
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED'
    and type = 'num'
  order by name;
  select count(*) into :nnumvars trimmed
  from dictionary.columns
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED'
    and type = 'num';
quit;

%put NOTE: [23] Numeric columns to scan -- &nnumvars;

/* Single-pass: emit one row per matching (variable, sentinel value) observation */
data work._num_raw;
  length variable $32 raw_value_num 8;
  set g.master_data_harmonized (keep=&numlist);

  array _n(*) _numeric_;

  do _i = 1 to dim(_n);
    if not missing(_n(_i)) then do;
      if _n(_i) in (-999, -99, -9, 99, 999, 777, 888, 9999, 99999) then do;
        variable = vname(_n(_i));
        raw_value_num = _n(_i);
        output;
      end;
    end;
  end;

  drop _i;
  keep variable raw_value_num;
run;

/* Group by (variable, raw_value_num) for counts */
proc sql noprint;
  create table work._num_freq as
  select variable,
         raw_value_num,
         count(*) as n_rows,
         count(*) / &_totalrows * 100 as pct_rows format=8.4
  from work._num_raw
  group by variable, raw_value_num;
quit;

/* Build numeric candidate rows matching the candidates schema */
data work._num_candidates;
  set work._num_freq;
  length raw_value $200 raw_hex $400 raw_len 8
         normalized_value $200 var_type $4
         non_ascii_flag 8 column_group $20
         candidate_class $10 match_rule $20 role $4;

  var_type        = 'num';
  raw_value       = strip(put(raw_value_num, best32.));
  raw_hex         = %hexkey(strip(put(raw_value_num, best32.)));
  raw_len         = length(raw_value);
  normalized_value = raw_value;
  non_ascii_flag  = 0;

  /* column_group from score list */
  column_group = '';
  if indexw(upcase("&score_cols"), upcase(variable)) > 0 then
    column_group = 'SCORE';
  else if indexw(upcase("&demog_cols"), upcase(variable)) > 0 then
    column_group = 'DEMOGRAPHIC';

  /* Numeric sentinels always REVIEW -- D-03: never auto-classify numeric */
  candidate_class = 'REVIEW';
  match_rule      = 'NUMERIC_SENTINEL';
  role            = '';

  keep variable raw_value raw_hex raw_len normalized_value var_type
       n_rows pct_rows column_group candidate_class non_ascii_flag
       match_rule role;
  drop raw_value_num;
run;

%put NOTE: [23] Numeric sentinel scan complete;

/* Combine char and numeric candidates */
data work.candidates;
  set work._char_candidates
      work._num_candidates;
run;

%put NOTE: [23] Combined candidates dataset built;


/* =========================================================================
   SECTION 4: Ambiguous reclassification + write qc/23_sentinel_candidates.csv
   ========================================================================= */

/* --- 4a. Reclassify AMBIGUOUS char values (normalized match) ---- */
data work.candidates;
  set work.candidates;

  /* Base AMBIGUOUS list (all char columns) */
  if var_type = 'char' then do;
    if normalized_value in ('NONE', 'NOT APPLICABLE', 'DECLINED', 'REFUSED',
       'OTHER', 'NOT ASSESSED', 'NOT PERFORMED', 'PENDING',
       'UNABLE TO OBTAIN', 'NOT SPECIFIED', 'PATIENT DECLINED') then do;
      candidate_class = 'AMBIGUOUS';
      match_rule = 'AMBIGUOUS_BASE';
    end;
    /* UNKNOWN in DEMOGRAPHIC columns -> AMBIGUOUS (overrides AUTO for those cols) */
    else if normalized_value = 'UNKNOWN' and
            indexw(upcase("&demog_cols"), upcase(variable)) > 0 then do;
      candidate_class = 'AMBIGUOUS';
      match_rule = 'AMBIGUOUS_DEMOG';
    end;
  end;
run;

/* --- 4b. Numeric 0 in score_cols -> AMBIGUOUS ---- */
/* Get numeric members of score_cols present in dataset */
proc sql noprint;
  create table work._score_num_cols as
  select name
  from dictionary.columns
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED'
    and type = 'num'
    and indexw(upcase("&score_cols"), upcase(name)) > 0;
  select count(*) into :n_score_num trimmed
  from work._score_num_cols;
quit;

%put NOTE: [23] Numeric score columns for zero-AMBIGUOUS scan -- &n_score_num;

%macro scan_score_zeros;
  %if &n_score_num > 0 %then %do;
    /* Get list of numeric score columns */
    proc sql noprint;
      select name into :score_num_list separated by ' '
      from work._score_num_cols;
    quit;

    /* Single-pass for 0 values in numeric score columns */
    data work._score_zero_raw;
      length variable $32;
      set g.master_data_harmonized (keep=&score_num_list);
      array _sn(*) &score_num_list;
      do _i = 1 to dim(_sn);
        if not missing(_sn(_i)) and _sn(_i) = 0 then do;
          variable = vname(_sn(_i));
          output;
        end;
      end;
      drop _i;
      keep variable;
    run;

    proc sql noprint;
      create table work._score_zero_freq as
      select variable,
             count(*) as n_rows,
             count(*) / &_totalrows * 100 as pct_rows format=8.4
      from work._score_zero_raw
      group by variable;
    quit;

    data work._score_zero_cands;
      set work._score_zero_freq;
      length raw_value $200 raw_hex $400 raw_len 8
             normalized_value $200 var_type $4
             non_ascii_flag 8 column_group $20
             candidate_class $10 match_rule $20 role $4;
      var_type         = 'num';
      raw_value        = '0';
      raw_hex          = %hexkey('0');
      raw_len          = 1;
      normalized_value = '0';
      non_ascii_flag   = 0;
      column_group     = 'SCORE';
      candidate_class  = 'AMBIGUOUS';
      match_rule       = 'AMBIGUOUS_SCORE_ZERO';
      role             = '';
      keep variable raw_value raw_hex raw_len normalized_value var_type
           n_rows pct_rows column_group candidate_class non_ascii_flag
           match_rule role;
    run;

    /* Append score-zero AMBIGUOUS rows to candidates */
    proc append base=work.candidates data=work._score_zero_cands force; run;
  %end;
%mend scan_score_zeros;
%scan_score_zeros;

/* --- 4c. Assert uniqueness on (variable, raw_hex) ---- */
%macro assert_unique_candidates;
  proc sql noprint;
    select count(*) into :_dup_count trimmed
    from (
      select variable, raw_hex, count(*) as cnt
      from work.candidates
      group by variable, raw_hex
      having count(*) > 1
    );
  quit;
  %if &_dup_count > 0 %then
    %fail_out(msg=23 -- work.candidates has &_dup_count duplicate (variable raw_hex) combinations -- check AMBIGUOUS reclassification);
  %put NOTE: [23] Uniqueness assertion passed -- no duplicate (variable raw_hex) combinations;
%mend assert_unique_candidates;
%assert_unique_candidates;

/* --- 4d. Sort: AMBIGUOUS first, then REVIEW, then AUTO; tiebreak variable, raw_value ---- */
proc sort data=work.candidates;
  by
    /* Manual sort key: AMBIGUOUS=1, REVIEW=2, AUTO=3 */
    descending candidate_class  /* A < R; AMBIGUOUS sorts last alpha -- use custom key */
    variable
    raw_value;
run;

/* Custom sort: create numeric sort key */
data work.candidates;
  set work.candidates;
  length _sort_key 8;
  if candidate_class = 'AMBIGUOUS' then _sort_key = 1;
  else if candidate_class = 'REVIEW'    then _sort_key = 2;
  else if candidate_class = 'AUTO'      then _sort_key = 3;
  else _sort_key = 9;
run;

proc sort data=work.candidates;
  by _sort_key variable raw_value;
run;

data work.candidates;
  set work.candidates;
  drop _sort_key;
run;

/* --- 4e. Write qc/23_sentinel_candidates.csv ---- */
/* Column order from interfaces spec:
   variable, raw_value, raw_hex, raw_len, normalized_value, var_type, n_rows, pct_rows,
   column_group, candidate_class, non_ascii_flag, match_rule, role */

data _null_;
  file "&qc_path.\23_sentinel_candidates.csv" dsd lrecl=32767;
  /* Header */
  put 'variable,raw_value,raw_hex,raw_len,normalized_value,var_type,n_rows,pct_rows,'
      'column_group,candidate_class,non_ascii_flag,match_rule,role';
run;

data _null_;
  set work.candidates;
  file "&qc_path.\23_sentinel_candidates.csv" dsd lrecl=32767 mod;
  put variable raw_value raw_hex raw_len normalized_value var_type
      n_rows pct_rows column_group candidate_class non_ascii_flag
      match_rule role;
run;

%put NOTE: [23] qc/23_sentinel_candidates.csv written;


/* =========================================================================
   SECTION 5: Case/whitespace variant report (PCNR-04)
   Group distinct char values by normalized form; report normalized forms
   with 2+ distinct raw spellings.
   ========================================================================= */

/* Build value frequency table from the full char sweep (all non-missing values) */
proc sql noprint;
  create table work._char_all_vals as
  select variable,
         raw_value,
         normalized_value,
         count(*) as n_rows
  from work._char_raw
  group by variable, raw_value, normalized_value;
quit;

/* Find normalized forms with 2+ distinct raw_value spellings per variable */
proc sql noprint;
  create table work._case_variant_norm as
  select variable, normalized_value,
         count(distinct raw_value) as n_spellings
  from work._char_all_vals
  group by variable, normalized_value
  having count(distinct raw_value) > 1;
quit;

/* Get all rows for those variable+normalized combinations */
proc sql noprint;
  create table work._case_variants as
  select a.variable, a.normalized_value, a.raw_value, a.n_rows
  from work._char_all_vals a
  inner join work._case_variant_norm b
    on a.variable = b.variable
    and a.normalized_value = b.normalized_value
  order by a.variable, a.normalized_value, a.n_rows desc, a.raw_value;
quit;

/* Write qc/23_case_variants.csv */
data _null_;
  file "&qc_path.\23_case_variants.csv" dsd lrecl=32767;
  put 'variable,normalized_value,raw_value,n_rows';
run;

data _null_;
  set work._case_variants;
  file "&qc_path.\23_case_variants.csv" dsd lrecl=32767 mod;
  put variable normalized_value raw_value n_rows;
run;

%put NOTE: [23] qc/23_case_variants.csv written;

/* Summary counts for log */
proc sql noprint;
  select count(*) into :_n_auto trimmed
  from work.candidates where candidate_class = 'AUTO';
  select count(*) into :_n_review trimmed
  from work.candidates where candidate_class = 'REVIEW';
  select count(*) into :_n_ambig trimmed
  from work.candidates where candidate_class = 'AMBIGUOUS';
  select count(*) into :_n_variants trimmed
  from work._case_variant_norm;
quit;

%put NOTE: [23] Candidate summary -- AUTO=&_n_auto REVIEW=&_n_review AMBIGUOUS=&_n_ambig;
%put NOTE: [23] Case variant normalized forms with 2+ spellings -- &_n_variants;

/* =========================================================================
   SECTION 6: Name-map draft (PCNR-05, PCM-D-05, PCM-D-23)
   Builds a row for every column of g.master_data_harmonized:
     role = KEY  for the four join keys (final_name blank)
     role = DROP for raw columns superseded by an h_* version (final_name blank)
     role = KEEP for everything else (gets pcnr_ prefix + truncation)
   Writes qc/23_pcnr_name_map_DRAFT.csv.
   Backfills role into qc/23_sentinel_candidates.csv.
   ========================================================================= */

/* --- 6a. Get all columns from dictionary.columns ---- */
proc sql noprint;
  create table work._all_cols as
  select name        as source_name length=32,
         label       as source_label length=256,
         type,
         length      as col_length
  from dictionary.columns
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED'
  order by source_name;
  select count(*) into :_total_cols trimmed
  from work._all_cols;
quit;

%put NOTE: [23] Total columns in g.master_data_harmonized -- &_total_cols;

/* --- 6b. Read concept_decisions.csv to identify DROP candidates
          (raw columns superseded by an h_* harmonized version)
          PCM-T-16: DATA step infile, NOT PROC IMPORT                ---- */

data work._cdec_raw;
  length concept $40 varname $32 value_txt $200 n_rows $20
         target_value $200 confirmed $3 harmonized_name $40
         priority $5 reviewer $40 comment $500;
  infile "&docs_path.\concept_decisions.csv"
    dsd firstobs=2 truncover lrecl=32767;
  input concept        : $40.
        varname        : $32.
        value_txt      : $200.
        n_rows         : $20.
        target_value   : $200.
        confirmed      : $3.
        harmonized_name : $40.
        priority       : $5.
        reviewer       : $40.
        comment        : $500.
        ;
run;

/* Extract distinct varname -> harmonized_name pairs where harmonized_name starts h_ */
proc sql noprint;
  create table work._drop_props as
  select distinct upcase(varname) as uvarname length=32,
                  varname         as raw_varname length=32,
                  harmonized_name
  from work._cdec_raw
  where upcase(strip(substr(harmonized_name,1,2))) = 'H_';
quit;

/* Check: for every DROP candidate varname, verify it exists in the dataset.
   If not found, emit NOTE (review item 7). Emit NOTE, NEVER WARNING. */
%macro check_drop_sources;
  %local _i _vn _found_cnt;
  proc sql noprint;
    select count(*) into :_ndrop trimmed from work._drop_props;
  quit;
  %do _i = 1 %to &_ndrop;
    proc sql noprint;
      select raw_varname into :_vn trimmed
      from work._drop_props(firstobs=&_i obs=&_i);
      select count(*) into :_found_cnt trimmed
      from work._all_cols
      where upcase(source_name) = upcase("&_vn");
    quit;
    %if &_found_cnt = 0 %then %do;
      %put NOTE: [23] DROP proposal source name &_vn not found in g.master_data_harmonized;
    %end;
  %end;
%mend check_drop_sources;
%check_drop_sources;

/* --- 6c. Assign role and compute proposed_name with truncation (PCM-D-23) ---- */

/* KEY columns (exact match, case-insensitive) */
%let key_cols = pecan_ID PRECEDE_STUDY_ID ENCRYPTED_MRN ENCRYPTED_ENCOUNTER;

data work._name_map_draft;
  length source_name $32 source_label $256
         role $4 h_strip $1
         proposed_name $32 override_name $32 final_name $32
         name_len 8 collision_flag 8 id_flag 8
         /* work variables */
         _stripped_name $32 _pfx_test $37 _ft $32 _head $32
         _ft_len 8 _head_budget 8 _head_trimmed $32
         _uname $32;

  set work._all_cols;

  _uname = upcase(source_name);

  /* --- Assign role ---- */
  /* KEY check */
  if indexw(upcase("&key_cols"), _uname) > 0 then do;
    role = 'KEY';
    h_strip = 'N';
    proposed_name = '';
    override_name = '';
    final_name = '';
    name_len = 0;
  end;
  else do;
    /* DROP check: is this source name a DROP candidate from concept_decisions? */
    /* We will join to the drop_props table after this data step via PROC SQL */
    role = '';  /* placeholder; will be overwritten in PROC SQL merge below */
    h_strip = 'N';
    proposed_name = '';
    override_name = '';
    final_name = '';
    name_len = 0;
  end;

  collision_flag = 0;
  id_flag        = 0;

  keep source_name source_label role h_strip proposed_name override_name
       final_name name_len collision_flag id_flag;
run;

/* Set DROP role via merge with drop candidates */
proc sql noprint;
  create table work._name_map_roles as
  select m.source_name,
         m.source_label,
         case
           when indexw(upcase("&key_cols"), upcase(m.source_name)) > 0 then 'KEY'
           when d.uvarname is not null then 'DROP'
           else 'KEEP'
         end as role length=4,
         m.collision_flag,
         m.id_flag
  from work._name_map_draft m
  left join work._drop_props d
    on upcase(m.source_name) = d.uvarname;
quit;

/* --- 6d. Compute h_strip, proposed_name, final_name for KEEP rows ---- */

data work._name_map_work;
  length source_name $32 source_label $256
         role $4 h_strip $1
         proposed_name $32 override_name $32 final_name $32
         name_len 8 collision_flag 8 id_flag 8
         _stripped $32 _ft $32 _head $32
         _ft_len 8 _hb 8;
  set work._name_map_roles;

  h_strip = 'N';
  override_name = '';

  if role = 'KEY' then do;
    proposed_name = '';
    final_name    = '';
    name_len      = 0;
  end;
  else if role = 'DROP' then do;
    proposed_name = '';
    final_name    = '';
    name_len      = 0;
    /* h_strip for DROP rows: if the DROP raw col itself begins h_, note it */
    if upcase(substr(source_name,1,2)) = 'H_' then h_strip = 'Y';
  end;
  else do;
    /* KEEP: strip h_ if present, then apply pcnr_ + truncation */
    if upcase(substr(source_name,1,2)) = 'H_' then do;
      h_strip = 'Y';
      _stripped = substr(source_name, 3);   /* remove 'h_' */
    end;
    else do;
      h_strip = 'N';
      _stripped = source_name;
    end;

    /* Truncation algorithm (PCM-D-23) */
    /* Step 1: does pcnr_ || _stripped fit in 32? */
    if length('pcnr_' || strip(_stripped)) <= 32 then do;
      proposed_name = 'pcnr_' || strip(_stripped);
    end;
    else do;
      /* Step 2: find final_token = substring after last underscore */
      _ft = '';
      _ft_len = 0;
      /* Scan right-to-left for the last _ */
      do _j = length(strip(_stripped)) to 1 by -1;
        if substr(strip(_stripped), _j, 1) = '_' then do;
          /* final token is everything after position _j */
          _ft = substr(strip(_stripped), _j+1);
          leave;
        end;
      end;
      _ft_len = length(strip(_ft));

      /* Determine if fallback applies:
         - no underscore in name (ft remains ''), OR
         - ft_len > 12 (oversized token), OR
         - ft is empty after stripping (name ends with _)  */
      if _ft = '' or _ft_len > 12 or strip(_ft) = '' then do;
        /* FALLBACK: plain tail truncation to 32 total */
        proposed_name = substr('pcnr_' || strip(_stripped), 1, 32);
      end;
      else do;
        /* Normal truncation: pcnr_ (5) + head + _ (1) + ft */
        _hb = 32 - 5 - 1 - _ft_len;   /* head budget */
        /* head = everything before the last _ (i.e., _stripped minus trailing _ft and its _) */
        _head = substr(strip(_stripped), 1, length(strip(_stripped)) - _ft_len - 1);
        /* trim head to budget */
        if length(strip(_head)) > _hb then
          _head = substr(strip(_head), 1, _hb);
        /* strip trailing underscore from head to avoid double __ */
        do while (length(strip(_head)) > 0 and
                  substr(strip(_head), length(strip(_head)), 1) = '_');
          _head = substr(strip(_head), 1, length(strip(_head)) - 1);
        end;
        proposed_name = 'pcnr_' || strip(_head) || '_' || strip(_ft);
        /* Safety: ensure <= 32 (trailing _ strip can shorten below 32) */
        if length(proposed_name) > 32 then
          proposed_name = substr(proposed_name, 1, 32);
      end;
    end;

    /* final_name = coalesce(override_name, proposed_name) for KEEP */
    if strip(override_name) ne '' then final_name = override_name;
    else final_name = proposed_name;

    name_len = length(strip(final_name));

    /* id_flag: source name pattern matches *_ID, *STUDY_ID*, ENCRYPTED_* */
    id_flag = 0;
    if indexw(upcase("&key_cols"), upcase(source_name)) = 0 then do;
      if prxmatch('/(_ID$|STUDY_ID|^ENCRYPTED_)/i', strip(source_name)) > 0 then
        id_flag = 1;
    end;
  end;

  drop _stripped _ft _ft_len _hb _head _j;
  keep source_name source_label role h_strip proposed_name override_name
       final_name name_len collision_flag id_flag;
run;

/* --- 6e. Compute collision_flag via PROC SQL self-join (KEEP rows, case-insensitive) ---- */
proc sql noprint;
  create table work._collision as
  select upcase(strip(final_name)) as ufn,
         count(*) as n
  from work._name_map_work
  where role = 'KEEP' and strip(final_name) ne ''
  group by upcase(strip(final_name))
  having count(*) > 1;
quit;

data work._name_map_draft2;
  set work._name_map_work;
  length _ufn $32;
  _ufn = upcase(strip(final_name));
  if role = 'KEEP' and strip(final_name) ne '' then do;
    /* Check collision */
    collision_flag = 0;  /* reset; will set via merge */
  end;
  drop _ufn;
run;

proc sql noprint;
  create table work.name_map_final as
  select m.source_name,
         m.source_label,
         m.role,
         m.h_strip,
         m.proposed_name,
         m.override_name,
         m.final_name,
         m.name_len,
         case when c.ufn is not null then 1 else 0 end as collision_flag,
         m.id_flag
  from work._name_map_draft2 m
  left join work._collision c
    on upcase(strip(m.final_name)) = c.ufn
  order by m.source_name;
quit;

%put NOTE: [23] Name-map built -- total columns &_total_cols;

/* --- 6f. Backfill role into qc/23_sentinel_candidates.csv ---- */
/* Join candidates to name map on variable=source_name; rewrite CSV with role */

proc sql noprint;
  create table work._candidates_with_role as
  select c.variable, c.raw_value, c.raw_hex, c.raw_len, c.normalized_value,
         c.var_type, c.n_rows, c.pct_rows, c.column_group, c.candidate_class,
         c.non_ascii_flag, c.match_rule,
         coalesce(m.role, '') as role length=4
  from work.candidates c
  left join work.name_map_final m
    on upcase(c.variable) = upcase(m.source_name)
  order by c.variable, c.raw_value;
quit;

/* Also update work.candidates so the sort key from Section 4 is preserved */
data work.candidates;
  set work._candidates_with_role;
run;

/* Re-sort candidates (AMBIGUOUS=1, REVIEW=2, AUTO=3) */
data work.candidates;
  set work.candidates;
  length _sort_key 8;
  if candidate_class = 'AMBIGUOUS' then _sort_key = 1;
  else if candidate_class = 'REVIEW'    then _sort_key = 2;
  else if candidate_class = 'AUTO'      then _sort_key = 3;
  else _sort_key = 9;
run;
proc sort data=work.candidates; by _sort_key variable raw_value; run;
data work.candidates;
  set work.candidates;
  drop _sort_key;
run;

/* Rewrite qc/23_sentinel_candidates.csv with role populated */
data _null_;
  file "&qc_path.\23_sentinel_candidates.csv" dsd lrecl=32767;
  put 'variable,raw_value,raw_hex,raw_len,normalized_value,var_type,n_rows,pct_rows,'
      'column_group,candidate_class,non_ascii_flag,match_rule,role';
run;

data _null_;
  set work.candidates;
  file "&qc_path.\23_sentinel_candidates.csv" dsd lrecl=32767 mod;
  put variable raw_value raw_hex raw_len normalized_value var_type
      n_rows pct_rows column_group candidate_class non_ascii_flag
      match_rule role;
run;

%put NOTE: [23] qc/23_sentinel_candidates.csv rewritten with role populated;

/* --- 6g. Write qc/23_pcnr_name_map_DRAFT.csv ---- */
/* Column order per interfaces spec:
   source_name, source_label, role, h_strip, proposed_name, override_name, final_name,
   name_len, collision_flag, id_flag                                                    */

data _null_;
  file "&qc_path.\23_pcnr_name_map_DRAFT.csv" dsd lrecl=32767;
  put 'source_name,source_label,role,h_strip,proposed_name,override_name,final_name,'
      'name_len,collision_flag,id_flag';
run;

data _null_;
  set work.name_map_final;
  file "&qc_path.\23_pcnr_name_map_DRAFT.csv" dsd lrecl=32767 mod;
  put source_name source_label role h_strip proposed_name override_name
      final_name name_len collision_flag id_flag;
run;

%put NOTE: [23] qc/23_pcnr_name_map_DRAFT.csv written;

/* Summary counts for name map */
proc sql noprint;
  select count(*) into :_nm_key    trimmed from work.name_map_final where role = 'KEY';
  select count(*) into :_nm_keep   trimmed from work.name_map_final where role = 'KEEP';
  select count(*) into :_nm_drop   trimmed from work.name_map_final where role = 'DROP';
  select count(*) into :_nm_trunc  trimmed
    from work.name_map_final
    where role = 'KEEP' and proposed_name ne 'pcnr_' || strip(
      case when upcase(substr(source_name,1,2)) = 'H_'
           then substr(source_name,3)
           else source_name end);
  select count(*) into :_nm_coll   trimmed from work.name_map_final where collision_flag = 1;
  select count(*) into :_nm_idflag trimmed from work.name_map_final where id_flag = 1;
quit;

%put NOTE: [23] Name-map role counts -- KEY=&_nm_key KEEP=&_nm_keep DROP=&_nm_drop;
%put NOTE: [23] Name-map flags -- truncated=&_nm_trunc collision_flag=&_nm_coll id_flag=&_nm_idflag;


/* =========================================================================
   SECTION 7: Sentinel-decisions draft (D-04, D-06)
   One row per candidate (skip DROP-role candidates per D-08).
   Pre-fill: num rows action=KEEP; char rows action blank.
   Append wildcard rows: one per distinct AUTO normalized_value (char only).
   Writes qc/23_sentinel_decisions_DRAFT.csv.
   ========================================================================= */

/* Filter candidates: exclude DROP-role rows (D-08) */
proc sql noprint;
  create table work._decisions_base as
  select variable, raw_value, raw_hex, raw_len, normalized_value,
         var_type, n_rows, pct_rows, column_group, candidate_class,
         non_ascii_flag, match_rule, role
  from work.candidates
  where upcase(strip(role)) ne 'DROP'
  order by variable, raw_value;
quit;

/* Build decisions draft with pre-fill and blank attribution */
data work._decisions_draft;
  set work._decisions_base;
  length action $7 rationale $500 decided_by $40 decided_date $10;

  /* Pre-fill per D-06 */
  if var_type = 'num' then action = 'KEEP';
  else action = '';   /* char: blank forces human review */

  rationale    = '';
  decided_by   = '';   /* human fills this at checkpoint */
  decided_date = '';   /* human fills this at checkpoint */

  keep variable raw_value raw_hex raw_len normalized_value var_type
       n_rows pct_rows column_group candidate_class non_ascii_flag
       match_rule action rationale decided_by decided_date;
run;

/* Build wildcard rows: one per distinct AUTO normalized_value from char rows only (D-03, D-06)
   Pitfall 2 (RESEARCH): UNKNOWN is both AUTO (non-demog) and AMBIGUOUS (demog cols).
   Emit the UNKNOWN wildcard with the AMBIGUOUS coverage note in rationale.
   Gate already excludes wildcards from resolving AMBIGUOUS candidates in Phase 24.       */

proc sql noprint;
  create table work._wildcard_nvals as
  select distinct normalized_value
  from work.candidates
  where var_type = 'char' and candidate_class = 'AUTO'
  order by normalized_value;
  select count(*) into :_n_wildcards trimmed from work._wildcard_nvals;
quit;

%put NOTE: [23] Wildcard rows to emit -- &_n_wildcards;

data work._wildcard_rows;
  set work._wildcard_nvals;
  length variable $32 raw_value $200 raw_hex $400 raw_len 8
         var_type $4 n_rows 8 pct_rows 8 column_group $20
         candidate_class $10 non_ascii_flag 8 match_rule $20
         action $7 rationale $500 decided_by $40 decided_date $10;

  variable         = '*';
  raw_value        = '';
  raw_hex          = '';
  raw_len          = 0;
  /* normalized_value kept from the set statement */
  var_type         = 'char';
  n_rows           = 0;
  pct_rows         = 0;
  column_group     = '';
  candidate_class  = 'AUTO';
  non_ascii_flag   = 0;
  match_rule       = 'WILDCARD';
  action           = '';   /* human fills */
  decided_by       = '';
  decided_date     = '';

  /* Pitfall 2 (RESEARCH.md): UNKNOWN wildcard does not cover AMBIGUOUS rows in demog cols */
  if normalized_value = 'UNKNOWN' then
    rationale = 'Wildcard does not cover AMBIGUOUS rows; demographic columns need per-variable decisions';
  else
    rationale = '';

  keep variable raw_value raw_hex raw_len normalized_value var_type
       n_rows pct_rows column_group candidate_class non_ascii_flag
       match_rule action rationale decided_by decided_date;
run;

/* Combine: decisions rows first, then wildcard rows */
data work._decisions_full;
  set work._decisions_draft
      work._wildcard_rows;
run;

/* Write qc/23_sentinel_decisions_DRAFT.csv */
/* Column order per interfaces spec:
   variable, raw_value, raw_hex, raw_len, normalized_value, var_type, n_rows, pct_rows,
   column_group, candidate_class, non_ascii_flag, match_rule, action, rationale,
   decided_by, decided_date                                                              */

data _null_;
  file "&qc_path.\23_sentinel_decisions_DRAFT.csv" dsd lrecl=32767;
  put 'variable,raw_value,raw_hex,raw_len,normalized_value,var_type,n_rows,pct_rows,'
      'column_group,candidate_class,non_ascii_flag,match_rule,action,rationale,'
      'decided_by,decided_date';
run;

data _null_;
  set work._decisions_full;
  file "&qc_path.\23_sentinel_decisions_DRAFT.csv" dsd lrecl=32767 mod;
  put variable raw_value raw_hex raw_len normalized_value var_type
      n_rows pct_rows column_group candidate_class non_ascii_flag
      match_rule action rationale decided_by decided_date;
run;

%put NOTE: [23] qc/23_sentinel_decisions_DRAFT.csv written;

proc sql noprint;
  select count(*) into :_n_dec_rows trimmed from work._decisions_draft;
  select count(*) into :_n_dec_keep trimmed from work._decisions_draft where action = 'KEEP';
  select count(*) into :_n_dec_blank trimmed from work._decisions_draft where action = '';
quit;

%put NOTE: [23] Decisions draft -- candidate rows=&_n_dec_rows KEEP_prefilled=&_n_dec_keep blank_action=&_n_dec_blank wildcards=&_n_wildcards;


/* =========================================================================
   SECTION 8: Validation report
   Assertions (fail on violation except collision which is NOTE only).
   Summary NOTE counts for log review.
   ========================================================================= */

%put NOTE: [23] ==== SECTION 8: Validation ====;

/* --- 8a. max(name_len) for KEEP final_names must be <= 32 ---- */
%macro assert_name_len;
  %local _maxnl;
  proc sql noprint;
    select max(name_len) into :_maxnl trimmed
    from work.name_map_final
    where role = 'KEEP' and strip(final_name) ne '';
  quit;
  %if %eval(&_maxnl > 32) %then
    %fail_out(msg=23 SECTION 8 -- max final_name length &_maxnl exceeds 32 -- truncation bug);
  %put NOTE: [23] SECTION 8 assertion passed -- max name_len=&_maxnl (must be <=32);
%mend assert_name_len;
%assert_name_len;

/* --- 8b. collision_flag count -- NOTE only, NEVER %fail_out ---- */
/* Hard zero-collision assertion belongs in Phase 24 gate against docs/pcnr_name_map.csv.
   Program 23 drafts only; human may add override_name to resolve collisions.           */
%put NOTE: [23] SECTION 8 collision_flag count=&_nm_coll (review item -- fix via override_name in docs/pcnr_name_map.csv);

/* --- 8c. Every source column appears exactly once in the name map (completeness) ---- */
%macro assert_name_map_complete;
  %local _map_count;
  proc sql noprint;
    select count(*) into :_map_count trimmed from work.name_map_final;
  quit;
  %if &_map_count ne &_total_cols %then
    %fail_out(msg=23 SECTION 8 -- name map has &_map_count rows but dataset has &_total_cols columns -- completeness failure);
  %put NOTE: [23] SECTION 8 assertion passed -- name map completeness OK &_map_count rows = &_total_cols cols;
%mend assert_name_map_complete;
%assert_name_map_complete;

/* --- 8d. DROP and KEY rows must have blank final_name ---- */
%macro assert_drop_key_blank;
  %local _bad_cnt;
  proc sql noprint;
    select count(*) into :_bad_cnt trimmed
    from work.name_map_final
    where role in ('DROP', 'KEY') and strip(final_name) ne '';
  quit;
  %if &_bad_cnt > 0 %then
    %fail_out(msg=23 SECTION 8 -- &_bad_cnt DROP or KEY rows have non-blank final_name -- role assignment bug);
  %put NOTE: [23] SECTION 8 assertion passed -- all DROP and KEY rows have blank final_name;
%mend assert_drop_key_blank;
%assert_drop_key_blank;

/* --- 8e. Summary NOTE counts ---- */
%put NOTE: [23] SECTION 8 summary -- char cols swept=&ncharvars;
%put NOTE: [23] SECTION 8 summary -- distinct AUTO candidates=&_n_auto REVIEW=&_n_review AMBIGUOUS=&_n_ambig;
%put NOTE: [23] SECTION 8 summary -- name-map KEY=&_nm_key KEEP=&_nm_keep DROP=&_nm_drop;
%put NOTE: [23] SECTION 8 summary -- names with truncation=&_nm_trunc collision_flag=&_nm_coll id_flag=&_nm_idflag;
%put NOTE: [23] SECTION 8 summary -- decisions draft rows=&_n_dec_rows wildcard rows=&_n_wildcards;

%put NOTE: ==== Phase 23 Sentinel Inventory complete ====;

%restore_log;
