# Phase 16: Rebuild the Analytic Cohort - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-21
**Phase:** 16-rebuild-the-analytic-cohort
**Areas discussed:** PCM-D-05 path, Program strategy, Assertion targets, Column scope

---

## PCM-D-05 path

| Option | Description | Selected |
|--------|-------------|----------|
| Hardcode admitted-only | Filter to INPATIENT+OBSERVATION in code with BMI rationale. PCM-D-05 resolved. | ✓ |
| %let gate, default admitted | Parameterize so Price can flip without editing code. | |
| Leave for Price before running | Blocking human-checkpoint before SAS run. | |

**User's choice:** Hardcode admitted-only  
**Notes:** None needed — matches ROADMAP success criterion that PCM-D-05 is resolved and attributed.

---

## PCM-D-05 detail: clinical-population shift figures

| Option | Description | Selected |
|--------|-------------|----------|
| Record all four shifts + racial composition | Charlson, anaesthesia, GI service, colonoscopy, RACE=WHITE — all five in DECISIONS.md | ✓ |
| Record racial shift only | Racial composition is the one explicitly flagged for methods sections | |

**User's choice:** Record all four shifts (plus racial composition = five total)

---

## Program strategy

| Option | Description | Selected |
|--------|-------------|----------|
| New program: 16_cohort_rebuild.sas | Reads g.master_data_harmonized, leaves 07_cohort.sas as historical artifact | ✓ |
| Revise 07_cohort.sas in-place | Update source dataset reference, simpler but overwrites Phase 7 artifact | |

**User's choice:** New standalone program

---

## 99_run_all.sas registration

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 8's job — don't touch here | Phase 8 Plan 02 already scoped it | ✓ |
| Add it here | Register 16_cohort_rebuild.sas in 99_run_all.sas as part of Phase 16 | |

**User's choice:** Leave to Phase 8

---

## Assertion targets

| Option | Description | Selected |
|--------|-------------|----------|
| Re-measure from harmonized, assert 3, leave all-three as measured-only | Assert 12726/20540/23311; drop 6523 assertion (stale) | ✓ |
| Carry all four assertions unchanged from 07_cohort.sas | Assert all four including all-three=6523 | |

**User's choice:** Re-measure from harmonized, assert 3 known values, drop all-three assertion

---

## h_* harmonized column Ns

| Option | Description | Selected |
|--------|-------------|----------|
| Measure h_* Ns and report — do not assert | Baselines never established; let first run create them | ✓ |
| Assert against full-file h_* Ns from Phase 15 | Within-cohort would be less; cannot assert directly | |

**User's choice:** Measure and report only

---

## Column scope

| Option | Description | Selected |
|--------|-------------|----------|
| All 174 harmonized columns | Full pass-through from g.master_data_harmonized | ✓ |
| Curated subset: source + h_* only | Drop md8 monitoring columns; smaller but risks silent exclusions | |

**User's choice:** All 174 columns

---

## Post-run harmonized-unchanged assertion

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, assert harmonized unchanged (174 cols, 41150 rows) | Mirrors 10b pattern; zero cost | ✓ |
| No, trust the DATA step | Read-only by design; no assertion needed | |

**User's choice:** Yes, assert

---

## Claude's Discretion

- Program section structure, macro naming, ODS LISTING handling, log routing, QC file format

## Deferred Ideas

None
