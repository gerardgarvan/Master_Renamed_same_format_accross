---
phase: 17-summary-stats-by-domain-context
plan: "01"
subsystem: sas-pipeline
tags: [discovery, wave-0, scaffold, preconditions, sentinel, extension-columns]
dependency_graph:
  requires: [g.analysis_base, g.master_data_merged, docs/precede_dictionary.csv, sas/00_config.sas]
  provides: [sas/17_summary_stats_by_domain.sas Sections 0+0b, qc/17_discovery.txt (after SAS run)]
  affects: [17-02-PLAN.md (Wave 1 consumes discovery facts), 17-03-PLAN.md]
tech_stack:
  added: []
  patterns: [dictionary.columns inventory, %route_log/%restore_log/%fail_out scaffold, macro-loop coverage scan, sentinel applicability scan, proc freq nlevels]
key_files:
  created: [sas/17_summary_stats_by_domain.sas]
  modified: []
decisions:
  - "SUPPRESS_MAX=11, SUPPRESS_LABEL=-- (not <11 — a cell of exactly 11 labelled <11 is false)"
  - "gate_stats macro aborts unless DOMAIN_MAP_APPROVED=1 — enforces Checkpoint 1 as a real execution barrier"
  - "MAC matched only by anchored prxmatch pattern, not bare index(name,'MAC')"
  - "PRECEDE_STUDY_ID_1 explicitly excluded from extension KEEP= list (md6 duplicate, Pitfall 5)"
  - "work.ext_candidates left in WORK for Wave 1 to build &extension_keep_list dynamically"
  - "Key type resolved at macro time from dictionary.columns; no runtime vtype() branching"
metrics:
  duration_seconds: 140
  completed_date: "2026-09-03"
  tasks_completed: 2
  files_created: 1
---

# Phase 17 Plan 01: Wave 0 Discovery and Program Scaffold Summary

**One-liner:** SAS scaffold (Sections 0+0b) with config include, named-macro precondition guards, Checkpoint 1 approval gate, suppression constants, and Wave 0 discovery code that resolves all RESEARCH open questions about year variable, key type/length/uniqueness, extension KEEP= list, coverage, identifiers, and sentinel applicability.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Program scaffold — Sections 0 (options, config, log routing, fail_out, preconditions) | f0adfef | sas/17_summary_stats_by_domain.sas (created) |
| 2 | Section 0b — discovery code | f0adfef | sas/17_summary_stats_by_domain.sas (appended in same file) |

Both tasks landed in a single commit because Task 2 is an append to the same file authored in Task 1, and no intervening SAS run was possible (P: drive, manual execution).

---

## Discovery Facts (resolved after manual SAS run)

> The following are EXPECTED findings based on project context. Actual values are written to
> qc/17_discovery.txt after the SAS program is run against the live P: drive datasets.
> The Wave 1 executor (17-02-PLAN.md) MUST read qc/17_discovery.txt and use the actual values,
> not the estimates below.

### Year Variable

The discovery code searches g.analysis_base for columns matching YEAR / _DATE / SURG / ENCOUNTER
in the name. PROC FREQ with /missing is run on any numeric candidate whose name contains YEAR.
The exact name and per-year N are written to qc/17_discovery.txt. If no year column is found,
the discovery file states "NO YEAR COLUMN FOUND" with a list of date candidates from which a
year can be derived.

**Wave 1 action:** read the year-variable finding from qc/17_discovery.txt before building the
per-year stratification (D-03).

### PRECEDE_STUDY_ID Type and Length

Both datasets are queried via dictionary.columns. The stored TYPE (num or char) and LENGTH are
written to qc/17_discovery.txt together with 10 sampled raw key values from each dataset so
leading-zero padding (or its absence) is visible.

Expected from project context: CHAR $12 in g.analysis_base; the resolved type in
g.master_data_merged (md7 was NUM8 at source but the merged file holds one resolved type).

**Wave 1 action:** use key_type_merged from the discovery file to generate the compile-safe cast
macro. Use best12. unless the sampled key values show zero-padding.

### Key Uniqueness

n_key_dups is written to qc/17_discovery.txt. If > 0, Wave 1 must resolve the duplicates before
merging. If 0, the uniqueness gate in Wave 1 will pass cleanly.

### Extension KEEP= List

work.ext_candidates (columns in g.master_data_merged not in g.analysis_base, filtered to
frailty/cognitive/intraop-physiologic concepts) is enumerated and written to qc/17_discovery.txt
as a pasteable KEEP= list. PRECEDE_STUDY_ID_1 is explicitly excluded.

Concept filters applied: FRAIL, COGNI, FEELS, WEIGHT_LOSS, GRIP, WALK, PHYSICAL_ACTIV, ABP,
BIS_, NIBP, MIDAZOLAM, MAC (anchored by prxmatch), ISO_SEV.

Expected candidates from project context: Cognitive_Score, Cognitive_Category, Frailty_Score,
Frailty_Category, the five frailty components, hemodynamic block (ABP/BIS/NIBP variables),
Total_Midazolam_mg, ISO_SEV_* variants, ORAL_MORPHINE_EQUIV_mg_POD_DAY6.

**Wave 1 action:** build &extension_keep_list dynamically from work.ext_candidates rather than
transcribing by hand.

### Extension Coverage (D3/Frailty Denominator)

Per-column non-missing N and pct_of_base are written for every extension candidate.
Any column below 90% of base rows is flagged "PARTIAL COVERAGE -- D3/frailty require a stated
denominator".

Expected from project context:
- Cognitive_Score: 20,540 / 41,150 = 49.9% -- PARTIAL COVERAGE
- Frailty_Score: 23,311 / 41,150 = 56.6% -- PARTIAL COVERAGE
- Hemodynamic block (ABP/BIS): ~3,500-4,000 / 41,150 = ~8-10% -- PARTIAL COVERAGE

**Wave 1 action:** state a separate denominator for D3 and the D2 frailty block; Wave 3 must
note this on the KEY sheet.

### Identifier Candidates

Columns matching _ID, ID_, MRN, ENCOUNTER patterns in g.analysis_base, plus any character
variable with > 200 distinct levels, are listed in qc/17_discovery.txt for OUT_OF_SCOPE marking.

Expected: PRECEDE_STUDY_ID, ENCRYPTED_MRN, ENCRYPTED_ENCOUNTER, and any positional ID columns.

### Sentinel Applicability

Only variables where -999 (numeric) or literal NULL (character) actually occur are listed.
Wave 2 recodes ONLY these. The list is written to qc/17_discovery.txt.

Expected from project context: dCDT-derived cognitive variables carry -999; md8-sourced
character variables may carry NULL strings. Actual list confirmed by the discovery run.

### VARnn Defect Count

n_varnn (count of positional VAR+digits column names) is written to qc/17_discovery.txt.
Expected: 0 in g.analysis_base (already validated in prior phases).

---

## Verification (code-side)

All acceptance criteria met from grep checks on the committed file:

| Check | Result |
|-------|--------|
| `%include "...00_config.sas"` present | 1 match |
| `%macro fail_out` with `ods excel close` and `%abort cancel` | present |
| `%macro route_log` / `%macro restore_log` referencing `17_summary_stats_by_domain.log` | present |
| `dictionary.tables` existence checks for ANALYSIS_BASE and MASTER_DATA_MERGED | 2 matches |
| `%let DOMAIN_MAP_APPROVED = 0` and `%macro gate_stats` | present |
| `%let SUPPRESS_MAX = 11` and `%let SUPPRESS_LABEL = --` | present |
| No `<11` as data label (comment-only appearances) | confirmed |
| `17_discovery.txt` referenced | 23 matches |
| `PRECEDE_STUDY_ID_1` exclusion | 2 matches |
| `key_type_merged` captured | 2 matches |
| `n_key_dups` computed | 3 matches |
| `nlevels` used for cardinality | 7 matches |
| `prxmatch('/(^|_)MAC(_|$)/')` anchored pattern | 2 matches |
| `work.ext_candidates` created and left in WORK | 6 matches |
| `sentinel_log` / sentinel scan | 12 matches |

**No bare open-code %IF** — all conditional logic is inside named macros (%macro ... %mend).
**No %abort cancel outside %fail_out** — confirmed by structure.

---

## Deviations from Plan

### Auto-applied adjustments

**1. [Rule 3 - Blocking] Task 1 and Task 2 committed in a single commit**
- **Reason:** Task 2 is an in-file append to the scaffold created in Task 1. Since SAS execution
  is manual (P: drive) and the plan's verification for both tasks is grep-based (not a SAS run),
  both tasks were authored sequentially in the same file and committed atomically.
- **Impact:** None — all acceptance criteria for both tasks are met.

None. Plan executed as written with the above noted commit consolidation.

---

## Known Stubs

The following are intentional placeholders that will be resolved by the manual SAS run and
subsequent Wave 1 (17-02-PLAN.md):

1. `qc/17_discovery.txt` — written by the SAS program on the P: drive; not in git (PHI path).
   Wave 1 executor must read this file before proceeding.
2. `%let DOMAIN_MAP_APPROVED = 0` — intentional gate; set to 1 only after Checkpoint 1 review.
3. Sections 1-11 — not yet written; added in 17-02 and 17-03.

---

## Self-Check

**Files created:**
- sas/17_summary_stats_by_domain.sas — FOUND (committed at f0adfef)

**Commits:**
- f0adfef — FOUND (feat(17-01): program scaffold Sections 0+0b)

## Self-Check: PASSED
