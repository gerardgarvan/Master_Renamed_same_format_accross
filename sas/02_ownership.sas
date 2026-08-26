/*==========================================================================
  Program : 02_ownership.sas
  Phase   : Phase 2 -- Ownership Map
  Purpose : Preconditions, cross-source variable enumeration via PROC
            CONTENTS, ownership table construction (single declared owner
            per variable name), and dual artifact write (human-readable
            text to qc/02_ownership_map.txt; machine-readable SAS dataset
            to qclib.ownership_map for Phase 4 consumption).
  Requirements addressed:
            OWN-01 (variable ownership table written to disk)
            OWN-02 (human-readable committed artifact for review)
  Author  : Executor (Phase 2 Plan 01)
  Created : 2026-08-26
  Note    : Plan 02 appends OWN-03 conflict block and OWN-04 coalesce
            assertions below the marker at end of this file.
            src libname is intentionally left open for Plan 02.
==========================================================================*/

options mprint;   /* macro-generated code visible in the log for audit */


/*==========================================================================
  SECTION 0: Paths and libnames
==========================================================================*/

%let source_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross;
%let qc_path     = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc;
%let docs_path   = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\docs;
libname src "&source_path" access=readonly;


/*==========================================================================
  SECTION 1: Preconditions
  All %abort cancel calls are inside macro definitions (RESEARCH Pitfall 5).
==========================================================================*/

/* ---- Precondition 1: libname src must resolve ---- */
%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: LIBNAME &lib could not be assigned. Check P: drive availability.;
    %abort cancel;
  %end;
  %else %put NOTE: LIBNAME &lib resolved.;
%mend check_libname;
%check_libname(lib=src);

/* ---- Precondition 2: qc output directory must exist ---- */
%macro check_qc_path;
  %if %sysfunc(fileexist(&qc_path)) = 0 %then %do;
    %put ERROR: qc output directory does not exist: &qc_path;
    %put ERROR- Create it before running (it is a committed artifact location).;
    %abort cancel;
  %end;
  %else %put NOTE: qc output directory found: &qc_path;
%mend check_qc_path;
%check_qc_path;

/* ---- Precondition 3: docs directory must exist (for DECISIONS.md write) ---- */
/*      FILE MOD to a non-existent directory silently fails or creates the
        file in an unexpected location -- abort with an actionable message
        (RESEARCH Pitfall 6).                                               */
%macro check_docs_path;
  %if %sysfunc(fileexist(&docs_path)) = 0 %then %do;
    %put ERROR: docs directory does not exist: &docs_path;
    %put ERROR- Create it before running (02_ownership.sas writes DECISIONS.md there).;
    %abort cancel;
  %end;
  %else %put NOTE: docs directory found: &docs_path;
%mend check_docs_path;
%check_docs_path;


/*==========================================================================
  SECTION 2: Enumerate all variables across all eight sources
==========================================================================*/

/* Raw enumeration -- src._ALL_ expands to every dataset in the library.
   This may include stale artifacts (master_data_all, master_data_dedup,
   master_data_7b, master_data_merged) still present on the P: drive.
   The filter step below restricts to the eight canonical sources only.
   We keep work.allvars intact (PCM-R-01 / PCM-T-02 -- no in-place rewrite). */
proc contents data=src._all_
  out=work.allvars (keep=memname name type length varnum)
  noprint;
run;

/* Normalise case and restrict to the eight master sources.
   CRITICAL: use IN, never IN: (prefix match).
   IN: would admit master_data_7b for the literal 'MASTER_DATA_7' --
   defeating the stale-artifact filter entirely (RESEARCH Pitfall 1).
   Write to work.allvars_src, NOT back into work.allvars (PCM-R-01).    */
data work.allvars_src;
  set work.allvars;
  where upcase(memname) in
    ('MASTER_DATA_1','MASTER_DATA_2','MASTER_DATA_3','MASTER_DATA_4',
     'MASTER_DATA_5','MASTER_DATA_6','MASTER_DATA_7','MASTER_DATA_8');
  name_u    = upcase(name);
  memname_u = upcase(memname);
run;


/*==========================================================================
  SECTION 3: Build ownership assignments into work.ownership_map
  Columns: varname $32, owner $12, n_sources 8, sources_present $40,
           coalesce_flag $1.
  Single-source variables: owner = the one source label (md1 .. md8).
  Multi-source variables:  owner = 'CONFLICT' (Plan 02 resolves specific owners).
  coalesce_flag initialized to 'N' for all rows; Plan 02 flips Admit_BMI
  and Race to 'Y'.
==========================================================================*/

proc sql noprint;
  create table work.ownership_map as
    select
      name_u                                       as varname    length=32,
      case
        when count(distinct memname_u) = 1
          then min(case
                    when memname_u='MASTER_DATA_1' then 'md1'
                    when memname_u='MASTER_DATA_2' then 'md2'
                    when memname_u='MASTER_DATA_3' then 'md3'
                    when memname_u='MASTER_DATA_4' then 'md4'
                    when memname_u='MASTER_DATA_5' then 'md5'
                    when memname_u='MASTER_DATA_6' then 'md6'
                    when memname_u='MASTER_DATA_7' then 'md7'
                    when memname_u='MASTER_DATA_8' then 'md8'
                  end)
        else 'CONFLICT'
      end                                          as owner      length=12,
      count(distinct memname_u)                    as n_sources,
      /* Build a pipe-delimited source-presence list.
         catx omits missing (sources where the variable is absent).
         Column arithmetic: max string = md1|md2|md3|md4|md5|md6|md7|md8
         = 31 chars. Declare $40 for overhead without collision.           */
      catx('|',
           min(case when memname_u='MASTER_DATA_1' then 'md1' end),
           min(case when memname_u='MASTER_DATA_2' then 'md2' end),
           min(case when memname_u='MASTER_DATA_3' then 'md3' end),
           min(case when memname_u='MASTER_DATA_4' then 'md4' end),
           min(case when memname_u='MASTER_DATA_5' then 'md5' end),
           min(case when memname_u='MASTER_DATA_6' then 'md6' end),
           min(case when memname_u='MASTER_DATA_7' then 'md7' end),
           min(case when memname_u='MASTER_DATA_8' then 'md8' end))
                                                   as sources_present length=40,
      'N'                                          as coalesce_flag  length=1
    from work.allvars_src
    group by name_u
    order by name_u;
quit;


/*==========================================================================
  SECTION 4: Write ownership table as two artifacts
  4a. Human-readable text: qc/02_ownership_map.txt  (OWN-02)
  4b. Machine-readable SAS dataset: qclib.ownership_map  (Phase 4)

  Column layout for text artifact:
    @1  varname       $32.  -> columns  1-32
    @35 owner         $12.  -> columns 35-46
    @50 n_sources       3.  -> columns 50-52
    @58 sources_present $32. -> columns 58-89  (max 31 chars + 1 pad)
    @95 coalesce_flag  $1.  -> column  95
  No overlap. $40. at @58 would reach col 97 and collide -- use $32.
  (RESEARCH Pattern 3 column arithmetic note.)
==========================================================================*/

/* 4a: Text artifact */
filename owntxt "&qc_path.\02_ownership_map.txt";
data _null_;
  set work.ownership_map;
  file owntxt;
  if _n_ = 1 then do;
    put "Variable Ownership Map -- Run: %sysfunc(datetime(), datetime20.)";
    put @1 "Variable" @35 "Owner" @50 "N_Src" @58 "Sources" @95 "Coalesce";
    put @1 "------------------------------------------------------------------------------------------------";
  end;
  put @1 varname $32. @35 owner $12. @50 n_sources 3. @58 sources_present $32. @95 coalesce_flag $1.;
run;
filename owntxt clear;

/* 4b: SAS dataset artifact for Phase 4 */
libname qclib "&qc_path";
data qclib.ownership_map;
  set work.ownership_map;
run;
libname qclib clear;


/*==========================================================================
  End of Plan 01 sections
==========================================================================*/

%put NOTE: OWN-01/OWN-02 -- ownership table written (Plan 01 sections);

/* === Plan 02 appends OWN-03 conflict block and OWN-04 coalesce assertions below this line === */


/*==========================================================================
  SECTION 5: OWN-03 -- Detect multi-source variable name conflicts and
             write each as a markdown row to docs/DECISIONS.md.
             A re-run guard (infile scan, no XCMD) prevents duplicate blocks.
==========================================================================*/

/* 5a: Build work.conflicts -- variable names appearing in > 1 source.
   PRECEDE_STUDY_ID is the merge key, not a conflict -- exclude it.
   Source: work.allvars_src (Plan 01 Section 2, restricted to 8 sources). */
proc sql noprint;
  create table work.conflicts as
    select name_u,
           count(distinct memname_u) as n_sources,
           catx('|', min(case when memname_u='MASTER_DATA_1' then 'md1' end),
                     min(case when memname_u='MASTER_DATA_2' then 'md2' end),
                     min(case when memname_u='MASTER_DATA_3' then 'md3' end),
                     min(case when memname_u='MASTER_DATA_4' then 'md4' end),
                     min(case when memname_u='MASTER_DATA_5' then 'md5' end),
                     min(case when memname_u='MASTER_DATA_6' then 'md6' end),
                     min(case when memname_u='MASTER_DATA_7' then 'md7' end),
                     min(case when memname_u='MASTER_DATA_8' then 'md8' end))
                as sources_present length=40
    from work.allvars_src
    where name_u ne 'PRECEDE_STUDY_ID'
    group by name_u
    having count(distinct memname_u) > 1
    order by name_u;
  select count(*) into :n_conflicts trimmed from work.conflicts;
quit;
%put NOTE: OWN-03 -- &n_conflicts variable name conflicts detected across sources.;

/* 5b: Re-run guard -- scan DECISIONS.md for the greppable marker.
   The %let pre-sets own03_written=0 so an empty file (no iterations,
   symputx never fires) leaves the guard correctly at 0, not undefined.
   Do NOT use FILENAME PIPE / findstr: that adds an XCMD dependency and
   fails silently under NOXCMD -- appending a duplicate block on every run.  */
%let own03_written = 0;
data _null_;
  infile "&docs_path.\DECISIONS.md" truncover end=eof;
  input line $256.;
  retain hits 0;
  if index(line, 'OWN-03 CONFLICT ROWS GENERATED') > 0 then hits + 1;
  if eof then call symputx('own03_written', hits, 'G');
run;

/* 5c: Append conflict block only on first run (own03_written = 0).
   Uses FILE ... MOD so the rest of DECISIONS.md is preserved (never REPLACE).
   The marker string 'OWN-03 CONFLICT ROWS GENERATED' is what the guard scans. */
%macro write_own03_block;
  %if &own03_written = 0 %then %do;
    filename dcsnmd "&docs_path.\DECISIONS.md";

    /* Write the marker line and table header */
    data _null_;
      file dcsnmd mod;
      put " ";
      put "<!-- OWN-03 CONFLICT ROWS GENERATED %sysfunc(datetime(), datetime20.) -->";
      put "| Variable | Sources | Declared Owner | Resolution |";
      put "|----------|---------|----------------|------------|";
    run;

    /* Write one markdown row per conflict variable */
    data _null_;
      set work.conflicts;
      file dcsnmd mod;
      put "| " name_u +(-1) " | " sources_present +(-1) " | TBD | Pending |";
    run;

    filename dcsnmd clear;
    %put NOTE: OWN-03 -- conflict block written to DECISIONS.md (&n_conflicts rows).;
  %end;
  %else %do;
    %put NOTE: OWN-03 conflict block already present in DECISIONS.md -- skipping append (re-run guard).;
  %end;
%mend write_own03_block;
%write_own03_block;


/*==========================================================================
  SECTION 6: OWN-04 -- Named coalesce-wanted variables with cross-source
             disagreement assertions.
             Macro compares one source (dsb) against the md3 spine (dsa).
             TYPE guard runs first (md8 cross-type trap, RESEARCH Pitfall 8).
             NULL sentinel guard is conditional on character type only.
             No VVALUE() -- not reliable in PROC SQL.
==========================================================================*/

%macro check_coalesce_agreement(var=, dsb=, dsa=master_data_3);
  %local n_disagree type_a type_b;

  /* Guard 1: both sides carry the variable, with the same type.
     Types come from work.allvars_src (Plan 01 Section 2).           */
  proc sql noprint;
    select type into :type_a trimmed from work.allvars_src
      where memname_u = upcase("&dsa") and name_u = upcase("&var");
    select type into :type_b trimmed from work.allvars_src
      where memname_u = upcase("&dsb") and name_u = upcase("&var");
  quit;

  %if %superq(type_a) = or %superq(type_b) = %then %do;
    %put NOTE: OWN-04 SKIP -- &var not present in both &dsa and &dsb.;
    %return;
  %end;
  %if &type_a ne &type_b %then %do;
    %put WARNING: OWN-04 TYPE MISMATCH -- &var is type &type_a in &dsa but &type_b in &dsb.;
    %put WARNING- Not comparable as values. Resolve the type before any coalesce.;
    %return;
  %end;

  /* Guard 2: md8 NULL sentinel -- CHARACTER variables only (type=2).
     A numeric cannot hold the sentinel; upcase() on a numeric forces
     an unwanted conversion. Type guard above runs first.              */
  proc sql noprint;
    create table work._coalesce_&var as
      select a.PRECEDE_STUDY_ID, a.&var as val_a, b.&var as val_b
      from src.&dsa as a
      inner join src.&dsb as b on a.PRECEDE_STUDY_ID = b.PRECEDE_STUDY_ID
      where not missing(a.&var) and not missing(b.&var)
        %if &type_a = 2 %then %do;
        and strip(upcase(a.&var)) ne 'NULL'
        and strip(upcase(b.&var)) ne 'NULL'
        %end;
        and a.&var ne b.&var;
    select count(*) into :n_disagree trimmed from work._coalesce_&var;
  quit;

  %if &n_disagree > 0 %then
    %put WARNING: OWN-04 -- &n_disagree rows where &var disagrees between &dsa and &dsb. Review before coalescing.;
  %else
    %put NOTE: OWN-04 OK -- &var consistent across &dsa/&dsb (or missing/NULL in all).;
%mend check_coalesce_agreement;

/* OWN-04: Admit_BMI and Race are the coalesce-wanted variables.
   Prior analysis (STATE.md) confirmed Admit_BMI coalescing recovers nothing --
   all 28,424 missings are missing at source, and no source disagreed.
   md3 is the fixed spine side; the other side iterates so md4-md8 are actually
   exercised. Add further coalesce-wanted variables here as identified.        */
%check_coalesce_agreement(var=Admit_BMI, dsb=master_data_1);
%check_coalesce_agreement(var=Admit_BMI, dsb=master_data_2);
%check_coalesce_agreement(var=Admit_BMI, dsb=master_data_4);
%check_coalesce_agreement(var=Admit_BMI, dsb=master_data_5);
%check_coalesce_agreement(var=Admit_BMI, dsb=master_data_6);
%check_coalesce_agreement(var=Admit_BMI, dsb=master_data_7);
%check_coalesce_agreement(var=Admit_BMI, dsb=master_data_8);  /* expect TYPE MISMATCH */

%check_coalesce_agreement(var=Race, dsb=master_data_1);
%check_coalesce_agreement(var=Race, dsb=master_data_2);
%check_coalesce_agreement(var=Race, dsb=master_data_4);
%check_coalesce_agreement(var=Race, dsb=master_data_5);
%check_coalesce_agreement(var=Race, dsb=master_data_6);
%check_coalesce_agreement(var=Race, dsb=master_data_7);
%check_coalesce_agreement(var=Race, dsb=master_data_8);

%put NOTE: OWN-04 -- add further coalesce-wanted variables to Section 6 as identified.;


/*==========================================================================
  SECTION 7: Close-out
==========================================================================*/

%put NOTE: ==== Phase 2 ownership map complete -- OWN-01..OWN-04 done ====;
libname src clear;
