# Phase 26: v2.1 Carry-Forward & Source Hardening — Research

**Researched:** 2026-09-29
**Domain:** SAS 9.4 pipeline — sentinel audit/cleanup, QC assertions, SHA-256 hash guard
**Confidence:** HIGH (all findings sourced directly from the existing codebase)

---

## Summary

Phase 26 is a three-part hardening pass over existing v2.1 programs. All implementation patterns are already established in the codebase; this phase applies them to new locations rather than inventing new approaches.

FIX-03 introduces a two-task human-checkpoint workflow: first produce a diagnostic CSV (`qc/23_contains_audit.csv`) that enumerates every CONTAINS match in program 23, then — after human review — narrow the CONTAINS block and clean up `docs/sentinel_decisions.csv` to match. FIX-04 adds two `%assert_eq` assertions in program 24 (one for `Cognitive_Score = 0`, one for `pcnr_rt_RM_START_to_AN_STAR_mins = -9`) using the exact macro pattern from program 05.

The HARD item creates a hash guard: a new seed program `19b_seed_hash_baseline.sas` copies today's sha256 values from `qc/19_raw_files.csv` into `docs/raw_hash_baseline.csv` and refuses to run if that file already exists. Program 19 reads the baseline with a DATA step `infile` and fails the pipeline with `%abort cancel` if any md1-md8 sha256 has drifted. DECISIONS.md gains one documentation note (HARD-03).

**Primary recommendation:** Implement in task order — FIX-03 Task 1 (audit), human stop, FIX-03 Task 2 (apply), FIX-04, then HARD. All `%abort cancel` calls must live inside named macros per PCM-R-05, and baseline CSV must be read with DATA step `infile` per PCM-T-16.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**FIX-03: Sentinel CONTAINS Cleanup**
- D-01: FIX-03 is a two-task process with a human checkpoint between tasks.
- D-02 (Task 1): Produce `qc/23_contains_audit.csv` with columns `(contains_fragment, variable, raw_value, n_rows)`, limited to non-freetext columns, before modifying program 23 or sentinel_decisions.csv.
- D-03 (Task 2, after human review): Narrow the CONTAINS block per the audit outcome:
  - DECLINED, REFUSED, NOT SPECIFIED: keep only if audit shows exclusively sentinel-only matches.
  - UNKNOWN and N/A compound forms appearing only as full-value matches: promote to EXACT rules; remove CONTAINS fragment.
  - Multi-word phrases with low false-positive risk (NOT DOCUMENTED, NOT RECORDED, NOT APPLICABLE, NOT ASSESSED, NOT PERFORMED, UNABLE TO OBTAIN): retain as CONTAINS unless audit shows false positives.
  - Short words with high false-positive risk (NONE, OTHER, MISSING, PENDING): drop from CONTAINS unless audit justifies them.
  - After narrowing, enumerate KEEP rows in `docs/sentinel_decisions.csv` that no longer match any remaining rule; present list for human approval before deletion.

**FIX-04: New QC Assertions in program 24**
- D-04: Both assertions go into `24_pcnr_build.sas`, after the sentinel-handling step, on `g.pcnr_harmonized`.
- D-05: `pcnr_Cognitive_Score = 0` count in `g.pcnr_harmonized` must equal 0. Triggers `%abort cancel` on failure (PCM-R-05).
- D-06: `pcnr_rt_RM_START_to_AN_STAR_mins = -9` count in `g.pcnr_harmonized` must equal 0. Triggers `%abort cancel` on failure (PCM-R-05).
- D-07: Both use `%assert_eq` macro pattern (PCM-R-05), consistent with program 05.

**HARD: Hash Baseline File Design**
- D-08: Baseline file `docs/raw_hash_baseline.csv`, columns `file_name, sha256, byte_size, seeded_date`. Read with DATA step `infile` in program 19 (PCM-T-16).
- D-09: Seed program `19b_seed_hash_baseline.sas` — copies verified sha256 values for md1-md8 from `19_raw_files.csv`, populates `seeded_date` with today; aborts if `docs/raw_hash_baseline.csv` already exists.
- D-10: Program 19 reads baseline and compares each md1-md8 sha256. Any mismatch triggers `%abort cancel` with explicit error before any merge program executes. Program 19 never writes the baseline.
- D-11: To update the baseline, operator manually deletes `docs/raw_hash_baseline.csv` and re-runs `19b_seed_hash_baseline.sas`.
- D-12: `run_pipeline.cmd` does NOT include `19b`. The seed program is a one-time manual step.

**HARD-03: DECISIONS.md Note**
- D-13: Add a documentation-only note explaining that the read-only file attribute is insufficient on a network share and that full source protection requires IT engagement for folder-level write/delete permission removal.

### Claude's Discretion

- Exact variable name for the rt_RM_START assertion — must be confirmed from `docs/pcnr_name_map.csv` before writing assertions.
- Whether the CONTAINS audit is a standalone SAS program or an audit mode flag inside program 23 — decide based on least disruption to existing program structure.
- The decision number for the HARD-03 DECISIONS.md entry (next available after PCM-D-27 if it exists, otherwise PCM-D-27).

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FIX-03 | Program 23 CONTAINS sentinel cleanup with human checkpoint | Audit CSV pattern established; existing CONTAINS block at lines 389-407 of program 23 |
| FIX-04 | QC assertions for Cognitive_Score=0 and rt_RM sentinel in program 24 | `%assert_eq` pattern from program 05 lines 41-47; confirmed pcnr names from pcnr_name_map.csv |
| HARD-01 | Program 19 reads baseline hash and fails on mismatch before any merge | sha256 pattern from program 19 lines 185-198; DATA step infile pattern established |
| HARD-02 | Baseline seeded once from 19_raw_files.csv; never auto-overwritten | `fileexist()` guard pattern in program 19 line 73 |
| HARD-03 | DECISIONS.md documents read-only attribute inadequacy on network share | Documentation-only; next available decision number needed |
</phase_requirements>

---

## Standard Stack

All implementation uses existing SAS 9.4M8 patterns already in this codebase. No new libraries or macros are needed.

### Core Patterns in Use

| Pattern | Location | Purpose |
|---------|----------|---------|
| `%assert_eq` macro | `05_qc_merge.sas` lines 41-47; referenced from `00_config.sas` comment | Count-based QC assertions with `%abort cancel` |
| `%abort cancel` inside named macro | Every program; PCM-R-05 | Safe abort that does not swallow subsequent submits |
| DATA step `infile` for CSV | `19_raw_dir_inventory.sas` lines ~695, ~778, ~941 | PCM-T-16 compliant CSV reads |
| certutil SHA-256 via PIPE FILEVAR | `19_raw_dir_inventory.sas` lines 185-198 | One pipe per file, spaces stripped, 64-hex test |
| `fileexist()` guard | `19_raw_dir_inventory.sas` line 73 | Abort if expected file is absent (inverse: abort if file already present) |
| CONTAINS sentinel block | `23_pcnr_inventory.sas` lines 389-407 | Current CONTAINS fragment matching |
| freetext_cols exclusion | `23_pcnr_inventory.sas` line 379 | `indexw(upcase("&freetext_cols"), upcase(variable)) > 0` |

---

## Architecture Patterns

### FIX-03: Two-Task Sentinel Audit Structure

**Task 1 — Diagnostic (no program 23 changes):**

The audit step should be implemented as a standalone audit section appended to the end of program 23's existing SECTION logic, or as a short standalone program. The CONTEXT recommends "least disruption." Given program 23 already runs and produces its candidate file, the audit can be added as a new final section gated by a flag (e.g., `%let run_contains_audit = 1;`) without touching existing logic. Alternatively a separate `23b_contains_audit.sas` keeps the diff minimal and allows human execution of just the audit without re-running the full program 23.

Audit output format (D-02):
- File: `qc/23_contains_audit.csv` on the P: drive (matches `&qc_path.`)
- Columns: `contains_fragment, variable, raw_value, n_rows`
- Sorted: by fragment, then variable, then descending n_rows
- Scope: non-freetext columns only (same `_isft` exclusion logic as lines 379, 389)
- Source: iterate over the current CONTAINS fragments against the char frequency data already in `work._char_freq` (or `work._char_candidates`)

Implementation note: `work._char_freq` is built inside program 23. If the audit runs inside program 23 as a new section, it can reference this work dataset directly. If it is a standalone program, it must rebuild the frequency table — making a standalone program more expensive and fragile. Recommendation: add as a new `SECTION 99 — CONTAINS audit` at the end of program 23, gated by a flag macro variable.

**Task 2 — Apply (after human checkpoint):**

After the human reviews `qc/23_contains_audit.csv`, program 23's CONTAINS block (lines 389-407) is narrowed according to D-03 rules. The narrowed CONTAINS list is the only code change. After narrowing, the planner must also update `docs/sentinel_decisions.csv` to remove KEEP rows that no longer match any rule (per D-03 final bullet).

Current CONTAINS fragments in program 23 (lines 389-407):
```
UNKNOWN, NOT DOCUMENTED, NOT RECORDED, MISSING, NOT APPLICABLE,
N/A, OTHER, NONE, DECLINED, REFUSED, NOT ASSESSED, NOT PERFORMED,
UNABLE TO OBTAIN, NOT SPECIFIED, PENDING
```

Per D-03 classification:
- Candidates to DROP (short, high false-positive): `NONE`, `OTHER`, `MISSING`, `PENDING` — unless audit justifies
- Candidates to promote to EXACT (compound forms seen as full-value only): `UNKNOWN/OTHER`, `N/A - NOT APPLICABLE` etc. — audit-driven
- Candidates to RETAIN as CONTAINS (multi-word, low false-positive): `NOT DOCUMENTED`, `NOT RECORDED`, `NOT APPLICABLE`, `NOT ASSESSED`, `NOT PERFORMED`, `UNABLE TO OBTAIN` — unless audit shows false positives
- Audit-dependent: `DECLINED`, `REFUSED`, `NOT SPECIFIED`

### FIX-04: Assert Pattern (copy from program 05)

Exact macro to replicate in `24_pcnr_build.sas`:

```sas
/* Source: sas/05_qc_merge.sas lines 41-47 (PCM-R-05 compliant) */
%macro assert_eq(actual=, expected=, label=);
  %if &actual ne &expected %then %do;
    %put ERROR: QC ASSERTION FAILED -- &label: expected &expected got &actual;
    %abort cancel;
  %end;
  %else %put NOTE: QC ASSERTION OK -- &label = &actual;
%mend assert_eq;
```

Assertion calls for FIX-04 (after sentinel-handling step in program 24):

```sas
/* FIX-04: Cognitive_Score = 0 must not survive as a value in pcnr_harmonized */
%macro check_cog_zero;
  %local n_cog_zero;
  proc sql noprint;
    select count(*) into :n_cog_zero trimmed
    from g.pcnr_harmonized
    where pcnr_Cognitive_Score = 0;
  quit;
  %assert_eq(actual=&n_cog_zero, expected=0,
             label=FIX-04 pcnr_Cognitive_Score placeholder 0 count);
%mend check_cog_zero;
%check_cog_zero;

/* FIX-04: rt_RM_START_to_AN_START sentinel -9 must not survive */
%macro check_rt_sentinel;
  %local n_rt_sentinel;
  proc sql noprint;
    select count(*) into :n_rt_sentinel trimmed
    from g.pcnr_harmonized
    where pcnr_rt_RM_START_to_AN_STAR_mins = -9;
  quit;
  %assert_eq(actual=&n_rt_sentinel, expected=0,
             label=FIX-04 pcnr_rt_RM_START_to_AN_STAR_mins sentinel -9 count);
%mend check_rt_sentinel;
%check_rt_sentinel;
```

**CRITICAL variable name finding:** From `docs/pcnr_name_map.csv` line 168, the pcnr name for `rt_RM_START_to_AN_START_mins` was shortened to **`pcnr_rt_RM_START_to_AN_STAR_mins`** (note: `START` truncated to `STAR`) because the full name exceeded the 27-character rule (PCM-D-23). The assertion must use `pcnr_rt_RM_START_to_AN_STAR_mins`, not `pcnr_rt_RM_START_to_AN_START_mins`.

### HARD: Hash Guard Architecture

**Program 19b (`19b_seed_hash_baseline.sas`) — one-time seed:**

```sas
/* Guard: refuse to run if baseline already exists */
%macro seed_guard;
  %if %sysfunc(fileexist("&docs_path.\raw_hash_baseline.csv")) %then %do;
    %put ERROR: SEED ABORTED -- docs/raw_hash_baseline.csv already exists.;
    %put ERROR: To re-seed, manually delete the file and re-run 19b.;
    %abort cancel;
  %end;
%mend seed_guard;
%seed_guard;
```

After the guard, read `qc/19_raw_files.csv` with a DATA step `infile` (PCM-T-16), filter to md1-md8 rows, extract `file_name` and `sha256`, add `byte_size` and today's date as `seeded_date`, write to `docs/raw_hash_baseline.csv`.

Note: `19_raw_files.csv` lives on the P: drive (`&qc_path.`), not in the git repo. The seed program reads from there and writes `docs/raw_hash_baseline.csv` to the C: drive (in git). This is correct — the baseline is a version-controlled document.

**Program 19 additions — hash guard section:**

New section added AFTER the existing `SECTION 12 -- PROC EXPORT -> qc/19_raw_files.csv` (around line 874), so sha256 values are already computed and exported before the comparison runs:

```sas
/* SECTION 13 -- Hash guard: compare md1-md8 against baseline (D-10) */
%macro check_hash_baseline;
  %local n_drift;
  %let n_drift = 0;

  /* PCM-T-16: read baseline with DATA step infile */
  data work._baseline;
    length file_name $200 sha256 $64 byte_size 8 seeded_date $12;
    infile "&docs_path.\raw_hash_baseline.csv"
           dsd dlm=',' firstobs=2 truncover;
    input file_name $ sha256 $ byte_size seeded_date $;
  run;

  /* Join against current sha256 values for md1-md8 */
  proc sql noprint;
    select count(*) into :n_drift trimmed
    from work._baseline b
    left join work.sha_results s
      on upcase(b.file_name) = upcase(strip(s.file_id))  /* match on filename key */
    where b.sha256 ne coalesce(s.sha256, 'MISSING');
  quit;

  %if &n_drift > 0 %then %do;
    %put ERROR: HASH GUARD FAILED -- &n_drift md1-md8 source file(s) have changed since baseline was seeded.;
    %put ERROR: Delete docs/raw_hash_baseline.csv and re-run 19b_seed_hash_baseline.sas to acknowledge new source files.;
    %abort cancel;
  %end;
  %put NOTE: Hash guard passed -- all md1-md8 sha256 values match baseline.;
%mend check_hash_baseline;
%check_hash_baseline;
```

Implementation note: The join key between `work._baseline.file_name` and `work.sha_results` needs care. `work.sha_results` is keyed on `file_id` (a sequence number), not filename. The seed program should store the actual filename (not file_id) in the baseline, and program 19's guard must join via `work.files_meta` to resolve filename → sha256. The planner should read lines ~185-199 of program 19 carefully to understand the `sha_results` table structure and use the appropriate join.

### HARD-03: DECISIONS.md Note

Add as the next available PCM-D number (check current highest in `docs/DECISIONS.md` before assigning). Content per D-13:

> **PCM-D-XX — Source File Write/Delete Protection (documentation note)**
> The read-only file attribute set on md1-md8 on the network share is insufficient: folder-level write and delete permissions can still allow deletion. Full source protection requires IT engagement to remove folder-level write and delete permissions from the share. This is a recommendation only; no pipeline code change is required.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| SHA-256 computation | Custom hashing routine | `certutil -hashfile ... SHA256` via INFILE PIPE FILEVAR= (already in program 19 lines 185-198) |
| Abort on QC failure | Custom error handler | `%abort cancel` inside named macro (PCM-R-05) |
| CSV read | PROC IMPORT | DATA step `infile` with explicit informats (PCM-T-16) |
| File existence check | OS-level check via X command | `%sysfunc(fileexist(...))` |

---

## Common Pitfalls

### Pitfall 1: Wrong pcnr variable name for rt_RM_START assertion
**What goes wrong:** Using `pcnr_rt_RM_START_to_AN_START_mins` (the original name with `START`) instead of the shortened form from the name map.
**Why it happens:** The name map shortened `rt_RM_START_to_AN_START_mins` to `pcnr_rt_RM_START_to_AN_STAR_mins` because the full pcnr_ prefixed name exceeded 32 characters (PCM-D-23 rule: >27 chars shortened). The underscore `_mins` suffix was preserved but `START` became `STAR`.
**How to avoid:** Always derive the pcnr name from `docs/pcnr_name_map.csv` column 7 (`pcnr_final_name`), not by prepending `pcnr_` to the original.
**Verified name:** `pcnr_rt_RM_START_to_AN_STAR_mins` (from pcnr_name_map.csv line 168).

### Pitfall 2: %abort cancel in open code
**What goes wrong:** Placing `%abort cancel` directly in open code rather than inside a named macro.
**Why it happens:** It works in some SAS contexts but leaves the session in a state where it can swallow subsequent submits without executing them (documented in 00_config.sas comments and PCM-R-05).
**How to avoid:** Every `%abort cancel` must be inside `%macro X; ... %mend X;` per PCM-R-05.

### Pitfall 3: Seed program reads wrong sha256 column from 19_raw_files.csv
**What goes wrong:** `qc/19_raw_files.csv` has many columns; the sha256 column may not be the second column. Reading with a fixed-column infile without checking the header order will silently pick the wrong field.
**How to avoid:** Read `19_raw_files.csv` with named column references or verify the column order from `work.files_out` (which is the source of the PROC EXPORT). The relevant columns are `file_id`, `filename`, `sha256`, `fsize` per the key legend in program 19 lines ~944-954.

### Pitfall 4: Hash guard join uses file_id instead of filename
**What goes wrong:** `work.sha_results` is keyed on `file_id` (sequence number, session-specific). The baseline stores filenames. A direct join without going through `work.files_meta` to resolve file_id → filename will produce zero matches and silently pass the guard.
**How to avoid:** Join `work.sha_results` to `work.files_meta` on `file_id` to get filename, then join to the baseline on filename.

### Pitfall 5: Baseline file committed to git — PHI risk
**What goes wrong:** `docs/raw_hash_baseline.csv` contains only sha256 hashes, file sizes, and filenames of the raw extracts — no PHI. It is safe to commit. However, if the seed program writes it to the wrong path (e.g., to `&qc_path.` on P: instead of `&docs_path.` on C:), it would not be version-controlled.
**How to avoid:** Seed program writes to `&docs_path.\raw_hash_baseline.csv` (C: drive, in git). Guard in program 19 reads from the same path.

### Pitfall 6: CONTAINS audit runs on stale work datasets
**What goes wrong:** If the audit section runs inside program 23, it must be positioned AFTER the char frequency computation steps (the work datasets must already exist). If added before `work._char_candidates` is built, it will fail silently or produce empty output.
**How to avoid:** Place the audit section at the end of program 23, after existing sections.

### Pitfall 7: Open-code %IF in 19b
**What goes wrong:** Using open-code `%if %sysfunc(fileexist(...)) %then ...;` without a `%do` block — SAS reports "Expected %DO not found" and may skip large portions of the program.
**Why it happens:** Documented in `00_config.sas` comments (lines 55-57): "In OPEN CODE, %IF/%THEN requires a %DO block — a bare statement after %THEN makes SAS report 'Expected %DO not found'."
**How to avoid:** Wrap all `%if/%then` in a named macro.

---

## Code Examples

### %assert_eq macro (from sas/05_qc_merge.sas lines 41-47)
```sas
%macro assert_eq(actual=, expected=, label=);
  %if &actual ne &expected %then %do;
    %put ERROR: QC ASSERTION FAILED -- &label: expected &expected got &actual;
    %abort cancel;
  %end;
  %else %put NOTE: QC ASSERTION OK -- &label = &actual;
%mend assert_eq;
```

### certutil SHA-256 pipe (from sas/19_raw_dir_inventory.sas lines 185-198)
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

### fileexist guard (from sas/19_raw_dir_inventory.sas line 73, inverted for 19b)
```sas
/* 19b: abort if baseline already exists (D-09) */
%macro seed_guard;
  %if %sysfunc(fileexist("&docs_path.\raw_hash_baseline.csv")) %then %do;
    %put ERROR: SEED ABORTED -- docs/raw_hash_baseline.csv already exists.;
    %put ERROR: Delete the file manually and re-run 19b to re-seed.;
    %abort cancel;
  %end;
%mend seed_guard;
%seed_guard;
```

### DATA step infile for CSV (PCM-T-16 pattern, from program 19 lines ~695 style)
```sas
data work._baseline;
  length file_name $200 sha256 $64 byte_size 8 seeded_date $12;
  infile "&docs_path.\raw_hash_baseline.csv"
         dsd dlm=',' firstobs=2 truncover;
  input file_name $ sha256 $ byte_size seeded_date $;
run;
```

---

## Environment Availability

Step 2.6: SKIPPED (no new external dependencies — certutil already in use in program 19; all tools verified in prior phases).

---

## Validation Architecture

Per `.planning/config.json` — nyquist_validation not explicitly set to false, so included.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | SAS log assertions via `%assert_eq` + manual log review |
| Config file | none — assertions embedded in programs |
| Quick run command | Run target program standalone in SAS; inspect log for ERROR/NOTE lines |
| Full suite command | `run_pipeline.cmd` end-to-end run; verify all programs complete without ERROR |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FIX-03 Task 1 | `qc/23_contains_audit.csv` produced with correct columns | smoke | Run program 23 (or 23b); verify file exists on P: and contains expected headers | Wave 0 gap — new output |
| FIX-03 Task 2 | CONTAINS block narrowed; sentinel_decisions.csv consistent | manual | Human review of audit CSV then log inspection | existing program 23 |
| FIX-04 | Both assertions pass on clean `g.pcnr_harmonized` | unit | Run `24_pcnr_build.sas` standalone; `%assert_eq` must emit NOTE (not ERROR) | existing program 24 |
| HARD-01 | Program 19 fails pipeline when sha256 drifts | integration | Manually alter one sha256 in baseline, run program 19, verify ERROR in log | new section in program 19 |
| HARD-02 | Program 19b aborts if baseline exists | unit | Run 19b twice; second run must log ERROR and not overwrite | new program 19b |
| HARD-03 | DECISIONS.md contains the new note | manual | Read DECISIONS.md; verify note present under correct PCM-D-XX number | docs/DECISIONS.md |

### Wave 0 Gaps

- [ ] `qc/23_contains_audit.csv` — new output; Wave 0 is Task 1 execution producing this file (human gate before Task 2)
- [ ] `docs/raw_hash_baseline.csv` — new file; Wave 0 is running `19b_seed_hash_baseline.sas` once after implementation

*(No new test infrastructure needed — SAS log assertions are the test framework for this project.)*

---

## Open Questions

1. **Join key between baseline and sha_results in program 19**
   - What we know: `work.sha_results` has `(file_id, sha256)`; the baseline stores `file_name`. `work.files_meta` has `(file_id, full_path, filename)`.
   - What's unclear: Whether the baseline should store `filename` (basename only) or `full_path`, and whether filename is unique enough across the md1-md8 set. Based on program 19 SECTION 11b (lines 844-863), all eight are in `raw\master\` and are distinct filenames.
   - Recommendation: Store `filename` (basename) in baseline. Join: `work.sha_results` inner join `work.files_meta` on `file_id`, filter to md1-md8 subset, match to baseline on `upcase(filename)`.

2. **Next available PCM-D number for HARD-03**
   - What we know: PCM-D-26 is the last decision recorded in STATE.md (PCM-D-27 may or may not exist in docs/DECISIONS.md).
   - What's unclear: Whether docs/DECISIONS.md contains PCM-D-27 yet.
   - Recommendation: Planner reads `docs/DECISIONS.md` to find the highest existing PCM-D-XX, then assigns the next number.

3. **Location of 23_contains_audit.csv**
   - What we know: qc outputs go to `&qc_path.` on P:. D-02 specifies `qc/23_contains_audit.csv`.
   - Confirmed: CONTEXT says `qc/23_contains_audit.csv`. This means P: drive, consistent with all other qc/ outputs.

---

## Sources

### Primary (HIGH confidence)
- `sas/05_qc_merge.sas` lines 41-47 — `%assert_eq` macro exact implementation
- `sas/19_raw_dir_inventory.sas` lines 185-198 — certutil SHA-256 PIPE pattern
- `sas/19_raw_dir_inventory.sas` line 73 — `fileexist()` guard pattern
- `sas/23_pcnr_inventory.sas` lines 379, 389-407 — freetext exclusion and CONTAINS block
- `sas/00_config.sas` lines 55-57 — open-code %IF/%THEN trap documented
- `docs/pcnr_name_map.csv` line 168 — confirmed `pcnr_rt_RM_START_to_AN_STAR_mins` (shortened)
- `docs/pcnr_name_map.csv` line 38 — confirmed `pcnr_Cognitive_Score` (not shortened)
- `.planning/phases/26-v2.1-carry-forward-source-hardening/26-CONTEXT.md` — all locked decisions

### Secondary (MEDIUM confidence)
- `.planning/STATE.md` — decision history and program sequencing
- `.planning/REQUIREMENTS.md` — FIX-03, FIX-04, HARD-01, HARD-02, HARD-03 definitions

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all patterns sourced directly from existing programs
- Architecture: HIGH — designs are direct extensions of verified existing patterns
- Pitfalls: HIGH — most identified from existing inline comments and documented PCM violations
- Variable names: HIGH — confirmed from pcnr_name_map.csv (authoritative source)

**Research date:** 2026-09-29
**Valid until:** Stable until `docs/pcnr_name_map.csv` is changed (Phase 29 gap-fill will add columns; truncated name for rt_RM variable will not change)
