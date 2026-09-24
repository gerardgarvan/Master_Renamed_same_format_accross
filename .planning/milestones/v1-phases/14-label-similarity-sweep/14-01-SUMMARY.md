---
phase: 14-label-similarity-sweep
plan: 01
subsystem: label-similarity
tags: [sas, label-sweep, HARM-02, HARM-03, COMPLEV, jaccard, pairwise-comparison]
dependency_graph:
  requires:
    - g.master_data_harmonized (Phase 10b output)
    - docs/precede_dictionary.csv (canonical name source)
    - 10_concept_profile.sas concept groups (for exclusion table)
  provides:
    - sas/14_label_similarity.sas Section A
    - docs/label_similarity_candidates.csv (committed; human-review input for Phase 15)
  affects:
    - Phase 15 (harmonize confirmed label-similar pairs)
tech_stack:
  added: []
  patterns:
    - COMPLEV normalized Levenshtein for edit-distance similarity
    - Word-level Jaccard for semantic similarity
    - PROC SQL self-join for pairwise scoring (O(n^2) at n=187)
    - dictionary.columns label extraction (no data read)
    - Dual-threshold OR logic (qualify on either measure)
    - Pattern-based pipeline-derived column exclusion (h_*, *_src, in_md*)
    - Concept table generated from datalines; pairs derived by self-join (not hardcoded)
key_files:
  created:
    - sas/14_label_similarity.sas
  modified: []
decisions:
  - "COMPLEV over COMPGED: COMPGED weighted costs (~100/op) produce large negative normalized scores; nothing clears a positive threshold. COMPLEV returns plain Levenshtein in characters and normalizes predictably."
  - "Jaccard required (not optional): edit distance misses semantically equivalent labels with different characters ('patient died' vs 'death occurred'). Both scores written; pair qualifies on EITHER."
  - "threshold=0.20 (edit) and jaccard_threshold=0.34 -- stated as %let macro variables at top of program, clearly labeled as tuning parameters."
  - "Dictionary precedence over SAS label: PRECEDE dictionary description wins because it is the authoritative specification; a SAS label is whatever an extract happened to carry."
  - "Known-pair exclusion derived from work.concepts self-join -- not hardcoded. Original had 8 non-existent h_ names and missed 6 real ones; pattern-based exclusion avoids all drift."
  - "PRECEDE dictionary deduplicated by sheet rank before join (MASTER_DATASET rank 1, DERIVED_VARIABLES_MASTER rank 2, others rank 3) -- same rule as Phase 11."
metrics:
  duration_minutes: 15
  completed: "2026-08-29"
  tasks_completed: 1
  tasks_total: 1
  files_created: 1
  files_modified: 0
---

# Phase 14 Plan 01: Label Similarity Sweep Section A Summary

**One-liner:** COMPLEV + Jaccard dual-threshold pairwise label sweep over g.master_data_harmonized with PRECEDE dictionary enrichment, producing docs/label_similarity_candidates.csv for human review.

## What Was Built

`sas/14_label_similarity.sas` Section A (621 lines) implements the only alias-finding method that name-based matching cannot perform: comparing variable labels instead of names.

### Program Sections

| Section | Purpose |
|---------|---------|
| 0: Preconditions | Check g.master_data_harmonized, precede_dictionary.csv, row count |
| 1: Read PRECEDE Dictionary | PROC IMPORT + dedup by sheet rank, sas_name column join |
| 2: Extract Labels | dictionary.columns query; excludes PRECEDE_STUDY_ID key |
| 3: Build Best-Labels | PRECEDE description > SAS label > varname; one-row-per-var assertion |
| 4: Known-Pair Exclusion Table | Concept datalines + self-join to generate all intra-group pairs |
| 5: Pairwise Similarity | COMPLEV edit score + word-level Jaccard; OR threshold logic |
| 6: Exclusion Filters | Remove known concept pairs and pipeline-derived columns by pattern |
| 7: Write CSV | docs/label_similarity_candidates.csv (committed artifact, HARM-03) |
| 8: Write Evidence Workbook | docs/LABEL_SIMILARITY_EVIDENCE.xlsx (KEY sheet leftmost) |
| 9: Write QC Artifact | qc/14_label_similarity.txt with calibration pair scores |
| B: Placeholder | Section B stub for Plan 02 (SSDI/CPT1 profiling) |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Correction] COMPGED replaced with COMPLEV**
- **Found during:** Task 1 (stated in RESEARCH.md correction 2026-08-29 and plan action section)
- **Issue:** COMPGED returns weighted edit costs (~100 per operation). Normalizing by 2*max_length gives `1 - 500/40 = -11.5` for a typical pair -- all scores large and negative, zero candidates above threshold. Silent failure reads as "no similar labels" rather than "arithmetic is wrong."
- **Fix:** Used COMPLEV (plain Levenshtein distance in characters); score_edit = 1 - complev(a,b) / max(lengthn(a), lengthn(b)). COMPGED still appears in file as a comment explaining the correction.
- **Files modified:** sas/14_label_similarity.sas
- **Commit:** a583d7e

**2. [Rule 1 - Correction] h_* exclusion changed from hardcoded names to LIKE pattern**
- **Found during:** Task 1 (stated in plan action section correction 2026-08-29)
- **Issue:** Hardcoded list had 8 non-existent h_ names and omitted 6 real ones, plus missed all 11 _src companions entirely.
- **Fix:** Pattern-based exclusion (`upcase(varname) LIKE 'H\_%'` and `LIKE '%\_SRC'`); derives from actual column names rather than a maintained list.
- **Files modified:** sas/14_label_similarity.sas
- **Commit:** a583d7e

**3. [Rule 2 - Enhancement] Added Jaccard threshold as %let macro variable**
- **Found during:** Task 1 (plan required Jaccard but did not specify it as a named macro variable)
- **Issue:** The plan specified `%let threshold = 0.20` for edit distance but Jaccard threshold was only mentioned inline.
- **Fix:** Added `%let jaccard_threshold = 0.34;` at top with the same tuning-parameter documentation block.
- **Files modified:** sas/14_label_similarity.sas
- **Commit:** a583d7e

**4. [Rule 2 - Enhancement] Added score_jaccard to candidates_out KEEP list**
- **Found during:** Task 1 (plan KEEP list omitted score_jaccard despite requiring it for human review)
- **Issue:** The plan's SECTION 7 KEEP statement omitted score_jaccard, which the human reviewer needs to understand why a pair was surfaced.
- **Fix:** Added score_jaccard to the KEEP list in candidates_out.
- **Files modified:** sas/14_label_similarity.sas
- **Commit:** a583d7e

## Known Stubs

- Section B placeholder at end of file: `%put NOTE: [14] Section B placeholder -- implement in Plan 02.;` -- intentional, Plan 02 will implement SSDI/CPT1 profiling (HARM-09).

## Self-Check: PASSED

- sas/14_label_similarity.sas: 621 lines, all acceptance criteria verified by grep
- Commit a583d7e confirmed in git log
- Contains: `%let threshold = 0.20;`, `dictionary.columns`, `precede_dictionary.csv`, `label_similarity_candidates.csv`, `work.known_pairs`, `%abort cancel` inside named macros, `COMPGED` (in correction comment), `LABEL_SIMILARITY_EVIDENCE.xlsx`, `14_label_similarity.txt`, `Section B` placeholder
- Does NOT contain: `VARIABLE_RECTIFICATION` as crosswalk, `&SQLOBS`, `data g.master_data_harmonized` as a write target
