# ROADMAP.md — PeCAN Master Dataset Integration

## Milestones

- v1 **PeCAN Master Dataset Integration Pipeline** -- Phases 1-8, 14-18 (shipped 2026-09-22)
  Archive: .planning/milestones/v1-ROADMAP.md

---

## Phase Progress

<details>
<summary>v1 PeCAN Master Dataset Integration Pipeline (Phases 1-18) -- SHIPPED 2026-09-22</summary>

| Phase | Name | Plans Complete | Status | Completed |
|-------|------|---------------|--------|-----------|
| 1 | Source Verification & Freeze | 2/2 | Complete | 2026-08-26 |
| 2 | Ownership Map | 2/2 | Complete | 2026-08-26 |
| 3 | Per-Source Normalization | 6/6 | Complete | 2026-09-14 |
| 4 | Merge | 2/2 | Complete | 2026-08-27 |
| 5 | Merge QC | 3/3 | Complete | 2026-09-14 |
| 6 | Variable Reconciliation | 3/3 | Complete | 2026-09-14 |
| 7 | Cohort & Missingness | 2/2 | Complete | 2026-09-22 |
| 8 | Documentation & Handoff | 3/3 | Complete | 2026-09-22 |
| 14 | Label-Similarity Sweep | 2/2 | Complete | 2026-09-21 |
| 15 | Extend the Harmonized Dataset | 2/2 | Complete | 2026-09-21 |
| 16 | Rebuild the Analytic Cohort | 2/2 | Complete | 2026-09-22 |
| 17 | Summary Stats by Domain | 4/4 | Complete | 2026-09-22 |
| 18 | Supplemental Raw Inventory | 2/2 | Complete | 2026-09-22 |

</details>

---

## Next Milestone

No next milestone defined. Use `/gsd:new-milestone` to plan v2 work.

Candidate v2 items (from v1 deferred list):
- Wire 10b/16b/17/18 programs into 99_run_all.sas for a single-runner end-to-end pipeline
- Fix D3 (Cognitive assessments) domain in Phase 17 workbook (one-line DATALINES fix)
- PCM-D-07 age floor investigation (if upstream inclusion criterion becomes available)
- Extension-column gap-fill integration (PCM-D-15 approved; wiring pending)
