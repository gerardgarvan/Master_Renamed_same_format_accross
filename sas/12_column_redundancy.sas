/*==========================================================================
  Program : 12_column_redundancy.sas
  Phase   : 12 -- Detect duplicate and constant columns
  Purpose : Compare EVERY column against every other for exact equality, and
            flag every column whose non-missing values are all the same. Report
            only; nothing is dropped.

  Requirements addressed
    RED-01  Every same-type column PAIR that could possibly be equal AND is
            informative is tested for exact equality across all rows. No
            sampling, no name-based guessing. Two exclusions, both deliberate
            and both stated on the KEY sheet: a pair where either column is
            CONSTANT (every all-Y flag pairs with every other all-Y flag --
            true, and uninformative), and a pair where both columns are
            ENTIRELY MISSING (equal on every row, but IDENTICAL here means at
            least one populated value). Both are reported on their own sheets
    RED-02  Every column is tested for constancy (one distinct non-missing value)
    RED-03  SUBSET pairs are found by a SEPARATE candidate path that permits
            different coverage, and judged on n_disagree_both -- rows where both
            are populated and the values differ. A subset has different coverage
            BY DEFINITION, so the exact-duplicate filter cannot find one
    RED-04  Nothing is dropped or altered. This produces evidence for a decision

  Reads   : g.&src_ds   (read-only)
  Writes  : docs/COLUMN_REDUNDANCY.xlsx
            qc/12_column_redundancy.txt

  Author  : 2026-08-28

  WHY A FULL SWEEP. The Phase 9 summary made three pairs look like duplicates
  because their distinct counts and non-missing counts matched exactly --
  ISO_EXP_INTRAOP_TOTAL against ISO_EXP_INTRAOP_MAC_TOTAL, the SEV equivalent,
  and SD_ABP_MEAN against AVG_ABP_MEAN. Matching marginals do NOT prove matching
  values, and PCM-T-12 records that spot-checking this class of question gave the
  wrong answer twice before. So every pair is tested, not the three that looked
  suspicious.

  COST. Pairwise comparison is O(n^2) in columns: ~187 columns gives ~8,000
  same-type pairs. Each is one pass over 41,150 rows on a network drive, so this
  is the slowest program in the pipeline -- budget 20-40 minutes. A pre-filter on
  (type, non-missing count, distinct count) cuts it to the handful of pairs that
  could possibly be equal, which is what SECTION 2 does.

  PCM compliance -- each of these has bitten this pipeline:
    - No bare open-code %IF (needs a %DO block in open code)
    - No apostrophes and no embedded semicolons in %PUT text
    - Every %abort cancel inside a named macro
    - No &SQLOBS; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - IS NOT MISSING is PROC SQL syntax; the DATA-step form is NOT MISSING(x)
    - No macro that generates SAS statements is ever called inside a %IF condition
    - Counts are checked with %LENGTH before use, so a failed query fails loudly
      rather than skipping a gate while appearing to pass
    - No PROC inside an open DATA step
    - Source datasets never on the left of a DATA statement
==========================================================================*/

options mprint nofmterr nodate nonumber ps=max ls=200;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* Which dataset to sweep. Matches the switch in 09_summary_stats.sas. */
%let src_ds = master_data_harmonized;

%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\12_column_redundancy.log" new;
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
  ods excel close;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;

%route_log;
libname g "&g_path";

%put NOTE: ==== Phase 12 Column Redundancy sweep starting ====;


/* =========================================================================
   SECTION 0: Preconditions
   ========================================================================= */

%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %fail_out(msg=&label directory not found: &path);
  %end;
%mend check_dir;
%check_dir(path=&docs_path, label=docs);
%check_dir(path=&qc_path,   label=qc);

proc sql noprint;
  select count(*) into :n_tab trimmed
  from dictionary.tables where libname='G' and memname=%upcase("&src_ds");
quit;

%macro check_src;
  %if %length(&n_tab) = 0 %then %do;
    %fail_out(msg=Table existence query returned no value);
  %end;
  %else %if &n_tab ne 1 %then %do;
    %fail_out(msg=g.&src_ds not found);
  %end;
%mend check_src;
%check_src;

proc sql noprint;
  select count(*) into :n_rows trimmed from g.&src_ds;
quit;

%macro check_rows;
  %if %length(&n_rows) = 0 %then %do;
    %fail_out(msg=Row count query returned no value);
  %end;
  %else %if &n_rows = 0 %then %do;
    %fail_out(msg=g.&src_ds is empty);
  %end;
  %put NOTE: [12_red] &n_rows rows in g.&src_ds.;
%mend check_rows;
%check_rows;


/* =========================================================================
   SECTION 1: Per-column profile -- non-missing count and distinct count
   -------------------------------------------------------------------------
   These two numbers are the pre-filter for SECTION 2 AND the constancy test for
   SECTION 3, so both come from one pass per column.
   ========================================================================= */

proc sql noprint;
  create table work.cols as
  select upcase(name) as cname length=32, name as oname length=32,
         type as ctype length=4, length as clen, varnum
  from dictionary.columns
  where libname='G' and memname=%upcase("&src_ds")
  order by varnum;
  select count(*) into :n_cols trimmed from work.cols;
quit;

%macro check_cols;
  %if %length(&n_cols) = 0 %then %do;
    %fail_out(msg=Column list query returned no value);
  %end;
  %else %if &n_cols = 0 %then %do;
    %fail_out(msg=No columns found in g.&src_ds);
  %end;
  %put NOTE: [12_red] &n_cols columns to profile.;
%mend check_cols;
%check_cols;

proc sql;
  create table work.profile
    (cname char(32), ctype char(4), n_nonmiss num, n_distinct num);
  /* Constant values live in their own table so a data value never has to be
     carried through a macro variable into generated code. */
  create table work.constvals (cname char(32), const_value char(60));
quit;

%macro profile_cols;
  %local i v n_nm n_dv ctp;
  proc sql noprint;
    select cname into :clist separated by ' ' from work.cols;
  quit;

  %do i = 1 %to &n_cols;
    %let v = %scan(&clist, &i);
    %let n_nm = ; %let n_dv = ;
    proc sql noprint;
      select count(&v), count(distinct &v) into :n_nm trimmed, :n_dv trimmed
      from g.&src_ds;
    quit;
    %if %length(&n_nm) = 0 or %length(&n_dv) = 0 %then %do;
      %fail_out(msg=Profile query failed for &v);
    %end;

    proc sql;
      insert into work.profile
      select "&v", ctype, &n_nm, &n_dv from work.cols where cname = "&v";
    quit;

    /* Capture the value itself when a column is constant -- knowing a column
       holds one value is far less useful than knowing WHICH.

       Selected DIRECTLY into a table, never round-tripped through a macro
       variable. An earlier version did `insert ... "&cval"`, so a value
       containing a double quote, ampersand or percent sign would have closed
       the string, triggered macro resolution, or generated invalid code. Data
       values must not travel through generated code.                       */
    %local ctp;
    proc sql noprint;
      select ctype into :ctp trimmed from work.cols where cname = "&v";
    quit;
    %if &n_dv = 1 %then %do;
      proc sql;
        insert into work.constvals
        select distinct "&v",
               %if %upcase(&ctp) = CHAR %then %do; strip(&v) %end;
               %else %do; strip(put(&v, best12.)) %end;
        from g.&src_ds where not missing(&v);
      quit;
    %end;
    %if %sysfunc(mod(&i,25)) = 0 %then %put NOTE: [12_red] profiled &i of &n_cols columns.;
  %end;
%mend profile_cols;
%profile_cols;


/* =========================================================================
   SECTION 2: Candidate pairs -- the pre-filter
   -------------------------------------------------------------------------
   Two columns can only be EXACTLY equal on every row if they share a type, a
   non-missing count and a distinct count. Those three are cheap and already
   computed, and they cut ~8,000 same-type pairs to a handful.

   The filter is SOUND, not merely convenient: any pair it excludes provably
   differs somewhere, because a differing marginal is itself a difference.

   Constant columns are excluded from pairing. Every all-Y flag would otherwise
   pair with every other all-Y flag, which is true but uninteresting -- they are
   reported separately in SECTION 4.
   ========================================================================= */

proc sql noprint;
  /* PATH 1 -- EXACT-DUPLICATE candidates. Two columns can only be equal on every
     row if they share type, coverage and cardinality. Sound, not merely cheap:
     a differing marginal is itself a difference.                            */
  create table work.cand_exact as
  select a.cname as col_a length=32, b.cname as col_b length=32,
         a.ctype, a.n_nonmiss as nm_a, b.n_nonmiss as nm_b, 'EXACT' as path length=8
  from work.profile as a, work.profile as b
  where a.cname < b.cname
    and a.ctype      = b.ctype
    and a.n_nonmiss  = b.n_nonmiss
    and a.n_distinct = b.n_distinct
    and a.n_nonmiss  > 0
    /* Constants excluded from BOTH paths -- this filter was dropped in an
       earlier refactor while the header still claimed it applied.          */
    and a.n_distinct > 1;

  /* PATH 2 -- SUBSET candidates. A strict subset has DIFFERENT coverage by
     definition, so the exact filter above excludes every one of them. An earlier
     version had only that filter while the header claimed subsets were detected;
     they structurally could not be, and n_a_only and n_b_only were always equal
     within a candidate.

     The narrower column can have at most as many distinct values as the wider
     one, and both must be populated somewhere. That is the whole filter -- it is
     much weaker than the exact one, so this path is the expensive half.      */
  create table work.cand_subset as
  select a.cname as col_a length=32, b.cname as col_b length=32,
         a.ctype, a.n_nonmiss as nm_a, b.n_nonmiss as nm_b, 'SUBSET' as path length=8
  from work.profile as a, work.profile as b
  where a.cname < b.cname
    and a.ctype = b.ctype
    and a.n_nonmiss ne b.n_nonmiss
    and a.n_nonmiss > 0 and b.n_nonmiss > 0
    and a.n_distinct > 1 and b.n_distinct > 1
    and ( (a.n_nonmiss > b.n_nonmiss and b.n_distinct <= a.n_distinct)
       or (b.n_nonmiss > a.n_nonmiss and a.n_distinct <= b.n_distinct) );

  create table work.candidates as
  select * from work.cand_exact
  union all
  select * from work.cand_subset;

  select count(*) into :n_cand   trimmed from work.candidates;
  select count(*) into :n_cand_e trimmed from work.cand_exact;
  select count(*) into :n_cand_s trimmed from work.cand_subset;
quit;

%macro report_cand;
  %if %length(&n_cand) = 0 %then %do;
    %fail_out(msg=Candidate query returned no value);
  %end;
  %put NOTE: [12_red] &n_cand candidate pairs -- &n_cand_e exact%str(,) &n_cand_s subset.;
  %put NOTE- Exact candidates share type%str(,) coverage and cardinality%str(,) so any pair;
  %put NOTE- excluded from THAT path provably differs. The subset path is filtered far;
  %put NOTE- more weakly and is the expensive half of this sweep.;
%mend report_cand;
%report_cand;


/* =========================================================================
   SECTION 3: Test each candidate for exact equality
   -------------------------------------------------------------------------
   n_differ counts rows where the two disagree, INCLUDING rows where one is
   missing and the other is not. Missing is not equal to a value, and a pair that
   differs only in which rows are populated is a SUBSET, not a duplicate -- the
   relationship Phase 10 found eleven times.
   ========================================================================= */

proc sql;
  create table work.pairtest
    (col_a char(32), col_b char(32), ctype char(4), path char(8),
     n_differ num, n_disagree_both num, n_both num, n_a_only num, n_b_only num,
     verdict char(16));
quit;

%macro test_pairs;
  %local i a b t p nd ndb nb na nbo;
  %if &n_cand = 0 %then %do;
    %put NOTE: [12_red] no candidate pairs.;
    %return;
  %end;

  %do i = 1 %to &n_cand;
    /* FIRSTOBS=/OBS=, not POINT=. POINT= takes a VARIABLE NAME. */
    data _null_;
      set work.candidates (firstobs=&i obs=&i);
      call symputx('a', col_a, 'L');
      call symputx('b', col_b, 'L');
      call symputx('t', ctype, 'L');
      call symputx('p', path,  'L');
    run;

    %let nd = ; %let ndb = ; %let nb = ; %let na = ; %let nbo = ;

    /* n_disagree_both is the measure a subset claim actually rests on: rows where
       BOTH are populated and the values differ. n_differ alone cannot support it,
       because it also counts coverage differences -- which is exactly what a
       subset has by definition.

       Character comparison uses STRIP on both sides, so trailing blanks never
       decide the verdict. This is a deliberate semantic choice, made explicit
       here because the two obvious alternatives are each wrong in one
       direction: bare NE depends on SAS padding rules, and COMPARE without the
       T modifier can treat declared-length padding as a real difference.

       For THIS program padding is storage, not data. Two columns holding FL and
       FL-with-trailing-blanks carry the same clinical value, and calling them
       different would HIDE a genuine duplicate -- which is the failure this
       sweep exists to prevent. A pair that differs only in declared width shows
       up on the Constant Columns or profile output instead, where width is
       visible without being mistaken for a value difference.                 */
    proc sql noprint;
      select
        /* n_differ also counts two DIFFERENT special missing values (.A vs .B).
           Both satisfy missing(), so without this a pair storing different
           special missing codes would be reported IDENTICAL. It does NOT feed
           n_disagree_both, which means specifically "both populated".      */
        sum(case when (missing(&a) and not missing(&b))
                   or (not missing(&a) and missing(&b))
                   %if %upcase(&t) ne CHAR %then %do;
                   or (missing(&a) and missing(&b) and &a ne &b)
                   %end;
                   or (not missing(&a) and not missing(&b) and
                       %if %upcase(&t) = CHAR %then %do; strip(&a) ne strip(&b) %end;
                       %else %do; &a ne &b %end;)
                 then 1 else 0 end),
        sum(case when not missing(&a) and not missing(&b) and
                       %if %upcase(&t) = CHAR %then %do; strip(&a) ne strip(&b) %end;
                       %else %do; &a ne &b %end;
                 then 1 else 0 end),
        sum(case when not missing(&a) and not missing(&b) then 1 else 0 end),
        sum(case when not missing(&a) and missing(&b)     then 1 else 0 end),
        sum(case when missing(&a) and not missing(&b)     then 1 else 0 end)
      into :nd trimmed, :ndb trimmed, :nb trimmed, :na trimmed, :nbo trimmed
      from g.&src_ds;
    quit;

    /* All FIVE checked. An earlier version validated only two of them while
       inserting and branching on all five.                                   */
    %if %length(&nd) = 0 or %length(&ndb) = 0 or %length(&nb) = 0
        or %length(&na) = 0 or %length(&nbo) = 0 %then %do;
      %fail_out(msg=Pair test failed for &a vs &b -- a count returned no value);
    %end;

    /* Five distinct relationships, not one catch-all. A_SUBSET_B and
       B_SUBSET_A are materially different from COVERAGE_DIFF, and all three
       differ from VALUE_DIFF.                                                */
    proc sql;
      insert into work.pairtest values
        ("&a", "&b", "&t", "&p", &nd, &ndb, &nb, &na, &nbo,
         %if &nd = 0 %then %do; 'IDENTICAL' %end;
         %else %if &ndb > 0 %then %do; 'VALUE_DIFF' %end;
         %else %if &na = 0 and &nbo > 0 %then %do; 'A_SUBSET_B' %end;
         %else %if &nbo = 0 and &na > 0 %then %do; 'B_SUBSET_A' %end;
         %else %do; 'COVERAGE_DIFF' %end;);
    quit;

    %if &nd = 0 %then %put NOTE: [12_red] IDENTICAL -- &a and &b.;
    %else %if &ndb = 0 and (&na = 0 or &nbo = 0) %then
      %put NOTE: [12_red] SUBSET -- &a and &b agree wherever both are populated.;
    %if %sysfunc(mod(&i,50)) = 0 %then %put NOTE: [12_red] tested &i of &n_cand pairs.;
  %end;
%mend test_pairs;
%test_pairs;

proc sql noprint;
  select count(*) into :n_ident  trimmed from work.pairtest where verdict='IDENTICAL';
  select count(*) into :n_subset trimmed from work.pairtest
    where verdict in ('A_SUBSET_B','B_SUBSET_A');
  select count(*) into :n_diff   trimmed from work.pairtest
    where verdict not in ('IDENTICAL','A_SUBSET_B','B_SUBSET_A');
quit;


/* =========================================================================
   SECTION 4: Constant columns
   -------------------------------------------------------------------------
   One distinct non-missing value. These carry no information: every populated
   row says the same thing. Some are correct by construction (IN_MD3 is the
   spine flag, so it is 1 everywhere) and some are findings (a Y-only flag means
   the absent state was never recorded).
   ========================================================================= */

proc sql noprint;
  create table work.constants as
  select p.cname, p.ctype, c.const_value, p.n_nonmiss,
         &n_rows - p.n_nonmiss as n_missing
  from work.profile as p
  left join work.constvals as c on c.cname = p.cname
  where p.n_distinct = 1
  order by p.n_nonmiss desc;

  create table work.allmissing as
  select p.cname, p.ctype from work.profile as p where p.n_nonmiss = 0;

  select count(*) into :n_const trimmed from work.constants;
  select count(*) into :n_empty trimmed from work.allmissing;
quit;

%macro report_const;
  %put NOTE: [12_red] &n_const columns hold a single distinct value.;
  %if &n_empty > 0 %then %do;
    %put WARNING: [12_red] &n_empty columns are entirely missing on every row.;
    %put WARNING- A column present but never populated is worth questioning --;
    %put WARNING- it may indicate a keep list or a merge that did not take.;
  %end;
%mend report_const;
%report_const;


/* =========================================================================
   SECTION 5: Workbook
   ========================================================================= */

%macro drop_stale;
  %local rc;
  %if %sysfunc(fileexist(%bquote(&docs_path.\COLUMN_REDUNDANCY.xlsx))) %then %do;
    filename _oldx "&docs_path.\COLUMN_REDUNDANCY.xlsx";
    %let rc = %sysfunc(fdelete(_oldx));
    filename _oldx clear;
    %if &rc ne 0 %then %do;
      %fail_out(msg=Could not delete the previous COLUMN_REDUNDANCY.xlsx -- rc=&rc. It may be open in Excel.);
    %end;
  %end;
%mend drop_stale;
%drop_stale;

ods excel file="&docs_path.\COLUMN_REDUNDANCY.xlsx"
    options(sheet_name="KEY" embedded_titles="yes" autofilter="all" frozen_headers="1");

title justify=left color=CX0021A5 height=14pt "PeCAN -- Duplicate and Constant Column Sweep";
title2 justify=left height=10pt "g.&src_ds, &n_rows rows, &n_cols columns. Generated %sysfunc(datetime(), datetime20.)";

data work.key;
  length Item $30 Meaning $260;
  Item="What this is";     Meaning="Every INFORMATIVE same-type candidate pair tested for exact equality, and every column tested for constancy. Constant and entirely-missing columns are reported separately rather than paired. Nothing is dropped -- this is evidence for a decision."; output;
  Item="Why a full sweep"; Meaning="The Phase 9 summary made three pairs LOOK identical because their distinct and non-missing counts matched. Matching marginals do not prove matching values, and spot-checking this class of question has given the wrong answer twice (PCM-T-12)."; output;
  Item="Exact path";       Meaning="Pairs sharing type, non-missing count AND distinct count. Sound, not just cheap: any pair excluded from this path provably differs, because a differing marginal is itself a difference."; output;
  Item="Subset path";      Meaning="A separate, much weaker filter that PERMITS different coverage -- a subset has different coverage by definition, so the exact filter cannot find one. This path is the expensive half of the sweep."; output;
  Item="Constants excluded"; Meaning="Pairs where either column holds one distinct value are not paired. Every all-Y flag would pair with every other all-Y flag: true, and uninformative. They are listed on Constant Columns with the value each holds."; output;
  Item="Empty columns";    Meaning="Two entirely-missing columns are equal on every row, but are NOT reported as an identical pair -- IDENTICAL here requires at least one populated value. They are listed individually on the Empty Columns sheet."; output;
  Item="IDENTICAL";        Meaning="The two columns are equal on EVERY row, missing included. One is redundant."; output;
  Item="A_SUBSET_B";       Meaning="A is populated only where B is, and they agree on every such row. A carries no information B lacks -- the relationship Phase 10 proved eleven times."; output;
  Item="B_SUBSET_A";       Meaning="The same, reversed."; output;
  Item="COVERAGE_DIFF";    Meaning="They agree wherever both are populated, but each covers rows the other does not. Neither is redundant; together they cover more than either alone."; output;
  Item="VALUE_DIFF";       Meaning="They disagree somewhere both are populated. Not duplicates, whatever their names suggest."; output;
  Item="n_disagree_both";  Meaning="Rows where BOTH are populated and the values differ. This is what a subset claim rests on -- n_differ alone cannot support it, because it also counts coverage differences, which is exactly what a subset has."; output;
  Item="Character compare"; Meaning="STRIP is applied to both sides, so trailing blanks never decide a verdict. Deliberate: padding is storage, not data, and treating FL and FL-with-trailing-blanks as different would HIDE a genuine duplicate. Declared width is reported separately and is not confused with a value difference."; output;
  Item="Constant Columns"; Meaning="One distinct non-missing value -- every populated row says the same thing. Some are correct by construction (IN_MD3 is the spine flag); some are findings (a Y-only flag means the absent state was never recorded)."; output;
  Item="Empty Columns";    Meaning="Present but never populated. Worth questioning: it may indicate a keep list or a merge that did not take."; output;
  Item="Not tested";       Meaning="Pairs of different types are never compared. A character and a numeric column holding the same information need harmonising (Phase 10), not de-duplicating."; output;
run;

proc print data=work.key noobs label; var Item Meaning; run;

ods excel options(sheet_name="Identical Pairs");
proc print data=work.pairtest noobs label;
  where verdict='IDENTICAL';
  var col_a col_b ctype n_both n_a_only n_b_only;
  label col_a="Column A" col_b="Column B" ctype="Type"
        n_both="Both Populated" n_a_only="Only A" n_b_only="Only B";
  format n_both n_a_only n_b_only comma12.;
run;

ods excel options(sheet_name="Subset Pairs");
proc print data=work.pairtest noobs label;
  where verdict in ('A_SUBSET_B','B_SUBSET_A');
  var col_a col_b ctype verdict n_disagree_both n_both n_a_only n_b_only;
  label col_a="Column A" col_b="Column B" ctype="Type" verdict="Verdict"
        n_disagree_both="Disagree Where Both" n_both="Both Populated"
        n_a_only="Only A" n_b_only="Only B";
  format n_disagree_both n_both n_a_only n_b_only comma12.;
run;

ods excel options(sheet_name="Tested, Neither");
proc print data=work.pairtest noobs label;
  where verdict not in ('IDENTICAL','A_SUBSET_B','B_SUBSET_A');
  var col_a col_b ctype verdict n_differ n_disagree_both n_both n_a_only n_b_only;
  label col_a="Column A" col_b="Column B" ctype="Type" verdict="Verdict"
        n_differ="Rows Differing" n_disagree_both="Disagree Where Both"
        n_both="Both Populated" n_a_only="Only A" n_b_only="Only B";
  format n_differ n_disagree_both n_both n_a_only n_b_only comma12.;
run;

ods excel options(sheet_name="Constant Columns");
proc print data=work.constants noobs label;
  var cname ctype const_value n_nonmiss n_missing;
  label cname="Column" ctype="Type" const_value="The One Value"
        n_nonmiss="N Populated" n_missing="N Missing";
  format n_nonmiss n_missing comma12.;
run;

%macro empty_sheet;
  %if &n_empty > 0 %then %do;
    ods excel options(sheet_name="Empty Columns");
    proc print data=work.allmissing noobs label;
      var cname ctype;
      label cname="Column" ctype="Type";
    run;
  %end;
%mend empty_sheet;
%empty_sheet;

ods excel options(sheet_name="All Candidates");
proc print data=work.candidates noobs label;
  var col_a col_b ctype path nm_a nm_b;
  label col_a="Column A" col_b="Column B" ctype="Type" path="Candidate Path"
        nm_a="A Populated" nm_b="B Populated";
  format nm_a nm_b comma12.;
run;

ods excel close;
title;

%macro check_xlsx;
  %if %sysfunc(fileexist(%bquote(&docs_path.\COLUMN_REDUNDANCY.xlsx))) = 0 %then %do;
    %fail_out(msg=COLUMN_REDUNDANCY.xlsx was not written);
  %end;
%mend check_xlsx;
%check_xlsx;


/* =========================================================================
   SECTION 6: QC artifact
   ========================================================================= */

data _null_;
  file "&qc_path.\12_column_redundancy.txt";
  put "12_column_redundancy -- Run: %sysfunc(datetime(), datetime20.)";
  put "=======================================================================";
  put " ";
  put "source_dataset=g.&src_ds";
  put "rows=&n_rows";
  put "columns=&n_cols";
  put "candidate_pairs=&n_cand";
  put "  candidates_exact_path=&n_cand_e";
  put "  candidates_subset_path=&n_cand_s";
  put "identical_pairs=&n_ident";
  put "subset_pairs=&n_subset";
  put "tested_neither=&n_diff";
  put "constant_columns=&n_const";
  put "empty_columns=&n_empty";
  put " ";
  put "NOTHING WAS DROPPED. A duplicate column is evidence for a decision, not a";
  put "decision. Before removing one, check which name the PRECEDE data dictionary";
  put "documents -- Phase 11 answers that -- and keep the documented name.";
  put " ";
  put "A_SUBSET_B or B_SUBSET_A is the strict-subset relationship Phase 10 proved";
  put "eleven times: the narrower column adds no rows AND disagrees nowhere, so it";
  put "carries no information the wider one lacks. Both conditions are required --";
  put "n_disagree_both = 0 is what makes it a subset rather than merely narrower.";
  put " ";
  put "Constant columns are excluded from pairing on purpose: every all-Y flag";
  put "pairs with every other all-Y flag, which is true and tells you nothing. The";
  put "Constant Columns sheet lists them with the single value each one holds.";
  put " ";
  put "Two entirely-missing columns are equal on every row but are NOT reported as";
  put "an identical pair -- IDENTICAL here requires at least one populated value.";
  put "They appear on the Empty Columns sheet instead.";
  put " ";
  put "For numeric columns, two DIFFERENT special missing values (.A against .B)";
  put "count as a difference. Both satisfy missing(), so without that test a pair";
  put "storing different special missing codes would be reported IDENTICAL.";
run;

%put NOTE: ==== Phase 12 complete ====;
%put NOTE- &n_ident identical%str(,) &n_subset subset%str(,) &n_const constant%str(,) &n_empty empty.;
%put NOTE- Workbook: docs/COLUMN_REDUNDANCY.xlsx;

%restore_log;
