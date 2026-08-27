/*==========================================================================
  Program : 00_config.sas
  Purpose : Single source of truth for all six path macro variables.
            Every other program in this pipeline starts with:
              %include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
            and then references &sas_path, &docs_path, &source_path,
            &g_path, &qc_path, &logs_path -- never hardcoding them again.
  Paths   : Code and docs on C: (version-controlled).
            Data, QC output, and logs on P: (PHI -- outside the repo).
  Author  : Path fix (2026-08-27)
  Revised :
==========================================================================*/

/* ---- Code paths (C: -- in git) ---- */
%let sas_path   = C:\Master_Renamed_same_format_accross\sas;
%let docs_path  = C:\Master_Renamed_same_format_accross\docs;

/* ---- Data paths (P: -- NOT in git, PHI lives here) ---- */
%let source_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross;
%let g_path      = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge;
%let qc_path     = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc;
%let logs_path   = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs;

/* ---- Pipeline flag ----
   0 = running standalone; the program redirects the log to its own file.
   1 = running under 99_run_all.sas, which owns the master log.

   The %SYMEXIST guard is essential. 99_run_all.sas sets in_pipeline=1 after its
   own include, but every phase program then re-includes THIS file. An
   unconditional %let would reset the flag to 0 on every phase, so each program
   would redirect the log to its own file and the master log would have a hole
   exactly where a failure needs investigating.                              */
%if not %symexist(in_pipeline) %then %let in_pipeline = 0;

%put NOTE: [00_config] sas_path    = &sas_path;
%put NOTE: [00_config] docs_path   = &docs_path;
%put NOTE: [00_config] source_path = &source_path;
%put NOTE: [00_config] g_path      = &g_path;
%put NOTE: [00_config] qc_path     = &qc_path;
%put NOTE: [00_config] logs_path   = &logs_path;
