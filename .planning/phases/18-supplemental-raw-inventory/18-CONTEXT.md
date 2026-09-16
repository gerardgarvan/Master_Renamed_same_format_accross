# Phase 18: Supplemental Raw Inventory — Context

**Gathered:** 2026-09-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the two follow-on items from Phase 16:

1. **2022 ID mismatch diagnostic (PCM-D-16)** — Identify why r7/r8/r9 2022 IDs match 0 base rows. Print 5 base IDs not in r9 beside 5 r9 IDs not in base with their lengths, write to `qc\18_id_diagnostic.txt`, then abort with a named message. Human decides the resolution; PCM-D-16 cannot be auto-closed.

2. **Gap-fill counts (PCM-D-15 input)** — For every IN_BASE column across all files with >0 matched IDs (r1, r2, r3, r4, r5, r6 — r7/r8 excluded until 2022 ID resolved), compute base-missing-but-raw-populated counts. Write `qc\18_gap_candidates.txt`. Phase 18 ends with a `%let D15_APPROVED=0` gate; Gerard reviews the output, records the decision in `docs/DECISIONS.md`, then sets the flag before Phase 17 can proceed.

Read-only: nothing under `raw\` is written to and no `g.*` dataset is modified.

</domain>

<decisions>
## Implementation Decisions

### D-01: 2022 ID mismatch handling
- **D-01:** Program runs the diagnostic (print 5 base IDs not in r9 vs 5 r9 IDs not in base with lengths), writes `qc\18_id_diagnostic.txt`, then **aborts** with a named message. Gerard inspects and decides whether a numeric→char cast or other fix applies. PCM-D-16 cannot be auto-closed in code — the cause may be a true ID-series difference, not just a formatting artefact.

### D-02: Gap-fill scope
- **D-02:** Compute base-missing-but-raw-populated counts on **all matched files** — every IN_BASE column on r1, r2, r3, r4, r5, r6 (files with >0 matched IDs). r7 and r8 are excluded until the 2022 ID mismatch (PCM-D-16) is resolved. r9 is excluded because its IN_BASE columns (Latitude, Longitude, YEAR) are already in base. This gives PCM-D-15 the full picture without a second pass.

### D-03: PCM-D-15 decision gate
- **D-03:** Phase 18 ends with a `%let D15_APPROVED=0` gate — same pattern as Phase 17 Checkpoint 1. The program writes `qc\18_gap_candidates.txt` with the missing-value counts per column per file. Gerard reviews, records the approved columns in `docs/DECISIONS.md` (attributed to Gerard, not Price — Phase 18 scope), then sets the flag to 1. Phase 17 cannot run until this gate is cleared.

### D-04: Program naming and outputs
- **D-04:** SAS program is `sas/18_supplemental_raw_gap.sas`. All outputs go to `qc\18_*.txt`:
  - `qc\18_id_diagnostic.txt` — 2022 ID comparison (produced before abort)
  - `qc\18_gap_candidates.txt` — base-missing-but-raw-populated counts per IN_BASE column per file
  - Log: `logs\18_supplemental_raw_gap.log`
  - Fits the phase-number-matches-program-number convention used throughout the pipeline.

### Claude's Discretion
- Exact format of `18_gap_candidates.txt` (sorted by recoverable-count descending is a reasonable default)
- Whether to produce a single combined gap table or one section per file
- Macro structure (one macro per file vs a generalized loop)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 16 completed spec (primary input)
- `16-supplemental-raw-inventory.md` (repo root) — Phase 16 summary: 9-file inventory, key findings, column overlap table, 2022 ID mismatch description, PCM-D-15/D-16 open decisions, and the exact "16b" next-steps this phase delivers. Read this first.

### Pipeline configuration
- `sas/00_config.sas` — all library and path definitions; every program must `%include` this. The `raw_path` macro variable introduced in Phase 16 is defined here.
- `sas/16_raw_inventory.sas` — Phase 16 program; established the import pattern (per-file libname, sheet handling, key detection, IN_BASE bucketing) to replicate and extend.

### Decision log
- `docs/DECISIONS.md` — PCM-D-15 and PCM-D-16 must be recorded here; review for current open-decision wording before writing new entries.

### Prior phase context
- `.planning/phases/17-summary-stats-by-domain-context/17-CONTEXT.md` — Phase 17 is downstream and gated on PCM-D-15. The gap-fill columns approved in Phase 18 feed Phase 17's extension dataset (`work.analysis_base_ext`).

### No external ADRs — requirements fully captured in decisions above and in `16-supplemental-raw-inventory.md`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sas/16_raw_inventory.sas` — import pattern for all 9 files (libname per file, `%import_sheet` macro for workbooks, key detection, IN_BASE bucketing via `dictionary.columns`); Phase 18 extends this without rerunning it
- `sas/00_config.sas` — `raw_path`, `g_path`, `qc_path`, `log_path` macros; all paths sourced from here
- `sas/17_summary_stats_by_domain.sas` — `%let DOMAIN_MAP_APPROVED=0` gate pattern to replicate for `%let D15_APPROVED=0`

### Established Patterns
- All programs `%include "C:\Master_Renamed_same_format_accross\sas\00_config.sas"` as first step
- No bare open-code `%IF` — all conditional logic in named macros
- Every `%abort cancel` inside a named macro (PCM-R-05)
- No `%PUT` with apostrophes or embedded semicolons
- `g.&src_ds` never on the left of a DATA statement (read-only source protection)
- `%let FLAG=0` gate with `%macro gate_X; %if &FLAG=0 %then %abort cancel; %mend;` — see Phase 17 Checkpoint 1

### Integration Points
- Reads `g.analysis_base` (built by `sas/07_cohort.sas`) — 41,150 rows, 125 columns at Phase 16 execution
- Reads raw files via libname/import under `&raw_path` (files listed in `16-supplemental-raw-inventory.md` §Scope)
- Writes to `qc\` and `logs\` (paths via `00_config.sas`)
- `docs/DECISIONS.md` is updated by Gerard manually after reviewing `qc\18_gap_candidates.txt`

### Known Pitfalls (from Phase 16)
- `cats()` of a numeric ID may not match the char form — do NOT assume the cast explains the 2022 mismatch until the diagnostic confirms it
- r2 `studyid` and r4 `studyid` are the patient keys (not `PRECEDE_STUDY_ID`) — key detection must handle alias names
- r8 has one duplicated PRECEDE_Study_ID (9,484 distinct of 9,485) — exclude r8 from gap-fill until 2022 ID resolved (numeric key, 0 matches)
- Excel row-ceiling flag check required on r2 (3,987 cols) — confirmed clear in Phase 16, but re-assert
- `dictionary.columns.type` is CHARACTER (`'char'`/`'num'`), not numeric — PCM-T-13

</code_context>

<specifics>
## Specific Ideas

- The Phase 16 spec (`16-supplemental-raw-inventory.md`) contains the exact diagnostic instruction: "print 5 base IDs not in r9 beside 5 r9 IDs not in base with their lengths." Use this verbatim as the acceptance criterion for the 2022 ID diagnostic task.
- The gap candidates most likely to matter (from Phase 16 findings): r1 induction/emergence times, r2 Frailty_Score / Education / Admit_BMI / comorbidity flags / labs, r6 five frailty components. The planner may want to highlight these in the output format even if the computation covers all IN_BASE columns.
- r9 (All_YEARS_LAT_LONG) — its IN_BASE columns (Latitude, Longitude, YEAR) are already in base per Phase 16; exclude from gap-fill computation.

</specifics>

<deferred>
## Deferred Ideas

- Actual gap-fill joins (merging raw values into `g.analysis_base`) — that is Phase 17+ work, gated on PCM-D-15 approval
- 2022 ID format fix / cast application — gated on PCM-D-16 resolution; Phase 18 only diagnoses, not fixes
- r7/r8 gap-fill (2022 files) — deferred until PCM-D-16 is resolved

</deferred>

---

*Phase: 18-supplemental-raw-inventory*
*Context gathered: 2026-09-16*
