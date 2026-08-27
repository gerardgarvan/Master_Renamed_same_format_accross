/*==========================================================================
  Program : 99_run_all.sas
  Purpose : Full pipeline runner. Submits all eight phases in order in a
            single clean SAS session. Any %abort cancel in an included
            program stops execution immediately; the log shows which phase
            failed.

  Pipeline
    Phase 1  01_verify_sources.sas  -- source preconditions, checksums
    Phase 2  02_ownership.sas       -- ownership map (qclib.ownership_map)
    Phase 3  03_prep_all.sas        -- per-source normalization (md1..8)
    Phase 4  04_merge.sas           -- ownership-governed merge
    Phase 5  05_qc_merge.sas        -- QC assertions on merged file
    Phase 6  06_reconcile.sas       -- variable reconciliation
    Phase 7  07_cohort.sas          -- cohort definition & missingness
    Phase 8  08_dictionary.sas      -- data dictionary (docs/DATA_DICTIONARY.xlsx)

  Expected final output
    g.master_data_merged   41,150 rows
    g.analytic_cohort      cohort subset
    docs/DATA_DICTIONARY.xlsx  variable dictionary (gitignored; produced on the analyst machine)
    qc/                    all QC artifacts
    logs/                  all per-phase logs

  Usage (batch)
    sas -sysin "C:\Master_Renamed_same_format_accross\sas\99_run_all.sas" ^
        -log   "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs\99_run_all.log"

    Code is on C: (in git); logs and data are on P: (outside git). The -sysin path
    is the only hardcoded path outside 00_config.sas.

  Usage (Display Manager)
    Open, select all, Submit. Close and reopen SAS between full runs to
    guarantee a clean session (macro symbol table, libname assignments).

  Author  : 2026-08-27
==========================================================================*/

options mprint nofmterr nodate nonumber ps=max ls=200;

/* ---- Single path config; all macros (&sas_path etc.) resolve from here ---- */
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* This driver owns the master log. Suppress each program's own PROC PRINTTO
   redirection so the -log file is a complete record of the whole run.        */
%let in_pipeline = 1;

%put NOTE: ============================================================;
%put NOTE: 99_run_all.sas -- pipeline start;
%put NOTE: sas_path    = &sas_path;
%put NOTE: source_path = &source_path;
%put NOTE: g_path      = &g_path;
%put NOTE: qc_path     = &qc_path;
%put NOTE: logs_path   = &logs_path;
%put NOTE: ============================================================;


/* =========================================================================
   PHASE 1 -- Source Verification & Freeze
   Assigns libname src (read-only). Checks keys, checksums, row counts.
   Clears src at the end; Phase 2 reassigns it from &source_path.
   ========================================================================= */
%put NOTE: ---- Phase 1: Source Verification ---------------------------;
%include "&sas_path.\01_verify_sources.sas";
%put NOTE: ---- Phase 1 complete --------------------------------------;


/* =========================================================================
   PHASE 2 -- Ownership Map
   Reads src. Writes qclib.ownership_map and qc/02_ownership_map.txt.
   Clears src and qclib at end.
   ========================================================================= */
%put NOTE: ---- Phase 2: Ownership Map --------------------------------;
%include "&sas_path.\02_ownership.sas";
%put NOTE: ---- Phase 2 complete --------------------------------------;


/* =========================================================================
   PHASE 3 -- Per-Source Normalization
   03_prep_all.sas is the phase driver: it %include-s 03_prep_setup.sas
   then 03_prep_md1..8.sas in order. Each sub-program is self-contained.
   Writes g.prep_md1..8. Aborts if any dataset is missing or wrong count.
   ========================================================================= */
%put NOTE: ---- Phase 3: Per-Source Normalization ----------------------;
%include "&sas_path.\03_prep_all.sas";
%put NOTE: ---- Phase 3 complete --------------------------------------;


/* =========================================================================
   PHASE 4 -- Ownership-Governed Merge
   Reads g.prep_md1..8 and qclib.ownership_map. Writes g.master_data_merged
   (41,150 rows). Leaves libname g open for Phases 5-7.
   ========================================================================= */
%put NOTE: ---- Phase 4: Merge ----------------------------------------;
%include "&sas_path.\04_merge.sas";
%put NOTE: ---- Phase 4 complete --------------------------------------;


/* =========================================================================
   PHASE 5 -- QC on Merged File
   Reads g.master_data_merged and qclib.ownership_map. Writes QC artifacts.
   ========================================================================= */
%put NOTE: ---- Phase 5: QC Merge -------------------------------------;
%include "&sas_path.\05_qc_merge.sas";
%put NOTE: ---- Phase 5 complete --------------------------------------;


/* =========================================================================
   PHASE 6 -- Variable Reconciliation
   Reads g.master_data_merged. Writes reconciliation QC artifacts.
   ========================================================================= */
%put NOTE: ---- Phase 6: Variable Reconciliation ----------------------;
%include "&sas_path.\06_reconcile.sas";
%put NOTE: ---- Phase 6 complete --------------------------------------;


/* =========================================================================
   PHASE 7 -- Cohort Definition & Missingness
   Reads g.master_data_merged. Writes g.analytic_cohort and QC artifacts.
   ========================================================================= */
%put NOTE: ---- Phase 7: Cohort & Missingness ------------------------;
%include "&sas_path.\07_cohort.sas";
%put NOTE: ---- Phase 7 complete --------------------------------------;


/* =========================================================================
   PHASE 8 -- Documentation & Handoff
   Reads g.master_data_merged and qclib.ownership_map (read-only).
   Reads docs/data_dictionary_notes.txt for derivation metadata.
   Writes docs/DATA_DICTIONARY.xlsx.
   ========================================================================= */
%put NOTE: ---- Phase 8: Documentation & Handoff --------------------;
%include "&sas_path.\08_dictionary.sas";
%put NOTE: ---- Phase 8 complete --------------------------------------;


/* =========================================================================
   PIPELINE COMPLETE
   ========================================================================= */
%put NOTE: ============================================================;
%put NOTE: 99_run_all.sas -- all phases complete.;
%put NOTE: g.master_data_merged and g.analytic_cohort are ready.;
%put NOTE: docs/DATA_DICTIONARY.xlsx written to: &docs_path;
%put NOTE: QC artifacts are in: &qc_path;
%put NOTE: Logs are in:         &logs_path;
%put NOTE: ============================================================;
