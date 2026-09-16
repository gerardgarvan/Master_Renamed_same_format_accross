/*==========================================================================
  Program : macros_raw_import.sas
  Purpose : Shared import macros for supplemental raw files.
            %import_csv  -- PROC IMPORT for CSV files (guessingrows=max)
            %import_xlsx -- XLSX engine import for all sheets in a workbook
            Moved verbatim from 16_raw_inventory.sas to this shared file
            so that both 16_raw_inventory.sas and 18_supplemental_raw_gap.sas
            reference one copy. Do NOT copy or redefine these macros in any
            program that %includes this file.

  Requires: &raw_path (defined in 00_config.sas)
            work.dslist (created by %ensure_dslist below if not already present)

  PCM compliance:
    - No bare open-code %IF/%THEN; all conditional logic in named macros
    - No apostrophes or embedded semicolons in %PUT text
    - ASCII only
==========================================================================*/

/* ---- Guard: create work.dslist if not already present ---- */
%macro ensure_dslist;
  %if %sysfunc(exist(work.dslist)) = 0 %then %do;
    data work.dslist;
      length rid $3 fname $80 sheet $64 memname $32;
      stop;
    run;
  %end;
%mend ensure_dslist;
%ensure_dslist;

/* ---- %import_csv(rid, fname) ------------------------------------------ */
/* Imports a CSV from &raw_path into work.&rid using PROC IMPORT.           */
/* guessingrows=max ensures type detection is based on the full file.        */
/* Records the imported dataset in work.dslist.                             */
%macro import_csv(rid, fname);
  proc import datafile="&raw_path\&fname"
      out=work.&rid dbms=csv replace;
      guessingrows=max;
  run;

  proc sql noprint;
    insert into work.dslist
      set rid     = "&rid",
          fname   = "&fname",
          sheet   = "csv",
          memname = upcase("&rid");
  quit;
%mend import_csv;

/* ---- %import_xlsx(rid, fname) ----------------------------------------- */
/* Assigns libname xin using the XLSX engine (access=readonly).              */
/* Enumerates every sheet via dictionary.tables and copies each into         */
/* work.&rid._s1, work.&rid._s2, etc. via call execute.                      */
/* Records each sheet dataset in work.dslist.                               */
/* Requires validmemname=extend (set in calling program) so that sheet names */
/* starting with a digit can be referenced as SAS name literals.             */
%macro import_xlsx(rid, fname);
  libname xin xlsx "&raw_path\&fname" access=readonly;

  /* Enumerate sheets into a helper dataset */
  proc sql noprint;
    create table work._sheets_&rid as
      select memname
      from dictionary.tables
      where libname = 'XIN'
      order by memname;
  quit;

  /* Count sheets */
  %let _ns_&rid = 0;
  proc sql noprint;
    select count(*) into :_ns_&rid trimmed
    from work._sheets_&rid;
  quit;

  /* Copy each sheet via call execute with a sequential suffix */
  data _null_;
    set work._sheets_&rid;
    suf = put(_n_, z2.);
    /* Build the output dataset name with sequential suffix */
    out_ds = "work.&rid._s" || strip(put(_n_, best32.));
    /* Reference the sheet as a SAS name literal */
    stmt = "data " || strip(out_ds) || "; set xin.'" || strip(memname) || "'n; run;";
    call execute(stmt);
    /* Record in dslist */
    ins = "proc sql noprint; insert into work.dslist "
       || "set rid='" || "&rid" || "', "
       || "fname='" || "&fname" || "', "
       || "sheet='" || strip(memname) || "', "
       || "memname='" || upcase("&rid") || "_S" || strip(put(_n_, best32.)) || "'; quit;";
    call execute(ins);
  run;

  libname xin clear;
%mend import_xlsx;
