---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: unknown
last_updated: "2026-08-27T15:44:47.324Z"
progress:
  total_phases: 8
  completed_phases: 4
  total_plans: 18
  completed_plans: 15
  percent: 83
---

# STATE.md — PeCAN Master Dataset Integration

**Project:** PCM | **Last Updated:** 2026-08-27 | **Last Session:** 2026-08-27T15:44:47.319Z

---

## Project Reference

**Core Value:** A single `99_run_all.sas` that runs start-to-finish in a clean SAS session against read-only sources, producing `g.master_data_merged` (41,150 rows), passing QC reports, a data dictionary, and a resolved DECISIONS.md — with no manual steps.

**Current Focus:** Phase 06 — variable-reconciliation

---

## Current Position

Phase: 06 (variable-reconciliation) — EXECUTING
Plan: 2 of 3
| Field | Value |
|-------|-------|
| Current Phase | 5 — Merge QC (COMPLETE) |
| Current Plan | 05-03-PLAN.md — all 4 tasks complete; QC-01 through QC-07 pass |
| Phase Status | Complete |
| Milestone | 1 of 1 |

**Progress:** [████████░░] 83%

**Phase status at a glance:**

| Phase | Name | Status |
|---|---|---|
| 1 | Source Verification & Freeze | ✅ Complete (2 of 2 plans) |
| 2 | Ownership Map | ✅ Complete (2 of 2 plans) |
| 3 | Per-Source Normalization | 🔄 Reopened — 5 of 6 plans; 03-06 pending |
| 4 | Merge | ⚠️ Complete but STALE — must re-run after 03-06 |
| 5 | Merge QC | ✅ Complete (3 of 3 plans) |
| 6 | Variable Reconciliation | ⬜ Not planned — blocked on Erin (PCM-D-01, D-02) |
| 7 | Cohort & Missingness | ⬜ Not planned |
| 8 | Documentation & Handoff | ⬜ Not planned |

**Why Phase 3 reopened:** PREP-08 changes `g.prep_mdN`, which makes `g.master_data_merged`
and every Phase 5 result stale. The chain is 03-06 → Phase 4 → Phase 5, with a SAS session
restart between each.

---

## Performance Metrics

| Metric | Target | Actual | Source |
|--------|--------|--------|--------|
| Source row count (md3 spine) | 41,150 | **41,150** ✓ | qc/src_counts.txt |
| Merged row count | 41,150 | **41,150** ✓ | QC-01, 2026-08-26 |
| Distinct merged IDs | 41,150 | **41,150** ✓ | Phase 4 assertions |
| Blank PRECEDE_STUDY_ID | 0 | **0** ✓ | MRG-02 |
| Surviving NULL strings | 0 | **0** ✓ | QC-03, all char vars |
| Char vars missing from width ref | 0 | **0** ✓ | QC-02 |
| Truncated char vars | 0 | **0** ✓ | QC-02 |
| md8-owned variables (derived) | ~20 | **20** ✓ | QC-04 |
| QC-04 scoping violations | 0 | **0** ✓ | 20 of 20 passed |
| QC-05 range assertions | 5 | 8 → **5** | three inert ceilings dropped (QC-07, PCM-D-09) |
| Negative operative intervals | 0 | **67** → nulled by PREP-08 | 52 rt1 + 15 rt2, disjoint |
| QC-06 unflagged violations | 0 | **0** (after MRG-05) | assertion passes |
| rt_envelope_flag = 1 | reported | **9** | 5 rt1 + 4 rt2 — flagged, not nulled (PCM-D-08) |
| Complete-case N (BMI) | — | 12,726 | prior analysis, re-confirm in Phase 7 |
| Complete-case N (Cognitive) | — | 20,540 | prior analysis |
| Complete-case N (Frailty) | — | 23,311 | prior analysis |
| Complete-case N (all three) | — | 6,523 | prior analysis |

**md8-only block population** — the old "22,473 for the whole block" target was wrong and has
been removed. Within-md8 population varies by design: `Total_Midazolam_mg` 22,473 (100%),
`AVG_ABP_Mean` 4,005 (~18%), `BIS_INDEX_LESS_30_COUNT` 3,604 (~16%),
`ABP_LESS_THAN_60_COUNT` 3,519 (~16%). Monitoring-derived columns are populated only where
the arterial line or BIS monitor was in use. This is logged, not asserted.

---
| Phase 06 P01 | 15 | 2 tasks | 1 files |

## Accumulated Context

### Roadmap Evolution

- Phase 5 added: Merge QC (QC-01 through QC-05)
- ROADMAP corrected 2026-08-27: Phase 1 restored, Phases 6–8 added (total 8, was 4/5),
  Phase 4 and 5 descriptions brought in line with the executed code

- AMENDMENT-01 raised 2026-08-26 by the QC-05 abort: adds PREP-08, PREP-09 (Phase 3) and
  QC-06 (Phase 5); plans 03-06 and 05-03

### Established Decisions

- md3 is the merge spine (complete superset, PCM-F-02); operation is 1:1 merge, not stack-dedup
- No PROC SQL UPDATE anywhere (silent truncation trap, PCM-T-01)
- No `data X; set X;` patterns (destroys dataset, PCM-T-02)
- Single ownership per variable (prevents last-wins overwrite, PCM-T-05)
- md8 stores literal `NULL` where others store blank; md8 numerics were forced to CHAR $4/$11 in prior work
- Coalescing BMI from other sources recovers nothing; 28,424 missing are missing at source
- `PRECEDE_Study_ID_1` in md6 is a duplicate column identical to `PRECEDE_STUDY_ID` — proven, then dropped
- Encoding damage confined to `Base_Procedure_1`, ≤9 rows per file — flag only, do not re-encode
- SRC-05 runs before SRC-01: blank key is "unique" when it occurs once and must be caught first (01-02)
- `&SQLOBS` not used anywhere; all counts use explicit `SELECT COUNT(*) INTO :macvar TRIMMED` (01-02)
- docs/DECISIONS.md created as committed stub before 02_ownership.sas runs (02-01)
- Stale-artifact filter uses `IN` not `IN:` — `IN:` prefix match would readmit master_data_7b (02-01)
- PROC CONTENTS writes to work.allvars; filter step writes to work.allvars_src — no in-place rewrite (02-01)
- src libname left open at end of 02_ownership.sas Plan 01; Plan 02 needs src for coalesce reads (02-01)
- Ownership enforced by generated `KEEP=` lists, NOT `RENAME=` — the `_d_varname_mdN` scheme
  overflows SAS's 32-char variable-name limit on a dozen-plus variables and will not compile (04-01)

- KEEP= lists are generated from `qclib.ownership_map` at run time, never hand-transcribed (04-01)
- LENGTH block uses each variable's OWNER width, not the cross-source max — only the owner's
  copy reaches the merge under KEEP= (04-01)

- Ownership resolution is a RULE (md3 if present, else highest-row-count source, ties to lowest
  number), with an explicit md7 override for the five frailty components on the width signal (04-01)

- QC-04 covers the md8-OWNED single-source block, NOT the eight PREP-03 conversion targets —
  those are md3-owned and span all 41,150 rows (05-01)

- QC-05 bounds are calibrated to OBSERVED data: Admit_BMI 10–100 (observed max 88.32; a
  ceiling of 80 would abort on correct data), Cognitive_Score 0–3 (NOT MMSE 0–30) (05-01)

- Age_at_Encounter floor of 18 cannot fire (observed min 64) and is a type-sanity guard only.
  Do NOT tighten it to 64 before PCM-D-07 is resolved (05-01)

- The g library lives OUTSIDE the git working tree — `git clean -xdf` deletes ignored files (03-01)
- All pipeline paths are on P: — g_path, logs_path, qc_path. QC reports are therefore NOT
  version-controlled; copy to the repo qc/ folder separately if commit history is wanted

- Preserve rather than reconcile: where two sources name the same concept differently and
  nothing verifies they measure the same thing, both columns are kept (D-01, D-02, D-03)

- Impossible VALUES are nulled at source (PREP-08); impossible COMBINATIONS are flagged, not
  nulled (MRG-05) — nulling a combination destroys good values to punish an unidentifiable one

- A bound that has never fired and cannot fire is not a check (QC-07). Floors at source,
  containment by relationship assertion

- md3-owns inherits md3's missingness at zero measured cost (PCM-F-17): BMI, Cognitive_Score
  and Frailty_Score all recover nothing from any other source

### Pending Decisions (blockers)

**Resolved 2026-08-27** — see `docs/DECISIONS.md`:

- **PCM-D-01** — Death variable naming: **keep separate**. Three columns in the merged file
- **PCM-D-02** — Frailty component encoding: **keep separate**. Ten columns for five concepts
- **PCM-D-03** — ISO_SEV naming: **keep separate**. md8's is a TOTAL, not an average
- **PCM-D-04** — Emergent usability: **retain despite rarity**; caveat in the data dictionary
- **PCM-D-06** — PRECEDE_Study_ID_1: resolved as drop (PREP-04), proven identical first
- **PCM-D-07** — Age floor of 64: **deferred, not pursuing**. The QC-05 floor of 18 stays a
  type-sanity guard — do NOT tighten it to 64

- **PCM-D-08** — The 9 envelope-violating rows: **flag, don't null** (`rt_envelope_flag`,
  MRG-05, derived in Phase 4). QC-06 asserts zero UNFLAGGED violations and passes

- **PCM-D-09** — QC-05 operative-interval ceilings: **drop them** (QC-07). QC-05 8 → 5 assertions
- **PCM-D-11** — md3-owns missingness: **closed, costs nothing** (PCM-F-17)

**Still open:**

- **PCM-D-05** — Analytic cohort INPATIENT/OBSERVATION restriction: pending (Phase 7)
- **PCM-D-10** — Negatives in other `rt_*` variables: needs the PREP-09 report from 03-06.
  `rt_ANCHOR_to_*_days` CAN legitimately be negative — offsets, not durations

**Phase 6 is no longer blocked on Erin.** D-01 and D-02 were its entry conditions and both are
resolved as keep-separate, which is a valid resolution. Phase 6 is now largely a documentation
exercise: record the three multi-column concepts in the data dictionary.

### Todos

- Report upstream to the PeCAN data group: the source system emits impossible operative
  timestamp combinations (9 rows) and negative intervals concentrated in percutaneous services
  (46% Neurosurgery, 20% EP/interventional cardiology among the 52)

- Raise with the PeCAN data group: the source system records incision/dressing times for
  percutaneous procedures that do not have them (46% Neurosurgery, 20% EP/interventional
  cardiology among the 52). Affects anyone using operative duration in this cohort

- Decide whether `.planning/PROJECT.md` should be replaced by the full original — the condensed
  version dropped the PCM-T-01..T-11 trap list, which is what prevents the CATS-truncation and
  `data X; set X;` incidents recurring

- Copy `ownership_map.sas7bdat` to the P: qc path if running Phase 5 on a machine that did not run Phase 2

### Blockers

- Phase 5 is COMPLETE — QC-01 through QC-07 all pass; 41,150 rows, 9 envelope-flagged rows
- Phase 6 is NO LONGER blocked — D-01 and D-02 resolved as keep-separate 2026-08-27
- No decision blockers remain for Phases 3–6. D-05 is a Phase 7 question; D-10 needs the
  PREP-09 report that 03-06 produces

---

## Session Continuity

To resume: read this file, then `ROADMAP.md`, then `.planning/AMENDMENT-01-timestamp-integrity.md`,
then `03-06-PLAN.md`.

**Key file locations:**

- Source data: `P:\PeCAN Master Data\Gerard\Master_Renamed_same_format_accross\` (read-only)
- g library: P: merge tree — **outside the git working tree** (PCM-C-04)
- SAS programs: `sas/` (version-controlled, local disk)
- QC outputs: `qc/` on the P: merge tree
- Logs: `logs/` on the P: merge tree
- Docs: `docs/`
- Planning: `.planning/`

**Do NOT** put the git repo on the P: drive (slow + index corruption risk).
**Do NOT** commit `*.sas7bdat`, `*.xlsx`, `*.csv`, or anything under `data/` (PHI).
**Do** restart the SAS session between programs — `%abort cancel` leaves an interactive
session that swallows the next submit without executing it.

---
*Last updated: 2026-08-27 — 8 phases; AMENDMENT-01 registered; metrics populated; D-01/02/03/04/07/08/09/11 resolved; Phase 6 unblocked*
