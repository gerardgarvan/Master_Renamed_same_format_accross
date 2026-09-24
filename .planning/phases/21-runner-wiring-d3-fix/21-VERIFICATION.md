---
phase: 21-runner-wiring-d3-fix
verified: 2026-09-24T00:00:00Z
status: passed
score: 9/9 must-haves verified
re_verification:
  previous_status: gaps_found
  previous_score: 7/9
  gaps_closed:
    - "PCM-D-19 Result field filled in DECISIONS.md -- D3 sheet confirmed present and populated (2026-09-24)"
    - "PCM-D-20 Population shift field filled in DECISIONS.md -- 27,260 non-cohort rows restricted, 0 cohort rows lost, differences on gap-filled columns documented"
    - "FIX-01 checked [x] in REQUIREMENTS.md"
  gaps_remaining: []
  regressions: []
---

# Phase 21: Runner Wiring & D3 Fix -- Verification Report

**Phase Goal:** Users can run the entire pipeline end-to-end from a single batch driver and regenerate the domain statistics workbook with the D3 cognitive domain correctly populated.

**Verified:** 2026-09-24
**Status:** passed
**Re-verification:** Yes -- after gap closure (previous score 7/9, gaps were DECISIONS.md PENDING fields and FIX-01 checkbox)

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | DOMAIN_MAP_APPROVED = 1 at line 145 with PCM-D-19 comment | VERIFIED | Line 145: `%let DOMAIN_MAP_APPROVED = 1;  /* PCM-D-19 -- approved by Gerard 2026-09-23 -- see docs/DECISIONS.md */` |
| 2 | g.analysis_base replaced by g.analytic_cohort in all data-reading references | VERIFIED | All data-reading references (set, from, data=, dictionary MEMNAME checks) use analytic_cohort; g.analysis_base appears only in header note and inside %pcm_d20_compare guard block |
| 3 | %pcm_d20_compare macro exists, guarded with %sysfunc(exist()), routes output to qc/17_pcm_d20_compare.txt via PROC PRINTTO | VERIFIED | Lines 232-263 of program 17; %sysfunc(exist(g.analysis_base)) guard at line 236; PROC PRINTTO at line 252 |
| 4 | pecan_ID excluded from statistics via existing identifier mechanism | VERIFIED | Regex `/(^|_)(ID|MRN)(_|$)/` at lines 690, 1698, 2148 matches PECAN_ID (ends in _ID); mechanism (a) confirmed; no DATALINES row needed or added |
| 5 | PCM-D-19 and PCM-D-20 recorded in docs/DECISIONS.md with rationale and attribution | VERIFIED | Lines 599-653 of DECISIONS.md; both entries present with full rationale, status, attribution |
| 6 | PCM-D-19 Result and PCM-D-20 Population shift PENDING lines filled in after run | VERIFIED | PCM-D-19 Result (lines 612-614): "CONFIRMED 2026-09-24 -- D3 (Cognitive) sheet present and populated"; PCM-D-20 Population shift (lines 646-653): 27,260 restricted rows, 0 lost, differing variables documented |
| 7 | run_pipeline.cmd exists at repo root with 14 programs in correct order | VERIFIED | File confirmed; order in :main is 01, 02, 03, 04, 05, 06, 07, 08, 19, 20, 10b, 16b, 17, 18 |
| 8 | 00_config.sas sets in_pipeline=1 via envlen(RUN_ALL) without WARNING | VERIFIED | Line 59: `%if %sysfunc(envlen(RUN_ALL)) > 0 %then %do;`; %symexist guard preserved; %put NOTE line at line 74 |
| 9 | FIX-01 confirmed: regenerated workbook contains populated D3 sheet | VERIFIED | REQUIREMENTS.md FIX-01 now `[x]`; DECISIONS.md PCM-D-19 Result confirms D3 sheet present and populated with COGNITIVE_SCORE and COGNITIVE_CATEGORY |

**Score:** 9/9 truths verified

---

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `sas/17_summary_stats_by_domain.sas` | VERIFIED | Gate=1, input redirected, %pcm_d20_compare macro present, column coverage assertions present, row count expectation updated to 13890 |
| `docs/DECISIONS.md` | VERIFIED | PCM-D-19 and PCM-D-20 entries present; Result and Population shift fields filled with confirmed run data |
| `run_pipeline.cmd` | VERIFIED | Exists at repo root; `start "" /wait`; `setlocal EnableDelayedExpansion`; `-set RUN_ALL 1`; `!ERRORLEVEL!` throughout; all 14 programs |
| `sas/00_config.sas` | VERIFIED | `envlen(RUN_ALL)` check present; %symexist guard preserved; %put NOTE line added |
| `sas/99_run_all.sas` | VERIFIED | Header lists all 14 programs; references `run_pipeline.cmd` as canonical batch entry point; %include statements unchanged |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `run_pipeline.cmd` | `sas/00_config.sas %_set_pipeline_default` | `-set RUN_ALL 1` OS env var read by `envlen(RUN_ALL)` | WIRED | Both sides confirmed: cmd sets `-set RUN_ALL 1`; 00_config.sas reads via envlen at line 59 |
| `run_pipeline.cmd` | each `sas/*.sas` program | `start "" /wait sas.exe -sysin` | WIRED | Pattern `start "" /wait` confirmed; all 14 program calls present in :main |
| `sas/17_summary_stats_by_domain.sas line 145` | Sections 5-11 gate | `%if &DOMAIN_MAP_APPROVED ne 1` | WIRED | Gate flag set to 1 at line 145; guard at line 197 |
| `sas/17_summary_stats_by_domain.sas` | `g.analytic_cohort` | data-reading references | WIRED | Multiple data-reading references confirmed; analytic_cohort in set/from/data=/dictionary references |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| RUN-01 | 21-02-PLAN.md | Full pipeline end-to-end via run_pipeline.cmd covering programs 1-8, 10b, 16b, 17, 18, 19, 20 | SATISFIED | run_pipeline.cmd contains all 14 programs in correct order; 21-02-SUMMARY Task 4 confirms full PASSED run (2026-09-24) |
| FIX-01 | 21-01-PLAN.md | Regenerated workbook contains D3 sheet with COGNITIVE_SCORE and COGNITIVE_CATEGORY | SATISFIED | REQUIREMENTS.md `[x]`; PCM-D-19 Result confirmed D3 sheet present and populated 2026-09-24 |

No orphaned requirements: REQUIREMENTS.md assigns only RUN-01 and FIX-01 to Phase 21; both are claimed and satisfied.

---

### Anti-Patterns Found

None. Previous gap (PENDING fields in DECISIONS.md; unchecked FIX-01) resolved.

---

### Human Verification Required

None outstanding. The full pipeline PASSED run was confirmed by Gerard (2026-09-24) and documented in 21-02-SUMMARY Task 4. D3 sheet confirmed by Gerard as part of that run, recorded in DECISIONS.md PCM-D-19 Result.

---

### Summary

Phase 21 goal achieved. Both requirements satisfied:

- **RUN-01**: `run_pipeline.cmd` wires all 14 pipeline programs as separate sas.exe sessions with correct exit-code gating, `setlocal EnableDelayedExpansion`, `-set RUN_ALL 1` propagation to `in_pipeline` via `00_config.sas`, and a WARNING-count summary per program in `99_run_all.log`. Full pipeline PASSED end-to-end run confirmed.

- **FIX-01**: `sas/17_summary_stats_by_domain.sas` has `DOMAIN_MAP_APPROVED = 1` (PCM-D-19), reads `g.analytic_cohort` (PCM-D-20), excludes pecan_ID via the existing identifier regex (mechanism a), and the regenerated `qc/17_summary_stats_by_domain.xlsx` contains a populated D3 sheet with COGNITIVE_SCORE and COGNITIVE_CATEGORY.

---

_Verified: 2026-09-24_
_Verifier: Claude (gsd-verifier)_
