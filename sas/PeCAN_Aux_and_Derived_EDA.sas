/*=============================================================================
  PeCAN Propensity Paper
  Exploratory data analysis: auxiliary data sets + derived variables

  Author : Gerard Garvan
  Created: 2026-08-31

  WHAT THIS PROGRAM DOES
    Section 0  Setup, libraries, UF-styled ODS destinations
    Section 1  Inventory of the auxiliary folder (what is actually on disk)
    Section 2  Import every auxiliary data set in its native format
    Section 3  Harmonize the merge key across auxiliary files
    Section 4  Per-file profiling: structure, key integrity, missingness,
               numeric distributions, character levels
    Section 5  Key overlap between each auxiliary file and the analysis master
    Section 6  Re-derive the create_data-stage variables (6a: merge cardinality)
    Section 7  Re-derive the MCI phenotype variables
    Section 8  Re-derive the 2024 analysis-block variables
    Section 9  Compare re-derived values against the stored values
               9a create_data stage   9b MCI phenotype   9c education bands
               9e master ADI vs relocated auxiliary ADI  9f summary
    Section 10 EDA on the derived variables
               10a-c distributions  10d recode verification
               10e unmapped source values  10f inherited logic issues
    Section 11 Consolidated missingness report and wrap-up

  THREE INHERITED LOGIC ISSUES ARE REPRODUCED VERBATIM, NOT SILENTLY FIXED
    - race_sa2 assigns back to race_sa for the "Other" branch
    - Edu_Years and MoCA tests treat numeric missing as the lowest value
    - the clock-face area parentheses do not average the two half-diameters
    - MCI_Group applies the ATT_AVG then MEM_AVG cutpoints to the same variable
  Each is commented at the point it occurs and measured in Section 10f, so the
  comparisons against the stored master stay meaningful. Decide, then change
  them deliberately.

  ASSUMPTIONS - CHANGE THESE IF THEY ARE WRONG
    - Auxiliary files kept their original extensions (.xlsx / .csv / .sas7bdat).
    - The two SAS auxiliary files sit loose in the folder, so LIBNAME AUX can
      read them as AUX.ADI_DATA and AUX._2018_2019_CU_LOS_DETAIL_EXIT_20.
    - The master and analysis-master data sets are still on Z:. Only the
      auxiliary inputs moved to P:.
    - PROC IMPORT with DBMS=XLSX requires SAS/ACCESS to PC Files. If that is
      not licensed, set XLSXENGINE=EXCELCS or convert the workbooks first.
=============================================================================*/

options ls=132 ps=60 nodate number mprint mlogic symbolgen nofmterr
        validvarname=v7 msglevel=i;
ods graphics on / width=6.5in height=4in;


/*=============================================================================
  SECTION 0 - PATHS, LIBRARIES, ODS STYLE
=============================================================================*/

/* --- auxiliary folder (the consolidated copies) ------------------------- */
%let auxpath   = P:\PeCAN Master Data\Gerard\Auxilary Data Sets;

/* --- original master locations ------------------------------------------ */
%let proppath  = Z:\PeCAN Master Data\Garvan\Propensity Paper\Data;
%let newprog   = Z:\PeCAN Master Data\Garvan\Propensity Paper\New Programs;

/* --- where EDA output is written ---------------------------------------- */
%let outpath   = P:\PeCAN Master Data\Gerard\Auxilary Data Sets\EDA Output;

libname aux  "&auxpath";
libname c1   "&proppath"  access=readonly;
libname c2   "&newprog"   access=readonly;
libname edaout "&outpath";

/* --- master data set names ---------------------------------------------- */
%let MASTER   = c1.cognitive_clock_sa_7_22_FINAL;   /* PeCAN master          */
%let ANALYSIS = c2.pecandata20230926v2;             /* analysis master       */
%let KEY      = PRECEDE_Study_ID;                   /* merge key everywhere  */

/* --- UF-branded output style -------------------------------------------- */
proc template;
  define style styles.uf;
    parent = styles.rtf;
    class fonts /
      'TitleFont'    = ("Arial", 12pt, bold)
      'TitleFont2'   = ("Arial", 11pt, bold)
      'HeadingFont'  = ("Arial", 10pt, bold)
      'docFont'      = ("Arial",  9pt)
      'StrongFont'   = ("Arial",  9pt, bold);
    class SystemTitle  / foreground = cx0021A5;
    class SystemFooter / foreground = cx555555;
    class Header       / backgroundcolor = cx0021A5
                         foreground      = cxFFFFFF
                         fontweight      = bold;
    class RowHeader    / backgroundcolor = cxE8ECF7
                         foreground      = cx0021A5;
    class Table        / bordercolor = cx0021A5 cellpadding = 3 rules = groups;
    class GraphColors  /
      'gdata1'  = cx0021A5
      'gdata2'  = cxFA4616
      'gdata3'  = cx6E8BD9
      'gcdata'  = cx0021A5
      'gdata'   = cx0021A5
      'gcfill'  = cx0021A5;
    class GraphFonts   /
      'GraphTitleFont'  = ("Arial", 11pt, bold)
      'GraphLabelFont'  = ("Arial",  9pt)
      'GraphValueFont'  = ("Arial",  8pt);
  end;
run;

ods _all_ close;
ods rtf file="&outpath\PeCAN_EDA_%sysfunc(today(),yymmddn8.).rtf"
        style=styles.uf startpage=no;
ods listing;

footnote "PeCAN Propensity Paper EDA - generated &sysdate9 &systime";


/*=============================================================================
  SECTION 1 - FOLDER INVENTORY
  Confirms what is actually sitting in the auxiliary folder before anything
  tries to read it. Run this first if a later import fails.
=============================================================================*/

data aux_inventory;
  length File_Name $200 Extension $20;
  rc  = filename('auxdir', "&auxpath");
  did = dopen('auxdir');
  if did = 0 then do;
     put "ERROR: Cannot open &auxpath";
     stop;
  end;
  n = dnum(did);
  do i = 1 to n;
     File_Name = dread(did, i);
     Extension = upcase(scan(File_Name, -1, '.'));
     output;
  end;
  rc = dclose(did);
  keep File_Name Extension;
run;

proc sort data=aux_inventory; by Extension File_Name; run;

title1 "Section 1. Contents of &auxpath";
proc print data=aux_inventory noobs label;
  var Extension File_Name;
  label Extension = "Type" File_Name = "File";
run;

proc freq data=aux_inventory;
  tables Extension / nocum;
  title2 "File count by type";
run;
title;


/*=============================================================================
  SECTION 2 - IMPORT THE AUXILIARY DATA SETS
=============================================================================*/

/* ---- Excel / CSV imports ----------------------------------------------- */
proc import out = raw_parkinson
            datafile = "&auxpath\2018_2019_2020_Parkinson_20211203.xlsx"
            dbms = xlsx replace;
  getnames = yes;
  sheet = "2018_2019_2020_Parkinson_202112";
run;

proc import out = raw_icdfind
            datafile = "&auxpath\2018_2019_ICD_FIND_out_20210525.csv"
            dbms = csv replace;
  getnames = yes;
  guessingrows = max;
run;

proc import out = raw_precede
            datafile = "&auxpath\2018_2019_Precede_Database.xlsx"
            dbms = xlsx replace;
  getnames = yes;
  sheet = "2018_2019_Precede_Database";
run;

proc import out = raw_transfuse
            datafile = "&auxpath\2018_2019_INTAOP_Blood_Loss_Transfused_20210816.xlsx"
            dbms = xlsx replace;
  getnames = yes;
  sheet = "Sheet1";
run;

proc import out = raw_cbc
            datafile = "&auxpath\2018_2019_X_PREOP_CBC_90_DAYS_BEFORE_SURGERY_MOST_RECENT_20210816.xlsx"
            dbms = xlsx replace;
  getnames = yes;
  sheet = "Sheet1";
run;

proc import out = raw_preoplab
            datafile = "&auxpath\2018_2019_X_PREOP_LAB_90_DAYS_BEFORE_SURGERY_MOST_RECENT_Blood_20210816.xlsx"
            dbms = xlsx replace;
  getnames = yes;
  sheet = "Sheet1";
run;

/* ---- SAS data sets already readable through LIBNAME AUX ---------------- */
data raw_adi;
  set aux.adi_data;
run;

data raw_icu;
  set aux._2018_2019_cu_los_detail_exit_20;
run;


/*=============================================================================
  SECTION 3 - HARMONIZE THE MERGE KEY
  Each source names the study identifier differently. Everything gets a
  character PRECEDE_Study_ID of length 25 so keys compare cleanly.
=============================================================================*/

/*-----------------------------------------------------------------------------
  CATS() rather than STRIP() so a source whose ID imported as numeric converts
  cleanly instead of throwing a conversion note. Where the source variable is
  already named PRECEDE_Study_ID, the LENGTH statement only sets the length;
  if any source imported that column as numeric, SAS will stop with a
  type-conflict error. PROC CONTENTS in Section 4 will show which is which.
-----------------------------------------------------------------------------*/
%macro setkey(in=, out=, from=);
  data &out;
    length &KEY $25;
    set &in;
    &KEY = cats(&from);
    if &KEY in (".", "") then &KEY = "";
  run;
  proc sort data=&out; by &KEY; run;
%mend setkey;

%setkey(in=raw_adi,       out=aux_adi,       from=studyid)
%setkey(in=raw_parkinson, out=aux_parkinson, from=Study_ID)
%setkey(in=raw_icdfind,   out=aux_icdfind,   from=Study_ID)
%setkey(in=raw_precede,   out=aux_precede,   from=studyid)
%setkey(in=raw_icu,       out=aux_icu,       from=PRECEDE_Study_ID)
%setkey(in=raw_transfuse, out=aux_transfuse, from=PRECEDE_Study_ID)
%setkey(in=raw_cbc,       out=aux_cbc,       from=PRECEDE_Study_ID)
%setkey(in=raw_preoplab,  out=aux_preoplab,  from=PRECEDE_Study_ID)


/*=============================================================================
  SECTION 4 - PER-FILE PROFILING
=============================================================================*/

/* ---- reusable missingness profiler ------------------------------------- */
%macro miss_profile(lib=WORK, ds=, label=);
  %local nv nobs;

  proc sql noprint;
    create table _vars as
      select name,
             type,
             varnum,
             length as Var_Length
        from dictionary.columns
       where libname = upcase("&lib")
         and memname = upcase("&ds")
       order by varnum;
    select count(*) into :nv trimmed from _vars;
  quit;

  %if &nv = 0 %then %do;
    %put WARNING: &lib..&ds has no columns or does not exist. Skipped.;
    %return;
  %end;

  data _null_;
    set _vars end=eof;
    length s $32000;
    retain s '';
    s = catx(', ', s,
             cats('sum(missing(', nliteral(name), ')) as _M', put(_n_, z4.)));
    if eof then call symputx('_msel', s);
  run;

  proc sql noprint;
    create table _mwide as
      select count(*) as _NOBS, &_msel from &lib..&ds;
    select _NOBS into :nobs trimmed from _mwide;
  quit;

  proc transpose data=_mwide(drop=_NOBS)
                 out=_mlong(rename=(col1=N_Missing)) name=_pos;
    var _M:;
  run;

  data _mrep;
    merge _vars(rename=(name=Variable)) _mlong(keep=N_Missing);
    length Data_Set $32 Source_Label $60 Var_Type $9;
    Data_Set     = "&ds";
    Source_Label = "&label";
    Var_Type     = ifc(lowcase(type)='num', 'Numeric', 'Character');
    N_Obs        = &nobs;
    N_Present    = N_Obs - N_Missing;
    Pct_Missing  = 100 * N_Missing / max(N_Obs, 1);
    keep Data_Set Source_Label varnum Variable Var_Type Var_Length
         N_Obs N_Present N_Missing Pct_Missing;
  run;

  proc append base=eda_missing_all data=_mrep force; run;

  title2 "Missingness by variable";
  proc print data=_mrep noobs label;
    var varnum Variable Var_Type Var_Length N_Obs N_Present N_Missing Pct_Missing;
    label varnum      = "#"
          Var_Type    = "Type"
          Var_Length  = "Len"
          N_Obs       = "Rows"
          N_Present   = "Present"
          N_Missing   = "Missing"
          Pct_Missing = "% Missing";
    format Pct_Missing 6.1 N_Obs N_Present N_Missing comma10.;
  run;

  proc datasets lib=work nolist;
    delete _vars _mwide _mlong _mrep;
  quit;
%mend miss_profile;


/* ---- full profile for one auxiliary file -------------------------------- */
%macro profile(ds=, label=);
  title1 "Section 4. &label";

  title2 "Structure";
  proc contents data=&ds varnum;
  run;

  title2 "Row and key counts";
  proc sql;
    select count(*)                 label="Rows"                as n_rows   format=comma12.,
           count(distinct &KEY)     label="Distinct study IDs"  as n_ids    format=comma12.,
           sum(missing(&KEY))       label="Rows with blank ID"  as n_noid   format=comma12.,
           count(*) - count(distinct &KEY)
                                    label="Rows above one per ID" as n_extra format=comma12.
      from &ds;
  quit;

  title2 "Duplicate study IDs";
  proc freq data=&ds noprint;
    tables &KEY / out=_dups(where=(count > 1 and not missing(&KEY)));
  run;
  proc sql noprint; select count(*) into :ndup trimmed from _dups; quit;
  %if &ndup = 0 %then %do;
    data _note; length Result $80; Result = "No duplicate study IDs."; run;
    proc print data=_note noobs label; label Result="Result"; run;
  %end;
  %else %do;
    proc print data=_dups(obs=25) noobs label;
      var &KEY count;
      label count = "Rows for this ID";
      title3 "&ndup duplicated IDs - first 25 shown (expected for long-format files)";
    run;
  %end;

  %miss_profile(lib=WORK, ds=&ds, label=&label)

  title2 "Numeric variable distributions";
  proc means data=&ds n nmiss mean std min p25 median p75 max maxdec=3;
  run;

  title2 "Character variable levels";
  proc freq data=&ds nlevels;
    tables _character_ / noprint;
  run;

  proc datasets lib=work nolist; delete _dups _note; quit;
  title;
%mend profile;

/* clear the accumulator so repeated runs in one session do not stack rows */
proc datasets lib=work nolist; delete eda_missing_all; quit;

%profile(ds=aux_adi,       label=ADI_data (Area Deprivation Index))
%profile(ds=aux_parkinson, label=Parkinson / principal diagnosis workbook)
%profile(ds=aux_icdfind,   label=Cognitive ICD code file)
%profile(ds=aux_precede,   label=Precede Database (Clock_Data))
%profile(ds=aux_icu,       label=ICU LOS detail (long format - one row per stay))
%profile(ds=aux_transfuse, label=Intraoperative blood loss and transfusion)
%profile(ds=aux_cbc,       label=Preoperative CBC (long format - one row per lab))
%profile(ds=aux_preoplab,  label=Preoperative labs within 90 days)


/*=============================================================================
  SECTION 5 - KEY OVERLAP AGAINST THE ANALYSIS MASTER
  How many analysis-master subjects each auxiliary file actually reaches.
  A low match rate here is the usual explanation for a derived variable that
  is unexpectedly missing.
=============================================================================*/

data anal_ids;
  set &ANALYSIS (keep = &KEY insample);
  if not missing(&KEY);
run;
proc sort data=anal_ids nodupkey; by &KEY; run;

%macro overlap(ds=, label=);
  %local n_master n_aux n_match n_m_unm n_orph;

  proc sql noprint;
    create table _o as
      select distinct &KEY from &ds where not missing(&KEY);

    select count(*) into :n_master trimmed from anal_ids;
    select count(*) into :n_aux    trimmed from _o;
    select count(*) into :n_match  trimmed
      from anal_ids a inner join _o b on a.&KEY = b.&KEY;
    select count(*) into :n_m_unm  trimmed
      from anal_ids where &KEY not in (select &KEY from _o);
    select count(*) into :n_orph   trimmed
      from _o where &KEY not in (select &KEY from anal_ids);
  quit;

  data _ov;
    length Source $60;
    Source             = "&label";
    N_Master           = &n_master;
    N_Aux              = &n_aux;
    N_Matched          = &n_match;
    N_Master_Unmatched = &n_m_unm;
    N_Aux_Orphans      = &n_orph;
    Pct_Master_Covered = 100 * N_Matched / max(N_Master, 1);
  run;

  proc append base=eda_overlap data=_ov force; run;
  proc datasets lib=work nolist; delete _o _ov; quit;
%mend overlap;

proc datasets lib=work nolist; delete eda_overlap; quit;

%overlap(ds=aux_adi,       label=ADI_data)
%overlap(ds=aux_parkinson, label=Parkinson workbook)
%overlap(ds=aux_icdfind,   label=Cognitive ICD file)
%overlap(ds=aux_precede,   label=Precede Database)
%overlap(ds=aux_icu,       label=ICU LOS detail)
%overlap(ds=aux_transfuse, label=Blood loss / transfusion)
%overlap(ds=aux_cbc,       label=Preoperative CBC)
%overlap(ds=aux_preoplab,  label=Preoperative labs)

title1 "Section 5. Study ID overlap with the analysis master";
proc print data=eda_overlap noobs label;
  var Source N_Master N_Aux N_Matched Pct_Master_Covered
      N_Master_Unmatched N_Aux_Orphans;
  label Source              = "Auxiliary source"
        N_Master            = "IDs in analysis master"
        N_Aux               = "Distinct IDs in file"
        N_Matched           = "Matched"
        Pct_Master_Covered  = "% of master covered"
        N_Master_Unmatched  = "Master IDs with no row"
        N_Aux_Orphans       = "File IDs not in master";
  format N_: comma10. Pct_Master_Covered 6.1;
run;

proc sgplot data=eda_overlap;
  hbar Source / response=Pct_Master_Covered fillattrs=(color=cx0021A5);
  xaxis label="% of analysis-master subjects with a row in this file" max=100;
  yaxis label=" " discreteorder=data;
  title2 "Coverage of the analysis master";
run;
title;


/*=============================================================================
  SECTION 6 - RE-DERIVE THE CREATE_DATA-STAGE VARIABLES
  Mirrors prog_create_data_20230926.sas, reading the auxiliary inputs from
  their new home on P: instead of their original scattered locations.
=============================================================================*/

/*-----------------------------------------------------------------------------
  ADI - IMPORTANT STRUCTURAL NOTE

  prog_create_data_20230926.sas computes adi_new2 and adi_quan inside DATA ONE,
  which reads the master only. The auxiliary ADI_data file is not merged until
  DATA TWO, one step later. So in the original pipeline the ADI bands are built
  from the master's own copy of adi_new, and the auxiliary copy then silently
  overwrites adi_new afterward without changing the bands already derived from
  it.

  That is reproduced verbatim below so Section 9 compares like with like. It
  does mean the create_data comparison does not, on its own, exercise the
  relocated ADI file. adi_new_aux carries the auxiliary value through under its
  own name so Section 9e can test the two copies against each other directly.
-----------------------------------------------------------------------------*/
data rd_adi;
  set aux_adi (keep = &KEY adi_new);
  adi_new_aux = adi_new;      /* survives the merge under its own name */
run;
proc sort data=rd_adi; by &KEY; run;

/* ---- ICD sources -------------------------------------------------------- */
data rd_icd1;
  set aux_parkinson (keep = &KEY ICD10_Principal_Diagnosis
                            ICD10_Principal_Diagnosis_Desc MovementDisorder);
run;
proc sort data=rd_icd1; by &KEY; run;

data rd_icd2;
  set aux_icdfind;
run;
proc sort data=rd_icd2; by &KEY; run;

/* ---- Clock_Data --------------------------------------------------------- */
data rd_miss;
  set aux_precede (keep = &KEY Clock_Data);
run;
proc sort data=rd_miss; by &KEY; run;

/* ---- ICU time, summed to one row per subject ---------------------------- */
data rd_icu_detail;
  set aux_icu;
  TIME_ICU  = TIME_IN_MINUTES + 0;
  TIME_ICU2 = TIME_ICU;
  if TIME_ICU > 15013 then TIME_ICU2 = 15013;   /* top-code, per original */
run;
proc sort data=rd_icu_detail; by &KEY; run;

data rd_icu_total;
  set rd_icu_detail (keep = &KEY TIME_ICU2);
  by &KEY;
  retain total_icu_time;
  if first.&KEY then total_icu_time = 0;
  total_icu_time = sum(of total_icu_time TIME_ICU2);
  if last.&KEY then output;
  keep &KEY total_icu_time;
run;
proc sort data=rd_icu_total; by &KEY; run;

/* ---- master + create_data recodes --------------------------------------- */
data rd_one;
  length &KEY $25;
  set &MASTER;
  &KEY = cats(studyid);

  adi_new_master = adi_new;   /* captured before the merge overwrites adi_new */

  adi_new2 = adi_new + 0;

  length adi_quan $ 25;
  adi_quan = "";
  if adi_new2 ne . and adi_new2 <= 15  then adi_quan = "1. Least Deprived";
  if adi_new2 > 15 and adi_new2 <= 41  then adi_quan = "2. 2nd Least Deprived";
  if adi_new2 > 41 and adi_new2 <= 62  then adi_quan = "3. 3rd Most Deprived";
  if adi_new2 > 62 and adi_new2 <= 81  then adi_quan = "4. 2nd Most Deprived";
  if adi_new2 > 81 and adi_new2 <= 100 then adi_quan = "5. Most Deprived";

  wrat_grade_level_CWG = .;
  if wrat_grade_level = "<K"                then wrat_grade_level_CWG = 1;
  if wrat_grade_level = "K, 1 and 2"        then wrat_grade_level_CWG = 2;
  if wrat_grade_level = "3, 4 , and 5"      then wrat_grade_level_CWG = 3;
  if wrat_grade_level = "6, 7, and 8"       then wrat_grade_level_CWG = 4;
  if wrat_grade_level = "9, 10, 11, and 12" then wrat_grade_level_CWG = 5;
  if wrat_grade_level = ">12.9"             then wrat_grade_level_CWG = 6;

  edu_new3 = .;
  if edu_new2 = "K, 1 and 2"        then edu_new3 = 1;
  if edu_new2 = "3, 4 , and 5"      then edu_new3 = 2;
  if edu_new2 = "6, 7, and 8"       then edu_new3 = 3;
  if edu_new2 = "9, 10, 11, and 12" then edu_new3 = 4;
  if edu_new2 = ">12.9"             then edu_new3 = 5;

  /*-------------------------------------------------------------------------
    NOTE: the original program reads

        if race_sa = "Other" then race_sa = "Other";

    which assigns back to race_sa, not race_sa2, so race_sa2 stays blank for
    "Other". Reproduced verbatim below so the comparison in Section 9 is
    apples to apples. race_sa2_fixed holds the presumably intended recode;
    Section 10 quantifies the difference. Decide which one you want, then
    change it in one place.
  -------------------------------------------------------------------------*/
  length race_sa2 $ 12 race_sa2_fixed $ 12;
  race_sa2       = "";
  race_sa2_fixed = "";
  if race_sa = "White" then race_sa2 = "White";
  if race_sa = "Black" then race_sa2 = "Black";
  if race_sa = "Other" then race_sa = "Other";           /* verbatim */

  if race_sa in ("White", "Black", "Other") then race_sa2_fixed = race_sa;

  length dischg_dispos_sa2 $ 12;
  dischg_dispos_sa2 = "";
  if dischg_dispos_sa = "Home"       then dischg_dispos_sa2 = "Home";
  if dischg_dispos_sa = "RehabOrLTC" then dischg_dispos_sa2 = "RehabOrLTC";
  if dischg_dispos_sa = "HomeCare"   then dischg_dispos_sa2 = "HomeCare";
run;
proc sort data=rd_one; by &KEY; run;

/*-----------------------------------------------------------------------------
  CARDINALITY ASSERTION - run this before trusting anything downstream.

  The merge below is a six-way DATA step merge by study ID. If two or more of
  the inputs have duplicate IDs, SAS pairs rows by position within the BY
  group rather than producing a relational cross product, which silently
  fabricates combinations that exist in neither source. One duplicated input is
  survivable; two is not.

  rd_icu_total is collapsed to one row per ID by construction. The two ICD
  sources are the ones to watch - a subject with several qualifying diagnoses
  can legitimately appear more than once in the raw extracts.
-----------------------------------------------------------------------------*/
%macro assert_unique(ds=, label=);
  %local ndup;
  proc sql noprint;
    select count(*) into :ndup trimmed
      from (select &KEY from &ds where not missing(&KEY)
            group by &KEY having count(*) > 1);
  quit;

  data _a;
    length Input_Data_Set $32 Status $60;
    Input_Data_Set = "&ds";
    N_Duplicated_IDs = &ndup;
    Status = ifc(&ndup = 0, "OK - one row per study ID",
                            "DUPLICATES - merge result is not trustworthy");
  run;
  proc append base=eda_merge_check data=_a force; run;
  proc datasets lib=work nolist; delete _a; quit;

  %if &ndup > 0 %then
    %put WARNING: &ds has &ndup study IDs on more than one row. See Section 6a.;
%mend assert_unique;

proc datasets lib=work nolist; delete eda_merge_check; quit;

%assert_unique(ds=rd_one)
%assert_unique(ds=rd_miss)
%assert_unique(ds=rd_icd1)
%assert_unique(ds=rd_icd2)
%assert_unique(ds=rd_adi)
%assert_unique(ds=rd_icu_total)

title1 "Section 6a. Merge cardinality check";
proc print data=eda_merge_check noobs label;
  var Input_Data_Set N_Duplicated_IDs Status;
  label Input_Data_Set   = "Merge input"
        N_Duplicated_IDs = "IDs on >1 row"
        Status           = "Assessment";
run;
title2 "More than one input flagged DUPLICATES means the merge below is unsafe. "
       "Collapse the offending source to one row per ID before continuing.";
title;

/* ---- assemble the re-derived analysis master ---------------------------- */
/*-----------------------------------------------------------------------------
  No subsetting IF on infinal here: the original DATA TWO keeps auxiliary-only
  IDs as well, and the stored analysis master therefore contains them too.
  Retaining them keeps both sides of the Section 9 comparison aligned. Section 8
  applies the real analysis subset (insample=1 and pecaner non-missing).
-----------------------------------------------------------------------------*/
data rd_analysis;
  merge rd_one (in = infinal)
        rd_miss
        rd_icd1
        rd_icd2
        rd_adi
        rd_icu_total;
  by &KEY;
  insample = infinal;

  total_icu_time_inpt = .;
  if patient_type_sa2 = "Inpatient" then total_icu_time_inpt = total_icu_time / 60;

  /* band built from the AUXILIARY ADI value, for the Section 9e comparison */
  length adi_quan_aux $ 25;
  adi_quan_aux = "";
  if adi_new_aux ne . and adi_new_aux <= 15  then adi_quan_aux = "1. Least Deprived";
  if adi_new_aux > 15 and adi_new_aux <= 41  then adi_quan_aux = "2. 2nd Least Deprived";
  if adi_new_aux > 41 and adi_new_aux <= 62  then adi_quan_aux = "3. 3rd Most Deprived";
  if adi_new_aux > 62 and adi_new_aux <= 81  then adi_quan_aux = "4. 2nd Most Deprived";
  if adi_new_aux > 81 and adi_new_aux <= 100 then adi_quan_aux = "5. Most Deprived";
run;


/*=============================================================================
  SECTION 7 - RE-DERIVE THE MCI PHENOTYPE VARIABLES
  Mirrors Four_Group_20221222.sas (latest version by file date).
=============================================================================*/

data rd_mci;
  set rd_analysis;

  /* -- clock digit and face measures: -999 is a missing code -------------- */
  array old {32}
    COPYDigit1IdealDIff  COPYDigit2IdealDIff  COPYDigit3IdealDIff
    COPYDigit4IdealDIff  COPYDigit5IdealDIff  COPYDigit6IdealDIff
    COPYDigit7IdealDIff  COPYDigit8IdealDIff  COPYDigit9IdealDIff
    COPYDigit10IdealDIff COPYDigit11IdealDIff COPYDigit12IdealDIff
    COMDigit1IdealDIff   COMDigit2IdealDIff   COMDigit3IdealDIff
    COMDigit4IdealDIff   COMDigit5IdealDIff   COMDigit6IdealDIff
    COMDigit7IdealDIff   COMDigit8IdealDIff   COMDigit9IdealDIff
    COMDigit10IdealDIff  COMDigit11IdealDIff  COMDigit12IdealDIff
    COMClockFace1HorizSz COMClockFace1VertSz
    COMClockFace2HorizSz COMClockFace2VertSz
    COPYClockFace1HorizSz COPYClockFace1VertSz
    COPYClockFace2HorizSz COPYClockFace2VertSz;

  array new {32}
    nCOPYDigit1IdealDIff  nCOPYDigit2IdealDIff  nCOPYDigit3IdealDIff
    nCOPYDigit4IdealDIff  nCOPYDigit5IdealDIff  nCOPYDigit6IdealDIff
    nCOPYDigit7IdealDIff  nCOPYDigit8IdealDIff  nCOPYDigit9IdealDIff
    nCOPYDigit10IdealDIff nCOPYDigit11IdealDIff nCOPYDigit12IdealDIff
    nCOMDigit1IdealDIff   nCOMDigit2IdealDIff   nCOMDigit3IdealDIff
    nCOMDigit4IdealDIff   nCOMDigit5IdealDIff   nCOMDigit6IdealDIff
    nCOMDigit7IdealDIff   nCOMDigit8IdealDIff   nCOMDigit9IdealDIff
    nCOMDigit10IdealDIff  nCOMDigit11IdealDIff  nCOMDigit12IdealDIff
    nCOMClockFace1HorizSz nCOMClockFace1VertSz
    nCOMClockFace2HorizSz nCOMClockFace2VertSz
    nCOPYClockFace1HorizSz nCOPYClockFace1VertSz
    nCOPYClockFace2HorizSz nCOPYClockFace2VertSz;

  do i = 1 to 32;
     new{i} = old{i};
     if old{i} = -999 then new{i} = .;
  end;

  COPYdigit_accuracy = sumabs(of nCOPYDigit1IdealDIff--nCOPYDigit12IdealDIff);
  COMdigit_accuracy  = sumabs(of nCOMDigit1IdealDIff--nCOMDigit12IdealDIff);

  /*---------------------------------------------------------------------------
    NOTE: division binds tighter than addition, so the expression below is

        pi * (0.5*Horiz + 0.25*Vert)**2

    not the average of the two half-diameters. If the intent was
    pi * ((0.5*Horiz + 0.5*Vert)/2)**2, the parentheses are in the wrong place
    and the areas are systematically wrong, with the error growing as Horiz and
    Vert diverge. Reproduced verbatim from Four_Group_20221222.sas so Section 9b
    compares like with like. Section 10f quantifies the gap against the
    presumably intended formula. This one needs a decision from whoever owns the
    clock-drawing measures.
  ---------------------------------------------------------------------------*/
  pi = constant("pi");
  COMclockface_area1  = pi * (((0.5*nCOMClockFace1HorizSz  + 0.5*nCOMClockFace1VertSz /2))**2);
  COMclockface_area2  = pi * (((0.5*nCOMClockFace2HorizSz  + 0.5*nCOMClockFace2VertSz /2))**2);
  COPYclockface_area1 = pi * (((0.5*nCOPYClockFace1HorizSz + 0.5*nCOPYClockFace1VertSz/2))**2);
  COPYclockface_area2 = pi * (((0.5*nCOPYClockFace2HorizSz + 0.5*nCOPYClockFace2VertSz/2))**2);

  /* -- memory severity counts -------------------------------------------- */
  M1_1=0; M2_1=0; M3_1=0;
  if n_hvlt_delay_z > -1 and n_hvlt_delay_z <= -0.5 then M1_1 = 1;
  if n_hvlt_delay_z > -2 and n_hvlt_delay_z <= -1   then M2_1 = 1;
  if n_hvlt_delay_z ne . and n_hvlt_delay_z <= -2   then M3_1 = 1;
  if n_hvlt_delay_z = . then do; M1_1=.; M2_1=.; M3_1=.; end;

  M1_2=0; M2_2=0; M3_2=0;
  if n_hvlt_discrimination_index_z > -1 and n_hvlt_discrimination_index_z <= -0.5 then M1_2 = 1;
  if n_hvlt_discrimination_index_z > -2 and n_hvlt_discrimination_index_z <= -1   then M2_2 = 1;
  if n_hvlt_discrimination_index_z ne . and n_hvlt_discrimination_index_z <= -2   then M3_2 = 1;
  if n_hvlt_discrimination_index_z = . then do; M1_2=.; M2_2=.; M3_2=.; end;

  M1_3=0; M2_3=0; M3_3=0;
  if n_hvlt_total_z > -1 and n_hvlt_total_z <= -0.5 then M1_3 = 1;
  if n_hvlt_total_z > -2 and n_hvlt_total_z <= -1   then M2_3 = 1;
  if n_hvlt_total_z ne . and n_hvlt_total_z <= -2   then M3_3 = 1;
  if n_hvlt_total_z = . then do; M1_3=.; M2_3=.; M3_3=.; end;

  MEM_SEVERE   = M3_1 + M3_2 + M3_3;
  MEM_MODERATE = M2_1 + M2_2 + M2_3;
  MEM_MILD     = M1_1 + M1_2 + M1_3;

  /* -- attention severity counts ----------------------------------------- */
  A1_1=0; A2_1=0; A3_1=0;
  if n_wais_iii_backward_span_z > -1 and n_wais_iii_backward_span_z <= -0.5 then A1_1 = 1;
  if n_wais_iii_backward_span_z > -2 and n_wais_iii_backward_span_z <= -1   then A2_1 = 1;
  if n_wais_iii_backward_span_z ne . and n_wais_iii_backward_span_z <= -2   then A3_1 = 1;
  if n_wais_iii_backward_span_z = . then do; A1_1=.; A2_1=.; A3_1=.; end;

  A1_2=0; A2_2=0; A3_2=0;
  if n_wais_iii_forward_span_z > -1 and n_wais_iii_forward_span_z <= -0.5 then A1_2 = 1;
  if n_wais_iii_forward_span_z > -2 and n_wais_iii_forward_span_z <= -1   then A2_2 = 1;
  if n_wais_iii_forward_span_z ne . and n_wais_iii_forward_span_z <= -2   then A3_2 = 1;
  if n_wais_iii_forward_span_z = . then do; A1_2=.; A2_2=.; A3_2=.; end;

  A1_3=0; A2_3=0; A3_3=0;
  if n_cowa_f_z > -1 and n_cowa_f_z <= -0.5 then A1_3 = 1;
  if n_cowa_f_z > -2 and n_cowa_f_z <= -1   then A2_3 = 1;
  if n_cowa_f_z ne . and n_cowa_f_z <= -2   then A3_3 = 1;
  if n_cowa_f_z = . then do; A1_3=.; A2_3=.; A3_3=.; end;

  ATT_SEVERE   = A3_1 + A3_2 + A3_3;
  ATT_MODERATE = A2_1 + A2_2 + A2_3;
  ATT_MILD     = A1_1 + A1_2 + A1_3;

  MEMORY      = 100*MEM_SEVERE + 10*MEM_MODERATE + MEM_MILD;
  ATTENTION   = 100*ATT_SEVERE + 10*ATT_MODERATE + ATT_MILD;
  MCI_GRP_CWG = 100000*MEM_SEVERE + 10000*MEM_MODERATE + 1000*MEM_MILD
              +    100*ATT_SEVERE +    10*ATT_MODERATE +      ATT_MILD;

  ATT_AVG = mean(of n_wais_iii_backward_span_z n_wais_iii_forward_span_z n_cowa_f_z);
  MEM_AVG = mean(of n_hvlt_discrimination_index_z n_hvlt_total_z n_hvlt_delay_z);

  length MCI_AVG_GRP $ 30 ATT_AVG_GRP $ 15 MEM_AVG_GRP $ 15;
  MCI_AVG_GRP = ""; ATT_AVG_GRP = ""; MEM_AVG_GRP = "";

  if ATT_AVG ne . and ATT_AVG <= -2   then ATT_AVG_GRP = "SEVERE";
  if ATT_AVG >  -2 and ATT_AVG <= -1  then ATT_AVG_GRP = "MODERATE";
  if ATT_AVG >  -1 and ATT_AVG <= -.5 then ATT_AVG_GRP = "MILD";
  if ATT_AVG >  -.5                   then ATT_AVG_GRP = "NONE";

  if MEM_AVG ne . and MEM_AVG <= -2   then MEM_AVG_GRP = "SEVERE";
  if MEM_AVG >  -2 and MEM_AVG <= -1  then MEM_AVG_GRP = "MODERATE";
  if MEM_AVG >  -1 and MEM_AVG <= -.5 then MEM_AVG_GRP = "MILD";
  if MEM_AVG >  -.5                   then MEM_AVG_GRP = "NONE";

  /*-------------------------------------------------------------------------
    NOTE: MCI_Group applies the ATT_AVG cutpoints and then the MEM_AVG
    cutpoints to the same variable, so MEM_AVG silently overwrites ATT_AVG
    whenever both are non-missing. Reproduced verbatim; MCI_AVG_GRP is the
    variable the analyses actually use.
  -------------------------------------------------------------------------*/
  length MCI_Group $ 30;
  MCI_Group = "";
  if ATT_AVG ne . and ATT_AVG <= -2   then MCI_Group = "SEVERE";
  if ATT_AVG >  -2 and ATT_AVG <= -1  then MCI_Group = "MODERATE";
  if ATT_AVG >  -1 and ATT_AVG <= -.5 then MCI_Group = "MILD";
  if ATT_AVG >  -.5                   then MCI_Group = "NONE";
  if MEM_AVG ne . and MEM_AVG <= -2   then MCI_Group = "SEVERE";
  if MEM_AVG >  -2 and MEM_AVG <= -1  then MCI_Group = "MODERATE";
  if MEM_AVG >  -1 and MEM_AVG <= -.5 then MCI_Group = "MILD";
  if MEM_AVG >  -.5                   then MCI_Group = "NONE";

  /* -- 16-cell memory x attention grid ----------------------------------- */
  if ATT_AVG_GRP="NONE" and MEM_AVG_GRP="NONE"     then MCI_AVG_GRP="MEM-NONE_ATT-NONE";
  if ATT_AVG_GRP="NONE" and MEM_AVG_GRP="MILD"     then MCI_AVG_GRP="MEM-MILD_ATT-NONE";
  if ATT_AVG_GRP="NONE" and MEM_AVG_GRP="MODERATE" then MCI_AVG_GRP="MEM-MOD_ATT-NONE";
  if ATT_AVG_GRP="NONE" and MEM_AVG_GRP="SEVERE"   then MCI_AVG_GRP="MEM-SEV_ATT-NONE";

  if ATT_AVG_GRP="MILD" and MEM_AVG_GRP="NONE"     then MCI_AVG_GRP="MEM-NONE_ATT-MILD";
  if ATT_AVG_GRP="MILD" and MEM_AVG_GRP="MILD"     then MCI_AVG_GRP="MEM-MILD_ATT-MILD";
  if ATT_AVG_GRP="MILD" and MEM_AVG_GRP="MODERATE" then MCI_AVG_GRP="MEM-MOD_ATT-MILD";
  if ATT_AVG_GRP="MILD" and MEM_AVG_GRP="SEVERE"   then MCI_AVG_GRP="MEM-SEV_ATT-MILD";

  if ATT_AVG_GRP="MODERATE" and MEM_AVG_GRP="NONE"     then MCI_AVG_GRP="MEM-NONE_ATT-MOD";
  if ATT_AVG_GRP="MODERATE" and MEM_AVG_GRP="MILD"     then MCI_AVG_GRP="MEM-MILD_ATT-MOD";
  if ATT_AVG_GRP="MODERATE" and MEM_AVG_GRP="MODERATE" then MCI_AVG_GRP="MEM-MOD_ATT-MOD";
  if ATT_AVG_GRP="MODERATE" and MEM_AVG_GRP="SEVERE"   then MCI_AVG_GRP="MEM-SEV_ATT-MOD";

  if ATT_AVG_GRP="SEVERE" and MEM_AVG_GRP="NONE"     then MCI_AVG_GRP="MEM-NONE_ATT-SEV";
  if ATT_AVG_GRP="SEVERE" and MEM_AVG_GRP="MILD"     then MCI_AVG_GRP="MEM-MILD_ATT-SEV";
  if ATT_AVG_GRP="SEVERE" and MEM_AVG_GRP="MODERATE" then MCI_AVG_GRP="MEM-MOD_ATT-SEV";
  if ATT_AVG_GRP="SEVERE" and MEM_AVG_GRP="SEVERE"   then MCI_AVG_GRP="MEM-SEV_ATT-SEV";

  /* -- collapsed groupings ------------------------------------------------ */
  length MCI_POS_NEG $ 30;
  MCI_POS_NEG = "";
  if MCI_AVG_GRP = "MEM-NONE_ATT-NONE" then MCI_POS_NEG = "MCI NEGATIVE";
  else if not missing(MCI_AVG_GRP)     then MCI_POS_NEG = "MCI POSITIVE";

  length MCI_NEW_CONDENSED $ 30;
  MCI_NEW_CONDENSED = "";
  if MCI_AVG_GRP = "MEM-NONE_ATT-NONE" then MCI_NEW_CONDENSED = "MCI NONE";
  if MCI_AVG_GRP in ("MEM-MILD_ATT-NONE","MEM-MOD_ATT-NONE","MEM-SEV_ATT-NONE")
                                       then MCI_NEW_CONDENSED = "MCI MEMORY";
  if MCI_AVG_GRP in ("MEM-NONE_ATT-MILD","MEM-NONE_ATT-MOD","MEM-NONE_ATT-SEV")
                                       then MCI_NEW_CONDENSED = "MCI ATTENTION";
  if MCI_AVG_GRP in ("MEM-MILD_ATT-MILD","MEM-MOD_ATT-MILD","MEM-SEV_ATT-MILD",
                     "MEM-MILD_ATT-MOD","MEM-MOD_ATT-MOD","MEM-SEV_ATT-MOD",
                     "MEM-MILD_ATT-SEV","MEM-MOD_ATT-SEV","MEM-SEV_ATT-SEV")
                                       then MCI_NEW_CONDENSED = "MCI BOTH";

  length MCI_NEW_CONDENSED2 $ 30;
  MCI_NEW_CONDENSED2 = "";
  if MCI_AVG_GRP = "MEM-NONE_ATT-NONE" then MCI_NEW_CONDENSED2 = "MCI NONE";
  if MCI_AVG_GRP = "MEM-MILD_ATT-NONE" then MCI_NEW_CONDENSED2 = "MCI MEMORY MILD";
  if MCI_AVG_GRP = "MEM-MOD_ATT-NONE"  then MCI_NEW_CONDENSED2 = "MCI MEMORY MOD";
  if MCI_AVG_GRP = "MEM-SEV_ATT-NONE"  then MCI_NEW_CONDENSED2 = "MCI MEMORY SEV";
  if MCI_AVG_GRP = "MEM-NONE_ATT-MILD" then MCI_NEW_CONDENSED2 = "MCI ATTENTION MILD";
  if MCI_AVG_GRP = "MEM-NONE_ATT-MOD"  then MCI_NEW_CONDENSED2 = "MCI ATTENTION MOD";
  if MCI_AVG_GRP = "MEM-NONE_ATT-SEV"  then MCI_NEW_CONDENSED2 = "MCI ATTENTION SEV";
  if MCI_AVG_GRP in ("MEM-MILD_ATT-MILD")                   then MCI_NEW_CONDENSED2 = "MCI BOTH MILD";
  if MCI_AVG_GRP in ("MEM-MOD_ATT-MILD","MEM-MOD_ATT-MOD",
                     "MEM-MILD_ATT-MOD")                    then MCI_NEW_CONDENSED2 = "MCI BOTH MOD";
  if MCI_AVG_GRP in ("MEM-SEV_ATT-MILD","MEM-SEV_ATT-MOD",
                     "MEM-MILD_ATT-SEV","MEM-MOD_ATT-SEV",
                     "MEM-SEV_ATT-SEV")                     then MCI_NEW_CONDENSED2 = "MCI BOTH SEV";

  length mci_type_att $30 mci_type_mem $30 mci_type_both $30
         mci_type_mild $30 mci_type_mod $30 mci_type_sev $30;
  mci_type_att=""; mci_type_mem=""; mci_type_both="";
  mci_type_mild=""; mci_type_mod=""; mci_type_sev="";

  if MCI_NEW_CONDENSED2 = "MCI ATTENTION MILD" then mci_type_att = "ATT MILD";
  if MCI_NEW_CONDENSED2 = "MCI ATTENTION MOD"  then mci_type_att = "ATT MOD";
  if MCI_NEW_CONDENSED2 = "MCI ATTENTION SEV"  then mci_type_att = "ATT SEV";

  if MCI_NEW_CONDENSED2 = "MCI MEMORY MILD" then mci_type_mem = "MEM MILD";
  if MCI_NEW_CONDENSED2 = "MCI MEMORY MOD"  then mci_type_mem = "MEM MOD";
  if MCI_NEW_CONDENSED2 = "MCI MEMORY SEV"  then mci_type_mem = "MEM SEV";

  if MCI_NEW_CONDENSED2 = "MCI BOTH MILD" then mci_type_both = "Both MILD";
  if MCI_NEW_CONDENSED2 = "MCI BOTH MOD"  then mci_type_both = "Both MOD";
  if MCI_NEW_CONDENSED2 = "MCI BOTH SEV"  then mci_type_both = "Both SEV";

  if MCI_NEW_CONDENSED2 = "MCI ATTENTION MILD" then mci_type_mild = "MCI_ATT_MILD";
  if MCI_NEW_CONDENSED2 = "MCI MEMORY MILD"    then mci_type_mild = "MCI_MEM_MILD";
  if MCI_NEW_CONDENSED2 = "MCI BOTH MILD"      then mci_type_mild = "MCI_BOTH_MILD";

  if MCI_NEW_CONDENSED2 = "MCI ATTENTION MOD" then mci_type_mod = "MCI_ATT_MOD";
  if MCI_NEW_CONDENSED2 = "MCI MEMORY MOD"    then mci_type_mod = "MCI_MEM_MOD";
  if MCI_NEW_CONDENSED2 = "MCI BOTH MOD"      then mci_type_mod = "MCI_BOTH_MOD";

  if MCI_NEW_CONDENSED2 = "MCI ATTENTION SEV" then mci_type_sev = "MCI_ATT_SEV";
  if MCI_NEW_CONDENSED2 = "MCI MEMORY SEV"    then mci_type_sev = "MCI_MEM_SEV";
  if MCI_NEW_CONDENSED2 = "MCI BOTH SEV"      then mci_type_sev = "MCI_BOTH_SEV";

  length MCI_PECAN $ 30;
  MCI_PECAN = "";
  if MCI_POS_NEG = "MCI NEGATIVE" then MCI_PECAN = "MCI NEGATIVE";
  if MCI_POS_NEG = "MCI POSITIVE" then MCI_PECAN = "MCI POSITIVE";
  if pecan_ref_label = "Not Referred" then MCI_PECAN = "Not Referred To PECAN";

  /* -- education and WRAT bands ------------------------------------------ */
  length wrat_grade_level2 $ 20 wrat_grade_level3 $ 20;
  wrat_grade_level2 = ""; wrat_grade_level3 = "";
  if wrat_grade_level = "<K"                then wrat_grade_level2 = "a. <K";
  if wrat_grade_level = "K, 1 and 2"        then wrat_grade_level2 = "b. K, 1 and 2";
  if wrat_grade_level = "3, 4 , and 5"      then wrat_grade_level2 = "c. 3, 4 , and 5";
  if wrat_grade_level = "6, 7, and 8"       then wrat_grade_level2 = "d. 6, 7, and 8";
  if wrat_grade_level = "9, 10, 11, and 12" then wrat_grade_level2 = "e. 9, 10, 11, and 12";
  if wrat_grade_level = ">12.9"             then wrat_grade_level2 = "f. >12.9";

  if wrat_grade_level in ("<K","K, 1 and 2","3, 4 , and 5","6, 7, and 8")
                                            then wrat_grade_level3 = "a. <K-8";
  if wrat_grade_level = "9, 10, 11, and 12" then wrat_grade_level3 = "b. 9, 10, 11, and 12";
  if wrat_grade_level = ">12.9"             then wrat_grade_level3 = "c. >12.9";

  /*---------------------------------------------------------------------------
    NOTE - MISSING VALUE TRAP. In SAS a numeric missing sorts below every real
    number, so Edu_Years = . satisfies both "le 8" and "le 2". Every subject
    with no recorded education is therefore filed in the LOWEST education band
    rather than left blank. Because the same unguarded test is in
    Four_Group_20221222.sas, that misclassification is already baked into the
    stored edu_new and edu_new2 on the master.

    Reproduced verbatim so Section 9c isolates real differences instead of
    drowning in this one. rd_edu_new_guarded holds the version that leaves
    missing education blank; Section 10f counts how many subjects the two
    disagree on. This is a decision about the analysis cohort, not a typo to
    quietly repair.
  ---------------------------------------------------------------------------*/
  length rd_edu_new $20 rd_edu_new2 $20 rd_edu_new_guarded $20;
  rd_edu_new = ""; rd_edu_new2 = ""; rd_edu_new_guarded = "";
  if Edu_Years le 8                       then rd_edu_new = "a. <K-8";
  if Edu_Years ge 9 and Edu_Years le 12   then rd_edu_new = "b. 9, 10, 11, and 12";
  if Edu_Years ge 13                      then rd_edu_new = "c. >12.9";

  if Edu_Years le 2                       then rd_edu_new2 = "a. K, 1 and 2";
  if Edu_Years ge 3  and Edu_Years le 5   then rd_edu_new2 = "b. 3, 4 , and 5";
  if Edu_Years ge 6  and Edu_Years le 8   then rd_edu_new2 = "c. 6, 7, and 8";
  if Edu_Years ge 9  and Edu_Years le 12  then rd_edu_new2 = "d. 9, 10, 11, and 12";
  if Edu_Years ge 13                      then rd_edu_new2 = "e. >12.9";

  if not missing(Edu_Years) then do;
     if Edu_Years le 8                      then rd_edu_new_guarded = "a. <K-8";
     if Edu_Years ge 9 and Edu_Years le 12  then rd_edu_new_guarded = "b. 9, 10, 11, and 12";
     if Edu_Years ge 13                     then rd_edu_new_guarded = "c. >12.9";
  end;

  length pecan_only $ 20;
  pecan_only = "";
  if pecan_testing = 4 then pecan_only = "PeCAN";

  /*---------------------------------------------------------------------------
    NOTE - the same missing-value trap, second instance. The "< 3" tests below
    are true when the MoCA subscore is missing, so a subject with no recorded
    Command or Copy score is flagged as needing PeCAN rather than left blank.
    Verbatim from the original; counted in Section 10f.
  ---------------------------------------------------------------------------*/
  length pecan_flag $ 45;
  pecan_flag = "";
  if COMMocaOverallScore_85hand  = 3 and COPYMocaOverallScore_85hand  = 3
     and mmse_3word_recall = 3 then pecan_flag = "No PeCAN Needed";
  if COMMocaOverallScore_85hand  < 3 and COPYMocaOverallScore_85hand  = 3
     and mmse_3word_recall = 3 then pecan_flag = "PeCAN Needed Command";
  if COPYMocaOverallScore_85hand < 3 and COMMocaOverallScore_85hand   = 3
     and mmse_3word_recall = 3 then pecan_flag = "PeCAN Needed Copy";
  if COMMocaOverallScore_85hand  = 3 and COPYMocaOverallScore_85hand  = 3
     and mmse_3word_recall < 3 then pecan_flag = "PeCAN Needed 3 Word";
  if COMMocaOverallScore_85hand  < 3 and COPYMocaOverallScore_85hand  = 3
     and mmse_3word_recall < 3 then pecan_flag = "PeCAN Needed Command and 3 Word";
  if COPYMocaOverallScore_85hand < 3 and COMMocaOverallScore_85hand   = 3
     and mmse_3word_recall < 3 then pecan_flag = "PeCAN Needed Copy and 3 Word";
  if COMMocaOverallScore_85hand  < 3 and COPYMocaOverallScore_85hand  < 3
     and mmse_3word_recall < 3 then pecan_flag = "PeCAN Needed Command, Copy, and 3 Word";

  drop i;
run;


/*=============================================================================
  SECTION 8 - RE-DERIVE THE 2024 ANALYSIS-BLOCK VARIABLES
  Mirrors prog_DEC_24_2024_ref_vs_tested.sas (latest file in the folder),
  with Clock_Screened from prog_DEC_23_2024_AA_MS.sas added alongside Refused.
  Nothing stored to compare against, so these are profiled only.
=============================================================================*/

data rd_final;
  set rd_mci;
  if &KEY = "" or &KEY = "Precede029027229 07" then delete;
  if insample = 1 and pecaner ne .;

  Refused = 0;
  if Clock_Data in (1, 3, 7, 10) then Refused = 1;

  Clock_Screened = 0;
  if Clock_Data in (1, 3, 7, 10) then Clock_Screened = 1;

  /* -- cognitive ICD flags: Y/N to 1/0 ----------------------------------- */
  %macro yn(v);
    n_&v = .;
    if &v = "N" then n_&v = 0;
    if &v = "Y" then n_&v = 1;
  %mend yn;

  %yn(F01)    %yn(F03)    %yn(F01_50) %yn(F01_51)
  %yn(F02_80) %yn(F02_81) %yn(F03_90) %yn(F03_91)
  %yn(G20)    %yn(G30_1)  %yn(G30_9)  %yn(G31_83)
  %yn(G31_84) %yn(R41_9)  %yn(R41_81)

  if Clock_Data in (1, 3) then Clock_Miss_reason = .;
  if Clock_Data > 3       then Clock_Miss_reason = Clock_Data;

  any_cognitive_code = max(of n_F01 n_F03 n_F01_50 n_F01_51 n_F02_80 n_F02_81
                              n_F03_90 n_F03_91 n_G20 n_G30_1 n_G30_9
                              n_G31_83 n_G31_84 n_R41_9 n_R41_81);

  COMDwgTotTime_2 = .;
  if COMDwgTotTime > 0 then COMDwgTotTime_2 = COMDwgTotTime;

  COPYDwgTotTime_2 = .;
  if COPYDwgTotTime > 0 then COPYDwgTotTime_2 = COPYDwgTotTime;

  COMDwgTotTime_3 = .;
  if COMDwgTotTime > 0 and COMDwgTotTime <= 200 then COMDwgTotTime_3 = COMDwgTotTime;

  if COMDwgTotTime_2 ne . and COMDwgTotTime_2 <= 22.553   then DEC_CLOCK = 1;
  if COMDwgTotTime_2 >  22.553 and COMDwgTotTime_2 <= 26.2155 then DEC_CLOCK = 2;
  if COMDwgTotTime_2 >  26.2155 and COMDwgTotTime_2 <= 29.127 then DEC_CLOCK = 3;
  if COMDwgTotTime_2 >  29.127 and COMDwgTotTime_2 <= 31.867  then DEC_CLOCK = 4;
  if COMDwgTotTime_2 >  31.867 and COMDwgTotTime_2 <= 34.989  then DEC_CLOCK = 5;
  if COMDwgTotTime_2 >  34.989 and COMDwgTotTime_2 <= 39.12   then DEC_CLOCK = 6;
  if COMDwgTotTime_2 >  39.12  and COMDwgTotTime_2 <= 44.491  then DEC_CLOCK = 7;
  if COMDwgTotTime_2 >  44.491 and COMDwgTotTime_2 <= 52.063  then DEC_CLOCK = 8;
  if COMDwgTotTime_2 >  52.063 and COMDwgTotTime_2 <= 67.012  then DEC_CLOCK = 9;
  if COMDwgTotTime_2 >  67.012                                then DEC_CLOCK = 10;

  race_sa_CWG = race_sa;
  if race_sa = "Unknown" then race_sa_CWG = "";
run;


/*=============================================================================
  SECTION 9 - COMPARE RE-DERIVED VALUES AGAINST STORED VALUES
  Any difference here means the auxiliary copies on P: no longer reproduce
  what is baked into the analysis master, or that an input changed.
=============================================================================*/

proc sort data=rd_analysis out=cmp_new; by &KEY; run;

data cmp_old;
  set &ANALYSIS;
  if not missing(&KEY);
run;
proc sort data=cmp_old; by &KEY; run;

/* ---- create_data-stage variables ---------------------------------------- */
%let CREATEVARS = adi_new2 adi_quan wrat_grade_level_CWG edu_new3
                  race_sa2 dischg_dispos_sa2 insample total_icu_time_inpt;

title1 "Section 9a. Re-derived vs stored - create_data-stage variables";
proc compare base = cmp_old (keep = &KEY &CREATEVARS)
             compare = cmp_new (keep = &KEY &CREATEVARS)
             out = diff_create outnoequal outbase outcomp outdif
             method = absolute criterion = 1e-8
             listvar maxprint = (40, 20);
  id &KEY;
run;

/* ---- MCI phenotype variables -------------------------------------------- */
proc sort data=rd_mci out=cmp_mci_new; by &KEY; run;

%let MCIVARS = ATT_AVG MEM_AVG ATT_AVG_GRP MEM_AVG_GRP MCI_AVG_GRP
               MCI_POS_NEG MCI_NEW_CONDENSED MCI_NEW_CONDENSED2
               MCI_GRP_CWG MEMORY ATTENTION
               COMdigit_accuracy COPYdigit_accuracy
               COMclockface_area1 COMclockface_area2
               COPYclockface_area1 COPYclockface_area2;

title1 "Section 9b. Re-derived vs stored - MCI phenotype variables";
proc compare base = cmp_old (keep = &KEY &MCIVARS)
             compare = cmp_mci_new (keep = &KEY &MCIVARS)
             out = diff_mci outnoequal outbase outcomp outdif
             method = absolute criterion = 1e-6
             listvar maxprint = (40, 20);
  id &KEY;
run;

/* ---- education bands (renamed to avoid collision) ----------------------- */
title1 "Section 9c. Re-derived vs stored - education bands";
proc sql;
  create table diff_edu as
    select a.&KEY,
           a.edu_new     as edu_new_stored,
           b.rd_edu_new  as edu_new_rederived,
           a.edu_new2    as edu_new2_stored,
           b.rd_edu_new2 as edu_new2_rederived,
           a.Edu_Years
      from cmp_old as a
           inner join cmp_mci_new as b on a.&KEY = b.&KEY
     where a.edu_new  ne b.rd_edu_new
        or a.edu_new2 ne b.rd_edu_new2;
quit;

proc sql;
  select count(*) as N_Education_Mismatches format=comma10. from diff_edu;
quit;
proc print data=diff_edu(obs=40) noobs;
  title2 "First 40 mismatching records";
run;

/* ---- master ADI vs auxiliary ADI ---------------------------------------- */
/*-----------------------------------------------------------------------------
  The create_data comparison above does not exercise the relocated ADI file,
  for the reason documented in Section 6. This is the test that does: the
  master's own adi_new against the value carried in from ADI_data on P:.
-----------------------------------------------------------------------------*/
title1 "Section 9e. Master ADI vs relocated auxiliary ADI";

data adi_check;
  set rd_analysis;
  length ADI_Status $40;
  if      missing(adi_new_master) and missing(adi_new_aux) then ADI_Status = "Missing in both";
  else if missing(adi_new_aux)                             then ADI_Status = "Missing in auxiliary only";
  else if missing(adi_new_master)                          then ADI_Status = "Missing in master only";
  else if abs(adi_new_master - adi_new_aux) < 1e-8         then ADI_Status = "Identical";
  else                                                          ADI_Status = "Different values";
  ADI_Diff = adi_new_master - adi_new_aux;
  keep &KEY adi_new_master adi_new_aux ADI_Diff ADI_Status adi_quan adi_quan_aux;
run;

proc freq data=adi_check;
  tables ADI_Status / nocum;
  title2 "Agreement between the two copies of adi_new";
run;

proc means data=adi_check(where=(ADI_Status = "Different values"))
           n mean std min max maxdec=3;
  var ADI_Diff;
  title2 "Size of the disagreement where the two copies differ";
run;

proc print data=adi_check(where=(ADI_Status in ("Different values",
                                               "Missing in auxiliary only"))
                          obs=40) noobs;
  var &KEY adi_new_master adi_new_aux ADI_Diff adi_quan adi_quan_aux;
  title2 "First 40 disagreeing records";
run;

proc freq data=adi_check;
  tables adi_quan * adi_quan_aux / missing norow nocol nopercent;
  title2 "Deprivation band from the master value vs from the auxiliary value";
run;
title;

/* ---- one-line summary of every comparison ------------------------------- */
%let n_diff_create = 0;
%let n_diff_mci    = 0;
%let n_diff_edu    = 0;
%let n_diff_adi    = 0;

proc sql noprint;
  select count(distinct &KEY) into :n_diff_create trimmed
    from diff_create where _TYPE_ = 'DIF';
  select count(distinct &KEY) into :n_diff_mci trimmed
    from diff_mci where _TYPE_ = 'DIF';
  select count(*) into :n_diff_edu trimmed
    from diff_edu;
  select count(*) into :n_diff_adi trimmed
    from adi_check where ADI_Status = "Different values";
quit;

data eda_compare_summary;
  length Comparison $40;
  Comparison = "create_data-stage variables"; N_Differing = &n_diff_create; output;
  Comparison = "MCI phenotype variables";     N_Differing = &n_diff_mci;    output;
  Comparison = "Education bands";             N_Differing = &n_diff_edu;    output;
  Comparison = "ADI: master vs auxiliary";    N_Differing = &n_diff_adi;    output;
run;

title1 "Section 9f. Comparison summary";
proc print data=eda_compare_summary noobs label;
  var Comparison N_Differing;
  label Comparison  = "Comparison"
        N_Differing = "Study IDs that differ";
  format N_Differing comma10.;
run;
title;


/*=============================================================================
  SECTION 10 - EDA ON THE DERIVED VARIABLES
=============================================================================*/

%let DERIVED_CAT = Refused Clock_Screened Clock_Miss_reason
                   n_F01 n_F03 n_F01_50 n_F01_51 n_F02_80 n_F02_81
                   n_F03_90 n_F03_91 n_G20 n_G30_1 n_G30_9
                   n_G31_83 n_G31_84 n_R41_9 n_R41_81
                   any_cognitive_code DEC_CLOCK race_sa_CWG
                   adi_quan wrat_grade_level_CWG edu_new3 race_sa2
                   dischg_dispos_sa2 insample
                   MCI_AVG_GRP MCI_POS_NEG MCI_NEW_CONDENSED
                   MCI_NEW_CONDENSED2 MCI_PECAN pecan_flag pecan_only;

%let DERIVED_NUM = adi_new2 COMDwgTotTime_2 COPYDwgTotTime_2 COMDwgTotTime_3
                   total_icu_time_inpt ATT_AVG MEM_AVG
                   MEM_SEVERE MEM_MODERATE MEM_MILD
                   ATT_SEVERE ATT_MODERATE ATT_MILD
                   COMdigit_accuracy COPYdigit_accuracy
                   COMclockface_area1 COMclockface_area2
                   COPYclockface_area1 COPYclockface_area2;

title1 "Section 10a. Derived variables - categorical distributions";
proc freq data=rd_final;
  tables &DERIVED_CAT / missing nocum;
run;

title1 "Section 10b. Derived variables - numeric distributions";
proc means data=rd_final n nmiss mean std min p1 p25 median p75 p99 max maxdec=3;
  var &DERIVED_NUM;
run;

title1 "Section 10c. Derived variables - distribution plots";
proc sgplot data=rd_final;
  histogram COMDwgTotTime_2 / fillattrs=(color=cx0021A5);
  density COMDwgTotTime_2 / lineattrs=(color=cxFA4616 thickness=2);
  xaxis label="Command clock drawing total time (seconds)";
  title2 "COMDwgTotTime_2";
run;

proc sgplot data=rd_final;
  histogram adi_new2 / fillattrs=(color=cx0021A5) binwidth=5;
  xaxis label="Area Deprivation Index (national percentile)";
  title2 "adi_new2";
run;

proc sgplot data=rd_final(where=(not missing(MCI_NEW_CONDENSED)));
  vbox MEM_AVG / category=MCI_NEW_CONDENSED fillattrs=(color=cx0021A5);
  yaxis label="Mean HVLT z-score";
  xaxis label="MCI group";
  title2 "MEM_AVG by MCI_NEW_CONDENSED";
run;

/* ---- recode verification: do the bands respect their cutpoints? --------- */
title1 "Section 10d. Recode verification";

proc means data=rd_final n min max maxdec=4;
  class adi_quan;
  var adi_new2;
  title2 "adi_quan against adi_new2 - min/max should sit inside each band";
run;

proc means data=rd_final n min max maxdec=4;
  class DEC_CLOCK;
  var COMDwgTotTime_2;
  title2 "DEC_CLOCK against COMDwgTotTime_2 - deciles should not overlap";
run;

proc freq data=rd_final;
  tables wrat_grade_level * wrat_grade_level_CWG / missing norow nocol nopercent;
  title2 "wrat_grade_level_CWG against its source";
run;

proc freq data=rd_final;
  tables edu_new2 * edu_new3 / missing norow nocol nopercent;
  title2 "edu_new3 against its source";
run;

proc freq data=rd_final;
  tables race_sa * race_sa2 / missing norow nocol nopercent;
  title2 "race_sa2 against its source - watch the Other row";
run;

proc freq data=rd_final;
  tables race_sa * race_sa2_fixed / missing norow nocol nopercent;
  title2 "race_sa2_fixed against its source - for comparison";
run;

proc freq data=rd_final;
  tables dischg_dispos_sa * dischg_dispos_sa2 / missing norow nocol nopercent;
  title2 "dischg_dispos_sa2 against its source";
run;

proc freq data=rd_final;
  tables MCI_AVG_GRP * MCI_NEW_CONDENSED / missing norow nocol nopercent;
  title2 "MCI_NEW_CONDENSED against the 16-cell grid";
run;

proc freq data=rd_final;
  tables Clock_Data * Refused / missing norow nocol nopercent;
  title2 "Refused against Clock_Data";
run;

proc freq data=rd_final;
  tables Refused * Clock_Screened / missing;
  title2 "Refused against Clock_Screened - identical logic, expect a clean diagonal";
run;

/* ---- unmapped values: source populated but recode blank ---------------- */
title1 "Section 10e. Unmapped source values";

data unmapped;
  set rd_final;
  length Derived_Var $32 Source_Var $32 Source_Value $60;

  if not missing(race_sa) and missing(race_sa2) then do;
     Derived_Var='race_sa2'; Source_Var='race_sa';
     Source_Value=race_sa; output;
  end;
  if not missing(wrat_grade_level) and wrat_grade_level_CWG = . then do;
     Derived_Var='wrat_grade_level_CWG'; Source_Var='wrat_grade_level';
     Source_Value=wrat_grade_level; output;
  end;
  if not missing(edu_new2) and edu_new3 = . then do;
     Derived_Var='edu_new3'; Source_Var='edu_new2';
     Source_Value=edu_new2; output;
  end;
  if not missing(dischg_dispos_sa) and missing(dischg_dispos_sa2) then do;
     Derived_Var='dischg_dispos_sa2'; Source_Var='dischg_dispos_sa';
     Source_Value=dischg_dispos_sa; output;
  end;
  if adi_new2 ne . and missing(adi_quan) then do;
     Derived_Var='adi_quan'; Source_Var='adi_new2';
     Source_Value=put(adi_new2, best12.); output;
  end;
  if not missing(MCI_AVG_GRP) and missing(MCI_NEW_CONDENSED) then do;
     Derived_Var='MCI_NEW_CONDENSED'; Source_Var='MCI_AVG_GRP';
     Source_Value=MCI_AVG_GRP; output;
  end;
  keep &KEY Derived_Var Source_Var Source_Value;
run;

proc freq data=unmapped;
  tables Derived_Var * Source_Value / list missing nocum;
  title2 "Source values that fall through every IF and leave the derived variable blank";
run;
title;


/*-----------------------------------------------------------------------------
  SECTION 10f - INHERITED LOGIC ISSUES, QUANTIFIED

  Three constructs in the historical programs behave in ways that are probably
  not what was intended. All three are reproduced verbatim elsewhere in this
  program so the comparisons stay honest. This section measures how much each
  one actually affects the cohort, so the decision to keep or change them rests
  on counts rather than on reading the code.
-----------------------------------------------------------------------------*/
title1 "Section 10f. Inherited logic issues, quantified";

/* -- 1. missing Edu_Years filed in the lowest education band -------------- */
data edu_trap;
  set rd_final;
  length Edu_Trap $50;
  if missing(Edu_Years) and not missing(rd_edu_new)
     then Edu_Trap = "Missing education, filed in lowest band";
  else if missing(Edu_Years)
     then Edu_Trap = "Missing education, left blank";
  else Edu_Trap = "Education recorded";
  keep &KEY Edu_Years rd_edu_new rd_edu_new_guarded rd_edu_new2 Edu_Trap;
run;

proc freq data=edu_trap;
  tables Edu_Trap / nocum;
  title2 "1. Subjects with no recorded education that the unguarded test bands anyway";
run;

proc freq data=edu_trap;
  tables rd_edu_new * rd_edu_new_guarded / missing norow nocol nopercent;
  title3 "Verbatim banding vs the guarded version - off-diagonal cells are the affected subjects";
run;

/* -- 2. missing MoCA subscores flagged as needing PeCAN ------------------- */
data pecan_trap;
  set rd_final;
  length PeCAN_Trap $60;
  if (missing(COMMocaOverallScore_85hand) or missing(COPYMocaOverallScore_85hand)
      or missing(mmse_3word_recall)) and not missing(pecan_flag)
     then PeCAN_Trap = "Missing subscore, flagged as needing PeCAN";
  else if missing(pecan_flag)
     then PeCAN_Trap = "No flag assigned";
  else PeCAN_Trap = "All subscores recorded";
  keep &KEY COMMocaOverallScore_85hand COPYMocaOverallScore_85hand
       mmse_3word_recall pecan_flag PeCAN_Trap;
run;

proc freq data=pecan_trap;
  tables PeCAN_Trap / nocum;
  title2 "2. Subjects flagged by pecan_flag on the strength of a missing subscore";
run;

proc freq data=pecan_trap(where=(PeCAN_Trap = "Missing subscore, flagged as needing PeCAN"));
  tables pecan_flag / nocum;
  title3 "Which flag values those subjects received";
run;

/* -- 3. clock-face area: verbatim formula vs intended formula ------------- */
data area_check;
  set rd_final;
  pi_ = constant("pi");

  /* as written in the historical program: pi * (0.5H + 0.25V)^2 */
  area1_verbatim = pi_ * ((0.5*nCOMClockFace1HorizSz + 0.5*nCOMClockFace1VertSz/2)**2);

  /* average of the two half-diameters, squared: pi * ((0.5H + 0.5V)/2)^2 */
  area1_intended = pi_ * (((0.5*nCOMClockFace1HorizSz + 0.5*nCOMClockFace1VertSz)/2)**2);

  if area1_intended not in (., 0)
     then Pct_Difference = 100 * (area1_verbatim - area1_intended) / area1_intended;

  keep &KEY nCOMClockFace1HorizSz nCOMClockFace1VertSz
       area1_verbatim area1_intended Pct_Difference;
run;

proc means data=area_check n mean std min p25 median p75 max maxdec=2;
  var area1_verbatim area1_intended Pct_Difference;
  title2 "3. COMclockface_area1 under each formula, and the gap between them";
run;

proc sgplot data=area_check;
  scatter x=area1_intended y=area1_verbatim /
          markerattrs=(color=cx0021A5 symbol=circlefilled size=5);
  lineparm x=0 y=0 slope=1 / lineattrs=(color=cxFA4616 thickness=2 pattern=shortdash);
  xaxis label="Area under the intended formula";
  yaxis label="Area under the formula as written";
  title3 "Points off the reference line are subjects the parenthesis placement affects";
run;
title;


/*=============================================================================
  SECTION 11 - CONSOLIDATED REPORTS AND WRAP-UP
=============================================================================*/

title1 "Section 11a. Missingness across every auxiliary file";
proc sort data=eda_missing_all; by descending Pct_Missing; run;
proc print data=eda_missing_all(obs=60) noobs label;
  var Data_Set Variable Var_Type N_Obs N_Missing Pct_Missing;
  label Data_Set = "File" Var_Type = "Type" N_Obs = "Rows"
        N_Missing = "Missing" Pct_Missing = "% Missing";
  format Pct_Missing 6.1 N_Obs N_Missing comma10.;
  title2 "60 most incomplete variables";
run;

/* ---- persist the EDA artifacts so they can be reviewed later ----------- */
data edaout.eda_missing_all;    set eda_missing_all;      run;
data edaout.eda_overlap;        set eda_overlap;          run;
data edaout.eda_unmapped;       set unmapped;             run;
data edaout.eda_merge_check;    set eda_merge_check;      run;
data edaout.eda_compare_summary;set eda_compare_summary;  run;
data edaout.eda_adi_check;      set adi_check;            run;
data edaout.eda_edu_trap;       set edu_trap;             run;
data edaout.eda_pecan_trap;     set pecan_trap;           run;
data edaout.eda_area_check;     set area_check;           run;
data edaout.rd_final;           set rd_final;             run;

title1 "Section 11b. Data sets written to &outpath";
proc sql;
  select memname   label="Data set",
         nobs      label="Rows"    format=comma12.,
         nvar      label="Columns" format=comma6.
    from dictionary.tables
   where libname = "EDAOUT"
   order by memname;
quit;

title;
footnote;
ods rtf close;
ods listing;

%put NOTE: ============================================================;
%put NOTE: EDA complete. RTF report and data sets are in &outpath..;
%put NOTE: ============================================================;
