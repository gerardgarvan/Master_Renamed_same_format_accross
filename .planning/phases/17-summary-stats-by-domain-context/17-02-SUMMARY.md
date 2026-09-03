---
phase: 17-summary-stats-by-domain-context
plan: "02"
subsystem: sas-pipeline
tags: [wave-1, domain-map, extension-build, checkpoint-pending]
dependency_graph:
  requires: [sas/17_summary_stats_by_domain.sas Sections 0+0b, g.analysis_base, g.master_data_merged, docs/precede_dictionary.csv, work.ext_candidates]
  provides: [sas/17_summary_stats_by_domain.sas Sections 1-4, g.var_domain_map, qc/17_var_domain_map_review.csv]
  affects: [17-03-PLAN.md (Wave 2 statistics; reads g.var_domain_map for MEANS/FREQ variable lists per domain)]
tech_stack:
  added: []
  patterns: [macro-time key type resolution, compile-safe CHAR cast, coverage-denominator capture, three-tier dictionary match EXACT/SQUASH, cardinality-and-type stat_route, named-macro guards, single-quoted rationale literals]
key_files:
  created: []
  modified: [sas/17_summary_stats_by_domain.sas]
decisions:
  - "Tasks 1 and 2 committed in a single commit — both are appends to the same file with no intervening SAS run possible (P: drive); all acceptance criteria met"
  - "Source_dataset for extension columns resolved by SQL join to work.ext_candidates rather than hand-coded list"
  - "Domain lookup authored as DATA step INFILE DATALINES with single-quoted rationale literals — version-controlled and macro-trigger-safe"
  - "Unrecognised matched variables default to OUT_OF_SCOPE with rationale 'not in domain lookup; review needed' so the blank-rationale guard always passes and the reviewer sees them clearly"
  - "Denominator note applied to D3 rows and D2 frailty (assign_rule=instrument) rows using the D3_DENOM_NOTE global macro variable set by coverage computation"
metrics:
  duration_seconds: 420
  completed_date: "2026-09-03"
  tasks_completed: 2
  files_created: 0
  files_modified: 1
---

# Phase 17 Plan 02: Wave 1 Domain Assignment and Extension Build Summary

**One-liner:** SAS Sections 1-4 appended — macro-time key cast, D-01 left join to work.analysis_base_ext, three-tier dictionary match against ANALYSIS_BASE_EXT, cardinality-and-type stat_route, domain assignment lookup with single-quoted rationales, g.var_domain_map permanent artifact, four named-macro guards, and CSV export for Checkpoint 1.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Section 1 — build work.analysis_base_ext (D-01 join, macro-time key cast, uniqueness assert) | 142986f | sas/17_summary_stats_by_domain.sas (appended) |
| 2 | Sections 2-4 — dictionary match, identifier exclusion, stat_route, domain assignment, guards, crosswalk export | 142986f | sas/17_summary_stats_by_domain.sas (appended in same file) |

Both tasks landed in one commit: Task 2 is an in-file append to the same file as Task 1, no intervening SAS run is possible (P: drive), and all acceptance criteria are verifiable by grep.

---

## Grep Verification Results

| Acceptance Check | Result |
|-----------------|--------|
| `grep -c "analysis_base_ext"` >= 1 | 20 matches |
| `grep "key_type_merged"` | 5 matches |
| `grep "best12."` | 3 matches |
| `grep -c "vtype(PRECEDE_STUDY_ID)"` = 0 | 0 matches (PASSED — no runtime type branching) |
| `grep "n_key_dups"` | 7 matches |
| `grep -c "g.var_domain_map"` >= 2 | 12 matches |
| `grep "domain_rationale"` | 14 matches |
| `grep "stat_route"` | 14 matches |
| `grep "nlevels"` | 14 matches |
| `grep "n_blank"` | 8 matches |
| `grep "17_var_domain_map_review.csv"` | 6 matches |
| `grep "proc import"` with `guessingrows=max` | 1 match each |
| `grep "ANALYSIS_BASE_EXT"` (Section 3 match target) | 2 matches |
| `grep "prxmatch"` (identifier exclusion and VARnn guard) | 5 matches |

---

## Section 1 Summary: work.analysis_base_ext

**Key uniqueness gate:** `proc sql` counts duplicates in `g.master_data_merged` BEFORE merge; `%check_key_unique` calls `%fail_out` if > 0.

**Macro-time key cast:** `select type into :key_type_merged trimmed from dictionary.columns where libname='G' and memname='MASTER_DATA_MERGED'` — type resolved before any DATA step compiles. `%build_ext_cols` macro branches on `%if &key_type_merged = num` using `best12.` (not `z12.` — no zero-padding evidence in expected discovery values).

**Extension KEEP= list:** built dynamically from `work.ext_candidates` left in WORK by Wave 0, not hand-transcribed.

**Left merge:** `data work.analysis_base_ext; merge work.analysis_base_sorted (in=inbase) work.merged_ext_cols; by PRECEDE_STUDY_ID; if inbase; run;`

**Assertions:** row-count equality (`&n_ext_rows = &n_base_rows`), cognitive-score non-missing guard (`%fail_out` if `n_cog_nonmiss = 0`), per-column coverage in `work.ext_coverage_ext`.

**Denominator:** `D3_DENOM_NOTE` global macro variable set when any extension column has < 90% coverage; applied to D3 rows and D2 frailty rows in `g.var_domain_map`.

**No write to g.:** only `work.analysis_base_ext`, `work.merged_ext_cols`, `work.analysis_base_sorted`, `work.ext_coverage_ext`.

---

## Section 2 Summary: Dictionary Import

`proc import datafile="&docs_path.\precede_dictionary.csv" dbms=csv guessingrows=max` — copied from `16_summary_docx.sas` lines 147-181. `work.dict_u` is one row per upcased sas_name with MASTER_DATASET sheet preferred (sheet_rank=1).

---

## Section 3 Summary: Dictionary Match + Identifier Exclusion + Stat_route

**Match target:** `dictionary.columns where libname='WORK' and memname='ANALYSIS_BASE_EXT'` (the extended dataset, not `g.analysis_base`).

**Match tiers:** OR-join on exact name or squash (compress underscores); ranked, deduplicated to strongest match per variable. Ties warned but not aborted.

**Reconciliation buckets:** in-both (matched), dict-only, data-only. Data-only variables set `domain='OUT_OF_SCOPE'` with rationale `'not in PRECEDE dictionary'`.

**Identifier exclusion (Section 3b, before domain assignment):** marks `PRECEDE_STUDY_ID`, `PRECEDE_STUDY_ID_1`, `ENCRYPTED_MRN`, `ENCRYPTED_ENCOUNTER`, `prxmatch('/(^|_)(ID|MRN)(_|$)/')` matches, and character variables with > 200 distinct levels as `OUT_OF_SCOPE / identifier or technical key; not an analytic variable`. Log written to `work.id_excluded_log`.

**Stat_route (Section 3c):** `proc freq data=work.analysis_base_ext nlevels; tables _all_ / noprint; ods output nlevels=work.nlevels_ext;` — one pass. Route: `vtype='char'` → FREQ; `vtype='num' and n_levels <= 10` → FREQ; `vtype='num' and n_levels > 10` → MEANS. Both `stat_route` and `n_levels` stored on `g.var_domain_map`.

---

## Section 4 Summary: Domain Assignment, g.var_domain_map, Guards, Export

**Domain lookup:** DATA step INFILE DATALINES table keyed on upcased varname — covers D1 (sociodemographics), D2 (preop + frailty), D3 (cognitive instruments), D4 (intraoperative), D5 (outcomes). Rationale literals are SINGLE-quoted throughout (no macro trigger risk). Three-rule order: timing → analytic_role; instrument overrides both.

**g.var_domain_map columns:** varname, sas_label, vtype, n_levels, stat_route, domain, domain_rationale, assign_rule, source_dataset, denominator_note, dict_name, match_how.

**Unrecognised matched variables** (matched to dictionary but not in the domain lookup): set to `OUT_OF_SCOPE` with rationale `'not in domain lookup; review needed'` — visible in the CSV so the reviewer can catch legitimate variables the lookup missed and request a correction before Wave 2.

**Guards (all named macros calling %fail_out):**
1. Blank rationale: `where missing(domain_rationale) and domain ne 'OUT_OF_SCOPE'` → abort if > 0
2. VARnn survivor: `prxmatch('/^VAR\d+$/', strip(varname))` → abort if any
3. Blank stat_route: in-scope rows with route not in ('MEANS','FREQ') → abort if any
4. Identifier leak: in-scope rows matching identifier pattern with stat_route set → abort if any

**CSV export:** `proc export data=g.var_domain_map outfile="&qc_path.\17_var_domain_map_review.csv" dbms=csv replace;` — rows ordered by domain then varname.

---

## Checkpoint 1 Status

**Status:** PENDING — awaiting Gerard's variable-by-variable review of `qc\17_var_domain_map_review.csv`.

The program will abort at `%gate_stats` (Sections 5-11) until `%let DOMAIN_MAP_APPROVED = 1;` is set in Section 0 after approval.

---

## Domain Counts (expected after SAS run)

> These figures are structural estimates based on the domain taxonomy and expected variable set.
> Actual counts will be confirmed by the SAS run and visible in `qc\17_var_domain_map_review.csv`.

| Domain | Contents (examples) | Stat Routes |
|--------|---------------------|-------------|
| D1 | Age, sex, race, ethnicity, insurance, marital, zip/state | FREQ (most); MEANS (age) |
| D2 | BMI, frailty score/components, ASA, smoking, comorbidities | FREQ (ASA, smoking, binary comorbidities); MEANS (BMI, frailty score) |
| D3 | Cognitive_Score, Cognitive_Category, dCDT subscales | FREQ (category); MEANS (score) |
| D4 | Procedure, CPT, service line, anesthesia, case duration, emergent, hemodynamic block | FREQ (emergent, anesthesia type); MEANS (duration, ABP, BIS, midazolam, ISO_SEV) |
| D5 | 30-day mortality, LOS, readmission, discharge disposition, opioid use | FREQ (mortality, readmission, disposition); MEANS (LOS, opioid) |
| OUT_OF_SCOPE | Identifiers, high-cardinality, not-in-dictionary | No stat_route |

**Extension coverage verdict (from 17-01-SUMMARY.md expected values):**
- Cognitive_Score: ~49.9% — PARTIAL — denominator_note applies to D3 and D2 frailty
- Frailty_Score: ~56.6% — PARTIAL
- Hemodynamic block: ~8-10% — PARTIAL

---

## Deviations from Plan

### Auto-applied adjustments

**1. [Rule 3 - Blocking] Tasks 1 and 2 committed in a single commit**
- **Reason:** Both tasks are in-file appends to the same SAS file with no intervening SAS run possible on the P: drive. All acceptance criteria for both tasks are met by grep verification.
- **Impact:** None.

**2. [Rule 2 - Missing functionality] Source_dataset field resolved by SQL join to work.ext_candidates**
- **Found during:** Task 2 domain staging build
- **Issue:** A hand-coded IF/ELSE list of extension column names would drift from the actual discovery output; the plan specified building the KEEP= list dynamically but the source_dataset field for g.var_domain_map also needed reliable assignment.
- **Fix:** SQL left join from domain_staging to work.ext_candidates to set source_dataset='master_data_merged' for extension columns.
- **Files modified:** sas/17_summary_stats_by_domain.sas

**3. [Rule 2 - Missing functionality] Unrecognised matched variables defaulted to OUT_OF_SCOPE with visible rationale**
- **Found during:** Task 2 domain assignment
- **Issue:** Variables matched to the dictionary but absent from the domain lookup DATA step would have an empty domain, tripping the blank-domain path and failing the blank-rationale guard with a cryptic message.
- **Fix:** Any remaining `domain=''` after the lookup join is set to `OUT_OF_SCOPE` with rationale `'not in domain lookup; review needed'` — surfaces at Checkpoint 1 without aborting.
- **Files modified:** sas/17_summary_stats_by_domain.sas

---

## Known Stubs

1. `qc/17_var_domain_map_review.csv` — written by the SAS program on the P: drive; not in git (PHI path). Checkpoint 1 depends on this file.
2. `%let DOMAIN_MAP_APPROVED = 0` — intentional gate; set to 1 only after Checkpoint 1 review.
3. Domain lookup table — covers expected variable names from the PRECEDE dictionary and project context. After the SAS run, the reviewer will identify any correctly-matched variables that landed in 'not in domain lookup; review needed' and request corrections before Wave 2.
4. Sections 5-11 — not yet written; added in 17-03.

---

## Self-Check

**Files modified:**
- sas/17_summary_stats_by_domain.sas — FOUND (committed at 142986f, 754 insertions)

**Commits:**
- 142986f — FOUND (feat(17-02): Sections 1-4 Wave 1 ext build, domain map, crosswalk export)

## Self-Check: PASSED
