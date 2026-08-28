/*==========================================================================
  Program : 10_concept_profile.sas
  Phase   : 10 -- Concept Harmonization, Part 1 of 2 (EVIDENCE)
  Purpose : For every group of columns SUSPECTED of measuring the same thing,
            show what the values actually are and how they line up. Produces the
            evidence a human needs to decide whether they really are the same,
            plus a pre-populated decision template to fill in.

            THIS PROGRAM DECIDES NOTHING AND CHANGES NOTHING. It only reads
            g.master_data_merged and writes two artifacts.

  Requirements addressed
    CON-01  Every suspected duplicate-concept group is profiled: per-column value
            frequencies, and the pairwise cross-tabulation that reveals the mapping
    CON-02  Agreement is never computed before a mapping is known. A cross-tab is
            shown; a percentage that presumes Y=1 is not
    CON-03  A decision template is written with one row per observed source value,
            for a human to complete. 10b reads it back and applies nothing else
    CON-04  Overlap counts are reported per group -- two columns that never
            co-occur cannot be compared at all, and that is a finding

  Reads   : g.master_data_merged   (read-only, never written)
  Writes  : docs/CONCEPT_EVIDENCE.xlsx
            docs/concept_decisions_TEMPLATE.csv
            qc/10_concept_profile.txt

  Author  : 2026-08-27

  WHY THIS IS SPLIT IN TWO. A program cannot decide that Death_Date_Y_N and
  IsDead_Y_N measure the same thing -- that is a judgement about what a hospital
  recorded, and PCM-D-01/D-02/D-03 were deliberately left as keep-separate because
  nobody had checked. What a program CAN do is show the values side by side and
  then apply, mechanically, whatever a human concludes. 10b does the applying.

  PCM compliance -- each of these has bitten this pipeline:
    - No bare open-code %IF (needs a %DO block in open code); every gate is in a macro
    - No apostrophes and no embedded semicolons in %PUT text
    - Every %abort cancel inside a named macro
    - No &SQLOBS; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - %GLOBAL for anything read outside its setting macro
    - IS NOT MISSING is PROC SQL syntax; the DATA-step form is NOT MISSING(x)
    - dictionary.columns.TYPE is char/num; PROC CONTENTS OUT= type is 1/2
    - g.master_data_merged never on the left of a DATA statement
==========================================================================*/

options mprint nofmterr nodate nonumber ps=max ls=200;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\10_concept_profile.log" new;
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

%put NOTE: ==== Phase 10 Concept Profiling starting ====;


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
  from dictionary.tables where libname='G' and memname='MASTER_DATA_MERGED';
quit;

%macro check_src;
  %if &n_tab ne 1 %then %do;
    %fail_out(msg=g.master_data_merged not found -- run Phase 4 first);
  %end;
%mend check_src;
%check_src;

proc sql noprint;
  select count(*) into :n_rows trimmed from g.master_data_merged;
quit;

%macro check_rows;
  /* Branch sequentially. `%if %superq(x) = or &x = 0` looks safe but is not:
     %EVAL evaluates the WHOLE expression, so when x is empty the second operand
     resolves to `= 0` and the macro aborts with "a character operand was found
     in the %EVAL function". %LENGTH first, then the numeric test.            */
  %if %length(&n_rows) = 0 %then %do;
    %fail_out(msg=Row count query returned no value -- g.master_data_merged unreadable);
  %end;
  %else %if &n_rows = 0 %then %do;
    %fail_out(msg=g.master_data_merged is empty);
  %end;
  %put NOTE: [10_profile] &n_rows rows in g.master_data_merged.;
%mend check_rows;
%check_rows;


/* =========================================================================
   SECTION 1: The concept groups
   -------------------------------------------------------------------------
   Each row names one column and the CONCEPT it is suspected of measuring. Every
   group is a HYPOTHESIS drawn from the rectification register, not an
   established fact -- that is exactly what this program tests.

   To add a group later, add rows here. Nothing else needs changing.

   NOT INCLUDED, deliberately:
     ISO_SEV_MAC_TOTAL_Exp -- says TOTAL where the others say AVERAGE. A
       different statistic, not a naming variant. Folding it in would be wrong
       even if the other two ISO_SEV columns turn out identical.
     _30_DAY_MORTALITY, Death_Days_After_Surgery -- time-bounded and interval
       measures, never candidates for the death flag.
   ========================================================================= */

data work.concepts;
  length concept $32 varname $32 note $80;
  infile datalines dsd dlm='|' truncover;
  input concept $ varname $ note $;
  datalines;
DEATH_FLAG|Death_Date_Y_N|md1-md5 naming
DEATH_FLAG|IsDead_Y_N|md6 naming
DEATH_FLAG|Death|md7 naming
SLEEP_APNEA|Sleep_Apnea|md4/md5 naming
SLEEP_APNEA|Sleep_Apnea_YN|md3 naming
DIABETES|Diabetes|md4/md5 naming
DIABETES|Diabetes_YN|md3 naming
HYPERLIPIDEMIA|Hyperlipidemia|md4/md5 naming
HYPERLIPIDEMIA|Hyperlipidemia_YN|md3 naming
HYPERTENSION|Hypertension|md4/md5 naming
HYPERTENSION|Hypertension_YN|md3 naming
MOVEMENT_DISORDER|MovementDisorder|md4/md5 naming
MOVEMENT_DISORDER|MovementDisorder_YN|md3 naming
COGNITIVE_DISORDER|Cognitive_Disorder|md4/md5 naming
COGNITIVE_DISORDER|CognitiveDisorder_YN|md3 naming
ISO_SEV_AVERAGE|ISO_SEV_Exp_IntraOp_MAC_Average|md1-md3 naming
ISO_SEV_AVERAGE|ISO_SEV_IntraOp_MAC_Average|md4 naming
FRAILTY_EXHAUST|Feels_Exausted|char Y/N form
FRAILTY_EXHAUST|Feels_Exausted_Value|numeric form
FRAILTY_ACTIVITY|Low_Physical_Activity|char Y/N form
FRAILTY_ACTIVITY|Low_Physical_Activity_Value|numeric form
FRAILTY_WALKING|Slow_Walking_Speed|char Y/N form
FRAILTY_WALKING|Slow_Walking_Speed_Value|numeric form
FRAILTY_WEIGHT|Unintended_Weight_Loss|char Y/N form
FRAILTY_WEIGHT|Unintended_Weight_Loss_Value|numeric form
FRAILTY_GRIP|Week_Grip_Strength|char Y/N form
FRAILTY_GRIP|Week_Grip_Strength_Value|numeric form
COGNITIVE_GRAIN|Cognitive_Score|0-3 score
COGNITIVE_GRAIN|Cognitive_Category|label form
FRAILTY_GRAIN|Frailty_Score|0-5 score
FRAILTY_GRAIN|Frailty_Category|label form
;
run;

/* Keep only columns that actually exist in the merged file. A named column that
   is absent is itself worth reporting -- it means the register is out of date. */
proc sql noprint;
  create table work.concept_vars as
  select c.concept, c.varname, c.note,
         d.type as vtype length=4,
         d.length as vlength
  from work.concepts as c
  left join (select upcase(name) as nm, type, length
             from dictionary.columns
             where libname='G' and memname='MASTER_DATA_MERGED') as d
    on upcase(c.varname) = d.nm
  order by concept, varname;

  create table work.concept_missing as
  select * from work.concept_vars where vtype is null;

  select count(*) into :n_absent trimmed from work.concept_missing;
  select count(*) into :n_present trimmed from work.concept_vars where vtype is not null;
quit;

%macro report_absent;
  %if &n_absent > 0 %then %do;
    %put WARNING: [10_profile] &n_absent named columns are NOT in the merged file.;
    %put WARNING- They are listed on the Missing Columns sheet. The register may be stale.;
  %end;
  %put NOTE: [10_profile] &n_present of the named columns are present and will be profiled.;
%mend report_absent;
%report_absent;


/* =========================================================================
   SECTION 2: Value inventory -- what values does each column actually hold?
   -------------------------------------------------------------------------
   This is the step that answers "Y/N or 1/0 or YES/NO", which nobody has
   checked. Character and numeric are handled separately because PROC MEANS
   cannot process character variables and PROC FREQ output differs by type.

   Values ARE written here. That is safe: these are clinical codes on
   low-cardinality columns, not identifiers. A guard below refuses to profile
   any column with more than 50 distinct values, which would indicate the
   register named something identifier-like by mistake.
   ========================================================================= */

proc sql;
  create table work.valinv
    (concept char(32), varname char(32), vtype char(4),
     value_txt char(60), n_rows num, pct num);
quit;

%macro value_inventory;
  %local i v c t n_lv;
  proc sql noprint;
    select count(*) into :n_v trimmed from work.concept_vars where vtype is not null;
    select varname into :vlist separated by ' ' from work.concept_vars where vtype is not null;
    select concept into :clist separated by ' ' from work.concept_vars where vtype is not null;
    select vtype   into :tlist separated by ' ' from work.concept_vars where vtype is not null;
  quit;

  %do i = 1 %to &n_v;
    %let v = %scan(&vlist, &i);
    %let c = %scan(&clist, &i);
    %let t = %scan(&tlist, &i);

    /* Cardinality guard -- refuse to list values for anything near-unique */
    proc sql noprint;
      select count(distinct &v) into :n_lv trimmed from g.master_data_merged;
    quit;

    %if &n_lv > 50 %then %do;
      proc sql;
        insert into work.valinv
          values("&c", "&v", "&t", "(&n_lv distinct values -- not listed)", ., .);
      quit;
      %put WARNING: [10_profile] &v has &n_lv distinct values. Values not listed.;
      %put WARNING- A concept group should hold low-cardinality codes. Check the register.;
    %end;
    %else %do;
      proc sql;
        insert into work.valinv
        select "&c", "&v", "&t",
               %if %upcase(&t) = CHAR %then %do;
                 case when missing(&v) then "(missing)" else strip(&v) end
               %end;
               %else %do;
                 case when missing(&v) then "(missing)" else strip(put(&v, best12.)) end
               %end;
               , count(*), 100 * count(*) / &n_rows
        from g.master_data_merged
        group by
               %if %upcase(&t) = CHAR %then %do;
                 case when missing(&v) then "(missing)" else strip(&v) end
               %end;
               %else %do;
                 case when missing(&v) then "(missing)" else strip(put(&v, best12.)) end
               %end;
               ;
      quit;
    %end;
  %end;
%mend value_inventory;
%value_inventory;

proc sort data=work.valinv; by concept varname descending n_rows; run;


/* =========================================================================
   SECTION 3: Pairwise cross-tabulation -- the actual evidence
   -------------------------------------------------------------------------
   CON-02. A percentage agreement cannot be computed before the value mapping is
   known: asserting Y=1 in order to measure whether Y=1 is circular. The cross-tab
   shows every observed combination and its count, and a human reads the mapping
   off it.

   CON-04. n_both is reported per pair. Two columns that NEVER co-occur cannot be
   compared at all -- for a merged file built on md3-owns ownership that is a
   real possibility, and it is a finding rather than a null result.
   ========================================================================= */

proc sql;
  create table work.xtab
    (concept char(32), var_a char(32), var_b char(32),
     val_a char(60), val_b char(60), n_rows num);
  create table work.pairsum
    (concept char(32), var_a char(32), var_b char(32),
     n_both num, n_a_only num, n_b_only num, n_neither num, n_combos num);
quit;

%macro crosstabs;
  %local ci nc cn vi vj na nb ta tb;
  proc sql noprint;
    select count(distinct concept) into :nc trimmed
    from work.concept_vars where vtype is not null;
    select distinct concept into :conlist separated by ' '
    from work.concept_vars where vtype is not null;
  quit;

  %do ci = 1 %to &nc;
    %let cn = %scan(&conlist, &ci);
    %local nvar;
    proc sql noprint;
      select count(*) into :nvar trimmed
      from work.concept_vars where concept = "&cn" and vtype is not null;
      select varname into :cv separated by ' '
      from work.concept_vars where concept = "&cn" and vtype is not null;
      select vtype into :ct separated by ' '
      from work.concept_vars where concept = "&cn" and vtype is not null;
    quit;

    %do vi = 1 %to %eval(&nvar - 1);
      %do vj = %eval(&vi + 1) %to &nvar;
        %let na = %scan(&cv, &vi);  %let ta = %scan(&ct, &vi);
        %let nb = %scan(&cv, &vj);  %let tb = %scan(&ct, &vj);

        proc sql;
          insert into work.xtab
          select "&cn", "&na", "&nb",
                 %if %upcase(&ta) = CHAR %then %do; case when missing(&na) then "(missing)" else strip(&na) end %end;
                 %else %do; case when missing(&na) then "(missing)" else strip(put(&na, best12.)) end %end;,
                 %if %upcase(&tb) = CHAR %then %do; case when missing(&nb) then "(missing)" else strip(&nb) end %end;
                 %else %do; case when missing(&nb) then "(missing)" else strip(put(&nb, best12.)) end %end;,
                 count(*)
          from g.master_data_merged
          group by
                 %if %upcase(&ta) = CHAR %then %do; case when missing(&na) then "(missing)" else strip(&na) end %end;
                 %else %do; case when missing(&na) then "(missing)" else strip(put(&na, best12.)) end %end;,
                 %if %upcase(&tb) = CHAR %then %do; case when missing(&nb) then "(missing)" else strip(&nb) end %end;
                 %else %do; case when missing(&nb) then "(missing)" else strip(put(&nb, best12.)) end %end;
                 ;

        quit;

        /* n_combos comes from work.xtab, which the query above has just filled
           with one row per observed combination for this pair. Counting those
           rows is exact, and avoids both a second full scan of the merged file
           and a scalar subquery in the SELECT list -- which PROC SQL does not
           reliably support. An earlier version used CATX here, which drops blank
           arguments and so collapsed (missing, Y) and (Y, missing) into one.  */
        %local n_cb;
        proc sql noprint;
          select count(*) into :n_cb trimmed
          from work.xtab
          where concept = "&cn" and var_a = "&na" and var_b = "&nb";

          insert into work.pairsum
          select "&cn", "&na", "&nb",
                 sum(&na is not missing and &nb is not missing),
                 sum(&na is not missing and &nb is missing),
                 sum(&na is missing and &nb is not missing),
                 sum(&na is missing and &nb is missing),
                 &n_cb
          from g.master_data_merged;
        quit;
      %end;
    %end;
  %end;
%mend crosstabs;
%crosstabs;

proc sort data=work.xtab;    by concept var_a var_b descending n_rows; run;
proc sort data=work.pairsum; by concept descending n_both; run;

proc sql noprint;
  select count(*) into :n_pairs   trimmed from work.pairsum;
  select count(*) into :n_nooverlap trimmed from work.pairsum where n_both = 0;
quit;

%macro report_overlap;
  %if &n_nooverlap > 0 %then %do;
    %put WARNING: [10_profile] &n_nooverlap of &n_pairs pairs NEVER co-occur.;
    %put WARNING- Those cannot be compared on values. See the Pair Summary sheet.;
  %end;
  %put NOTE: [10_profile] &n_pairs pairs cross-tabulated.;
%mend report_overlap;
%report_overlap;


/* =========================================================================
   SECTION 4: Decision template
   -------------------------------------------------------------------------
   CON-03. One row per (concept, source column, observed value). A human sets
   TARGET_VALUE and CONFIRMED. 10b_concept_harmonize.sas reads the completed file
   back and applies exactly what it says -- nothing inferred, nothing defaulted.

   Written as CSV rather than a sheet of the workbook so it can be edited without
   touching the evidence, and so 10b has an unambiguous input format.
   ========================================================================= */

data work.template;
  /* LENGTH before SET: once SET defines a variable, a later LENGTH cannot change
     its type and cannot reliably enlarge it.                                   */
  length concept $32 varname $32 value_txt $60 n_rows 8
         target_value $40 confirmed $3 harmonized_name $32 priority 8
         reviewer $40 comment $200;
  set work.valinv;
  where value_txt ne "(missing)"
    and n_rows is not missing
    and index(value_txt, "distinct values") = 0;
  target_value    = "";   /* human fills: the standard value this maps to        */
  confirmed       = "";   /* human fills: YES only if the concept is confirmed   */
  harmonized_name = "";   /* human fills: new column name, MUST start h_ and be
                             28 characters or fewer so h_*_src fits in 32        */
  priority        = 1;    /* human edits: when two sources both hold a value on a
                             row, the LOWEST number wins. 10b fails on a tie
                             between two DIFFERENT source columns.              */
  reviewer        = "";
  comment         = "";
  keep concept varname value_txt n_rows target_value confirmed harmonized_name
       priority reviewer comment;
run;

/* Reject values that cannot be carried safely into generated code. 10b builds
   IF statements from these strings, so a value containing a double quote, an
   ampersand or a percent sign would break the statement or trigger macro
   resolution. None are expected in clinical Y/N codes -- but the program claims
   to apply ARBITRARY mappings, so it must say so when it cannot.             */
proc sql noprint;
  create table work.unsafe_values as
  select concept, varname, value_txt
  from work.template
  where index(value_txt, '22'x) > 0      /* double quote */
     or index(value_txt, '&')  > 0
     or index(value_txt, '%')  > 0;
  select count(*) into :n_unsafe trimmed from work.unsafe_values;
quit;

%macro warn_unsafe;
  %if &n_unsafe > 0 %then %do;
    %put WARNING: [10_profile] &n_unsafe observed values contain a quote%str(,) ampersand or percent sign.;
    %put WARNING- 10b cannot build a mapping rule from those safely. See work.unsafe_values.;
  %end;
%mend warn_unsafe;
%warn_unsafe;

proc export data=work.template
    outfile="&docs_path.\concept_decisions_TEMPLATE.csv"
    dbms=csv replace;
run;

proc sql noprint;
  select count(*) into :n_template trimmed from work.template;
quit;
%put NOTE: [10_profile] decision template written with &n_template value rows.;


/* =========================================================================
   SECTION 5: Evidence workbook
   ========================================================================= */

%macro drop_stale;
  %local rc;
  %if %sysfunc(fileexist(%bquote(&docs_path.\CONCEPT_EVIDENCE.xlsx))) %then %do;
    filename _oldx "&docs_path.\CONCEPT_EVIDENCE.xlsx";
    %let rc = %sysfunc(fdelete(_oldx));
    filename _oldx clear;
    %if &rc ne 0 %then %do;
      %fail_out(msg=Could not delete the previous CONCEPT_EVIDENCE.xlsx -- rc=&rc. It may be open in Excel.);
    %end;
  %end;
%mend drop_stale;
%drop_stale;

ods excel file="&docs_path.\CONCEPT_EVIDENCE.xlsx"
    options(sheet_name="KEY" embedded_titles="yes" autofilter="all" frozen_headers="1");

title justify=left color=CX0021A5 height=14pt "PeCAN -- Duplicate Concept Evidence";
title2 justify=left height=10pt "g.master_data_merged, &n_rows rows. Generated %sysfunc(datetime(), datetime20.)";

data work.key;
  length Item $34 Meaning $230;
  Item="What this is";      Meaning="Evidence for deciding whether columns suspected of measuring the same thing actually do. It decides nothing."; output;
  Item="Concept";           Meaning="A hypothesis drawn from the rectification register, not an established fact. Testing it is the point."; output;
  Item="Value Inventory";   Meaning="Every observed value of every named column, with counts. This answers Y/N versus 1/0 versus YES/NO, which nobody has checked."; output;
  Item="Cross-Tabs";        Meaning="Every observed combination of two columns in a concept, with counts. Read the value mapping off this."; output;
  Item="Pair Summary";      Meaning="Per pair: rows where both are present, only one, or neither, plus the number of distinct combinations."; output;
  Item="n_both = 0";        Meaning="The two columns NEVER co-occur, so they cannot be compared on values. That is a finding, not a null result."; output;
  Item="No agreement %";    Meaning="Deliberate. A percentage cannot be computed before the mapping is known -- assuming Y=1 to test whether Y=1 is circular."; output;
  Item="Missing Columns";   Meaning="Named in the register but absent from the merged file. Means the register is stale."; output;
  Item="Next step";         Meaning="Complete docs/concept_decisions_TEMPLATE.csv, save it as concept_decisions.csv, then run 10b_concept_harmonize.sas."; output;
  Item="priority column";   Meaning="When two source columns both hold a value on the same row, the LOWEST priority number wins. 10b FAILS on a tie between two different source columns rather than picking silently."; output;
  Item="harmonized_name";   Meaning="Must start with h_ and be 28 characters or fewer, so the h_*_src companion fits within the 32-character limit. 10b rejects a name that collides with an existing column."; output;
  Item="Originals";         Meaning="10b NEVER overwrites a source column. It creates new h_ prefixed columns and leaves every original intact."; output;
  Item="Excluded on purpose"; Meaning="ISO_SEV_MAC_TOTAL_Exp is a TOTAL, not an average -- a different statistic. _30_DAY_MORTALITY and Death_Days_After_Surgery are separate measures."; output;
run;

proc print data=work.key noobs label; var Item Meaning; run;

ods excel options(sheet_name="Value Inventory");
proc print data=work.valinv noobs label;
  var concept varname vtype value_txt n_rows pct;
  label concept="Concept" varname="Variable" vtype="Type"
        value_txt="Observed Value" n_rows="N Rows" pct="Pct of File";
  format n_rows comma12. pct 6.1;
run;

ods excel options(sheet_name="Cross-Tabs");
proc print data=work.xtab noobs label;
  var concept var_a val_a var_b val_b n_rows;
  label concept="Concept" var_a="Variable A" val_a="Value A"
        var_b="Variable B" val_b="Value B" n_rows="N Rows";
  format n_rows comma12.;
run;

ods excel options(sheet_name="Pair Summary");
proc print data=work.pairsum noobs label;
  var concept var_a var_b n_both n_a_only n_b_only n_neither n_combos;
  label concept="Concept" var_a="Variable A" var_b="Variable B"
        n_both="Both Present" n_a_only="Only A" n_b_only="Only B"
        n_neither="Neither" n_combos="Distinct Combos";
  format n_both n_a_only n_b_only n_neither comma12.;
run;

ods excel options(sheet_name="Missing Columns");
proc print data=work.concept_missing noobs label;
  var concept varname note;
  label concept="Concept" varname="Named Variable (ABSENT)" note="Register note";
run;

ods excel close;
title;

%macro check_xlsx;
  %if %sysfunc(fileexist(%bquote(&docs_path.\CONCEPT_EVIDENCE.xlsx))) = 0 %then %do;
    %fail_out(msg=CONCEPT_EVIDENCE.xlsx was not written);
  %end;
%mend check_xlsx;
%check_xlsx;


/* =========================================================================
   SECTION 6: QC artifact
   ========================================================================= */

data _null_;
  file "&qc_path.\10_concept_profile.txt";
  put "10_concept_profile -- Run: %sysfunc(datetime(), datetime20.)";
  put "=======================================================================";
  put " ";
  put "merged_rows=&n_rows";
  put "columns_named=&n_present";
  put "columns_absent=&n_absent";
  put "pairs_crosstabbed=&n_pairs";
  put "pairs_with_no_overlap=&n_nooverlap";
  put "template_value_rows=&n_template";
  put " ";
  put "This program decides nothing. It writes evidence and a decision template.";
  put "Complete docs/concept_decisions_TEMPLATE.csv, save it as";
  put "docs/concept_decisions.csv, then run 10b_concept_harmonize.sas.";
  put " ";
  put "A pair with no overlap cannot be compared on values at all. Under md3-owns";
  put "ownership that is a real possibility and it is a finding, not a null result.";
run;

%put NOTE: ==== Phase 10 profiling complete ====;
%put NOTE- Evidence: docs/CONCEPT_EVIDENCE.xlsx;
%put NOTE- Template: docs/concept_decisions_TEMPLATE.csv;

%restore_log;
