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
%let qc_path     = C:\Master_Renamed_same_format_accross\qc;
%let docs_path   = C:\Master_Renamed_same_format_accross\docs;
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
