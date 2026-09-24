---
phase: 21-runner-wiring-d3-fix
plan: 01
subsystem: sas-pipeline
tags: [sas, program17, analytic_cohort, d3-fix, domain-map, pecan_id]

requires:
  - phase: 20-pecan-id-derivation
    provides: g.analytic_cohort with pecan_ID column (175 cols, 13890 rows)
  - phase: 16-rebuild-analytic-cohort
    provides: g.analytic_cohort base dataset (16b_cohort_rebuild.sas)

provides:
  - sas/17_summary_stats_by_domain.sas with DOMAIN_MAP_APPROVED=1 (PCM-D-19)
  - input redirect to g.analytic_cohort (PCM-D-20)
  - %pcm_d20_compare keyed audit block writing qc/17_pcm_d20_compare.txt
  - column coverage assertions for g.analytic_cohort
  - PCM-D-19 and PCM-D-20 decision records in docs/DECISIONS.md

affects:
  - 21-runner-wiring-d3-fix plan 02 (runner wiring; program 17 must work standalone first)
  - docs/DECISIONS.md (decision log)

tech-stack:
  added: []
  patterns:
    - "PROC PRINTTO used to route PROC COMPARE output to qc/ (never to SAS listing -- PHI safety)"
    - "Column coverage assertions use dictionary.columns with upcase() matching"
    - "Identifier exclusion confirmed via regex /(^|_)(ID|MRN)(_|$)/ -- mechanism (a), no DATALINES row needed"

key-files:
  created: []
  modified:
    - sas/17_summary_stats_by_domain.sas
    - docs/DECISIONS.md

key-decisions:
  - "PCM-D-19: DOMAIN_MAP_APPROVED set to 1; D3 DATALINES rows confirmed correct at domain=D3 assign_rule=instrument"
  - "PCM-D-20: program 17 redirected from g.analysis_base (P:-drive artifact, no pipeline producer) to g.analytic_cohort (pipeline-produced by 16b)"
  - "pecan_ID exclusion: mechanism (a) -- the existing regex /(^|_)(ID|MRN)(_|$)/ already matches PECAN_ID; no DATALINES row added"
  - "PROC COMPARE output routed via PROC PRINTTO to qc/17_pcm_d20_compare.txt (batch .lst file is inside git working tree)"

patterns-established:
  - "Keyed PROC COMPARE with %sysfunc(exist()) guard: run only when the reference dataset is present"
  - "Row count expectation updated at redirect: 13890 WARNING (not abort) to allow pipeline evolution"

requirements-completed: [FIX-01]

duration: 45min
completed: 2026-09-23
---

# Phase 21 Plan 01: Runner Wiring & D3 Fix Summary

**DOMAIN_MAP_APPROVED flipped to 1 (PCM-D-19) and program 17 redirected from P:-drive g.analysis_base to pipeline-produced g.analytic_cohort (PCM-D-20) with keyed audit comparison and column coverage assertions**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-09-23T00:00:00Z
- **Completed:** 2026-09-23
- **Tasks:** 2 of 3 complete (Task 3 is checkpoint:human-verify -- awaiting run)
- **Files modified:** 2

## Accomplishments

- Gate DOMAIN_MAP_APPROVED flipped 0 -> 1 with a comment pointing to PCM-D-19 in DECISIONS.md
- All g.analysis_base data-reading references in program 17 replaced with g.analytic_cohort (MEMNAME='ANALYTIC_COHORT' in dictionary queries; set/from/data= references)
- %pcm_d20_compare macro added: guards with %sysfunc(exist()), runs PROC SQL keyed counts, routes PROC COMPARE output via PROC PRINTTO to qc/17_pcm_d20_compare.txt
- Column coverage assertion macros added: %check_cohort_col_coverage (static named vars) and %check_year_col_coverage (dynamic year variable, called after %pick_year_safe)
- Row count expectation updated from old g.analysis_base count to 13,890 (WARNING, not abort, to allow evolution)
- PCM-D-19 and PCM-D-20 entries appended to docs/DECISIONS.md with full rationale and PENDING result lines
- pecan_ID exclusion: mechanism (a) confirmed -- existing regex /(^|_)(ID|MRN)(_|$)/ already matches PECAN_ID (ends with _ID); no DATALINES row added or needed

## Task Commits

1. **Task 1: Flip gate, redirect input, add keyed comparison, exclude pecan_ID** - `b6ba2a0` (feat)
2. **Task 2: Record PCM-D-19 and PCM-D-20 in DECISIONS.md** - `9fb63df` (docs)
3. **Task 3: Run program 17, confirm D3 sheet** - CHECKPOINT -- awaiting human verification

## Files Created/Modified

- `sas/17_summary_stats_by_domain.sas` - Gate flipped, input redirected, %pcm_d20_compare added, column coverage macros added, row count expectation updated
- `docs/DECISIONS.md` - PCM-D-19 and PCM-D-20 entries appended (lines 599+)

## Decisions Made

- **PCM-D-19 approved:** DOMAIN_MAP_APPROVED = 1. D3 DATALINES rows (COGNITIVE_SCORE, COGNITIVE_CATEGORY at domain=D3 assign_rule=instrument) confirmed correct; Checkpoint 1 review complete.
- **PCM-D-20 approved:** Program 17 redirected to g.analytic_cohort. g.analysis_base has no producer in the repo; a clean RUN-01 run requires all inputs to be pipeline-produced.
- **pecan_ID mechanism (a):** The existing identifier regex in Section 3b already matches PECAN_ID. No DATALINES row added. This is the finding the SUMMARY must record (plan specification: "record which of (a)/(b)/(c) applied").
- **PROC PRINTTO for comparison output:** Batch SAS writes the .lst file next to -sysin, which is inside the git working tree. Routing PROC COMPARE output to the listing would write record-level values into the git directory. PROC PRINTTO to qc/17_pcm_d20_compare.txt prevents that.

## Deviations from Plan

None - plan executed exactly as written. All seven edits were applied as specified. The pecan_ID finding (mechanism a -- regex already handles it) was anticipated by the plan's (a)/(b)/(c) branching logic.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Task 3 checkpoint requires: run program 17 standalone (after 16b has produced g.analytic_cohort), confirm no ERROR in log, confirm D3 sheet present in qc/17_summary_stats_by_domain.xlsx, note qc/17_pcm_d20_compare.txt row counts if g.analysis_base is present, then fill in PENDING lines in PCM-D-19 and PCM-D-20 in DECISIONS.md.
- After Task 3 checkpoint approved: proceed to Plan 21-02 (runner wiring -- add programs 19 and 20 to 99_run_all.sas).

---
*Phase: 21-runner-wiring-d3-fix*
*Completed: 2026-09-23*
