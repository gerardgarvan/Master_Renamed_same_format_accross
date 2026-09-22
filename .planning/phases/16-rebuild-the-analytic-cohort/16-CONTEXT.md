# Phase 16: Rebuild the Analytic Cohort - Context

**Gathered:** 2026-09-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce a valid `g.analytic_cohort` that:
- Derives from `g.master_data_harmonized` (174 cols, 41,150 rows), not the old `g.master_data_merged`
- Carries all `h_*` harmonized columns and no dropped aliases
- Has PCM-D-05 resolved, documented, and committed to `docs/DECISIONS.md`

Everything from Phase 7 (`07_cohort.sas`, the old `g.analytic_cohort` from merged) is historical.
Phase 16 supersedes it without modifying it.

</domain>

<decisions>
## Implementation Decisions

### PCM-D-05: Cohort Restriction

- **D-01:** Hardcode INPATIENT+OBSERVATION filter. PCM-D-05 is resolved as "admitted-only,
  because Admit_BMI forces it." The old rationale (ambulatory patients were never eligible
  for geriatric assessments) is VOID after MRG-06 — most cognitive/frailty scores belong
  to ambulatory rows. The new rationale: all 12,726 Admit_BMI values are inside the
  admitted cohort, zero are ambulatory, so any BMI analysis requires the restriction. No
  parameterization gate needed.

- **D-02:** The DECISIONS.md PCM-D-05 entry must state what the restriction actually does —
  it selects a clinically different population, not a convenience missingness filter.
  Required population-shift figures (from Phase 13 measurements, per ROADMAP SC-3 and SC-4):
  - Charlson 0: 60.8% (full) → 34.5% (cohort)
  - General anaesthesia: 57.6% → 84.2%
  - GI service: 18.4% → 1.7%
  - Colonoscopy: 8.5% → 0.4%
  - RACE=WHITE: 79.8% → 87.1% (7.3-point shift — required in methods sections per ROADMAP)
  All five figures go into the DECISIONS.md entry.

### Program Design

- **D-03:** New standalone program `sas/16_cohort_rebuild.sas`. Reads
  `g.master_data_harmonized`, produces `g.analytic_cohort`. Leaves `sas/07_cohort.sas`
  as a committed historical artifact — do not modify it.

- **D-04:** Do NOT add `16_cohort_rebuild.sas` to `sas/99_run_all.sas`. That is Phase 8's
  job (Phase 8 Plan 02 already scoped it). Phase 16 verifies the program runs standalone.

### Assertion Strategy

- **D-05:** Re-measure the three known complete-case Ns from `g.master_data_harmonized`
  (not from `g.master_data_merged`) and assert the established values:
  - Admit_BMI = 12,726
  - Cognitive_Score = 20,540
  - Frailty_Score = 23,311
  These should be identical because the harmonized file carries the same underlying values
  for these columns. If any assertion fires, it is a genuine pipeline anomaly.

- **D-06:** Drop the all-three simultaneous assertion (was 6,523). STATE.md flags this
  figure as stale (pre-coalesce). Measure it and write it to the QC file; do not assert it.
  The first clean run establishes the baseline.

- **D-07:** Measure `h_*` harmonized column Ns within the cohort and report them in the
  QC file — do not assert. Within-cohort h_* baselines have never been established.

- **D-08:** Post-run: assert `g.master_data_harmonized` is unmodified (174 columns, 41,150
  rows). Mirrors the `%assert_merged_unchanged` pattern from `10b_concept_harmonize.sas`.
  The program reads harmonized but must never write it.

### Column Scope

- **D-09:** `g.analytic_cohort` carries all 174 columns from `g.master_data_harmonized`
  (full pass-through, restricted to admitted rows). No curated subset. Downstream analysts
  get source columns, `h_*` columns, and pipeline variables. Zero dropped aliases.

### Claude's Discretion

- Program section structure, macro naming, ODS LISTING handling, log routing, and QC file
  format: follow the 07_cohort.sas and 10b_concept_harmonize.sas patterns already
  established in the codebase.
- PCM violations to avoid: same list as all prior programs (PCM-T-01, T-02, T-11, R-02,
  R-05; no SQLOBS; no non-ASCII; no in-place dataset rewrite; every abort inside named macro).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase definition
- `.planning/ROADMAP.md` §Phase 16 — success criteria 1-4, requirements (HARM-10, PCM-D-05)

### Existing cohort program (read for pattern, do not modify)
- `sas/07_cohort.sas` — Phase 7 cohort program reading g.master_data_merged; follow its
  section structure, fail_out macro, check_dir, verify_promotion, and ODS LISTING patterns

### Harmonization program (read for assertion patterns)
- `sas/10b_concept_harmonize.sas` — Source of `%assert_merged_unchanged` pattern and
  HARM-07 gate design; Phase 16 borrows the post-run dataset-unchanged assertion

### Decision record
- `docs/DECISIONS.md` — PCM-D-05 pending entry (currently "Pending — Phase 7 | TBD");
  Phase 16 Plan 02 resolves it with the BMI-forces-restriction rationale and all five
  population-shift figures

### Phase 7 summary (prior cohort work, for context)
- `.planning/phases/07-cohort-missingness/07-01-SUMMARY.md` — what 07_cohort.sas did,
  why certain patterns were chosen (e.g. build-in-WORK-then-promote, ODS truncation trap)

### Phase 15 output summary (harmonized dataset spec)
- `.planning/phases/15-extend-the-harmonized-dataset/15-02-SUMMARY.md` — confirms
  g.master_data_harmonized = 174 columns, 41,150 rows; h_* column list and coverage Ns

### Config
- `sas/00_config.sas` — g_path, qc_path, logs_path macro variables (required by every SAS program)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `%fail_out(msg=)` macro pattern — from 07_cohort.sas: restores ODS listing and PROC PRINTTO
  before every abort. Copy this pattern verbatim into 16_cohort_rebuild.sas.
- `%check_dir(path=, label=)` — precondition check from 07_cohort.sas; reuse as-is.
- `%assert_complete_case_n(var=, expected=, outvar=)` — from 07_cohort.sas; reuse directly.
- `%assert_merged_unchanged` pattern — from 10b_concept_harmonize.sas SECTION 6; adapt to
  check g.master_data_harmonized (174 cols, 41,150 rows).
- `%classify_cohort` / `%gate_on_status` — degenerate-cohort guard from 07_cohort.sas; reuse.
- `%verify_promotion` — post-promotion row count check from 07_cohort.sas; reuse.

### Established Patterns
- Build cohort candidate in WORK, validate, then promote to g.analytic_cohort in one DATA step
  (never write g.analytic_cohort before all assertions pass).
- ODS LISTING FILE= written to a SEPARATE QC file from the key=value summary (avoid truncation).
- All counts via `SELECT COUNT(*) INTO :macvar TRIMMED` — never `&SQLOBS`.
- Log routed via PROC PRINTTO; every abort path restores it via `%fail_out`.
- `data _null_; file "..." mod;` for appending to QC summary file.

### Integration Points
- Reads: `g.master_data_harmonized` (written by sas/10b_concept_harmonize.sas)
- Writes: `g.analytic_cohort` (replaces the Phase 7 version in the g library)
- QC output: `&qc_path.\16_cohort_missingness.txt` and `&qc_path.\16_cohort_tables.txt`
- Log: `&logs_path.\16_cohort_rebuild.log`

</code_context>

<specifics>
## Specific Ideas

- The DECISIONS.md PCM-D-05 entry should retire the shorthand "the ~53% gap" that referred
  ambiguously to BMI availability. The Phase 16 resolution entry should state both HAVE and
  LACK percentages with their direction spelled out (as 07-02-PLAN.md required but never ran).

- The five clinical-population shift figures (Charlson, anaesthesia, GI service, colonoscopy,
  racial composition) come from Phase 13 measurements already in the ROADMAP — they do not
  need to be re-measured in Phase 16 SAS code; they need to be transcribed into DECISIONS.md.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 16-rebuild-the-analytic-cohort*
*Context gathered: 2026-09-21*
