/*==========================================================================
  Program : 11_dictionary_reconcile.sas
  Phase   : 11 -- Reconcile the merged file against the PRECEDE data dictionary
  Purpose : Cross-reference every column in g.master_data_merged against the
            authoritative Data_Dictionary_PRECEDE_11_4_2020, and produce:
              - a RENAME MAP from actual column name to documented canonical name
              - the columns documented but ABSENT from the merged file
              - the columns present but UNDOCUMENTED
              - documented type vs actual type mismatches
              - TESTED assertions drawn from the dictionary descriptions

  Requirements addressed
    DIC-01  Every merged column is classified: matched, renamed, or undocumented
    DIC-02  Matching is fuzzy by design -- exact, then case-insensitive, then
            SAS-normalised, then de-underscored. Every match records HOW it was
            made, so a weak match can be reviewed rather than trusted
    DIC-03  A rename map is produced but NEVER auto-applied. Renaming is a
            decision; this program supplies the evidence for it
    DIC-04  Documented rules that are testable are TESTED against the data, and
            a contradiction is reported as a finding rather than assumed away
    DIC-05  Nothing is written to g.master_data_merged

  Reads   : g.master_data_merged           (read-only)
            docs/precede_dictionary.csv    (extracted from the 2020 workbook)
  Writes  : docs/DICTIONARY_RECONCILE.xlsx
            docs/rename_map_PROPOSED.csv
            qc/11_dictionary_reconcile.txt

  Author  : 2026-08-28

  WHY THIS EXISTS. Until now, canonical names were inferred from what the source
  extracts happened to be called, and semantics were inferred from observed
  values. The dictionary is the actual specification, and on first reading it
  already contradicts two things this project treated as established:

    Emergent -- documented as "1 is emergent; otherwise is missing". PCM-F-06
      recorded Y/N/blank, and 06_reconcile.sas tests upcase(Emergent)='Y'. If the
      stored value is 1, that test returns zero and the summary reads
      "0 Y / 0 N", which looks like a finding rather than a coding error.

    Age_at_Encounter -- documented as "changed to 90 if age is 90 or above".
      Observed maximum is 100. Either the top-coding was not applied to this
      extract or the dictionary is stale.

  Neither is assumed here. Both are TESTED in SECTION 5, and whichever way they
  come out is written to the report.

  PCM compliance -- each of these has bitten this pipeline:
    - No bare open-code %IF (needs a %DO block in open code)
    - No apostrophes and no embedded semicolons in %PUT text
    - Every %abort cancel inside a named macro
    - No &SQLOBS; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - IS NOT MISSING is PROC SQL syntax; the DATA-step form is NOT MISSING(x)
    - dictionary.columns.TYPE is char/num; PROC CONTENTS OUT= type is 1/2
    - LENGTH before SET, so PROC IMPORT never decides a type
    - g.master_data_merged never on the left of a DATA statement
==========================================================================*/

options mprint nofmterr nodate nonumber ps=max ls=200;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\11_dictionary_reconcile.log" new;
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

%put NOTE: ==== Phase 11 Dictionary Reconciliation starting ====;


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

%macro check_dict_file;
  %if %sysfunc(fileexist(%bquote(&docs_path.\precede_dictionary.csv))) = 0 %then %do;
    %put ERROR: docs/precede_dictionary.csv not found.;
    %put ERROR- It is the flattened form of Data_Dictionary_PRECEDE_11_4_2020.xlsx,;
    %put ERROR- with one row per documented variable across all 19 sheets.;
    %fail_out(msg=Dictionary CSV missing);
  %end;
%mend check_dict_file;
%check_dict_file;

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
  %if %length(&n_rows) = 0 %then %do;
    %fail_out(msg=Row count query returned no value);
  %end;
  %else %if &n_rows = 0 %then %do;
    %fail_out(msg=g.master_data_merged is empty);
  %end;
  %put NOTE: [11_dict] &n_rows rows in the merged file.;
%mend check_rows;
%check_rows;


/* =========================================================================
   SECTION 1: Read the dictionary and the actual column list
   ========================================================================= */

proc import datafile="&docs_path.\precede_dictionary.csv"
    out=work.dict_raw dbms=csv replace;
  guessingrows=max;
run;

/* LENGTH before SET so PROC IMPORT never decides a type or truncates a
   description. Every field is renamed on the way in.                       */
data work.dict;
  length sheet $40 dict_name $60 dict_type $20 description $300
         source $120 note $80 sas_name $32 key_u $32;
  set work.dict_raw (rename=(sheet=_s dict_name=_n dict_type=_t
                             description=_d source=_o note=_e sas_name=_a));
  sheet       = strip(cats(_s));
  dict_name   = strip(cats(_n));
  dict_type   = strip(cats(_t));
  description = strip(cats(_d));
  source      = strip(cats(_o));
  note        = strip(cats(_e));
  sas_name    = strip(cats(_a));
  key_u       = upcase(sas_name);
  if missing(dict_name) then delete;
  keep sheet dict_name dict_type description source note sas_name key_u;
run;

/* A variable can appear on several sheets (PRECEDE Study ID appears on many).
   Keep one row per normalised name, preferring MASTER_DATASET, then
   DERIVED_VARIABLES_MASTER, then whatever else -- the master sheets carry the
   definition that matters for the merged file.                              */
data work.dict_ranked;
  set work.dict;
  if      sheet = 'MASTER_DATASET'           then sheet_rank = 1;
  else if sheet = 'DERIVED_VARIABLES_MASTER' then sheet_rank = 2;
  else                                            sheet_rank = 3;
run;

proc sort data=work.dict_ranked; by key_u sheet_rank sheet; run;

data work.dict_u;
  set work.dict_ranked;
  by key_u;
  if first.key_u;
run;

proc sql noprint;
  create table work.actual as
  select upcase(name) as act_u length=32,
         name         as act_name length=32,
         type         as act_type length=4,
         length       as act_len,
         varnum
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED'
  order by varnum;

  select count(*) into :n_dict   trimmed from work.dict_u;
  select count(*) into :n_actual trimmed from work.actual;
quit;

%put NOTE: [11_dict] &n_dict documented variables%str(,) &n_actual actual columns.;


/* =========================================================================
   SECTION 2: Match, in decreasing order of confidence
   -------------------------------------------------------------------------
   DIC-02. Four passes, each recorded so a weak match can be reviewed rather
   than trusted. De-underscoring is the loosest and is FLAGGED as REVIEW, not
   accepted: it would match Death_Date_Y_N to DeathDateYN, which is almost
   certainly right, but also Sleep_Apnea to SleepApnea when a separate
   Sleep_Apnea_YN exists.
   ========================================================================= */

%macro squash(v);
  compress(upcase(&v), '_')
%mend squash;

proc sql;
  create table work.matched as
  select a.varnum, a.act_name, a.act_u, a.act_type, a.act_len,
         d.dict_name, d.sas_name, d.dict_type, d.description, d.sheet,
         case
           when a.act_name = d.sas_name                         then 'EXACT'
           when a.act_u    = d.key_u                            then 'CASE'
           else 'SQUASH'
         end as match_how length=8
  from work.actual as a
  inner join work.dict_u as d
    on a.act_u = d.key_u
       or %squash(a.act_name) = %squash(d.sas_name);
quit;

/* A single actual column must not match several dictionary entries */
proc sql noprint;
  create table work.ambiguous as
  select act_name, count(*) as n_matches
  from work.matched group by act_name having calculated n_matches > 1;
  select count(*) into :n_ambig trimmed from work.ambiguous;
quit;

%macro report_ambig;
  %if &n_ambig > 0 %then %do;
    %put WARNING: [11_dict] &n_ambig columns match more than one dictionary entry.;
    %put WARNING- Listed on the Ambiguous sheet. Resolve before applying any rename.;
  %end;
%mend report_ambig;
%report_ambig;

/* Keep the strongest match per column: EXACT beats CASE beats SQUASH */
data work.matched_rank;
  set work.matched;
  if      match_how = 'EXACT'  then how_rank = 1;
  else if match_how = 'CASE'   then how_rank = 2;
  else                              how_rank = 3;
run;

proc sort data=work.matched_rank; by act_u how_rank dict_name; run;

data work.match_best;
  set work.matched_rank;
  by act_u;
  if first.act_u;
run;

proc sql;
  /* documented but absent from the merged file */
  create table work.doc_not_present as
  select d.sheet, d.dict_name, d.sas_name, d.dict_type, d.description
  from work.dict_u as d
  where d.key_u not in (select act_u from work.match_best)
  order by sheet, dict_name;

  /* present but undocumented */
  create table work.present_not_doc as
  select a.varnum, a.act_name, a.act_type, a.act_len
  from work.actual as a
  where a.act_u not in (select act_u from work.match_best)
  order by varnum;

  select count(*) into :n_match  trimmed from work.match_best;
  select count(*) into :n_docabs trimmed from work.doc_not_present;
  select count(*) into :n_undoc  trimmed from work.present_not_doc;
  select count(*) into :n_exact  trimmed from work.match_best where match_how='EXACT';
  select count(*) into :n_case   trimmed from work.match_best where match_how='CASE';
  select count(*) into :n_squash trimmed from work.match_best where match_how='SQUASH';
quit;

%put NOTE: [11_dict] matched &n_match (&n_exact exact%str(,) &n_case case%str(,) &n_squash squash).;
%put NOTE: [11_dict] &n_docabs documented but absent%str(,) &n_undoc present but undocumented.;


/* =========================================================================
   SECTION 3: Type agreement
   -------------------------------------------------------------------------
   The dictionary writes types as free text -- num, char, char(15), int, double,
   Foreign Key, ID; String. Normalise to CHAR or NUM and compare. Anything that
   cannot be normalised is UNKNOWN, not a mismatch.
   ========================================================================= */

data work.typecheck;
  set work.match_best;
  length doc_type_norm $8 type_verdict $12;
  _t = upcase(dict_type);
  if      index(_t,'CHAR')   > 0 or index(_t,'STRING') > 0 then doc_type_norm = 'CHAR';
  else if index(_t,'NUM')    > 0 or index(_t,'INT')    > 0
       or index(_t,'DOUBLE') > 0 or index(_t,'FLOAT')  > 0 then doc_type_norm = 'NUM';
  else doc_type_norm = 'UNKNOWN';

  if      doc_type_norm = 'UNKNOWN'                          then type_verdict = 'UNDOCUMENTED';
  else if doc_type_norm = upcase(act_type)                   then type_verdict = 'AGREES';
  else                                                            type_verdict = 'MISMATCH';
  drop _t;
run;

proc sql noprint;
  select count(*) into :n_typebad trimmed from work.typecheck where type_verdict='MISMATCH';
quit;

%macro report_type;
  %if &n_typebad > 0 %then %do;
    %put WARNING: [11_dict] &n_typebad columns disagree with the documented type.;
    %put WARNING- Some are expected -- PREP-03 converted md8 char columns to numeric,;
    %put WARNING- and PREP-07 harmonised Base_Procedure_Code_1 to character. Review;
    %put WARNING- the Type Check sheet rather than assuming any of them is wrong.;
  %end;
%mend report_type;
%report_type;


/* =========================================================================
   SECTION 4: Rename map -- PROPOSED, never applied
   -------------------------------------------------------------------------
   DIC-03. A rename changes every downstream reference, so it is a decision.
   This writes the proposal and the evidence for it; a human applies it.
   ========================================================================= */

proc sql;
  create table work.rename_map as
  select act_name          as current_name length=32,
         sas_name          as proposed_name length=32,
         dict_name         as documented_as length=60,
         match_how,
         sheet             as dict_sheet,
         act_type, act_len,
         description
  from work.match_best
  where act_name ne sas_name
  order by match_how, act_name;

  select count(*) into :n_rename trimmed from work.rename_map;
quit;

proc export data=work.rename_map
    outfile="&docs_path.\rename_map_PROPOSED.csv" dbms=csv replace;
run;

%put NOTE: [11_dict] &n_rename columns differ from their documented name.;


/* =========================================================================
   SECTION 5: TEST the documented rules -- DIC-04
   -------------------------------------------------------------------------
   The dictionary states rules that can be checked. Two of them contradict what
   this project has been assuming, so they are TESTED rather than believed.
   Findings are reported; nothing aborts, because a contradiction here is
   information about the extract, not a pipeline defect.
   ========================================================================= */

proc sql;
  create table work.rule_tests
    (rule_id char(20), variable char(32), documented char(120),
     observed char(120), verdict char(12));
quit;

/* Column-existence test via dictionary.columns rather than
   %sysfunc(varnum(%sysfunc(open(...)))). The open() form leaks a dataset handle
   -- nothing ever calls close() -- and three of them would sit open for the rest
   of the session.                                                            */
%macro col_exists(col=);
  %local n;
  %let n = 0;
  proc sql noprint;
    select count(*) into :n trimmed from dictionary.columns
    where libname='G' and memname='MASTER_DATA_MERGED' and upcase(name)=%upcase("&col");
  quit;
  &n
%mend col_exists;

/* RULE 1 -- Age_at_Encounter: "changed to 90 if age is 90 or above" */
%macro test_age;
  %local n_over amax;
  %if %col_exists(col=Age_at_Encounter) = 0 %then %do;
    proc sql; insert into work.rule_tests values
      ('AGE-TOPCODE','Age_at_Encounter','top-coded at 90','column not present','SKIPPED'); quit;
    %return;
  %end;
  proc sql noprint;
    select count(*) into :n_over trimmed from g.master_data_merged
      where Age_at_Encounter is not missing and Age_at_Encounter > 90;
    select max(Age_at_Encounter) into :amax trimmed from g.master_data_merged;
  quit;
  proc sql;
    insert into work.rule_tests values
      ('AGE-TOPCODE','Age_at_Encounter',
       'changed to 90 if age is 90 or above',
       "&n_over rows exceed 90, max is &amax",
       %if &n_over = 0 %then %do; 'HOLDS' %end; %else %do; 'CONTRADICTED' %end;);
  quit;
  %put NOTE: [11_dict] AGE-TOPCODE -- &n_over rows above 90%str(,) max &amax.;
%mend test_age;
%test_age;

/* RULE 2 -- Emergent: "1 is emergent; otherwise is missing" */
%macro test_emergent;
  %local n_one n_y n_n n_other;
  %if %col_exists(col=Emergent) = 0 %then %do;
    proc sql; insert into work.rule_tests values
      ('EMERGENT-CODE','Emergent','1 is emergent','column not present','SKIPPED'); quit;
    %return;
  %end;
  proc sql noprint;
    select count(*) into :n_one   trimmed from g.master_data_merged where strip(Emergent) = '1';
    select count(*) into :n_y     trimmed from g.master_data_merged where upcase(strip(Emergent)) = 'Y';
    select count(*) into :n_n     trimmed from g.master_data_merged where upcase(strip(Emergent)) = 'N';
    select count(*) into :n_other trimmed from g.master_data_merged
      where not missing(Emergent) and strip(Emergent) not in ('1') and upcase(strip(Emergent)) not in ('Y','N');
  quit;
  proc sql;
    insert into work.rule_tests values
      ('EMERGENT-CODE','Emergent',
       '1 is emergent, otherwise missing',
       "1=&n_one, Y=&n_y, N=&n_n, other=&n_other",
       %if &n_one > 0 and &n_y = 0 %then %do; 'HOLDS' %end;
       %else %if &n_y > 0 and &n_one = 0 %then %do; 'CONTRADICTED' %end;
       %else %do; 'REVIEW' %end;);
  quit;
  %put NOTE: [11_dict] EMERGENT-CODE -- 1=&n_one Y=&n_y N=&n_n other=&n_other.;
  %put NOTE- If Y is populated and 1 is zero, 06_reconcile.sas is testing the right;
  %put NOTE- value and the dictionary is stale. If the reverse, that program reports;
  %put NOTE- zero for a field that is actually populated.;
%mend test_emergent;
%test_emergent;

/* RULE 3 -- Weekend_Indicator: "Y is weekend; N is weekdays" */
%macro test_weekend;
  %local n_bad;
  %if %col_exists(col=Weekend_Indicator) = 0 %then %do;
    proc sql; insert into work.rule_tests values
      ('WEEKEND-YN','Weekend_Indicator','Y or N','column not present','SKIPPED'); quit;
    %return;
  %end;
  proc sql noprint;
    select count(*) into :n_bad trimmed from g.master_data_merged
      where not missing(Weekend_Indicator)
        and upcase(strip(Weekend_Indicator)) not in ('Y','N');
  quit;
  proc sql;
    insert into work.rule_tests values
      ('WEEKEND-YN','Weekend_Indicator','Y is weekend, N is weekdays',
       "&n_bad values are neither Y nor N",
       %if &n_bad = 0 %then %do; 'HOLDS' %end; %else %do; 'CONTRADICTED' %end;);
  quit;
%mend test_weekend;
%test_weekend;

proc sql noprint;
  select count(*) into :n_contra trimmed from work.rule_tests where verdict='CONTRADICTED';
quit;

%macro report_rules;
  %if &n_contra > 0 %then %do;
    %put WARNING: [11_dict] &n_contra documented rules are CONTRADICTED by the data.;
    %put WARNING- That is a finding about the extract or a stale dictionary, not a;
    %put WARNING- pipeline defect. See the Rule Tests sheet.;
  %end;
%mend report_rules;
%report_rules;


/* =========================================================================
   SECTION 6: Workbook
   ========================================================================= */

%macro drop_stale;
  %local rc;
  %if %sysfunc(fileexist(%bquote(&docs_path.\DICTIONARY_RECONCILE.xlsx))) %then %do;
    filename _oldx "&docs_path.\DICTIONARY_RECONCILE.xlsx";
    %let rc = %sysfunc(fdelete(_oldx));
    filename _oldx clear;
    %if &rc ne 0 %then %do;
      %fail_out(msg=Could not delete the previous DICTIONARY_RECONCILE.xlsx -- rc=&rc. It may be open in Excel.);
    %end;
  %end;
%mend drop_stale;
%drop_stale;

ods excel file="&docs_path.\DICTIONARY_RECONCILE.xlsx"
    options(sheet_name="KEY" embedded_titles="yes" autofilter="all" frozen_headers="1");

title justify=left color=CX0021A5 height=14pt "PeCAN -- Merged File vs PRECEDE Data Dictionary";
title2 justify=left height=10pt "&n_actual columns, &n_dict documented variables. Generated %sysfunc(datetime(), datetime20.)";

data work.key;
  length Item $30 Meaning $250;
  Item="Source of truth";  Meaning="Data_Dictionary_PRECEDE_11_4_2020, flattened to docs/precede_dictionary.csv -- 310 variables across 19 sheets."; output;
  Item="Not every var matches"; Meaning="The dictionary covers the whole PRECEDE study. The merged file is a subset, and it also carries columns the dictionary never documented."; output;
  Item="match_how EXACT";   Meaning="Column name equals the documented name after SAS normalisation. Trust it."; output;
  Item="match_how CASE";    Meaning="Matches ignoring case. SAS names are case-insensitive, so this is safe."; output;
  Item="match_how SQUASH";  Meaning="Matches only after removing underscores. REVIEW each one -- this is the loosest pass and can pair a bare name with a _YN variant."; output;
  Item="Rename Map";        Meaning="PROPOSED only. A rename changes every downstream reference, so it is a decision. Written to docs/rename_map_PROPOSED.csv."; output;
  Item="Documented, Absent";Meaning="In the dictionary, not in the merged file. Expected -- the merge covers a subset of the study."; output;
  Item="Present, Undocumented"; Meaning="In the merged file, not in the dictionary. These are the ones to question: an undocumented column has no specification to check against."; output;
  Item="Type Check";        Meaning="Documented type versus actual. Some mismatches are intended: PREP-03 converted md8 char columns to numeric, PREP-07 made Base_Procedure_Code_1 character."; output;
  Item="Rule Tests";        Meaning="Documented rules tested against the data. CONTRADICTED means the extract and the dictionary disagree -- a finding, not a defect."; output;
  Item="Nothing is applied"; Meaning="This program reads the merged file and writes reports. It renames nothing and changes nothing."; output;
run;

proc print data=work.key noobs label; var Item Meaning; run;

ods excel options(sheet_name="Rule Tests");
proc print data=work.rule_tests noobs label;
  var rule_id variable documented observed verdict;
  label rule_id="Rule" variable="Variable" documented="Documented Rule"
        observed="Observed" verdict="Verdict";
run;

ods excel options(sheet_name="Rename Map");
proc print data=work.rename_map noobs label;
  var current_name proposed_name documented_as match_how dict_sheet act_type act_len description;
  label current_name="Current Name" proposed_name="Proposed Name" documented_as="Documented As"
        match_how="Match" dict_sheet="Dict Sheet" act_type="Type" act_len="Length"
        description="Description";
run;

ods excel options(sheet_name="Present, Undocumented");
proc print data=work.present_not_doc noobs label;
  var varnum act_name act_type act_len;
  label varnum="Order" act_name="Column" act_type="Type" act_len="Length";
run;

ods excel options(sheet_name="Documented, Absent");
proc print data=work.doc_not_present noobs label;
  var sheet dict_name sas_name dict_type description;
  label sheet="Dict Sheet" dict_name="Documented Name" sas_name="SAS Form"
        dict_type="Doc Type" description="Description";
run;

ods excel options(sheet_name="Type Check");
proc print data=work.typecheck noobs label;
  where type_verdict ne 'AGREES';
  var act_name act_type act_len dict_type doc_type_norm type_verdict description;
  label act_name="Column" act_type="Actual Type" act_len="Actual Length"
        dict_type="Documented Type" doc_type_norm="Normalised" type_verdict="Verdict"
        description="Description";
run;

ods excel options(sheet_name="All Matches");
proc print data=work.match_best noobs label;
  var varnum act_name sas_name match_how sheet act_type act_len description;
  label varnum="Order" act_name="Column" sas_name="Documented (SAS form)"
        match_how="Match" sheet="Dict Sheet" act_type="Type" act_len="Length"
        description="Description";
run;

%macro amb_sheet;
  %if &n_ambig > 0 %then %do;
    ods excel options(sheet_name="Ambiguous");
    proc print data=work.ambiguous noobs label;
      var act_name n_matches;
      label act_name="Column" n_matches="Dictionary Entries Matched";
    run;
  %end;
%mend amb_sheet;
%amb_sheet;

ods excel close;
title;

%macro check_xlsx;
  %if %sysfunc(fileexist(%bquote(&docs_path.\DICTIONARY_RECONCILE.xlsx))) = 0 %then %do;
    %fail_out(msg=DICTIONARY_RECONCILE.xlsx was not written);
  %end;
%mend check_xlsx;
%check_xlsx;


/* =========================================================================
   SECTION 7: QC artifact
   ========================================================================= */

data _null_;
  file "&qc_path.\11_dictionary_reconcile.txt";
  put "11_dictionary_reconcile -- Run: %sysfunc(datetime(), datetime20.)";
  put "=======================================================================";
  put " ";
  put "merged_columns=&n_actual";
  put "documented_variables=&n_dict";
  put "matched=&n_match";
  put "  match_exact=&n_exact";
  put "  match_case=&n_case";
  put "  match_squash=&n_squash";
  put "documented_but_absent=&n_docabs";
  put "present_but_undocumented=&n_undoc";
  put "renames_proposed=&n_rename";
  put "type_mismatches=&n_typebad";
  put "ambiguous_matches=&n_ambig";
  put "rules_contradicted=&n_contra";
  put " ";
  put "NOTHING WAS RENAMED OR CHANGED. A rename touches every downstream";
  put "reference, so this program supplies the proposal and the evidence;";
  put "a human applies it.";
  put " ";
  put "match_squash entries need review individually. That pass ignores";
  put "underscores, which is right for Death_Date_Y_N but can also pair a bare";
  put "comorbidity name with its _YN variant when both exist as columns.";
  put " ";
  put "A CONTRADICTED rule means the extract and the 2020 dictionary disagree.";
  put "That is information about the data, not a pipeline defect -- but it does";
  put "mean one of the two is stale and the analysis should say which it trusts.";
run;

%put NOTE: ==== Phase 11 complete ====;
%put NOTE- Workbook: docs/DICTIONARY_RECONCILE.xlsx;
%put NOTE- Rename proposal: docs/rename_map_PROPOSED.csv;
%put NOTE- Report: qc/11_dictionary_reconcile.txt;

%restore_log;
