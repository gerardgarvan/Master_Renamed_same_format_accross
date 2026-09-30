---
phase: 26-v2.1-carry-forward-source-hardening
plan: "02"
subsystem: pcnr-sentinel-hardening
tags: [FIX-04, assertions, sentinel, pcnr, program-24]
dependency_graph:
  requires: ["26-01"]
  provides: ["FIX-04"]
  affects: ["sas/24_pcnr_build.sas", "docs/sentinel_decisions.csv"]
tech_stack:
  added: []
  patterns: ["%assert_eq PCM-R-05 pattern", "WORK-then-promote assertion guard"]
key_files:
  created: []
  modified:
    - docs/sentinel_decisions.csv
    - sas/24_pcnr_build.sas
decisions:
  - "PCM-D-05 resolved: Cognitive_Score=0 is a placeholder sentinel, not a valid score; 11,687 rows recoded to MISSING"
  - "PCM-D-06 resolved: rt_RM_START_to_AN_START_mins=-9 is a sentinel code, not a real negative interval; 380 rows recoded to MISSING"
metrics:
  duration: "~20 minutes"
  completed_date: "2026-09-30"
  tasks_completed: 2
  files_modified: 2
---

# Phase 26 Plan 02: FIX-04 Sentinel Assertions Summary

**One-liner:** FIX-04 implemented -- two named %assert_eq macros added to program 24 that abort the pipeline if Cognitive_Score=0 or rt sentinel=-9 survive into work.pcnr_harmonized, backed by flipping both decisions to MISSING in sentinel_decisions.csv.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 0 | Flip Cognitive_Score and rt sentinel decisions to MISSING | a0d3e8f | docs/sentinel_decisions.csv |
| 1 | Add two FIX-04 sentinel assertions to program 24 | 7f80ad7 | sas/24_pcnr_build.sas |

---

## What Was Built

### Task 0 — docs/sentinel_decisions.csv

Exactly two rows changed (git diff: 2 insertions, 2 deletions):

| variable | raw_hex | Old action | New action | rationale | decided_by | decided_date |
|---|---|---|---|---|---|---|
| Cognitive_Score | 30 | KEEP | MISSING | FIX-04: placeholder sentinel; 0 is not a valid Cognitive Score (lowest real score > 0); D-05 | Gerard | 2026-09-30 |
| rt_RM_START_to_AN_START_mins | 2D39 | KEEP | MISSING | FIX-04: sentinel -9 code (not a real negative interval); D-06 | Gerard | 2026-09-30 |

These are the first numeric recode decisions under the PCM-D-24 approval path.

### Task 1 — sas/24_pcnr_build.sas (new SECTION 5b)

Inserted between SECTION 5 (type/length gate) and SECTION 6 (WORK-then-promote):

1. **`%assert_eq` definition** — exact 05_qc_merge.sas lines 41-47 signature, defined locally since it is not in 00_config.sas. `%abort cancel` lives inside this named macro (PCM-R-05 compliant).

2. **`%check_cog_zero`** — queries `work.pcnr_harmonized` for `pcnr_Cognitive_Score = 0`; calls `%assert_eq(actual=..., expected=0, label=FIX-04 pcnr_Cognitive_Score placeholder 0 count)`.

3. **`%check_rt_sentinel`** — queries `work.pcnr_harmonized` for `pcnr_rt_RM_START_to_AN_STAR_mins = -9` (STAR truncation per PCM-D-23 middle-truncation rule); calls `%assert_eq(actual=..., expected=0, label=FIX-04 pcnr_rt_RM_START_to_AN_STAR_mins sentinel -9 count)`.

4. **`%report_cog_category_check`** — NOTE-only (never aborts) cross-tab: counts rows where `pcnr_Cognitive_Score` is missing but `pcnr_Cognitive_Category` is non-missing. Surfaces score/category disagreements for reviewer decision.

Variable names confirmed from `docs/pcnr_name_map.csv` before writing:
- `pcnr_Cognitive_Score` (line 38)
- `pcnr_rt_RM_START_to_AN_STAR_mins` (line 168 — STAR, not START)

---

## Acceptance Criteria Verification

| Criterion | Status |
|---|---|
| sas/24_pcnr_build.sas contains `%macro check_cog_zero` | PASS |
| sas/24_pcnr_build.sas contains `%macro check_rt_sentinel` | PASS |
| docs/sentinel_decisions.csv rows (Cognitive_Score,30) and (rt_RM_START_to_AN_START_mins,2D39) have action MISSING | PASS |
| Both assertions query work.pcnr_harmonized (before SECTION 6 promote) | PASS |
| sas/24_pcnr_build.sas contains `where pcnr_Cognitive_Score = 0` | PASS |
| sas/24_pcnr_build.sas contains `where pcnr_rt_RM_START_to_AN_STAR_mins = -9` (STAR not START) | PASS |
| sas/24_pcnr_build.sas contains two `%assert_eq(` calls with `expected=0` | PASS |
| %abort cancel is inside named macro (PCM-R-05) | PASS |
| MISSING row count in sentinel_decisions.csv increased by exactly 2 | PASS |

Note: Runtime verification (SAS log showing QC ASSERTION OK, qc/24_recode_rules_generated.sas numeric rules, qc/24_pcnr_recode_counts.csv n_recoded counts) requires a full pipeline run in the SAS environment and cannot be confirmed here.

---

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

One clarification applied: the plan note says "27-char rule" for PCM-D-23 but the confirmed rule is middle-truncation (head cut to leave total <= 32 chars including `pcnr_` prefix). The variable name `pcnr_rt_RM_START_to_AN_STAR_mins` was written using the authoritative pcnr_name_map.csv value, not inferred from any rule description.

---

## Decisions Made

- **PCM-D-05 resolved:** Cognitive_Score=0 is a placeholder sentinel; confirmed by Gerard 2026-09-30; 11,687 rows approved for recode to MISSING.
- **PCM-D-06 resolved:** rt_RM_START_to_AN_START_mins=-9 is a sentinel code (not a real negative interval); confirmed by Gerard 2026-09-30; 380 rows approved for recode to MISSING.

---

## Known Stubs

None.

---

## Self-Check: PASSED

Files modified exist in git:
- `docs/sentinel_decisions.csv` — commit a0d3e8f
- `sas/24_pcnr_build.sas` — commit 7f80ad7
