---
phase: quick
plan: 260930-mze
type: execute
wave: 1
depends_on: []
files_modified:
  - sas/00_config.sas
  - sas/19c_seed_source_hash_baseline.sas
  - sas/19_raw_dir_inventory.sas
  - .planning/phases/26-v2.1-carry-forward-source-hardening/26-VALIDATION.md
  - docs/DECISIONS.md
autonomous: true
requirements: [HARD-02]

must_haves:
  truths:
    - "19c seed aborts if docs/source_hash_baseline.csv already has data rows (not just header)"
    - "19 SECTION 14 reads docs/source_hash_baseline.csv, asserts 8 rows, flags sha256/size drift, writes qc/19_source_hash_check.csv on every run"
    - "src_hash_files in 00_config.sas lists sas7bdat files (what programs 01-08 actually read)"
    - "PCM-D-30 recorded in docs/DECISIONS.md scoping HARD-01 to raw\\master and HARD-02 to &source_path"
  artifacts:
    - path: "sas/19c_seed_source_hash_baseline.sas"
      provides: "One-time seed of docs/source_hash_baseline.csv from live hashes of the 8 sas7bdat files"
    - path: "docs/DECISIONS.md"
      provides: "PCM-D-30 entry"
  key_links:
    - from: "sas/19_raw_dir_inventory.sas SECTION 14"
      to: "docs/source_hash_baseline.csv"
      via: "DATA step infile (PCM-T-16)"
      pattern: "source_hash_baseline"
---

<objective>
Implement HARD-02: source-file hash guard for the 8 sas7bdat files in &source_path that
programs 01-08 read.

Purpose: Detect any post-seed change (corruption, replacement, accidental overwrite) in
the renamed source extracts before any merge program runs. Parallel to HARD-01, which
guards the originals in raw\master.

Output:
- sas/19c_seed_source_hash_baseline.sas — one-time seed program (not in run_pipeline.cmd)
- sas/19_raw_dir_inventory.sas updated: SECTION 14 source hash guard inserted before the
  current SECTION 14 ODS Excel block (which becomes SECTION 15); SECTION 15 output
  verification becomes SECTION 16
- sas/00_config.sas: src_hash_files corrected from .xlsx to .sas7bdat (programs 01-08
  read sas7bdat, confirmed by grep of sas/01_verify_sources.sas)
- docs/DECISIONS.md: PCM-D-30 appended
- 26-VALIDATION.md: two new verification rows added
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@.planning/STATE.md
@sas/00_config.sas
@sas/19b_seed_hash_baseline.sas
@sas/19_raw_dir_inventory.sas
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix src_hash_files in 00_config.sas (sas7bdat not xlsx)</name>
  <files>sas/00_config.sas</files>
  <action>
Programs 01-08 read sas7bdat files from &source_path, not xlsx files. The current
src_hash_files value lists master_data_1.xlsx through master_data_8.xlsx — this is wrong.

Edit the %let src_hash_files line (around line 40-41) to list sas7bdat files:

  %let src_hash_files = master_data_1.sas7bdat master_data_2.sas7bdat
                        master_data_3.sas7bdat master_data_4.sas7bdat
                        master_data_5.sas7bdat master_data_6.sas7bdat
                        master_data_7.sas7bdat master_data_8.sas7bdat;

Also update the comment block above src_hash_files (lines 33-43) to say:
  "19c_seed_source_hash_baseline.sas  seeds docs\source_hash_baseline.csv once"
  "19_raw_dir_inventory.sas SECTION 14 checks it on every pipeline run."
  and in the "Programs 01-08 read the RENAMED files" sentence, change
  "renamed files in &source_path -- a different directory" to add "(as .sas7bdat)".

No other changes to 00_config.sas. The %src_hash_compute macro uses
hashing_file('SHA256', strip(full_path), 4) which works for any file type including
sas7bdat, so no macro change needed.

PCM compliance: no open-code %IF, no literal quotes in %sysfunc(), ASCII only.
  </action>
  <verify>
    <automated>findstr /C:"sas7bdat" "C:\Master_Renamed_same_format_accross\sas\00_config.sas"</automated>
  </verify>
  <done>src_hash_files lists 8 sas7bdat filenames; no xlsx remains in that macro variable.</done>
</task>

<task type="auto">
  <name>Task 2: Create sas/19c_seed_source_hash_baseline.sas</name>
  <files>sas/19c_seed_source_hash_baseline.sas</files>
  <action>
Create a new one-time seed program modelled on sas/19b_seed_hash_baseline.sas but for
the HARD-02 scope (&source_path sas7bdat files, not raw\master csv/xlsx files).

Key differences from 19b:
- Source of hash data: call %src_hash_compute (defined in 00_config.sas) to get live
  hashes of the 8 sas7bdat files; do NOT read from qc/19_raw_files.csv (those are
  raw\master hashes, not source_path hashes)
- Baseline file: &src_hash_baseline (= &docs_path.\source_hash_baseline.csv, defined
  in 00_config.sas) -- different from docs/raw_hash_baseline.csv used by 19b/HARD-01
- Exists-guard counts DATA ROWS (not just file existence): read the baseline with a DATA
  step infile; count non-header lines; if count > 0 abort. This prevents a header-only
  stub (created by a failed first run) from being treated as "unseeded" and overwriting
  a partial baseline. Header-only = 0 data rows = safe to proceed.
- Expected files: derive from &src_hash_files (space-delimited list from 00_config.sas);
  count words with countw("&src_hash_files",' ') -- must equal 8
- Status filter: %src_hash_compute writes status = 'OK' / 'NOT_FOUND' / 'OPEN_FAILED' /
  'HASH_FAILED'; abort if any row is not OK before writing baseline

Program structure (sections, all conditional logic in named macros):

  SECTION 0 -- Header, %include 00_config.sas, options
  SECTION 1 -- Utility macro: %fail_out(msg=) -> %put ERROR: &msg; %abort cancel;
  SECTION 2 -- Exists-guard:
    %macro seed_guard:
      Read &src_hash_baseline with DATA step infile (PCM-T-16); count observations.
      If obs > 0: %fail_out -- baseline already seeded; delete and re-run 19c to reseed.
      Check countw("&src_hash_files",' ') = 8; if not: %fail_out.
      %put NOTE: Exists-guard passed.
  SECTION 3 -- Compute live hashes:
    %src_hash_compute(out=work._src_hash_now);  /* uses 00_config macro */
  SECTION 4 -- Assert all 8 files hashed successfully:
    %macro assert_hash_ok:
      proc sql noprint: select count(*) into :n_ok where status='OK';
                        select count(*) into :n_bad where status ne 'OK';
      If n_ok ne 8 or n_bad > 0: print bad rows to log; %fail_out.
      %put NOTE: assert_hash_ok passed -- 8 files hashed OK.
  SECTION 5 -- Build and sort baseline rows (sorted by file_name for stable git diff):
    data work._baseline_out:
      set work._src_hash_now;
      length seeded_date $10;
      seeded_date = put(today(), yymmdd10.);
      keep file_name sha256 bytes seeded_date;
    proc sort: by file_name;
  SECTION 6 -- Write docs/source_hash_baseline.csv (DATA step PUT, not PROC EXPORT):
    Header line: file_name,sha256,byte_size,seeded_date
    Data rows: file_name sha256 bytes :32. seeded_date
    Use file "&src_hash_baseline" lrecl=1000 for header.
    Use file "&src_hash_baseline" dsd mod lrecl=1000 for rows.
  SECTION 7 -- Verify the output (exists + header + 8 data rows):
    %macro verify_baseline_written:
      fileexist(&src_hash_baseline) -- if 0: fail.
      DATA step infile: count lines; check line 1 = 'file_name,sha256,byte_size,seeded_date';
      If header wrong or total lines ne 9 (1 header + 8 data): fail.
      %put NOTE: source_hash_baseline.csv verified -- header plus 8 rows.
      %put NOTE: ==== 19c seed complete. Do not re-run without deleting the file first. ====

Header comment block must say:
  "IMPORTANT: NOT part of run_pipeline.cmd. Run exactly once after confirming
   the 8 renamed source extracts in &source_path are the correct verified files."
  "To re-seed: delete docs/source_hash_baseline.csv, re-run this program, git diff
   before committing."

PCM compliance: no open-code %IF/%THEN; DATA step infile for CSV writes (PCM-T-16);
no quotes inside %sysfunc(fileexist(...)) (B-06); %abort cancel only inside %fail_out;
ASCII only; no PROC IMPORT.
  </action>
  <verify>
    <automated>if exist "C:\Master_Renamed_same_format_accross\sas\19c_seed_source_hash_baseline.sas" (echo FILE_EXISTS) else (echo MISSING)</automated>
  </verify>
  <done>
    File exists. Contains %include 00_config.sas, %fail_out macro, seed_guard that counts
    data rows (not just file existence), %src_hash_compute call, assert_hash_ok, write of
    &src_hash_baseline with header + 8 sorted rows, verify_baseline_written.
  </done>
</task>

<task type="auto">
  <name>Task 3: Insert SECTION 14 source hash guard into sas/19_raw_dir_inventory.sas</name>
  <files>sas/19_raw_dir_inventory.sas</files>
  <action>
The current program has SECTION 13 (HARD-01 hash guard) ending at line ~980, then
SECTION 14 (ODS Excel) at line ~984, then SECTION 15 (output verification) at ~1099.

Insert a new SECTION 14 (HARD-02 source hash guard) AFTER the SECTION 13 %check_hash_baseline
call and BEFORE the current ODS Excel block. Renumber the current SECTION 14 -> SECTION 15
and the current SECTION 15 -> SECTION 16.

New SECTION 14 to insert (complete, self-contained SAS code):

/* ============================================================
   SECTION 14 -- HARD-02 source hash guard
   Reads docs/source_hash_baseline.csv (seeded once by 19c).
   Requires 8 data rows; aborts if sha256 or byte_size drifted.
   Writes qc/19_source_hash_check.csv on every run (pass or fail)
   so drift is auditable even when the run succeeds.
   &src_hash_baseline and %src_hash_compute are defined in 00_config.sas.
   ============================================================ */

%macro check_source_hash_baseline;
  %local n_base n_drift;
  %let n_base  = 0;
  %let n_drift = 0;

  /* 14a -- Baseline must exist and have data rows */
  %if %sysfunc(fileexist(&src_hash_baseline)) = 0 %then %do;
    %fail_out(msg=HARD-02 baseline docs/source_hash_baseline.csv not found -- run 19c once to seed it);
  %end;

  data work._src_baseline;
    length file_name $64 sha256 $64 byte_size 8 seeded_date $12;
    infile "&src_hash_baseline" dsd dlm=',' firstobs=2 truncover lrecl=500;
    input file_name $ sha256 $ byte_size seeded_date $;
  run;

  proc sql noprint;
    select count(*) into :n_base trimmed from work._src_baseline;
  quit;
  %if &n_base ne 8 %then %do;
    %fail_out(msg=HARD-02 baseline row count is &n_base -- expected 8. Re-seed docs/source_hash_baseline.csv by running 19c.);
  %end;

  /* 14b -- Compute live hashes of the 8 source sas7bdat files */
  %src_hash_compute(out=work._src_hash_now);

  /* 14c -- Compare; write audit CSV regardless of result */
  proc sql noprint;
    create table work._src_hash_check as
    select b.file_name,
           b.sha256     as baseline_sha256    length=64,
           b.byte_size  as baseline_bytes,
           n.sha256     as current_sha256     length=64,
           n.bytes      as current_bytes,
           n.status     as hash_status        length=12,
           case when n.status ne 'OK'                             then 'HASH_ERROR'
                when lowcase(strip(b.sha256)) ne
                     lowcase(strip(coalesce(n.sha256,'')))        then 'SHA256_DRIFT'
                when b.byte_size ne coalesce(n.bytes, -1)         then 'SIZE_DRIFT'
                else 'OK'
           end as check_result length=12,
           put(today(), yymmdd10.) as check_date length=10
    from work._src_baseline b
    left join work._src_hash_now n
      on upcase(strip(b.file_name)) = upcase(strip(n.file_name));
  quit;

  proc export data=work._src_hash_check
    outfile="&qc_path.\19_source_hash_check.csv"
    dbms=csv replace;
  run;
  %put NOTE: qc/19_source_hash_check.csv written (HARD-02 audit);

  proc sql noprint;
    select count(*) into :n_drift trimmed
    from work._src_hash_check
    where check_result ne 'OK';
  quit;

  %if &n_drift > 0 %then %do;
    %fail_out(msg=HARD-02 HASH GUARD FAILED -- &n_drift source file(s) in &source_path changed since baseline. Delete docs/source_hash_baseline.csv and re-run 19c to acknowledge new sources.);
  %end;

  %put NOTE: HARD-02 hash guard passed -- all 8 source sas7bdat sha256 values match baseline.;
%mend check_source_hash_baseline;
%check_source_hash_baseline;

Then renumber:
- The ODS Excel section comment "SECTION 14" -> "SECTION 15"
- The output verification section comment "SECTION 15" -> "SECTION 16"
- Update the %verify_output macro to also check &qc_path.\19_source_hash_check.csv:
    Add after the existing fileexist checks:
    %if %sysfunc(fileexist(&qc_path.\19_source_hash_check.csv)) = 0 %then %do;
      %fail_out(msg=OUTPUT MISSING -- qc/19_source_hash_check.csv was not created);
    %end;

Also update the program header comment block at the top (Writes section) to add:
    "            qc/19_source_hash_check.csv -- HARD-02 source hash audit (written every run)"
And update Revised date line:
    "            2026-09-30 (round 6 -- SECTION 14 HARD-02 source hash guard for &source_path sas7bdat files)"

PCM compliance: all conditional logic inside named macros; no open-code %IF;
%abort cancel only inside %fail_out; DATA step infile for CSV read (PCM-T-16);
no literal quotes inside %sysfunc(fileexist(...)).
  </action>
  <verify>
    <automated>findstr /C:"SECTION 14" /C:"HARD-02" "C:\Master_Renamed_same_format_accross\sas\19_raw_dir_inventory.sas"</automated>
  </verify>
  <done>
    sas/19_raw_dir_inventory.sas contains SECTION 14 with HARD-02 label and
    %check_source_hash_baseline macro. Current SECTION 14/15 renamed to 15/16.
    %verify_output checks for qc/19_source_hash_check.csv.
  </done>
</task>

<task type="auto">
  <name>Task 4: Add two rows to 26-VALIDATION.md and append PCM-D-30 to DECISIONS.md</name>
  <files>
    .planning/phases/26-v2.1-carry-forward-source-hardening/26-VALIDATION.md
    docs/DECISIONS.md
  </files>
  <action>
## 26-VALIDATION.md

In the Per-Task Verification Map table, append two rows after the existing last row
(26-04-01):

| 26-mze-01 | mze | 1 | HARD-02 seed / abort | manual | run 19c -> docs/source_hash_baseline.csv (9 lines: 1 header + 8 data rows); re-run 19c -> SAS log shows `SEED ABORTED` | ❌ W0 | ⬜ pending |
| 26-mze-02 | mze | 1 | HARD-02 hash guard pass/fail | automated | run program 19 -> log shows `HARD-02 hash guard passed`; tamper test: corrupt one sha256 in docs/source_hash_baseline.csv (64-char hex value, change last char) -> re-run program 19 -> log shows `HARD-02 HASH GUARD FAILED`; restore value -> passes again | ❌ W0 | ⬜ pending |

Also add to the Manual-Only Verifications table:

| HARD-02 seed refuses to overwrite data rows | HARD-02 | Interactive test -- seed once, re-run; abort must fire | Run 19c -> baseline created; run 19c again -> SAS log shows SEED ABORTED |
| HARD-02 guard triggers on drift | HARD-02 | Must see the guard fail once | Change ONE sha256 in docs/source_hash_baseline.csv to wrong 64-hex value; run program 19 -> HARD-02 HASH GUARD FAILED; restore -> passes |

## docs/DECISIONS.md

Append at the very end of the file (after the PCM-D-29 entry):

---

## PCM-D-30 -- HARD-01 vs HARD-02 Scope Boundary: RESOLVED

**Date:** 2026-09-30
**Decided by:** Gerard
**Status:** RESOLVED

**Question:** Which hash guard covers which set of files, and why are they separate?

**Decision:**

HARD-01 (program 19 SECTION 13 + 19b seed): covers the 8 ORIGINAL extracts
  in raw\master (csv/xlsx format, read-only, not imported by any SAS program directly).
  Baseline: docs/raw_hash_baseline.csv. Hashes computed by certutil via PIPE in program 19
  SECTION 5 during the directory inventory.

HARD-02 (program 19 SECTION 14 + 19c seed): covers the 8 RENAMED source extracts
  in &source_path (master_data_1.sas7bdat ... master_data_8.sas7bdat), which are
  the files programs 01-08 actually set/import. Baseline: docs/source_hash_baseline.csv.
  Hashes computed by %src_hash_compute (00_config.sas) using HASHING_FILE(..., 4).
  Audit CSV written on every run: qc/19_source_hash_check.csv.

These are different directories and different file formats. raw\master holds the
originals as exported; &source_path holds the working copies renamed to a uniform
master_data_N.sas7bdat naming convention. A file in &source_path could drift from
its raw\master counterpart without triggering HARD-01 (which only sees the originals).
HARD-02 closes that gap.

19c must be run manually once after programs 01-08 have been run successfully and
the sas7bdat files in &source_path are confirmed correct. 19c is NOT added to
run_pipeline.cmd (same constraint as 19b for HARD-01).

**Traceability:** HARD-02 requirement; Phase 26 quick task 260930-mze;
docs/source_hash_baseline.csv (detective control).

**Resolved:** 2026-09-30 | Owner: Gerard | Phase 26 quick
  </action>
  <verify>
    <automated>findstr /C:"PCM-D-30" "C:\Master_Renamed_same_format_accross\docs\DECISIONS.md"</automated>
  </verify>
  <done>
    docs/DECISIONS.md contains PCM-D-30 entry with scope boundary explanation.
    26-VALIDATION.md contains rows 26-mze-01 and 26-mze-02.
  </done>
</task>

</tasks>

<verification>
After all tasks complete:
1. sas/00_config.sas: src_hash_files lists 8 .sas7bdat filenames
2. sas/19c_seed_source_hash_baseline.sas exists and follows 19b pattern
3. sas/19_raw_dir_inventory.sas: SECTION 14 = HARD-02 guard, old 14/15 = 15/16
4. docs/DECISIONS.md ends with PCM-D-30
5. 26-VALIDATION.md has 26-mze-01 and 26-mze-02 rows
</verification>

<success_criteria>
- src_hash_files in 00_config.sas matches what programs 01-08 actually read (sas7bdat)
- 19c seed program: exists-guard counts data rows, calls %src_hash_compute, writes
  docs/source_hash_baseline.csv with header + 8 sorted rows
- Program 19 SECTION 14: reads baseline, requires 8 rows, compares sha256 + bytes,
  writes qc/19_source_hash_check.csv on every run, aborts on drift
- PCM-D-30 documents the two-guard scope boundary
- All PCM compliance rules maintained (no open-code %IF, PCM-T-16, B-06, ASCII only)
</success_criteria>

<output>
No SUMMARY file required for quick tasks.
</output>
