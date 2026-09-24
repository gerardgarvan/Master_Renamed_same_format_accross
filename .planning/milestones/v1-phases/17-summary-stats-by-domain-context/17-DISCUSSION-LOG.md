# Phase 17: Summary Statistics by Variable Domain — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-03
**Phase:** 17-summary-stats-by-domain-context
**Areas discussed:** Domain definition, Dataset scope (D-01), Output format, Statistics depth (D-02, D-03)

---

## Domain definition

| Option | Description | Selected |
|--------|-------------|----------|
| Data-source ownership (md1–md8) | Group variables by which master file owns them | |
| Clinical / conceptual domain | Five domains: Sociodemographics, Preoperative, Cognitive, Intraoperative, Outcomes | ✓ |
| Variable category (type-based) | Numeric vs character, identifier vs measure vs flag | |
| Patient subgroup | Stats stratified by patient characteristic | |

**User's choice:** Clinical / conceptual domain (D1–D5 taxonomy from pre-written spec)

**Notes:** User pointed to `summary-stats-by-domain-CONTEXT (1).md` at repo root — a fully
worked draft spec. Domain definitions, assignment rules, and pitfalls were already documented
there. All subsequent decisions reference that spec.

---

## Domain assignment source

| Option | Description | Selected |
|--------|-------------|----------|
| Hard-coded lookup table in SAS | PROC FORMAT with domain labels per variable name | |
| Read from precede_dictionary.csv | Add domain column to existing CSV | |
| Read from new domain-map CSV | Separate variable → domain file | |
| You decide | Claude picks practical approach | |

**User's choice:** Referred to pre-written spec — domain assignment follows the three-rule
framework (timing first, analytic role second, instrument membership overrides) with
`domain_rationale` column in crosswalk. Implementation approach left to planner.

---

## D-01: Source dataset for D2 frailty and D3 cognitive

| Option | Description | Selected |
|--------|-------------|----------|
| (a) analysis_base only — D3 empty, D2 without frailty | Simplest, no new join | |
| (b) Build analysis_base_ext — left-join frailty/cognitive from master_data_merged | All five domains covered | ✓ |
| (c) Split — partial now, defer D3+frailty | Avoid join complexity today | |

**User's choice:** Option (b) — build `g.analysis_base_ext`
**Notes:** PRECEDE_STUDY_ID type conflict (CHAR vs NUM8 in md7) must be resolved before joining.

---

## D-02: Denominator for categorical percentages

| Option | Description | Selected |
|--------|-------------|----------|
| Both: n (%) on non-missing + separate n-missing column | Reader sees completeness + distribution | ✓ |
| Non-missing denominator only | Cleaner table, hides missingness | |
| Full 41,150 denominator | Standard epi convention | |

**User's choice:** Both — `n (%)` on non-missing with separate `n missing` column

---

## D-03: Year stratification

| Option | Description | Selected |
|--------|-------------|----------|
| Pooled only | Compact, fastest to build | |
| Pooled + per-year column blocks | Matches 'covering all years' intent | ✓ |
| Per-year only | Shows trends, loses overall picture | |

**User's choice:** Pooled + per-year column blocks

---

## Output format

| Option | Description | Selected |
|--------|-------------|----------|
| (1) version — more detailed spec | domain_rationale in crosswalk, richer QC sheet | ✓ |
| Base version — simpler crosswalk | No domain_rationale | |
| Reconcile both | Claude picks per section | |

**User's choice:** `summary-stats-by-domain-CONTEXT (1).md` is the authoritative spec

---

## Statistics depth (per-year blocks)

| Option | Description | Selected |
|--------|-------------|----------|
| Same full set per year block | Complete but very wide sheets | ✓ |
| Reduced set per year (n, n-missing, mean/median only) | Narrower, more readable | |
| You decide | Claude picks balance | |

**User's choice:** Full statistic set repeated in each year block

---

## Claude's Discretion

- How "in data only" variables are handled (not in PRECEDE dictionary)
- Whether `g.analysis_base_ext` is materialized as `work.` or permanent dataset

## Deferred Ideas

- None — discussion stayed within phase scope
