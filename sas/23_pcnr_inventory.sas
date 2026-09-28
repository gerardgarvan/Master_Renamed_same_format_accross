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

/* ---- Column lists (PCM-D-25) -- hardcoded in program header -----------
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
%put NOTE: ==== Phase 23 Sentinel Inventory complete ====;

%restore_log;
