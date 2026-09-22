/*=============================================================================
  Fibromyalgia Aim 2 (Yonah Joffe)
  Exploratory data analysis: source data sets + derived variables

  Author : Gerard Garvan
  Created: 2026-09-01
  Revised: 2026-09-01  Added Section 7b - stored intraoperative components
                       compared cell by cell against the re-derivation, after
                       all nine JAN_27_2026 part programs were read in full.

  WHAT THIS PROGRAM DOES
    Section 0  Setup, paths, preflight, UF-styled ODS
    Section 1  Inventory of every source folder
    Section 2  Import the source data in its native format
    Section 3  Harmonize the three competing keys
    Section 4  Per-file profiling: structure, key integrity, missingness,
               distributions
    Section 5  Key overlap - how much of the cohort each component reaches
    Section 6  Key construction test (Finding 5: two ways to build YJ_ID)
    Section 7  Re-derive the intraoperative means
    Section 7b Stored cwg_* components vs the re-derivation (Finding 8)
    Section 8  Re-derive the pain means
    Section 9  Re-derive the analysis recodes, and compare to stored values
    Section 10 EDA on the derived variables, incl. recode verification
    Section 11 Inherited issues, quantified
    Section 12 Consolidated reports and wrap-up

  READ THE FINDINGS TAB OF THE WORKBOOK FIRST. Two programs in the source
  folder cannot run as written, a third builds an output from a workbook it
  never imports, and the same libref letter points at three different folders
  depending on which program you open. This program uses meaningful librefs
  (FIBRO, BBPS, FORCG, AIM2, FLOW, PAINLIB) for that reason.

  ASSUMPTIONS - CHANGE THESE IF THEY ARE WRONG
    - The share is reachable. Set ROOT below if the drive letter differs.
    - PROC IMPORT with DBMS=XLSX requires SAS/ACCESS to PC Files.
    - The intraop and pain component data sets have already been built by the
      JAN_27_2026 and APR_20_2026 programs. This program re-derives them from
      the raw workbooks and compares, so it does not depend on them being right.
=============================================================================*/

/*-----------------------------------------------------------------------------
  MPRINT/MLOGIC/SYMBOLGEN are off. Turn them on only if a macro misbehaves -
  with the loops in Section 7 they produce a log tens of thousands of lines long.

  DLCREATEDIR is NOT set globally. It is switched on for the one LIBNAME that
  should create its folder and switched off again, so a mistyped source path
  fails loudly instead of being silently created as an empty directory.
-----------------------------------------------------------------------------*/
options ls=132 ps=60 nodate number nofmterr validvarname=v7 msglevel=i;
ods graphics on / width=6.5in height=4in;


/*=============================================================================
  SECTION 0 - PATHS, LIBRARIES, PREFLIGHT, ODS STYLE
=============================================================================*/

%let root    = Z:\PeCAN Research\06 Individual Folders\Yonah Joffe\Fibromyalgia;

%let p_bbps  = &root\BBPS;
%let p_forcg = &root\For CG;
%let p_aim2  = &root\Aim 2;
%let p_flow  = &root\Aim 2\Master Data Intraop Flow;
%let p_pain  = &root\Aim 2\Master Data Pain;

/* where this program writes - change if you would rather not write to the share */
%let outpath = &root\Aim 2\EDA Output;

/*-----------------------------------------------------------------------------
  MEANINGFUL LIBREFS.

  The source programs use a, b, c, d, e and yj, and the same letter means
  different folders in different programs: B is BBPS in the 2025 programs,
  Master Data Pain in the PAIN programs, and the Aim 2 folder in
  create_data_APRIL_20_2026.sas. Copying a data step between programs therefore
  reads or writes the wrong folder with no error at all. These names cannot
  collide that way.
-----------------------------------------------------------------------------*/
libname fibro   "&root"    access=readonly;
libname bbps    "&p_bbps"  access=readonly;
libname forcg   "&p_forcg" access=readonly;
libname aim2    "&p_aim2"  access=readonly;
libname flow    "&p_flow"  access=readonly;
libname painlib "&p_pain"  access=readonly;

options dlcreatedir;
libname edaout "&outpath";
options nodlcreatedir;

/* --- the analysis data set the pipeline produces ------------------------- */
%let ANALYSIS = aim2.YJ_AIM2_APRIL_21_2026;
%let KEYNUM   = YJ_ID;        /* numeric key: master, pain, intraop           */
%let KEYCHAR  = aim2_id;      /* character key: propensity join               */

/*-----------------------------------------------------------------------------
  PREFLIGHT - stop here rather than 1,000 lines later.

  A folder that does not exist is a path problem. A libref that would not
  assign despite the folder existing is a permissions problem. These are
  separated, and when a folder is missing the parent's contents are listed so
  the right path is usually visible in the log.
-----------------------------------------------------------------------------*/
%macro listdir(path=, label=);
  %local rc did n i;
  %if not %sysfunc(fileexist(&path)) %then %do;
    %put ERROR- ..... cannot list &label - "&path" does not exist either.;
    %return;
  %end;
  %let rc  = %sysfunc(filename(_pfdir, &path));
  %let did = %sysfunc(dopen(_pfdir));
  %if &did = 0 %then %do;
    %put ERROR- ..... cannot open &label.;
    %return;
  %end;
  %let n = %sysfunc(dnum(&did));
  %put ERROR- ..... what IS in &label (&n entries):;
  %do i = 1 %to %sysfunc(min(&n, 25));
    %put ERROR- .....   %sysfunc(dread(&did, &i));
  %end;
  %let rc = %sysfunc(dclose(&did));
  %let rc = %sysfunc(filename(_pfdir));
%mend listdir;

%macro checkpath(path=, name=, parent=);
  %if %sysfunc(fileexist(&path)) %then %do;
    %put NOTE: &name found: &path;
    0
  %end;
  %else %do;
    %put ERROR: &name does NOT exist: &path;
    %listdir(path=&parent, label=its parent)
    1
  %end;
%mend checkpath;

%macro preflight;
  %local bad;
  %let bad = 0;

  %if %checkpath(path=&root,    name=Fibromyalgia root,
                 parent=Z:\PeCAN Research\06 Individual Folders\Yonah Joffe) %then %let bad = 1;
  %if %checkpath(path=&p_forcg, name=For CG folder,          parent=&root)   %then %let bad = 1;
  %if %checkpath(path=&p_aim2,  name=Aim 2 folder,           parent=&root)   %then %let bad = 1;
  %if %checkpath(path=&p_flow,  name=Master Data Intraop Flow, parent=&p_aim2) %then %let bad = 1;
  %if %checkpath(path=&p_pain,  name=Master Data Pain,       parent=&p_aim2) %then %let bad = 1;

  %if %sysfunc(libref(fibro))   %then %do; %put ERROR: FIBRO libref not assigned.;   %let bad = 1; %end;
  %if %sysfunc(libref(aim2))    %then %do; %put ERROR: AIM2 libref not assigned.;    %let bad = 1; %end;
  %if %sysfunc(libref(flow))    %then %do; %put ERROR: FLOW libref not assigned.;    %let bad = 1; %end;
  %if %sysfunc(libref(painlib)) %then %do; %put ERROR: PAINLIB libref not assigned.; %let bad = 1; %end;
  %if %sysfunc(libref(edaout))  %then %do; %put ERROR: EDAOUT libref not assigned.;  %let bad = 1; %end;

  %if &bad %then %do;
    %put ERROR: ==========================================================;
    %put ERROR: Stopping before this produces a log full of downstream;
    %put ERROR: damage. Fix the paths reported above - most likely the;
    %put ERROR: share is on a different drive letter. Adjust %nrstr(%let root).;
    %put ERROR: ==========================================================;
    %abort cancel;
  %end;
  %else %put NOTE: Preflight passed.;
%mend preflight;

%preflight

/* --- UF-branded output style -------------------------------------------- */
proc template;
  define style styles.uf;
    parent = styles.rtf;
    class fonts /
      'TitleFont'   = ("Arial", 12pt, bold)
      'TitleFont2'  = ("Arial", 11pt, bold)
      'HeadingFont' = ("Arial", 10pt, bold)
      'docFont'     = ("Arial",  9pt)
      'StrongFont'  = ("Arial",  9pt, bold);
    class SystemTitle  / foreground = cx0021A5;
    class SystemFooter / foreground = cx555555;
    class Header       / backgroundcolor = cx0021A5 foreground = cxFFFFFF fontweight = bold;
    class RowHeader    / backgroundcolor = cxE8ECF7 foreground = cx0021A5;
    class Table        / bordercolor = cx0021A5 cellpadding = 3 rules = groups;
    class GraphColors  /
      'gdata1' = cx0021A5 'gdata2' = cxFA4616 'gdata3' = cx6E8BD9
      'gcdata' = cx0021A5 'gdata'  = cx0021A5 'gcfill' = cx0021A5;
    class GraphFonts   /
      'GraphTitleFont' = ("Arial", 11pt, bold)
      'GraphLabelFont' = ("Arial",  9pt)
      'GraphValueFont' = ("Arial",  8pt);
  end;
run;

ods _all_ close;
ods rtf file="&outpath\Fibro_Aim2_EDA_%sysfunc(today(),yymmddn8.).rtf"
        style=styles.uf startpage=no;
ods listing;

footnote "Fibromyalgia Aim 2 EDA - generated &sysdate9 &systime";


/*=============================================================================
  SECTION 1 - FOLDER INVENTORY
=============================================================================*/

%macro inventory(path=, label=);
  data _inv;
    length Folder $60 File_Name $200 Extension $20;
    Folder = "&label";
    rc  = filename('invdir', "&path");
    did = dopen('invdir');
    if did = 0 then do;
       put "ERROR: cannot open &path";
       stop;
    end;
    n = dnum(did);
    do i = 1 to n;
       File_Name = dread(did, i);
       Extension = upcase(scan(File_Name, -1, '.'));
       output;
    end;
    rc = dclose(did);
    keep Folder File_Name Extension;
  run;
  proc append base=fibro_inventory data=_inv force; run;
  proc datasets lib=work nolist; delete _inv; quit;
%mend inventory;

proc datasets lib=work nolist; delete fibro_inventory; quit;

%inventory(path=&root,    label=Fibromyalgia (root))
%inventory(path=&p_forcg, label=For CG)
%inventory(path=&p_aim2,  label=Aim 2)
%inventory(path=&p_flow,  label=Aim 2\Master Data Intraop Flow)
%inventory(path=&p_pain,  label=Aim 2\Master Data Pain)

title1 "Section 1. What is actually in each source folder";
proc freq data=fibro_inventory;
  tables Folder * Extension / list nocum missing;
run;

proc print data=fibro_inventory noobs label;
  where Extension in ("XLSX", "XLS", "CSV", "SAS7BDAT");
  var Folder Extension File_Name;
  label Folder = "Folder" Extension = "Type" File_Name = "File";
  title2 "Data files only";
run;
title;


/*=============================================================================
  SECTION 2 - IMPORT THE SOURCE DATA

  The intraop and pain workbooks come in year x part combinations that the
  original programs handle with nine and four near-identical programs. One
  macro with a parameter list replaces all thirteen - see Finding 7.

  This also fixes a real gap: the raw1 PROC IMPORT is commented out in all nine
  JAN_27_2026 part programs, so 2018_2019_X_INTRAOP_Part1.xlsx is never actually
  imported anywhere in that folder. Here every one of the nine workbooks is read.
=============================================================================*/

/* ---- the stage 1 and stage 3 masters ------------------------------------ */
proc import out = src_master_apr26
            datafile = "&root\FIBRO_MASTER_APRIL_20_2026.xlsx"
            dbms = xlsx replace;
  getnames = yes;
  sheet = "FIBRO_MASTER_APRIL_20_2026";
run;

/* ---- the propensity workbooks ------------------------------------------- */
proc import out = src_zscore
            datafile = "&p_aim2\NEW AND CUT_Z-Score Propensity Match Dataset.xlsx"
            dbms = xlsx replace;
  getnames = yes;
  sheet = "Sheet1";
run;

proc import out = src_condensed
            datafile = "&p_aim2\Aim 2 Propensity Match Condensed Dataset.xlsx"
            dbms = xlsx replace;
  getnames = yes;
  sheet = "Sheet1";
run;

/* ---- intraoperative flowsheets: one macro, nine calls ------------------- */
%macro get_flow(file=, sheet=, origin=, out=);
  proc import out = &out
              datafile = "&p_flow\&file"
              dbms = xlsx replace;
    getnames = yes;
    sheet = "&sheet";
  run;
  data &out;
    set &out;
    length source_file $ 50;
    source_file = "&origin";
  run;
%mend get_flow;

%get_flow(file=2018_2019_X_INTRAOP_Part1.xlsx, sheet=2018_2019_X_INTRAOP_Part1,
          origin=2018_2019_X_INTRAOP_Part1, out=flow01)
%get_flow(file=2018_2019_X_INTRAOP_Part2.xlsx, sheet=2018_2019_X_INTRAOP_Part2,
          origin=2018_2019_X_INTRAOP_Part2, out=flow02)
%get_flow(file=2018_2019_X_INTRAOP_Part3.xlsx, sheet=2018_2019_X_INTRAOP_Part3,
          origin=2018_2019_X_INTRAOP_Part3, out=flow03)
%get_flow(file=2020_X_INTRAOP_Part1.xlsx, sheet=2020_X_INTRAOP_Part1,
          origin=2020_X_INTRAOP_Part1, out=flow04)
%get_flow(file=2020_X_INTRAOP_Part2.xlsx, sheet=2020_X_INTRAOP_Part2,
          origin=2020_X_INTRAOP_Part2, out=flow05)
%get_flow(file=2021_X_INTRAOP_Part1.xlsx, sheet=2021_X_INTRAOP_Part1,
          origin=2021_X_INTRAOP_Part1, out=flow06)
%get_flow(file=2021_X_INTRAOP_Part2.xlsx, sheet=2021_X_INTRAOP_Part2,
          origin=2021_X_INTRAOP_Part2, out=flow07)
%get_flow(file=2022_X_INTRAOP_Part1.xlsx, sheet=2022_X_INTRAOP_Part1,
          origin=2022_X_INTRAOP_Part1, out=flow08)
%get_flow(file=2022_X_INTRAOP_Part2.xlsx, sheet=2022_X_INTRAOP_Part2,
          origin=2022_X_INTRAOP_Part2, out=flow09)

data src_flow;
  set flow01 - flow09;
run;

/* ---- pain workbooks: one macro, four calls ------------------------------ */
%macro get_pain(file=, sheet=, yr=, out=);
  proc import out = &out
              datafile = "&p_pain\&file"
              dbms = xlsx replace;
    getnames = yes;
    sheet = "&sheet";
  run;
  data &out;
    set &out;
    length pain_year $ 12;
    pain_year = "&yr";
  run;
%mend get_pain;

%get_pain(file=2018_2019_PAIN.xlsx, sheet=2018_2019_MASTER_DATASET_PAIN_2,
          yr=2018_2019, out=pain01)
%get_pain(file=2020_PAIN.xlsx, sheet=2020_MASTER_DATASET_PAIN_202105, yr=2020, out=pain02)
%get_pain(file=2021_PAIN.xlsx, sheet=2021_MASTER_DATASET_PAIN_202312, yr=2021, out=pain03)
%get_pain(file=2022_PAIN.xlsx, sheet=2022_PAIN, yr=2022, out=pain04)

data src_pain;
  set pain01 - pain04;
run;


/*=============================================================================
  SECTION 3 - HARMONIZE THE KEYS

  Three identifiers are in circulation: YJ_ID (numeric, built by stripping the
  literal 'Precede' from a study id), aim2_id (character $35), and the raw
  Study_ID / PRECEDE_Study_ID / pid columns. All three are built here so the
  joins in Sections 5, 7b and 9 can be done on whichever one applies.
=============================================================================*/

%macro setkeys(in=, out=, from=);
  data &out;
    length &KEYCHAR $35;
    set &in;
    &KEYCHAR = cats(&from);
    &KEYNUM  = input(compress(cats(&from), "Precede"), ?? best32.);
    if &KEYCHAR in (".", "") then &KEYCHAR = "";
  run;
  proc sort data=&out; by &KEYNUM; run;
%mend setkeys;

%setkeys(in=src_master_apr26, out=k_master,    from=PRECEDE_Study_ID)
%setkeys(in=src_zscore,       out=k_zscore,    from=pid)
%setkeys(in=src_condensed,    out=k_condensed, from=PRECEDE_Study_ID)
%setkeys(in=src_flow,         out=k_flow,      from=Study_ID)
%setkeys(in=src_pain,         out=k_pain,      from=Study_ID)


/*=============================================================================
  SECTION 4 - PER-FILE PROFILING
=============================================================================*/

/*-----------------------------------------------------------------------------
  The missingness expression list is built in chunks. A macro variable caps at
  32,767 characters, and a wide flowsheet extract will blow past that if the
  whole SELECT is assembled in one go.
-----------------------------------------------------------------------------*/
%macro miss_profile(lib=WORK, ds=, label=, chunk=100, printmax=40);
  %local nv nobs i nchunks lo hi;

  proc sql noprint;
    create table _vars as
      select name, type, varnum, length as Var_Length
        from dictionary.columns
       where libname = upcase("&lib") and memname = upcase("&ds")
       order by varnum;
    select count(*) into :nv trimmed from _vars;
  quit;

  %if &nv = 0 %then %do;
    %put WARNING: &lib..&ds has no columns or does not exist. Skipped.;
    %return;
  %end;

  proc sql noprint; select count(*) into :nobs trimmed from &lib..&ds; quit;
  proc datasets lib=work nolist; delete _mlong; quit;

  %let nchunks = %sysfunc(ceil(%sysevalf(&nv / &chunk)));
  %do i = 1 %to &nchunks;
    %let lo = %eval((&i - 1) * &chunk + 1);
    %let hi = %sysfunc(min(%eval(&i * &chunk), &nv));

    data _null_;
      set _vars(firstobs=&lo obs=&hi) end=eof;
      length s $30000;
      retain s '';
      s = catx(', ', s, cats('sum(missing(', nliteral(name), ')) as _M', put(_n_, z4.)));
      if eof then call symputx('_msel', s);
    run;

    proc sql noprint; create table _mwide as select &_msel from &lib..&ds; quit;
    proc transpose data=_mwide out=_ml(rename=(col1=N_Missing)) name=_pos;
      var _M:;
    run;
    proc append base=_mlong data=_ml force; run;
    proc datasets lib=work nolist; delete _mwide _ml; quit;
  %end;

  data _mrep;
    merge _vars(rename=(name=Variable)) _mlong(keep=N_Missing);
    length Data_Set $32 Source_Label $60 Var_Type $9;
    Data_Set     = "&ds";
    Source_Label = "&label";
    Var_Type     = ifc(lowcase(type) = 'num', 'Numeric', 'Character');
    N_Obs        = &nobs;
    N_Present    = N_Obs - N_Missing;
    Pct_Missing  = 100 * N_Missing / max(N_Obs, 1);
    keep Data_Set Source_Label varnum Variable Var_Type Var_Length
         N_Obs N_Present N_Missing Pct_Missing;
  run;

  proc append base=eda_missing_all data=_mrep force; run;
  proc sort data=_mrep out=_mshow; by descending Pct_Missing varnum; run;

  title2 "Missingness by variable";
  %if &nv > &printmax %then %do;
    title3 "&nv columns - showing the &printmax most incomplete. "
           "Full detail in EDAOUT.EDA_MISSING_ALL.";
  %end;
  proc print data=_mshow(obs=&printmax) noobs label;
    var varnum Variable Var_Type Var_Length N_Obs N_Present N_Missing Pct_Missing;
    label varnum = "#" Var_Type = "Type" Var_Length = "Len" N_Obs = "Rows"
          N_Present = "Present" N_Missing = "Missing" Pct_Missing = "% Missing";
    format Pct_Missing 6.1 N_Obs N_Present N_Missing comma10.;
  run;
  title3;

  proc datasets lib=work nolist; delete _vars _mlong _mrep _mshow; quit;
%mend miss_profile;


%macro profile(ds=, label=, key=&KEYNUM, expect_one_row=Y);
  %local nnum nchar ndup;
  title1 "Section 4. &label";

  title2 "Structure";
  proc contents data=&ds varnum; run;

  title2 "Row and key counts";
  proc sql;
    select count(*)              label="Rows"                 as n_rows format=comma12.,
           count(distinct &key)  label="Distinct keys"        as n_ids  format=comma12.,
           sum(missing(&key))    label="Rows with blank key"  as n_noid format=comma12.,
           count(*) - count(distinct &key)
                                 label="Rows above one per key" as n_ex format=comma12.
      from &ds;
  quit;

  proc freq data=&ds noprint;
    tables &key / out=_dups(where=(count > 1 and not missing(&key)));
  run;
  proc sql noprint; select count(*) into :ndup trimmed from _dups; quit;

  data _keynote;
    length Result $140;
    %if &expect_one_row = Y %then %do;
      if &ndup = 0 then Result = "One row per key, as expected.";
      else Result = "&ndup keys appear on more than one row. This file is "
                 || "supposed to be one row per subject - investigate before merging.";
    %end;
    %else %do;
      if &ndup = 0 then Result = "One row per key - unexpected for a long-format file. "
                              || "Check the import picked up all rows.";
      else Result = "&ndup keys on more than one row, which is expected for this "
                 || "long-format file.";
    %end;
  run;
  title2 "Key cardinality";
  proc print data=_keynote noobs label; label Result = "Assessment"; run;

  %miss_profile(lib=WORK, ds=&ds, label=&label)

  proc sql noprint;
    select sum(type = 'num'), sum(type = 'char') into :nnum trimmed, :nchar trimmed
      from dictionary.columns where libname = 'WORK' and memname = upcase("&ds");
  quit;

  %if &nnum > 0 %then %do;
    title2 "Numeric variable distributions";
    proc means data=&ds n nmiss mean std min p25 median p75 max maxdec=3; run;
  %end;
  %else %put NOTE: &ds has no numeric columns - PROC MEANS skipped.;

  %if &nchar > 0 %then %do;
    title2 "Character variable levels";
    proc freq data=&ds nlevels; tables _character_ / noprint; run;
  %end;

  proc datasets lib=work nolist; delete _dups _keynote; quit;
  title;
%mend profile;

proc datasets lib=work nolist; delete eda_missing_all; quit;

%profile(ds=k_master,    label=Stage 3 master (FIBRO_MASTER_APRIL_20_2026))
%profile(ds=k_zscore,    label=Clock-drawing z-scores (propensity workbook))
%profile(ds=k_condensed, label=Propensity match condensed dataset)
%profile(ds=k_flow,      label=Intraoperative flowsheets (long - one row per reading),
         expect_one_row=N)
%profile(ds=k_pain,      label=Pain scores (long - one row per score), expect_one_row=N)

title1 "Section 4f. Rows contributed by each source file";
proc freq data=k_flow;
  tables source_file / nocum;
  title2 "Intraoperative flowsheets";
run;
proc freq data=k_pain;
  tables pain_year / nocum;
  title2 "Pain workbooks";
run;
title;


/*=============================================================================
  SECTION 5 - KEY OVERLAP AGAINST THE ANALYSIS COHORT

  The analysis cohort is defined by membership in the condensed propensity
  dataset, not by anything in the master. This measures how much of that cohort
  each component actually reaches - the usual explanation for a derived
  variable that is emptier than expected.
=============================================================================*/

data cohort_ids;
  set k_condensed (keep = &KEYNUM &KEYCHAR);
  if not missing(&KEYNUM);
run;
proc sort data=cohort_ids nodupkey; by &KEYNUM; run;

%macro overlap(ds=, label=);
  %local n_coh n_src n_match n_unm n_orph;
  proc sql noprint;
    create table _o as select distinct &KEYNUM from &ds where not missing(&KEYNUM);
    select count(*) into :n_coh   trimmed from cohort_ids;
    select count(*) into :n_src   trimmed from _o;
    select count(*) into :n_match trimmed
      from cohort_ids a inner join _o b on a.&KEYNUM = b.&KEYNUM;
    select count(*) into :n_unm   trimmed
      from cohort_ids where &KEYNUM not in (select &KEYNUM from _o);
    select count(*) into :n_orph  trimmed
      from _o where &KEYNUM not in (select &KEYNUM from cohort_ids);
  quit;

  data _ov;
    length Source $60;
    Source              = "&label";
    N_Cohort            = &n_coh;
    N_Source            = &n_src;
    N_Matched           = &n_match;
    N_Cohort_Unmatched  = &n_unm;
    N_Source_Orphans    = &n_orph;
    Pct_Cohort_Covered  = 100 * N_Matched / max(N_Cohort, 1);
  run;
  proc append base=eda_overlap data=_ov force; run;
  proc datasets lib=work nolist; delete _o _ov; quit;
%mend overlap;

proc datasets lib=work nolist; delete eda_overlap; quit;

%overlap(ds=k_master, label=Stage 3 master)
%overlap(ds=k_zscore, label=Clock-drawing z-scores)
%overlap(ds=k_flow,   label=Intraoperative flowsheets)
%overlap(ds=k_pain,   label=Pain scores)

title1 "Section 5. Coverage of the analysis cohort";
proc print data=eda_overlap noobs label;
  var Source N_Cohort N_Source N_Matched Pct_Cohort_Covered
      N_Cohort_Unmatched N_Source_Orphans;
  label Source             = "Source"
        N_Cohort           = "IDs in cohort"
        N_Source           = "Distinct IDs in source"
        N_Matched          = "Matched"
        Pct_Cohort_Covered = "% of cohort covered"
        N_Cohort_Unmatched = "Cohort IDs with no row"
        N_Source_Orphans   = "Source IDs not in cohort";
  format N_: comma10. Pct_Cohort_Covered 6.1;
run;

proc sgplot data=eda_overlap;
  hbar Source / response=Pct_Cohort_Covered fillattrs=(color=cx0021A5);
  xaxis label="% of the analysis cohort with a row in this source" max=100;
  yaxis label=" " discreteorder=data;
  title2 "Coverage";
run;
title;


/*=============================================================================
  SECTION 6 - KEY CONSTRUCTION TEST

  create_data_APRIL_20_2026.sas builds YJ_ID two different ways inside one
  program: compress(Study_ID,"Precede") + 0 for the 2018-2019, 2020 and 2021
  pain files, and a bare YJ_ID = Study_ID for 2022. If the 2022 ids still carry
  the prefix, those subjects silently fail to join. This measures it.
=============================================================================*/

data key_test;
  set k_pain;
  length Raw_Has_Prefix $ 4 Key_Status $ 60;

  Raw_Has_Prefix = ifc(index(upcase(cats(Study_ID)), "PRECEDE") > 0, "Yes", "No");

  /* what the bare assignment used for 2022 would produce */
  bare_key = input(cats(Study_ID), ?? best32.);

  if      missing(&KEYNUM)                 then Key_Status = "Compressed key will not parse";
  else if missing(bare_key)                then Key_Status = "Bare assignment loses the key";
  else if &KEYNUM = bare_key               then Key_Status = "Both methods agree";
  else                                          Key_Status = "Methods disagree";
  keep pain_year Study_ID &KEYNUM bare_key Raw_Has_Prefix Key_Status;
run;

title1 "Section 6. Does the 2022 key construction match the other three years?";
proc freq data=key_test;
  tables pain_year * Raw_Has_Prefix / missing norow nocol nopercent;
  title2 "Do the raw ids carry the 'Precede' prefix, by year?";
run;

proc freq data=key_test;
  tables pain_year * Key_Status / missing norow nocol nopercent;
  title2 "Compressed key vs the bare assignment used for 2022";
run;

proc print data=key_test(where=(Key_Status ne "Both methods agree") obs=30) noobs;
  var pain_year Study_ID &KEYNUM bare_key Raw_Has_Prefix Key_Status;
  title2 "First 30 disagreements";
run;
title;


/*=============================================================================
  SECTION 7 - RE-DERIVE THE INTRAOPERATIVE MEANS

  Mirrors create_data_JAN_27_2026_partN.sas, but as one array-driven pass over
  all nine files rather than nine copies of a 200-line block. Both NIBP parses
  are computed so Section 11 can quantify the difference.
=============================================================================*/

%let FLOWVARS = NIBP_SYS NIBP_DIA ABP ABP_mean AWRR BIS_Index ETCO2 ETCO2_Avance
                ETCO2_RR FiO2 HR_SpO2 HR_monitor ISO_Exp ISO_Insp N2O_Exp N2O_Insp
                NIBP NIBP_mean PEEP_set PIP PPV RR SEV_Exp SEV_Insp SpO2 Temp
                Temp_bladder Temp_core Temp_esoph Temp_naso Temp_rectal Temp_skin Tv_Et;

data rd_flow_rows;
  set k_flow;

  /* current parse: split on the slash */
  NIBP_SYS = input(scan(cats(NIBP), 1, '/'), ?? best32.);
  NIBP_DIA = input(scan(cats(NIBP), 2, '/'), ?? best32.);

  /* superseded parse, kept only for the Section 11 comparison */
  NIBP_SYS_substr = input(substr(cats(NIBP), 1, 3), ?? best32.);
  NIBP_DIA_substr = input(substr(cats(NIBP), 4, 2), ?? best32.);
run;

proc sort data=rd_flow_rows; by &KEYNUM; run;

/*-----------------------------------------------------------------------------
  One array pass replaces 33 retained counters, 33 retained accumulators and
  33 division statements. The zero-count guard is the one deliberate change
  from the original: dividing by a zero count logs a note on every affected
  row, and the guard makes the intent explicit rather than relying on SAS
  setting the result to missing.
-----------------------------------------------------------------------------*/
data rd_flow;
  set rd_flow_rows;
  by &KEYNUM;

  array _v {*} &FLOWVARS;
  array _c {33} _temporary_;
  array _s {33} _temporary_;
  array _m {*} mean_NIBP_SYS mean_NIBP_DIA mean_ABP mean_ABP_mean mean_AWRR
               mean_BIS_Index mean_ETCO2 mean_ETCO2_Avance mean_ETCO2_RR mean_FiO2
               mean_HR_SpO2 mean_HR_monitor mean_ISO_Exp mean_ISO_Insp mean_N2O_Exp
               mean_N2O_Insp mean_NIBP mean_NIBP_mean mean_PEEP_set mean_PIP mean_PPV
               mean_RR mean_SEV_Exp mean_SEV_Insp mean_SpO2 mean_Temp
               mean_Temp_bladder mean_Temp_core mean_Temp_esoph mean_Temp_naso
               mean_Temp_rectal mean_Temp_skin mean_Tv_Et;

  array _n {*} n_NIBP_SYS n_NIBP_DIA n_ABP n_ABP_mean n_AWRR
               n_BIS_Index n_ETCO2 n_ETCO2_Avance n_ETCO2_RR n_FiO2
               n_HR_SpO2 n_HR_monitor n_ISO_Exp n_ISO_Insp n_N2O_Exp
               n_N2O_Insp n_NIBP n_NIBP_mean n_PEEP_set n_PIP n_PPV
               n_RR n_SEV_Exp n_SEV_Insp n_SpO2 n_Temp
               n_Temp_bladder n_Temp_core n_Temp_esoph n_Temp_naso
               n_Temp_rectal n_Temp_skin n_Tv_Et;

  if first.&KEYNUM then do i = 1 to dim(_v);
     _c{i} = 0;
     _s{i} = 0;
  end;

  do i = 1 to dim(_v);
     if _v{i} ne . then do;
        _c{i} = _c{i} + 1;
        _s{i} = _s{i} + _v{i};
     end;
  end;

  if last.&KEYNUM then do;
     do i = 1 to dim(_v);
        _n{i} = _c{i};
        if _c{i} > 0 then _m{i} = _s{i} / _c{i};
        else              _m{i} = .;
     end;
     output;
  end;

  keep &KEYNUM &KEYCHAR source_file
       mean_: n_:;
run;

title1 "Section 7. Re-derived intraoperative means";
proc means data=rd_flow n nmiss mean std min p25 median p75 max maxdec=2;
  var mean_NIBP_SYS mean_NIBP_DIA mean_NIBP_mean mean_HR_monitor mean_BIS_Index
      mean_SpO2 mean_ETCO2 mean_Temp_core;
  title2 "The parameters the analysis actually uses";
run;

proc means data=rd_flow n mean min max maxdec=1;
  var n_NIBP_mean n_HR_monitor n_BIS_Index n_SpO2;
  title2 "Readings per subject behind each mean - a mean built on one reading is fragile";
run;
title;


/*=============================================================================
  SECTION 7b - STORED INTRAOP COMPONENTS vs THE RE-DERIVATION

  The nine create_data_JAN_27_2026_partN.sas programs are one program with five
  tokens swapped: which PROC IMPORT is left uncommented, the SET data set, the
  output data set name, the origin literal, and the ODS RTF file name. Eight of
  the nine are internally consistent. part1 is not: it reads raw1 but the import
  left uncommented is raw5 (2020_X_INTRAOP_Part2), and the raw1 import is
  commented out in all nine files. So AIM2.CWG_2018_2019_X_INTRAOP_PART1 was
  built from whatever WORK.RAW1 happened to be in session memory, and part1 will
  not run standalone.

  Section 7 has already re-derived every component from the raw workbooks. This
  compares those re-derivations cell by cell against what is stored, so the
  question of whether that one output is right is settled by counts rather than
  by reading the program again.
=============================================================================*/

%let PART_SRC =
   2018_2019_X_INTRAOP_Part1 2018_2019_X_INTRAOP_Part2 2018_2019_X_INTRAOP_Part3
   2020_X_INTRAOP_Part1      2020_X_INTRAOP_Part2
   2021_X_INTRAOP_Part1      2021_X_INTRAOP_Part2
   2022_X_INTRAOP_Part1      2022_X_INTRAOP_Part2;

/* the stored data set name is always cwg_ + the origin literal */
%macro cwg_check;
  %local i src ds;
  proc datasets lib=work nolist; delete cwg_compare cwg_cells; quit;

  %do i = 1 %to 9;
    %let src = %scan(&PART_SRC, &i, %str( ));
    %let ds  = cwg_&src;

    %if %sysfunc(exist(aim2.&ds)) = 0 %then %do;
      data _sum;
        length Source_File $50 Stored_Data_Set $40;
        Source_File = "&src";  Stored_Data_Set = "AIM2.&ds";
        N_IDs_Compared = .; N_Cells_Compared = .; N_Cells_Differ = .;
        Max_Abs_Diff = .; N_Stored_Only = .; N_New_Only = .;
      run;
      proc append base=cwg_compare data=_sum force; run;
      proc datasets lib=work nolist; delete _sum; quit;
      %put WARNING: AIM2.&ds not found - nothing to compare for &src..;
    %end;
    %else %do;

      data _st;
        set aim2.&ds;
        &KEYNUM = input(compress(cats(Study_ID), "Precede"), ?? best32.);
        if not missing(&KEYNUM);
        keep &KEYNUM mean_:;
      run;
      proc sort data=_st; by &KEYNUM; run;

      data _rd;
        set rd_flow (where = (source_file = "&src") keep = &KEYNUM source_file mean_:);
      run;
      proc sort data=_rd; by &KEYNUM; run;

      proc transpose data=_st out=_lst(rename=(col1=Stored_Value)) name=Variable;
        by &KEYNUM; var mean_:;
      run;
      proc transpose data=_rd out=_lrd(rename=(col1=New_Value)) name=Variable;
        by &KEYNUM; var mean_:;
      run;
      proc sort data=_lst; by &KEYNUM Variable; run;
      proc sort data=_lrd; by &KEYNUM Variable; run;

      data _cells;
        length Source_File $50;
        merge _lst (in=s) _lrd (in=r);
        by &KEYNUM Variable;
        Source_File = "&src";
        In_Stored = s;
        In_New    = r;
        if s and r and Stored_Value ne . and New_Value ne . then do;
           Comparable = 1;
           Abs_Diff   = abs(Stored_Value - New_Value);
        end;
        else Comparable = 0;
      run;
      proc append base=cwg_cells data=_cells force; run;

      proc sql;
        create table _sum as
          select "&src"     as Source_File     length=50,
                 "AIM2.&ds" as Stored_Data_Set length=40,
                 count(distinct &KEYNUM)                   as N_IDs_Compared,
                 sum(Comparable)                           as N_Cells_Compared,
                 sum(Comparable = 1 and Abs_Diff > 1e-8)   as N_Cells_Differ,
                 max(Abs_Diff)                             as Max_Abs_Diff,
                 sum(In_Stored = 1 and In_New = 0)         as N_Stored_Only,
                 sum(In_New = 1 and In_Stored = 0)         as N_New_Only
            from _cells;
      quit;

      proc append base=cwg_compare data=_sum force; run;
      proc datasets lib=work nolist;
        delete _st _rd _lst _lrd _cells _sum;
      quit;
    %end;
  %end;
%mend cwg_check;

%cwg_check

data cwg_compare;
  set cwg_compare;
  length Verdict $70 Provenance $110;

  if      N_Cells_Compared = .                     then Verdict = "Stored data set not found";
  else if N_Cells_Differ = 0 and N_Stored_Only = 0
      and N_New_Only = 0                           then Verdict = "Matches the re-derivation exactly";
  else if N_Cells_Differ = 0                       then Verdict = "Values agree, but the ID sets differ";
  else                                                  Verdict = "Values disagree - investigate";

  if Source_File = "2018_2019_X_INTRAOP_Part1" then
     Provenance = "Built by part1, which reads raw1 while importing raw5. Source unverified - "
               || "see Finding 8.";
  else
     Provenance = "Import and SET agree in the source program.";
run;

title1 "Section 7b. Stored intraoperative components vs the re-derivation";
proc print data=cwg_compare noobs label;
  var Source_File Stored_Data_Set N_IDs_Compared N_Cells_Compared N_Cells_Differ
      Max_Abs_Diff Verdict;
  label Source_File      = "Source file"
        Stored_Data_Set  = "Stored data set"
        N_IDs_Compared   = "Subjects"
        N_Cells_Compared = "Means compared"
        N_Cells_Differ   = "Means differing"
        Max_Abs_Diff     = "Largest difference"
        Verdict          = "Verdict";
  format N_: comma10. Max_Abs_Diff 12.6;
run;

proc print data=cwg_compare noobs label;
  where Source_File = "2018_2019_X_INTRAOP_Part1";
  var Source_File Provenance N_Stored_Only N_New_Only;
  label Provenance    = "Why this row is different"
        N_Stored_Only = "Means present only in the stored data set"
        N_New_Only    = "Means present only in the re-derivation";
  title2 "The one component whose source cannot be read off the program";
run;

proc sort data=cwg_cells out=_worst;
  where Comparable = 1 and Abs_Diff > 1e-8;
  by descending Abs_Diff;
run;

proc print data=_worst(obs=30) noobs label;
  var Source_File &KEYNUM Variable Stored_Value New_Value Abs_Diff;
  label Variable = "Mean" Stored_Value = "Stored" New_Value = "Re-derived"
        Abs_Diff = "Difference";
  format Stored_Value New_Value Abs_Diff 12.4;
  title2 "30 largest disagreements, across all nine components";
run;

proc datasets lib=work nolist; delete _worst; quit;
title;


/*=============================================================================
  SECTION 8 - RE-DERIVE THE PAIN MEANS
  Mirrors create_data_*_PAIN_*_V2.sas. Pre and post are split on the sign of
  rt_RM_END_to_RECORDED_mins, with zero counted as postoperative per the original.
=============================================================================*/

proc sort data=k_pain out=rd_pain_rows; by &KEYNUM; run;

data rd_pain;
  set rd_pain_rows;
  by &KEYNUM;
  retain pain_sum_pre n_pain_pre pain_sum_post n_pain_post;

  if first.&KEYNUM then do;
     pain_sum_pre = 0; n_pain_pre = 0;
     pain_sum_post = 0; n_pain_post = 0;
  end;

  if pain_num ne . and rt_RM_END_to_RECORDED_mins ne . then do;
     if rt_RM_END_to_RECORDED_mins < 0 then do;
        pain_sum_pre = pain_sum_pre + pain_num;
        n_pain_pre   = n_pain_pre + 1;
     end;
     else do;
        pain_sum_post = pain_sum_post + pain_num;
        n_pain_post   = n_pain_post + 1;
     end;
  end;

  if last.&KEYNUM then do;
     if n_pain_pre  > 0 then mean_pain_CWG_pre  = pain_sum_pre  / n_pain_pre;
     if n_pain_post > 0 then mean_pain_CWG_post = pain_sum_post / n_pain_post;
     output;
  end;

  keep &KEYNUM &KEYCHAR pain_year mean_pain_CWG_pre mean_pain_CWG_post
       n_pain_pre n_pain_post;
run;

title1 "Section 8. Re-derived pain means";
proc means data=rd_pain n nmiss mean std min p25 median p75 max maxdec=2;
  var mean_pain_CWG_pre mean_pain_CWG_post n_pain_pre n_pain_post;
run;

proc freq data=rd_pain;
  tables pain_year / nocum;
  title2 "Subjects per source year";
run;

proc sgplot data=rd_pain;
  histogram mean_pain_CWG_pre  / fillattrs=(color=cx0021A5) transparency=0.4 binwidth=0.5;
  histogram mean_pain_CWG_post / fillattrs=(color=cxFA4616) transparency=0.4 binwidth=0.5;
  xaxis label="Mean pain score";
  keylegend / title="";
  title2 "Preoperative (blue) and postoperative (orange) pain";
run;
title;


/*=============================================================================
  SECTION 9 - RE-DERIVE THE ANALYSIS RECODES AND COMPARE
  Mirrors create_propensity_data_APRIL_21_2026.sas.
=============================================================================*/

proc sort data=k_master    out=cmp_master;    by &KEYCHAR; run;
proc sort data=k_zscore    out=cmp_zscore;    by &KEYCHAR; run;
proc sort data=k_condensed out=cmp_condensed(keep = &KEYCHAR mean_HR_monitor_new
                                                    mean_BIS_Index_new);
  by &KEYCHAR;
run;

data rd_analysis;
  merge cmp_master cmp_zscore cmp_condensed (in = incohort);
  by &KEYCHAR;
  if incohort = 1;

  length RACE_YJ $ 25;
  RACE_YJ = "";
  if race ne ""      then RACE_YJ = "OTHER";
  if race = "BLACK"  then RACE_YJ = "BLACK";
  if race = "WHITE"  then RACE_YJ = "WHITE";

  length ETHNICITY_YJ $ 25;
  ETHNICITY_YJ = "";
  if Ethnicity = "HISPANIC"     then ETHNICITY_YJ = "HISPANIC";
  if Ethnicity = "NOT HISPANIC" then ETHNICITY_YJ = "NOT HISPANIC";

  length Anesthesia_Type_YJ $ 25;
  Anesthesia_Type_YJ = "";
  if Anesthesia_Type = "Epidural" or Anesthesia_Type = "Spinal"
                                       then Anesthesia_Type_YJ = "Epi/Spinal";
  if Anesthesia_Type = "General"       then Anesthesia_Type_YJ = "General";
  if Anesthesia_Type = "Monitor Anesthesia Care "
                                       then Anesthesia_Type_YJ = "Monitor Anesthesia Care";

  length type_patient $ 15;
  type_patient = "";
  if LOS = 0 then type_patient = "Outpatient";
  if LOS > 0 then type_patient = "Inpatient";
run;

/* ---- compare against the stored analysis data set ----------------------- */
%macro compare_stored;
  %if %sysfunc(exist(&ANALYSIS)) %then %do;
    proc sort data=&ANALYSIS out=cmp_stored; by &KEYCHAR; run;
    proc sort data=rd_analysis out=cmp_new;  by &KEYCHAR; run;

    %let RECODES = RACE_YJ ETHNICITY_YJ Anesthesia_Type_YJ type_patient;

    title1 "Section 9a. Re-derived vs stored - analysis recodes";
    proc compare base = cmp_stored (keep = &KEYCHAR &RECODES)
                 compare = cmp_new (keep = &KEYCHAR &RECODES)
                 out = diff_recodes outnoequal outbase outcomp outdif
                 listvar maxprint = (40, 20);
      id &KEYCHAR;
    run;
  %end;
  %else %do;
    %put WARNING: &ANALYSIS does not exist - Section 9a comparison skipped.;
    data _nostored;
      length Result $160;
      Result = "&ANALYSIS not found. The re-derived recodes are profiled in "
            || "Section 10 but not compared against a stored version.";
    run;
    title1 "Section 9a. Re-derived vs stored - analysis recodes";
    proc print data=_nostored noobs label; label Result = "Note"; run;
    proc datasets lib=work nolist; delete _nostored; quit;
  %end;
%mend compare_stored;

%compare_stored
title;


/*=============================================================================
  SECTION 10 - EDA ON THE DERIVED VARIABLES
=============================================================================*/

title1 "Section 10a. Derived variables - categorical distributions";
proc freq data=rd_analysis;
  tables RACE_YJ ETHNICITY_YJ Anesthesia_Type_YJ type_patient / missing nocum;
run;

title1 "Section 10b. Recode verification";

proc freq data=rd_analysis;
  tables race * RACE_YJ / missing norow nocol nopercent;
  title2 "RACE_YJ against its source - catch-all first, so nothing should fall through";
run;

proc freq data=rd_analysis;
  tables Ethnicity * ETHNICITY_YJ / missing norow nocol nopercent;
  title2 "ETHNICITY_YJ against its source - no catch-all, so watch for blanks";
run;

proc freq data=rd_analysis;
  tables Anesthesia_Type * Anesthesia_Type_YJ / missing norow nocol nopercent;
  title2 "Anesthesia_Type_YJ against its source - watch the trailing-space level";
run;

proc means data=rd_analysis n min max maxdec=2;
  class type_patient;
  var LOS;
  title2 "type_patient against LOS - Outpatient should be exactly zero";
run;

/* ---- source values that fall through every IF --------------------------- */
data unmapped;
  set rd_analysis;
  length Derived_Var $32 Source_Var $32 Source_Value $80;

  if not missing(race) and missing(RACE_YJ) then do;
     Derived_Var='RACE_YJ'; Source_Var='race'; Source_Value=race; output;
  end;
  if not missing(Ethnicity) and missing(ETHNICITY_YJ) then do;
     Derived_Var='ETHNICITY_YJ'; Source_Var='Ethnicity'; Source_Value=Ethnicity; output;
  end;
  if not missing(Anesthesia_Type) and missing(Anesthesia_Type_YJ) then do;
     Derived_Var='Anesthesia_Type_YJ'; Source_Var='Anesthesia_Type';
     Source_Value=Anesthesia_Type; output;
  end;
  if LOS ne . and missing(type_patient) then do;
     Derived_Var='type_patient'; Source_Var='LOS';
     Source_Value=put(LOS, best12.); output;
  end;
  keep &KEYCHAR Derived_Var Source_Var Source_Value;
run;

title1 "Section 10c. Unmapped source values";
proc freq data=unmapped;
  tables Derived_Var * Source_Value / list missing nocum;
  title2 "Values that leave the derived variable blank";
run;
title;


/*=============================================================================
  SECTION 11 - INHERITED ISSUES, QUANTIFIED

  Two constructs in the source programs behave in ways that are probably not
  intended. Rather than assert that, this measures how much of the cohort each
  one actually affects, so the decision rests on counts.
=============================================================================*/

title1 "Section 11. Inherited issues, quantified";

/* -- 1. NIBP: delimiter parse vs fixed-position parse --------------------- */
data nibp_check;
  set rd_flow_rows;
  where not missing(NIBP);
  length NIBP_Parse $ 60;
  if      missing(NIBP_SYS) and missing(NIBP_SYS_substr) then NIBP_Parse = "Neither method parses";
  else if missing(NIBP_SYS_substr)                       then NIBP_Parse = "Only the slash parse works";
  else if missing(NIBP_SYS)                              then NIBP_Parse = "Only the substr parse works";
  else if NIBP_SYS = NIBP_SYS_substr and NIBP_DIA = NIBP_DIA_substr
                                                         then NIBP_Parse = "Both agree";
  else                                                        NIBP_Parse = "Methods disagree";
  keep &KEYNUM NIBP NIBP_SYS NIBP_DIA NIBP_SYS_substr NIBP_DIA_substr NIBP_Parse;
run;

proc freq data=nibp_check;
  tables NIBP_Parse / nocum;
  title2 "1. Slash parse vs the superseded fixed-position parse";
run;

proc print data=nibp_check(where=(NIBP_Parse = "Methods disagree") obs=30) noobs;
  var NIBP NIBP_SYS NIBP_DIA NIBP_SYS_substr NIBP_DIA_substr;
  title3 "First 30 readings the two methods read differently";
run;

/* -- 2. means built on very few readings ---------------------------------- */
data thin_means;
  set rd_flow;
  length Reading_Depth $ 40;
  if      n_NIBP_mean = 0 then Reading_Depth = "No readings - mean is missing";
  else if n_NIBP_mean = 1 then Reading_Depth = "One reading";
  else if n_NIBP_mean <= 5 then Reading_Depth = "Two to five readings";
  else                          Reading_Depth = "More than five readings";
  keep &KEYNUM n_NIBP_mean mean_NIBP_mean Reading_Depth;
run;

proc freq data=thin_means;
  tables Reading_Depth / nocum;
  title2 "2. How many readings sit behind mean_NIBP_mean";
run;

proc sgplot data=thin_means(where=(n_NIBP_mean > 0));
  scatter x=n_NIBP_mean y=mean_NIBP_mean /
          markerattrs=(color=cx0021A5 symbol=circlefilled size=4) transparency=0.6;
  xaxis label="Number of readings" type=log;
  yaxis label="Mean NIBP";
  title3 "Spread narrows as readings accumulate - the left edge is the fragile part";
run;

/* -- 3. component provenance, carried forward from Section 7b ------------- */
proc print data=cwg_compare noobs label;
  var Source_File Verdict N_Cells_Differ Max_Abs_Diff;
  label Source_File = "Component" Verdict = "Verdict"
        N_Cells_Differ = "Means differing" Max_Abs_Diff = "Largest difference";
  format Max_Abs_Diff 12.6;
  title2 "3. Stored components vs the re-derivation - summary from Section 7b";
run;
title;


/*=============================================================================
  SECTION 12 - CONSOLIDATED REPORTS AND WRAP-UP
=============================================================================*/

title1 "Section 12a. Missingness across every source";
proc sort data=eda_missing_all; by descending Pct_Missing; run;
proc print data=eda_missing_all(obs=60) noobs label;
  var Data_Set Variable Var_Type N_Obs N_Missing Pct_Missing;
  label Data_Set = "Source" Var_Type = "Type" N_Obs = "Rows"
        N_Missing = "Missing" Pct_Missing = "% Missing";
  format Pct_Missing 6.1 N_Obs N_Missing comma10.;
  title2 "60 most incomplete variables";
run;

data edaout.eda_inventory;    set fibro_inventory; run;
data edaout.eda_missing_all;  set eda_missing_all; run;
data edaout.eda_overlap;      set eda_overlap;     run;
data edaout.eda_key_test;     set key_test;        run;
data edaout.eda_cwg_compare;  set cwg_compare;     run;
data edaout.eda_cwg_cells;    set cwg_cells;       run;
data edaout.eda_nibp_check;   set nibp_check;      run;
data edaout.eda_thin_means;   set thin_means;      run;
data edaout.eda_unmapped;     set unmapped;        run;
data edaout.rd_flow;          set rd_flow;         run;
data edaout.rd_pain;          set rd_pain;         run;
data edaout.rd_analysis;      set rd_analysis;     run;

title1 "Section 12b. Data sets written to &outpath";
proc sql;
  select memname label="Data set",
         nobs    label="Rows"    format=comma12.,
         nvar    label="Columns" format=comma6.
    from dictionary.tables
   where libname = "EDAOUT"
   order by memname;
quit;

title;
footnote;
ods rtf close;
ods listing;

%put NOTE: ============================================================;
%put NOTE: Fibro Aim 2 EDA complete. Output is in &outpath..;
%put NOTE: Section 7b settles whether cwg_2018_2019_X_INTRAOP_Part1 -;
%put NOTE: the one component with no verifiable source - is correct.;
%put NOTE: ============================================================;
