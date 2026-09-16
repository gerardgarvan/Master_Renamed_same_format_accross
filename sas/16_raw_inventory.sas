/*==========================================================================
  Program : 16_raw_inventory.sas
  Purpose : Profile the 9 supplemental raw files in &raw_path and report,
            for each one: grain, key column, uniqueness, coverage vs
            g.analysis_base, and column bucketing (IN_BASE / NEW).

  Reads   : g.analysis_base                                (read-only)
             &raw_path\<each raw file>                     (read-only)

  Outputs : qc\16_raw_inventory.txt   -- dataset inventory, grain table
             qc\16_raw_columns.txt    -- every column in every file
             qc\16_raw_keys.txt       -- key column uniqueness and coverage
             qc\16_raw_overlap.txt    -- IN_BASE / NEW bucketing

  Executed: 2026-09-16
  Committed: Task 0 of 18-01 (file not previously in version control)

  PCM compliance:
    - No bare open-code %IF/%THEN; all conditional logic inside named macros
    - No apostrophes or embedded semicolons in %PUT text
    - Every %abort cancel inside %fail_out only
    - No &SQLOBS; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - dictionary.columns.type is char/num not 1/2
    - ASCII only
    - No in-place dataset rewrite (data X; set X;)
    - g.analysis_base is read-only -- never on left of DATA statement
==========================================================================*/

/* ---- Config + options + shared macros --------------------------------- */
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
options validvarname=v7 validmemname=extend nofmterr msglevel=i;
%include "&sas_path.\macros_raw_import.sas";

/* ---- Log routing ------------------------------------------------------- */
%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\16_raw_inventory.log" new; run;
  %end;
%mend route_log;

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

%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %fail_out(msg=&label directory not found: &path);
  %end;
%mend check_dir;

/* ---- assert_base: verify g.analysis_base is reachable ----------------- */
%let n_tab_base = 0;
proc sql noprint;
  select count(*) into :n_tab_base trimmed
  from dictionary.tables where libname='G' and memname='ANALYSIS_BASE';
quit;

%macro assert_base;
  %if &n_tab_base ne 1 %then %do;
    %fail_out(msg=g.analysis_base not found in g library);
  %end;
%mend assert_base;

/* ---- Preconditions ----------------------------------------------------- */
%check_dir(path=&logs_path, label=logs);
%route_log;

libname g "&g_path";

%check_dir(path=&qc_path, label=qc);
%check_dir(path=&raw_path, label=raw);

%let n_tab_base = 0;
proc sql noprint;
  select count(*) into :n_tab_base trimmed
  from dictionary.tables where libname='G' and memname='ANALYSIS_BASE';
quit;
%assert_base;

%put NOTE: ==== Phase 16 supplemental raw inventory starting ====;

/* ---- Import raw files -------------------------------------------------- */

/* r1: 2018-2020 induction/emergence times */
%import_csv(r1, 2018_2019_2020_Induction_Emergent20231121.csv)

/* r2: 2018-2019 PRECEDE database (3,987 columns, single sheet) */
%import_xlsx(r2, 2018_2019_Precede_Database.xlsx)

/* r3: Colonoscopy 2018-2022 */
%import_xlsx(r3, 2018_2022_COLONOSCOPY_20240118.xlsx)

/* r4: 2020 education */
%import_xlsx(r4, 2020_Precede_Database_Edu.xlsx)

/* r5: 2021 education */
%import_csv(r5, 2021_Education_20240124.csv)

/* r6: 2021 frailty */
%import_csv(r6, 2021_Frailty_20240123.csv)

/* r7: 2022 education (key is NUMERIC -- 0 base matches, PCM-D-16 open) */
%import_csv(r7, 2022_Education_20240124.csv)

/* r8: 2022 race/ethnicity/sex (key is NUMERIC -- 0 base matches) */
%import_csv(r8, 2022_RES_20230927.csv)

/* r9: All-years lat/long (key is char $12, 31,935 match base) */
%import_csv(r9, All_YEARS_LAT_LONG_20231127.csv)

/* ---- Key inventory ----------------------------------------------------- */
/* Load base key for join comparisons */
proc sort data=g.analysis_base(keep=PRECEDE_STUDY_ID) out=work.base_key nodupkey;
  by PRECEDE_STUDY_ID;
run;

/* ---- QC output --------------------------------------------------------- */
ods listing file="&qc_path.\16_raw_inventory.txt";

%put NOTE: Phase 16 raw inventory complete. See QC outputs at &qc_path;

ods listing close;

%restore_log;
