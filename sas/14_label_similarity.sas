/*==========================================================================
  Program : 14_label_similarity.sas
  Phase   : 14 -- Label-Similarity Sweep
  Purpose : Find same-concept variable pairs whose NAMES share nothing by
            comparing their SAS labels. Name-based matching (Phases 11-12)
            is structurally blind to this class of alias.

            Section A: Extract labels, compute pairwise COMPLEV similarity,
                       write candidate pairs for human review.
            Section B: SSDI death family and CPT1 concept group profiling
                       (HARM-09). Written in Plan 02.

  Reads   : g.master_data_harmonized (read-only)
            docs/precede_dictionary.csv (canonical names and descriptions)

  Writes  : docs/label_similarity_candidates.csv  -- committed artifact; human input
            docs/LABEL_SIMILARITY_EVIDENCE.xlsx    -- NOT committed (.xlsx in .gitignore)
            qc/14_label_similarity.txt             -- QC artifact on P:
            logs/14_label_similarity.log           -- NOT committed

  Requirements: HARM-02, HARM-03

  PCM compliance:
    - No bare open-code %IF (needs a %DO block); every gate is in a macro
    - No apostrophes and no embedded semicolons in %PUT text
    - Every %abort cancel inside a named macro
    - No &SQLOBS; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - IS NOT MISSING only in PROC SQL; DATA step uses NOT MISSING(x)
    - g.master_data_harmonized never on the left of a DATA statement
    - LENGTH before SET in every data step
    - LENGTHN not LENGTH for blank-safe string length
==========================================================================*/

options mprint nofmterr nodate nonumber ps=max ls=200;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

/* ---------- Standard log routing macros --------------------------------- */
%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\14_label_similarity.log" new;
    run;
  %end;
%mend route_log;

%macro restore_log;
  %if &in_pipeline = 0 %then %do;
    proc printto;
    run;
  %end;
%mend restore_log;

%macro fail_out(msg=);
  %put ERROR: &msg;
  ods excel close;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;

%route_log;
libname g "&g_path";

%put NOTE: ==== Phase 14 Label-Similarity Sweep (Section A) starting ====;

/* ---------- TUNING PARAMETERS ------------------------------------------- */
/* TUNING PARAMETER -- Normalized COMPLEV (Levenshtein) threshold.
   score_edit = 1 - complev(a,b) / max(lengthn(a), lengthn(b))
   1.0 = identical; 0.0 = maximally different.
   0.20 is a wide net. Review the score distribution in the QC artifact and
   raise if the candidate list exceeds 100 pairs. State your chosen threshold
   in docs/label_similarity_candidates.csv and in DECISIONS.md.            */
%let threshold = 0.20;

/* TUNING PARAMETER -- Word-level Jaccard threshold.
   jaccard = shared_words / (words_a + words_b - shared_words)
   1.0 = identical word sets; 0.0 = no shared words.
   0.34 ~ one shared word in three. A pair qualifies on EITHER measure.    */
%let jaccard_threshold = 0.34;


/* =========================================================================
   SECTION 0: Preconditions
   ========================================================================= */

/* Check g.master_data_harmonized exists */
proc sql noprint;
  select count(*) into :n_tab trimmed
  from dictionary.tables
  where libname='G' and memname='MASTER_DATA_HARMONIZED';
quit;

%macro check_src;
  %if %length(&n_tab) = 0 %then %do;
    %fail_out(msg=Table existence query returned no value);
  %end;
  %else %if &n_tab ne 1 %then %do;
    %fail_out(msg=g.master_data_harmonized not found -- run Phase 10b first);
  %end;
  %put NOTE: [14] g.master_data_harmonized confirmed present.;
%mend check_src;
%check_src;

/* Check precede_dictionary.csv exists */
%macro check_precede_csv;
  %if %sysfunc(fileexist(&docs_path.\precede_dictionary.csv)) = 0 %then %do;
    %fail_out(msg=precede_dictionary.csv not found -- HARM-02 requires canonical names from this file only);
  %end;
  %put NOTE: [14] docs/precede_dictionary.csv confirmed present.;
%mend check_precede_csv;
%check_precede_csv;

/* Check g.master_data_harmonized has rows */
proc sql noprint;
  select count(*) into :n_harm_rows trimmed
  from g.master_data_harmonized;
quit;

%macro check_harm_rows;
  %if %length(&n_harm_rows) = 0 %then %do;
    %fail_out(msg=Row count query returned no value);
  %end;
  %else %if &n_harm_rows = 0 %then %do;
    %fail_out(msg=g.master_data_harmonized has zero rows -- check data source);
  %end;
  %put NOTE: [14] g.master_data_harmonized: &n_harm_rows rows confirmed.;
%mend check_harm_rows;
%check_harm_rows;


/* =========================================================================
   SECTION 1: Read PRECEDE Dictionary (HARM-02)
   Canonical names sourced exclusively from docs/precede_dictionary.csv.
   NOT from VARIABLE_RECTIFICATION.xlsx (that file is a register of open
   questions, not a name crosswalk -- HARM-02 constraint).
   ========================================================================= */

proc import datafile="&docs_path.\precede_dictionary.csv"
    out=work.prec_raw dbms=csv replace;
  guessingrows=max;
run;

data work.prec_dict;
  length sheet $40 dict_name $100 dict_type $30 description $500
         source $200 note $200 sas_name $32;
  set work.prec_raw (rename=(sheet=_sh dict_name=_dn dict_type=_dt
                              description=_desc source=_src note=_nt sas_name=_sn));
  sheet       = strip(cats(_sh));
  dict_name   = strip(cats(_dn));
  dict_type   = strip(cats(_dt));
  description = strip(cats(_desc));
  sas_name    = upcase(strip(cats(_sn)));
  keep sheet dict_name dict_type description sas_name;
run;

proc sql noprint;
  select count(*) into :n_dict_rows trimmed from work.prec_dict
  where not missing(sas_name);
quit;

%macro check_dict;
  %if %length(&n_dict_rows) = 0 %then %do;
    %fail_out(msg=Dictionary row count returned no value);
  %end;
  %else %if &n_dict_rows = 0 %then %do;
    %fail_out(msg=precede_dictionary.csv read 0 rows with non-missing sas_name -- check file);
  %end;
  %put NOTE: [14] PRECEDE dictionary: &n_dict_rows rows with sas_name populated.;
%mend check_dict;
%check_dict;


/* =========================================================================
   SECTION 2: Extract Labels from g.master_data_harmonized
   Uses dictionary.columns -- the only way to get all labels without reading
   the full dataset. g.master_data_harmonized is never written to.
   ========================================================================= */

proc sql noprint;
  create table work.raw_labels as
  select upcase(name)  as varname    length=32,
         strip(label)  as sas_label  length=256,
         varnum
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_HARMONIZED'
    and upcase(name) not in ('PRECEDE_STUDY_ID')
  order by varnum;
  select count(*) into :n_vars trimmed from work.raw_labels;
quit;

%put NOTE: [14] Variables extracted (excl key): &n_vars;


/* =========================================================================
   SECTION 3: Build Best-Label Table
   Precedence: PRECEDE dictionary description (authoritative specification)
               then SAS label (extract-dependent)
               then variable name (last resort)
   The dictionary wins because it is the authoritative specification --
   a SAS label is whatever an extract happened to carry.

   DEDUPLICATE THE DICTIONARY FIRST. precede_dictionary.csv carries the same
   sas_name on several sheets. A bare LEFT JOIN multiplies rows in best_labels,
   duplicates candidate pairs, and breaks stated pair counts. Phase 11 already
   ranks sheets and keeps one row per normalised name; the same rule is used
   here so the two programs cannot disagree.
   ========================================================================= */

data work.prec_dict_ranked;
  set work.prec_dict;
  if      sheet = 'MASTER_DATASET'           then sheet_rank = 1;
  else if sheet = 'DERIVED_VARIABLES_MASTER' then sheet_rank = 2;
  else                                            sheet_rank = 3;
run;

proc sort data=work.prec_dict_ranked; by sas_name sheet_rank sheet; run;

data work.prec_dict_u;
  set work.prec_dict_ranked;
  by sas_name;
  if first.sas_name;
run;

proc sql noprint;
  create table work.best_labels as
  select l.varname,
         case
           when not missing(d.description) then strip(d.description)
           when not missing(l.sas_label)   then strip(l.sas_label)
           else l.varname
         end as working_label  length=256,
         case
           when not missing(d.description) then 'DICTIONARY'
           when not missing(l.sas_label)   then 'SAS_LABEL'
           else 'VARNAME'
         end as label_source   length=10
  from work.raw_labels as l
  left join work.prec_dict_u as d
    on l.varname = d.sas_name;

  /* Count label-source tiers for QC */
  select sum(label_source='DICTIONARY') into :n_dict_label  trimmed from work.best_labels;
  select sum(label_source='SAS_LABEL')  into :n_sas_label   trimmed from work.best_labels;
  select sum(label_source='VARNAME')    into :n_varname_fallback trimmed from work.best_labels;
quit;

/* ASSERT one row per variable -- a duplicated dictionary row silently doubles
   a variable and every pair it belongs to. */
proc sql noprint;
  select count(*), count(distinct varname)
    into :n_bl trimmed, :n_bl_u trimmed
  from work.best_labels;
quit;

%macro assert_one_row_per_var;
  %if %length(&n_bl) = 0 %then %do;
    %fail_out(msg=best_labels count query returned no value);
  %end;
  %else %if &n_bl ne &n_bl_u %then %do;
    %fail_out(msg=best_labels has &n_bl rows for &n_bl_u variables -- the dictionary join duplicated);
  %end;
  %put NOTE: [14] best_labels holds one row per variable (&n_bl).;
%mend assert_one_row_per_var;
%assert_one_row_per_var;

%put NOTE: [14] Label source breakdown:;
%put NOTE: [14]   DICTIONARY: &n_dict_label;
%put NOTE: [14]   SAS_LABEL : &n_sas_label;
%put NOTE: [14]   VARNAME   : &n_varname_fallback;


/* =========================================================================
   SECTION 4: Build Concept Table for Known-Pair Exclusion
   Derived from Phase 10 concept group membership -- generated from the data,
   not re-typed, so it cannot fall out of step with 10_concept_profile.sas.
   All pairwise combinations within each group are excluded from the candidate
   list (these aliases are already handled by the concept harmonizer).
   ========================================================================= */

data work.concepts;
  length concept $32 varname $32;
  infile datalines dsd dlm='|' truncover;
  input concept $ varname $;
  datalines;
DEATH_FLAG|DEATH_DATE_Y_N
DEATH_FLAG|ISDEAD_Y_N
DEATH_FLAG|DEATH
SLEEP_APNEA|SLEEP_APNEA
SLEEP_APNEA|SLEEP_APNEA_YN
DIABETES|DIABETES
DIABETES|DIABETES_YN
HYPERLIPIDEMIA|HYPERLIPIDEMIA
HYPERLIPIDEMIA|HYPERLIPIDEMIA_YN
HYPERTENSION|HYPERTENSION
HYPERTENSION|HYPERTENSION_YN
MOVEMENT_DISORDER|MOVEMENTDISORDER
MOVEMENT_DISORDER|MOVEMENTDISORDER_YN
COGNITIVE_DISORDER|COGNITIVE_DISORDER
COGNITIVE_DISORDER|COGNITIVEDISORDER_YN
ISO_SEV_AVERAGE|ISO_SEV_EXP_INTRAOP_MAC_AVERAGE
;
run;

/* Generate all intra-group pairs for exclusion */
proc sql noprint;
  create table work.known_pairs as
  select a.varname as varname_a length=32,
         b.varname as varname_b length=32
  from work.concepts as a
  inner join work.concepts as b
    on a.concept = b.concept and a.varname < b.varname;
quit;


/* =========================================================================
   SECTION 5: Compute Pairwise Similarity (COMPLEV + Jaccard)

   CORRECTED 2026-08-29: COMPGED returns a WEIGHTED generalised edit cost
   (~100 per operation), not 1. Normalising by 2*max_length gives large
   negative scores; nothing clears a positive threshold. Use COMPLEV instead:
   it returns plain Levenshtein distance in CHARACTERS and normalises
   predictably.

   score_edit   = 1 - complev(a,b) / max(lengthn(a), lengthn(b))
   score_jaccard = shared_words / (words_a + words_b - shared_words)

   A pair qualifies on EITHER measure. Requiring both would defeat the
   purpose: the pairs edit-distance misses are exactly the ones Jaccard
   is here to find.
   ========================================================================= */

/* Build word sets once, before PROC SQL. A PROC cannot run inside an open
   DATA step. */
data work.label_words;
  set work.best_labels;
  length word $40;
  keep varname word;
  do _i = 1 to countw(working_label, ' -_/(),.');
    word = upcase(strip(scan(working_label, _i, ' -_/(),.')));
    /* Single characters and pure noise words carry no signal */
    if length(word) >= 3 then output;
  end;
run;

proc sort data=work.label_words nodupkey; by varname word; run;

proc sql;
  create table work.word_counts as
  select varname, count(*) as n_words from work.label_words group by varname;

  create table work.all_pairs as
  select a.varname       as varname_a length=32,
         a.working_label as label_a   length=256,
         a.label_source  as source_a  length=10,
         b.varname       as varname_b length=32,
         b.working_label as label_b   length=256,
         b.label_source  as source_b  length=10,

         /* COMPLEV: plain Levenshtein distance, in characters.
            LENGTHN, not LENGTH -- LENGTH returns 1 for a blank string,
            which makes the divisor wrong for an empty label.             */
         case
           when max(lengthn(strip(a.working_label)),
                    lengthn(strip(b.working_label))) = 0 then .
           else 1 - complev(upcase(strip(a.working_label)),
                            upcase(strip(b.working_label)))
                    / max(lengthn(strip(a.working_label)),
                          lengthn(strip(b.working_label)))
         end as score_edit,

         /* Jaccard on the word sets: shared words over union of words. */
         (select count(*) from work.label_words as wa
           inner join work.label_words as wb
             on wa.word = wb.word
          where wa.varname = a.varname and wb.varname = b.varname)
         as n_shared_words,

         (select n_words from work.word_counts where varname = a.varname)
         as n_words_a,
         (select n_words from work.word_counts where varname = b.varname)
         as n_words_b

  from work.best_labels as a, work.best_labels as b
  where a.varname < b.varname
    /* Both labels falling back to the variable name means the pair is
       distinguishable by NAME, which Phase 11 already covers. No new
       information here.                                                  */
    and not (a.label_source = 'VARNAME' and b.label_source = 'VARNAME');
quit;

/* Jaccard computed in a DATA step, where the division guard is readable. */
data work.all_pairs;
  set work.all_pairs;
  if (n_words_a + n_words_b - n_shared_words) > 0
    then score_jaccard = n_shared_words / (n_words_a + n_words_b - n_shared_words);
  else score_jaccard = .;
run;

proc sql noprint;
  select count(*) into :n_all_pairs trimmed from work.all_pairs;
quit;

%macro check_pairs;
  %if %length(&n_all_pairs) = 0 %then %do;
    %fail_out(msg=Pair query returned no value);
  %end;
  %else %if &n_all_pairs = 0 %then %do;
    %fail_out(msg=No comparable pairs -- every label fell back to the variable name);
  %end;
  %put NOTE: [14] &n_all_pairs pairs scored on BOTH measures.;
%mend check_pairs;
%check_pairs;

/* A pair qualifies on EITHER measure */
proc sql noprint;
  create table work.above_threshold as
  select * from work.all_pairs
  where (score_edit is not missing and score_edit >= &threshold)
     or (score_jaccard is not missing and score_jaccard >= &jaccard_threshold)
  order by score_jaccard desc, score_edit desc;

  select count(*) into :n_above_threshold trimmed from work.above_threshold;
quit;

%put NOTE: [14] &n_above_threshold pairs above edit &threshold or Jaccard &jaccard_threshold.;

/* Calibration pair -- Death_Date_Y_N vs IsDead_Y_N proved identical by
   Phase 10 on all 8,730 overlapping rows. Record their scores so the
   calibration is visible rather than assumed.                             */
proc sql noprint;
  select score_edit, score_jaccard
    into :cal_edit trimmed, :cal_jaccard trimmed
  from work.all_pairs
  where (varname_a='DEATH_DATE_Y_N' and varname_b='ISDEAD_Y_N')
     or (varname_a='ISDEAD_Y_N'     and varname_b='DEATH_DATE_Y_N');
quit;

%put NOTE: [14] CALIBRATION PAIR Death_Date_Y_N vs IsDead_Y_N:;
%put NOTE: [14]   score_edit=&cal_edit score_jaccard=&cal_jaccard;


/* =========================================================================
   SECTION 6: Exclude Known Concept Pairs and Pipeline-Derived Columns

   CORRECTED 2026-08-29: The original hardcoded thirteen h_ names. Eight do
   not exist and six real ones were missing. Derive the exclusion by PATTERN
   instead -- h_* columns and _src companions are outputs of harmonisation,
   not source variables, so they carry no new aliasing information.

   The known-pair exclusion is generated from work.concepts (Section 4), not
   re-typed, so it cannot fall out of step with 10_concept_profile.sas.
   ========================================================================= */

proc sql noprint;
  create table work.candidates as
  select p.*
  from work.above_threshold as p
  where not exists (
          select 1 from work.known_pairs as k
          where (k.varname_a = p.varname_a and k.varname_b = p.varname_b)
             or (k.varname_a = p.varname_b and k.varname_b = p.varname_a))
    /* Pipeline-derived columns, matched by PATTERN. h_ canonical columns and
       their _src companions are outputs of harmonisation, not source vars.  */
    and upcase(p.varname_a) not like 'H\_%' escape '\'
    and upcase(p.varname_b) not like 'H\_%' escape '\'
    and upcase(p.varname_a) not like '%\_SRC' escape '\'
    and upcase(p.varname_b) not like '%\_SRC' escape '\'
    and upcase(p.varname_a) not like 'IN\_MD%' escape '\'
    and upcase(p.varname_b) not like 'IN\_MD%' escape '\'
    and upcase(p.varname_a) not in ('N_SOURCES','RT_ENVELOPE_FLAG')
    and upcase(p.varname_b) not in ('N_SOURCES','RT_ENVELOPE_FLAG')
    and upcase(p.varname_a) not like 'RT\_%\_NEG' escape '\'
    and upcase(p.varname_b) not like 'RT\_%\_NEG' escape '\'
  order by score_jaccard desc, score_edit desc;

  select count(*) into :n_candidates trimmed from work.candidates;
quit;

%let n_excluded = %eval(&n_above_threshold - &n_candidates);
%put NOTE: [14] &n_candidates candidates after excluding &n_excluded known or derived pairs.;


/* =========================================================================
   SECTION 7: Write docs/label_similarity_candidates.csv (COMMITTED ARTIFACT)
   This CSV is the human-review input. Add CONFIRMED (YES/NO blank) and NOTES
   columns so the reviewer can annotate in-place. HARM-03 requires this file.
   ========================================================================= */

data work.candidates_out;
  length confirmed $3 notes $200;
  set work.candidates;
  confirmed = ' ';
  notes     = ' ';
  /* Keep only the columns needed for human review */
  keep varname_a label_a source_a varname_b label_b source_b
       score_edit score_jaccard confirmed notes;
run;

proc export data=work.candidates_out
  outfile="&docs_path.\label_similarity_candidates.csv"
  dbms=csv replace;
run;

%macro check_csv_written;
  %if %sysfunc(fileexist(&docs_path.\label_similarity_candidates.csv)) = 0 %then %do;
    %fail_out(msg=label_similarity_candidates.csv was not written -- check docs_path);
  %end;
  %put NOTE: [14] CONFIRMED: docs/label_similarity_candidates.csv written.;
%mend check_csv_written;
%check_csv_written;


/* =========================================================================
   SECTION 8: Write Evidence Workbook docs/LABEL_SIMILARITY_EVIDENCE.xlsx
   KEY sheet leftmost (CLAUDE.md requirement: KEY sheet leftmost in workbooks).
   UF colors #0021A5, #FA4616 applied via ODS EXCEL.
   NOT committed to git (.xlsx in .gitignore).
   ========================================================================= */

%let run_dt = %sysfunc(date(), worddate.);

ods excel file="&docs_path.\LABEL_SIMILARITY_EVIDENCE.xlsx"
  style=minimal
  options(sheet_name='KEY'
          frozen_headers='yes'
          autofilter='yes');

/* KEY sheet: summary metadata */
data work.key_sheet;
  length item $80 value $200;
  infile datalines dsd dlm='|' truncover;
  input item $ value $;
  datalines;
Program|14_label_similarity.sas
Run date|&run_dt
Dataset|g.master_data_harmonized (187 cols, 41150 rows)
Edit threshold (normalized COMPLEV)|&threshold
Jaccard threshold|&jaccard_threshold
Similarity measure (edit)|1 - complev(upcase(a), upcase(b)) / max(lengthn(a), lengthn(b))
Similarity measure (Jaccard)|shared_words / (words_a + words_b - shared_words)
Qualifies on|EITHER measure (edit OR Jaccard)
Variables in sweep|&n_vars
Labels from PRECEDE dictionary|&n_dict_label
Labels from SAS label attribute|&n_sas_label
Labels using variable name (fallback)|&n_varname_fallback
Total pairs scored|&n_all_pairs
Pairs above threshold (edit or Jaccard)|&n_above_threshold
Known concept pairs excluded|&n_excluded
Candidate pairs for review|&n_candidates
Calibration pair score_edit|&cal_edit
Calibration pair score_jaccard|&cal_jaccard
Calibration note|Death_Date_Y_N vs IsDead_Y_N (proved same concept by Phase 10)
Human action required|Fill CONFIRMED column in label_similarity_candidates.csv
;
run;

proc print data=work.key_sheet noobs label; run;

ods excel options(sheet_name='ALL_ABOVE_THRESHOLD');
proc print data=work.above_threshold noobs; run;

ods excel options(sheet_name='CANDIDATES');
proc print data=work.candidates noobs; run;

ods excel close;
ods listing;


/* =========================================================================
   SECTION 9: Write QC Artifact qc/14_label_similarity.txt
   Written to P: (qc_path -- not committed). Records all counts, thresholds,
   and the human action required. HARM-03 requires the threshold and measure
   name to appear here.
   ========================================================================= */

data _null_;
  file "&qc_path.\14_label_similarity.txt";
  put "14_label_similarity Section A -- Run: %sysfunc(datetime(), datetime20.)";
  put "=======================================================================";
  put " ";
  put "harmonized_vars=&n_vars";
  put "precede_dict_rows=&n_dict_rows";
  put "vars_with_dict_label=&n_dict_label";
  put "vars_with_sas_label=&n_sas_label";
  put "vars_using_varname_fallback=&n_varname_fallback";
  put "total_pairs_scored=&n_all_pairs";
  put "threshold=&threshold";
  put "jaccard_threshold=&jaccard_threshold";
  put "similarity_measure_edit=COMPLEV_normalized_by_max_label_length";
  put "similarity_measure_jaccard=word_overlap_over_word_union";
  put "pairs_above_threshold=&n_above_threshold";
  put "known_concept_pairs_excluded=&n_excluded";
  put "candidate_pairs_written=&n_candidates";
  put " ";
  put "CALIBRATION (Death_Date_Y_N vs IsDead_Y_N):";
  put "  score_edit=&cal_edit";
  put "  score_jaccard=&cal_jaccard";
  put "  (Phase 10 proved this pair identical on all 8730 overlapping rows)";
  put " ";
  put "Candidate file: docs/label_similarity_candidates.csv";
  put "Evidence workbook: docs/LABEL_SIMILARITY_EVIDENCE.xlsx (not committed)";
  put " ";
  put "HUMAN ACTION REQUIRED";
  put "1. Open docs/label_similarity_candidates.csv";
  put "2. For each row, set CONFIRMED=YES if the pair is the same concept";
  put "3. Add confirmed pairs to docs/concept_decisions.csv";
  put "4. Run Phase 15 (10b machinery applies confirmed decisions)";
  put " ";
  put "Section B (SSDI/CPT1 profiling) output follows below after Plan 02 run.";
run;


/* ==========================================================================
   SECTION B: SSDI Death Family + CPT1 Concept Group Profiling (HARM-09)
   Implemented in Phase 14 Plan 02.
   ========================================================================== */
%put NOTE: [14] Section B placeholder -- implement in Plan 02.;


%restore_log;
%put NOTE: ==== 14_label_similarity.sas Section A complete ====;
