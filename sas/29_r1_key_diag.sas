/* 29_r1_key_diag.sas -- one-time diagnostic for r1 key width (Phase 29).
   Read-only. Not part of run_pipeline.cmd.                                 */
%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas";
%include "&sas_path.\macros_raw_import.sas";
libname g "&g_path" access=readonly;

%import_csv(r1, 2018_2019_2020_Induction_Emergent20231121.csv)

/* 1. Profile every key */
data work._r1_key;
  set work.r1(keep=PRECEDE_Study_ID);
  length id_strip $18 digits $18 id_hex $40;
  id_strip  = strip(PRECEDE_Study_ID);
  strip_len = lengthn(id_strip);
  nonprint  = (notprint(id_strip) > 0);
  has_pref  = (index(upcase(id_strip), 'PRECEDE') = 1);
  digits    = compress(id_strip, , 'kd');
  n_digits  = lengthn(digits);
  if strip_len > 12 then id_hex = put(substr(id_strip, 1, 20), $hex40.);
run;

title "r1 key: length / prefix / non-printable distribution";
proc freq data=work._r1_key;
  tables strip_len has_pref nonprint n_digits strip_len*has_pref / missing list;
run;

title "r1 keys longer than 12 characters (first 50)";
proc print data=work._r1_key(where=(strip_len > 12) obs=50);
  var PRECEDE_Study_ID strip_len has_pref nonprint digits id_hex;
run;

/* 2. Do long keys collapse onto an existing short key? (suffix / re-entry test) */
proc sql;
  title "Long keys whose digits match a <=12-char key in r1";
  select count(*) as n_long,
         sum(case when s.id_strip is not null then 1 else 0 end) as n_match_short
  from (select distinct id_strip, digits from work._r1_key where strip_len > 12) as l
  left join (select distinct id_strip, compress(id_strip, , 'kd') as digits
             from work._r1_key where strip_len <= 12) as s
    on l.digits = s.digits;
quit;

/* 3. Are r1's data columns already in the base? (new-columns-only scope) */
proc sql;
  title "r1 data columns already present in g.master_data_merged";
  select name, type, length
  from dictionary.columns
  where libname = 'G' and memname = 'MASTER_DATA_MERGED'
    and upcase(name) in ('RT_RM_START_TO_INDUCTION_MINS', 'RT_RM_START_TO_EMERGENCE_MINS');
quit;
title;
