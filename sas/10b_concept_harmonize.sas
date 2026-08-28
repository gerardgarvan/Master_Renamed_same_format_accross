/*==========================================================================
  Program : 10b_concept_harmonize.sas
  Phase   : 10 -- Concept Harmonization, Part 2 of 2 (ACTION)
  Purpose : Read the completed decision file and create standardized columns for
            the concepts a human has CONFIRMED. Produces g.master_data_harmonized.

  Requirements addressed
    CON-05  Only rows marked CONFIRMED=YES are acted on
    CON-06  No source column is ever MODIFIED. Harmonized values land in NEW h_
            prefixed columns. A source column is DROPPED from the harmonized
            output only when this program has PROVEN, in this run and on this
            data, that it is redundant: a strict subset of a higher-priority
            source AND in complete agreement with it wherever both are present.
            g.master_data_merged is untouched, so any drop is reversible by
            re-running. Set DROP_REDUNDANT=0 to keep everything.
    CON-07  Every mapping is value-level and explicit. An unmapped source value,
            a duplicate rule, or a conflicting target is a HARD FAILURE
    CON-08  Provenance: h_*_src records which source supplied the value per row
    CON-09  Row count unchanged; key still unique; source columns unchanged in
            type and length (asserted, not merely claimed)

  Reads   : g.master_data_merged        (read-only)
            docs/concept_decisions.csv  (human-completed)
  Writes  : g.master_data_harmonized
            qc/10b_harmonize_report.txt

  Author  : 2026-08-27
  Revised : 2026-08-27 after review. The previous version was NOT RUNNABLE and
            made a promise it did not keep. Corrections:

    1. PROC SQL was invoked INSIDE the open output DATA step (via %emit_rules).
       A PROC terminates the active DATA step, so every generated IF landed in
       open code. ALL rule metadata is now extracted BEFORE the DATA step opens,
       into indexed macro variables, and the DATA step contains no procedure.
    2. harmonized_name was never validated. A reviewer entering the name of an
       existing column would have had it cleared by `call missing(&h, ...)` --
       directly breaking the originals-are-never-touched guarantee. The name must
       now start with h_, be a valid SAS name of 28 characters or fewer, and not
       collide with any existing column.
    3. The header claimed ties were a hard failure. No tie check existed, and the
       template had no priority column, so every source tied and ALPHABETICAL
       ORDER silently decided the winner. Priority is now in the template, and a
       tie between two different source columns aborts.
    4. n_rows was queried in the same PROC SQL that checked whether the table
       existed, so an absent table produced an SQL error before the intended gate.
    5. SET preceded LENGTH, so PROC IMPORT decided the types.
    6. Duplicate and conflicting mappings were accepted silently -- whichever rule
       ran first won, because each rule tests `if missing(&hname)`.
    7. Rules were carried in pipe-delimited macro lists, so a value containing a
       pipe, quote, ampersand or percent sign would break the generated code.
       Rules now travel in indexed macro variables, and unsafe values abort.
    8. Numeric values were rendered `strip(&v)` here but `put(&v,best12.)` in the
       profiler, so numeric coverage checks could fail on correct data.

  PCM compliance: no bare open-code %IF, no apostrophes or embedded semicolons in
  %PUT, every %abort inside a macro, no &SQLOBS, IS NOT MISSING only in SQL.
==========================================================================*/

options mprint nofmterr nodate nonumber ps=max ls=200;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\10b_harmonize.log" new;
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

%put NOTE: ==== Phase 10b Harmonization starting ====;


/* =========================================================================
   SECTION 0: Preconditions -- ordered so each gate runs before the query that
   depends on it. Previously n_rows was read from a table that might not exist.
   ========================================================================= */

%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %fail_out(msg=&label directory not found: &path);
  %end;
%mend check_dir;
%check_dir(path=&docs_path, label=docs);
%check_dir(path=&qc_path,   label=qc);

%macro check_decisions_file;
  %if %sysfunc(fileexist(%bquote(&docs_path.\concept_decisions.csv))) = 0 %then %do;
    %put ERROR: docs/concept_decisions.csv not found.;
    %put ERROR- Run 10_concept_profile.sas, complete the TEMPLATE it writes, and;
    %put ERROR- save it as concept_decisions.csv. This program applies decisions;
    %put ERROR- rather than making them, so it cannot proceed without that file.;
    %fail_out(msg=Decision file missing);
  %end;
%mend check_decisions_file;
%check_decisions_file;

/* Gate on existence FIRST, in its own step */
proc sql noprint;
  select count(*) into :n_tab trimmed
  from dictionary.tables where libname='G' and memname='MASTER_DATA_MERGED';
quit;

%macro check_src_exists;
  %if &n_tab ne 1 %then %do;
    %fail_out(msg=g.master_data_merged not found -- run Phase 4 first);
  %end;
%mend check_src_exists;
%check_src_exists;

/* Only now is it safe to read the table */
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
  %put NOTE: [10b] &n_rows rows in the merged file.;
%mend check_rows;
%check_rows;


/* =========================================================================
   SECTION 1: Read the decision file
   ========================================================================= */

proc import datafile="&docs_path.\concept_decisions.csv"
    out=work.dec_raw dbms=csv replace;
  guessingrows=max;
run;

/* Required headers must be present BEFORE the RENAME= below touches them. A
   reviewer who deletes or renames a column would otherwise get SAS complaining
   about an unknown variable in a RENAME clause -- accurate, but it does not say
   which column is missing or that the decision file is the cause.

   The required list is built in a DATA step, NOT as SELECT literals joined by
   UNION ALL: SAS PROC SQL requires a FROM clause, so a bare SELECT of constants
   is a syntax error. That error is also why this gate silently did nothing on
   the first run -- the query failed, n_hdr_missing never resolved, and the %IF
   testing it errored out INSIDE the macro, so %fail_out was never reached and
   the program carried on past a broken gate.                                  */
data work.req_hdr;
  length hdr $20;
  infile datalines truncover;
  input hdr $20.;
  datalines;
CONCEPT
VARNAME
VALUE_TXT
TARGET_VALUE
CONFIRMED
HARMONIZED_NAME
;
run;

proc sql noprint;
  create table work.hdr_missing as
  select hdr from work.req_hdr
  where hdr not in (select upcase(name) from dictionary.columns
                    where libname='WORK' and upcase(memname)='DEC_RAW');
  select count(*) into :n_hdr_missing trimmed from work.hdr_missing;
quit;

%macro check_headers;
  /* %LENGTH first. If the query above ever fails again, n_hdr_missing is unset
     and `%if &n_hdr_missing > 0` is a macro error rather than a clean failure --
     which is exactly how this gate came to be skipped without anyone noticing. */
  %if %length(&n_hdr_missing) = 0 %then %do;
    %fail_out(msg=Header check did not run -- n_hdr_missing is unset);
  %end;
  %else %if &n_hdr_missing > 0 %then %do;
    %local hdr_list;
    proc sql noprint;
      select hdr into :hdr_list separated by ', ' from work.hdr_missing;
    quit;
    %put ERROR: concept_decisions.csv is missing required columns: &hdr_list;
    %put ERROR- Re-export the template from 10_concept_profile.sas and complete it;
    %put ERROR- without removing or renaming any header.;
    %fail_out(msg=Decision file is missing required columns);
  %end;
  %put NOTE: [10b] all six required headers present.;
%mend check_headers;
%check_headers;

/* Does the CSV carry a priority column? A file produced by an older template
   will not, and referencing a non-existent variable is a compile error rather
   than a missing value.                                                      */
proc sql noprint;
  select count(*) into :has_prio trimmed
  from dictionary.columns
  where libname='WORK' and upcase(memname)='DEC_RAW' and upcase(name)='PRIORITY';
quit;

%macro read_decisions;
  /* LENGTH before SET, with every field renamed on the way in, so PROC IMPORT's
     guessed types and widths never reach the working copy. CATS is used for the
     assignments because it accepts a character OR numeric argument -- PROC
     IMPORT can type a sparse text column as numeric.                         */
  data work.decisions;
    length concept $32 varname $32 value_txt $60 target_value $40
           confirmed $3 harmonized_name $32 priority 8 priority_invalid 8;
    set work.dec_raw (rename=(concept=_c varname=_v value_txt=_x
                              target_value=_t confirmed=_f harmonized_name=_h
    %if &has_prio = 1 %then %do; priority=_p %end;
    ));
    concept         = upcase(strip(cats(_c)));
    varname         = strip(cats(_v));
    value_txt       = strip(cats(_x));
    target_value    = strip(cats(_t));
    confirmed       = upcase(strip(cats(_f)));
    /* UPCASE. SAS variable names are case-insensitive, so h_Death and H_DEATH are
       ONE variable -- but count(distinct harmonized_name) would see two, emit two
       LENGTH declarations for the same column, and interleave their rules.     */
    harmonized_name = upcase(strip(cats(_h)));
  %if &has_prio = 1 %then %do;
    /* A BLANK priority reasonably defaults to 1. Text that is not a number does
       NOT -- an entry of HIGH would otherwise be read as priority 1 and the
       reviewer would never know their intent was discarded. Flagged here and
       rejected in SECTION 2.                                                  */
    if not missing(cats(_p)) then do;
      priority = input(cats(_p), ?? best32.);
      if missing(priority) then priority_invalid = 1;
      else if priority < 1 or priority ne int(priority) then priority_invalid = 1;
    end;
    else priority = 1;
  %end;
    if missing(priority) and priority_invalid ne 1 then priority = 1;
    if missing(priority_invalid) then priority_invalid = 0;
    keep concept varname value_txt target_value confirmed harmonized_name
         priority priority_invalid;
  run;

  %if &has_prio = 0 %then %do;
    %put WARNING: [10b] concept_decisions.csv has no priority column.;
    %put WARNING- Every source defaults to priority 1. If any concept has more than;
    %put WARNING- one source column, the tie gate in SECTION 2 will fail the run --;
    %put WARNING- which is correct: the reviewer, not alphabetical order, decides.;
  %end;
%mend read_decisions;
%read_decisions;

proc sql noprint;
  select count(*) into :n_dec trimmed from work.decisions;
  select count(*) into :n_yes trimmed from work.decisions where confirmed='YES';
  select count(distinct concept) into :n_con_yes trimmed
    from work.decisions where confirmed='YES';
quit;

%macro check_decisions;
  %if &n_dec = 0 %then %do;
    %fail_out(msg=concept_decisions.csv has no rows);
  %end;
  %if &n_yes = 0 %then %do;
    %put ERROR: No rows are marked CONFIRMED=YES in concept_decisions.csv.;
    %put ERROR- Nothing to harmonize. That is not a data failure -- it means the;
    %put ERROR- evidence has not been reviewed, or nothing was confirmed.;
    %fail_out(msg=No confirmed concepts);
  %end;
  %put NOTE: [10b] &n_yes confirmed mappings across &n_con_yes concepts.;
%mend check_decisions;
%check_decisions;


/* =========================================================================
   SECTION 2: Validate the decision file -- every check below is a HARD gate
   ========================================================================= */

proc sql noprint;
  /* (a) confirmed rows must be complete */
  select count(*) into :v_incomplete trimmed
  from work.decisions
  where confirmed='YES' and (missing(target_value) or missing(harmonized_name));

  /* (b) harmonized_name must be h_ prefixed, valid, and short enough for _src */
  create table work.bad_name as
  select distinct harmonized_name
  from work.decisions
  where confirmed='YES'
    and ( upcase(substr(harmonized_name,1,2)) ne 'H_'
          or length(harmonized_name) > 28
          or nvalid(harmonized_name,'V7') = 0 );
  select count(*) into :v_badname trimmed from work.bad_name;

  /* (c) harmonized_name must NOT collide with an existing column. Without this
         the call missing() below would clear an original -- the exact thing
         CON-06 promises never happens. */
  create table work.name_collision as
  select distinct d.harmonized_name
  from work.decisions as d
  where d.confirmed='YES'
    and ( upcase(d.harmonized_name) in
            (select upcase(name) from dictionary.columns
             where libname='G' and memname='MASTER_DATA_MERGED')
       or upcase(cats(d.harmonized_name,'_SRC')) in
            (select upcase(name) from dictionary.columns
             where libname='G' and memname='MASTER_DATA_MERGED') );
  select count(*) into :v_collide trimmed from work.name_collision;

  /* (d) one concept must resolve to exactly one harmonized column */
  create table work.multi_name as
  select concept, count(distinct harmonized_name) as n_names
  from work.decisions where confirmed='YES'
  group by concept having calculated n_names > 1;
  select count(*) into :v_multiname trimmed from work.multi_name;

  /* (e) every confirmed source column must exist */
  create table work.missing_var as
  select distinct varname from work.decisions
  where confirmed='YES'
    and upcase(varname) not in (select upcase(name) from dictionary.columns
                                where libname='G' and memname='MASTER_DATA_MERGED');
  select count(*) into :v_novar trimmed from work.missing_var;

  /* (f) one source value must not map to two different targets */
  create table work.conflict_map as
  select harmonized_name, varname, value_txt,
         count(distinct target_value) as n_targets
  from work.decisions where confirmed='YES'
  group by harmonized_name, varname, value_txt
  having calculated n_targets > 1;
  select count(*) into :v_conflict trimmed from work.conflict_map;

  /* (g) a source column must carry ONE priority, not several */
  create table work.multi_prio as
  select harmonized_name, varname, count(distinct priority) as n_prio
  from work.decisions where confirmed='YES'
  group by harmonized_name, varname
  having calculated n_prio > 1;
  select count(*) into :v_multiprio trimmed from work.multi_prio;

  /* (h) two DIFFERENT source columns must not share a priority. The header used
         to claim ties were a hard failure; they were not, and alphabetical order
         silently decided the winner. */
  create table work.prio_tie as
  select harmonized_name, priority, count(distinct varname) as n_vars
  from work.decisions where confirmed='YES'
  group by harmonized_name, priority
  having calculated n_vars > 1;
  select count(*) into :v_tie trimmed from work.prio_tie;

  /* (i) exact duplicate rules. The header claims duplicates are a hard failure;
         gate (f) only caught the same source value mapping to DIFFERENT targets,
         so two identical rows passed and were applied twice.                   */
  create table work.duplicate_rule as
  select harmonized_name, varname, value_txt, target_value, priority, count(*) as n
  from work.decisions where confirmed='YES'
  group by harmonized_name, varname, value_txt, target_value, priority
  having calculated n > 1;
  select count(*) into :v_duplicate trimmed from work.duplicate_rule;

  /* (j) two concepts must not target the same harmonized column -- their rules
         would silently interleave under one name.                              */
  create table work.multi_concept as
  select harmonized_name, count(distinct concept) as n_concepts
  from work.decisions where confirmed='YES'
  group by harmonized_name
  having calculated n_concepts > 1;
  select count(*) into :v_multiconcept trimmed from work.multi_concept;

  /* (k) partial confirmation within a concept. If a reviewer confirms every value
         of one source column but leaves a second source blank, that second source
         is silently dropped and the coverage gate never examines it. Confirmation
         is CONCEPT-level: a confirmed concept must have every one of its template
         rows marked.                                                            */
  create table work.partial_confirm as
  select concept,
         sum(confirmed='YES') as n_yes,
         count(*)             as n_rows_in_concept
  from work.decisions
  group by concept
  having calculated n_yes > 0 and calculated n_yes < calculated n_rows_in_concept;
  select count(*) into :v_partial trimmed from work.partial_confirm;

  /* (l) priority entries that are not positive integers. A blank defaults to 1;
         text such as HIGH does not, or the reviewer's intent is silently lost. */
  create table work.bad_priority as
  select distinct concept, varname, value_txt
  from work.decisions where confirmed='YES' and priority_invalid = 1;
  select count(*) into :v_badprio trimmed from work.bad_priority;

  /* (m) values that cannot be carried safely into generated code */
  create table work.unsafe_val as
  select distinct varname, value_txt, target_value
  from work.decisions where confirmed='YES'
    and ( index(value_txt,'22'x)>0 or index(value_txt,'&')>0 or index(value_txt,'%')>0
       or index(target_value,'22'x)>0 or index(target_value,'&')>0 or index(target_value,'%')>0 );
  select count(*) into :v_unsafe trimmed from work.unsafe_val;
quit;

%macro validate_decisions;
  %local bad;
  %let bad = 0;
  %if &v_incomplete > 0 %then %do;
    %put ERROR: &v_incomplete confirmed rows lack target_value or harmonized_name.;
    %let bad = 1;
  %end;
  %if &v_badname > 0 %then %do;
    %put ERROR: &v_badname harmonized names are invalid. A name must start with h_%str(,);
    %put ERROR- be a valid SAS V7 name%str(,) and be 28 characters or fewer so that the;
    %put ERROR- h_*_src companion fits within the 32-character limit. See work.bad_name.;
    %let bad = 1;
  %end;
  %if &v_collide > 0 %then %do;
    %put ERROR: &v_collide harmonized names collide with an existing column.;
    %put ERROR- Writing there would CLEAR an original value. Source columns are never;
    %put ERROR- modified -- pick a new name. See work.name_collision.;
    %let bad = 1;
  %end;
  %if &v_multiname > 0 %then %do;
    %put ERROR: &v_multiname concepts map to more than one harmonized column. See work.multi_name.;
    %let bad = 1;
  %end;
  %if &v_novar > 0 %then %do;
    %put ERROR: &v_novar confirmed source columns are absent from the merged file. See work.missing_var.;
    %let bad = 1;
  %end;
  %if &v_conflict > 0 %then %do;
    %put ERROR: &v_conflict source values map to more than one target value. See work.conflict_map.;
    %let bad = 1;
  %end;
  %if &v_multiprio > 0 %then %do;
    %put ERROR: &v_multiprio source columns carry more than one priority. See work.multi_prio.;
    %let bad = 1;
  %end;
  %if &v_tie > 0 %then %do;
    %put ERROR: &v_tie priority ties -- two different source columns share a priority.;
    %put ERROR- Which one wins would then be decided by alphabetical order rather than;
    %put ERROR- by the reviewer. Assign distinct priorities. See work.prio_tie.;
    %let bad = 1;
  %end;
  %if &v_duplicate > 0 %then %do;
    %put ERROR: &v_duplicate exact duplicate rules. The same value would be applied twice.;
    %put ERROR- See work.duplicate_rule.;
    %let bad = 1;
  %end;
  %if &v_multiconcept > 0 %then %do;
    %put ERROR: &v_multiconcept harmonized columns are targeted by more than one concept.;
    %put ERROR- Their rules would interleave under one name. See work.multi_concept.;
    %let bad = 1;
  %end;
  %if &v_partial > 0 %then %do;
    %put ERROR: &v_partial concepts are only PARTIALLY confirmed -- some template rows;
    %put ERROR- are marked YES and others are blank. A blank row means that source is;
    %put ERROR- silently excluded and the coverage gate never checks it. Confirmation;
    %put ERROR- is concept-level: mark every row of a confirmed concept, or none.;
    %put ERROR- See work.partial_confirm.;
    %let bad = 1;
  %end;
  %if &v_badprio > 0 %then %do;
    %put ERROR: &v_badprio confirmed rows have a priority that is not a positive integer.;
    %put ERROR- A blank priority defaults to 1%str(,) but text such as HIGH does not --;
    %put ERROR- reading it as 1 would discard the reviewer intent silently.;
    %put ERROR- See work.bad_priority.;
    %let bad = 1;
  %end;
  %if &v_unsafe > 0 %then %do;
    %put ERROR: &v_unsafe values contain a quote%str(,) ampersand or percent sign.;
    %put ERROR- A rule cannot be generated from those safely. See work.unsafe_val.;
    %let bad = 1;
  %end;
  %if &bad = 1 %then %do;
    %fail_out(msg=Decision file failed validation -- see the ERROR lines above);
  %end;
  %put NOTE: [10b] decision file passed all thirteen validation gates.;
%mend validate_decisions;
%validate_decisions;


/* =========================================================================
   SECTION 3: Coverage -- every OBSERVED value must be mapped
   -------------------------------------------------------------------------
   An unmapped value would become silently missing in the harmonized column.
   Numeric columns are rendered with put(&v,best12.), matching the profiler
   exactly -- a mismatch here would fail coverage on correct data.
   ========================================================================= */

proc sql;
  create table work.unmapped (varname char(32), value_txt char(60), n_rows num);
quit;

%macro check_coverage;
  %local i v t n_un;
  proc sql noprint;
    select count(distinct varname) into :n_cv trimmed
      from work.decisions where confirmed='YES';
    select distinct varname into :cvlist separated by ' '
      from work.decisions where confirmed='YES';
  quit;

  %do i = 1 %to &n_cv;
    %let v = %scan(&cvlist, &i);
    proc sql noprint;
      select type into :t trimmed from dictionary.columns
      where libname='G' and memname='MASTER_DATA_MERGED' and upcase(name)=%upcase("&v");
    quit;
    proc sql;
      insert into work.unmapped
      select "&v",
             %if %upcase(&t) = CHAR %then %do; strip(&v) %end;
             %else %do; strip(put(&v, best12.)) %end;,
             count(*)
      from g.master_data_merged
      where not missing(&v)
        and %if %upcase(&t) = CHAR %then %do; strip(&v) %end;
            %else %do; strip(put(&v, best12.)) %end;
            not in (select value_txt from work.decisions
                    where confirmed='YES' and varname="&v")
      group by %if %upcase(&t) = CHAR %then %do; strip(&v) %end;
               %else %do; strip(put(&v, best12.)) %end;;
    quit;
  %end;

  proc sql noprint;
    select count(*) into :n_un trimmed from work.unmapped;
  quit;

  %if &n_un > 0 %then %do;
    %put ERROR: &n_un observed values are not mapped in the decision file.;
    %put ERROR- An unmapped value would become silently missing in the harmonized;
    %put ERROR- column. Map them, or mark the concept unconfirmed. See work.unmapped.;
    %fail_out(msg=Unmapped source values);
  %end;
  %put NOTE: [10b] every observed value of every confirmed column is mapped.;
%mend check_coverage;
%check_coverage;


/* =========================================================================
   SECTION 4: Extract ALL rule metadata BEFORE the DATA step opens
   -------------------------------------------------------------------------
   This is the correction that makes the program runnable. The previous version
   ran PROC SQL from inside the open DATA step, which terminated it and threw
   every generated IF into open code.

   Rules travel in INDEXED macro variables rather than a delimited list, so a
   value containing a delimiter cannot split a rule. (Values containing quotes,
   ampersands or percent signs were already rejected in SECTION 2.)
   ========================================================================= */

proc sql noprint;
  create table work.rules as
  select d.harmonized_name, d.varname, d.value_txt, d.target_value, d.priority,
         c.type as vtype length=4
  from work.decisions as d
  inner join (select upcase(name) as nm, type from dictionary.columns
              where libname='G' and memname='MASTER_DATA_MERGED') as c
    on upcase(d.varname) = c.nm
  where d.confirmed='YES'
  order by harmonized_name, priority, varname, value_txt;
quit;

data _null_;
  set work.rules end=eof;
  call symputx(cats('r_h_',  _n_), harmonized_name, 'G');
  call symputx(cats('r_v_',  _n_), varname,         'G');
  call symputx(cats('r_sv_', _n_), value_txt,       'G');
  call symputx(cats('r_tv_', _n_), target_value,    'G');
  call symputx(cats('r_t_',  _n_), vtype,           'G');
  if eof then call symputx('n_rules', _n_, 'G');
run;

proc sql noprint;
  select distinct harmonized_name into :hnames separated by ' ' from work.rules;
  select count(distinct harmonized_name) into :n_h trimmed from work.rules;
  /* Floor of 40. Without it, a run whose targets are all Y and N would declare
     the harmonized column $1, and any later assignment of a longer label would
     truncate silently. 40 matches the target_value width in the decision file. */
  select max(40, max(length(target_value))) into :max_tv trimmed from work.rules;
quit;

%macro check_rules;
  %if %length(&n_rules) = 0 %then %do;
    %fail_out(msg=No rules extracted -- work.rules is empty);
  %end;
  %put NOTE: [10b] &n_rules rules across &n_h harmonized columns.;
%mend check_rules;
%check_rules;


/* =========================================================================
   SECTION 4b: PROVE redundancy before dropping anything
   -------------------------------------------------------------------------
   Phase 10 profiling found that for every confirmed concept the lower-priority
   source is a STRICT SUBSET of the higher-priority one and agrees with it
   completely -- so it carries no information its partner lacks, and the _src
   columns confirmed it never once supplied a value.

   Those columns are dropped from the harmonized output. But NOT on the strength
   of that finding: redundancy is re-proven here, on this data, in this run. A
   column is droppable only when BOTH hold:

     (a) rows where it is populated and the priority-1 source is NOT  =  0
     (b) rows where both are populated and their MAPPED values differ =  0

   Test (b) compares mapped values, not raw ones. Feels_Exausted holds YES/NO and
   Feels_Exausted_Value holds 1/0 -- comparing those raw would report total
   disagreement between two columns that agree perfectly.

   A column failing either test is KEPT and reported. Nothing is dropped on trust.
   ========================================================================= */

/* Set to 0 to keep every source column in the harmonized output. */
%let drop_redundant = 1;

proc sql;
  create table work.redundancy
    (harmonized_name char(32), varname char(32), primary_var char(32),
     n_would_add num, n_disagree num, verdict char(12));
quit;

%global n_sec;
%let n_sec = 0;

%macro prove_redundancy;
  %local i hn sv pv sv_t pv_t;

  /* Two plain steps rather than one correlated subquery. An earlier version used
     a LIBREF-QUALIFIED outer reference, which SAS rejects; the query failed,
     n_sec went unset, and the gate reported zero as though it had run.       */
  proc sql noprint;
    create table work.minpri as
    select harmonized_name, min(priority) as pri
    from work.rules group by harmonized_name;

    create table work.primary_src as
    select distinct r.harmonized_name, r.varname as primary_var
    from work.rules as r
    inner join work.minpri as m
      on r.harmonized_name = m.harmonized_name and r.priority = m.pri;

    create table work.secondary as
    select distinct r.harmonized_name, r.varname, p.primary_var
    from work.rules as r
    inner join work.primary_src as p on r.harmonized_name = p.harmonized_name
    where r.varname ne p.primary_var;

    select count(*) into :n_sec trimmed from work.secondary;
  quit;

  %if %length(&n_sec) = 0 %then %do;
    %fail_out(msg=Redundancy setup failed -- n_sec is unset. See the SQL errors above.);
  %end;
  %else %if &n_sec = 0 %then %do;
    %put NOTE: [10b] no secondary sources -- nothing is a drop candidate.;
    %return;
  %end;
  %put NOTE: [10b] &n_sec secondary sources to test for redundancy.;

  %do i = 1 %to &n_sec;
    /* FIRSTOBS=/OBS=, not POINT=. POINT= takes a VARIABLE NAME, so point=&i
       resolves to a literal and SAS reports "Expecting a name".             */
    data _null_;
      set work.secondary (firstobs=&i obs=&i);
      call symputx('hn', harmonized_name, 'L');
      call symputx('sv', varname, 'L');
      call symputx('pv', primary_var, 'L');
    run;

    /* Types come from work.rules, which carries vtype from dictionary.columns.
       They decide how a stored value is rendered as text, and that rendering
       MUST match the one used by the profiler and the coverage gate:
       strip(x) for character, strip(put(x,best12.)) for numeric.            */
    %let sv_t = ;
    %let pv_t = ;
    proc sql noprint;
      select distinct vtype into :sv_t trimmed from work.rules
        where harmonized_name = "&hn" and varname = "&sv";
      select distinct vtype into :pv_t trimmed from work.rules
        where harmonized_name = "&hn" and varname = "&pv";
    quit;

    %if %length(&sv_t) = 0 or %length(&pv_t) = 0 %then %do;
      %fail_out(msg=Could not determine the type of &sv or &pv for &hn);
    %end;

    %let nadd = ;
    %let ndis = ;

    /* (a) would this column ever contribute a row the primary lacks?
       (b) where both are populated, do their MAPPED values ever differ?

       Both are plain queries, and the mapped comparison is an INNER JOIN to
       work.rules rather than a correlated subquery calling VVALUE(). VVALUE is
       a DATA STEP function: in PROC SQL it does not resolve, so both lookups
       returned missing, `missing ne missing` was FALSE, ndis came back 0, and
       every column was declared redundant and dropped. A safety proof that
       cannot fail is worse than no proof at all.                             */
    proc sql noprint;
      select count(*) into :nadd trimmed
      from g.master_data_merged
      where not missing(&sv) and missing(&pv);

      select count(*) into :ndis trimmed
      from g.master_data_merged as d
      inner join work.rules as rs
        on rs.harmonized_name = "&hn" and rs.varname = "&sv"
       and rs.value_txt = %if %upcase(&sv_t) = CHAR %then %do; strip(d.&sv) %end;
                          %else %do; strip(put(d.&sv, best12.)) %end;
      inner join work.rules as rp
        on rp.harmonized_name = "&hn" and rp.varname = "&pv"
       and rp.value_txt = %if %upcase(&pv_t) = CHAR %then %do; strip(d.&pv) %end;
                          %else %do; strip(put(d.&pv, best12.)) %end;
      where not missing(d.&sv) and not missing(d.&pv)
        and rs.target_value ne rp.target_value;
    quit;

    /* CHECK BEFORE USE. The previous version referenced &nadd and &ndis inside
       the INSERT and the %IF that decided the verdict, and only checked they
       were populated afterwards -- so a failed query broke macro expansion
       before the guard could run.                                            */
    %if %length(&nadd) = 0 or %length(&ndis) = 0 %then %do;
      %fail_out(msg=Redundancy test failed for &sv -- a count query returned no value);
    %end;

    proc sql;
      insert into work.redundancy values
        ("&hn", "&sv", "&pv", &nadd, &ndis,
         %if &nadd = 0 and &ndis = 0 %then %do; 'REDUNDANT' %end;
         %else %do; 'KEEP' %end;);
    quit;

    %put NOTE: [10b] &sv vs &pv -- would add &nadd rows%str(,) &ndis disagreements.;
  %end;
%mend prove_redundancy;
%prove_redundancy;

proc sql noprint;
  select count(*) into :n_redundant trimmed from work.redundancy where verdict='REDUNDANT';
  select count(*) into :n_keepsec   trimmed from work.redundancy where verdict='KEEP';
  select count(*) into :n_tested    trimmed from work.redundancy;
quit;

/* If rules exist but nothing was tested, the proof did not run -- and reporting
   "0 redundant" would look identical to a genuine result. Fail instead.      */
%macro assert_tested;
  %if %length(&n_tested) = 0 %then %do;
    %fail_out(msg=Redundancy test produced no table -- the proof did not run);
  %end;
  /* n_sec counts SECONDARY SOURCES. An earlier version tested n_rules > n_h --
     but n_rules counts VALUE MAPPINGS, so a single source with Y and N rules
     gives n_rules=2, n_h=1, and the gate would abort a perfectly valid
     single-source run.                                                       */
  %if &n_tested = 0 and &n_sec > 0 %then %do;
    %put ERROR: &n_sec secondary sources exist but no redundancy test was recorded.;
    %put ERROR- The proof did not run and nothing can be dropped safely.;
    %fail_out(msg=Redundancy proof did not execute);
  %end;
%mend assert_tested;
%assert_tested;

%macro report_redundancy;
  %if &n_keepsec > 0 %then %do;
    %put WARNING: [10b] &n_keepsec secondary sources are NOT redundant and are KEPT.;
    %put WARNING- They either add rows the primary lacks or disagree with it. That;
    %put WARNING- contradicts the Phase 10 profiling and is worth investigating.;
    %put WARNING- See work.redundancy.;
  %end;
  %put NOTE: [10b] &n_redundant secondary sources proven redundant.;
%mend report_redundancy;
%report_redundancy;

%global droplist n_dropped;
%let droplist = ;
%let n_dropped = 0;
%macro build_droplist;
  /* Always create it, empty if need be -- SECTION 6 references it either way. */
  proc sql;
    create table work.drop_ok (varname char(32));
  quit;
  %if &drop_redundant = 1 and &n_redundant > 0 %then %do;
    proc sql; drop table work.drop_ok; quit;
    /* A variable is droppable only if it is redundant AND is not the PRIMARY
       source for some other harmonized column, and is not a secondary that was
       KEPT elsewhere. Dropping a column that another concept still reads would
       make the merged output depend on a column the file no longer carries.  */
    proc sql noprint;
      create table work.drop_ok as
      select distinct r.varname
      from work.redundancy as r
      where r.verdict='REDUNDANT'
        and upcase(r.varname) not in
            (select upcase(primary_var) from work.primary_src)
        and upcase(r.varname) not in
            (select upcase(varname) from work.redundancy where verdict='KEEP');

      select distinct varname into :droplist separated by ' ' from work.drop_ok;
      select count(*) into :n_dropped trimmed from work.drop_ok;
    quit;

    %if &n_dropped ne &n_redundant %then %do;
      %put WARNING: [10b] &n_redundant proven redundant but only &n_dropped droppable.;
      %put WARNING- The rest are primary for another harmonized column, or were kept;
      %put WARNING- elsewhere. They are RETAINED. See work.redundancy and work.drop_ok.;
    %end;
    %put NOTE: [10b] dropping from the harmonized output: &droplist;
    %put NOTE- g.master_data_merged is untouched, so this is reversible.;
  %end;
  %else %do;
    %put NOTE: [10b] no columns dropped (drop_redundant=&drop_redundant).;
  %end;
%mend build_droplist;
%build_droplist;


/* =========================================================================
   SECTION 5: Build the harmonized dataset -- NO procedure inside this step
   ========================================================================= */

/* Which harmonized columns actually need a _src companion?

   A _src column records WHICH source supplied the value on a given row. That is
   only informative when more than one source can supply it. Where a concept has
   a single contributing source -- or where the secondary was proven redundant
   and never fires -- every populated row carries the same string, and the column
   holds no information at all.

   The first build emitted eleven such columns, every one with a single distinct
   value. They are now emitted ONLY where a row could genuinely have come from
   either source, which is the case the column was designed for.

   Set force_src = 1 to emit them regardless, if a downstream consumer expects
   the companion column to exist unconditionally.                            */
%let force_src = 1;   /* keep the _src companions -- see the note above */

proc sql noprint;
  create table work.src_needed as
  select r.harmonized_name,
         count(distinct r.varname) as n_src,
         sum(case when d.verdict = 'REDUNDANT' then 1 else 0 end) as n_redundant
  from work.rules as r
  left join work.redundancy as d
    on d.harmonized_name = r.harmonized_name and d.varname = r.varname
  group by r.harmonized_name;

  select count(*) into :n_src_needed trimmed
  from work.src_needed where n_src - n_redundant > 1;

  select harmonized_name into :srclist separated by ' '
  from work.src_needed where n_src - n_redundant > 1;
quit;

%global srclist;
%macro default_srclist;
  %if %symexist(srclist) = 0 %then %let srclist = ;
  %if &n_src_needed = 0 %then %do;
    %let srclist = ;
    %put NOTE: [10b] no harmonized column draws from more than one live source%str(,);
    %put NOTE- so no _src companions are emitted. Every one would have held a single;
    %put NOTE- repeated value. Set force_src=1 to emit them anyway.;
  %end;
  %else %put NOTE: [10b] _src companions emitted for: &srclist;
%mend default_srclist;
%default_srclist;

%macro build_harmonized;
  %local i k h emit_src;
  data g.master_data_harmonized;
    set g.master_data_merged;
    /* Proven-redundant sources dropped here, AFTER the rules below have read
       them -- the DROP statement removes them from the OUTPUT, not the PDV, so
       priority-2 rules still evaluate correctly even for a dropped column.   */
  %if %length(&droplist) > 0 %then %do;
    drop &droplist;
  %end;

    length
    %do i = 1 %to &n_h;
      %let h = %scan(&hnames, &i);
      &h $&max_tv
      %if &force_src = 1 or %sysfunc(indexw(&srclist, &h)) > 0 %then %do;
        &h._src $32
      %end;
    %end;
    ;

    %do i = 1 %to &n_h;
      %let h = %scan(&hnames, &i);
      call missing(&h);
      %if &force_src = 1 or %sysfunc(indexw(&srclist, &h)) > 0 %then %do;
        call missing(&h._src);
      %end;
    %end;

    /* Rules in priority order. The first source holding a value wins; the
       missing(&h) test is what makes priority meaningful, and SECTION 2 has
       already guaranteed no two source columns share a priority.            */
    %do k = 1 %to &n_rules;
      %if %upcase(&&r_t_&k) = CHAR %then %do;
      if missing(&&r_h_&k) and not missing(&&r_v_&k)
         and strip(&&r_v_&k) = "&&r_sv_&k" then do;
      %end;
      %else %do;
      if missing(&&r_h_&k) and not missing(&&r_v_&k)
         and strip(put(&&r_v_&k, best12.)) = "&&r_sv_&k" then do;
      %end;
        &&r_h_&k = "&&r_tv_&k";
      %if &force_src = 1 or %sysfunc(indexw(&srclist, &&r_h_&k)) > 0 %then %do;
        &&r_h_&k.._src = "&&r_v_&k";
      %end;
      end;
    %end;
  run;
%mend build_harmonized;
%build_harmonized;


/* =========================================================================
   SECTION 6: Assertions
   ========================================================================= */

proc sql noprint;
  select count(*) into :n_out trimmed from g.master_data_harmonized;
  select count(distinct PRECEDE_STUDY_ID) into :n_key trimmed
    from g.master_data_harmonized;

  /* CON-09: source columns unchanged in TYPE and LENGTH, not merely present.
     The old version claimed this in a comment and only checked names.       */
  /* A column may legitimately be ABSENT from the harmonized file only if it was
     proven redundant in SECTION 4b. Any other absence, or any change of type or
     length, is a defect: harmonization must never alter a column it keeps.   */
  create table work.src_changed as
  select a.name, a.type as t_before, b.type as t_after,
         a.length as l_before, b.length as l_after,
         case when b.name is null then 'DROPPED' else 'ALTERED' end as issue length=8
  from (select upcase(name) as name, type, length from dictionary.columns
        where libname='G' and memname='MASTER_DATA_MERGED') as a
  left join (select upcase(name) as name, type, length from dictionary.columns
             where libname='G' and memname='MASTER_DATA_HARMONIZED') as b
    on a.name = b.name
  where (b.name is null or a.type ne b.type or a.length ne b.length)
    /* Keyed off what was ACTUALLY dropped, not what was proven redundant. With
       drop_redundant=0 nothing is dropped, so any absence at all is a defect --
       an exclusion based on the verdict would have let a stray drop through.
       STRIP guards against trailing blanks in the char(32) varname column.   */
    and a.name not in (select strip(upcase(varname)) from work.drop_ok)
  ;
  select count(*) into :n_changed trimmed from work.src_changed;

  /* And every column we DID intend to drop must actually be gone */
  create table work.drop_failed as
  select varname from work.drop_ok
  where strip(upcase(varname)) in (select upcase(name) from dictionary.columns
                                   where libname='G' and memname='MASTER_DATA_HARMONIZED');
  select count(*) into :n_dropfail trimmed from work.drop_failed;
quit;

%macro assert_all;
  %if &n_out ne &n_rows %then %do;
    %fail_out(msg=Harmonized file has &n_out rows%str(,) merged file has &n_rows);
  %end;
  %if &n_key ne &n_rows %then %do;
    %fail_out(msg=PRECEDE_STUDY_ID has &n_key distinct values in &n_out rows -- key not unique);
  %end;
  %if &n_changed > 0 %then %do;
    %put ERROR: &n_changed columns vanished or changed type/length WITHOUT being;
    %put ERROR- proven redundant. Only a column proven redundant in SECTION 4b may;
    %put ERROR- be absent, and no kept column may be altered. See work.src_changed.;
    %fail_out(msg=Columns were altered or dropped without proof);
  %end;
  %if &drop_redundant = 1 and &n_dropfail > 0 %then %do;
    %put ERROR: &n_dropfail columns were marked redundant but are still present.;
    %put ERROR- The DROP statement did not take. See work.drop_failed.;
    %fail_out(msg=Redundant columns were not dropped);
  %end;
  %put NOTE: [10b] CON-06 and CON-09 OK -- &n_out rows%str(,) key unique.;
  %put NOTE- &n_redundant proven redundant%str(,) &n_dropped actually dropped%str(,) every other original intact.;
%mend assert_all;
%assert_all;


/* =========================================================================
   SECTION 7: Report
   ========================================================================= */

%macro coverage_report;
  %local i h n_pop;
  data _null_;
    file "&qc_path.\10b_harmonize_report.txt";
    put "10b_concept_harmonize -- Run: %sysfunc(datetime(), datetime20.)";
    put "=======================================================================";
    put " ";
    put "merged_rows=&n_rows";
    put "harmonized_rows=&n_out";
    put "harmonized_columns=&n_h";
    put "confirmed_value_mappings=&n_yes";
    put "concepts_confirmed=&n_con_yes";
    put "rules_applied=&n_rules";
    put " ";
    put "Secondary sources proven redundant : &n_redundant";
    put "Source columns actually DROPPED     : &n_dropped  (drop_redundant=&drop_redundant)";
    put "  A column is dropped ONLY when this run proved it adds no rows the";
    put "  primary lacks AND disagrees with it nowhere. g.master_data_merged is";
    put "  untouched, so re-running restores anything dropped.";
    put "Every other source column is RETAINED, unchanged in type and length.";
    put "Harmonized values are additive, in new h_ prefixed columns, each with an";
    put "h_*_src companion naming which source supplied the value on that row.";
    put " ";
    put "Column                              N Populated    Pct";
    put "---------------------------------------------------------";
  run;

  %do i = 1 %to &n_h;
    %let h = %scan(&hnames, &i);
    proc sql noprint;
      select count(&h) into :n_pop trimmed from g.master_data_harmonized;
    quit;
    data _null_;
      file "&qc_path.\10b_harmonize_report.txt" mod;
      put @1 "&h" @37 "&n_pop" @51 "%sysfunc(putn(%sysevalf(100*&n_pop/&n_rows), 6.1))";
    run;
    %put NOTE: [10b] &h populated on &n_pop of &n_rows rows.;
  %end;

  data _null_;
    file "&qc_path.\10b_harmonize_report.txt" mod;
    put " ";
    put "A harmonized column populated on fewer rows than the union of its sources";
    put "would mean some rows had no mapped value -- but the coverage gate in";
    put "SECTION 3 fails the run before it gets here, so that should be impossible.";
  run;
%mend coverage_report;
%coverage_report;

%put NOTE: ==== Phase 10b complete ====;
%put NOTE- Output: g.master_data_harmonized;
%put NOTE- Report: qc/10b_harmonize_report.txt;

%restore_log;
