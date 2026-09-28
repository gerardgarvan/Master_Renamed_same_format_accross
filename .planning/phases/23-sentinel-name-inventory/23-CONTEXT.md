# Phase 23: Sentinel & Name Inventory - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning
**Revised:** 2026-09-28 (11 corrections before planning — gate logic, keying, schema, name map rules, D-number assignments)

<domain>
## Phase Boundary

Enumerate every candidate placeholder value and every column name that cannot accept the
`pcnr_` prefix — then capture human decisions into gate files — before any values are changed.
Program `sas/23_pcnr_inventory.sas` reads `g.master_data_harmonized` read-only.

Deliverables:
- `qc/23_sentinel_candidates.csv` — every character column swept; `candidate_class` column (AUTO / REVIEW / AMBIGUOUS); sorted AMBIGUOUS first, then REVIEW, then AUTO
- `qc/23_case_variants.csv` — case and whitespace variant report (report only, no recoding)
- `docs/sentinel_decisions.csv` — human decision for **every** candidate (AUTO, REVIEW, and AMBIGUOUS); gate reads this
- `docs/pcnr_name_map.csv` — proposed and final pcnr names for every column
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
character values are already SAS missing and need no further treatment.

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

### D-04: `sentinel_decisions.csv` Schema

```
variable, raw_value, raw_hex, raw_len, normalized_value, var_type, n_rows, pct_rows,
column_group, candidate_class, non_ascii_flag, match_rule, action, rationale,
decided_by, decided_date
```

- **Key is `(variable, raw_hex)`.** `raw_value` is display-only; `raw_hex` is what the gate
  uses for matching. This survives CSV round-trips that strip whitespace.
- **`non_ascii_flag`:** set when the raw value contains bytes outside `'20'x`–`'7E'x`. The
  hex-only representation is written to `raw_hex`; `raw_value` may be blank or truncated.
  `candidate_class` is unchanged.
- **`action` values:** `MISSING` or `KEEP` only. No RECODE — value remapping is harmonization
  and 10b already handles it.
- **`variable = *` wildcard rows:** A `*` row matches on `normalized_value` across all columns.
  Per-variable rows (keyed on `raw_hex`) override it.
  - **Wildcard rows may resolve AUTO and REVIEW candidates only.**
  - **Every AMBIGUOUS candidate requires a per-variable row.** The gate enforces this: a
    wildcard decision against a candidate whose `candidate_class = AMBIGUOUS` is a gate failure.
- **Gate checks both directions:**
  - Abort if any current candidate has no decision.
  - Abort if any per-variable decision row's `(variable, raw_hex)` is absent from the scan
    (stale per-variable decision).
  - Abort if any wildcard row's `normalized_value` appears in no column's scan (stale wildcard).
  - A wildcard row that matches zero columns is always stale; the stale check prevents this from
    silently passing.
- **No confirmed flag.** A non-blank `action` serves as confirmation; one signal is enough.
  (Prior note about following `concept_decisions.csv`'s confirmed flag was incorrect — that
  column does not exist in the schema above.)

### D-05: `pcnr_name_map.csv` Schema

```
source_name, source_label, role, h_strip, proposed_name, override_name, final_name,
name_len, collision_flag
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
- **Truncation rule (PCM-D-23):** **Truncate the middle, preserve the final token.** Plain
  tail truncation collapses names that differ only by suffix (`_1`, `_2`, `_DATE`) into
  collisions. The middle-truncation approach preserves the trailing token (the part after the
  last `_`) while cutting characters from the interior. `collision_flag` catches any collisions
  that survive. Exact algorithm to be proposed in the plan and confirmed by Gerard at the
  checkpoint before the name map is generated; this is the recommended approach.
- **Final name:** `coalesce(override_name, proposed_name)` for KEEP rows; blank for KEY and DROP.
- **Validation runs on `final_name` for KEEP rows:**
  - ≤ 32 characters and valid SAS V7 name
  - Unique case-insensitively across all final names
  - No final name collides with a KEY name
  - Every source column appears exactly once in the map (completeness check)
- **Original name preserved as variable label** in the built dataset for traceability.

### D-06: Single PCNR_APPROVED Gate

One gate in `00_config.sas` validates both `sentinel_decisions.csv` and `pcnr_name_map.csv`.
Phase 24 needs both files anyway; two flags create a partial-approval state that has no valid
use. The name map is reviewed before the gate flips, not after.

Pattern: same as `D15_APPROVED` in `00_config.sas`.

### PCM-D-21 through PCM-D-25 Assignment

To give the planner unambiguous targets for DECISIONS.md entries:

- **PCM-D-21:** Sentinel seed list and matching rules (D-01 above)
- **PCM-D-22:** Key columns that stay unprefixed (`pecan_ID`, `PRECEDE_STUDY_ID`, `ENCRYPTED_MRN`, `ENCRYPTED_ENCOUNTER`) — already implicit from v2.0; record it explicitly
- **PCM-D-23:** `pcnr_` name construction rule: `h_` stripping (Y/N) and truncation algorithm (middle-truncate, preserve final token) — checkpoint before name map is generated
- **PCM-D-24:** Numeric sentinel approval gate — any numeric `MISSING` action approved per-variable here; default is `KEEP`
- **PCM-D-25:** Ambiguous-value column scope — the hardcoded demographic and count/score column lists; reviewable before gate flips

### Claude's Discretion

- Exact column widths and sort tiebreakers within candidate_class groups
- Whether PCNR-02 numeric output is a separate section within `23_sentinel_candidates.csv` or its own `23_numeric_sentinels.txt` (REQUIREMENTS says "counts reported" — either is acceptable)
- Middle-truncation algorithm details (propose in the plan; Gerard confirms at the checkpoint)

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
- `docs/` — new files: `sentinel_decisions.csv`, `pcnr_name_map.csv`
- `qc/` — new outputs: `23_sentinel_candidates.csv`, `23_case_variants.csv`

</code_context>

<specifics>
## Specific Ideas

- **Hex key:** `raw_hex = put(value, $hex.)` written alongside `raw_value`. Gate uses `raw_hex` for matching; Excel users read `raw_value`. This handles whitespace variants and non-ASCII in a single mechanism.
- **Wildcard coalesce order:** gate resolves each candidate by looking for a per-variable row first (`variable = that_column`), then a wildcard row (`variable = *`). If neither matches → gate failure. AMBIGUOUS candidates must have a per-variable row or the gate fails even if a wildcard would otherwise cover them.
- **Stale wildcard detection:** a `*` row whose `normalized_value` appears in no column in the current scan is stale. The gate must actively check this, not just skip unmatched decisions.
- **DROP proposal from concept_decisions.csv:** program reads `docs/concept_decisions.csv`, extracts `varname` → `harmonized_name` pairs where the harmonized name starts with `h_`, and sets `role = DROP` (proposed) for those raw columns in the name map. Gerard confirms rather than hunts.
- **PCM-D-23 middle-truncation:** preserve the final `_token`; cut characters from just before it to hit ≤ 32 chars. Example: `pcnr_Long_Variable_Name_DATE` → `pcnr_Long_Variabl_DATE` (cut middle, keep `_DATE`). `collision_flag` catches any remaining collisions.
- **PCM-D-25 column lists** (hardcoded in program header, echoed into `column_group`):
  - Demographic: to be proposed by planner from PROC CONTENTS of `g.master_data_harmonized` and confirmed by Gerard
  - Count/score: similarly proposed from PROC CONTENTS

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 23-sentinel-name-inventory*
*Context gathered: 2026-09-28*
*Revised: 2026-09-28*
