/* 29_allowlist_diag.sas -- Phase 29 allowlist pre-approval checks.
   Read-only. Not part of run_pipeline.cmd.
   Run BEFORE populating docs/gapfill_allowlist.csv.

   Section 1: r6 frailty -- are these columns already in g.master_data_merged?
   Section 2: r4 edu_categorical -- does it duplicate base Education column?
   Section 3: r2 individual new columns -- fill rates + base name-similarity flags.  */

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
%include "&sas_path.\macros_raw_import.sas";
libname g "&g_path" access=readonly;

/* ========================================================================
   SECTION 1: r6 frailty -- check if components already in master_data_merged */

title "r6 frailty / grip / walking columns already in g.master_data_merged";
proc sql;
  select name, type, length
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED'
    and (upcase(name) like '%EXAUST%' or upcase(name) like '%EXAUS%'
         or upcase(name) like '%GRIP%'  or upcase(name) like '%WALK%'
         or upcase(name) like '%WEIGHT_LOSS%' or upcase(name) like '%PHYSICAL%'
         or upcase(name) like '%FRAILTY%');
quit;

/* ========================================================================
   SECTION 2: r4 edu_categorical -- duplicate of base Education? */

%import_xlsx(r4, 2020_Precede_Database_Edu.xlsx)

/* Normalize key so we can join to master */
data work.r4_keyed;
  length PRECEDE_STUDY_ID $12;
  set work.r4_s1 (keep=studyid edu_categorical Edu_Years rename=(studyid=_k_raw));
  if index(upcase(strip(_k_raw)), 'PRECEDE') = 0
    then PRECEDE_STUDY_ID = 'Precede' || strip(_k_raw);
    else PRECEDE_STUDY_ID = 'Precede' || substr(strip(_k_raw), 8);
  drop _k_raw;
run;

/* Join to base to get the Education column for the same rows */
proc sql;
  create table work._r4_edu_check as
  select r.PRECEDE_STUDY_ID,
         r.Edu_Years,
         r.edu_categorical,
         b.Education
  from work.r4_keyed as r
  left join g.master_data_merged as b
    on r.PRECEDE_STUDY_ID = b.PRECEDE_STUDY_ID;
quit;

title "r4 edu_categorical vs base Education -- cross-tabulation (2020 cohort rows)";
proc freq data=work._r4_edu_check;
  tables edu_categorical * Education / missing list nocum nopercent;
run;

title "r4 Edu_Years vs base Education -- distribution (Edu_Years populated rows only)";
proc means data=work._r4_edu_check n mean std min max;
  where Edu_Years ne .;
  var Edu_Years;
run;
proc freq data=work._r4_edu_check;
  where Edu_Years ne .;
  tables Education / missing list nocum;
run;

/* ========================================================================
   SECTION 3: r2 individual new columns -- fill rates + base name-similarity.

   "Individual" = not in the four rolled-up families
   (COM_dCDT, COPY_dCDT, LINUS, paper_neuropsych).
   Program 18 lists 120 such columns. We reconstruct them here by importing r2,
   dropping family columns, and comparing each remaining new column name against
   the base column list.

   Family prefixes to exclude from the individual list:
     COM*, COPY*, LINUS_*, COMLibon*, COMCVLT*, COMNine*, COMWais*,
     COMVerb*, COMStroop*, COMTrails*, COMBnt*, COMCVLT*, ron_CPT_*,
     ron_BPC_*, ron_Base_*                                               */

%import_xlsx(r2, 2018_2019_Precede_Database.xlsx)

/* Get base column names */
proc sql noprint;
  select upcase(name) into :_base_cols separated by '|'
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED';
quit;

/* Get r2 column names and classify */
proc sql;
  create table work._r2_cols as
  select name as col_name,
         type as raw_type,
         /* Is this column already in the base? */
         case when indexw("&_base_cols", upcase(name), '|') > 0
              then 'IN_BASE' else 'NEW' end as bucket,
         /* Family flag: name starts with a rolled-up family prefix */
         case
           when upcase(name) like 'COM%'   and upcase(name) not like 'COMP10%'
                                           and upcase(name) not like 'COMPLICATION%'
                                           and upcase(name) not like 'COGNITIVE%'
                then 'family'
           when upcase(name) like 'COPY%'  then 'family'
           when upcase(name) like 'LINUS%' then 'family'
           else 'individual'
         end as col_class
  from dictionary.columns
  where libname='WORK' and memname='R2_S1'
    and upcase(name) ne 'STUDYID';
quit;

/* For individual NEW columns: compute fill rate from the actual data */
proc sql;
  create table work._r2_individual_new as
  select c.col_name, c.raw_type,
         /* Check if base has a similar name (within first 20 chars) */
         case when indexw("&_base_cols", upcase(substr(c.col_name,1,20)), '|') > 0
              then 'SIMILAR_NAME_IN_BASE' else '' end as base_similarity
  from work._r2_cols as c
  where c.bucket = 'NEW' and c.col_class = 'individual'
  order by col_name;
quit;

title "r2 individual NEW columns -- not in base, not in rolled-up families";
title2 "base_similarity flag = first 20 chars of name matches a base column (review for concept duplication)";
proc print data=work._r2_individual_new noobs;
  var col_name raw_type base_similarity;
run;

/* Fill rates for individual NEW columns -- dynamic SQL via PROC SQL passthrough */
/* Build a select list from the column names */
proc sql noprint;
  select quote(strip(col_name), "'") into :_r2_ind_cols separated by ','
  from work._r2_individual_new;
quit;

/* Compute n non-missing for each individual new column */
data work._r2_fillrates;
  length col_name $64 n_populated 8 pct_populated 8;
  set work._r2_individual_new (keep=col_name);
  /* placeholder: actual fill rates are in qc/18_gap_candidates.txt already */
  /* Cross-reference NEW COLUMN DETAIL section of that report for pct_raw_populated */
  n_populated = .;
  pct_populated = .;
run;

title "r2 individual NEW columns -- refer to qc/18_gap_candidates.txt NEW COLUMN DETAIL";
title2 "for fill rates (pct_raw_populated). Flag base_similarity columns for concept review.";
proc print data=work._r2_individual_new noobs label;
  var col_name raw_type base_similarity;
  label col_name       = 'Column'
        raw_type       = 'Type'
        base_similarity = 'Similar name in base?';
run;

/* Summary by bucket and class */
title "r2 column inventory summary";
proc freq data=work._r2_cols;
  tables bucket * col_class / missing list nocum nopercent;
run;

title;
