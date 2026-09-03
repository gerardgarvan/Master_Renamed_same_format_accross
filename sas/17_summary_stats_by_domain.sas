/*==========================================================================
  Program : 17_summary_stats_by_domain.sas
  Purpose : Wave 0 discovery and Wave 1 domain map for five-domain descriptive
            summary statistics of every PRECEDE-dictionary-documented variable
            in g.analysis_base (extended with frailty, cognitive, and
            intraoperative-physiologic columns from g.master_data_merged).

  SCOPE OF THIS FILE (read this before setting DOMAIN_MAP_APPROVED):
            This file contains Sections 0, 0b, and 1 through 4 only.
            Sections 5 through 11 (sentinel recode, PROC MEANS, PROC FREQ,
            suppression, ODS EXCEL workbook, QC artifact) are NOT YET WRITTEN.
            Setting DOMAIN_MAP_APPROVED to 1 will therefore not produce any
            statistics. The %gate_stats macro is defined here for Sections
            5 to 11 to call once they exist. It is deliberately not invoked.

  Output  : qc\17_discovery.txt                 (Wave 0 plus Section 1 coverage)
            g.var_domain_map                    (Wave 1, the ONE permanent artifact)
            qc\17_var_domain_map_review.csv     (Wave 1, Checkpoint 1 review)

  Reads   : g.analysis_base            (read-only)
            g.master_data_merged       (read-only)
            docs\precede_dictionary.csv

  Author  : 2026-09-03

  PCM compliance:
    - No bare open-code %IF or %DO (all conditional logic inside named macros)
    - No apostrophes and no embedded semicolons in %PUT text
    - Every %abort cancel inside %fail_out only
    - No &SQLOBS; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - Every SELECT INTO target is initialised with %let first, so a zero-row
      query leaves an empty macro variable rather than an unresolved reference
    - dictionary.columns.TYPE is char/num, not 1/2
    - ASCII only (session encoding is not UTF-8 on this project)
==========================================================================*/


/* =========================================================================
   SECTION 0: Options, config include, log routing, preconditions
   ========================================================================= */

options nodate nonumber ps=max ls=200 nofmterr;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* ---- in_pipeline default if 00_config did not set it -------------------- */
%macro init_pipeline_flag;
  %if %symexist(in_pipeline) = 0 %then %do;
    %global in_pipeline;
    %let in_pipeline = 0;
  %end;
%mend init_pipeline_flag;
%init_pipeline_flag;

/* ---- Checkpoint 1 approval gate -----------------------------------------
   Set DOMAIN_MAP_APPROVED = 1 only after Gerard reviews and approves
   qc\17_var_domain_map_review.csv. Sections 5 to 11, once written, must open
   with %gate_stats so they are unreachable until the flag is 1.           */
%let DOMAIN_MAP_APPROVED = 0;

/* ---- Small-cell suppression constants ------------------------------------
   SUPPRESS_MAX  : cells with n <= &SUPPRESS_MAX are suppressed.
   SUPPRESS_LABEL: the display string replacing suppressed cells.
   NOTE: do NOT use the string <11 as the label. Under n <= 11 a cell of
   exactly 11 labelled <11 is a false statement. Rule here is n <= 11 with
   the -- label.                                                            */
%let SUPPRESS_MAX   = 11;
%let SUPPRESS_LABEL = --;

/* ---- Log routing -------------------------------------------------------- */
%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\17_summary_stats_by_domain.log" new;
    run;
  %end;
%mend route_log;

%macro restore_log;
  %if &in_pipeline = 0 %then %do;
    proc printto;
    run;
  %end;
%mend restore_log;

/* ---- fail_out: named macro, %abort cancel only here -------------------- */
%macro fail_out(msg=);
  %put ERROR: &msg;
  ods excel close;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;

/* ---- Checkpoint 1 gate macro (for Sections 5 to 11 when written) ------- */
%macro gate_stats;
  %if &DOMAIN_MAP_APPROVED ne 1 %then %do;
    %put NOTE: Domain map awaiting Checkpoint 1 approval -- statistics sections skipped.;
    %restore_log;
    %abort cancel;
  %end;
%mend gate_stats;

%route_log;
libname g "&g_path";

%put NOTE: ==== Phase 17 summary-stats-by-domain starting ====;
%put NOTE: SUPPRESS_MAX=&SUPPRESS_MAX SUPPRESS_LABEL=&SUPPRESS_LABEL;

/* ---- Directory preconditions ------------------------------------------- */
%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %fail_out(msg=&label directory not found: &path);
  %end;
%mend check_dir;
%check_dir(path=&docs_path, label=docs);
%check_dir(path=&qc_path,   label=qc);

/* ---- Dictionary CSV precondition --------------------------------------- */
%macro check_dict_csv;
  %if %sysfunc(fileexist(%bquote(&docs_path.\precede_dictionary.csv))) = 0 %then %do;
    %fail_out(msg=docs precede_dictionary.csv not found);
  %end;
%mend check_dict_csv;
%check_dict_csv;

/* ---- Source dataset existence: g.analysis_base ------------------------- */
%let n_tab_base = 0;
proc sql noprint;
  select count(*) into :n_tab_base trimmed
  from dictionary.tables
  where libname='G' and memname='ANALYSIS_BASE';
quit;

%macro check_src_base;
  %if &n_tab_base ne 1 %then %do;
    %fail_out(msg=g.analysis_base not found in g library);
  %end;
%mend check_src_base;
%check_src_base;

/* ---- Source dataset existence: g.master_data_merged -------------------- */
%let n_tab_merged = 0;
proc sql noprint;
  select count(*) into :n_tab_merged trimmed
  from dictionary.tables
  where libname='G' and memname='MASTER_DATA_MERGED';
quit;

%macro check_src_merged;
  %if &n_tab_merged ne 1 %then %do;
    %fail_out(msg=g.master_data_merged not found in g library);
  %end;
%mend check_src_merged;
%check_src_merged;

/* ---- Row count: g.analysis_base ---------------------------------------- */
%let n_base_rows = 0;
proc sql noprint;
  select count(*) into :n_base_rows trimmed from g.analysis_base;
quit;

%macro check_rows;
  %if &n_base_rows = 0 %then %do;
    %fail_out(msg=g.analysis_base is empty or the row count query returned nothing);
  %end;
  %put NOTE: [17] &n_base_rows rows in g.analysis_base.;
%mend check_rows;
%check_rows;


/* =========================================================================
   SECTION 0b: Discovery
   -------------------------------------------------------------------------
   Answers every open question before any statistics are planned.
   Writes results to qc\17_discovery.txt.
   Produces NO permanent datasets and writes NOTHING to g.
   work.ext_candidates is left in WORK for Section 1 to build the KEEP= list.
   ========================================================================= */

%put NOTE: ==== Section 0b: Discovery starting ====;

/* ---- 1. Column inventory from dictionary.columns ----------------------- */
proc sql;
  create table work.cols_base as
    select upcase(name) as name     length=32,
           type         as vtype    length=4,
           length       as vlen,
           label        as sas_label length=256
    from dictionary.columns
    where libname='G' and memname='ANALYSIS_BASE';

  create table work.cols_merged as
    select upcase(name) as name  length=32,
           type         as vtype length=4,
           length       as vlen
    from dictionary.columns
    where libname='G' and memname='MASTER_DATA_MERGED';
quit;


/* ---- 2. KEY METADATA: type and length of PRECEDE_STUDY_ID -------------- */
/* Every target initialised first: a zero-row query must leave the macro    */
/* variable EMPTY, not unresolved. An unresolved reference would survive    */
/* %length tests and then fail as a syntax error deep in a later step.      */
%let key_type_base   = ;
%let key_len_base    = ;
%let key_type_merged = ;
%let key_len_merged  = ;

proc sql noprint;
  select type, length
    into :key_type_base trimmed, :key_len_base trimmed
  from dictionary.columns
  where libname='G' and memname='ANALYSIS_BASE'
    and upcase(name)='PRECEDE_STUDY_ID';

  select type, length
    into :key_type_merged trimmed, :key_len_merged trimmed
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED'
    and upcase(name)='PRECEDE_STUDY_ID';
quit;

%macro check_key_present;
  %if %length(&key_type_base) = 0 %then %do;
    %fail_out(msg=PRECEDE_STUDY_ID not found in g.analysis_base -- cannot build the D-01 join key);
  %end;
  %if %length(&key_type_merged) = 0 %then %do;
    %fail_out(msg=PRECEDE_STUDY_ID not found in g.master_data_merged -- cannot build the D-01 join key);
  %end;
  %put NOTE: [17-discovery] key type base=&key_type_base len=&key_len_base merged=&key_type_merged len=&key_len_merged;
%mend check_key_present;
%check_key_present;

/* Normalised key length: never truncate either side. */
%macro set_key_len;
  %global key_norm_len;
  %let key_norm_len = 12;
  %if &key_type_base = char %then %do;
    %if %eval(&key_len_base > &key_norm_len) %then %let key_norm_len = &key_len_base;
  %end;
  %if &key_type_merged = char %then %do;
    %if %eval(&key_len_merged > &key_norm_len) %then %let key_norm_len = &key_len_merged;
  %end;
  %put NOTE: [17-discovery] normalised key length = &key_norm_len;
%mend set_key_len;
%set_key_len;

/* ---- Sample 10 non-missing key values from each dataset ---------------- */
/* MONOTONIC() removed: undocumented, unreliable in subqueries, and HAVING  */
/* without GROUP BY forces a remerge. Dataset option (obs=) is supported.   */
%let key_sample_base   = ;
%let key_sample_merged = ;

%macro sample_keys;
  data work._ksb;
    set g.analysis_base(keep=PRECEDE_STUDY_ID);
    length k $&key_norm_len;
    %if &key_type_base = num %then %do;
      if missing(PRECEDE_STUDY_ID) then delete;
      k = strip(put(PRECEDE_STUDY_ID, best12.));
    %end;
    %else %do;
      if missing(PRECEDE_STUDY_ID) then delete;
      k = strip(PRECEDE_STUDY_ID);
    %end;
    keep k;
    if _n_ > 5000 then stop;
  run;

  data work._ksm;
    set g.master_data_merged(keep=PRECEDE_STUDY_ID);
    length k $&key_norm_len;
    %if &key_type_merged = num %then %do;
      if missing(PRECEDE_STUDY_ID) then delete;
      k = strip(put(PRECEDE_STUDY_ID, best12.));
    %end;
    %else %do;
      if missing(PRECEDE_STUDY_ID) then delete;
      k = strip(PRECEDE_STUDY_ID);
    %end;
    keep k;
    if _n_ > 5000 then stop;
  run;

  proc sql noprint;
    select k into :key_sample_base separated by '|'   from work._ksb(obs=10);
    select k into :key_sample_merged separated by '|' from work._ksm(obs=10);
  quit;
%mend sample_keys;
%sample_keys;


/* ---- 3. KEY UNIQUENESS and MISSING KEYS -------------------------------- */
/* Missing keys must be excluded from the duplicate test. Two or more       */
/* missing values form one group with count > 1 and would abort the run     */
/* for the wrong reason. Missing keys are reported separately.              */
%let n_key_dups    = 0;
%let n_missing_key = 0;

proc sql noprint;
  select count(*) into :n_key_dups trimmed
  from (
    select PRECEDE_STUDY_ID
    from g.master_data_merged
    where not missing(PRECEDE_STUDY_ID)
    group by PRECEDE_STUDY_ID
    having count(*) > 1
  );

  select count(*) into :n_missing_key trimmed
  from g.master_data_merged
  where missing(PRECEDE_STUDY_ID);
quit;


/* ---- 4. YEAR VARIABLE: identify, decide, and quantify ------------------ */
/* Discovery must produce a DECISION, not a candidate list. Downstream       */
/* waves read &year_variable and work.year_dist as committed facts.          */
proc sql;
  create table work.year_candidates as
    select name, vtype, sas_label
    from work.cols_base
    where index(name,'YEAR')      > 0
       or index(name,'_DATE')     > 0
       or index(name,'SURG')      > 0
       or index(name,'ENCOUNTER') > 0;
quit;

%let year_cand_list = ;
proc sql noprint;
  select name into :year_cand_list separated by ' '
  from work.cols_base
  where index(name,'YEAR') > 0 and vtype = 'num';
quit;

/* (an earlier pick_year draft was removed; %pick_year_safe below is the one used) */

/* The empty-dataset branch above must not reference an undefined variable. */
%macro pick_year_safe;
  %global year_variable n_year_cands year_note;
  %let n_year_cands = %sysfunc(countw(&year_cand_list));

  %if &n_year_cands = 0 %then %do;
    %let year_variable = ;
    %let year_note = NO NUMERIC YEAR COLUMN FOUND -- per-year stratification must derive year from a surgery date column. See the candidate list below.;
    %put WARNING: [17-discovery] &year_note;
    data work.year_dist;
      length year_value 8 n_rows 8 percent 8;
      stop;
    run;
  %end;
  %else %do;
    %let year_variable = %scan(&year_cand_list, 1);
    %if &n_year_cands > 1 %then %do;
      %let year_note = &n_year_cands numeric YEAR candidates found. Using &year_variable. Confirm the choice at Checkpoint 1.;
      %put WARNING: [17-discovery] &year_note;
    %end;
    %else %do;
      %let year_note = Year variable resolved to &year_variable.;
      %put NOTE: [17-discovery] &year_note;
    %end;

    proc freq data=g.analysis_base noprint;
      tables &year_variable / missing out=work._yd(rename=(count=n_rows));
    run;

    data work.year_dist;
      set work._yd;
      length year_value 8;
      year_value = &year_variable;
      keep year_value n_rows percent;
    run;
  %end;
%mend pick_year_safe;
%pick_year_safe;


/* ---- 5. EXTENSION COLUMN LIST (D-01 KEEP=) ----------------------------- */
/* Columns in g.master_data_merged NOT in g.analysis_base, filtered to      */
/* frailty, cognitive, and intraop-physiologic concepts. MAC is matched by  */
/* an anchored pattern only -- a bare index for MAC hits PHARMACY, STOMACH. */
/* NOTE: this concept filter is a heuristic. A frailty, cognitive, or       */
/* intraoperative variable whose name contains none of these fragments will */
/* be missed. The resolved list is written to the discovery report for      */
/* review at Checkpoint 1 -- treat it as a proposal, not an authority.      */
proc sql;
  create table work.ext_candidates as
    select m.name, m.vtype
    from work.cols_merged m
    where m.name not in (select name from work.cols_base)
      and m.name ne 'PRECEDE_STUDY_ID_1'   /* md6 duplicate -- pitfall 5 */
      and (
            index(m.name,'FRAIL')          > 0
         or index(m.name,'COGNI')          > 0
         or index(m.name,'FEELS')          > 0
         or index(m.name,'WEIGHT_LOSS')    > 0
         or index(m.name,'GRIP')           > 0
         or index(m.name,'WALK')           > 0
         or index(m.name,'PHYSICAL_ACTIV') > 0
         or index(m.name,'ABP')            > 0
         or index(m.name,'BIS_')           > 0
         or index(m.name,'NIBP')           > 0
         or index(m.name,'MIDAZOLAM')      > 0
         or prxmatch('/(^|_)MAC(_|$)/', strip(m.name)) > 0
         or index(m.name,'ISO_SEV')        > 0
      );
quit;

%let n_ext_cols = 0;
proc sql noprint;
  select count(*) into :n_ext_cols trimmed from work.ext_candidates;
quit;


/* ---- 6. IDENTIFIER CANDIDATES ------------------------------------------ */
/* Anchored pattern only. A bare index for ID_ matches COVID_STATUS,        */
/* RAPID_TEST and VALID_FLAG. This is the SAME pattern Section 3b applies,  */
/* so the report and the exclusion cannot disagree.                         */
proc sql;
  create table work.id_candidates as
    select name, vtype, vlen
    from work.cols_base
    where name in ('PRECEDE_STUDY_ID','PRECEDE_STUDY_ID_1',
                   'ENCRYPTED_MRN','ENCRYPTED_ENCOUNTER')
       or prxmatch('/(^|_)(ID|MRN)(_|$)/', strip(name)) > 0;
quit;

/* ---- High-cardinality character variables: REVIEW FLAG ONLY ------------ */
/* These are NOT excluded. CPT codes, procedure names and ZIP codes all     */
/* exceed 200 levels and are legitimate analytic variables. Cardinality is  */
/* reported so the reviewer can sort on it at Checkpoint 1.                 */
proc freq data=g.analysis_base nlevels;
  tables _character_ / noprint;
  ods output nlevels=work.char_nlevels;
run;

proc sql;
  create table work.hi_card_chars as
    select upcase(strip(tablevar)) as name length=32, nlevels
    from work.char_nlevels
    where nlevels > 200;
quit;


/* ---- 7. SENTINEL APPLICABILITY ----------------------------------------- */
/* Single pass with arrays. The previous per-variable PROC SQL loop made    */
/* roughly one network read per column against the P: drive.               */
/* Output name and values match what Wave 2 (Section 5) will read:          */
/*   work.sentinel_applicable, sentinel_kind in NUM_-999 / CHAR_NULL        */
/* Wave 2 keeps its own work.sentinel_log for recode counts -- do not       */
/* reuse that name here.                                                    */
%let sent_num_all = ;
%let sent_chr_all = ;
proc sql noprint;
  select name into :sent_num_all separated by ' '
  from work.cols_base where vtype = 'num';
  select name into :sent_chr_all separated by ' '
  from work.cols_base where vtype = 'char';
quit;

%macro scan_sentinels;
  %local n_num n_chr;
  %let n_num = %sysfunc(countw(&sent_num_all));
  %let n_chr = %sysfunc(countw(&sent_chr_all));

  %if &n_num = 0 and &n_chr = 0 %then %do;
    data work.sentinel_applicable;
      length varname $32 sentinel_kind $10 n_sentinel 8;
      stop;
    run;
    %put WARNING: [17-discovery] g.analysis_base has no columns to scan for sentinels.;
  %end;
  %else %do;
    data work.sentinel_applicable(keep=_vn _sk _ns
                                  rename=(_vn=varname _sk=sentinel_kind _ns=n_sentinel));
      length _vn $32 _sk $10 _ns 8;
      set g.analysis_base end=_eof;

      %if &n_num > 0 %then %do;
        array _sn {*} &sent_num_all;
        array _cn {&n_num} _temporary_;
        do _i = 1 to dim(_sn);
          if _sn{_i} = -999 then _cn{_i} + 1;
        end;
      %end;

      %if &n_chr > 0 %then %do;
        array _sc {*} &sent_chr_all;
        array _cc {&n_chr} _temporary_;
        do _j = 1 to dim(_sc);
          if upcase(strip(_sc{_j})) = 'NULL' then _cc{_j} + 1;
        end;
      %end;

      if _eof then do;
        %if &n_num > 0 %then %do;
          do _i = 1 to &n_num;
            if _cn{_i} > 0 then do;
              _vn = upcase(vname(_sn{_i}));
              _sk = 'NUM_-999';
              _ns = _cn{_i};
              output;
            end;
          end;
        %end;
        %if &n_chr > 0 %then %do;
          do _j = 1 to &n_chr;
            if _cc{_j} > 0 then do;
              _vn = upcase(vname(_sc{_j}));
              _sk = 'CHAR_NULL';
              _ns = _cc{_j};
              output;
            end;
          end;
        %end;
      end;
    run;
  %end;
%mend scan_sentinels;
%scan_sentinels;

%let n_sent_vars = 0;
proc sql noprint;
  select count(*) into :n_sent_vars trimmed from work.sentinel_applicable;
quit;


/* ---- 8. VARnn positional-name defect scan ------------------------------ */
%let n_varnn = 0;
proc sql noprint;
  select count(*) into :n_varnn trimmed
  from work.cols_base
  where prxmatch('/^VAR\d+$/', strip(name)) > 0;
quit;


/* ---- 9. Write qc\17_discovery.txt -------------------------------------- */
/* The PROC EXPORT that previously sat between these DATA steps has been    */
/* deleted. It rewrote the same path and destroyed everything written above */
/* it, and the DATA step below already emits the candidate list.            */
%macro write_discovery;
  %local dt_run;
  %let dt_run = %sysfunc(datetime(), datetime20.);

  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200;
    put "=================================================================";
    put "Phase 17 Discovery Report";
    put "Run: &dt_run";
    put "Program: 17_summary_stats_by_domain.sas (Section 0b)";
    put "=================================================================";
    put " ";
    put "--- BASE ROW COUNT ---";
    put "g.analysis_base rows: &n_base_rows";
    put " ";
    put "--- KEY METADATA ---";
    put "PRECEDE_STUDY_ID in g.analysis_base:      type=&key_type_base  length=&key_len_base";
    put "PRECEDE_STUDY_ID in g.master_data_merged: type=&key_type_merged  length=&key_len_merged";
    put "Normalised join key length: $&key_norm_len";
    put " ";
    put "NOTE: a SAS variable has exactly one type per dataset. The CHAR vs";
    put "NUM8 history describes the md1 to md8 SOURCE files, not the merged";
    put "dataset, which now holds a single resolved type.";
    put " ";
    put "Sampled key values from g.analysis_base (up to 10, pipe-separated):";
    put "&key_sample_base";
    put "Sampled key values from g.master_data_merged (up to 10, pipe-separated):";
    put "&key_sample_merged";
    put "Inspect these for zero-padding before trusting the join format.";
    put "Section 1 additionally tests the format empirically by match count.";
    put " ";
    put "--- KEY UNIQUENESS ---";
    put "Duplicate PRECEDE_STUDY_ID count in g.master_data_merged (missing excluded): &n_key_dups";
    put "Rows with a MISSING PRECEDE_STUDY_ID in g.master_data_merged: &n_missing_key";
    put " ";
    put "--- VARNN DEFECT SCAN ---";
    put "Columns with positional VAR+digits names in g.analysis_base: &n_varnn";
    put " ";
  run;

  /* Year variable: decision, candidates, distribution */
  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "--- YEAR VARIABLE ---";
    put "Resolved year variable: &year_variable";
    put "&year_note";
    put " ";
    put "Candidate columns considered:";
  run;

  data _null_;
    set work.year_candidates;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "  " name "  type=" vtype "  label=" sas_label;
  run;

  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put " ";
    put "Per-year row counts (missing included):";
  run;

  data _null_;
    set work.year_dist;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "  year=" year_value "  n_rows=" n_rows;
  run;

  /* Extension column list */
  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put " ";
    put "--- EXTENSION COLUMN LIST (D-01 KEEP=) ---";
    put "Columns in g.master_data_merged NOT in g.analysis_base, concept-filtered.";
    put "PRECEDE_STUDY_ID_1 explicitly excluded (md6 duplicate).";
    put "Count: &n_ext_cols";
    put "REVIEW: the concept filter is a name heuristic. A frailty, cognitive";
    put "or intraoperative variable named outside these fragments is missed.";
    put "Confirm this list against the dictionary at Checkpoint 1.";
    put " ";
  run;

  data _null_;
    set work.ext_candidates;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "  " name "  type=" vtype;
  run;

  /* Identifier candidates */
  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put " ";
    put "--- IDENTIFIER CANDIDATES (marked OUT_OF_SCOPE in Wave 1) ---";
    put "Matched on the anchored pattern (^ or underscore) ID or MRN (underscore or end).";
  run;

  data _null_;
    set work.id_candidates;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "  " name;
  run;

  /* High-cardinality character variables: review flag only */
  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put " ";
    put "--- HIGH-CARDINALITY CHARACTER VARIABLES (>200 levels) ---";
    put "REVIEW FLAG ONLY -- these are NOT excluded. CPT codes, procedure";
    put "names and ZIP codes legitimately exceed 200 levels.";
  run;

  data _null_;
    set work.hi_card_chars;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "  " name "  nlevels=" nlevels;
  run;

  /* Sentinel applicability */
  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put " ";
    put "--- SENTINEL APPLICABILITY (Wave 2 recodes ONLY these variables) ---";
    put "Variables with at least one observed sentinel value: &n_sent_vars";
    put "A variable here that nobody expected to carry a sentinel is a finding.";
    put " ";
    put "  -999 sentinel (numeric):";
  run;

  data _null_;
    set work.sentinel_applicable;
    where sentinel_kind = 'NUM_-999';
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "    " varname "  n=" n_sentinel;
  run;

  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "  literal NULL sentinel (character):";
  run;

  data _null_;
    set work.sentinel_applicable;
    where sentinel_kind = 'CHAR_NULL';
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "    " varname "  n=" n_sentinel;
  run;

  %put NOTE: [17] Discovery report written to &qc_path.\17_discovery.txt;
%mend write_discovery;
%write_discovery;

%put NOTE: ==== Section 0b complete ====;


/* =========================================================================
   SECTION 1: Build work.analysis_base_ext (D-01 join)
   -------------------------------------------------------------------------
   1. Defensive globals
   2. Key uniqueness gate (missing keys already excluded from the test)
   3. Macro-time key type resolution
   4. KEEP= list from work.ext_candidates, with a row-count check
   5. Normalise BOTH keys to CHAR; test the numeric format empirically
   6. Sort and left merge
   7. Row-count and cognitive-score assertions
   8. Per-column coverage, appended to the discovery report
   ========================================================================= */

%put NOTE: ==== Section 1: build work.analysis_base_ext starting ====;

/* ---- 1. Defensive globals ---------------------------------------------- */
/* Declared and emptied here so no later step can reference an undefined    */
/* macro variable if an upstream branch was skipped.                        */
%global D3_DENOM_NOTE cog_col n_cog_nonmiss key_fmt extension_keep_list
        ext_num_list ext_chr_list;
%let D3_DENOM_NOTE     = ;
%let cog_col           = ;
%let n_cog_nonmiss     = .;
%let key_fmt           = ;
%let extension_keep_list = ;
%let ext_num_list      = ;
%let ext_chr_list      = ;


/* ---- 2. Key uniqueness gate -------------------------------------------- */
%macro check_key_unique;
  %if &n_key_dups > 0 %then %do;
    %fail_out(msg=&n_key_dups duplicate PRECEDE_STUDY_ID values in g.master_data_merged -- the extension merge requires a unique key or an explicit collapse rule);
  %end;
  %put NOTE: [17-S1] PRECEDE_STUDY_ID uniqueness confirmed (dups=&n_key_dups missing=&n_missing_key).;
%mend check_key_unique;
%check_key_unique;


/* ---- 3. KEEP= list from work.ext_candidates ---------------------------- */
/* Check the ROW COUNT, not merely that the table exists. An empty table    */
/* would leave extension_keep_list empty and break the KEEP= below.         */
%macro check_ext_candidates;
  %if &n_ext_cols = 0 %then %do;
    %fail_out(msg=work.ext_candidates has no rows -- the concept filter matched nothing and the D-01 extension cannot be built);
  %end;
%mend check_ext_candidates;
%check_ext_candidates;

proc sql noprint;
  select name into :extension_keep_list separated by ' ' from work.ext_candidates;
  select name into :ext_num_list separated by ' ' from work.ext_candidates where vtype='num';
  select name into :ext_chr_list separated by ' ' from work.ext_candidates where vtype='char';
quit;

%put NOTE: [17-S1] extension_keep_list: &extension_keep_list;


/* ---- 4. Normalise the base key ----------------------------------------- */
%macro norm_base_key;
  data work.base_keyed;
    set g.analysis_base;
    length _key_c $&key_norm_len;
    %if &key_type_base = num %then %do;
      _key_c = strip(put(PRECEDE_STUDY_ID, best12.));
    %end;
    %else %do;
      _key_c = strip(PRECEDE_STUDY_ID);
    %end;
    drop PRECEDE_STUDY_ID;
    rename _key_c = PRECEDE_STUDY_ID;
  run;
%mend norm_base_key;
%norm_base_key;


/* ---- 5. Normalise the extension key, choosing the format empirically --- */
/* The sampled values in the discovery report tell the reviewer what the    */
/* keys look like, but the program must not depend on anyone eyeballing     */
/* them. When the merged key is numeric, both candidate representations are */
/* tested against the base keys and the one that actually matches is used.  */
/* best12. gives 123456789 and z12. gives 000123456789 -- picking wrong     */
/* yields a join that matches nothing while the row count still passes.     */
%macro build_ext_cols(fmt=);
  data work.merged_ext_cols;
    set g.master_data_merged (keep=PRECEDE_STUDY_ID &extension_keep_list);
    length _key_c $&key_norm_len;
    if missing(PRECEDE_STUDY_ID) then delete;
    %if &key_type_merged = num %then %do;
      %if &fmt = Z %then %do;
        _key_c = put(PRECEDE_STUDY_ID, z12.);
      %end;
      %else %do;
        _key_c = strip(put(PRECEDE_STUDY_ID, best12.));
      %end;
    %end;
    %else %do;
      _key_c = strip(PRECEDE_STUDY_ID);
    %end;
    drop PRECEDE_STUDY_ID;
    rename _key_c = PRECEDE_STUDY_ID;
  run;
%mend build_ext_cols;

%macro count_key_overlap(into=);
  proc sql noprint;
    select count(*) into :&into trimmed
    from work.merged_ext_cols
    where PRECEDE_STUDY_ID in (select PRECEDE_STUDY_ID from work.base_keyed);
  quit;
%mend count_key_overlap;

%macro pick_key_format;
  %local n_best n_z;
  %let n_best = 0;
  %let n_z    = 0;

  %if &key_type_merged = char %then %do;
    %let key_fmt = CHAR;
    %build_ext_cols(fmt=CHAR);
    %count_key_overlap(into=n_best);
    %put NOTE: [17-S1] character key: &n_best extension rows match a base key.;
    %if &n_best = 0 %then %do;
      %fail_out(msg=Character join key produced zero matches against g.analysis_base -- padding or case differs between the two datasets);
    %end;
  %end;
  %else %do;
    %build_ext_cols(fmt=BEST);
    %count_key_overlap(into=n_best);
    %put NOTE: [17-S1] best12. representation: &n_best matches.;

    %if &n_best = 0 %then %do;
      %put WARNING: [17-S1] best12. matched nothing. Testing zero-padded z12.;
      %build_ext_cols(fmt=Z);
      %count_key_overlap(into=n_z);
      %put NOTE: [17-S1] z12. representation: &n_z matches.;
      %if &n_z = 0 %then %do;
        %fail_out(msg=Neither best12. nor z12. matched any base key -- the numeric key cannot be reconciled with the character key in g.analysis_base);
      %end;
      %let key_fmt = Z12;
    %end;
    %else %do;
      %let key_fmt = BEST12;
    %end;
  %end;
  %put NOTE: [17-S1] key format selected: &key_fmt;
%mend pick_key_format;
%pick_key_format;


/* ---- 6. Sort and left merge -------------------------------------------- */
proc sort data=work.merged_ext_cols; by PRECEDE_STUDY_ID; run;
proc sort data=work.base_keyed out=work.analysis_base_sorted; by PRECEDE_STUDY_ID; run;

data work.analysis_base_ext;
  merge work.analysis_base_sorted (in=inbase)
        work.merged_ext_cols;
  by PRECEDE_STUDY_ID;
  if inbase;
run;


/* ---- 7. Row-count assertion -------------------------------------------- */
%let n_ext_rows = 0;
proc sql noprint;
  select count(*) into :n_ext_rows trimmed from work.analysis_base_ext;
quit;

%macro check_ext_rows;
  %if &n_ext_rows ne &n_base_rows %then %do;
    %fail_out(msg=Row count mismatch after the D-01 join: work.analysis_base_ext has &n_ext_rows rows against &n_base_rows in g.analysis_base);
  %end;
  %put NOTE: [17-S1] Row-count assertion passed: &n_ext_rows rows.;
%mend check_ext_rows;
%check_ext_rows;


/* ---- 8. Cognitive-score non-missing guard ------------------------------ */
proc sql noprint;
  select name into :cog_col trimmed
  from work.ext_candidates
  where index(upcase(name),'COGNI') > 0 and index(upcase(name),'SCORE') > 0;
quit;

%macro check_cog_populated;
  %if %length(&cog_col) = 0 %then %do;
    %put WARNING: [17-S1] No cognitive score column (COGNI and SCORE) in ext_candidates. Cognitive guard skipped.;
  %end;
  %else %do;
    %let n_cog_nonmiss = 0;
    proc sql noprint;
      select count(*) into :n_cog_nonmiss trimmed
      from work.analysis_base_ext
      where not missing(&cog_col);
    quit;
    %if &n_cog_nonmiss = 0 %then %do;
      %fail_out(msg=Cognitive score column &cog_col is all-missing in work.analysis_base_ext -- the join key silently failed to match);
    %end;
    %put NOTE: [17-S1] Cognitive guard passed: &cog_col has &n_cog_nonmiss non-missing values.;
  %end;
%mend check_cog_populated;
%check_cog_populated;


/* ---- 9. Per-column extension coverage ---------------------------------- */
/* Computed on work.analysis_base_ext AFTER the join, so the denominator is */
/* the base row count and the figure is meaningful. The previous Section 0b */
/* version counted in g.master_data_merged but divided by the base row      */
/* count, which could exceed 100 percent.                                   */
/* Single pass with arrays, split by type -- a SAS array cannot mix types.  */
%macro ext_coverage;
  %local n_en n_ec;
  %let n_en = %sysfunc(countw(&ext_num_list));
  %let n_ec = %sysfunc(countw(&ext_chr_list));

  data work.ext_coverage(keep=_vn _nm rename=(_vn=varname _nm=n_nonmiss));
    length _vn $32 _nm 8;
    set work.analysis_base_ext end=_eof;

    %if &n_en > 0 %then %do;
      array _en {*} &ext_num_list;
      array _kn {&n_en} _temporary_;
      do _i = 1 to dim(_en);
        if not missing(_en{_i}) then _kn{_i} + 1;
      end;
    %end;

    %if &n_ec > 0 %then %do;
      array _ec {*} &ext_chr_list;
      array _kc {&n_ec} _temporary_;
      do _j = 1 to dim(_ec);
        if not missing(_ec{_j}) then _kc{_j} + 1;
      end;
    %end;

    if _eof then do;
      %if &n_en > 0 %then %do;
        do _i = 1 to &n_en;
          _vn = upcase(vname(_en{_i}));
          _nm = coalesce(_kn{_i}, 0);
          output;
        end;
      %end;
      %if &n_ec > 0 %then %do;
        do _j = 1 to &n_ec;
          _vn = upcase(vname(_ec{_j}));
          _nm = coalesce(_kc{_j}, 0);
          output;
        end;
      %end;
    end;
  run;

  data work.ext_coverage;
    set work.ext_coverage;
    length coverage_flag $40;
    pct_of_base = 100 * n_nonmiss / &n_base_rows;
    if pct_of_base < 90 then coverage_flag = 'PARTIAL';
    else coverage_flag = 'FULL';
  run;
%mend ext_coverage;
%ext_coverage;

%let n_partial_cov = 0;
proc sql noprint;
  select count(*) into :n_partial_cov trimmed
  from work.ext_coverage where coverage_flag = 'PARTIAL';
quit;

/* Denominator note. It does NOT claim a single N for both blocks: coverage */
/* differs by extension variable, and the cognitive-score count is not the  */
/* frailty denominator. Per-variable N appears in the results themselves.   */
%macro set_denom_note;
  %if &n_partial_cov > 0 %then %do;
    %let D3_DENOM_NOTE = Coverage varies by variable in this block. Statistics use the non-missing observations available for each variable rather than the &n_base_rows row base. See the per-variable N column and the QC sheet coverage table.;
    %put NOTE: [17-S1] PARTIAL coverage on &n_partial_cov extension columns. Denominator note set.;
  %end;
  %else %do;
    %let D3_DENOM_NOTE = ;
    %put NOTE: [17-S1] Full coverage on all extension columns.;
  %end;
%mend set_denom_note;
%set_denom_note;

/* Append the coverage block to the discovery report */
data _null_;
  file "&qc_path.\17_discovery.txt" lrecl=200 mod;
  put " ";
  put "--- EXTENSION COVERAGE (post-join, denominator = &n_base_rows base rows) ---";
  put "Columns flagged PARTIAL: &n_partial_cov";
run;

data _null_;
  set work.ext_coverage;
  file "&qc_path.\17_discovery.txt" lrecl=200 mod;
  put "  " varname "  n_nonmiss=" n_nonmiss "  pct_of_base=" pct_of_base 6.1 "  " coverage_flag;
run;

data _null_;
  file "&qc_path.\17_discovery.txt" lrecl=200 mod;
  put " ";
  put "=================================================================";
  put "End of Phase 17 Discovery Report";
  put "=================================================================";
run;

%put NOTE: ==== Section 1 complete: work.analysis_base_ext ready ====;


/* =========================================================================
   SECTION 2: Import PRECEDE dictionary
   ========================================================================= */

%put NOTE: ==== Section 2: import PRECEDE dictionary starting ====;

proc import datafile="&docs_path.\precede_dictionary.csv"
    out=work.dict_raw dbms=csv replace;
  guessingrows=max;
run;

data work.dict;
  length sheet $40 dict_name $60 dict_type $20 description $300 sas_name $32;
  set work.dict_raw (rename=(sheet=_s dict_name=_n dict_type=_t
                             description=_d sas_name=_a));
  sheet       = strip(cats(_s));
  dict_name   = strip(cats(_n));
  dict_type   = strip(cats(_t));
  description = strip(cats(_d));
  /* UPCASE before sort: BY-group processing is case-sensitive */
  sas_name    = upcase(strip(cats(_a)));
  if missing(sas_name) then delete;
  /* MASTER_DATASET first, DERIVED second, so the authoritative sheet wins */
  if      sheet = 'MASTER_DATASET'           then sheet_rank = 1;
  else if sheet = 'DERIVED_VARIABLES_MASTER' then sheet_rank = 2;
  else                                            sheet_rank = 3;
  keep sheet dict_name dict_type description sas_name sheet_rank;
run;

proc sort data=work.dict; by sas_name sheet_rank sheet; run;

/* One row per documented name: the dictionary repeats names across sheets */
data work.dict_u;
  set work.dict;
  by sas_name;
  if first.sas_name;
run;

%put NOTE: ==== Section 2 complete: work.dict_u ready ====;


/* =========================================================================
   SECTION 3: Match dictionary against work.analysis_base_ext
   -------------------------------------------------------------------------
   Two-tier match: exact then squash (underscores compressed).
   Matched against ANALYSIS_BASE_EXT, not ANALYSIS_BASE, so the extension
   columns are documented too.
   ========================================================================= */

%put NOTE: ==== Section 3: dictionary match starting ====;

proc sql;
  create table work.actual_ext as
    select upcase(name) as var_u     length=32,
           upcase(name) as varname   length=32,
           type         as vtype     length=4,
           length       as vlen,
           label        as sas_label length=256,
           varnum
    from dictionary.columns
    where libname='WORK' and memname='ANALYSIS_BASE_EXT';

  create table work.doc_all_ext as
    select a.varnum, a.varname, a.vtype, a.vlen, a.sas_label,
           d.dict_name, d.dict_type, d.description, d.sheet, d.sas_name,
           case when a.var_u = upcase(d.sas_name) then 'EXACT'
                else 'SQUASH' end as match_how length=8,
           case when a.var_u = upcase(d.sas_name) then 1
                else 3 end as match_rank
    from work.actual_ext as a
    inner join work.dict_u as d
      on a.var_u = upcase(d.sas_name)
         or compress(a.var_u,'_') = compress(upcase(d.sas_name),'_');
quit;

proc sort data=work.doc_all_ext; by varname match_rank dict_name; run;

/* Keep the strongest match per variable */
data work.var_domain_raw;
  set work.doc_all_ext;
  by varname;
  if first.varname;
run;

/* Match ties: two dictionary entries matching one column equally well */
%let n_ties_ext = 0;
proc sql noprint;
  create table work.match_ties_ext as
    select a.varname, count(*) as n_at_best
    from work.doc_all_ext as a
    inner join work.var_domain_raw as b
      on a.varname = b.varname and a.match_rank = b.match_rank
    group by a.varname having calculated n_at_best > 1;
  select count(*) into :n_ties_ext trimmed from work.match_ties_ext;
quit;

%macro report_ties_ext;
  %if &n_ties_ext > 0 %then %do;
    %put WARNING: [17-S3] &n_ties_ext columns match two dictionary entries equally well. Alphabetically first was used. See work.match_ties_ext.;
  %end;
%mend report_ties_ext;
%report_ties_ext;

/* Reconciliation buckets.                                                  */
/* dict_only is derived from the dictionary names that actually MATCHED,    */
/* not from exact uppercase membership. A dictionary entry matched by the   */
/* squash rule would otherwise be reported as dictionary-only as well.      */
%let n_data_only = 0;
%let n_dict_only = 0;
%let n_matched   = 0;

proc sql noprint;
  create table work.dict_only as
    select sas_name as varname length=32
    from work.dict_u
    where upcase(sas_name) not in
          (select upcase(sas_name) from work.doc_all_ext);

  create table work.data_only as
    select varname, vtype, vlen, sas_label
    from work.actual_ext
    where varname not in
          (select varname from work.var_domain_raw);

  select count(*) into :n_data_only trimmed from work.data_only;
  select count(*) into :n_dict_only trimmed from work.dict_only;
  select count(*) into :n_matched   trimmed from work.var_domain_raw;
quit;

%put NOTE: [17-S3] Match summary: &n_matched matched, &n_dict_only dict-only, &n_data_only data-only;


/* =========================================================================
   SECTION 3c: NLEVELS pass for stat_route and the cardinality review flag
   -------------------------------------------------------------------------
   Routing on vtype alone sends every numeric to PROC MEANS, which is wrong
   for 0/1 and small-integer-coded categoricals (_30_DAY_MORTALITY, sex,
   ASA class, emergent Y/N). Type AND cardinality decide the route.
   ========================================================================= */

proc freq data=work.analysis_base_ext nlevels;
  tables _all_ / noprint;
  ods output nlevels=work.nlevels_raw;
run;

data work.nlevels_ext;
  set work.nlevels_raw;
  length varname_u $32;
  varname_u = upcase(strip(tablevar));
  rename nlevels = n_levels;
  keep varname_u nlevels;
run;

/* ---- Build the staging table: matched rows plus data-only rows --------- */
data work.data_only_oos;
  length varname $32 vtype $4 vlen 8 sas_label $256
         dict_name $60 dict_type $20 description $300 match_how $8
         domain $16 domain_rationale $200 assign_rule $20
         source_dataset $32;
  set work.data_only;
  domain           = 'OUT_OF_SCOPE';
  domain_rationale = 'not in PRECEDE dictionary';
  assign_rule      = 'data_only';
  dict_name        = '';
  dict_type        = '';
  description      = '';
  match_how        = 'NONE';
  source_dataset   = 'analysis_base_ext';
run;

/* The previous version had an open-code %DO placeholder here. %DO is not   */
/* valid outside a macro definition and would abort the run. It was also    */
/* redundant: the SQL join below assigns source_dataset properly.           */
data work.domain_staging;
  length varname $32 vtype $4 vlen 8 sas_label $256
         dict_name $60 dict_type $20 description $300 match_how $8
         domain $16 domain_rationale $200 assign_rule $20
         source_dataset $32 stat_route $8 n_levels 8 denominator_note $300;

  set work.var_domain_raw (in=inmatched)
      work.data_only_oos  (in=indataonly);

  if inmatched then do;
    source_dataset   = 'analysis_base';
    domain           = '';
    domain_rationale = '';
    assign_rule      = '';
  end;
  if indataonly then source_dataset = 'analysis_base_ext';
run;

/* source_dataset for extension columns, by join rather than by macro loop */
proc sql;
  create table work.domain_staging2 as
    select ds.*,
           case when ec.name is not null              then 'master_data_merged'
                when ds.source_dataset = 'analysis_base_ext' then 'analysis_base_ext'
                else 'analysis_base' end as src_ds length=32
    from work.domain_staging as ds
    left join work.ext_candidates as ec
      on upcase(ds.varname) = upcase(ec.name);
quit;

data work.domain_staging2;
  set work.domain_staging2;
  source_dataset = src_ds;
  drop src_ds;
run;

/* Join n_levels */
proc sql;
  create table work.domain_staging3 as
    select ds.*, nl.n_levels as n_levels_join
    from work.domain_staging2 as ds
    left join work.nlevels_ext as nl
      on upcase(ds.varname) = nl.varname_u;
quit;

data work.domain_staging3;
  set work.domain_staging3;
  if missing(n_levels) then n_levels = n_levels_join;
  drop n_levels_join;
run;


/* =========================================================================
   SECTION 3b: Identifier exclusion (BEFORE domain assignment)
   -------------------------------------------------------------------------
   Identifiers and technical keys must never reach statistics: a character
   ID routed to PROC FREQ yields a table with tens of thousands of levels.

   CARDINALITY IS NOT AN EXCLUSION CRITERION. The previous version also
   excluded any character variable with more than 200 levels, which silently
   removed CPT_CODE, PROCEDURE_NAME and ZIP_CODE -- all of which are in the
   Section 4 domain lookup. Because the lookup join is scoped to rows that
   are not already OUT_OF_SCOPE, the domain assignment could not rescue
   them and every guard still passed. Cardinality is now a review flag
   carried on n_levels for Checkpoint 1.
   ========================================================================= */

data work.domain_staging3;
  set work.domain_staging3;
  length hi_cardinality_flag $3;

  if domain = '' then do;
    if varname in ('PRECEDE_STUDY_ID','PRECEDE_STUDY_ID_1',
                   'ENCRYPTED_MRN','ENCRYPTED_ENCOUNTER')
       or prxmatch('/(^|_)(ID|MRN)(_|$)/', strip(upcase(varname))) > 0
    then do;
      domain           = 'OUT_OF_SCOPE';
      domain_rationale = 'identifier or technical key; not an analytic variable';
      assign_rule      = 'identifier_exclusion';
    end;
  end;

  /* Review flag only -- never an exclusion */
  if vtype = 'char' and n_levels > 200 then hi_cardinality_flag = 'YES';
  else hi_cardinality_flag = 'NO';
run;

%let n_id_excluded = 0;
proc sql noprint;
  select count(*) into :n_id_excluded trimmed
  from work.domain_staging3 where assign_rule = 'identifier_exclusion';
quit;
%put NOTE: [17-S3b] &n_id_excluded variables marked OUT_OF_SCOPE as identifiers.;


/* ---- stat_route: type AND cardinality ---------------------------------- */
data work.domain_staging3;
  set work.domain_staging3;

  if domain ne 'OUT_OF_SCOPE' then do;
    if vtype = 'char' then stat_route = 'FREQ';
    else if vtype = 'num' then do;
      if n_levels <= 10 then stat_route = 'FREQ';
      else                   stat_route = 'MEANS';
    end;
  end;
  else stat_route = '';
run;


/* =========================================================================
   SECTION 4: Domain assignment with rationales, g.var_domain_map, guards,
              and the Checkpoint 1 crosswalk export
   -------------------------------------------------------------------------
   Lookup keyed on upcased varname. The quotes that previously wrapped each
   rationale have been removed: INFILE DSD does not strip single quotes, so
   they were being stored literally and exported into the review CSV. They
   were never needed -- DATALINES does not resolve macro triggers, and no
   rationale contains a comma.

   assign_rule for frailty is 'timing', not 'instrument'. The locked rule
   defines instrument membership as the override to D3 for named COGNITIVE
   instruments. Tagging frailty the same way would mix the two in the QC
   sheet's per-rule counts.
   ========================================================================= */

%put NOTE: ==== Section 4: domain assignment starting ====;

data work.domain_lookup;
  length varname_u $32 domain $16 assign_rule $20 domain_rationale $200;
  infile datalines dsd dlm=',' truncover;
  input varname_u :$32. domain :$16. assign_rule :$20. domain_rationale :$200.;
datalines;
AGE_AT_SURGERY,D1,timing,captured at surgery registration; sociodemographic descriptor
AGE_AT_ENCOUNTER,D1,timing,captured at encounter; sociodemographic descriptor
SEX,D1,timing,recorded at registration; sociodemographic descriptor
RACE,D1,timing,recorded at registration; sociodemographic descriptor
ETHNICITY,D1,timing,recorded at registration; sociodemographic descriptor
INSURANCE_TYPE,D1,analytic_role,payer type known preoperatively; sociodemographic proxy
PAYER,D1,analytic_role,payer type known preoperatively; sociodemographic proxy
MARITAL_STATUS,D1,timing,recorded at registration; sociodemographic descriptor
MARITAL,D1,timing,recorded at registration; sociodemographic descriptor
ZIP_CODE,D1,timing,geographic locator recorded at registration; sociodemographic
ZIPCODE,D1,timing,geographic locator recorded at registration; sociodemographic
STATE,D1,timing,geographic locator recorded at registration; sociodemographic
ADMIT_BMI,D2,timing,captured at preoperative admission; preoperative physiologic assessment
BMI,D2,timing,measured preoperatively; standard preoperative assessment variable
FRAILTY_SCORE,D2,timing,frailty assessed before surgery; preoperative assessment
FRAILTY_CATEGORY,D2,timing,frailty assessed before surgery; preoperative assessment
FEELS_EXHAUSTED,D2,timing,frailty component captured preoperatively (Fried criteria)
FEELS_EXAUSTED,D2,timing,frailty component captured preoperatively (Fried criteria; source spelling)
WEIGHT_LOSS,D2,timing,frailty component captured preoperatively (Fried criteria)
GRIP_STRENGTH,D2,timing,frailty component captured preoperatively (Fried criteria)
WEAK_GRIP_STRENGTH,D2,timing,frailty component captured preoperatively (Fried criteria)
WALK_TIME,D2,timing,frailty component captured preoperatively (Fried criteria)
SLOW_WALKING_SPEED,D2,timing,frailty component captured preoperatively (Fried criteria)
PHYSICAL_ACTIVITY,D2,timing,frailty component captured preoperatively (Fried criteria)
LOW_PHYSICAL_ACTIVITY,D2,timing,frailty component captured preoperatively (Fried criteria)
ASA_CLASS,D2,analytic_role,preoperative risk classification assigned before surgery
ASA,D2,analytic_role,preoperative risk classification assigned before surgery
SMOKING_STATUS,D2,timing,preoperative habit assessment; standard preoperative variable
SMOKING,D2,timing,preoperative habit assessment; standard preoperative variable
HYPERTENSION,D2,timing,comorbidity documented in preoperative assessment
DIABETES,D2,timing,comorbidity documented in preoperative assessment
COPD,D2,timing,comorbidity documented in preoperative assessment
CHF,D2,timing,comorbidity documented in preoperative assessment
CAD,D2,timing,comorbidity documented in preoperative assessment
AFIB,D2,timing,comorbidity documented in preoperative assessment
CKD,D2,timing,comorbidity documented in preoperative assessment
CANCER,D2,timing,comorbidity documented in preoperative assessment
COGNITIVE_SCORE,D3,instrument,named cognitive instrument score; instrument membership overrides timing
COGNITIVE_CATEGORY,D3,instrument,named cognitive instrument category; instrument membership overrides timing
CLOCK_SCORE,D3,instrument,clock-drawing instrument score; instrument membership overrides timing
DCDT_SCORE,D3,instrument,dCDT instrument score; instrument membership overrides timing
DCDT_COMMAND,D3,instrument,dCDT command clock subscale; instrument membership overrides timing
DCDT_COPY,D3,instrument,dCDT copy clock subscale; instrument membership overrides timing
PROCEDURE_NAME,D4,timing,surgical procedure recorded at time of operation
BASE_PROCEDURE_1,D4,timing,surgical procedure recorded at time of operation
CPT_CODE,D4,timing,procedure CPT code assigned at time of operation
CPT_1,D4,timing,procedure CPT code assigned at time of operation
SERVICE_LINE,D4,timing,surgical service recorded at time of operation
ANESTHESIA_TYPE,D4,timing,anesthesia type administered intraoperatively
CASE_DURATION,D4,timing,elapsed operative time; intraoperative variable by timing
OPERATIVE_TIME,D4,timing,elapsed operative time; intraoperative variable by timing
EMERGENT,D4,timing,emergent case flag set at time of surgery
EMERGENT_CASE,D4,timing,emergent case flag set at time of surgery
AVG_ABP_MEAN,D4,timing,intraoperative arterial blood pressure mean
ABP_LESS_THAN_60_COUNT,D4,timing,count of intraoperative low arterial pressure events
BIS_INDEX_LESS_30_COUNT,D4,timing,count of intraoperative low BIS index events
SD_BIS_INDEX,D4,timing,intraoperative BIS index variability
TOTAL_MIDAZOLAM_MG,D4,timing,total intraoperative midazolam dose
ISO_SEV_TOTAL,D4,timing,total volatile anesthetic exposure
ISO_SEV_AVG,D4,timing,average volatile anesthetic exposure
_30_DAY_MORTALITY,D5,analytic_role,postoperative outcome realized after surgery
MORTALITY_30,D5,analytic_role,30-day mortality outcome realized postoperatively
LOS,D5,analytic_role,length of stay determined postoperatively
LENGTH_OF_STAY,D5,analytic_role,length of stay determined postoperatively
READMISSION_30,D5,analytic_role,30-day readmission outcome realized postoperatively
READMISSION,D5,analytic_role,readmission outcome realized postoperatively
DISCHARGE_DISPOSITION,D5,analytic_role,disposition known only at discharge
DISCHARGE_DISPO,D5,analytic_role,disposition known only at discharge
COMPLICATIONS,D5,analytic_role,postoperative complication status
ORAL_MORPHINE_EQUIV_MG_POD_DAY6,D5,analytic_role,postoperative opioid use realized after surgery
;
run;

/* Apply the lookup. The ON clause scopes the join to rows that are not     */
/* already OUT_OF_SCOPE, so identifier exclusions are not overridden.       */
proc sql;
  create table work.domain_staging4 as
    select ds.*,
           coalesce(dl.domain,           ds.domain)           as domain_final    length=16,
           coalesce(dl.domain_rationale, ds.domain_rationale) as rationale_final length=200,
           coalesce(dl.assign_rule,      ds.assign_rule)      as rule_final      length=20
    from work.domain_staging3 as ds
    left join work.domain_lookup as dl
      on upcase(ds.varname) = dl.varname_u
     and ds.domain not in ('OUT_OF_SCOPE');
quit;

data work.domain_staging4;
  set work.domain_staging4;
  domain           = domain_final;
  domain_rationale = rationale_final;
  assign_rule      = rule_final;

  /* A matched, dictionary-documented variable with no lookup entry is an
     INCOMPLETE MAP, not an out-of-scope variable. It is parked here and
     GUARD 5 below fails the run so the omission cannot pass review. */
  if domain = '' then do;
    domain           = 'OUT_OF_SCOPE';
    domain_rationale = 'not in domain lookup; lookup is incomplete';
    assign_rule      = 'unrecognised';
    stat_route       = '';
  end;

  /* Any row demoted to OUT_OF_SCOPE must not carry a statistic route */
  if domain = 'OUT_OF_SCOPE' then stat_route = '';

  drop domain_final rationale_final rule_final;
run;

/* Denominator note on the extension-sourced blocks */
data work.domain_staging4;
  set work.domain_staging4;
  length denominator_note $300;
  if source_dataset = 'master_data_merged' then denominator_note = "&D3_DENOM_NOTE";
  else denominator_note = '';
run;

/* ---- Write g.var_domain_map: the ONE permanent artifact of this phase --- */
/* g.analysis_base and g.master_data_merged remain read-only. This dataset  */
/* is the explicitly authorized exception (see 17-CONTEXT.md).              */
data g.var_domain_map;
  length varname $32 sas_label $256 vtype $4 n_levels 8 hi_cardinality_flag $3
         stat_route $8 domain $16 domain_rationale $200
         assign_rule $20 source_dataset $32 denominator_note $300
         dict_name $60 match_how $8;
  set work.domain_staging4;
  keep varname sas_label vtype n_levels hi_cardinality_flag stat_route
       domain domain_rationale assign_rule source_dataset denominator_note
       dict_name match_how;
run;

proc sort data=g.var_domain_map; by domain varname; run;

%put NOTE: [17-S4] g.var_domain_map written.;


/* ---- Export the crosswalk BEFORE the guards ---------------------------- */
/* The export runs first deliberately. GUARD 5 is expected to fail on the   */
/* first pass while the lookup is incomplete, and the reviewer needs the    */
/* CSV in hand to see exactly which variables still need lookup entries.    */
proc export data=g.var_domain_map
  outfile="&qc_path.\17_var_domain_map_review.csv"
  dbms=csv replace;
run;

%put NOTE: [17-S4] qc\17_var_domain_map_review.csv exported for Checkpoint 1 review.;


/* =========================================================================
   SECTION 4 GUARDS: hard exit criteria
   ========================================================================= */

/* GUARD 1: blank rationale on any assigned variable */
%let n_blank = 0;
proc sql noprint;
  select count(*) into :n_blank trimmed
  from g.var_domain_map
  where missing(domain_rationale) and domain ne 'OUT_OF_SCOPE';
quit;

%macro check_blank_rationale;
  %if &n_blank > 0 %then %do;
    %fail_out(msg=&n_blank assigned variables have a blank domain_rationale -- Checkpoint 1 cannot proceed);
  %end;
  %put NOTE: [17-S4] Blank-rationale guard passed.;
%mend check_blank_rationale;
%check_blank_rationale;

/* GUARD 2: VARnn positional name survivor */
%let n_varnn_map = 0;
proc sql noprint;
  select count(*) into :n_varnn_map trimmed
  from g.var_domain_map
  where prxmatch('/^VAR\d+$/', strip(varname)) > 0;
quit;

%macro check_varnn_map;
  %if &n_varnn_map > 0 %then %do;
    %fail_out(msg=&n_varnn_map VARnn positional names survived into g.var_domain_map -- the dictionary match is defective);
  %end;
  %put NOTE: [17-S4] VARnn guard passed.;
%mend check_varnn_map;
%check_varnn_map;

/* GUARD 3: stat_route set on every in-scope variable */
%let n_blank_route = 0;
proc sql noprint;
  select count(*) into :n_blank_route trimmed
  from g.var_domain_map
  where domain ne 'OUT_OF_SCOPE'
    and stat_route not in ('MEANS','FREQ');
quit;

%macro check_blank_route;
  %if &n_blank_route > 0 %then %do;
    %fail_out(msg=&n_blank_route in-scope variables have a stat_route that is neither MEANS nor FREQ);
  %end;
  %put NOTE: [17-S4] Stat-route guard passed.;
%mend check_blank_route;
%check_blank_route;

/* GUARD 4: identifier leak into statistics */
%let n_id_leak = 0;
proc sql noprint;
  select count(*) into :n_id_leak trimmed
  from g.var_domain_map
  where stat_route ne ''
    and domain ne 'OUT_OF_SCOPE'
    and (
      varname in ('PRECEDE_STUDY_ID','PRECEDE_STUDY_ID_1',
                  'ENCRYPTED_MRN','ENCRYPTED_ENCOUNTER')
      or prxmatch('/(^|_)(ID|MRN)(_|$)/', strip(upcase(varname))) > 0
    );
quit;

%macro check_id_leak;
  %if &n_id_leak > 0 %then %do;
    %fail_out(msg=&n_id_leak identifier variables have a stat_route set and are not OUT_OF_SCOPE);
  %end;
  %put NOTE: [17-S4] Identifier-leak guard passed.;
%mend check_id_leak;
%check_id_leak;

/* GUARD 5: dictionary-documented variables with no domain assignment
   -----------------------------------------------------------------
   A variable that matched the PRECEDE dictionary but is absent from the
   Section 4 lookup is an incomplete map. Previously it became OUT_OF_SCOPE
   with a non-blank rationale, so GUARD 1 and GUARD 3 both passed and the
   omission was invisible. This guard makes it a hard failure. */
%let n_unassigned = 0;
proc sql noprint;
  select count(*) into :n_unassigned trimmed
  from g.var_domain_map
  where assign_rule = 'unrecognised' and match_how ne 'NONE';
quit;

%macro check_unassigned;
  %if &n_unassigned > 0 %then %do;
    %put ERROR: [17-S4] The following documented variables have no lookup entry.;
    proc print data=g.var_domain_map noobs;
      where assign_rule = 'unrecognised' and match_how ne 'NONE';
      var varname sas_label vtype n_levels;
      title "Documented variables missing from the Section 4 domain lookup";
    run;
    title;
    %fail_out(msg=&n_unassigned dictionary-documented variables have no entry in the Section 4 domain lookup -- filter the review CSV on assign_rule=unrecognised and add them before Checkpoint 1);
  %end;
  %put NOTE: [17-S4] Unassigned-documented guard passed.;
%mend check_unassigned;
%check_unassigned;


/* =========================================================================
   END OF WAVE 1 (Sections 1 to 4)
   -------------------------------------------------------------------------
   Checkpoint 1: Gerard reviews qc\17_var_domain_map_review.csv
   variable-by-variable -- domain, domain_rationale, and stat_route, paying
   closest attention to rows where assign_rule is analytic_role and to
   numeric variables near the 10-level routing boundary.

   Sections 5 to 11 (sentinel recode, PROC MEANS, PROC FREQ, suppression,
   ODS EXCEL workbook, QC artifact) are NOT in this file yet. Setting
   DOMAIN_MAP_APPROVED to 1 will not produce statistics until they are
   written. Each of those sections must open with %gate_stats.
   ========================================================================= */

%put NOTE: ==== Phase 17 Wave 1 complete. Checkpoint 1 pending. ====;
%put NOTE: Review qc\17_var_domain_map_review.csv variable-by-variable.;
%put NOTE: Sections 5 to 11 are not yet written -- see the header block.;

%restore_log;
