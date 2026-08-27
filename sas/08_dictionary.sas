/* Program: 08_dictionary.sas
   Phase   : 8 -- Documentation and Handoff
   Purpose : Produce docs/DATA_DICTIONARY.xlsx from g.master_data_merged.
             Every variable is documented with source, type, length, coverage
             percentage, and derivation rule (DOC-01).
   Output  : docs/DATA_DICTIONARY.xlsx (gitignored -- contains column metadata
             but not row data; not a PHI artifact).
             KEY sheet is FIRST (leftmost); Dictionary sheet is SECOND.
   Author  : Executor (Phase 8 Plan 01)
   Created : 2026-08-27
   Requirements: DOC-01
   PCM violations avoided:
     PCM-T-01: no PROC SQL UPDATE
     PCM-T-02: no data X; set X;
     PCM-T-13: dictionary.columns.type is CHARACTER (char/num), not 1/2
     All counts use SELECT COUNT(*) INTO :macvar TRIMMED
     All %abort cancel calls are inside named %macro definitions (PCM-R-05)
   Coverage: PROC SQL COUNT() for ALL variables (both numeric and character).
     PROC MEANS cannot process character variables -- one SQL path for all types.
   Ownership: Resolved by rule (00_ownership_rule.sas), NOT a raw join to
     qclib.ownership_map.owner which contains literal CONFLICT for 135 of 163 vars.
*/

options nodate nonumber ps=max ls=200;
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* Default the pipeline flag before anything reads it. 00_config.sas defines it,
   so standalone runs normally resolve fine -- but if the include ever fails or the
   program is submitted piecemeal, `%if &in_pipeline = 0` errors on an unresolved
   reference instead of behaving. One line removes that failure mode.            */
/* Wrapped in a macro on purpose. In OPEN CODE, %IF/%THEN requires a %DO block --
   a bare statement after %THEN makes SAS report "Expected %DO not found" and then
   skip forward hunting for a %END, swallowing the rest of the file. Inside a macro
   definition the bare form is fine. This bit once: an open-code version here made
   99_run_all.sas execute nothing at all.                                        */
%macro _set_pipeline_default;
  %if not %symexist(in_pipeline) %then %do;
    %global in_pipeline;
    %let in_pipeline = 0;
  %end;
%mend _set_pipeline_default;
%_set_pipeline_default;

%macro restore_log;
  %if &in_pipeline = 0 %then %do;
    proc printto; run;
  %end;
%mend restore_log;

%macro fail_out(msg=);
  %put ERROR: &msg;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;

/* =========================================================================
   SECTION 0 -- LOG REDIRECT AND PRECONDITIONS
   All %fail_out calls precede any ODS EXCEL open so the abort closes cleanly.
   ========================================================================= */
%if &in_pipeline = 0 %then %do;
  proc printto log="&logs_path.\08_dictionary.log" new; run;
%end;

libname g      "&g_path";
/* qclib is &qc_path, NOT a "qclib" subfolder of the merge tree. ownership_map
   lives beside the other QC artifacts, and every other program in this pipeline
   assigns it this way. The earlier "&g_path.\qclib" pointed at a folder that does
   not exist, so the libname failed and the precondition below reported the wrong
   cause.                                                                        */
libname qclib  "&qc_path";

/* Precondition: the ODS EXCEL output directory must exist. Checked HERE, not at
   SECTION 7 -- a missing docs\ would otherwise fail after all 173 coverage
   queries have run.                                                             */
%macro check_docs_dir;
  %if %sysfunc(fileexist(&docs_path)) = 0 %then
    %fail_out(msg=docs directory not found: &docs_path);
  %put NOTE: [08_dictionary] docs directory found.;
%mend check_docs_dir;
%check_docs_dir;

/* Precondition: g.master_data_merged must exist and be non-empty */
proc sql noprint;
  select count(*) into :n_merged trimmed from g.master_data_merged;
quit;
%macro _gate1;
  %if &n_merged = 0 %then %do;
    %fail_out(msg=g.master_data_merged is empty or missing -- re-run Phase 4);
  %end;
%mend _gate1;
%_gate1;

/* Precondition: qclib.ownership_map must exist and be non-empty */
proc sql noprint;
  select count(*) into :n_own trimmed from qclib.ownership_map;
quit;
%macro _gate2;
  %if &n_own = 0 %then %do;
    %fail_out(msg=qclib.ownership_map is empty or missing -- re-run Phase 2);
  %end;
%mend _gate2;
%_gate2;

%put NOTE: [08_dictionary] Preconditions OK -- &n_merged rows in g.master_data_merged; &n_own rows in ownership_map.;

/* =========================================================================
   SECTION 1 -- COLUMN METADATA (dictionary.columns)
   PCM-T-13: type column is CHARACTER (char or num), not numeric 1/2.
   Filter uses upcase() on both libname and memname.
   ========================================================================= */
proc sql noprint;
  create table work.dict_meta as
  select upcase(name)   as varname   length=32,
         type,
         length,
         label
  from   dictionary.columns
  where  upcase(libname)  = "G"
    and  upcase(memname)  = "MASTER_DATA_MERGED"
  order by varname;

  /* Explicit count, never &SQLOBS. Banned project-wide since Phase 1: its value
     after CREATE TABLE is version/context dependent. Worse here -- a %let inside
     the PROC SQL block resolves during tokenization, BEFORE the CREATE TABLE
     runs, so it would read whatever the previous statement left behind.        */
  select count(*) into :n_dict_meta trimmed from work.dict_meta;
quit;

%macro _gate3;
  %if &n_dict_meta = 0 %then %do;
    %fail_out(msg=dictionary.columns returned 0 rows for G.MASTER_DATA_MERGED -- check libname assignment);
  %end;
%mend _gate3;
%_gate3;

%put NOTE: [08_dictionary] SECTION 1 OK -- &n_dict_meta variables found in dictionary.columns.;

/* =========================================================================
   SECTION 2 -- COVERAGE (PROC SQL COUNT, NOT PROC MEANS)
   PROC MEANS fails on character variables: "Variable X in list does not
   match type prescribed for this list."  Use COUNT(var) for all types.
   COUNT() counts non-missing values; SAS treats all-blank char as missing.
   Do NOT hardcode 41150 as the denominator -- read it so percentages stay
   correct if the row count legitimately changes.  QC-01 asserts the target.
   firstobs=/obs= indexing avoids POINT=, which cannot be combined with WHERE
   and has produced silent no-op loops in this project.
   ========================================================================= */
proc sql noprint;
  select count(*) into :n_total trimmed from g.master_data_merged;  /* QC-01: expect 41150 */
  select count(*) into :n_vars  trimmed from work.dict_meta;
quit;

proc sql;
  create table work.coverage
    (varname char(32), n_nonmiss num, coverage_pct num);
quit;

%macro coverage_all;
  %local i v n;
  /* Guard the denominator. If n_total were 0 the %sysevalf below divides by zero
     inside a values() clause, producing a malformed INSERT rather than a clean
     failure.                                                                    */
  %if %superq(n_total) = or &n_total = 0 %then
    %fail_out(msg=n_total is zero or unset -- cannot compute coverage percentages);
  %do i = 1 %to &n_vars;
    proc sql noprint;
      select varname into :v trimmed from work.dict_meta (firstobs=&i obs=&i);
      select count(&v) into :n trimmed from g.master_data_merged;
      insert into work.coverage
        values("&v", &n, %sysevalf(100 * &n / &n_total));
    quit;
  %end;
%mend coverage_all;
%coverage_all;

%put NOTE: [08_dictionary] SECTION 2 OK -- coverage computed for &n_vars variables over &n_total rows.;

/* =========================================================================
   SECTION 3 -- OWNERSHIP RESOLUTION
   Do NOT join ownership_map.owner directly -- it holds the literal string
   CONFLICT for 135 of 163 variables.  Apply the resolution RULE via the
   shared include 00_ownership_rule.sas.  This is the third copy of the rule;
   extracting to 00_ownership_rule.sas keeps all three in sync.
   ========================================================================= */
data work.own_resolved;
  set qclib.ownership_map;
  length owner_resolved $4;
  %include "&sas_path.\00_ownership_rule.sas";
  varname_u = upcase(varname);
run;

proc sql noprint;
  create table work.dict_with_owner as
  select d.varname, d.type, d.length, d.label,
         coalesce(o.owner_resolved, "derived") as source length=40
  from   work.dict_meta as d
  left join work.own_resolved as o
    on d.varname = o.varname_u;
quit;

/* Assert: no row may carry literal CONFLICT after the resolution rule */
proc sql noprint;
  select count(*) into :n_conflict trimmed
  from work.dict_with_owner where upcase(source) = 'CONFLICT';
quit;
%macro _gate4;
  %if &n_conflict > 0 %then %do;
    %fail_out(msg=&n_conflict dictionary rows have source=CONFLICT -- the resolution rule did not apply);
  %end;
%mend _gate4;
%_gate4;

%put NOTE: [08_dictionary] SECTION 3 OK -- ownership resolved; 0 CONFLICT rows.;

/* =========================================================================
   SECTION 4 -- DERIVATION OVERLAY
   Hard-coded derivation strings for variables that need a non-default label.
   ASCII only -- plain hyphens, no em-dashes, no smart quotes.
   Variables not in the derivation_map get the default rule from the source
   column: "mdN owner (ownership_map)" where N is their resolved source.
   Join uses upcase(varname) to be case-insensitive.
   ========================================================================= */
data work.derivation_map;
  length varname $64 derivation $200;

  /* MRG-06 gap-fill variables: md3 spine + md8 gap-fill */
  varname="COGNITIVE_SCORE";             derivation="md3 spine, md8 gap-fill (MRG-06)"; output;
  varname="COGNITIVE_CATEGORY";          derivation="md3 spine, md8 gap-fill (MRG-06)"; output;
  varname="FRAILTY_SCORE";               derivation="md3 spine, md8 gap-fill (MRG-06)"; output;
  varname="FRAILTY_CATEGORY";            derivation="md3 spine, md8 gap-fill (MRG-06)"; output;
  varname="ORAL_MORPHINE_EQUIV_MG_POD_DAY6"; derivation="md3 spine, md8 gap-fill (MRG-06)"; output;

  /* Merge-derived flags: not in ownership_map */
  varname="RT_ENVELOPE_FLAG";            derivation="derived at merge (Phase 4); not in ownership_map"; output;
  varname="N_SOURCES";                   derivation="derived at merge (Phase 4); not in ownership_map"; output;
  varname="IN_MD1";                      derivation="derived at merge (Phase 4); not in ownership_map"; output;
  varname="IN_MD2";                      derivation="derived at merge (Phase 4); not in ownership_map"; output;
  varname="IN_MD3";                      derivation="derived at merge (Phase 4); not in ownership_map"; output;
  varname="IN_MD4";                      derivation="derived at merge (Phase 4); not in ownership_map"; output;
  varname="IN_MD5";                      derivation="derived at merge (Phase 4); not in ownership_map"; output;
  varname="IN_MD6";                      derivation="derived at merge (Phase 4); not in ownership_map"; output;
  varname="IN_MD7";                      derivation="derived at merge (Phase 4); not in ownership_map"; output;
  varname="IN_MD8";                      derivation="derived at merge (Phase 4); not in ownership_map"; output;

  /* PCM-D-01 mortality */
  varname="DEATH_DATE_Y_N";              derivation="source-specific; kept separate per PCM-D-01"; output;
  varname="ISDEAD_Y_N";                  derivation="source-specific; kept separate per PCM-D-01"; output;
  varname="DEATH";                       derivation="source-specific; kept separate per PCM-D-01"; output;

  /* PCM-D-02 frailty components */
  varname="FEELS_EXAUSTED";              derivation="source-specific encoding; kept separate per PCM-D-02"; output;
  varname="LOW_PHYSICAL_ACTIVITY";       derivation="source-specific encoding; kept separate per PCM-D-02"; output;
  varname="SLOW_WALKING_SPEED";          derivation="source-specific encoding; kept separate per PCM-D-02"; output;
  varname="UNINTENDED_WEIGHT_LOSS";      derivation="source-specific encoding; kept separate per PCM-D-02"; output;
  varname="WEEK_GRIP_STRENGTH";          derivation="source-specific encoding; kept separate per PCM-D-02"; output;
  varname="FEELS_EXAUSTED_VALUE";        derivation="source-specific encoding; kept separate per PCM-D-02"; output;
  varname="LOW_PHYSICAL_ACTIVITY_VALUE"; derivation="source-specific encoding; kept separate per PCM-D-02"; output;
  varname="SLOW_WALKING_SPEED_VALUE";    derivation="source-specific encoding; kept separate per PCM-D-02"; output;
  varname="UNINTENDED_WEIGHT_LOSS_VALUE"; derivation="source-specific encoding; kept separate per PCM-D-02"; output;
  varname="WEEK_GRIP_STRENGTH_VALUE";    derivation="source-specific encoding; kept separate per PCM-D-02"; output;

  /* PCM-D-03 ISO_SEV */
  varname="ISO_SEV_EXP_INTRAOP_MAC_AVERAGE"; derivation="source-specific; md8 col is a TOTAL not an average; kept separate per PCM-D-03"; output;
  varname="ISO_SEV_INTRAOP_MAC_AVERAGE";     derivation="source-specific; md8 col is a TOTAL not an average; kept separate per PCM-D-03"; output;
  varname="ISO_SEV_MAC_TOTAL_EXP";           derivation="source-specific; md8 col is a TOTAL not an average; kept separate per PCM-D-03"; output;

  /* Anchor offsets: negative values are legitimate (PCM-D-10) */
  varname="RT_ANCHOR_TO_ADMIT_DAYS";    derivation="offset from anchor date; negative values are legitimate (PCM-D-10)"; output;
  varname="RT_ANCHOR_TO_SURGERY_DAYS";  derivation="offset from anchor date; negative values are legitimate (PCM-D-10)"; output;
  varname="RT_ANCHOR_TO_DISCHG_DAYS";   derivation="offset from anchor date; negative values are legitimate (PCM-D-10)"; output;

  /* Bucket-D negatives: duration variables; negatives retained by decision (PCM-D-10) */
  varname="RT_RM_START_TO_AN_START_MINS";        derivation="duration; negative values retained by decision (PCM-D-10)"; output;
  varname="RT_ADMIT_TO_AN_START_MINS";           derivation="duration; negative values retained by decision (PCM-D-10)"; output;
  varname="RT_ADMIT_TO_BLOCK_START_MINS";        derivation="duration; negative values retained by decision (PCM-D-10)"; output;
  varname="RT_ADMIT_TO_BLOCK_END_MINS";          derivation="duration; negative values retained by decision (PCM-D-10)"; output;
  varname="RT_ADMIT_TO_RM_START_MINS";           derivation="duration; negative values retained by decision (PCM-D-10)"; output;
  varname="RT_ADMIT_TO_INCISION_MINS";           derivation="duration; negative values retained by decision (PCM-D-10)"; output;
  varname="RT_ADMIT_TO_DRESS_MINS";              derivation="duration; negative values retained by decision (PCM-D-10)"; output;
  varname="RT_RM_START_TO_DRESS_MINS";           derivation="duration; negative values retained by decision (PCM-D-10)"; output;
  varname="RT_RM_START_TO_INDUCTION_MINS";       derivation="duration; negative values retained by decision (PCM-D-10)"; output;
  varname="RT_RM_START_TO_EMERGENCE_MINS";       derivation="duration; negative values retained by decision (PCM-D-10)"; output;
  varname="RT_BLOCK_START_TO_BLOCK_END_MINS";    derivation="duration; negative values retained by decision (PCM-D-10)"; output;
run;

/* Join derivation_map onto dict_with_owner; construct default derivation from source */
proc sql noprint;
  create table work.dict_final as
  select d.varname,
         d.type,
         d.length,
         d.source,
         /* CATX, not CATS. CATS strips leading AND trailing blanks from every
            argument, so cats(d.source, " owner (...)") yields "md3owner (...)"
            with no space. CATX inserts the delimiter between the parts.        */
         coalesce(dm.derivation,
                  catx(" ", d.source, "owner (ownership_map)")) as derivation length=200,
         d.label
  from   work.dict_with_owner as d
  left join work.derivation_map as dm
    on upcase(d.varname) = upcase(dm.varname);
quit;

/* =========================================================================
   SECTION 5 -- COVERAGE JOIN
   Add coverage_pct (numeric, format=6.1) from work.coverage.
   ========================================================================= */
proc sql noprint;
  create table work.dict_final2 as
  select d.varname, d.type, d.length, d.source, d.derivation, d.label,
         c.coverage_pct
  from   work.dict_final as d
  left join work.coverage as c
    on upcase(d.varname) = upcase(c.varname);
quit;

/* Rename for clarity */
data work.dict_final;
  set work.dict_final2;
  format coverage_pct 6.1;
run;

/* =========================================================================
   SECTION 6 -- ASSERTIONS (all must pass before ODS EXCEL opens)
   ========================================================================= */
proc sql noprint;
  select count(*) into :n_final trimmed from work.dict_final;
quit;
%macro _gate5;
  %if &n_final ne &n_dict_meta %then %do;
    %fail_out(msg=dict_final row count &n_final does not match dict_meta count &n_dict_meta);
  %end;
%mend _gate5;
%_gate5;

proc sql noprint;
  select count(*) into :n_nosrc trimmed
  from work.dict_final
  where source is missing or source = "";
quit;
%macro _gate6;
  %if &n_nosrc > 0 %then %do;
    %fail_out(msg=&n_nosrc variables have a missing source in dict_final);
  %end;
%mend _gate6;
%_gate6;

%put NOTE: [08_dictionary] SECTION 6 OK -- &n_final rows in dict_final; 0 missing sources.;

/* =========================================================================
   SECTION 7 -- ODS EXCEL OUTPUT
   KEY sheet is opened FIRST (leftmost in the workbook per CLAUDE.md).
   UF blue (#0021A5) on all column headers.
   Path uses period before backslash: "&docs_path.\DATA_DICTIONARY.xlsx"
   ========================================================================= */
ods listing close;
ods excel file="&docs_path.\DATA_DICTIONARY.xlsx"
    options(sheet_name="KEY"
            frozen_headers="yes"
            autofilter="no"
            embedded_titles="yes");

/* KEY sheet: legend explaining each column in the Dictionary sheet */
data work.key_legend;
  length Column $30 Meaning $200;
  Column="varname";      Meaning="SAS variable name (uppercase)"; output;
  Column="type";         Meaning="num = numeric, char = character"; output;
  Column="length";       Meaning="Stored byte length (SAS LENGTH statement value)"; output;
  Column="source";       Meaning="Owner source (md1..md8) or derived"; output;
  Column="derivation";   Meaning="Derivation rule or decision reference"; output;
  Column="coverage_pct"; Meaning="Percent non-missing rows (N / &n_total * 100); &n_total is the merged row count, asserted by QC-01"; output;
  Column="label";        Meaning="SAS variable label if set; blank if no label assigned"; output;
run;

proc report data=work.key_legend nowd;
  columns Column Meaning;
  define Column  / "Column"  style(header)=[background=#0021A5 color=white fontweight=bold];
  define Meaning / "Meaning" style(header)=[background=#0021A5 color=white fontweight=bold];
run;

/* Dictionary sheet: one row per variable in g.master_data_merged */
ods excel options(sheet_name="Dictionary" frozen_headers="yes" autofilter="yes");

proc report data=work.dict_final nowd;
  columns varname type length source derivation coverage_pct label;
  define varname      / "Variable"     style(header)=[background=#0021A5 color=white fontweight=bold];
  define type         / "Type"         style(header)=[background=#0021A5 color=white fontweight=bold];
  define length       / "Length"       style(header)=[background=#0021A5 color=white fontweight=bold];
  define source       / "Source"       style(header)=[background=#0021A5 color=white fontweight=bold];
  define derivation   / "Derivation"   style(header)=[background=#0021A5 color=white fontweight=bold];
  define coverage_pct / "Coverage (%)" style(header)=[background=#0021A5 color=white fontweight=bold] format=6.1;
  define label        / "Label"        style(header)=[background=#0021A5 color=white fontweight=bold];
run;

ods excel close;
ods listing;

/* =========================================================================
   SECTION 8 -- LOG SUMMARY
   ========================================================================= */
%put NOTE: [08_dictionary] DATA_DICTIONARY.xlsx written to &docs_path.;
%put NOTE: [08_dictionary] Variable count: &n_final;
%put NOTE: [08_dictionary] Coverage based on &n_total rows (QC-01 asserts 41150);

%restore_log;
