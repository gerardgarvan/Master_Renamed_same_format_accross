### Phase 2: Ownership Map
**Goal**: Every variable in the pipeline has exactly one declared owner source, and every conflict is named — so no silent last-wins overwrite is possible in downstream merge steps
**Depends on**: Phase 1
**Requirements**: OWN-01, OWN-02, OWN-03, OWN-04
**Success Criteria** (what must be TRUE):
  1. `02_ownership.sas` runs and writes a variable→source ownership table to disk as a committed artifact
  2. The ownership table is reviewable before any merge program executes (artifact exists in `qc/` or `docs/`)
  3. Every variable name conflict across sources is explicitly listed in `docs/DECISIONS.md` (none are silently resolved in code)
  4. Coalesce-wanted variables (e.g., BMI, Race) are explicitly named in `02_ownership.sas` with disagreement-check assertions
**Plans**: 2 plans
Plans:
- [x] 02-01-PLAN.md — Scaffolding (docs/DECISIONS.md stub) + ownership enumeration and table artifact (OWN-01, OWN-02)
- [x] 02-02-PLAN.md — Conflict detection to DECISIONS.md + BMI/Race coalesce assertions (OWN-03, OWN-04)

### Phase 3: Per-Source Normalization
**Goal**: Each source file has a standalone prep program that resolves all known type, encoding, and structural anomalies — so the merge step receives clean, identically-typed inputs with no sentinel values, no duplicate columns, and all widths pre-declared
**Depends on**: Phase 2
**Requirements**: PREP-01, PREP-02, PREP-03, PREP-04, PREP-05, PREP-06
**Success Criteria** (what must be TRUE):
  1. Eight independently-runnable prep programs (`03_prep_md1.sas` … `03_prep_md8.sas`) exist and each completes without error
  2. An exception report is written to `qc/` before any type conversion executes; zero rows is the pass condition
  3. The md8 literal `NULL` sentinel is cleared and all md8 forced-char numerics are correctly converted to numeric type
  4. The `PRECEDE_Study_ID_1` duplicate column in md6 is dropped from the prep output
  5. Every character variable has an explicit `length` statement before every `merge`/`set` in prep code (PCM-R-02)
  6. Conversion counts for each prep program are written to `logs/`
**Plans**: 5 plans
Plans:
- [x] 03-01-PLAN.md — Wave 0 setup: create data/ (g library), confirm dirs, PROC CONTENTS inventory + char-var width extract (PREP-01, PREP-05, PREP-06)
- [x] 03-02-PLAN.md — md8 primary normalization: NULL sentinel clear + eight forced-char-to-numeric conversions, exception report, assertions (PREP-01, PREP-02, PREP-03, PREP-05, PREP-06)
- [x] 03-03-PLAN.md — md1/md2/md3 structural prep (md3 spine 41,150 asserted) (PREP-01, PREP-02, PREP-05, PREP-06)
- [x] 03-04-PLAN.md — md4/md5/md6 structural prep; drop PRECEDE_Study_ID_1 from md6 (PREP-01, PREP-02, PREP-04, PREP-05, PREP-06)
- [x] 03-05-PLAN.md — md7 structural prep + 03_prep_all.sas driver and consolidated summary (PREP-01, PREP-02, PREP-05, PREP-06)

### Phase 4: Merge
**Goal**: Produce `g.master_data_merged` with exactly 41,150 rows and 41,150 distinct IDs by merging all eight normalized prep outputs on md3 as the spine, with provenance flags for each source and no silent last-wins overwrites
**Depends on**: Phase 3
**Requirements**: MRG-01, MRG-02, MRG-03, MRG-04
**Success Criteria** (what must be TRUE):
  1. `04_merge.sas` runs and produces `g.master_data_merged` with exactly 41,150 rows
  2. Zero blank `PRECEDE_STUDY_ID` values in the merged output
  3. Provenance flags `in_md1`–`in_md8` and `n_sources` are present and match source row counts
  4. md3 is listed first in the `merge` statement (spine); ownership map governs all variable assignments (no last-wins)
**Plans**: 2 plans
Plans:
- [x] 04-01-PLAN.md — Write sas/04_merge.sas: preconditions, sort, DATA step merge with full LENGTH block, RENAME= ownership block for all 135 CONFLICT variables, provenance flags, five-part assertions, log output (MRG-01, MRG-04)
- [x] 04-02-PLAN.md — Static validation + human-verify SAS run: confirm all 12 assertions pass, commit qc/04_merge_provenance.txt (MRG-02, MRG-03)

### Phase 5: Merge QC

**Goal**: `05_qc_merge.sas` runs against `g.master_data_merged` and asserts: exactly 41,150 rows, no truncated character widths, no surviving literal NULL strings, md8-only hemodynamic block populated for exactly 22,473 rows, and type-converted variables within expected clinical ranges — aborting loudly on any failure
**Depends on**: Phase 4
**Requirements**: QC-01, QC-02, QC-03, QC-04, QC-05
**Success Criteria** (what must be TRUE):
  1. `05_qc_merge.sas` runs and `abort`s if row count ≠ 41,150 (QC-01)
  2. No character variable is truncated — max widths from prep are preserved (QC-02)
  3. Zero surviving literal `NULL` strings anywhere in `g.master_data_merged` (QC-03)
  4. md8-only hemodynamic block populated for exactly 22,473 rows (QC-04)
  5. Type-converted variables verified within expected clinical ranges (QC-05)
**Plans**: 2 plans

Plans:
- [ ] 05-01-PLAN.md — Write sas/05_qc_merge.sas: SECTION 0-3 (assert_eq macro, preconditions, QC-01 row count, QC-02 owner-width truncation check, QC-03 all-char NULL scan) + SECTION 4-6 (QC-04 hemodynamic block Part B asserts / Part A logs, QC-05 guarded clinical ranges, close-out) (QC-01, QC-02, QC-03, QC-04, QC-05)
- [ ] 05-02-PLAN.md — Static PCM validation + human SAS run: confirm 20 QC ASSERTION OK lines, review QC-04 Part A counts, commit qc/05_qc_merge_report.txt (QC-01, QC-02, QC-03, QC-04, QC-05)
