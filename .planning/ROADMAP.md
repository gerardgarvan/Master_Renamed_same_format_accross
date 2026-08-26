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
- [ ] 03-05-PLAN.md — md7 structural prep + 03_prep_all.sas driver and consolidated summary (PREP-01, PREP-02, PREP-05, PREP-06)