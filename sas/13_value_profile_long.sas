/*==========================================================================
  Program : 13_value_profile_long.sas
  Phase   : 13 -- Stacked value profile across datasets
  Purpose : Build ONE long dataset holding the value distribution of every
            low-cardinality variable in every dataset you name, so a single
            PROC FREQ answers questions that would otherwise take dozens of
            separate runs across separate files.

            g.value_profile_long -- one row per (dataset, variable, value):

              ds_name      which dataset the row came from
              varname      the column
              vtype        char or num
              value_txt    the value, rendered as text
              n_rows       how many rows hold it
              pct_of_ds    percent of that dataset
              n_ds_rows    that dataset's row count

  How to use it
    Frequencies are PRE-COMPUTED, so PROC FREQ needs a WEIGHT statement to
    reproduce the distribution rather than counting one row per value:

      proc freq data=g.value_profile_long;
        where varname = 'RACE';
        tables ds_name * value_txt;
        weight n_rows;
      run;

    That single call shows how Race is distributed in every dataset side by
    side -- which is the question that motivated this program, and one that
    otherwise needs a PROC FREQ per dataset and manual comparison.

    Other things it answers in one pass:
      - did a value disappear between the merged and harmonized files?
      - which variables changed distribution after the cohort restriction?
      - which variables hold a value in one dataset and not another?

  Requirements addressed
    VP-01  Every named dataset is profiled with the same rendering, so values
           are comparable across them: strip(x) for character,
           strip(put(x,best12.)) for numeric -- matching Phases 9, 10 and 11
    VP-02  A cardinality ceiling and an identifier-name test keep patient
           identifiers out of the output. This dataset holds VALUES, so that
           guard is load-bearing rather than cosmetic
    VP-03  A dataset named but absent is reported, not silently skipped
    VP-04  Nothing is read that is not named, and no source dataset is written

  Reads   : each dataset in &ds_list (read-only)
  Writes  : g.value_profile_long
            qc/13_value_profile.txt

  Author  : 2026-08-28

  PCM compliance -- each of these has bitten this pipeline:
    - No bare open-code %IF (needs a %DO block in open code)
    - No apostrophes and no embedded semicolons in %PUT text
    - Every %abort cancel inside a named macro
    - No &SQLOBS; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - Counts checked with %LENGTH before use, so a failed query fails loudly
      rather than skipping a gate while appearing to have run
    - No macro that generates SAS statements is called inside a %IF condition
    - FIRSTOBS=/OBS= for indexed reads, never POINT=
    - No data VALUE is round-tripped through a macro variable into generated
      code -- values go straight into the output table
    - dictionary.columns.TYPE is char/num, NOT the numeric 1/2 of PROC CONTENTS
==========================================================================*/

options mprint nofmterr nodate nonumber ps=max ls=200;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* ---- WHICH DATASETS TO PROFILE ------------------------------------------
   Space-delimited, in the g library. Add or remove freely; a name that does
   not exist is reported rather than silently skipped.                      */
%let ds_list = master_data_merged master_data_harmonized analytic_cohort;

/* Variables with more distinct values than this are skipped. The point is to
   compare CATEGORIES across datasets, and a column with hundreds of values
   produces noise rather than an answer -- and may be identifying.          */
%let max_levels = 50;

/* Percentage-point tolerance for calling a distribution shifted. The datasets
   have different row counts by design, so counts always differ and only the
   SHARE is comparable. 0.5 keeps rounding and tiny cells out of the report.  */
%let pct_tol = 0.5;

%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\13_value_profile.log" new;
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

%put NOTE: ==== Phase 13 Stacked Value Profile starting ====;


/* =========================================================================
   SECTION 0: Preconditions
   ========================================================================= */

%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %fail_out(msg=&label directory not found: &path);
  %end;
%mend check_dir;
%check_dir(path=&qc_path, label=qc);

%global n_ds n_ds_ok;
%let n_ds = %sysfunc(countw(&ds_list));

%macro check_ds_list;
  %if &n_ds = 0 %then %do;
    %fail_out(msg=ds_list is empty -- name at least one dataset);
  %end;
  %put NOTE: [13_vp] &n_ds datasets named.;
%mend check_ds_list;
%check_ds_list;

proc sql;
  create table work.ds_status (ds_name char(32), n_ds_rows num, status char(12));
quit;

%macro check_datasets;
  %local i d n_t n_r;
  %do i = 1 %to &n_ds;
    %let d = %scan(&ds_list, &i);
    %let n_t = ;
    proc sql noprint;
      select count(*) into :n_t trimmed from dictionary.tables
      where libname='G' and memname=%upcase("&d");
    quit;
    %if %length(&n_t) = 0 %then %do;
      %fail_out(msg=Existence query failed for &d);
    %end;
    %if &n_t ne 1 %then %do;
      proc sql; insert into work.ds_status values(%upcase("&d"), ., 'NOT FOUND'); quit;
      %put WARNING: [13_vp] g.&d not found -- skipped and recorded.;
    %end;
    %else %do;
      %let n_r = ;
      proc sql noprint;
        select count(*) into :n_r trimmed from g.&d;
      quit;
      %if %length(&n_r) = 0 %then %do;
        %fail_out(msg=Row count failed for &d);
      %end;
      proc sql;
        insert into work.ds_status values(%upcase("&d"), &n_r,
          %if &n_r = 0 %then %do; 'EMPTY' %end; %else %do; 'OK' %end;);
      quit;
      %put NOTE: [13_vp] g.&d has &n_r rows.;
    %end;
  %end;

  proc sql noprint;
    select count(*) into :n_ds_ok trimmed from work.ds_status where status='OK';
  quit;

  %if &n_ds_ok = 0 %then %do;
    %fail_out(msg=None of the named datasets exists and holds rows);
  %end;
%mend check_datasets;
%check_datasets;


/* =========================================================================
   SECTION 1: Build the stacked profile
   -------------------------------------------------------------------------
   VP-02. This dataset holds VALUES, so the identifier guard is load-bearing.
   A column is skipped when its name matches an identifier pattern OR its
   distinct count exceeds &max_levels. The first catches a low-cardinality
   identifier; the second catches a high-cardinality column whatever it is
   called. Skips are RECORDED, so a variable missing from the output is
   distinguishable from one that was never considered.
   ========================================================================= */

proc sql;
  /* value_txt is $200, not $60. Grouping happens at full length in the source
     query, so a $60 target would truncate on INSERT and two genuinely distinct
     values sharing their first 60 characters would appear as duplicate rows
     with the same text -- which looks like a data problem rather than a
     storage one. was_truncated marks any value still longer than the target. */
  create table g.value_profile_long
    (ds_name char(32), varname char(32), vtype char(4),
     value_txt char(200), n_rows num, pct_of_ds num, n_ds_rows num,
     was_truncated num);
  create table work.skipped
    (ds_name char(32), varname char(32), reason char(40), n_distinct num);
quit;

%macro profile_all;
  %local i j d nr nv v t nlv;

  %do i = 1 %to &n_ds;
    %let d = %scan(&ds_list, &i);

    /* Only datasets marked OK -- FIRSTOBS=/OBS= indexing, never POINT= */
    %local ok;
    %let ok = ;
    proc sql noprint;
      select count(*) into :ok trimmed from work.ds_status
      where ds_name = %upcase("&d") and status = 'OK';
    quit;
    %if &ok ne 1 %then %do;
      %put NOTE: [13_vp] skipping &d -- not OK in ds_status.;
    %end;
    %else %do;

      /* ORDER BY varnum on BOTH list queries. Without it SQL gives no guarantee
         that the two return rows in the same order, so a CHARACTER variable
         could be paired with the type NUM and generate put(charvar, best12.).
         Phase 12 orders its column list this way; this program did not.     */
      %let nr = ; %let nv = ; %let vlist = ; %let tlist = ;
      proc sql noprint;
        select n_ds_rows into :nr trimmed from work.ds_status where ds_name = %upcase("&d");
        select count(*) into :nv trimmed from dictionary.columns
        where libname='G' and memname=%upcase("&d");
        select upcase(name) into :vlist separated by ' ' from dictionary.columns
        where libname='G' and memname=%upcase("&d") order by varnum;
        select type into :tlist separated by ' ' from dictionary.columns
        where libname='G' and memname=%upcase("&d") order by varnum;
      quit;

      /* The two lists must be the same length as the column count, or the
         name-to-type pairing below is meaningless.                          */
      %if %length(&nr) = 0 or %length(&nv) = 0 %then %do;
        %fail_out(msg=Column metadata query failed for &d);
      %end;
      %if %sysfunc(countw(&vlist)) ne &nv or %sysfunc(countw(&tlist)) ne &nv %then %do;
        %fail_out(msg=Name and type lists for &d do not both have &nv entries);
      %end;

      %put NOTE: [13_vp] profiling &d -- &nv columns%str(,) &nr rows.;

      %do j = 1 %to &nv;
        %let v = %scan(&vlist, &j);
        %let t = %scan(&tlist, &j);

        /* Identifier by NAME -- caught before any value is read.

           NARROWED. A bare ENCOUNTER substring also matched Age_at_Encounter,
           a legitimate analytic variable with about 40 distinct values that
           belongs in this profile. ENCRYPTED already catches both
           ENCRYPTED_MRN and ENCRYPTED_ENCOUNTER, which are the actual
           identifiers.

           The CARDINALITY CEILING below is the primary guard: a true identifier
           has thousands of distinct values and is skipped by count whatever it
           is called. This name test is belt-and-braces, which is why narrowing
           it is safe.                                                        */
        %if %index(%upcase(&v), PRECEDE_STUDY_ID) > 0
         or %index(%upcase(&v), ENCRYPTED) > 0
         or %upcase(&v) = MRN
         or %index(%upcase(&v), _MRN) > 0
         or %index(%upcase(&v), MRN_) > 0 %then %do;
          proc sql;
            insert into work.skipped
            values(%upcase("&d"), "&v", 'identifier name pattern', .);
          quit;
        %end;
        %else %do;
          %let nlv = ;
          proc sql noprint;
            select count(distinct &v) into :nlv trimmed from g.&d;
          quit;
          %if %length(&nlv) = 0 %then %do;
            %fail_out(msg=Distinct count failed for &v in &d);
          %end;

          %if &nlv > &max_levels %then %do;
            proc sql;
              insert into work.skipped
              values(%upcase("&d"), "&v", 'above the cardinality ceiling', &nlv);
            quit;
          %end;
          %else %do;
            /* Values go STRAIGHT into the table. Rendering matches Phases 9,
               10 and 11 exactly, so the same value reads the same way
               everywhere and is comparable across datasets.               */
            proc sql;
              insert into g.value_profile_long
              select %upcase("&d"), "&v", "&t",
                     %if %upcase(&t) = CHAR %then %do;
                       case when missing(&v) then "(missing)" else strip(&v) end
                     %end;
                     %else %do;
                       case when missing(&v) then "(missing)"
                            else strip(put(&v, best12.)) end
                     %end;,
                     count(*), 100 * count(*) / &nr, &nr,
                     /* MAX(), so this is an AGGREGATE. Without it the expression
                        is neither aggregated nor in the GROUP BY, SAS remerges
                        summary statistics back with the original data, and the
                        insert returns ONE ROW PER DATA ROW instead of one per
                        value -- 41,150 rows for a single variable. The first
                        such insert succeeded silently and produced garbage; a
                        later one failed hard and deleted the output table.   */
                     %if %upcase(&t) = CHAR %then %do;
                       max(case when length(strip(&v)) > 200 then 1 else 0 end)
                     %end;
                     %else %do; max(0) %end;
              from g.&d
              group by
                     %if %upcase(&t) = CHAR %then %do;
                       case when missing(&v) then "(missing)" else strip(&v) end
                     %end;
                     %else %do;
                       case when missing(&v) then "(missing)"
                            else strip(put(&v, best12.)) end
                     %end;;
            quit;
          %end;
        %end;

        %if %sysfunc(mod(&j,40)) = 0 %then
          %put NOTE: [13_vp] &d -- &j of &nv columns.;
      %end;
    %end;
  %end;
%mend profile_all;
%profile_all;

proc sort data=g.value_profile_long; by varname ds_name descending n_rows; run;

proc sql noprint;
  select count(*)                into :n_out    trimmed from g.value_profile_long;
  select count(distinct varname) into :n_vars   trimmed from g.value_profile_long;
  select count(*)                into :n_skip   trimmed from work.skipped;
  select count(distinct varname) into :n_skipv  trimmed from work.skipped;
quit;

%macro check_output;
  %if %length(&n_out) = 0 %then %do;
    %fail_out(msg=Output count query returned no value);
  %end;
  %else %if &n_out = 0 %then %do;
    %fail_out(msg=g.value_profile_long is empty -- nothing was profiled);
  %end;
  %put NOTE: [13_vp] &n_out value rows across &n_vars variables.;
  %put NOTE: [13_vp] &n_skip column-dataset pairs skipped (&n_skipv distinct variables).;
%mend check_output;
%check_output;


/* =========================================================================
   SECTION 2: Variables whose distribution CHANGED between datasets
   -------------------------------------------------------------------------
   The reason for stacking in the first place. A value present in one dataset
   and absent from another is exactly what you want to see after a merge, a
   harmonisation or a cohort restriction -- and it is invisible when the
   profiles live in separate files.
   ========================================================================= */

/* Which datasets actually carry each variable? A variable absent from a dataset
   entirely is a different matter from a VALUE absent within it, and conflating
   the two produces noise.                                                    */
proc sql;
  create table work.var_in_ds as
  select distinct varname, ds_name from g.value_profile_long;

  create table work.var_ds_count as
  select varname, count(distinct ds_name) as n_ds_with_var
  from work.var_in_ds group by varname;

  /* Every (variable, value, dataset) combination that SHOULD exist: each value
     seen for a variable, crossed with every dataset carrying that variable. */
  create table work.expected as
  select distinct v.varname, v.value_txt, d.ds_name
  from (select distinct varname, value_txt from g.value_profile_long) as v
  inner join work.var_in_ds as d on d.varname = v.varname;

  /* VALUE ABSENT: expected but not observed. This is the question the program
     claims to answer -- "did a value disappear between two datasets" -- and the
     earlier version could not answer it. That version reported a value only
     when it appeared in exactly ONE dataset, so a value present in two of three
     and missing from the third went unreported, which is precisely the case
     that matters after a cohort restriction.                                */
  create table g.value_profile_absent as
  select e.varname, e.value_txt, e.ds_name as absent_from
  from work.expected as e
  where not exists (select 1 from g.value_profile_long as o
                    where o.varname = e.varname
                      and o.value_txt = e.value_txt
                      and o.ds_name = e.ds_name)
  order by varname, value_txt, absent_from;

  /* DISTRIBUTION SHIFT. Compared on PERCENT, not count. The datasets have
     different row counts by design -- 41,150 merged against 13,890 admitted --
     so a count comparison flags essentially every value and tells you nothing.
     Both counts and percents are kept in the output; only the FILTER changed. */
  create table g.value_profile_delta as
  select a.varname, a.value_txt,
         a.ds_name as ds_a, a.n_rows as n_a, a.pct_of_ds as pct_a,
         b.ds_name as ds_b, b.n_rows as n_b, b.pct_of_ds as pct_b,
         abs(a.pct_of_ds - b.pct_of_ds) as pct_shift
  from g.value_profile_long as a
  inner join g.value_profile_long as b
    on a.varname = b.varname and a.value_txt = b.value_txt
   and a.ds_name < b.ds_name
  where abs(a.pct_of_ds - b.pct_of_ds) > &pct_tol
  order by pct_shift desc, varname, value_txt;

  select count(*) into :n_delta  trimmed from g.value_profile_delta;
  select count(*) into :n_absent trimmed from g.value_profile_absent;
quit;

%put NOTE: [13_vp] &n_delta value shares differ by more than &pct_tol percentage points.;
%put NOTE: [13_vp] &n_absent value-dataset combinations are absent where the variable exists.;


/* =========================================================================
   SECTION 3: QC artifact
   ========================================================================= */

data _null_;
  file "&qc_path.\13_value_profile.txt";
  put "13_value_profile_long -- Run: %sysfunc(datetime(), datetime20.)";
  put "=======================================================================";
  put " ";
  put "datasets_named=&n_ds";
  put "datasets_profiled=&n_ds_ok";
  put "value_rows=&n_out";
  put "variables_profiled=&n_vars";
  put "skipped_column_dataset_pairs=&n_skip";
  put "distinct_variables_skipped=&n_skipv";
  put "cardinality_ceiling=&max_levels";
  put "distribution_shifts_over_&pct_tol._points=&n_delta";
  put "absent_value_dataset_combinations=&n_absent";
  put " ";
  put "HOW TO USE g.value_profile_long";
  put "  Frequencies are PRE-COMPUTED, so PROC FREQ needs a WEIGHT statement:";
  put " ";
  put "    proc freq data=g.value_profile_long;";
  put "      where varname = 'RACE';";
  put "      tables ds_name * value_txt;";
  put "      weight n_rows;";
  put "    run;";
  put " ";
  put "  Without WEIGHT, PROC FREQ counts one row per VALUE rather than per";
  put "  patient, and every cell reads 1.";
  put " ";
  put "COMPANION TABLES";
  put "  g.value_profile_delta  -- values whose SHARE differs by more than";
  put "                            &pct_tol percentage points between two datasets.";
  put "                            Compared on percent, not count: the datasets have";
  put "                            different row counts by design, so a count";
  put "                            comparison flags nearly everything.";
  put "  g.value_profile_absent -- a value seen for a variable in one dataset and";
  put "                            NOT present in another that carries that same";
  put "                            variable. This is the did-it-disappear question.";
  put " ";
  put "SKIPPED COLUMNS";
  put "  Identifier-named columns are skipped before any value is read, and any";
  put "  column above the cardinality ceiling is skipped by count. This dataset";
  put "  holds VALUES, so that guard is load-bearing rather than cosmetic. Every";
  put "  skip is recorded in work.skipped with its reason, so a variable absent";
  put "  from the output is distinguishable from one never considered.";
run;

%put NOTE: ==== Phase 13 complete ====;
%put NOTE- Output: g.value_profile_long (&n_out rows);
%put NOTE- Also  : g.value_profile_delta%str(,) g.value_profile_absent;
%put NOTE- Report: qc/13_value_profile.txt;

%restore_log;
