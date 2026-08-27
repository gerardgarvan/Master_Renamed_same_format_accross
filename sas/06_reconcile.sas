/* Program: 06_reconcile.sas
   Phase   : 6 -- Variable Reconciliation
   Purpose : Read-only QC program over g.master_data_merged. Confirms the 16 deliberately-
             separate columns are present (D-01, D-02, D-03), counts the Emergent
             distribution (D-04), documents the rt_envelope_flag distribution (MRG-05),
             asserts that the deliberate columns are populated (not just present),
             and writes a committed prose QC summary to qc/06_reconcile_summary.txt.
   Requirements: D-01, D-02, D-03, D-04, MRG-05, REC-01, REC-02, REC-03, REC-04
   Author  : Executor (Phase 6 Plan 02)
   Created : 2026-08-27
   Revised : 2026-08-27 -- QC completeness fixes, see REVISION NOTES below
   PCM violations avoided:
     PCM-T-01: no PROC SQL UPDATE
     PCM-T-02: no data X; set X;
     PCM-T-11: every numeric comparison guarded with IS NOT MISSING
     PCM-R-05: every %abort cancel is inside a named %macro definition
     All counts use SELECT COUNT(*) INTO :macvar TRIMMED (never &SQLOBS)
   NOTE: This program MODIFIES NO DATASET. It reads g.master_data_merged (read-only)
         and writes only qc/06_reconcile_summary.txt. It does NOT call any prep program.

   ---------------------------------------------------------------------------
   REVISION NOTES -- what changed and why
   ---------------------------------------------------------------------------
   R1. SECTION 3b previously promised to "flag loudly" on a zero populated count
       but only printed the number. A zero looked identical to 41,150. Now
       %flag_if_zero emits WARNING lines and sets &pop_status, and the summary
       file states its own verdict instead of leaving a reader to compare six
       numbers against six parenthetical expectations.

   R2. SECTION 1 now asserts column TYPE, not just presence. SECTION 3 compared
       rt_envelope_flag to numeric 0/1 on an unverified type. PROC SQL does not
       implicitly convert across types the way a DATA step does -- a character
       column would raise "components that are of different data types" and kill
       the step. This program already documents that exact lesson for Emergent
       (Y/N, not 1/0); it now applies the same skepticism to the flag. The
       distribution is also computed type-agnostically via PUT(), so it reports
       rather than fails even if the type is unexpected.

   R3. SECTION 3 filtered missing rt_envelope_flag out via WHERE and never
       reported it. If the flag were assigned only to violating rows, the output
       would read "0 at 0, 9 at 1" with no sign that the rest of the table was
       excluded. The WHERE is gone; missing is now a reported category.

   R4. Emergent and rt_envelope_flag distributions gained an "other" bucket.
       Previously a stray value fell into no category and the counts silently
       failed to sum to N, while the summary presented them as exhaustive. Every
       distribution now reconciles to the row count, and that reconciliation is
       itself checked.

   R5. Every count is now reported against a denominator. &n_total is captured
       once and printed in the summary header. "Death_Date_Y_N non-missing:
       41150" is uninterpretable on its own.

   R6. COALESCE(SUM(...), 0) throughout. SUM() over zero qualifying rows returns
       missing, which would resolve into the macro variable as "." and print
       malformed prose. Only reachable on an empty table now that the SECTION 3
       WHERE is gone, but it costs nothing.

   R7. logs_path was defined and never used, while a comment pointed at
       logs/06_reconcile.log as a grep target that nothing created. PROC PRINTTO
       now actually routes the log there.

   Reviewed and rejected:
     - "&qc_path.\file.txt is ambiguous, drop the dot": incorrect. The trailing
       dot is the macro-name delimiter and is consumed, yielding exactly one
       backslash. Removing it is the less defensive form, not the more.
     - "use eq instead of = in %if": %if evaluates through %eval automatically
       and the two are synonyms. Style only.
     - "Feels_Exausted / Week_Grip_Strength look like typos": they match the
       upstream md7 schema. A wrong name aborts at %assert_col, so this class of
       error fails loudly by construction and cannot produce a silent wrong
       answer.
   --------------------------------------------------------------------------- */

/* =========================================================================
   SECTION 0: Options, paths, libname, preconditions
   =========================================================================
   g_path, logs_path and qc_path all live under the P: merge tree, consistent
   with all prior phases (copied from sas/05_qc_merge.sas SECTION 0).
   ========================================================================= */
options nodate nonumber ps=max ls=200;
%let g_path    = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge;
%let logs_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\logs;
%let qc_path   = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\qc;
libname g "&g_path";

%put NOTE: ==== Phase 6 Variable Reconciliation starting -- read-only QC over g.master_data_merged ====;

/* 0a: g library resolves */
%macro check_libname(lib=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    %put ERROR: PRECONDITION -- LIBNAME &lib could not be assigned. Check g_path.;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- LIBNAME &lib resolved.;
%mend check_libname;
%check_libname(lib=g);

/* 0b: qc_path and logs_path directories exist */
%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: PRECONDITION -- &label directory missing: &path;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- &label directory found: &path;
%mend check_dir;
%check_dir(path=&qc_path,   label=qc);
%check_dir(path=&logs_path, label=logs);

/* 0b2: R7 -- route the log to the documented grep target. Previously
   logs_path was defined but never used, so logs/06_reconcile.log existed only
   if an external wrapper happened to create it. */
proc printto log="&logs_path.\06_reconcile.log" new;
run;

%put NOTE: ==== Log routed to &logs_path.\06_reconcile.log ====;

/* 0c: g.master_data_merged exists */
proc sql noprint;
  select count(*) into :n_tab trimmed
  from dictionary.tables
  where libname='G' and upcase(memname)='MASTER_DATA_MERGED';
quit;

%macro check_merged;
  %if &n_tab ne 1 %then %do;
    %put ERROR: PRECONDITION -- g.master_data_merged not found. Run Phase 4 and Phase 5 first.;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- g.master_data_merged present.;
%mend check_merged;
%check_merged;

/* 0c2: R5 -- capture the row count once. Every count below is reported
   against this denominator. */
proc sql noprint;
  select count(*) into :n_total trimmed from g.master_data_merged;
quit;

%macro check_nonempty;
  %if &n_total = 0 %then %do;
    %put ERROR: PRECONDITION -- g.master_data_merged has zero observations.;
    %put ERROR: Every distribution below would be vacuous. Investigate Phase 4/5.;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- g.master_data_merged has &n_total observations.;
%mend check_nonempty;
%check_nonempty;

/* 0d: Open the QC summary and write a header (FILE, not MOD -- starts fresh) */
filename outref "&qc_path.\06_reconcile_summary.txt";
data _null_;
  file outref;
  put "06_reconcile_summary -- Run: %sysfunc(datetime(), datetime20.)";
  put "Phase 6 Variable Reconciliation -- read-only QC over g.master_data_merged";
  put "===========================================================================";
  put " ";
  put "Dataset: g.master_data_merged";
  put "Observations: &n_total";
  put "(Every count below is against this denominator.)";
run;
filename outref clear;


/* =========================================================================
   SECTION 1: Column presence and type checks (D-01, D-02, D-03, D-04, MRG-05)
   Uses dictionary.columns with libname='G' and upcase(memname)='MASTER_DATA_MERGED'.
   %macro assert_col aborts loudly on absence -- that is a real finding, not a defect.
   Each %put on success contains "PASS" so `grep -c "PASS" logs/06_reconcile.log`
   returns at least 18.

   R2: assert_col now optionally checks type. Pass type=num or type=char to
   assert; omit to check presence only. dictionary.columns.type holds 'num' or
   'char'. Catching a type surprise here, with a clear message, beats a PROC SQL
   data-type error three sections downstream.
   ========================================================================= */

%macro assert_col(lib=, dsn=, col=, label=, type=);
  %local n actual;
  proc sql noprint;
    select count(*) into :n trimmed
    from dictionary.columns
    where libname = upcase("&lib")
      and upcase(memname) = upcase("&dsn")
      and upcase(name) = upcase("&col");
  quit;
  %if &n = 0 %then %do;
    %put ERROR: &label -- &col absent from &lib..&dsn -- PRESENCE CHECK FAILED;
    %abort cancel;
  %end;

  %if %superq(type) ne %then %do;
    proc sql noprint;
      select type into :actual trimmed
      from dictionary.columns
      where libname = upcase("&lib")
        and upcase(memname) = upcase("&dsn")
        and upcase(name) = upcase("&col");
    quit;
    %if %upcase(&actual) ne %upcase(&type) %then %do;
      %put ERROR: &label -- &col is type &actual but &type was expected -- TYPE CHECK FAILED;
      %put ERROR: Downstream comparisons assume &type.. Fix the expectation or the column.;
      %abort cancel;
    %end;
    %put NOTE: &label PASS -- &col present in &lib..&dsn (type &actual);
  %end;
  %else %put NOTE: &label PASS -- &col present in &lib..&dsn;
%mend assert_col;

/* D-01: Mortality columns (PCM-D-01 -- keep separate) */
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Death_Date_Y_N, label=REC-01/D-01);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=IsDead_Y_N,     label=REC-01/D-01);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Death,          label=REC-01/D-01);

/* D-02: Frailty char columns (md7-owned, PCM-D-02 -- keep separate) */
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Feels_Exausted,          label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Low_Physical_Activity,   label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Slow_Walking_Speed,      label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Unintended_Weight_Loss,  label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Week_Grip_Strength,      label=REC-02/D-02);

/* D-02: Frailty numeric columns (md3/md5-owned, PCM-D-02 -- keep separate) */
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Feels_Exausted_Value,         label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Low_Physical_Activity_Value,  label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Slow_Walking_Speed_Value,     label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Unintended_Weight_Loss_Value, label=REC-02/D-02);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Week_Grip_Strength_Value,     label=REC-02/D-02);

/* D-03: ISO_SEV columns (PCM-D-03 -- keep separate; md8's is a TOTAL not an average) */
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=ISO_SEV_Exp_IntraOp_MAC_Average, label=REC-03/D-03);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=ISO_SEV_IntraOp_MAC_Average,     label=REC-03/D-03);
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=ISO_SEV_MAC_TOTAL_Exp,           label=REC-03/D-03);

/* D-04: Emergent (retained despite rarity, PCM-D-04).
   Type asserted: PCM-F-06 established this is CHARACTER $1 holding Y/N/blank.
   If it ever arrives numeric, SECTION 2 would silently count zero of everything. */
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=Emergent, label=REC-04/D-04, type=char);

/* MRG-05: rt_envelope_flag (derived flag for envelope-violating rows, PCM-D-08).
   Type NOT asserted -- SECTION 3 handles either type via PUT(). The type is
   reported in the log by assert_col so a change is visible without being fatal. */
%assert_col(lib=G, dsn=MASTER_DATA_MERGED, col=rt_envelope_flag, label=MRG-05);

/* Capture rt_envelope_flag's actual type for the summary narrative */
proc sql noprint;
  select type into :flag_type trimmed
  from dictionary.columns
  where libname='G' and upcase(memname)='MASTER_DATA_MERGED'
    and upcase(name)='RT_ENVELOPE_FLAG';
quit;

%put NOTE: SECTION 1 complete -- all 18 column presence checks passed.;
%put NOTE: rt_envelope_flag is type &flag_type..;

/* Write SECTION 1 result to summary */
data _null_;
  file "&qc_path.\06_reconcile_summary.txt" mod;
  put " ";
  put "SECTION 1 -- Column presence and type (18 checks)";
  put "--------------------------------------------------";
  put "Column presence: 16 deliberate columns + Emergent + rt_envelope_flag all PASS";
  put "  D-01 (mortality, 3 cols):     Death_Date_Y_N  IsDead_Y_N  Death";
  put "  D-02 (frailty char, 5 cols):  Feels_Exausted  Low_Physical_Activity";
  put "                                Slow_Walking_Speed  Unintended_Weight_Loss";
  put "                                Week_Grip_Strength";
  put "  D-02 (frailty num, 5 cols):   Feels_Exausted_Value  Low_Physical_Activity_Value";
  put "                                Slow_Walking_Speed_Value  Unintended_Weight_Loss_Value";
  put "                                Week_Grip_Strength_Value";
  put "  D-03 (ISO_SEV, 3 cols):       ISO_SEV_Exp_IntraOp_MAC_Average";
  put "                                ISO_SEV_IntraOp_MAC_Average";
  put "                                ISO_SEV_MAC_TOTAL_Exp  (md8 col is a TOTAL not an average)";
  put "  D-04 (Emergent):              Emergent   [type asserted CHARACTER, per PCM-F-06]";
  put "  MRG-05 (derived flag):        rt_envelope_flag   [observed type: &flag_type]";
  put " ";
  put "Note on spelling: Feels_Exausted and Week_Grip_Strength reproduce the upstream";
  put "md7 schema exactly. They are not typos in this program. A wrong column name";
  put "aborts at %nrstr(%assert_col), so this error class cannot pass silently.";
run;


/* =========================================================================
   SECTION 2: Emergent distribution (D-04 / REC-04)
   Emergent is CHARACTER $1 (md3-owned; Phase 4 LENGTH block). Values are Y/N/blank.
   NOT 1/0 -- using '1'/'0' returns 0 for both counts (PCM-F-06 established this).
   Guard applied: IS NOT MISSING before comparison (PCM-T-11).
   Report counts only; assert NOTHING about the Y/N split (no expected value for
   the merged md3-owned column).

   R4: an "other" bucket now catches any value that is neither Y, N, nor blank.
       Previously such a value fell into no category and the three counts
       silently failed to sum to N while being presented as exhaustive.
   R6: coalesce(sum(...), 0) so an empty result reports 0, not ".".
   ========================================================================= */
proc sql noprint;
  select coalesce(sum(Emergent is not missing and upcase(strip(Emergent)) = 'Y'), 0),
         coalesce(sum(Emergent is not missing and upcase(strip(Emergent)) = 'N'), 0),
         coalesce(sum(missing(Emergent)), 0),
         coalesce(sum(Emergent is not missing
                      and upcase(strip(Emergent)) not in ('Y','N')), 0)
    into :n_emergent_y    trimmed,
         :n_emergent_n    trimmed,
         :n_emergent_miss trimmed,
         :n_emergent_oth  trimmed
  from g.master_data_merged;
quit;

%put NOTE: REC-04/D-04 -- Emergent: &n_emergent_y Y, &n_emergent_n N, &n_emergent_miss missing, &n_emergent_oth other (of &n_total);

/* R4: the categories must reconcile to the row count. If they do not, the
   distribution is not describing the column and the report would mislead. */
%macro check_emergent_sum;
  %local s;
  %let s = %eval(&n_emergent_y + &n_emergent_n + &n_emergent_miss + &n_emergent_oth);
  %if &s ne &n_total %then %do;
    %put ERROR: Emergent categories sum to &s but the table has &n_total rows.;
    %put ERROR: The reported distribution does not describe the column. Investigate.;
    %abort cancel;
  %end;
  %else %put NOTE: Emergent distribution reconciles to &n_total rows -- PASS;
%mend check_emergent_sum;
%check_emergent_sum;

%macro emergent_other_note;
  %if &n_emergent_oth > 0 %then %do;
    %put WARNING: Emergent holds &n_emergent_oth value(s) outside Y/N/blank.;
    %put WARNING: PCM-F-06 assumed Y/N/blank only. Inspect before using this column.;
  %end;
%mend emergent_other_note;
%emergent_other_note;

data _null_;
  file "&qc_path.\06_reconcile_summary.txt" mod;
  put " ";
  put "SECTION 2 -- Emergent distribution (D-04 / REC-04)";
  put "----------------------------------------------------";
  put "  Y       : &n_emergent_y";
  put "  N       : &n_emergent_n";
  put "  missing : &n_emergent_miss";
  put "  other   : &n_emergent_oth   (values outside Y/N/blank)";
  put "  -------------------------";
  put "  total   : &n_total   (categories reconcile to the row count -- asserted)";
  put " ";
  put "(Values are Y/N/blank -- NOT 1/0. Using '1'/'0' returns zero for both, PCM-F-06.)";
  put "No assertion on the Y/N split: the merged Emergent is md3-owned; its distribution";
  put "has not been separately measured. The 0.05% and 0.09% figures from DECISIONS.md";
  put "(PCM-D-04) are md1 and md8 SOURCE rates and do not describe this column.";
run;


/* =========================================================================
   SECTION 3: rt_envelope_flag distribution (MRG-05 / PCM-D-08)
   Report 0, 1, missing, and other. Do NOT assert n_flag1 = 9 -- this is a
   pipeline observation, not an invariant.
   (RESEARCH Pitfall 4; QC-06 already asserts zero UNFLAGGED violations.)

   R2: comparison goes through PUT() so it is correct whether the column is
       numeric or character. The previous `rt_envelope_flag = 0` assumed numeric;
       PROC SQL raises a data-type error on a character column rather than
       converting, which would have killed the step.
   R3: the WHERE ... IS NOT MISSING is gone. It removed missing rows from the
       denominator without reporting them, so a flag populated only on violating
       rows would have printed "0 at 0, 9 at 1" with no sign that the rest of the
       table was excluded.
   ========================================================================= */
proc sql noprint;
  select coalesce(sum(rt_envelope_flag is not missing
                      and strip(put(rt_envelope_flag, best.)) = '0'), 0),
         coalesce(sum(rt_envelope_flag is not missing
                      and strip(put(rt_envelope_flag, best.)) = '1'), 0),
         coalesce(sum(missing(rt_envelope_flag)), 0),
         coalesce(sum(rt_envelope_flag is not missing
                      and strip(put(rt_envelope_flag, best.)) not in ('0','1')), 0)
    into :n_flag0     trimmed,
         :n_flag1     trimmed,
         :n_flag_miss trimmed,
         :n_flag_oth  trimmed
  from g.master_data_merged;
quit;
/* flagged count is an observation, not an invariant -- see PCM-D-08 */

%put NOTE: MRG-05 -- rt_envelope_flag: &n_flag0 at 0, &n_flag1 at 1, &n_flag_miss missing, &n_flag_oth other (of &n_total);

%macro check_flag_sum;
  %local s;
  %let s = %eval(&n_flag0 + &n_flag1 + &n_flag_miss + &n_flag_oth);
  %if &s ne &n_total %then %do;
    %put ERROR: rt_envelope_flag categories sum to &s but the table has &n_total rows.;
    %put ERROR: The reported distribution does not describe the column. Investigate.;
    %abort cancel;
  %end;
  %else %put NOTE: rt_envelope_flag distribution reconciles to &n_total rows -- PASS;
%mend check_flag_sum;
%check_flag_sum;

%macro flag_shape_notes;
  %if &n_flag_oth > 0 %then %do;
    %put WARNING: rt_envelope_flag holds &n_flag_oth value(s) outside 0/1.;
    %put WARNING: PCM-D-08 describes a binary flag. Inspect before using this column.;
  %end;
  %if &n_flag_miss > 0 %then %do;
    %put WARNING: rt_envelope_flag is missing on &n_flag_miss of &n_total rows.;
    %put WARNING: A flag populated only on violating rows would look like this. If the;
    %put WARNING: intent was 0 for non-violating rows, the derivation is incomplete.;
  %end;
%mend flag_shape_notes;
%flag_shape_notes;

data _null_;
  file "&qc_path.\06_reconcile_summary.txt" mod;
  put " ";
  put "SECTION 3 -- rt_envelope_flag distribution (MRG-05 / PCM-D-08)";
  put "----------------------------------------------------------------";
  put "  0       : &n_flag0";
  put "  1       : &n_flag1   (flagged count is an observation, not asserted)";
  put "  missing : &n_flag_miss";
  put "  other   : &n_flag_oth   (values outside 0/1)";
  put "  -------------------------";
  put "  total   : &n_total   (categories reconcile to the row count -- asserted)";
  put " ";
  put "Column type as read from dictionary.columns: &flag_type";
  put "Counting is type-agnostic (via PUT), so a type change reports rather than fails.";
  put " ";
  put "The rows flagged in Phase 5 QC-06 carry operative sub-interval > room occupancy.";
  put "Each timestamp is individually plausible; only the combination is impossible.";
  put "PCM-D-08: flag, do not null. QC-06 asserts zero UNFLAGGED violations (passes).";
  put "A different flagged count is not a pipeline failure -- it is a data change worth reading.";
  put "A large missing count IS worth reading: it would mean the flag was never set to 0";
  put "on non-violating rows, which changes what the flagged count is a fraction of.";
run;


/* =========================================================================
   SECTION 3b: Populated check for six deliberate columns
   Presence confirms a column EXISTS; it does not confirm that anything landed
   in it. A broken keep list or stale merge produces a column that is present
   and entirely missing. SECTION 1 cannot see this.

   R1: this section previously promised to "flag loudly" and then only printed
       counts -- a zero looked identical to 41,150. %flag_if_zero now emits
       WARNING lines, sets &pop_status, and the summary carries the verdict.
       Still not an %abort: an empty column is a real finding to report, not a
       reason to withhold the rest of the QC output.
   R5: every count is reported against &n_total.
   ========================================================================= */
proc sql noprint;
  select coalesce(sum(Death_Date_Y_N        is not missing), 0),
         coalesce(sum(IsDead_Y_N            is not missing), 0),
         coalesce(sum(Death                 is not missing), 0),
         coalesce(sum(Feels_Exausted        is not missing), 0),
         coalesce(sum(Feels_Exausted_Value  is not missing), 0),
         coalesce(sum(ISO_SEV_MAC_TOTAL_Exp is not missing), 0)
    into :n_pop_dd  trimmed,
         :n_pop_id  trimmed,
         :n_pop_dt  trimmed,
         :n_pop_fe  trimmed,
         :n_pop_fev trimmed,
         :n_pop_iso trimmed
  from g.master_data_merged;
quit;

%let pop_status = PASS;

%macro flag_if_zero(n=, col=, owner=);
  %if &n = 0 %then %do;
    %put WARNING: POPULATED CHECK FAILED -- &col is present but entirely missing.;
    %put WARNING: The keep-separate resolution did not take for &col (&owner).;
    %put WARNING: Check the Phase 4 keep list and the merge that should have populated it.;
    %let pop_status = FAIL;
  %end;
  %else %put NOTE: POPULATED CHECK PASS -- &col has &n non-missing of &n_total (&owner);
%mend flag_if_zero;

%flag_if_zero(n=&n_pop_dd,  col=Death_Date_Y_N,        owner=md3-owned);
%flag_if_zero(n=&n_pop_id,  col=IsDead_Y_N,            owner=md6-owned);
%flag_if_zero(n=&n_pop_dt,  col=Death,                 owner=md7-owned);
%flag_if_zero(n=&n_pop_fe,  col=Feels_Exausted,        owner=md7-owned char);
%flag_if_zero(n=&n_pop_fev, col=Feels_Exausted_Value,  owner=md3-owned num);
%flag_if_zero(n=&n_pop_iso, col=ISO_SEV_MAC_TOTAL_Exp, owner=md8-owned);

%put NOTE: Populated-check overall status: &pop_status;

%macro pop_status_banner;
  %if &pop_status = FAIL %then %do;
    %put WARNING: ==================================================================;
    %put WARNING: ONE OR MORE DELIBERATE COLUMNS LANDED EMPTY. See WARNINGs above.;
    %put WARNING: The merge completed but did not deliver what Phase 6 is verifying.;
    %put WARNING: ==================================================================;
  %end;
%mend pop_status_banner;
%pop_status_banner;

data _null_;
  file "&qc_path.\06_reconcile_summary.txt" mod;
  put " ";
  put "SECTION 3b -- Populated counts for spot-checked deliberate columns";
  put "-------------------------------------------------------------------";
  put "STATUS: &pop_status";
  put " ";
  put "A count of 0 means the column landed empty -- the keep-separate resolution";
  put "did not take. Presence alone (SECTION 1) cannot detect this. A zero here is";
  put "a real finding and raises a WARNING in the log.";
  put " ";
  put "  Death_Date_Y_N        non-missing: &n_pop_dd  of &n_total  (rough expectation: ~41150, md3-owned)";
  put "  IsDead_Y_N            non-missing: &n_pop_id  of &n_total  (rough expectation: ~9462,  md6-owned)";
  put "  Death                 non-missing: &n_pop_dt  of &n_total  (rough expectation: ~9215,  md7-owned)";
  put "  Feels_Exausted        non-missing: &n_pop_fe  of &n_total  (rough expectation: ~9215,  md7-owned char)";
  put "  Feels_Exausted_Value  non-missing: &n_pop_fev of &n_total  (rough expectation: ~41150, md3-owned num)";
  put "  ISO_SEV_MAC_TOTAL_Exp non-missing: &n_pop_iso of &n_total  (rough expectation: ~22473, md8-owned)";
  put " ";
  put "Expectations are approximate and not asserted -- they describe source-file row";
  put "counts, and the merged column may legitimately differ. Only a count of exactly";
  put "zero is treated as a failure.";
run;


/* =========================================================================
   SECTION 4: PCM-D-10 confirmation note (read-only)
   Anchor-offset variables (rt_ANCHOR_to_ADMIT_days, rt_ANCHOR_to_SURGERY_days,
   rt_ANCHOR_to_DISCHG_days) legitimately carry negative values. A negative offset
   means the event preceded the anchor date -- this is meaningful, not an error.
   These variables were NOT nulled by PREP-08. DO NOT add them to PREP-08.
   Resolved: docs/DECISIONS.md PCM-D-10. No data modification in this section.
   ========================================================================= */
%put NOTE: PCM-D-10 -- rt_ANCHOR_to_*_days negatives are legitimate offsets, not nulled.;

data _null_;
  file "&qc_path.\06_reconcile_summary.txt" mod;
  put " ";
  put "SECTION 4 -- PCM-D-10: anchor-offset variables (read-only note)";
  put "----------------------------------------------------------------";
  put "PCM-D-10: anchor-offset rt_ANCHOR_to_*_days negatives are legitimate, not nulled.";
  put "  rt_ANCHOR_to_ADMIT_days, rt_ANCHOR_to_SURGERY_days, rt_ANCHOR_to_DISCHG_days";
  put "  are date offsets from an anchor date, not durations. A negative value means the";
  put "  event preceded the anchor, which is clinically meaningful.";
  put "  PREP-08 does NOT null these variables. Do not add them to PREP-08.";
  put "  Cross-reference: docs/DECISIONS.md PCM-D-10.";
run;


/* =========================================================================
   SECTION 5: Emergent caveat and close-out
   ========================================================================= */
data _null_;
  file "&qc_path.\06_reconcile_summary.txt" mod;
  put " ";
  put "SECTION 5 -- Emergent caveat and close-out";
  put "------------------------------------------";
  put "Emergent caveat (PCM-D-04): the merged value is md3-owned. At source, md1 and md8";
  put "showed 0.05% and 0.09% Y with matching blank shares -- consistent with a field";
  put "clinicians rarely complete rather than a true emergency rate. Patient_Type and";
  put "Admit_Source are likely better urgency proxies. Do not model on Emergent without";
  put "checking the observed rate in SECTION 2 first.";
  put " ";
  put "===========================================================================";
  put "Phase 6 Variable Reconciliation QC complete.";
  put "  Observations examined: &n_total";
  put "  16 deliberate columns + Emergent + rt_envelope_flag: all presence checks PASSED.";
  put "  Emergent type asserted CHARACTER: PASSED.";
  put "  Emergent distribution reconciles to row count: PASSED. See SECTION 2.";
  put "  rt_envelope_flag distribution reconciles to row count: PASSED. See SECTION 3.";
  put "  Populated-column check: &pop_status. See SECTION 3b.";
  put "  PCM-D-10 anchor-offset note: see SECTION 4.";
  put "  No dataset was modified by this program.";
  put "===========================================================================";
run;

%put NOTE: ==== Phase 6 Variable Reconciliation QC complete -- 06_reconcile_summary.txt written ====;
%put NOTE: ==== Populated-check status: &pop_status ====;

/* Restore the log destination so an enclosing driver is not left writing here */
proc printto;
run;
