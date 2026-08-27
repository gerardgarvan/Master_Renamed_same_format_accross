/*==========================================================================
  Program : 03_prep_all.sas
  Phase   : Phase 3 -- Per-Source Normalization (Driver)
  Purpose : Run setup + all eight structural prep programs in one command,
            then write a consolidated summary confirming all eight g.prep_mdN
            datasets exist with their expected row counts. Aborts if any
            dataset is missing or has a wrong row count.
  Requirements addressed:
            PREP-01 (all eight prep programs run; single-command phase runner)
            PREP-02 (consolidated existence check)
            PREP-05 (each included program gates LENGTH-before-SET)
            PREP-06 (all 16 per-source artifacts confirmed downstream)
  Usage   : sas -sysin "C:\Master_Renamed_same_format_accross\sas\03_prep_all.sas"
                 -log "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs\03_prep_all.log"
            (code on C: in git; logs and data on P: outside git)
            (or open in SAS Display Manager and submit; close SAS between phases)
  Author  : Executor (Phase 3 Plan 05)
  Created : 2026-08-26
==========================================================================*/

options mprint nofmterr;


/*==========================================================================
  SECTION 0: Paths and libnames
  These declarations are redundant when included after 03_prep_setup.sas
  but are kept here so this driver can be submitted standalone (e.g. for
  debugging). Each included prep program also declares its own paths.
==========================================================================*/

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
/* sas_path corrected 2026-08-27. It previously pointed at
   a sas\ folder that did not exist at the time -- so all nine
   %include statements below resolved to nothing. The driver ran, included no
   programs, and produced no PREP-08 nulling and no PREP-09 reports, with no error
   obvious enough to notice. If a future run produces no logs/03_negtime_mdN.txt
   files, check this line first.                                                   */
libname src "&source_path" access=readonly;
libname g   "&g_path";


/*==========================================================================
  SECTION 1: Run setup + all eight prep programs in order
  Each prep program is self-contained (declares its own libnames, writes its
  own exception report and conversion log, and asserts its own row count).
  %include-ing them sequentially in one session is safe -- libname assignments
  are idempotent and each writes a distinct g.prep_mdN.
  %abort cancel inside any included program cancels this entire submit.
==========================================================================*/

%include "&sas_path.\03_prep_setup.sas";
%include "&sas_path.\03_prep_md1.sas";
%include "&sas_path.\03_prep_md2.sas";
%include "&sas_path.\03_prep_md3.sas";
%include "&sas_path.\03_prep_md4.sas";
%include "&sas_path.\03_prep_md5.sas";
%include "&sas_path.\03_prep_md6.sas";
%include "&sas_path.\03_prep_md7.sas";
%include "&sas_path.\03_prep_md8.sas";


/*==========================================================================
  SECTION 2: Consolidated summary
  For each g.prep_mdN, check existence then row count. Expected values are
  stored in global macro variables via one_summary so the count appears in
  exactly ONE place per source -- in the one_summary call. The assertion
  macro reads &&exp&i and &&act&i to avoid maintaining three copies.
  Uses SELECT ... INTO :n TRIMMED (never &SQLOBS per project convention).
==========================================================================*/

%macro one_summary(n=, expected=);
  %global act&n exp&n;
  %let exp&n = &expected;
  proc sql noprint;
    select count(*) into :exists_&n trimmed from dictionary.tables
      where libname='G' and memname="PREP_MD&n";
  quit;
  %if &&exists_&n = 0 %then %do;
    %let act&n = MISSING;
  %end;
  %else %do;
    proc sql noprint;
      select count(*) into :act&n trimmed from g.prep_md&n;
    quit;
  %end;
%mend one_summary;

%one_summary(n=1, expected=14778);
%one_summary(n=2, expected=14778);
%one_summary(n=3, expected=41150);
%one_summary(n=4, expected=7695);
%one_summary(n=5, expected=7695);
%one_summary(n=6, expected=9462);
%one_summary(n=7, expected=9215);
%one_summary(n=8, expected=22473);

filename sumf "&qc_path.\03_prep_summary.txt";
data _null_;
  file sumf;
  put "Phase 3 Prep Summary -- Run: %sysfunc(datetime(), datetime20.)";
  put @1 "Dataset" @20 "Expected" @35 "Actual";
  put @1 "----------------------------------------";
  put @1 "g.prep_md1" @20 "&exp1" @35 "&act1";
  put @1 "g.prep_md2" @20 "&exp2" @35 "&act2";
  put @1 "g.prep_md3" @20 "&exp3" @35 "&act3";
  put @1 "g.prep_md4" @20 "&exp4" @35 "&act4";
  put @1 "g.prep_md5" @20 "&exp5" @35 "&act5";
  put @1 "g.prep_md6" @20 "&exp6" @35 "&act6";
  put @1 "g.prep_md7" @20 "&exp7" @35 "&act7";
  put @1 "g.prep_md8" @20 "&exp8" @35 "&act8";
run;
filename sumf clear;


/*==========================================================================
  SECTION 3: Final assertion gate
  Build a mismatch count; abort with a clear error message if nonzero.
  Each source's expected count is read from &&exp&i (set by one_summary)
  so there is a single authoritative source per count.
==========================================================================*/

%macro assert_all;
  %local bad;
  %let bad = 0;
  %local i;
  %do i = 1 %to 8;
    %if &&act&i ne &&exp&i %then %do;
      %put ERROR: Phase 3 summary -- g.prep_md&i expected &&exp&i got &&act&i;
      %let bad = %eval(&bad+1);
    %end;
  %end;
  %if &bad > 0 %then %do;
    %put ERROR: Phase 3 summary -- &bad of 8 prep datasets missing or wrong row count. See qc/03_prep_summary.txt.;
    %abort cancel;
  %end;
  %else %put NOTE: ==== Phase 3 COMPLETE -- all 8 g.prep_mdN present with correct row counts ====;
%mend assert_all;
%assert_all;
