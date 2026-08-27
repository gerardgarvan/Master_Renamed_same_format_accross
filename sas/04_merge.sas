/* Program: 04_merge.sas | Phase 4 | Requirements: MRG-01, MRG-04
   Purpose: Ownership-map-governed DATA step merge producing g.master_data_merged
            (41,150 rows). md3 is the spine (PCM-F-02, MRG-04). Ownership for every
            variable is resolved at run time from qclib.ownership_map; keep lists are
            generated, never transcribed by hand.
   Author : Executor (Phase 4 Plan 01)
   Created: 2026-08-26
   PCM violations avoided:
     PCM-T-01: no PROC SQL UPDATE
     PCM-T-02: no data X; set X;
     PCM-R-05: every %abort cancel is inside a named %macro
     PCM-R-02: LENGTH before MERGE in the DATA step
     All counts use SELECT COUNT(*) INTO :macvar TRIMMED (not the automatic counter)
*/

/* =========================================================================
   SECTION 0: Options, paths, libname assignments
   =========================================================================
   Path notes:
     g_path    = C: drive location for g.prep_mdN and g.master_data_merged.
                 SAS7BDAT files are gitignored; no PHI reaches the repo.
     logs_path = C: drive logs directory (sibling of merge/ on the network share).
                 The merge log and provenance text file are committed artifacts
                 from the C: side; they contain only row counts, not PHI.
     qc_path   = C: drive qc directory (sibling of merge/ on the network share); qclib libname points here to read
                 qclib.ownership_map (Phase 2 artifact).
   The g libname is left open at end of this program (no LIBNAME CLEAR) so
   that 99_run_all.sas can chain phases without re-assigning the library.
   ========================================================================= */
options nodate nonumber ps=max ls=200 mprint nofmterr;
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
libname g "&g_path";

%put NOTE: ==== Phase 4 merge starting ====;

/* =========================================================================
   SECTION 1: Preconditions
   All %abort cancel calls are inside named %macro definitions (PCM-R-05).
   ========================================================================= */

/* 1a: g library resolves */
%macro check_libname_g;
  %if %sysfunc(libref(g)) ne 0 %then %do;
    %put ERROR: LIBNAME g could not be assigned. Check &g_path;
    %abort cancel;
  %end;
  %else %put NOTE: LIBNAME g resolved: &g_path;
%mend check_libname_g;
%check_libname_g;

/* 1b: logs/ and qc/ directories exist */
%macro check_dir(path=, label=);
  %if %sysfunc(fileexist(&path)) = 0 %then %do;
    %put ERROR: &label directory missing: &path;
    %abort cancel;
  %end;
  %else %put NOTE: &label directory found: &path;
%mend check_dir;
%check_dir(path=&logs_path, label=logs);
%check_dir(path=&qc_path,   label=qc);

/* 1c: All eight g.prep_mdN datasets exist */
proc sql noprint;
  select count(*) into :n_tables trimmed
  from dictionary.tables
  where libname='G'
    and upcase(memname) in ('PREP_MD1','PREP_MD2','PREP_MD3','PREP_MD4',
                            'PREP_MD5','PREP_MD6','PREP_MD7','PREP_MD8');
quit;
%macro check_eight_inputs;
  %if &n_tables ne 8 %then %do;
    %put ERROR: MRG PRECONDITION -- Expected 8 g.prep_mdN datasets, found &n_tables. Re-run Phase 3.;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- all 8 g.prep_mdN datasets present.;
%mend check_eight_inputs;
%check_eight_inputs;

/* 1d: PRECEDE_Study_ID_1 must NOT be present in g.prep_md6 (PREP-04 drop asserted) */
proc sql noprint;
  select count(*) into :n_dup trimmed
  from dictionary.columns
  where libname='G' and upcase(memname)='PREP_MD6'
    and upcase(name)='PRECEDE_STUDY_ID_1';
quit;
%macro check_no_dup_key;
  %if &n_dup ne 0 %then %do;
    %put ERROR: PRECEDE_Study_ID_1 found in g.prep_md6 -- re-run Phase 3 prep for md6 (PREP-04 not applied).;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- PRECEDE_Study_ID_1 is absent from g.prep_md6 (PREP-04 confirmed).;
%mend check_no_dup_key;
%check_no_dup_key;

/* =========================================================================
   SECTION 2: Pre-sort all eight inputs to WORK with NODUPKEY duplicate-key check
   =========================================================================
   Pattern: PROC SORT with NODUPKEY writes to work.sort_prep_mdN (not in-place).
   PCM-T-02: never sort in place over the source dataset.
   %sort_and_check calls %assert_sorted, which is defined once at the outer level
   and takes parameters, so every %abort cancel is inside a named macro (PCM-R-05)
   without building a macro name from a macro variable (which does not compile).
   Expected NODUPKEY counts are the Phase 1 SRC-01 verified row totals
   (qc/src_counts.txt): md3=41150, md8=22473, md1=md2=14778, md6=9462,
   md7=9215, md4=md5=7695.
   ========================================================================= */
/* The assertion macro is defined ONCE, at the outer level, and takes parameters.
   An earlier version defined `%macro _sort_assert_&dsn;` INSIDE sort_and_check.
   A macro NAME cannot be constructed from a macro variable in the %MACRO statement:
   SAS reported "Expected semicolon not found. The macro will not be compiled." and
   compiled a dummy, so all eight NODUPKEY assertions silently never ran.
   %abort cancel stays inside a named macro definition (PCM-R-05).                  */
%macro assert_sorted(actual=, expected=, dsn=);
  %if &actual ne &expected %then %do;
    %put ERROR: MRG PRECONDITION -- &dsn has duplicate PRECEDE_STUDY_ID keys.;
    %put ERROR- Expected &expected unique rows -- NODUPKEY kept &actual;
    %abort cancel;
  %end;
  %else %put NOTE: PRECONDITION OK -- &dsn has &actual unique keys.;
%mend assert_sorted;

%macro sort_and_check(dsn=, expected_nobs=);
  proc sort data=g.&dsn out=work.sort_&dsn nodupkey; by PRECEDE_STUDY_ID; run;
  proc sql noprint;
    select count(*) into :n_sorted trimmed from work.sort_&dsn;
  quit;
  %assert_sorted(actual=&n_sorted, expected=&expected_nobs, dsn=&dsn);
%mend sort_and_check;

%sort_and_check(dsn=prep_md1, expected_nobs=14778)
%sort_and_check(dsn=prep_md2, expected_nobs=14778)
%sort_and_check(dsn=prep_md3, expected_nobs=41150)
%sort_and_check(dsn=prep_md4, expected_nobs=7695)
%sort_and_check(dsn=prep_md5, expected_nobs=7695)
%sort_and_check(dsn=prep_md6, expected_nobs=9462)
%sort_and_check(dsn=prep_md7, expected_nobs=9215)
%sort_and_check(dsn=prep_md8, expected_nobs=22473)

/* =========================================================================
   SECTION 2b: Resolve ownership and generate per-source KEEP= lists
   =========================================================================
   This section is the core of MRG-04. It NEVER hand-transcribes ownership:
   all 163 variable assignments (28 single-source + 135 CONFLICT) flow from
   qclib.ownership_map at run time. The work.ownership_resolved dataset is
   also the reference for SECTION 5s reconciliation assertions.

   Variable deletion before keep-list build:
     PRECEDE_STUDY_ID   -- the merge key; supplied explicitly on all 8 inputs
     PRECEDE_STUDY_ID_1 -- dropped in Phase 3 PREP-04; must not reach any list

   MD3-OWNS MISSINGNESS TRADE-OFF (PCM-D-09):
     Any variable owned by md3 inherits md3s missingness pattern -- that is,
     the merged file will show missing values wherever md3 was missing, even if
     another source had a non-missing value. For Admit_BMI this is provably free:
     PCM-F-07 showed that coalescing every other source recovers nothing (all
     28,424 missings are missing at source). For other md3-owned variables this
     trade-off has NOT been verified. It is a deliberate design choice:
     md3 is the spine (41,150 rows, complete superset); accepting its missingness
     avoids arbitrary tie-breaking. Recorded in docs/DECISIONS.md as PCM-D-09.

   Source of truth: qclib.ownership_map (Phase 2 machine-readable artifact).
   Resolution rule (from interfaces):
     1. If md3 carries the variable -> md3 owns it (spine, 41,150 rows)
     2. Otherwise highest row count: md3>md8>md1=md2>md6>md7>md4=md5
     3. Ties broken by lowest source number
   Exception: five frailty components override to md7 (width mismatch signal,
     PCM-D-02 -- $3 in md7 vs $1 in md6 means they are NOT the same encoding).
   PRECEDE_STUDY_ID and PRECEDE_STUDY_ID_1 are excluded from keep lists:
     the merge key is kept explicitly on all eight; PRECEDE_STUDY_ID_1 was
     dropped in Phase 3 (PREP-04) and must not appear in any keep list.
   ========================================================================= */
libname qclib "&qc_path";

data work.ownership_resolved;
  set qclib.ownership_map;
  length owner_resolved $4;
  /* THE ownership rule lives in 00_ownership_rule.sas and is included here,
     not duplicated. 08_dictionary.sas includes the same file, so the dictionary
     can never describe an ownership the merge did not apply.                 */
  %include "&sas_path.\00_ownership_rule.sas";
run;

/* Guard: every remaining variable must have exactly one resolved owner */
proc sql noprint;
  select count(*) into :n_unresolved trimmed
  from work.ownership_resolved where missing(owner_resolved);
quit;
%macro assert_resolved;
  %if &n_unresolved > 0 %then %do;
    %put ERROR: MRG-04 -- &n_unresolved variables have no resolved owner. Check sources_present in ownership_map.;
    %abort cancel;
  %end;
  %else %put NOTE: MRG-04 OK -- every mapped variable has exactly one owner.;
%mend assert_resolved;
%assert_resolved;

/* Build one macro variable per source: &keep1 through &keep8 */
%macro build_keeplists;
  %local i;
  %do i = 1 %to 8;
    %global keep&i;
    proc sql noprint;
      select varname into :keep&i separated by ' '
      from work.ownership_resolved where owner_resolved = "md&i";
    quit;
    /* countw() errors on an empty string; md2 and md5 legitimately own ZERO
       variables -- every column they carry is owned by md3 or md1.          */
    %if %superq(keep&i) = %then
      %put NOTE: md&i owns 0 variables (every column it carries is owned elsewhere).;
    %else
      %put NOTE: md&i owns %sysfunc(countw(&&keep&i)) variables.;
  %end;
%mend build_keeplists;
%build_keeplists;

/* =========================================================================
   SECTION 3: Spine-first DATA step merge with generated KEEP= lists
   LENGTH block declares each character variable at its OWNERs width.
   PCM-R-02: LENGTH before MERGE.
   PCM-F-02, MRG-04: work.sort_prep_md3 is the FIRST dataset in MERGE.
   No RENAME= blocks (the prefix-suppress scheme overflows the 32-char name limit -- PCM violation).
   Provenance flags in_md1..in_md8 and n_sources assigned immediately after BY.
   ========================================================================= */
/* ---- MRG-06 / PCM-D-11 (REOPENED 2026-08-27): build the md8 donor set ------
   These five are the variables where md3 OWNS the column but md8 holds values for
   patients md3 has blanks for. Measured across all seven donors (578 owner/donor/
   variable combinations tested); md8 is the only source that contributes anything:

       Cognitive_Score                  8,412 recoverable, 0 disagreements
       Cognitive_Category               8,445 recoverable, 0 disagreements
       Frailty_Score                    9,268 recoverable, 0 disagreements
       Frailty_Category                 1,789 recoverable, 0 disagreements
       ORAL_MORPHINE_EQUIV_mg_POD_DAY6  7,695 recoverable, 0 disagreements

   Zero disagreements everywhere both sources hold a value, so the coalesce in the
   merge below is a pure gap-fill and not a choice between conflicting data.

   Renamed to _d8_* so they cannot collide with md3s owned copies. The KEEP=
   ownership rule still governs the canonical names; these are working storage and
   are dropped before the merged dataset is written, so MRG-04s unmapped-column
   reconciliation is unaffected.                                                 */
data work.md8_donors;
  set work.sort_prep_md8 (keep=PRECEDE_STUDY_ID
                               Cognitive_Score Cognitive_Category
                               Frailty_Score Frailty_Category
                               ORAL_MORPHINE_EQUIV_mg_POD_DAY6
                          rename=(Cognitive_Score    = _d8_cog_score
                                  Cognitive_Category = _d8_cog_cat
                                  Frailty_Score      = _d8_frl_score
                                  Frailty_Category   = _d8_frl_cat
                                  ORAL_MORPHINE_EQUIV_mg_POD_DAY6 = _d8_ome_d6));
run;

data g.master_data_merged;
  length
    /* Key */
    PRECEDE_STUDY_ID                $12

    /* ---------------------------------------------------------------
       Character variables at OWNERS width (from qc/03_charvars_all.txt).
       Under KEEP= only the owners copy enters the PDV -- max-width would
       be wasteful and misleading.
       --------------------------------------------------------------- */

    /* md3 owns: spine variables (Race $16, Emergent $1, etc.) */
    ENCRYPTED_MRN                   $40   /* md3 owns; md1/md2 also $40 */
    ENCRYPTED_ENCOUNTER             $49   /* md3 owns */
    Day_of_Week__CHAR_              $3    /* md3 owns */
    Holidays                        $1    /* md3 owns */
    Weekend_Indicator               $1    /* md3 owns */
    EmployeeStatus                  $23   /* md3 owns */
    Education                       $19   /* md3 owns */
    Race                            $16   /* md3 owns */
    Ethnicity                       $15   /* md3 owns */
    Sex                             $6    /* md3 owns */
    Marital_Status                  $22   /* md3 owns */
    Service                         $32   /* md3 owns */
    Room_Type                       $22   /* md3 owns */
    Emergent                        $1    /* md3 owns; md8s $4 is char-forced (not kept) */
    Base_Procedure_1                $199  /* md3 owns */
    Base_Procedure_Code_1           $10   /* md3 owns */
    CPT_1                           $8    /* md3 owns */
    CPT_1_Description               $75   /* md3 owns */
    CPT1_Label                      $96   /* md3 owns */
    Patient_Type                    $18   /* md3 owns */
    Payer                           $12   /* md3 owns */
    ICD10_Principal_Diagnosis_Desc  $60   /* md3 owns (md1/md2/md4/md5 also have it) */
    ICD10_Principal_Diagnosis       $7    /* md3 owns */
    Intraop_Ketamine                $1    /* md3 owns; md8s $4 is char-forced (not kept) */
    Preop_block                     $1    /* md3 owns; md8s $4 is char-forced (not kept) */
    Admit_Source                    $40   /* md3 owns */
    Dischg_Disposition              $43   /* md3 owns */

    /* PCM-D-01 PENDING: Death_Date_Y_N provisional owner md3; IsDead_Y_N (md6) and Death (md7)
       land as separate columns. Re-examine in Phase 6 per Erin sign-off. */
    Death_Date_Y_N                  $1    /* md3 owns provisionally (PCM-D-01) */
    SSDI_Death_Date_Y_N             $1    /* md3 owns */
    Anesthesia_Type                 $33   /* md3 owns */
    Sleep_Apnea_YN                  $1    /* md3 owns */
    Diabetes_YN                     $1    /* md3 owns */
    Hyperlipidemia_YN               $1    /* md3 owns */
    Hypertension_YN                 $1    /* md3 owns */
    MovementDisorder_YN             $1    /* md3 owns */
    CognitiveDisorder_YN            $1    /* md3 owns */
    Cognitive_Category              $22   /* md3 owns */

    /* PCM-D-02 PENDING: Frailty_Score/Cognitive_Score owner md3; the five frailty components
       are owned by md7 on a width override. Re-examine in Phase 6. */
    Frailty_Category                $24   /* md3 owns */

    /* ISO_SEV_Exp_IntraOp_MAC_Average: numeric in md2/md3 (type 1, length 8), char in md1.
       md3 owns it (spine rule) so it is NUMERIC -- not declared in character LENGTH block.
       md1s char copy is excluded by KEEP=. See PCM-D-03 block below. */

    /* md6 owns */
    IsDead_Y_N                      $1    /* md6 owns; single-source; see PCM-D-01 block above */
    ICD10_Principal_Diagnosis_POA   $6    /* md6 owns (md6|md7 both $6) */
    SSDI_Death_Y_N                  $1    /* md6 owns (md4|md5|md6; md6 highest rows) */

    /* PCM-D-03 PENDING: three ISO_SEV columns retained separately; md8s is a TOTAL, not an
       average -- do not fold it in even when D-03 is decided. */

    /* md7 owns (single-source) */
    Death                           $1    /* md7 owns; single-source; see PCM-D-01 block above */
    SSDI_Death                      $1    /* md7 owns; single-source */

    /* md7 owns (PCM-D-02 override: $3 in md7 vs $1 in md6 -- width mismatch) */
    Feels_Exausted                  $3
    Low_Physical_Activity           $3
    Slow_Walking_Speed              $3
    Unintended_Weight_Loss          $3
    Week_Grip_Strength              $3

    /* md4 owns */
    /* (md4 character variables: CPT1_Label $96 -- but md3 owns CPT1_Label; SORT_ID is numeric;
       md4 owns: Sleep_Apnea $1, Diabetes $1, Hyperlipidemia $1, Hypertension $1,
       MovementDisorder $1, Cognitive_Disorder $1 -- separate from the md3 _YN variants) */
    Sleep_Apnea                     $1    /* md4 owns (md4|md5; md4 is lower number) */
    Diabetes                        $1    /* md4 owns */
    Hyperlipidemia                  $1    /* md4 owns */
    Hypertension                    $1    /* md4 owns */
    MovementDisorder                $1    /* md4 owns */
    Cognitive_Disorder              $1    /* md4 owns */

    /* md1 owns */
    _30_DAY_MORTALITY               $1    /* md1 owns (md1|md2; md1 lower number) */

    /* Provenance flags -- numeric length 3 */
    in_md1 3 in_md2 3 in_md3 3 in_md4 3
    in_md5 3 in_md6 3 in_md7 3 in_md8 3 n_sources 3
    rt_envelope_flag 3                     /* MRG-05 -- derived below, see PCM-D-08 */
    ;

  merge
    work.sort_prep_md3 (in=in3 keep=PRECEDE_STUDY_ID &keep3)   /* SPINE -- MUST be first (MRG-04, PCM-F-02) */
    work.sort_prep_md1 (in=in1 keep=PRECEDE_STUDY_ID &keep1)
    work.sort_prep_md2 (in=in2 keep=PRECEDE_STUDY_ID &keep2)
    work.sort_prep_md4 (in=in4 keep=PRECEDE_STUDY_ID &keep4)
    work.sort_prep_md5 (in=in5 keep=PRECEDE_STUDY_ID &keep5)
    work.sort_prep_md6 (in=in6 keep=PRECEDE_STUDY_ID &keep6)
    work.sort_prep_md7 (in=in7 keep=PRECEDE_STUDY_ID &keep7)
    work.sort_prep_md8 (in=in8 keep=PRECEDE_STUDY_ID &keep8)

    /* MRG-06 / PCM-D-11: md8 gap-fill donors, prebuilt as work.md8_donors above.
       Built as its own dataset rather than reading work.sort_prep_md8 twice in
       one MERGE -- a double read of the same dataset is legal, but there is no
       reason to depend on how SAS sequences the second instance under BY-group
       processing when a separate dataset is equivalent and obviously correct.  */
    work.md8_donors
    ;
  by PRECEDE_STUDY_ID;

  /* Provenance flags -- assigned immediately after BY (MRG-03 audit trail) */
  in_md1 = in1; in_md2 = in2; in_md3 = in3; in_md4 = in4;
  in_md5 = in5; in_md6 = in6; in_md7 = in7; in_md8 = in8;
  n_sources = in_md1+in_md2+in_md3+in_md4+in_md5+in_md6+in_md7+in_md8;

  /* ---- MRG-05 / PCM-D-08 (resolved 2026-08-27): operative envelope flag ----
     9 rows have an operative sub-interval LONGER than the room-occupancy interval
     that contains it (5 on rt_INCISE_to_DRESS_mins, 4 on rt_RM_START_to_INCISION_mins).
     A patient cannot be under the knife longer than they were in the room.

     FLAG, DO NOT NULL. Each of the three timestamps is individually plausible; only
     the combination is impossible, and nothing identifies which one is wrong. Nulling
     would destroy two good values to punish an unidentifiable third. The flag preserves
     all three and moves the judgment to the analyst.

     These are NOT the same rows PREP-08 nulled. PREP-08 handled 67 NEGATIVE values;
     these 9 are POSITIVE and were inside the old QC-05 bounds -- a per-variable range
     check structurally cannot see a relationship between two variables.

     Derived HERE and not in Phase 3 prep: the ownership map is built in Phase 2 from
     the SOURCE files, so a variable invented during prep is not in it, and the MRG-04
     reconciliation below asserts zero unmapped columns. A prep-created flag would fail
     that assertion. Derived at merge time, it joins the exclusion list instead.

     Both sides guarded (PCM-T-11): `a > b` is TRUE when b is missing, because missing
     sorts below every number. Without the envelope guard this would flag every row
     with no room interval recorded.                                                  */
  /* SYNTAX NOTE: DATA step, so guards are `not missing(x)`. The `x IS NOT MISSING`
     operator is PROC SQL / WHERE-clause syntax and is a syntax error here.        */
  rt_envelope_flag =
     ( not missing(rt_RM_START_to_RM_END_mins)
       and ( (not missing(rt_INCISE_to_DRESS_mins)
              and rt_INCISE_to_DRESS_mins > rt_RM_START_to_RM_END_mins)
          or (not missing(rt_RM_START_to_INCISION_mins)
              and rt_RM_START_to_INCISION_mins > rt_RM_START_to_RM_END_mins) ) );
  label rt_envelope_flag = 'Operative sub-interval exceeds room interval (1=yes)';

  /* ---- MRG-06 / PCM-D-11: fill md3s blanks from md8 ----------------------
     Direction is one-way and explicit: md3s value is NEVER overwritten. Only a
     MISSING md3 value is filled, and only from md8, and only for these five.

     Why this is needed: the KEEP= ownership rule gives md3 first claim, so md8s
     copy is normally never kept -- correct for preventing last-wins overwrites,
     but it also discards values for patients md3 simply has no data on. PCM-D-11
     was originally closed as "costs nothing" on a check that tested md5 and md6
     and OMITTED md8. That was wrong: md5 and md6 hold only duplicates, md8 holds
     8-9k real values per score variable.

     Arithmetic check on the result:
       Cognitive_Score  12,128 + 8,412 = 20,540  (Phase 7 expected N)
       Frailty_Score    14,043 + 9,268 = 23,311  (Phase 7 expected N)

     DATA step, so the guard is `missing(x)` -- `x IS MISSING` is PROC SQL syntax. */
  if missing(Cognitive_Score)    then Cognitive_Score    = _d8_cog_score;
  if missing(Cognitive_Category) then Cognitive_Category = _d8_cog_cat;
  if missing(Frailty_Score)      then Frailty_Score      = _d8_frl_score;
  if missing(Frailty_Category)   then Frailty_Category   = _d8_frl_cat;
  if missing(ORAL_MORPHINE_EQUIV_mg_POD_DAY6)
                                 then ORAL_MORPHINE_EQUIV_mg_POD_DAY6 = _d8_ome_d6;

  /* Donor columns are working storage only -- dropped so the merged column list
     still reconciles against the ownership map (MRG-04).                       */
  drop _d8_:;
run;

%put NOTE: DATA step merge complete. Proceeding to SECTION 4 log.;

/* MRG-05: report the flag count. Informational -- NOT asserted here. QC-06 in
   05_qc_merge.sas asserts that no violation ESCAPED the flag, which is the check
   that stays meaningful if a future re-extract introduces a new one.            */
proc sql noprint;
  select sum(rt_envelope_flag) into :n_env_flag trimmed from g.master_data_merged;
quit;
%put NOTE: MRG-05 -- &n_env_flag rows carry rt_envelope_flag=1 (expected 9, PCM-D-08).;

/* MRG-06: report post-coalesce coverage. Reported, not asserted here -- Phase 7
   asserts the two score Ns, which is where the expectation is established.     */
proc sql noprint;
  select sum(Cognitive_Score is not missing),
         sum(Frailty_Score   is not missing),
         sum(Cognitive_Category is not missing),
         sum(Frailty_Category   is not missing),
         sum(ORAL_MORPHINE_EQUIV_mg_POD_DAY6 is not missing)
    into :n_cog trimmed, :n_frl trimmed, :n_cogc trimmed,
         :n_frlc trimmed, :n_ome trimmed
  from g.master_data_merged;
quit;
%put NOTE: MRG-06 -- post-coalesce coverage (md3 owned, md8 gap-filled):;
%put NOTE-   Cognitive_Score    = &n_cog  (expect 20540);
%put NOTE-   Frailty_Score      = &n_frl  (expect 23311);
%put NOTE-   Cognitive_Category = &n_cogc;
%put NOTE-   Frailty_Category   = &n_frlc;
%put NOTE-   ORAL_MORPHINE_EQUIV_mg_POD_DAY6 = &n_ome;

/* =========================================================================
   SECTION 4: Merge summary log written to logs/04_merge_log.txt
   =========================================================================
   Two artifacts:
     logs/04_merge_log.txt          -- session log, not committed (runtime info)
     qc/04_merge_provenance.txt     -- committed QC artifact (same format as
                                       qc/src_counts.txt from Phase 1); contains
                                       only provenance totals and row counts, no PHI.
   The n_sources distribution is written in a DATA _NULL_ step using FILE/PUT
   (not PROC EXPORT, not PROC PRINT) so the format is deterministic.
   All counts re-queried here using SELECT COUNT(*) INTO :macvar TRIMMED to avoid
   dependence on macro variables set earlier in the session.
   and committed QC artifact qc/04_merge_provenance.txt.
   All counts use PROC SQL SELECT COUNT(*) INTO :macvar TRIMMED (not the automatic counter).
   ========================================================================= */

/* Count provenance totals */
proc sql noprint;
  select count(*)                    into :n_rows     trimmed from g.master_data_merged;
  select count(distinct PRECEDE_STUDY_ID) into :n_dist trimmed from g.master_data_merged;
  select sum(in_md1)  into :n_in_md1 trimmed from g.master_data_merged;
  select sum(in_md2)  into :n_in_md2 trimmed from g.master_data_merged;
  select sum(in_md3)  into :n_in_md3 trimmed from g.master_data_merged;
  select sum(in_md4)  into :n_in_md4 trimmed from g.master_data_merged;
  select sum(in_md5)  into :n_in_md5 trimmed from g.master_data_merged;
  select sum(in_md6)  into :n_in_md6 trimmed from g.master_data_merged;
  select sum(in_md7)  into :n_in_md7 trimmed from g.master_data_merged;
  select sum(in_md8)  into :n_in_md8 trimmed from g.master_data_merged;
quit;

/* Write merge summary log to logs/ */
data _null_;
  file "&logs_path.\04_merge_log.txt";
  put "=== Phase 4 Merge Log ===";
  put "Timestamp: %sysfunc(datetime(), datetime20.)";
  put "Total rows in g.master_data_merged : &n_rows";
  put "Distinct PRECEDE_STUDY_ID           : &n_dist";
  put "--- Provenance flag totals ---";
  put "in_md1  : &n_in_md1  (expected 14778)";
  put "in_md2  : &n_in_md2  (expected 14778)";
  put "in_md3  : &n_in_md3  (expected 41150)";
  put "in_md4  : &n_in_md4  (expected 7695)";
  put "in_md5  : &n_in_md5  (expected 7695)";
  put "in_md6  : &n_in_md6  (expected 9462)";
  put "in_md7  : &n_in_md7  (expected 9215)";
  put "in_md8  : &n_in_md8  (expected 22473)";
run;

/* n_sources distribution */
data _null_;
  set g.master_data_merged end=eof;
  retain _cnt1-_cnt8 0;
  select(n_sources);
    when(1) _cnt1+1; when(2) _cnt2+1; when(3) _cnt3+1; when(4) _cnt4+1;
    when(5) _cnt5+1; when(6) _cnt6+1; when(7) _cnt7+1; when(8) _cnt8+1;
    otherwise _cnt1+0; /* defensive: n_sources=0 would indicate merge error */
  end;
  if eof then do;
    file "&logs_path.\04_merge_log.txt" mod;
    put "--- n_sources distribution ---";
    put "n_sources=1: " _cnt1;
    put "n_sources=2: " _cnt2;
    put "n_sources=3: " _cnt3;
    put "n_sources=4: " _cnt4;
    put "n_sources=5: " _cnt5;
    put "n_sources=6: " _cnt6;
    put "n_sources=7: " _cnt7;
    put "n_sources=8: " _cnt8;
    put "=== END ===";
  end;
run;

/* Write committed QC artifact: qc/04_merge_provenance.txt (same format as src_counts.txt) */
data _null_;
  file "&qc_path.\04_merge_provenance.txt";
  put "04_merge_provenance -- Run: %sysfunc(datetime(), datetime20.)";
  put "Provenance flags for g.master_data_merged";
  put "in_md1  Expected=14778  Actual=&n_in_md1";
  put "in_md2  Expected=14778  Actual=&n_in_md2";
  put "in_md3  Expected=41150  Actual=&n_in_md3";
  put "in_md4  Expected=7695   Actual=&n_in_md4";
  put "in_md5  Expected=7695   Actual=&n_in_md5";
  put "in_md6  Expected=9462   Actual=&n_in_md6";
  put "in_md7  Expected=9215   Actual=&n_in_md7";
  put "in_md8  Expected=22473  Actual=&n_in_md8";
  put "Total merged rows: &n_rows  Distinct IDs: &n_dist";
run;

/* =========================================================================
   SECTION 5: Five-part assertion block (MRG-01, MRG-02, MRG-03, MRG-04)
   =========================================================================
   Assertions:
     MRG-01: n_merged = 41,150 (spine drives the total)
     MRG-01: n_dist  = 41,150 (one row per patient -- no accidental stacking)
     MRG-02: n_blank_key = 0  (no PRECEDE_STUDY_ID missing from any merged row)
     MRG-03: in_mdN totals match expected source row counts from qc/src_counts.txt
             for all eight sources
     NULL sentinel: md8-owned character columns have zero surviving NULL strings
     MRG-04: ownership reconciliation -- no orphaned columns, no absent mapped vars

   The %assert_eq macro is defined here (not in SECTION 1) because it is
   logic-layer rather than precondition-layer. All %abort cancel calls are
   inside this macro (PCM-R-05).
   All %abort cancel inside %macro definitions (PCM-R-05).
   All counts use PROC SQL SELECT COUNT(*) INTO :macvar TRIMMED (not the automatic counter).
   ========================================================================= */

%macro assert_eq(actual=, expected=, label=);
  %if &actual ne &expected %then %do;
    %put ERROR: MRG ASSERTION FAILED -- &label: expected &expected got &actual;
    %abort cancel;
  %end;
  %else %put NOTE: MRG ASSERTION OK -- &label = &actual;
%mend assert_eq;

/* Five-part assertion counts (MRG-01, MRG-02, MRG-03) */
proc sql noprint;
  select count(*)                         into :n_merged    trimmed from g.master_data_merged;
  select count(distinct PRECEDE_STUDY_ID) into :n_dist      trimmed from g.master_data_merged;
  select count(*)                         into :n_blank_key trimmed from g.master_data_merged
    where missing(PRECEDE_STUDY_ID);
  select sum(in_md1) into :n_in_md1 trimmed from g.master_data_merged;
  select sum(in_md2) into :n_in_md2 trimmed from g.master_data_merged;
  select sum(in_md3) into :n_in_md3 trimmed from g.master_data_merged;
  select sum(in_md4) into :n_in_md4 trimmed from g.master_data_merged;
  select sum(in_md5) into :n_in_md5 trimmed from g.master_data_merged;
  select sum(in_md6) into :n_in_md6 trimmed from g.master_data_merged;
  select sum(in_md7) into :n_in_md7 trimmed from g.master_data_merged;
  select sum(in_md8) into :n_in_md8 trimmed from g.master_data_merged;
quit;

/* MRG-01: row count and distinct IDs */
%assert_eq(actual=&n_merged,    expected=41150, label=merged row count);
%assert_eq(actual=&n_dist,      expected=41150, label=distinct PRECEDE_STUDY_ID);
/* MRG-02: no blank key */
%assert_eq(actual=&n_blank_key, expected=0,     label=blank PRECEDE_STUDY_ID count);
/* MRG-03: provenance flag totals */
%assert_eq(actual=&n_in_md1,    expected=14778, label=in_md1 total);
%assert_eq(actual=&n_in_md2,    expected=14778, label=in_md2 total);
%assert_eq(actual=&n_in_md3,    expected=41150, label=in_md3 total);
%assert_eq(actual=&n_in_md4,    expected=7695,  label=in_md4 total);
%assert_eq(actual=&n_in_md5,    expected=7695,  label=in_md5 total);
%assert_eq(actual=&n_in_md6,    expected=9462,  label=in_md6 total);
%assert_eq(actual=&n_in_md7,    expected=9215,  label=in_md7 total);
%assert_eq(actual=&n_in_md8,    expected=22473, label=in_md8 total);

/* NULL sentinel scan -- scoped to md8-owned character columns only.
   md8 owns only the hemodynamic block (all numeric) and ENCRYPTED_MRN/ENCRYPTED_ENCOUNTER
   (where it is NOT the owner -- md3 owns those). Derive the actual risk surface:         */
proc sql noprint;
  select count(*) into :n_md8_char trimmed
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED' and type='char'
    and upcase(name) in (select upcase(varname) from work.ownership_resolved
                         where owner_resolved='md8');

  select name into :md8_charvars separated by ' '
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED' and type='char'
    and upcase(name) in (select upcase(varname) from work.ownership_resolved
                         where owner_resolved='md8');
quit;

%macro null_scan;
  /* %GLOBAL is required. The two branches below set this variable by different
     mechanisms: the zero branch uses %let (LOCAL by default, so it would vanish
     at %mend and leave the %assert_eq below reading an undefined variable), and
     the scan branch uses call symputx(...,G) (global). Declaring it here makes
     both paths global and the behaviour consistent.                            */
  %global n_null_merged;
  %if &n_md8_char = 0 %then %do;
    %put NOTE: MRG -- md8 owns no character variables in the merged file.;
    %put NOTE- The NULL sentinel is unreachable by construction. md8s owned columns;
    %put NOTE- are entirely numeric (hemodynamic block converted in PREP-03).;
    %put NOTE- This is a stronger result than a scan -- no md8-char values to corrupt.;
    %let n_null_merged = 0;
  %end;
  %else %do;
    %put NOTE: MRG -- md8 owns &n_md8_char character variables: &md8_charvars;
    data _null_;
      set g.master_data_merged end=eof;
      retain _n_null 0;
      /* Explicit $ -- these are character variables. SAS would usually infer the
         type from the SET, but this array only exists on the branch where md8
         owns character columns, so being explicit costs nothing.               */
      array _m8 {*} $ &md8_charvars;
      do _i = 1 to dim(_m8);
        if strip(upcase(_m8{_i})) = 'NULL' then _n_null + 1;
      end;
      drop _i;
      if eof then call symputx('n_null_merged', _n_null, 'G');
    run;
  %end;
%mend null_scan;
%null_scan;
%assert_eq(actual=&n_null_merged, expected=0, label=surviving NULL sentinel strings in md8-owned char vars);

/* MRG-04 ownership reconciliation: every column in the merged file must appear
   in the ownership map; every mapped variable must appear in the merged file.   */
proc sql noprint;
  select count(*) into :n_unmapped trimmed
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_MERGED'
    and upcase(name) not in (select upcase(varname) from work.ownership_resolved)
    and upcase(name) not in ('PRECEDE_STUDY_ID','IN_MD1','IN_MD2','IN_MD3','IN_MD4',
                             'IN_MD5','IN_MD6','IN_MD7','IN_MD8','N_SOURCES',
                             'RT_ENVELOPE_FLAG');
    /* RT_ENVELOPE_FLAG is derived in SECTION 3 (MRG-05), not read from a source, so it
       is legitimately absent from the ownership map. Omitting it here would make MRG-04
       fail on the merges own derived column.                                         */

  select count(*) into :n_absent trimmed
  from work.ownership_resolved
  where upcase(varname) not in (select upcase(name) from dictionary.columns
                                where libname='G' and memname='MASTER_DATA_MERGED');
quit;
%assert_eq(actual=&n_unmapped, expected=0, label=unmapped columns in merged file);
%assert_eq(actual=&n_absent,   expected=0, label=mapped variables absent from merged file);

/* =========================================================================
   SECTION 6: Close-out
   ========================================================================= */
%put NOTE: ==== Phase 4 merge complete ====;
/* Leave g and qclib libnames open; 99_run_all.sas will manage libname lifecycle */
