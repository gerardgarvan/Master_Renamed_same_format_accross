/*==========================================================================
  Program : 17_summary_stats_by_domain.sas
  Purpose : Wave 0 discovery and Wave 1 domain map for five-domain descriptive
            summary statistics of every PRECEDE-dictionary-documented variable
            in g.analysis_base (extended with frailty, cognitive, and
            intraoperative-physiologic columns from g.master_data_merged).

  SCOPE OF THIS FILE:
            This file contains Sections 0, 0b, and 1 through 11 (complete).
            Section 9: ODS EXCEL workbook assembly (KEY, D1-D5, Crosswalk, QC)
            Section 10: QC text artifact
            Section 11: Output verification and log restore
            Sections 5 to 11 are gated by %gate_stats and only run when
            DOMAIN_MAP_APPROVED = 1 (set after Checkpoint 1 review).

  Output  : qc\17_discovery.txt                 (Wave 0 plus Section 1 coverage)
            g.var_domain_map                    (Wave 1, the ONE permanent artifact)
            qc\17_var_domain_map_review.csv     (Wave 1, Checkpoint 1 review)
            qc\17_summary_stats_by_domain.xlsx  (Wave 3, eight-tab deliverable)
            qc\17_summary_stats_by_domain.txt   (Wave 3, QC text artifact)

  Reads   : g.analysis_base            (read-only)
            g.master_data_merged       (read-only)
            docs\precede_dictionary.csv

  Created : 2026-09-03
  Revised : 2026-09-10  (review fixes -- see REVISION NOTES)

  PCM compliance:
    - No bare open-code %IF or %DO (all conditional logic inside named macros)
    - No apostrophes and no embedded semicolons in %PUT text
    - Every %abort cancel inside %fail_out only
    - No &SQLOBS; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - Every SELECT INTO target is initialised with %let first, so a zero-row
      query leaves an empty macro variable rather than an unresolved reference
    - dictionary.columns.TYPE is char/num, not 1/2
    - ASCII only (session encoding is not UTF-8 on this project)
    - No semicolons inside DATALINES rows (plain DATALINES stops at one)
    - %sysfunc(countw()) is never called on a possibly-empty list; %nwords
      wraps it because an empty argument is an ERROR, not zero

  REVISION NOTES (2026-09-10):
    R1  Dictionary import is now guarded: required columns must exist in
        dict_raw, work.dict_u must have rows, and Section 3 must match at
        least one variable. Previously a mis-headed CSV produced an empty
        map that passed every guard.
    R2  stat_route no longer counts sentinel values as levels: n_levels is
        reduced by one for variables in work.sentinel_applicable, and the
        raw count is kept as n_levels_raw for review. A missing n_levels
        leaves stat_route blank so GUARD 3 fails instead of routing to FREQ.
    R3  Section 4 lookup keys must be unique, and the row count is asserted
        before and after the lookup join.
    R4  %gate_stats now routes through %fail_out (single %abort cancel).
    R5  %fail_out only closes ODS EXCEL when a destination is open.
    R6  logs_path is checked before the log is routed.
    R7  Numeric keys use best32. and the padded test uses the OBSERVED width
        of the character side, not a fixed 12. Padding is also tried on the
        base side when the base key is numeric and the merged key is char.
    R8  Base-key duplicate and missing counts are reported in discovery.
    R9  Key sampling stops after 10 output rows, not 5000 input rows.
    R10 Year candidate order is deterministic (SURG-containing names first).
    R11 Every cognitive score column is tested, not an arbitrary one.
    R12 Denominator note is read with symget, not a quoted macro reference.
    R13 g.var_domain_map carries map_status (INCOMPLETE until all guards
        pass, then REVIEW) and n_dict_matches (tie count for review).
    R14 Section 4 lookup extended to all 82 dictionary-documented variables
        from the 2026-09-10 review CSV. Entries whose rationale contains
        REVIEW are judgement calls for Checkpoint 1. LATITUDE and LONGITUDE
        are explicitly OUT_OF_SCOPE (privacy_exclusion).
    R15 Lookup keys are upcased and stripped on load; the join strips the
        staging varname; a zero-hit lookup fails before GUARD 5.
    R16 ROOT CAUSE of the empty lookup: DATALINES stops at the first line
        containing a semicolon. All rationales now use -- instead.
    R17 %nwords replaces %sysfunc(countw()) everywhere (empty list = ERROR).
    R18 Extension columns from g.master_data_merged may take a lookup entry
        even when absent from the PRECEDE dictionary; stat_route is
        recomputed after the lookup; unmapped extension columns WARN.
        Lookup entries added for the 13 extension columns seen in the log.
    R19 Sections 5-11 review fixes (2026-09-10):
        - PROC MEANS stackodsoutput names the variable column Variable, not
          _Label_; pooled vs per-year rows are told apart by a missing class
          value, not _TYPE_ (the ODS Summary table has no _TYPE_).
        - ODS ONEWAYFREQS/CROSSTABFREQS Table column reads Table VARNAME;
          the level scan takes the NON-MISSING F_ column; crosstab marginal
          rows (_TYPE_ ne 11) are dropped.
        - SYMGET cannot be called through %sysfunc; &D3_DENOM_NOTE is used.
        - d5_note contained a semicolon that ended the %let early.
        - n_years was the first group count (always 1); now %nwords.
        - sas_label is joined from g.var_domain_map for the wide datasets;
          transposes guard the empty-domain case.
        - work.sentinel_log column is n_recoded, not n_sentinel.
        - Crosswalk PROC REPORT BY statement removed (one table per variable).
        - ODS EXCEL: sheet_interval=now starts each new tab; none is set
          only after the first table on the tab has been written.
        - Suppressed continuous cells display as -- via formats, not as dot.
        - year_variable must be non-empty before Section 6.
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
/* ods_excel_open is set to 1 by any later section that opens ODS EXCEL,   */
/* so a failure before that point does not emit a spurious close warning.  */
%global ods_excel_open;
%let ods_excel_open = 0;

%macro fail_out(msg=);
  %put ERROR: &msg;
  %if &ods_excel_open = 1 %then %do;
    ods excel close;
  %end;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;

/* ---- nwords: word count that is safe on an empty list ------------------ */
/* %sysfunc(countw()) with an empty argument is an ERROR (too few          */
/* arguments), not 0. The 2026-09-10 run hit this in the cognitive guard.  */
%macro nwords(list);
  %if %length(%superq(list)) = 0 %then 0;
  %else %sysfunc(countw(%superq(list)));
%mend nwords;

/* ---- Checkpoint 1 gate macro (for Sections 5 to 11 when written) ------- */
%macro gate_stats;
  %if &DOMAIN_MAP_APPROVED ne 1 %then %do;
    %fail_out(msg=Domain map awaiting Checkpoint 1 approval -- run stopped before the statistics sections);
  %end;
%mend gate_stats;

/* ---- Directory preconditions (logs first, before the log is routed) ---- */
%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %fail_out(msg=&label directory not found: &path);
  %end;
%mend check_dir;
%check_dir(path=&logs_path, label=logs);

%route_log;
libname g "&g_path";

%put NOTE: ==== Phase 17 summary-stats-by-domain starting ====;
%put NOTE: SUPPRESS_MAX=&SUPPRESS_MAX SUPPRESS_LABEL=&SUPPRESS_LABEL;

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
%mend set_key_len;
%set_key_len;

/* Observed key widths. The DECLARED length of a character key says nothing */
/* about how wide the stored values are, and a numeric key wider than 12    */
/* digits would be mangled by best12. Both feed key_norm_len, and the char  */
/* side width is the zero-padding width tested in Section 1.                */
%let key_obs_len_base   = 0;
%let key_obs_len_merged = 0;

%macro obs_key_len;
  proc sql noprint;
    %if &key_type_base = char %then %do;
      select max(length(strip(PRECEDE_STUDY_ID))) into :key_obs_len_base trimmed
      from g.analysis_base where not missing(PRECEDE_STUDY_ID);
    %end;
    %else %do;
      select max(length(strip(put(PRECEDE_STUDY_ID, best32.)))) into :key_obs_len_base trimmed
      from g.analysis_base where not missing(PRECEDE_STUDY_ID);
    %end;
    %if &key_type_merged = char %then %do;
      select max(length(strip(PRECEDE_STUDY_ID))) into :key_obs_len_merged trimmed
      from g.master_data_merged where not missing(PRECEDE_STUDY_ID);
    %end;
    %else %do;
      select max(length(strip(put(PRECEDE_STUDY_ID, best32.)))) into :key_obs_len_merged trimmed
      from g.master_data_merged where not missing(PRECEDE_STUDY_ID);
    %end;
  quit;
  %if %length(&key_obs_len_base)   = 0 %then %let key_obs_len_base   = 0;
  %if %length(&key_obs_len_merged) = 0 %then %let key_obs_len_merged = 0;
  %if %eval(&key_obs_len_base   > &key_norm_len) %then %let key_norm_len = &key_obs_len_base;
  %if %eval(&key_obs_len_merged > &key_norm_len) %then %let key_norm_len = &key_obs_len_merged;
  %put NOTE: [17-discovery] observed key width base=&key_obs_len_base merged=&key_obs_len_merged;
  %put NOTE: [17-discovery] normalised key length = &key_norm_len;
%mend obs_key_len;
%obs_key_len;

/* ---- Sample 10 non-missing key values from each dataset ---------------- */
/* Stops after 10 OUTPUT rows, so a leading run of missing keys cannot     */
/* leave the sample short.                                                  */
%let key_sample_base   = ;
%let key_sample_merged = ;

%macro sample_keys;
  data work._ksb;
    set g.analysis_base(keep=PRECEDE_STUDY_ID);
    length k $&key_norm_len;
    if missing(PRECEDE_STUDY_ID) then delete;
    %if &key_type_base = num %then %do;
      k = strip(put(PRECEDE_STUDY_ID, best32.));
    %end;
    %else %do;
      k = strip(PRECEDE_STUDY_ID);
    %end;
    output;
    _nout + 1;
    if _nout >= 10 then stop;
    keep k;
  run;

  data work._ksm;
    set g.master_data_merged(keep=PRECEDE_STUDY_ID);
    length k $&key_norm_len;
    if missing(PRECEDE_STUDY_ID) then delete;
    %if &key_type_merged = num %then %do;
      k = strip(put(PRECEDE_STUDY_ID, best32.));
    %end;
    %else %do;
      k = strip(PRECEDE_STUDY_ID);
    %end;
    output;
    _nout + 1;
    if _nout >= 10 then stop;
    keep k;
  run;

  proc sql noprint;
    select k into :key_sample_base separated by '|'   from work._ksb;
    select k into :key_sample_merged separated by '|' from work._ksm;
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

/* Base-side key uniqueness is REPORTED, not enforced. Duplicate base keys  */
/* do not inflate the left merge, but they tell the reviewer whether the    */
/* unit of analysis is one row per patient before patient-level statistics */
/* are planned.                                                             */
%let n_base_key_dups    = 0;
%let n_base_missing_key = 0;

proc sql noprint;
  select count(*) into :n_base_key_dups trimmed
  from (
    select PRECEDE_STUDY_ID
    from g.analysis_base
    where not missing(PRECEDE_STUDY_ID)
    group by PRECEDE_STUDY_ID
    having count(*) > 1
  );

  select count(*) into :n_base_missing_key trimmed
  from g.analysis_base
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

/* Deterministic order: names containing SURG first, then alphabetical, so */
/* the first candidate is the same on every run and is the surgery year     */
/* whenever one exists.                                                     */
%let year_cand_list = ;
proc sql noprint;
  select name into :year_cand_list separated by ' '
  from work.cols_base
  where index(name,'YEAR') > 0 and vtype = 'num'
  order by (index(name,'SURG') = 0), name;
quit;

/* (an earlier pick_year draft was removed; %pick_year_safe below is the one used) */

/* The empty-dataset branch above must not reference an undefined variable. */
%macro pick_year_safe;
  %global year_variable n_year_cands year_note;
  %let n_year_cands = %nwords(&year_cand_list);

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
      %let year_note = &n_year_cands numeric YEAR candidates found. Using &year_variable (SURG-containing names ranked first). Confirm the choice at Checkpoint 1.;
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
  %let n_num = %nwords(&sent_num_all);
  %let n_chr = %nwords(&sent_chr_all);

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
    put "Observed key width: base=&key_obs_len_base  merged=&key_obs_len_merged";
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
    put "Duplicate PRECEDE_STUDY_ID count in g.analysis_base (missing excluded): &n_base_key_dups";
    put "Rows with a MISSING PRECEDE_STUDY_ID in g.analysis_base: &n_base_missing_key";
    put "REVIEW: duplicate base keys mean g.analysis_base is not one row per patient.";
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
/* fmt=Z with width= is used only when the base key is numeric and the      */
/* merged key is character and zero-padded (see %pick_key_format).          */
%macro norm_base_key(fmt=BEST, width=12);
  data work.base_keyed;
    set g.analysis_base;
    length _key_c $&key_norm_len;
    %if &key_type_base = num %then %do;
      %if &fmt = Z %then %do;
        _key_c = put(PRECEDE_STUDY_ID, z&width..);
      %end;
      %else %do;
        _key_c = strip(put(PRECEDE_STUDY_ID, best32.));
      %end;
    %end;
    %else %do;
      _key_c = strip(PRECEDE_STUDY_ID);
    %end;
    drop PRECEDE_STUDY_ID;
    rename _key_c = PRECEDE_STUDY_ID;
  run;
%mend norm_base_key;
%norm_base_key(fmt=BEST);


/* ---- 5. Normalise the extension key, choosing the format empirically --- */
/* The sampled values in the discovery report tell the reviewer what the    */
/* keys look like, but the program must not depend on anyone eyeballing     */
/* them. When the merged key is numeric, both candidate representations are */
/* tested against the base keys and the one that actually matches is used.  */
/* best32. gives 123456789 and z<w>. gives 000123456789 -- picking wrong    */
/* yields a join that matches nothing while the row count still passes.    */
/* The padding width is the OBSERVED width of the character side, not 12.  */
%macro build_ext_cols(fmt=, width=12);
  data work.merged_ext_cols;
    set g.master_data_merged (keep=PRECEDE_STUDY_ID &extension_keep_list);
    length _key_c $&key_norm_len;
    if missing(PRECEDE_STUDY_ID) then delete;
    %if &key_type_merged = num %then %do;
      %if &fmt = Z %then %do;
        _key_c = put(PRECEDE_STUDY_ID, z&width..);
      %end;
      %else %do;
        _key_c = strip(put(PRECEDE_STUDY_ID, best32.));
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

  %if &key_type_merged = &key_type_base %then %do;
    /* Same type on both sides: no representation choice to make. */
    %let key_fmt = SAME_TYPE;
    %build_ext_cols(fmt=BEST);
    %count_key_overlap(into=n_best);
    %put NOTE: [17-S1] same-type key (&key_type_base): &n_best extension rows match a base key.;
    %if &n_best = 0 %then %do;
      %fail_out(msg=Join key produced zero matches against g.analysis_base -- padding or case differs between the two datasets);
    %end;
  %end;
  %else %if &key_type_merged = num %then %do;
    /* Merged numeric, base character: pad the MERGED side to the base width */
    %build_ext_cols(fmt=BEST);
    %count_key_overlap(into=n_best);
    %put NOTE: [17-S1] best32. representation of merged key: &n_best matches.;

    %if &n_best = 0 %then %do;
      %put WARNING: [17-S1] best32. matched nothing. Testing zero-padded z&key_obs_len_base. on the merged key.;
      %build_ext_cols(fmt=Z, width=&key_obs_len_base);
      %count_key_overlap(into=n_z);
      %put NOTE: [17-S1] z&key_obs_len_base. representation: &n_z matches.;
      %if &n_z = 0 %then %do;
        %fail_out(msg=Neither best32. nor z&key_obs_len_base. matched any base key -- the numeric merged key cannot be reconciled with the character base key);
      %end;
      %let key_fmt = Z&key_obs_len_base._MERGED;
    %end;
    %else %do;
      %let key_fmt = BEST_MERGED;
    %end;
  %end;
  %else %do;
    /* Base numeric, merged character: pad the BASE side to the merged width */
    %build_ext_cols(fmt=CHAR);
    %count_key_overlap(into=n_best);
    %put NOTE: [17-S1] best32. representation of base key: &n_best matches.;

    %if &n_best = 0 %then %do;
      %put WARNING: [17-S1] best32. matched nothing. Testing zero-padded z&key_obs_len_merged. on the base key.;
      %norm_base_key(fmt=Z, width=&key_obs_len_merged);
      %count_key_overlap(into=n_z);
      %put NOTE: [17-S1] z&key_obs_len_merged. representation: &n_z matches.;
      %if &n_z = 0 %then %do;
        %fail_out(msg=Neither best32. nor z&key_obs_len_merged. matched any merged key -- the numeric base key cannot be reconciled with the character merged key);
      %end;
      %let key_fmt = Z&key_obs_len_merged._BASE;
    %end;
    %else %do;
      %let key_fmt = BEST_BASE;
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
/* Every column matching COGNI and SCORE is tested. A single INTO without   */
/* ORDER BY picked an arbitrary one and could pass while another was empty. */
proc sql noprint;
  select name into :cog_col separated by ' '
  from work.ext_candidates
  where index(upcase(name),'COGNI') > 0 and index(upcase(name),'SCORE') > 0
  order by name;
quit;

%macro check_cog_populated;
  %local n_cog i c n_this;
  %let n_cog = %nwords(&cog_col);
  %if &n_cog = 0 %then %do;
    %put WARNING: [17-S1] No cognitive score column (COGNI and SCORE) in ext_candidates. Cognitive guard skipped.;
  %end;
  %else %do;
    %do i = 1 %to &n_cog;
      %let c = %scan(&cog_col, &i);
      %let n_this = 0;
      proc sql noprint;
        select count(*) into :n_this trimmed
        from work.analysis_base_ext
        where not missing(&c);
      quit;
      %if &n_this = 0 %then %do;
        %fail_out(msg=Cognitive score column &c is all-missing in work.analysis_base_ext -- the join key silently failed to match);
      %end;
      %put NOTE: [17-S1] Cognitive guard: &c has &n_this non-missing values.;
      %let n_cog_nonmiss = &n_this;
    %end;
    %put NOTE: [17-S1] Cognitive guard passed on &n_cog column(s).;
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
  %let n_en = %nwords(&ext_num_list);
  %let n_ec = %nwords(&ext_chr_list);

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

/* Required columns must exist. A mis-headed CSV previously produced a     */
/* RENAME warning, an all-missing sas_name, an empty dict_u, and a map in   */
/* which every variable was OUT_OF_SCOPE -- and every guard passed.         */
%let n_dict_cols = 0;
proc sql noprint;
  select count(*) into :n_dict_cols trimmed
  from dictionary.columns
  where libname='WORK' and memname='DICT_RAW'
    and upcase(name) in ('SHEET','DICT_NAME','DICT_TYPE','DESCRIPTION','SAS_NAME');
quit;

%macro check_dict_cols;
  %if &n_dict_cols ne 5 %then %do;
    %fail_out(msg=precede_dictionary.csv must have columns sheet dict_name dict_type description sas_name -- found &n_dict_cols of 5);
  %end;
  %put NOTE: [17-S2] Dictionary column check passed.;
%mend check_dict_cols;
%check_dict_cols;

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

%let n_dict_u = 0;
proc sql noprint;
  select count(*) into :n_dict_u trimmed from work.dict_u;
quit;

%macro check_dict_rows;
  %if &n_dict_u = 0 %then %do;
    %fail_out(msg=work.dict_u has no rows -- every sas_name in precede_dictionary.csv is blank);
  %end;
  %put NOTE: [17-S2] &n_dict_u documented names in work.dict_u.;
%mend check_dict_rows;
%check_dict_rows;

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

/* Match counts: dictionary entries matching each column at its best rank. */
/* Carried into g.var_domain_map as n_dict_matches so ties are visible in  */
/* the review CSV, not only in the log.                                     */
%let n_ties_ext = 0;
proc sql noprint;
  create table work.match_counts_ext as
    select a.varname, count(*) as n_at_best
    from work.doc_all_ext as a
    inner join work.var_domain_raw as b
      on a.varname = b.varname and a.match_rank = b.match_rank
    group by a.varname;

  create table work.match_ties_ext as
    select varname, n_at_best
    from work.match_counts_ext
    where n_at_best > 1;

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

%macro check_any_matched;
  %if &n_matched = 0 %then %do;
    %fail_out(msg=No column of work.analysis_base_ext matched any dictionary sas_name -- the dictionary and the data cannot be reconciled);
  %end;
%mend check_any_matched;
%check_any_matched;


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
         source_dataset $32 n_dict_matches 8;
  set work.data_only;
  domain           = 'OUT_OF_SCOPE';
  domain_rationale = 'not in PRECEDE dictionary';
  assign_rule      = 'data_only';
  dict_name        = '';
  dict_type        = '';
  description      = '';
  match_how        = 'NONE';
  source_dataset   = 'analysis_base_ext';
  n_dict_matches   = 0;
run;

/* The previous version had an open-code %DO placeholder here. %DO is not   */
/* valid outside a macro definition and would abort the run. It was also    */
/* redundant: the SQL join below assigns source_dataset properly.           */
data work.domain_staging;
  length varname $32 vtype $4 vlen 8 sas_label $256
         dict_name $60 dict_type $20 description $300 match_how $8
         domain $16 domain_rationale $200 assign_rule $20
         source_dataset $32 stat_route $8 n_levels 8 n_levels_raw 8
         n_dict_matches 8 denominator_note $300;

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

/* Join n_levels, the sentinel flag, and the dictionary match count.       */
/* NLEVELS was computed on the raw data, so -999 and literal NULL each      */
/* count as one level. For a variable in work.sentinel_applicable that      */
/* level will disappear at the Section 5 recode, so it is subtracted here   */
/* before routing. The raw count is kept as n_levels_raw for review.        */
proc sql;
  create table work.domain_staging3 as
    select ds.*,
           nl.n_levels                  as n_levels_join,
           (sa.varname is not null)     as has_sentinel,
           mc.n_at_best                 as n_dict_matches_join
    from work.domain_staging2 as ds
    left join work.nlevels_ext as nl
      on upcase(ds.varname) = nl.varname_u
    left join work.sentinel_applicable as sa
      on upcase(ds.varname) = sa.varname
    left join work.match_counts_ext as mc
      on ds.varname = mc.varname;
quit;

data work.domain_staging3;
  set work.domain_staging3;
  n_levels_raw = n_levels_join;
  if missing(n_levels) then n_levels = n_levels_join;
  if has_sentinel = 1 and n_levels > . then n_levels = n_levels - 1;
  if missing(n_dict_matches) then n_dict_matches = coalesce(n_dict_matches_join, 0);
  drop n_levels_join has_sentinel n_dict_matches_join;
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
      /* A missing n_levels is less than 10 in SAS and would route to FREQ */
      /* silently. It is left blank so GUARD 3 fails the run.              */
      if      n_levels > . and n_levels <= 10 then stat_route = 'FREQ';
      else if n_levels > 10                   then stat_route = 'MEANS';
      else                                         stat_route = '';
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

   NO SEMICOLONS IN THE DATA LINES. Plain DATALINES ends at the first line
   containing a semicolon. The 2026-09-10 run loaded ZERO rows because the
   first rationale contained one, and every documented variable then came
   out unrecognised. Rationales use -- as the clause separator instead.

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
  varname_u   = upcase(strip(varname_u));
  domain      = upcase(strip(domain));
  assign_rule = strip(assign_rule);
datalines;
AGE_AT_SURGERY,D1,timing,captured at surgery registration -- sociodemographic descriptor
AGE_AT_ENCOUNTER,D1,timing,captured at encounter -- sociodemographic descriptor
SEX,D1,timing,recorded at registration -- sociodemographic descriptor
RACE,D1,timing,recorded at registration -- sociodemographic descriptor
ETHNICITY,D1,timing,recorded at registration -- sociodemographic descriptor
INSURANCE_TYPE,D1,analytic_role,payer type known preoperatively -- sociodemographic proxy
PAYER,D1,analytic_role,payer type known preoperatively -- sociodemographic proxy
MARITAL_STATUS,D1,timing,recorded at registration -- sociodemographic descriptor
MARITAL,D1,timing,recorded at registration -- sociodemographic descriptor
ZIP_CODE,D1,timing,geographic locator recorded at registration -- sociodemographic
ZIPCODE,D1,timing,geographic locator recorded at registration -- sociodemographic
STATE,D1,timing,geographic locator recorded at registration -- sociodemographic
ADMIT_BMI,D2,timing,captured at preoperative admission -- preoperative physiologic assessment
BMI,D2,timing,measured preoperatively -- standard preoperative assessment variable
FRAILTY_SCORE,D2,timing,frailty assessed before surgery -- preoperative assessment
FRAILTY_CATEGORY,D2,timing,frailty assessed before surgery -- preoperative assessment
FEELS_EXHAUSTED,D2,timing,frailty component captured preoperatively (Fried criteria)
FEELS_EXAUSTED,D2,timing,frailty component captured preoperatively (Fried criteria -- source spelling)
WEIGHT_LOSS,D2,timing,frailty component captured preoperatively (Fried criteria)
GRIP_STRENGTH,D2,timing,frailty component captured preoperatively (Fried criteria)
WEAK_GRIP_STRENGTH,D2,timing,frailty component captured preoperatively (Fried criteria)
WALK_TIME,D2,timing,frailty component captured preoperatively (Fried criteria)
SLOW_WALKING_SPEED,D2,timing,frailty component captured preoperatively (Fried criteria)
PHYSICAL_ACTIVITY,D2,timing,frailty component captured preoperatively (Fried criteria)
LOW_PHYSICAL_ACTIVITY,D2,timing,frailty component captured preoperatively (Fried criteria)
ASA_CLASS,D2,analytic_role,preoperative risk classification assigned before surgery
ASA,D2,analytic_role,preoperative risk classification assigned before surgery
SMOKING_STATUS,D2,timing,preoperative habit assessment -- standard preoperative variable
SMOKING,D2,timing,preoperative habit assessment -- standard preoperative variable
HYPERTENSION,D2,timing,comorbidity documented in preoperative assessment
DIABETES,D2,timing,comorbidity documented in preoperative assessment
COPD,D2,timing,comorbidity documented in preoperative assessment
CHF,D2,timing,comorbidity documented in preoperative assessment
CAD,D2,timing,comorbidity documented in preoperative assessment
AFIB,D2,timing,comorbidity documented in preoperative assessment
CKD,D2,timing,comorbidity documented in preoperative assessment
CANCER,D2,timing,comorbidity documented in preoperative assessment
COGNITIVE_SCORE,D3,instrument,named cognitive instrument score -- instrument membership overrides timing
COGNITIVE_CATEGORY,D3,instrument,named cognitive instrument category -- instrument membership overrides timing
CLOCK_SCORE,D3,instrument,clock-drawing instrument score -- instrument membership overrides timing
DCDT_SCORE,D3,instrument,dCDT instrument score -- instrument membership overrides timing
DCDT_COMMAND,D3,instrument,dCDT command clock subscale -- instrument membership overrides timing
DCDT_COPY,D3,instrument,dCDT copy clock subscale -- instrument membership overrides timing
PROCEDURE_NAME,D4,timing,surgical procedure recorded at time of operation
BASE_PROCEDURE_1,D4,timing,surgical procedure recorded at time of operation
CPT_CODE,D4,timing,procedure CPT code assigned at time of operation
CPT_1,D4,timing,procedure CPT code assigned at time of operation
SERVICE_LINE,D4,timing,surgical service recorded at time of operation
ANESTHESIA_TYPE,D4,timing,anesthesia type administered intraoperatively
CASE_DURATION,D4,timing,elapsed operative time -- intraoperative variable by timing
OPERATIVE_TIME,D4,timing,elapsed operative time -- intraoperative variable by timing
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
ADMIT_SOURCE,D2,timing,admission source known at admission before surgery -- encounter context (REVIEW: could be argued D1)
BASE_PROCEDURE_CODE_1,D4,timing,procedure code assigned at time of operation
ASA__ANESTH_RECORD_,D2,analytic_role,preoperative risk classification from the anesthesia record -- ASA variant
CHARGES,D5,analytic_role,encounter charges accrue through discharge -- realized after surgery (REVIEW: consider excluding from descriptive summary)
CHARLSON_COMORBIDITY_INDEX,D2,timing,comorbidity burden index computed from preoperative diagnoses
COGNITIVEDISORDER_YN,D2,timing,cognitive disorder diagnosis flag is a comorbidity not a named instrument -- timing rule applies (REVIEW: D3 if treated as cognitive status)
COMPLICATION_SUM,D5,analytic_role,count of postoperative complications realized after surgery
DAY_OF_WEEK__CHAR_,D4,timing,day of week of the operative encounter -- scheduling characteristic (REVIEW: confirm anchor event)
DEATH_DATE_Y_N,D5,analytic_role,death indicator realized after surgery
DIABETES_YN,D2,timing,comorbidity documented in preoperative assessment
DISCHG_DISPOSITION,D5,analytic_role,disposition known only at discharge
EDUCATION,D1,timing,recorded at registration -- sociodemographic descriptor
EMPLOYEESTATUS,D1,timing,recorded at registration -- sociodemographic descriptor
FENTANYL_SUBLIMAZE_MG_INTRAOP_TO,D4,timing,total intraoperative opioid dose
HOLIDAYS,D4,timing,holiday indicator for the operative encounter -- scheduling characteristic (REVIEW: confirm anchor event)
HYDROMORPHONE_MG_INTRAOP_TOTAL,D4,timing,total intraoperative opioid dose
HYPERLIPIDEMIA_YN,D2,timing,comorbidity documented in preoperative assessment
HYPERTENSION_YN,D2,timing,comorbidity documented in preoperative assessment
ICD10_PRINCIPAL_DIAGNOSIS,D2,timing,principal diagnosis is the indication for surgery -- preoperative clinical characteristic (REVIEW: coded at discharge)
ICD10_PRINCIPAL_DIAGNOSIS_DESC,D2,timing,principal diagnosis description -- preoperative clinical characteristic (REVIEW: coded at discharge)
ICU_LOS_TOTAL_TIME_HOURS,D5,analytic_role,ICU length of stay determined postoperatively
INTRAOP_KETAMINE,D4,timing,intraoperative adjunct administered
ISO_EXP_INTRAOP_MAC_AVERAGE,D4,timing,average intraoperative volatile anesthetic exposure
ISO_EXP_INTRAOP_MAC_MINUTES_TOTA,D4,timing,total intraoperative volatile anesthetic exposure minutes
ISO_EXP_INTRAOP_MAC_TOTAL,D4,timing,total intraoperative volatile anesthetic exposure
ISO_EXP_INTRAOP_TOTAL,D4,timing,total intraoperative volatile anesthetic exposure
ISO_SEV_INTRAOP_MAC_AVERAGE,D4,timing,average intraoperative volatile anesthetic exposure (extension column)
KETAMINE_MG_INTRAOP_TOTAL,D4,timing,total intraoperative ketamine dose
LATITUDE,OUT_OF_SCOPE,privacy_exclusion,precise geolocation -- quasi-identifier not summarised (REVIEW: ZIP-level geography is the D1 locator)
LONGITUDE,OUT_OF_SCOPE,privacy_exclusion,precise geolocation -- quasi-identifier not summarised (REVIEW: ZIP-level geography is the D1 locator)
LIDOCAINE_MG_INTRAOP_TOTAL,D4,timing,total intraoperative lidocaine dose
LOS_IN_HOURS,D5,analytic_role,length of stay in hours determined postoperatively
MOVEMENTDISORDER_YN,D2,timing,comorbidity documented in preoperative assessment
ORAL_MORPHINE_EQUIV_INTRAOP_TOTA,D4,timing,total intraoperative opioid dose in oral morphine equivalents
ORAL_MORPHINE_EQUIV_MG_POD_DAY1,D5,analytic_role,postoperative opioid use realized after surgery
ORAL_MORPHINE_EQUIV_MG_POD_DAY2,D5,analytic_role,postoperative opioid use realized after surgery
ORAL_MORPHINE_EQUIV_MG_POD_DAY3,D5,analytic_role,postoperative opioid use realized after surgery
ORAL_MORPHINE_EQUIV_MG_POD_DAY4,D5,analytic_role,postoperative opioid use realized after surgery
ORAL_MORPHINE_EQUIV_MG_POD_DAY5,D5,analytic_role,postoperative opioid use realized after surgery
ORAL_MORPHINE_EQUIV_MG_POD_DAY7,D5,analytic_role,postoperative opioid use realized after surgery
PATIENT_TYPE,D2,timing,encounter type (inpatient or outpatient) set before surgery -- encounter context (REVIEW: could be argued D4)
PREOP_BLOCK,D4,timing,regional block is an anesthetic intervention of the operative episode (REVIEW: name says preop)
PROPOFOL_MG_INTRAOP_TOTAL,D4,timing,total intraoperative propofol dose
ROOM_TYPE,D4,timing,room type of the operative encounter (REVIEW: confirm whether OR room or ward room -- if ward then D5)
RT_ADMIT_TO_AN_END_MINS,D4,timing,perioperative process interval anchored on the operative episode
RT_ADMIT_TO_AN_START_MINS,D4,timing,perioperative process interval anchored on the operative episode
RT_ADMIT_TO_BLOCK_END_MINS,D4,timing,perioperative process interval anchored on the operative episode
RT_ADMIT_TO_BLOCK_START_MINS,D4,timing,perioperative process interval anchored on the operative episode
RT_ADMIT_TO_DRESS_MINS,D4,timing,perioperative process interval anchored on the operative episode
RT_ADMIT_TO_INCISION_MINS,D4,timing,perioperative process interval anchored on the operative episode
RT_ADMIT_TO_RM_END_MINS,D4,timing,perioperative process interval anchored on the operative episode
RT_ADMIT_TO_RM_START_MINS,D4,timing,perioperative process interval anchored on the operative episode
RT_ANCHOR_TO_ADMIT_DAYS,D4,timing,scheduling interval from anchor to admission (REVIEW: confirm anchor definition)
RT_ANCHOR_TO_DISCHG_DAYS,D5,analytic_role,interval to discharge realized postoperatively
RT_ANCHOR_TO_SURGERY_DAYS,D4,timing,scheduling interval from anchor to surgery (REVIEW: confirm anchor definition)
RT_AN_START_TO_AN_END_MINS,D4,timing,anesthesia duration -- intraoperative variable by timing
RT_BLOCK_START_TO_BLOCK_END_MINS,D4,timing,block duration -- intraoperative variable by timing
RT_INCISE_TO_DRESS_MINS,D4,timing,incision to dressing duration -- intraoperative variable by timing
RT_RM_START_TO_AN_START_MINS,D4,timing,operating room process interval -- intraoperative variable by timing
RT_RM_START_TO_DRESS_MINS,D4,timing,operating room process interval -- intraoperative variable by timing
RT_RM_START_TO_EMERGENCE_MINS,D4,timing,operating room process interval -- intraoperative variable by timing
RT_RM_START_TO_INCISION_MINS,D4,timing,operating room process interval -- intraoperative variable by timing
RT_RM_START_TO_INDUCTION_MINS,D4,timing,operating room process interval -- intraoperative variable by timing
RT_RM_START_TO_RM_END_MINS,D4,timing,operating room time -- intraoperative variable by timing
SERVICE,D4,timing,surgical service recorded at time of operation
SEV_EXP_INTRAOP_TOTAL,D4,timing,total intraoperative volatile anesthetic exposure
SLEEP_APNEA_YN,D2,timing,comorbidity documented in preoperative assessment
SSDI_DEATH_DATE_Y_N,D5,analytic_role,death indicator from SSDI realized after surgery
SUFENTANIL_MG_INTRAOP_TOTAL,D4,timing,total intraoperative opioid dose
WEEKEND_INDICATOR,D4,timing,weekend indicator for the operative encounter -- scheduling characteristic (REVIEW: confirm anchor event)
ISO_SEV_MAC_TOTAL_EXP,D4,timing,total volatile anesthetic exposure (extension column)
ABP_LESS_THAN_70_COUNT,D4,timing,count of intraoperative low arterial pressure events (extension column)
ABP_LESS_THAN_80_COUNT,D4,timing,count of intraoperative low arterial pressure events (extension column)
BIS_INDEX_LESS_40_COUNT,D4,timing,count of intraoperative low BIS index events (extension column)
NIBP_LESS_60_COUNT,D4,timing,count of intraoperative low non-invasive blood pressure events (extension column)
NIBP_LESS_70_COUNT,D4,timing,count of intraoperative low non-invasive blood pressure events (extension column)
NIBP_LESS_80_COUNT,D4,timing,count of intraoperative low non-invasive blood pressure events (extension column)
SD_ABP_MEAN,D4,timing,intraoperative arterial pressure variability (extension column)
SD_NIBP_MEAN,D4,timing,intraoperative non-invasive blood pressure variability (extension column)
AVG_NIBP_MEAN,D4,timing,intraoperative non-invasive blood pressure mean (extension column)
AVG_BIS_INDEX,D4,timing,intraoperative BIS index mean (extension column)
UNINTENDED_WEIGHT_LOSS,D2,timing,frailty component captured preoperatively (Fried criteria -- extension column)
WEEK_GRIP_STRENGTH,D2,timing,frailty component captured preoperatively (Fried criteria -- extension column source spelling)
COGNITIVE_DISORDER,D3,timing,cognitive-status column from the extension block (REVIEW: align with COGNITIVEDISORDER_YN which is D2 -- choose one domain for both)
;
run;

/* Lookup keys must be unique. A duplicated varname_u would duplicate rows  */
/* through the left join below and every downstream guard would still pass. */
%let n_lookup_dups = 0;
proc sql noprint;
  select count(*) into :n_lookup_dups trimmed
  from (
    select varname_u from work.domain_lookup
    group by varname_u having count(*) > 1
  );
quit;

%macro check_lookup_unique;
  %if &n_lookup_dups > 0 %then %do;
    %fail_out(msg=&n_lookup_dups varname_u values are duplicated in the Section 4 domain lookup DATALINES);
  %end;
  %put NOTE: [17-S4] Lookup key uniqueness passed.;
%mend check_lookup_unique;
%check_lookup_unique;

%let n_stg3 = 0;
proc sql noprint;
  select count(*) into :n_stg3 trimmed from work.domain_staging3;
quit;

/* The lookup must actually hit. A run where every lookup key fails to     */
/* match (encoding, stray whitespace, empty DATALINES) would otherwise show */
/* up only as GUARD 5 listing variables that ARE in the lookup.             */
%let n_lookup_rows = 0;
%let n_lookup_hits = 0;
proc sql noprint;
  select count(*) into :n_lookup_rows trimmed from work.domain_lookup;
  select count(*) into :n_lookup_hits trimmed
  from work.domain_staging3 as ds
  where upcase(strip(ds.varname)) in (select varname_u from work.domain_lookup);
quit;

%macro check_lookup_hits;
  %if &n_lookup_rows = 0 %then %do;
    %fail_out(msg=work.domain_lookup has no rows -- the DATALINES block did not load);
  %end;
  %if &n_lookup_hits = 0 %then %do;
    %fail_out(msg=No variable in domain_staging3 matched any of the &n_lookup_rows lookup keys -- inspect work.domain_lookup varname_u values in the log before adding entries);
  %end;
  %put NOTE: [17-S4] Lookup loaded &n_lookup_rows keys; &n_lookup_hits staging rows match a key.;
%mend check_lookup_hits;
%check_lookup_hits;

/* Apply the lookup. The ON clause scopes the join to rows that are not     */
/* already OUT_OF_SCOPE, so identifier exclusions are not overridden.       */
/* EXCEPTION: columns pulled in from g.master_data_merged by the Section 0b */
/* concept filter are eligible even though they are not in the PRECEDE     */
/* dictionary. The 2026-09-10 run showed 22 of the 23 extension columns    */
/* (frailty components, ABP, NIBP, BIS) are absent from the dictionary;     */
/* without this exception the extension is pulled in and then discarded.   */
proc sql;
  create table work.domain_staging4 as
    select ds.*,
           coalesce(dl.domain,           ds.domain)           as domain_final    length=16,
           coalesce(dl.domain_rationale, ds.domain_rationale) as rationale_final length=200,
           coalesce(dl.assign_rule,      ds.assign_rule)      as rule_final      length=20
    from work.domain_staging3 as ds
    left join work.domain_lookup as dl
      on upcase(strip(ds.varname)) = dl.varname_u
     and (   ds.domain not in ('OUT_OF_SCOPE')
          or (ds.source_dataset = 'master_data_merged' and ds.assign_rule = 'data_only'));
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

  /* stat_route is recomputed here because an extension column rescued by  */
  /* the lookup was OUT_OF_SCOPE (blank route) at Section 3b.               */
  if domain ne 'OUT_OF_SCOPE' then do;
    if vtype = 'char' then stat_route = 'FREQ';
    else if vtype = 'num' then do;
      if      n_levels > . and n_levels <= 10 then stat_route = 'FREQ';
      else if n_levels > 10                   then stat_route = 'MEANS';
      else                                         stat_route = '';
    end;
  end;
  else stat_route = '';

  drop domain_final rationale_final rule_final;
run;

/* Row-count assertion across the lookup join */
%let n_stg4 = 0;
proc sql noprint;
  select count(*) into :n_stg4 trimmed from work.domain_staging4;
quit;

%macro check_lookup_rows;
  %if &n_stg4 ne &n_stg3 %then %do;
    %fail_out(msg=Row count changed across the domain lookup join: &n_stg3 before and &n_stg4 after);
  %end;
  %put NOTE: [17-S4] Lookup join row-count assertion passed: &n_stg4 rows.;
%mend check_lookup_rows;
%check_lookup_rows;

/* Denominator note on the extension-sourced blocks. symget reads the macro */
/* variable at run time, so the note text is never re-scanned for quotes or */
/* macro triggers.                                                          */
data work.domain_staging4;
  set work.domain_staging4;
  length denominator_note $300;
  if source_dataset = 'master_data_merged' then denominator_note = symget('D3_DENOM_NOTE');
  else denominator_note = '';
run;

/* ---- Write g.var_domain_map: the ONE permanent artifact of this phase --- */
/* g.analysis_base and g.master_data_merged remain read-only. This dataset  */
/* is the explicitly authorized exception (see 17-CONTEXT.md).              */
/* map_status is INCOMPLETE until every Section 4 guard passes, then       */
/* REVIEW. Sections 5 to 11 should test map_status as well as the           */
/* DOMAIN_MAP_APPROVED flag, so a map left behind by a failed run cannot be  */
/* mistaken for a reviewed one.                                              */
data g.var_domain_map;
  length varname $32 sas_label $256 vtype $4 n_levels 8 n_levels_raw 8
         hi_cardinality_flag $3 stat_route $8 domain $16 domain_rationale $200
         assign_rule $20 source_dataset $32 denominator_note $300
         dict_name $60 match_how $8 n_dict_matches 8 map_status $12;
  set work.domain_staging4;
  map_status = 'INCOMPLETE';
  keep varname sas_label vtype n_levels n_levels_raw hi_cardinality_flag
       stat_route domain domain_rationale assign_rule source_dataset
       denominator_note dict_name match_how n_dict_matches map_status;
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
    %fail_out(msg=&n_blank_route in-scope variables have a stat_route that is neither MEANS nor FREQ -- a blank route on a numeric means n_levels was missing);
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

/* Extension columns with no lookup entry are a WARNING, not a failure:    */
/* they are not dictionary-documented, so GUARD 5 does not own them.        */
%let n_ext_unmapped = 0;
proc sql noprint;
  select count(*) into :n_ext_unmapped trimmed
  from g.var_domain_map
  where source_dataset = 'master_data_merged' and domain = 'OUT_OF_SCOPE';
quit;

%macro warn_ext_unmapped;
  %if &n_ext_unmapped > 0 %then %do;
    %put WARNING: [17-S4] &n_ext_unmapped extension columns from g.master_data_merged have no lookup entry and are OUT_OF_SCOPE -- filter the review CSV on source_dataset=master_data_merged.;
  %end;
%mend warn_ext_unmapped;
%warn_ext_unmapped;

/* ---- All guards passed: promote map_status and refresh the review CSV --- */
proc sql;
  update g.var_domain_map set map_status = 'REVIEW';
quit;

proc export data=g.var_domain_map
  outfile="&qc_path.\17_var_domain_map_review.csv"
  dbms=csv replace;
run;

%put NOTE: [17-S4] All Section 4 guards passed. map_status=REVIEW. Review CSV refreshed.;


/* =========================================================================
   END OF WAVE 1 (Sections 1 to 4)
   -------------------------------------------------------------------------
   Checkpoint 1: Gerard reviews qc\17_var_domain_map_review.csv
   variable-by-variable -- domain, domain_rationale, and stat_route, paying
   closest attention to rows where assign_rule is analytic_role, to numeric
   variables near the 10-level routing boundary (compare n_levels with
   n_levels_raw), and to rows where n_dict_matches is greater than 1.

   Sections 5 to 11 (sentinel recode, PROC MEANS, PROC FREQ, suppression,
   ODS EXCEL workbook, QC artifact) are NOT in this file yet. Setting
   DOMAIN_MAP_APPROVED to 1 will not produce statistics until they are
   written. Each of those sections must open with %gate_stats.
   ========================================================================= */

%put NOTE: ==== Phase 17 Wave 1 complete. Checkpoint 1 pending. ====;
%put NOTE: Review qc\17_var_domain_map_review.csv variable-by-variable.;


/* =========================================================================
   SECTION 5: Gate entry, scoped sentinel recode, per-variable recode log
   -------------------------------------------------------------------------
   GATE FIRST. This section and all later sections (5-11) must not run
   until Checkpoint 1 approval sets DOMAIN_MAP_APPROVED = 1.

   Work plan:
   1. Create work.analysis_base_clean as a copy of work.analysis_base_ext.
   2. Read the sentinel applicability list (variables where -999 or literal
      NULL was OBSERVED in Wave 0) and store as macro vars.
   3. Count sentinel values BEFORE recoding (one row per variable).
   4. Recode in a SINGLE DATA step using arrays -- NOT one dataset
      rewrite per variable.
   5. Concatenate numeric and character logs into work.sentinel_log.

   PCM compliance:
   - All conditional logic inside named macros.
   - Counts use SELECT COUNT(*) INTO :macvar TRIMMED -- never &SQLOBS.
   - Character count matches ONLY upcase(strip(v))='NULL' -- never
     'or missing(v)' which inflates n_recoded with untouched rows.
   - drop _i _j prevents index variables from reaching statistics.
   ========================================================================= */

%gate_stats;

%put NOTE: ==== Section 5: sentinel recode starting ====;

/* Per-year stratification in Sections 6-9 requires a resolved year column. */
%macro check_year_resolved;
  %if %length(&year_variable) = 0 %then %do;
    %fail_out(msg=No numeric year variable was resolved in discovery -- Sections 6 to 9 stratify by year and cannot run);
  %end;
%mend check_year_resolved;
%check_year_resolved;

/* ---- 5.1 Working copy -------------------------------------------------- */
data work.analysis_base_clean;
  set work.analysis_base_ext;
run;

/* ---- 5.2 Retrieve sentinel applicability lists from Wave 0 ------------- */
/* work.sentinel_applicable was built in Section 0b and is still in WORK.   */
/* If it is absent (e.g. the program was restarted after Checkpoint 1) the  */
/* recode macros still initialise the lists to empty and skip gracefully.    */
%global sentinel_num_list sentinel_chr_list;
%let sentinel_num_list = ;
%let sentinel_chr_list = ;

%macro load_sentinel_lists;
  %local n_sent_tab;
  %let n_sent_tab = 0;
  proc sql noprint;
    select count(*) into :n_sent_tab trimmed
    from dictionary.tables
    where libname='WORK' and memname='SENTINEL_APPLICABLE';
  quit;
  %if &n_sent_tab = 1 %then %do;
    proc sql noprint;
      select varname into :sentinel_num_list separated by ' '
      from work.sentinel_applicable where sentinel_kind='NUM_-999';
      select varname into :sentinel_chr_list separated by ' '
      from work.sentinel_applicable where sentinel_kind='CHAR_NULL';
    quit;
    %put NOTE: [17-S5] sentinel_num_list: &sentinel_num_list;
    %put NOTE: [17-S5] sentinel_chr_list: &sentinel_chr_list;
  %end;
  %else %do;
    %put WARNING: [17-S5] work.sentinel_applicable not found. Sentinel lists are empty -- recode will be skipped.;
  %end;
%mend load_sentinel_lists;
%load_sentinel_lists;

/* ---- 5.3 Count sentinels BEFORE recoding -------------------------------- */
/* One row per variable written into work.sentinel_log_num and               */
/* work.sentinel_log_chr, then concatenated into work.sentinel_log.          */
/* Character count uses ONLY upcase(strip(v))='NULL' -- adding               */
/* 'or missing(v)' would inflate n_recoded with already-missing rows.        */
%macro recode_sentinels;
  %local n_sn n_sc i v;

  %let n_sn = %nwords(&sentinel_num_list);
  %let n_sc = %nwords(&sentinel_chr_list);

  /* --- Numeric counts --- */
  %if &n_sn > 0 %then %do;
    proc sql;
      create table work.sentinel_log_num as
      %do i = 1 %to &n_sn;
        %let v = %scan(&sentinel_num_list, &i);
        select "&v"     as varname       length=32,
               'NUM_-999' as sentinel_kind length=12,
               (select count(*) from work.analysis_base_clean where &v = -999)
                         as n_recoded
        %if &i < &n_sn %then %do; union all %end;
      %end;
      ;
    quit;
  %end;
  %else %do;
    data work.sentinel_log_num;
      length varname $32 sentinel_kind $12 n_recoded 8;
      stop;
    run;
  %end;

  /* --- Character counts (literal NULL only, never or missing()) --- */
  %if &n_sc > 0 %then %do;
    proc sql;
      create table work.sentinel_log_chr as
      %do i = 1 %to &n_sc;
        %let v = %scan(&sentinel_chr_list, &i);
        select "&v"       as varname       length=32,
               'CHAR_NULL' as sentinel_kind length=12,
               (select count(*) from work.analysis_base_clean
                where upcase(strip(&v)) = 'NULL') as n_recoded
        %if &i < &n_sc %then %do; union all %end;
      %end;
      ;
    quit;
  %end;
  %else %do;
    data work.sentinel_log_chr;
      length varname $32 sentinel_kind $12 n_recoded 8;
      stop;
    run;
  %end;

  /* --- Single-pass recode using arrays: one DATA step for ALL variables --- */
  /* Empty strings are already missing to SAS -- no action needed.            */
  data work.analysis_base_clean;
    set work.analysis_base_clean;
    %if &n_sn > 0 %then %do;
      array _sn {*} &sentinel_num_list;
      do _i = 1 to dim(_sn);
        if _sn{_i} = -999 then call missing(_sn{_i});
      end;
    %end;
    %if &n_sc > 0 %then %do;
      array _sc {*} $ &sentinel_chr_list;
      do _j = 1 to dim(_sc);
        if upcase(strip(_sc{_j})) = 'NULL' then call missing(_sc{_j});
      end;
    %end;
    /* drop index variables so they do not appear in any downstream PROC */
    %if &n_sn > 0 %then %do; drop _i; %end;
    %if &n_sc > 0 %then %do; drop _j; %end;
  run;

  /* --- Concatenate into work.sentinel_log --------------------------------- */
  data work.sentinel_log;
    set work.sentinel_log_num
        work.sentinel_log_chr;
  run;

  %put NOTE: [17-S5] Sentinel recode complete. &n_sn numeric variables and &n_sc character variables recoded.;
  %put NOTE: [17-S5] work.sentinel_log has per-variable recode counts (consumed by Wave 3 QC sheet).;
  %put NOTE: [17-S5] Empty strings are already missing to SAS and were not separately recoded.;
%mend recode_sentinels;
%recode_sentinels;

/* Guard: work.analysis_base_clean must have the same row count as the       */
/* pre-recode working copy (recode must not drop or add rows).               */
%let n_clean_rows = 0;
proc sql noprint;
  select count(*) into :n_clean_rows trimmed from work.analysis_base_clean;
quit;

%macro check_clean_rows;
  %if &n_clean_rows ne &n_ext_rows %then %do;
    %fail_out(msg=Row count changed during sentinel recode: expected &n_ext_rows but work.analysis_base_clean has &n_clean_rows);
  %end;
  %put NOTE: [17-S5] Row-count guard after sentinel recode passed: &n_clean_rows rows.;
%mend check_clean_rows;
%check_clean_rows;

%put NOTE: ==== Section 5 complete: work.analysis_base_clean ready for statistics ====;


/* =========================================================================
   SECTION 6: Continuous statistics -- PROC MEANS pooled + per-year via CLASS
   -------------------------------------------------------------------------
   Variables routed by stat_route='MEANS' in g.var_domain_map, never by
   vtype alone. Numeric-coded categoricals (_30_DAY_MORTALITY, sex, ASA)
   have stat_route='FREQ' and do not reach this section.

   Per-year stratification uses CLASS &year_variable with TYPES () &year_variable
   so no BY-sort is required and pooled plus per-year come from one PROC.

   SD column name differs across SAS releases (StdDev vs Std). The column
   list is resolved from dictionary.columns AFTER the ODS output step so
   the code is release-safe.

   Domains with an empty MEANS list are guarded by a named macro.
   ========================================================================= */

%put NOTE: ==== Section 6: PROC MEANS (continuous) starting ====;

/* ---- 6.1 Pull per-domain MEANS lists from g.var_domain_map ------------- */
%global means_d1 means_d2 means_d3 means_d4 means_d5
        freq_d1  freq_d2  freq_d3  freq_d4  freq_d5;
%let means_d1 = ; %let means_d2 = ; %let means_d3 = ;
%let means_d4 = ; %let means_d5 = ;
%let freq_d1  = ; %let freq_d2  = ; %let freq_d3  = ;
%let freq_d4  = ; %let freq_d5  = ;

proc sql noprint;
  select varname into :means_d1 separated by ' '
    from g.var_domain_map where domain='D1' and stat_route='MEANS';
  select varname into :means_d2 separated by ' '
    from g.var_domain_map where domain='D2' and stat_route='MEANS';
  select varname into :means_d3 separated by ' '
    from g.var_domain_map where domain='D3' and stat_route='MEANS';
  select varname into :means_d4 separated by ' '
    from g.var_domain_map where domain='D4' and stat_route='MEANS';
  select varname into :means_d5 separated by ' '
    from g.var_domain_map where domain='D5' and stat_route='MEANS';
  select varname into :freq_d1  separated by ' '
    from g.var_domain_map where domain='D1' and stat_route='FREQ';
  select varname into :freq_d2  separated by ' '
    from g.var_domain_map where domain='D2' and stat_route='FREQ';
  select varname into :freq_d3  separated by ' '
    from g.var_domain_map where domain='D3' and stat_route='FREQ';
  select varname into :freq_d4  separated by ' '
    from g.var_domain_map where domain='D4' and stat_route='FREQ';
  select varname into :freq_d5  separated by ' '
    from g.var_domain_map where domain='D5' and stat_route='FREQ';
quit;

%put NOTE: [17-S6] means_d1: &means_d1;
%put NOTE: [17-S6] means_d2: &means_d2;
%put NOTE: [17-S6] means_d3: &means_d3;
%put NOTE: [17-S6] means_d4: &means_d4;
%put NOTE: [17-S6] means_d5: &means_d5;

/* ---- 6.2 Macro: run PROC MEANS for one domain -------------------------- */
/* Guards against an empty variable list (named macro, calls %return).       */
/* Uses CLASS &year_variable / TYPES () &year_variable so pooled row and     */
/* per-year rows come from a SINGLE run -- no unsorted BY-group.             */
%macro run_means(domain=, varlist=, out=);
  %local nv;
  %let nv = %nwords(&varlist);
  %if &nv = 0 %then %do;
    %put NOTE: [17-S6] Domain &domain has no MEANS-routed variables. PROC MEANS skipped.;
    data &out;
      length varname $32 domain $4 &year_variable 8 N 8 NMiss 8 Mean 8 StdDev 8
             Median 8 P25 8 P75 8 Min 8 Max 8;
      stop;
    run;
    %return;
  %end;

  ods listing close;
  proc means data=work.analysis_base_clean
      n nmiss mean std median p25 p75 min max
      maxdec=2 stackodsoutput;
    var &varlist;
    class &year_variable;
    types () &year_variable;
    ods output summary=&out;
  run;
  ods listing;

  /* stackodsoutput emits Variable (the name) and, when labels exist, Label. */
  /* Pooled rows are the ones where the class value is missing (TYPES ()).   */
  data &out;
    set &out;
    length varname $32 domain $4;
    varname = upcase(strip(Variable));
    domain  = "&domain";
  run;

  %put NOTE: [17-S6] PROC MEANS for domain &domain complete: &nv variables.;
%mend run_means;

%run_means(domain=D1, varlist=&means_d1, out=work.means_d1);
%run_means(domain=D2, varlist=&means_d2, out=work.means_d2);
%run_means(domain=D3, varlist=&means_d3, out=work.means_d3);
%run_means(domain=D4, varlist=&means_d4, out=work.means_d4);
%run_means(domain=D5, varlist=&means_d5, out=work.means_d5);

/* ---- 6.3 Resolve release-safe statistic column names ------------------- */
/* The SD column is StdDev in some SAS 9.4 releases and Std in others.       */
/* Inspect dictionary.columns AFTER the first ODS output to resolve the      */
/* actual name. work.means_d1 is used as the probe; if it has no rows        */
/* (empty MEANS list for D1), try subsequent domains.                        */
%global sd_col_name;
%let sd_col_name = Std;   /* safe default */

%macro resolve_sd_col;
  %local probe_ds n_probe i d;
  %let probe_ds = ;
  %do i = 1 %to 5;
    %let d = D&i;
    %let n_probe = 0;
    proc sql noprint;
      select count(*) into :n_probe trimmed
      from dictionary.columns
      where libname='WORK' and memname="MEANS_&d"
        and upcase(name) in ('STDDEV','STD');
    quit;
    %if &n_probe > 0 %then %do;
      %let probe_ds = means_d&i;
      /* leave the loop by exhausting the index */
      %let i = 99;
    %end;
  %end;
  %if %length(&probe_ds) > 0 %then %do;
    proc sql noprint;
      select name into :sd_col_name trimmed
      from dictionary.columns
      where libname='WORK' and upcase(memname)=upcase("&probe_ds")
        and upcase(name) in ('STDDEV','STD');
    quit;
    %put NOTE: [17-S6] SD column resolved as: &sd_col_name;
  %end;
  %else %do;
    %put WARNING: [17-S6] Could not probe SD column name -- no MEANS output has rows. Using default: &sd_col_name;
  %end;
%mend resolve_sd_col;
%resolve_sd_col;

%put NOTE: ==== Section 6 complete ====;


/* =========================================================================
   SECTION 7: Categorical statistics -- PROC FREQ pooled + per-year
   -------------------------------------------------------------------------
   Variables routed by stat_route='FREQ' in g.var_domain_map.

   Pooled: tables (&freq_dN) / missing nocum; ods output onewayfreqs=...
   Per-year crosstab: tables (&freq_dN) * &year_variable / missing nocum
                      norow nocol nopercent; ods output crosstabfreqs=...

   Both outputs are normalized to a long structure:
     varname | level | year (blank = pooled) | frequency |
     n_nonmissing | n_missing | pct_nonmissing

   Percent is recomputed on the NON-MISSING denominator per D-02.
   The raw ODS Percent includes missing and is NOT used.

   Domains with an empty FREQ list are guarded by a named macro.
   ========================================================================= */

%put NOTE: ==== Section 7: PROC FREQ (categorical) starting ====;

/* ---- 7.1 Macro: run PROC FREQ and normalize output for one domain ------- */
%macro run_freq(domain=, varlist=, out_pooled=, out_year=, out=);
  %local nv;
  %let nv = %nwords(&varlist);
  %if &nv = 0 %then %do;
    %put NOTE: [17-S7] Domain &domain has no FREQ-routed variables. PROC FREQ skipped.;
    data &out;
      length varname $32 level $200 year_val $32
             frequency 8 n_nonmissing 8 n_missing 8 pct_nonmissing 8
             is_pooled 8 domain $4;
      stop;
    run;
    %return;
  %end;

  /* --- Pooled one-way frequency tables ----------------------------------- */
  ods listing close;
  ods output onewayfreqs=&out_pooled;
  proc freq data=work.analysis_base_clean;
    tables (&varlist) / missing nocum;
  run;
  ods listing;

  /* --- Per-year crosstab ------------------------------------------------- */
  ods listing close;
  ods output crosstabfreqs=&out_year;
  proc freq data=work.analysis_base_clean;
    tables (&varlist) * &year_variable / missing nocum norow nocol nopercent;
  run;
  ods listing;

  /* --- Normalize pooled output to the long structure --------------------- */
  /* ODS ONEWAYFREQS: Table (varname), F_<varname> (level char or formatted), */
  /* Frequency, Percent. Missing level identified by missing(F_<varname>).    */
  data work.freq_pooled_long;
    length varname $32 level $200;
    set &out_pooled;
    /* Table reads Table VARNAME -- the second word is the name.              */
    varname  = upcase(strip(scan(Table, 2, ' ')));
    /* One F_ column exists per variable in the TABLES list; only the column  */
    /* for this row's variable is populated. Take the NON-MISSING one (a       */
    /* missing level leaves every F_ column blank, so level stays blank).      */
    array _fcols {*} $ _character_;
    level = '';
    do _k = 1 to dim(_fcols);
      if substr(vname(_fcols{_k}),1,2) = 'F_' and not missing(_fcols{_k})
        then level = strip(_fcols{_k});
    end;
    keep varname level Frequency;
    rename Frequency=frequency;
  run;

  /* Compute n_missing and n_nonmissing per variable (pooled) */
  proc sql;
    create table work.freq_pool_agg as
      select varname,
             sum(case when missing(level) then frequency else 0 end) as n_missing,
             sum(case when not missing(level) then frequency else 0 end) as n_nonmissing
      from work.freq_pooled_long
      group by varname;
  quit;

  /* Join back to get pct_nonmissing on non-missing denominator */
  proc sql;
    create table work.freq_pooled_out as
      select f.varname, f.level,
             '' as year_val length=32,
             f.frequency,
             a.n_nonmissing,
             a.n_missing,
             case when a.n_nonmissing > 0 and not missing(f.level)
               then 100 * f.frequency / a.n_nonmissing
               else . end as pct_nonmissing,
             1 as is_pooled,
             "&domain" as domain length=4
      from work.freq_pooled_long as f
      inner join work.freq_pool_agg as a on f.varname = a.varname;
  quit;

  /* --- Normalize per-year crosstab output -------------------------------- */
  /* ODS CROSSTABFREQS: Table (varname*year), row var level, col var level,  */
  /* Frequency.                                                               */
  data work.freq_year_long;
    length varname $32 level $200 year_val $32;
    set &out_year;
    /* CROSSTABFREQS carries marginal rows (_TYPE_ 10, 01, 00). Cells only.   */
    where _TYPE_ = '11';
    /* Table reads Table VARNAME * YEAR -- the second word is the name.       */
    varname  = upcase(strip(scan(Table, 2, ' *')));
    year_val = strip(put(&year_variable, best12.));

    array _fcols2 {*} $ _character_;
    level = '';
    do _k = 1 to dim(_fcols2);
      if substr(vname(_fcols2{_k}),1,2) = 'F_'
         and upcase(vname(_fcols2{_k})) ne upcase("F_&year_variable")
         and not missing(_fcols2{_k})
        then level = strip(_fcols2{_k});
    end;
    keep varname level year_val Frequency;
    rename Frequency=frequency;
  run;

  proc sql;
    create table work.freq_year_agg as
      select varname, year_val,
             sum(case when missing(level) then frequency else 0 end) as n_missing,
             sum(case when not missing(level) then frequency else 0 end) as n_nonmissing
      from work.freq_year_long
      group by varname, year_val;
  quit;

  proc sql;
    create table work.freq_year_out as
      select f.varname, f.level, f.year_val,
             f.frequency,
             a.n_nonmissing,
             a.n_missing,
             case when a.n_nonmissing > 0 and not missing(f.level)
               then 100 * f.frequency / a.n_nonmissing
               else . end as pct_nonmissing,
             0 as is_pooled,
             "&domain" as domain length=4
      from work.freq_year_long as f
      inner join work.freq_year_agg as a
        on f.varname = a.varname and f.year_val = a.year_val;
  quit;

  /* --- Stack pooled and per-year into a single long display dataset ------- */
  data &out;
    set work.freq_pooled_out
        work.freq_year_out;
  run;

  %put NOTE: [17-S7] PROC FREQ for domain &domain complete: &nv variables.;
%mend run_freq;

%run_freq(domain=D1, varlist=&freq_d1,
          out_pooled=work.freq_d1_pooled, out_year=work.freq_d1_year,
          out=work.freq_d1);
%run_freq(domain=D2, varlist=&freq_d2,
          out_pooled=work.freq_d2_pooled, out_year=work.freq_d2_year,
          out=work.freq_d2);
%run_freq(domain=D3, varlist=&freq_d3,
          out_pooled=work.freq_d3_pooled, out_year=work.freq_d3_year,
          out=work.freq_d3);
%run_freq(domain=D4, varlist=&freq_d4,
          out_pooled=work.freq_d4_pooled, out_year=work.freq_d4_year,
          out=work.freq_d4);
%run_freq(domain=D5, varlist=&freq_d5,
          out_pooled=work.freq_d5_pooled, out_year=work.freq_d5_year,
          out=work.freq_d5);

%put NOTE: ==== Section 7 complete ====;


/* =========================================================================
   SECTION 8: Small-cell suppression pass
   -------------------------------------------------------------------------
   Applied AFTER statistics, BEFORE any workbook output.
   Reads &SUPPRESS_MAX and &SUPPRESS_LABEL from Section 0 constants.

   Rules (all four must be applied):
   a. Categorical level counts: frequency <= &SUPPRESS_MAX -> suppressed.
   b. n_missing: suppress on the same rule as level counts.
   c. Continuous blocks: if non-missing n <= &SUPPRESS_MAX for ANY block
      (pooled or per-year), suppress the ENTIRE statistic row for that
      variable-block (mean, SD, median, Q1, Q3, min, max, and n).
   d. Complementary disclosure: when exactly one level of a variable-block
      is suppressed and the block total is printed, suppress the next-
      smallest level too.

   Accumulates total suppressed cells into :n_suppressed.
   Adds suppressed=1 flag on every affected cell.
   ========================================================================= */

%put NOTE: ==== Section 8: suppression pass starting ====;

%global n_suppressed;
%let n_suppressed = 0;

/* ---- 8.1 Suppress categorical display datasets (work.freq_dN) ----------- */
/* Applied to every domain; the macro loops over domains 1-5.                */
%macro suppress_freq(ds=, out=);
  %local n_rows_in;
  %let n_rows_in = 0;
  proc sql noprint;
    select count(*) into :n_rows_in trimmed from &ds;
  quit;
  %if &n_rows_in = 0 %then %do;
    data &out;
      set &ds;
      length n_display $32 pct_display $32 suppressed 8 supp_reason $32;
      stop;
    run;
    %return;
  %end;

  /* --- step a+b: flag every small cell and n_missing -------------------- */
  data work.freq_supp_step1;
    set &ds;
    length n_display $32 pct_display $32 suppressed 8 supp_reason $32;
    suppressed   = 0;
    supp_reason  = '';
    n_display    = strip(put(frequency, comma12.));
    if missing(level) then pct_display = '';
    else pct_display = strip(put(pct_nonmissing, 6.1));

    /* Suppress level counts that are <= &SUPPRESS_MAX */
    if not missing(level) and frequency <= &SUPPRESS_MAX then do;
      n_display   = "&SUPPRESS_LABEL";
      pct_display = "&SUPPRESS_LABEL";
      suppressed  = 1;
      supp_reason = 'level_count';
    end;

    /* Suppress n_missing on the same rule */
    if missing(level) and n_missing <= &SUPPRESS_MAX then do;
      n_display   = "&SUPPRESS_LABEL";
      pct_display = "&SUPPRESS_LABEL";
      suppressed  = 1;
      supp_reason = 'n_missing';
    end;
  run;

  /* --- step d: complementary disclosure suppression --------------------- */
  /* Within each varname + year_val block, if exactly one non-missing level  */
  /* is suppressed, suppress the next-smallest unsuppressed level also.      */
  proc sort data=work.freq_supp_step1;
    by domain varname year_val suppressed frequency;
  run;

  /* Count suppressed non-missing levels per block */
  proc sql noprint;
    create table work.freq_supp_counts as
      select domain, varname, year_val,
             sum(case when suppressed=1 and not missing(level) then 1 else 0 end)
               as n_suppressed_levels,
             min(case when suppressed=0 and not missing(level) then frequency
                 else . end) as min_unsuppressed_freq
      from work.freq_supp_step1
      group by domain, varname, year_val;
  quit;

  /* Tag rows that need complementary suppression (the next-smallest          */
  /* unsuppressed level in blocks where exactly one level is suppressed).     */
  proc sql;
    create table work.freq_supp_step2 as
      select f.*,
             c.n_suppressed_levels,
             c.min_unsuppressed_freq,
             case when c.n_suppressed_levels = 1
                    and f.suppressed = 0
                    and not missing(f.level)
                    and f.frequency = c.min_unsuppressed_freq
               then 1 else 0 end as comp_supp
      from work.freq_supp_step1 as f
      inner join work.freq_supp_counts as c
        on f.domain=c.domain and f.varname=c.varname and f.year_val=c.year_val;
  quit;

  data &out;
    set work.freq_supp_step2;
    if comp_supp = 1 then do;
      n_display   = "&SUPPRESS_LABEL";
      pct_display = "&SUPPRESS_LABEL";
      suppressed  = 1;
      supp_reason = 'complementary';
    end;
    drop n_suppressed_levels min_unsuppressed_freq comp_supp;
  run;

  /* Accumulate suppressed cell count */
  %local n_new_supp;
  %let n_new_supp = 0;
  proc sql noprint;
    select count(*) into :n_new_supp trimmed from &out where suppressed = 1;
  quit;
  %let n_suppressed = %eval(&n_suppressed + &n_new_supp);

  %put NOTE: [17-S8] &out suppressed cells: &n_new_supp (running total: &n_suppressed);
%mend suppress_freq;

%suppress_freq(ds=work.freq_d1, out=work.freq_d1_display);
%suppress_freq(ds=work.freq_d2, out=work.freq_d2_display);
%suppress_freq(ds=work.freq_d3, out=work.freq_d3_display);
%suppress_freq(ds=work.freq_d4, out=work.freq_d4_display);
%suppress_freq(ds=work.freq_d5, out=work.freq_d5_display);

/* ---- 8.2 Suppress continuous display datasets (work.means_dN) ----------- */
/* Rule c: if a variable-block (pooled or per-year) has non-missing n <=     */
/* &SUPPRESS_MAX, the ENTIRE statistic row is suppressed -- mean, SD,        */
/* median, Q1, Q3, min, max AND n. Min and max on seven patients are more    */
/* disclosive than the suppressed count; showing n=-- beside a real mean     */
/* defeats the rule entirely.                                                */
%macro suppress_means(ds=, out=);
  %local n_rows_in;
  %let n_rows_in = 0;
  proc sql noprint;
    select count(*) into :n_rows_in trimmed from &ds;
  quit;
  %if &n_rows_in = 0 %then %do;
    data &out;
      set &ds;
      length suppressed 8 supp_reason $32;
      stop;
    run;
    %return;
  %end;

  data &out;
    set &ds;
    length suppressed 8 supp_reason $32;
    suppressed  = 0;
    supp_reason = '';

    /* N is the non-missing count in PROC MEANS stackodsoutput output.        */
    /* The column name is N (or NObs -- resolve from the actual dataset).     */
    /* We test the variable named N; if absent the comparison will produce a  */
    /* warning and the guard below catches it.                                 */
    if N <= &SUPPRESS_MAX then do;
      suppressed  = 1;
      supp_reason = 'continuous_small_n';
      /* Suppress every statistic by setting to missing */
      N     = .;
      NMiss = .;
      Mean  = .;
      &sd_col_name = .;
      Median = .;
      P25    = .;
      P75    = .;
      Min    = .;
      Max    = .;
    end;
  run;

  /* Accumulate */
  %local n_new_supp;
  %let n_new_supp = 0;
  proc sql noprint;
    select count(*) into :n_new_supp trimmed from &out where suppressed = 1;
  quit;
  %let n_suppressed = %eval(&n_suppressed + &n_new_supp);

  %put NOTE: [17-S8] &out suppressed rows: &n_new_supp (running total: &n_suppressed);
%mend suppress_means;

%suppress_means(ds=work.means_d1, out=work.means_d1_display);
%suppress_means(ds=work.means_d2, out=work.means_d2_display);
%suppress_means(ds=work.means_d3, out=work.means_d3_display);
%suppress_means(ds=work.means_d4, out=work.means_d4_display);
%suppress_means(ds=work.means_d5, out=work.means_d5_display);

%put NOTE: [17-S8] Total suppressed cells across all domains: &n_suppressed;
%put NOTE: ==== Section 8 complete. Display datasets ready for Wave 3 assembly. ====;


/* =========================================================================
   END OF WAVE 2 (Sections 5 to 8)
   -------------------------------------------------------------------------
   Display datasets produced (per domain, D1-D5):
     work.means_dN_display  -- continuous stats, suppression flags applied
     work.freq_dN_display   -- categorical stats (long structure), suppression
                               flags applied to level counts, n_missing, and
                               complementary cells
   Total suppressed cells: &n_suppressed

   Wave 3 (Sections 9-10) will consume these datasets to assemble the
   ODS EXCEL workbook and write the QC artifact.

   Sentinel recode log (work.sentinel_log) is available for the QC sheet.
   ========================================================================= */

%put NOTE: ==== Phase 17 Wave 2 complete. Ready for Wave 3 ODS EXCEL assembly. ====;


/* =========================================================================
   SECTION 9: ODS EXCEL workbook assembly
   -------------------------------------------------------------------------
   Produces: qc\17_summary_stats_by_domain.xlsx
   Sheet order (eight tabs, KEY leftmost):
     KEY        -- legend, run metadata, suppression rule, denominator rules
     D1 - D5    -- continuous + categorical tables per domain (both on one tab)
     Crosswalk  -- g.var_domain_map with every variable incl. OUT_OF_SCOPE
     QC         -- run metadata, recode counts, suppression counts,
                   per-domain counts, per-rule counts, OUT_OF_SCOPE counts

   CRITICAL: sheet_interval="none" is set at ODS EXCEL open and NEVER
   changed. Under the default ("table") every PROC REPORT starts a new tab,
   so a domain's continuous and categorical tables land on "D1" and "D1 1".
   With sheet_interval="none" both PROC REPORTs land on the current tab;
   switching tabs requires changing sheet_name via ods excel options().

   Display datasets are in LONG format (one row per variable per year).
   Sections 9.2-9.6 transpose each domain to WIDE before PROC REPORT so
   that pooled and per-year blocks can be placed under spanning headers.
   ========================================================================= */

%put NOTE: ==== Section 9: ODS EXCEL workbook assembly starting ====;

/* ---- 9.0 Delete prior workbook if it exists (locked-file guard) ----------- */
%macro drop_stale_xlsx;
  %local rc_xlsx;
  %if %sysfunc(fileexist(%bquote(&qc_path.\17_summary_stats_by_domain.xlsx))) %then %do;
    filename _oldx "&qc_path.\17_summary_stats_by_domain.xlsx";
    %let rc_xlsx = %sysfunc(fdelete(_oldx));
    filename _oldx clear;
    %if &rc_xlsx ne 0 %then %do;
      %fail_out(msg=Could not delete prior qc\17_summary_stats_by_domain.xlsx rc=&rc_xlsx -- file may be open in Excel);
    %end;
    %put NOTE: [17-S9] Prior xlsx deleted before rebuild.;
  %end;
%mend drop_stale_xlsx;
%drop_stale_xlsx;

/* ---- 9.1 Build the year list macro variable from work.year_dist ----------- */
/* &year_list is a space-separated list of distinct years (numeric values)     */
/* used below to loop over per-year column blocks for spanning headers.        */
%global year_list n_years;
%let year_list = ;
%let n_years   = 0;

proc sql noprint;
  select distinct year_value into :year_list separated by ' '
  from work.year_dist
  where not missing(year_value)
  order by year_value;
quit;
%let n_years = %nwords(&year_list);

%macro check_years;
  %if &n_years = 0 %then %do;
    %fail_out(msg=work.year_dist has no non-missing year values -- per-year column blocks cannot be built);
  %end;
%mend check_years;
%check_years;

/* Display formats: suppressed (missing) numeric cells print as the label. */
proc format;
  value suppint  . = "&SUPPRESS_LABEL" other = [comma12.];
  value suppdec  . = "&SUPPRESS_LABEL" other = [12.2];
run;

%put NOTE: [17-S9] Year list for spanning headers: &year_list (n=&n_years years);

/* ---- 9.1b Build the KEY dataset ------------------------------------------- */
data work.key;
  length item $60 detail $500;
  item="Program";       detail="17_summary_stats_by_domain.sas -- Phase 17 Wave 3"; output;
  item="Source";        detail="work.analysis_base_ext (g.analysis_base extended with g.master_data_merged frailty/cognitive/intraoperative columns)"; output;
  item="Rows";          detail="&n_base_rows rows (one per PRECEDE_STUDY_ID)"; output;
  item="Run datetime";  detail="%sysfunc(datetime(), datetime20.)"; output;
  item="Scope";         detail="Descriptive statistics only -- no inferential testing. Pooled and per-year breakdowns for all dictionary-documented and approved extension variables."; output;
  item="Continuous stats"; detail="N (non-missing) NMiss Mean SD Median Q1 Q3 Min Max -- pooled and per year"; output;
  item="Categorical stats"; detail="Level N % of non-missing N-missing -- pooled and per year"; output;
  item="Suppression rule";  detail="Cells representing &SUPPRESS_MAX or fewer patients are shown as &SUPPRESS_LABEL. For continuous blocks at or below that count ALL statistics for the block are suppressed -- not only N. N-missing is suppressed on the same rule."; output;
  item="Denominator rule";  detail="Percents on categorical variables are computed on the non-missing denominator (D-02). N-missing is reported separately and is itself subject to suppression."; output;
  item="D3 and D2 frailty denominator"; detail=symget('D3_DENOM_NOTE'); output;
  item="Domains";           detail="D1 Sociodemographics; D2 Preoperative incl. frailty; D3 Cognitive instruments; D4 Intraoperative; D5 Outcomes"; output;
  item="OUT_OF_SCOPE";      detail="Identifiers, high-cardinality keys, and variables not matched to the PRECEDE dictionary are excluded from statistics but appear on the Crosswalk sheet with their reason."; output;
run;

/* ---- 9.2 Transpose display datasets to WIDE for PROC REPORT --------------- */
/* For means: pivot pooled row and per-year rows to wide columns so spanning   */
/* headers can be placed over each year block.                                 */
/* Column names: n_pool mean_pool std_pool median_pool q1_pool q3_pool         */
/*               min_pool max_pool nmiss_pool                                  */
/*               n_YYYY mean_YYYY std_YYYY ... for each year                   */

%macro transpose_means_wide(ds=, out=);
  /* Pooled rows: class value missing (TYPES () emits the overall row with  */
  /* the class variable missing). Year rows: class value present.           */
  /* sas_label is not in the MEANS output; it is joined from the map.        */
  %local i yr n_in;
  %let n_in = 0;
  proc sql noprint;
    select count(*) into :n_in trimmed from &ds;
  quit;
  %if &n_in = 0 %then %do;
    data &out;
      length varname $32 domain $4 sas_label $256;
      stop;
    run;
    %return;
  %end;

  proc sql noprint;
    create table work._m_pool as
      select d.varname, d.domain, m.sas_label, d.supp_reason,
             d.N as n_pool, d.NMiss as nmiss_pool, d.Mean as mean_pool,
             d.&sd_col_name as std_pool, d.Median as median_pool,
             d.P25 as q1_pool, d.P75 as q3_pool, d.Min as min_pool, d.Max as max_pool,
             d.suppressed as supp_pool
      from &ds as d
      left join g.var_domain_map as m on d.varname = m.varname
      where missing(d.&year_variable)
      order by d.varname;
  quit;

  /* One set of year columns per year value */
  data work._m_wide;
    set work._m_pool;
    /* initialise all year columns to missing */
    %do i = 1 %to &n_years;
      %let yr = %scan(&year_list, &i);
      length n_&yr 8 nmiss_&yr 8 mean_&yr 8 std_&yr 8
             median_&yr 8 q1_&yr 8 q3_&yr 8 min_&yr 8 max_&yr 8 supp_&yr 8;
      n_&yr = .; nmiss_&yr = .; mean_&yr = .; std_&yr = .;
      median_&yr = .; q1_&yr = .; q3_&yr = .; min_&yr = .; max_&yr = .;
      supp_&yr = 0;
    %end;
  run;

  /* Update each year column from the per-year rows */
  %do i = 1 %to &n_years;
    %let yr = %scan(&year_list, &i);
    proc sql noprint;
      create table work._m_yr_&yr as
        select varname,
               N as n_&yr, NMiss as nmiss_&yr, Mean as mean_&yr,
               &sd_col_name as std_&yr, Median as median_&yr,
               P25 as q1_&yr, P75 as q3_&yr, Min as min_&yr, Max as max_&yr,
               suppressed as supp_&yr
        from &ds
        where &year_variable = &yr;
    quit;

    proc sql;
      update work._m_wide w
        set n_&yr      = (select n_&yr      from work._m_yr_&yr y where y.varname=w.varname),
            nmiss_&yr  = (select nmiss_&yr  from work._m_yr_&yr y where y.varname=w.varname),
            mean_&yr   = (select mean_&yr   from work._m_yr_&yr y where y.varname=w.varname),
            std_&yr    = (select std_&yr    from work._m_yr_&yr y where y.varname=w.varname),
            median_&yr = (select median_&yr from work._m_yr_&yr y where y.varname=w.varname),
            q1_&yr     = (select q1_&yr     from work._m_yr_&yr y where y.varname=w.varname),
            q3_&yr     = (select q3_&yr     from work._m_yr_&yr y where y.varname=w.varname),
            min_&yr    = (select min_&yr    from work._m_yr_&yr y where y.varname=w.varname),
            max_&yr    = (select max_&yr    from work._m_yr_&yr y where y.varname=w.varname),
            supp_&yr   = (select supp_&yr   from work._m_yr_&yr y where y.varname=w.varname);
    quit;
  %end;

  data &out;
    set work._m_wide;
  run;

  /* Cleanup temp datasets */
  proc datasets lib=work nolist;
    delete _m_pool _m_wide
    %do i = 1 %to &n_years; _m_yr_%scan(&year_list,&i) %end;;
  quit;
%mend transpose_means_wide;

%macro transpose_freq_wide(ds=, out=);
  /* Pool rows: is_pooled=1 (year_val='')                              */
  /* Year rows: is_pooled=0, year_val holds the year as a string       */
  /* Output: one row per varname+level with pool columns and year cols */
  %local i yr n_in;
  %let n_in = 0;
  proc sql noprint;
    select count(*) into :n_in trimmed from &ds;
  quit;
  %if &n_in = 0 %then %do;
    data &out;
      length varname $32 domain $4 level $200 sas_label $256;
      stop;
    run;
    %return;
  %end;

  proc sql noprint;
    create table work._f_pool as
      select d.varname, d.domain, d.level, m.sas_label,
             d.frequency as n_pool, d.n_nonmissing as n_nonmiss_pool,
             d.n_missing as n_miss_pool, d.pct_nonmissing as pct_pool,
             d.n_display as n_disp_pool, d.pct_display as pct_disp_pool,
             d.suppressed as supp_pool, d.supp_reason as supp_reason_pool
      from &ds as d
      left join g.var_domain_map as m on d.varname = m.varname
      where d.is_pooled = 1
      order by d.varname, d.level;
  quit;

  data work._f_wide;
    set work._f_pool;
    %do i = 1 %to &n_years;
      %let yr = %scan(&year_list, &i);
      length n_&yr 8 pct_&yr 8 n_disp_&yr $32 pct_disp_&yr $32 supp_&yr 8;
      n_&yr = .; pct_&yr = .;
      n_disp_&yr = ''; pct_disp_&yr = ''; supp_&yr = 0;
    %end;
  run;

  %do i = 1 %to &n_years;
    %let yr = %scan(&year_list, &i);
    proc sql noprint;
      create table work._f_yr_&yr as
        select varname, level,
               frequency as n_&yr, pct_nonmissing as pct_&yr,
               n_display as n_disp_&yr, pct_display as pct_disp_&yr,
               suppressed as supp_&yr
        from &ds
        where is_pooled = 0 and year_val = strip(put(&yr, best12.));
    quit;

    proc sql;
      update work._f_wide w
        set n_&yr        = (select n_&yr        from work._f_yr_&yr y where y.varname=w.varname and y.level=w.level),
            pct_&yr      = (select pct_&yr      from work._f_yr_&yr y where y.varname=w.varname and y.level=w.level),
            n_disp_&yr   = (select n_disp_&yr   from work._f_yr_&yr y where y.varname=w.varname and y.level=w.level),
            pct_disp_&yr = (select pct_disp_&yr from work._f_yr_&yr y where y.varname=w.varname and y.level=w.level),
            supp_&yr     = (select supp_&yr     from work._f_yr_&yr y where y.varname=w.varname and y.level=w.level);
    quit;
  %end;

  data &out;
    set work._f_wide;
    /* The missing level is a real row; label it so it is not a blank cell */
    if missing(level) then level = '(missing)';
  run;

  proc datasets lib=work nolist;
    delete _f_pool _f_wide
    %do i = 1 %to &n_years; _f_yr_%scan(&year_list,&i) %end;;
  quit;
%mend transpose_freq_wide;

/* Transpose all five domains */
%transpose_means_wide(ds=work.means_d1_display, out=work.means_d1_wide);
%transpose_means_wide(ds=work.means_d2_display, out=work.means_d2_wide);
%transpose_means_wide(ds=work.means_d3_display, out=work.means_d3_wide);
%transpose_means_wide(ds=work.means_d4_display, out=work.means_d4_wide);
%transpose_means_wide(ds=work.means_d5_display, out=work.means_d5_wide);

%transpose_freq_wide(ds=work.freq_d1_display, out=work.freq_d1_wide);
%transpose_freq_wide(ds=work.freq_d2_display, out=work.freq_d2_wide);
%transpose_freq_wide(ds=work.freq_d3_display, out=work.freq_d3_wide);
%transpose_freq_wide(ds=work.freq_d4_display, out=work.freq_d4_wide);
%transpose_freq_wide(ds=work.freq_d5_display, out=work.freq_d5_wide);

%put NOTE: [17-S9] Wide display datasets built for all five domains.;

/* ---- 9.3 Macro: PROC REPORT spanning column list -------------------------- */
/* Generates the COLUMN statement for a wide means or freq dataset with        */
/* Pooled and per-year spanning headers.                                       */
%macro means_col_stmt;
  /* Pooled spanning group */
  column varname sas_label
    ("Pooled" n_pool nmiss_pool mean_pool std_pool median_pool q1_pool q3_pool min_pool max_pool)
  %local i yr;
  %do i = 1 %to &n_years;
    %let yr = %scan(&year_list, &i);
    ("&yr" n_&yr nmiss_&yr mean_&yr std_&yr median_&yr q1_&yr q3_&yr min_&yr max_&yr)
  %end;
  ;
%mend means_col_stmt;

%macro freq_col_stmt;
  column varname sas_label level
    ("Pooled" n_disp_pool pct_disp_pool)
  %local i yr;
  %do i = 1 %to &n_years;
    %let yr = %scan(&year_list, &i);
    ("&yr" n_disp_&yr pct_disp_&yr)
  %end;
  ;
%mend freq_col_stmt;

/* ---- 9.4 Open ODS EXCEL once with sheet_interval=none, KEY sheet first --- */
%let ods_excel_open = 1;
ods listing close;
ods excel file="&qc_path.\17_summary_stats_by_domain.xlsx"
    options(sheet_name="KEY"
            embedded_titles="yes"
            autofilter="all"
            frozen_headers="1"
            sheet_interval="none");

/* KEY sheet */
proc report data=work.key nowd
    style(header)=[background=CX0021A5 color=white fontweight=bold]
    style(column)=[fontsize=9pt];
  columns item detail;
  define item   / display "Item"   style(column)=[width=1.8in fontweight=bold];
  define detail / display "Detail" style(column)=[width=5.5in];
run;

/* ---- 9.5 Domain sheets D1 through D5 ------------------------------------- */
/* For each domain: switch sheet, report the wide continuous dataset,          */
/* then the wide categorical dataset. Both land on the same tab because        */
/* sheet_interval is none.                                                     */

/* Macro: report one domain sheet */
%macro report_domain(dom=, means_ds=, freq_ds=, note=);
  /* sheet_interval=now opens a new tab for the next table. Under none a     */
  /* changed sheet_name does NOT open a tab. none is restored only after the  */
  /* first table on this tab has been written, so the second table joins it. */
  %local tab_started;
  %let tab_started = 0;
  ods excel options(sheet_name="&dom" sheet_interval="now");

  /* -- Continuous section -- */
  %local n_rows_m;
  %let n_rows_m = 0;
  proc sql noprint;
    select count(*) into :n_rows_m trimmed from &means_ds;
  quit;
  %if &n_rows_m > 0 %then %do;
    title "&dom -- Continuous Statistics (n, n-missing, mean, SD, median, Q1, Q3, min, max)";
    %if %length(&note) > 0 %then %do;
      title2 "&note";
    %end;
    proc report data=&means_ds nowd
        style(header)=[background=CX0021A5 color=white fontweight=bold]
        style(column)=[fontsize=8pt];
      %means_col_stmt
      define varname    / display "Variable"  style(column)=[width=1.2in];
      define sas_label  / display "Label"     style(column)=[width=1.8in];
      define n_pool     / display "N"      format=suppint.;
      define nmiss_pool / display "N-miss" format=suppint.;
      define mean_pool  / display "Mean"   format=suppdec.;
      define std_pool   / display "SD"     format=suppdec.;
      define median_pool / display "Median" format=suppdec.;
      define q1_pool    / display "Q1"     format=suppdec.;
      define q3_pool    / display "Q3"     format=suppdec.;
      define min_pool   / display "Min"    format=suppdec.;
      define max_pool   / display "Max"    format=suppdec.;
      %local i yr;
      %do i = 1 %to &n_years;
        %let yr = %scan(&year_list, &i);
        define n_&yr      / display "N"      format=suppint.;
        define nmiss_&yr  / display "N-miss" format=suppint.;
        define mean_&yr   / display "Mean"   format=suppdec.;
        define std_&yr    / display "SD"     format=suppdec.;
        define median_&yr / display "Median" format=suppdec.;
        define q1_&yr     / display "Q1"     format=suppdec.;
        define q3_&yr     / display "Q3"     format=suppdec.;
        define min_&yr    / display "Min"    format=suppdec.;
        define max_&yr    / display "Max"    format=suppdec.;
      %end;
    run;
    title;
    %let tab_started = 1;
    ods excel options(sheet_interval="none");
  %end;

  /* -- Categorical section -- */
  %local n_rows_f;
  %let n_rows_f = 0;
  proc sql noprint;
    select count(*) into :n_rows_f trimmed from &freq_ds;
  quit;
  %if &n_rows_f > 0 %then %do;
    title "&dom -- Categorical Statistics (level, n, % of non-missing, n-missing)";
    %if %length(&note) > 0 %then %do;
      title2 "&note";
    %end;
    proc report data=&freq_ds nowd
        style(header)=[background=CX0021A5 color=white fontweight=bold]
        style(column)=[fontsize=8pt];
      %freq_col_stmt
      define varname       / display "Variable"  style(column)=[width=1.2in];
      define sas_label     / display "Label"     style(column)=[width=1.8in];
      define level         / display "Level"     style(column)=[width=1.0in];
      define n_disp_pool   / display "N";
      define pct_disp_pool / display "%";
      %local i yr;
      %do i = 1 %to &n_years;
        %let yr = %scan(&year_list, &i);
        define n_disp_&yr   / display "N";
        define pct_disp_&yr / display "%";
      %end;
    run;
    title;
    %if &tab_started = 0 %then %do;
      ods excel options(sheet_interval="none");
    %end;
  %end;
%mend report_domain;

/* D5 note about _30_DAY_MORTALITY missingness */
%let d5_note = _30_DAY_MORTALITY -- missingness reflects the md1 join (cases not in md1 have no outcome value) and does not indicate the outcome itself;

%report_domain(dom=D1, means_ds=work.means_d1_wide, freq_ds=work.freq_d1_wide, note=);
%report_domain(dom=D2, means_ds=work.means_d2_wide, freq_ds=work.freq_d2_wide,
               note=%bquote(&D3_DENOM_NOTE));
%report_domain(dom=D3, means_ds=work.means_d3_wide, freq_ds=work.freq_d3_wide,
               note=%bquote(&D3_DENOM_NOTE));
%report_domain(dom=D4, means_ds=work.means_d4_wide, freq_ds=work.freq_d4_wide, note=);
%report_domain(dom=D5, means_ds=work.means_d5_wide, freq_ds=work.freq_d5_wide,
               note=&d5_note);

/* ---- 9.6 Crosswalk sheet -------------------------------------------------- */
ods excel options(sheet_name="Crosswalk" sheet_interval="now");
title "Crosswalk -- All Variables (including OUT_OF_SCOPE identifiers)";
proc report data=g.var_domain_map(keep=varname sas_label vtype n_levels stat_route
                                       source_dataset domain domain_rationale
                                       assign_rule denominator_note)
    nowd
    style(header)=[background=CX0021A5 color=white fontweight=bold]
    style(column)=[fontsize=8pt];
  columns varname sas_label vtype n_levels stat_route source_dataset
          domain domain_rationale assign_rule denominator_note;
  define varname          / display "Variable"       style(column)=[width=1.2in];
  define sas_label        / display "Label"          style(column)=[width=1.8in];
  define vtype            / display "Type"           style(column)=[width=0.4in];
  define n_levels         / display "N Levels";
  define stat_route       / display "Stat Route"     style(column)=[width=0.7in];
  define source_dataset   / display "Source"         style(column)=[width=1.0in];
  define domain           / display "Domain"         style(column)=[width=0.6in];
  define domain_rationale / display "Domain Rationale" style(column)=[width=2.0in];
  define assign_rule      / display "Assign Rule"    style(column)=[width=0.8in];
  define denominator_note / display "Denominator Note" style(column)=[width=1.8in];
run;
ods excel options(sheet_interval="none");
title;

/* ---- 9.7 QC sheet --------------------------------------------------------- */
/* Build work.qc_summary from accumulated macro variables and sentinel_log.    */

/* Per-domain variable counts from g.var_domain_map */
%let n_d1=0; %let n_d2=0; %let n_d3=0; %let n_d4=0; %let n_d5=0;
%let n_oos=0; %let n_oos_id=0; %let n_oos_dict=0; %let n_oos_lookup=0;
%let n_rule_timing=0; %let n_rule_analytic=0; %let n_rule_instrument=0;
%let n_total_recodes=0;
%let n_supp_level=0; %let n_supp_nmiss=0; %let n_supp_comp=0; %let n_supp_cont=0;

proc sql noprint;
  select count(*) into :n_d1           trimmed from g.var_domain_map where domain='D1';
  select count(*) into :n_d2           trimmed from g.var_domain_map where domain='D2';
  select count(*) into :n_d3           trimmed from g.var_domain_map where domain='D3';
  select count(*) into :n_d4           trimmed from g.var_domain_map where domain='D4';
  select count(*) into :n_d5           trimmed from g.var_domain_map where domain='D5';
  select count(*) into :n_oos          trimmed from g.var_domain_map where domain='OUT_OF_SCOPE';
  select count(*) into :n_oos_id       trimmed from g.var_domain_map
    where domain='OUT_OF_SCOPE' and index(domain_rationale,'identifier') > 0;
  select count(*) into :n_oos_dict     trimmed from g.var_domain_map
    where domain='OUT_OF_SCOPE' and index(domain_rationale,'not in PRECEDE dictionary') > 0;
  select count(*) into :n_oos_lookup   trimmed from g.var_domain_map
    where domain='OUT_OF_SCOPE' and index(domain_rationale,'not in domain lookup') > 0;
  select count(*) into :n_rule_timing  trimmed from g.var_domain_map where assign_rule='timing';
  select count(*) into :n_rule_analytic trimmed from g.var_domain_map where assign_rule='analytic_role';
  select count(*) into :n_rule_instrument trimmed from g.var_domain_map where assign_rule='instrument';
  select coalesce(sum(n_recoded), 0) into :n_total_recodes trimmed from work.sentinel_log;
quit;

/* Accumulate across all domains for suppression by reason */
%macro count_supp_reason(domain_n=);
  %local _sl _sn _sc _sk;
  %let _sl=0; %let _sn=0; %let _sc=0; %let _sk=0;
  proc sql noprint;
    select count(*) into :_sl trimmed from work.freq_d&domain_n._display where supp_reason='level_count';
    select count(*) into :_sn trimmed from work.freq_d&domain_n._display where supp_reason='n_missing';
    select count(*) into :_sc trimmed from work.freq_d&domain_n._display where supp_reason='complementary';
    select count(*) into :_sk trimmed from work.means_d&domain_n._display where supp_reason='continuous_small_n';
  quit;
  %let n_supp_level = %eval(&n_supp_level + &_sl);
  %let n_supp_nmiss = %eval(&n_supp_nmiss + &_sn);
  %let n_supp_comp  = %eval(&n_supp_comp  + &_sc);
  %let n_supp_cont  = %eval(&n_supp_cont  + &_sk);
%mend count_supp_reason;

/* Reset and re-accumulate across all 5 domains */
%let n_supp_level=0; %let n_supp_nmiss=0; %let n_supp_comp=0; %let n_supp_cont=0;
%count_supp_reason(domain_n=1);
%count_supp_reason(domain_n=2);
%count_supp_reason(domain_n=3);
%count_supp_reason(domain_n=4);
%count_supp_reason(domain_n=5);

data work.qc_summary;
  length item $80 value $200;
  item="Run datetime";          value="%sysfunc(datetime(), datetime20.)";       output;
  item="Source dataset";        value="work.analysis_base_ext";                  output;
  item="Source rows";           value="&n_base_rows";                            output;
  item="Year variable";         value="&year_variable";                          output;
  item="Years available";       value="&year_list";                              output;
  item="";                      value="";                                         output;
  item="Variables D1";          value="&n_d1";                                   output;
  item="Variables D2";          value="&n_d2";                                   output;
  item="Variables D3";          value="&n_d3";                                   output;
  item="Variables D4";          value="&n_d4";                                   output;
  item="Variables D5";          value="&n_d5";                                   output;
  item="OUT_OF_SCOPE total";    value="&n_oos";                                  output;
  item="  -- identifier/key";   value="&n_oos_id";                               output;
  item="  -- not in dictionary";value="&n_oos_dict";                             output;
  item="  -- not in lookup";    value="&n_oos_lookup";                           output;
  item="";                      value="";                                         output;
  item="Assign_rule timing";    value="&n_rule_timing";                          output;
  item="Assign_rule analytic_role"; value="&n_rule_analytic";                    output;
  item="Assign_rule instrument"; value="&n_rule_instrument";                     output;
  item="";                      value="";                                         output;
  item="Total sentinel recodes";value="&n_total_recodes";                        output;
  item="Total suppressed cells";value="&n_suppressed";                           output;
  item="  -- level_count";      value="&n_supp_level";                           output;
  item="  -- n_missing";        value="&n_supp_nmiss";                           output;
  item="  -- complementary";    value="&n_supp_comp";                            output;
  item="  -- continuous_small_n"; value="&n_supp_cont";                          output;
  item="D3/frailty denominator note"; value=symget('D3_DENOM_NOTE');   output;
run;

ods excel options(sheet_name="QC" sheet_interval="now");
title "QC Sheet -- Run Metadata and Validation Counts";
proc report data=work.qc_summary nowd
    style(header)=[background=CX0021A5 color=white fontweight=bold]
    style(column)=[fontsize=9pt];
  columns item value;
  define item  / display "Item"  style(column)=[width=2.0in fontweight=bold];
  define value / display "Value" style(column)=[width=3.0in];
run;
title;
ods excel options(sheet_interval="none");

/* Per-variable sentinel recode counts on QC sheet (separate table) */
title "QC Sheet -- Per-Variable Sentinel Recode Counts";
proc report data=work.sentinel_log nowd
    style(header)=[background=CX0021A5 color=white fontweight=bold]
    style(column)=[fontsize=9pt];
  columns varname sentinel_kind n_recoded;
  define varname       / display "Variable"      style(column)=[width=1.5in];
  define sentinel_kind / display "Sentinel Type" style(column)=[width=1.0in];
  define n_recoded     / display "Recode Count";
run;
title;

/* Close ODS EXCEL */
ods excel close;
%let ods_excel_open = 0;
ods listing;

%put NOTE: ==== Section 9 complete. Workbook written. ====;


/* =========================================================================
   SECTION 10: QC text artifact
   -------------------------------------------------------------------------
   qc\17_summary_stats_by_domain.txt -- machine-readable QC facts
   No apostrophes or embedded semicolons in any literal string.
   ========================================================================= */

%put NOTE: ==== Section 10: QC text artifact starting ====;

data _null_;
  file "&qc_path.\17_summary_stats_by_domain.txt";
  put "17_summary_stats_by_domain -- QC Artifact";
  put "Run: %sysfunc(datetime(), datetime20.)";
  put "=======================================================================";
  put " ";
  put "source=work.analysis_base_ext (g.analysis_base + extension columns)";
  put "source_rows=&n_base_rows";
  put "year_variable=&year_variable";
  put "years_available=&year_list";
  put " ";
  put "DOMAIN VARIABLE COUNTS";
  put "D1_variables=&n_d1";
  put "D2_variables=&n_d2";
  put "D3_variables=&n_d3";
  put "D4_variables=&n_d4";
  put "D5_variables=&n_d5";
  put "OUT_OF_SCOPE_total=&n_oos";
  put "OUT_OF_SCOPE_identifier_or_key=&n_oos_id";
  put "OUT_OF_SCOPE_not_in_dictionary=&n_oos_dict";
  put "OUT_OF_SCOPE_not_in_domain_lookup=&n_oos_lookup";
  put " ";
  put "ASSIGNMENT RULE COUNTS";
  put "assign_rule_timing=&n_rule_timing";
  put "assign_rule_analytic_role=&n_rule_analytic";
  put "assign_rule_instrument=&n_rule_instrument";
  put " ";
  put "SENTINEL RECODES";
  put "total_sentinel_recodes=&n_total_recodes";
  put " ";
  put "SUPPRESSION SUMMARY";
  put "total_suppressed_cells=&n_suppressed";
  put "suppressed_level_count=&n_supp_level";
  put "suppressed_n_missing=&n_supp_nmiss";
  put "suppressed_complementary=&n_supp_comp";
  put "suppressed_continuous_small_n=&n_supp_cont";
  put " ";
  put "D3_FRAILTY_DENOMINATOR_NOTE=&D3_DENOM_NOTE";
  put " ";
  put "SUPPRESSION RULE";
  put "Cells representing &SUPPRESS_MAX or fewer patients are shown as &SUPPRESS_LABEL";
  put "Continuous blocks at or below that count have ALL statistics suppressed";
  put " ";
  put "DENOMINATOR RULE (D-02)";
  put "Percents computed on non-missing denominator";
  put "N-missing is reported separately and suppressed on the same rule";
run;

%put NOTE: ==== Section 10 complete. QC text artifact written. ====;


/* =========================================================================
   SECTION 11: Verify outputs, then restore log
   -------------------------------------------------------------------------
   Order matters: %fail_out calls %restore_log internally, so checking
   outputs AFTER %restore_log is backwards -- the checks must come FIRST.
   Both deliverables must exist before the log is restored.
   ========================================================================= */

%put NOTE: ==== Section 11: Output verification starting ====;

%macro check_xlsx;
  %if %sysfunc(fileexist(%bquote(&qc_path.\17_summary_stats_by_domain.xlsx))) = 0 %then %do;
    %fail_out(msg=VERIFY FAILED: qc\17_summary_stats_by_domain.xlsx was not created);
  %end;
  %put NOTE: [17-S11] VERIFIED: qc\17_summary_stats_by_domain.xlsx exists.;
%mend check_xlsx;

%macro check_qc_txt;
  %if %sysfunc(fileexist(%bquote(&qc_path.\17_summary_stats_by_domain.txt))) = 0 %then %do;
    %fail_out(msg=VERIFY FAILED: qc\17_summary_stats_by_domain.txt was not created);
  %end;
  %put NOTE: [17-S11] VERIFIED: qc\17_summary_stats_by_domain.txt exists.;
%mend check_qc_txt;

%check_xlsx;
%check_qc_txt;

%put NOTE: ==== Section 11 complete. Both deliverables verified. ====;
%put NOTE: ==== Phase 17 Wave 3 complete. Proceeding to log restore. ====;

%restore_log;
