# Phase 29: Gap-Fill Wiring (r1-r6) — Research

**Researched:** 2026-10-07
**Domain:** SAS 9.4 DATA step merge gap-fill, PROC COMPARE snapshot guard, pcnr map extension
**Confidence:** HIGH — all findings from direct codebase reads; no external sources needed

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01 — Column Selection (two-stage)**
Two-stage rule:
1. Automatic prefilter: column passes if (a) not already in `g.master_data_merged`, (b) fill rate >= threshold, (c) not an ID/key column
2. Human allowlist: Gerard reviews and approves final column set before wiring

Reuse check: if `D15_APPROVED=1` and `qc/18_gap_candidates.txt` was generated from unchanged source file SHAs, check for an existing approved column list before re-reviewing.

Source files:
- r1: `P:\PeCAN Master Data\Gerard\raw\2018_2019_2020_Induction_Emergent20231121.csv`
- r2: `P:\PeCAN Master Data\Gerard\raw\2018_2019_Precede_Database.xlsx` (14,807 rows)
- r3: `P:\PeCAN Master Data\Gerard\raw\2018_2022_COLONOSCOPY_20240118.xlsx`
- r4: `P:\PeCAN Master Data\Gerard\raw\2020_Precede_Database_Edu.xlsx` (7,696 rows)
- r5: `P:\PeCAN Master Data\Gerard\raw\2021_Education_20240124.csv`
- r6: `P:\PeCAN Master Data\Gerard\raw\2021_Frailty_20240123.csv`

**D-02 — Fan-Out Risk (BLOCKER)**
r1 (+3 rows), r2 (+29 rows), r4 (+1 row) have duplicate PRECEDE_STUDY_IDs relative to their cohort sizes. Prep program must detect duplicates and `%abort cancel` (inside named macro) if any remain after de-dup rule is applied. De-dup rule per file must be documented in DECISIONS.md before the merge block runs.

**D-03 — Wiring Architecture**
- Step 1: new program `sas/03r_prep_gapfill.sas` — imports r1-r6, normalizes key, applies de-dup, keeps PRECEDE_STUDY_ID + approved columns only
- Step 2: new gap-fill block in `sas/04_merge.sas` adjacent to MRG-06 — left join from `g.master_data_merged` to each prepared work dataset; COALESCE / conditional assignment only (no overwrites); row-count assertion after each join stays at 41,150; r7/r8/r9 skipped with comment citing PCM-D-28
- NOT a post-merge program (would require new dataset name or in-place rewrite, both forbidden)

**D-04 — pcnr Map and Sentinel Entries**
Auto-generate candidate rows (same pattern as program 23). Gate flag blocks program 24 if any wired column lacks a map entry with PCNR_APPROVED=1. Column-count assertions in programs 23 (175) and 24 (163) updated to reflect new totals.

**D-05 — Pre-Change Snapshot and PROC COMPARE**
```sas
libname snap "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\snap";
proc copy in=g out=snap;
  select master_data_merged master_data_harmonized;
run;
```
PROC COMPARE: `base=snap.master_data_merged compare=g.master_data_merged`, `id PRECEDE_STUDY_ID`, restrict variable list to original columns, assert `%eval(&sysinfo & 4096) = 0` (bit 12 = value differences). Repeat for `master_data_harmonized`.

### Claude's Discretion

- Exact fill-rate threshold for D-01 prefilter (user suggested 5% as example)
- Macro layout and section numbering within `03r_prep_gapfill.sas`
- Whether PROC COMPARE step lives in standalone program or as final section of the wiring program
- Exact de-dup rules for r1, r2, r4 — planner surfaces duplicates, Gerard approves

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| GAP-01 | Extension-column gap candidates from D15_APPROVED list for r1-r6 are wired into the base merge; r7-r9 remain excluded per PCM-D-28 | `sas/18_supplemental_raw_gap.sas` Section B call list confirmed for r1-r6; r7/r8/r9 are in the same file but will be skipped in the merge block with a comment |
| GAP-02 | `docs/pcnr_name_map.csv` and `docs/sentinel_decisions.csv` extended to cover new columns; column-count assertions updated (currently 175 and 163) | Assertion locations confirmed: program 24 line ~919 (163), fingerprint read line ~97 (175); name map schema confirmed from file header |
| GAP-03 | PROC COMPARE of pre-change vs post-change copies; both datasets remain at 41,150 rows; existing columns byte-identical before and after | `snap` libname pattern not yet in codebase — must be introduced; `&sysinfo & 4096` assertion pattern defined in CONTEXT.md D-05 |
</phase_requirements>

---

## Summary

Phase 29 wires approved extension columns from six supplemental raw files (r1-r6) into `g.master_data_merged` and extends the pcnr documentation infrastructure. The codebase is mature and provides a complete template for every step: `sas/18_supplemental_raw_gap.sas` already imports all six files and runs gap-fill counts; `sas/04_merge.sas` contains the MRG-06 md8 gap-fill block that is the direct architectural template; programs 23 and 24 show the pcnr candidate-generation and gate patterns.

The critical blocker before any merge code runs is duplicate PRECEDE_STUDY_ID resolution for r1, r2, and r4. Each has more rows than its cohort. A plain left join without de-dup would fan out `g.master_data_merged` beyond 41,150 rows, violating GAP-03. De-dup rules must be proposed by the planner and approved by Gerard, then documented in DECISIONS.md.

The `snap` libname for the PROC COMPARE snapshot is a new concept in the pipeline — no existing program uses it. The directory `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\snap` must be created before the wiring program runs, and the `snap` libname must be introduced in the program or a config extension.

**Primary recommendation:** Build in three plans — (1) column allowlist + de-dup investigation (human checkpoint), (2) prep program `03r_prep_gapfill.sas` + merge block in `04_merge.sas`, (3) PROC COMPARE verification + pcnr map extension + assertion updates.

---

## Standard Stack

No new libraries or packages. This is a pure SAS 9.4 codebase using existing infrastructure:

| Asset | Current State | Purpose in Phase 29 |
|-------|--------------|---------------------|
| `sas/macros_raw_import.sas` | `%import_csv`, `%import_xlsx` macros | Import r1-r6 in `03r_prep_gapfill.sas` |
| `sas/04_merge.sas` | MRG-06 block (lines ~242-478) | Template for gap-fill merge block |
| `sas/18_supplemental_raw_gap.sas` | Sections B-C, lines ~676-987 | Template for key normalization per file |
| `sas/00_config.sas` | `D15_APPROVED=1`, path macros | Gate flag; `&raw_path`, `&g_path`, `&qc_path` |
| `docs/pcnr_name_map.csv` | 10-column schema, 175 rows | Extended with new column entries |
| `docs/sentinel_decisions.csv` | 16-column schema | Extended with new column entries |
| `sas/23_pcnr_inventory.sas` | SECTION 8 completeness assertion | Re-run after wiring; column count updates |
| `sas/24_pcnr_build.sas` | Column-count assertion = 163 (line ~919) | Must update to 163 + N_new_cols |

---

## Architecture Patterns

### Pattern 1: md8_donors / MRG-06 Template (direct reuse)

The md8 gap-fill in `04_merge.sas` is the authoritative template for the r1-r6 merge block. Key structure:

```sas
/* Step 1: build donor dataset in WORK with renamed columns to avoid PDV collision */
data work.r1_donors;
  set work.r1_prepped (keep=PRECEDE_STUDY_ID col_a col_b ...
                       rename=(col_a=_r1_col_a col_b=_r1_col_b ...));
run;
proc sort data=work.r1_donors; by PRECEDE_STUDY_ID; run;

/* Step 2: inside the g.master_data_merged DATA step, after existing MERGE statement */
/* MRG-06-r1 / PCM-D-15: r1 gap-fill */
if missing(col_a) then col_a = _r1_col_a;
if missing(col_b) then col_b = _r1_col_b;
drop _r1_:;
```

However, for Phase 29 the CONTEXT.md D-03 decision specifies adding the block to `04_merge.sas` rather than a post-merge program. The DATA step in `04_merge.sas` already writes `g.master_data_merged` directly (line ~261), so the r1-r6 donors must be pre-built work datasets added to the MERGE statement list, following the exact md8_donors pattern.

**Key constraint:** The DATA step `data g.master_data_merged` is a single DATA step. New donor datasets must be added to the MERGE statement and new conditional assignments must be added after the existing MRG-06 block. The `drop _r1_: _r2_: ...;` pattern must cover all working-storage columns.

### Pattern 2: Key Normalization per File (from `%gap_file`)

Confirmed key types and dataset naming from `sas/18_supplemental_raw_gap.sas` lines 676-731:

| File ID | fname | Import macro | Key column | Work dataset | Key type |
|---------|-------|-------------|-----------|-------------|----------|
| r1 | `2018_2019_2020_Induction_Emergent20231121.csv` | `%import_csv` | `PRECEDE_Study_ID` | `work.r1` | char (normalize to $12) |
| r2 | `2018_2019_Precede_Database.xlsx` | `%import_xlsx` | `studyid` | `work.r2_s1` | char (normalize to $12) |
| r3 | `2018_2022_COLONOSCOPY_20240118.xlsx` | `%import_xlsx` | `PRECEDE_Study_ID` | `work.r3_s1` | char (normalize to $12) |
| r4 | `2020_Precede_Database_Edu.xlsx` | `%import_xlsx` | `studyid` | `work.r4_s1` | numeric — use `strip(put(studyid, best32.))` then prepend `Precede` prefix |
| r5 | `2021_Education_20240124.csv` | `%import_csv` | `PRECEDE_Study_ID` | `work.r5` | char (normalize to $12) |
| r6 | `2021_Frailty_20240123.csv` | `%import_csv` | `PRECEDE_Study_ID` | `work.r6` | char (normalize to $12) |

**r4 numeric key pattern** (from `%gap_file` normalization in program 18, line ~412):
```sas
_k = strip(cats(studyid));
if substr(_k, 1, 7) ne 'Precede' then _k = 'Precede' || _k;
```
For the prep program, the final `PRECEDE_STUDY_ID` character variable for r4 must be built as:
```sas
length PRECEDE_STUDY_ID $12;
PRECEDE_STUDY_ID = 'Precede' || strip(put(studyid, best32.));
```

**r2 key column is `studyid` (not `PRECEDE_Study_ID`).** This is confirmed at line 731 in program 18. The prep program must rename/derive PRECEDE_STUDY_ID from studyid for both r2 and r4.

### Pattern 3: Duplicate Detection and Abort (from CONTEXT.md D-02)

The prep program must check for duplicates per file and abort before producing the cleaned work dataset:

```sas
%macro check_no_dups(ds=, label=);
  proc sort data=&ds out=work._dedup_check nodupkey dupout=work._dups_&label;
    by PRECEDE_STUDY_ID;
  run;
  %let _ndups = 0;
  proc sql noprint;
    select count(*) into :_ndups trimmed from work._dups_&label;
  quit;
  %if &_ndups > 0 %then %do;
    %fail_out(msg=&label has &_ndups duplicate PRECEDE_STUDY_ID rows -- de-dup rule required before merge);
  %end;
%mend check_no_dups;
```

De-dup rules (to be proposed in Plan 1 for Gerard's approval, then documented in DECISIONS.md):
- r1 (3 excess rows): unknown — requires review of which PRECEDE_STUDY_IDs are duplicated
- r2 (29 excess rows): unknown — requires review; r2 is extremely wide (~3,984+ columns), duplicates likely re-entries or split encounters
- r4 (1 excess row): unknown — single duplicate; likely safe to keep-first by sort order, but requires Gerard approval

### Pattern 4: PROC COMPARE Snapshot (`snap` libname — new pattern)

No existing program uses a `snap` libname. It must be introduced. The directory must exist on the P: drive outside the `g` library:

```sas
/* Create snap directory if not present -- use DCREATE */
%macro ensure_snap_dir;
  %if %sysfunc(fileexist("&snap_path")) = 0 %then %do;
    %let _rc = %sysfunc(dcreate(snap, "&source_path"));
    %if &_rc = 0 %then
      %fail_out(msg=Could not create snap directory at &snap_path);
  %end;
%mend ensure_snap_dir;

libname snap "P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\snap";

proc copy in=g out=snap;
  select master_data_merged master_data_harmonized;
run;
```

PROC COMPARE check (from CONTEXT.md D-05):
```sas
proc compare base=snap.master_data_merged
             compare=g.master_data_merged
             noprint;
  id PRECEDE_STUDY_ID;
  var &original_col_list;  /* derived from snap.master_data_merged dictionary */
run;
%macro assert_no_value_diffs;
  %if %eval(&sysinfo & 4096) ne 0 %then %do;
    %fail_out(msg=PROC COMPARE found value differences in original columns -- GAP-03 FAILED);
  %end;
%mend assert_no_value_diffs;
%assert_no_value_diffs;
```

`&original_col_list` is derived at runtime from `dictionary.columns` on `snap.master_data_merged` before wiring.

**sysinfo bit 4096 meaning:** This bit is set when PROC COMPARE finds value differences between the base and compare datasets. The assertion `%eval(&sysinfo & 4096) = 0` means zero value differences — pass. Other bits (e.g., bit 1 = datasets differ in number of observations, bit 8 = variables not in both datasets) may be non-zero when new columns exist in the compare dataset; those are expected and not failures.

### Pattern 5: pcnr Map Auto-Generation for New Columns

Program 23 generates candidate rows for every column in `g.master_data_harmonized` via `dictionary.columns`. After wiring adds N new columns, program 23 is re-run. The new columns appear automatically in the draft output.

The gate pattern in program 24 reads `docs/pcnr_name_map.csv` and checks that every column in `g.master_data_harmonized` has an entry with PCNR_APPROVED=1 (via the fingerprint check at SECTION 0, line ~97, which asserts `nvars=175`). After wiring, this fingerprint will fail until program 23 is re-run and the new map entries are approved and committed. The planner must sequence: wire → re-run 23 → Gerard approves new rows → update fingerprint assertion → re-run 24.

**Column-count assertion locations to update:**
- `sas/24_pcnr_build.sas` line ~919: `%if &n_pcnr_cols ne 163` — update to `163 + N_new_pcnr_cols`
- `sas/24_pcnr_build.sas` line ~1003: `%let n_typelen_mismatch = %eval(&n_typelen_mismatch + (&n_typelen_matched ne 163))` — update same
- `sas/24_pcnr_build.sas` line ~1084: log NOTE `(163 cols, 41150 rows)` — update
- `sas/24_pcnr_build.sas` line ~1244: second column count check = 163 — update
- `sas/23_pcnr_inventory.sas` fingerprint file `qc/23_sentinel_fingerprint.txt` will update automatically when program 23 is re-run; the hardcoded `nobs=41150 nvars=175` comment at line 97 in program 24 is a comment only — the live check reads the file

### Anti-Patterns to Avoid

- **data g.master_data_merged; set g.master_data_merged;** — PCM-T-02 in-place rewrite, destroys the dataset if the session aborts mid-step
- **PROC SQL UPDATE** — PCM-T-01, silent truncation
- **%abort cancel in open code** — PCM-R-05: must be inside a named macro
- **open-code %IF/%THEN** — PCM-T-15: must be inside a %macro...%mend
- **bare `%let` inside a macro** — macro-local only; path macros must be set via `%include` in open code
- **%import_csv / %import_xlsx re-defined** — these macros live in `macros_raw_import.sas`; never copy them into `03r_prep_gapfill.sas`, only `%include` the shared file
- **Overwriting existing column values** — gap-fill is one-directional: `if missing(col) then col = _rN_col;` never a bare assignment

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| CSV import | DATA step infile with hardcoded columns | `%import_csv` from `macros_raw_import.sas` (PCM-T-16 compliant) |
| XLSX import | PROC IMPORT | `%import_xlsx` from `macros_raw_import.sas` |
| Key normalization | Custom logic | Reuse `_k = strip(cats(key)); if substr(_k,1,7) ne 'Precede' then _k = 'Precede' || _k;` from `%gap_file` |
| Dataset copy for snapshot | `data snap.x; set g.x;` | `proc copy in=g out=snap; select ...;` (PCM-T-02 safe) |
| Column existence check | Manual list | `dictionary.columns` query at runtime |
| Abort with message | `%abort cancel;` in open code | `%macro fail_out(msg=); ... %abort cancel; %mend;` then call it |

---

## Program 18 Section B — What Is Already Done

Key confirmed facts from direct code read:

1. `D15_APPROVED = 1` is already set in `sas/00_config.sas` (line 48). Section C gate passes.

2. All six r1-r6 files are already in the `%gap_file` call list (lines 676-731 of `18_supplemental_raw_gap.sas`). Program 18 has already run and `qc/18_gap_candidates.txt` should exist on the P: drive.

3. r2 has special post-processing: divider columns excluded, paper_neuropsych and dCDT families rolled up. The approved column list for r2 must come from the `work.r2_new_nondiv` rows with `family = ''` (individual, unfamilied NEW columns) or explicit family-level approval by Gerard.

4. **PACU_STAY file is NOT in program 18's `%gap_file` call list.** The current call list covers r1, r3, r4, r5, r6, r9, r7, r8, r2 — nine files. `2018-2022_PACU_STAY` (41,423 rows) is not called. CONTEXT.md notes it as "not in the current Section B call list." It is NOT a Phase 29 candidate unless Gerard explicitly adds it. The planner should flag it as out-of-scope for this phase.

5. r9, r7, r8 are also in program 18's call list (for diagnostic purposes) but are excluded from Phase 29 wiring per PCM-D-28.

---

## Duplicate Row Investigation

Known excess rows (from CONTEXT.md D-02):

| File | Total rows | Cohort N | Excess |
|------|-----------|---------|--------|
| r1 (2018_2019_2020_Induction_Emergent) | 22,476 | 22,473 (md8) | 3 |
| r2 (2018_2019_Precede_Database.xlsx) | 14,807 | 14,778 (2018-19 cohort) | 29 |
| r4 (2020_Precede_Database_Edu.xlsx) | 7,696 | 7,695 (2020 cohort) | 1 |

**The specific duplicate PRECEDE_STUDY_IDs are not accessible in the git repo** (all `.sas7bdat` and `.xlsx` files are gitignored). They exist only on the P: drive. Plan 1 must include a SAS step that identifies and prints the specific duplicate IDs from each file so Gerard can assign a de-dup rule. The pattern from `%gap_file` (line ~416) writes dups to `work._dup_&rid` — this output can be directed to a QC file.

Suggested approach for Plan 1: a standalone diagnostic program that imports r1, r2, r4, runs PROC SORT NODUPKEY with DUPOUT=, prints the duplicate IDs to `qc/29_dup_candidates.txt`, and aborts. Gerard reviews and records de-dup rules in DECISIONS.md. Plan 2 then implements the rules in `03r_prep_gapfill.sas`.

---

## Common Pitfalls

### Pitfall 1: Fan-Out from Undeduplicated Join
**What goes wrong:** A source file with 22,476 rows left-joined to `g.master_data_merged` (41,150 rows) on a non-unique key adds rows wherever the key matches multiple source records, producing a dataset with more than 41,150 rows. This silently corrupts `g.master_data_merged`.
**Why it happens:** SAS DATA step MERGE BY is not a SQL join — it is a BY-group merge where a many:one match is fine but a one:many match fans out output rows.
**How to avoid:** Assert unique keys in the prep work dataset BEFORE the merge block. `%abort cancel` if any duplicate remains.
**Warning signs:** Row-count assertion after `data g.master_data_merged` fails with N > 41,150.

### Pitfall 2: r2 Key Column Is `studyid`, Not `PRECEDE_Study_ID`
**What goes wrong:** The prep program looks for `PRECEDE_Study_ID` in `work.r2_s1` and finds it missing, causing an import error or an empty join.
**Why it happens:** r2 and r4 both use `studyid` as their key column (confirmed in `%gap_file` calls at lines 688 and 731 of program 18). This differs from r1/r3/r5/r6.
**How to avoid:** In `03r_prep_gapfill.sas`, derive `PRECEDE_STUDY_ID $12` from `studyid` for r2 and r4 before the merge.
**Warning signs:** n_matched = 0 for r2 or r4 after the inner join.

### Pitfall 3: r4 Numeric Key Requires `best32.` Rendering + Prefix
**What goes wrong:** `strip(cats(studyid))` on a numeric key gives `123456` (no prefix). Base IDs are `PrecedeXXXXXX`. The join produces zero matches.
**Why it happens:** r4's `studyid` is numeric; the base `PRECEDE_STUDY_ID` is char $12 with a `Precede` prefix.
**How to avoid:** `PRECEDE_STUDY_ID = 'Precede' || strip(put(studyid, best32.));`

### Pitfall 4: `snap` Directory Not Created Before PROC COPY
**What goes wrong:** `proc copy in=g out=snap;` fails with "libname snap not found" or "directory does not exist."
**Why it happens:** The `snap` libname and its backing directory do not exist in the current pipeline.
**How to avoid:** Plan 3 must include a precondition check that creates the directory (via `%sysfunc(dcreate(...))`) and assigns the libname before PROC COPY runs.

### Pitfall 5: sysinfo Bit Misinterpretation
**What goes wrong:** The PROC COMPARE assertion fails spuriously because sysinfo bit 1 (row count difference) or bit 8 (unequal variable lists) is set — which is EXPECTED when new columns exist in the compare dataset.
**Why it happens:** New columns appear only in `g.master_data_merged` (compare), not in `snap.master_data_merged` (base). PROC COMPARE sets bit 8 for "variables not in both."
**How to avoid:** The VAR statement in PROC COMPARE must explicitly list only the ORIGINAL columns (from `snap.master_data_merged`). This restricts the comparison to pre-existing columns only and prevents bit 8 from firing. Derive the var list from `dictionary.columns where libname='SNAP' and memname='MASTER_DATA_MERGED'` before wiring.

### Pitfall 6: Fingerprint File Mismatch Blocks Program 24
**What goes wrong:** After wiring adds N new columns to `g.master_data_merged` and `g.master_data_harmonized`, program 24's gate reads `qc/23_sentinel_fingerprint.txt` and finds `nvars=175` but the live dataset now has `175 + N` variables. Gate aborts.
**Why it happens:** Program 23 must be re-run after wiring to regenerate the fingerprint file with the new column count.
**How to avoid:** The plan sequence must include: (1) wire, (2) re-run program 23 (regenerates fingerprint), (3) Gerard approves new map entries, (4) commit updated `docs/pcnr_name_map.csv` and `docs/sentinel_decisions.csv`, (5) update column-count assertions in program 24, (6) re-run program 24.

### Pitfall 7: `%import_xlsx` Produces Multiple Sheet Datasets
**What goes wrong:** `%import_xlsx(r2, ...)` produces `work.r2_s1`, `work.r2_s2`, etc. for each sheet. If r2 has a second sheet (e.g., a data dictionary tab), `work.r2_s2` is imported as well.
**Why it happens:** `%import_xlsx` iterates ALL sheets via `dictionary.tables` on the XLSX libname.
**How to avoid:** In `03r_prep_gapfill.sas`, always reference `work.r2_s1` (and `work.r3_s1`, `work.r4_s1`) explicitly — the first sheet is the data sheet. Verify that `work.r2_s1` is the correct sheet during Plan 1 diagnostic.

---

## Code Examples

### Building a prep work dataset (r1 example — char key)
```sas
/* Source: sas/18_supplemental_raw_gap.sas %gap_file + 04_merge.sas md8_donors pattern */
%include "&sas_path.\macros_raw_import.sas";
%import_csv(r1, 2018_2019_2020_Induction_Emergent20231121.csv)

data work.r1_prepped;
  set work.r1 (keep=PRECEDE_Study_ID col_approved_1 col_approved_2 ...);
  length PRECEDE_STUDY_ID $12;
  /* Normalize key -- strip prefix if needed; base IDs are already Precede-prefixed */
  PRECEDE_STUDY_ID = strip(cats(PRECEDE_Study_ID));
  drop PRECEDE_Study_ID;
run;

/* De-dup per approved rule (recorded in DECISIONS.md) */
proc sort data=work.r1_prepped nodupkey dupout=work._r1_dup_check;
  by PRECEDE_STUDY_ID;
run;

%macro r1_dup_gate;
  %let _r1_dups = 0;
  proc sql noprint;
    select count(*) into :_r1_dups trimmed from work._r1_dup_check;
  quit;
  %if &_r1_dups > 0 %then %do;
    %fail_out(msg=r1 still has &_r1_dups duplicate PRECEDE_STUDY_ID rows after de-dup -- resolve before merge);
  %end;
%mend r1_dup_gate;
%r1_dup_gate;
```

### Building a prep work dataset (r4 example — numeric key)
```sas
/* Source: sas/18_supplemental_raw_gap.sas %gap_file line ~412 + CONTEXT.md D-03 */
%import_xlsx(r4, 2020_Precede_Database_Edu.xlsx)

data work.r4_prepped;
  set work.r4_s1 (keep=studyid col_approved_x ...);
  length PRECEDE_STUDY_ID $12;
  PRECEDE_STUDY_ID = 'Precede' || strip(put(studyid, best32.));
  drop studyid;
run;
```

### Merge block extension in `04_merge.sas` (structure)
```sas
/* Source: 04_merge.sas lines 242-478 md8_donors pattern -- CONTEXT.md D-03 */

/* Pre-build donor datasets (outside the DATA step, same as work.md8_donors) */
data work.r1_donors;
  set work.r1_prepped (rename=(col_approved_1=_r1_col1 col_approved_2=_r1_col2));
run;
proc sort data=work.r1_donors; by PRECEDE_STUDY_ID; run;

/* ... repeat for r2, r3, r4, r5, r6 ... */

/* Inside data g.master_data_merged -- add to existing MERGE statement: */
/*   work.r1_donors work.r2_donors ... work.r6_donors                  */
/* After existing MRG-06 block: */

/* MRG-06-r1 / PCM-D-15: r1 extension gap-fill */
/* r7/r8/r9 EXCLUDED -- PCM-D-28: no ENCRYPTED_MRN crosswalk available */
if missing(col_approved_1) then col_approved_1 = _r1_col1;
if missing(col_approved_2) then col_approved_2 = _r1_col2;
drop _r1_: _r2_: _r3_: _r4_: _r5_: _r6_:;
```

### Row-count assertion after merge (same pattern as program 04)
```sas
/* Source: 04_merge.sas existing assertion pattern */
%let _n_merged = 0;
proc sql noprint;
  select count(*) into :_n_merged trimmed from g.master_data_merged;
quit;

%macro assert_row_count;
  %if &_n_merged ne 41150 %then %do;
    %fail_out(msg=Row count assertion FAILED -- g.master_data_merged has &_n_merged rows, expected 41150 -- fan-out detected);
  %end;
%mend assert_row_count;
%assert_row_count;
```

### PROC COMPARE with original-column restriction
```sas
/* Source: CONTEXT.md D-05 */

/* Build original column list from snap (before wiring) */
proc sql noprint;
  select name into :_orig_cols separated by ' '
  from dictionary.columns
  where libname='SNAP' and memname='MASTER_DATA_MERGED'
    and upcase(name) ne 'PRECEDE_STUDY_ID';  /* ID handled by ID statement */
quit;

proc compare base=snap.master_data_merged
             compare=g.master_data_merged
             noprint;
  id PRECEDE_STUDY_ID;
  var &_orig_cols;
run;

%macro assert_no_value_diffs;
  %if %eval(&sysinfo & 4096) ne 0 %then %do;
    %fail_out(msg=GAP-03 FAILED -- PROC COMPARE found value differences in original columns of master_data_merged);
  %end;
%mend assert_no_value_diffs;
%assert_no_value_diffs;
```

---

## Project Constraints (from CLAUDE.md)

- SAS 9.4M8 on Windows; session encoding not UTF-8
- Read-only on `master_data_1..8.sas7bdat` and everything under `raw\master`
- No PHI in git: `.gitignore` excludes `*.sas7bdat`, `*.xlsx`, `*.csv`, `data/` tree
- UF colors on visual deliverables (not applicable to this phase — no ODS output)
- PCM-T-01: no PROC SQL UPDATE
- PCM-T-02: no `data X; set X;`
- PCM-T-05: single ownership per variable
- PCM-T-15: no open-code `%IF`
- PCM-T-16: no PROC IMPORT for gate/decision files (but PROC IMPORT for raw data CSV/XLSX is the standard pattern via `%import_csv`/`%import_xlsx`)
- PCM-R-05: `%abort cancel` only inside named macros
- GSD Workflow Enforcement: use `/gsd:execute-phase` for file changes

---

## Environment Availability

Step 2.6: SKIPPED for the SAS programs themselves (no new external tools). The `snap` directory on P: is the only new filesystem dependency and must be created as part of Plan 3 before PROC COPY runs.

| Dependency | Required By | Available | Notes |
|------------|------------|-----------|-------|
| `P:\...\snap\` directory | GAP-03 PROC COPY | Unknown — must be created | `%sysfunc(dcreate(...))` in program or manual pre-step |
| `qc/18_gap_candidates.txt` | D-01 column review | Exists on P: (D15_APPROVED=1 confirmed) | Gitignored; Gerard reviews on P: drive |
| r1-r6 raw files on P: | `03r_prep_gapfill.sas` | Confirmed present (program 18 ran) | Gitignored |

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | SAS assertions via `%assert_eq` / `%fail_out` macros (PCM-R-05 pattern) |
| Config file | `sas/00_config.sas` |
| Quick run command | `sas.exe "C:\Master_Renamed_same_format_accross\sas\03r_prep_gapfill.sas"` |
| Full suite command | `run_pipeline.cmd` (all programs end-to-end) |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command |
|--------|----------|-----------|-------------------|
| GAP-01 | r1-r6 extension columns appear in `g.master_data_merged`; r7-r9 absent | assertion in `03r_prep_gapfill.sas` + merge block | `sas.exe 04_merge.sas` |
| GAP-02 | Every new column has entry in `docs/pcnr_name_map.csv` with PCNR_APPROVED=1 | program 24 gate check (Section 0) | `sas.exe 24_pcnr_build.sas` |
| GAP-03 | PROC COMPARE sysinfo bit 4096 = 0; row count = 41,150 | `%assert_no_value_diffs` + `%assert_row_count` in wiring/compare step | standalone compare program |

### Wave 0 Gaps

- [ ] `sas/03r_prep_gapfill.sas` — new file, does not exist yet; covers GAP-01 and GAP-02 partially
- [ ] Snap directory creation step — needed before Plan 3 can run

---

## Open Questions

1. **What are the specific duplicate PRECEDE_STUDY_IDs in r1, r2, and r4?**
   - What we know: r1 has 3 excess rows, r2 has 29, r4 has 1
   - What's unclear: which IDs are duplicated; whether they are split encounters, re-entries, or data errors
   - Recommendation: Plan 1 includes a diagnostic SAS step that identifies and writes the duplicate IDs to `qc/29_dup_candidates.txt`; Gerard assigns a de-dup rule per file; rules documented in DECISIONS.md before Plan 2 proceeds

2. **What columns from `qc/18_gap_candidates.txt` does Gerard want to approve for r1-r6?**
   - What we know: D15_APPROVED=1 means Gerard reviewed and approved the gap-fill analysis; but the approved COLUMN LIST may not have been recorded in a docs/ artifact
   - What's unclear: whether a prior approved column list exists in git history or docs/
   - Recommendation: Plan 1 searches git history for any prior `docs/` artifact naming approved gap-fill columns; if none, presents the `qc/18_gap_candidates.txt` NEW column rows (bucket='NEW', pct_raw_populated >= threshold) filtered for r1-r6 as a review list

3. **Is `2018-2022_PACU_STAY` (41,423 rows) in scope for Phase 29?**
   - What we know: it is NOT in program 18's `%gap_file` call list; CONTEXT.md notes it as "confirm whether this is a Phase 29 candidate"; it has 41,423 rows vs base 41,150 — 273 excess, indicating either non-patient rows or multi-visit records
   - What's unclear: whether Gerard wants to include it; it was never analyzed in program 18
   - Recommendation: flag as OUT OF SCOPE for Phase 29 unless Gerard explicitly decides otherwise; the 273-row excess means it would require a more complex de-dup investigation than the 1-29 row excesses in r1/r2/r4

4. **Will the snap directory path need to be added to `00_config.sas`?**
   - What we know: D-05 specifies the path directly in the PROC COPY statement; `00_config.sas` currently defines six path macros
   - Recommendation: add `%let snap_path = P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\snap;` to `00_config.sas` for consistency with existing path management

---

## Sources

### Primary (HIGH confidence)

All findings from direct code reads — no external sources required.

- `sas/18_supplemental_raw_gap.sas` — confirmed: r1-r6 file list (lines 676-731), key types per file, `%gap_file` macro structure, D15_APPROVED gate, PACU_STAY absence
- `sas/04_merge.sas` — confirmed: md8_donors pattern (lines 242-478), MRG-06 COALESCE block, LENGTH statement structure, DATA step merge structure
- `sas/macros_raw_import.sas` — confirmed: `%import_csv` and `%import_xlsx` exact signatures
- `sas/00_config.sas` — confirmed: `D15_APPROVED=1` (line 48), all path macros, `PCNR_APPROVED=1`
- `sas/24_pcnr_build.sas` — confirmed: column-count assertion = 163 at lines 919, 1003, 1084, 1244; fingerprint read at line 97 (`nvars=175`)
- `docs/pcnr_name_map.csv` — confirmed: 10-column schema (source_name, source_label, role, h_strip, proposed_name, override_name, final_name, name_len, collision_flag, id_flag)
- `docs/sentinel_decisions.csv` — confirmed: 16-column schema (variable, raw_value, raw_hex, raw_len, normalized_value, var_type, n_rows, pct_rows, column_group, candidate_class, non_ascii_flag, match_rule, action, rationale, decided_by, decided_date)

---

## Metadata

**Confidence breakdown:**
- Architecture patterns: HIGH — copied from live code
- Key normalization per file: HIGH — directly from program 18 lines 676-731
- Column-count assertion locations: HIGH — directly from program 24
- Duplicate counts: HIGH (counts from CONTEXT.md), LOW (specific IDs — not in git repo)
- snap libname pattern: HIGH — no existing usage confirmed; pattern specified in CONTEXT.md D-05

**Research date:** 2026-10-07
**Valid until:** Until any of r1-r6 source files, `04_merge.sas`, `24_pcnr_build.sas`, or `macros_raw_import.sas` are modified (stable for the duration of Phase 29 execution)
