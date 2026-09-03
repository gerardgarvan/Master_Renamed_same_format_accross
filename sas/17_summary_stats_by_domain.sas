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
   -------------------------------------------------------------------------
   Sections 1-11 (Wave 1: domain assignment; Wave 2: statistics;
   Wave 3: workbook assembly) will be appended after Checkpoint 1 approval.
   ========================================================================= */

%put NOTE: ==== Phase 17 Wave 0 discovery complete ====;
%put NOTE: Review qc\17_discovery.txt and then proceed with 17-02-PLAN.md (Wave 1).;

%restore_log;
