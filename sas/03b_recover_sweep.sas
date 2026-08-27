/* Program: 03b_recover_sweep.sas
   Phase   : cross-cutting diagnostic (feeds PCM-D-11, MRG-04)
   Purpose : For EVERY ordered pair of prep sources and EVERY variable they
             share, count the rows where the first source is missing and the
             second has a value. That count is what a KEEP=-based ownership
             merge silently discards when the first source is the owner.

             Also counts DISAGREEMENTS -- rows where both have a value and the
             values differ. A recoverable count says "coalescing would add
             data"; a disagreement count says "coalescing is a decision, not a
             gap-fill". Both are needed before changing the merge.

   Why this exists: PCM-D-11 was closed as "md3-owns costs nothing" on a
             two-source spot check (md3<-md5, md3<-md6) that omitted md8, the
             largest non-spine source. It was wrong. A later md3<-md8 check
             found Cognitive_Score and Frailty_Score losing ~8-9k values each,
             and a full md3/md8 sweep found three MORE variables that no spot
             check would have thought to test. Spot checks produced the wrong
             answer twice. This does not spot check.

   Output  : qc/03b_recover_sweep.txt         -- committed, grep-able
             work.recover_all                 -- full matrix, all pairs
             work.recover_owner_loss          -- ONLY the losses that the
                                                CURRENT ownership map causes
   Runtime : 56 ordered pairs x shared variables. Expect several minutes.
             Read the owner-loss table first; the full matrix is reference.

   Author  : 2026-08-27
   Revised : 2026-08-27 -- review fixes:
             * POINT= no longer combined with WHERE= (SAS rejects that outright);
               work.pairvars_testable is pre-filtered before the loop.
             * One PROC SQL pass per variable-pair instead of three joins.
             * Numeric comparisons use a 1e-8 tolerance; character stays exact.
             * %local declarations hoisted out of the %do loop.
             NOT changed: "&path.\file" is correct macro syntax -- the period
             terminates the variable name and is consumed by the macro processor,
             leaving the backslash. Do not rewrite these to "&path\file".
   PCM     : no PROC SQL UPDATE, no in-place rewrite, no source dataset written.
             Every %abort cancel inside a named macro (PCM-R-05).
             Every comparison IS NOT MISSING guarded (PCM-T-11).
*/

options nodate nonumber ps=max ls=200;

%let g_path    = C:\Master_Renamed_same_format_accross;
%let qc_path   = C:\Master_Renamed_same_format_accross\qc;
%let logs_path = C:\Master_Renamed_same_format_accross\logs;

libname g     "&g_path";
libname qclib "&qc_path";

%macro fail_out(msg=);
  %put ERROR: &msg;
  ods listing;
  proc printto; run;
  %abort cancel;
%mend fail_out;

%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: &label directory not found: &path;
    %abort cancel;
  %end;
%mend check_dir;
%check_dir(path=&qc_path,   label=qc);
%check_dir(path=&logs_path, label=logs);

proc printto log="&logs_path.\03b_recover_sweep.log" new;
run;

%put NOTE: ==== Cross-source recoverability sweep starting ====;

/* ---- Preconditions: all eight prep datasets present -------------------- */
%macro check_preps;
  %local i n;
  %do i = 1 %to 8;
    proc sql noprint;
      select count(*) into :n trimmed from dictionary.tables
      where libname='G' and upcase(memname)="PREP_MD&i";
    quit;
    %if &n ne 1 %then %fail_out(msg=g.prep_md&i not found. Run Phase 3 first.);
  %end;
  %put NOTE: PRECONDITION OK -- all eight prep datasets present.;
%mend check_preps;
%check_preps;


/* =========================================================================
   SECTION 1: Build the variable-overlap map for every ordered pair
   -------------------------------------------------------------------------
   ORDERED, not unordered: md3<-md8 and md8<-md3 answer different questions.
   The first is "what does md3-owns discard"; the second is the reverse.
   56 ordered pairs (8 x 7).

   NOTE: type is deliberately NOT matched. A variable that is character in one
   source and numeric in another is exactly the blind spot that hid md8 from
   the original BMI check. Those pairs are FLAGGED, not silently skipped --
   they cannot be compared until the types are harmonised, and that fact is
   itself a finding.
   ========================================================================= */

proc sql noprint;
  create table work.allcols as
  select upcase(memname) as memname length=16,
         upcase(name)    as varname length=32,
         type
  from dictionary.columns
  where libname='G' and upcase(memname) like 'PREP\_MD_' escape '\'
    and upcase(name) ne 'PRECEDE_STUDY_ID';
quit;

data work.pairs;
  length src_from src_to $16;
  do i = 1 to 8;
    do j = 1 to 8;
      if i ne j then do;
        src_from = cats('PREP_MD', put(i,1.));   /* the OWNER side */
        src_to   = cats('PREP_MD', put(j,1.));   /* the DONOR side */
        output;
      end;
    end;
  end;
  drop i j;
run;

proc sql noprint;
  create table work.pairvars as
  select p.src_from, p.src_to, a.varname,
         a.type as type_from, b.type as type_to,
         (a.type ne b.type) as type_mismatch
  from work.pairs p
  inner join work.allcols a on a.memname = p.src_from
  inner join work.allcols b on b.memname = p.src_to and b.varname = a.varname
  order by src_from, src_to, varname;

  select count(*) into :n_tests trimmed from work.pairvars where type_mismatch = 0;
  select count(*) into :n_skip  trimmed from work.pairvars where type_mismatch = 1;
quit;

/* Pre-filter into its own dataset. POINT= (direct access) CANNOT be combined
   with a WHERE= dataset option or WHERE statement -- SAS rejects it with
   "ERROR: POINT= is not valid when WHERE is specified", because direct access
   bypasses the WHERE mechanism entirely. The loop below reads by observation
   number, so the filtering has to happen first.                              */
data work.pairvars_testable;
  set work.pairvars;
  where type_mismatch = 0;
run;

%put NOTE: &n_tests comparable variable-pairs to test; &n_skip skipped on type mismatch.;


/* =========================================================================
   SECTION 2: The sweep
   -------------------------------------------------------------------------
   For each comparable pair: recoverable (from is missing, to has a value) and
   disagree (both have values, values differ).
   ========================================================================= */

proc sql;
  create table work.recover_all
    (src_from char(16), src_to char(16), varname char(32),
     recoverable num, disagree num, both_present num);
quit;

%macro sweep_all;
  /* All %local declarations at the top -- declaring inside the %do loop works
     but re-declares on every iteration for no benefit.                        */
  %local i n_rows f t v vtype n_rec n_dis n_both diff_expr;

  proc sql noprint;
    select count(*) into :n_rows trimmed from work.pairvars_testable;
  quit;

  %do i = 1 %to &n_rows;
    data _null_;
      set work.pairvars_testable point=&i;
      call symputx('f',     src_from,  'L');
      call symputx('t',     src_to,    'L');
      call symputx('v',     varname,   'L');
      call symputx('vtype', type_from, 'L');
      stop;
    run;

    /* Type-aware difference test. For CHARACTER (type=2) an exact `ne` is what
       you want -- a code of 'GQ' vs 'U' is a real disagreement. For NUMERIC,
       exact `ne` flags floating-point representation noise (differences of
       ~1e-14 between two exports of the same value) as disagreement, which
       would bury the real conflicts in false positives.                       */
    %if &vtype = 2 %then
      %let diff_expr = (a.&v ne b.&v);
    %else
      %let diff_expr = (abs(a.&v - b.&v) > 1e-8);

    /* ONE pass per variable-pair, not three. The earlier version ran three
       separate inner joins over the same two datasets for every column --
       across thousands of pairs on a network drive that is the difference
       between minutes and an afternoon.                                       */
    proc sql noprint;
      select coalesce(sum(a.&v is missing     and b.&v is not missing), 0),
             coalesce(sum(a.&v is not missing and b.&v is not missing), 0),
             coalesce(sum(a.&v is not missing and b.&v is not missing
                          and &diff_expr), 0)
        into :n_rec trimmed, :n_both trimmed, :n_dis trimmed
      from g.&f a inner join g.&t b
        on a.PRECEDE_STUDY_ID = b.PRECEDE_STUDY_ID;

      insert into work.recover_all
        values("&f", "&t", "&v", &n_rec, &n_dis, &n_both);
    quit;

    %if %sysfunc(mod(&i, 100)) = 0 %then %put NOTE: swept &i of &n_rows pairs...;
  %end;
%mend sweep_all;
%sweep_all;

%put NOTE: Sweep complete.;


/* =========================================================================
   SECTION 3: Restrict to the losses the CURRENT ownership map actually causes
   -------------------------------------------------------------------------
   The full matrix is reference. What matters operationally is narrower: for
   each variable, only the OWNER's row matters, because only the owner's copy
   survives the KEEP= merge. A high recoverable count from a non-owner pair is
   irrelevant -- that source was never going to supply the value anyway.
   ========================================================================= */

data work.ownership_resolved;
  set qclib.ownership_map;
  length owner_resolved $4;
  if      index(sources_present,'md3') then owner_resolved = 'md3';
  else if index(sources_present,'md8') then owner_resolved = 'md8';
  else if index(sources_present,'md1') then owner_resolved = 'md1';
  else if index(sources_present,'md2') then owner_resolved = 'md2';
  else if index(sources_present,'md6') then owner_resolved = 'md6';
  else if index(sources_present,'md7') then owner_resolved = 'md7';
  else if index(sources_present,'md4') then owner_resolved = 'md4';
  else if index(sources_present,'md5') then owner_resolved = 'md5';
  if upcase(varname) in ('FEELS_EXAUSTED','LOW_PHYSICAL_ACTIVITY','SLOW_WALKING_SPEED',
                         'UNINTENDED_WEIGHT_LOSS','WEEK_GRIP_STRENGTH')
     then owner_resolved = 'md7';
  if upcase(varname) in ('PRECEDE_STUDY_ID_1','PRECEDE_STUDY_ID') then delete;
  varname_u = upcase(varname);
run;

proc sql;
  create table work.recover_owner_loss as
  select r.varname,
         o.owner_resolved as owner,
         r.src_to as donor,
         r.recoverable,
         r.disagree,
         r.both_present
  from work.recover_all r
  inner join work.ownership_resolved o
    on o.varname_u = r.varname
   and upcase(r.src_from) = upcase(cats('PREP_', o.owner_resolved))
  where r.recoverable > 0
  order by r.recoverable desc, r.varname;
quit;

proc sql noprint;
  select count(*)                 into :n_loss    trimmed from work.recover_owner_loss;
  select count(distinct varname)  into :n_lossvar trimmed from work.recover_owner_loss;
  select coalesce(sum(disagree),0) into :n_disagree trimmed from work.recover_owner_loss;
quit;


/* =========================================================================
   SECTION 4: Report
   ========================================================================= */

data _null_;
  file "&qc_path.\03b_recover_sweep.txt";
  put "Cross-source recoverability sweep -- Run: %sysfunc(datetime(), datetime20.)";
  put "=========================================================================";
  put " ";
  put "WHAT THIS MEASURES";
  put "  recoverable  = rows where the OWNER is missing and a DONOR has a value.";
  put "                 These are values the KEEP= ownership merge DISCARDS.";
  put "  disagree     = rows where both have a value and the values DIFFER.";
  put "                 Non-zero means coalescing is a DECISION, not a gap-fill.";
  put "                 CHARACTER variables use exact inequality. NUMERIC variables";
  put "                 use abs(a-b) > 1e-8, so floating-point representation noise";
  put "                 between two exports is not reported as a conflict.";
  put "  both_present = rows where both have a value (the disagreement denominator).";
  put " ";
  put "WHY THIS EXISTS";
  put "  PCM-D-11 was closed as 'md3-owns costs nothing' on a spot check that";
  put "  omitted md8. It was wrong -- Cognitive_Score and Frailty_Score were each";
  put "  losing 8-9k values, and three more variables were found only by sweeping";
  put "  all of md3/md8 rather than guessing which to test.";
  put " ";
  put "SCOPE NOTE";
  put "  &n_skip variable-pairs were SKIPPED because the types differ between";
  put "  sources. They cannot be compared until harmonised -- see the type";
  put "  mismatch section below. A skipped pair is NOT a clean result.";
  put " ";
  put "=== OWNERSHIP LOSSES (act on these) ===";
  put "variables affected=&n_lossvar   owner/donor rows=&n_loss   total disagreements=&n_disagree";
  put " ";
  put @1 "Variable" @36 "Owner" @44 "Donor" @56 "Recoverable" @70 "Disagree";
  put @1 "-----------------------------------------------------------------------------";
run;

data _null_;
  set work.recover_owner_loss end=eof;
  file "&qc_path.\03b_recover_sweep.txt" mod;
  put @1 varname $32. @36 owner $6. @44 donor $10. @56 recoverable 8. @70 disagree 8.;
  if eof then do;
    put " ";
    put "Reading this table:";
    put "  disagree = 0  -> coalescing from the donor is a safe gap-fill.";
    put "  disagree > 0  -> the sources conflict where both have data. Coalescing";
    put "                   silently picks the owner. Resolve before coalescing.";
  end;
run;

/* Type mismatches -- invisible to the sweep, so named explicitly */
proc sql noprint;
  create table work.type_mismatch as
  select distinct varname, src_from, src_to, type_from, type_to
  from work.pairvars where type_mismatch = 1
  order by varname;
  select count(distinct varname) into :n_tmvar trimmed from work.type_mismatch;
quit;

data _null_;
  file "&qc_path.\03b_recover_sweep.txt" mod;
  put " ";
  put "=== TYPE MISMATCHES (not tested -- &n_tmvar variables) ===";
  put "These could not be compared because the type differs between sources.";
  put "This is the same blind spot that hid md8 from the original BMI check:";
  put "md8's Admit_BMI was character then, so the coalesce silently skipped it.";
  put " ";
run;

data _null_;
  set work.type_mismatch;
  file "&qc_path.\03b_recover_sweep.txt" mod;
  put @1 varname $32. @36 src_from $10. @48 src_to $10. @60 "type " type_from 1. " vs " type_to 1.;
run;

%put NOTE: ==== Sweep complete -- &n_lossvar variables lose data under current ownership ====;
%put NOTE- Report: qc/03b_recover_sweep.txt;
%put NOTE- Full matrix: work.recover_all;
%put NOTE- Action list: work.recover_owner_loss;

proc printto;
run;
