/*==========================================================================
  Program : 16_summary_docx.sas
  Purpose : A Word document summarising every variable in g.analysis_base that
            the PRECEDE data dictionary documents -- PROC MEANS for numerics,
            PROC FREQ for categoricals -- with each variable labelled by its
            DOCUMENTED name so a reader can find it in the dictionary.

  Output  : docs/DOCUMENTED_VARIABLE_SUMMARY.docx
            qc/16_summary_docx.txt

  Reads   : g.analysis_base            (read-only)
            docs/precede_dictionary.csv

  Author  : 2026-08-29

  WHY THE ALIAS MATTERS. Documented and actual names diverge, and a reader
  holding the dictionary will look for the documented one. Two cases in this set:

    ASA__Anesth_Record_  is documented as  ASA (Anesth Record)
    ISO_SEV_Exp_IntraOp_MAC_Average  is the column present; the dictionary
      documents ISO_SEV_IntraOp_MAC_Average, which lives in md4. Phase 10 proved
      the two IDENTICAL on all 7,695 overlapping rows, so the md3 column carries
      the documented measure under a different name. Without that stated, someone
      searches for the documented name, does not find it, and concludes the
      variable is missing.

  SCOPE. This covers the documented subset only. g.analysis_base deliberately
  EXCLUDES Cognitive_Score, Frailty_Score, the five frailty components and the
  hemodynamic block, because none appear in the dictionary sheets that matched.
  If an analysis needs those, g.master_data_merged is the file -- and md3 alone
  holds 8,412 fewer cognitive values than the merge does. Both files look
  complete in isolation, which is why the boundary is stated in the document
  itself and not only here.

  ODS WORD writes a real .docx natively (SAS 9.4M6+). If this release does not
  support it, switch the two ODS statements to ODS RTF and change the extension;
  Word opens RTF without complaint.

  PCM compliance -- each of these has bitten this pipeline:
    - No bare open-code %IF, and no %DO outside a macro definition
    - No apostrophes and no embedded semicolons in %PUT text
    - Every %abort cancel inside a named macro
    - No &SQLOBS; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - Counts checked with %LENGTH BEFORE use
    - No macro that generates SAS statements called inside a %IF condition
    - dictionary.columns.TYPE is char/num, not the 1/2 of PROC CONTENTS
    - No data VALUE routed through a macro variable into generated code
    - Nothing written to g
==========================================================================*/

options nodate nonumber ps=max ls=200 nofmterr;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* Variables with more distinct values than this get PROC MEANS-style treatment
   or a distinct-count line rather than a full frequency table. A 4,644-level
   frequency table is not a summary.                                          */
%let max_freq_levels = 25;

%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\16_summary_docx.log" new;
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
  ods word close;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;

%route_log;
libname g "&g_path";

%put NOTE: ==== Documented variable summary starting ====;


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

%macro check_dict_csv;
  %if %sysfunc(fileexist(%bquote(&docs_path.\precede_dictionary.csv))) = 0 %then %do;
    %fail_out(msg=docs/precede_dictionary.csv not found);
  %end;
%mend check_dict_csv;
%check_dict_csv;

proc sql noprint;
  select count(*) into :n_tab trimmed
  from dictionary.tables where libname='G' and memname='ANALYSIS_BASE';
quit;

%macro check_src;
  %if %length(&n_tab) = 0 %then %do;
    %fail_out(msg=Existence query returned no value);
  %end;
  %else %if &n_tab ne 1 %then %do;
    %fail_out(msg=g.analysis_base not found);
  %end;
%mend check_src;
%check_src;

proc sql noprint;
  select count(*) into :n_rows trimmed from g.analysis_base;
quit;

%macro check_rows;
  %if %length(&n_rows) = 0 %then %do;
    %fail_out(msg=Row count query returned no value);
  %end;
  %else %if &n_rows = 0 %then %do;
    %fail_out(msg=g.analysis_base is empty);
  %end;
  %put NOTE: [16] &n_rows rows in g.analysis_base.;
%mend check_rows;
%check_rows;


/* =========================================================================
   SECTION 1: The documented subset, with aliases
   -------------------------------------------------------------------------
   Matching mirrors Phase 11: exact, then case-insensitive, then underscores
   removed. The SQUASH pass is what pairs ASA__Anesth_Record_ with the
   documented ASA__Anesth_Record, and without it that variable would be
   reported as undocumented.
   ========================================================================= */

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
  /* UPCASE before the sort. BY-group processing is case-sensitive, so
     Age_at_Encounter and AGE_AT_ENCOUNTER on two sheets would survive as two
     rows, both match one column on the case-insensitive join below, and trip
     the duplicate gate.                                                     */
  sas_name    = upcase(strip(cats(_a)));
  if missing(sas_name) then delete;
  /* MASTER_DATASET first, then DERIVED, so the authoritative sheet wins */
  if      sheet = 'MASTER_DATASET'           then sheet_rank = 1;
  else if sheet = 'DERIVED_VARIABLES_MASTER' then sheet_rank = 2;
  else                                            sheet_rank = 3;
  keep sheet dict_name dict_type description sas_name sheet_rank;
run;

proc sort data=work.dict; by sas_name sheet_rank sheet; run;

/* One row per documented name -- the dictionary repeats names across sheets,
   and an undeduplicated join multiplies every variable it touches.          */
data work.dict_u;
  set work.dict;
  by sas_name;
  if first.sas_name;
run;

proc sql;
  create table work.actual as
  select name as varname length=32, upcase(name) as var_u length=32,
         type as vtype length=4, length as vlen, label as sas_label length=256,
         varnum
  from dictionary.columns
  where libname='G' and memname='ANALYSIS_BASE';

  /* Every match, WITH a rank. The OR-join keeps exact and squash matches alike,
     so a column with an exact match to one entry and a squash match to another
     survived twice and tripped the duplicate gate. Rank, sort, keep the
     strongest.                                                              */
  create table work.doc_all as
  select a.varnum, a.varname, a.vtype, a.vlen, a.sas_label,
         d.dict_name, d.description, d.sheet, d.sas_name,
         case when a.var_u = upcase(d.sas_name) then 'EXACT'
              else 'SQUASH' end as match_how length=8,
         case when a.var_u = upcase(d.sas_name) then 1
              else 3 end as match_rank
  from work.actual as a
  inner join work.dict_u as d
    on a.var_u = upcase(d.sas_name)
       or compress(a.var_u,'_') = compress(upcase(d.sas_name),'_');
quit;

proc sort data=work.doc_all; by varname match_rank dict_name; run;

data work.doc_vars;
  set work.doc_all;
  by varname;
  if first.varname;
run;

/* Ties at the STRONGEST rank are reported, not silently resolved -- two
   dictionary entries matching one column equally well is a finding.        */
proc sql noprint;
  create table work.match_ties as
  select a.varname, count(*) as n_at_best
  from work.doc_all as a
  inner join work.doc_vars as b
    on a.varname = b.varname and a.match_rank = b.match_rank
  group by a.varname having calculated n_at_best > 1;
  select count(*) into :n_ties trimmed from work.match_ties;
quit;

%macro report_ties;
  %if &n_ties > 0 %then %do;
    %put WARNING: [16] &n_ties columns match two dictionary entries equally well.;
    %put WARNING- The alphabetically first was used. See work.match_ties.;
  %end;
%mend report_ties;
%report_ties;

proc sql;

  select count(*), count(distinct varname)
    into :n_doc trimmed, :n_doc_u trimmed
  from work.doc_vars;
quit;

%macro check_doc;
  %if %length(&n_doc) = 0 %then %do;
    %fail_out(msg=Documented-subset query returned no value);
  %end;
  %else %if &n_doc = 0 %then %do;
    %fail_out(msg=No columns matched the dictionary);
  %end;
  %if &n_doc ne &n_doc_u %then %do;
    %fail_out(msg=&n_doc rows for &n_doc_u variables -- the dictionary join duplicated);
  %end;
  %put NOTE: [16] &n_doc documented variables to summarise.;
%mend check_doc;
%check_doc;

/* The alias IS the label. PROC FREQ and PROC MEANS both print the label, so
   applying it here makes every table in the document carry the documented name
   without touching either procedure.

   CORRECTED. An earlier version wrote the label into DOUBLE quotes and claimed
   no value passed through generated code. Both were wrong: this file IS
   generated code, %INCLUDE-d below, and inside double quotes an & or a % in a
   dictionary description resolves as a macro trigger -- producing a warning at
   best and wrong text at worst.

   SINGLE quotes. Macro triggers are not resolved inside a single-quoted SAS
   literal, so &, % and any punctuation pass through as text. Embedded
   apostrophes are doubled, which is the only escape single quoting needs.   */
data _null_;
  set work.doc_vars end=eof;
  length lbl $200;
  file "%sysfunc(pathname(work))\doc_labels.sas";
  if _n_ = 1 then put "proc datasets library=work nolist nowarn;";
  if _n_ = 1 then put "  modify base_doc;";
  if _n_ = 1 then put "    label";
  /* Documented name, then the stored column name -- which is what the scope
     page says the label contains. An earlier version used sas_label here, a
     label ATTRIBUTE rather than the column name, so the two disagreed.      */
  lbl = catx(' -- ', strip(dict_name), cats('stored: ', strip(varname)));
  /* Double any embedded quote so the generated LABEL statement stays valid */
  /* Double any embedded apostrophe so the single-quoted literal stays valid */
  lbl = tranwrd(strip(lbl), "'", "''");
  put '      ' varname " = '" lbl +(-1) "'";
  if eof then do;
    put "    ;";
    put "quit;";
  end;
run;

proc sql noprint;
  select varname into :keeplist separated by ' ' from work.doc_vars;
quit;

data work.base_doc;
  set g.analysis_base (keep=&keeplist);
run;

%include "%sysfunc(pathname(work))\doc_labels.sas";


/* =========================================================================
   SECTION 2: Classify -- numeric summary, frequency table, or neither
   ========================================================================= */

proc sql;
  create table work.classify
    (varname char(32), vtype char(4), n_distinct num, treatment char(12));
quit;

%macro classify_vars;
  %local i v t nd;
  proc sql noprint;
    select varname into :vlist separated by ' ' from work.doc_vars order by varnum;
    select vtype   into :tlist separated by ' ' from work.doc_vars order by varnum;
  quit;

  %do i = 1 %to &n_doc;
    %let v = %scan(&vlist, &i);
    %let t = %scan(&tlist, &i);
    %let nd = ;
    proc sql noprint;
      select count(distinct &v) into :nd trimmed from work.base_doc;
    quit;
    %if %length(&nd) = 0 %then %do;
      %fail_out(msg=Distinct count failed for &v);
    %end;

    proc sql;
      insert into work.classify values
        ("&v", "&t", &nd,
         %if %upcase(&t) = NUM and &nd > &max_freq_levels %then %do; 'MEANS' %end;
         %else %if &nd > &max_freq_levels %then %do; 'HIGH-CARD' %end;
         %else %do; 'FREQ' %end;);
    quit;
  %end;
%mend classify_vars;
%classify_vars;

proc sql noprint;
  /* Derived, never asserted. An earlier version stated "two aliases" in prose
     while the actual count depended on the data.                            */
  select count(*) into :n_alias trimmed
  from work.doc_vars where upcase(varname) ne upcase(sas_name);
  select count(*) into :n_squash trimmed
  from work.doc_vars where match_how = 'SQUASH';

  select count(*) into :n_means trimmed from work.classify where treatment='MEANS';
  select count(*) into :n_freq  trimmed from work.classify where treatment='FREQ';
  select count(*) into :n_high  trimmed from work.classify where treatment='HIGH-CARD';
  select varname into :meanslist separated by ' ' from work.classify where treatment='MEANS';
  select varname into :freqlist  separated by ' ' from work.classify where treatment='FREQ';
quit;

%put NOTE: [16] &n_means numeric summaries%str(,) &n_freq frequency tables%str(,) &n_high high-cardinality.;


/* =========================================================================
   SECTION 3: The document
   ========================================================================= */

%macro drop_stale;
  %local rc;
  %if %sysfunc(fileexist(%bquote(&docs_path.\DOCUMENTED_VARIABLE_SUMMARY.docx))) %then %do;
    filename _oldd "&docs_path.\DOCUMENTED_VARIABLE_SUMMARY.docx";
    %let rc = %sysfunc(fdelete(_oldd));
    filename _oldd clear;
    %if &rc ne 0 %then %do;
      %fail_out(msg=Could not delete the previous document -- rc=&rc. It may be open in Word.);
    %end;
  %end;
%mend drop_stale;
%drop_stale;

ods listing close;
ods word file="&docs_path.\DOCUMENTED_VARIABLE_SUMMARY.docx"
         options(contents="on" toc_data="on");

ods proclabel "Contents and Scope";
title justify=left color=CX0021A5 height=16pt "PeCAN -- Documented Variable Summary";
title2 justify=left height=11pt "g.analysis_base -- &n_rows records, &n_doc documented variables";
title3 justify=left height=9pt  "Generated %sysfunc(datetime(), datetime20.)";

data work.scope;
  length item $34 detail $250;
  item="Source";     detail="g.analysis_base -- master_data_3 with _30_DAY_MORTALITY joined from master_data_1"; output;
  item="Records";    detail="&n_rows, one per PRECEDE_STUDY_ID"; output;
  item="Variables";  detail="&n_doc, being every column the PRECEDE data dictionary documents"; output;
  item="Variable names"; detail="Each table is titled with the DOCUMENTED name followed by the column name as stored, so a reader holding the dictionary can find the variable either way"; output;
    item="Aliases";    detail="&n_alias variables are stored under a name differing from the documented one; &n_squash matched only after underscores were removed and are worth reviewing. The Variable Index lists every one"; output;
  item="ISO/SEV";    detail="Stored as ISO_SEV_Exp_IntraOp_MAC_Average. The dictionary documents ISO_SEV_IntraOp_MAC_Average, a master_data_4 column. Phase 10 found the two identical on all 7,695 overlapping records -- a dated finding from that phase, not recomputed here"; output;
  item="Numeric summaries"; detail="&n_means variables -- N, missing, mean, standard deviation, minimum, quartiles, median, maximum"; output;
  item="Frequency tables";  detail="&n_freq variables with &max_freq_levels or fewer distinct values, missing shown"; output;
  item="High cardinality";  detail="&n_high variables above that threshold -- distinct counts only, since a frequency table of several thousand levels is not a summary"; output;
  item="NOT INCLUDED";      detail="Cognitive_Score, Frailty_Score, the five frailty components and the hemodynamic block. None appears in the dictionary sheets that matched, so none is in this file. An analysis needing them must use g.master_data_merged, where Cognitive_Score has 8,412 more values than master_data_3 holds alone"; output;
  item="Missing values";    detail="Reported throughout. A blank is not read as a negative anywhere in this document"; output;
run;

proc report data=work.scope nowd
    style(header)=[background=CX0021A5 color=white fontweight=bold]
    style(column)=[fontsize=9pt];
  columns item detail;
  define item   / display "Item"   style(column)=[width=1.6in fontweight=bold];
  define detail / display "Detail" style(column)=[width=4.9in];
run;

/* ---- Variable index: documented name against stored name ---- */
ods proclabel "Variable Index";
title justify=left color=CX0021A5 height=13pt "Variable Index";
title2 justify=left height=9pt "Documented name, stored column name, and how the two were matched";

proc sql;
  create table work.index_tbl as
  select d.dict_name  as documented_name length=60,
         d.varname    as stored_name     length=32,
         d.match_how,
         c.treatment,
         c.n_distinct,
         d.sheet      as dict_sheet      length=40
  from work.doc_vars as d
  inner join work.classify as c on c.varname = d.varname
  order by documented_name;
quit;

proc report data=work.index_tbl nowd
    style(header)=[background=CX0021A5 color=white fontweight=bold]
    style(column)=[fontsize=8pt];
  columns documented_name stored_name match_how treatment n_distinct dict_sheet;
  define documented_name / display "Documented Name" style(column)=[width=1.9in];
  define stored_name     / display "Stored As"       style(column)=[width=1.6in];
  define match_how       / display "Match"           style(column)=[width=0.6in];
  define treatment       / display "Summary"         style(column)=[width=0.7in];
  define n_distinct      / display "Distinct"        style(column)=[width=0.6in];
  define dict_sheet      / display "Dictionary Sheet" style(column)=[width=1.2in];
run;

/* ---- Numeric summaries ---- */
%macro numeric_section;
  %if &n_means = 0 %then %do;
    %put NOTE: [16] no numeric variables above the frequency threshold.;
    %return;
  %end;
  ods proclabel "Numeric Variables";
  title justify=left color=CX0021A5 height=13pt "Numeric Variables";
  title2 justify=left height=9pt "Each row is labelled with its documented name. N Miss counts records with no value.";

  proc means data=work.base_doc n nmiss mean std min p25 median p75 max maxdec=2 stackodsoutput;
    var &meanslist;
    ods output summary=work.means_out;
  run;

  /* The ODS column names depend on the SAS release -- the standard-deviation
     column is StdDev in some and Std in others, and a PROC REPORT COLUMNS list
     naming one that is absent fails with "Variable not found". Build the list
     from what the table ACTUALLY contains rather than from an assumption.   */
  %local statlist;
  %let statlist = ;
  proc sql noprint;
    select name into :statlist separated by ' '
    from dictionary.columns
    where libname='WORK' and upcase(memname)='MEANS_OUT'
      and upcase(name) in ('N','NMISS','MEAN','STDDEV','STD','MIN','P25',
                           'MEDIAN','P75','MAX')
    order by varnum;
  quit;

  %if %length(&statlist) = 0 %then %do;
    %fail_out(msg=No recognised statistic columns in work.means_out);
  %end;

  /* Attach the documented name explicitly. STACKODSOUTPUT puts the stored name
     in Variable; relying on an ODS Label column would be another
     release-dependent assumption, and this join is certain.                 */
  proc sql;
    create table work.means_rpt as
    select d.dict_name as documented_name length=60,
           m.*
    from work.means_out as m
    inner join work.doc_vars as d on upcase(d.varname) = upcase(m.Variable)
    order by documented_name;
  quit;

  proc report data=work.means_rpt nowd
      style(header)=[background=CX0021A5 color=white fontweight=bold]
      style(column)=[fontsize=8pt];
    columns documented_name Variable &statlist;
    define documented_name / display "Documented Name" style(column)=[width=1.9in];
    define Variable        / display "Stored As"       style(column)=[width=1.6in];
  run;
  title; title2;
%mend numeric_section;
%numeric_section;

/* ---- Frequency tables ---- */
%macro freq_section;
  %if &n_freq = 0 %then %do;
    %put NOTE: [16] no variables qualify for a frequency table.;
    %return;
  %end;
  ods proclabel "Categorical Variables";
  title justify=left color=CX0021A5 height=13pt "Categorical Variables";
  title2 justify=left height=9pt "Missing shown as a level throughout. A blank is not read as a negative.";

  proc freq data=work.base_doc;
    tables &freqlist / missing nocum;
  run;
  title; title2;
%mend freq_section;
%freq_section;

/* ---- High-cardinality ---- */
%macro highcard_section;
  %if &n_high = 0 %then %do;
    %return;
  %end;
  ods proclabel "High-Cardinality Variables";
  title justify=left color=CX0021A5 height=13pt "High-Cardinality Variables";
  title2 justify=left height=9pt "Above &max_freq_levels distinct values. Counts only -- a frequency table of this many levels is not a summary.";

  proc sql;
    create table work.high_tbl as
    select d.dict_name as documented_name length=60,
           c.varname   as stored_name     length=32,
           c.vtype, c.n_distinct
    from work.classify as c
    inner join work.doc_vars as d on d.varname = c.varname
    where c.treatment = 'HIGH-CARD'
    order by c.n_distinct desc;
  quit;

  proc report data=work.high_tbl nowd
      style(header)=[background=CX0021A5 color=white fontweight=bold]
      style(column)=[fontsize=8pt];
    columns documented_name stored_name vtype n_distinct;
    define documented_name / display "Documented Name" style(column)=[width=2.4in];
    define stored_name     / display "Stored As"       style(column)=[width=2.0in];
    define vtype           / display "Type"            style(column)=[width=0.6in];
    define n_distinct      / display "Distinct Values" style(column)=[width=1.0in];
  run;
  title; title2;
%mend highcard_section;
%highcard_section;

ods word close;
ods listing;
title;

%macro check_docx;
  %if %sysfunc(fileexist(%bquote(&docs_path.\DOCUMENTED_VARIABLE_SUMMARY.docx))) = 0 %then %do;
    %fail_out(msg=DOCUMENTED_VARIABLE_SUMMARY.docx was not written. If this release lacks ODS WORD, switch the two ODS statements to ODS RTF.);
  %end;
  %put NOTE: [16] document written.;
%mend check_docx;
%check_docx;


/* =========================================================================
   SECTION 4: QC artifact
   ========================================================================= */

data _null_;
  file "&qc_path.\16_summary_docx.txt";
  put "16_summary_docx -- Run: %sysfunc(datetime(), datetime20.)";
  put "=======================================================================";
  put " ";
  put "source=g.analysis_base";
  put "records=&n_rows";
  put "documented_variables=&n_doc";
  put "numeric_summaries=&n_means";
  put "frequency_tables=&n_freq";
  put "high_cardinality=&n_high";
  put "frequency_level_ceiling=&max_freq_levels";
  put " ";
  put "ALIASES. Every table carries the DOCUMENTED name, so a reader holding the";
  put "PRECEDE dictionary finds the variable under the name they know.";
  put "aliases_differing_from_stored_name=&n_alias   (derived this run, not assumed)";
  put "squash_matches=&n_squash   (matched only after removing underscores -- review)";
  put "match_ties=&n_ties";
  put " ";
  put "The ISO/SEV mapping is a PRIOR FINDING, not measured here: the dictionary";
  put "documents ISO_SEV_IntraOp_MAC_Average, a master_data_4 column, and Phase 10";
  put "found it identical to this file column on all 7,695 overlapping records.";
  put "That figure is dated evidence from Phase 10 and is not recomputed by this";
  put "program -- re-verify it if the extracts are ever refreshed.";
  put " ";
  put "SCOPE BOUNDARY. This covers the documented subset only. Cognitive_Score,";
  put "Frailty_Score, the frailty components and the hemodynamic block are NOT in";
  put "g.analysis_base -- none appears in the dictionary sheets that matched. An";
  put "analysis needing them must use g.master_data_merged, where Cognitive_Score";
  put "carries 8,412 more values than master_data_3 holds alone. Both files look";
  put "complete in isolation, which is why this is stated in the document itself.";
run;

%put NOTE: ==== Document complete ====;
%put NOTE- docs/DOCUMENTED_VARIABLE_SUMMARY.docx;

%restore_log;
