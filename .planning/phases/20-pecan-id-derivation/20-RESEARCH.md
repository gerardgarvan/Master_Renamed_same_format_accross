# Phase 20: pecan_ID Derivation - Research

**Researched:** 2026-09-23
**Domain:** SAS 9.4 crosswalk construction, PROC APPEND, certutil checksum, PROC IMPORT targeted re-import, PUT-to-fileref text output, data dictionary static-entry pattern
**Confidence:** HIGH (all findings from direct codebase reads; no training-data inference required)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**PCM-D-17: pecan_ID Derivation Method**
- Surrogate sequential integer (1, 2, 3...). Distinct ENCRYPTED_MRN values numbered in ascending order of each MRN's smallest PRECEDE_STUDY_ID in g.master_data_merged. MRNs added on later runs are appended after the existing maximum. Blank and placeholder MRNs excluded entirely.
- g.pecan_id_xwalk (ENCRYPTED_MRN, pecan_ID) is append-only. Reference for "unchanged" is the latest dated backup. Before appending, assert current xwalk equals latest backup. Add new MRNs via PROC APPEND only. After appending, assert every backup row still present. Only then write a new dated backup. First run: skip pre/post assertions, build xwalk, write first backup, log as initial build.
- ENCRYPTED_MRN is retained in all analysis outputs alongside pecan_ID. No DROP.
- Dated backup written to a protected location outside qc/ and outside git. Path in 00_config.sas as a macro variable.

**PCM-D-18: Attach Point**
- Programs 10b and 16b join the crosswalk at build time. Each dataset has a single producer. g.master_data_merged is untouched.
- Row count unchanged after join; zero blank pecan_ID where ENCRYPTED_MRN is non-blank and non-placeholder; zero PRECEDE_STUDY_IDs gaining a second pecan_ID after attachment.
- Column count: g.master_data_harmonized and g.analytic_cohort each go from 174 to 175 columns. PID-05 assertions in 10b and 16b.

**Runner order:** 1-8 → 19 → 20 → 10b → 16b → 17 → 18

**Source file:** raw\master\2018_2022_X_MASTER_DATASET_20240402.csv

**Phase 19 CSV handoffs consumed by Phase 20:**
- qc/19_raw_files.csv — checksum records (PID-01)
- qc/19_raw_key_columns.csv — ENCRYPTED_MRN key-column flags (PID-07 scope)
- qc/19_raw_sheets.csv — sheet metadata (PID-07 targeted import)
- qc/19_raw_variables_md3.csv — ENCRYPTED_MRN type/length for md3 (D-11)

**Cross-check (D-14):** Join CSV to g.master_data_merged on PRECEDE_STUDY_ID after applying md3 prep normalization to CSV side. Any mismatch aborts.

**PID-06 in 16b:** Counts to qc/16b_pecan_id_counts.txt and log.

**PID-07:** qc/20_linkage_reach.txt. All ENCRYPTED_MRN-tagged files from qc/19_raw_key_columns.csv. Section per file+sheet+column. Explicit YES/NO for r7/r8/r9 (PCM-D-16 test). Exclusions list for UNENC_MRN-only files. Numeric-MRN "type mismatch: not compared" block.

**PID-08:** pecan_ID as static entry in 08_dictionary.sas lines 234-244 block. No PROC SQL UPDATE. No xlsx manipulation (PCM-T-01).

### Claude's Discretion

- Exact SAS macro structure inside program 20 (looping over qc/19_raw_key_columns.csv rows for PID-07, PUT statement layout for text report files)
- Backup location path for the crosswalk (macro variable in 00_config.sas; must be outside qc/ and outside git)
- Whether the static pecan_ID entry in 08_dictionary.sas uses the existing `varname = "..."; derivation = "..."; output;` pattern or a separate hardcoded dataset

### Deferred Ideas (OUT OF SCOPE)

- PCM-D-15 gap-fill wiring (extension-column join key decision) remains deferred to v2.1 pending PID-07 result.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PID-01 | pecan_ID source file checksummed and verified against INV-01 record before Phase 20 reads it | Phase 19 certutil+PIPE pattern reused; 19_raw_files.csv read via PROC IMPORT |
| PID-02 | Source audit: blank MRN count, distinct MRN count, distinct PRECEDE_STUDY_ID count, both-direction cardinalities | PROC SQL counts on g.master_data_merged after normalization |
| PID-03 | Every PRECEDE_STUDY_ID maps to exactly one ENCRYPTED_MRN; abort otherwise | PROC SQL group-by + HAVING count > 1; abort in named macro |
| PID-04 | g.pecan_id_xwalk built per PCM-D-17; append-only; existing assignments never renumbered | PROC APPEND pattern; dated backup; first-run vs re-run branch |
| PID-05 | Row count unchanged; zero blank pecan_ID where MRN non-blank; zero duplicate pecan_ID per PRECEDE (in 10b and 16b) | PROC SQL count assertions inside 10b and 16b after join |
| PID-06 | Distinct pecan_ID counts and encounter distribution for both harmonized and cohort (in 16b) | PROC SQL + PUT-to-fileref pattern; output to qc/16b_pecan_id_counts.txt |
| PID-07 | Linkage reach for all ENCRYPTED_MRN-tagged raw files; r7/r8/r9 YES/NO test | Targeted re-import from qc/19_raw_key_columns.csv + qc/19_raw_sheets.csv; PUT-to-fileref text output |
| PID-08 | pecan_ID in DATA_DICTIONARY.xlsx with derivation note; PCM-D-17/D-18 in DECISIONS.md | Static entry in 08_dictionary.sas derivation_map block |
</phase_requirements>

---

## Summary

Phase 20 is a pure SAS 9.4 construction phase. It builds one new permanent dataset (`g.pecan_id_xwalk`), amends two existing programs (10b, 16b) to join it, amends the dictionary program (08) to document it, and writes three QC text files and one DECISIONS.md amendment. No new library dependencies are needed. All patterns required already exist in the codebase.

The most structurally novel piece is the append-only crosswalk with a backup-comparison guard (D-02). The pattern does not exist verbatim in the codebase but is fully constructible from established SAS primitives (PROC APPEND, PROC SQL count + %abort cancel). Every other pattern — certutil checksum, PUT-to-fileref text output, static derivation entry, column-count assertion, targeted PROC IMPORT — is directly reusable from existing programs.

**Critical pre-condition:** The four Phase 19 CSV handoffs (`qc/19_raw_files.csv`, `qc/19_raw_key_columns.csv`, `qc/19_raw_sheets.csv`, `qc/19_raw_variables_md3.csv`) do NOT currently exist. Program 19 currently writes only `qc/19_raw_files.csv` (Section 12). The other three CSVs require a Phase 19 plan amendment before Phase 20 can execute.

**Primary recommendation:** Plan Phase 20 in five distinct tasks: (1) Phase 19 amendment, (2) new program 20 (PID-01 through PID-04, PID-07, PID-08), (3) amend 10b (PID-05 join), (4) amend 16b (PID-05 join + PID-06 counts), (5) amend 08_dictionary.sas (PID-08 static entry).

---

## Standard Stack

### Core (no new installs required)

| Component | Version | Purpose | Source in Codebase |
|-----------|---------|---------|-------------------|
| SAS 9.4M8 | 9.4M8 | All program logic | All existing sas/ programs |
| PROC APPEND | base SAS | Append-only crosswalk growth | Standard SAS; not yet used in this pipeline |
| PROC IMPORT | base SAS | Reading Phase 19 CSVs + targeted raw re-imports | 19_raw_dir_inventory.sas, 18_supplemental_raw_gap.sas |
| PROC EXPORT | base SAS | Writing CSV handoffs | 19_raw_dir_inventory.sas SECTION 12 |
| FILENAME PIPE | base SAS | certutil checksum | 19_raw_dir_inventory.sas SECTION 5 |
| FILENAME (fileref) | base SAS | PUT-to-fileref text output | 18_supplemental_raw_gap.sas, 03_prep_md3.sas |
| ODS EXCEL | base SAS | DATA_DICTIONARY.xlsx regeneration | 08_dictionary.sas |

**Installation:** None required.

---

## Architecture Patterns

### Pattern 1: certutil SHA-256 Checksum (reuse from program 19)

**What:** A DATA step with `INFILE ... PIPE FILEVAR=` runs certutil once per file through a DATA step iteration. The 64-hex line is identified by length and notxdigit test.

**Exact code from 19_raw_dir_inventory.sas SECTION 5:**

```sas
data work.sha_results;
  set work.files_meta(keep=file_id full_path);
  length _cmd $1000 line $400 compressed $400 sha256 $64;
  _cmd   = 'certutil -hashfile "' || strip(full_path) || '" SHA256';
  sha256 = 'FAILED';
  infile ckpipe pipe filevar=_cmd end=_done truncover lrecl=400;
  do while (not _done);
    input line $400.;
    compressed = compress(line, ' ');
    if lengthn(compressed) = 64 and notxdigit(strip(compressed)) = 0 then
      sha256 = lowcase(compressed);
  end;
  if sha256 = 'FAILED' then put 'WARNING: SHA-256 FAILED for ' full_path=;
  keep file_id sha256;
run;
```

**For PID-01:** Program 20 checksums the single file `raw\master\2018_2022_X_MASTER_DATASET_20240402.csv`, then reads `qc/19_raw_files.csv` (via PROC IMPORT) to find that file's sha256 record, and asserts the two values are equal. If they differ, `%abort cancel` inside a named macro.

**Reading qc/19_raw_files.csv for the stored checksum:**
```sas
proc import datafile="&qc_path.\19_raw_files.csv"
    out=work.files19 dbms=csv replace;
  guessingrows=max;
run;

/* Then look up the sha256 for the md3 source filename */
proc sql noprint;
  select sha256 into :expected_sha trimmed
  from work.files19
  where upcase(strip(filename)) = '2018_2022_X_MASTER_DATASET_20240402.CSV';
quit;
```

### Pattern 2: PUT-to-fileref text output (reuse from programs 03, 18)

**What:** FILENAME assigns a fileref to a qc/ path. DATA _NULL_ writes with PUT. Subsequent appends use `file fileref mod`.

**Exact code from 18_supplemental_raw_gap.sas:**

```sas
data _null_;
  file "&qc_path.\18_id_diagnostic.txt" lrecl=200;
  put "==========================================================================";
  put "Phase 18 -- 2022 Cohort ID Mismatch Diagnostic";
  /* ... */
run;

/* Append-mode write later in same program: */
data _null_;
  file "&qc_path.\18_id_diagnostic.txt" mod;
  /* ... more lines */
run;
```

**For PID-07 (`qc/20_linkage_reach.txt`) and PID-06 (`qc/16b_pecan_id_counts.txt`):** Use the same pattern. Open fresh at program start (no `mod`), append each section with `mod`. Note: `file "&qc_path.\20_linkage_reach.txt"` uses the macro variable with period-termination, same as program 16b line 100 comment documents: "The period terminates the macro variable name and is consumed by the macro processor; the backslash remains."

**From 03_prep_md3.sas — FILENAME fileref variant (equivalent):**
```sas
filename excf "&qc_path.\03_exceptions_md3.txt";
data _null_;
  file excf;
  put "md3 Exception Report -- Run: %sysfunc(datetime(), datetime20.)";
  put "NULL sentinel strings: &n_sent";
run;
filename excf clear;
```

Either form works. The inline string form used in program 18 is slightly simpler for one-off files.

### Pattern 3: Append-only crosswalk with backup guard (new in this pipeline)

**What:** PROC APPEND adds new rows only. The pre-append and post-append assertions compare the crosswalk to the latest dated backup, not to itself. First run branches explicitly.

**Structure:**

```sas
%macro build_or_append_xwalk;
  %local xwalk_exists backup_exists;

  /* Check existence */
  proc sql noprint;
    select count(*) into :xwalk_exists trimmed
    from dictionary.tables where libname='G' and memname='PECAN_ID_XWALK';
  quit;

  /* Check if any backup file exists */
  %let backup_exists = %sysfunc(fileexist(&xwalk_backup_path.\pecan_id_xwalk_backup_latest.sas7bdat));
  /* (actual discovery of latest backup may use dir pipe or a known naming convention) */

  %if &xwalk_exists = 0 or &backup_exists = 0 %then %do;
    /* First run: build from scratch */
    /* ... PROC SQL to build g.pecan_id_xwalk ... */
    /* ... DATA step to write backup ... */
    %put NOTE: [20] Initial crosswalk build complete.;
  %end;
  %else %do;
    /* Re-run: assert xwalk = backup before appending */
    /* ... PROC SQL compare g.pecan_id_xwalk to backup ... */
    /* ... PROC APPEND new rows ... */
    /* ... assert backup rows still present after append ... */
    /* ... write new dated backup ... */
  %end;
%mend build_or_append_xwalk;
```

**Key PROC APPEND syntax:**
```sas
proc append base=g.pecan_id_xwalk data=work.new_mrns force; run;
/* FORCE is needed only if the datasets differ in length/type;
   with identical structure (both char $40 ENCRYPTED_MRN, num pecan_ID) FORCE is unnecessary */
```

**Next available integer:**
```sas
proc sql noprint;
  select max(pecan_ID) into :max_pid trimmed from g.pecan_id_xwalk;
quit;
/* new assignments start at &max_pid + 1 */
```

**Crosswalk equality assertion (xwalk vs backup):**
```sas
proc sql noprint;
  /* Rows in xwalk not in backup (by both columns) */
  select count(*) into :n_xwalk_only trimmed
  from g.pecan_id_xwalk x
  where not exists (
    select 1 from g.pecan_id_xwalk_backup b
    where b.ENCRYPTED_MRN = x.ENCRYPTED_MRN
      and b.pecan_ID = x.pecan_ID
  );
  /* Rows in backup not in xwalk */
  select count(*) into :n_backup_only trimmed
  from g.pecan_id_xwalk_backup b
  where not exists (
    select 1 from g.pecan_id_xwalk x
    where x.ENCRYPTED_MRN = b.ENCRYPTED_MRN
      and x.pecan_ID = b.pecan_ID
  );
quit;
```

### Pattern 4: Static entry in 08_dictionary.sas derivation_map (verified)

**What:** Lines 234-244 in 08_dictionary.sas contain a DATA step that builds `work.derivation_map`. Each entry is one line:
```sas
varname="VARNAME";  derivation="text description"; output;
```

**Verified structure (lines 224-244):**
```sas
data work.derivation_map;
  length varname $64 derivation $200;

  varname="COGNITIVE_SCORE";   derivation="md3 spine, md8 gap-fill (MRG-06)"; output;
  /* ... more entries ... */
  varname="RT_ENVELOPE_FLAG";  derivation="derived at merge (Phase 4); not in ownership_map"; output;
  varname="N_SOURCES";         derivation="derived at merge (Phase 4); not in ownership_map"; output;
  /* ... more entries ... */
run;
```

**Critical finding:** The derivation_map is a LEFT JOIN onto `work.dict_with_owner` (which comes from `dictionary.columns` for `G.MASTER_DATA_MERGED`). If a varname in derivation_map does not exist in `g.master_data_merged`, the join produces no output row for it — the entry is silently dropped. This is confirmed by the join in SECTION 5:
```sas
proc sql noprint;
  create table work.dict_final as
  select d.varname, ...
         coalesce(dm.derivation, catx(" ", d.source, "owner (ownership_map)")) as derivation
  from   work.dict_with_owner as d
  left join work.derivation_map as dm
    on upcase(d.varname) = upcase(dm.varname);
quit;
```

**Conclusion for PID-08:** Since `pecan_ID` is NOT in `g.master_data_merged`, a derivation_map entry for it would be silently dropped by the LEFT JOIN — the dictionary only adds rows that exist in `g.master_data_merged`. To add a row for `pecan_ID`, a separate explicit OUTPUT is needed AFTER dict_final is built, or a UNION ALL is appended before the ODS step. The existing "static entry block" annotates existing columns; it does NOT add new rows for variables absent from `g.master_data_merged`.

**The correct approach for PID-08:** After `work.dict_final` is built (before ODS EXCEL opens), add an explicit INSERT or DATA step that appends one row for `pecan_ID`. This must also be reflected in the `n_dict_meta` assertion — that assertion checks `n_final ne n_dict_meta`, where both come from `dictionary.columns` for `G.MASTER_DATA_MERGED`. A pecan_ID row added manually will make n_final = n_dict_meta + 1, which will trigger the gate failure. The assertion must be updated to expect `n_dict_meta + 1`.

**Exact assertion in 08_dictionary.sas:**
```sas
%macro _gate5;
  %if &n_final ne &n_dict_meta %then %do;
    %fail_out(msg=dict_final row count &n_final does not match dict_meta count &n_dict_meta);
  %end;
%mend _gate5;
```
Must change to `ne %eval(&n_dict_meta + 1)` (or read the expected count as a computed value). The 10b program also asserts `g.master_data_merged` has exactly 176 columns post-run. That assertion is for `g.master_data_merged` only and is unaffected by the dictionary row addition.

**Also check in 10b:** Line 1082 asserts `n_merged_cols ne 176`. Adding a dictionary row does not touch `g.master_data_merged`, so this assertion is unaffected.

### Pattern 5: pecan_ID join in 10b and 16b

**10b current terminal step (SECTION 5):**
```sas
data g.master_data_harmonized
  (drop=in_md3 ... )
  work.src_check (...);
  set g.master_data_merged;
  /* rules */
run;
```

**Required change:** After the DATA step writes `g.master_data_harmonized`, add a PROC SQL join to attach pecan_ID:
```sas
proc sql noprint;
  create table work.harmonized_with_pid as
  select h.*, x.pecan_ID
  from g.master_data_harmonized as h
  left join g.pecan_id_xwalk as x
    on h.ENCRYPTED_MRN = x.ENCRYPTED_MRN;
quit;

/* PCM-T-02: no in-place rewrite. Write to WORK first, then promote. */
data g.master_data_harmonized;
  set work.harmonized_with_pid;
run;
```

**Assertion after join (PID-05):**
```sas
proc sql noprint;
  select count(*) into :n_post trimmed from g.master_data_harmonized;
  select count(*) into :n_blank_pid trimmed
  from g.master_data_harmonized
  where pecan_ID is missing
    and not missing(ENCRYPTED_MRN)
    and strip(upcase(ENCRYPTED_MRN)) ne 'NULL';
  select count(*) into :n_dup_pid trimmed
  from (
    select PRECEDE_STUDY_ID, count(distinct pecan_ID) as n_pid
    from g.master_data_harmonized
    group by PRECEDE_STUDY_ID
    having calculated n_pid > 1
  );
quit;
```

**Column count assertion update:** 10b currently asserts `g.master_data_harmonized` has a specific column count implicitly through n_changed check vs g.master_data_merged. After adding pecan_ID, the assert_harmonized_unchanged macro (SECTION 6) checks `&n_cols ne 174` — this must be updated to 175. Similarly, 16b's `verify_cohort_cols` checks `ne 174` — must update to 175, and `assert_harmonized_unchanged` checks `n_cols ne 174` — must update to 175.

**16b: pecan_ID join in SECTION 5 (before or after promotion to g.analytic_cohort):**

Since 16b reads `g.master_data_harmonized` (which by this point already has pecan_ID, because 20 → 10b → 16b), the join in 16b may simply be a pass-through — pecan_ID is already in the source. No second join needed IF 10b has already attached it. However, the SECTION 2 data step in 16b:
```sas
data work.cohort_candidate;
  set g.master_data_harmonized;
  where upcase(strip(Patient_Type)) in ('INPATIENT','OBSERVATION');
run;
```
This already carries pecan_ID through since it's a full SET. No structural change to 16b's filter step. The PID-05 assertions and the column-count updates (174 → 175) in SECTION 5 and SECTION 6 are the changes needed.

### Pattern 6: PRECEDE_STUDY_ID numeric cast for cross-check (D-14)

The md3 CSV may import PRECEDE_STUDY_ID as numeric. The merged file stores it as `$12`. Before the cross-check join:

```sas
/* On CSV side: */
if missing(PRECEDE_STUDY_ID_num) then _pid_key = '';
else _pid_key = strip(put(PRECEDE_STUDY_ID_num, best32.));

/* On merged file side: */
_pid_key = strip(PRECEDE_STUDY_ID);  /* already char $12 */
```

Both sides must produce matching strings. If PRECEDE_STUDY_ID is stored as char in the CSV, strip() alone suffices.

### Pattern 7: Targeted re-import for PID-07 (D-25)

Phase 19 uses `%import_csv` and `%import_xlsx` macros. Phase 20 must NOT use those (they take source IDs and are not designed for targeted column reads). Use direct PROC IMPORT:

```sas
/* For a CSV: */
proc import datafile="&raw_path.\path\to\file.csv"
    out=work._tmp_mrn_col dbms=csv replace;
  guessingrows=max;
run;

/* For an xlsx sheet: */
proc import datafile="&raw_path.\path\to\file.xlsx"
    out=work._tmp_mrn_col dbms=xlsx replace;
  sheet="SheetName";
  getnames=yes;
run;
```

The SHEET= value comes from `qc/19_raw_sheets.csv`. The target file path and column name come from `qc/19_raw_key_columns.csv`. A macro loop over key_columns.csv rows drives the section-per-file+sheet+column structure.

### Recommended Program Structure for 20_pecan_id.sas

```
SECTION 0  -- Options, %include config, libnames, utility macros (fail_out, route_log, restore_log)
SECTION 1  -- Preconditions: existence of all four Phase 19 CSVs (abort if any missing; PCM-T-12)
SECTION 2  -- PID-01: checksum source CSV; compare to qc/19_raw_files.csv record
SECTION 3  -- PID-01 cont.: ENCRYPTED_MRN type/length from qc/19_raw_variables_md3.csv (D-11)
SECTION 4  -- PID-01 cont.: import CSV at $64, assert max length <= 40 (D-12)
SECTION 5  -- D-14 cross-check: apply md3 prep rules to CSV, join to g.master_data_merged, assert
SECTION 6  -- PID-02: source audit on g.master_data_merged (blank count, distinct counts, cardinalities)
SECTION 7  -- PID-03: cardinality assertion (PRECEDE->many MRN aborts)
SECTION 8  -- PID-04: build or append crosswalk (first-run vs re-run branch)
SECTION 9  -- PID-07: linkage reach report -- loop over qc/19_raw_key_columns.csv rows
SECTION 10 -- PID-08: DECISIONS.md amendment (data _null_ write)
```

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Running certutil | Shell exec via %SYSFUNC(SYSTEM()) | INFILE PIPE FILEVAR= pattern (program 19) | FILEVAR= handles paths with spaces; %SYSFUNC(SYSTEM) has quoting traps |
| Appending rows to a persistent dataset | DATA step rewrite | PROC APPEND | DATA step + set g.x would violate PCM-T-02 (in-place rewrite) |
| Sequential integer key | UUID, hash | PROC SQL with ROW_NUMBER() or retain counter | Simpler, stable, append-compatible |
| Text file output | ODS TEXT, ODS LISTING | DATA _NULL_ with FILE/PUT | ODS LISTING creates or replaces -- cannot append sections; PUT/mod is reliable |
| CSV reads | Macro-generated INFILE with custom parsing | PROC IMPORT dbms=csv guessingrows=max | PROC IMPORT handles quoting, newlines in values |

---

## Common Pitfalls

### Pitfall 1: Derivation_map entry silently dropped for pecan_ID
**What goes wrong:** A `varname="PECAN_ID"; derivation="..."; output;` line added to the derivation_map DATA step produces no row in dict_final because derivation_map is LEFT-joined onto dict_with_owner (which only contains variables from `g.master_data_merged`). pecan_ID is not in g.master_data_merged, so the join produces no match and the row is dropped.
**Why it happens:** The join is `from dict_with_owner LEFT JOIN derivation_map`, not the reverse. An entry in derivation_map for a variable absent from dict_with_owner produces no output row.
**How to avoid:** Add pecan_ID as an explicit row after dict_final is assembled, using a UNION or a separate SET, and update the `n_dict_meta + 1` assertion accordingly.
**Warning signs:** dict_final row count equals n_dict_meta (not n_dict_meta + 1); pecan_ID absent from workbook.

### Pitfall 2: Column count assertions broken in 10b and 16b
**What goes wrong:** Adding pecan_ID to g.master_data_harmonized and g.analytic_cohort changes the column count from 174 to 175. Three assertions (assert_harmonized_unchanged in 10b, assert_harmonized_unchanged in 16b, verify_cohort_cols in 16b) all hardcode 174. They will abort on first run after the join is added.
**How to avoid:** Update all three assertions from 174 to 175 as part of the same edit that adds the join. Also update g.master_data_merged assertion in 10b (line 1082: `ne 176`) — this one is for the MERGED file and should remain 176 since pecan_ID is not added there.

### Pitfall 3: In-place rewrite when promoting the joined dataset (PCM-T-02)
**What goes wrong:** Writing `data g.master_data_harmonized; set g.master_data_harmonized; ...` after the join step violates PCM-T-02.
**How to avoid:** Build in WORK first, then DATA g.master_data_harmonized; set work.harmonized_with_pid; run; — exact pattern used by 16b for g.analytic_cohort.

### Pitfall 4: PRECEDE_STUDY_ID type mismatch in cross-check (D-14)
**What goes wrong:** The md3 CSV may import PRECEDE_STUDY_ID as numeric (PROC IMPORT default when all values are digits). Joining character $12 (merged file) to numeric silently fails to match rows.
**How to avoid:** Read type from qc/19_raw_variables_md3.csv first (D-11). If numeric, cast with put(val, best32.) before joining. The existing pipeline stores PRECEDE_STUDY_ID as $12; if the CSV numeric value renders as "12345" and the merged value is "Precede12345", they won't match — apply normalization from 03_prep_md3.sas exactly.
**Warning signs:** Cross-check reports zero matched rows or a large orphan count.

### Pitfall 5: Crosswalk compare-to-itself always passes
**What goes wrong:** Asserting `g.pecan_id_xwalk` equals itself (or running the equality check between the pre-append and post-append states of the same table) always returns true.
**How to avoid:** Per D-02, the reference is the LATEST DATED BACKUP — a separate .sas7bdat written outside the g library. Compare the crosswalk to the backup, not to a WORK copy of itself.

### Pitfall 6: md8 size and PROC IMPORT timeout for PID-07
**What goes wrong:** md8 has ~1M rows. A full PROC IMPORT of md8 to read only ENCRYPTED_MRN may be slow (minutes). No explicit timeout trap exists in the codebase.
**How to avoid:** D-25 specifies targeted re-import. For PROC IMPORT of an xlsx with ~1M rows, use LIBNAME XLSX engine instead, which supports lazy column reads. Or use PROC IMPORT with OBS= if only a subset is needed for type detection. Since only MRN column is needed, consider reading just that column via LIBNAME XLSX:
```sas
libname _xl8 xlsx "&raw_path.\path\to\md8.xlsx" sheet="SheetName";
proc sql noprint;
  create table work._md8_mrn as
  select ENCRYPTED_MRN from _xl8.sheet_table;
quit;
libname _xl8 clear;
```
This is faster than PROC IMPORT for column-level reads.

### Pitfall 7: Backup path with PHI outside qc/ but inside git tracking
**What goes wrong:** The crosswalk backup contains ENCRYPTED_MRN values (PHI). If placed anywhere under `C:\Master_Renamed_same_format_accross\` it could accidentally be committed.
**How to avoid:** The backup path must be on P: (outside the git tree). The macro variable `&xwalk_backup_path` in 00_config.sas should point to a P: subdirectory (e.g., `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\xwalk_backup`). The .gitignore already excludes *.sas7bdat, but belt-and-suspenders: keep it on P:.

### Pitfall 8: Phase 19 CSVs do not yet exist
**What goes wrong:** All four Phase 19 CSV handoffs are absent. Program 20 will abort at SECTION 1 precondition checks (or earlier if the planner skips the precondition step).
**How to avoid:** The planner must schedule a Phase 19 amendment task BEFORE the Phase 20 new-program task. Specifically, program 19 must be amended to PROC EXPORT `work.key_columns_out`, `work.sheets_out`, and a filtered `work.variables` (md3 rows only) as the three additional CSVs in the same SECTION 12 block.

---

## Code Examples

### ENCRYPTED_MRN normalization (from 03_prep_md3.sas SECTION 2, and CONTEXT.md D-15)

```sas
/* Blank/placeholder test -- apply identically to both CSV and merged-file sides */
%macro is_excluded(col=);
  (missing(&col) or strip(upcase(&col)) = 'NULL')
%mend is_excluded;

/* Applied in cross-check and crosswalk build:
   if %is_excluded(col=ENCRYPTED_MRN) then [exclude row];
*/
```

The md3 prep program (03_prep_md3.sas) confirms md3 has no NULL sentinels (it asserts n_sent = 0 for md3). The `strip(upcase()) = 'NULL'` test is from PREP-02 and is the authoritative normalization rule. Strip() removes leading/trailing blanks. No other transformation is documented in 03_prep_md3.sas for ENCRYPTED_MRN itself.

### Reading Phase 19 CSVs for PID-01 and PID-07

```sas
/* PID-01: read checksum records */
proc import datafile="&qc_path.\19_raw_files.csv"
    out=work.inv_files dbms=csv replace;
  guessingrows=max;
run;

/* PID-07: read key-column flags */
proc import datafile="&qc_path.\19_raw_key_columns.csv"
    out=work.inv_key_cols dbms=csv replace;
  guessingrows=max;
run;

/* PID-07: read sheet metadata */
proc import datafile="&qc_path.\19_raw_sheets.csv"
    out=work.inv_sheets dbms=csv replace;
  guessingrows=max;
run;

/* D-11: read md3 variable metadata */
proc import datafile="&qc_path.\19_raw_variables_md3.csv"
    out=work.inv_vars_md3 dbms=csv replace;
  guessingrows=max;
run;
```

### 00_config.sas addition for crosswalk backup path

```sas
/* ---- Phase 20 / PCM-D-17: crosswalk backup path (P: -- NOT in git, PHI lives here) ---- */
%let xwalk_backup_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\merge\xwalk_backup;
```

This macro variable is added to 00_config.sas in the existing "Data paths (P:)" block and echoed with a `%put NOTE:` line to match the existing convention.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| certutil.exe | PID-01 checksum | Confirmed available (Phase 19 uses it) | Windows built-in | None; required |
| P: drive (raw\master) | PID-01 source CSV | Confirmed (Phase 19 profiled it) | — | None; required |
| P: drive (merge\qc) | All CSV handoffs, text outputs | Confirmed (all prior phases write here) | — | None; required |
| qc/19_raw_files.csv | PID-01 | NOT FOUND (Phase 19 amendment required) | — | None; must exist before program 20 runs |
| qc/19_raw_key_columns.csv | PID-07 | NOT FOUND (Phase 19 amendment required) | — | None; must exist before program 20 runs |
| qc/19_raw_sheets.csv | PID-07 | NOT FOUND (Phase 19 amendment required) | — | None; must exist before program 20 runs |
| qc/19_raw_variables_md3.csv | PID-01 D-11 | NOT FOUND (Phase 19 amendment required) | — | None; must exist before program 20 runs |
| g.master_data_merged | PID-02, PID-03, PID-04, D-14 | Confirmed (Phase 4 complete) | 41,150 rows, 176 cols | None; required |
| g.master_data_harmonized | 10b amendment | Confirmed (Phase 10b complete) | 41,150 rows, 174 cols | None; required |
| XCMD enabled | certutil via PIPE | Confirmed (Phase 19 used it successfully) | — | None |

**Missing dependencies with no fallback:**
- qc/19_raw_files.csv — blocks PID-01 and program 20 execution
- qc/19_raw_key_columns.csv — blocks PID-07
- qc/19_raw_sheets.csv — blocks PID-07 targeted imports
- qc/19_raw_variables_md3.csv — blocks D-11 type/length confirmation

**Required pre-task:** Phase 19 plan amendment to write the three additional CSVs. This is a prerequisite for any program 20 execution, not just planning.

---

## Validation Architecture

Phase 20 is a SAS pipeline phase. There is no automated test framework (no pytest, no jest). Validation follows the pipeline's own assertion-abort pattern (PCM-R-05: every `%abort cancel` inside a named macro).

### Inline assertion gates replace a test suite

| Assertion | Location | Failure mode |
|-----------|----------|-------------|
| Phase 19 CSV existence | Program 20 SECTION 1 | %abort cancel |
| Checksum match (PID-01) | Program 20 SECTION 2 | %abort cancel |
| Max ENCRYPTED_MRN length <= 40 (D-12) | Program 20 SECTION 4 | %abort cancel |
| Cross-check PRECEDE/MRN agreement (D-14) | Program 20 SECTION 5 | %abort cancel |
| PRECEDE -> one MRN (PID-03) | Program 20 SECTION 7 | %abort cancel |
| Xwalk equals backup before append (D-02) | Program 20 SECTION 8 | %abort cancel |
| Backup rows still present after append (D-02) | Program 20 SECTION 8 | %abort cancel |
| Row count unchanged after join (PID-05) | 10b and 16b | %abort cancel |
| Zero blank pecan_ID (PID-05) | 10b and 16b | %abort cancel |
| Zero duplicate pecan_ID per PRECEDE (PID-05) | 10b and 16b | %abort cancel |
| Column count = 175 (10b) | 10b SECTION 6 | %abort cancel |
| Column count = 175 (16b cohort) | 16b SECTION 5 | %abort cancel |
| g.master_data_merged unchanged (176 cols, 41150 rows) | 10b post-run | %abort cancel |
| g.master_data_harmonized unchanged (175 cols, 41150 rows) | 16b post-run | %abort cancel |
| dict_final row count = n_dict_meta + 1 (pecan_ID added) | 08_dictionary.sas _gate5 | %abort cancel |

**Quick run command:** Submit the program in SAS and check the log for `ERROR:` or `NOTE: ==== Phase XX complete ====`. No separate test runner.

**Phase gate:** All inline assertions green + QC text files present at qc/20_linkage_reach.txt, qc/16b_pecan_id_counts.txt before `/gsd:verify-work`.

---

## State of the Art

| Old State | Current State | Impact |
|-----------|---------------|--------|
| g.master_data_harmonized: 174 cols | After 10b amendment: 175 cols (+ pecan_ID) | All col-count assertions in 10b and 16b must update |
| g.analytic_cohort: 174 cols | After 16b amendment: 175 cols (+ pecan_ID) | verify_cohort_cols and assert_harmonized_unchanged in 16b update |
| DATA_DICTIONARY has N rows (from g.master_data_merged) | After 08 amendment: N + 1 rows (pecan_ID added explicitly) | _gate5 assertion must use n_dict_meta + 1 |
| 99_run_all.sas does not include program 19 or 20 | Phase 21 adds them | Phase 20 creates 20_pecan_id.sas but does not wire it to the runner |
| qc/19_raw_files.csv only (Phase 19 current output) | Phase 19 amendment adds 3 more CSVs | Phase 19 must be amended before program 20 runs |

---

## Open Questions

1. **What columns does qc/19_raw_key_columns.csv contain?**
   - What we know: The Phase 19 CONTEXT.md (D-01) mentions writing KEY_COLUMNS sheet to the xlsx workbook. The CSV is described as containing "key-column flags." The planner must verify the column names when the Phase 19 amendment is written.
   - What's unclear: Exact column names (file_id? filename? var_name? is_encrypted_mrn?). The PID-07 loop macro needs these names.
   - Recommendation: The Phase 19 amendment task should document the schema of key_columns in its plan, and the program 20 plan should reference that schema. If planning in parallel, use placeholder column names and note they must match what Phase 19 actually writes.

2. **Naming convention for dated backups (D-04)**
   - What we know: D-04 says "latest dated backup copy." The program must be able to find the latest backup deterministically.
   - What's unclear: Naming scheme (e.g., `pecan_id_xwalk_YYYYMMDD.sas7bdat` vs `pecan_id_xwalk_backup.sas7bdat` overwritten each run vs a fixed "latest" pointer file).
   - Recommendation: Use `pecan_id_xwalk_YYYYMMDD.sas7bdat` with a `%sysfunc(today(), yymmddn8.)` suffix. To find the latest, use a DIR PIPE to list files matching the pattern and take the last one alphabetically (YYYYMMDD sorts correctly). A simpler alternative: always overwrite one file named `pecan_id_xwalk_backup.sas7bdat` — this is sufficient since the comparison is between the live xwalk and the backup, and both are written by program 20 only. The dated-backup intent is primarily for disaster recovery, not versioning. Confirm with Gerard which approach is preferred; dated files are safer.

3. **Is PRECEDE_STUDY_ID in the md3 CSV stored as character or numeric?**
   - What we know: In g.master_data_merged it is `$12`. In the md3 CSV source file, PROC IMPORT may read it as numeric if all values are pure digits.
   - What's unclear: Actual values — do they start with "Precede" (then char is guaranteed) or are they pure numeric?
   - Recommendation: The D-11 step (read qc/19_raw_variables_md3.csv) resolves this. Plan a conditional branch on the type field. The cross-check must cast accordingly. This is already addressed in the decisions.

---

## Sources

### Primary (HIGH confidence)
- Direct read: `sas/19_raw_dir_inventory.sas` — certutil PIPE pattern (SECTION 5), PROC EXPORT CSV handoff (SECTION 12)
- Direct read: `sas/18_supplemental_raw_gap.sas` — PUT-to-fileref text output pattern (SECTION A-6)
- Direct read: `sas/10b_concept_harmonize.sas` — full program structure; SECTION 5 DATA step, SECTION 6 assertions; col-count=174 assertion (line 1082); assert_harmonized_unchanged
- Direct read: `sas/16b_cohort_rebuild.sas` — full program structure; verify_cohort_cols (ne 174); assert_harmonized_unchanged (ne 174/41150); SECTION 5 promotion pattern
- Direct read: `sas/08_dictionary.sas` lines 224-350 — derivation_map structure (DATA step + output), LEFT JOIN to dict_with_owner, n_dict_meta assertion (_gate5), variable count logging
- Direct read: `sas/03_prep_md3.sas` — ENCRYPTED_MRN $40, PRECEDE_STUDY_ID $12, NULL sentinel test (strip/upcase), filename fileref PUT pattern
- Direct read: `sas/04_merge.sas` lines 260-273 — ENCRYPTED_MRN $40 canonical length
- Direct read: `sas/00_config.sas` — all existing macro variable definitions and naming conventions
- File existence check: `qc/19_raw_files.csv`, `qc/19_raw_key_columns.csv`, `qc/19_raw_sheets.csv`, `qc/19_raw_variables_md3.csv` — all NOT FOUND (confirmed by filesystem probe)

---

## Metadata

**Confidence breakdown:**
- Standard stack (SAS patterns): HIGH — all patterns read directly from existing programs
- Architecture (program structure): HIGH — based on codebase reading
- Pitfalls: HIGH (derivation_map JOIN behavior, col-count assertions) — verified by direct code inspection; MEDIUM (md8 performance) — inferred from size description
- Phase 19 CSV absence: HIGH — confirmed by filesystem check

**Research date:** 2026-09-23
**Valid until:** 2026-10-23 (stable codebase; only invalidated if 10b, 16b, or 08 are modified before Phase 20 executes)
