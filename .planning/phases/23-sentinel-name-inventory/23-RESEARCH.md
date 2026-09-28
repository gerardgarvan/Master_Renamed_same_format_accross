# Phase 23: Sentinel & Name Inventory — Research

**Researched:** 2026-09-28
**Domain:** SAS 9.4M8 — placeholder-value enumeration, name-map generation, human-gate workflow
**Confidence:** HIGH (all findings from first-party project sources: CONTEXT.md, REQUIREMENTS.md,
existing SAS programs, committed QC outputs)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01 / PCM-D-21: Sentinel Matching — Seed and Discover**
- Normalize before matching: upcase, trim, collapse internal whitespace
- Key is `(variable, raw_hex)`, not `(variable, raw_value)`
- Auto-candidates (exact match on normalized): `?`, `??`, `-`, `--`, `.`, `UNKNOWN`, `UNK`,
  `N/A`, `NA`, `NULL`, `MISSING`, `NOT DOCUMENTED`, `NOT RECORDED`
- Whitespace-only control chars scanned explicitly: TAB (`'09'x`), CR/LF (`'0D'x`/`'0A'x`),
  NBSP (`'A0'x`); normalized tokens `<TAB>`, `<CRLF>`, `<NBSP>` written to `normalized_value`
- Contains matches → REVIEW class only, never AUTO
- Known artifacts (2-byte encounter placeholder, literal NULL) included explicitly

**D-02 / PCM-D-25: Ambiguous Value List**
- AMBIGUOUS class — per-variable decision required; wildcards may NOT resolve AMBIGUOUS candidates
- Base list: `None`, `Not applicable`, `Declined`, `Refused`, `Other`
- Additional: `NOT ASSESSED`, `NOT PERFORMED`, `PENDING`, `UNABLE TO OBTAIN`,
  `NOT SPECIFIED`, `PATIENT DECLINED`
- `UNKNOWN` in demographic columns → AMBIGUOUS for those columns
- `0` in count/score columns → AMBIGUOUS for those columns only
- `candidate_class` is a clean enum: AUTO / REVIEW / AMBIGUOUS
- `non_ascii_flag` is a separate boolean column; does not affect `candidate_class`
- Sort order: AMBIGUOUS first, then REVIEW, then AUTO; DROP rows need no decision

**D-03 / PCM-D-24: Numeric Sentinel Scan**
- Candidates: `-999, -99, -9, 99, 999, 777, 888, 9999, 99999`; IS NOT MISSING guard on every scan
- Numeric candidates go into `sentinel_decisions.csv` with `var_type = num`
- Default pre-filled `action = KEEP`; changed to `MISSING` only when PCM-D-24 approves per-variable
- Numeric keying: `raw_hex = put(strip(put(x, best32.)), $hex.)` — hex of the text string
- Wildcards NOT allowed for `var_type = num`

**D-04: `sentinel_decisions.csv` Schema (locked)**
```
variable, raw_value, raw_hex, raw_len, normalized_value, var_type, n_rows, pct_rows,
column_group, candidate_class, non_ascii_flag, match_rule, action, rationale,
decided_by, decided_date
```
- Key is `(variable, raw_hex)`; `raw_value` is display-only
- NEVER read gate files with PROC IMPORT — use DATA step `infile` with explicit `$` informats (PCM-T-16)
- `action` values: `MISSING` or `KEEP` only
- `variable = *` wildcard rows: match on `normalized_value` across all KEEP/KEY columns;
  per-variable rows override; AMBIGUOUS candidates excluded from wildcard resolution;
  wildcards must have `var_type = char`
- Gate checks both directions (coverage + stale); gate runs at top of program 24, not program 23
- `role` column in decisions file is display-only; gate reads role from `docs/pcnr_name_map.csv`
- No confirmed flag; non-blank `action` = confirmed

**D-05: `pcnr_name_map.csv` Schema (locked)**
```
source_name, source_label, role, h_strip, proposed_name, override_name, final_name,
name_len, collision_flag, id_flag
```
- `role` values: KEY / KEEP / DROP
- KEY columns: `pecan_ID`, `PRECEDE_STUDY_ID`, `ENCRYPTED_MRN`, `ENCRYPTED_ENCOUNTER` — unprefixed
- KEEP: get `pcnr_` prefix (with `h_` stripping)
- DROP: raw columns superseded by an `h_*` version — program proposes DROP from `concept_decisions.csv`
- `h_strip = Y/N`; decision: strip `h_` and mark raw counterpart DROP (recorded as PCM-D-23)
- Truncation rule (PCM-D-23): preserve final token after last `_`; fallback plain tail truncation
- `final_name = coalesce(override_name, proposed_name)` for KEEP rows; blank for KEY/DROP
- `collision_flag`: proposed/final name matches another row case-insensitively
- `id_flag`: KEEP row whose source name matches `*_ID`, `*STUDY_ID*`, or `ENCRYPTED_*` not on KEY list

**D-06: Draft/Docs Split and Gate Placement (locked)**
- Program 23 writes ONLY to `qc/`: `23_sentinel_candidates.csv`, `23_case_variants.csv`,
  `23_sentinel_decisions_DRAFT.csv`, `23_pcnr_name_map_DRAFT.csv`, `23_sentinel_fingerprint.txt`
- Program 23 NEVER writes to `docs/`; protection is structural — no `file=docs/` in the program
- Static check required: `grep -ni "docs" sas/23_pcnr_inventory.sas` must show only the
  `concept_decisions.csv` read, with no occurrence inside `filename`, `file=`, `outfile=`, or
  `ods ... file=` statement
- Draft pre-fill: numeric rows `action = KEEP`; character rows `action` left blank;
  one wildcard row proposed per distinct AUTO `normalized_value` (action blank)
- Fingerprint: `qc/23_sentinel_fingerprint.txt` records nobs, nvars, modate from SASHELP.VTABLE
- Gate (`%pcnr_gate_check`) runs at top of program 24; reads `qc/23_sentinel_candidates.csv`
  from disk with DATA step infile (PCM-T-16); aborts if fingerprint mismatches

**D-07: PCM-D-25 Column Lists — Proposed from `qc/03_contents_all.txt`**
- Planner proposes demographic and count/score lists from the committed contents export
- Final lists hardcoded in program header and echoed into `23_sentinel_candidates.csv` as `column_group`

**D-08: DROP Rows Skip Sentinel Decisions**
- Candidates in DROP-role columns require no entry in `sentinel_decisions.csv`
- Gate skips DROP-role candidates in coverage check; `role` carried into candidates CSV

**D-09: Git Tracking and PHI Containment**
- `docs/sentinel_decisions.csv` and `docs/pcnr_name_map.csv`: committed with `git add -f`
- `qc/` CSV drafts: NOT committed (already excluded by `*.csv` in `.gitignore`)
- `qc/23_sentinel_candidates.csv`: NOT committed (REVIEW rows may contain PHI in raw_value)
- PHI mitigation: restrict contains rule to columns with SAS length <= 50 (heuristic), OR
  hardcode an exclusion list of known free-text columns
- Pre-commit PHI scan required before `git add -f docs/sentinel_decisions.csv`:
  review REVIEW rows' `raw_value` for names, DOBs, MRN fragments, free-text narrative

**PCM-T-16: Never PROC IMPORT a Gate File**
- Hex strings like `30`, `39`, `09` mis-typed as integers by PROC IMPORT, breaking key lookups
- Always read both gate files with DATA step `infile` and explicit `$` informats

### Claude's Discretion

- Exact column widths and sort tiebreakers within candidate_class groups
- Whether PCNR-02 numeric output is a separate section within `23_sentinel_candidates.csv`
  or its own `23_numeric_sentinels.txt`
- Middle-truncation algorithm details (propose in plan with real example; Gerard confirms at checkpoint)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

## Summary

Phase 23 is a pure evidence-gathering and human-gate phase. The single SAS program
`23_pcnr_inventory.sas` reads `g.master_data_harmonized` read-only and produces three
categories of output: (1) a sentinel candidate sweep over every character and numeric column,
(2) a name-map draft proposing `pcnr_` prefixed names for every column, and (3) draft gate
files that a human reviews, edits, and copies to `docs/` to set `PCNR_APPROVED = 1`.

The CONTEXT.md is exhaustive and mature (four rounds of revision). All implementation
decisions are locked. The planner's job is to decompose the program into verifiable waves,
propose the PCM-D-25 column lists from the committed contents export, work a real truncation
example, and define the human checkpoint tasks precisely.

**Primary recommendation:** Write the program in sections that correspond to locked decisions
(D-01 through D-09), validate each section's output independently, and treat the draft-to-docs
human workflow as a distinct acceptance-criteria category with its own checklist.

---

## Standard Stack

This phase is pure SAS 9.4M8 against existing pipeline patterns. No new libraries.

| Component | Version | Purpose | Pattern Source |
|-----------|---------|---------|----------------|
| SAS 9.4M8 | M8 | Program execution | Existing pipeline |
| `00_config.sas` | current | Path macros, gate flag, `%fail_out` | All programs |
| `sas/10_concept_profile.sas` | current | Value-sweep pattern to replicate | Program 23 starting point |
| `sas/10b_concept_harmonize.sas` | current | Gate abort pattern to replicate | Program 23 gate model |
| `docs/concept_decisions.csv` | current | Gate file read pattern (DATA step infile) | Schema reference |
| `qc/03_contents_all.txt` | current | Column inventory for PCM-D-25 proposals | Committed; readable |

**Installation:** No new packages. Ensure `%let PCNR_APPROVED = 0;` added to `sas/00_config.sas`.

---

## Architecture Patterns

### Recommended Program Structure for `23_pcnr_inventory.sas`

```
sas/23_pcnr_inventory.sas
  HEADER: hardcoded demographic + count/score column lists (PCM-D-25)
  SECTION 0: Preconditions
    - %include 00_config.sas
    - Gate: PCNR_APPROVED must be 0 (structural guard — program only writes drafts)
    - Gate: g.master_data_harmonized exists + row count = 41,150
    - Gate: docs/concept_decisions.csv readable (needed for DROP proposals)
  SECTION 1: Write fingerprint (qc/23_sentinel_fingerprint.txt)
    - Read nobs, nvars, modate from SASHELP.VTABLE
  SECTION 2: Character sentinel sweep (PCNR-01, D-01)
    - PROC SQL + DATA step loop over all char vars from dictionary.columns
    - Normalize: upcase, strip, compbl
    - raw_hex = put(value, $hex.)
    - Exact-match AUTO classification; contains-match REVIEW; AMBIGUOUS from D-02 list
    - Control-char scan: '09'x, '0D'x, '0A'x, 'A0'x → normalized tokens
    - column_group column from hardcoded lists
  SECTION 3: Numeric sentinel scan (PCNR-02, D-03)
    - PROC SQL per numeric sentinel value; IS NOT MISSING guard
    - Output with var_type = num; raw_hex of text representation
  SECTION 4: Ambiguous-value AMBIGUOUS class (D-02)
    - UNKNOWN in demographic columns; 0 in score/count columns
    - Merged into candidates dataset; candidate_class = AMBIGUOUS
  SECTION 5: Case/whitespace variant report (PCNR-04)
    - Write qc/23_case_variants.csv; report only, no recoding
  SECTION 6: Name map draft (PCNR-05, D-05)
    - Read docs/concept_decisions.csv to identify h_* columns → propose DROP for raw counterparts
    - Proposed name: pcnr_ + name (after h_ strip), apply truncation algorithm
    - Collision detection; id_flag logic
    - Write qc/23_pcnr_name_map_DRAFT.csv
  SECTION 7: Sentinel decisions draft (D-04, D-06)
    - One row per candidate from candidate dataset
    - Pre-fill: num rows action=KEEP; char rows action=blank
    - Append one wildcard row per distinct AUTO normalized_value; action blank
    - Write qc/23_sentinel_decisions_DRAFT.csv
  SECTION 8: Validation report
    - Log total char cols swept, total distinct values, candidate counts by class
    - Log name map: count by role, count with truncation, count with collision_flag
```

### Pattern 1: Character Column Sweep (from `10_concept_profile.sas`)

`sas/10_concept_profile.sas` already iterates over specified column groups using
`dictionary.columns` and produces value frequencies. Program 23 generalizes this to
ALL character columns.

```sas
/* Source: sas/10_concept_profile.sas — value frequency pattern */
proc sql noprint;
  select name into :varlist separated by ' '
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_HARMONIZED'
    and type='char';
  select count(*) into :ncharvars trimmed
  from dictionary.columns
  where libname='G' and memname='MASTER_DATA_HARMONIZED'
    and type='char';
quit;
```

### Pattern 2: Gate Abort (from `10b_concept_harmonize.sas`)

```sas
/* Source: sas/10b_concept_harmonize.sas — gate abort pattern */
%macro fail_out(msg=);
  %put ERROR: &msg;
  ods listing;
  %restore_log;
  %abort cancel;
%mend fail_out;
```

### Pattern 3: DATA Step Infile for Gate Files (PCM-T-16)

```sas
/* Never PROC IMPORT. Hex columns mis-typed as numeric by PROC IMPORT. */
data work.decisions;
  length variable $32 raw_value $200 raw_hex $400 var_type $4
         action $7 rationale $500 decided_by $40 decided_date $10;
  infile "&docs_path.\sentinel_decisions.csv"
    dsd firstobs=2 truncover lrecl=32767;
  input variable      : $32.
        raw_value     : $200.
        raw_hex       : $400.
        /* ... all columns with explicit $ informats ... */
  ;
run;
```

### Pattern 4: Hex Key Generation

```sas
/* Character value — MUST use $hex400. + length trim; bare $hex. encodes only first 2 bytes */
raw_hex = substr(put(raw_value, $hex400.), 1, 2*length(raw_value));
/* Define in 00_config.sas as: %macro hexkey(var) / substr(put(&var,$hex400.),1,2*length(&var)) %mend; */
/* grep -n '\$hex\.' sas/*.sas must return nothing — any bare $hex. is the truncating form */

/* Numeric sentinel — same length-trim applied to text representation */
raw_hex = substr(put(strip(put(x, best32.)), $hex400.), 1, 2*length(strip(put(x, best32.))));

/* Control-character normalized tokens */
if raw_value = '09'x then normalized_value = '<TAB>';
else if raw_value in ('0D0A'x, '0D'x, '0A'x) then normalized_value = '<CRLF>';
else if raw_value = 'A0'x then normalized_value = '<NBSP>';
```

### Pattern 5: Fingerprint Write

```sas
proc sql noprint;
  select nobs, nvar, modate
  into :fp_nobs trimmed, :fp_nvars trimmed, :fp_modate trimmed
  from sashelp.vtable
  where libname='G' and memname='MASTER_DATA_HARMONIZED';
quit;

data _null_;
  file "&qc_path.\23_sentinel_fingerprint.txt";
  put "nobs=&fp_nobs nvars=&fp_nvars modate=&fp_modate";
run;
```

### Pattern 6: Gate Flag in `00_config.sas`

```sas
/* Add after D15_APPROVED line -- same pattern */
%let PCNR_APPROVED = 0;
%put NOTE: [00_config] PCNR_APPROVED = &PCNR_APPROVED;
```

### Anti-Patterns to Avoid

- **PROC IMPORT on gate files:** mis-types hex strings `30`, `09`, `39` as integers (PCM-T-16)
- **Writing to `docs/` from program 23:** structural prohibition; any `file=` or `filename` filerefs pointing at `docs/` (except the read of `concept_decisions.csv`) are a static-check failure
- **Wildcards for AMBIGUOUS candidates or numeric candidates:** gate aborts on both; the program should pre-fill accordingly so drafts are self-consistent
- **Open-code `%IF/%THEN` without `%DO`:** PCM compliance requirement across all pipeline programs
- **`IS NOT MISSING` in DATA steps:** correct only in PROC SQL; DATA step form is `NOT MISSING(x)`
- **`&SQLOBS`:** never used; use explicit `SELECT COUNT(*) INTO :macvar TRIMMED`

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Column type/length metadata | Manual PROC CONTENTS parse | `dictionary.columns` in PROC SQL | Authoritative, no intermediate dataset |
| Dataset metadata for fingerprint | Custom macro | `SASHELP.VTABLE` (nobs, nvar, modate) | Direct, always current |
| Hex encoding of values | Custom byte loop | `put(value, $hex.)` SAS format | Handles all byte values including non-ASCII |
| Gate abort | Custom error handling | `%fail_out` macro from `00_config.sas` | Consistent abort pattern across pipeline |
| Collision detection | Hash-based approach | PROC SORT + DATA step LAG or PROC SQL self-join | Simple, deterministic, no external tools |

---

## PCM-D-25 Column Lists — Proposed from `qc/03_contents_all.txt`

The planner has read the committed contents export. The following lists are proposed for
Gerard's confirmation at the PCM-D-25 checkpoint.

### Proposed Demographic Columns
These are columns where `UNKNOWN` should be treated as AMBIGUOUS (not AUTO):

```
Race
Ethnicity
Sex
Marital_Status
Education
EmployeeStatus
Patient_Type
Payer
```

Rationale: these are the columns representing patient identity/social categories where
`UNKNOWN` is a legitimate recorded category, not a data-entry placeholder.

### Proposed Count/Score Columns
These are columns where `0` should be treated as AMBIGUOUS:

```
/* Frailty component scores */
Feels_Exausted_Value
Low_Physical_Activity_Value
Slow_Walking_Speed_Value
Unintended_Weight_Loss_Value
Week_Grip_Strength_Value
Braden_Activity
Braden_Mobility
Braden_Sensory_Perception

/* Composite scores */
Charlson_Comorbidity_Index
Cognitive_Score
Frailty_Score

/* Complication indicator counts */
COMP10_T80, COMP10_T81, COMP10_T82, COMP10_T83, COMP10_T84,
COMP10_T85, COMP10_T86, COMP10_T87, COMP10_T88
complication_sum

/* Hemodynamic/monitoring counts (md8) */
ABP_LESS_THAN_60_COUNT, ABP_LESS_THAN_70_COUNT, ABP_LESS_THAN_80_COUNT
BIS_INDEX_LESS_30_COUNT, BIS_INDEX_LESS_40_COUNT
NIBP_LESS_60_COUNT, NIBP_LESS_70_COUNT, NIBP_LESS_80_COUNT
```

Rationale: a value of 0 in these columns is clinically meaningful (e.g., no complications,
no frailty component met, no hemodynamic events) and should not be auto-classified as a
placeholder sentinel.

Note: `ASA__Anesth_Record_` is numeric in most sources and not on the count list, though
a 0 there would be clinically implausible — the planner recommends Gerard consider adding it.

**Confirm at PCM-D-25 checkpoint before the gate flips.**

---

## PCM-D-23 Truncation Algorithm — Real Examples

From `qc/03_contents_all.txt`, variable names > 27 characters that appear in `g.master_data_harmonized`
(after harmonization the `h_` prefixed versions are in the dataset; their source names are those below):

Variables at exactly 32 characters (SAS limit — already at limit, `pcnr_` prefix impossible without truncation):
- `rt_BLOCK_START_TO_BLOCK_END_mins` (32 chars)
- `fentaNYL_SUBLIMAZE_mg__1_7_Total` (32 chars)
- `fentaNYL_SUBLIMAZE_mg_IntraOp_To` (32 chars — already truncated in source)
- `Total_Phenylephrine_HCl_Pressors` (32 chars)
- `Total_Norepinephrine_Bitartrate_` (32 chars)
- `Total_EPHEDRINE_SULFATE_PRESSORS` (32 chars)
- `SEV_Exp_IntraOp_MAC_Minutes_Tota` (32 chars)
- `Oral_Morphine_Equiv_IntraOp_Tota` (32 chars)
- `Oral_Morphine_Equiv_Given__1_7_T` (32 chars)
- `ISO_Exp_IntraOp_MAC_Minutes_Tota` (32 chars)

**Correct truncation table — all 10 at-limit names (acceptance criteria for Plan 02 Task 1):**

| Source name (32 chars) | Proposed name (32 chars) | Notes |
|---|---|---|
| rt_BLOCK_START_TO_BLOCK_END_mins | pcnr_rt_BLOCK_START_TO_BLOC_mins | head=22: `rt_BLOCK_START_TO_BLOC` |
| fentaNYL_SUBLIMAZE_mg__1_7_Total | pcnr_fentaNYL_SUBLIMAZE_mg_Total | double-_ in source; head loses `_1_7` distinguisher — flag for `override_name` at checkpoint |
| fentaNYL_SUBLIMAZE_mg_IntraOp_To | pcnr_fentaNYL_SUBLIMAZE_mg_In_To | already truncated at source |
| Total_Phenylephrine_HCl_Pressors | pcnr_Total_Phenylephrin_Pressors | |
| Total_Norepinephrine_Bitartrate_ | pcnr_Total_Norepinephrine_Bitar_ | trailing `_` in source → final_token is empty → fallback to tail truncation; result has trailing `_` which is stripped from head → `pcnr_Total_Norepinephrine_Bitar_` ⚠ empty final_token edge case — use tail truncation |
| Total_EPHEDRINE_SULFATE_PRESSORS | pcnr_Total_EPHEDRINE_SU_PRESSORS | |
| SEV_Exp_IntraOp_MAC_Minutes_Tota | pcnr_SEV_Exp_IntraOp_MAC_Mi_Tota | |
| Oral_Morphine_Equiv_IntraOp_Tota | pcnr_Oral_Morphine_Equiv_In_Tota | |
| Oral_Morphine_Equiv_Given__1_7_T | pcnr_Oral_Morphine_Equiv_Given_T | double-_ → `_1_7` lost, flag for checkpoint |
| ISO_Exp_IntraOp_MAC_Minutes_Tota | pcnr_ISO_Exp_IntraOp_MAC_Mi_Tota | |

No collisions in the table. `Total_Norepinephrine_Bitartrate_` exposes the empty-final-token edge case: trailing `_` in the source means the final token is an empty string — fall back to tail truncation. Strip trailing `_` from `head` before rejoining so a truncation that lands on an underscore cannot produce a double `__`.

**Worked example (primary checkpoint example):**
Name: `rt_BLOCK_START_TO_BLOCK_END_mins` (32 chars)
After `pcnr_` prefix: `pcnr_rt_BLOCK_START_TO_BLOCK_END_mins` = 37 chars (exceeds 32)
Algorithm:
1. `final_token` = `mins` (4 chars)
2. Budget: 32 − 5(`pcnr_`) − 1(`_`) − 4(`mins`) = **22 chars** for `head`
3. `rt_BLOCK_START_TO_BLOCK_END` (27 chars) → trim to 22 = `rt_BLOCK_START_TO_BLOC`
4. Result: `pcnr_rt_BLOCK_START_TO_BLOC_mins` = **32 chars** ✓

**Confirm this table at the PCM-D-23 checkpoint before the name map draft is generated.**

Note: variables in `g.master_data_harmonized` that were already truncated at the source
(e.g., `fentaNYL_SUBLIMAZE_mg_IntraOp_To` has already lost its trailing characters) cannot
be restored. The name map's `proposed_name` works from the source name as it exists in the
dataset. The `source_label` column preserves the full original label for traceability.

---

## Common Pitfalls

### Pitfall 1: PROC IMPORT Mis-types Hex Columns (PCM-T-16)
**What goes wrong:** Hex strings like `30`, `09`, `39` in `raw_hex` are read as integers by
PROC IMPORT's type-guessing logic, silently breaking every key lookup.
**Why it happens:** PROC IMPORT guesses column types from the data; short hex strings look numeric.
**How to avoid:** Always read both gate files with DATA step `infile` and explicit `$` informats.
**Warning signs:** Gate reports zero matches for known candidates; key lookups return no rows.

### Pitfall 2: Wildcard Resolving an AMBIGUOUS Candidate
**What goes wrong:** A `variable = *` row with `normalized_value = UNKNOWN` appears in
`sentinel_decisions.csv`. The gate aborts because `UNKNOWN` appears in a demographic column
as AMBIGUOUS, and wildcards may not resolve AMBIGUOUS candidates.
**Why it happens:** Draft proposes wildcards for all AUTO `normalized_value`s, but `UNKNOWN`
is simultaneously AUTO in non-demographic columns and AMBIGUOUS in demographic columns.
**How to avoid:** Program 23 must detect this dual-class situation and either (a) not propose
a wildcard for `UNKNOWN` in the draft, or (b) add a NOTE in the draft warning that the wildcard
does not cover AMBIGUOUS rows.

### Pitfall 3: Stale Wildcard After Dataset Refresh
**What goes wrong:** After refreshing program 23 against updated source data, a wildcard row
in `docs/sentinel_decisions.csv` targets a `normalized_value` that no longer appears in any
KEEP/KEY column. Gate aborts with stale-wildcard error.
**Why it happens:** Source data changes between program 23 runs; fingerprint catches the change
but the human-edited `docs/` files lag behind.
**How to avoid:** Fingerprint check forces re-review when dataset changes. Stale wildcard is a
gate abort — by design.

### Pitfall 4: `docs/` Write Seeping Into Program 23
**What goes wrong:** A code edit adds a `filename` or `file=` pointing at `docs/` — even for a
legitimate intermediate output — breaking the structural protection.
**Why it happens:** Easy to add an ODS output or a DATA step FILE statement without realizing
it points at `docs/`.
**How to avoid:** Static check: `grep -ni "docs" sas/23_pcnr_inventory.sas` must show only the
`concept_decisions.csv` read; no file-write statement pointing at `docs/`.

### Pitfall 5: Committing PHI via Sentinel Decisions CSV
**What goes wrong:** A REVIEW row in `sentinel_decisions.csv` carries a raw value from a
free-text procedure description field — patient name, diagnosis narrative, or MRN fragment.
**Why it happens:** The contains rule fires on long free-text columns; `raw_value` holds the
actual text.
**How to avoid:** Restrict contains rule to columns with SAS length <= 50 (or an explicit
exclusion list). Pre-commit PHI scan is a mandatory acceptance criterion.

### Pitfall 6: Non-ASCII Values Breaking Normalization
**What goes wrong:** A value with bytes outside `'20'x`–`'7E'x` fails upcase/strip and
produces a blank or garbage `normalized_value`, causing misclassification.
**Why it happens:** SAS encoding damage confined to `Base_Procedure_1` (PCM-F-10); other
non-ASCII values can arise from copy-paste artifacts.
**How to avoid:** Detect non-ASCII by checking `verify(value, '20'x||'7E'x...complements)`;
set `non_ascii_flag = 1`; still write the hex representation to `raw_hex`.

---

## Code Examples

### Reading SASHELP.VTABLE for Fingerprint
```sas
/* Source: SAS documentation / established pipeline convention */
proc sql noprint;
  select put(nobs, 20. -L),
         put(nvar, 8. -L),
         put(modate, datetime20.)
  into :fp_nobs trimmed,
       :fp_nvars trimmed,
       :fp_modate trimmed
  from sashelp.vtable
  where libname = 'G' and memname = 'MASTER_DATA_HARMONIZED';
quit;
%put NOTE: [23] Fingerprint: nobs=&fp_nobs nvars=&fp_nvars modate=&fp_modate;
```

### Numeric Sentinel Scan with IS NOT MISSING Guard
```sas
/* Source: REQUIREMENTS.md PCM-T-11 / D-03 */
%macro scan_num_sentinel(val=);
  proc sql noprint;
    create table work._num_&val as
    select name as variable,
           "&val" as raw_value length=20,
           put(strip("&val"), $hex.) as raw_hex length=40,
           count(*) as n_rows
    from g.master_data_harmonized (keep=<numvars>)
    /* Must use IS NOT MISSING -- PROC SQL syntax */
    where <var> is not missing and <var> = &val
    group by name;
  quit;
%mend scan_num_sentinel;
/* Called for each of: -999 -99 -9 99 999 777 888 9999 99999 */
```

### Collision Detection for Name Map
```sas
/* Source: D-05 spec */
proc sql noprint;
  create table work.collision_check as
  select a.source_name, a.final_name,
         case when b.n > 1 then 1 else 0 end as collision_flag
  from work.name_map_draft a
  left join (
    select upcase(final_name) as ufn, count(*) as n
    from work.name_map_draft
    where role = 'KEEP' and final_name ne ''
    group by upcase(final_name)
  ) b on upcase(a.final_name) = b.ufn;
quit;
```

---

## Environment Availability

Step 2.6: SKIPPED — Phase 23 has no external tool dependencies beyond SAS 9.4M8 (already
operational; pipeline PASSED in Phase 22 on 2026-09-28) and file system paths already
configured in `00_config.sas`.

Files confirmed readable by the planner (committed to git):
- `qc/03_contents_all.txt` — AVAILABLE; used above for PCM-D-25 proposals and truncation examples
- `docs/concept_decisions.csv` — AVAILABLE; needed to propose DROP rows in name map draft
- `sas/00_config.sas`, `sas/10_concept_profile.sas`, `sas/10b_concept_harmonize.sas` — AVAILABLE

Files NOT readable by the planner (on P: drive, not committed):
- `g.master_data_harmonized` — on P:; program 23 reads it at runtime (41,150 rows, 175 cols)
- All `qc/*.csv` and `qc/*.txt` generated files — on P:

---

## Validation Architecture

No automated test framework (SAS pipeline; no pytest/jest infrastructure). Validation is
by SAS assertions within the program and manual acceptance criteria.

### Phase Requirements → Acceptance Criteria Map

| Req | Behavior | Verification Method |
|-----|----------|---------------------|
| PCNR-01 | Every char column swept, not sampled | Log: `ncharvars` columns processed = column count from `dictionary.columns`; no WHERE clause limits columns |
| PCNR-02 | Numeric sentinels scanned with IS NOT MISSING; report only | Inspect draft CSV for `var_type = num` rows; confirm `action = KEEP` pre-filled |
| PCNR-03 | Ambiguous values reported separately | `candidate_class = AMBIGUOUS` rows present in `23_sentinel_candidates.csv`; no AMBIGUOUS row resolved by wildcard |
| PCNR-04 | Case/whitespace variants in `23_case_variants.csv` | File written; spot-check `Race`, `Sex`, `Patient_Type` for known variants |
| PCNR-05 | Name map complete; all names <= 32 chars and unique | Assertions in SECTION 8: max(name_len) <= 32; zero collision_flag rows after overrides |
| PCNR-06 | Draft files written; gate flag default 0 | `qc/23_sentinel_decisions_DRAFT.csv` and `qc/23_pcnr_name_map_DRAFT.csv` exist; `PCNR_APPROVED = 0` in `00_config.sas` |

### Static Check (acceptance criterion for every plan wave)
```
grep -ni "docs" sas/23_pcnr_inventory.sas
```
Must show only the `concept_decisions.csv` read with no `file=`, `outfile=`, `filename`, or
`ods ... file=` statement pointing at `docs/`.

### Human Checkpoint (Gate Flip Prerequisites)
1. Gerard reviews `qc/23_sentinel_candidates.csv` — sorts AMBIGUOUS first
2. Gerard reviews `qc/23_pcnr_name_map_DRAFT.csv` — confirms PCM-D-23 truncation, DROP proposals
3. Price reviews D-21 (which candidates become MISSING), D-24 (numeric approvals), D-25 (column scope)
4. Pre-commit PHI scan of REVIEW rows in draft decisions file
5. Copy drafts to `docs/` and edit decisions/actions
6. `git add -f docs/sentinel_decisions.csv docs/pcnr_name_map.csv`
7. Set `PCNR_APPROVED = 1` in `sas/00_config.sas`

---

## Open Questions

1. **Demographic column list completeness**
   - What we know: `Race`, `Ethnicity`, `Sex`, `Marital_Status`, `Education`, `EmployeeStatus`,
     `Patient_Type`, `Payer` are candidate demographics from the contents export
   - What's unclear: Whether `Anesthesia_Type`, `Service`, `Room_Type`, `Admit_Source`,
     `Dischg_Disposition` should also have `UNKNOWN` treated as AMBIGUOUS
   - Recommendation: Propose the conservative list above; Gerard confirms at PCM-D-25 checkpoint

2. **Free-text column exclusion list vs. length heuristic**
   - What we know: CONTEXT.md gives two options: exclude SAS length > 50, or hardcode exclusion list
   - What's unclear: Which columns are truly free-text vs. long categorical
   - Recommendation: The length-50 heuristic captures `Base_Procedure_1` (length 198-199),
     `CPT1_Label` (length 96), `CPT_1_Description` (length 70-75), `ICD10_Principal_Diagnosis_Desc`
     (length 60), `Admit_Source` (length 28-40), `Dischg_Disposition` (length 28-43),
     `Anesthesia_Type` (length 33). Planner should propose this as the exclusion list rather than
     the length heuristic, so the scope is explicit and auditable in the program header.

3. **`UNKNOWN` wildcard dual-class problem**
   - What we know: `UNKNOWN` is AUTO for non-demographic columns but AMBIGUOUS for demographic columns
   - What's unclear: Whether program 23 should suppress the wildcard for `UNKNOWN` in the draft,
     or include it with a warning comment
   - Recommendation: Include the wildcard row but add a comment column in the draft noting
     "Wildcard does not cover AMBIGUOUS rows; demographic columns require per-variable decision rows"

---

## Sources

### Primary (HIGH confidence)
- `23-CONTEXT.md` — all locked decisions; four rounds of revision; project-authority source
- `sas/00_config.sas` — gate macro pattern, path macros, `%fail_out`, `D15_APPROVED` pattern
- `sas/10_concept_profile.sas` — value-sweep and `dictionary.columns` patterns
- `sas/10b_concept_harmonize.sas` — gate abort pattern, DATA step infile pattern for CSV reads
- `docs/concept_decisions.csv` — existing gate file schema and read pattern
- `qc/03_contents_all.txt` — column inventory; used directly for PCM-D-25 proposals and
  truncation examples
- `REQUIREMENTS.md` PCNR-01 through PCNR-06 — acceptance criteria

### Secondary (MEDIUM confidence)
- None required; all findings derived from first-party project sources

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all patterns from existing committed programs
- Architecture: HIGH — program structure derived directly from locked CONTEXT.md decisions
- PCM-D-25 column lists: MEDIUM — proposed from contents export; Gerard must confirm
- Truncation examples: HIGH — computed from actual variable names in `qc/03_contents_all.txt`
- Pitfalls: HIGH — each derived from an explicitly named trap in CONTEXT.md or project history

**Research date:** 2026-09-28
**Valid until:** 2026-10-28 (stable SAS pipeline; validity limited only by source dataset changes)
