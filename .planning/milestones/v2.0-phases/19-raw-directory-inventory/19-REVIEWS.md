---
phase: 19
reviewers: [human-author]
reviewed_at: 2026-09-23
plans_reviewed: [19-01-PLAN.md, 19-02-PLAN.md]
review_rounds: 2
---

# Cross-AI Plan Review — Phase 19

## Human Author Review

### Summary

Plan 02 is sound. Plan 01 follows CONTEXT.md faithfully in structure, but its code sketches contain several bugs that would stop or silently corrupt the first run. These should be fixed in the plan rather than deferred to Plan 02's debug loop, because several fail silently and would not produce an ERROR line in the SAS log.

### Strengths

- Plan 02 wave/checkpoint structure is correct
- Overall section ordering in Plan 01 matches CONTEXT.md decisions
- INV-06 three-term assertion concept is correct

---

## Bugs That Would Break the Run

### B-01 — Section 4 required-files list is wrong (CRITICAL)

The DATALINES block mixes supplemental files (Induction_Emergent, Precede_Database, COLONOSCOPY) with invented-looking names (2020_2022_PRECEDE_DATABASE_20240402.*). The correct md1–md8 filenames are:

```
md1: 2018_2019_CPT_ROLLUP_X_MASTER_DATASET_20200801.csv
md2: 2018_2019_X_MASTER_DATASET_20200801.csv
md3: 2018_2022_X_MASTER_DATASET_20240402.csv
md4: 2020_CPT_ROLLUP_X_MASTER_DATASET_20210609.csv
md5: 2020_X_MASTER_DATASET_20210519.csv
md6: 2021_X_MASTER_DATASET_20230512.csv
md7: 2022_MASTER_DATASET_20231024.csv
md8: ALL_AIM2_MASTER_DATASET_20210917.xlsx
```

Two related sub-fixes:
- **md3 .xlsx must NOT be on the required list.** Whether that file exists is the open question from PID-01; requiring it would abort the program if it's absent.
- **The executor note pointing at `16_raw_inventory.sas` and `macros_raw_import.sas` as the source of md1–md8 names is wrong** — those programs cover supplemental files. Point the executor at the Phase 1 source list instead.
- The same wrong list is repeated in Section 10, along with an "r1 also md1" guess that must be removed.

### B-02 — &syserr threshold too strict; import warnings flagged as failures (CRITICAL, silent)

The master CSVs emit a "Some character data was lost" transcoding WARNING on import (Base_Procedure_1). This sets `&syserr` to 4. `%if &syserr = 0` then flags the file as `read-failed`, and PID-01's source file is silently lost.

Fix: treat `&syserr <= 4` as success. Record the warning in a separate `import_warning` column (set to the `&sysmsg` value when `&syserr` is 1–4).

### B-03 — One-pass DATA step won't compile (CRITICAL)

`array n_miss_n {*} _temporary_;` is invalid — temporary arrays require an explicit size. Fix:

1. Get numeric and character column counts from `dictionary.columns` into macro variables `&n_num` and `&n_char` before the DATA step.
2. Declare `array n_miss_n {%eval(%sysfunc(max(&n_num,1)))} _temporary_;` — use `max(...,1)` so a file with no numeric (or no character) columns still compiles.

### B-04 — Trailing `stop;` kills the _eof block (CRITICAL)

The `stop;` at the end of the main loop runs on the first iteration, so the `_eof` block never executes and nothing is output. Remove the `stop;`.

### B-05 — FOPEN takes a fileref, not a path (CRITICAL, silent)

`fopen(full_path)` fails silently. `FOPEN` requires a fileref. Fix:

```sas
rc   = filename('_fr_', full_path);
fid  = fopen('_fr_');
/* ... read size and date ... */
rc   = fclose(fid);
rc   = filename('_fr_');   /* clear fileref */
```

As written, every file gets size=. and date="UNKNOWN" without an ERROR in the log.

### B-06 — Section 14 existence check always fails (CRITICAL, silent)

`%sysfunc(fileexist("&qc_path.\19_raw_inventory.xlsx"))` passes the double-quotes as literal characters in the path, so FILEEXIST returns 0 and `%fail_out` fires after a successful run. Fix: drop the quotes inside %sysfunc:

```sas
%if %sysfunc(fileexist(&qc_path.\19_raw_inventory.xlsx)) = 0 %then ...
```

---

## Issues That Would Give Wrong Results

### W-01 — Key-column matching too loose; PHI risk

Bare `MRN`, `ENCOUNTER`, `STUDYID`, and `STUDY_ID` are too broad. A plain MRN column may be an unencrypted MRN; flagging it as ENCRYPTED_MRN would cause PID-07 to compare encrypted and plain values and report a misleading match rate. It is also a PHI signal that should appear separately.

Fix options (pick one):
- Give these loose patterns `match_basis = 'loose'` and a distinct `key_type` value (e.g. `UNENC_MRN`).
- Or normalize strings with `compress(upcase(x), ' _-')` and only promote to the encrypted key type when the column name starts with `ENCRYPTED_`.

### W-02 — Normalize before comparing; drop var_type restriction

Use `compress(upcase(col_name), ' _-')` rather than listing every spelling variant explicitly.

Also remove the `var_type = 'char'` restriction on label matching — `PRECEDE_STUDY_ID` is numeric in md7.

### W-03 — Build VARIABLES from dictionary.columns, then left-join counts

Building VARIABLES inside the `_eof` block means a file with zero rows produces no VARIABLES rows, and `pct_* = n / nobs` divides by zero for non-zero-row files where the _eof block has a bug.

Fix: populate `work.variables` from `dictionary.columns` first (always produces one row per column), then left-join the computed counts in.

Also add a `sheet_name` column to VARIABLES. Without it, variables from different sheets of the same workbook are indistinguishable and appear as duplicates.

### W-04 — D-06 abort-on-required-file-failure not implemented

CONTEXT D-06 states that a required file failing import aborts the run. After the import loop, add an assertion that each of the eight md1–md8 masters has `status = 'profiled'`. If any do not, call `%fail_out`.

---

## Plan 02 — One Addition

### P02-01 — Checkpoint must include COM scouting log review

Plan 01 defers COM scouting to runtime (the executor runs a query and reviews the log). The FAMILIES DATALINES block cannot be approved until someone has looked at that output. The Plan 02 human-verify checkpoint should explicitly include: "Review the COM scouting `proc print` output in the SAS log and confirm the FAMILIES DATALINES prefix list is complete."

---

## Consensus Summary

### Agreed Concerns (all HIGH severity)

1. Five code-level bugs in Plan 01 that fail silently — executor would produce a corrupt or empty workbook without a single ERROR line (B-03, B-04, B-05, B-06, B-02)
2. Wrong md1–md8 filename list in Sections 4 and 10 — run aborts or silently skips required files (B-01)
3. Key-column matching is too broad and creates a PHI classification risk for downstream phases (W-01)

### Agreed Strengths

- Section-by-section structure mirrors CONTEXT.md decisions precisely
- INV-06 three-term assertion and FAMILIES full-join assertion are correctly planned
- Plan 02 wave/checkpoint split is appropriate

### Divergent Views

None — single reviewer.

---

## Human Author Review — Round 2 (post-revision read-through)

### Summary

All Round 1 issues landed correctly. A close read of the revised code sketches reveals five further problems: three that break the run and two that produce wrong results, plus three smaller correctness issues.

---

## Bugs That Would Break the Run

### R2-B-01 — `=:` operator invalid in PROC SQL (CRITICAL)

Section 8 key-column query uses `upcase(var_name) =: 'ENCRYPTED_MRN'`. The `=:` starts-with operator is valid in DATA step `WHERE` clauses but **PROC SQL rejects it** — syntax error, run stops.

Fix: use `eqt` (sounds-like/starts-with in SQL context is not the right operator — use `upcase(var_name) like 'ENCRYPTED_%'` is tempting but `_` is a wildcard in LIKE). The correct replacement is to test the prefix explicitly:

```sas
substr(upcase(compress(var_name,' _-')), 1, 9) = 'ENCRYPTED'
```

or use `index(upcase(var_name), 'ENCRYPTED_') = 1`. Either avoids the invalid `=:` and avoids the LIKE `_` wildcard problem.

### R2-B-02 — `&dsname_&sheetnum` resolves wrong macro variable (CRITICAL, silent)

In Section 6's xlsx import branch, `&dsname_&sheetnum` causes SAS to look for a macro variable named `dsname_` (which doesn't exist), so the reference resolves to blank and every sheet copy fails silently — every workbook including md8 comes out `read-failed`, and `%assert_masters_profiled` then aborts the run.

Fix: `&dsname._&sheetnum` — the period terminates the first macro variable name before the underscore.

### R2-B-03 — PROC PRINT output does not go to the SAS log (CRITICAL)

The COM scouting step uses `PROC PRINT` and `%route_log` only redirects the log channel. Plan 02 both greps the log for "COM scouting" and asks the reviewer to find the list there — neither works if PROC PRINT goes to the ODS output destination instead.

Fix (pick one):
- Replace `PROC PRINT` with a `DATA _null_; set work.com_scout; put var_name=; run;` so output lands in the log.
- Or write to a separate `COM_SCOUTING` sheet in the ODS Excel workbook and update the Plan 02 checkpoint to direct the reviewer there instead of the log.

---

## Issues That Would Give Wrong Results

### R2-W-01 — `ENCOUNTERID` and `STUDYID`/`STUDY_ID` violate the W-01 rule

The plan maps `ENCOUNTERID` → `ENCRYPTED_ENCOUNTER` and `STUDYID`/`STUDY_ID` → a study-ID key type, but W-01 (from Round 1) says: only promote to an `ENCRYPTED_*` key type when the column name starts with `ENCRYPTED_`. `ENCOUNTERID` does not start with `ENCRYPTED_` — it should be `UNENC_ENCOUNTER` with `match_basis = 'loose'`. Similarly `STUDYID`/`STUDY_ID` could belong to another study; classify as `match_basis = 'loose'` rather than `match_basis = 'name'`.

### R2-W-02 — Required-file presence check doesn't restrict to `raw\master\`

Section 4 checks that each md1–md8 filename appears somewhere under `raw` (the full recursive listing). If a copy of the md3 CSV sits in another subfolder, the check passes even though the canonical copy in `raw\master\` may be absent. PID-01 would then find two `FILES` rows for md3 and could pick the wrong checksum.

Fix: require the `path` column to contain `\master\` (or the canonical subdirectory). Also assert exactly one `FILES` row per required file — not just ≥1.

---

## Smaller Correctness Fixes

### R2-S-01 — `&sysmsg` is not where PROC IMPORT warnings land

`&sysmsg` holds the most recent system message, not the PROC IMPORT warning text. The transcoding warning ends up in `&syswarningtext`. Use `&syswarningtext` to fill the `import_warning` column.

### R2-S-02 — `&syscc` stays at 4 after a warning-only import

After a `syserr le 4` warning branch, `&syscc` remains 4. A clean run with only transcoding warnings exits with code 1, which RUN-01 (or a calling script) may interpret as failure. Either reset `%let syscc = 0;` in the warning branch (same pattern D-06 prescribes for read-failed), or document that RUN-01 must treat exit code 1 as success for this program.

### R2-S-03 — Zero-row dataset: `nobs` comes out missing, not 0

When a dataset has zero rows, `open()`/`attrn()` returns `.` (missing) for nobs rather than `0`. Any arithmetic on it propagates missing into `pct_missing` and `pct_sentinel`. Wrap with `coalesce(m_nobs.nobs, 0)` (or the equivalent `ifn(nobs=., 0, nobs)`) wherever nobs is used in the FILES and VARIABLES counts.

---

## Consensus Summary (Round 2)

### Agreed Concerns (HIGH severity)

1. `=:` in PROC SQL is a syntax error — run stops immediately at the key-column query (R2-B-01)
2. `&dsname_&sheetnum` resolves to blank — all workbooks silently read-failed, abort fires (R2-B-02)
3. PROC PRINT in the COM scouting step doesn't reach the log — Plan 02 checkpoint can't be completed (R2-B-03)

### Agreed Strengths

- All Round 1 fixes verified present
- assert_masters_profiled, B04-NOSTOP-VERIFIED, r1-r9 DATALINES, /a-d flag, fileref FOPEN pattern all confirmed in plan text

### Divergent Views

None — single reviewer.
