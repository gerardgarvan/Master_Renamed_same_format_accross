# ROADMAP.md — PeCAN Master Dataset Integration

**Project:** PCM | **Milestone:** v1.0 | **Total phases:** 8
**Last updated:** 2026-08-27 — corrected: Phase 1 restored, Phases 6–8 added, Phase 4/5
descriptions brought in line with the executed code, amendment plans 03-06 and 05-03 registered

---

### Phase 1: Source Verification & Freeze
**Goal**: The eight source files are checksummed and frozen, and the two structural guarantees the whole pipeline rests on — one row per patient, md3 a complete superset — are asserted in executable code rather than asserted in prose
**Depends on**: none
**Requirements**: SRC-01, SRC-02, SRC-03, SRC-04, SRC-05, SRC-06
**Success Criteria** (what must be TRUE):
 1. SHA-256 for all eight sources written to committed `qc/checksums.txt` at run start (SRC-04)
 2. Per-source row and distinct-ID counts written to committed `qc/src_counts.txt` (SRC-03)
 3. `PRECEDE_STUDY_ID` is non-missing in every row of all eight sources — asserted BEFORE uniqueness (SRC-05)
 4. `PRECEDE_STUDY_ID` is unique in all eight sources (SRC-01 / PCM-F-01)
 5. md3 is a complete superset of md1, md2, md4–md8 (SRC-02 / PCM-F-02)
 6. `PRECEDE_STUDY_ID` is present, character, length 12 in all eight — verified, not assumed (SRC-06)
 7. Read-only libname enforced; run aborts if P: drive, XCMD, or the key is unavailable
**Plans**: 2 plans
Plans:
- [x] 01-01-PLAN.md — Preconditions (libname + XCMD), SRC-06 key verification, SHA-256 checksums, per-source counts (SRC-03, SRC-04, SRC-06)
- [x] 01-02-PLAN.md — SRC-05 blank-key assertion (runs first), SRC-01 uniqueness, SRC-02 superset anti-join; all counted explicitly, never `&SQLOBS` (SRC-01, SRC-02, SRC-05)

### Phase 2: Ownership Map
**Goal**: Every variable in the pipeline has exactly one declared owner source, and every conflict is named — so no silent last-wins overwrite is possible in downstream merge steps
**Depends on**: Phase 1
**Requirements**: OWN-01, OWN-02, OWN-03, OWN-04
**Success Criteria** (what must be TRUE):
 1. `02_ownership.sas` runs and writes a variable→source ownership table to disk as a committed artifact
 2. The ownership table is reviewable before any merge program executes (artifact exists in `qc/` or `docs/`)
 3. Every variable name conflict across sources is explicitly listed in `docs/DECISIONS.md` (none are silently resolved in code)
 4. Coalesce-wanted variables (`Admit_BMI`, `Race`) are explicitly named in `02_ownership.sas` with disagreement-check assertions
**Plans**: 2 plans
Plans:
- [x] 02-01-PLAN.md — Scaffolding (docs/DECISIONS.md stub) + ownership enumeration and table artifact (OWN-01, OWN-02)
- [x] 02-02-PLAN.md — Conflict detection to DECISIONS.md + Admit_BMI/Race coalesce assertions, type-guarded and iterated across contributing sources (OWN-03, OWN-04)

### Phase 3: Per-Source Normalization
**Goal**: Each source file has a standalone prep program that resolves all known type, encoding, and structural anomalies — so the merge step receives clean, identically-typed inputs with no sentinel values, no duplicate columns, no invalid elapsed times, and all widths pre-declared
**Depends on**: Phase 2
**Requirements**: PREP-01, PREP-02, PREP-03, PREP-04, PREP-05, PREP-06, PREP-07, PREP-08, PREP-09
**Success Criteria** (what must be TRUE):
 1. Eight independently-runnable prep programs (`03_prep_md1.sas` … `03_prep_md8.sas`) exist and each completes without error
 2. An exception report is written to `qc/` before any type conversion executes; both counts are MEASURED, never a hardcoded zero
 3. The md8 literal `NULL` sentinel is cleared and all md8 forced-char numerics are correctly converted to numeric type
 4. `PRECEDE_Study_ID_1` is PROVEN identical to the key, then dropped from md6, then asserted absent
 5. Every character variable has an explicit `length` statement before every `merge`/`set` in prep code (PCM-R-02)
 6. Conversion counts for each prep program are written to `logs/`
 7. `Base_Procedure_Code_1` harmonized to CHARACTER `$10` in md4–md7 (PREP-07)
 8. Negative operative intervals set to missing, asserted zero afterwards (PREP-08)
 9. Every other `rt_*` variable scanned and its negative count reported, nothing modified (PREP-09)
**Plans**: 6 plans
Plans:
- [x] 03-01-PLAN.md — Wave 0 setup: create the out-of-repo g library, confirm dirs, PROC CONTENTS inventory + char-var width extract (PREP-01, PREP-05, PREP-06)
- [x] 03-02-PLAN.md — md8 primary normalization: NULL sentinel clear + eight forced-char-to-numeric conversions, exception report, assertions (PREP-01, PREP-02, PREP-03, PREP-05, PREP-06)
- [x] 03-03-PLAN.md — md1/md2/md3 structural prep (md3 spine 41,150 asserted) (PREP-01, PREP-02, PREP-05, PREP-06)
- [x] 03-04-PLAN.md — md4/md5/md6 structural prep; prove-then-drop PRECEDE_Study_ID_1 from md6; Base_Procedure_Code_1 to CHAR (PREP-01, PREP-02, PREP-04, PREP-05, PREP-06, PREP-07)
- [x] 03-05-PLAN.md — md7 structural prep + 03_prep_all.sas driver and consolidated summary (PREP-01, PREP-02, PREP-05, PREP-06, PREP-07)
- [ ] 03-06-PLAN.md — AMENDMENT-01: null negative operative intervals across all eight; report-only negative scan of every other `rt_*` (PREP-08, PREP-09)

### Phase 4: Merge
**Goal**: Produce `g.master_data_merged` with exactly 41,150 rows and 41,150 distinct IDs by merging all eight normalized prep outputs on md3 as the spine, with provenance flags for each source and no silent last-wins overwrites
**Depends on**: Phase 3
**Requirements**: MRG-01, MRG-02, MRG-03, MRG-04, MRG-05, MRG-06
**Success Criteria** (what must be TRUE):
 1. `04_merge.sas` runs and produces `g.master_data_merged` with exactly 41,150 rows
 2. Zero blank `PRECEDE_STUDY_ID` values in the merged output
 3. Provenance flags `in_md1`–`in_md8` and `n_sources` are present and match source row counts
 4. md3 is listed first in the `merge` statement (spine); every source carries `KEEP=` so a non-owner copy never enters the PDV
 5. The merged column list reconciles exactly against the ownership map — zero unmapped columns, zero mapped-but-absent variables
 6. `rt_envelope_flag` derived and excluded from the MRG-04 reconciliation (MRG-05, PCM-D-08)
**Plans**: 2 plans
Plans:
- [x] 04-01-PLAN.md — Write sas/04_merge.sas: preconditions, ownership resolution from qclib.ownership_map, sort, DATA step merge with generated KEEP= lists and owner-width LENGTH block, provenance flags, rt_envelope_flag, 14 assertions, log output (MRG-01, MRG-04, MRG-05) — *amended 2026-08-27: MRG-05 added, requires re-run*
  *Amended 2026-08-27: MRG-06 added — `work.md8_donors` fills md3 blanks from md8 for five variables (PCM-D-11 / PCM-F-18). Requires a Phase 4 re-run.*
- [x] 04-02-PLAN.md — Static validation + human-verify SAS run: confirm all 14 assertions pass, commit qc/04_merge_provenance.txt (MRG-02, MRG-03)

*Note: Phase 4 output is STALE pending the 03-06 re-run. PREP-08 changes `g.prep_mdN`, so `g.master_data_merged` must be regenerated before Phase 5 results mean anything.*

### Phase 5: Merge QC
**Goal**: `05_qc_merge.sas` runs against `g.master_data_merged` and asserts: exactly 41,150 rows, no truncated character widths, no surviving literal NULL strings, md8-OWNED variables non-missing only within md8 rows, type-converted variables within observation-calibrated clinical ranges, and operative sub-intervals contained within the room interval — aborting loudly on any failure
**Depends on**: Phase 4
**Requirements**: QC-01, QC-02, QC-03, QC-04, QC-05, QC-06, QC-07
**Success Criteria** (what must be TRUE):
 1. `05_qc_merge.sas` runs and `abort`s if row count ≠ 41,150 (QC-01)
 2. No character variable is truncated — owner widths from prep are preserved (QC-02)
 3. Zero surviving literal `NULL` strings anywhere in `g.master_data_merged` (QC-03)
 4. Every md8-OWNED variable (the ~20 single-source ABP_*/BIS_*/NIBP_*/SD_*/AVG_*/Total_* block, derived from the ownership map) is non-missing ONLY within md8 rows; within-md8 counts are logged, not asserted (QC-04)
 5. Type-converted variables verified within ranges calibrated to observed data (QC-05)
 6. Zero UNFLAGGED envelope violations; the flagged count (9) is reported, not asserted (QC-06)
 7. The three inert operative-interval ceilings are removed; QC-05 carries five assertions (QC-07)
**Plans**: 3 plans
Plans:
- [x] 05-01-PLAN.md — Write sas/05_qc_merge.sas: SECTION 0–3 (assert_eq macro, five preconditions, QC-01 row count, QC-02 owner-width check, QC-03 all-char NULL scan) + SECTION 4–6 (QC-04 derived md8-owned list, QC-05 guarded clinical ranges, close-out) (QC-01…QC-05)
- [~] 05-02-PLAN.md — Static PCM validation + human SAS run. RAN 2026-08-26: QC-01–QC-04 passed; QC-05 aborted on `rt_INCISE_to_DRESS_mins` = 52. Blocked pending 03-06 (QC-01…QC-05)
- [x] 05-03-PLAN.md — AMENDMENT-01: QC-06 unflagged-containment assertion, QC-07 ceiling removal, distribution report retained as the PCM-D-09 record (QC-06, QC-07)

### Phase 6: Variable Reconciliation
**Goal**: The variable-naming conflicts deliberately carried through unreconciled are resolved with Erin's sign-off, so the merged file has one column per measured concept rather than three
**Depends on**: Phase 5
**Requirements**: PCM-D-10 (the only open item); D-01, D-02, D-03, D-04, D-07, D-08, D-09, D-11 resolved 2026-08-27
**Success Criteria** (what must be TRUE):
 1. The three multi-column concepts (mortality, frailty components, ISO_SEV) documented in the data dictionary as deliberate, not oversight (D-01, D-02, D-03)
 2. `Emergent` retained with its limitation recorded — 7 and 21 positives is likely non-completion, not a true rate (D-04)
 3. Negatives in the other `rt_*` variables triaged from the PREP-09 report; `rt_ANCHOR_to_*_days` left alone (PCM-D-10)
 4. `rt_envelope_flag` documented for downstream users (MRG-05)
 5. The deferred age-floor question recorded as inherited by Phase 7 (D-07)
**Plans**: 3 plans
Plans:
- [x] 06-01-PLAN.md — PCM-D-10 triage: read PREP-09 report (logs/03_negtime_md3.txt), record resolution in DECISIONS.md; human checkpoint flags any bucket-D duration for Phase 3->4->5 re-run (PCM-D-10)
- [x] 06-02-PLAN.md — Write and run sas/06_reconcile.sas: confirm 16 deliberate columns present, count Emergent (D-04), document rt_envelope_flag (MRG-05), write qc/06_reconcile_summary.txt (D-01, D-02, D-03, D-04, MRG-05)
- [x] 06-03-PLAN.md — Create docs/data_dictionary_notes.txt stub: document five concept groups, record D-07 as inherited by Phase 7, cross-reference D-09/D-11 (D-07, D-08, D-09, D-11)

### Phase 7: Cohort & Missingness
**Goal**: The analytic cohort is defined on a pre-specifiable criterion rather than on data availability, and the missingness profile is documented with complete-case Ns stated
**Depends on**: Phase 6
**Requirements**: PCM-D-05, PCM-F-11, PCM-F-19 (supersedes PCM-F-12)
**Success Criteria** (what must be TRUE):
 1. Cohort inclusion criterion defined and justified. **The original justification is void** — PCM-F-12 said ambulatory patients were never eligible for the geriatric assessments, but after MRG-06 most cognitive and frailty scores belong to patients OUTSIDE the admitted cohort (PCM-F-19). `Admit_BMI` is what actually forces the restriction: all 12,726 values are inside the admitted cohort, zero outside. Re-decide PCM-D-05 on that basis, with Erin
 2. Missingness profile documented per analysis variable
 3. Complete-case Ns stated, including the ~53% gap within the admitted population
 4. The md3-owns missingness trade-off recorded — free for `Admit_BMI` (PCM-F-07), unchecked elsewhere
**Plans**: 2 plans
Plans:
- [x] 07-01-PLAN.md — Write sas/07_cohort.sas: measure Patient_Type distribution, derive g.analytic_cohort, assert four complete-case Ns, write qc/07_cohort_missingness.txt (PCM-D-05, PCM-F-11, PCM-F-12)
- [ ] 07-02-PLAN.md — Update docs/DECISIONS.md with PCM-D-05 resolution (rationale, admitted N, PCM-D-07 disposition); human-verify SAS run and QC output (PCM-D-05, PCM-F-11, PCM-F-12)

### Phase 8: Documentation & Handoff
**Goal**: `99_run_all.sas` runs start-to-finish in a clean session with no manual steps, and the pipeline is documented well enough for someone else to run and trust it
**Depends on**: Phase 7
**Requirements**: PCM-R-09, PCM-R-11, PCM-R-12
**Success Criteria** (what must be TRUE):
 1. `99_run_all.sas` verified from a clean SAS session against read-only sources
 2. `docs/DATA_DICTIONARY.xlsx` — every variable with source, type, length, coverage, derivation
 3. `docs/DECISIONS.md` complete — PCM-D-01 through D-10 resolved and attributed
 4. A git history where each phase is a reviewable commit
 5. `%abort cancel` OS return-code behavior settled — required if `99_run_all.sas` is ever scheduled
**Plans**: not yet planned

---

## Amendment log

| ID | Raised | Affects | Status |
|---|---|---|---|
| AMENDMENT-01 — Operative timestamp integrity | 2026-08-26, by the QC-05 abort | Phase 3 (PREP-08, PREP-09), Phase 5 (QC-06) | Plans written, not executed |

**Re-run chain for AMENDMENT-01:** 03-06 → Phase 4 re-merge → Phase 5. Restart the SAS
session between each; every program can end in `%abort cancel`, which leaves an interactive
session swallowing the next submit without executing it.

**Expected outcome of that chain (after the 2026-08-27 decisions):** everything passes.
QC-05 runs five assertions rather than eight; QC-06 asserts zero UNFLAGGED violations and
passes, logging 9 rows flagged. The merged file gains one column, `rt_envelope_flag`.

An earlier version predicted QC-06 failing at 9 — correct under the null-or-block reading of
PCM-D-08, superseded by the flag resolution.
