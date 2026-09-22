---
milestone: v1.0 (active phases 6-8, 14-18)
audited: 2026-09-22T00:00:00Z
status: gaps_found
scores:
  requirements: 24/35 checkboxes formally updated in REQUIREMENTS.md (but functionally higher -- see analysis)
  phases: 7/8 verified (Phase 15 missing VERIFICATION.md)
  integration: end-to-end code chain verified; runtime gate (D15_APPROVED=0) blocks 17 from full execution
  flows: v1.0 pipeline complete; v1.1 pipeline code complete but runtime outputs unconfirmed for Phase 14

gaps:
  requirements:
    - id: "REQUIREMENTS.md stale checkboxes"
      status: "partial"
      phase: "Phases 6-8, 14-16"
      evidence: "COH-01 through COH-04, DOC-02 through DOC-04, HARM-04, HARM-07 remain [ ] in REQUIREMENTS.md despite all being satisfied by verified phase work. The file has not been updated since phases executed."

    - id: "Phase 15 -- VERIFICATION.md missing"
      status: "orphaned"
      phase: "15-extend-the-harmonized-dataset"
      evidence: "No 15-VERIFICATION.md exists. Both plan SUMMARYs are complete (15-01 at e42d2a3, 15-02 at 59e920e, SAS run 2026-09-21 zero ERRORs). Goal is achieved but has not been formally verified."

    - id: "Phase 14 -- runtime outputs not committed"
      status: "partial"
      phase: "14-label-similarity-sweep"
      evidence: "14-VERIFICATION.md status is gaps_found. docs/label_similarity_candidates.csv and docs/concept_decisions_EXT_TEMPLATE.csv are MISSING from git. 15-01-SUMMARY Task 1 confirms both files WERE present on disk at the time Phase 15 ran (pre-requisite confirmed). However VERIFICATION.md predates Phase 15 execution and was never re-verified. As of the verifier's assessment (2026-08-29) they were absent."

    - id: "HARM-09 -- REQUIREMENTS.md traceability stale"
      status: "partial"
      phase: "Phase 14"
      evidence: "HARM-09 is marked [x] in REQUIREMENTS.md body text but the traceability table status column was not updated."

    - id: "Phase 18 RAW-08 through RAW-12 -- not in REQUIREMENTS.md"
      status: "orphaned"
      phase: "18-supplemental-raw-inventory"
      evidence: "RAW-08 through RAW-12 are defined in 18-RESEARCH.md and ROADMAP.md only. They do not appear in REQUIREMENTS.md at all -- no body entry, no traceability row."

    - id: "SUMM-DOMAIN-DISC/MAP/STATS/BOOK -- traceability gap"
      status: "partial"
      phase: "Phase 17"
      evidence: "These four IDs are registered in REQUIREMENTS.md body text (all [x]) and traceability table (Phase 17, Complete). Gap is resolved: 2026-09-22 resolution notes in 17-VERIFICATION.md confirm registration. SUMM-DOMAIN-* are satisfied."

    - id: "D3 tab absent from Phase 17 workbook"
      status: "partial"
      phase: "17-summary-stats-by-domain-context"
      evidence: "COGNITIVE_SCORE and COGNITIVE_CATEGORY not assigned assign_rule=instrument in DATALINES block -- D3 sheet absent from qc/17_summary_stats_by_domain.xlsx. Acknowledged by Gerard at Checkpoint 2 (2026-09-10) as a known follow-up item, not a blocker per checkpoint approval."

    - id: "PCM-D-15 gate -- D15_APPROVED=0 committed"
      status: "partial"
      phase: "Phases 17-18"
      evidence: "sas/17_summary_stats_by_domain.sas has %let DOMAIN_MAP_APPROVED = 0 committed. sas/00_config.sas has %let D15_APPROVED = 0. These gates prevent Phase 17 from producing analysis_base_ext and Phase 18 from proceeding past its diagnostic, by design, until Gerard approves PCM-D-15. The supplemental raw gap analysis has not yet been formally approved for integration."

  integration:
    - from: "Phase 14 (14_label_similarity.sas)"
      to: "Phase 15 (concept_decisions.csv extension)"
      issue: "14-VERIFICATION.md flagged CSV outputs as missing. 15-01-SUMMARY Task 1 confirms they were present when Phase 15 ran. Gap is practically closed but Phase 14 VERIFICATION.md was not re-run after Phase 15 confirmed the outputs existed."

    - from: "99_run_all.sas"
      to: "g.master_data_harmonized / g.analytic_cohort"
      issue: "99_run_all.sas covers Phases 1-8 only. It does not include 10b_concept_harmonize.sas, 16b_cohort_rebuild.sas, 17_summary_stats_by_domain.sas, or 18_supplemental_raw_gap.sas. These v1.1 milestone programs are not wired into the single runner. This is expected scope (v1.0 runner vs v1.1 phases) but should be explicit."

  flows: []

tech_debt:
  - phase: 04-merge
    items:
      - "sas/04_merge.sas retains an inline copy of the ownership resolution rule instead of %include-ing sas/00_ownership_rule.sas. Both copies implement the same rule (verified). Updating 04_merge.sas requires a full Phase 4+5 re-run. Deferred intentionally per 08-01-SUMMARY."

  - phase: 06-variable-reconciliation
    items:
      - "%macro assert_col defined twice in sas/06_reconcile.sas. SAS uses the last definition silently; both are identical. Flagged in 06-VERIFICATION.md as a warning, not a blocker."

  - phase: 14-label-similarity-sweep
    items:
      - "Phase 14 VERIFICATION.md status is gaps_found and was never re-verified after Phase 15 confirmed the prerequisite CSV files were present. A re-verification of Phase 14 would close this stale flag."
      - "docs/label_similarity_candidates.csv and docs/concept_decisions_EXT_TEMPLATE.csv are .gitignore'd (*.csv) and require git add -f after each SAS run. This is a recurring manual step."

  - phase: 16-rebuild-the-analytic-cohort
    items:
      - "STATE.md has 3 new non-ASCII bytes (em-dashes) introduced by Phase 16. Pre-existing count was 291; HEAD is 294. Plan acceptance criterion required pure ASCII. Flagged as human-verification item. Functionally harmless."
      - "REQUIREMENTS.md traceability table still shows HARM-10 as Phase 9 / Pending and COH-01 through COH-04 as Pending, though they are satisfied by Phases 7 and 16."

  - phase: 17-summary-stats-by-domain-context
    items:
      - "ROADMAP.md line 181 showed 17-04-PLAN.md as unchecked / '3/4 plans executed'. ROADMAP.md has been corrected to '4/4 plans complete' per Phase 17 gap resolution (2026-09-22)."
      - "D3 (Cognitive assessments) domain absent from workbook. One-line DATALINES fix needed before next run."
      - "DOMAIN_MAP_APPROVED = 0 is committed; requires manual override before each statistics run. By design but operationally fragile."

  - phase: 18-supplemental-raw-inventory
    items:
      - "RAW-08 through RAW-12 are not registered in .planning/REQUIREMENTS.md. Phase 18 work is complete and verified at code level but has no formal traceability entry."
      - "PCM-D-15 decision (supplement raw gap-fill integration) is still open. Until D15_APPROVED=1 in 00_config.sas, Phase 17 cannot build work.analysis_base_ext from extension columns, and Phase 18 aborts after writing the diagnostic files."
      - "PCM-D-16 (2022 ID mismatch for r7/r8/r9) is diagnosed but not fixed. By design -- the program documents the cause, applies no fix."
---

# Milestone Audit Report — PeCAN Master Dataset Integration

**Milestone:** v1.0 + v1.1 (active phases 6, 7, 8, 14, 15, 16, 17, 18)
**Audited:** 2026-09-22
**Auditor:** Claude (milestone-auditor)

---

## Verdict: GAPS FOUND — Not Yet Archivable

The pipeline is functionally complete and the core deliverable (g.master_data_merged, 41,150 rows) is produced and passes QC. The v1.1 harmonized dataset (g.master_data_harmonized, 174 columns, 41,150 rows) and the rebuilt analytic cohort (g.analytic_cohort, 13,890 rows, 174 columns) are also in place with SAS runs confirmed. The gaps blocking archive are **administrative and documentation gaps**, not code correctness failures.

---

## Phase Verification Status

| Phase | Name | VERIFICATION.md | Status | Score |
|-------|------|-----------------|--------|-------|
| 06 | Variable Reconciliation | Exists | passed | 5/5 |
| 07 | Cohort & Missingness | Exists | human_needed* | 5/6 (human items confirmed by context) |
| 08 | Documentation & Handoff | Exists | passed | 5/5 |
| 14 | Label-Similarity Sweep | Exists | **gaps_found** | 4/6 |
| 15 | Extend the Harmonized Dataset | **MISSING** | unverified | N/A |
| 16 | Rebuild the Analytic Cohort | Exists | human_needed* | 7/8 |
| 17 | Summary Stats by Domain | Exists | passed (after gap resolution) | 8/8 |
| 18 | Supplemental Raw Inventory | Exists | human_needed* | 7/8 |

*human_needed items are SAS runtime confirmations (log/QC files on P: drive, not git-tracked). The SUMMARYs document human-approved checkpoints for all of these.

**Phase 15 is missing a VERIFICATION.md.** This is the only unverified phase. The work is complete (SAS run 2026-09-21 zero ERRORs, all 7 assertion NOTEs confirmed, g.master_data_harmonized at 174 cols per 15-02-SUMMARY).

---

## Requirements Coverage (3-Source Cross-Reference)

### v1.0 Requirements (SRC, OWN, PREP, MRG, QC, REC, COH, DOC)

| REQ-ID | REQUIREMENTS.md | SUMMARY frontmatter | VERIFICATION.md | Final Status |
|--------|----------------|--------------------|----|-------------|
| SRC-01 through SRC-04 | [x] | Phases 1-2 | Not in scope (Phases 1-5 pre-audit) | satisfied |
| OWN-01 through OWN-04 | [x] | Phases 1-2 | Not in scope | satisfied |
| PREP-01 through PREP-07 | [x] | Phases 1-5 | Not in scope | satisfied |
| MRG-01 through MRG-06 | [x] | Phases 4-5 | Not in scope | satisfied |
| QC-01 through QC-05 | [x] | Phases 4-5 | Not in scope | satisfied |
| REC-01 through REC-04, REC-06 | [x] | 06-* SUMMARYs | 06-VERIFICATION passed | satisfied |
| **REC-05** | **[ ]** | Not listed | 06-VERIFICATION: "Satisfied (deferred by design)" | **satisfied** (PCM-D-07 deferred as a deliberate decision, not an open gap; checkbox needs update) |
| **COH-01** | **[ ]** | 07-02: requirements-completed: [PCM-D-05, PCM-F-11] | 07-VERIFICATION passed | **satisfied** (07_cohort.sas exists, 453 lines, INPATIENT/OBSERVATION filter, 13,890 cohort; checkbox stale) |
| **COH-02** | **[ ]** | 07-02 SUMMARY | 07-VERIFICATION: missingness profile documented | **satisfied** (pct_bmi_have/lack measured; checkbox stale) |
| **COH-03** | **[ ]** | 07-02 SUMMARY | 07-VERIFICATION: four complete-case assertions coded | **satisfied** (assert_complete_case_n for 12726, 20540, 23311, 6523; checkbox stale) |
| **COH-04** | **[ ]** | 07-02: PCM-D-05 satisfied | 07-VERIFICATION: PCM-D-05 resolved | **satisfied** (PCM-D-05 entry in DECISIONS.md; checkbox stale) |
| **DOC-01** | [x] | 08-03: DOC-01 satisfied | 08-VERIFICATION passed | satisfied |
| **DOC-02** | **[ ]** | 08-03: DOC-02 satisfied | 08-VERIFICATION: all 12 PCM-D present | **satisfied** (PCM-D-01 through D-14 all resolved/attributed; checkbox stale) |
| **DOC-03** | **[ ]** | 08-03: DOC-03 satisfied | 08-VERIFICATION: clean pipeline run confirmed | **satisfied** (99_run_all.sas ran clean; checkbox stale) |
| **DOC-04** | **[ ]** | 08-03: DOC-04 satisfied | 08-VERIFICATION: git history confirmed | **satisfied** (phase-01 through phase-08 commits; checkbox stale) |

### v1.1 Requirements (HARM, SUMM)

| REQ-ID | REQUIREMENTS.md | SUMMARY frontmatter | VERIFICATION.md | Final Status |
|--------|----------------|--------------------|----|-------------|
| HARM-01, 05, 06, 08 | [x] | Phases 9-13 (pre-audit) | Pre-audit | satisfied |
| HARM-02, HARM-03 | [x] | 14-01, 14-02 SUMMARYs | 14-VERIFICATION: satisfied | satisfied |
| **HARM-04** | **[ ]** | 15-01: requirements-completed implied | **No VERIFICATION.md** | **satisfied** (concept_decisions.csv has 39 YES rows; PCM-D-13 attributed; checkbox stale) |
| **HARM-07** | **[ ]** | 15-02: HARM-07 drop rule enforced, all assertions pass | **No VERIFICATION.md** | **satisfied** (10b DROP= block + %assert_harm07; checkbox stale) |
| HARM-09 | [x] | 14-02 SUMMARY | 14-VERIFICATION: satisfied | satisfied |
| HARM-10 | marked Pending (stale) | 16-01, 16-02 SUMMARYs | 16-VERIFICATION: satisfied | satisfied (HARM-10 delivered by Phase 16) |
| SUMM-01, SUMM-02 | [x] | Pre-audit Phases 9-13 | Pre-audit | satisfied |
| SUMM-DOMAIN-* | [x] (registered 2026-09-22) | 17-01 through 17-04 | 17-VERIFICATION: satisfied | satisfied |
| RAW-08 through RAW-12 | **not registered** | 18-01, 18-02 SUMMARYs | 18-VERIFICATION: satisfied (code) / human-needed (runtime) | **partial** -- code satisfied; runtime pending human run; IDs not in REQUIREMENTS.md |

---

## Cross-Phase Integration

### E2E Data Chain (v1.0)

```
master_data_1..8 (read-only)
  -> 01_verify_sources.sas   [checksums, SRC-01/02/03/04]
  -> 02_ownership.sas        [qclib.ownership_map, OWN-01/02/03/04]
  -> 03_prep_md*.sas         [normalized g.prep_md*, PREP-01..07]
  -> 04_merge.sas            [g.master_data_merged 41,150 rows 176 cols, MRG-01..06]
  -> 05_qc_merge.sas         [assertions pass, QC-01..05]
  -> 06_reconcile.sas        [qc/06_reconcile_summary.txt, REC-01..04/06]
  -> 07_cohort.sas           [g.analytic_cohort initial, COH-01..04]
  -> 08_dictionary.sas       [docs/DATA_DICTIONARY.xlsx 176 vars, DOC-01]
  -> 99_run_all.sas          [wires all 8 phases, DOC-03]
```

VERIFIED: All 8 phases code-verified. Phase 8 confirmed clean run (2026-09-22).

### E2E Data Chain (v1.1 -- not in 99_run_all.sas)

```
g.master_data_merged (41,150 x 176)
  -> 10b_concept_harmonize.sas  [g.master_data_harmonized 41,150 x 174, HARM-04/07]
  -> 14_label_similarity.sas    [docs/label_similarity_candidates.csv, HARM-02/03/09]
  -> 16b_cohort_rebuild.sas     [g.analytic_cohort 13,890 x 174, HARM-10]
  -> 17_summary_stats_by_domain.sas [qc/17_summary_stats_by_domain.xlsx, SUMM-DOMAIN-*]
  -> 18_supplemental_raw_gap.sas    [qc/18_gap_candidates.txt, RAW-08..12]
```

VERIFIED (code): All programs exist and are substantively wired.
GATE OPEN: D15_APPROVED=0 in 00_config.sas prevents Phase 17 from building work.analysis_base_ext. Phase 18 writes diagnostics then aborts. This is by design pending PCM-D-15 decision.

### Key Integration Finding: 14 -> 15 Hand-off

Phase 14 VERIFICATION.md (dated 2026-08-29) reported docs/label_similarity_candidates.csv and docs/concept_decisions_EXT_TEMPLATE.csv as MISSING. Phase 15-01-SUMMARY (dated 2026-09-21) explicitly confirms "All three prerequisite CSVs confirmed present" in Task 1. The Phase 14 gap was resolved before Phase 15 ran. Phase 14's VERIFICATION.md was never re-verified and still shows gaps_found -- this is a stale verification artifact, not an active code gap.

---

## Open Decision Items

| Decision | Status | Blocker? |
|----------|--------|----------|
| PCM-D-05 -- Cohort restriction | Resolved (Phase 16, 2026-09-21) | No |
| PCM-D-07 -- Age floor | Deferred -- not pursuing | No |
| PCM-D-12 -- %abort cancel return code | Resolved = 3 | No |
| PCM-D-13 -- SSDI/CPT1 harmonization | Resolved (Phase 15, 2026-09-22) | No |
| PCM-D-14 -- Pipeline-derived column rule | Resolved (Phase 15, 2026-09-14) | No |
| PCM-D-15 -- Supplemental raw gap-fill integration | **OPEN** | Blocks Phase 17 work.analysis_base_ext |
| PCM-D-16 -- 2022 ID mismatch (r7/r8/r9) | Diagnosed, not fixed (by design) | No |

---

## Summary of Blocking Items

### Blocking for Archive

1. **Phase 15 VERIFICATION.md is missing.** The work is done (SAS run confirmed, two plan SUMMARYs complete) but no formal verification record exists. This is a documentation gap that prevents clean archive.

2. **REQUIREMENTS.md checkboxes are stale.** COH-01 through COH-04, DOC-02 through DOC-04, HARM-04, HARM-07 are all `[ ]` despite being satisfied by verified phase work. The traceability table also shows HARM-10 and several HARM/SUMM entries with stale statuses. These will create confusion if the project is archived or audited in future without this context.

3. **Phase 14 VERIFICATION.md status is gaps_found.** The root cause (CSV outputs not committed) was resolved when Phase 15 confirmed those files were present. A re-verification of Phase 14 is needed to formally close the gaps_found flag.

### Non-Blocking (Tech Debt)

4. **RAW-08 through RAW-12 not in REQUIREMENTS.md.** The Phase 18 requirements exist only in ROADMAP.md and RESEARCH.md. Consider adding them to REQUIREMENTS.md for complete project-level traceability.

5. **PCM-D-15 gate open (D15_APPROVED=0).** Until Gerard decides whether to integrate the supplemental raw gap-fill columns, Phase 17 cannot produce the full extension-column analysis and Phase 18 remains in diagnostic-only mode. This is not a code defect but an outstanding project decision.

6. **D3 cognitive domain absent from Phase 17 workbook.** One-line fix in DATALINES block. Not blocking archive; acknowledged at Checkpoint 2.

7. **04_merge.sas inline ownership rule.** Known maintenance concern; updating requires Phase 4+5 re-run. Deferred intentionally.

---

## Nyquist Compliance

No VALIDATION.md files found in any active phase directory. Nyquist compliance discovery was performed; no phase has been formally validated.

---

## Recommended Actions Before Archive

**Must do (blocking):**

1. Run Phase 15 verification -- write .planning/phases/15-extend-the-harmonized-dataset/15-VERIFICATION.md
2. Re-verify Phase 14 -- the CSV gaps are closed; re-run to flip gaps_found to passed
3. Update REQUIREMENTS.md checkboxes: mark COH-01/02/03/04, DOC-02/03/04, HARM-04, HARM-07 as [x]; update traceability table statuses for HARM-10 and COH-* to Complete

**Should do (clean archive):**

4. Register RAW-08 through RAW-12 in REQUIREMENTS.md
5. Decide PCM-D-15 and set D15_APPROVED accordingly (or explicitly document D15 as deferred to v2)

**Nice to have:**

6. Fix D3 tab in Phase 17 workbook (one-line DATALINES fix)
7. Rephrase STATE.md status lines to use "--" instead of em-dashes (resolves Phase 16 ASCII compliance note)

---

_Audited: 2026-09-22_
_Auditor: Claude (milestone-auditor)_
