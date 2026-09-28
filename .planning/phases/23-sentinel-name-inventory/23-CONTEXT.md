# Phase 23: Sentinel & Name Inventory - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Enumerate every candidate placeholder value and every column name that cannot accept the
`pcnr_` prefix — then capture human decisions into gate files — before any values are changed.
Program `sas/23_pcnr_inventory.sas` reads `g.master_data_harmonized` read-only.

Deliverables:
- `qc/23_sentinel_candidates.csv` — every character column swept; one `candidate_class` column (AUTO / REVIEW / AMBIGUOUS); sorted with AMBIGUOUS first
- `qc/23_case_variants.csv` — case and whitespace variant report (report only)
- `docs/sentinel_decisions.csv` — human decision for every AUTO and REVIEW candidate; gate reads this
- `docs/pcnr_name_map.csv` — proposed and final pcnr names for every column
- PCM-D-21..D-25 resolved and attributed in `docs/DECISIONS.md`

No values are changed in this phase. The single `PCNR_APPROVED` gate (default 0 in `00_config.sas`) covers both files; Phase 24 cannot run until both are complete and the gate flips.

</domain>

<decisions>
## Implementation Decisions

### D-01: Sentinel Matching — Seed and Discover

Normalize before matching: uppercase, trim, collapse internal whitespace. Keep both the exact
raw value and the normalized value in the output (raw visible for context; normalized drives matching).

**Auto-candidates (exact match on normalized value):**
`?`, `??`, `-`, `--`, `.`, `UNKNOWN`, `UNK`, `N/A`, `NA`, `NULL`, `MISSING`,
`NOT DOCUMENTED`, `NOT RECORDED`, blank or whitespace-only strings.

**Contains matches → REVIEW class only, never AUTO.** Compound forms like
`UNKNOWN/NOT DOCUMENTED` and `OTHER/UNKNOWN` are flagged REVIEW by a contains rule.
Exact-match-only for AUTO prevents false positives (`NA` catching `NATIVE`, `NA+` lab text, etc.).

**Known artifacts included explicitly:** the 2-byte encounter placeholder and literal `NULL` are
listed even though they're already known, so `sentinel_decisions.csv` covers them on the record.

### D-02: Ambiguous Value List (PCNR-03)

AMBIGUOUS class (never auto-classified, always require a human decision):
- PCNR-03 base list: `None`, `Not applicable`, `Declined`, `Refused`, `Other`, `0`
- Additional: `NOT ASSESSED`, `NOT PERFORMED`, `PENDING`, `UNABLE TO OBTAIN`,
  `NOT SPECIFIED`, `PATIENT DECLINED`
- `UNKNOWN` in demographic columns (race, ethnicity, sex, insurance) → AMBIGUOUS for those
  columns even though it is AUTO elsewhere (it is often a legitimate category in those columns)
- `0` in any count or score column → AMBIGUOUS

**Single file:** Everything stays in `qc/23_sentinel_candidates.csv` with a `candidate_class`
column. A separate file would require keeping two lists in sync; the gate checks one CSV.
Sort order: AMBIGUOUS rows first, then REVIEW, then AUTO.

### D-03: Numeric Sentinel Scan (PCNR-02)

Report-only. Candidates: `-999`, `-99`, `-9`, `999`, `9999` (plus `99`, `9999`, `99999`, `777`, `888` per REQUIREMENTS). Include an IS NOT MISSING guard on every numeric scan. `-999` is known in clock variables; `999` can be a real value elsewhere — no auto-classification allowed.

No numeric value is recoded unless PCM-D-24 explicitly approves it for that variable (Phase 23 does not set that approval).

### D-04: `sentinel_decisions.csv` Schema

```
variable, raw_value, raw_len, normalized_value, var_type, n_rows, pct_rows,
candidate_class, match_rule, action, rationale, decided_by, decided_date
```

- **`action` values:** `MISSING` or `KEEP` only. No RECODE — value remapping is harmonization
  and 10b already handles it.
- **`variable = *` wildcard rows allowed.** A `*` row covers every column; per-variable rows
  override it. Prevents hundreds of identical hand-entries for universal sentinels like `?`.
- **Gate checks both directions:**
  - Abort if any current candidate has no decision (standard gate behavior)
  - Also abort if any decision row matches no current candidate (catches stale decisions after
    source changes)
- **`raw_len`** catches whitespace variants that are invisible in Excel.
- **CSV safety:** keep file ASCII. If a candidate value contains non-ASCII characters (e.g.,
  ESOPH multi-byte artifact), flag it in `candidate_class` rather than writing the raw bytes
  into the CSV.

Follows `concept_decisions.csv` conventions (confirmed flag, n_rows) while adding the
fields needed for the sentinel use-case.

### D-05: `pcnr_name_map.csv` Schema

```
source_name, source_label, role, proposed_name, override_name, final_name,
name_len, collision_flag
```

- **`role` values:** `KEY`, `KEEP`, or `DROP`.
  - KEY: `pecan_ID`, `PRECEDE_STUDY_ID`, `ENCRYPTED_MRN`, `ENCRYPTED_ENCOUNTER` — stay
    unprefixed per PCM-D-22.
  - KEEP: analysis columns — get `pcnr_` prefix.
  - DROP: raw columns superseded by an `h_*` version — this is where raw-vs-h_ is recorded.
- **Proposed name:** `pcnr_` + source name (strip `h_` prefix if that rule is adopted) truncated
  to 32 characters. Truncation rule to be recorded as PCM-D-23 in DECISIONS.md.
- **Final name:** `coalesce(override_name, proposed_name)`.
- **Validation runs on `final_name`:**
  - ≤ 32 characters and valid SAS V7 name
  - Unique case-insensitively across all final names
  - No final name collides with a KEY name
- **Original name preserved as variable label** in the built dataset for traceability.

### D-06: Single PCNR_APPROVED Gate

One gate in `00_config.sas` validates both `sentinel_decisions.csv` and `pcnr_name_map.csv`.
Phase 24 needs both files anyway; two flags create a partial-approval state that has no valid
use. The name map is reviewed before the gate flips, not after.

Pattern: same as `D15_APPROVED` in `00_config.sas`.

### Claude's Discretion

- Exact column widths, sort tiebreakers within candidate_class groups in `23_sentinel_candidates.csv`
- Whether PCNR-02 numeric output goes into `23_sentinel_candidates.csv` as a separate section
  or its own `23_numeric_sentinels.txt` report (REQUIREMENTS says "counts reported" — either works)
- Exact PCM-D-23 truncation algorithm (drop trailing chars vs abbreviation table) — propose in
  the plan; Gerard confirms before the gate file is generated

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase requirements
- `.planning/REQUIREMENTS.md` §Sentinel & Name Inventory — PCNR-01 through PCNR-06 acceptance criteria

### Existing pipeline programs (patterns to follow)
- `sas/00_config.sas` — gate macro pattern (`D15_APPROVED`, `DOMAIN_MAP_APPROVED`); `PCNR_APPROVED` goes here
- `sas/10b_concept_harmonize.sas` — reads `docs/concept_decisions.csv`; gate abort pattern to replicate
- `sas/10_concept_profile.sas` — value profiling / sweep pattern; likely closest to what program 23 needs

### Gate file reference (schema to extend)
- `docs/concept_decisions.csv` — columns: concept, varname, value_txt, n_rows, target_value, confirmed, harmonized_name, priority, reviewer, comment
- `docs/concept_decisions_TEMPLATE.csv` — blank template showing the expected headers

### Source dataset
- `g.master_data_harmonized` — 41,150 rows, 175 columns (read-only; PCM-T-02 forbids writing to it)

### Decisions log
- `docs/DECISIONS.md` — PCM-D-21 through PCM-D-25 will be added here; read existing entries for attribution format

No external specs — requirements fully captured in decisions above and REQUIREMENTS.md.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/10_concept_profile.sas` — value-sweep pattern against harmonized dataset; starting point for
  the character column sweep in program 23
- `sas/10b_concept_harmonize.sas` — gate abort pattern: reads decisions CSV, checks for missing
  decisions, aborts with `%fail_out`; replicate for `sentinel_decisions.csv`
- `sas/00_config.sas` `%fail_out` macro — standard abort path used across all gate checks

### Established Patterns
- WORK-then-promote for any output dataset (PCM-T-02) — program 23 is read-only so no dataset is promoted, but the principle applies if any intermediate dataset is created
- Gate default: `%let PCNR_APPROVED = 0;` with `%put NOTE:` line — matches D15_APPROVED pattern
- `ODS EXCEL` + `styles.uf_inventory` for any Excel output (UF blue #0021A5 headers) — if a summary workbook is produced, use this style
- PCM-C-05: each program runs as a separate `sas.exe` session via `run_pipeline.cmd`

### Integration Points
- `sas/00_config.sas` — add `%let PCNR_APPROVED = 0;`
- `run_pipeline.cmd` — program 23 wired after program 20 and before program 24 (not done in this phase; Phase 25 handles full wiring)
- `docs/` — new files: `sentinel_decisions.csv`, `pcnr_name_map.csv`
- `qc/` — new outputs: `23_sentinel_candidates.csv`, `23_case_variants.csv`

</code_context>

<specifics>
## Specific Ideas

- **Wildcard row in sentinel_decisions.csv:** `variable = *` allows a single `MISSING` decision for `?` to cover every column without hundreds of identical rows. Per-variable rows override the wildcard. Gate must implement this coalesce logic.
- **Stale-decision check:** gate aborts if a decision row's `(variable, raw_value)` pair no longer appears in the candidate scan. This is new relative to the `concept_decisions.csv` pattern and must be implemented explicitly.
- **Column-type override for UNKNOWN:** the AMBIGUOUS rule for UNKNOWN in demographic columns (race, ethnicity, sex, insurance) requires the program to know which columns are "demographic." A small hardcoded list in the program is acceptable; or tag via `var_type` in the output.
- **`raw_len` column:** stores `length(raw_value)` before normalization. Whitespace variants with the same normalized form but different lengths appear as separate rows in the candidate list (so `"? "` and `"?"` are both reported, with different `raw_len`).
- **PCM-D-23 truncation rule:** to be decided by Gerard before the name map CSV is generated. Planner should surface options (trailing-char drop vs abbreviation table) and flag it as a checkpoint before the program runs.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 23-sentinel-name-inventory*
*Context gathered: 2026-09-28*
