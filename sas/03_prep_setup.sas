/*==========================================================================
  Program : 03_prep_setup.sas
  Phase   : Phase 3 -- Per-Source Normalization
  Purpose : Wave 0 setup and variable inventory.
            Creates the persistent g library assignment, confirms required
            output directories exist, and captures the authoritative variable
            inventory (names, types, lengths) for all eight sources --
            plus a character-variable-only extract so LENGTH statement blocks
            in Plans 02-05 are written from PROC CONTENTS fact, not inference.
  Requirements addressed:
            PREP-01 (g library assignable, output dirs confirmed)
            PREP-05 (character-variable width inventory -- input for LENGTH blocks)
            PREP-06 (logs/ confirmed present before any conversion log is written)
  Author  : Executor (Phase 3 Plan 01)
  Created : 2026-08-26
==========================================================================*/

options mprint nofmterr;

/* =========================================================================
   SECTION 0 -- Paths (canonical values reused verbatim by Plans 02-05)
   ========================================================================= */
%let source_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross;
%let qc_path     = C:\Master_Renamed_same_format_accross\qc;
%let logs_path   = C:\Master_Renamed_same_format_accross\logs;
%let g_path      = C:\PeCAN_work\data;   /* OUTSIDE the repo tree -- see RESEARCH Pitfall 9 */
libname src "&source_path" access=readonly;
libname g   "&g_path";

/* =========================================================================
   SECTION 1 -- Preconditions
   %abort cancel is valid only inside a macro definition (PCM-R-05).
   Each check is wrapped in a named macro and called immediately.
   ========================================================================= */
%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: LIBNAME &lib could not be assigned. Check the path.;
    %abort cancel;
  %end;
  %else %put NOTE: LIBNAME &lib resolved.;
%mend check_libname;

%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: &label directory does not exist: &path -- create it before running.;
    %abort cancel;
  %end;
  %else %put NOTE: &label directory present: &path.;
%mend check_dir;

/* Gate on src libref -- confirms P: drive is mapped */
%check_libname(lib=src);

/* Gate on g libref -- confirms C:\PeCAN_work\data\ exists (Task 1 of Plan 01) */
%check_libname(lib=g);

/* Confirm output directories */
%check_dir(path=&qc_path,   label=qc);
%check_dir(path=&logs_path, label=logs);

/* =========================================================================
   SECTION 2 -- Full variable inventory for all eight sources
   Uses IN not IN: -- IN: prefix-matches and would readmit stale master_data_7b
   (Phase 2 Pitfall 1).  Writes to work.allvars_src, never back into
   work.allvars (data X; set X; is prohibited, PCM-R-01 / PCM-T-02).
   ========================================================================= */
proc contents data=src._all_ out=work.allvars (keep=memname name type length varnum) noprint;
run;

data work.allvars_src;
  set work.allvars;
  where upcase(memname) in
    ('MASTER_DATA_1','MASTER_DATA_2','MASTER_DATA_3','MASTER_DATA_4',
     'MASTER_DATA_5','MASTER_DATA_6','MASTER_DATA_7','MASTER_DATA_8');
run;

proc sort data=work.allvars_src; by memname varnum; run;

/* =========================================================================
   SECTION 3 -- Write the full inventory to qc/03_contents_all.txt
   Human-readable; committed to version control.
   type=1 is NUMERIC, type=2 is CHARACTER.
   ========================================================================= */
filename cnall "&qc_path.\03_contents_all.txt";
data _null_;
  set work.allvars_src end=last;
  file cnall;
  if _n_ = 1 then do;
    put "Phase 3 Variable Inventory (all eight sources) -- Run: %sysfunc(datetime(), datetime20.)";
    put @1 "Source" @22 "Variable" @56 "Type" @64 "Length";
    put @1 "-------------------------------------------------------------------------";
  end;
  put @1 memname $20. @22 name $32. @56 type 3. @64 length 5.;
run;
filename cnall clear;

/* =========================================================================
   SECTION 4 -- CHARACTER-ONLY inventory to qc/03_charvars_all.txt
   This is the source of truth for LENGTH statement blocks in Plans 02-05.
   type=2 is CHARACTER.
   ========================================================================= */
data work.charvars;
  set work.allvars_src;
  where type = 2;   /* type=2 is character */
run;

filename chall "&qc_path.\03_charvars_all.txt";
data _null_;
  set work.charvars end=last;
  file chall;
  if _n_ = 1 then do;
    put "Phase 3 CHARACTER variables and widths (source of truth for LENGTH blocks) -- Run: %sysfunc(datetime(), datetime20.)";
    put @1 "Source" @22 "CharVariable" @56 "Width";
    put @1 "-------------------------------------------------------------";
  end;
  put @1 memname $20. @22 name $32. @56 length 5.;
run;
filename chall clear;

/* =========================================================================
   SECTION 5 -- Close-out
   libname src and libname g are intentionally left assigned (matches
   Phase 2 close-out convention; harmless since nothing else runs here).
   ========================================================================= */
%put NOTE: ==== Phase 3 Wave 0 setup complete -- inventory written, g library assigned ====;
