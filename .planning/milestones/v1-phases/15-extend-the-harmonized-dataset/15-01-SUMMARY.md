---
plan: 15-01
phase: 15-extend-the-harmonized-dataset
status: complete
completed: 2026-09-21
tasks_complete: 3
tasks_total: 3
key_decisions:
  - "PCM-D-13: SSDI_DEATH_FLAG confirmed -> h_ssdi_death by Gerard 2026-09-21"
  - "CPT1_CODE_LABEL deferred (gate (m): & character in D&C label value)"
  - "Label-similarity candidates: none confirmed"
---

# Plan 15-01 Summary: Extend concept_decisions.csv (HARM-04 Decision Gate)

## What Was Built

Extended `docs/concept_decisions.csv` with 5 confirmed SSDI_DEATH_FLAG rows and
recorded the decision as PCM-D-13 in `docs/DECISIONS.md`. This satisfies the
HARM-04 requirement: every canonical-name decision attributed, dated, and applied
by program rather than by hand.

## Task Results

### Task 1: Phase 14 artifacts confirmed on disk

All three prerequisite CSVs confirmed present:
- `docs/concept_decisions.csv` (existing 11-concept base file, 34 YES rows)
- `docs/concept_decisions_EXT_TEMPLATE.csv` (Phase 14 output: SSDI + CPT1 rows)
- `docs/label_similarity_candidates.csv` (label-sweep candidate pairs)

### Task 2: Gate (m) screen and human review

**Gate (m) screen output:**

| Concept | Hit | Character | Action |
|---------|-----|-----------|--------|
| CPT1_CODE_LABEL | VALUE_TXT "Diagnostic dilatation and curettage (D&C)" | & | DEFERRED |
| SSDI_DEATH_FLAG | none | -- | PASSES |

**Human decisions (Gerard, 2026-09-21):**
- SSDI_DEATH_FLAG: CONFIRMED -> h_ssdi_death, Y/N pass-through (TARGET_VALUE = VALUE_TXT)
- CPT1_CODE_LABEL: DEFERRED (gate (m) screen)
- Label-similarity candidates: none confirmed

### Task 3: Append and record

- YES rows in concept_decisions.csv: 34 -> 39 (+5 SSDI rows, all CONFIRMED=YES)
- Single header line confirmed
- PCM-D-13 appears in pending table AND resolution section of DECISIONS.md
- concept_decisions.csv force-added to git (*.csv gitignored)
- Committed: e42d2a3

## Acceptance Criteria

- [x] Phase 14 artifacts confirmed on disk before confirmation work
- [x] Gate (m) screen run; CPT1 deferred, SSDI passes
- [x] concept_decisions.csv YES rows = 34 + 5 = 39
- [x] Exactly one header line; six required headers intact
- [x] PCM-D-13 in pending table AND resolution section of DECISIONS.md
- [x] PCM-D-13 names date (2026-09-21), reviewer (Gerard), confirmed concept -> h_ name, deferred concept with reason
- [x] DECISIONS.md ASCII only (no non-ASCII bytes introduced)
- [x] concept_decisions.csv staged and committed (force-added)

## Key Files

- `docs/concept_decisions.csv` — extended with 5 SSDI rows (force-committed)
- `docs/DECISIONS.md` — PCM-D-13 entry added
- `docs/concept_decisions_EXT_TEMPLATE.csv` — source (git-ignored, on disk)
- `docs/label_similarity_candidates.csv` — reviewed, none confirmed (git-ignored)

## Notes

CPT1_CODE_LABEL deferral is by gate (m) rule: the & character in the observed
CPT1_LABEL value must match exactly for SECTION 3 coverage, and 10b cannot emit
& inside a %if condition safely. Extending gate (m) to handle this is a separate
future decision (would require changes to 10b's VALUE_TXT parsing).

Plan 15-02 applies these decisions by running 10b_concept_harmonize.sas end-to-end
(Wave 2, depends on this plan).
