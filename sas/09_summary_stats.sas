/*==========================================================================
  Program : 09_summary_stats.sas
  Phase   : 9 -- Per-Variable Summary Statistics
  Purpose : One row per variable in g.&src_ds, with type-appropriate
            summary statistics, written to docs/&xl_name.

            Numeric : N, NMiss, coverage%, N distinct, Min, P25, Median, Mean,
                      P75, Max, StdDev
            Character: N, NMiss, coverage%, N distinct, and the min/max
                      OBSERVED TRIMMED length of the value

            No mode / most-common value is reported. An earlier draft of this
            header promised one; it was never implemented, and for an
            identifier-like column the modal VALUE is exactly what SUM-04
            forbids writing. Distinct counts carry the information safely.

  Requirements addressed
    SUM-01  Every variable in the merged file gets exactly one summary row
    SUM-02  N distinct is reported for EVERY variable -- this is the statistic
            that makes ID-like columns interpretable (see SUM-04)
    SUM-03  Numeric and character variables get type-appropriate statistics;
            PROC MEANS is never asked to process a character variable
    SUM-04  No identifying VALUE is written to the workbook. Counts always;
            example values only for low-cardinality non-identifier columns
    SUM-05  PRECEDE_STUDY_ID distinct count is asserted equal to the row count,
            re-confirming PCM-F-01 at the merged level

  Reads   : g.&src_ds  (read-only -- never written)
  Writes  : docs/&xl_name
            qc/&qc_name   (grep-able key=value summary)

  Author  : 2026-08-27

  PCM compliance -- every one of these has bitten this pipeline before:
    - No bare open-code %IF. In OPEN CODE, %IF/%THEN needs a %DO block, so every
      gate here lives inside a named macro. ("Expected %DO not found" once made
      99_run_all.sas execute nothing at all.)
    - No apostrophes and no embedded semicolons in %PUT text. A %PUT ends at its
      first semicolon; an apostrophe opens a string that never closes and
      silently swallows every statement that follows.
    - Every %abort cancel is inside a named macro (PCM-R-05).
    - No &SQLOBS anywhere -- explicit SELECT COUNT(*) INTO :macvar TRIMMED.
    - %GLOBAL declared for any macro variable read outside its setting macro.
    - IS NOT MISSING is PROC SQL / WHERE syntax. In a DATA step IF it is a
      syntax error; the DATA-step form is NOT MISSING(x). This has bitten this
      pipeline three times.
    - PROC MEANS cannot process character variables -- VAR _CHARACTER_ is an
      error, not a no-op.
    - g.&src_ds never appears on the left of a DATA statement.
==========================================================================*/

options mprint nofmterr nodate nonumber ps=max ls=200;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* ---- WHICH DATASET TO SUMMARISE ----------------------------------------
   master_data_merged     -- the Phase 4 output: 176 columns, every original
                             source column, before concept harmonisation.
   master_data_harmonized -- the Phase 10 output: adds the h_ columns and their
                             h_*_src provenance companions, and omits the eleven
                             aliases proven redundant. This is the working file.

   Run it BOTH ways. The two workbooks together show what harmonisation changed:
   which columns disappeared, which appeared, and how coverage moved. Each run
   writes its own workbook, so neither overwrites the other.               */
%let src_ds  = master_data_harmonized;

/* Output names derive from the dataset, so the two runs cannot collide. */
%macro set_outputs;
  %global xl_name qc_name ds_label;
  %if %upcase(&src_ds) = MASTER_DATA_HARMONIZED %then %do;
    %let xl_name  = SUMMARY_STATS_HARMONIZED.xlsx;
    %let qc_name  = 09_summary_stats_harmonized.txt;
    %let ds_label = g.master_data_harmonized (Phase 10 output);
  %end;
  %else %do;
    %let xl_name  = SUMMARY_STATS_MERGED.xlsx;
    %let qc_name  = 09_summary_stats_merged.txt;
    %let ds_label = g.&src_ds (Phase 4 output);
  %end;
%mend set_outputs;
%set_outputs;

/* Log routing. Standalone: own file. Under 99_run_all: leave the master log
   alone, or the driver log gets a hole exactly where a failure needs reading. */
%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\09_summary_stats.log" new;
    run;
  %end;
  %else %do;
    %put NOTE: [09_summary] running under 99_run_all -- log stays in the master log.;
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
  ods excel close;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;

%route_log;

libname g "&g_path";

%put NOTE: ==== Phase 9 Summary Statistics starting ====;


/* =========================================================================
   SECTION 0: Preconditions
   ========================================================================= */

%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %fail_out(msg=&label directory not found: &path);
  %end;
  %put NOTE: [09_summary] &label directory found.;
%mend check_dir;
%check_dir(path=&docs_path, label=docs);
%check_dir(path=&qc_path,   label=qc);

proc sql noprint;
  select count(*) into :n_tab trimmed
  from dictionary.tables
  where libname='G' and memname=%upcase("&src_ds");
quit;

%macro check_source;
  %if &n_tab ne 1 %then %do;
    %fail_out(msg=g.&src_ds not found -- run Phase 4 first);
  %end;
%mend check_source;
%check_source;

proc sql noprint;
  select count(*) into :n_rows trimmed from g.&src_ds;
quit;

%macro check_rows;
  %if %superq(n_rows) = %then %do;
    %fail_out(msg=Row count query returned no value);
  %end;
  %if &n_rows = 0 %then %do;
    %fail_out(msg=g.&src_ds is empty);
  %end;
  %put NOTE: [09_summary] g.&src_ds has &n_rows rows.;
%mend check_rows;
%check_rows;


/* =========================================================================
   SECTION 1: Variable inventory from dictionary.columns
   -------------------------------------------------------------------------
   NOTE: dictionary.columns.TYPE is CHARACTER with values char and num. This is
   the OPPOSITE convention from PROC CONTENTS OUT=, where type is numeric
   1=NUM / 2=CHAR. Both appear in this pipeline; comparing the dictionary form
   against 2 silently never matches.
   ========================================================================= */

proc sql noprint;
  create table work.varlist as
  select upcase(name)  as varname length=32,
         type          as vtype   length=4,
         length        as vlength,
         label         as vlabel  length=256,
         varnum
  from dictionary.columns
  where libname='G' and memname=%upcase("&src_ds")
  order by varnum;

  select count(*) into :n_vars trimmed from work.varlist;
  select count(*) into :n_num  trimmed from work.varlist where vtype = 'num';
  select count(*) into :n_chr  trimmed from work.varlist where vtype = 'char';
quit;

%put NOTE: [09_summary] &n_vars variables -- &n_num numeric, &n_chr character.;


/* =========================================================================
   SECTION 2: Distinct counts for EVERY variable -- one pass
   -------------------------------------------------------------------------
   PROC FREQ NLEVELS computes the number of distinct levels for every variable
   in a single pass. That is far cheaper than one COUNT(DISTINCT) query per
   variable, which would be 173 full scans of a 41,150-row table on a network
   drive.

   NOPRINT suppresses the individual frequency tables -- without it this would
   print a table for every variable, including one with 41,150 rows for
   ENCRYPTED_MRN. The NLevels table is still produced and captured by ODS.

   If this step runs out of memory on a future, wider dataset, the fallback is
   to split TABLES _ALL_ into numeric and character passes.
   ========================================================================= */

ods listing close;
ods output nlevels=work.nlev;

proc freq data=g.&src_ds nlevels;
  tables _all_ / noprint;
run;

ods output close;
ods listing;

proc sql noprint;
  select count(*)                  into :n_nlev  trimmed from work.nlev;
  select count(distinct TableVar)  into :n_nlevu trimmed from work.nlev;

  /* Does this SAS release emit NNonMissLevels? NLevels COUNTS THE MISSING LEVEL
     when one is present, which would contradict the KEY sheet definition
     (distinct values, missing excluded). Prefer NNonMissLevels when available. */
  select count(*) into :has_nonmiss trimmed
  from dictionary.columns
  where libname='WORK' and upcase(memname)='NLEV'
    and upcase(name)='NNONMISSLEVELS';
quit;

%macro check_nlev;
  %if &n_nlev = 0 %then %do;
    %fail_out(msg=PROC FREQ NLEVELS produced no rows -- cannot report distinct counts);
  %end;
  /* SUM-02 needs one row per variable, not merely some rows. A partial NLEVELS
     result would otherwise surface only as a warning much later.             */
  %if &n_nlev ne &n_vars %then %do;
    %fail_out(msg=NLEVELS returned &n_nlev rows for &n_vars variables);
  %end;
  %if &n_nlevu ne &n_nlev %then %do;
    %fail_out(msg=NLEVELS has duplicate TableVar rows -- &n_nlevu distinct of &n_nlev);
  %end;
  %put NOTE: [09_summary] NLEVELS captured for &n_nlev variables, one row each.;
%mend check_nlev;
%check_nlev;

%macro build_distinct;
  data work.distinct;
    set work.nlev;
    length varname $32;
    varname = upcase(TableVar);
  %if &has_nonmiss = 1 %then %do;
    /* Non-missing levels reported directly -- exactly the KEY definition. */
    n_distinct       = NNonMissLevels;
    distinct_is_exact = 1;
  %end;
  %else %do;
    /* NNonMissLevels not emitted by this release. Carry the raw level count and
       correct it in SECTION 5 against N Missing, which is computed there from
       COUNT()/NMISS and is reliable.                                         */
    n_distinct       = NLevels;
    distinct_is_exact = 0;
  %end;
    keep varname n_distinct distinct_is_exact;
  run;

  %local src;
  %if &has_nonmiss = 1 %then %let src = NNonMissLevels (exact);
  %else %let src = NLevels (corrected in SECTION 5 using N Missing);
  %put NOTE: [09_summary] distinct counts taken from &src.;
%mend build_distinct;
%build_distinct;


/* =========================================================================
   SECTION 3: Numeric statistics
   -------------------------------------------------------------------------
   STACKODSOUTPUT gives one row per variable rather than one wide row for the
   whole dataset, which is what we need to join back to the variable list.
   VAR _NUMERIC_ only -- PROC MEANS REJECTS character variables outright.
   ========================================================================= */

%macro numeric_stats;
  %if &n_num = 0 %then %do;
    /* Defensive: build an empty shell so the SECTION 5 join still works */
    data work.numstats;
      length varname $32;
      call missing(varname);
      n_val=.; nmiss_val=.; min_val=.; p25_val=.; med_val=.;
      mean_val=.; p75_val=.; max_val=.; std_val=.;
      delete;
    run;
    %put NOTE: [09_summary] no numeric variables -- numeric stats skipped.;
  %end;
  %else %do;
    ods listing close;
    ods output summary=work.numraw;
    proc means data=g.&src_ds
               n nmiss min p25 median mean p75 max std
               stackodsoutput;
      var _numeric_;
    run;
    ods output close;
    ods listing;

    data work.numstats;
      set work.numraw;
      length varname $32;
      varname   = upcase(Variable);
      n_val     = N;
      nmiss_val = NMiss;
      min_val   = Min;
      p25_val   = P25;
      med_val   = Median;
      mean_val  = Mean;
      p75_val   = P75;
      max_val   = Max;
      std_val   = StdDev;
      keep varname n_val nmiss_val min_val p25_val med_val mean_val p75_val max_val std_val;
    run;
  %end;
%mend numeric_stats;
%numeric_stats;


/* =========================================================================
   SECTION 4: Character statistics
   -------------------------------------------------------------------------
   PROC MEANS cannot help here. N and NMiss come from COUNT(var), which counts
   non-missing values and treats an all-blank character string as missing --
   so one expression is correct for both types.

   The min and max OBSERVED TRIMMED LENGTH are reported instead of min/max
   VALUE. These are the lengths of the values actually stored in each row, NOT
   the declared column width -- that is reported separately as Length. A length is
   never identifying, whereas the minimum value of ENCRYPTED_MRN is a patient
   identifier. See SECTION 5 for the value-suppression rule.
   ========================================================================= */

proc sql;
  create table work.chrstats
    (varname char(32), n_val num, nmiss_val num, minlen num, maxlen num);
quit;

%macro char_stats;
  %local i v n nm mn mx chrlist;
  %if &n_chr = 0 %then %do;
    %put NOTE: [09_summary] no character variables.;
    %return;
  %end;

  proc sql noprint;
    select varname into :chrlist separated by ' '
    from work.varlist where vtype = 'char';
  quit;

  %do i = 1 %to &n_chr;
    %let v = %scan(&chrlist, &i);
    proc sql noprint;
      /* coalesce(...,.) so an entirely-missing column still yields a usable
         value for the INSERT rather than an empty macro variable.          */
      select count(&v),
             sum(missing(&v)),
             coalesce(min(ifn(missing(&v), ., length(strip(&v)))), .),
             coalesce(max(ifn(missing(&v), ., length(strip(&v)))), .)
        into :n trimmed, :nm trimmed, :mn trimmed, :mx trimmed
      from g.&src_ds;

      insert into work.chrstats values("&v", &n, &nm, &mn, &mx);
    quit;
  %end;
  %put NOTE: [09_summary] character statistics computed for &n_chr variables.;
%mend char_stats;
%char_stats;


/* =========================================================================
   SECTION 5: Assemble, and apply the value-suppression rule
   -------------------------------------------------------------------------
   SUM-04. This workbook is a shareable artifact. Counts are never identifying;
   VALUES can be. A variable is treated as identifier-like when either:

     (a) its name matches a known identifier pattern, or
     (b) its distinct count exceeds half the row count -- near-unique columns
         are identifying in practice whatever they are named

   For those, distinct counts and coverage are reported and example values are
   suppressed. This is why N distinct is the statistic that matters for ID
   columns: it tells you the column is unique, or is not, without exposing it.
   ========================================================================= */

proc sql;
  create table work.summary as
  select v.varnum,
         v.varname,
         v.vtype,
         v.vlength,
         v.vlabel,
         coalesce(d.n_distinct, .)                as n_distinct,
         coalesce(d.distinct_is_exact, 0)         as distinct_is_exact,
         coalesce(n.n_val,  c.n_val)              as n_nonmiss,
         coalesce(n.nmiss_val, c.nmiss_val)       as n_missing,
         n.min_val, n.p25_val, n.med_val, n.mean_val, n.p75_val, n.max_val, n.std_val,
         c.minlen, c.maxlen
  from work.varlist as v
  left join work.distinct as d on d.varname = v.varname
  left join work.numstats as n on n.varname = v.varname
  left join work.chrstats as c on c.varname = v.varname
  order by v.varnum;
quit;

data work.summary_final;
  set work.summary;
  /* $60, not $40. The cardinality reason string is 41 characters and was being
     silently truncated to "...row coun".                                      */
  length coverage_pct 8 id_like 3 id_reason $60;

  /* DATA step, so the guard is NOT MISSING(x). IS NOT MISSING is PROC SQL /
     WHERE syntax and is a syntax error here.                                */
  if not missing(n_nonmiss) and &n_rows > 0
    then coverage_pct = 100 * n_nonmiss / &n_rows;

  /* ---- STEP 1: correct n_distinct BEFORE anything reads it ----
     ORDER MATTERS. The cardinality test below compares n_distinct against half
     the row count, so it must see the corrected value. An earlier draft
     classified first and corrected after: a phantom missing level could push a
     variable just over the 50% threshold, falsely marking it identifier-like and
     suppressing statistics that were safe to publish.

     When NNonMissLevels is unavailable, NLevels counts the missing value as one
     additional level. Subtract it whenever any missing value exists. N Missing is
     the reliable signal here -- it is computed above from COUNT()/NMISS. A
     previous draft corrected only when n_distinct > n_nonmiss, which fires only
     for near-unique columns: 5 distinct values with some missing gives NLevels=6
     against n_nonmiss=100, and 6 > 100 is false, so the phantom level survived. */
  if distinct_is_exact = 0 and not missing(n_distinct)
     and not missing(n_missing) and n_missing > 0
     then n_distinct = n_distinct - 1;

  /* Sanity floor: a distinct count can never exceed the non-missing row count. */
  if not missing(n_distinct) and not missing(n_nonmiss) and n_distinct > n_nonmiss
     then n_distinct = n_nonmiss;

  /* ---- STEP 2: classify, using the corrected n_distinct ---- */

  /* (a) name-based */
  id_like = 0;
  id_reason = "";
  if index(upcase(varname),'PRECEDE_STUDY_ID') > 0
     or index(upcase(varname),'ENCRYPTED')     > 0
     or index(upcase(varname),'MRN')           > 0
     or index(upcase(varname),'ENCOUNTER')     > 0
     then do;
       id_like = 1;
       id_reason = "name matches identifier pattern";
     end;

  /* (b) cardinality-based -- near-unique is identifying whatever it is called */
  if id_like = 0 and not missing(n_distinct)
     and n_distinct > 0.5 * &n_rows then do;
       id_like = 1;
       id_reason = "distinct count exceeds half the row count";
  end;

  /* ---- SUM-04 ENFORCEMENT ----
     Flagging a variable identifier-like is not enough; the VALUES must actually
     be withheld. An earlier draft flagged them and then printed Min, Max, Mean,
     P25, Median, P75 and StdDev for numerics on the Numeric sheet -- the exact
     thing SUM-04 forbids. Min and Max are single real observed values; for a
     near-unique numeric column they identify a patient as surely as the column
     itself. Counts and coverage are retained, since those are never
     identifying.                                                             */
  if id_like = 1 then do;
    call missing(min_val, p25_val, med_val, mean_val, p75_val, max_val, std_val);
    call missing(minlen, maxlen);
  end;

  label varnum       = "Order"
        varname      = "Variable"
        vtype        = "Type"
        vlength      = "Length"
        vlabel       = "Label"
        n_distinct   = "N Distinct"
        n_nonmiss    = "N Non-Missing"
        n_missing    = "N Missing"
        coverage_pct = "Coverage %"
        min_val      = "Min"
        p25_val      = "P25"
        med_val      = "Median"
        mean_val     = "Mean"
        p75_val      = "P75"
        max_val      = "Max"
        std_val      = "Std Dev"
        minlen       = "Min Observed Length"
        maxlen       = "Max Observed Length"
        id_like      = "Identifier-like"
        id_reason    = "Identifier reason";
run;

proc sql noprint;
  select count(*) into :n_summary trimmed from work.summary_final;
  select count(*) into :n_idlike  trimmed from work.summary_final where id_like = 1;
  select count(*) into :n_nodist  trimmed from work.summary_final where n_distinct is missing;
quit;

%macro check_summary;
  %if &n_summary ne &n_vars %then %do;
    %fail_out(msg=Summary has &n_summary rows but the merged file has &n_vars variables);
  %end;
  /* SUM-02 says EVERY variable gets a distinct count. A warning here would let
     the workbook ship while violating a stated requirement.                  */
  %if &n_nodist > 0 %then %do;
    %fail_out(msg=SUM-02 VIOLATION -- &n_nodist variables have no distinct count. Check the NLEVELS join.);
  %end;
  %put NOTE: [09_summary] SUM-01 OK -- &n_summary rows, one per variable.;
  %put NOTE: [09_summary] SUM-04 -- &n_idlike variables flagged identifier-like, values suppressed.;
%mend check_summary;
%check_summary;


/* =========================================================================
   SECTION 6: SUM-05 -- the key must still be unique in the merged file
   ========================================================================= */

proc sql noprint;
  select n_distinct into :n_key_distinct trimmed
  from work.summary_final where varname = 'PRECEDE_STUDY_ID';
quit;

%macro assert_key_unique;
  %if %superq(n_key_distinct) = %then %do;
    %fail_out(msg=PRECEDE_STUDY_ID not found in the summary -- cannot verify uniqueness);
  %end;
  %if &n_key_distinct ne &n_rows %then %do;
    %fail_out(msg=PRECEDE_STUDY_ID has &n_key_distinct distinct values in &n_rows rows -- key is not unique);
  %end;
  %put NOTE: [09_summary] SUM-05 OK -- PRECEDE_STUDY_ID has &n_key_distinct distinct values in &n_rows rows.;
%mend assert_key_unique;
%assert_key_unique;


/* =========================================================================
   SECTION 7: Excel workbook
   -------------------------------------------------------------------------
   KEY sheet is written FIRST so it lands leftmost in the workbook.
   ========================================================================= */

/* Delete any previous workbook BEFORE opening ODS. Otherwise the FILEEXIST
   check at the end of this section passes on a stale file from an earlier run
   even if this run failed to write anything.

   A FILENAME STATEMENT is used rather than %sysfunc(filename(...)). The
   function form is ambiguous about whether its first argument names the fileref
   or receives a generated one, and an earlier draft assigned fileref FREF while
   checking _OLDXL -- so the stale file was never actually deleted. The
   statement form has no such question.                                       */
%macro drop_stale_xlsx;
  %local rc;
  %if %sysfunc(fileexist(%bquote(&docs_path.\&xl_name))) %then %do;
    filename _oldxl "&docs_path.\&xl_name";
    %let rc = %sysfunc(fdelete(_oldxl));
    filename _oldxl clear;
    %if &rc ne 0 %then %do;
      %fail_out(msg=Could not delete the previous &xl_name -- rc=&rc. It may be open in Excel.);
    %end;
    %put NOTE: [09_summary] previous &xl_name removed.;
  %end;
  %else %do;
    %put NOTE: [09_summary] no previous &xl_name to remove.;
  %end;
%mend drop_stale_xlsx;
%drop_stale_xlsx;

ods excel file="&docs_path.\&xl_name"
    options(sheet_name="KEY"
            embedded_titles="yes"
            autofilter="all"
            frozen_headers="1");

title justify=left color=CX0021A5 height=14pt "PeCAN Merged Dataset -- Summary Statistics";
title2 justify=left height=10pt "g.&src_ds, &n_rows rows, &n_vars variables. Generated %sysfunc(datetime(), datetime20.)";

data work.key;
  length Item $40 Meaning $220;
  Item="Source";              Meaning="&ds_label -- &n_rows rows, &n_vars variables"; output;
  Item="Which workbook";      Meaning="This file is &xl_name. Run 09 with src_ds set the other way to produce the companion, and compare the two to see exactly what concept harmonisation changed."; output;
  Item="N Distinct";          Meaning="Number of distinct values, missing excluded. For a key this equals the row count"; output;
  Item="N Non-Missing";       Meaning="Rows with a value. Blank character strings count as missing"; output;
  Item="Coverage %";          Meaning="N Non-Missing divided by &n_rows, times 100"; output;
  Item="Min / Max / Median";  Meaning="Numeric variables only. PROC MEANS cannot process character variables"; output;
  Item="Min/Max Observed Length"; Meaning="Character variables only -- length of the trimmed VALUE actually stored in each row. This is NOT the column Length, which is the declared storage width"; output;
  Item="Identifier-like";     Meaning="1 = name matches an identifier pattern, or distinct count exceeds half the row count"; output;
  Item="Distinct count basis"; Meaning="Taken from PROC FREQ NLEVELS. Where the release reports NNonMissLevels it is used directly; otherwise NLevels is corrected by subtracting the missing level whenever N Missing is greater than zero"; output;
  Item="Value suppression";   Meaning="For identifier-like variables the distribution statistics (Min, P25, Median, Mean, P75, Max, StdDev, observed lengths) are BLANKED. Counts and coverage are retained -- counts are never identifying, values can be"; output;
  Item="Numeric sheet";       Meaning="One row per numeric variable, with distribution statistics"; output;
  Item="Character sheet";     Meaning="One row per character variable, with distinct counts, the declared column Length, and the min/max OBSERVED trimmed length of the values"; output;
  Item="All Variables sheet"; Meaning="Every variable in merged-file column order"; output;
run;

proc print data=work.key noobs label;
  var Item Meaning;
run;

ods excel options(sheet_name="All Variables");
proc print data=work.summary_final noobs label;
  var varnum varname vtype vlength n_distinct n_nonmiss n_missing coverage_pct id_like vlabel;
  format coverage_pct 6.1 n_distinct n_nonmiss n_missing comma12.;
run;

ods excel options(sheet_name="Numeric");
proc print data=work.summary_final noobs label;
  where vtype = 'num';
  var varname n_distinct n_nonmiss n_missing coverage_pct
      min_val p25_val med_val mean_val p75_val max_val std_val vlabel;
  format coverage_pct 6.1
         n_distinct n_nonmiss n_missing comma12.
         min_val p25_val med_val mean_val p75_val max_val std_val best12.;
run;

ods excel options(sheet_name="Character");
proc print data=work.summary_final noobs label;
  where vtype = 'char';
  var varname vlength n_distinct n_nonmiss n_missing coverage_pct
      minlen maxlen id_like id_reason vlabel;
  format coverage_pct 6.1 n_distinct n_nonmiss n_missing comma12.
         vlength minlen maxlen 8.;
run;

ods excel close;
title;

%macro check_xlsx;
  %if %sysfunc(fileexist(&docs_path.\&xl_name)) = 0 %then %do;
    %fail_out(msg=&xl_name was not written to &docs_path);
  %end;
  %put NOTE: [09_summary] SUM-01 OK -- workbook written.;
%mend check_xlsx;
%check_xlsx;


/* =========================================================================
   SECTION 8: Grep-able QC artifact
   ========================================================================= */

data _null_;
  file "&qc_path.\&qc_name";
  put "09_summary_stats -- Run: %sysfunc(datetime(), datetime20.)";
  put "=======================================================================";
  put " ";
  put "merged_rows=&n_rows";
  put "n_variables=&n_vars";
  put "n_numeric=&n_num";
  put "n_character=&n_chr";
  put "n_summary_rows=&n_summary";
  put "n_identifier_like=&n_idlike";
  put "n_missing_distinct_count=&n_nodist";
  put "precede_study_id_distinct=&n_key_distinct";
  put " ";
  put "SUM-05: PRECEDE_STUDY_ID distinct equals the row count, so the key is";
  put "  still unique in the merged file. This re-confirms PCM-F-01 downstream";
  put "  of the merge rather than only at source.";
  put " ";
  put "SUM-04 value suppression: no example VALUES are written for variables";
  put "  flagged identifier-like. Distinct counts and coverage are reported for";
  put "  every variable, which is what makes an ID column interpretable without";
  put "  exposing it.";
run;

%put NOTE: ==== Phase 9 complete ====;
%put NOTE- Workbook: docs/&xl_name;
%put NOTE- Summary : qc/&qc_name;

%restore_log;
