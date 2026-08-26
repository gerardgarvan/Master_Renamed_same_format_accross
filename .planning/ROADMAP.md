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