/*==========================================================================
  Program : 17_summary_stats_by_domain.sas
  Purpose : Wave 0 discovery and scaffold for five-domain descriptive
            summary statistics of every PRECEDE-dictionary-documented variable
            in g.analysis_base (extended with frailty, cognitive, and
            intraoperative-physiologic columns from g.master_data_merged).

  Output  : qc\17_summary_stats_by_domain.xlsx   (Waves 2-3, after Checkpoint 1)
            qc\17_summary_stats_by_domain.txt     (Waves 2-3, after Checkpoint 1)
            qc\17_discovery.txt                   (Wave 0, this program)

  Reads   : g.analysis_base            (read-only)
            g.master_data_merged       (read-only)
            docs/precede_dictionary.csv

  Author  : 2026-09-03

  Wave structure:
    Section 0:  Options, config include, log routing, fail_out, preconditions
    Section 0b: Discovery — year variable, key metadata, extension list,
                coverage, identifiers, sentinel applicability
    [Sections 1-11 added in Waves 1-3 after Checkpoint 1 approval]

  PCM compliance:
    - No bare open-code %IF (all conditional logic inside named macros)
    - No apostrophes and no embedded semicolons in %PUT text
    - Every %abort cancel inside %fail_out only
    - No &SQLOBS; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - dictionary.columns.TYPE is char/num, not 1/2
==========================================================================*/


/* =========================================================================
   SECTION 0: Options, config include, log routing, preconditions
   ========================================================================= */

options nodate nonumber ps=max ls=200 nofmterr;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* ---- Checkpoint 1 approval gate -----------------------------------------
   Set DOMAIN_MAP_APPROVED = 1 only after Gerard reviews and approves
   qc\17_var_domain_map_review.csv (Wave 1 output). Sections 5-11 (statistics
   and workbook assembly) are unreachable until the flag is 1.            */
%let DOMAIN_MAP_APPROVED = 0;   /* set to 1 only after Gerard approves qc\17_var_domain_map_review.csv */

/* ---- Small-cell suppression constants ------------------------------------
   SUPPRESS_MAX  : cells with n <= &SUPPRESS_MAX are suppressed.
   SUPPRESS_LABEL: the display string replacing suppressed cells.
   NOTE: do NOT use <11 as the label. Under n <= 11, a cell of exactly 11
   labelled <11 is a false statement. The rule here is n <= 11 with -- label. */
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

/* ---- Checkpoint 1 gate macro ------------------------------------------- */
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
    %fail_out(msg=docs/precede_dictionary.csv not found);
  %end;
%mend check_dict_csv;
%check_dict_csv;

/* ---- Source dataset existence: g.analysis_base ------------------------- */
proc sql noprint;
  select count(*) into :n_tab_base trimmed
  from dictionary.tables
  where libname='G' and memname='ANALYSIS_BASE';
quit;

%macro check_src_base;
  %if %length(&n_tab_base) = 0 %then %do;
    %fail_out(msg=Existence query for g.analysis_base returned no value);
  %end;
  %else %if &n_tab_base ne 1 %then %do;
    %fail_out(msg=g.analysis_base not found in g library);
  %end;
%mend check_src_base;
%check_src_base;

/* ---- Source dataset existence: g.master_data_merged -------------------- */
proc sql noprint;
  select count(*) into :n_tab_merged trimmed
  from dictionary.tables
  where libname='G' and memname='MASTER_DATA_MERGED';
quit;

%macro check_src_merged;
  %if %length(&n_tab_merged) = 0 %then %do;
    %fail_out(msg=Existence query for g.master_data_merged returned no value);
  %end;
  %else %if &n_tab_merged ne 1 %then %do;
    %fail_out(msg=g.master_data_merged not found in g library);
  %end;
%mend check_src_merged;
%check_src_merged;

/* ---- Row count: g.analysis_base ---------------------------------------- */
proc sql noprint;
  select count(*) into :n_base_rows trimmed from g.analysis_base;
quit;

%macro check_rows;
  %if %length(&n_base_rows) = 0 %then %do;
    %fail_out(msg=Row count query for g.analysis_base returned no value);
  %end;
  %else %if &n_base_rows = 0 %then %do;
    %fail_out(msg=g.analysis_base is empty);
  %end;
  %put NOTE: [17] &n_base_rows rows in g.analysis_base.;
%mend check_rows;
%check_rows;


/* =========================================================================
   SECTION 0b: Discovery
   -------------------------------------------------------------------------
   Answers every open question from 17-RESEARCH.md before any statistics
   are planned. Writes results to qc\17_discovery.txt.
   Produces NO permanent datasets and writes NOTHING to g.
   work.ext_candidates is left in WORK for Wave 1 to build &extension_keep_list.
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

/* ---- 2. KEY METADATA: type and length of PRECEDE_STUDY_ID in both datasets */
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

/* Sample 10 non-missing key values from each dataset */
proc sql noprint;
  select PRECEDE_STUDY_ID into :key_sample_base separated by '|'
  from (
    select PRECEDE_STUDY_ID from g.analysis_base
    where not missing(PRECEDE_STUDY_ID)
  )
  having monotonic() <= 10;

  select PRECEDE_STUDY_ID into :key_sample_merged separated by '|'
  from (
    select PRECEDE_STUDY_ID from g.master_data_merged
    where not missing(PRECEDE_STUDY_ID)
  )
  having monotonic() <= 10;
quit;

/* ---- 3. KEY UNIQUENESS: duplicate PRECEDE_STUDY_ID in g.master_data_merged */
proc sql noprint;
  select count(*) into :n_key_dups trimmed
  from (
    select PRECEDE_STUDY_ID
    from g.master_data_merged
    group by PRECEDE_STUDY_ID
    having count(*) > 1
  );
quit;

/* ---- 4. YEAR VARIABLE: candidate columns in g.analysis_base ------------ */
proc sql;
  create table work.year_candidates as
    select name, vtype, sas_label
    from work.cols_base
    where index(name,'YEAR')>0
       or index(name,'_DATE')>0
       or index(name,'SURG')>0
       or index(name,'ENCOUNTER')>0;
quit;

/* Run PROC FREQ with /missing on all numeric year-name candidates */
%macro freq_year_candidates;
  %local dsid nobs rc i vname;
  %let dsid = %sysfunc(open(work.year_candidates));
  %let nobs  = %sysfunc(attrn(&dsid, nobs));
  %let rc    = %sysfunc(close(&dsid));

  %do i = 1 %to &nobs;
    %let dsid  = %sysfunc(open(work.year_candidates));
    %let rc    = %sysfunc(fetchobs(&dsid, &i));
    %let vname = %sysfunc(getvarc(&dsid, %sysfunc(varnum(&dsid, name))));
    %let vtype = %sysfunc(getvarc(&dsid, %sysfunc(varnum(&dsid, vtype))));
    %let rc    = %sysfunc(close(&dsid));

    %if %index(&vname, YEAR) > 0 and &vtype = num %then %do;
      %put NOTE: [17-discovery] Running PROC FREQ on year candidate: &vname;
      proc freq data=g.analysis_base;
        tables &vname / missing;
        title "Year candidate: &vname";
      run;
      title;
    %end;
  %end;
%mend freq_year_candidates;
%freq_year_candidates;

/* ---- 5. EXTENSION COLUMN LIST (D-01 KEEP=) ----------------------------- */
/* Columns in g.master_data_merged NOT in g.analysis_base, filtered to
   frailty/cognitive/intraop-physiologic concepts. MAC matched by anchored
   pattern only -- bare index(name,'MAC') matches PHARMACY, STOMACH, etc. */
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

/* ---- 6. EXTENSION COVERAGE: non-missing count per extension column ------ */
/* work.ext_candidates is queried dynamically. Coverage vs. n_base_rows. */
%macro ext_coverage;
  %local dsid nobs rc i vname;
  %let dsid = %sysfunc(open(work.ext_candidates));
  %let nobs  = %sysfunc(attrn(&dsid, nobs));
  %let rc    = %sysfunc(close(&dsid));

  /* Build coverage table */
  data work.ext_coverage;
    length varname $32 n_nonmissing 8 pct_of_base 8;
    stop;
  run;

  %do i = 1 %to &nobs;
    %let dsid  = %sysfunc(open(work.ext_candidates));
    %let rc    = %sysfunc(fetchobs(&dsid, &i));
    %let vname = %sysfunc(getvarc(&dsid, %sysfunc(varnum(&dsid, name))));
    %let rc    = %sysfunc(close(&dsid));

    proc sql noprint;
      select count(*) into :n_nm trimmed
      from g.master_data_merged
      where not missing(&vname);
    quit;

    data work._cov_row;
      length varname $32 n_nonmissing 8 pct_of_base 8;
      varname      = "&vname";
      n_nonmissing = &n_nm;
      pct_of_base  = 100 * &n_nm / &n_base_rows;
    run;

    proc append base=work.ext_coverage data=work._cov_row force; run;
  %end;
%mend ext_coverage;
%ext_coverage;

/* ---- 7. IDENTIFIER CANDIDATES ----------------------------------------- */
proc sql;
  create table work.id_candidates as
    select name, vtype, vlen
    from work.cols_base
    where index(name,'_ID')    > 0
       or index(name,'ID_')    > 0
       or name in ('PRECEDE_STUDY_ID','ENCRYPTED_MRN','ENCRYPTED_ENCOUNTER')
       or index(name,'MRN')    > 0
       or index(name,'ENCOUNTER') > 0;
quit;

/* High-cardinality character variables (>200 levels) via proc freq nlevels */
proc freq data=g.analysis_base nlevels;
  tables _character_ / noprint;
  ods output nlevels=work.char_nlevels;
run;

proc sql;
  create table work.hi_card_chars as
    select tablevar as name length=32, nlevels
    from work.char_nlevels
    where nlevels > 200;
quit;

/* ---- 8. SENTINEL APPLICABILITY ----------------------------------------- */
/* For each numeric variable: count rows = -999.
   For each character variable: count rows where upcase(strip(x))='NULL'.
   Write only variables with a non-zero count.                              */
%macro check_sentinels;
  %local dsid nobs rc i vname vtype_v n_sent;

  /* Numeric sentinels */
  data work.sentinel_log;
    length varname $32 sentinel_kind $8 n_sentinel 8;
    stop;
  run;

  /* numeric variables */
  %let dsid = %sysfunc(open(work.cols_base));
  %let nobs  = %sysfunc(attrn(&dsid, nobs));
  %let rc    = %sysfunc(close(&dsid));

  %do i = 1 %to &nobs;
    %let dsid    = %sysfunc(open(work.cols_base));
    %let rc      = %sysfunc(fetchobs(&dsid, &i));
    %let vname   = %sysfunc(getvarc(&dsid, %sysfunc(varnum(&dsid, name))));
    %let vtype_v = %sysfunc(getvarc(&dsid, %sysfunc(varnum(&dsid, vtype))));
    %let rc      = %sysfunc(close(&dsid));

    %if &vtype_v = num %then %do;
      proc sql noprint;
        select count(*) into :n_sent trimmed
        from g.analysis_base
        where &vname = -999;
      quit;
      %if &n_sent > 0 %then %do;
        data work._sent_row;
          length varname $32 sentinel_kind $8 n_sentinel 8;
          varname      = "&vname";
          sentinel_kind = '-999';
          n_sentinel   = &n_sent;
        run;
        proc append base=work.sentinel_log data=work._sent_row force; run;
      %end;
    %end;

    %if &vtype_v = char %then %do;
      proc sql noprint;
        select count(*) into :n_sent trimmed
        from g.analysis_base
        where upcase(strip(&vname)) = 'NULL';
      quit;
      %if &n_sent > 0 %then %do;
        data work._sent_row;
          length varname $32 sentinel_kind $8 n_sentinel 8;
          varname      = "&vname";
          sentinel_kind = 'NULL';
          n_sentinel   = &n_sent;
        run;
        proc append base=work.sentinel_log data=work._sent_row force; run;
      %end;
    %end;
  %end;
%mend check_sentinels;
%check_sentinels;

/* ---- 9. IN-DATA-ONLY / DEFECT scan: VARnn positional names ------------- */
proc sql noprint;
  select count(*) into :n_varnn trimmed
  from work.cols_base
  where prxmatch('/^VAR\d+$/', strip(name)) > 0;
quit;

/* ---- 10. Write qc\17_discovery.txt ------------------------------------- */
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
    put "PRECEDE_STUDY_ID in g.analysis_base:    type=&key_type_base  length=&key_len_base";
    put "PRECEDE_STUDY_ID in g.master_data_merged: type=&key_type_merged  length=&key_len_merged";
    put " ";
    put "Sampled key values from g.analysis_base (up to 10, pipe-separated):";
    put "&key_sample_base";
    put "Sampled key values from g.master_data_merged (up to 10, pipe-separated):";
    put "&key_sample_merged";
    put " ";

    put "--- KEY UNIQUENESS ---";
    put "Duplicate PRECEDE_STUDY_ID count in g.master_data_merged: &n_key_dups";
    %if &n_key_dups > 0 %then %do;
    put "WARNING: Duplicates present -- Wave 1 must resolve before merging";
    %end;
    %else %do;
    put "PRECEDE_STUDY_ID is unique in g.master_data_merged -- safe to merge";
    %end;
    put " ";

    put "--- VARNN DEFECT SCAN ---";
    put "Columns with positional VAR+digits names in g.analysis_base: &n_varnn";
    put " ";
  run;

  /* Append year candidates */
  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "--- YEAR VARIABLE CANDIDATES ---";
  run;
  proc export data=work.year_candidates
    outfile="&qc_path.\17_discovery.txt"
    dbms=dlm;
    delimiter='|';
    /* appending is not supported by proc export; use data step below */
  run;

  /* Write year candidates via data step */
  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "(See PROC FREQ output in SAS log/listing for per-year N and missing counts)";
    put "NOTE: If no YEAR candidate was found, derive year from a surgery date column.";
    set work.year_candidates;
    put "  Candidate: " name " type=" vtype " label=" sas_label;
    if _n_ = 1 then do;
      /* header already written above */
    end;
  run;

  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put " ";
  run;

  /* Append extension columns */
  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "--- EXTENSION COLUMN LIST (D-01 KEEP=) ---";
    put "(Columns in g.master_data_merged NOT in g.analysis_base, concept-filtered)";
    put "(PRECEDE_STUDY_ID_1 explicitly excluded -- md6 duplicate)";
    put " ";
    put "Paste as KEEP= list:";
  run;

  data _null_;
    set work.ext_candidates;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "  " name;
  run;

  /* Append extension coverage */
  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put " ";
    put "--- EXTENSION COVERAGE (non-missing count per extension column) ---";
    put "(Denominator: &n_base_rows rows in g.analysis_base)";
  run;

  data _null_;
    set work.ext_coverage;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    length flag $60;
    if pct_of_base < 90 then flag = 'PARTIAL COVERAGE -- D3/frailty require a stated denominator';
    else flag = '';
    put varname '  n_nonmissing=' n_nonmissing '  pct_of_base=' pct_of_base 6.1 '  ' flag;
  run;

  /* Append identifier candidates */
  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put " ";
    put "--- IDENTIFIER CANDIDATES (mark OUT_OF_SCOPE in Wave 1) ---";
  run;

  data _null_;
    set work.id_candidates;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "  " name;
  run;

  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put " ";
    put "--- HIGH-CARDINALITY CHARACTER VARIABLES (>200 levels) ---";
  run;

  data _null_;
    set work.hi_card_chars;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "  " name "  nlevels=" nlevels;
  run;

  /* Append sentinel applicability */
  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put " ";
    put "--- SENTINEL APPLICABILITY (Wave 2 recodes ONLY these variables) ---";
    put "  -999 sentinel (numeric variables):";
  run;

  data _null_;
    set work.sentinel_log;
    where sentinel_kind = '-999';
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "    " varname "  n=" n_sentinel;
  run;

  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "  NULL sentinel (character variables):";
  run;

  data _null_;
    set work.sentinel_log;
    where sentinel_kind = 'NULL';
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put "    " varname "  n=" n_sentinel;
  run;

  data _null_;
    file "&qc_path.\17_discovery.txt" lrecl=200 mod;
    put " ";
    put "=================================================================";
    put "End of Phase 17 Discovery Report";
    put "=================================================================";
  run;

  %put NOTE: [17] Discovery report written to &qc_path.\17_discovery.txt;
%mend write_discovery;
%write_discovery;


/* =========================================================================
   END OF WAVE 0 (Sections 0 and 0b)
   =========================================================================
   Sections 1-4 (Wave 1) follow immediately below.
   Sections 5-11 (Wave 2-3) are wrapped in %gate_stats and will abort
   until DOMAIN_MAP_APPROVED is set to 1 after Checkpoint 1 review.
   ========================================================================= */

%put NOTE: ==== Phase 17 Wave 0 discovery complete ====;
%put NOTE: Review qc\17_discovery.txt; Sections 1-4 (Wave 1) follow.;


/* =========================================================================
   SECTION 1: Build work.analysis_base_ext (D-01 join)
   -------------------------------------------------------------------------
   Steps:
     1. Key uniqueness gate (before any merge)
     2. Macro-time key type resolution from dictionary.columns
     3. Build work.merged_ext_cols with CHAR $12 key
     4. Sort both inputs; left merge to work.analysis_base_ext
     5. Row-count and cognitive-score non-missing assertion
     6. Extension coverage capture; denominator note when PARTIAL
   ========================================================================= */

%put NOTE: ==== Section 1: build work.analysis_base_ext starting ====;


/* ---- 1. KEY UNIQUENESS GATE (before any merge) ------------------------- */
/* A DATA step merge silently becomes a match-merge when the extension side  */
/* has duplicate keys. Assert BEFORE merging so the error names the cause.  */
proc sql noprint;
  select count(*) into :n_key_dups trimmed
  from (
    select PRECEDE_STUDY_ID
    from g.master_data_merged
    group by PRECEDE_STUDY_ID
    having count(*) > 1
  );
quit;

%macro check_key_unique;
  %if &n_key_dups > 0 %then %do;
    %fail_out(msg=&n_key_dups duplicate PRECEDE_STUDY_ID values in g.master_data_merged -- extension merge requires a unique key or an explicit collapse rule);
  %end;
  %put NOTE: [17-S1] PRECEDE_STUDY_ID uniqueness confirmed in g.master_data_merged (n_key_dups=&n_key_dups).;
%mend check_key_unique;
%check_key_unique;


/* ---- 2. MACRO-TIME KEY TYPE RESOLUTION --------------------------------- */
/* Read the stored TYPE of PRECEDE_STUDY_ID from dictionary.columns.         */
/* dictionary.columns.type is 'num' or 'char' (character strings), NOT 1/2. */
/* Do NOT write a runtime vtype() branch: SAS compiles BOTH branches of a   */
/* DATA step IF, so put(charvar, best12.) is a compile-time error when the  */
/* key is character. Only macro-time branching is safe.                     */
proc sql noprint;
  select type into :key_type_merged trimmed
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED'
    and upcase(name)='PRECEDE_STUDY_ID';
quit;

%put NOTE: [17-S1] key_type_merged=&key_type_merged (resolved at macro time from dictionary.columns).;


/* ---- 3. Build KEEP= list from work.ext_candidates left by Wave 0 ------- */
/* Prefer building the list dynamically over hand-transcribing it.           */
/* If Wave 0 did not run in this session, ext_candidates is not in WORK;    */
/* the error surfaces here with a clear message.                             */
proc sql noprint;
  select count(*) into :n_ext_cand trimmed
  from dictionary.tables
  where libname='WORK' and memname='EXT_CANDIDATES';
quit;

%macro check_ext_candidates;
  %if &n_ext_cand = 0 %then %do;
    %fail_out(msg=work.ext_candidates not found in WORK -- Wave 0 (Section 0b) must run in the same SAS session before Section 1);
  %end;
%mend check_ext_candidates;
%check_ext_candidates;

proc sql noprint;
  select name into :extension_keep_list separated by ' '
  from work.ext_candidates;
quit;

%put NOTE: [17-S1] extension_keep_list (from work.ext_candidates): &extension_keep_list;


/* ---- 4. Cast key to CHAR $12 using MACRO-TIME branch ------------------- */
/* Format choice: best12. unless Wave 0 sampled keys show zero-padding.     */
/* z12. pads to 12 digits; numeric 123456789 -> '000123456789' while the    */
/* analysis_base side holds '123456789'; the merge then matches nothing and  */
/* every extension column comes back missing (silent failure, Pitfall 1).   */
%macro build_ext_cols;
  data work.merged_ext_cols;
    set g.master_data_merged (keep=PRECEDE_STUDY_ID &extension_keep_list);
    length key_char $12;
    %if &key_type_merged = num %then %do;
      key_char = strip(put(PRECEDE_STUDY_ID, best12.));
    %end;
    %else %do;
      key_char = strip(PRECEDE_STUDY_ID);
    %end;
    drop PRECEDE_STUDY_ID;
    rename key_char = PRECEDE_STUDY_ID;
  run;
%mend build_ext_cols;
%build_ext_cols;


/* ---- 5. Sort both inputs; left merge ----------------------------------- */
proc sort data=work.merged_ext_cols; by PRECEDE_STUDY_ID; run;
proc sort data=g.analysis_base out=work.analysis_base_sorted; by PRECEDE_STUDY_ID; run;

data work.analysis_base_ext;
  merge work.analysis_base_sorted (in=inbase)
        work.merged_ext_cols;
  by PRECEDE_STUDY_ID;
  if inbase;
run;

%put NOTE: [17-S1] work.analysis_base_ext built. Verifying row count and extension columns.;


/* ---- 6. Row-count assertion: work.analysis_base_ext = g.analysis_base -- */
proc sql noprint;
  select count(*) into :n_ext_rows trimmed from work.analysis_base_ext;
quit;

%macro check_ext_rows;
  %if &n_ext_rows ne &n_base_rows %then %do;
    %fail_out(msg=Row count mismatch after D-01 join: work.analysis_base_ext has &n_ext_rows rows but g.analysis_base has &n_base_rows -- possible duplicate key or merge error);
  %end;
  %put NOTE: [17-S1] Row-count assertion passed: &n_ext_rows rows (= n_base_rows).;
%mend check_ext_rows;
%check_ext_rows;


/* ---- 7. Cognitive-score non-missing guard ------------------------------- */
/* A count of 0 proves the key cast silently failed (type or format mismatch */
/* left all extension columns missing while the row count still matched).    */
/* Identify the cognitive score column dynamically from ext_candidates.      */
proc sql noprint;
  select name into :cog_col trimmed
  from work.ext_candidates
  where index(upcase(name),'COGNI') > 0 and index(upcase(name),'SCORE') > 0;
quit;

%macro check_cog_populated;
  %if %length(&cog_col) = 0 %then %do;
    %put WARNING: [17-S1] No cognitive score column (COGNI+SCORE) found in ext_candidates. Skipping cognitive-score guard.;
  %end;
  %else %do;
    proc sql noprint;
      select count(*) into :n_cog_nonmiss trimmed
      from work.analysis_base_ext
      where not missing(&cog_col);
    quit;
    %if &n_cog_nonmiss = 0 %then %do;
      %fail_out(msg=Cognitive score column &cog_col is all-missing in work.analysis_base_ext -- key type or format mismatch caused a silent join failure (Pitfall 1));
    %end;
    %put NOTE: [17-S1] Cognitive score guard passed: &cog_col has &n_cog_nonmiss non-missing values.;
  %end;
%mend check_cog_populated;
%check_cog_populated;


/* ---- 8. Extension coverage capture ------------------------------------- */
/* Per-column non-missing N in work.analysis_base_ext.                       */
/* Sets denominator note macro variable when coverage is PARTIAL             */
/* (any extension column < 90% of base). Wave 3 prints this on KEY sheet    */
/* and affected domain sheets; without it D3 reads as ~95% missing.         */
%macro compute_ext_coverage;
  %local dsid nobs rc i vname n_nm;

  /* Build per-column coverage table */
  data work.ext_coverage_ext;
    length varname $32 n_nonmiss 8 pct_of_base 8 coverage_flag $60;
    stop;
  run;

  %let dsid = %sysfunc(open(work.ext_candidates));
  %let nobs  = %sysfunc(attrn(&dsid, nobs));
  %let rc    = %sysfunc(close(&dsid));

  %do i = 1 %to &nobs;
    %let dsid  = %sysfunc(open(work.ext_candidates));
    %let rc    = %sysfunc(fetchobs(&dsid, &i));
    %let vname = %sysfunc(getvarc(&dsid, %sysfunc(varnum(&dsid, name))));
    %let rc    = %sysfunc(close(&dsid));

    proc sql noprint;
      select count(*) into :n_nm trimmed
      from work.analysis_base_ext
      where not missing(&vname);
    quit;

    data work._cov_row_ext;
      length varname $32 n_nonmiss 8 pct_of_base 8 coverage_flag $60;
      varname      = "&vname";
      n_nonmiss    = &n_nm;
      pct_of_base  = 100 * &n_nm / &n_base_rows;
      if pct_of_base < 90 then
        coverage_flag = 'PARTIAL COVERAGE -- D3/frailty require a stated denominator';
      else coverage_flag = '';
    run;

    proc append base=work.ext_coverage_ext data=work._cov_row_ext force; run;
  %end;

  /* Check for any PARTIAL coverage to set the denominator note */
  proc sql noprint;
    select count(*) into :n_partial_cov trimmed
    from work.ext_coverage_ext
    where coverage_flag ne '';
  quit;

  %if &n_partial_cov > 0 %then %do;
    %global D3_DENOM_NOTE;
    %let D3_DENOM_NOTE = D3 and the D2 frailty block are computed on the subcohort with a non-missing assessment (n=&n_cog_nonmiss), not on the &n_base_rows base;
    %put NOTE: [17-S1] PARTIAL coverage detected for &n_partial_cov extension columns. D3_DENOM_NOTE set.;
  %end;
  %else %do;
    %global D3_DENOM_NOTE;
    %let D3_DENOM_NOTE = ;
    %put NOTE: [17-S1] Full coverage for all extension columns. No denominator note needed.;
  %end;
%mend compute_ext_coverage;
%compute_ext_coverage;

%put NOTE: ==== Section 1 complete: work.analysis_base_ext ready ====;


/* =========================================================================
   SECTION 2: Import PRECEDE dictionary
   -------------------------------------------------------------------------
   Reads docs\precede_dictionary.csv and builds work.dict_u (one row per
   upcased sas_name, authoritative sheet preferred).
   Pattern copied from sas/16_summary_docx.sas lines 147-181.
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
  /* UPCASE before sort — BY-group is case-sensitive */
  sas_name    = upcase(strip(cats(_a)));
  if missing(sas_name) then delete;
  /* MASTER_DATASET first, DERIVED second, so authoritative sheet wins */
  if      sheet = 'MASTER_DATASET'           then sheet_rank = 1;
  else if sheet = 'DERIVED_VARIABLES_MASTER' then sheet_rank = 2;
  else                                            sheet_rank = 3;
  keep sheet dict_name dict_type description sas_name sheet_rank;
run;

proc sort data=work.dict; by sas_name sheet_rank sheet; run;

/* One row per documented name — dictionary repeats names across sheets */
data work.dict_u;
  set work.dict;
  by sas_name;
  if first.sas_name;
run;

%put NOTE: ==== Section 2 complete: work.dict_u ready ====;


/* =========================================================================
   SECTION 3: Match dictionary against work.analysis_base_ext
   -------------------------------------------------------------------------
   Three-tier match: exact, case-insensitive, squash (compress underscores).
   Match against ANALYSIS_BASE_EXT (NOT ANALYSIS_BASE) — the extended dataset
   includes extension columns that need to be documented.
   Produces: work.var_domain_raw, work.dict_only, work.data_only
   ========================================================================= */

%put NOTE: ==== Section 3: dictionary match starting ====;

proc sql;
  create table work.actual_ext as
    select upcase(name) as var_u     length=32,
           name         as varname   length=32,
           type         as vtype     length=4,
           length       as vlen,
           label        as sas_label length=256,
           varnum
    from dictionary.columns
    where libname='WORK' and memname='ANALYSIS_BASE_EXT';

  /* OR-join: exact or squash match; rank to keep strongest */
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

/* Keep strongest match per variable */
data work.var_domain_raw;
  set work.doc_all_ext;
  by varname;
  if first.varname;
run;

/* Match ties: two dictionary entries matching one column equally */
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

/* Reconciliation buckets */
proc sql noprint;
  /* dictionary-only: in dict, not in data */
  create table work.dict_only as
    select sas_name as varname length=32
    from work.dict_u
    where upcase(sas_name) not in
          (select var_u from work.actual_ext);

  /* data-only: in data, not in dictionary (including extension cols) */
  create table work.data_only as
    select varname, vtype, sas_label
    from work.actual_ext
    where varname not in
          (select varname from work.var_domain_raw);

  select count(*) into :n_data_only trimmed from work.data_only;
  select count(*) into :n_dict_only trimmed from work.dict_only;
  select count(*) into :n_matched   trimmed from work.var_domain_raw;
quit;

%put NOTE: [17-S3] Match summary: &n_matched matched, &n_dict_only dict-only, &n_data_only data-only;


/* =========================================================================
   SECTION 3b: Identifier exclusion (BEFORE domain assignment)
   -------------------------------------------------------------------------
   Identifiers and technical keys must never reach statistics. A character ID
   routed to PROC FREQ yields a ~41,000-level table and an unusable sheet.
   Mark OUT_OF_SCOPE with rationale. These rows stay in the crosswalk.
   Write excluded list to QC log.
   ========================================================================= */

/* ---- SECTION 3c: NLEVELS pass for stat_route --------------------------- */
/* Run once over work.analysis_base_ext to capture distinct level counts.   */
/* Routing on vtype alone sends every numeric to PROC MEANS, which is wrong */
/* for 0/1 or small-integer-coded categoricals (_30_DAY_MORTALITY, sex,     */
/* ASA class, emergent Y/N). Type AND cardinality determine the route.      */

proc freq data=work.analysis_base_ext nlevels;
  tables _all_ / noprint;
  ods output nlevels=work.nlevels_ext;
run;

/* Normalise variable name to UPCASE for join */
data work.nlevels_ext;
  set work.nlevels_ext;
  varname_u = upcase(strip(tablevar));
  rename nlevels = n_levels;
run;

/* ---- Build combined domain staging table ------------------------------- */
/* Start from matched variables + data-only variables */

/* Add data-only rows with OUT_OF_SCOPE pre-set */
data work.data_only_oos;
  set work.data_only;
  domain           = 'OUT_OF_SCOPE';
  domain_rationale = 'not in PRECEDE dictionary';
  assign_rule      = 'data_only';
  dict_name        = '';
  match_how        = 'NONE';
  source_dataset   = 'analysis_base_ext';
run;

/* Combine matched + data-only into one staging table */
data work.domain_staging;
  length varname $32 vtype $4 vlen 8 sas_label $256
         dict_name $60 dict_type $20 description $300 match_how $8
         domain $16 domain_rationale $200 assign_rule $20
         source_dataset $32 stat_route $8 n_levels 8 denominator_note $300;

  set work.var_domain_raw (in=inmatched)
      work.data_only_oos  (in=indataonly);

  /* source_dataset: matched vars are from analysis_base or master_data_merged */
  if inmatched then do;
    /* Check if varname is one of the extension columns */
    if varname in (%do _vi = 1 %to 1; /* placeholder — will use WHERE join below */ %end; '') then
      source_dataset = 'master_data_merged';
    else source_dataset = 'analysis_base';
  end;
  if indataonly then source_dataset = 'analysis_base_ext';

  /* Initialize domain fields for matched rows */
  if inmatched then do;
    domain           = '';
    domain_rationale = '';
    assign_rule      = '';
  end;
run;

/* Better source_dataset assignment using SQL join to ext_candidates */
proc sql;
  create table work.domain_staging2 as
    select ds.*,
           case when ec.name is not null then 'master_data_merged'
                when ds.source_dataset = 'analysis_base_ext' then 'analysis_base_ext'
                else 'analysis_base' end as src_ds length=32
    from work.domain_staging as ds
    left join work.ext_candidates as ec
      on upcase(ds.varname) = upcase(ec.name);
quit;

data work.domain_staging2;
  set work.domain_staging2;
  if source_dataset ne 'analysis_base_ext' then
    source_dataset = src_ds;
  drop src_ds;
run;

/* Join n_levels from the nlevels pass */
proc sql;
  create table work.domain_staging3 as
    select ds.*,
           coalesce(nl.n_levels, 0) as n_levels_join
    from work.domain_staging2 as ds
    left join work.nlevels_ext as nl
      on upcase(ds.varname) = nl.varname_u;
quit;

data work.domain_staging3;
  set work.domain_staging3;
  if n_levels = . or n_levels = 0 then n_levels = n_levels_join;
  drop n_levels_join;
run;


/* ---- Apply identifier exclusion --------------------------------------- */
data work.domain_staging3;
  set work.domain_staging3;

  /* Mark identifiers OUT_OF_SCOPE before any domain assignment */
  if domain = '' then do;
    if varname in ('PRECEDE_STUDY_ID','PRECEDE_STUDY_ID_1',
                   'ENCRYPTED_MRN','ENCRYPTED_ENCOUNTER')
       or prxmatch('/(^|_)(ID|MRN)(_|$)/', strip(upcase(varname))) > 0
       or (vtype = 'char' and n_levels > 200)
    then do;
      domain           = 'OUT_OF_SCOPE';
      domain_rationale = 'identifier or technical key; not an analytic variable';
      assign_rule      = 'identifier_exclusion';
    end;
  end;
run;

/* Log identifier-excluded variables for reviewer */
data work.id_excluded_log;
  set work.domain_staging3;
  where domain = 'OUT_OF_SCOPE' and assign_rule = 'identifier_exclusion';
  keep varname vtype n_levels domain domain_rationale;
run;

proc sql noprint;
  select count(*) into :n_id_excluded trimmed from work.id_excluded_log;
quit;
%put NOTE: [17-S3b] &n_id_excluded variables marked OUT_OF_SCOPE as identifiers/high-cardinality.;


/* ---- Apply stat_route (type AND cardinality) -------------------------- */
data work.domain_staging3;
  set work.domain_staging3;

  if domain ne 'OUT_OF_SCOPE' and domain ne 'data_only' then do;
    if vtype = 'char' then stat_route = 'FREQ';
    else if vtype = 'num' then do;
      if n_levels <= 10 then stat_route = 'FREQ';
      else                   stat_route = 'MEANS';
    end;
  end;
  /* data-only OUT_OF_SCOPE rows get no route */
  else stat_route = '';
run;


/* =========================================================================
   SECTION 4: Domain assignment with rationales, g.var_domain_map, guards,
              and crosswalk CSV export
   -------------------------------------------------------------------------
   Build a DATA step lookup table keyed on upcased varname.
   Rationale literals are SINGLE-quoted (prevent macro trigger resolution).
   Three-step ordered rule: timing > analytic_role; instrument overrides both.
   ========================================================================= */

%put NOTE: ==== Section 4: domain assignment starting ====;

/* Domain assignment lookup — covers all matched, non-OUT_OF_SCOPE variables.
   Variables not listed here remain with domain='' and are caught by the
   blank-domain guard (they become OUT_OF_SCOPE / unrecognised).
   Rationale strings use SINGLE QUOTES throughout — no macro trigger risk.    */

data work.domain_lookup;
  length varname_u $32 domain $16 domain_rationale $200 assign_rule $20;
  infile datalines dsd;
  input varname_u $ domain $ assign_rule $ domain_rationale $;
datalines;
AGE_AT_SURGERY,D1,timing,'captured at surgery registration; sociodemographic descriptor'
AGE_AT_ENCOUNTER,D1,timing,'captured at encounter; sociodemographic descriptor'
SEX,D1,timing,'recorded at registration; biological sex as sociodemographic variable'
RACE,D1,timing,'recorded at registration; race as sociodemographic variable'
ETHNICITY,D1,timing,'recorded at registration; ethnicity as sociodemographic variable'
INSURANCE_TYPE,D1,analytic_role,'payer type known preoperatively; sociodemographic proxy'
PAYER,D1,analytic_role,'payer type known preoperatively; sociodemographic proxy'
MARITAL_STATUS,D1,timing,'recorded at registration; sociodemographic descriptor'
MARITAL,D1,timing,'recorded at registration; sociodemographic descriptor'
ZIP_CODE,D1,timing,'geographic locator recorded at registration; sociodemographic'
ZIPCODE,D1,timing,'geographic locator recorded at registration; sociodemographic'
STATE,D1,timing,'geographic locator recorded at registration; sociodemographic'
ADMIT_BMI,D2,timing,'captured at preoperative admission; preoperative physiologic assessment'
BMI,D2,timing,'measured preoperatively; standard preoperative assessment variable'
FRAILTY_SCORE,D2,instrument,'named frailty instrument score; preoperative assessment per D-02'
FRAILTY_CATEGORY,D2,instrument,'named frailty instrument category; preoperative assessment per D-02'
FEELS_EXHAUSTED,D2,instrument,'frailty component (Fried criteria); preoperative assessment'
WEIGHT_LOSS,D2,instrument,'frailty component (Fried criteria); preoperative assessment'
GRIP_STRENGTH,D2,instrument,'frailty component (Fried criteria); preoperative assessment'
WALK_TIME,D2,instrument,'frailty component (Fried criteria); preoperative assessment'
PHYSICAL_ACTIVITY,D2,instrument,'frailty component (Fried criteria); preoperative assessment'
ASA_CLASS,D2,analytic_role,'preoperative risk classification assigned before surgery; D2 per analytic role'
ASA,D2,analytic_role,'preoperative risk classification; D2 per analytic role'
SMOKING_STATUS,D2,timing,'preoperative habit assessment; standard preoperative variable'
SMOKING,D2,timing,'preoperative habit assessment; standard preoperative variable'
HYPERTENSION,D2,timing,'comorbidity documented in preoperative assessment; D2 by timing'
DIABETES,D2,timing,'comorbidity documented in preoperative assessment; D2 by timing'
COPD,D2,timing,'comorbidity documented in preoperative assessment; D2 by timing'
CHF,D2,timing,'comorbidity documented in preoperative assessment; D2 by timing'
CAD,D2,timing,'comorbidity documented in preoperative assessment; D2 by timing'
AFIB,D2,timing,'comorbidity documented in preoperative assessment; D2 by timing'
CKD,D2,timing,'comorbidity documented in preoperative assessment; D2 by timing'
CANCER,D2,timing,'comorbidity documented in preoperative assessment; D2 by timing'
COGNITIVE_SCORE,D3,instrument,'named cognitive instrument score (dCDT/MoCA); instrument membership overrides timing'
COGNITIVE_CATEGORY,D3,instrument,'named cognitive instrument category; instrument membership overrides timing'
CLOCK_SCORE,D3,instrument,'clock-drawing instrument score; instrument membership overrides timing'
DCDT_SCORE,D3,instrument,'dCDT instrument score; instrument membership overrides timing'
DCDT_COMMAND,D3,instrument,'dCDT command clock subscale; instrument membership overrides timing'
DCDT_COPY,D3,instrument,'dCDT copy clock subscale; instrument membership overrides timing'
PROCEDURE_NAME,D4,timing,'surgical procedure recorded at time of operation; D4 by timing'
CPT_CODE,D4,timing,'procedure CPT code assigned at time of operation; D4 by timing'
SERVICE_LINE,D4,timing,'surgical service recorded at time of operation; D4 by timing'
ANESTHESIA_TYPE,D4,timing,'anesthesia type administered intraoperatively; D4 by timing'
CASE_DURATION,D4,timing,'elapsed operative time; intraoperative variable by timing'
OPERATIVE_TIME,D4,timing,'elapsed operative time; intraoperative variable by timing'
EMERGENT,D4,timing,'emergent case flag set at time of surgery; D4 by timing'
EMERGENT_CASE,D4,timing,'emergent case flag set at time of surgery; D4 by timing'
AVG_ABP_MEAN,D4,timing,'intraoperative arterial blood pressure mean; D4 by timing'
ABP_LESS_THAN_60_COUNT,D4,timing,'count of intraoperative ABP < 60 events; D4 by timing'
BIS_INDEX_LESS_30_COUNT,D4,timing,'count of intraoperative BIS < 30 events; D4 by timing'
TOTAL_MIDAZOLAM_MG,D4,timing,'total intraoperative midazolam dose; D4 by timing'
ISO_SEV_TOTAL,D4,timing,'total volatile anesthetic exposure (isoflurane/sevoflurane); D4 by timing'
ISO_SEV_AVG,D4,timing,'average volatile anesthetic exposure; D4 by timing'
_30_DAY_MORTALITY,D5,analytic_role,'postoperative outcome realized after surgery; D5 by analytic role'
MORTALITY_30,D5,analytic_role,'30-day mortality outcome realized postoperatively; D5 by analytic role'
LOS,D5,analytic_role,'length of stay determined postoperatively; D5 by analytic role'
LENGTH_OF_STAY,D5,analytic_role,'length of stay determined postoperatively; D5 by analytic role'
READMISSION_30,D5,analytic_role,'30-day readmission outcome realized postoperatively; D5 by analytic role'
READMISSION,D5,analytic_role,'readmission outcome realized postoperatively; D5 by analytic role'
DISCHARGE_DISPOSITION,D5,analytic_role,'disposition known only at discharge; D5 by analytic role'
DISCHARGE_DISPO,D5,analytic_role,'disposition known only at discharge; D5 by analytic role'
COMPLICATIONS,D5,analytic_role,'postoperative complication status; D5 by analytic role'
ORAL_MORPHINE_EQUIV_MG_POD_DAY6,D5,analytic_role,'postoperative opioid use (POD day 6) realized after surgery; D5 by analytic role'
;
run;

/* Apply lookup to domain_staging3 */
proc sql;
  create table work.domain_staging4 as
    select ds.*,
           coalesce(dl.domain,           ds.domain)           as domain_final   length=16,
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
  /* Any remaining unassigned matched variable -> OUT_OF_SCOPE / unrecognised */
  if domain = '' then do;
    domain           = 'OUT_OF_SCOPE';
    domain_rationale = 'not in domain lookup; review needed';
    assign_rule      = 'unrecognised';
  end;
  drop domain_final rationale_final rule_final;
run;

/* Apply denominator note to D3 and frailty (D2 frailty block) variables */
data work.domain_staging4;
  set work.domain_staging4;
  length denominator_note $300;
  if domain = 'D3' then denominator_note = "&D3_DENOM_NOTE";
  else if domain = 'D2' and assign_rule = 'instrument' then
    denominator_note = "&D3_DENOM_NOTE";
  else denominator_note = '';
run;

/* ---- Write g.var_domain_map (the ONE permanent artifact of this phase) -- */
data g.var_domain_map;
  length varname $32 sas_label $256 vtype $4 n_levels 8
         stat_route $8 domain $16 domain_rationale $200
         assign_rule $20 source_dataset $32 denominator_note $300
         dict_name $60 match_how $8;
  set work.domain_staging4;
  rename sas_label = sas_label;
  keep varname sas_label vtype n_levels stat_route domain domain_rationale
       assign_rule source_dataset denominator_note dict_name match_how;
run;

/* Sort by domain then varname for human review */
proc sort data=g.var_domain_map; by domain varname; run;

%put NOTE: [17-S4] g.var_domain_map written.;


/* =========================================================================
   SECTION 4 GUARDS: Hard exit criteria
   Each in a named macro calling %fail_out.
   ========================================================================= */

/* GUARD 1: Blank rationale on any assigned (non-OUT_OF_SCOPE) variable */
proc sql noprint;
  select count(*) into :n_blank trimmed
  from g.var_domain_map
  where missing(domain_rationale) and domain ne 'OUT_OF_SCOPE';
quit;

%macro check_blank_rationale;
  %if &n_blank > 0 %then %do;
    %fail_out(msg=&n_blank variables have blank domain_rationale and are not OUT_OF_SCOPE -- Checkpoint 1 cannot proceed);
  %end;
  %put NOTE: [17-S4] Blank-rationale guard passed (n_blank=&n_blank).;
%mend check_blank_rationale;
%check_blank_rationale;


/* GUARD 2: VARnn positional name survivor */
proc sql noprint;
  select count(*) into :n_varnn_map trimmed
  from g.var_domain_map
  where prxmatch('/^VAR\d+$/', strip(varname)) > 0;
quit;

%macro check_varnn_map;
  %if &n_varnn_map > 0 %then %do;
    %fail_out(msg=&n_varnn_map VARnn positional names survived into g.var_domain_map -- dictionary match is defective);
  %end;
  %put NOTE: [17-S4] VARnn guard passed (n_varnn_map=&n_varnn_map).;
%mend check_varnn_map;
%check_varnn_map;


/* GUARD 3: Blank stat_route on any in-scope variable */
proc sql noprint;
  select count(*) into :n_blank_route trimmed
  from g.var_domain_map
  where domain not in ('OUT_OF_SCOPE')
    and stat_route not in ('MEANS','FREQ');
quit;

%macro check_blank_route;
  %if &n_blank_route > 0 %then %do;
    %fail_out(msg=&n_blank_route in-scope variables have a stat_route that is not MEANS or FREQ -- routing is incomplete);
  %end;
  %put NOTE: [17-S4] Stat-route guard passed (n_blank_route=&n_blank_route).;
%mend check_blank_route;
%check_blank_route;


/* GUARD 4: Identifier leak — any in-scope row whose name matches identifier pattern */
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
    %fail_out(msg=&n_id_leak identifier variables have a stat_route set and are not OUT_OF_SCOPE -- identifier leak into statistics);
  %end;
  %put NOTE: [17-S4] Identifier-leak guard passed (n_id_leak=&n_id_leak).;
%mend check_id_leak;
%check_id_leak;


/* ---- Export g.var_domain_map to CSV for Checkpoint 1 review ----------- */
/* Rows already sorted by domain then varname (applied above).              */
proc export data=g.var_domain_map
  outfile="&qc_path.\17_var_domain_map_review.csv"
  dbms=csv replace;
run;

%put NOTE: [17-S4] qc\17_var_domain_map_review.csv exported for Checkpoint 1 review.;


/* =========================================================================
   END OF WAVE 1 (Sections 1-4)
   -------------------------------------------------------------------------
   Checkpoint 1: Gerard reviews qc\17_var_domain_map_review.csv
   variable-by-variable. After approval:
     1. Set %let DOMAIN_MAP_APPROVED = 1; in Section 0 above.
     2. Re-run the program. %gate_stats will no longer abort.
     3. Sections 5-11 (Wave 2 statistics and Wave 3 workbook) will execute.
   ========================================================================= */

%put NOTE: ==== Phase 17 Wave 1 complete. Checkpoint 1 pending. ====;
%put NOTE: Open qc\17_var_domain_map_review.csv and review domain assignment variable-by-variable.;
%put NOTE: Set DOMAIN_MAP_APPROVED=1 in Section 0 only after approval then re-run.;

%restore_log;
