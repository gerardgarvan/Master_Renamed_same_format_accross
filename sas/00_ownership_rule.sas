/*==========================================================================
  Program : 00_ownership_rule.sas
  Purpose : THE ownership resolution rule, defined once.

            qclib.ownership_map records which sources carry each variable, but
            it does NOT choose an owner: Phase 2 deliberately wrote the literal
            string CONFLICT into the `owner` column for every multi-source
            variable -- 135 of 163. Choosing the owner is this files job.

  Usage   : %include-d INSIDE an already-open DATA step that has done:

                data <out>;
                  set qclib.ownership_map;
                  length owner_resolved $4;
                  %include "&sas_path.\00_ownership_rule.sas";
                  ...
                run;

            This file therefore contains ONLY assignment statements -- no
            `data`, no `set`, no `run`. Adding any of those breaks every caller.

  Requires: sources_present (char, pipe-delimited e.g. "md3|md6|md8")
            varname         (char)
            owner_resolved  (char $4, declared by the caller)

  Callers : sas/04_merge.sas          -- builds the KEEP= lists from the result
            sas/08_dictionary.sas     -- fills the dictionarys source column

            Both MUST use this file. A second copy of the rule lets the data
            dictionary describe an ownership the merge never applied, and that
            divergence would be invisible until someone traced a value back to
            its source.

  Rule    : 1. md3 if md3 carries the variable (it is the spine, 41,150 rows --
               its value is present for every patient in the merged file)
            2. otherwise the contributing source with the highest row count:
               md3 41150 > md8 22473 > md1 = md2 14778 > md6 9462 > md7 9215
                        > md4 = md5 7695
            3. ties break to the lowest source number (md1 before md2,
               md4 before md5)
            4. explicit override for the five frailty components -- see below

  Author  : 2026-08-27 (extracted from 04_merge.sas SECTION 2b)
==========================================================================*/

/* Rules 1-3: first match wins, and the order of these tests IS the row-count
   ordering above. Do not reorder them.                                      */
if      index(sources_present,'md3') then owner_resolved = 'md3';
else if index(sources_present,'md8') then owner_resolved = 'md8';
else if index(sources_present,'md1') then owner_resolved = 'md1';
else if index(sources_present,'md2') then owner_resolved = 'md2';
else if index(sources_present,'md6') then owner_resolved = 'md6';
else if index(sources_present,'md7') then owner_resolved = 'md7';
else if index(sources_present,'md4') then owner_resolved = 'md4';
else if index(sources_present,'md5') then owner_resolved = 'md5';

/* Rule 4 -- OVERRIDE, applied after the row-count rule.
   The five frailty components are $3 in md7 and $1 in md6. Rule 2 would pick
   md6 (9,462 rows vs 9,215), but md6s $1 width cannot hold md7s 3-character
   values -- and that width difference is itself evidence the two sources are
   not storing the same encoding. PCM-D-02 covers this and is resolved as
   "keep separate"; the override makes md7 the owner so no value is truncated. */
if upcase(varname) in ('FEELS_EXAUSTED','LOW_PHYSICAL_ACTIVITY','SLOW_WALKING_SPEED',
                       'UNINTENDED_WEIGHT_LOSS','WEEK_GRIP_STRENGTH')
   then owner_resolved = 'md7';

/* Dropped in Phase 3 (PREP-04) and deleted from the Phase 4 keep lists, so it
   must never reach a caller as an owned variable. The key itself is kept
   explicitly on every source and is not owned by any one of them.            */
if upcase(varname) in ('PRECEDE_STUDY_ID_1','PRECEDE_STUDY_ID') then delete;
