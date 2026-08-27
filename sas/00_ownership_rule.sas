/*==========================================================================
  Include : 00_ownership_rule.sas
  Purpose : Single source of truth for the ownership resolution rule applied
            to qclib.ownership_map.  Three programs apply this same logic:
              04_merge.sas     -- builds work.ownership_resolved for KEEP= lists
              04_merge.sas     -- recovery sweep for MRG-06 gap-fill
              08_dictionary.sas -- builds work.own_resolved for the dictionary
            Extract here so all three cannot drift apart.

  Usage   :
    data work.own_resolved;
      set qclib.ownership_map;
      %include "&sas_path.\00_ownership_rule.sas";
    run;

    The DATA step that %includes this file is responsible for setting the
    input dataset (qclib.ownership_map) and any needed LENGTH statements.
    This file contributes ONLY executable DATA step statements; it does not
    open or close a DATA step.

  Resolution rule (MRG-04, PCM-F-18):
    1. md3 if md3 is in sources_present (spine, 41,150 rows)
    2. else md8 (22,473 rows)
    3. else md1 (14,778 rows)
    4. else md2 (14,778 rows -- lower priority, ties go to lowest number md1)
    5. else md6 (9,462 rows)
    6. else md7 (9,215 rows)
    7. else md4 (7,695 rows)
    8. else md5 (7,695 rows -- lower priority, ties go to lowest number md4)

    Override: five frailty components -> md7 regardless of row count.
    Reason: md7 is $3 and md6 is $1 for these variables; the width signal
    proves the encodings differ, so row-count priority would lose data.

  ASCII only.  No em-dashes, no smart quotes.
  PCM-T-01: no PROC SQL UPDATE.
  PCM-T-02: no data X; set X;
==========================================================================*/

  /* sources_present is the pipe-delimited list built in Phase 2,
     e.g. 'md3|md6|md7'.  INDEX() returns a non-zero position when found.  */
  if      index(sources_present,'md3') then owner_resolved = 'md3';
  else if index(sources_present,'md8') then owner_resolved = 'md8';
  else if index(sources_present,'md1') then owner_resolved = 'md1';
  else if index(sources_present,'md2') then owner_resolved = 'md2';
  else if index(sources_present,'md6') then owner_resolved = 'md6';
  else if index(sources_present,'md7') then owner_resolved = 'md7';
  else if index(sources_present,'md4') then owner_resolved = 'md4';
  else if index(sources_present,'md5') then owner_resolved = 'md5';

  /* PCM-D-02 override: these five frailty components are $3 in md7 and $1 in md6.
     md6 wins on row count (9,462 > 9,215) but cannot hold md7's 3-character values.
     Width mismatch means the encodings differ -- override to md7.                   */
  if upcase(varname) in ('FEELS_EXAUSTED','LOW_PHYSICAL_ACTIVITY','SLOW_WALKING_SPEED',
                         'UNINTENDED_WEIGHT_LOSS','WEEK_GRIP_STRENGTH')
     then owner_resolved = 'md7';
