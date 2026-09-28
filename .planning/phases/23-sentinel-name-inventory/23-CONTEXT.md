# Phase 23: Sentinel & Name Inventory - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning
**Revised:** 2026-09-28 (11 corrections before planning — gate logic, keying, schema, name map rules, D-number assignments)
**Revised:** 2026-09-28 (8 further corrections — draft/docs split, hex-key PROC IMPORT trap, wildcard/AMBIGUOUS wording, numeric keying, control-char tokens, truncation algorithm, gate placement, DROP scoping)
**Revised:** 2026-09-28 (6 final corrections — overwrite guard removed, gate scan source defined with fingerprint, git/PHI clarified, role source disambiguation, numeric wildcard aborts, id_flag split from collision_flag)

<domain>
## Phase Boundary

Enumerate every candidate placeholder value and every column name that cannot accept the
`pcnr_` prefix — then capture human decisions into gate files — before any values are changed.
Program `sas/23_pcnr_inventory.sas` reads `g.master_data_harmonized` read-only.

Deliverables:
- `qc/23_sentinel_candidates.csv` — every character column swept; `candidate_class` column (AUTO / REVIEW / AMBIGUOUS); `role` column (KEEP/KEY/DROP) carried through; sorted AMBIGUOUS first, then REVIEW, then AUTO; DROP rows need no decision
- `qc/23_case_variants.csv` — case and whitespace variant report (report only, no recoding)
- `qc/23_sentinel_decisions_DRAFT.csv` — program-generated draft; human copies to `docs/` to create the authoritative gate file
- `qc/23_pcnr_name_map_DRAFT.csv` — program-generated draft; human copies to `docs/` to create the authoritative gate file
- `docs/sentinel_decisions.csv` — human-owned; never written by program 23
- `docs/pcnr_name_map.csv` — human-owned; never written by program 23
- PCM-D-21 through PCM-D-25 resolved and attributed in `docs/DECISIONS.md`

No values are changed in this phase. The single `PCNR_APPROVED` gate (default 0 in `00_config.sas`) covers both files; Phase 24 cannot run until both are complete and the gate flips.

</domain>

<decisions>
## Implementation Decisions

### D-01: Sentinel Matching — Seed and Discover (PCM-D-21)

Normalize before matching: uppercase, trim, collapse internal whitespace. Keep both the exact
raw value (display only) and the normalized value (drives matching) in the output.

**Key:** `(variable, raw_hex)` — not `(variable, raw_value)`. PROC IMPORT trims leading and
trailing blanks, so `"? "` round-trips as `"?"` and its `raw_len` mismatches. Hex encoding
survives the CSV round-trip intact and also handles non-ASCII values (see D-04).

**Auto-candidates (exact match on normalized value):**
`?`, `??`, `-`, `--`, `.`, `UNKNOWN`, `UNK`, `N/A`, `NA`, `NULL`, `MISSING`,
`NOT DOCUMENTED`, `NOT RECORDED`.

**Whitespace-only values:** the relevant cases are tab (`'09'x`), carriage return / line feed
(`'0D'x`/`'0A'x`), and non-breaking space (`'A0'x`). Scan for these explicitly; plain all-blank
character values are already SAS missing and need no further treatment. Control characters
receive a normalized token in the `normalized_value` column rather than a blank — `<TAB>`,
`<CRLF>`, `<NBSP>` — so a wildcard row can target them by name, not by empty string.

**Contains matches → REVIEW class only, never AUTO.** Compound forms like
`UNKNOWN/NOT DOCUMENTED` and `OTHER/UNKNOWN` are flagged REVIEW by a contains rule.
Exact-match-only for AUTO prevents false positives (`NA` catching `NATIVE`, `NA+` lab text, etc.).

**Known artifacts included explicitly:** the 2-byte encounter placeholder and literal `NULL` are
listed even though already known, so `sentinel_decisions.csv` covers them on the record.

This seed list and these matching rules are recorded as **PCM-D-21** in DECISIONS.md.

### D-02: Ambiguous Value List (PCNR-03)

AMBIGUOUS class — never auto-classified; every AMBIGUOUS candidate requires a per-variable
decision row (wildcard rows may NOT resolve AMBIGUOUS candidates — see D-04):

- PCNR-03 base list: `None`, `Not applicable`, `Declined`, `Refused`, `Other`
- Additional: `NOT ASSESSED`, `NOT PERFORMED`, `PENDING`, `UNABLE TO OBTAIN`,
  `NOT SPECIFIED`, `PATIENT DECLINED`
- `UNKNOWN` in demographic columns → AMBIGUOUS for those columns even though it is AUTO
  elsewhere (legitimate category in race, ethnicity, sex, insurance)
- `0` in count or score columns → AMBIGUOUS (scoped to those column lists only; numeric zeros
  in other columns are not candidates and would flood the report)

**Demographic columns** and **count/score columns** are hardcoded reviewable lists in the
program header, echoed into `23_sentinel_candidates.csv` as a `column_group` column
(`DEMOGRAPHIC`, `SCORE`, or blank). This makes the scope auditable without reading source code.

**Single file:** Everything in `qc/23_sentinel_candidates.csv` with a `candidate_class` column.
Sort order: AMBIGUOUS rows first, then REVIEW, then AUTO.

**`candidate_class` is a clean enum: AUTO / REVIEW / AMBIGUOUS.** Non-ASCII flag is a
separate `non_ascii_flag` column (see D-04) and does not modify `candidate_class`.

### D-03: Numeric Sentinel Scan (PCNR-02)

Candidates: `-999, -99, -9, 99, 999, 777, 888, 9999, 99999`. Include an IS NOT MISSING
guard on every numeric scan. `-999` is known in clock variables; `999` can be a real value
elsewhere.

**Numeric candidates go into `sentinel_decisions.csv`** with `var_type = num`. The default
pre-filled action is `KEEP` (safe choice is the easy choice). No numeric value is recoded
unless PCM-D-24 explicitly approves it for that variable by changing the action to `MISSING`.
This gives Phase 24 a machine-readable source for any approved numeric recodes rather than
requiring it to parse DECISIONS.md prose.

**Numeric keying:** `raw_value = strip(put(x, best32.))`. `raw_hex` is the hex of that text
string (i.e., `put(strip(put(x, best32.)), $hex.)`), not the float bytes of the numeric value.
**Wildcards are not allowed for `var_type = num`.** PCM-D-24 approves per variable; a wildcard
would bypass that per-variable requirement.

### D-04: `sentinel_decisions.csv` Schema

```
variable, raw_value, raw_hex, raw_len, normalized_value, var_type, n_rows, pct_rows,
column_group, candidate_class, non_ascii_flag, match_rule, action, rationale,
decided_by, decided_date
```

- **Key is `(variable, raw_hex)`.** `raw_value` is display-only; `raw_hex` is what the gate
  uses for matching. This survives CSV round-trips. Do NOT use PROC IMPORT to read either gate
  file — hex values like `30`, `39`, `09` look numeric and will be mis-typed, breaking every
  key lookup. Read both files with a DATA step `infile` using explicit `$` informats for every
  column. (Add to PCM traps: "never PROC IMPORT a gate file — use DATA step infile with $
  informats" — PCM-T-16.)
- **`non_ascii_flag`:** set when the raw value contains bytes outside `'20'x`–`'7E'x`. The
  hex representation is still written to `raw_hex`; `raw_value` may be blank or best-effort.
  `candidate_class` is unchanged — `non_ascii_flag` is a separate boolean column.
- **`role` column:** present in `sentinel_decisions.csv` as a display-only convenience column
  carried from the candidates CSV. The gate reads `role` exclusively from `docs/pcnr_name_map.csv`
  (the human-confirmed version) and ignores any `role` column in the decisions file. This prevents
  the two sources from disagreeing silently. DROP rows in the decisions file are skipped by the
  gate based on the name map's `role`, not the decisions file's.
- **`action` values:** `MISSING` or `KEEP` only. No RECODE — value remapping is harmonization
  and 10b already handles it.
- **`variable = *` wildcard rows:** A `*` row matches on `normalized_value` across all KEEP/KEY
  columns. Per-variable rows (keyed on `raw_hex`) override it.
  - **Wildcard rows may resolve AUTO and REVIEW candidates only. Wildcards are not eligible
    to resolve AMBIGUOUS candidates.** The gate fails if any AMBIGUOUS candidate in a KEEP or
    KEY column lacks a per-variable decision row — regardless of whether a wildcard would
    otherwise cover its `normalized_value`.
  - **Wildcards are not allowed for `var_type = num`** (see D-03).
- **Gate checks both directions:**
  - Abort if any KEEP/KEY candidate has no decision (missing per-variable or wildcard coverage).
  - Abort if any AMBIGUOUS KEEP/KEY candidate lacks a per-variable row.
  - Abort if any per-variable decision row's `(variable, raw_hex)` is absent from the scan
    (stale per-variable decision).
  - Abort if any wildcard row's `normalized_value` appears in no KEEP/KEY column's scan
    (stale wildcard — a `*` row matching zero columns always fails this check).
  - Abort if any wildcard row has `var_type = num` (numeric approvals must be per-variable).
  - Abort if any wildcard row lacks `var_type = char` (every wildcard row must be explicitly typed).
  - Abort if any wildcard row's `normalized_value` matches only numeric candidates in the scan
    (wildcard resolving a numeric candidate by its text representation bypasses PCM-D-24).
- **Gate placement:** the gate check runs at the top of program 24, in a `%pcnr_gate_check`
  macro. Program 23 never runs the gate — it only generates drafts. This ensures the files
  are re-validated at the point of use, after any human edits to the `docs/` copies.
- **No confirmed flag.** A non-blank `action` serves as confirmation; one signal is enough.

### D-05: `pcnr_name_map.csv` Schema

```
source_name, source_label, role, h_strip, proposed_name, override_name, final_name,
name_len, collision_flag, id_flag
```

- **`role` values:** `KEY`, `KEEP`, or `DROP`.
  - KEY: `pecan_ID`, `PRECEDE_STUDY_ID`, `ENCRYPTED_MRN`, `ENCRYPTED_ENCOUNTER` — stay
    unprefixed per PCM-D-22. Final name is blank.
  - KEEP: analysis columns — get `pcnr_` prefix (with `h_` stripping per below).
  - DROP: raw columns superseded by an `h_*` version. Final name is blank.
- **DROP proposal:** The program should propose `role = DROP` for any raw column that
  `concept_decisions.csv` maps to an `h_*` column. Gerard confirms each DROP proposal rather
  than hunting for raw/h_ pairs manually.
- **`h_strip` column (Y/N):** Records whether the `h_` prefix was removed before prefixing
  with `pcnr_`. **Decision: strip `h_` and mark the raw counterpart DROP.** This is resolved
  at the same checkpoint as PCM-D-23 (they change every proposed name). Record as part of
  PCM-D-23.
- **Proposed name:** `pcnr_` + source name (after `h_` strip), truncated to 32 characters by
  the PCM-D-23 rule.
- **Truncation rule (PCM-D-23):** Algorithm:
  1. If `length("pcnr_" || name) <= 32`, no truncation needed — leave it alone.
  2. Otherwise: `final = "pcnr_" || head || "_" || final_token`, where `final_token` is the
     substring after the last `_` in the (possibly `h_`-stripped) source name, and `head` is
     the source name (minus `final_token` and its `_`) trimmed so the total is exactly 32 chars.
  3. **Fallback** (no underscore in the name, or `final_token` alone is > 12 characters):
     plain tail truncation to 32 characters total.
  4. `collision_flag = 1` if the resulting `final_name` matches any other row case-insensitively.

  The exact algorithm is confirmed at the PCM-D-23 checkpoint before the name map draft is
  generated. The planner should include a real example from `g.master_data_harmonized` with a
  name longer than 27 characters to verify the algorithm produces the expected result.
- **Final name:** `coalesce(override_name, proposed_name)` for KEEP rows; blank for KEY and DROP.
- **Validation runs on `final_name` for KEEP rows:**
  - ≤ 32 characters and valid SAS V7 name
  - Unique case-insensitively across all final names
  - No final name collides with a KEY name
  - Every source column appears exactly once in the map (completeness check)
  - DROP rows have a blank `final_name`
- **`collision_flag`:** set when `final_name` matches another row case-insensitively. Means only collision.
- **`id_flag`:** separate column; set for any KEEP row whose source name matches `*_ID`,
  `*STUDY_ID*`, or `ENCRYPTED_*` and is not on the KEY list. Surfaces accidental omissions like
  `PRECEDE_Study_ID_1` before it gets a `pcnr_` prefix. Keeping it separate means validation
  logic for collision and for ID leakage is independently readable and testable.
- **Original name preserved as variable label** in the built dataset for traceability.

### D-06: Single PCNR_APPROVED Gate and Draft/Docs Split

**Draft/docs split (critical):** Program 23 writes drafts only:
- `qc/23_sentinel_decisions_DRAFT.csv`
- `qc/23_pcnr_name_map_DRAFT.csv`

Program 23 must **never write to `docs/`**. No runtime guard for this — the protection is
structural: program 23 simply has no `file=` or `outfile=` statement pointing at `docs/`.
The plan's acceptance criteria must include a static check: `grep -n "file=" sas/23_pcnr_inventory.sas`
must show no `docs/` paths. A runtime abort guard is not needed and would block every full
pipeline run after `PCNR_APPROVED = 1` is set.

The human copies drafts to `docs/` and edits them there. From that point, the `docs/` files
are human-owned.

**Gate placement:** `%pcnr_gate_check` macro runs at the top of program 24. Program 23 does
not run the gate. Program 24's session has no access to program 23's WORK data, so the gate
reads `qc/23_sentinel_candidates.csv` from disk using a DATA step `infile` with explicit `$`
informats per PCM-T-16. This is the authoritative candidate list for coverage and stale checks.

**Fingerprint:** Program 23 writes a one-line `qc/23_sentinel_fingerprint.txt` alongside the
candidates CSV: source nobs, nvars, and run timestamp of `g.master_data_harmonized` (read
from SASHELP.VTABLE or PROC CONTENTS). The gate aborts if the current `g.master_data_harmonized`
nobs or nvars does not match the fingerprint. This prevents a stale candidates file from a
prior run passing validation silently.

Other gate behaviors:
- Program 23 can be rerun freely to refresh drafts after source data changes.
- The stale-decision check surfaces drift between refreshed drafts and the human-edited
  `docs/` files (gate re-reads `docs/` at program 24 runtime).

**Gate flag:** `PCNR_APPROVED` in `00_config.sas`, default 0. Pattern: same as `D15_APPROVED`.
One flag covers both files; two flags create a partial-approval state with no valid use.

### D-09: Git Tracking and PHI Containment for Gate Files

**`.gitignore` has `*.csv` globally.** The gate files (`docs/sentinel_decisions.csv`,
`docs/pcnr_name_map.csv`) must be committed with `git add -f` — the same mechanism used
for `docs/concept_decisions.csv`, which is already tracked despite the global rule. The
plan must include explicit `git add -f` steps for both files.

**`qc/` CSV drafts must NOT be committed.** `qc/23_sentinel_decisions_DRAFT.csv` and
`qc/23_pcnr_name_map_DRAFT.csv` live on P: drive and stay there. They are already excluded
by `*.csv` in `.gitignore` and must not be force-added.

**`qc/23_sentinel_candidates.csv` must NOT be committed.** REVIEW rows from free-text columns
(procedure descriptions, notes fields) may contain patient text verbatim in `raw_value` and
`raw_hex`. This file lives on P: only.

**PHI mitigation for committed `docs/sentinel_decisions.csv`:** Restrict the contains rule
(which generates REVIEW rows) to columns where free text is plausible. Either:
- Exclude columns with SAS length > 50 from the contains rule (procedure/notes fields tend
  to be long), or
- Hardcode an exclusion list of known free-text columns in the program header.
In either case, long-text columns are still swept by the exact-match AUTO rule (exact sentinel
hits are short strings and safe to commit); only the contains sweep is restricted.
Planner should propose the exclusion approach based on `qc/03_contents_all.txt` column lengths.

**Canonical refs confirmed:**
- `docs/concept_decisions.csv` — tracked in git (force-added before `*.csv` rule; confirmed via `git ls-files`)
- `qc/03_contents_all.txt` — tracked in git (confirmed via `git ls-files`); planner can read it
- `docs/DATA_DICTIONARY.xlsx` — NOT tracked (`*.xlsx` ignored, lives on P: only); do not reference as a readable file in plans

### PCM-T-16: Never PROC IMPORT a Gate File

PROC IMPORT mis-types hex strings that look numeric (`30`, `39`, `09` → integer), breaking
every key lookup in `sentinel_decisions.csv` and `pcnr_name_map.csv`. Always read gate files
with a DATA step `infile` using explicit `$` informats for every column.

Add to `docs/DECISIONS.md` trap list alongside PCM-T-14 and PCM-T-15.

### PCM-D-21 through PCM-D-25 Assignment

To give the planner unambiguous targets for DECISIONS.md entries:

- **PCM-D-21:** Sentinel seed list and matching rules (D-01 above)
- **PCM-D-22:** Key columns that stay unprefixed (`pecan_ID`, `PRECEDE_STUDY_ID`, `ENCRYPTED_MRN`, `ENCRYPTED_ENCOUNTER`) — already implicit from v2.0; record it explicitly
- **PCM-D-23:** `pcnr_` name construction rule: `h_` stripping (Y/N) and truncation algorithm (middle-truncate, preserve final token) — checkpoint before name map is generated
- **PCM-D-24:** Numeric sentinel approval gate — any numeric `MISSING` action approved per-variable here; default is `KEEP`
- **PCM-D-25:** Ambiguous-value column scope — the hardcoded demographic and count/score column lists; reviewable before gate flips

### D-07: Proposing Demographic and Count/Score Column Lists

The planner cannot run PROC CONTENTS against P:. The demographic and count/score column lists
(PCM-D-25) are therefore proposed one of two ways:
1. **Preferred:** extract candidate column names from `docs/DATA_DICTIONARY.xlsx` or
   `qc/03_contents_all.txt` (both committed and readable). The planner reads those and proposes
   a list; Gerard confirms before the gate is set.
2. **Fallback:** program 23 writes a first-run draft with `column_group` blank for all rows.
   Gerard fills in the lists manually in the draft before copying to `docs/`.

Whichever approach is used, the final lists are hardcoded in the program header and echoed
into `23_sentinel_candidates.csv` as the `column_group` column.

### D-08: DROP Rows Skip Sentinel Decisions

Candidates in columns with `role = DROP` require no entry in `sentinel_decisions.csv` — those
columns never reach `g.pcnr_harmonized`. The gate explicitly skips DROP-role candidates in its
coverage check. `role` is carried from the name map draft into `23_sentinel_candidates.csv` so
the skip reason is visible to reviewers.

### Claude's Discretion

- Exact column widths and sort tiebreakers within candidate_class groups
- Whether PCNR-02 numeric output is a separate section within `23_sentinel_candidates.csv` or its own `23_numeric_sentinels.txt` (REQUIREMENTS says "counts reported" — either is acceptable)
- Middle-truncation algorithm details (propose in plan with real example from contents export; Gerard confirms at checkpoint)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase requirements
- `.planning/REQUIREMENTS.md` §Sentinel & Name Inventory — PCNR-01 through PCNR-06 acceptance criteria

### Existing pipeline programs (patterns to follow)
- `sas/00_config.sas` — gate macro pattern (`D15_APPROVED`, `DOMAIN_MAP_APPROVED`); `PCNR_APPROVED` goes here
- `sas/10b_concept_harmonize.sas` — reads `docs/concept_decisions.csv`; gate abort pattern to replicate (extend with stale-decision and wildcard-vs-AMBIGUOUS checks)
- `sas/10_concept_profile.sas` — value profiling / sweep pattern; starting point for the character column sweep

### Gate file reference (schema to extend, not copy)
- `docs/concept_decisions.csv` — columns: concept, varname, value_txt, n_rows, target_value, confirmed, harmonized_name, priority, reviewer, comment
- `docs/concept_decisions_TEMPLATE.csv` — blank template showing expected headers

### Column inventory (for proposing PCM-D-25 lists without running PROC CONTENTS against P:)
- `qc/03_contents_all.txt` — committed PROC CONTENTS export; planner uses this to propose demographic and count/score column lists, and to find names > 27 characters for truncation examples
- `docs/DATA_DICTIONARY.xlsx` — NOT tracked in git (`*.xlsx` ignored; lives on P: only); do not reference as a readable file in plans

### Source dataset
- `g.master_data_harmonized` — 41,150 rows, 175 columns (read-only; PCM-T-02 forbids writing to it)

### Decisions log
- `docs/DECISIONS.md` — PCM-D-21 through PCM-D-25 will be added here; read existing entries for attribution format

No external specs — requirements fully captured in decisions above and REQUIREMENTS.md.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/10_concept_profile.sas` — value-sweep pattern against harmonized dataset; starting point for the character column sweep in program 23
- `sas/10b_concept_harmonize.sas` — gate abort pattern: reads decisions CSV, checks for missing decisions, aborts with `%fail_out`; replicate with three new checks (missing decision, stale per-variable, stale wildcard)
- `sas/00_config.sas` `%fail_out` macro — standard abort path used across all gate checks

### Established Patterns
- WORK-then-promote for any output dataset (PCM-T-02) — program 23 is read-only so no dataset is promoted, but applies to any intermediate work datasets
- Gate default: `%let PCNR_APPROVED = 0;` with `%put NOTE:` line — matches D15_APPROVED pattern
- `ODS EXCEL` + `styles.uf_inventory` for any Excel output (UF blue #0021A5 headers) — use if a summary workbook is produced
- PCM-C-05: each program runs as a separate `sas.exe` session via `run_pipeline.cmd`

### Integration Points
- `sas/00_config.sas` — add `%let PCNR_APPROVED = 0;`
- `run_pipeline.cmd` — program 23 wired after program 20 and before program 24 (Phase 25 handles full wiring, not this phase)
- `docs/` — human-owned gate files (`sentinel_decisions.csv`, `pcnr_name_map.csv`); program 23 never writes here
- `qc/` — program outputs: `23_sentinel_candidates.csv`, `23_case_variants.csv`, `23_sentinel_decisions_DRAFT.csv`, `23_pcnr_name_map_DRAFT.csv`

</code_context>

<specifics>
## Specific Ideas

- **Hex key for character values:** `raw_hex = put(value, $hex.)`. Gate uses `raw_hex` for matching; `raw_value` is display only. Handles whitespace variants and non-ASCII in one mechanism. Never read gate files with PROC IMPORT (PCM-T-16).
- **Hex key for numeric candidates:** `raw_hex = put(strip(put(x, best32.)), $hex.)` — hex of the text representation, not the float bytes.
- **Control-character normalized tokens:** tab → `<TAB>`, CR/LF → `<CRLF>`, NBSP (`'A0'x`) → `<NBSP>` in `normalized_value`. Allows wildcard targeting by token, not by empty string.
- **Wildcard coalesce order:** gate resolves each KEEP/KEY candidate by looking for a per-variable row first (`variable = that_column`), then a wildcard row (`variable = *`). If neither → gate failure. AMBIGUOUS candidates must have a per-variable row or the gate fails even if a wildcard covers the `normalized_value`.
- **Stale wildcard detection:** a `*` row whose `normalized_value` appears in no KEEP/KEY column's scan is stale; gate aborts.
- **DROP proposal from concept_decisions.csv:** program reads `docs/concept_decisions.csv`, extracts `varname` → `harmonized_name` pairs where `harmonized_name` starts with `h_`, and proposes `role = DROP` for those raw columns in the name map draft. Gerard confirms rather than hunts.
- **PCM-D-23 truncation example:** planner should extract a real name > 27 characters from `qc/03_contents_all.txt` and show the algorithm's output for that name in the plan. The `pcnr_Long_Variable_Name_DATE` example used in discussion was 28 characters and would not trigger truncation — it is not a valid illustration.
- **PCM-D-25 column lists:** planner proposes from `qc/03_contents_all.txt` or `docs/DATA_DICTIONARY.xlsx` (both committed). Gerard confirms before gate is set.
- **Draft/docs workflow:** program 23 → writes `qc/*_DRAFT.csv` + `qc/23_sentinel_fingerprint.txt` → human copies drafts to `docs/` and edits → `git add -f docs/sentinel_decisions.csv docs/pcnr_name_map.csv` → program 24 gate reads `docs/` files + fingerprint at runtime. No runtime guard in program 23; protection is structural (no `file=docs/` in program 23).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 23-sentinel-name-inventory*
*Context gathered: 2026-09-28*
*Revised: 2026-09-28*
