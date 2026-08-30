/*==========================================================================
  Program : 15_id_overlap.sas
  Purpose : Measure exactly which PRECEDE_STUDY_IDs appear in which of the eight
            source datasets, and how they overlap.

            This is the question that decides whether the eight masters can be
            STACKED for summary statistics, or whether pooling across them would
            double-count patients.

  Why it matters
    The eight masters are believed to be overlapping VARIABLE SETS over ONE
    patient population, not eight separate cohorts -- md3 holds 41,150 rows and
    is thought to be a complete superset. If that is right, stacking md3 and md4
    for a variable both carry gives 48,845 rows for 41,150 people: the 7,695 md4
    patients are counted twice, N is inflated, and the distribution is weighted
    toward whoever appears in more sources.

    If it is WRONG -- if some source holds patients md3 does not -- then md3 is
    not a superset, several existing assertions rest on a false premise, and the
    merge design needs revisiting.

    Either answer is worth having, and neither is currently established beyond
    the row counts.

  Outputs
    g.id_overlap_pairs    every ordered pair of sources: shared, only-A, only-B
    g.id_source_profile   one row per source: N, how many of its IDs are unique
                          to it, how many are in md3
    g.id_membership       one row per PATIENT, with in_md1..in_md8 flags and a
                          count -- the table that answers "how many patients are
                          in exactly one source, two, three..."
    docs/ID_OVERLAP.xlsx
    qc/15_id_overlap.txt

  Reads   : g.prep_md1 .. g.prep_md8 (read-only)

  Author  : 2026-08-29

  PCM compliance -- each of these has bitten this pipeline:
    - No bare open-code %IF (open code needs a %DO block)
    - No apostrophes and no embedded semicolons in %PUT text
    - Every %abort cancel inside a named macro
    - No &SQLOBS; explicit SELECT COUNT(*) INTO :macvar TRIMMED
    - Counts checked with %LENGTH BEFORE use, so a failed query fails loudly
      rather than skipping a gate while appearing to have run
    - No macro that generates SAS statements is called inside a %IF condition
    - No aggregate mixed with an ungrouped expression -- that silently remerges
      and returns one row per DATA row
    - Built in WORK, promoted to g once at the end: hundreds of inserts into a
      permanent dataset on a network drive caused lock failures before
    - No source dataset written
==========================================================================*/

options mprint nofmterr nodate nonumber ps=max ls=200;

%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";

%macro route_log;
  %if &in_pipeline = 0 %then %do;
    proc printto log="&logs_path.\15_id_overlap.log" new;
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

%put NOTE: ==== ID overlap analysis starting ====;


/* =========================================================================
   SECTION 0: Preconditions -- all eight preps present and non-empty
   ========================================================================= */

%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %fail_out(msg=&label directory not found: &path);
  %end;
%mend check_dir;
%check_dir(path=&docs_path, label=docs);
%check_dir(path=&qc_path,   label=qc);

/* The key column must EXIST, and be the same TYPE, in all eight -- checked
   before any query references it. Otherwise a missing column makes the count
   query itself fail, with an SQL error rather than a diagnostic naming the
   dataset.                                                                    */
proc sql noprint;
  create table work.id_meta as
  select upcase(memname) as memname length=16, type, length
  from dictionary.columns
  where libname='G'
    and upcase(memname) in ('PREP_MD1','PREP_MD2','PREP_MD3','PREP_MD4',
                            'PREP_MD5','PREP_MD6','PREP_MD7','PREP_MD8')
    and upcase(name) = 'PRECEDE_STUDY_ID';

  select count(*)            into :n_idmeta  trimmed from work.id_meta;
  select count(distinct type)into :n_idtypes trimmed from work.id_meta;
  select max(length)         into :id_len    trimmed from work.id_meta;
  select min(type)           into :id_type   trimmed from work.id_meta;
quit;

%macro check_key_column;
  %if %length(&n_idmeta) = 0 %then %do;
    %fail_out(msg=Key metadata query returned no value);
  %end;
  %if &n_idmeta ne 8 %then %do;
    %fail_out(msg=PRECEDE_STUDY_ID found in only &n_idmeta of the 8 prep datasets);
  %end;
  %if &n_idtypes ne 1 %then %do;
    %fail_out(msg=PRECEDE_STUDY_ID has more than one TYPE across the sources -- SET would fail);
  %end;
  %if %upcase(&id_type) ne CHAR %then %do;
    %fail_out(msg=PRECEDE_STUDY_ID is &id_type%str(,) not character. This program assumes character.);
  %end;
  %put NOTE: [15_id] key present in all 8%str(,) type &id_type%str(,) max length &id_len.;
%mend check_key_column;
%check_key_column;

proc sql;
  create table work.src_rows (mdnum num, ds_name char(16), n_rows num, n_ids num);
quit;

%macro check_sources;
  %local i n_t n_r n_i;
  %do i = 1 %to 8;
    %let n_t = ;
    proc sql noprint;
      select count(*) into :n_t trimmed from dictionary.tables
      where libname='G' and upcase(memname)="PREP_MD&i";
    quit;
    %if %length(&n_t) = 0 %then %do;
      %fail_out(msg=Existence query failed for prep_md&i);
    %end;
    %if &n_t ne 1 %then %do;
      %fail_out(msg=g.prep_md&i not found -- run Phase 3 first);
    %end;

    /* Row count AND distinct-ID count. If they differ, the key is not unique in
       that source, and every overlap number below would be built on repeated
       IDs rather than distinct patients.                                     */
    %let n_r = ; %let n_i = ;
    proc sql noprint;
      select count(*), count(distinct PRECEDE_STUDY_ID)
        into :n_r trimmed, :n_i trimmed
      from g.prep_md&i;
    quit;
    %if %length(&n_r) = 0 or %length(&n_i) = 0 %then %do;
      %fail_out(msg=Count query failed for prep_md&i);
    %end;
    %if &n_r ne &n_i %then %do;
      %fail_out(msg=prep_md&i has &n_r rows but &n_i distinct IDs -- the key is not unique);
    %end;

    proc sql;
      insert into work.src_rows values(&i, "prep_md&i", &n_r, &n_i);
    quit;
    %put NOTE: [15_id] prep_md&i -- &n_r rows%str(,) &n_i distinct IDs.;
  %end;
%mend check_sources;
%check_sources;


/* =========================================================================
   SECTION 1: Membership -- one row per PATIENT, flagged by source
   -------------------------------------------------------------------------
   Built by stacking ID-ONLY extracts. Stacking is safe HERE precisely because
   only the key is carried: no variable can be double-counted, because no
   variable is present. That is the difference between this and stacking the
   masters for summary statistics.
   ========================================================================= */

/* WRAPPED IN A MACRO. %DO is invalid in open code -- "ERROR: The %DO statement
   is not valid in open code" -- and this DATA step would not have compiled. The
   same rule that puts %IF gates inside macros applies to %DO, and only the %IF
   half was being checked.

   LENGTH comes from the sources, not a hardcoded $12. Phase 1 SRC-06 gates
   PRECEDE_STUDY_ID as Char 12 across all eight, but a length declared BEFORE SET
   fixes the PDV: if any source were wider, IDs would be silently TRUNCATED and
   two distinct patients could collapse onto one key -- corrupting every overlap
   number this program produces. &id_len is the observed maximum, validated in
   SECTION 0.                                                                  */
%macro build_id_stack;
  data work.id_stack;
    length PRECEDE_STUDY_ID $&id_len mdnum 8;
    set
    %do i = 1 %to 8;
      g.prep_md&i (keep=PRECEDE_STUDY_ID in=_in&i)
    %end;
    ;
    %do i = 1 %to 8;
      if _in&i then mdnum = &i;
    %end;
  run;
%mend build_id_stack;
%build_id_stack;

/* A DATA step, not PROC SQL with a mixed aggregate -- an ungrouped expression
   alongside an aggregate silently remerges and yields one row per input row. */
proc sort data=work.id_stack; by PRECEDE_STUDY_ID mdnum; run;

data work.id_membership;
  set work.id_stack;
  by PRECEDE_STUDY_ID;
  array _f {8} in_md1-in_md8;
  retain in_md1-in_md8;
  if first.PRECEDE_STUDY_ID then do _j = 1 to 8;
    _f{_j} = 0;
  end;
  _f{mdnum} = 1;
  if last.PRECEDE_STUDY_ID then do;
    n_sources = sum(of in_md1-in_md8);
    output;
  end;
  keep PRECEDE_STUDY_ID in_md1-in_md8 n_sources;
run;

proc sql noprint;
  select count(*) into :n_patients trimmed from work.id_membership;
quit;

%macro check_membership;
  %if %length(&n_patients) = 0 %then %do;
    %fail_out(msg=Membership count query returned no value);
  %end;
  %else %if &n_patients = 0 %then %do;
    %fail_out(msg=No patients found across the eight sources);
  %end;
  %put NOTE: [15_id] &n_patients distinct patients across all eight sources.;
%mend check_membership;
%check_membership;


/* =========================================================================
   SECTION 2: Is md3 really a superset?
   -------------------------------------------------------------------------
   The whole merge design rests on this. If any patient appears in another
   source but NOT md3, then md3 is not a superset, the 1:1 merge onto md3 as
   spine silently drops those patients, and the row-count assertions that have
   been passing were checking the wrong thing.
   ========================================================================= */

proc sql noprint;
  select count(*) into :n_not_in_md3 trimmed
  from work.id_membership where in_md3 = 0;
  select count(*) into :n_md3 trimmed
  from work.id_membership where in_md3 = 1;
quit;

%macro check_superset;
  %if %length(&n_not_in_md3) = 0 %then %do;
    %fail_out(msg=Superset query returned no value);
  %end;
  %if &n_not_in_md3 = 0 %then %do;
    %put NOTE: [15_id] md3 IS a complete superset -- all &n_patients patients appear in it.;
    %put NOTE- The merge spine is sound and stacking would double-count every;
    %put NOTE- patient who appears in more than one source.;
  %end;
  %else %do;
    %put WARNING: [15_id] md3 is NOT a superset -- &n_not_in_md3 patients are absent from it.;
    %put WARNING- The 1:1 merge onto md3 as spine DROPS those patients silently.;
    %put WARNING- Several row-count assertions rest on this premise and would need;
    %put WARNING- revisiting. See the Not In MD3 sheet.;
  %end;
%mend check_superset;
%check_superset;

proc sql;
  create table work.not_in_md3 as
  select * from work.id_membership where in_md3 = 0;
quit;


/* =========================================================================
   SECTION 3: Pairwise overlap
   -------------------------------------------------------------------------
   Every ordered pair, so md3-against-md4 and md4-against-md3 are both readable
   without mental arithmetic. n_only_a is what pair A would contribute that B
   does not -- the number that decides whether combining them adds patients.
   ========================================================================= */

proc sql;
  create table work.pairs (a num, b num);
quit;

data work.pairs;
  do a = 1 to 8;
    do b = 1 to 8;
      if a ne b then output;
    end;
  end;
run;

proc sql;
  create table work.id_overlap_pairs
    (src_a char(16), src_b char(16), n_a num, n_b num,
     n_shared num, n_only_a num, n_only_b num, pct_a_shared num);
quit;

%macro pairwise;
  %local i a b;
  %do i = 1 %to 56;
    /* FIRSTOBS=/OBS=, not POINT= -- POINT= takes a VARIABLE NAME, so point=&i
       resolves to a literal and SAS reports "Expecting a name".            */
    data _null_;
      set work.pairs (firstobs=&i obs=&i);
      call symputx('a', a, 'L');
      call symputx('b', b, 'L');
    run;

    proc sql;
      insert into work.id_overlap_pairs
      select "prep_md&a", "prep_md&b",
             sum(in_md&a),
             sum(in_md&b),
             sum(in_md&a = 1 and in_md&b = 1),
             sum(in_md&a = 1 and in_md&b = 0),
             sum(in_md&a = 0 and in_md&b = 1),
             case when sum(in_md&a) = 0 then .
                  else 100 * sum(in_md&a = 1 and in_md&b = 1) / sum(in_md&a) end
      from work.id_membership;
    quit;
  %end;
%mend pairwise;
%pairwise;


/* Each of the 56 pairs must have produced exactly one row. A silently failed
   insert would leave a gap that no other check would notice.                 */
proc sql noprint;
  select count(*), count(distinct catx('|', src_a, src_b))
    into :n_pair_rows trimmed, :n_pair_u trimmed
  from work.id_overlap_pairs;
quit;

%macro assert_pairs;
  %if %length(&n_pair_rows) = 0 %then %do;
    %fail_out(msg=Pair row count returned no value);
  %end;
  %if &n_pair_rows ne 56 %then %do;
    %fail_out(msg=Expected 56 ordered pairs%str(,) got &n_pair_rows);
  %end;
  %if &n_pair_u ne 56 %then %do;
    %fail_out(msg=Pair table has duplicates -- &n_pair_u distinct of &n_pair_rows);
  %end;
  %put NOTE: [15_id] all 56 ordered pairs present and distinct.;
%mend assert_pairs;
%assert_pairs;


/* =========================================================================
   SECTION 4: Per-source profile
   ========================================================================= */

proc sql;
  create table work.id_source_profile
    (mdnum num, ds_name char(16), n_ids num, n_unique_to_source num,
     n_also_in_md3 num, pct_unique num);
quit;

%macro source_profile;
  %local i;
  %do i = 1 %to 8;
    proc sql;
      insert into work.id_source_profile
      select &i, "prep_md&i",
             sum(in_md&i),
             sum(in_md&i = 1 and n_sources = 1),
             sum(in_md&i = 1 and in_md3 = 1),
             case when sum(in_md&i) = 0 then .
                  else 100 * sum(in_md&i = 1 and n_sources = 1) / sum(in_md&i) end
      from work.id_membership;
    quit;
  %end;
%mend source_profile;
%source_profile;

/* Cross-check the profile against SECTION 0. If the membership build altered or
   collapsed any ID -- the truncation risk the length validation guards against --
   these two counts diverge, and that is the signal.                          */
proc sql noprint;
  select count(*) into :n_prof trimmed from work.id_source_profile;
  select count(*) into :n_mismatch trimmed
  from work.id_source_profile as p
  inner join work.src_rows as r on p.mdnum = r.mdnum
  where p.n_ids ne r.n_ids;
quit;

%macro assert_profile;
  %if %length(&n_prof) = 0 or %length(&n_mismatch) = 0 %then %do;
    %fail_out(msg=Profile check queries returned no value);
  %end;
  %if &n_prof ne 8 %then %do;
    %fail_out(msg=Expected 8 source profile rows%str(,) got &n_prof);
  %end;
  %if &n_mismatch > 0 %then %do;
    %put ERROR: &n_mismatch sources have a membership count that disagrees with;
    %put ERROR- their source row count. The membership build altered or collapsed;
    %put ERROR- IDs -- check for key truncation.;
    %fail_out(msg=Membership counts disagree with source counts);
  %end;
  %put NOTE: [15_id] per-source counts agree with the source datasets.;
%mend assert_profile;
%assert_profile;

/* How many patients appear in exactly one source, two, three ... eight */
proc sql;
  create table work.n_source_dist as
  select n_sources, count(*) as n_patients,
         100 * count(*) / &n_patients as pct
  from work.id_membership
  group by n_sources
  order by n_sources;
quit;


/* =========================================================================
   SECTION 5: What stacking would cost
   -------------------------------------------------------------------------
   The number the whole question turns on. If every patient appeared in exactly
   one source, stacking would be free. They do not, so this quantifies the
   double-counting a stacked summary statistic would carry.
   ========================================================================= */

proc sql noprint;
  select sum(n_sources) into :n_stacked_rows trimmed from work.id_membership;
  select count(*) into :n_multi trimmed from work.id_membership where n_sources > 1;
  select max(n_sources) into :max_sources trimmed from work.id_membership;
quit;

%macro stack_cost;
  %if %length(&n_stacked_rows) = 0 %then %do;
    %fail_out(msg=Stack cost query returned no value);
  %end;
  %put NOTE: [15_id] Stacking all eight sources would give &n_stacked_rows rows;
  %put NOTE- for &n_patients distinct patients.;
  %put NOTE- &n_multi patients appear in more than one source and would be counted;
  %put NOTE- once per source they appear in. The most any patient appears is &max_sources.;
%mend stack_cost;
%stack_cost;


/* =========================================================================
   SECTION 6: Promote, then report
   ========================================================================= */

data g.id_membership;    set work.id_membership;    run;
data g.id_overlap_pairs; set work.id_overlap_pairs; run;
data g.id_source_profile;set work.id_source_profile;run;

%macro verify_promotion;
  %local n_perm n_pperm n_sperm;
  %let n_perm = ; %let n_pperm = ; %let n_sperm = ;
  proc sql noprint;
    select count(*) into :n_perm  trimmed from g.id_membership;
    select count(*) into :n_pperm trimmed from g.id_overlap_pairs;
    select count(*) into :n_sperm trimmed from g.id_source_profile;
  quit;
  /* All THREE checked. Verifying one and reporting success for three would let a
     partial write finish with a completion message.                          */
  %if %length(&n_perm) = 0 or %length(&n_pperm) = 0 or %length(&n_sperm) = 0 %then %do;
    %fail_out(msg=Could not read one of the promoted tables);
  %end;
  %if &n_perm ne &n_patients %then %do;
    %fail_out(msg=Promoted &n_perm membership rows but work held &n_patients);
  %end;
  %if &n_pperm ne 56 %then %do;
    %fail_out(msg=Promoted &n_pperm pair rows%str(,) expected 56);
  %end;
  %if &n_sperm ne 8 %then %do;
    %fail_out(msg=Promoted &n_sperm profile rows%str(,) expected 8);
  %end;
  %put NOTE: [15_id] promoted &n_perm patients%str(,) &n_pperm pairs%str(,) &n_sperm profiles.;
%mend verify_promotion;
%verify_promotion;

%macro drop_stale;
  %local rc;
  %if %sysfunc(fileexist(%bquote(&docs_path.\ID_OVERLAP.xlsx))) %then %do;
    filename _oldx "&docs_path.\ID_OVERLAP.xlsx";
    %let rc = %sysfunc(fdelete(_oldx));
    filename _oldx clear;
    %if &rc ne 0 %then %do;
      %fail_out(msg=Could not delete the previous ID_OVERLAP.xlsx -- rc=&rc. It may be open in Excel.);
    %end;
  %end;
%mend drop_stale;
%drop_stale;

ods excel file="&docs_path.\ID_OVERLAP.xlsx"
    options(sheet_name="KEY" embedded_titles="yes" autofilter="all" frozen_headers="1");

title justify=left color=CX0021A5 height=14pt "PeCAN -- PRECEDE_STUDY_ID Overlap Across the Eight Masters";
title2 justify=left height=10pt "&n_patients distinct patients. Generated %sysfunc(datetime(), datetime20.)";

data work.key;
  length item $40 value $250;
  item='Question';            value="Do the eight masters hold ONE patient population or eight? The answer decides whether they can be stacked for summary statistics."; output;
  item='Distinct patients';   value="&n_patients"; output;
  item='Rows if stacked';     value="&n_stacked_rows"; output;
  item='Patients in >1 source'; value="&n_multi -- each would be counted once per source it appears in"; output;
  item='Most sources per patient'; value="&max_sources"; output;
  item='Patients not in md3'; value="&n_not_in_md3 -- if this is 0, md3 is a complete superset and the merge spine is sound"; output;
  item='Why not just stack';  value="A variable carried by two sources would have its N inflated by the shared patients, and its distribution weighted toward whoever appears in more sources. PCM-T-03 records a stack-then-dedup that produced exactly 41,150 rows and looked correct while discarding md8 entirely."; output;
  item='Overlap Pairs sheet'; value="Every ORDERED pair. n_only_a is what A holds that B does not -- the number that decides whether combining them adds patients."; output;
  item='Source Profile sheet';value="Per source: how many of its patients are unique to it, and how many are also in md3."; output;
  item='Sources Per Patient'; value="How many patients appear in exactly one source, two, three, and so on."; output;
  item='Nothing was changed'; value="This program reads the eight prep datasets and writes reports. It combines nothing."; output;
run;

proc print data=work.key noobs label; var item value; run;

ods excel options(sheet_name="Sources Per Patient");
proc print data=work.n_source_dist noobs label;
  var n_sources n_patients pct;
  label n_sources="Sources Containing The Patient" n_patients="Patients" pct="Pct";
  format n_patients comma12. pct 6.2;
run;

ods excel options(sheet_name="Source Profile");
proc print data=work.id_source_profile noobs label;
  var mdnum ds_name n_ids n_unique_to_source n_also_in_md3 pct_unique;
  label mdnum="MD" ds_name="Dataset" n_ids="Patients"
        n_unique_to_source="Unique To It" n_also_in_md3="Also In md3" pct_unique="Pct Unique";
  format n_ids n_unique_to_source n_also_in_md3 comma12. pct_unique 6.2;
run;

ods excel options(sheet_name="Overlap Pairs");
proc print data=work.id_overlap_pairs noobs label;
  var src_a src_b n_a n_b n_shared n_only_a n_only_b pct_a_shared;
  label src_a="Source A" src_b="Source B" n_a="A Patients" n_b="B Patients"
        n_shared="Shared" n_only_a="Only A" n_only_b="Only B"
        pct_a_shared="Pct Of A Also In B";
  format n_a n_b n_shared n_only_a n_only_b comma12. pct_a_shared 6.2;
run;

%macro not_md3_sheet;
  %if &n_not_in_md3 > 0 %then %do;
    ods excel options(sheet_name="Not In MD3");
    proc print data=work.not_in_md3 (obs=500) noobs label;
      var PRECEDE_STUDY_ID in_md1-in_md8 n_sources;
      label PRECEDE_STUDY_ID="Patient" n_sources="Sources";
    run;
  %end;
%mend not_md3_sheet;
%not_md3_sheet;

ods excel close;
title;

%macro check_xlsx;
  %if %sysfunc(fileexist(%bquote(&docs_path.\ID_OVERLAP.xlsx))) = 0 %then %do;
    %fail_out(msg=ID_OVERLAP.xlsx was not written);
  %end;
  %put NOTE: [15_id] workbook written.;
%mend check_xlsx;
%check_xlsx;


/* =========================================================================
   SECTION 7: QC artifact
   ========================================================================= */

data _null_;
  file "&qc_path.\15_id_overlap.txt";
  put "15_id_overlap -- Run: %sysfunc(datetime(), datetime20.)";
  put "=======================================================================";
  put " ";
  put "distinct_patients=&n_patients";
  put "rows_if_stacked=&n_stacked_rows";
  put "patients_in_more_than_one_source=&n_multi";
  put "max_sources_per_patient=&max_sources";
  put "patients_not_in_md3=&n_not_in_md3";
  put "patients_in_md3=&n_md3";
  put " ";
  put "WHAT THIS DECIDES";
  put "  If patients_not_in_md3 = 0, md3 is a complete superset: the 1:1 merge";
  put "  onto md3 as spine loses no patient, and stacking the masters for summary";
  put "  statistics WOULD double-count every patient appearing in more than one";
  put "  source.";
  put " ";
  put "  If patients_not_in_md3 > 0, md3 is NOT a superset. The merge silently";
  put "  drops those patients, and the row-count assertions that have been passing";
  put "  were checking the wrong thing.";
  put " ";
  put "STACKING IS SAFE HERE, AND ONLY HERE";
  put "  SECTION 1 stacks ID-ONLY extracts. IDs repeat there by design and are";
  put "  consolidated to one row per patient. No ANALYTIC MEASUREMENT is carried,";
  put "  so none can be double-counted. That is precisely the difference between";
  put "  this program and stacking the masters to summarise their variables.";
  put " ";
  put "  PCM-T-03 records the alternative: a stack-then-dedup that yielded exactly";
  put "  41,150 rows and looked correct while discarding md8 entirely. Row count";
  put "  alone does not validate a combine.";
run;

%put NOTE: ==== ID overlap complete ====;
%put NOTE- Workbook: docs/ID_OVERLAP.xlsx;
%put NOTE- Tables  : g.id_membership%str(,) g.id_overlap_pairs%str(,) g.id_source_profile;

%restore_log;
