# Phase 23: Sentinel & Name Inventory - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-28
**Phase:** 23-sentinel-name-inventory
**Areas discussed:** Sentinel pattern list, Ambiguous-value handling, sentinel_decisions.csv schema, pcnr_name_map.csv

---

## Sentinel Pattern List

| Option | Description | Selected |
|--------|-------------|----------|
| Lock the list now | Exact list only; no discovery | |
| Seed and discover | Lock a seed list; program also surfaces anything that looks like a placeholder | ✓ |
| Fully dynamic | No seed list; pure discovery | |

**User's choice:** Seed and discover. Auto-candidates by exact match on normalized value; contains-matches go to REVIEW class only, never AUTO.

**Notes:** Compound forms (`UNKNOWN/NOT DOCUMENTED`) surface via contains-match but land in REVIEW — prevents false positives (e.g., `NA` catching `NATIVE`). Known artifacts (`NULL`, 2-byte encounter placeholder) included explicitly even though already known, so the decisions file covers them on the record.

---

## Ambiguous-Value Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Use PCNR-03 base list only | `None`, `Not applicable`, `Declined`, `Refused`, `Other`, `0` | |
| Extend and keep single file | Expanded list; one CSV with candidate_class column | ✓ |
| Separate AMBIGUOUS file | Two output files | |

**User's choice:** Extended list in a single file. Added: `NOT ASSESSED`, `NOT PERFORMED`, `PENDING`, `UNABLE TO OBTAIN`, `NOT SPECIFIED`, `PATIENT DECLINED`. Column-type override: `UNKNOWN` is AMBIGUOUS for demographic columns (race, ethnicity, sex, insurance) even though it's AUTO elsewhere. `0` in count/score columns → AMBIGUOUS.

**Notes:** Single file (`23_sentinel_candidates.csv`) with `candidate_class` avoids two-list sync problem. Sort order: AMBIGUOUS first, then REVIEW, then AUTO.

---

## sentinel_decisions.csv Schema

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror concept_decisions.csv exactly | Same columns as existing gate file | |
| New schema, concept_decisions conventions | New columns for sentinel use-case, keep confirmed/n_rows pattern | ✓ |

**User's choice:** New schema: `variable, raw_value, raw_len, normalized_value, var_type, n_rows, pct_rows, candidate_class, match_rule, action, rationale, decided_by, decided_date`.

**Notes:**
- `action` is MISSING or KEEP only — RECODE excluded (harmonization is 10b's job)
- `variable = *` wildcard rows allowed; per-variable rows override — prevents hundreds of identical decisions for universal sentinels
- Gate checks BOTH directions: missing decision → abort; stale decision (no matching candidate) → abort
- `raw_len` catches whitespace variants invisible in Excel
- Non-ASCII values (ESOPH artifacts) flagged rather than written raw into CSV

---

## pcnr_name_map.csv

| Option | Description | Selected |
|--------|-------------|----------|
| Deterministic truncation only | Drop trailing characters automatically | |
| Proposal + manual override column | `proposed_name` + `override_name`; `final_name = coalesce(override, proposed)` | ✓ |
| Manual map only | Human writes every name by hand | |

**User's choice:** `source_name, source_label, role, proposed_name, override_name, final_name, name_len, collision_flag`. `role` column: KEY (unprefixed), KEEP (get prefix), DROP (superseded by h_* version).

**Notes:**
- Final name validation: ≤ 32 chars, valid V7 name, unique case-insensitively, no collision with KEY names
- Original name preserved as variable label in built dataset
- PCM-D-23 truncation algorithm: a checkpoint before the program runs — planner should surface options (trailing-char drop vs abbreviation table) for Gerard to decide
- Single PCNR_APPROVED gate covers both files; two flags create an invalid partial-approval state

---

## Claude's Discretion

- Exact column widths and sort tiebreakers within candidate_class groups
- Whether PCNR-02 numeric output is a separate section in `23_sentinel_candidates.csv` or its own txt report
- PCM-D-23 truncation algorithm (surface options; Gerard confirms before name map generated)

## Deferred Ideas

None — discussion stayed within phase scope.
