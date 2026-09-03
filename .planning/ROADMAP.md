# ROADMAP.md — PeCAN Master Dataset Integration

**Project:** PCM | **Milestone:** v1.0 | **Total phases:** 8
**Last updated:** 2026-08-27 -- corrected: Phase 1 restored, Phases 6-8 added, Phase 4/5
descriptions brought in line with the executed code, amendment plans 03-06 and 05-03 registered

---

### Phase 1: Source Verification & Freeze
**Goal**: The eight source files are checksummed and frozen, and the two structural guarantees the whole pipeline rests on -- one row per patient, md3 a complete superset -- are asserted in executable code rather than asserted in prose
**Depends on**: none
**Requirements**: SRC-01, SRC-02, SRC-03, SRC-04, SRC-05, SRC-06
**Success Criteria** (what must be TRUE):
 1. SHA-256 for all eight sources written to committed `qc/checksums.txt` at run start (SRC-04)
 2. Per-source row and distinct-ID counts written to committed `qc/src_counts.txt` (SRC-03)
 3. `PRECEDE_STUDY_ID` is non-missing in every row of all eight sources -- asserted BEFORE uniqueness (SRC-05)
 4. `PRECEDE_STUDY_ID` is unique in all eight sources (SRC-01 / PCM-F-01)
 5. md3 is a complete superset of md1, md2, md4-md8 (SRC-02 / PCM-F-02)
 6. `PRECEDE_STUDY_ID` is present, character, length 12 in all eight -- verified, not assumed (SRC-06)
 7. Read-only libname enforced; run aborts if P: drive, XCMD, or the key is unavailable
**Plans**: 2 plans
Plans:
- [x] 01-01-PLAN.md -- Preconditions (libname + XCMD), SRC-06 key verification, SHA-256 checksums, per-source counts (SRC-03, SRC-04, SRC-06)
- [x] 01-02-PLAN.md -- SRC-05 blank-key assertion (runs first), SRC-01 uniqueness, SRC-02 superset anti-join; all counted explicitly, never `&SQLOBS` (SRC-01, SRC-02, SRC-05)

### Phase 2: Ownership Map
**Goal**: Every variable in the pipeline has exactly one declared owner source, and every conflict is named -- so no silent last-wins overwrite is possible in downstream merge steps
**Depends on**: Phase 1
**Requirements**: OWN-01, OWN-02, OWN-03, OWN-04
**Success Criteria** (what must be TRUE):
 1. `02_ownership.sas` runs and writes a variable->source ownership table to disk as a committed artifact
 2. The ownership table is reviewable before any merge program executes (artifact exists in `qc/` or `docs/`)
 3. Every variable name conflict across sources is explicitly listed in `docs/DECISIONS.md` (none are silently resolved in code)
 4. Coalesce-wanted variables (`Admit_BMI`, `Race`) are explicitly named in `02_ownership.sas` with disagreement-check assertions
**Plans**: 2 plans
Plans:
- [x] 02-01-PLAN.md -- Scaffolding (docs/DECISIONS.md stub) + ownership enumeration and table artifact (OWN-01, OWN-02)
- [x] 02-02-PLAN.md -- Conflict detection to DECISIONS.md + Admit_BMI/Race coalesce assertions, type-guarded and iterated across contributing sources (OWN-03, OWN-04)

### Phase 3: Per-Source Normalization
**Goal**: Each source file has a standalone prep program that resolves all known type, encoding, and structural anomalies -- so the merge step receives clean, identically-typed inputs with no sentinel values, no duplicate columns, no invalid elapsed times, and all widths pre-declared
**Depends on**: Phase 2
**Requirements**: PREP-01, PREP-02, PREP-03, PREP-04, PREP-05, PREP-06, PREP-07, PREP-08, PREP-09
**Success Criteria** (what must be TRUE):
 1. Eight independently-runnable prep programs (`03_prep_md1.sas` ... `03_prep_md8.sas`) exist and each completes without error
 2. An exception report is written to `qc/` before any type conversion executes; both counts are MEASURED, never a hardcoded zero
 3. The md8 literal `NULL` sentinel is cleared and all md8 forced-char numerics are correctly converted to numeric type
 4. `PRECEDE_Study_ID_1` is PROVEN identical to the key, then dropped from md6, then asserted absent
 5. Every character variable has an explicit `length` statement before every `merge`/`set` in prep code (PCM-R-02)
 6. Conversion counts for each prep program are written to `logs/`
 7. `Base_Procedure_Code_1` harmonized to CHARACTER `$10` in md4-md7 (PREP-07)
 8. Negative operative intervals set to missing, asserted zero afterwards (PREP-08)
 9. Every other `rt_*` variable scanned and its negative count reported, nothing modified (PREP-09)
**Plans**: 6 plans
Plans:
- [x] 03-01-PLAN.md -- Wave 0 setup: create the out-of-repo g library, confirm dirs, PROC CONTENTS inventory + char-var width extract (PREP-01, PREP-05, PREP-06)
- [x] 03-02-PLAN.md -- md8 primary normalization: NULL sentinel clear + eight forced-char-to-numeric conversions, exception report, assertions (PREP-01, PREP-02, PREP-03, PREP-05, PREP-06)
- [x] 03-03-PLAN.md -- md1/md2/md3 structural prep (md3 spine 41,150 asserted) (PREP-01, PREP-02, PREP-05, PREP-06)
- [x] 03-04-PLAN.md -- md4/md5/md6 structural prep; prove-then-drop PRECEDE_Study_ID_1 from md6; Base_Procedure_Code_1 to CHAR (PREP-01, PREP-02, PREP-04, PREP-05, PREP-06, PREP-07)
- [x] 03-05-PLAN.md -- md7 structural prep + 03_prep_all.sas driver and consolidated summary (PREP-01, PREP-02, PREP-05, PREP-06, PREP-07)
- [ ] 03-06-PLAN.md -- AMENDMENT-01: null negative operative intervals across all eight; report-only negative scan of every other `rt_*` (PREP-08, PREP-09)

### Phase 4: Merge
**Goal**: Produce `g.master_data_merged` with exactly 41,150 rows and 41,150 distinct IDs by merging all eight normalized prep outputs on md3 as the spine, with provenance flags for each source and no silent last-wins overwrites
**Depends on**: Phase 3
**Requirements**: MRG-01, MRG-02, MRG-03, MRG-04, MRG-05, MRG-06
**Success Criteria** (what must be TRUE):
 1. `04_merge.sas` runs and produces `g.master_data_merged` with exactly 41,150 rows
 2. Zero blank `PRECEDE_STUDY_ID` values in the merged output
 3. Provenance flags `in_md1`-`in_md8` and `n_sources` are present and match source row counts
 4. md3 is listed first in the `merge` statement (spine); every source carries `KEEP=` so a non-owner copy never enters the PDV
 5. The merged column list reconciles exactly against the ownership map -- zero unmapped columns, zero mapped-but-absent variables
 6. `rt_envelope_flag` derived and excluded from the MRG-04 reconciliation (MRG-05, PCM-D-08)
**Plans**: 2 plans
Plans:
- [x] 04-01-PLAN.md -- Write sas/04_merge.sas: preconditions, ownership resolution from qclib.ownership_map, sort, DATA step merge with generated KEEP= lists and owner-width LENGTH block, provenance flags, rt_envelope_flag, 14 assertions, log output (MRG-01, MRG-04, MRG-05) -- *amended 2026-08-27: MRG-05 added, requires re-run*
  *Amended 2026-08-27: MRG-06 added -- `work.md8_donors` fills md3 blanks from md8 for five variables (PCM-D-11 / PCM-F-18). Requires a Phase 4 re-run.*
- [x] 04-02-PLAN.md -- Static validation + human-verify SAS run: confirm all 14 assertions pass, commit qc/04_merge_provenance.txt (MRG-02, MRG-03)

*Note: Phase 4 output is STALE pending the 03-06 re-run. PREP-08 changes `g.prep_mdN`, so `g.master_data_merged` must be regenerated before Phase 5 results mean anything.*

### Phase 5: Merge QC
**Goal**: `05_qc_merge.sas` runs against `g.master_data_merged` and asserts: exactly 41,150 rows, no truncated character widths, no surviving literal NULL strings, md8-OWNED variables non-missing only within md8 rows, type-converted variables within observation-calibrated clinical ranges, and operative sub-intervals contained within the room interval -- aborting loudly on any failure
**Depends on**: Phase 4
**Requirements**: QC-01, QC-02, QC-03, QC-04, QC-05, QC-06, QC-07
**Success Criteria** (what must be TRUE):
 1. `05_qc_merge.sas` runs and `abort`s if row count != 41,150 (QC-01)
 2. No character variable is truncated -- owner widths from prep are preserved (QC-02)
 3. Zero surviving literal `NULL` strings anywhere in `g.master_data_merged` (QC-03)
 4. Every md8-OWNED variable (the ~20 single-source ABP_*/BIS_*/NIBP_*/SD_*/AVG_*/Total_* block, derived from the ownership map) is non-missing ONLY within md8 rows; within-md8 counts are logged, not asserted (QC-04)
 5. Type-converted variables verified within ranges calibrated to observed data (QC-05)
 6. Zero UNFLAGGED envelope violations; the flagged count (9) is reported, not asserted (QC-06)
 7. The three inert operative-interval ceilings are removed; QC-05 carries five assertions (QC-07)
**Plans**: 3 plans
Plans:
- [x] 05-01-PLAN.md -- Write sas/05_qc_merge.sas: SECTION 0-3 (assert_eq macro, five preconditions, QC-01 row count, QC-02 owner-width check, QC-03 all-char NULL scan) + SECTION 4-6 (QC-04 derived md8-owned list, QC-05 guarded clinical ranges, close-out) (QC-01...QC-05)
- [~] 05-02-PLAN.md -- Static PCM validation + human SAS run. RAN 2026-08-26: QC-01-QC-04 passed; QC-05 aborted on `rt_INCISE_to_DRESS_mins` = 52. Blocked pending 03-06 (QC-01...QC-05)
- [x] 05-03-PLAN.md -- AMENDMENT-01: QC-06 unflagged-containment assertion, QC-07 ceiling removal, distribution report retained as the PCM-D-09 record (QC-06, QC-07)

### Phase 6: Variable Reconciliation
**Goal**: The variable-naming conflicts deliberately carried through unreconciled are resolved with Price's sign-off, so the merged file has one column per measured concept rather than three
**Depends on**: Phase 5
**Requirements**: PCM-D-10 (the only open item); D-01, D-02, D-03, D-04, D-07, D-08, D-09, D-11 resolved 2026-08-27
**Success Criteria** (what must be TRUE):
 1. The three multi-column concepts (mortality, frailty components, ISO_SEV) documented in the data dictionary as deliberate, not oversight (D-01, D-02, D-03)
 2. `Emergent` retained with its limitation recorded -- 7 and 21 positives is likely non-completion, not a true rate (D-04)
 3. Negatives in the other `rt_*` variables triaged from the PREP-09 report; `rt_ANCHOR_to_*_days` left alone (PCM-D-10)
 4. `rt_envelope_flag` documented for downstream users (MRG-05)
 5. The deferred age-floor question recorded as inherited by Phase 7 (D-07)
**Plans**: 3 plans
Plans:
- [x] 06-01-PLAN.md -- PCM-D-10 triage: read PREP-09 report (logs/03_negtime_md3.txt), record resolution in DECISIONS.md; human checkpoint flags any bucket-D duration for Phase 3->4->5 re-run (PCM-D-10)
- [x] 06-02-PLAN.md -- Write and run sas/06_reconcile.sas: confirm 16 deliberate columns present, count Emergent (D-04), document rt_envelope_flag (MRG-05), write qc/06_reconcile_summary.txt (D-01, D-02, D-03, D-04, MRG-05)
- [x] 06-03-PLAN.md -- Create docs/data_dictionary_notes.txt stub: document five concept groups, record D-07 as inherited by Phase 7, cross-reference D-09/D-11 (D-07, D-08, D-09, D-11)

### Phase 7: Cohort & Missingness
**Goal**: The analytic cohort is defined on a pre-specifiable criterion rather than on data availability, and the missingness profile is documented with complete-case Ns stated
**Depends on**: Phase 6
**Requirements**: PCM-D-05, PCM-F-11, PCM-F-19 (supersedes PCM-F-12)
**Success Criteria** (what must be TRUE):
 1. Cohort inclusion criterion defined and justified. **The original justification is void** -- PCM-F-12 said ambulatory patients were never eligible for the geriatric assessments, but after MRG-06 most cognitive and frailty scores belong to patients OUTSIDE the admitted cohort (PCM-F-19). `Admit_BMI` is what actually forces the restriction: all 12,726 values are inside the admitted cohort, zero outside. Re-decide PCM-D-05 on that basis, with Price
 2. Missingness profile documented per analysis variable
 3. Complete-case Ns stated, including the ~53% gap within the admitted population
 4. The md3-owns missingness trade-off recorded -- free for `Admit_BMI` (PCM-F-07), unchecked elsewhere
**Plans**: 2 plans
Plans:
- [x] 07-01-PLAN.md -- Write sas/07_cohort.sas: measure Patient_Type distribution, derive g.analytic_cohort, assert four complete-case Ns, write qc/07_cohort_missingness.txt (PCM-D-05, PCM-F-11, PCM-F-12)
- [ ] 07-02-PLAN.md -- Update docs/DECISIONS.md with PCM-D-05 resolution (rationale, admitted N, PCM-D-07 disposition); human-verify SAS run and QC output (PCM-D-05, PCM-F-11, PCM-F-12)

### Phase 8: Documentation & Handoff
**Goal**: `99_run_all.sas` runs start-to-finish in a clean session with no manual steps, and the pipeline is documented well enough for someone else to run and trust it
**Depends on**: Phase 7
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04
**Success Criteria** (what must be TRUE):
 1. `99_run_all.sas` verified from a clean SAS session against read-only sources
 2. `docs/DATA_DICTIONARY.xlsx` -- every variable with source, type, length, coverage, derivation
 3. `docs/DECISIONS.md` complete -- PCM-D-01 through D-12 resolved and attributed
 4. A git history where each phase is a reviewable commit
 5. `%abort cancel` OS return-code behavior settled (PCM-D-12) -- required if `99_run_all.sas` is ever scheduled
**Plans**: 3 plans
Plans:
- [x] 08-01-PLAN.md -- Write sas/08_dictionary.sas: metadata join (dictionary.columns), coverage (PROC MEANS), ownership join (qclib.ownership_map), derivation overlay, ODS EXCEL output with KEY sheet first and UF colors (DOC-01)
- [ ] 08-02-PLAN.md -- Add Phase 8 block to 99_run_all.sas; verify PCM-D-05 resolution; add PCM-D-12 (%abort cancel return code) to DECISIONS.md (DOC-02, DOC-03)
- [ ] 08-03-PLAN.md -- Human-verify full pipeline run and DATA_DICTIONARY.xlsx; confirm git history completeness (DOC-01, DOC-04)

---

## Amendment log

| ID | Raised | Affects | Status |
|---|---|---|---|
| AMENDMENT-01 -- Operative timestamp integrity | 2026-08-26, by the QC-05 abort | Phase 3 (PREP-08, PREP-09), Phase 5 (QC-06) | Plans written, not executed |

**Re-run chain for AMENDMENT-01:** 03-06 -> Phase 4 re-merge -> Phase 5. Restart the SAS
session between each; every program can end in `%abort cancel`, which leaves an interactive
session swallowing the next submit without executing it.

**Expected outcome of that chain (after the 2026-08-27 decisions):** everything passes.
QC-05 runs five assertions rather than eight; QC-06 asserts zero UNFLAGGED violations and
passes, logging 9 rows flagged. The merged file gains one column, `rt_envelope_flag`.

An earlier version predicted QC-06 failing at 9 -- correct under the null-or-block reading of
PCM-D-08, superseded by the flag resolution.

### Phase 17: Summary Statistics by Variable Domain

**Goal:** Produce descriptive summary statistics for every PRECEDE-dictionary-documented
variable, organized into five clinical domains (D1 Sociodemographics, D2 Preoperative
assessment, D3 Cognitive assessments, D4 Intraoperative variables, D5 Outcomes), output as a
single Excel workbook with pooled and per-year column blocks, sentinel recoding, and small-cell
suppression (<=11). Descriptive only -- no inferential testing, no cohort restriction beyond
g.analysis_base.
**Requirements**: SUMM-DOMAIN-DISC, SUMM-DOMAIN-MAP, SUMM-DOMAIN-STATS, SUMM-DOMAIN-BOOK
**Depends on:** Phase 16
**Plans:** 4 plans

Plans:
- [ ] 17-01-PLAN.md -- Wave 0 discovery: program scaffold (config, log routing, preconditions) + discover year variable, extension KEEP= list, per-year N (SUMM-DOMAIN-DISC)
- [ ] 17-02-PLAN.md -- Wave 1: build work.analysis_base_ext (D-01 CHAR $12 join), dictionary match, domain assignment with rationale, g.var_domain_map + Checkpoint 1 human review (SUMM-DOMAIN-MAP)
- [ ] 17-03-PLAN.md -- Wave 2: sentinel recode + log, PROC MEANS + PROC FREQ pooled and per-year, small-cell suppression (SUMM-DOMAIN-STATS)
- [ ] 17-04-PLAN.md -- Wave 3: ODS EXCEL workbook (KEY leftmost, D1-D5, Crosswalk, QC), UF colors, QC text artifact + Checkpoint 2 review (SUMM-DOMAIN-BOOK)

---

## Milestone v1.1 — Variable Harmonization

**Goal:** Close the gap that name-based matching structurally cannot reach -- same-concept
variables whose NAMES share nothing -- and bring the analytic cohort onto the harmonized
file.

**Phases:** 14-16
**Added:** 2026-08-29
**Rescoped:** 2026-08-29

**RENUMBERED FROM 9-11.** Those numbers are taken: `09_summary_stats.sas`,
`10_concept_profile.sas` / `10b_concept_harmonize.sas`, `11_dictionary_reconcile.sas`,
`12_column_redundancy.sas` and `13_value_profile_long.sas` all exist and have run. 14-16
matches the `14_harmonize.sas` naming already chosen.

**RESCOPED.** As first written this milestone re-specified delivered work.
`g.master_data_harmonized` already exists -- 187 columns, 41,150 rows, eleven harmonized
columns, eleven aliases dropped after being PROVEN redundant in the run rather than assumed.
HARM-01, 05, 06, 08 and SUMM-01, 02 are met; see REQUIREMENTS.md, where they are marked
Complete with the program that met them rather than deleted.

What remains genuinely open is the label sweep, three concept groups never profiled, and the
stale cohort file.

### Phase 14: Label-Similarity Sweep
**Goal**: Same-concept variables whose NAMES share nothing are found by comparing LABELS, and every gap is reported -- the one class of alias that name matching cannot reach
**Depends on**: Phase 13
**Requirements**: HARM-02, HARM-03, HARM-09
**Success Criteria** (what must be TRUE):
  1. Every variable label in `g.master_data_harmonized` is compared against every other by a stated similarity measure; the measure and its threshold are recorded, not left implicit (HARM-03)
  2. Candidate pairs are written to a committed artifact with their labels side by side, so a human judges the match rather than the program asserting it (HARM-03)
  3. Canonical names come from `docs/precede_dictionary.csv`, read programmatically. `VARIABLE_RECTIFICATION.xlsx` is NOT used as a crosswalk -- it is a register of open questions and holds no name mapping (HARM-02)
  4. The SSDI death family and the `CPT1_CLASS`/`CPT1_LABEL` pair are added to the concept list and profiled (HARM-09)
  5. A pair the sweep proposes is never harmonised without human confirmation -- the `concept_decisions.csv` pattern, where the program applies exactly what is confirmed and FAILS on any unmapped value
**Plans**: 2 plans
Plans:
- [x] 14-01-PLAN.md -- Write sas/14_label_similarity.sas Section A: extract labels from g.master_data_harmonized, join precede_dictionary.csv for best-label enrichment, COMPGED pairwise sweep, exclude known pairs, write docs/label_similarity_candidates.csv and evidence workbook (HARM-02, HARM-03)
- [x] 14-02-PLAN.md -- Implement Section B: SSDI death family and CPT1 concept group profiling, write docs/concept_decisions_EXT_TEMPLATE.csv and docs/CONCEPT_EVIDENCE_EXT.xlsx; human-verify SAS run (HARM-09)

### Phase 15: Extend the Harmonized Dataset
**Goal**: Concepts confirmed in Phase 14 are harmonised into `g.master_data_harmonized` by the existing `10b` machinery, and a stated rule governs the pipeline-derived columns
**Depends on**: Phase 14
**Requirements**: HARM-04, HARM-07
**Success Criteria** (what must be TRUE):
  1. Every canonical-name decision is recorded in `concept_decisions.csv`, attributed and dated, and applied by program rather than by hand (HARM-04)
  2. A written rule states which pipeline-derived columns are carried and which dropped, and the rule is enforced in code. It must address the twelve columns that carry no information: `in_md3` (constant -- md3 is the spine) and the eleven `h_*_src` companions (each a single repeated value, because the redundancy proof showed no secondary source ever fires) (HARM-07)
  3. `g.master_data_merged` is confirmed unmodified after the run -- 176 columns, 41,150 rows
  4. Any newly dropped alias is PROVEN redundant in the run, not assumed: zero rows added and zero disagreements where both are populated
**Plans**: TBD

### Phase 16: Rebuild the Analytic Cohort
**Goal**: `g.analytic_cohort` is rebuilt from `g.master_data_harmonized` so all three datasets are in step, and the cohort decision itself is settled
**Depends on**: Phase 15
**Requirements**: HARM-10, PCM-D-05
**Success Criteria** (what must be TRUE):
  1. `g.analytic_cohort` derives from `g.master_data_harmonized`, carries the `h_` columns, and carries no dropped alias (HARM-10)
  2. PCM-D-05 is resolved and recorded with attribution. Its ORIGINAL rationale is void: PCM-F-12 held that ambulatory patients were never eligible for the geriatric assessments, and PCM-F-19 disproved it -- most cognitive and frailty scores belong to patients OUTSIDE the admitted cohort
  3. The decision record states what the restriction actually does. Phase 13 measured it: the admitted cohort is a different clinical population, not a subset. Charlson 0 falls from 60.8% to 34.5%, general anaesthesia rises from 57.6% to 84.2%, and the excluded group is largely ambulatory endoscopy -- GI service 18.4% to 1.7%, colonoscopy 8.5% to 0.4%
  4. The racial composition shift is recorded in the decision and carried into any methods section: RACE=WHITE is 79.8% in the full file and 87.1% in the cohort, a 7.3-point difference that bears directly on generalisability
**Plans**: TBD
